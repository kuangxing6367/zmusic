import 'dart:io';

import 'package:flutter/material.dart';

/// Artwork renderer for remote URLs, local cover files and placeholders.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url = '',
    this.size = 56,
    this.radius = 12,
    this.icon = Icons.music_note_rounded,
    this.heroTag,
  });

  final String url;
  final double size;
  final double radius;
  final IconData icon;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final cachePixels = (size * ratio).round().clamp(1, 4096);
    final trimmed = url.trim();
    Widget image;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      image = Image.network(
        trimmed,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cachePixels,
        cacheHeight: cachePixels,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: _fadeIn,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else if (trimmed.isNotEmpty) {
      final file = File(trimmed);
      if (file.existsSync()) {
        image = Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cachePixels,
          cacheHeight: cachePixels,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: _fadeIn,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      } else {
        image = const SizedBox.shrink();
      }
    } else {
      image = const SizedBox.shrink();
    }

    final content = Stack(
      fit: StackFit.expand,
      children: [_placeholder(scheme), image],
    );

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: content),
    );
    if (heroTag == null) return clipped;
    return Hero(tag: heroTag!, child: clipped);
  }

  /// QPlayer's CoverImage settles in over 260 ms instead of popping.
  Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.9),
            scheme.tertiaryContainer.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.4,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
