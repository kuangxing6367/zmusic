import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Mouse-wheel smoothing for vertical lists.
///
/// Flutter's default wheel handling jumps the scroll offset by the raw delta,
/// which reads as a stutter on Windows. A listener placed *inside* the
/// scrollable (around each item) registers with the pointer signal resolver
/// before the [Scrollable] does, so it can win the event and animate to the
/// target instead. Trackpad and touch input are untouched.
class SmoothScrollItem extends StatelessWidget {
  const SmoothScrollItem({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final delta = event.scrollDelta.dy;
        if (delta == 0) return;
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          _scrollBy(delta);
        });
      },
      child: child,
    );
  }

  void _scrollBy(double delta) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    position.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }
}

/// A [ListView] whose children get animated mouse-wheel scrolling.
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
      widget.controller ?? ScrollController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _controller,
      padding: widget.padding,
      physics: widget.physics,
      children: [
        for (final child in widget.children)
          SmoothScrollItem(controller: _controller, child: child),
      ],
    );
  }
}
