import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../../core/playback/playback_controller.dart';
import 'cover_art.dart';

/// Persistent compact player shown above the navigation bar/rail.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final AppController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (!controller.initialized || controller.initError.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final playback = controller.playback;
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final song = playback.currentSong;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: song == null
              ? const SizedBox.shrink(key: ValueKey('mini-empty'))
              : _bar(context, playback, song),
        );
      },
    );
  }

  Widget _bar(BuildContext context, PlaybackController playback, Song song) {
    final theme = Theme.of(context);
    final duration = math.max(playback.durationMs, song.durationMs);
    final progress = duration <= 0
        ? 0.0
        : (playback.positionMs / duration).clamp(0.0, 1.0);
    return Padding(
      key: const ValueKey('mini-player'),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.85,
        ),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniProgress(
                progress: progress,
                loading: playback.resolving,
                color: theme.colorScheme.primary,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                child: Row(
                  children: [
                    Hero(
                      tag: 'now-playing-cover',
                      child: CoverArt(
                        url: song.artworkUrl,
                        size: 44,
                        radius: 11,
                        icon: song.isLocal
                            ? Icons.audio_file_rounded
                            : Icons.music_note_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (song.artistLabel.isNotEmpty)
                            Text(
                              song.artistLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: playback.togglePlayPause,
                      icon: playback.resolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              playback.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    IconButton(
                      onPressed: playback.hasNext ? playback.next : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini progress: a 450 ms OutCubic catch-up after seeks, plus a
/// sweeping indeterminate bar while the next stream is being resolved.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({
    required this.progress,
    required this.loading,
    required this.color,
  });

  final double progress;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: Colors.transparent,
        color: color,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        color: color,
      ),
    );
  }
}
