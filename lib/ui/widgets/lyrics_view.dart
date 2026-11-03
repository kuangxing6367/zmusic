import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/lyric/lyric_models.dart';

/// Scrolling lyric view with syllable-level karaoke highlighting.
///
/// The motion model mirrors QPlayer's Skia renderer (which ports AMLL):
///
/// * the active line is pinned at 35% of the column height;
/// * the column is driven by a spring (k = 65, damping = 11) instead of a
///   fixed-duration tween, so consecutive line changes blend into one motion;
/// * lines below the active one trail it (0.05 s per line, decaying), which is
///   the Apple Music "wave" as the column advances;
/// * the highlight itself is a time curve (fade in 450 ms before the line,
///   fade out 100 ms after it), so lines light up and dim continuously rather
///   than switching on an index boundary;
/// * the coarse backend position (mpv reports every ~200 ms) is extrapolated on
///   a frame clock, so both the sweep and the scroll are smooth at 60 fps.
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positionMs,
    required this.activeIndex,
    required this.onSeek,
    this.playing = true,
    this.emptyLabel = '暂无歌词',
    this.fontSize = 20,
    this.fontWeight = FontWeight.w500,
    this.lineSpacing = 1.6,
    this.alignment = 'duet',
    this.showTranslation = true,
    this.showRomanization = true,
    this.shadow = true,
    this.fontFamily,
  });

  final Lyrics lyrics;
  final int positionMs;
  final int activeIndex;
  final ValueChanged<int> onSeek;
  final bool playing;
  final String emptyLabel;
  final double fontSize;
  final FontWeight fontWeight;
  final double lineSpacing;
  final String alignment;
  final bool showTranslation;
  final bool showRomanization;
  final bool shadow;
  final String? fontFamily;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricRow {
  const _LyricRow.group(this.groupIndex)
      : nextGroup = -1,
        interludeStartMs = 0,
        interludeEndMs = 0;

  const _LyricRow.interlude(
    this.nextGroup,
    this.interludeStartMs,
    this.interludeEndMs,
  ) : groupIndex = -1;

  final int groupIndex;
  final int nextGroup;
  final int interludeStartMs;
  final int interludeEndMs;

  bool get isInterlude => groupIndex < 0;
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  // ---- Motion constants, lifted from QPlayer's LyricRenderer ---------------
  static const double _anchor = 0.35; // active line sits above the centre
  static const double _stiffness = 65; // AMLL computeLinePosYSpringParams
  static const double _damping = 11; // zeta ~ 0.68: one soft overshoot
  static const double _seekStiffness = 180;
  static const double _seekDamping = 28;
  static const double _edgePad = 0.7; // fraction of the column
  static const double _snapDistance = 420; // px; beyond this, jump cut
  static const double _seekDistance = 90; // px; beyond this, firm spring
  static const int _fadeInMs = 600;
  static const int _fadeInLeadMs = 450;
  static const int _fadeOutMs = 350;
  static const int _fadeOutDelayMs = 100;

  // ---- Interlude dots (ported from AMLL / QPlayer LyricRenderer) -----------
  static const int _interludeThresholdMs = 2000; // min gap to show dots
  static const int _interludeTrimMs = 250; // next line trims the tail
  static const double _interludeRowHeight = 40;
  static const double _dotRadius = 6.8;
  static const double _dotSpacing = 27;

  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_onTick);

  List<GlobalKey> _keys = const [];
  List<_LyricRow> _rows = const [];
  List<int> _groupRow = const [];
  int _row = 0;

  // Wall-clock position extrapolation.
  int _anchorMs = 0;
  Duration _anchorElapsed = Duration.zero;
  Duration _lastTick = Duration.zero;
  double _positionMs = 0;

  // Spring state for the column offset.
  double _offset = 0;
  double _velocity = 0;
  double _target = 0;
  bool _firmSpring = false;
  bool _snapPending = false;
  bool _retargetPending = false;
  double _lastViewport = 0;
  int _retargetTries = 0;

  // Per-line trailing offsets (the cascade below the active line).
  final Map<int, double> _trail = <int, double>{};
  int _trailAnchor = -2;

  // Set while the user is scrolling by hand; auto-follow resumes after it.
  Duration? _resumeAt;

  int _maxTimeMs = 0;

  @override
  void initState() {
    super.initState();
    _positionMs = widget.positionMs.toDouble();
    _anchorMs = widget.positionMs;
    _rebuildRows();
    _syncMaxTime();
    _retargetSoon();
    if (widget.playing) _startTicker();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.lyrics != widget.lyrics) {
      _rebuildRows();
      _syncMaxTime();
      _snapPending = true;
      _trail.clear();
      _offset = 0;
      _velocity = 0;
      _retargetSoon();
    }

    if (widget.positionMs != oldWidget.positionMs) {
      _syncPosition(widget.positionMs);
    }

    if (widget.activeIndex != oldWidget.activeIndex) {
      _retargetSoon();
      _startTicker();
    }

    if (widget.playing != oldWidget.playing) {
      if (widget.playing) {
        _startTicker();
      } else {
        _ensureTicker();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- setup ---------------------------------------------------------------

  /// Flattens the groups into rows, inserting a dots row before a line that
  /// follows a gap of at least [_interludeThresholdMs] (the intro counts too).
  void _rebuildRows() {
    final groups = widget.lyrics.groups;
    final rows = <_LyricRow>[];
    final groupRow = List<int>.filled(groups.length, 0);
    for (var i = 0; i < groups.length; i++) {
      final previousEnd = i == 0 ? 0 : groups[i - 1].endMs;
      final start = groups[i].startMs;
      if (start - previousEnd >= _interludeThresholdMs) {
        rows.add(
          _LyricRow.interlude(i, previousEnd, start - _interludeTrimMs),
        );
      }
      groupRow[i] = rows.length;
      rows.add(_LyricRow.group(i));
    }
    _rows = rows;
    _groupRow = groupRow;
    _keys = List.generate(rows.length, (_) => GlobalKey());
    _row = _rowForPosition(_positionMs);
  }

  /// Row that the column should follow at [positionMs]: the sung line, or the
  /// dots slot while a long instrumental gap is running.
  int _rowForPosition(double positionMs) {
    if (_rows.isEmpty) return 0;
    final groups = widget.lyrics.groups;
    final position = positionMs.round();
    final group = widget.lyrics.indexAt(position);
    if (group < 0) {
      // Intro: the dots row sits before the first line.
      return _rows.first.isInterlude ? 0 : _groupRow[0];
    }
    if (group + 1 < groups.length) {
      final gapStart = groups[group].endMs;
      final nextStart = groups[group + 1].startMs;
      if (nextStart - gapStart >= _interludeThresholdMs &&
          position >= gapStart &&
          position < nextStart - _interludeTrimMs) {
        return _groupRow[group + 1] - 1;
      }
    }
    return _groupRow[group];
  }

  void _syncMaxTime() {
    final groups = widget.lyrics.groups;
    if (groups.isEmpty) {
      _maxTimeMs = 0;
      return;
    }
    _maxTimeMs = groups.last.endMs + 1000;
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _anchorMs = widget.positionMs;
    _positionMs = widget.positionMs.toDouble();
    _anchorElapsed = Duration.zero;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  /// Restart the ticker only when there is still something to animate.
  void _ensureTicker() {
    if (_ticker.isActive) return;
    final delta = (_target - _offset).abs();
    if (delta > 0.2 || _trail.isNotEmpty || _resumeAt != null) {
      _startTicker();
    }
  }

  void _syncPosition(int ms) {
    if (!_ticker.isActive) {
      _anchorMs = ms;
      _positionMs = ms.toDouble();
      return;
    }
    final predicted =
        _anchorMs + (_lastTick - _anchorElapsed).inMicroseconds / 1000.0;
    final diff = ms - predicted;
    if (diff.abs() > 400) {
      // A seek (or the player resumed from a long stall): anchor again.
      _anchorMs = ms;
      _anchorElapsed = _lastTick;
      _positionMs = ms.toDouble();
    } else {
      // Nudge a quarter of the residual every update: the sweep stays smooth
      // while the extrapolation cannot drift away from the real clock.
      final corrected = predicted + diff * 0.25;
      _anchorMs = corrected.round();
      _anchorElapsed = _lastTick;
      _positionMs = corrected;
    }
  }

  // ---- scroll targeting ----------------------------------------------------

  void _retargetSoon() {
    _retargetPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_retargetPending) return;
      _retargetNow();
    });
  }

  void _retargetNow() {
    _retargetPending = false;
    if (_keys.isEmpty) return;
    // The row depends on the playhead: during a long gap the dots slot becomes
    // the anchor, so the spring carries them to the centre like a lyric line.
    _row = _rowForPosition(_positionMs);
    final index = _row.clamp(0, _keys.length - 1);
    final context = _keys[index].currentContext;
    if (context == null || !_scroll.hasClients) {
      // The target line is not laid out yet: a far seek can land outside the
      // builder's cache window. Jump to a proportional guess so it gets built,
      // then aim precisely on the next frame.
      _retargetTries++;
      if (_retargetTries > 2 && _scroll.hasClients) {
        final position = _scroll.position;
        final count = math.max(1, _keys.length - 1);
        final approx =
            position.maxScrollExtent * (index / count);
        _velocity = 0;
        _offset = approx.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        _applyOffset(_offset, force: true);
      }
      _retargetSoon();
      return;
    }
    final object = context.findRenderObject();
    if (object == null) {
      _retargetSoon();
      return;
    }
    _retargetTries = 0;
    final viewport = RenderAbstractViewport.of(object);
    final reveal = viewport.getOffsetToReveal(object, _anchor);
    final position = _scroll.position;
    final target = reveal.offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    final delta = target - _offset;
    if (_snapPending || delta.abs() > _snapDistance) {
      _snapPending = false;
      _offset = target;
      _velocity = 0;
      _firmSpring = false;
      _trail.clear();
      _applyOffset(target, force: true);
    } else if (delta.abs() > _seekDistance) {
      _firmSpring = true;
    }
    _target = target;
    _ensureTicker();
  }

  void _applyOffset(double value, {bool force = false}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final clamped = value.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (force || (_scroll.offset - clamped).abs() > 0.01) {
      _scroll.jumpTo(clamped);
    }
    if (force) _offset = clamped;
  }

  void _pauseAutoFollow() {
    // Hand-driven scroll (drag or wheel): stop fighting it, then glide back to
    // the active line once the user has been idle for a moment.
    _resumeAt = _lastTick + const Duration(milliseconds: 2200);
    _velocity = 0;
    _trail.clear();
    _startTicker();
  }

  // ---- frame loop ----------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dtUs = (elapsed - _lastTick).inMicroseconds;
    _lastTick = elapsed;
    final dt = (dtUs / 1000000.0).clamp(0.0, 0.05);
    if (dt <= 0) {
      setState(() {});
      return;
    }

    if (widget.playing) {
      final predicted =
          _anchorMs + (elapsed - _anchorElapsed).inMicroseconds / 1000.0;
      _positionMs = predicted.clamp(0.0, _maxTimeMs.toDouble());
    } else {
      _positionMs = _anchorMs.toDouble();
    }

    // Crossing into / out of an interlude swaps the scroll target even though
    // the active lyric line does not change.
    if (_resumeAt == null) {
      final row = _rowForPosition(_positionMs);
      if (row != _row) _retargetNow();
    }

    final resumeAt = _resumeAt;
    if (resumeAt != null) {
      // The user is driving the column; keep the spring pinned to reality so it
      // does not snap back mid-gesture.
      if (_scroll.hasClients) {
        _offset = _scroll.offset;
        _target = _offset;
      }
      _velocity = 0;
      if (elapsed >= resumeAt) {
        _resumeAt = null;
        _firmSpring = true;
        _trail.clear();
        _retargetNow();
      }
    }

    var moving = false;
    if (_resumeAt == null) {
      final delta = _target - _offset;
      if (delta.abs() > 0.05 || _velocity.abs() > 0.5) {
        final k = _firmSpring ? _seekStiffness : _stiffness;
        final c = _firmSpring ? _seekDamping : _damping;
        final acceleration = k * delta - c * _velocity;
        _velocity += acceleration * dt;
        _offset += _velocity * dt;
        moving = true;
        if (delta.abs() < 0.2 && _velocity.abs() < 4) {
          _offset = _target;
          _velocity = 0;
          _firmSpring = false;
          moving = false;
        } else {
          _applyOffset(_offset);
        }
      }
    }

    _advanceTrail(dt);

    if (_retargetPending) _retargetNow();

    setState(() {});

    if (!widget.playing &&
        !moving &&
        _resumeAt == null &&
        !_retargetPending &&
        _trailCleared()) {
      _ticker.stop();
    }
  }

  void _advanceTrail(double dt) {
    if (_resumeAt != null) {
      _trail.clear();
      return;
    }
    final active = _row;
    if (active != _trailAnchor) {
      _trailAnchor = active;
      if (active >= 0) {
        for (var i = active + 1; i <= active + 26; i++) {
          _trail.putIfAbsent(i, () => _offset);
        }
      }
    }
    if (_trail.isEmpty) return;
    final remove = <int>[];
    for (final entry in _trail.entries) {
      final distance = entry.key - active;
      if (distance <= 0 || distance > 30) {
        remove.add(entry.key);
        continue;
      }
      // Apple's Specs.lineDelay = 0.05 s per line, decaying with distance.
      final tau = (0.05 * distance).clamp(0.05, 0.36);
      final factor = 1 - math.exp(-dt / tau);
      final next = entry.value + (_offset - entry.value) * factor;
      _trail[entry.key] = (_offset - next).abs() < 0.25 ? _offset : next;
    }
    for (final index in remove) {
      _trail.remove(index);
    }
  }

  bool _trailCleared() => _trail.values
      .every((value) => (value - _offset).abs() < 0.5);

  double _trailOffset(int index) {
    if (index <= _row) return 0;
    final value = _trail[index];
    if (value == null) return 0;
    return (_offset - value).clamp(0.0, 64.0);
  }

  // ---- styling -------------------------------------------------------------

  static double _smoothStep(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double _activeK(LyricGroup group) {
    final position = _positionMs;
    final fadeInStart = group.startMs - _fadeInLeadMs;
    final fadeInEnd = fadeInStart + _fadeInMs;
    if (position < fadeInStart) return 0;
    if (position < fadeInEnd) {
      return _smoothStep((position - fadeInStart) / _fadeInMs);
    }
    final fadeOutStart = group.endMs + _fadeOutDelayMs;
    final fadeOutEnd = fadeOutStart + _fadeOutMs;
    if (position < fadeOutStart) return 1;
    if (position >= fadeOutEnd) return 0;
    return 1 - _smoothStep((position - fadeOutStart) / _fadeOutMs);
  }

  /// Emphasis scale: pops with a small overshoot the moment the line becomes
  /// current, so it grows while the column starts moving (not before it).
  double _scaleK(LyricGroup group) {
    final position = _positionMs;
    if (position < group.startMs) return 0;
    const entranceMs = 420.0;
    final entrance = (position - group.startMs) / entranceMs;
    if (entrance < 1) return _easeOutBack(entrance);
    final fadeOutStart = group.endMs + _fadeOutDelayMs;
    if (position < fadeOutStart) return 1;
    final out = (position - fadeOutStart) / _fadeOutMs;
    if (out >= 1) return 0;
    return 1 - _smoothStep(out);
  }

  static double _easeOutBack(double value) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final shifted = value - 1;
    return 1 + c3 * shifted * shifted * shifted + c1 * shifted * shifted;
  }

  static double _easeInOutBack(double value) {
    const c1 = 1.70158;
    const c2 = c1 * 1.525;
    if (value < 0.5) {
      final x = 2 * value;
      return x * x * ((c2 + 1) * x - c2) / 2;
    }
    final x = 2 * value - 2;
    return (x * x * ((c2 + 1) * x + c2) + 2) / 2;
  }

  static double _easeOutExpo(double value) {
    if (value >= 1) return 1;
    return 1 - math.pow(2, -10 * value).toDouble();
  }

  // ---- interlude dots ------------------------------------------------------

  Widget _interludeRow(
    BuildContext context,
    int index,
    _LyricRow row,
    ThemeData theme,
  ) {
    final nextLine = widget.lyrics.groups[row.nextGroup].line;
    return SizedBox(
      key: _keys.length > index ? _keys[index] : null,
      height: _interludeRowHeight,
      child: Align(
        alignment: _scaleAlignment(nextLine),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _interludeDots(row, theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _interludeDots(_LyricRow row, Color color) {
    final start = row.interludeStartMs.toDouble();
    final end = row.interludeEndMs.toDouble();
    final duration = end - start;
    final position = _positionMs;
    if (duration <= 0 || position < start || position > end) {
      return const SizedBox.shrink();
    }
    final elapsed = position - start;
    final remaining = end - position;

    // Phase windows shrink with short gaps, so a 2.5 s verse pause still gets
    // a fade-in / hold / exit instead of only a fade.
    final fadeInEnd = math.min(600.0, duration * 0.20);
    final scaleRamp = math.min(1500.0, duration * 0.35);
    final exitScale = math.min(750.0, duration * 0.20);
    final exitOpacity = math.min(375.0, duration * 0.10);
    final breathe = duration / (duration / 1500.0).ceil();

    var scale = 1.0;
    var opacity = 1.0;
    // One sine per ~1.5 s breath, +/-5%.
    scale *= math.sin(1.5 * math.pi - (elapsed / breathe) * 2.0) / 20.0 + 1.0;
    if (elapsed < scaleRamp) scale *= _easeOutExpo(elapsed / scaleRamp);
    if (elapsed < fadeInEnd) {
      opacity *= (elapsed / fadeInEnd).clamp(0.0, 1.0);
    }
    if (remaining < exitScale) {
      scale *= 1 - _easeInOutBack((exitScale - remaining) / exitScale / 2);
    }
    if (remaining < exitOpacity) {
      opacity *= (remaining / exitOpacity).clamp(0.0, 1.0);
    }
    final dotsDuration = math.max(1.0, duration - exitScale);
    scale = math.max(0.0, scale) * 0.7;
    if (scale < 0.01) return const SizedBox.shrink();

    double dotOpacity(int index) {
      final ramp =
          ((elapsed - dotsDuration * index / 3.0) * 3.0 / dotsDuration) * 0.75;
      return (ramp.clamp(0.25, 1.0) * opacity).clamp(0.0, 1.0);
    }

    return SizedBox(
      width: _dotRadius * 2 + _dotSpacing * 2,
      height: _dotRadius * 2,
      child: Transform.scale(
        scale: scale,
        child: Stack(
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: i * _dotSpacing,
                top: 0,
                child: Container(
                  width: _dotRadius * 2,
                  height: _dotRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: dotOpacity(i)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  CrossAxisAlignment _crossAxisFor(LyricLine line) {
    switch (widget.alignment) {
      case 'left':
        return CrossAxisAlignment.start;
      case 'center':
        return CrossAxisAlignment.center;
      case 'right':
        return CrossAxisAlignment.end;
      default:
        return line.isDuetRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;
    }
  }

  Alignment _scaleAlignment(LyricLine line) {
    switch (widget.alignment) {
      case 'center':
        return Alignment.center;
      case 'right':
        return Alignment.centerRight;
      case 'left':
        return Alignment.centerLeft;
      default:
        return line.isDuetRight ? Alignment.centerRight : Alignment.centerLeft;
    }
  }

  TextAlign get _textAlign => switch (widget.alignment) {
        'left' => TextAlign.left,
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.start,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.lyrics.groups;
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              widget.emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if ((height - _lastViewport).abs() > 1) {
          _lastViewport = height;
          _retargetSoon();
        }
        return ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.09, 0.89, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Listener(
            onPointerMove: (event) {
              if (event.buttons != 0) _pauseAutoFollow();
            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) _pauseAutoFollow();
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: ListView.builder(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  vertical: height * _edgePad,
                  horizontal: 8,
                ),
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final child = row.isInterlude
                      ? _interludeRow(context, index, row, theme)
                      : _line(
                          context,
                          index,
                          groups[row.groupIndex],
                          theme,
                        );
                  return Transform.translate(
                    offset: Offset(0, _trailOffset(index)),
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    int index,
    LyricGroup group,
    ThemeData theme,
  ) {
    final line = group.line;
    final activeK = _activeK(group);
    final scaleK = _scaleK(group);
    final scale = 0.97 + 0.17 * scaleK;
    final idle = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.42);
    final hot = theme.colorScheme.onSurface.withValues(alpha: 0.94);
    final base = Color.lerp(idle, hot, activeK)!;
    final accent = theme.colorScheme.primary;

    final shadows = widget.shadow
        ? [
            Shadow(
              blurRadius: 10 + 8 * activeK,
              color: Colors.black.withValues(alpha: 0.35 + 0.35 * activeK),
              offset: const Offset(0, 1),
            ),
          ]
        : null;

    return Container(
      key: _keys.length > index ? _keys[index] : null,
      margin: EdgeInsets.symmetric(vertical: 10 * widget.lineSpacing),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSeek(line.startMs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Transform.scale(
            scale: scale,
            alignment: _scaleAlignment(line),
            child: Column(
              crossAxisAlignment: _crossAxisFor(line),
              children: [
                _karaokeLine(
                  line,
                  base: base,
                  accent: accent,
                  activeK: activeK,
                  shadows: shadows,
                  theme: theme,
                ),
                for (final background in group.backgrounds)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 5,
                      left: 36,
                      right: 12,
                    ),
                    child: Align(
                      alignment: line.isDuetRight
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: _karaokeLine(
                        background,
                        base: base.withValues(
                          alpha: (base.a * 0.7).clamp(0.0, 1.0),
                        ),
                        accent: accent.withValues(alpha: 0.75),
                        activeK: activeK,
                        shadows: shadows,
                        theme: theme,
                        small: true,
                      ),
                    ),
                  ),
                if (widget.showTranslation &&
                    line.translation.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line.translation,
                      textAlign: _textAlign,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: widget.fontSize * 0.64,
                        fontFamily: widget.fontFamily,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.42 + 0.42 * activeK,
                        ),
                        height: 1.35,
                      ),
                    ),
                  ),
                if (widget.showRomanization &&
                    line.romanization.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line.romanization,
                      textAlign: _textAlign,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: widget.fontSize * 0.54,
                        fontFamily: widget.fontFamily,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.34 + 0.36 * activeK,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Fraction of the line's *width* that has been sung, so the highlight sweeps
  /// through the glyphs (a half-sung character is half lit) instead of the
  /// whole line changing colour at once.
  double _sweepProgress(LyricLine line) {
    final syllables = line.syllables;
    if (syllables.isEmpty) return 0;
    var total = 0;
    for (final syllable in syllables) {
      total += syllable.text.runes.length;
    }
    if (total == 0) return 0;
    final position = _positionMs;
    var done = 0;
    for (final syllable in syllables) {
      final length = syllable.text.runes.length;
      final start = syllable.startMs.toDouble();
      final end = start + syllable.durationMs;
      if (position < start) return done / total;
      if (position < end) {
        final fill = syllable.durationMs <= 0
            ? 1.0
            : ((position - start) / syllable.durationMs).clamp(0.0, 1.0);
        return (done + length * fill) / total;
      }
      done += length;
    }
    return 1;
  }

  Widget _karaokeLine(
    LyricLine line, {
    required Color base,
    required Color accent,
    required double activeK,
    required List<Shadow>? shadows,
    required ThemeData theme,
    bool small = false,
  }) {
    final baseSize = small ? widget.fontSize * 0.64 : widget.fontSize;

    // The unsung part of the active line stays clearly dimmer than the lit
    // part, otherwise the sweep is invisible (white on white). This mirrors
    // QPlayer: the whole row is drawn, then only the sung part is raised.
    final rest = small
        ? base.withValues(alpha: base.a * 0.75)
        : theme.colorScheme.onSurfaceVariant
            .withValues(alpha: 0.38 + 0.16 * activeK);
    final restStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: baseSize,
      height: 1.4,
      fontFamily: widget.fontFamily,
      fontWeight: widget.fontWeight,
      color: rest,
      shadows: shadows,
    );

    final progress = _sweepProgress(line).clamp(0.0, 1.0);
    if (activeK <= 0.01) {
      return Text(line.text, textAlign: _textAlign, style: restStyle);
    }

    // Saturated highlight: the dark-scheme primary is a very light tone, which
    // would read as white next to the dim row. Pulling it toward the container
    // tone keeps the sweep visibly coloured for any seed the user picks.
    final lit = theme.brightness == Brightness.dark
        ? Color.lerp(accent, theme.colorScheme.primaryContainer, 0.30)!
        : accent;
    if (progress >= 1) {
      return Text(
        line.text,
        textAlign: _textAlign,
        style: restStyle?.copyWith(
          color: Color.lerp(rest, lit, activeK),
        ),
      );
    }
    if (progress <= 0) {
      return Text(line.text, textAlign: _textAlign, style: restStyle);
    }

    // One masked pass on top of the dim row: a fully opaque band up to the
    // current syllable, then a ~12 px fade, then transparent. ShaderMask
    // resolves that per pixel, so half of a single glyph can be lit.
    return Stack(
      children: [
        Text(line.text, textAlign: _textAlign, style: restStyle),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) {
            final width = math.max(1.0, rect.width);
            final fade = (12.0 / width).clamp(0.003, 0.10);
            final edgeIn = (progress - fade).clamp(0.0, 1.0);
            final edgeOut = (progress + fade).clamp(0.0, 1.0);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                lit,
                lit,
                lit.withValues(alpha: 0),
                lit.withValues(alpha: 0),
              ],
              stops: [0.0, edgeIn, edgeOut, 1.0],
            ).createShader(rect);
          },
          child: Text(
            line.text,
            textAlign: _textAlign,
            style: restStyle?.copyWith(color: Colors.white, shadows: null),
          ),
        ),
      ],
    );
  }
}

