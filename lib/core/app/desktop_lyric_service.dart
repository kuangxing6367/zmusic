import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../lyric/lyric_settings.dart';
import '../playback/playback_controller.dart';

/// Owns the always-on-top desktop lyric window and pushes the active lyric line
/// to it. The window itself runs in a separate Flutter engine (see
/// `ui/windows/desktop_lyric_window.dart`).
class DesktopLyricService extends ChangeNotifier {
  DesktopLyricService(this._playback, this._settings) {
    instance = this;
  }

  /// The active service, used by the player page and tray menu.
  static DesktopLyricService? instance;

  final PlaybackController _playback;
  final LyricSettings _settings;

  WindowController? _controller;
  int _lastIndex = -2;
  String _lastSongId = '';
  bool _starting = false;

  bool get visible => _controller != null;
  bool get busy => _starting;

  Future<void> toggle() async {
    if (!Platform.isWindows) return;
    if (visible) {
      await close();
      return;
    }
    // A previous engine can outlive a failed handshake; clear orphans so the
    // next toggle always creates exactly one lyric window.
    final ids = await DesktopMultiWindow.getAllSubWindowIds();
    for (final id in ids) {
      try {
        await WindowController.fromWindowId(id).close();
      } catch (_) {}
    }
    await open();
  }

  Future<void> open() async {
    if (!Platform.isWindows) return;
    if (_controller != null || _starting) return;
    _starting = true;
    notifyListeners();
    try {
      final controller = await DesktopMultiWindow.createWindow(
        jsonEncode(const {'type': 'lyrics'}),
      );
      _controller = controller;
      await controller.setTitle('zmusic 桌面歌词');
      // Size/position through the plugin's own MoveWindow call. Doing this
      // with SetWindowPos from inside the secondary engine crashed the
      // process, while the plugin's main-engine path is stable.
      try {
        final display = await screenRetriever.getPrimaryDisplay();
        const width = 920.0;
        const height = 168.0;
        final left = (display.size.width - width) / 2;
        final top = display.size.height - height - 80;
        await controller.setFrame(
          Rect.fromLTWH(left, top, width, height),
        );
      } catch (error) {
        debugPrint('[desktop-lyric] frame failed: $error');
      }
      await controller.show();
      _playback.addListener(_push);
      _settings.addListener(_onSettings);
      _lastIndex = -2;
      _lastSongId = '';
      await _push();
      // The secondary engine may still be registering its method handler when
      // the first push lands; repeat once after it has settled.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!identical(_controller, controller)) return;
        _lastIndex = -2;
        _lastSongId = '';
        await _push();
      }));
    } catch (error) {
      debugPrint('[desktop-lyric] open failed: $error');
      _controller = null;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _playback.removeListener(_push);
    _settings.removeListener(_onSettings);
    notifyListeners();
    try {
      await controller.close();
    } catch (_) {
      // The window may already be gone.
    }
  }

  void _onSettings() {
    unawaited(_push(force: true));
  }

  Future<void> _push({bool force = false}) async {
    final controller = _controller;
    if (controller == null) return;
    final song = _playback.currentSong;
    final index = _playback.lyricIndex;
    final songId = song?.id ?? '';
    if (!force && index == _lastIndex && songId == _lastSongId) return;
    _lastIndex = index;
    _lastSongId = songId;

    final groups = _playback.lyrics.groups;
    var line = '';
    var translation = '';
    var next = '';
    if (index >= 0 && index < groups.length) {
      final current = groups[index].line;
      line = current.text;
      translation = current.translation;
      if (index + 1 < groups.length) next = groups[index + 1].line.text;
    } else if (groups.isNotEmpty) {
      next = groups.first.line.text;
    }

    try {
      await DesktopMultiWindow.invokeMethod(controller.windowId, 'lyric', {
        'line': line,
        'translation': translation,
        'next': next,
        'title': song?.title ?? '',
        'artist': song?.artistLabel ?? '',
        'playing': _playback.playing,
        'fontSize': _settings.desktopFontSize,
        'fontFamily': _settings.fontFamily,
        'backgroundOpacity': _settings.desktopBackgroundOpacity,
      });
    } catch (_) {
      // The engine disappeared; drop the stale handle so the tray menu can
      // open a fresh window next time.
      if (identical(_controller, controller)) {
        _controller = null;
        _playback.removeListener(_push);
        _settings.removeListener(_onSettings);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    if (identical(instance, this)) instance = null;
    super.dispose();
  }
}
