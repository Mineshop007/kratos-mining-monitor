import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/volt_theme.dart';

/// Full-screen "Block Found" celebration overlay.
///
/// Replaces the v1.0 confetti dialog. A single golden block falls from
/// above, lands with a bounce, and emits volt arcs. Tap to dismiss.
///
/// Triggered by MinerStore.pendingBlockFoundMiner — see HomeScreen.
class FallingBlockOverlay extends StatefulWidget {
  final String minerName;
  final String? coinTicker;
  final VoidCallback onDone;

  const FallingBlockOverlay({
    super.key,
    required this.minerName,
    this.coinTicker,
    required this.onDone,
  });

  @override
  State<FallingBlockOverlay> createState() => _FallingBlockOverlayState();
}

class _FallingBlockOverlayState extends State<FallingBlockOverlay>
    with TickerProviderStateMixin {
  KratosPalette get kc => KratosColors.of(context);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return GestureDetector(
      onTap: widget.onDone,
      child: Material(
        color: Colors.black.withOpacity(0.86),
        child: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const _VoltArcs(),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (ctx, _) => Transform.translate(
                  offset: Offset(0,
                      Curves.easeOutCubic.transform(_ctrl.value) *
                              0 -
                          0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Block(controller: _ctrl),
                      SizedBox(height: 32),
                      _Text(
                          minerName: widget.minerName,
                          coinTicker: widget.coinTicker,
                          ctrl: _ctrl),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'tap to dismiss',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ).animate(delay: 1100.ms).fadeIn(duration: 400.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final AnimationController controller;
  const _Block({required this.controller});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Animate(
      effects: const [
        SlideEffect(
          begin: Offset(0, -3),
          end: Offset(0, 0),
          duration: Duration(milliseconds: 600),
          curve: Curves.bounceOut,
        ),
      ],
      child: Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFD66B),
              Color(0xFFF7931A),
              Color(0xFFC0651A),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: kc.accent.withOpacity(0.5),
              blurRadius: 60,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: const Color(0xFFFFD66B).withOpacity(0.4),
              blurRadius: 80,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '₿',
            style: TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A0F00),
            ),
          ),
        ),
      ).animate(delay: 600.ms).shake(
            duration: 400.ms,
            hz: 8,
            offset: const Offset(2, 2),
          ),
    );
  }
}

class _Text extends StatelessWidget {
  final String minerName;
  final String? coinTicker;
  final AnimationController ctrl;
  const _Text({
    required this.minerName,
    required this.coinTicker,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(
      children: [
        Text(
          'BLOCK FOUND',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 4,
          ),
        )
            .animate(delay: 700.ms)
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.5, end: 0),
        SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '${coinTicker ?? "BTC"} · $minerName',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 1.2,
            ),
          ),
        ).animate(delay: 850.ms).fadeIn(duration: 400.ms),
        SizedBox(height: 14),
        Text(
          'Klaw approves.',
          style: TextStyle(
            fontSize: 13,
            color: kc.accentBright,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ).animate(delay: 1000.ms).fadeIn(duration: 400.ms),
      ],
    );
  }
}

class _VoltArcs extends StatefulWidget {
  const _VoltArcs();
  @override
  State<_VoltArcs> createState() => _VoltArcsState();
}

class _VoltArcsState extends State<_VoltArcs>
    with SingleTickerProviderStateMixin {
  KratosPalette get kc => KratosColors.of(context);
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => CustomPaint(
        painter: _ArcsPainter(progress: _ctrl.value, accent: kc.accent),
        size: Size.infinite,
      ),
    );
  }
}

class _ArcsPainter extends CustomPainter {
  final double progress;
  final Color accent;
  _ArcsPainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()
      ..color = accent.withOpacity(0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);

    for (var i = 0; i < 8; i++) {
      final phase = (progress + i / 8) % 1;
      final fade = (math.sin(phase * math.pi * 2) + 1) / 2;
      paint.color =
          accent.withOpacity(0.10 + fade * 0.18);
      final startX =
          rng.nextDouble() * size.width;
      final endX = rng.nextDouble() * size.width;
      final startY = rng.nextBool() ? -10.0 : size.height + 10;
      final endY =
          startY < 0 ? size.height * 0.45 : size.height * 0.55;
      final path = Path()..moveTo(startX, startY);
      // Random-ish jagged spline.
      final mid1x = startX + (rng.nextDouble() - 0.5) * 80;
      final mid1y = startY + (endY - startY) * 0.33;
      final mid2x = endX + (rng.nextDouble() - 0.5) * 80;
      final mid2y = startY + (endY - startY) * 0.66;
      path.lineTo(mid1x, mid1y);
      path.lineTo(mid2x, mid2y);
      path.lineTo(endX, endY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
