import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../lyric/lrc_parser.dart';
import '../lyric/lyric_models.dart';
import '../lyric/lyric_parser.dart';
import '../media/models.dart';

/// Host-owned local library: folder selection, recursive scanning, metadata,
/// embedded artwork/lyrics and sidecar lyric files.
class LocalLibrary extends ChangeNotifier {
  LocalLibrary({required this.supportDirectory});

  final Directory supportDirectory;

  static const List<String> lyricExtensions = [
    '.ttml',
    '.yrc',
    '.eslrc',
    '.lrc',
    '.qrc',
    '.lys',
  ];

  static final Set<String> _audioExtensions = {
    ...supportedFileExtensions,
    '.aac',
    '.m4b',
    '.wma',
  };

  static const List<String> _coverNames = [
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'folder.jpg',
    'folder.jpeg',
    'folder.png',
    'front.jpg',
    'front.jpeg',
    'front.png',
    'album.jpg',
    'album.png',
  ];

  final List<String> _folders = [];
  List<Song> _songs = [];
  bool _scanning = false;
  String _scanMessage = '';
  String _error = '';
  final Map<String, Uint8List?> _artworkCache = {};
  final Map<String, String?> _folderCoverCache = {};
  static const int _maxArtworkBytes = 24 * 1024 * 1024;
  int _artworkBytes = 0;

  List<String> get folders => List.unmodifiable(_folders);
  List<Song> get songs => List.unmodifiable(_songs);
  bool get scanning => _scanning;
  String get scanMessage => _scanMessage;
  String get error => _error;
  bool get isEmpty => _songs.isEmpty;

  File get _cacheFile => File(p.join(supportDirectory.path, 'local-library.json'));

