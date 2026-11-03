import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../widgets/cards.dart';
import '../widgets/cover_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';
import 'details_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0;
  String _filter = '';

  AppController get _controller => widget.controller;

  Future<void> _addFolder() async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择音乐文件夹',
    );
    if (directory == null) return;
    await _controller.library.addFolder(directory);
  }

  Future<void> _scan() async {
    await _controller.library.scan();
  }

  List<Song> get _songs {
    final all = _controller.library.songs;
    final needle = _filter.trim().toLowerCase();
    if (needle.isEmpty) return all;
    return all.where((song) {
      return song.title.toLowerCase().contains(needle) ||
          song.artistLabel.toLowerCase().contains(needle) ||
          (song.album?.name.toLowerCase().contains(needle) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller.library]),
      builder: (context, _) {
        final library = _controller.library;
        final songs = _songs;
        final albums = library.albums();
        final artists = library.artists();
        final theme = Theme.of(context);

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本地音乐',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${library.songs.length} 首歌曲 · '
                        '${library.folders.length} 个文件夹',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '扫描文件夹',
                  onPressed: library.scanning ? null : _scan,
                  icon: library.scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '添加文件夹',
                  onPressed: _addFolder,
                  icon: const Icon(Icons.create_new_folder_rounded),
                ),
              ],
            ),
            if (library.folders.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final folder in library.folders)
                    InputChip(
                      avatar: const Icon(Icons.folder_rounded, size: 18),
                      label: Text(
                        folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: () => library.removeFolder(folder),
                    ),
                ],
              ),
            ],
            if (library.scanning) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                borderRadius: BorderRadius.circular(100),
              ),
              if (library.scanMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    library.scanMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            if (library.error.isNotEmpty) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: library.error, onRetry: _scan),
            ],
            if (library.songs.isEmpty && !library.scanning)
              EmptyState(
                icon: Icons.library_music_rounded,
                title: '把音乐放进来',
                message: '选择一个或多个音乐文件夹，zmusic 会自动读取标签、封面与歌词。',
                actionLabel: '选择文件夹',
                onAction: _addFolder,
              )
            else ...[
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => _filter = value),
                decoration: const InputDecoration(
                  hintText: '筛选本地歌曲…',
                  prefixIcon: Icon(Icons.filter_list_rounded),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('歌曲')),
                  ButtonSegment(value: 1, label: Text('专辑')),
                  ButtonSegment(value: 2, label: Text('歌手')),
                ],
                selected: {_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 10),
              if (_tab == 0)
                for (var i = 0; i < songs.length; i++)
                  SongTile(
                    song: songs[i],
                    controller: _controller,
                    playback: _controller.playback,
                    index: i,
                    onTap: () => _controller.playback.playSongs(
                      songs,
                      index: i,
                      contextName: '本地音乐',
                    ),
                  ),
              if (_tab == 1)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 236,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return AlbumCard(
                      album: album,
                      width: 180,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailPage(
                            controller: _controller,
                            album: album,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (_tab == 2)
                for (final artist in artists)
                  ListTile(
                    leading: CoverArt(
                      url: artist.coverUrl,
                      size: 52,
                      radius: 26,
                      icon: Icons.person_rounded,
                    ),
                    title: Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${artist.songCount} 首歌曲'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailPage(
                          controller: _controller,
                          artist: artist,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}
