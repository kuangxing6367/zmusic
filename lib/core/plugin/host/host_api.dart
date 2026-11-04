import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as c;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/api.dart'
    show
        AEADParameters,
        BlockCipher,
        CipherParameters,
        KeyParameter,
        ParametersWithIV,
        PaddedBlockCipherParameters;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

import '../plugin_hashes.dart';
import '../plugin_manifest.dart';
import '../plugin_permission.dart';

class HostCallException implements Exception {
  HostCallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Services implemented by the Flutter shell (player, trampoline, save dialog).
abstract class PluginAppBridge {
  Future<Map<String, dynamic>> playbackRead(String pluginId);

  Future<void> playbackPlay();

  Future<void> playbackPause();

  Future<void> playbackSeek(int positionMs);

  Future<void> playbackSelect(
    String pluginId,
    String songId,
    int positionMs,
    bool playing,
  );

  Future<void> playbackNext();

  Future<void> blockAutoAdvance(String pluginId, bool blocked);

  Future<void> replaceQueue(String pluginId, Map<String, dynamic> arguments);

  Future<bool> downloadCurrent(String pluginId);

  Future<bool> saveUrl({
    required String url,
    Map<String, String> headers,
    String filename,
    String mimeType,
  });

  Future<String> runWebAuth(String originUrl, String script);

  void toast(String message);

  Future<void> copyText(String text);

  Future<void> openUrl(String url);
}

/// Core-owned, namespaced implementations of the plugin host ABI.
class CorePluginHostApi {
  CorePluginHostApi({
    required this.storageRoot,
    required this.manifestOf,
    required this.appBridge,
    this.secureStorage = const FlutterSecureStorage(),
  });

  final Directory storageRoot;
  final PluginManifest? Function(String pluginId) manifestOf;
  final PluginAppBridge appBridge;
  final FlutterSecureStorage secureStorage;

  static const int maxStorageBytes = 1024 * 1024;
  static const int maxHttpBytes = 16 * 1024 * 1024;
  static const int maxRedirects = 5;

  static final RegExp _keyPattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  Future<dynamic> call(
    String pluginId,
    String method,
    Map<String, dynamic> args,
  ) async {
    final manifest = manifestOf(pluginId);
    if (manifest == null) {
      throw HostCallException('plugin is not enabled: $pluginId');
    }
    _requirePermission(manifest, method);

    switch (method) {
      case 'storage.get':
        return _storageGet(pluginId, args);
      case 'storage.put':
        return _storagePut(pluginId, args);
      case 'storage.delete':
        return _storageDelete(pluginId, args);
      case 'credentials.get':
        return _credentialGet(pluginId, args);
      case 'credentials.put':
        return _credentialPut(pluginId, args);
      case 'credentials.delete':
        return _credentialDelete(pluginId, args);
      case 'http.request':
        return _httpRequest(manifest, args);
      case 'crypto.sha256':
        return _sha256(args);
      case 'crypto.digest':
        return _digest(args);
      case 'crypto.random':
        return _random(args);
      case 'crypto.aes':
        return _aes(args);
      case 'crypto.hmac':
        return _hmac(args);
      case 'crypto.modPow':
        return _modPow(args);
      case 'crypto.x25519':
        return _x25519(args);
      case 'compression.gunzip':
        return _gunzip(args);
      case 'playback.read':
        return appBridge.playbackRead(pluginId);
      case 'playback.play':
        await appBridge.playbackPlay();
        return true;
      case 'playback.pause':
        await appBridge.playbackPause();
        return true;
      case 'playback.seek':
        await appBridge.playbackSeek(_int(args['positionMs']));
        return true;
      case 'playback.select':
        await appBridge.playbackSelect(
          pluginId,
          _string(args['songId']),
          args.containsKey('positionMs') ? _int(args['positionMs']) : 0,
          args.containsKey('playing') ? args['playing'] == true : true,
        );
        return true;
      case 'playback.next':
        await appBridge.playbackNext();
        return true;
      case 'playback.blockAutoAdvance':
        await appBridge.blockAutoAdvance(pluginId, args['blocked'] == true);
        return true;
      case 'queue.replace':
        await appBridge.replaceQueue(pluginId, args);
        return true;
      case 'notifications.toast':
        appBridge.toast(_clip(_string(args['message']), 500));
        return true;
      case 'clipboard.write':
        await appBridge.copyText(_clip(_string(args['text']), 16 * 1024));
        return true;
      case 'files.downloadCurrent':
        return appBridge.downloadCurrent(pluginId);
      case 'files.save':
        return _filesSave(manifest, args);
      case 'webAuth.runScript':
        return _webAuth(manifest, args);
      default:
        // `openUrl` has no public call in the original ABI, but the prefix is
        // accepted by the gate. Reject unknown methods instead of guessing.
        throw HostCallException('unknown host method: $method');
    }
  }

