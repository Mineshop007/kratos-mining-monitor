import 'package:flutter/material.dart';

class KratosShield extends StatelessWidget {
  final double size;
  const KratosShield({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ShieldPainter(),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Gold gradient shield
    final goldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFD700), Color(0xFFF7931A), Color(0xFFB86D00)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Shield path scaled from 100x100 viewBox
    final s = w / 100.0;
    final shieldPath = Path()
      ..moveTo(20 * s, 18 * s)
      ..lineTo(80 * s, 18 * s)
      ..lineTo(80 * s, 60 * s)
      ..quadraticBezierTo(80 * s, 78 * s, 50 * s, 92 * s)
      ..quadraticBezierTo(20 * s, 78 * s, 20 * s, 60 * s)
      ..close();

    canvas.drawPath(shieldPath, goldPaint);

    // Dark K letter
    final kPaint = Paint()..color = const Color(0xFF0D1117);

    // Vertical stem: x=33 y=32 w=8 h=42
    canvas.drawRect(
      Rect.fromLTWH(33 * s, 32 * s, 8 * s, 42 * s),
      kPaint,
    );

    // Upper diagonal
    final upperPath = Path()
      ..moveTo(41 * s, 52 * s)
      ..lineTo(60 * s, 32 * s)
      ..lineTo(67 * s, 32 * s)
      ..lineTo(47 * s, 52 * s)
      ..close();
    canvas.drawPath(upperPath, kPaint);

    // Lower diagonal
    final lowerPath = Path()
      ..moveTo(41 * s, 52 * s)
      ..lineTo(67 * s, 72 * s)
      ..lineTo(60 * s, 72 * s)
      ..lineTo(41 * s, 58 * s)
      ..close();
    canvas.drawPath(lowerPath, kPaint);

    // Gold highlight strip at top
    final highlightPath = Path()
      ..moveTo(22 * s, 20 * s)
      ..lineTo(78 * s, 20 * s)
      ..lineTo(76 * s, 26 * s)
      ..lineTo(24 * s, 26 * s)
      ..close();
    canvas.drawPath(
      highlightPath,
      Paint()..color = const Color(0xFFFFE580).withOpacity(0.5),
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => false;
}
