import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';

/// Smooth sparkline chart widget for hashrate history
class Sparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;
  final bool showGradient;

  const Sparkline({
    super.key,
    required this.data,
    this.color = const Color(0xFF39d353),
    this.height = 28,
    this.showGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          color: color,
          showGradient: showGradient,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool showGradient;

  _SparklinePainter({
    required this.data,
    required this.color,
    required this.showGradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Single data point — draw a dot
    if (data.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        2.5,
        Paint()..color = color,
      );
      return;
    }

    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    var range = maxVal - minVal;

    // Ensure minimum visible spread (5% of mean) so stable hashrate
    // doesn’t render as a perfectly flat line — add artificial padding.
    final mean = data.reduce((a, b) => a + b) / data.length;
    final minRange = mean * 0.05;
    if (range < minRange) range = minRange;

    final midVal = (minVal + maxVal) / 2;
    final lo = midVal - range / 2;

    double toY(double v) {
      final t = (v - lo) / range;
      return size.height - t.clamp(0.0, 1.0) * (size.height * 0.8) - size.height * 0.1;
    }

    final xStep = size.width / (data.length - 1);

    // Build smooth path with cubic bezier
    final path = Path();
    path.moveTo(0, toY(data[0]));

    for (int i = 1; i < data.length; i++) {
      final x1 = i * xStep;
      final y1 = toY(data[i]);
      final x0 = (i - 1) * xStep;
      final y0 = toY(data[i - 1]);
      final cpX = (x0 + x1) / 2;
      path.cubicTo(cpX, y0, cpX, y1, x1, y1);
    }

    // Gradient fill
    if (showGradient) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data.length != data.length ||
      old.color != color ||
      (data.isNotEmpty && old.data.isNotEmpty && old.data.last != data.last);
}
