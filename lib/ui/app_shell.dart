import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../../core/plugin/host/host_api.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/my_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/web_auth_page.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/brand_mark.dart';

/// Root shell: adaptive navigation, persistent mini player and the plugin
/// web-auth trampoline.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.navigatorKey,
  });

  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  List<Widget>? _pages;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.attachWebAuthRunner(_runWebAuth);
    });
  }

  Future<String> _runWebAuth(String originUrl, String script) async {
    if (!WebAuthPage.supported) {
      throw HostCallException('当前平台不支持内置网页登录');
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      throw HostCallException('内置浏览器不可用');
    }
    final result = await navigator.push<String>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/web-auth'),
        builder: (_) => WebAuthPage(originUrl: originUrl, script: script),
      ),
    );
    if (result == null) throw HostCallException('网页登录已取消');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _controller.lyricSettings]),
      builder: (context, _) {
        if (_controller.initializing) return const _SplashScreen();
        if (_controller.initError.isNotEmpty) {
          return _InitErrorScreen(message: _controller.initError);
        }
        _pages ??= [
          HomePage(controller: _controller),
          SearchPage(controller: _controller),
          LibraryPage(controller: _controller),
          MyPage(controller: _controller),
          SettingsPage(controller: _controller),
        ];
        final pages = _pages!;
        return ValueListenableBuilder<Song?>(
          valueListenable: _controller.playback.currentSongNotifier,
          builder: (context, song, _) => AppBackdrop(
            settings: _controller.appearance,
            coverUrl: song?.coverUrl ?? '',
            child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              if (wide) {
                final extended = constraints.maxWidth >= 1180;
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Row(
                  children: [
                    NavigationRail(
                      extended: extended,
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      labelType: extended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      minWidth: 76,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: _RailLogo(),
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: Text('首页'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.search_outlined),
                          selectedIcon: Icon(Icons.search_rounded),
                          label: Text('搜索'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music_rounded),
                          label: Text('本地'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: Text('我的'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings_rounded),
                          label: Text('设置'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _AnimatedTabStack(
                              index: _index,
                              children: pages,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        // Reserve a band for the lyric island so it never
                        // covers page titles on phones.
                        padding: EdgeInsets.only(
                          top: (Platform.isAndroid || Platform.isIOS) &&
                                  _controller.lyricSettings.showIsland
                              ? 34
                              : 0,
                        ),
                        child: _AnimatedTabStack(
                          index: _index,
                          children: pages,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search_rounded),
                    label: '搜索',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: '本地',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: '我的',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置',
                  ),
                ],
              ),
            );
            },
          ),
          ),
        );
      },
    );
  }
}

class _AnimatedTabStack extends StatefulWidget {
  const _AnimatedTabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

/// Root navigation motion copied from QPlayer's PageMotion: the outgoing page
/// fades/scales/slides away for 220 ms, then the incoming one settles in from
/// the opposite edge for another 220 ms. Pages stay alive in the tree so scroll
/// offsets and form state survive switches.
class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  static const Duration _segment = Duration(milliseconds: 220);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _segment * 2,
    value: 1,
  )..addStatusListener(_onStatus);

  late int _index = widget.index;
  int? _leaving;
  int _direction = 1;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _leaving != null) {
      setState(() => _leaving = null);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _index) {
      _leaving = _index;
      _direction = widget.index > _index ? 1 : -1;
      _index = widget.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++) _buildPage(i),
      ],
    );
  }

  Widget _buildPage(int index) {
    final active = index == _index;
    final leaving = index == _leaving;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active || _controller.isAnimating,
        child: TickerMode(
          enabled: active || leaving,
          child: Offstage(
            offstage: !active && !leaving,
            child: AnimatedBuilder(
              animation: _controller,
              child: widget.children[index],
              builder: (context, page) {
                final value = _controller.value;
                double opacity;
                double scale;
                double dx;
                if (active) {
                  final t = Curves.easeOutCubic
                      .transform(((value - 0.5) / 0.5).clamp(0.0, 1.0));
                  opacity = t;
                  scale = 0.94 + 0.06 * t;
                  dx = _direction * 44.0 * (1 - t);
                } else if (leaving) {
                  final t = Curves.easeInCubic
                      .transform((value / 0.5).clamp(0.0, 1.0));
                  opacity = 1 - t;
                  scale = 1 - 0.06 * t;
                  dx = -_direction * 44.0 * t;
                } else {
                  opacity = 0;
                  scale = 0.94;
                  dx = 0;
                }
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.scale(scale: scale, child: page!),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo();

  @override
  Widget build(BuildContext context) {
    return const BrandMark(size: 42);
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.28),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: const BrandMark(size: 92),
            ),
            const SizedBox(height: 20),
            Text(
              'zmusic',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '正在准备音源与播放引擎…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(100)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  const _InitErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 54,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 14),
                Text(
                  '启动失败',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'zmusic 无法初始化本地数据目录或插件运行时。请检查磁盘权限后重新启动应用。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
