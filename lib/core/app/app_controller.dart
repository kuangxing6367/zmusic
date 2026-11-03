import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/local_library.dart';
import '../lyric/lyric_models.dart';
import '../lyric/lyric_parser.dart';
import '../lyric/lyric_settings.dart';
import '../media/media_id.dart';
import '../media/media_kind.dart';
import '../media/models.dart';
import '../playback/playback_controller.dart';
import '../plugin/host/host_api.dart';
import '../plugin/installed_plugin.dart';
import '../plugin/plugin_manager.dart';
import '../plugin/plugin_provider_service.dart';
import '../plugin/plugin_registry.dart';
import '../plugin/provider_capability.dart';
import 'appearance_settings.dart';

/// Runs a plugin-supplied login script in a host-controlled web view.
typedef WebAuthRunner = Future<String> Function(String originUrl, String script);

/// One provider's home payload, or the error that prevented loading it.
class HomeProviderFeed {
  const HomeProviderFeed({
    required this.providerId,
    required this.providerName,
    this.home = const ProviderHome(),
    this.account,
    this.error = '',
  });

  final String providerId;
  final String providerName;
  final ProviderHome home;
  final AccountProfile? account;
  final String error;

  bool get isEmpty =>
      error.isEmpty &&
      home.songs.isEmpty &&
      home.playlists.isEmpty &&
      home.sections.isEmpty;
}

/// Combined search results for one provider.
class ProviderSearchResult {
  const ProviderSearchResult({
    required this.providerId,
    required this.providerName,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.error = '',
  });

  final String providerId;
  final String providerName;
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;
  final String error;

  bool get isEmpty =>
      songs.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty &&
      error.isEmpty;
}

class HistoryEntry {
  const HistoryEntry({required this.song, required this.playedAtMs});

  final Song song;
  final int playedAtMs;

  DateTime get playedAt => DateTime.fromMillisecondsSinceEpoch(playedAtMs);

  Map<String, dynamic> toJson() => {
        'song': song.toJson(),
        'playedAtMs': playedAtMs,
      };

  static HistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return HistoryEntry(
        song: Song.fromJson(raw['song']),
        playedAtMs: (raw['playedAtMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Application composition root: owns plugins, the local library and playback,
/// and implements the host bridge the plugin runtime calls into.
class AppController extends ChangeNotifier implements PluginAppBridge {
  AppController();

  static const Map<String, String> qualityLabels = {
    'standard': '标准',
    'higher': '较高',
    'exhigh': '极高',
    'lossless': '无损',
    'hires': 'Hi-Res',
  };

  static const String _historyKey = 'library.history';
  static const String _qualityKey = 'playback.quality';
  static const String _themeKey = 'ui.themeMode';
  static const String _searchHistoryKey = 'ui.searchHistory';

  late final Directory supportDirectory;
  late final PluginManager plugins;
  late final LocalLibrary library;
  PlaybackController? _playback;

  WebAuthRunner? _webAuthRunner;
  void Function(String message)? _toastSink;
  bool _initializing = true;
  String _initError = '';
  bool _disposed = false;

  List<HomeProviderFeed> _homeFeeds = const [];
  bool _homeLoading = false;
  String _homeError = '';

  List<HistoryEntry> _history = const [];
  String _quality = 'exhigh';
  String _themeMode = 'system';
  final LyricSettings lyricSettings = LyricSettings();
  final AppearanceSettings appearance = AppearanceSettings();
  final Map<String, ({Playlist value, DateTime at})> _playlistCache = {};
  List<String> _searchHistory = const [];
  String _searchProvider = '';

  // ---------------------------------------------------------------------------
  // Lifecycle

  bool get initializing => _initializing;
  bool get initialized => !_initializing;
  String get initError => _initError;
  PlaybackController get playback => _playback!;

  List<HomeProviderFeed> get homeFeeds => _homeFeeds;
  bool get homeLoading => _homeLoading;
  String get homeError => _homeError;

  List<HistoryEntry> get history => _history;
  String get quality => _quality;
  String get qualityLabel => qualityLabels[_quality] ?? _quality;

  /// Persisted UI theme: `system`, `light` or `dark`.
  String get themeMode => _themeMode;

  Future<void> setThemeMode(String value) async {
    const allowed = {'system', 'light', 'dark'};
    if (!allowed.contains(value) || value == _themeMode) return;
    _themeMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value);
    notifyListeners();
  }

  /// Provider tab currently selected on the search page.
  String get searchProvider => _searchProvider;
  set searchProvider(String value) {
    if (_searchProvider == value) return;
    _searchProvider = value;
    notifyListeners();
  }

  /// Recent search terms, newest first (max 10).
  List<String> get searchHistory => _searchHistory;

  Future<void> addSearchTerm(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) return;
    final next = [term, ..._searchHistory.where((item) => item != term)]
        .take(10)
        .toList(growable: false);
    _searchHistory = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryKey, next);
  }

  Future<void> clearSearchHistory() async {
    if (_searchHistory.isEmpty) return;
    _searchHistory = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }

  Future<void> removeSearchTerm(String term) async {
    final next =
        _searchHistory.where((item) => item != term).toList(growable: false);
    if (next.length == _searchHistory.length) return;
    _searchHistory = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryKey, next);
  }