  void _requirePermission(PluginManifest manifest, String method) {
    PluginPermission? required;
    if (method.startsWith('http.')) {
      required = PluginPermission.network;
    } else if (method.startsWith('credentials.')) {
      required = PluginPermission.credentials;
    } else if (method.startsWith('webAuth.')) {
      required = PluginPermission.webAuth;
    } else if (method.startsWith('clipboard.')) {
      required = PluginPermission.clipboard;
    } else if (method.startsWith('openUrl.')) {
      required = PluginPermission.openUrl;
    } else if (method == 'playback.read') {
      required = PluginPermission.playbackRead;
    } else if (method.startsWith('playback.')) {
      required = PluginPermission.playbackControl;
    } else if (method.startsWith('queue.')) {
      required = PluginPermission.queueWrite;
    } else if (method.startsWith('notifications.')) {
      required = PluginPermission.notifications;
    } else if (method.startsWith('timers.')) {
      required = PluginPermission.backgroundTimers;
    } else if (method.startsWith('files.')) {
      required = PluginPermission.filesSave;
    }
    if (required != null && !manifest.hasPermission(required)) {
      throw HostCallException('permission denied for host method $method');
    }
  }

  // ---------------------------------------------------------------------------
  // Storage & credentials

  Directory _pluginDataDir(String pluginId) =>
      Directory('${storageRoot.path}${Platform.pathSeparator}$pluginId');

  String _keyFile(String pluginId, String key) {
    _validateKey(key);
    return '${_pluginDataDir(pluginId).path}${Platform.pathSeparator}'
        '${PluginHashes.textSha256Hex(key)}.json';
  }

  void _validateKey(String key) {
    if (!_keyPattern.hasMatch(key)) {
      throw HostCallException('invalid storage key');
    }
  }

