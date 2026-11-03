import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import 'plugin_manifest.dart';
import 'plugin_permission.dart';

class PluginExecutionException implements Exception {
  PluginExecutionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Signature of the permission-checked host dispatcher.
typedef PluginHostCall = Future<dynamic> Function(
  String pluginId,
  String method,
  Map<String, dynamic> arguments,
);

/// One isolated JavaScript actor for one enabled source plugin.
///
/// Mirrors QPlayer's Rhino runtime: CommonJS modules, a narrow
/// `qplayer.call()` bridge, serialized handler execution and a 90s deadline.
class PluginRuntime {
  PluginRuntime({
    required this.root,
    required this.manifest,
    required this.hostCall,
    this.callTimeout = const Duration(seconds: 90),
  });

  final Directory root;
  final PluginManifest manifest;
  final PluginHostCall hostCall;
  final Duration callTimeout;

  static const int maxModuleBytes = 4 * 1024 * 1024;

  JavascriptRuntime? _js;
  Timer? _tickTimer;
  Future<void> _tail = Future.value();
  int _sequence = 0;
  bool _closed = false;
  bool _tickRunning = false;

  bool get isRunning => _js != null && !_closed;

  Future<void> start({bool backgroundTicks = false}) async {
    final sources = await _loadModuleSources();
    final js = getJavascriptRuntime(xhr: false);
    _js = js;
    js.onMessage('qplayer.host', _onHostMessage);
    try {
      _evaluateChecked(js, _bootstrap(sources));
      final missing = <String>[];
      for (final capability in manifest.capabilitySet) {
        if (!_hasHandlerSync(capability.wireName)) {
          missing.add(capability.wireName);
        }
      }
      for (final contribution in manifest.ui) {
        final name = 'ui.${contribution.id}';
        if (!_hasHandlerSync(name)) missing.add(name);
      }
      if (missing.isNotEmpty) {
        throw PluginExecutionException(
            '插件声明了但未实现: ${missing.join(', ')}');
      }
      _pump();
      if (backgroundTicks &&
          manifest.hasPermission(PluginPermission.backgroundTimers) &&
          _hasHandlerSync('backgroundTick')) {
        _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          _runBackgroundTick();
        });
      }
    } catch (e) {
      close();
      rethrow;
    }
  }

  Future<void> _runBackgroundTick() async {
    if (_closed || _tickRunning) return;
    _tickRunning = true;
    try {
      await invoke('backgroundTick', const {}, discardResult: true);
    } catch (_) {
      // A rejected tick is logged by the host; future ticks still run.
    } finally {
      _tickRunning = false;
    }
  }

  Future<Map<String, String>> _loadModuleSources() async {
    final result = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.js')) {
        continue;
      }
      final length = await entity.length();
      if (length > maxModuleBytes) {
        throw PluginExecutionException('插件模块过大: ${entity.path}');
      }
      final relative = entity.path
          .substring(root.path.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      result[relative] = await entity.readAsString();
    }
    result.putIfAbsent(manifest.entry, () => '');
    if ((result[manifest.entry] ?? '').isEmpty) {
      throw PluginExecutionException('插件入口不存在: ${manifest.entry}');
    }
    return result;
  }

  bool _hasHandlerSync(String name) {
    final js = _js;
    if (js == null) return false;
    final result =
        js.evaluate('typeof __qplayerHandlers[${jsonEncode(name)}] === "function"');
    return result.stringResult == 'true';
  }

  Future<bool> hasHandler(String name) => _enqueue(() async {
        _pump();
        return _hasHandlerSync(name);
      });

  Future<dynamic> invoke(
    String name,
    Map<String, dynamic> arguments, {
    bool discardResult = false,
  }) async {
    if (name.isEmpty) {
      throw ArgumentError('handler name is empty');
    }
    final js = _js;
    if (js == null || _closed) {
      throw PluginExecutionException('plugin runtime is closed');
    }
    if (!_hasHandlerSync(name)) {
      throw PluginExecutionException(
          'plugin ${manifest.id} does not implement $name');
    }
    final requestedAt = DateTime.now();
    final callId = ++_sequence;
    final argsJson = jsonEncode(arguments);
    // Handlers are promise based: the JS call itself only kicks off the work
    // (usually an HTTP request) and returns immediately. Running them
    // concurrently keeps a slow home-feed fetch from blocking a playlist open.
    js.evaluate(
      '__qplayerRun($callId, ${jsonEncode(name)}, ${jsonEncode(argsJson)})',
    );
    _pump();

    final deadline = DateTime.now().add(callTimeout);
    while (true) {
      final raw = js.evaluate('__qplayerPoll($callId)').stringResult;
      final state = jsonDecode(raw);
      if (state is Map && state['done'] == true) {
        final elapsed = DateTime.now().difference(requestedAt).inMilliseconds;
        if (kDebugMode && name != 'backgroundTick') {
          debugPrint('[plugin:${manifest.id}] $name '
              'ok=${state['ok']} ${elapsed}ms '
              '${state['ok'] == true ? _preview(state['value']) : state['error']}');
        }
        if (state['ok'] == true) {
          if (discardResult) return null;
          return state['value'];
        }
        throw PluginExecutionException(
          (state['error']?.toString().trim().isNotEmpty ?? false)
              ? state['error'].toString().trim()
              : 'plugin promise rejected',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
            'plugin call timed out: ${manifest.id}.$name', callTimeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 4));
      _pump();
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_closed) {
        if (!completer.isCompleted) {
          completer.completeError(
              PluginExecutionException('plugin runtime is closed'));
        }
        return;
      }
      try {
        final value = await action();
        if (!completer.isCompleted) completer.complete(value);
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _onHostMessage(dynamic payload) {
    if (payload is! Map) return;
    final message = payload.cast<String, dynamic>();
    final id = message['id'];
    final method = message['method']?.toString() ?? '';
    final args = message['args'] is Map
        ? (message['args'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    // Never re-enter the engine from inside sendMessage(); schedule first.
    scheduleMicrotask(() async {
      try {
        final result = await hostCall(manifest.id, method, args);
        _finishHostCall(id, true, result);
      } catch (error) {
        _finishHostCall(id, false, error.toString());
      }
    });
  }

  void _finishHostCall(Object? id, bool ok, Object? value) {
    final js = _js;
    if (js == null || _closed) return;
    if (kDebugMode) {
      final preview = ok ? _preview(value) : value.toString();
      debugPrint('[plugin:${manifest.id}] host#$id ok=$ok $preview');
    }
    if (ok) {
      String encoded;
      try {
        encoded = jsonEncode(value);
      } catch (_) {
        encoded = 'null';
      }
      js.evaluate(
        '__qplayerHostResult($id, true, ${jsonEncode(encoded)})',
      );
    } else {
      final message = value?.toString() ?? 'host call failed';
      js.evaluate(
        '__qplayerHostResult($id, false, ${jsonEncode(message)})',
      );
    }
    _pump();
  }

  void _pump() {
    final js = _js;
    if (js == null) return;
    try {
      js.executePendingJob();
    } catch (_) {
      // Pending-job errors surface through the polled call state.
    }
  }

  static String _preview(Object? value) {
    String text;
    try {
      text = jsonEncode(value);
    } catch (_) {
      text = value.toString();
    }
    return text.length <= 400 ? text : '${text.substring(0, 400)}…';
  }

  dynamic _evaluateChecked(JavascriptRuntime js, String code) {
    final result = js.evaluate(code);
    if (result.isError) {
      throw PluginExecutionException(
          result.stringResult.trim().isEmpty
              ? 'plugin JavaScript error'
              : result.stringResult.trim());
    }
    return result.rawResult;
  }

  void close() {
    _closed = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    final js = _js;
    _js = null;
    if (js != null) {
      try {
        js.dispose();
      } catch (_) {
        // Engine teardown is best-effort.
      }
    }
  }

  String _bootstrap(Map<String, String> sources) {
    final permissions = manifest.permissionSet.map((p) => p.wireName).toList();
    return '''
(function () {
  'use strict';
  var __qplayerSources = ${jsonEncode(sources)};
  var __qplayerCache = {};
  var __qplayerPermissions = ${jsonEncode(permissions)};
  var __qplayerHostSeq = 0;
  var __qplayerHostPending = {};
  var __qplayerCalls = {};
  var __qplayerRegistered = null;
  var __qplayerSend = (typeof sendMessage === 'function') ? sendMessage : null;

  try { delete globalThis.sendMessage; } catch (e) {}
  try { delete globalThis.setTimeout; } catch (e) {}
  try { delete globalThis.setInterval; } catch (e) {}
  try { delete globalThis.clearTimeout; } catch (e) {}
  try { delete globalThis.clearInterval; } catch (e) {}
  try { delete globalThis.fetch; } catch (e) {}
  try { delete globalThis.XMLHttpRequest; } catch (e) {}

  function __qplayerPermissionFor(method) {
    if (method.indexOf('http.') === 0) return 'network';
    if (method.indexOf('credentials.') === 0) return 'credentials';
    if (method.indexOf('webAuth.') === 0) return 'webAuth';
    if (method.indexOf('clipboard.') === 0) return 'clipboard';
    if (method.indexOf('openUrl.') === 0) return 'openUrl';
    if (method === 'playback.read') return 'playbackRead';
    if (method.indexOf('playback.') === 0) return 'playbackControl';
    if (method.indexOf('queue.') === 0) return 'queueWrite';
    if (method.indexOf('notifications.') === 0) return 'notifications';
    if (method.indexOf('timers.') === 0) return 'backgroundTimers';
    if (method.indexOf('files.') === 0) return 'files.save';
    return null;
  }

  function __qplayerUnprivileged(method) {
    return method.indexOf('storage.') === 0 ||
      method.indexOf('crypto.') === 0 ||
      method.indexOf('compression.') === 0 ||
      method.indexOf('events.') === 0 ||
      method.indexOf('qr.') === 0;
  }

  var qplayer = {
    pluginId: ${jsonEncode(manifest.id)},
    call: function (method, args) {
      method = String(method == null ? '' : method);
      var required = __qplayerPermissionFor(method);
      if ((required === null && !__qplayerUnprivileged(method)) ||
          (required !== null && __qplayerPermissions.indexOf(required) < 0)) {
        throw new Error('permission denied for host method ' + method);
      }
      if (__qplayerSend === null) {
        return Promise.reject(new Error('host bridge unavailable'));
      }
      return new Promise(function (resolve, reject) {
        var id = ++__qplayerHostSeq;
        __qplayerHostPending[id] = { resolve: resolve, reject: reject };
        __qplayerSend('qplayer.host', JSON.stringify({
          id: id,
          method: method,
          args: (args && typeof args === 'object') ? args : {}
        }));
      });
    },
    register: function (plugin) {
      if (__qplayerRegistered !== null) throw new Error('plugin registered twice');
      __qplayerRegistered = plugin;
    }
  };
  globalThis.qplayer = qplayer;

  function __qplayerNormalize(requested, parent) {
    if (typeof requested !== 'string' || requested.length === 0 ||
        requested.indexOf(':') >= 0) {
      throw new Error('invalid module path');
    }
    if (parent !== null && requested.indexOf('./') !== 0 &&
        requested.indexOf('../') !== 0) {
      throw new Error('only relative plugin modules may be required');
    }
    var combined = (parent === null || parent === '') ? requested : parent + '/' + requested;
    var parts = combined.split('/');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (part === '' || part === '.') continue;
      if (part === '..') {
        if (out.length === 0) throw new Error('module escapes plugin package');
        out.pop();
      } else {
        out.push(part);
      }
    }
    var path = out.join('/');
    if (path.indexOf('..') === 0) throw new Error('module escapes plugin package');
    if (!/\\.js\$/.test(path)) path += '.js';
    return path;
  }

  function __qplayerRequire(parent) {
    return function (requested) {
      return __qplayerLoad(__qplayerNormalize(requested, parent));
    };
  }

  function __qplayerLoad(path) {
    if (__qplayerCache[path]) return __qplayerCache[path].exports;
    var source = __qplayerSources[path];
    if (typeof source !== 'string') throw new Error('plugin module not found: ' + path);
    var module = { exports: {} };
    __qplayerCache[path] = module;
    var dir = path.indexOf('/') < 0 ? '' : path.substring(0, path.lastIndexOf('/'));
    var fn = new Function('exports', 'module', 'require', 'qplayer',
      source + '\\n//# sourceURL=' + path);
    fn.call(module.exports, module.exports, module, __qplayerRequire(dir), qplayer);
    return module.exports;
  }

  var entry = __qplayerLoad(${jsonEncode(manifest.entry)});
  var plugin = __qplayerRegistered !== null ? __qplayerRegistered : entry;
  if (!plugin || typeof plugin !== 'object' || !plugin.handlers ||
      typeof plugin.handlers !== 'object') {
    throw new Error('plugin entry must export { handlers: {...} }');
  }
  globalThis.__qplayerHandlers = plugin.handlers;

  globalThis.__qplayerRun = function (callId, name, argsJson) {
    var state = { done: false, ok: false, value: null, error: '' };
    __qplayerCalls[callId] = state;
    try {
      var fn = __qplayerHandlers[name];
      if (typeof fn !== 'function') throw new Error('plugin does not implement ' + name);
      var args = argsJson ? JSON.parse(argsJson) : {};
      Promise.resolve(fn(args)).then(function (value) {
        state.done = true; state.ok = true; state.value = value;
      }, function (error) {
        state.done = true; state.ok = false;
        state.error = (error && error.message) ? String(error.message) : String(error);
      });
    } catch (error) {
      state.done = true; state.ok = false;
      state.error = (error && error.message) ? String(error.message) : String(error);
    }
  };

  globalThis.__qplayerPoll = function (callId) {
    var state = __qplayerCalls[callId];
    if (!state) return JSON.stringify({ done: true, ok: false, error: 'unknown call' });
    if (!state.done) return JSON.stringify({ done: false });
    delete __qplayerCalls[callId];
    var payload = { done: true, ok: state.ok, value: state.ok ? state.value : null,
      error: state.ok ? '' : state.error };
    try {
      return JSON.stringify(payload);
    } catch (error) {
      return JSON.stringify({ done: true, ok: false,
        error: 'plugin result is not serializable: ' + String(error) });
    }
  };

  globalThis.__qplayerHostResult = function (id, ok, payload) {
    var pending = __qplayerHostPending[id];
    if (!pending) return;
    delete __qplayerHostPending[id];
    if (ok) {
      var value = null;
      try { value = JSON.parse(payload); } catch (e) { value = null; }
      pending.resolve(value);
    } else {
      pending.reject(new Error(String(payload)));
    }
  };
})();
''';
  }
}
