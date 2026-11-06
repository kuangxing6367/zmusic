import 'package:flutter/material.dart';

import '../../core/lyric/lyric_models.dart';
import '../../core/playback/playback_controller.dart';
import 'cover_art.dart';

/// In-app Dynamic-Island style capsule pinned below the status bar.
///
/// By default it shows the song title and artist. Turning on "capsule lyrics"
/// switches it to the line being sung (with translation), which is what the
/// system provider shows on supported devices.
class LyricIsland extends StatefulWidget {
  const LyricIsland({
    super.key,
    required this.playback,
    this.onTap,
    this.showLyrics = false,
  });

  final PlaybackController playback;
  final VoidCallback? onTap;
  final bool showLyrics;

  @override
  State<LyricIsland> createState() => _LyricIslandState();
}

class _LyricIslandState extends State<LyricIsland> {
  String _title = '';
  String _subtitle = '';
  String _artwork = '';
  bool _playing = false;
  bool _hasContent = false;

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
    if (oldWidget.showLyrics != widget.showLyrics) _sync();
  }

  @override
  void dispose() {
    widget.playback.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final playback = widget.playback;
    final song = playback.currentSong;
    if (song == null) {
      if (!_hasContent) return;
      setState(() {
        _hasContent = false;
        _title = '';
        _subtitle = '';
      });
      return;
    }

    var title = song.title;
    var subtitle = song.artistLabel;
    if (widget.showLyrics) {
      final groups = playback.lyrics.groups;
      final index = playback.lyricIndex;
      LyricGroup? group;
      if (index >= 0 && index < groups.length) {
        group = groups[index];
      } else if (groups.isNotEmpty) {
        group = groups.firstWhere(
          (g) => g.startMs >= playback.positionMs,
          orElse: () => groups.last,
        );
      }
      final text = group?.line.text.trim() ?? '';
      if (text.isNotEmpty) {
        title = text;
        subtitle = group?.line.translation.trim() ?? '';
      }
    }

    final artwork = song.artworkUrl;
    final playing = playback.playing;
    if (title == _title &&
        subtitle == _subtitle &&
        artwork == _artwork &&
        playing == _playing &&
        _hasContent) {
      return;
    }
    setState(() {
      _title = title;
      _subtitle = subtitle;
      _artwork = artwork;
      _playing = playing;
      _hasContent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return IgnorePointer(
      ignoring: !_hasContent,
      child: AnimatedOpacity(
        opacity: _hasContent ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: Ink(
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
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(24),
                splashColor: scheme.primary.withValues(alpha: 0.22),
                highlightColor: scheme.primary.withValues(alpha: 0.10),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
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
                            key: ValueKey('$_title|$_subtitle'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              if (_subtitle.isNotEmpty)
                                Text(
                                  _subtitle,
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
                      _TapIcon(
                        playing: _playing,
                        onTap: widget.playback.togglePlayPause,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TapIcon extends StatelessWidget {
  const _TapIcon({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      splashColor: Colors.white.withValues(alpha: 0.16),
      highlightColor: Colors.white.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.88),
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