  // ---------------------------------------------------------------------------
  // Persistence & scanning

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _folders
      ..clear()
      ..addAll(prefs.getStringList('library.folders') ?? const []);
    await _loadCache();
  }

  Future<void> addFolder(String path) async {
    final normalized = p.normalize(path);
    if (_folders.contains(normalized)) return;
    _folders.add(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('library.folders', _folders);
    await scan();
  }

  Future<void> removeFolder(String path) async {
    _folders.removeWhere((folder) => p.normalize(folder) == p.normalize(path));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('library.folders', _folders);
    await scan();
  }

  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    _error = '';
    _scanMessage = '正在准备扫描…';
    notifyListeners();

    final found = <String>{};
    final songs = <Song>[];
    try {
      for (final folder in _folders) {
        final directory = Directory(folder);
        if (!await directory.exists()) continue;
        try {
          await for (final entity
              in directory.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final extension = p.extension(entity.path).toLowerCase();
            if (!_audioExtensions.contains(extension)) continue;
            if (!found.add(entity.path)) continue;

            _scanMessage = '正在读取 ${p.basename(entity.path)}';
            songs.add(await _songFromFile(entity));
            if (songs.length % 16 == 0) notifyListeners();
            // Yield so the UI and plugin actors keep running during long scans.
            await Future<void>.delayed(Duration.zero);
          }
        } catch (e) {
          _error = '无法扫描 $folder: $e';
        }
      }
      songs.sort(_compareSongs);
      _songs = songs;
      await _saveCache();
    } finally {
      _scanning = false;
      _scanMessage = '';
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _songs = [];
    _folders.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('library.folders');
    try {
      if (await _cacheFile.exists()) await _cacheFile.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<Song> _songFromFile(File file) async {
    var title = p.basenameWithoutExtension(file.path);
    var artist = '';
    var album = '';
    var durationMs = 0;
    try {
      final metadata = readMetadata(file, getImage: false);
      final rawTitle = metadata.title?.trim() ?? '';
      if (rawTitle.isNotEmpty) title = rawTitle;
      artist = metadata.artist?.trim() ?? '';
      album = metadata.album?.trim() ?? '';
      durationMs = metadata.duration?.inMilliseconds ?? 0;
    } catch (_) {
      // Unsupported tags fall back to file-name metadata.
    }
    final cover = await _folderCover(p.dirname(file.path));
    final encodedPath = base64Url.encode(utf8.encode(file.path));
    return Song(
      id: 'local:$encodedPath',
      provider: 'local',
      nativeId: file.path,
      title: title,
      artists: artist.isEmpty
          ? const []
          : [
              MediaRef(
                id: 'local:artist:${Uri.encodeComponent(artist)}',
                name: artist,
              ),
            ],
      album: album.isEmpty
          ? null
          : MediaRef(
              id: 'local:album:${Uri.encodeComponent(album)}',
              name: album,
            ),
      durationMs: durationMs,
      artworkUrl: cover ?? '',
      localPath: file.path,
    );
  }

  static int _compareSongs(Song a, Song b) {
    final albumCompare = (a.album?.name ?? '').compareTo(b.album?.name ?? '');
    if (albumCompare != 0) return albumCompare;
    final artistCompare =
        (a.artistLabel).compareTo(b.artistLabel);
    if (artistCompare != 0) return artistCompare;
    return a.title.compareTo(b.title);
  }

  Future<String?> _folderCover(String directory) async {
    if (_folderCoverCache.containsKey(directory)) {
      return _folderCoverCache[directory];
    }
    String? result;
    for (final name in _coverNames) {
      final candidate = File(p.join(directory, name));
      if (await candidate.exists()) {
        result = candidate.path;
        break;
      }
    }
    _folderCoverCache[directory] = result;
    return result;
  }

  Future<void> _loadCache() async {
    try {
      if (!await _cacheFile.exists()) return;
      final raw = jsonDecode(await _cacheFile.readAsString());
      final list = (raw is Map ? raw['songs'] : raw) as List?;
      if (list == null) return;
      _songs = [
        for (final item in list)
          if (item is Map) Song.fromJson(item),
      ];
      notifyListeners();
    } catch (_) {
      // A corrupt cache is ignored; the user can rescan.
    }
  }

  Future<void> _saveCache() async {
    try {
      await supportDirectory.create(recursive: true);
      final temp = File('${_cacheFile.path}.tmp');
      await temp.writeAsString(jsonEncode({
        'schemaVersion': 1,
        'songs': _songs.map((song) => song.toJson()).toList(),
      }), flush: true);
      await temp.rename(_cacheFile.path);
    } catch (_) {
      // Cache persistence is optional.
    }
  }

  // ---------------------------------------------------------------------------
  // Artwork & lyrics

  /// Embedded cover for a local track (folder covers are already in
  /// [Song.artworkUrl]).
  Future<Uint8List?> artworkFor(Song song) async {
    if (song.localPath.isEmpty) return null;
    final cached = _artworkCache[song.localPath];
    if (cached != null || _artworkCache.containsKey(song.localPath)) {
      return cached;
    }
    Uint8List? bytes;
    try {
      final metadata = readMetadata(File(song.localPath), getImage: true);
      Picture? front;
      for (final picture in metadata.pictures) {
        if (picture.pictureType == PictureType.coverFront) {
          front = picture;
          break;
        }
      }
      front ??= metadata.pictures.isEmpty ? null : metadata.pictures.first;
      bytes = front?.bytes;
    } catch (_) {
      bytes = null;
    }
    final previous = _artworkCache.remove(song.localPath);
    if (previous != null) _artworkBytes -= previous.length;
    _artworkCache[song.localPath] = bytes;
    _artworkBytes += bytes?.length ?? 0;
    while (_artworkBytes > _maxArtworkBytes && _artworkCache.length > 1) {
      final oldest = _artworkCache.keys.first;
      final removed = _artworkCache.remove(oldest);
      _artworkBytes -= removed?.length ?? 0;
    }
    return bytes;
  }
  Future<Lyrics> lyricsFor(Song song) async {
    if (song.localPath.isEmpty) return Lyrics.empty;
    final directory = p.dirname(song.localPath);
    final base = p.join(directory, p.basenameWithoutExtension(song.localPath));

    for (final extension in lyricExtensions) {
      final candidate = File('$base$extension');
      if (await candidate.exists()) {
        final translation = await _firstExisting([
          '$base.trans.lrc',
          '$base.zh.lrc',
          '$base.translation.lrc',
        ]);
        final romanization = await _firstExisting([
          '$base.romaji.lrc',
          '$base.roma.lrc',
          '$base.romanization.lrc',
        ]);
        return LyricParser.parseFile(
          candidate.path,
          translationPath: translation,
          romanizationPath: romanization,
        );
      }
    }

    // Embedded lyrics: parse as LRC when it looks timed, otherwise show the
    // plain text as a single unsynchronised line.
    try {
      final metadata = readMetadata(File(song.localPath), getImage: false);
      final raw = metadata.lyrics?.trim();
      if (raw != null && raw.isNotEmpty) {
        final lines = LrcParser.parse(raw);
        if (lines.isNotEmpty) {
          return Lyrics(lines: lines, format: 'lrc');
        }
        return Lyrics(
          lines: [
            LyricLine()
              ..syllables.add(
                LyricSyllable(text: raw, startMs: 0, durationMs: 0),
              ),
          ],
          format: 'text',
        );
      }
    } catch (_) {}
    return Lyrics.empty;
  }

  Future<String?> _firstExisting(List<String> paths) async {
    for (final path in paths) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Search & grouping helpers

  List<Song> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return songs;
    return _songs.where((song) {
      return song.title.toLowerCase().contains(needle) ||
          song.artistLabel.toLowerCase().contains(needle) ||
          (song.album?.name.toLowerCase().contains(needle) ?? false) ||
          p.basename(song.localPath).toLowerCase().contains(needle);
    }).toList();
  }

  List<Album> albums() {
    final groups = <String, List<Song>>{};
    for (final song in _songs) {
      final name = song.album?.name ?? '未知专辑';
      groups.putIfAbsent(name, () => []).add(song);
    }
    final result = <Album>[];
    for (final entry in groups.entries) {
      final first = entry.value.first;
      result.add(Album(
        id: first.album?.id ?? 'local:album:${Uri.encodeComponent(entry.key)}',
        provider: 'local',
        nativeId: entry.key,
        name: entry.key,
        artists: first.album == null && first.artists.isNotEmpty
            ? first.artists
            : const [],
        artworkUrl: first.artworkUrl,
        trackCount: entry.value.length,
        songs: entry.value,
      ));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<Artist> artists() {
    final groups = <String, List<Song>>{};
    for (final song in _songs) {
      final name = song.artistLabel.isEmpty ? '未知歌手' : song.artistLabel;
      groups.putIfAbsent(name, () => []).add(song);
    }
    final result = <Artist>[];
    for (final entry in groups.entries) {
      final first = entry.value.first;
      result.add(Artist(
        id: 'local:artist:${Uri.encodeComponent(entry.key)}',
        provider: 'local',
        nativeId: entry.key,
        name: entry.key,
        artworkUrl: first.artworkUrl,
        songCount: entry.value.length,
        songs: entry.value,
      ));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
