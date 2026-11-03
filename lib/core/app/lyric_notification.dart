import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../lyric/lyric_models.dart';
import '../lyric/lyric_settings.dart';
import '../playback/playback_controller.dart';
import 'app_controller.dart';

/// Mirrors the lyric line into an ongoing Android notification.
///
/// On Android 16+ the notification asks to be promoted as a Live Update, which
/// is what the system shows in the status-bar chip ("灵动岛" / 流体云).
/// Xiaomi's 超级岛 additionally requires a whitelist from Xiaomi's developer
/// portal; the notification is still posted so those builds can promote it.
class LyricNotification {
  LyricNotification._();

  static final LyricNotification instance = LyricNotification._();
  static const MethodChannel _channel = MethodChannel('zmusic/lyric');

  PlaybackController? _playback;
  LyricSettings? _settings;
  String _lastKey = '';

  void attach(AppController controller) {
    if (!Platform.isAndroid) return;
    if (_playback != null) return;
    _playback = controller.playback;
    _settings = controller.lyricSettings;
    _playback!.addListener(_sync);
    _settings!.addListener(_sync);
    _sync();
  }

  void _sync() {
    final playback = _playback;
    final settings = _settings;
    if (playback == null || settings == null) return;
    final song = playback.currentSong;
    if (song == null || !settings.showIsland) {
      _hide();
      return;
    }
    final groups = playback.lyrics.groups;
    if (groups.isEmpty) {
      _hide();
      return;
    }
    final index = playback.lyricIndex;
    final LyricGroup group;
    if (index >= 0 && index < groups.length) {
      group = groups[index];
    } else {
      group = groups.firstWhere(
        (g) => g.startMs >= playback.positionMs,
        orElse: () => groups.last,
      );
    }
    final text = group.line.text.trim();
    if (text.isEmpty) {
      _hide();
      return;
    }
    final title = [song.title, song.artistLabel]
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final key = '$title|$text';
    if (key == _lastKey) return;
    _lastKey = key;
    unawaited(
      _channel
          .invokeMethod<void>('show', {'title': title, 'text': text})
          .catchError((Object _) {}),
    );
  }

  void _hide() {
    if (_lastKey.isEmpty) return;
    _lastKey = '';
    unawaited(
      _channel.invokeMethod<void>('hide').catchError((Object _) {}),
    );
  }
}
