import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app/appearance_settings.dart';
import '../../core/app/backdrop_service.dart';

/// Full-bleed page backdrop: a blurred image (cover art, Bing's daily
/// wallpaper, a random illustration or a custom URL) under a themed scrim.
///
/// The image is decoded at viewport size and isolated behind a
/// [RepaintBoundary] so the blur is not recomputed when the page above it
/// animates.
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({
    super.key,
    required this.settings,
    required this.coverUrl,
    required this.child,
  });

  final AppearanceSettings settings;
  final String coverUrl;
  final Widget child;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> {
  static final BackdropService _service = BackdropService();

  String _url = '';
  int _token = 0;
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AppBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettings);
      widget.settings.addListener(_onSettings);
      _resolve();
      return;
    }
    if (widget.settings.backdropSource == BackdropSource.cover &&
        oldWidget.coverUrl != widget.coverUrl) {
      _resolve();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    _resolve();
  }

  Future<void> _resolve() async {
    final settings = widget.settings;
    final key = [
      settings.backdropSource.name,
      settings.backdropUrl,
      settings.backdropRevision,
      if (settings.backdropSource == BackdropSource.cover) widget.coverUrl,
    ].join('|');
    if (key == _lastKey) return;
    _lastKey = key;
    final token = ++_token;
    if (settings.backdropSource == BackdropSource.none) {
      if (mounted) setState(() => _url = '');
      return;
    }
    final url = await _service.resolve(
      settings.backdropSource,
      customUrl: settings.backdropUrl,
      revision: settings.backdropRevision,
      displayWidth: View.of(context).display.size.width,
    );
    if (!mounted || token != _token) return;
    setState(() => _url = url);
  }

  ImageProvider _provider(String url, int cacheWidth) {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return ResizeImage(NetworkImage(url), width: cacheWidth);
    }
    return ResizeImage(FileImage(File(url)), width: cacheWidth);
  }

  /// Quantised decode width: dragging the window edge must not re-decode the
  /// wallpaper on every frame. Buckets scale up to 4K so a maximised window on
  /// a high-DPI monitor is not stuck with a 1080p bitmap.
  int _decodeWidth(double logicalWidth, double dpr) {
    final pixels = logicalWidth * dpr * 1.1;
    if (pixels <= 1280) return 1280;
    if (pixels <= 1600) return 1600;
    if (pixels <= 1920) return 1920;
    if (pixels <= 2560) return 2560;
    if (pixels <= 3200) return 3200;
    return 3840;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    final dim = (1 - settings.backdropOpacity).clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.scaffoldBackgroundColor),
        if (_url.isNotEmpty)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: settings.backdropBlur,
                sigmaY: settings.backdropBlur,
                tileMode: TileMode.decal,
              ),
              child: Transform.scale(
                // Blur pulls pixels inward; a slight overscan hides the edge.
                scale: 1.12,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 700),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  // The default AnimatedSwitcher Stack is loose, which would
                  // leave the decoded bitmap at its intrinsic size and expose
                  // empty bands after the window is enlarged. Expand instead.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      ?currentChild,
                    ],
                  ),
                  child: Image(
                    key: ValueKey(_url),
                    image: _provider(_url, _decodeWidth(width, dpr)),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
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
                  theme.scaffoldBackgroundColor.withValues(
                    alpha: (0.10 + dim * 0.82).clamp(0.0, 1.0),
                  ),
                  theme.scaffoldBackgroundColor.withValues(
                    alpha: (0.24 + dim * 0.76).clamp(0.0, 1.0),
                  ),
                  theme.scaffoldBackgroundColor.withValues(
                    alpha: (0.42 + dim * 0.58).clamp(0.0, 1.0),
                  ),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
