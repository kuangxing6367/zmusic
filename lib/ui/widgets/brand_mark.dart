import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The zmusic brand mark: a rounded navy tile with a cyan music note and three
/// sound arcs. Drawn with a painter instead of a bitmap so it stays crisp in the
/// rail, the splash screen and the taskbar-sized previews alike.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrandPainter(radius: radius)),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({this.radius});

  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final rect = Offset.zero & size;
    final corner = Radius.circular(radius ?? side * 0.245);
    final rrect = RRect.fromRectAndRadius(rect, corner);

    canvas.save();
    canvas.clipRRect(rrect);

    // Deep navy tile with a soft top-left sheen.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243469), Color(0xFF10173A), Color(0xFF0A0F26)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.5, -0.7),
          radius: 0.95,
          colors: [
            const Color(0xFF3B4E93).withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    final cyan = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5FD8FF), Color(0xFF22E3DC)],
      ).createShader(rect);

    // Note head (slightly tilted).
    canvas.save();
    canvas.translate(side * 0.395, side * 0.665);
    canvas.rotate(-0.32);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: side * 0.265,
        height: side * 0.205,
      ),
      cyan,
    );
    canvas.restore();

    // Stem.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          side * 0.492,
          side * 0.245,
          side * 0.082,
          side * 0.400,
        ),
        Radius.circular(side * 0.041),
      ),
      cyan,
    );

    // Flag sweeping to the right.
    final flag = Path()
      ..moveTo(side * 0.566, side * 0.268)
      ..quadraticBezierTo(side * 0.792, side * 0.300, side * 0.735, side * 0.500)
      ..quadraticBezierTo(side * 0.735, side * 0.378, side * 0.566, side * 0.392)
      ..close();
    canvas.drawPath(flag, cyan);

    // Three sound arcs, purple to teal.
    const arcColors = [Color(0xFF9A7BFF), Color(0xFF6E8BFF), Color(0xFF38E0E6)];
    final center = Offset(side * 0.505, side * 0.545);
    for (var i = 0; i < 3; i++) {
      final radiusPx = side * (0.185 + i * 0.092);
      final arcRect = Rect.fromCircle(center: center, radius: radiusPx);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * (0.052 - i * 0.004)
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [arcColors[i], arcColors[math.min(i + 1, 2)]],
        ).createShader(arcRect);
      canvas.drawArc(arcRect, -0.72, 1.44, false, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
