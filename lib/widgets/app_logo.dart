import 'package:flutter/material.dart';

import '../app_theme.dart';

/// CampusFlow mark: a campus location pin with a parking-ready route marker.
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
    final pin = Path()
      ..moveTo(size.width * .5, size.height * .82)
      ..cubicTo(
        size.width * .42,
        size.height * .70,
        size.width * .22,
        size.height * .49,
        size.width * .22,
        size.height * .37,
      )
      ..cubicTo(
        size.width * .22,
        size.height * .19,
        size.width * .35,
        size.height * .10,
        size.width * .5,
        size.height * .10,
      )
      ..cubicTo(
        size.width * .65,
        size.height * .10,
        size.width * .78,
        size.height * .19,
        size.width * .78,
        size.height * .37,
      )
      ..cubicTo(
        size.width * .78,
        size.height * .49,
        size.width * .58,
        size.height * .70,
        size.width * .5,
        size.height * .82,
      )
      ..close();
    canvas.drawPath(pin, Paint()..color = Colors.white.withValues(alpha: .96));
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .37),
      scale * .19,
      Paint()..color = const Color(0xFF147D7A),
    );

    final p = TextPainter(
      text: TextSpan(
        text: 'P',
        style: TextStyle(
          color: Colors.white,
          fontSize: scale * .29,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(
      canvas,
      Offset(size.width * .5 - p.width / 2, size.height * .37 - p.height / 2),
    );

    final route = Path()
      ..moveTo(size.width * .20, size.height * .83)
      ..cubicTo(
        size.width * .34,
        size.height * .73,
        size.width * .66,
        size.height * .73,
        size.width * .80,
        size.height * .83,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = Colors.white.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale * .055
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowMarkPainter oldDelegate) => false;
}

