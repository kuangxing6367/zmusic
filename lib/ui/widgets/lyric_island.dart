import 'package:flutter/material.dart';

import '../../core/lyric/lyric_models.dart';
import '../../core/playback/playback_controller.dart';
import 'cover_art.dart';

/// A Dynamic-Island style capsule pinned to the top of the screen, showing the
/// lyric line that is being sung right now.
///
/// Third-party apps cannot draw inside another app's island, so this renders a
/// capsule just below the status bar / cutout (`SafeArea` + view padding) with
/// the same silhouette and motion: it widens when a line arrives, swaps text
/// with a short fade, and taps through to the player.
class LyricIsland extends StatefulWidget {
  const LyricIsland({super.key, required this.playback, this.onTap});

  final PlaybackController playback;
  final VoidCallback? onTap;

  @override
  State<LyricIsland> createState() => _LyricIslandState();
}

class _LyricIslandState extends State<LyricIsland> {
  String _text = '';
  String _translation = '';
  String _artwork = '';
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant LyricIsland oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(_sync);
      widget.playback.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.playback.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final playback = widget.playback;
    final groups = playback.lyrics.groups;
    final index = playback.lyricIndex;
    LyricGroup? group;
    if (index >= 0 && index < groups.length) {
      group = groups[index];
    } else if (groups.isNotEmpty && playback.positionMs > 0) {
      // Between groups the index can be -1; keep the upcoming line visible.
      final next = groups.firstWhere(
        (g) => g.startMs >= playback.positionMs,
        orElse: () => groups.last,
      );
      group = next;
    }
    final text = group?.line.text.trim() ?? '';
    final translation = group?.line.translation.trim() ?? '';
    final artwork = playback.currentSong?.artworkUrl ?? '';
    final playing = playback.playing;
    if (text == _text &&
        translation == _translation &&
        artwork == _artwork &&
        playing == _playing) {
      return;
    }
    setState(() {
      _text = text;
      _translation = translation;
      _artwork = artwork;
      _playing = playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasText = _text.isNotEmpty;

    return IgnorePointer(
      ignoring: !hasText,
      child: AnimatedOpacity(
        opacity: hasText ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: hasText ? 16 : 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: const Color(0xF20A0B10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_artwork.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CoverArt(url: _artwork, size: 26, radius: 7),
                    ),
                    const SizedBox(width: 9),
                  ] else ...[
                    _Pulse(playing: _playing, color: scheme.primary),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_text),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (_translation.isNotEmpty)
                            Text(
                              _translation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 11,
                                height: 1.25,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Pulse(playing: _playing, color: scheme.primary),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.playback.togglePlayPause,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small three-bar equalizer that only animates while playing.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.35;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(6, 0.45 + t * 0.55),
            const SizedBox(width: 2),
            _bar(12, 1.0 - t * 0.55),
            const SizedBox(width: 2),
            _bar(8, 0.55 + t * 0.45),
          ],
        );
      },
    );
  }

  Widget _bar(double height, double factor) {
    return Container(
      width: 2.4,
      height: height * factor.clamp(0.35, 1.0),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
