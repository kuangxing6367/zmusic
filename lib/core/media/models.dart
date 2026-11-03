import 'media_id.dart';
import 'media_kind.dart';

/// A lightweight artist/owner reference.
class MediaRef {
  const MediaRef({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static MediaRef fromJson(Object? raw) {
    if (raw is! Map) return const MediaRef(id: '', name: '');
    return MediaRef(
      id: raw['id']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
    );
  }
}

/// Source-neutral song DTO. Remote songs carry a canonical [id] owned by the host;
/// local files use the synthetic `local:song:<path>` identity.
class Song {
  Song({
    required this.id,
    required this.provider,
    required this.nativeId,
    required this.title,
    this.artists = const [],
    this.album,
    this.durationMs = 0,
    this.artworkUrl = '',
    this.isrc = '',
    this.playable = true,
    this.trial = false,
    this.restricted = false,
    this.cachedOffline = false,
    this.localPath = '',
  });

  final String id;
  final String provider;
  final String nativeId;
  final String title;
  final List<MediaRef> artists;
  final MediaRef? album;
  final int durationMs;
  final String artworkUrl;
  final String isrc;
  final bool playable;
  final bool trial;
  final bool restricted;
  final bool cachedOffline;

  /// Absolute path for local tracks; empty for remote tracks.
  final String localPath;

  bool get isLocal => provider == 'local' || localPath.isNotEmpty;

  String get artistLabel =>
      artists.map((a) => a.name).where((n) => n.isNotEmpty).join(' / ');

  /// Best available cover: remote artwork or a local file path.
  String get coverUrl => artworkUrl.isNotEmpty ? artworkUrl : localPath;

  Duration get duration => Duration(milliseconds: durationMs);

  MediaId? get mediaId {
    if (provider == 'local') return null;
    try {
      return MediaId(provider, MediaKind.song, nativeId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'nativeId': nativeId,
        'title': title,
        'artists': artists.map((a) => a.toJson()).toList(),
        'album': album?.toJson(),
        'durationMs': durationMs,
        'artworkUrl': artworkUrl,
        'isrc': isrc,
        'playable': playable,
        'trial': trial,
        'restricted': restricted,
        'cachedOffline': cachedOffline,
        'localPath': localPath,
      };

  static Song fromJson(Object? raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return Song(
      id: map['id']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      nativeId: map['nativeId']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      artists: (map['artists'] as List?)
              ?.map(MediaRef.fromJson)
              .where((a) => a.name.isNotEmpty)
              .toList() ??
          const [],
      album: map['album'] == null ? null : MediaRef.fromJson(map['album']),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      artworkUrl: map['artworkUrl']?.toString() ?? '',
      isrc: map['isrc']?.toString() ?? '',
      playable: map['playable'] as bool? ?? true,
      trial: map['trial'] as bool? ?? false,
      restricted: map['restricted'] as bool? ?? false,
      cachedOffline: map['cachedOffline'] as bool? ?? false,
      localPath: map['localPath']?.toString() ?? '',
    );
  }
}

class Playlist {
  Playlist({
    required this.id,
    required this.provider,
    required this.nativeId,
    required this.name,
    this.description = '',
    this.artworkUrl = '',
    this.owner,
    this.trackCount = 0,
    this.playCount = 0,
    this.subscribed = false,
    this.owned = false,
    this.mutable = false,
    this.deletable = false,
    this.songs = const [],
    this.sourceName = '',
  });

  final String id;
  final String provider;
  final String nativeId;
  final String name;
  final String description;
  final String artworkUrl;
  final MediaRef? owner;
  final int trackCount;
  final int playCount;
  final bool subscribed;
  final bool owned;
  final bool mutable;
  final bool deletable;
  final List<Song> songs;

  /// Display name of the owning source (host-side augmentation).
  final String sourceName;

  String get coverUrl => artworkUrl;

  static Playlist fromJson(Object? raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return Playlist(
      id: map['id']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      nativeId: map['nativeId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      artworkUrl: map['artworkUrl']?.toString() ?? '',
      owner: map['owner'] == null ? null : MediaRef.fromJson(map['owner']),
      trackCount: (map['trackCount'] as num?)?.toInt() ?? 0,
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
      subscribed: map['subscribed'] as bool? ?? false,
      owned: map['owned'] as bool? ?? false,
      mutable: map['mutable'] as bool? ?? false,
      deletable: map['deletable'] as bool? ?? false,
      songs: (map['songs'] as List?)?.map(Song.fromJson).toList() ?? const [],
      sourceName: map['sourceName']?.toString() ?? '',
    );
  }
}

class Album {
  Album({
    required this.id,
    required this.provider,
    required this.nativeId,
    required this.name,
    this.artists = const [],
    this.artworkUrl = '',
    this.publishTimeMs = 0,
    this.description = '',
    this.trackCount = 0,
    this.songs = const [],
  });

  final String id;
  final String provider;
  final String nativeId;
  final String name;
  final List<MediaRef> artists;
  final String artworkUrl;
  final int publishTimeMs;
  final String description;
  final int trackCount;
  final List<Song> songs;

  String get coverUrl => artworkUrl;
  String get artistLabel => artists.map((a) => a.name).join(' / ');

  static Album fromJson(Object? raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return Album(
      id: map['id']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      nativeId: map['nativeId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      artists: (map['artists'] as List?)
              ?.map(MediaRef.fromJson)
              .where((a) => a.name.isNotEmpty)
              .toList() ??
          const [],
      artworkUrl: map['artworkUrl']?.toString() ?? '',
      publishTimeMs: (map['publishTimeMs'] as num?)?.toInt() ?? 0,
      description: map['description']?.toString() ?? '',
      trackCount: (map['trackCount'] as num?)?.toInt() ?? 0,
      songs: (map['songs'] as List?)?.map(Song.fromJson).toList() ?? const [],
    );
  }
}

class Artist {
  Artist({
    required this.id,
    required this.provider,
    required this.nativeId,
    required this.name,
    this.artworkUrl = '',
    this.description = '',
    this.albumCount = 0,
    this.songCount = 0,
    this.songs = const [],
    this.albums = const [],
  });

  final String id;
  final String provider;
  final String nativeId;
  final String name;
  final String artworkUrl;
  final String description;
  final int albumCount;
  final int songCount;
  final List<Song> songs;
  final List<Album> albums;

  String get coverUrl => artworkUrl;

  static Artist fromJson(Object? raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return Artist(
      id: map['id']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      nativeId: map['nativeId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      artworkUrl: map['artworkUrl']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      albumCount: (map['albumCount'] as num?)?.toInt() ?? 0,
      songCount: (map['songCount'] as num?)?.toInt() ?? 0,
      songs: (map['songs'] as List?)?.map(Song.fromJson).toList() ?? const [],
      albums:
          (map['albums'] as List?)?.map(Album.fromJson).toList() ?? const [],
    );
  }
}

class StreamDescriptor {
  StreamDescriptor({
    required this.url,
    this.headers = const {},
    this.mimeType = '',
    this.expiresAtMs = 0,
    this.trial = false,
    this.cacheable = true,
    this.renditionId = '',
  });

  final String url;
  final Map<String, String> headers;
  final String mimeType;
  final int expiresAtMs;
  final bool trial;
  final bool cacheable;
  final String renditionId;
}

class Paged<T> {
  const Paged({required this.items, this.nextCursor = ''});

  final List<T> items;
  final String nextCursor;

  bool get hasMore => nextCursor.isNotEmpty;

  static Paged<T> fromJson<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse, {
    int limit = 200,
  }) {
    if (raw is! Map) return const Paged(items: [], nextCursor: '');
    final items = <T>[];
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final item in rawItems.take(limit)) {
        if (item is Map) {
          try {
            items.add(parse(item.cast<String, dynamic>()));
          } catch (_) {
            // Malformed songs are omitted from ordinary lists.
          }
        }
      }
    }
    final cursor = (raw['nextCursor']?.toString() ?? '');
    return Paged(
      items: items,
      nextCursor: cursor.length > 8192 ? '' : cursor,
    );
  }
}

class HomeSection {
  const HomeSection({required this.title, required this.playlists});

  final String title;
  final List<Playlist> playlists;
}

class ProviderHome {
  const ProviderHome({
    this.songs = const [],
    this.playlists = const [],
    this.sections = const [],
  });

  final List<Song> songs;
  final List<Playlist> playlists;
  final List<HomeSection> sections;
}

class AccountProfile {
  const AccountProfile({
    this.loggedIn = false,
    this.id = '',
    this.displayName = '',
    this.avatarUrl = '',
    this.membershipTier = 0,
    this.level = 0,
    this.signature = '',
  });

  final bool loggedIn;
  final String id;
  final String displayName;
  final String avatarUrl;
  final int membershipTier;
  final int level;
  final String signature;
}

class LyricAsset {
  const LyricAsset({
    required this.format,
    required this.role,
    required this.text,
  });

  final String format;
  final String role;
  final String text;
}

class LyricsPayload {
  const LyricsPayload(this.assets);

  final List<LyricAsset> assets;
}

class LoginMethod {
  const LoginMethod({
    required this.id,
    required this.type,
    required this.label,
    this.instructions = '',
    this.webUrl = '',
    this.cookieUrl = '',
    this.credentialCookieName = '',
    this.credentialLabel = '',
    this.appLabel = '',
  });

  final String id;
  final String type;
  final String label;
  final String instructions;
  final String webUrl;
  final String cookieUrl;
  final String credentialCookieName;
  final String credentialLabel;
  final String appLabel;
}

class LoginChallenge {
  const LoginChallenge({
    required this.status,
    this.id = '',
    this.methodId = '',
    this.message = '',
    this.qrContent = '',
    this.qrImageBase64 = '',
    this.appUrl = '',
    this.appLabel = '',
    this.expiresAtMs = 0,
    this.account,
  });

  final String status;
  final String id;
  final String methodId;
  final String message;
  final String qrContent;
  final String qrImageBase64;
  final String appUrl;
  final String appLabel;
  final int expiresAtMs;
  final AccountProfile? account;

  bool get isTerminal => status == 'success' || status == 'failed';

  /// Poll responses only carry `id`/`methodId`/`status`; keep the QR artwork
  /// and app link from the original `begin` response so the code does not
  /// vanish one tick after it is shown.
  LoginChallenge keepVisualsFrom(LoginChallenge? previous) {
    if (previous == null) return this;
    return LoginChallenge(
      status: status,
      id: id,
      methodId: methodId.isEmpty ? previous.methodId : methodId,
      message: message,
      qrContent: qrContent.isEmpty ? previous.qrContent : qrContent,
      qrImageBase64:
          qrImageBase64.isEmpty ? previous.qrImageBase64 : qrImageBase64,
      appUrl: appUrl.isEmpty ? previous.appUrl : appUrl,
      appLabel: appLabel.isEmpty ? previous.appLabel : appLabel,
      expiresAtMs: expiresAtMs == 0 ? previous.expiresAtMs : expiresAtMs,
      account: account ?? previous.account,
    );
  }
}
