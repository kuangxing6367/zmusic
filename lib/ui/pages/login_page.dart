import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../widgets/app_toast.dart';
import '../widgets/cover_art.dart';
import '../widgets/empty_state.dart';
import 'web_auth_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    required this.providerId,
  });

  final AppController controller;
  final String providerId;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _credential = TextEditingController();
  List<LoginMethod> _methods = const [];
  LoginMethod? _active;
  LoginChallenge? _challenge;
  Timer? _poll;
  bool _loadingMethods = true;
  bool _busy = false;
  bool _polling = false;
  bool _finished = false;
  String _error = '';
  int _generation = 0;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _credential.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    setState(() {
      _loadingMethods = true;
      _error = '';
    });
    try {
      final methods = await _controller.loginMethods(widget.providerId);
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _loadingMethods = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMethods = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _select(LoginMethod method) async {
    _poll?.cancel();
    _poll = null;
    _generation++;
    final generation = _generation;
    _credential.clear();
    setState(() {
      _active = method;
      _challenge = null;
      _error = '';
      _busy = true;
      _finished = false;
    });
    try {
      switch (method.type) {
        case 'qr':
        case 'app':
          final challenge = await _controller.beginLogin(
            widget.providerId,
            method.id,
          );
          if (!mounted || generation != _generation) return;
          setState(() {
            _challenge = challenge;
            _busy = false;
          });
          _handleChallenge(challenge, restartable: true);
        case 'web':
          setState(() => _busy = false);
          await _startWeb(method, generation);
        case 'credential':
          setState(() => _busy = false);
        default:
          setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startWeb(LoginMethod method, int generation) async {
    if (method.webUrl.isEmpty || method.cookieUrl.isEmpty) {
      _showError('该网页登录方式缺少必要的地址');
      return;
    }
    if (WebLoginPage.supported) {
      final header = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => WebLoginPage(
            url: method.webUrl,
            cookieUrl: method.cookieUrl,
            cookieName: method.credentialCookieName,
          ),
        ),
      );
      if (!mounted || generation != _generation) return;
      if (header == null) return;
      if (header.trim().isEmpty) {
        _showError('未检测到登录 Cookie，请重试');
        return;
      }
      await _submit(method, header.trim());
      return;
    }

    // Desktop fallback: open the provider page in the system browser, then let
    // the user paste the Cookie header captured by the browser.
    setState(() => _error = '');
    final opened = await launchUrl(
      Uri.parse(method.webUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!opened) {
      _showError('无法打开登录页面');
    }
  }

  Future<void> _submit(LoginMethod method, String credential) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final challenge = await _controller.submitLogin(
        widget.providerId,
        method.id,
        credential,
      );
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _busy = false;
      });
      _handleChallenge(challenge, restartable: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  void _handleChallenge(
    LoginChallenge challenge, {
    required bool restartable,
  }) {
    if (challenge.status == 'success') {
      unawaited(_onSuccess(challenge));
      return;
    }
    if (challenge.status == 'failed') {
      _poll?.cancel();
      setState(() => _busy = false);
      return;
    }
    if (challenge.status == 'expired') {
      _poll?.cancel();
      if (restartable && _active != null) {
        unawaited(_restart());
      }
      return;
    }
    if (challenge.id.isEmpty) {
      _poll?.cancel();
      return;
    }
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _pollOnce(challenge.id),
    );
  }

  Future<void> _restart() async {
    final method = _active;
    if (method == null) return;
    _poll?.cancel();
    _poll = null;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _challenge = null;
      _error = '';
    });
    try {
      final challenge = await _controller.beginLogin(
        widget.providerId,
        method.id,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _challenge = challenge;
        _busy = false;
      });
      _handleChallenge(challenge, restartable: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pollOnce(String challengeId) async {
    if (_polling || _finished) return;
    _polling = true;
    try {
      final challenge = await _controller.pollLogin(
        widget.providerId,
        challengeId,
      );
      if (!mounted || _finished) return;
      final merged = challenge.keepVisualsFrom(_challenge);
      setState(() => _challenge = merged);
      _handleChallenge(merged, restartable: true);
    } catch (e) {
      _poll?.cancel();
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _polling = false;
    }
  }

  Future<void> _onSuccess(LoginChallenge challenge) async {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    await _controller.refreshAccount(widget.providerId);
    if (!mounted) return;
    AppToast.success(
      challenge.account?.displayName.isNotEmpty ?? false
          ? '已登录：${challenge.account!.displayName}'
          : '登录成功',
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('将删除该插件保存的登录凭据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.logout(widget.providerId);
      if (!mounted) return;
      setState(() {
        _active = null;
        _challenge = null;
      });
      _loadMethods();
    } catch (e) {
      _showError('退出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final account = _controller.accountOf(widget.providerId);
        final providerName = _controller.providerName(widget.providerId);
        return Scaffold(
          appBar: AppBar(
            title: Text('$providerName 账号'),
            actions: [
              if (account?.loggedIn ?? false)
                TextButton(
                  onPressed: _logout,
                  child: const Text('退出登录'),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (account?.loggedIn ?? false)
                _AccountCard(account: account!),
              if (account?.loggedIn ?? false) ...[
                const SizedBox(height: 16),
                Text(
                  '登录方式',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (_loadingMethods)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_loadingMethods && _methods.isEmpty && _error.isEmpty)
                const EmptyState(
                  icon: Icons.login_rounded,
                  title: '没有可用的登录方式',
                  message: '该音源插件没有声明登录能力，或暂时不可用。',
                  compact: true,
                ),
              if (!_loadingMethods && _active == null)
                for (final method in _methods)
                  _MethodTile(
                    method: method,
                    onTap: () => _select(method),
                  ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ErrorBanner(
                    message: _error,
                    onRetry: _active == null ? _loadMethods : null,
                  ),
                ),
              if (_active != null) ...[
                const SizedBox(height: 6),
                _ActiveLogin(
                  method: _active!,
                  challenge: _challenge,
                  busy: _busy,
                  credentialController: _credential,
                  onBack: () {
                    _poll?.cancel();
                    _generation++;
                    setState(() {
                      _active = null;
                      _challenge = null;
                      _error = '';
                    });
                  },
                  onRetry: _restart,
                  onSubmit: (value) => _submit(_active!, value),
                  onOpenUrl: (url) async {
                    final uri = Uri.tryParse(url);
                    if (uri == null) return;
                    final ok = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok) _showError('无法打开链接');
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final AccountProfile account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Row(
        children: [
          CoverArt(
            url: account.avatarUrl,
            size: 66,
            radius: 33,
            icon: Icons.person_rounded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName.isEmpty ? '已登录' : account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (account.level > 0) 'Lv.${account.level}',
                    if (account.membershipTier > 0)
                      '会员 ${account.membershipTier}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
                if (account.signature.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    account.signature,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.onTap});

  final LoginMethod method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (method.type) {
      'qr' => Icons.qr_code_2_rounded,
      'web' => Icons.public_rounded,
      'app' => Icons.phone_android_rounded,
      _ => Icons.key_rounded,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(
          method.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: method.instructions.isEmpty
            ? Text(switch (method.type) {
                'qr' => '使用手机 App 扫码',
                'web' => '在网页中完成登录',
                'app' => '在手机 App 中确认',
                _ => '输入凭据登录',
              })
            : Text(
                method.instructions,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _ActiveLogin extends StatelessWidget {
  const _ActiveLogin({
    required this.method,
    required this.challenge,
    required this.busy,
    required this.credentialController,
    required this.onBack,
    required this.onRetry,
    required this.onSubmit,
    required this.onOpenUrl,
  });

  final LoginMethod method;
  final LoginChallenge? challenge;
  final bool busy;
  final TextEditingController credentialController;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = challenge;
    final status = current?.status ?? 'waiting';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                method.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (method.instructions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              method.instructions,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (method.type == 'qr' && !busy && current != null)
          _QrBlock(challenge: current, status: status),
        if (method.type == 'app' && !busy)
          _AppBlock(
            challenge: current,
            status: status,
            onOpenUrl: onOpenUrl,
          ),
        if (method.type == 'credential' && !busy) ...[
          const SizedBox(height: 8),
          TextField(
            controller: credentialController,
            obscureText: false,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: method.credentialLabel.isEmpty
                  ? 'Cookie / 登录凭据'
                  : method.credentialLabel,
              hintText: method.credentialCookieName.isEmpty
                  ? '粘贴完整凭据'
                  : '粘贴完整的 Cookie 请求头',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final value = credentialController.text.trim();
              if (value.isEmpty) return;
              onSubmit(value);
            },
            child: const Text('提交登录'),
          ),
        ],
        if (method.type == 'web' && !busy) ...[
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    WebLoginPage.supported
                        ? '点击下方按钮打开内置浏览器完成登录。'
                        : '当前桌面平台使用外部浏览器登录。登录完成后，请在浏览器开发者工具中复制 Cookie 请求头并粘贴到下方。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: method.webUrl.isEmpty
                        ? null
                        : () => onOpenUrl(method.webUrl),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('打开登录页'),
                  ),
                  if (!WebLoginPage.supported) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: credentialController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Cookie 请求头',
                        hintText: 'name=value; name2=value2',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () {
                        final value = credentialController.text.trim();
                        if (value.isEmpty) return;
                        onSubmit(value);
                      },
                      child: const Text('提交登录'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (status == 'scanned')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              '已扫码，请在手机上确认登录',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (status == 'expired')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                Text(
                  '二维码已过期',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('重新获取'),
                ),
              ],
            ),
          ),
        if (status == 'failed')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                Text(
                  current?.message.isNotEmpty ?? false
                      ? current!.message
                      : '登录失败，请重试',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QrBlock extends StatelessWidget {
  const _QrBlock({required this.challenge, required this.status});

  final LoginChallenge challenge;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _decodeQrImage(challenge.qrImageBase64);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: image != null
              ? Image.memory(image, width: 226, height: 226)
              : (challenge.qrContent.isNotEmpty
                  ? QrImageView(
                      data: challenge.qrContent,
                      size: 226,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    )
                  : const SizedBox(
                      width: 226,
                      height: 226,
                      child: Center(child: Text('二维码不可用')),
                    )),
        ),
        const SizedBox(height: 14),
        Text(
          switch (status) {
            'waiting' => '请使用手机 App 扫描二维码',
            'scanned' => '已扫码，请在手机上确认',
            _ => '等待登录…',
          },
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (challenge.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              challenge.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static Uint8List? _decodeQrImage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final bytes = base64Decode(text);
      if (bytes.length < 8 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

class _AppBlock extends StatelessWidget {
  const _AppBlock({
    required this.challenge,
    required this.status,
    required this.onOpenUrl,
  });

  final LoginChallenge? challenge;
  final String status;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = challenge?.appUrl ?? '';
    return Column(
      children: [
        Icon(
          Icons.phone_android_rounded,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 10),
        Text(
          switch (status) {
            'waiting' => '请在手机 App 中确认登录',
            'scanned' => '已确认，正在完成登录…',
            _ => '等待手机确认…',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => onOpenUrl(url),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(
              (challenge?.appLabel.isNotEmpty ?? false)
                  ? challenge!.appLabel
                  : '打开手机 App',
            ),
          ),
        ],
        if (challenge?.message.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              challenge!.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
