import 'dart:convert';

import '../media/media_id.dart';
import '../media/media_kind.dart';
import '../media/models.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'provider_capability.dart';

class ProviderException implements Exception {
  ProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Translates .qplug handler results into host DTOs and qualifies
/// native ids exactly like the original Java host.
class PluginProviderService {
  PluginProviderService({
    required PluginManifest? Function(String provider) manifestOf,
    required PluginRuntime? Function(String provider) runtimeOf,
  })  : _manifestOf = manifestOf, // ignore: prefer_initializing_formals
        _runtimeOf = runtimeOf; // ignore: prefer_initializing_formals

  final PluginManifest? Function(String provider) _manifestOf;
  final PluginRuntime? Function(String provider) _runtimeOf;

  static const int _maxArtists = 64;

  PluginManifest _requireManifest(String provider) {
    final manifest = _manifestOf(provider);
    if (manifest == null) {
      throw ProviderException('音源插件未启用: $provider');
    }
    return manifest;
  }

  PluginRuntime _requireRuntime(String provider) {
    final runtime = _runtimeOf(provider);
    if (runtime == null || !runtime.isRunning) {
      throw ProviderException('音源插件未运行: $provider');
    }
    return runtime;
  }

  void _requireCapability(String provider, ProviderCapability capability) {
    final manifest = _requireManifest(provider);
    if (!manifest.hasCapability(capability)) {
      throw ProviderException('$provider 不支持 ${capability.wireName}');
    }
  }

  Future<dynamic> _invoke(
    String provider,
    ProviderCapability capability,
    Map<String, dynamic> args,
  ) async {
    _requireCapability(provider, capability);
    return _requireRuntime(provider).invoke(capability.wireName, args);
  }

  // ---------------------------------------------------------------------------
  // Search & discovery

  Future<Paged<Song>> searchSongs(
    String provider,
    String query,
    String cursor,
    int limit,
  ) async {
    final raw = await _invoke(provider, ProviderCapability.searchSongs, {
      'query': query,
      'cursor': cursor,
      'limit': limit.clamp(1, 100),
    });
    return Paged.fromJson<Song>(
      raw,
      (item) => _parseSong(provider, item),
      limit: 200,
    );
  }

  Future<Paged<Album>> searchAlbums(
    String provider,
    String query,
    String cursor,
    int limit,
  ) async {
    final raw = await _invoke(provider, ProviderCapability.searchAlbums, {
      'query': query,
      'cursor': cursor,
      'limit': limit.clamp(1, 100),
    });
    return Paged.fromJson<Album>(
      raw,
      (item) => _parseAlbum(provider, item),
      limit: 200,
    );
  }

  Future<Paged<Artist>> searchArtists(
    String provider,
    String query,
    String cursor,
    int limit,
  ) async {
    final raw = await _invoke(provider, ProviderCapability.searchArtists, {
      'query': query,
      'cursor': cursor,
      'limit': limit.clamp(1, 100),
    });
    return Paged.fromJson<Artist>(
      raw,
      (item) => _parseArtist(provider, item),
      limit: 200,
    );
  }

  Future<Paged<Playlist>> searchPlaylists(
    String provider,
    String query,
    String cursor,
    int limit,
  ) async {
    final raw = await _invoke(provider, ProviderCapability.searchPlaylists, {
      'query': query,
      'cursor': cursor,
      'limit': limit.clamp(1, 100),
    });
    return Paged.fromJson<Playlist>(
      raw,
      (item) => _parsePlaylist(provider, item),
      limit: 200,
    );
  }

