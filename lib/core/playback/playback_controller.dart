import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lyric/lyric_models.dart';
import '../media/media_id.dart';
import '../media/media_kind.dart';
import '../media/models.dart';

enum RepeatMode {
  off('off'),
  one('one'),
  all('all');

  const RepeatMode(this.wireName);

  final String wireName;

  RepeatMode get next => switch (this) {
        RepeatMode.off => RepeatMode.all,
        RepeatMode.all => RepeatMode.one,
        RepeatMode.one => RepeatMode.off,
      };

  String get label => switch (this) {
        RepeatMode.off => '顺序播放',
        RepeatMode.all => '列表循环',
        RepeatMode.one => '单曲循环',
      };
}

typedef StreamResolver = Future<StreamDescriptor> Function(Song song);
typedef LyricsLoader = Future<Lyrics> Function(Song song);
typedef ScrobbleSink = Future<void> Function(
  Song song,
  int playedMs,
  int durationMs,
  bool completed,
);
typedef HistorySink = Future<void> Function(Song song, int positionMs);
typedef PlaybackErrorSink = void Function(String message);

/// Host-owned playback engine: queue, shuffle/repeat, sleep timer, lyric
/// loading, scrobbling and the state a plugin observes through
/// `playback.read`.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.resolveStream,
    required this.loadLyrics,
    this.onScrobble,
    this.onHistory,
    this.onError,
    this.onSongChanged,
  });

  final StreamResolver resolveStream;
  final LyricsLoader loadLyrics;
  final ScrobbleSink? onScrobble;
  final HistorySink? onHistory;
  final PlaybackErrorSink? onError;
  final void Function(Song? song)? onSongChanged;

  // libmpv otherwise keeps 32 MiB forward + 32 MiB back of demuxer cache, which
  // is most of the difference between a lean audio player and a memory hog.
  final Player player = Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<Song> _queue = [];
  List<int> _order = [];
  int _orderPos = -1;
  Song? _currentSong;

  /// Fires only when the track changes (not on every position tick), so the
  /// shell can refresh the cover backdrop without rebuilding at 5 Hz.
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);

  StreamDescriptor? _stream;
  Lyrics _lyrics = Lyrics.empty;
  String _contextName = '';
  String _error = '';
  bool _resolving = false;
  bool _started = false;
  bool _playing = false;
  bool _buffering = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 100;
  RepeatMode _repeatMode = RepeatMode.off;
  bool _shuffle = false;
  bool _lyricsVisible = true;

  int _seekRevision = 0;
  int _endRevision = 0;
  int _pendingSeekMs = 0;
  String _autoAdvanceBlocker = '';
  bool _pendingNaturalEnd = false;
  bool _scrobbled = false;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  int _lastNotifiedPosition = -1;
  int _lyricOffsetMs = 0;
  int _loadGeneration = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Read-only state

  Song? get currentSong => _currentSong;
  StreamDescriptor? get stream => _stream;
  Lyrics get lyrics => _lyrics;
  String get contextName => _contextName;
  String get error => _error;
  bool get resolving => _resolving;
  bool get playing => _playing;
  bool get buffering => _buffering;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get volume => _volume;
  RepeatMode get repeatMode => _repeatMode;
  bool get shuffle => _shuffle;
  bool get lyricsVisible => _lyricsVisible;
  int get lyricOffsetMs => _lyricOffsetMs;
  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _orderPos < 0 || _orderPos >= _order.length
      ? -1
      : _order[_orderPos];
  Duration get position => Duration(milliseconds: _positionMs);
  Duration get duration => Duration(milliseconds: _durationMs);
  bool get hasPrevious => _orderPos > 0 || _positionMs > 3000;
  bool get hasNext =>
      _orderPos + 1 < _order.length || _repeatMode == RepeatMode.all;
  DateTime? get sleepDeadline => _sleepDeadline;

  int get lyricIndex =>
      _lyrics.isEmpty ? -1 : _lyrics.indexAt(_positionMs + _lyricOffsetMs);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _volume = prefs.getDouble('playback.volume') ?? 100;
    _repeatMode = RepeatMode.values.firstWhere(
      (mode) => mode.wireName == prefs.getString('playback.repeat'),
      orElse: () => RepeatMode.off,
    );
    _shuffle = prefs.getBool('playback.shuffle') ?? false;

    await player.setVolume(_volume);
    _subscriptions.add(player.stream.playing.listen((value) {
      if (_disposed) return;
      _playing = value;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.buffering.listen((value) {
      if (_disposed) return;
      if (_buffering == value) return;
      _buffering = value;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.duration.listen((value) {
      if (_disposed) return;
      final ms = value.inMilliseconds;
      if (ms == _durationMs) return;
      _durationMs = ms;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.position.listen((value) {
      if (_disposed) return;
      final ms = value.inMilliseconds;
      _positionMs = ms;
      _maybeScrobble();
      if ((ms - _lastNotifiedPosition).abs() >= 200) {
        _lastNotifiedPosition = ms;
        notifyListeners();
      }
    }));
    _subscriptions.add(player.stream.completed.listen((value) {
      if (_disposed || !value) return;
      _onCompleted();
    }));
    _subscriptions.add(player.stream.error.listen((message) {
      if (_disposed) return;
      _error = message;
      onError?.call(message);
      notifyListeners();
    }));
  }

  // ---------------------------------------------------------------------------
  // Queue

  /// Replaces the queue and starts at [index] (index into [songs]).
  Future<void> playSongs(
    List<Song> songs, {
    int index = 0,
    String contextName = '',
    bool autoPlay = true,
    int seekMs = 0,
  }) async {
    if (songs.isEmpty) return;
    _queue = List<Song>.from(songs);
    _contextName = contextName;
    final anchor = index.clamp(0, songs.length - 1);
    _rebuildOrder(anchor: anchor);
    // `_rebuildOrder` keeps the natural order when shuffle is off, so the
    // anchor is not necessarily at position 0 — find it instead of always
    // starting from the first song.
    final position = _order.indexOf(anchor);
    _orderPos = _order.isEmpty ? -1 : (position < 0 ? 0 : position);
    if (_orderPos < 0) return;
    await _openCurrent(seekMs: seekMs, autoPlay: autoPlay);
  }

  Future<void> playSong(Song song, {String contextName = ''}) {
    return playSongs([song], contextName: contextName);
  }

  void enqueueNext(Song song) {
    if (_queue.isEmpty) {
      playSong(song);
      return;
    }
    final insertAt = currentIndex < 0 ? _queue.length : currentIndex + 1;
    _queue.insert(insertAt, song);
    _order.insert(
      (_orderPos + 1).clamp(0, _order.length),
      insertAt,
    );
    notifyListeners();
  }

  void addToQueue(Song song) {
    if (_queue.isEmpty) {
      playSong(song);
      return;
    }
    final index = _queue.length;
    _queue.add(song);
    _order.add(index);
    notifyListeners();
  }

  Future<void> removeFromQueue(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    final removingCurrent = queueIndex == currentIndex;
    _queue.removeAt(queueIndex);
    _order = [
      for (final value in _order)
        if (value != queueIndex) value > queueIndex ? value - 1 : value,
    ];
    if (_order.isEmpty) {
      await stop();
      return;
    }
    if (removingCurrent) {
      _orderPos = _orderPos.clamp(0, _order.length - 1);
      await _openCurrent();
      return;
    }
    _orderPos = _order.indexOf(currentIndex);
    if (_orderPos < 0) _orderPos = 0;
    notifyListeners();
  }

  void _rebuildOrder({int anchor = 0}) {
    final indices = List<int>.generate(_queue.length, (i) => i);
    if (_shuffle) {
      indices.shuffle(Random());
      if (anchor >= 0 && anchor < indices.length) {
        indices.remove(anchor);
        indices.insert(0, anchor);
      }
    }
    _order = indices;
  }

  Future<void> setShuffle(bool value) async {
    if (_shuffle == value) return;
    _shuffle = value;
    final current = currentIndex;
    _rebuildOrder(anchor: current);
    _orderPos = current < 0 ? -1 : _order.indexOf(current);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('playback.shuffle', value);
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    _repeatMode = _repeatMode.next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playback.repeat', _repeatMode.wireName);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Transport

  Future<void> play() async {
    if (_currentSong == null) {
      if (_queue.isEmpty) return;
      _orderPos = 0;
      await _openCurrent();
      return;
    }
    if (!_started) {
      await _openCurrent(seekMs: _positionMs);
      return;
    }
    await player.play();
  }

  Future<void> pause() => player.pause();

  Future<void> togglePlayPause() async {
    if (_playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(int positionMs) async {
    final target = positionMs.clamp(0, max(0, _durationMs)).toInt();
    _positionMs = target;
    _seekRevision++;
    await player.seek(Duration(milliseconds: target));
    notifyListeners();
  }

  Future<void> seekFraction(double fraction) =>
      seek((_durationMs * fraction.clamp(0.0, 1.0)).round());

  Future<void> next() => _advance(auto: false);

  Future<void> previous() async {
    if (_positionMs > 3000 || _orderPos <= 0) {
      await seek(0);
      return;
    }
    _orderPos--;
    await _openCurrent();
  }

  Future<void> stop() async {
    _loadGeneration++;
    await player.stop();
    _currentSong = null;
    currentSongNotifier.value = null;
    _stream = null;
    _lyrics = Lyrics.empty;
    _positionMs = 0;
    _durationMs = 0;
    _started = false;
    _playing = false;
    onSongChanged?.call(null);
    notifyListeners();
  }

  Future<void> selectQueueIndex(int queueIndex) async {
    final orderPos = _order.indexOf(queueIndex);
    if (orderPos < 0) return;
    if (orderPos == _orderPos && _started) {
      await seek(0);
      return;
    }
    _orderPos = orderPos;
    await _openCurrent();
  }

  /// Plugin-initiated selection by native or canonical id inside the current
  /// queue, mirroring QPlayer's `pluginSongId` + `selectPluginTrack`.
  Future<bool> selectFromPlugin(
    String pluginId,
    String songId,
    int positionMs,
    bool shouldPlay,
  ) async {
    final queueIndex =
        _queue.indexWhere((song) => _matchesPluginSongId(pluginId, song, songId));
    if (queueIndex < 0) return false;
    if (queueIndex == currentIndex && _started) {
      await seek(positionMs);
      if (shouldPlay) {
        await player.play();
      } else {
        await player.pause();
      }
      return true;
    }
    _orderPos = _order.indexOf(queueIndex);
    await _openCurrent(seekMs: positionMs, autoPlay: shouldPlay);
    return true;
  }

  void setAutoAdvanceBlocked(String pluginId, bool blocked) {
    if (blocked) {
      _autoAdvanceBlocker = pluginId;
      return;
    }
    if (_autoAdvanceBlocker != pluginId) return;
    _autoAdvanceBlocker = '';
    if (_pendingNaturalEnd) {
      _pendingNaturalEnd = false;
      unawaited(_advance(auto: true));
    }
  }

  /// Replaces the whole queue on behalf of a plugin (`queue.replace`).
  ///
  /// The queue and its order are rebuilt, then the target song is opened at
  /// [positionMs]. Returns false when the requested song is not in [songs].
  Future<bool> replaceQueueFromPlugin(
    String pluginId,
    List<Song> songs,
    String songId,
    int positionMs,
    bool shouldPlay,
  ) async {
    if (songs.isEmpty) return false;
    final target = songs.indexWhere(
      (song) => _matchesPluginSongId(pluginId, song, songId),
    );
    if (target < 0) return false;
    _loadGeneration++;
    _queue = List<Song>.from(songs);
    _contextName = '插件队列';
    _rebuildOrder(anchor: target);
    _orderPos = _order.indexOf(target);
    if (_orderPos < 0) _orderPos = 0;
    await _openCurrent(seekMs: positionMs, autoPlay: shouldPlay);
    return true;
  }

  /// Plugin song ids may be native ids or canonical `provider:kind:native`
  /// ids; a canonical id from another provider is rejected.
  static bool _matchesPluginSongId(String pluginId, Song song, String raw) {
    if (song.provider != pluginId) return false;
    if (raw.contains(':')) {
      try {
        final id = MediaId.parse(raw);
        return id.provider == pluginId &&
            id.kind == MediaKind.song &&
            id.nativeId == song.nativeId;
      } catch (_) {
        return false;
      }
    }
    return song.nativeId == raw;
  }

  Future<void> _advance({required bool auto}) async {
    if (_order.isEmpty) return;
    if (auto && _repeatMode == RepeatMode.one) {
      await seek(0);
      await player.play();
      return;
    }
    if (_orderPos + 1 < _order.length) {
      _orderPos++;
      await _openCurrent();
      return;
    }
    if (_repeatMode == RepeatMode.all) {
      _orderPos = 0;
      await _openCurrent();
      return;
    }
    await player.pause();
    _playing = false;
    notifyListeners();
  }

  void _onCompleted() {
    _endRevision++;
    if (_autoAdvanceBlocker.isNotEmpty) {
      _pendingNaturalEnd = true;
      return;
    }
    _finishScrobble(completed: true);
    unawaited(_advance(auto: true));
  }

  Future<void> _openCurrent({int seekMs = 0, bool? autoPlay}) async {
    if (_orderPos < 0 || _orderPos >= _order.length) return;
    final generation = ++_loadGeneration;
    final song = _queue[_order[_orderPos]];
    _currentSong = song;
    currentSongNotifier.value = song;
    _stream = null;
    _lyrics = Lyrics.empty;
    _error = '';
    _scrobbled = false;
    _positionMs = seekMs;
    _durationMs = song.durationMs;
    _resolving = true;
    _started = false;
    _pendingSeekMs = seekMs;
    onSongChanged?.call(song);
    notifyListeners();

    unawaited(_loadLyricsFor(song, generation));

    try {
      final descriptor = song.isLocal && song.localPath.isNotEmpty
          ? StreamDescriptor(
              url: Uri.file(song.localPath).toString(),
              mimeType: '',
            )
          : await resolveStream(song);
      if (_disposed || generation != _loadGeneration) return;
      _stream = descriptor;
      _resolving = false;
      notifyListeners();
      final media = Media(
        descriptor.url,
        httpHeaders:
            descriptor.headers.isEmpty ? null : descriptor.headers,
      );
      await player.open(media, play: autoPlay ?? true);
      if (_disposed || generation != _loadGeneration) return;
      _started = true;
      if (_pendingSeekMs > 0) {
        await player.seek(Duration(milliseconds: _pendingSeekMs));
      }
      _playing = autoPlay ?? true;
      _error = '';
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      _resolving = false;
      _started = false;
      _playing = false;
      _error = e.toString();
      onError?.call(_error);
      notifyListeners();
    }
  }

  Future<void> _loadLyricsFor(Song song, int generation) async {
    try {
      final lyrics = await loadLyrics(song);
      if (_disposed || generation != _loadGeneration) return;
      _lyrics = lyrics;
      notifyListeners();
    } catch (_) {
      // Lyrics are optional; playback continues without them.
    }
  }

  // ---------------------------------------------------------------------------
  // Volume, lyric offset, sleep timer

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 100);
    await player.setVolume(_volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback.volume', _volume);
    notifyListeners();
  }

  void toggleLyrics() {
    _lyricsVisible = !_lyricsVisible;
    notifyListeners();
  }

  void setLyricOffset(int offsetMs) {
    _lyricOffsetMs = offsetMs.clamp(-30000, 30000);
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (duration == null) {
      _sleepDeadline = null;
      notifyListeners();
      return;
    }
    _sleepDeadline = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      _sleepTimer = null;
      _sleepDeadline = null;
      await pause();
      notifyListeners();
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Scrobbling & history

  void _maybeScrobble() {
    if (_scrobbled) return;
    final song = _currentSong;
    if (song == null) return;
    final total = _durationMs > 0 ? _durationMs : song.durationMs;
    if (total <= 0) return;
    if (_positionMs >= max(30000, (total * 0.5).round())) {
      _finishScrobble(completed: false);
    }
  }

  void _finishScrobble({required bool completed}) {
    if (_scrobbled) return;
    final song = _currentSong;
    if (song == null) return;
    _scrobbled = true;
    final sink = onScrobble;
    if (sink != null) {
      unawaited(sink(song, _positionMs, _durationMs, completed).catchError(
        (Object _) {},
      ));
    }
    final history = onHistory;
    if (history != null && !song.isLocal) {
      unawaited(history(song, _positionMs).catchError((Object _) {}));
    }
  }

  // ---------------------------------------------------------------------------
  // Plugin ABI snapshot

  Map<String, dynamic> snapshotForPlugin(String pluginId) {
    final song = _currentSong;
    final currentId =
        song != null && song.provider == pluginId ? song.nativeId : '';
    final queueOwned = _queue.every((item) => item.provider == pluginId);
    return {
      'currentSongId': currentId,
      'queueSongIds': queueOwned
          ? _queue.map((item) => item.nativeId).toList()
          : const <String>[],
      'positionMs': max(0, _positionMs),
      'durationMs': max(0, _durationMs),
      'playing': _playing,
      'transitioning': _resolving,
      'seekRevision': _seekRevision,
      'endRevision': _endRevision,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    currentSongNotifier.dispose();
    player.dispose();
    super.dispose();
  }
}