  void attachWebAuthRunner(WebAuthRunner runner) => _webAuthRunner = runner;

  void attachToastSink(void Function(String message) sink) =>
      _toastSink = sink;

  Future<void> initialize() async {
    try {
      final base = await getApplicationSupportDirectory();
      supportDirectory = Directory(p.join(base.path, 'zmusic'));
      await supportDirectory.create(recursive: true);

      final pluginsRoot = Directory(p.join(supportDirectory.path, 'plugins'));
      final dataRoot = Directory(p.join(supportDirectory.path, 'plugin-data'));
      await pluginsRoot.create(recursive: true);
      await dataRoot.create(recursive: true);

      plugins = PluginManager(
        registry: PluginRegistry(
          File(p.join(supportDirectory.path, 'plugins.json')),
        ),
        pluginsRoot: pluginsRoot,
        dataRoot: dataRoot,
      );
      plugins.attachAppBridge(this);
      await plugins.initialize();

      library = LocalLibrary(supportDirectory: supportDirectory);
      await library.initialize();

      final playback = PlaybackController(
        resolveStream: _resolveStream,
        loadLyrics: _lyricsFor,
        onScrobble: _scrobble,
        onHistory: _recordHistory,
        onError: (message) => _toast('播放失败：$message'),
      );
      _playback = playback;
      await playback.initialize();

      await _loadPreferences();
    } catch (e) {
      _initError = e.toString();
      debugPrint('AppController initialization failed: $e');
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }

    if (_initError.isEmpty) {
      unawaited(refreshHome());
      unawaited(_refreshAllAccounts());
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final quality = prefs.getString(_qualityKey) ?? 'exhigh';
    const legacyQuality = {
      'low': 'standard',
      'medium': 'higher',
      'high': 'exhigh',
    };
    _quality = qualityLabels.containsKey(quality)
        ? quality
        : (legacyQuality[quality] ?? 'exhigh');
    final theme = prefs.getString(_themeKey) ?? 'system';
    _themeMode = const {'system', 'light', 'dark'}.contains(theme)
        ? theme
        : 'system';
    await lyricSettings.load(prefs);
    await appearance.load(prefs);
    _searchHistory = (prefs.getStringList(_searchHistoryKey) ?? const [])
        .take(10)
        .toList(growable: false);

    final rawHistory = prefs.getString(_historyKey);
    if (rawHistory != null && rawHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHistory);
        if (decoded is List) {
          _history = decoded
              .map(HistoryEntry.fromJson)
              .whereType<HistoryEntry>()
              .take(200)
              .toList();
        }
      } catch (_) {
        _history = const [];
      }
    }
  }

  Future<void> setQuality(String value) async {
    if (!qualityLabels.containsKey(value) || value == _quality) return;
    _quality = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Plugins & home

  String providerName(String providerId) =>
      plugins.entry(providerId)?.name ?? providerId;

  bool supports(String providerId, ProviderCapability capability) =>
      plugins.entry(providerId)?.manifest.hasCapability(capability) ?? false;

  List<InstalledPlugin> get installedPlugins => plugins.installed;

  List<String> get enabledProviders => plugins.enabledProviderIds;

  Future<void> refreshHome() async {
    if (_homeLoading || _initError.isNotEmpty) return;
    _homeLoading = true;
    _homeError = '';
    notifyListeners();

    try {
      final ids = plugins.enabledProviderIds
          .where((id) => supports(id, ProviderCapability.home))
          .toList();
      final primary = plugins.primaryId;
      if (primary != null && ids.remove(primary)) ids.insert(0, primary);

      final feeds = await Future.wait(ids.map((id) async {
        final name = providerName(id);
        try {
          final home = await plugins.providers.home(id, 12);
          return HomeProviderFeed(
            providerId: id,
            providerName: name,
            home: home,
            account: plugins.accountOf(id),
          );
        } catch (e) {
          return HomeProviderFeed(
            providerId: id,
            providerName: name,
            account: plugins.accountOf(id),
            error: e.toString(),
          );
        }
      }));
      _homeFeeds = feeds;
      if (feeds.every((feed) => feed.error.isNotEmpty)) {
        _homeError = feeds.map((feed) => feed.error).join('\n');
      }
    } catch (e) {
      _homeError = e.toString();
      _homeFeeds = const [];
    } finally {
      _homeLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _refreshAllAccounts() async {
    for (final id in plugins.enabledProviderIds) {
      if (!supports(id, ProviderCapability.account)) continue;
      try {
        await plugins.refreshAccount(id);
      } catch (_) {
        // Login state is optional; the account page surfaces failures.
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<AccountProfile?> refreshAccount(String providerId) async {
    try {
      return await plugins.refreshAccount(providerId);
    } catch (e) {
      _toast('账号信息刷新失败：$e');
      return null;
    }
  }

  AccountProfile? accountOf(String providerId) =>
      plugins.accountOf(providerId);

  String? get primaryProviderId => plugins.primaryId;

  /// Playlists owned by the signed-in account of [providerId] (or the primary
  /// source). Returns an empty list for sources without the capability.
  Future<List<Playlist>> myPlaylists({String? providerId}) async {
    final id = providerId ?? plugins.primaryId;
    if (id == null || !supports(id, ProviderCapability.userPlaylists)) {
      return const [];
    }
    return plugins.providers.userPlaylists(id, 200);
  }

  // ---------------------------------------------------------------------------
  // Search

  Future<List<String>> hotSearchTerms() async {
    final ids = plugins.enabledProviderIds
        .where((id) => supports(id, ProviderCapability.hotSearch))
        .toList();
    final seen = <String>{};
    final result = <String>[];
    for (final id in ids) {
      try {
        final terms = await plugins.providers.hotSearch(id);
        for (final term in terms) {
          if (seen.add(term)) result.add(term);
          if (result.length >= 50) return result;
        }
      } catch (_) {
        // Search suggestions are optional.
      }
    }
    return result;
  }

  Future<List<ProviderSearchResult>> search(
    String query, {
    int limit = 30,
  }) async {
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    final ids = plugins.searchProviders;
    return Future.wait(ids.map((id) async {
      final name = providerName(id);
      final songs = <Song>[];
      final albums = <Album>[];
      final artists = <Artist>[];
      final playlists = <Playlist>[];
      final errors = <String>[];
      try {
        if (supports(id, ProviderCapability.searchSongs)) {
          songs.addAll(
            (await plugins.providers.searchSongs(id, needle, '', limit)).items,
          );
        }
        if (supports(id, ProviderCapability.searchAlbums)) {
          albums.addAll(
            (await plugins.providers.searchAlbums(id, needle, '', limit))
                .items,
          );
        }
        if (supports(id, ProviderCapability.searchArtists)) {
          artists.addAll(
            (await plugins.providers.searchArtists(id, needle, '', limit))
                .items,
          );
        }
        if (supports(id, ProviderCapability.searchPlaylists)) {
          playlists.addAll(
            (await plugins.providers.searchPlaylists(id, needle, '', limit))
                .items,
          );
        }
      } catch (e) {
        errors.add(e.toString());
      }
      return ProviderSearchResult(
        providerId: id,
        providerName: name,
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        error: errors.join('\n'),
      );
    }));
  }

  // ---------------------------------------------------------------------------
  // Details

  Future<Playlist> playlistDetails(MediaId id) async {
    final key = id.toString();
    final cached = _playlistCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 10)) {
      return cached.value;
    }
    final watch = Stopwatch()..start();
    final playlist = await plugins.providers.playlist(id);
    final decorated = _decoratePlaylist(playlist);
    debugPrint('[perf] playlistDetails $key '
        '${watch.elapsedMilliseconds}ms (${playlist.songs.length} songs)');
    if (playlist.songs.isNotEmpty) {
      _playlistCache[key] = (value: decorated, at: DateTime.now());
      while (_playlistCache.length > 24) {
        _playlistCache.remove(_playlistCache.keys.first);
      }
    }
    return decorated;
  }

  Future<Album> albumDetails(MediaId id) =>
      plugins.providers.album(id);

  Future<Artist> artistDetails(MediaId id) =>
      plugins.providers.artist(id);

  Playlist _decoratePlaylist(Playlist playlist) => Playlist(
        id: playlist.id,
        provider: playlist.provider,
        nativeId: playlist.nativeId,
        name: playlist.name,
        description: playlist.description,
        artworkUrl: playlist.artworkUrl,
        owner: playlist.owner,
        trackCount: playlist.trackCount,
        playCount: playlist.playCount,
        subscribed: playlist.subscribed,
        owned: playlist.owned,
        mutable: playlist.mutable,
        deletable: playlist.deletable,
        songs: playlist.songs,
        sourceName: providerName(playlist.provider),
      );

  Future<Set<String>> likedSongs(String providerId) async {
    if (!supports(providerId, ProviderCapability.like)) return <String>{};
    return plugins.providers.likedSongs(providerId);
  }

  Future<bool> setLiked(Song song, bool liked) async {
    final id = song.mediaId;
    if (id == null) return false;
    return plugins.providers.setLiked(id, liked);
  }

  Future<String> shareSong(Song song) async {
    final id = song.mediaId;
    if (id == null) return '';
    if (!supports(song.provider, ProviderCapability.share)) return '';
    return plugins.providers.share(id);
  }

  Future<String> createPlaylist(
    String providerId,
    String name, {
    bool privateList = false,
  }) {
    return plugins.providers.createPlaylist(providerId, name, privateList);
  }

  Future<bool> mutatePlaylist(
    MediaId playlistId,
    String operation,
    List<Song> songs, {
    String? name,
  }) {
    return plugins.providers.mutatePlaylist(
      playlistId,
      operation,
      songs.map((song) => song.mediaId).whereType<MediaId>().toList(),
      name: name,
    );
  }

  Future<bool> reorderPlaylist(MediaId playlistId, List<Song> songs) {
    return plugins.providers.reorderPlaylist(
      playlistId,
      songs.map((song) => song.mediaId).whereType<MediaId>().toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Playback callbacks

  Future<StreamDescriptor> _resolveStream(Song song) async {
    final id = song.mediaId;
    if (id == null) throw ProviderException('无法解析歌曲来源');
    return plugins.providers.resolveStream(id, _quality);
  }

  Future<Lyrics> _lyricsFor(Song song) async {
    if (song.isLocal) return library.lyricsFor(song);
    final id = song.mediaId;
    if (id == null) return Lyrics.empty;
    if (!supports(song.provider, ProviderCapability.lyrics)) {
      return Lyrics.empty;
    }
    final payload = await plugins.providers.lyrics(id);
    return LyricParser.fromPluginAssets(payload);
  }

  Future<void> _scrobble(
    Song song,
    int playedMs,
    int durationMs,
    bool completed,
  ) async {
    final id = song.mediaId;
    if (id == null) return;
    if (!supports(song.provider, ProviderCapability.scrobble)) return;
    await plugins.providers.scrobble(id, playedMs, durationMs, completed);
  }

  Future<void> _recordHistory(Song song, int positionMs) async {
    final filtered = _history.where((entry) => entry.song.id != song.id);
    _history = [
      HistoryEntry(
        song: song,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      ...filtered,
    ].take(200).toList();
    if (!_disposed) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(_history.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // History persistence is best-effort.
    }
  }

  Future<void> clearHistory() async {
    _history = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  // ---------------------------------------------------------------------------
  // Login

  Future<List<LoginMethod>> loginMethods(String providerId) async {
    if (!supports(providerId, ProviderCapability.login)) return const [];
    final raw = await plugins.providers.login(providerId, 'methods', {
      'platform': _loginPlatform(),
    });
    if (raw is! List) return const [];
    final methods = <LoginMethod>[];
    for (final item in raw.take(8)) {
      if (item is! Map) continue;
      final method = _parseLoginMethod(item.cast<String, dynamic>());
      if (method != null) methods.add(method);
    }
    return methods;
  }

  Future<LoginChallenge> beginLogin(String providerId, String methodId) async {
    final raw = await plugins.providers.login(providerId, 'begin', {
      'methodId': methodId,
    });
    final challenge = parseLoginChallenge(raw);
    if (challenge == null) throw ProviderException('登录响应格式错误');
    return challenge;
  }

  Future<LoginChallenge> pollLogin(
    String providerId,
    String challengeId,
  ) async {
    final raw = await plugins.providers.login(providerId, 'poll', {
      'challengeId': challengeId,
    });
    final challenge = parseLoginChallenge(raw);
    if (challenge == null) throw ProviderException('登录响应格式错误');
    return challenge;
  }

  Future<LoginChallenge> submitLogin(
    String providerId,
    String methodId,
    String credential,
  ) async {
    final raw = await plugins.providers.login(providerId, 'submit', {
      'methodId': methodId,
      'credential': credential,
    });
    final challenge = parseLoginChallenge(raw);
    if (challenge == null) throw ProviderException('登录响应格式错误');
    return challenge;
  }

  Future<bool> logout(String providerId) async {
    final raw = await plugins.providers.login(providerId, 'logout', const {});
    final ok = raw != false;
    if (ok) {
      await plugins.refreshAccountIfSupported(providerId);
      notifyListeners();
    }
    return ok;
  }

  static String _loginPlatform() {
    if (kIsWeb) return 'desktop';
    return Platform.isAndroid ? 'android' : 'desktop';
  }

  static final RegExp _loginIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');

  static LoginMethod? _parseLoginMethod(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final type = (raw['type']?.toString() ?? '').toLowerCase();
    final label = _clip(raw['label']?.toString() ?? '', 4096);
    if (!_loginIdPattern.hasMatch(id) ||
        label.isEmpty ||
        !const {'qr', 'web', 'credential', 'app'}.contains(type)) {
      return null;
    }
    return LoginMethod(
      id: id,
      type: type,
      label: label,
      instructions: _clip(raw['instructions']?.toString() ?? '', 64 * 1024),
      webUrl: _clip(raw['webUrl']?.toString() ?? '', 8192),
      cookieUrl: _clip(raw['cookieUrl']?.toString() ?? '', 8192),
      credentialCookieName:
          _clip(raw['credentialCookieName']?.toString() ?? '', 1024),
      credentialLabel:
          _clip(raw['credentialLabel']?.toString() ?? '', 4096),
      appLabel: _clip(raw['appLabel']?.toString() ?? '', 4096),
    );
  }

  static LoginChallenge? parseLoginChallenge(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final status = (map['status']?.toString() ?? '').toLowerCase();
    if (!const {'waiting', 'scanned', 'success', 'expired', 'failed'}
        .contains(status)) {
      return null;
    }
    return LoginChallenge(
      status: status,
      id: _clip(map['id']?.toString() ?? '', 8192),
      methodId: _clip(map['methodId']?.toString() ?? '', 128),
      message: _clip(map['message']?.toString() ?? '', 64 * 1024),
      qrContent: _clip(map['qrContent']?.toString() ?? '', 64 * 1024),
      qrImageBase64: _clip(map['qrImageBase64']?.toString() ?? '', 300000),
      appUrl: _clip(map['appUrl']?.toString() ?? '', 8192),
      appLabel: _clip(map['appLabel']?.toString() ?? '', 4096),
      expiresAtMs: (map['expiresAtMs'] as num?)?.toInt() ?? 0,
      account: map['account'] is Map
          ? _parseAccount(map['account'] as Map)
          : null,
    );
  }

  static AccountProfile _parseAccount(Map raw) => AccountProfile(
        loggedIn: raw['loggedIn'] == true,
        id: _clip(raw['id']?.toString() ?? '', 4096),
        displayName: _clip(raw['displayName']?.toString() ?? '', 4096),
        avatarUrl: _clip(raw['avatarUrl']?.toString() ?? '', 8192),
        membershipTier: (raw['membershipTier'] as num?)?.toInt() ?? 0,
        level: (raw['level'] as num?)?.toInt() ?? 0,
        signature: _clip(raw['signature']?.toString() ?? '', 64 * 1024),
      );

  // ---------------------------------------------------------------------------
  // Declarative UI

  Future<Map<String, dynamic>> invokeUi(
    String providerId,
    String contributionId,
    String action,
    Map<String, dynamic> inputs,
  ) {
    return plugins.openUiDialog(providerId, contributionId, action, inputs);
  }

  /// Registers a handler for plugin HTTP-side downloads / lyric cache eviction
  /// when the host later adds those hooks.
  // ---------------------------------------------------------------------------
  // PluginAppBridge

  @override
  Future<Map<String, dynamic>> playbackRead(String pluginId) async {
    final playback = _playback;
    if (playback == null) {
      return const {
        'currentSongId': '',
        'queueSongIds': <String>[],
        'positionMs': 0,
        'durationMs': 0,
        'playing': false,
        'transitioning': true,
        'seekRevision': 0,
        'endRevision': 0,
      };
    }
    return playback.snapshotForPlugin(pluginId);
  }

  @override
  Future<void> playbackPlay() => _playback?.play() ?? Future.value();

  @override
  Future<void> playbackPause() => _playback?.pause() ?? Future.value();

  @override
  Future<void> playbackSeek(int positionMs) =>
      _playback?.seek(positionMs) ?? Future.value();

  @override
  Future<void> playbackSelect(
    String pluginId,
    String songId,
    int positionMs,
    bool playing,
  ) async {
    final playback = _playback;
    if (playback == null) return;
    final ok = await playback.selectFromPlugin(
      pluginId,
      songId,
      positionMs,
      playing,
    );
    if (!ok) {
      throw HostCallException('target song is not in the queue');
    }
  }

  @override
  Future<void> playbackNext() => _playback?.next() ?? Future.value();

  @override
  Future<void> blockAutoAdvance(String pluginId, bool blocked) async {
    _playback?.setAutoAdvanceBlocked(pluginId, blocked);
  }

  @override
  Future<void> replaceQueue(
    String pluginId,
    Map<String, dynamic> arguments,
  ) async {
    final playback = _playback;
    if (playback == null) throw HostCallException('playback is unavailable');
    final songs =
        plugins.providers.validateSongsStrict(pluginId, arguments['songs']);
    final rawSongId = _clip(arguments['currentSongId']?.toString() ?? '', 2048);
    if (rawSongId.isEmpty) {
      throw HostCallException('currentSongId is required');
    }
    final nativeId = _nativeSongIdFor(pluginId, rawSongId);
    final position = ((arguments['positionMs'] as num?)?.toInt() ?? 0)
        .clamp(0, 31 * 24 * 60 * 60 * 1000);
    final shouldPlay = arguments['playing'] != false;
    final ok = await playback.replaceQueueFromPlugin(
      pluginId,
      songs,
      nativeId,
      position,
      shouldPlay,
    );
    if (!ok) {
      throw HostCallException('target song is not in replacement queue');
    }
  }

  String _nativeSongIdFor(String pluginId, String raw) {
    if (raw.contains(':')) {
      try {
        final id = MediaId.parse(raw);
        if (id.provider != pluginId || id.kind != MediaKind.song) {
          throw HostCallException('song provider mismatch');
        }
        return id.nativeId;
      } on ArgumentError {
        // A native id may contain a colon; fall through to the literal value.
      }
    }
    return raw;
  }

  @override
  Future<bool> downloadCurrent(String pluginId) async {
    final song = _playback?.currentSong;
    if (song == null || song.provider != pluginId) {
      throw HostCallException('当前没有属于该插件的歌曲');
    }
    final id = song.mediaId;
    if (id == null) return false;
    final descriptor = await plugins.providers.resolveStream(id, _quality);
    final filename = _suggestFilename(
      song,
      descriptor.mimeType,
      descriptor.url,
    );
    return saveUrl(
      url: descriptor.url,
      headers: descriptor.headers,
      filename: filename,
      mimeType: descriptor.mimeType,
    );
  }

  @override
  Future<bool> saveUrl({
    required String url,
    Map<String, String> headers = const {},
    String filename = '',
    String mimeType = '',
  }) async {
    final safeName = _sanitizeFilename(
      filename.isEmpty ? 'qplayer-download' : filename,
    );
    final fullName = _withExtension(safeName, mimeType, url);
    final dio = Dio(BaseOptions(
      followRedirects: true,
      maxRedirects: 5,
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(minutes: 5),
      validateStatus: (status) => status != null && status < 400,
    ));
    final Uint8List bytes;
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(headers: headers, responseType: ResponseType.bytes),
      );
      bytes = Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw HostCallException('下载失败：${e.message ?? e.type.name}');
    }
    if (bytes.isEmpty) throw HostCallException('下载内容为空');

    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存文件',
      fileName: fullName,
      bytes: bytes,
    );
    if (path == null) return false;
    // Desktop platforms return a path without writing the bytes themselves.
    final file = File(path);
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    _toast('已保存到 ${p.basename(path)}');
    return true;
  }

  @override
  Future<String> runWebAuth(String originUrl, String script) async {
    final runner = _webAuthRunner;
    if (runner == null) throw HostCallException('内置浏览器不可用');
    return runner(originUrl, script);
  }

  @override
  void toast(String message) => _toast(message);

  void _toast(String message) {
    final sink = _toastSink;
    if (sink != null) {
      sink(message);
    } else {
      debugPrint(message);
    }
  }

  @override
  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty) {
      throw HostCallException('无效的链接');
    }
    const allowed = {
      'http',
      'https',
      'mailto',
      'tel',
      'snssdk1128',
      'snssdk2329',
      'snssdk8478',
      'snssdk8663',
      'luna',
      'aweme',
      'orpheus',
      'orpheuswidget',
      'wtloginmqq',
      'mqqapi',
      'mqq',
      'qqmusic',
    };
    if (!allowed.contains(uri.scheme.toLowerCase())) {
      throw HostCallException('不支持的链接类型');
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) throw HostCallException('无法打开链接');
  }

  // ---------------------------------------------------------------------------
  // Files

  static String _sanitizeFilename(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_')
        .trim();
    final clipped = cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
    return clipped.isEmpty ? 'qplayer-download' : clipped;
  }

  static String _withExtension(String name, String mimeType, String url) {
    if (p.extension(name).isNotEmpty) return name;
    final lowerMime = mimeType.toLowerCase().split(';').first.trim();
    final extension = switch (lowerMime) {
      'audio/mpeg' || 'audio/mp3' => '.mp3',
      'audio/flac' || 'audio/x-flac' => '.flac',
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/aac' => '.aac',
      _ => '',
    };
    if (extension.isNotEmpty) return '$name$extension';
    final fromUrl = p.extension(Uri.tryParse(url)?.path ?? '');
    if (fromUrl.isNotEmpty && fromUrl.length <= 6) return '$name$fromUrl';
    return '$name.mp3';
  }

  static String _suggestFilename(
    Song song,
    String mimeType,
    String url,
  ) {
    final artist = song.artistLabel.trim();
    final base = artist.isEmpty ? song.title : '$artist - ${song.title}';
    return _withExtension(_sanitizeFilename(base), mimeType, url);
  }

  // ---------------------------------------------------------------------------
  // Helpers

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  @override
  void dispose() {
    _disposed = true;
    _playback?.dispose();
    try {
      library.dispose();
    } catch (_) {}
    try {
      plugins.dispose();
    } catch (_) {}
    super.dispose();
  }
}
