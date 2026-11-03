import 'package:flutter/material.dart';

import '../../core/playback/playback_controller.dart';
import 'cover_art.dart';

Future<void> showQueueSheet(
  BuildContext context,
  PlaybackController playback,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.72,
        child: AnimatedBuilder(
          animation: playback,
          builder: (context, _) {
            final theme = Theme.of(sheetContext);
            final queue = playback.queue;
            final current = playback.currentIndex;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.queue_music_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '播放队列',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${queue.length} 首',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (queue.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        '队列是空的',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final song = queue[index];
                        final active = index == current;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            playback.selectQueueIndex(index);
                            Navigator.of(sheetContext).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 26,
                                  child: active
                                      ? Icon(
                                          Icons.graphic_eq_rounded,
                                          size: 18,
                                          color: theme.colorScheme.primary,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                ),
                                CoverArt(
                                  url: song.artworkUrl,
                                  size: 42,
                                  radius: 10,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: active
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: active
                                              ? theme.colorScheme.primary
                                              : null,
                                        ),
                                      ),
                                      if (song.artistLabel.isNotEmpty)
                                        Text(
                                          song.artistLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme.colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '移除',
                                  onPressed: () =>
                                      playback.removeFromQueue(index),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}
