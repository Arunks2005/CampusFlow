import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Continue with Google" button with a drawn Google "G" (no image needed).
class GoogleButton extends StatelessWidget {
  const GoogleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const GoogleLogo(size: 22),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final center = rect.center;

    Paint paintFor(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;

    double rad(double degrees) => degrees * math.pi / 180;

    // Angles are in degrees, clockwise, 0 = 3 o'clock.
    canvas.drawArc(rect, rad(210), rad(105), false, paintFor(_red));
    canvas.drawArc(rect, rad(135), rad(75), false, paintFor(_yellow));
    canvas.drawArc(rect, rad(45), rad(90), false, paintFor(_green));
    canvas.drawArc(rect, rad(0), rad(45), false, paintFor(_blue));

    // The horizontal bar of the "G".
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke * 0.42,
        rect.right + stroke / 2,
        center.dy + stroke * 0.42,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