  Future<List<String>> hotSearch(String provider) async {
    final raw = await _invoke(provider, ProviderCapability.hotSearch, {});
    if (raw is! List) return const [];
    return raw
        .map((v) => v?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .take(50)
        .toList();
  }

  Future<ProviderHome> home(String provider, int limit) async {
    final raw = await _invoke(provider, ProviderCapability.home, {
      'limit': limit.clamp(1, 100),
    });
    if (raw is! Map) return const ProviderHome();
    final songs = _parseSongList(provider, raw['songs'], max: 100);
    final playlists = _parsePlaylistList(provider, raw['playlists'], max: 100);
    final sections = <HomeSection>[];
    final rawSections = raw['sections'];
    if (rawSections is List) {
      for (final section in rawSections.take(6)) {
        if (section is! Map) continue;
        final title = section['title']?.toString() ?? '';
        final items = _parsePlaylistList(provider, section['playlists'], max: 30);
        if (items.isEmpty) continue;
        sections.add(HomeSection(title: title, playlists: items));
      }
    }
    return ProviderHome(
      songs: songs,
      playlists: playlists,
      sections: sections,
    );
  }

  Future<List<Song>> recommendSongs(String provider, int limit) async {
    final raw = await _invoke(provider, ProviderCapability.home, {
      'operation': 'recommendSongs',
    });
    return _parseSongList(provider, raw, max: 500);
  }

  Future<List<Playlist>> userPlaylists(String provider, int limit) async {
    final raw = await _invoke(provider, ProviderCapability.userPlaylists, {
      'limit': limit.clamp(1, 500),
    });
    return _parsePlaylistList(provider, raw, max: 500);
  }

  Future<List<Song>> recent(String provider, int limit) async {
    final raw = await _invoke(provider, ProviderCapability.recent, {
      'limit': limit.clamp(1, 500),
    });
    return _parseSongList(provider, raw, max: 500);
  }

  Future<List<Song>> heartRecommendations(
    MediaId seedSong,
    MediaId seedPlaylist,
    int limit,
  ) async {
    final provider = seedSong.provider;
    final raw = await _invoke(
      provider,
      ProviderCapability.heartRecommendation,
      {
        'songId': seedSong.nativeId,
        'playlistId': seedPlaylist.nativeId,
        'limit': limit.clamp(1, 500),
      },
    );
    return _parseSongList(provider, raw, max: 500);
  }

  // ---------------------------------------------------------------------------
  // Details

  Future<List<Song>> songDetails(String provider, List<MediaId> ids) async {
    if (ids.isEmpty) return const [];
    final raw = await _invoke(provider, ProviderCapability.songDetails, {
      'ids': ids.take(500).map((id) => id.nativeId).toList(),
    });
    final songs = _parseSongList(provider, raw, max: 500);
    final order = {for (var i = 0; i < ids.length; i++) ids[i].nativeId: i};
    songs.sort((a, b) =>
        (order[a.nativeId] ?? 1 << 30).compareTo(order[b.nativeId] ?? 1 << 30));
    return songs;
  }

  Future<Playlist> playlist(MediaId id) async {
    final raw = await _invoke(
      id.provider,
      ProviderCapability.playlistDetails,
      {'id': id.nativeId},
    );
    if (raw is! Map) throw ProviderException('歌单详情格式错误');
    return _parsePlaylist(id.provider, raw.cast<String, dynamic>());
  }

  Future<Album> album(MediaId id) async {
    final raw = await _invoke(
      id.provider,
      ProviderCapability.albumDetails,
      {'id': id.nativeId},
    );
    if (raw is! Map) throw ProviderException('专辑详情格式错误');
    return _parseAlbum(id.provider, raw.cast<String, dynamic>());
  }

  Future<Artist> artist(MediaId id) async {
    final raw = await _invoke(
      id.provider,
      ProviderCapability.artistDetails,
      {'id': id.nativeId},
    );
    if (raw is! Map) throw ProviderException('歌手详情格式错误');
    return _parseArtist(id.provider, raw.cast<String, dynamic>());
  }

  // ---------------------------------------------------------------------------
  // Playback, lyrics, account

  Future<StreamDescriptor> resolveStream(MediaId id, String quality) async {
    final raw = await _invoke(
      id.provider,
      ProviderCapability.resolveStream,
      {'id': id.nativeId, 'quality': quality},
    );
    if (raw is! Map) throw ProviderException('播放地址格式错误');
    final url = _string(raw['url']).trim();
    if (url.isEmpty) throw ProviderException('插件未返回播放地址');
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries.take(64)) {
        final name = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        if (!RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name) ||
            name.length > 128 ||
            value.length > 8192 ||
            value.contains('\r') ||
            value.contains('\n') ||
            name.toLowerCase() == 'host' ||
            name.toLowerCase() == 'content-length' ||
            name.toLowerCase() == 'connection') {
          continue;
        }
        headers[name] = value;
      }
    }
    final renditionNative = _string(raw['renditionId']);
    final renditionId = renditionNative.isEmpty
        ? ''
        : MediaId.of(id.provider, MediaKind.song, renditionNative).toString();
    return StreamDescriptor(
      url: url,
      headers: headers,
      mimeType: _string(raw['mimeType']),
      expiresAtMs: _int(raw['expiresAtMs']),
      trial: _bool(raw['trial']),
      cacheable: raw.containsKey('cacheable') ? _bool(raw['cacheable']) : true,
      renditionId: renditionId,
    );
  }

  Future<LyricsPayload> lyrics(MediaId id) async {
    final raw = await _invoke(
      id.provider,
      ProviderCapability.lyrics,
      {'id': id.nativeId},
    );
    if (raw is! Map) return const LyricsPayload([]);
    final assets = <LyricAsset>[];
    final rawAssets = raw['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets.take(12)) {
        if (item is! Map) continue;
        final format = _string(item['format']).toLowerCase();
        if (!const {'lrc', 'yrc', 'ttml'}.contains(format)) continue;
        var role = _string(item['role']);
        if (role.isEmpty) role = 'original';
        if (!const {'original', 'translation', 'romanization'}.contains(role)) {
          continue;
        }
        final text = _string(item['text']);
        if (text.isEmpty || text.length > 4 * 1024 * 1024) continue;
        assets.add(LyricAsset(format: format, role: role, text: text));
      }
    }
    return LyricsPayload(assets);
  }

  Future<AccountProfile> account(String provider) async {
    final raw = await _invoke(provider, ProviderCapability.account, {});
    if (raw is! Map) return const AccountProfile();
    return _parseAccount(raw);
  }

  /// Raw login result: a method array for `methods`, a challenge map otherwise.
  Future<dynamic> login(
    String provider,
    String operation,
    Map<String, dynamic> extra,
  ) async {
    final args = <String, dynamic>{'operation': operation, ...extra};
    return _invoke(provider, ProviderCapability.login, args);
  }

  // ---------------------------------------------------------------------------
  // Mutations

  Future<Set<String>> likedSongs(String provider) async {
    final raw = await _invoke(provider, ProviderCapability.like, {
      'operation': 'list',
    });
    if (raw is! List) return <String>{};
    final result = <String>{};
    for (final item in raw.take(100000)) {
      final native = item?.toString() ?? '';
      if (native.isEmpty) continue;
      try {
        result.add(MediaId.of(provider, MediaKind.song, native).toString());
      } catch (_) {
        // Ignore malformed ids.
      }
    }
    return result;
  }

  Future<bool> setLiked(MediaId id, bool liked) async {
    final raw = await _invoke(id.provider, ProviderCapability.like, {
      'operation': 'set',
      'id': id.nativeId,
      'liked': liked,
    });
    return _success(raw);
  }

  Future<bool> mutatePlaylist(
    MediaId playlistId,
    String operation,
    List<MediaId> songs, {
    String? name,
  }) async {
    final raw = await _invoke(
      playlistId.provider,
      ProviderCapability.playlistMutation,
      {
        'operation': operation,
        'playlistId': playlistId.nativeId,
        'songIds': songs.take(1000).map((s) => s.nativeId).toList(),
        'name': ?name,
      },
    );
    return _success(raw);
  }

  Future<String> createPlaylist(
    String provider,
    String name,
    bool privateList,
  ) async {
    final raw = await _invoke(provider, ProviderCapability.playlistMutation, {
      'operation': 'create',
      'name': name,
      'private': privateList,
    });
    if (raw is String) return raw;
    if (raw is Map) {
      final native = _string(raw['id']);
      if (native.isNotEmpty) {
        return MediaId.of(provider, MediaKind.playlist, native).toString();
      }
    }
    return '';
  }

  Future<bool> reorderPlaylist(MediaId playlistId, List<MediaId> order) async {
    final raw = await _invoke(
      playlistId.provider,
      ProviderCapability.playlistReorder,
      {
        'playlistId': playlistId.nativeId,
        'songIds': order.map((s) => s.nativeId).toList(),
      },
    );
    return _success(raw);
  }

  Future<bool> setPlaylistCover(
    MediaId playlistId,
    List<int> image,
    String filename,
    String mimeType,
  ) async {
    final raw = await _invoke(
      playlistId.provider,
      ProviderCapability.playlistCover,
      {
        'playlistId': playlistId.nativeId,
        'imageBase64': base64Encode(image),
        'filename': filename,
        'mimeType': mimeType,
      },
    );
    return _success(raw);
  }

  Future<void> scrobble(
    MediaId id,
    int playedMs,
    int durationMs,
    bool completed,
  ) async {
    await _invoke(id.provider, ProviderCapability.scrobble, {
      'id': id.nativeId,
      'playedMs': playedMs,
      'durationMs': durationMs,
      'completed': completed,
    });
  }

  Future<String> share(MediaId id) async {
    final raw = await _invoke(id.provider, ProviderCapability.share, {
      'id': id.nativeId,
      'kind': id.kind.wireName,
    });
    return raw?.toString() ?? '';
  }

  /// Validates a raw song array a plugin supplied in `queue.replace`.
  List<Song> validateSongs(String provider, Object? raw) =>
      _parseSongList(provider, raw, max: 5000);

  /// Strict variant used by `queue.replace`: unlike ordinary lists, malformed
  /// entries reject the whole array.
  List<Song> validateSongsStrict(String provider, Object? raw) {
    if (raw is! List || raw.isEmpty || raw.length > 500) {
      throw ProviderException('播放队列格式错误');
    }
    final result = <Song>[];
    for (final item in raw) {
      if (item is! Map) throw ProviderException('播放队列包含无效歌曲');
      result.add(_parseSong(provider, item.cast<String, dynamic>()));
    }
    return result;
  }

  /// Invokes a declarative UI contribution: `ui.<id>`.
  Future<Map<String, dynamic>> invokeUi(
    String provider,
    String contributionId,
    String action,
    Map<String, dynamic> inputs,
  ) async {
    final raw = await _requireRuntime(provider).invoke(
      'ui.$contributionId',
      {
        'action': action,
        'payload': {'inputs': inputs},
      },
    );
    if (raw is! Map) throw ProviderException('插件界面返回格式错误');
    return raw.cast<String, dynamic>();
  }

  // ---------------------------------------------------------------------------
  // DTO parsing

  Song _parseSong(String provider, Map<String, dynamic> raw) {
    final native = _string(raw['id']);
    if (native.isEmpty) throw const FormatException('song id is empty');
    final title = _string(raw['title']);
    if (title.isEmpty) throw const FormatException('song title is empty');
    final id = MediaId.of(provider, MediaKind.song, native);
    final artists = <MediaRef>[];
    final rawArtists = raw['artists'];
    if (rawArtists is List) {
      for (final item in rawArtists.take(_maxArtists)) {
        if (item is! Map) continue;
        final name = _string(item['name']);
        final artistNative = _string(item['id']);
        if (name.isEmpty || artistNative.isEmpty) continue;
        try {
          artists.add(MediaRef(
            id: MediaId.of(provider, MediaKind.artist, artistNative).toString(),
            name: name.length > 4096 ? name.substring(0, 4096) : name,
          ));
        } catch (_) {
          // Skip malformed credits.
        }
      }
    }
    MediaRef? album;
    final rawAlbum = raw['album'];
    if (rawAlbum is Map) {
      final albumNative = _string(rawAlbum['id']);
      final albumName = _string(rawAlbum['name']);
      if (albumNative.isNotEmpty && albumName.isNotEmpty) {
        try {
          album = MediaRef(
            id: MediaId.of(provider, MediaKind.album, albumNative).toString(),
            name: albumName.length > 4096
                ? albumName.substring(0, 4096)
                : albumName,
          );
        } catch (_) {
          album = null;
        }
      }
    }
    final duration = _int(raw['durationMs']);
    return Song(
      id: id.toString(),
      provider: provider,
      nativeId: native,
      title: title.length > 4096 ? title.substring(0, 4096) : title,
      artists: artists,
      album: album,
      durationMs: duration.clamp(0, 31 * 24 * 60 * 60 * 1000),
      artworkUrl: _string(raw['artworkUrl']).length > 8192
          ? ''
          : _string(raw['artworkUrl']),
      isrc: _string(raw['isrc']),
      playable: raw.containsKey('playable') ? _bool(raw['playable']) : true,
      trial: _bool(raw['trial']),
      restricted: _bool(raw['restricted']),
    );
  }

  List<Song> _parseSongList(String provider, Object? raw, {required int max}) {
    if (raw is! List) return const [];
    final result = <Song>[];
    for (final item in raw.take(max)) {
      if (item is! Map) continue;
      try {
        result.add(_parseSong(provider, item.cast<String, dynamic>()));
      } catch (_) {
        // Ordinary lists omit malformed songs.
      }
    }
    return result;
  }

  Playlist _parsePlaylist(String provider, Map<String, dynamic> raw) {
    final native = _string(raw['id']);
    if (native.isEmpty) throw const FormatException('playlist id is empty');
    final name = _string(raw['name']);
    if (name.isEmpty) throw const FormatException('playlist name is empty');
    MediaRef? owner;
    final rawOwner = raw['owner'];
    if (rawOwner is Map) {
      final ownerNative = _string(rawOwner['id']);
      final ownerName = _string(rawOwner['name']);
      if (ownerName.isNotEmpty) {
        owner = MediaRef(
          id: ownerNative.isEmpty
              ? ''
              : MediaId.of(provider, MediaKind.user, ownerNative).toString(),
          name: ownerName,
        );
      }
    }
    final owned = _bool(raw['owned']);
    return Playlist(
      id: MediaId.of(provider, MediaKind.playlist, native).toString(),
      provider: provider,
      nativeId: native,
      name: name.length > 4096 ? name.substring(0, 4096) : name,
      description: _clip(_string(raw['description']), 1024 * 1024),
      artworkUrl: _clip(_string(raw['artworkUrl']), 8192),
      owner: owner,
      trackCount: _int(raw['trackCount']).clamp(0, 1 << 40),
      playCount: _int(raw['playCount']).clamp(0, 1 << 40),
      subscribed: _bool(raw['subscribed']),
      owned: owned,
      mutable: raw.containsKey('mutable') ? _bool(raw['mutable']) : owned,
      deletable: raw.containsKey('deletable') ? _bool(raw['deletable']) : owned,
      songs: _parseSongList(provider, raw['songs'], max: 20000),
    );
  }

  List<Playlist> _parsePlaylistList(
    String provider,
    Object? raw, {
    required int max,
  }) {
    if (raw is! List) return const [];
    final result = <Playlist>[];
    for (final item in raw.take(max)) {
      if (item is! Map) continue;
      try {
        result.add(_parsePlaylist(provider, item.cast<String, dynamic>()));
      } catch (_) {
        // Skip malformed entries.
      }
    }
    return result;
  }

  Album _parseAlbum(String provider, Map<String, dynamic> raw) {
    final native = _string(raw['id']);
    if (native.isEmpty) throw const FormatException('album id is empty');
    final name = _string(raw['name']);
    if (name.isEmpty) throw const FormatException('album name is empty');
    final artists = <MediaRef>[];
    final rawArtists = raw['artists'];
    if (rawArtists is List) {
      for (final item in rawArtists.take(_maxArtists)) {
        if (item is! Map) continue;
        final artistId = _string(item['id']);
        final artistName = _string(item['name']);
        if (artistId.isEmpty || artistName.isEmpty) continue;
        try {
          artists.add(MediaRef(
            id: MediaId.of(provider, MediaKind.artist, artistId).toString(),
            name: artistName,
          ));
        } catch (_) {}
      }
    }
    return Album(
      id: MediaId.of(provider, MediaKind.album, native).toString(),
      provider: provider,
      nativeId: native,
      name: name.length > 4096 ? name.substring(0, 4096) : name,
      artists: artists,
      artworkUrl: _clip(_string(raw['artworkUrl']), 8192),
      publishTimeMs: _int(raw['publishTimeMs']),
      description: _clip(_string(raw['description']), 1024 * 1024),
      trackCount: _int(raw['trackCount']).clamp(0, 1000000),
      songs: _parseSongList(provider, raw['songs'], max: 5000),
    );
  }

  Artist _parseArtist(String provider, Map<String, dynamic> raw) {
    final native = _string(raw['id']);
    if (native.isEmpty) throw const FormatException('artist id is empty');
    final name = _string(raw['name']);
    if (name.isEmpty) throw const FormatException('artist name is empty');
    final albums = <Album>[];
    final rawAlbums = raw['albums'];
    if (rawAlbums is List) {
      for (final item in rawAlbums.take(1000)) {
        if (item is! Map) continue;
        try {
          albums.add(_parseAlbum(provider, item.cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    return Artist(
      id: MediaId.of(provider, MediaKind.artist, native).toString(),
      provider: provider,
      nativeId: native,
      name: name.length > 4096 ? name.substring(0, 4096) : name,
      artworkUrl: _clip(_string(raw['artworkUrl']), 8192),
      description: _clip(_string(raw['description']), 1024 * 1024),
      albumCount: _int(raw['albumCount']).clamp(0, 1000000),
      songCount: _int(raw['songCount']).clamp(0, 10000000),
      songs: _parseSongList(provider, raw['songs'], max: 1000),
      albums: albums,
    );
  }

  AccountProfile _parseAccount(Map<dynamic, dynamic> raw) {
    return AccountProfile(
      loggedIn: _bool(raw['loggedIn']),
      id: _string(raw['id']),
      displayName: _clip(_string(raw['displayName']), 4096),
      avatarUrl: _clip(_string(raw['avatarUrl']), 8192),
      membershipTier: _int(raw['membershipTier']).clamp(0, 1000),
      level: _int(raw['level']).clamp(0, 100000),
      signature: _clip(_string(raw['signature']), 64 * 1024),
    );
  }

  static bool _success(Object? raw) {
    if (raw is bool) return raw;
    if (raw is Map) return raw['success'] == true;
    return false;
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _bool(Object? value) => value == true;

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
