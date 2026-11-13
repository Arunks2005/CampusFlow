import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Compact CampusFlow mark: a flowing route joining three campus points.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CampusFlow logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .29),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4AD6B1), Color(0xFF148D99), Color(0xFF286D9A)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyDark.withValues(alpha: .16),
              blurRadius: size * .18,
              offset: Offset(0, size * .07),
            ),
          ],
        ),
        child: CustomPaint(painter: _FlowMarkPainter()),
      ),
    );
  }
}

class _FlowMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide;
    final route = Path()
      ..moveTo(size.width * .23, size.height * .68)
      ..cubicTo(
        size.width * .37,
        size.height * .68,
        size.width * .35,
        size.height * .34,
        size.width * .51,
        size.height * .34,
      )
      ..cubicTo(
        size.width * .68,
        size.height * .34,
        size.width * .66,
        size.height * .67,
        size.width * .80,
        size.height * .67,
      );

    final routePaint = Paint()
      ..color = Colors.white.withValues(alpha: .95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route, routePaint);

    final points = <Offset>[
      Offset(size.width * .23, size.height * .68),
      Offset(size.width * .51, size.height * .34),
      Offset(size.width * .80, size.height * .67),
    ];
    final nodePaint = Paint()..color = Colors.white;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(
        points[index],
        scale * (index == 1 ? .105 : .09),
        nodePaint,
      );
      canvas.drawCircle(
        points[index],
        scale * (index == 1 ? .045 : .036),
        Paint()..color = const Color(0xFF167F87),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowMarkPainter oldDelegate) => false;
}
