import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../playback/media_session.dart';
import 'app_controller.dart';
import 'desktop_lyric_service.dart';

/// Windows shell integration: tray icon, close-to-tray, SMTC media keys and
/// the desktop lyric window.
class SystemIntegration with WindowListener, TrayListener {
  SystemIntegration({required this.controller})
      : desktopLyrics = DesktopLyricService(
          controller.playback,
          controller.lyricSettings,
        );

  final AppController controller;
  final DesktopLyricService desktopLyrics;

  MediaSession? _mediaSession;
  bool _quitting = false;
  bool _trayReady = false;
  String _menuSignature = '';

  Future<void> init() async {
    if (!Platform.isWindows) return;
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    _trayReady = true;
    trayManager.addListener(this);

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('zmusic');
    } catch (error) {
      debugPrint('[tray] init failed: $error');
    }

    controller.playback.addListener(_scheduleTraySync);
    desktopLyrics.addListener(_scheduleTraySync);
    await _syncTray();

    _mediaSession = await MediaSession.create(controller.playback);
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await desktopLyrics.close();
      await _mediaSession?.dispose();
      await controller.playback.pause();
      await trayManager.destroy();
    } catch (_) {
      // Shutdown best-effort.
    }
    await windowManager.destroy();
  }

  void _scheduleTraySync() {
    unawaited(_syncTray());
  }

  Future<void> _syncTray() async {
    if (!_trayReady) return;
    final playback = controller.playback;
    final song = playback.currentSong;
    final signature = [
      song?.id ?? '',
      song?.title ?? '',
      song?.artistLabel ?? '',
      playback.playing,
      playback.hasNext,
      playback.hasPrevious,
      desktopLyrics.visible,
    ].join('|');
    if (signature == _menuSignature) return;
    _menuSignature = signature;

    final title = song == null
        ? 'zmusic'
        : 'zmusic · ${song.title}${song.artistLabel.isEmpty ? '' : ' — ${song.artistLabel}'}';
    try {
      await trayManager.setToolTip(title.length > 120 ? 'zmusic' : title);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(
          key: 'play_pause',
          label: playback.playing ? '暂停' : '播放',
          disabled: song == null,
        ),
        MenuItem(
          key: 'previous',
          label: '上一首',
          disabled: !playback.hasPrevious,
        ),
        MenuItem(
          key: 'next',
          label: '下一首',
          disabled: !playback.hasNext,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'desktop_lyric',
          label: desktopLyrics.visible ? '关闭桌面歌词' : '开启桌面歌词',
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出 zmusic'),
      ]));
    } catch (error) {
      if (kDebugMode) debugPrint('[tray] sync failed: $error');
    }
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    unawaited(hideWindow());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(() async {
      if (await windowManager.isVisible()) {
        await hideWindow();
      } else {
        await showWindow();
      }
    }());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
        break;
      case 'play_pause':
        unawaited(controller.playback.togglePlayPause());
        break;
      case 'previous':
        unawaited(controller.playback.previous());
        break;
      case 'next':
        unawaited(controller.playback.next());
        break;
      case 'desktop_lyric':
        unawaited(desktopLyrics.toggle());
        break;
      case 'quit':
        unawaited(quit());
        break;
    }
  }
}