  Future<dynamic> _storageGet(String pluginId, Map<String, dynamic> args) async {
    final key = _string(args['key']);
    final file = File(_keyFile(pluginId, key));
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['key'] != key) return null;
      return raw['value'];
    } catch (_) {
      return null;
    }
  }

  Future<bool> _storagePut(String pluginId, Map<String, dynamic> args) async {
    final key = _string(args['key']);
    final file = File(_keyFile(pluginId, key));
    final envelope = jsonEncode({'key': key, 'value': args['value']});
    if (utf8.encode(envelope).length > maxStorageBytes) {
      throw HostCallException('storage record exceeds 1 MiB');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(envelope, flush: true);
    await temp.rename(file.path);
    return true;
  }

  Future<bool> _storageDelete(
      String pluginId, Map<String, dynamic> args) async {
    final file = File(_keyFile(pluginId, _string(args['key'])));
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  String _credentialKey(String pluginId, String key) {
    _validateKey(key);
    return 'qplayer.$pluginId.${PluginHashes.textSha256Hex(key)}';
  }

  Future<String?> _credentialGet(
      String pluginId, Map<String, dynamic> args) async {
    return secureStorage.read(key: _credentialKey(pluginId, _string(args['key'])));
  }

  Future<bool> _credentialPut(String pluginId, Map<String, dynamic> args) async {
    final value = _string(args['value']);
    if (value.isEmpty) throw HostCallException('credential value is empty');
    if (utf8.encode(value).length > 1024 * 1024) {
      throw HostCallException('credential exceeds 1 MiB');
    }
    await secureStorage.write(
      key: _credentialKey(pluginId, _string(args['key'])),
      value: value,
    );
    return true;
  }

  Future<bool> _credentialDelete(
      String pluginId, Map<String, dynamic> args) async {
    final storageKey = _credentialKey(pluginId, _string(args['key']));
    final existed = await secureStorage.read(key: storageKey) != null;
    await secureStorage.delete(key: storageKey);
    return existed;
  }

  // ---------------------------------------------------------------------------
  // Network

  Future<Map<String, dynamic>> _httpRequest(
    PluginManifest manifest,
    Map<String, dynamic> args,
  ) async {
    final rawUrl = _string(args['url']);
    if (rawUrl.isEmpty || rawUrl.length > 16 * 1024) {
      throw HostCallException('invalid request url');
    }
    var method = _string(args['method']).toUpperCase();
    if (method.isEmpty) method = 'GET';
    final allowedMethods = manifest.networkMethods.isEmpty
        ? const {'GET', 'POST'}
        : manifest.networkMethods.toSet();
    if (!allowedMethods.contains(method)) {
      throw HostCallException('method not allowed: $method');
    }
    final headers = _cleanHeaders(args['headers']);
    final timeout = _int(args['timeoutMs']).clamp(1000, 30000);
    // The music CDNs occasionally accept a request and then send nothing for
    // half a minute. Capping the idle timeout keeps a stalled playlist fetch
    // from hanging for the plugin's full 30 s budget; the retry below then
    // usually succeeds in well under a second.
    final receiveTimeout = Duration(milliseconds: timeout < 12000 ? timeout : 12000);
    final follow = args.containsKey('followRedirects')
        ? args['followRedirects'] == true
        : true;
    final includeBase64 = args['includeBase64'] == true;

    dynamic data;
    final hasBody = args['bodyBase64'] != null ||
        args['body'] != null ||
        args['multipart'] != null;
    if (args['bodyBase64'] != null) {
      final encoded = _string(args['bodyBase64']);
      if (encoded.isEmpty) throw HostCallException('bodyBase64 is empty');
      data = base64Decode(encoded);
    } else if (args['body'] != null) {
      final body = _string(args['body']);
      if (body.isEmpty) throw HostCallException('body is empty');
      data = utf8.encode(body);
    } else if (args['multipart'] is Map) {
      data = _multipart(args['multipart'] as Map);
    }
    if (!hasBody) data = null;

    final dio = Dio(BaseOptions(
      connectTimeout: Duration(milliseconds: timeout),
      receiveTimeout: receiveTimeout,
      sendTimeout: Duration(milliseconds: timeout),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.bytes,
    ));
    // When the plugin did not choose an encoding, negotiate gzip
    // and decode it here instead of relying on the HTTP client's transparency.
    final pluginEncoding = headers.keys
        .firstWhere((key) => key.toLowerCase() == 'accept-encoding',
            orElse: () => '');
    final hostNegotiatedGzip = pluginEncoding.isEmpty;
    if (hostNegotiatedGzip) headers['Accept-Encoding'] = 'gzip';
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.autoUncompress = false;
        return client;
      },
    );

    var currentUrl = rawUrl;
    var currentMethod = method;
    var currentData = data;
    final currentHeaders = Map<String, String>.from(headers);
    final setCookies = <String>[];

    for (var hop = 0; hop <= maxRedirects; hop++) {
      _requireUrlGrant(manifest, currentUrl);
      final watch = Stopwatch()..start();

      Future<Response<List<int>>> send() => dio.request<List<int>>(
            currentUrl,
            data: currentData,
            options: Options(
              method: currentMethod,
              headers: currentHeaders,
              followRedirects: false,
              responseType: ResponseType.bytes,
              validateStatus: (_) => true,
            ),
          );

      Response<List<int>> response;
      try {
        response = await send();
      } on DioException catch (first) {
        final retryable = first.type == DioExceptionType.receiveTimeout ||
            first.type == DioExceptionType.connectionTimeout ||
            first.type == DioExceptionType.connectionError;
        if (!retryable) {
          if (kDebugMode) {
            debugPrint('[host] FAILED $currentMethod $currentUrl '
                't=${watch.elapsedMilliseconds}ms type=${first.type.name}');
          }
          throw HostCallException('网络请求失败: ${first.message ?? first.type.name}');
        }
        if (kDebugMode) {
          debugPrint('[host] retry $currentMethod $currentUrl after '
              '${first.type.name} (${watch.elapsedMilliseconds}ms)');
        }
        try {
          response = await send();
        } on DioException catch (second) {
          if (kDebugMode) {
            debugPrint('[host] FAILED $currentMethod $currentUrl '
                't=${watch.elapsedMilliseconds}ms type=${second.type.name}');
          }
          throw HostCallException(
              '网络请求失败: ${second.message ?? second.type.name}');
        }
      }
      if (kDebugMode) {
        final rawLen = response.data?.length ?? -1;
        final sent = currentData;
        final preview = sent is List<int> && sent.isNotEmpty
            ? utf8.decode(sent.take(90).toList(), allowMalformed: true)
            : '';
        debugPrint('[host] $currentMethod $currentUrl '
            't=${watch.elapsedMilliseconds}ms '
            'send=${sent?.length ?? 0} recv=$rawLen '
            'enc=${response.headers.value('content-encoding')} '
            'len=${response.headers.value('content-length')} '
            'body=${preview.replaceAll('\n', ' ')}');
      }

      final location = response.headers.value('location');
      final status = response.statusCode ?? 0;
      if (follow && location != null && status >= 300 && status < 400) {
        if (hop == maxRedirects) throw HostCallException('too many redirects');
        final cookies = response.headers['set-cookie'] ?? const [];
        setCookies.addAll(cookies);
        currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        if (status == 303 ||
            ((status == 301 || status == 302) && currentMethod == 'POST')) {
          currentMethod = 'GET';
          currentData = null;
          currentHeaders.remove('Content-Type');
        }
        continue;
      }

      var bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.length > maxHttpBytes) {
        throw HostCallException('response exceeds 16 MiB');
      }
      final contentEncoding =
          response.headers.value('content-encoding')?.toLowerCase() ?? '';
      final decoded = hostNegotiatedGzip && contentEncoding == 'gzip';
      if (decoded) {
        try {
          bytes = Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
        } on FormatException {
          throw HostCallException('invalid gzip response body');
        }
      }
      if (bytes.length > maxHttpBytes) {
        throw HostCallException('response body exceeds 16 MiB');
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (decoded &&
            (lower == 'content-encoding' || lower == 'content-length')) {
          return;
        }
        responseHeaders[name] = values.join(', ');
      });
      final cookies = response.headers['set-cookie'] ?? const [];
      setCookies.addAll(cookies);

      return {
        'status': status,
        'finalUrl': currentUrl,
        'body': utf8.decode(bytes, allowMalformed: true),
        'headers': responseHeaders,
        'setCookies': setCookies,
        if (includeBase64) 'bodyBase64': base64Encode(bytes),
      };
    }
    throw HostCallException('too many redirects');
  }

  Map<String, String> _cleanHeaders(Object? raw) {
    final result = <String, String>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries.take(64)) {
      final name = entry.key.toString();
      final value = entry.value?.toString() ?? '';
      if (!RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name) ||
          name.length > 128 ||
          value.length > 8192 ||
          value.contains('\r') ||
          value.contains('\n')) {
        continue;
      }
      final lower = name.toLowerCase();
      if (lower == 'host' || lower == 'content-length' || lower == 'connection') {
        continue;
      }
      result[name] = value;
    }
    return result;
  }

  FormData _multipart(Map raw) {
    final form = FormData();
    final fields = raw['fields'];
    if (fields is Map) {
      for (final entry in fields.entries.take(32)) {
        form.fields.add(MapEntry(
          entry.key.toString(),
          _clip(entry.value?.toString() ?? '', 4096),
        ));
      }
    }
    final file = raw['file'];
    if (file is Map) {
      final field = _string(file['field']);
      final filename = _string(file['filename']);
      final bytes = base64Decode(_string(file['bodyBase64']));
      if (bytes.isNotEmpty) {
        form.files.add(MapEntry(
          field.isEmpty ? 'file' : field,
          MultipartFile.fromBytes(
            bytes,
            filename: filename.isEmpty ? 'upload.bin' : filename,
            contentType: null,
          ),
        ));
      }
    }
    return form;
  }

  void _requireUrlGrant(PluginManifest manifest, String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw HostCallException('invalid url');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw HostCallException('unsupported url scheme');
    }
    if (scheme == 'http' && !manifest.hasPermission(PluginPermission.clearTextNetwork)) {
      throw HostCallException('clear text network is not permitted');
    }
    if (!manifest.networkDomains.any((pattern) => _domainMatches(pattern, uri.host))) {
      throw HostCallException('url is not covered by networkDomains: ${uri.host}');
    }
    if (_isLocalHost(uri.host) &&
        !manifest.hasPermission(PluginPermission.localNetwork)) {
      throw HostCallException('local network is not permitted');
    }
  }

  static bool _domainMatches(String pattern, String host) {
    final domain = host.toLowerCase();
    final rule = pattern.toLowerCase();
    if (rule.startsWith('*.')) {
      final suffix = rule.substring(2);
      return domain.endsWith('.$suffix') && domain != suffix;
    }
    return domain == rule;
  }

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h.endsWith('.local')) return true;
    final parts = h.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      final a = int.parse(parts[0]);
      final b = int.parse(parts[1]);
      if (a == 10 || a == 127) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 169 && b == 254) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Cryptography & compression

  String _sha256(Map<String, dynamic> args) {
    final value = _string(args['value']);
    return crypto.sha256.convert(utf8.encode(value)).toString();
  }

  String _digest(Map<String, dynamic> args) {
    final algorithm = _string(args['algorithm']);
    final data = _decode(_string(args['data']),
        _string(args['dataEncoding']).isEmpty ? 'utf8' : _string(args['dataEncoding']));
    final output = _encoding(args['outputEncoding']);
    final dynamic digest = switch (algorithm) {
      'SHA-256' => crypto.sha256,
      'SHA-1' => crypto.sha1,
      'MD5' => crypto.md5,
      _ => throw HostCallException('unsupported digest: $algorithm'),
    };
    return _encode(Uint8List.fromList(digest.convert(data).bytes), output);
  }

  String _random(Map<String, dynamic> args) {
    final length = args.containsKey('length') ? _int(args['length']) : 16;
    if (length < 1 || length > 1024) {
      throw HostCallException('random length out of range');
    }
    final random = Random.secure();
    final bytes = Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
    return _encode(bytes, _encoding(args['outputEncoding']));
  }

  String _aes(Map<String, dynamic> args) {
    final transformation = _string(args['transformation']).toUpperCase();
    final key = _decode(_string(args['key']), _encoding(args['keyEncoding']));
    if (!const {16, 24, 32}.contains(key.length)) {
      throw HostCallException('invalid AES key length');
    }
    final data = _decode(_string(args['data']),
        _string(args['dataEncoding']).isEmpty ? 'utf8' : _encoding(args['dataEncoding']));
    final decrypt = _string(args['operation']).toLowerCase() == 'decrypt';
    final output = _encoding(args['outputEncoding']);

    if (transformation == 'AES/GCM/NOPADDING') {
      final iv = _decode(_string(args['iv']), _encoding(args['ivEncoding']));
      if (iv.length != 12) throw HostCallException('GCM requires a 12-byte IV');
      final aad = args['aad'] == null
          ? Uint8List(0)
          : _decode(_string(args['aad']), _encoding(args['aadEncoding']));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(!decrypt,
            AEADParameters(KeyParameter(key), 128, iv, aad));
      final result = cipher.process(data);
      return _encode(result, output);
    }

    final BlockCipher base = switch (transformation) {
      'AES/CBC/PKCS5PADDING' => CBCBlockCipher(AESEngine()),
      'AES/ECB/PKCS5PADDING' => ECBBlockCipher(AESEngine()),
      _ => throw HostCallException('unsupported AES transformation'),
    };
    final iv = transformation.contains('/CBC/')
        ? _decode(_string(args['iv']), _encoding(args['ivEncoding']))
        : Uint8List(0);
    if (transformation.contains('/CBC/') && iv.length != 16) {
      throw HostCallException('CBC requires a 16-byte IV');
    }
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), base);
    final CipherParameters params = transformation.contains('/CBC/')
        ? ParametersWithIV(KeyParameter(key), iv)
        : KeyParameter(key);
    cipher.init(
      !decrypt,
      PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
          params, null),
    );

    if (data.isEmpty) {
      // BaseBlockCipher.process only handles a single block, so empty input has
      // to be padded/handled explicitly to mirror javax.crypto doFinal().
      if (decrypt) return _encode(Uint8List(0), output);
      return _encode(Uint8List(16)..fillRange(0, 16, 16), output);
    }
    if (decrypt && data.length % 16 != 0) {
      throw HostCallException('invalid AES ciphertext length');
    }
    Uint8List result;
    try {
      result = cipher.process(data);
    } on ArgumentError {
      throw HostCallException('invalid AES padding');
    }
    return _encode(result, output);
  }

  String _hmac(Map<String, dynamic> args) {
    final algorithm = _string(args['algorithm']);
    final key = _decode(_string(args['key']), _encoding(args['keyEncoding']));
    final data = _decode(_string(args['data']),
        _string(args['dataEncoding']).isEmpty ? 'utf8' : _encoding(args['dataEncoding']));
    final output = _encoding(args['outputEncoding']);
    final dynamic hmac = switch (algorithm) {
      'HmacSHA256' => crypto.Hmac(crypto.sha256, key),
      'HmacSHA1' => crypto.Hmac(crypto.sha1, key),
      _ => throw HostCallException('unsupported HMAC: $algorithm'),
    };
    return _encode(Uint8List.fromList(hmac.convert(data).bytes), output);
  }

  String _modPow(Map<String, dynamic> args) {
    final base = _hexBigInt(_string(args['baseHex']));
    final exponent = _hexBigInt(_string(args['exponentHex']));
    final modulus = _hexBigInt(_string(args['modulusHex']));
    if (modulus.bitLength < 2) throw HostCallException('invalid modulus');
    final width = _int(args['width']);
    var result = base.modPow(exponent, modulus).toRadixString(16);
    if (width > 0) result = result.padLeft(width, '0');
    return result;
  }

  BigInt _hexBigInt(String value) {
    final hex = value.trim();
    return hex.isEmpty ? BigInt.zero : BigInt.parse(hex, radix: 16);
  }

  Future<String> _x25519(Map<String, dynamic> args) async {
    final scalar = _decode(_string(args['scalar']), _encoding(args['scalarEncoding']));
    if (scalar.length != 32) throw HostCallException('X25519 scalar must be 32 bytes');
    final pointRaw = args['point'] == null
        ? null
        : _decode(_string(args['point']), _encoding(args['pointEncoding']));
    if (pointRaw != null && pointRaw.length != 32) {
      throw HostCallException('X25519 point must be 32 bytes');
    }
    final algorithm = c.X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(scalar);
    final remote = pointRaw ??
        Uint8List.fromList(List<int>.filled(32, 0)..[0] = 9);
    final shared = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: c.SimplePublicKey(remote, type: c.KeyPairType.x25519),
    );
    final bytes = await shared.extractBytes();
    return _encode(Uint8List.fromList(bytes), _encoding(args['outputEncoding']));
  }

  String _gunzip(Map<String, dynamic> args) {
    final data = _decode(_string(args['data']),
        _string(args['dataEncoding']).isEmpty ? 'base64' : _encoding(args['dataEncoding']));
    final bytes = GZipDecoder().decodeBytes(data);
    if (bytes.length > 8 * 1024 * 1024) {
      throw HostCallException('decompressed data exceeds 8 MiB');
    }
    return _encode(Uint8List.fromList(bytes), _encoding(args['outputEncoding']));
  }

  String _encoding(Object? value) {
    final name = _string(value).toLowerCase();
    return name.isEmpty ? 'base64' : name;
  }

  Uint8List _decode(String data, String encoding) {
    try {
      return switch (encoding) {
        'base64' => base64Decode(data),
        'hex' => _hexDecode(data),
        'utf8' => Uint8List.fromList(utf8.encode(data)),
        _ => throw HostCallException('unsupported encoding: $encoding'),
      };
    } on FormatException catch (e) {
      throw HostCallException('invalid $encoding data: ${e.message}');
    }
  }

  Uint8List _hexDecode(String value) {
    final clean = value.trim();
    if (clean.length.isOdd) throw const FormatException('odd hex length');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  String _encode(Uint8List bytes, String encoding) {
    return switch (encoding) {
      'base64' => base64Encode(bytes),
      'hex' => PluginHashes.hex(bytes),
      'utf8' => utf8.decode(bytes, allowMalformed: true),
      _ => throw HostCallException('unsupported encoding: $encoding'),
    };
  }

  // ---------------------------------------------------------------------------
  // Files & web auth

  Future<bool> _filesSave(
      PluginManifest manifest, Map<String, dynamic> args) async {
    final url = _string(args['url']);
    if (url.isEmpty || url.length > 16 * 1024) {
      throw HostCallException('invalid url');
    }
    _requireUrlGrant(manifest, url);
    return appBridge.saveUrl(
      url: url,
      headers: _cleanHeaders(args['headers']),
      filename: _clip(_string(args['filename']), 180),
      mimeType: _clip(_string(args['mimeType']), 128),
    );
  }

  Future<String> _webAuth(
      PluginManifest manifest, Map<String, dynamic> args) async {
    final originUrl = _string(args['originUrl']);
    final script = _string(args['script']);
    if (originUrl.isEmpty || originUrl.length > 2048) {
      throw HostCallException('invalid origin url');
    }
    if (script.isEmpty || script.length > 256 * 1024) {
      throw HostCallException('invalid webAuth script');
    }
    _requireUrlGrant(manifest, originUrl);
    if (!originUrl.toLowerCase().startsWith('https://') &&
        !manifest.hasPermission(PluginPermission.clearTextNetwork)) {
      throw HostCallException('clear text webAuth is not permitted');
    }
    return appBridge.runWebAuth(originUrl, script);
  }

  // ---------------------------------------------------------------------------
  // Helpers

  static String _string(Object? value) => value?.toString() ?? '';

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
