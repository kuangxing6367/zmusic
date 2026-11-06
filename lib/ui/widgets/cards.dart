import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/media/models.dart';
import 'cover_art.dart';

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.width = 156,
    this.subtitle,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final double width;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(theme),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle ??
                  (playlist.trackCount > 0
                      ? '${playlist.trackCount} 首'
                      : (playlist.sourceName.isNotEmpty
                          ? playlist.sourceName
                          : '')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(ThemeData theme) {
    return Stack(
      children: [
        CoverArtFrame(
          url: playlist.coverUrl,
          size: width,
          radius: 18,
          icon: Icons.queue_music_rounded,
        ),
        if (playlist.subscribed)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '已收藏',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
    this.width = 156,
  });

  final Album album;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Grid cells can be narrower than the preferred width (phones); use
        // whatever the cell gives us so albums fill the row.
        final maxHeight = constraints.maxHeight.isFinite
            ? math.max(80.0, constraints.maxHeight - 54)
            : double.infinity;
        final cardWidth = constraints.maxWidth.isFinite
            ? math.min(math.min(width, constraints.maxWidth), maxHeight)
            : width;
        return SizedBox(
          width: cardWidth,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoverArtFrame(
                  url: album.coverUrl,
                  size: cardWidth,
                  radius: 18,
                  icon: Icons.album_rounded,
                ),
                const SizedBox(height: 8),
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  album.artistLabel.isNotEmpty
                      ? album.artistLabel
                      : '${album.trackCount} 首',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CoverArtFrame extends StatelessWidget {
  const CoverArtFrame({
    super.key,
    required this.url,
    required this.size,
    required this.radius,
    required this.icon,
  });

  final String url;
  final double size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CoverArt(url: url, size: size, radius: radius, icon: icon);
  }
}
