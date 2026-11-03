import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Blurred artwork used as a detail-page hero background.
///
/// Works with both remote URLs and local cover files; when the URL is empty the
/// widget simply paints the theme surface so callers never need a conditional.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({
    super.key,
    required this.url,
    required this.child,
    this.fallbackUrls = const [],
    this.blur = 38,
    this.tint = 0.55,
    this.decodeWidth = 520,
  });

  final String url;

  /// Artwork used to build a blurred mosaic when [url] is empty — a playlist
  /// without a cover can borrow the covers of its first tracks.
  final List<String> fallbackUrls;
  final Widget child;
  final double blur;

  /// 0 = image fully covered by the scrim, 1 = image untouched.
  final double tint;
  final int decodeWidth;

  ImageProvider? _provider(String value) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return ResizeImage(NetworkImage(value), width: decodeWidth);
    }
    final file = File(value);
    if (!file.existsSync()) return null;
    return ResizeImage(FileImage(file), width: decodeWidth);
  }

  List<ImageProvider> _mosaic() {
    final seen = <String>{};
    final providers = <ImageProvider>[];
    for (final candidate in [url, ...fallbackUrls]) {
      final value = candidate.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      final provider = _provider(value);
      if (provider != null) providers.add(provider);
      if (providers.length == 4) break;
    }
    return providers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.scaffoldBackgroundColor;
    final scheme = theme.colorScheme;
    final images = _mosaic();
    final dim = (1 - tint).clamp(0.0, 1.0);
    final hasImage = images.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Playlists from a provider often have no artwork at all. Painting a
        // seeded gradient instead of a flat surface keeps those detail pages
        // colourful (and never pure black).
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(scheme.primary, surface, 0.32)!,
                Color.lerp(scheme.tertiary, surface, 0.46)!,
                surface,
              ],
              stops: const [0.0, 0.44, 1.0],
            ),
          ),
          child: hasImage
              ? const SizedBox.shrink()
              : Stack(
                  children: [
                    Positioned(
                      right: -40,
                      top: -60,
                      child: _Glow(
                        color: scheme.primary.withValues(alpha: 0.45),
                        size: 300,
                      ),
                    ),
                    Positioned(
                      left: -50,
                      bottom: -70,
                      child: _Glow(
                        color: scheme.tertiary.withValues(alpha: 0.34),
                        size: 260,
                      ),
                    ),
                  ],
                ),
        ),
        if (hasImage)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
                tileMode: TileMode.decal,
              ),
              child: Transform.scale(
                scale: 1.2,
                child: _CoverCollage(images: images),
              ),
            ),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  surface.withValues(
                    alpha: hasImage
                        ? (0.12 + dim * 0.30).clamp(0.0, 1.0)
                        : 0.02,
                  ),
                  surface.withValues(
                    alpha: hasImage
                        ? (0.30 + dim * 0.55).clamp(0.0, 1.0)
                        : 0.16,
                  ),
                  surface,
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _CoverCollage extends StatelessWidget {
  const _CoverCollage({required this.images});

  final List<ImageProvider> images;

  Widget _image(ImageProvider provider) => Image(
        image: provider,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) return _image(images.first);
    final cells = List<ImageProvider>.from(images);
    while (cells.length < 4) {
      cells.add(images.last);
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(cells[0])),
              Expanded(child: _image(cells[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(cells[2])),
              Expanded(child: _image(cells[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
