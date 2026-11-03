import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../media/models.dart';
import 'playback_controller.dart';

/// Windows System Media Transport Controls bridge.
///
/// This is what makes the keyboard media keys, the lock-screen style flyout and
/// the taskbar preview controls drive zmusic instead of the last app that used
/// SMTC. Failures are non-fatal: the player keeps working without it.
class MediaSession {
  MediaSession._(this._playback, this._smtc);

  final PlaybackController _playback;
  final SMTCWindows _smtc;

  StreamSubscription<PressedButton>? _buttonSub;
  bool _disposed = false;
  String _songId = '';
  bool? _wasPlaying;
  int _lastTimelineMs = -1 << 30;

  static Future<MediaSession?> create(PlaybackController playback) async {
    if (!Platform.isWindows) return null;
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          stopEnabled: false,
          nextEnabled: true,
          prevEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
        status: PlaybackStatus.paused,
        metadata: const MusicMetadata(title: 'zmusic', artist: ''),
        timeline: const PlaybackTimeline(
          positionMs: 0,
          startTimeMs: 0,
          endTimeMs: 0,
        ),
      );
      final session = MediaSession._(playback, smtc);
      session._buttonSub = smtc.buttonPressStream.listen(
        session._onButton,
        onError: (Object _) {},
      );
      playback.addListener(session._sync);
      await session._sync();
      return session;
    } catch (error) {
      debugPrint('[media-session] unavailable: $error');
      return null;
    }
  }

  void _onButton(PressedButton button) {
    switch (button) {
      case PressedButton.play:
        if (!_playback.playing) unawaited(_playback.play());
        break;
      case PressedButton.pause:
        if (_playback.playing) unawaited(_playback.pause());
        break;
      case PressedButton.next:
        unawaited(_playback.next());
        break;
      case PressedButton.previous:
        unawaited(_playback.previous());
        break;
      default:
        break;
    }
  }

  Future<void> _sync() async {
    if (_disposed) return;
    try {
      final song = _playback.currentSong;
      if (song == null) {
        await _smtc.clearMetadata();
        await _smtc.setPlaybackStatus(PlaybackStatus.stopped);
        _songId = '';
        return;
      }

      if (song.id != _songId) {
        _songId = song.id;
        await _smtc.updateMetadata(MusicMetadata(
          title: song.title,
          artist: song.artistLabel,
          album: song.album?.name,
          thumbnail: _thumbnail(song),
        ));
      }

      final playing = _playback.playing;
      if (_wasPlaying != playing) {
        _wasPlaying = playing;
        await _smtc.setPlaybackStatus(
          playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      }

      final duration = _playback.durationMs > 0
          ? _playback.durationMs
          : song.durationMs;
      final position = _playback.positionMs;
      if ((position - _lastTimelineMs).abs() >= 900 ||
          _lastTimelineMs < 0) {
        _lastTimelineMs = position;
        await _smtc.updateTimeline(PlaybackTimeline(
          positionMs: position,
          startTimeMs: 0,
          endTimeMs: duration,
        ));
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[media-session] sync failed: $error');
    }
  }

  String? _thumbnail(Song song) {
    final artwork = song.artworkUrl.trim();
    if (artwork.startsWith('http://') || artwork.startsWith('https://')) {
      return artwork;
    }
    if (artwork.isNotEmpty && File(artwork).existsSync()) {
      return Uri.file(artwork).toString();
    }
    return null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _playback.removeListener(_sync);
    await _buttonSub?.cancel();
    try {
      await _smtc.dispose();
    } catch (_) {
      // The Rust bridge can already be torn down during shutdown.
    }
  }
}
