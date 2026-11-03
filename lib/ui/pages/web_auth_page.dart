import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Host-controlled web view used for `webAuth.runScript`.
///
/// The page is navigated to [originUrl], then [script] is evaluated with a
/// `qplayerWebAuthDone(value)` bridge. The returned string is the value passed
/// to that function. Runs for at most 45 seconds.
class WebAuthPage extends StatefulWidget {
  const WebAuthPage({
    super.key,
    required this.originUrl,
    required this.script,
  });

  final String originUrl;
  final String script;

  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  State<WebAuthPage> createState() => _WebAuthPageState();
}

class _WebAuthPageState extends State<WebAuthPage> {
  static const String _channel = 'QPlayerWebAuth';

  WebViewController? _webView;
  Timer? _timeout;
  bool _started = false;
  bool _finished = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 45), () {
      if (_finished) return;
      _finish(null, error: '网页登录超时');
    });
    if (!WebAuthPage.supported) {
      _error = '当前平台不支持内置网页登录';
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0B10))
      ..addJavaScriptChannel(
        _channel,
        onMessageReceived: (message) {
          if (_finished) return;
          _finish(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _maybeRunScript(),
        ),
      )
      ..loadRequest(Uri.parse(widget.originUrl));
    _webView = controller;
  }

  Future<void> _maybeRunScript() async {
    if (_started || _finished || _webView == null) return;
    _started = true;
    try {
      await _webView!.runJavaScript('''
        (function () {
          window.qplayerWebAuthDone = function (value) {
            $_channel.postMessage(String(value == null ? "" : value));
          };
        })();
      ''');
      await _webView!.runJavaScript(widget.script);
    } catch (e) {
      if (_finished) return;
      _finish(null, error: '网页登录脚本执行失败：$e');
    }
  }

  void _finish(String? value, {String error = ''}) {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    if (!mounted) return;
    if (error.isNotEmpty) {
      setState(() => _error = error);
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(value ?? '');
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页登录'),
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => _finish(null),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: Stack(
        children: [
          if (_webView != null)
            WebViewWidget(controller: _webView!)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Material(
              color: theme.colorScheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error.isEmpty
                            ? '正在该网页上完成登录，请稍候…'
                            : _error,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _finish(null),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive sign-in page for `web` login methods. Waits for the provider
/// cookie named by the plugin, then returns the complete Cookie header.
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    super.key,
    required this.url,
    required this.cookieUrl,
    required this.cookieName,
  });

  final String url;
  final String cookieUrl;
  final String cookieName;

  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  WebViewController? _webView;
  Timer? _poll;
  bool _checking = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (WebLoginPage.supported) {
      _webView = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0A0B10))
        ..loadRequest(Uri.parse(widget.url));
      _poll = Timer.periodic(
        const Duration(milliseconds: 900),
        (_) => _checkCookie(),
      );
    }
  }

  Future<void> _checkCookie() async {
    if (_checking || _finished) return;
    _checking = true;
    try {
      final uri = Uri.tryParse(widget.cookieUrl);
      if (uri == null) return;
      final cookies =
          await WebViewCookieManager().getCookies(domain: uri);
      final match = cookies.any((cookie) => cookie.name == widget.cookieName);
      if (!match) return;
      final header = cookies
          .where((cookie) => cookie.name.isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (header.isEmpty) return;
      _finish(header);
    } catch (_) {
      // Keep waiting; cookie access can race with navigation.
    } finally {
      _checking = false;
    }
  }

  Future<void> _finish(String header) async {
    if (_finished || !mounted) return;
    _finished = true;
    _poll?.cancel();
    try {
      final uri = Uri.tryParse(widget.cookieUrl);
      if (uri != null) {
        final cookies =
            await WebViewCookieManager().getCookies(domain: uri);
        final complete = cookies
            .where((cookie) => cookie.name.isNotEmpty)
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
        if (complete.isNotEmpty) header = complete;
      }
    } catch (_) {
      // The header captured in _checkCookie is still usable.
    }
    if (!mounted) return;
    Navigator.of(context).pop(header);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          TextButton(
            onPressed: () => _finish(''),
            child: const Text('完成'),
          ),
        ],
      ),
      body: _webView == null
          ? const Center(child: Text('当前平台不支持内置网页登录'))
          : WebViewWidget(controller: _webView!),
    );
  }
}
