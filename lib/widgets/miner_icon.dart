import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';

class MinerIcon extends StatelessWidget {
  final MinerType type;
  final double size;

  const MinerIcon({super.key, required this.type, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _painterFor(type),
    );
  }

  CustomPainter _painterFor(MinerType t) {
    switch (t) {
      case MinerType.avalonQ:
      case MinerType.avalonMini3:
      case MinerType.avalonNano3:
      case MinerType.avalonNano3s:
        return _AvalonPainter(label: t == MinerType.avalonQ ? 'Q' : 'A');
      case MinerType.fluMinerT3:
        return const _FluMinerPainter();
      case MinerType.antminer:
      case MinerType.whatsminer:
      case MinerType.goldshell:
        return const _AntminerPainter();
      default:
        return const _NerdQaxePainter();
    }
  }
}

// ── Avalon / Purple isometric box ─────────────────────────────────────────────

class _AvalonPainter extends CustomPainter {
  final String label;
  const _AvalonPainter({required this.label});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = w / 100.0;

    // Top face — purple gradient
    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF3a2a4a), Color(0xFF5a3a7a), Color(0xFF2a1a3a)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final topFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 22 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..close();
    canvas.drawPath(topFace, topPaint);

    // Left face — very dark
    final leftPaint = Paint()..color = const Color(0xFF0a0510);
    final leftFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..lineTo(50 * s, 86 * s)
      ..lineTo(15 * s, 70 * s)
      ..close();
    canvas.drawPath(leftFace, leftPaint);

    // Right face — slightly lighter dark
    final rightPaint = Paint()..color = const Color(0xFF120a1e);
    final rightFace = Path()
      ..moveTo(50 * s, 54 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(85 * s, 70 * s)
      ..lineTo(50 * s, 86 * s)
      ..close();
    canvas.drawPath(rightFace, rightPaint);

    // Purple LED strip on right face bottom
    final ledPaint = Paint()
      ..color = const Color(0xFFa78bfa).withOpacity(0.8);
    final ledStrip = Path()
      ..moveTo(50 * s, 72 * s)
      ..lineTo(85 * s, 56 * s)
      ..lineTo(85 * s, 61 * s)
      ..lineTo(50 * s, 77 * s)
      ..close();
    canvas.drawPath(ledStrip, ledPaint);

    // Edge highlights
    final edgePaint = Paint()
      ..color = const Color(0xFF7c3aed).withOpacity(0.6)
      ..strokeWidth = 0.8 * s
      ..style = PaintingStyle.stroke;
    canvas.drawPath(topFace, edgePaint);

    // Label text
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontSize: 11 * s,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(62 * s - tp.width / 2, 28 * s - tp.height / 2));
  }

  @override
  bool shouldRepaint(_AvalonPainter old) => old.label != label;
}

// ── NerdQaxe / Green hexagonal PCB ────────────────────────────────────────────

class _NerdQaxePainter extends CustomPainter {
  const _NerdQaxePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = w / 100.0;

    // Main hexagonal PCB — green gradient
    final pcbPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2ea05f), Color(0xFF1a5f38)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final pcbPath = Path()
      ..moveTo(15 * s, 55 * s)
      ..lineTo(50 * s, 38 * s)
      ..lineTo(85 * s, 55 * s)
      ..lineTo(85 * s, 75 * s)
      ..lineTo(50 * s, 92 * s)
      ..lineTo(15 * s, 75 * s)
      ..close();
    canvas.drawPath(pcbPath, pcbPaint);

    // Top highlight face
    final topPaint = Paint()
      ..color = const Color(0xFF39d353).withOpacity(0.6);
    final topFace = Path()
      ..moveTo(15 * s, 55 * s)
      ..lineTo(50 * s, 38 * s)
      ..lineTo(85 * s, 55 * s)
      ..lineTo(50 * s, 72 * s)
      ..close();
    canvas.drawPath(topFace, topPaint);

    // PCB edge highlight
    final edgePaint = Paint()
      ..color = const Color(0xFF39d353).withOpacity(0.5)
      ..strokeWidth = 0.7 * s
      ..style = PaintingStyle.stroke;
    canvas.drawPath(pcbPath, edgePaint);

    // 4 small chip hexagons
    _drawChip(canvas, s, 35 * s, 58 * s, 7 * s);
    _drawChip(canvas, s, 55 * s, 52 * s, 6 * s);
    _drawChip(canvas, s, 65 * s, 68 * s, 6 * s);
    _drawChip(canvas, s, 30 * s, 72 * s, 5 * s);

    // Green status LED dot at top right
    final ledPaint = Paint()..color = const Color(0xFF39d353);
    canvas.drawCircle(Offset(76 * s, 46 * s), 3.5 * s, ledPaint);
    canvas.drawCircle(
      Offset(76 * s, 46 * s),
      5 * s,
      Paint()..color = const Color(0xFF39d353).withOpacity(0.3),
    );
  }

  void _drawChip(Canvas canvas, double s, double cx, double cy, double r) {
    final chipPath = Path();
    final half = r * 0.57;
    chipPath
      ..moveTo(cx, cy - r * 0.55)
      ..lineTo(cx + half, cy - r * 0.27)
      ..lineTo(cx + half, cy + r * 0.27)
      ..lineTo(cx, cy + r * 0.55)
      ..lineTo(cx - half, cy + r * 0.27)
      ..lineTo(cx - half, cy - r * 0.27)
      ..close();
    canvas.drawPath(chipPath, Paint()..color = const Color(0xFF0d2818));
    canvas.drawPath(
      chipPath,
      Paint()
        ..color = const Color(0xFF39d353).withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * s,
    );
  }

  @override
  bool shouldRepaint(_NerdQaxePainter old) => false;
}

