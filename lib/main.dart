import 'dart:ffi' show nullptr;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'core/app/app_controller.dart';
import 'core/app/lyric_bridge.dart';
import 'core/app/system_integration.dart';
import 'ui/app_shell.dart';
import 'ui/player_route.dart';
import 'ui/theme.dart';
import 'ui/widgets/app_toast.dart';
import 'ui/widgets/lyric_island.dart';
import 'ui/widgets/mini_player.dart';
import 'ui/widgets/smooth_scroll.dart';
import 'ui/windows/desktop_lyric_window.dart';

SystemIntegration? _systemIntegration;

/// Top-most route name and stack depth, used to keep the mini player above the
/// navigator (and to hide it inside the full player / login flows).
class _RouteInfo {
  const _RouteInfo({this.name = '', this.depth = 0});

  final String name;
  final int depth;
}

final ValueNotifier<_RouteInfo> _routeInfo =
    ValueNotifier(const _RouteInfo());
final _RouteObserver _routeObserver = _RouteObserver();

class _RouteObserver extends NavigatorObserver {
  final List<String?> _stack = [];

  void _publish() {
    final info = _RouteInfo(
      name: _stack.isEmpty ? '' : (_stack.last ?? ''),
      depth: _stack.length,
    );
    // Navigator observers fire during the initial build; notifying the
    // builder that wraps the Navigator in that phase would throw.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeInfo.value = info;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route.settings.name);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_stack.isNotEmpty) {
      _stack[_stack.length - 1] = newRoute?.settings.name;
    }
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _publish();
  }
}

/// True when this engine belongs to a desktop_multi_window sub-window. The
/// native window exists before the engine starts, so its class is a reliable
/// marker even if entrypoint arguments are not delivered.
bool _secondaryEngine() {
  final className = 'FlutterMultiWindow'.toNativeUtf16();
  final hwnd = FindWindow(className, nullptr);
  free(className);
  return hwnd != 0;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Artwork is decoded at its drawn size now; keep the cache bounded so a long
  // session does not pin hundreds of full-resolution cover bitmaps in memory.
  PaintingBinding.instance.imageCache
    ..maximumSize = 240
    ..maximumSizeBytes = 32 << 20;

  // Secondary engines spawned by desktop_multi_window run this same entry
  // point. The engine arguments normally say so; the window-class fallback
  // keeps the sub-window from ever entering the single-instance path, which
  // would call exit(0) and take the whole process (main window included) down.
  // Both paths are Windows-only; Android runs a single engine.
  if (Platform.isWindows &&
      ((args.isNotEmpty && args.first == 'multi_window') ||
          _secondaryEngine())) {
    await runDesktopLyricWindow(args.length > 2 ? args[2] : '{}');
    return;
  }

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'zmusic',
      onSecondWindow: (_) async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(960, 640),
      center: true,
      title: 'zmusic',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MediaKit.ensureInitialized();

  final controller = AppController();
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  controller.attachToastSink((message) {
    AppToast.show(message);
  });

  runApp(
    _ZMusicApp(
      controller: controller,
      navigatorKey: navigatorKey,
      messengerKey: messengerKey,
    ),
  );

  await controller.initialize();
  if (controller.initError.isEmpty) {
    LyricBridge.instance.attach(controller);
    _systemIntegration = SystemIntegration(controller: controller);
    await _systemIntegration!.init();
  }
}

class _ZMusicApp extends StatelessWidget {
  const _ZMusicApp({
    required this.controller,
    required this.navigatorKey,
    required this.messengerKey,
  });

  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, controller.appearance]),
        builder: (context, _) {
          return MaterialApp(
            title: 'zmusic',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            navigatorObservers: [_routeObserver],
            scaffoldMessengerKey: messengerKey,
            builder: (context, child) {
              final media = MediaQuery.maybeOf(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) => ValueListenableBuilder<_RouteInfo>(
                  valueListenable: _routeInfo,
                  child: child ?? const SizedBox.shrink(),
                  builder: (context, route, page) {
                  final width = media?.size.width ?? 1280;
                  final wide = width >= 880;
                  final pushed = route.depth > 1;
                  final railWidth = !wide || pushed
                      ? 0.0
                      : (width >= 1180 ? 256.0 : 76.0);
                  final hidden = route.name == '/player' ||
                      route.name == '/web-auth' ||
                      route.name == '/login';
                  final bottom = wide || pushed
                      ? 0.0
                      : 68.0 + (media?.padding.bottom ?? 0);
                  return AppToastHost(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        page ?? const SizedBox.shrink(),
                        if (!hidden)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            left: railWidth,
                            right: 0,
                            bottom: bottom,
                            child: MiniPlayer(
                              controller: controller,
                              onOpen: () =>
                                  openPlayer(navigatorKey, controller),
                            ),
                          ),
                        if (!hidden)
                          Positioned(
                            top: (media?.padding.top ?? 0) + 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: AnimatedBuilder(
                                animation: controller.lyricSettings,
                                builder: (context, _) {
                                  final mobile =
                                      Platform.isAndroid || Platform.isIOS;
                                  if (!mobile ||
                                      !controller.initialized ||
                                      !controller.lyricSettings
                                          .showIslandCapsule) {
                                    return const SizedBox.shrink();
                                  }
                                  return LyricIsland(
                                    playback: controller.playback,
                                    showLyrics: controller
                                        .lyricSettings.islandLyrics,
                                    onTap: () =>
                                        openPlayer(navigatorKey, controller),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  },
                ),
              );
            },
            theme: AppTheme.light(controller.appearance.seedColor),
            darkTheme: AppTheme.dark(controller.appearance.seedColor),
            themeMode: switch (controller.themeMode) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            themeAnimationDuration: const Duration(milliseconds: 240),
            scrollBehavior: const AppScrollBehavior(),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: AppShell(
              controller: controller,
              navigatorKey: navigatorKey,
            ),
          );
        },
      ),
    );
  }
}
