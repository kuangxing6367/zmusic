import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Smoothed, inertial mouse-wheel scrolling.
///
/// Flutter's default wheel handling moves the list by the raw delta in one
/// frame, which reads as a hard jump on Windows. Rather than fighting the
/// pointer-signal resolver per list item, this plugs into the scroll position
/// itself: every wheel notch is added to an accumulated target, and a
/// frame-driven exponential approach moves the pixels toward it. That keeps
/// the full wheel distance, works for sliver pages too, and never feels like
/// it "eats" a notch when the wheel is spammed.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// How quickly the position closes the gap to the wheel target. Smaller is
  /// snappier; ~70 ms keeps a 100 px notch readable but immediate.
  static const double _timeConstant = 0.07;

  double? _target;
  Duration? _lastTick;
  bool _frameScheduled = false;
  bool _disposed = false;

  bool get _hasTarget => _target != null;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      goBallistic(0.0);
      return;
    }
    if (!hasPixels || !hasViewportDimension || !hasContentDimensions) {
      super.pointerScroll(delta);
      return;
    }
    final base = _target ?? pixels;
    final next = (base + delta).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
    _target = next;
    _lastTick = null;
    if (activity is! IdleScrollActivity) goIdle();
    _scheduleFrame();
  }

  void _scheduleFrame() {
    if (_frameScheduled || _disposed) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    _frameScheduled = false;
    final target = _target;
    if (_disposed || !_hasTarget || !hasPixels || target == null) {
      _target = null;
      _lastTick = null;
      return;
    }
    final last = _lastTick;
    _lastTick = timestamp;
    if (last == null) {
      // Measure the first frame so the step uses a real delta time.
      _scheduleFrame();
      return;
    }
    final dt = ((timestamp - last).inMicroseconds / 1000000.0).clamp(
      0.001,
      0.05,
    );
    final diff = target - pixels;
    if (diff.abs() < 0.5) {
      setPixels(target);
      _target = null;
      _lastTick = null;
      return;
    }
    final step = diff * (1 - math.exp(-dt / _timeConstant));
    setPixels((pixels + step).clamp(minScrollExtent, maxScrollExtent));
    _scheduleFrame();
  }

  void _cancelSmoothing() {
    _target = null;
    _lastTick = null;
  }

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    _cancelSmoothing();
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _cancelSmoothing();
    return super.drag(details, dragCancelCallback);
  }

  @override
  void jumpTo(double value) {
    _cancelSmoothing();
    super.jumpTo(value);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSmoothing();
    super.dispose();
  }
}

/// Kept for source compatibility with sliver pages; smoothing now lives in
/// [SmoothScrollController], so this is a plain pass-through.
class SmoothScrollItem extends StatelessWidget {
  const SmoothScrollItem({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A [ListView] with smoothed mouse-wheel scrolling and working touch drags.
class SmoothScrollList extends StatefulWidget {
  const SmoothScrollList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  @override
  State<SmoothScrollList> createState() => _SmoothScrollListState();
}

class _SmoothScrollListState extends State<SmoothScrollList> {
  late final ScrollController _controller =
      widget.controller ?? SmoothScrollController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A bare `AlwaysScrollableScrollPhysics` drops the platform physics chain,
    // which also drops clamping and fling; merge it into the platform physics
    // so touch drags keep their momentum and never run away at the edges.
    final platform = ScrollConfiguration.of(context).getScrollPhysics(context);
    final physics = (widget.physics ?? const AlwaysScrollableScrollPhysics())
        .applyTo(platform);
    return ListView(
      controller: _controller,
      padding: widget.padding,
      physics: physics,
      children: widget.children,
    );
  }
}

/// App-wide scroll behaviour: allow touch, pen, trackpad and mouse drags so a
/// touchscreen laptop can swipe lists regardless of how Windows reports the
/// pointer.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.mouse,
        PointerDeviceKind.unknown,
      };
}
