import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/plugin/provider_capability.dart';
import 'app_toast.dart';
import 'cover_art.dart';

/// Standard song row used by every list in the app.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.controller,
    this.playback,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.showCover = true,
    this.isCurrent = false,
    this.index,
  });

  final Song song;
  final AppController? controller;
  final PlaybackController? playback;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final bool showCover;
  final bool isCurrent;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = isCurrent || (playback?.currentSong?.id == song.id);
    final label = subtitle ??
        [
          if (song.artistLabel.isNotEmpty) song.artistLabel,
          if (song.album?.name.isNotEmpty ?? false) song.album!.name,
        ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: () => showSongActions(context, song),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            if (index != null && !showCover)
              SizedBox(
                width: 34,
                child: Text(
                  '${index! + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (showCover) ...[
              CoverArt(
                url: song.artworkUrl.isNotEmpty ? song.artworkUrl : '',
                size: 48,
                radius: 12,
                icon: song.isLocal
                    ? Icons.audio_file_rounded
                    : Icons.music_note_rounded,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? theme.colorScheme.primary : null,
                    ),
                  ),
                  if (label.isNotEmpty)
                    const SizedBox(height: 2),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailing != null)
              trailing!
            else ...[
              if (song.durationMs > 0)
                Text(
                  formatDuration(Duration(milliseconds: song.durationMs)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              IconButton(
                tooltip: '更多',
                onPressed: () => showSongActions(context, song),
                icon: const Icon(Icons.more_vert_rounded, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> showSongActions(BuildContext context, Song song) async {
    final playbackController = playback ?? controller?.playback;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              ListTile(
                leading: CoverArt(
                  url: song.artworkUrl,
                  size: 48,
                  radius: 12,
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (song.artistLabel.isNotEmpty) song.artistLabel,
                    if (song.album?.name.isNotEmpty ?? false) song.album!.name,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              if (playbackController != null)
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: const Text('下一首播放'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    playbackController.enqueueNext(song);
                    _snack(context, '已加入下一首');
                  },
                ),
              if (playbackController != null)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: const Text('加入播放队列'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    playbackController.addToQueue(song);
                    _snack(context, '已加入队列');
                  },
                ),
              if (song.mediaId != null &&
                  (controller?.supports(
                        song.provider,
                        ProviderCapability.share,
                      ) ??
                      false))
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('分享'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    try {
                      final text = await controller!.shareSong(song);
                      if (text.isEmpty) {
                        AppToast.show('该歌曲没有可分享的链接');
                        return;
                      }
                      await controller!.copyText(text);
                      AppToast.show('分享链接已复制');
                    } catch (e) {
                      AppToast.error('分享失败：$e');
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制歌曲信息'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final text = '${song.title} - ${song.artistLabel}';
                  await Clipboard.setData(ClipboardData(text: text));
                  AppToast.show('已复制');
                },
              ),
              if (playbackController != null &&
                  playbackController.queue.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    '从队列移除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final index = playbackController.queue
                        .indexWhere((item) => item.id == song.id);
                    if (index >= 0) {
                      playbackController.removeFromQueue(index);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
            ),
          ),
        );
      },
    );
  }

  static void _snack(BuildContext context, String message) {
    AppToast.show(message);
  }
}

String formatDuration(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (total >= 3600) {
    final hours = total ~/ 3600;
    final rest = (total % 3600) ~/ 60;
    return '$hours:${rest.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