// ── Antminer / Orange isometric cube ──────────────────────────────────────────

class _AntminerPainter extends CustomPainter {
  const _AntminerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = w / 100.0;

    // Top face — lighter orange gradient
    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFAA44), Color(0xFFF7931A)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final topFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 22 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..close();
    canvas.drawPath(topFace, topPaint);

    // Left face — dark orange
    final leftPaint = Paint()..color = const Color(0xFF6b3800);
    final leftFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..lineTo(50 * s, 86 * s)
      ..lineTo(15 * s, 70 * s)
      ..close();
    canvas.drawPath(leftFace, leftPaint);

    // Right face — medium orange
    final rightPaint = Paint()..color = const Color(0xFF994c00);
    final rightFace = Path()
      ..moveTo(50 * s, 54 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(85 * s, 70 * s)
      ..lineTo(50 * s, 86 * s)
      ..close();
    canvas.drawPath(rightFace, rightPaint);

    // Orange LED strip on right face
    final ledPaint = Paint()
      ..color = const Color(0xFFF7931A).withOpacity(0.7);
    final ledStrip = Path()
      ..moveTo(50 * s, 72 * s)
      ..lineTo(85 * s, 56 * s)
      ..lineTo(85 * s, 61 * s)
      ..lineTo(50 * s, 77 * s)
      ..close();
    canvas.drawPath(ledStrip, ledPaint);

    // Edge highlight
    final edgePaint = Paint()
      ..color = const Color(0xFFFFAA44).withOpacity(0.5)
      ..strokeWidth = 0.8 * s
      ..style = PaintingStyle.stroke;
    canvas.drawPath(topFace, edgePaint);
  }

  @override
  bool shouldRepaint(_AntminerPainter old) => false;
}

// ── FluMiner T3 — Teal/blue industrial rack-style icon ───────────────────────

class _FluMinerPainter extends CustomPainter {
  const _FluMinerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;

    // Background circle
    canvas.drawCircle(
      Offset(50 * s, 50 * s),
      48 * s,
      Paint()..color = const Color(0xFF0A2030),
    );

    // Top face (teal)
    final topPaint = Paint()..color = const Color(0xFF00BCD4);
    final topFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 22 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..close();
    canvas.drawPath(topFace, topPaint);

    // Left face (darker teal)
    final leftPaint = Paint()..color = const Color(0xFF00838F);
    final leftFace = Path()
      ..moveTo(15 * s, 38 * s)
      ..lineTo(50 * s, 54 * s)
      ..lineTo(50 * s, 84 * s)
      ..lineTo(15 * s, 68 * s)
      ..close();
    canvas.drawPath(leftFace, leftPaint);

    // Right face (medium teal)
    final rightPaint = Paint()..color = const Color(0xFF006064);
    final rightFace = Path()
      ..moveTo(50 * s, 54 * s)
      ..lineTo(85 * s, 38 * s)
      ..lineTo(85 * s, 68 * s)
      ..lineTo(50 * s, 84 * s)
      ..close();
    canvas.drawPath(rightFace, rightPaint);

    // Blue LED accent
    final ledPaint = Paint()..color = const Color(0xFF40E0FF).withOpacity(0.8);
    final ledStrip = Path()
      ..moveTo(50 * s, 70 * s)
      ..lineTo(85 * s, 54 * s)
      ..lineTo(85 * s, 59 * s)
      ..lineTo(50 * s, 75 * s)
      ..close();
    canvas.drawPath(ledStrip, ledPaint);

    // "F" label on top
    final tp = TextPainter(
      text: TextSpan(
        text: 'F',
        style: TextStyle(
          color: const Color(0xFF001A20),
          fontSize: 18 * s,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(43 * s, 30 * s));
  }

  @override
  bool shouldRepaint(_FluMinerPainter old) => false;
}
