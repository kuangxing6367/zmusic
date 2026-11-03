import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/plugin/provider_capability.dart';
import '../widgets/cards.dart';
import '../widgets/cover_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import '../widgets/song_tile.dart';
import 'details_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<ProviderSearchResult> _results = const [];
  List<String> _hotTerms = const [];
  bool _loading = false;
  String _error = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadHotTerms();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHotTerms() async {
    final terms = await widget.controller.hotSearchTerms();
    if (!mounted) return;
    setState(() => _hotTerms = terms);
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _query = query;
      _loading = true;
      _error = '';
    });
    unawaited(widget.controller.addSearchTerm(query));
    try {
      final results = await widget.controller.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
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

  void _clear() {
    _text.clear();
    setState(() {
      _results = const [];
      _query = '';
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final providers = widget.controller.enabledProviders
            .where(
              (id) => widget.controller.supports(
                id,
                ProviderCapability.searchSongs,
              ),
            )
            .toList();
        final selected = widget.controller.searchProvider;
        final visible = selected.isEmpty
            ? _results
            : _results.where((r) => r.providerId == selected).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
          children: [
            Text(
              '搜索',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '在所有已启用的音源中查找歌曲、专辑与歌单',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌手、专辑…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: _clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            if (providers.length > 1 && _query.isNotEmpty) ...[
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ProviderFilterChip(
                      label: '全部',
                      selected: selected.isEmpty,
                      onTap: () =>
                          widget.controller.searchProvider = '',
                    ),
                    for (final id in providers)
                      _ProviderFilterChip(
                        label: widget.controller.providerName(id),
                        selected: selected == id,
                        onTap: () =>
                            widget.controller.searchProvider = id,
                      ),
                  ],
                ),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: ErrorBanner(
                  message: _error,
                  onRetry: () => _search(_query),
                ),
              ),
            if (!_loading && _query.isEmpty) ...[
              if (widget.controller.searchHistory.isNotEmpty) ...[
                SectionHeader(
                  title: '搜索历史',
                  actionLabel: '清空',
                  onAction: widget.controller.clearSearchHistory,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final term in widget.controller.searchHistory)
                      InputChip(
                        avatar: const Icon(Icons.history_rounded, size: 16),
                        label: Text(term),
                        onPressed: () {
                          _text.text = term;
                          _search(term);
                        },
                        onDeleted: () =>
                            widget.controller.removeSearchTerm(term),
                      ),
                  ],
                ),
              ],
              if (_hotTerms.isNotEmpty) ...[
                const SectionHeader(title: '热门搜索'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _hotTerms.length; i++)
                      ActionChip(
                        avatar: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: i < 3
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                        ),
                        label: Text(_hotTerms[i]),
                        onPressed: () {
                          _text.text = _hotTerms[i];
                          _search(_hotTerms[i]);
                        },
                      ),
                  ],
                ),
              ],
              if (widget.controller.history.isNotEmpty) ...[
                const SectionHeader(title: '最近播放'),
                for (final entry in widget.controller.history.take(8))
                  SongTile(
                    song: entry.song,
                    controller: widget.controller,
                    playback: widget.controller.playback,
                    onTap: () => widget.controller.playback.playSong(
                      entry.song,
                      contextName: '最近播放',
                    ),
                  ),
              ],
              if (_hotTerms.isEmpty &&
                  widget.controller.history.isEmpty &&
                  providers.isEmpty)
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有可用的音源',
                  message: '启用一个支持搜索的 qplug 插件后即可在这里搜索。',
                  actionLabel: '刷新',
                  onAction: _loadHotTerms,
                ),
            ],
            if (!_loading && _query.isNotEmpty) ...[
              if (visible.every((r) => r.isEmpty) && _error.isEmpty)
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有找到“$_query”',
                  message: '试试其他关键词，或切换音源。',
                ),
              for (final result in visible)
                _ProviderResults(
                  controller: widget.controller,
                  query: _query,
                  result: result,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ProviderFilterChip extends StatelessWidget {
  const _ProviderFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ProviderResults extends StatelessWidget {
  const _ProviderResults({
    required this.controller,
    required this.query,
    required this.result,
  });

  final AppController controller;
  final String query;
  final ProviderSearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              result.providerName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (result.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ErrorBanner(
              message: result.error,
              title: '${result.providerName} 搜索失败',
            ),
          ),
        if (result.songs.isNotEmpty) ...[
          SectionHeader(
            title: '歌曲',
            subtitle: '${result.songs.length} 个结果 · $query',
          ),
          for (var i = 0; i < result.songs.length; i++)
            SongTile(
              song: result.songs[i],
              controller: controller,
              playback: controller.playback,
              index: i,
              showCover: false,
              onTap: () => controller.playback.playSongs(
                result.songs,
                index: i,
                contextName: '搜索：$query',
              ),
            ),
        ],
        if (result.albums.isNotEmpty) ...[
          const SectionHeader(title: '专辑'),
          SizedBox(
            height: 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final album = result.albums[index];
                return AlbumCard(
                  album: album,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailPage(
                        controller: controller,
                        album: album,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (result.playlists.isNotEmpty) ...[
          const SectionHeader(title: '歌单'),
          SizedBox(
            height: 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final playlist = result.playlists[index];
                return PlaylistCard(
                  playlist: playlist,
                  subtitle: (playlist.owner?.name.isNotEmpty ?? false)
                      ? playlist.owner!.name
                      : (playlist.trackCount > 0
                          ? '${playlist.trackCount} 首'
                          : ''),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailPage(
                        controller: controller,
                        playlist: playlist,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (result.artists.isNotEmpty) ...[
          const SectionHeader(title: '歌手'),
          for (final artist in result.artists)
            ListTile(
              leading: CoverArt(
                url: artist.coverUrl,
                size: 48,
                radius: 24,
                icon: Icons.person_rounded,
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (artist.songCount > 0) '${artist.songCount} 首歌曲',
                  if (artist.albumCount > 0) '${artist.albumCount} 张专辑',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArtistDetailPage(
                    controller: controller,
                    artist: artist,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
