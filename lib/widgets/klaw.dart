import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/volt_theme.dart';

/// Klaw the Honey Badger — Kratos v2 mascot.
/// One asset, three contextual sizes (splash hero, empty-state, celebration).
/// All derive from `assets/images/klaw-mascot.png`.
class Klaw extends StatelessWidget {
  final double size;
  final bool glow;

  const Klaw({super.key, required this.size, this.glow = true});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/klaw-mascot.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!glow) return image;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KratosColors.volt.withOpacity(0.18),
            blurRadius: size * 0.25,
            spreadRadius: size * 0.04,
          ),
        ],
      ),
      child: image,
    );
  }
}

/// Empty-state widget shown anywhere there's nothing to display yet.
/// Klaw appears with a quip + an optional CTA.
class KlawEmptyState extends StatelessWidget {
  final String headline;
  final String quip;
  final Widget? cta;
  final double mascotSize;

  const KlawEmptyState({
    super.key,
    required this.headline,
    required this.quip,
    this.cta,
    this.mascotSize = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Klaw(size: mascotSize)
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1)),
          const SizedBox(height: 22),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: KratosColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            quip,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: KratosColors.muted,
              height: 1.4,
            ),
          ),
          if (cta != null) ...[
            const SizedBox(height: 24),
            cta!,
          ],
        ],
      ),
    );
  }
}

/// Boot splash. Shown for ~600ms while ThemeService + MinerStore load.
class KlawSplash extends StatelessWidget {
  const KlawSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosColors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Klaw(size: 200)
                .animate()
                .fadeIn(duration: 320.ms)
                .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
            const SizedBox(height: 28),
            const Text(
              'KRATOS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: KratosColors.text,
                letterSpacing: 4,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 320.ms),
            const SizedBox(height: 6),
            const Text(
              'forge your fleet',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: KratosColors.muted,
                letterSpacing: 2,
              ),
            ).animate().fadeIn(delay: 240.ms, duration: 320.ms),
          ],
        ),
      ),
    );
  }
}
