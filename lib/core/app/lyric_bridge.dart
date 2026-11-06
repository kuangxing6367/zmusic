import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../lyric/lyric_models.dart';
import '../lyric/lyric_settings.dart';
import '../media/models.dart';
import '../playback/playback_controller.dart';
import 'app_controller.dart';

/// Bridges the playback state to the Android system lyric provider.
///
/// The provider (Lyricon / 词幕) is the same overlay host the official Android
/// player publishes to: it draws syllable-timed lyrics in the status bar and
/// in the system island, so the island looks native instead of like a plain
/// notification. When the provider is absent an optional notification fallback
/// can be used on Android 16+.
class LyricBridge {
  LyricBridge._();

  static final LyricBridge instance = LyricBridge._();
  static const MethodChannel _channel = MethodChannel('zmusic/lyric');

  PlaybackController? _playback;
  LyricSettings? _settings;
  Lyrics? _lastLyrics;
  String _lastSong = '';
  String _lastSettings = '';
  int _lastIndex = -2;
  bool _available = false;
  bool _started = false;
  bool _hidden = true;
  int _lastPositionSent = 0;
  int _lastPositionAt = 0;

  void attach(AppController controller) {
    if (!Platform.isAndroid) return;
    if (_playback != null) return;
    _playback = controller.playback;
    _settings = controller.lyricSettings;
    _playback!.addListener(_sync);
    _settings!.addListener(_sync);
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      _available = await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      _available = false;
    }
    // Recompute the fallback flag now that we know whether a system provider
    // accepted the registration.
    _hidden = true;
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
    final index = _activeIndex(playback, groups);
    final settingsKey = [
      settings.showTranslation,
      settings.showRomanization,
      settings.islandFallbackNotification,
    ].join('|');
    final songKey = '${song.id}|${song.title}|${song.artistLabel}';
    final changed = !identical(playback.lyrics, _lastLyrics) ||
        songKey != _lastSong ||
        settingsKey != _lastSettings ||
        index != _lastIndex;

    if (changed || _hidden) {
      _hidden = false;
      _lastLyrics = playback.lyrics;
      _lastSong = songKey;
      _lastSettings = settingsKey;
      _lastIndex = index;
      _push(playback, settings, song, groups, index);
    } else {
      _position(playback);
    }
  }

  int _activeIndex(PlaybackController playback, List<LyricGroup> groups) {
    if (groups.isEmpty) return -1;
    final index = playback.lyricIndex;
    if (index >= 0 && index < groups.length) return index;
    final position = playback.positionMs + playback.lyricOffsetMs;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].startMs >= position) return i;
    }
    return groups.length - 1;
  }

  void _push(
    PlaybackController playback,
    LyricSettings settings,
    Song song,
    List<LyricGroup> groups,
    int index,
  ) {
    final activeText = index >= 0 && index < groups.length
        ? groups[index].line.text.trim()
        : '';
    final payload = <String, Object?>{
      'songId': song.id,
      'title': song.title,
      'artist': song.artistLabel,
      'durationMs': playback.durationMs > 0
          ? playback.durationMs
          : song.durationMs,
      'positionMs': playback.positionMs + playback.lyricOffsetMs,
      'playing': playback.playing,
      'showTranslation': settings.showTranslation,
      'showRomanization': settings.showRomanization,
      'fallback': settings.islandFallbackNotification && !_available,
      'activeText': activeText,
      'lines': [
        for (final group in groups)
          if (group.line.text.trim().isNotEmpty) _linePayload(group.line),
      ],
    };
    _lastPositionSent = playback.positionMs;
    _lastPositionAt = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      _channel.invokeMethod<bool>('push', payload).catchError((Object _) => false),
    );
  }

  Map<String, Object?> _linePayload(LyricLine line) {
    return {
      'begin': line.startMs,
      'end': line.endMs <= line.startMs ? line.startMs + 500 : line.endMs,
      'text': line.text.trim(),
      'translation': line.translation.trim(),
      'roma': line.romanization.trim(),
      'right': line.isDuetRight,
      'words': [
        for (final syllable in line.syllables)
          if (syllable.text.isNotEmpty)
            {
              'begin': syllable.startMs,
              'end': syllable.endMs,
              'text': syllable.text,
            },
      ],
    };
  }

  void _position(PlaybackController playback) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionAt < 450 &&
        (playback.positionMs - _lastPositionSent).abs() < 450) {
      return;
    }
    _lastPositionAt = now;
    _lastPositionSent = playback.positionMs;
    unawaited(
      _channel
          .invokeMethod<void>('position', {
            'positionMs': playback.positionMs + playback.lyricOffsetMs,
            'playing': playback.playing,
          })
          .catchError((Object _) {}),
    );
  }

  void _hide() {
    if (_hidden) return;
    _hidden = true;
    _lastLyrics = null;
    _lastSong = '';
    _lastIndex = -2;
    unawaited(_channel.invokeMethod<void>('hide').catchError((Object _) {}));
  }
}
