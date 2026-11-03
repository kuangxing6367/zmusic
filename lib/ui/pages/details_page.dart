import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/media_id.dart';
import '../../core/media/models.dart';
import '../widgets/cards.dart';
import '../widgets/cover_backdrop.dart';
import '../widgets/empty_state.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.controller,
    required this.playlist,
  });

  final AppController controller;
  final Playlist playlist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  static const int _pageSize = 80;

  late Playlist _playlist = widget.playlist;
  final TextEditingController _filterText = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _searchOpen = false;
  String _filter = '';
  String _error = '';
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeGrow);
    if (_playlist.songs.isEmpty && _playlist.provider != 'local') {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _filterText.dispose();
    super.dispose();
  }

  /// Long playlists are appended in pages: the sliver only ever holds a
  /// bounded number of rows, which keeps layout and painting cheap.
  void _maybeGrow() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 480) return;
    final total = _visibleSongs.length;
    if (_shown >= total) return;
    setState(() => _shown = math.min(total, _shown + _pageSize));
  }

  List<Song> get _visibleSongs {
    final query = _filter.toLowerCase();
    if (query.isEmpty) return _playlist.songs;
    return _playlist.songs.where((song) {
      final haystack = [
        song.title,
        song.artistLabel,
        song.album?.name ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final id = MediaId.parse(_playlist.id);
      final playlist = await widget.controller.playlistDetails(id);
      if (!mounted) return;
      setState(() {
        _playlist = playlist;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _play(int index) {
    final songs = _playlist.songs;
    if (songs.isEmpty) return;
    widget.controller.playback.playSongs(
      songs,
      index: index,
      contextName: _playlist.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              leading: const BackButton(),
              title: Text(_playlist.name, maxLines: 1),
              actions: [
                IconButton(
                  tooltip: _searchOpen ? '关闭搜索' : '搜索歌单',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _filterText.clear();
                      _filter = '';
                    }
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _Header(
                  playlist: _playlist,
                  onPlay: () => _play(0),
                ),
              ),
            ),
            if (_searchOpen)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: _TrackFilterField(
                    controller: _filterText,
                    hint: '在“${_playlist.name}”中搜索',
                    onChanged: (value) => setState(() => _filter = value.trim()),
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(child: _DetailSkeleton()),
            if (_error.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error, onRetry: _load),
                ),
              ),
            if (!_loading && _playlist.songs.isEmpty && _error.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: '这个歌单还是空的',
                  message: '换一个歌单，或稍后刷新试试。',
                  compact: true,
                ),
              ),
            if (!_loading &&
                _playlist.songs.isNotEmpty &&
                _visibleSongs.isEmpty &&
                _filter.isNotEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有匹配的歌曲',
                  message: '试试歌名、歌手或专辑里的其他关键词。',
                  compact: true,
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 120),
              sliver: SliverList.builder(
                itemCount: math.min(_visibleSongs.length, _shown),
                itemBuilder: (context, index) {
                  final song = _visibleSongs[index];
                  return SmoothScrollItem(
                    controller: _scroll,
                    child: SongTile(
                      song: song,
                      controller: widget.controller,
                      playback: widget.controller.playback,
                      index: index,
                      showCover: false,
                      onTap: () {
                        final list = _visibleSongs;
                        final position = list.indexOf(song);
                        widget.controller.playback.playSongs(
                          list,
                          index: position < 0 ? 0 : position,
                          contextName: _playlist.name,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _playlist.songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _play(0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                '播放全部',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.playlist, required this.onPlay});

  final Playlist playlist;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoverBackdrop(
      url: playlist.coverUrl,
      fallbackUrls: [
        for (final song in playlist.songs.take(4))
          if (song.artworkUrl.isNotEmpty) song.artworkUrl,
      ],
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              theme.colorScheme.surface.withValues(alpha: 0.32),
              theme.colorScheme.surface,
            ],
            stops: const [0.0, 0.60, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 18),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoverArtFrame(
                url: playlist.coverUrl,
                size: 128,
                radius: 22,
                icon: Icons.queue_music_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (playlist.sourceName.isNotEmpty) playlist.sourceName,
                        if (playlist.owner?.name.isNotEmpty ?? false)
                          playlist.owner!.name,
                        if (playlist.songs.isNotEmpty)
                          '${playlist.songs.length} 首'
                        else if (playlist.trackCount > 0)
                          '${playlist.trackCount} 首',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (playlist.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        playlist.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.controller,
    required this.album,
  });

  final AppController controller;
  final Album album;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Album _album = widget.album;
  final TextEditingController _filterText = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _searchOpen = false;
  String _filter = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (_album.songs.isEmpty && _album.provider != 'local') _load();
  }

  @override
  void dispose() {
    _filterText.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Song> get _visibleSongs {
    final query = _filter.toLowerCase();
    if (query.isEmpty) return _album.songs;
    return _album.songs.where((song) {
      final haystack = [
        song.title,
        song.artistLabel,
        song.album?.name ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final album = await widget.controller
          .albumDetails(MediaId.parse(_album.id));
      if (!mounted) return;
      setState(() {
        _album = album;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _play(int index) {
    if (_album.songs.isEmpty) return;
    widget.controller.playback.playSongs(
      _album.songs,
      index: index,
      contextName: _album.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 290,
              title: Text(_album.name, maxLines: 1),
              actions: [
                IconButton(
                  tooltip: _searchOpen ? '关闭搜索' : '搜索专辑',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _filterText.clear();
                      _filter = '';
                    }
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _DetailHeader(
                  title: _album.name,
                  subtitle: _album.artistLabel,
                  coverUrl: _album.coverUrl,
                  info: '${_album.songs.length} 首'
                      '${_album.publishTimeMs > 0 ? ' · ${_album.publishTimeMs}' : ''}',
                  icon: Icons.album_rounded,
                  onPlay: () => _play(0),
                ),
              ),
            ),
            if (_searchOpen)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: _TrackFilterField(
                    controller: _filterText,
                    hint: '在“${_album.name}”中搜索',
                    onChanged: (value) => setState(() => _filter = value.trim()),
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(child: _DetailSkeleton()),
            if (_error.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error, onRetry: _load),
                ),
              ),
            if (!_loading && _album.songs.isEmpty && _error.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.album_rounded,
                  title: '专辑里还没有歌曲',
                  compact: true,
                ),
              ),
            if (!_loading &&
                _album.songs.isNotEmpty &&
                _visibleSongs.isEmpty &&
                _filter.isNotEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有匹配的歌曲',
                  message: '试试歌名、歌手或专辑里的其他关键词。',
                  compact: true,
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 120),
              sliver: SliverList.builder(
                itemCount: _visibleSongs.length,
                itemBuilder: (context, index) {
                  final song = _visibleSongs[index];
                  return SmoothScrollItem(
                    controller: _scroll,
                    child: SongTile(
                      song: song,
                      controller: widget.controller,
                      playback: widget.controller.playback,
                      index: index,
                      showCover: false,
                      onTap: () {
                        final list = _visibleSongs;
                        final position = list.indexOf(song);
                        widget.controller.playback.playSongs(
                          list,
                          index: position < 0 ? 0 : position,
                          contextName: _album.name,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _album.songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _play(0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                '播放专辑',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.controller,
    required this.artist,
  });

  final AppController controller;
  final Artist artist;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  late Artist _artist = widget.artist;
  final TextEditingController _filterText = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _searchOpen = false;
  String _filter = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (_artist.songs.isEmpty && _artist.provider != 'local') _load();
  }

  @override
  void dispose() {
    _filterText.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Song> get _visibleSongs {
    final query = _filter.toLowerCase();
    if (query.isEmpty) return _artist.songs;
    return _artist.songs.where((song) {
      final haystack = [
        song.title,
        song.artistLabel,
        song.album?.name ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final artist = await widget.controller
          .artistDetails(MediaId.parse(_artist.id));
      if (!mounted) return;
      setState(() {
        _artist = artist;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _play(int index) {
    if (_artist.songs.isEmpty) return;
    widget.controller.playback.playSongs(
      _artist.songs,
      index: index,
      contextName: _artist.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 270,
              title: Text(_artist.name, maxLines: 1),
              actions: [
                IconButton(
                  tooltip: _searchOpen ? '关闭搜索' : '搜索歌曲',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _filterText.clear();
                      _filter = '';
                    }
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _DetailHeader(
                  title: _artist.name,
                  subtitle: _artist.description,
                  coverUrl: _artist.coverUrl,
                  info: [
                    if (_artist.songCount > 0) '${_artist.songCount} 首歌曲',
                    if (_artist.albumCount > 0) '${_artist.albumCount} 张专辑',
                  ].join(' · '),
                  icon: Icons.person_rounded,
                  circular: true,
                  onPlay: () => _play(0),
                ),
              ),
            ),
            if (_searchOpen)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: _TrackFilterField(
                    controller: _filterText,
                    hint: '在“${_artist.name}”中搜索',
                    onChanged: (value) => setState(() => _filter = value.trim()),
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(child: _DetailSkeleton()),
            if (_error.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error, onRetry: _load),
                ),
              ),
            if (_artist.albums.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text(
                    '专辑',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 218,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _artist.albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final album = _artist.albums[index];
                      return AlbumCard(
                        album: album,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailPage(
                              controller: widget.controller,
                              album: album,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (_artist.songs.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    '热门歌曲',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_visibleSongs.isEmpty && _filter.isNotEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '没有匹配的歌曲',
                    message: '试试歌名、歌手或专辑里的其他关键词。',
                    compact: true,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
                sliver: SliverList.builder(
                  itemCount: _visibleSongs.length,
                  itemBuilder: (context, index) {
                    final song = _visibleSongs[index];
                    return SmoothScrollItem(
                      controller: _scroll,
                      child: SongTile(
                        song: song,
                        controller: widget.controller,
                        playback: widget.controller.playback,
                        index: index,
                        showCover: false,
                        onTap: () {
                          final list = _visibleSongs;
                          final position = list.indexOf(song);
                          widget.controller.playback.playSongs(
                            list,
                            index: position < 0 ? 0 : position,
                            contextName: _artist.name,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ] else if (!_loading && _error.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.person_rounded,
                  title: '暂无歌手歌曲',
                  compact: true,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _artist.songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _play(0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放热门歌曲'),
            ),
    );
  }
}

class _DetailSkeleton extends StatefulWidget {
  const _DetailSkeleton();

  final int rows = 9;

  @override
  State<_DetailSkeleton> createState() => _DetailSkeletonState();
}

class _DetailSkeletonState extends State<_DetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 0.8,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = scheme.onSurface.withValues(alpha: 0.12);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
    return FadeTransition(
      opacity: _pulse,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: [
                    bar(16, 12),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.38 + (i % 3) * 0.12,
                            child: bar(double.infinity, 13),
                          ),
                          const SizedBox(height: 7),
                          FractionallySizedBox(
                            widthFactor: 0.22 + (i % 2) * 0.10,
                            child: bar(double.infinity, 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackFilterField extends StatelessWidget {
  const _TrackFilterField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.info,
    required this.icon,
    required this.onPlay,
    this.circular = false,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final String info;
  final IconData icon;
  final VoidCallback onPlay;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoverBackdrop(
      url: coverUrl,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              theme.colorScheme.surface.withValues(alpha: 0.34),
              theme.colorScheme.surface,
            ],
            stops: const [0.0, 0.60, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 18),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(circular ? 64 : 22),
                child: CoverArtFrame(
                  url: coverUrl,
                  size: 128,
                  radius: circular ? 64 : 22,
                  icon: icon,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (info.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        info,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
