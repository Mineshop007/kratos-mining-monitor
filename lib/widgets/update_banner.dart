import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/update_check_service.dart';
import '../theme/volt_theme.dart';

/// Non-intrusive top banner that appears when a newer version is available.
/// Wraps any screen body — just place [UpdateBanner] above or as overlay.
class UpdateBanner extends StatelessWidget {
  final Widget child;
  const UpdateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateCheckService>(
      builder: (ctx, svc, _) {
        if (!svc.updateAvailable) return child;
        return Column(children: [
          _Banner(svc: svc),
          Expanded(child: child),
        ]);
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final UpdateCheckService svc;
  const _Banner({required this.svc});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Material(
      color: const Color(0xFF1a2a1a),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kc.accent.withValues(alpha: 0.15),
              kc.accent.withValues(alpha: 0.08),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: kc.accent.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(children: [
          // KLAW icon
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Image.asset(
              'assets/images/klaw-mascot.png',
              width: 26, height: 26,
              filterQuality: FilterQuality.medium,
            ),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Update available — v${svc.latestVersion}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: kc.accent,
                ),
              ),
              Text(
                'Tap Update to get the latest Kratos features',
                style: TextStyle(fontSize: 11, color: kc.muted),
              ),
            ],
          )),
          const SizedBox(width: 8),
          // Update button
          GestureDetector(
            onTap: svc.openStore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kc.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'UPDATE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Dismiss
          GestureDetector(
            onTap: svc.dismiss,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: kc.muted),
            ),
          ),
        ]),
      ),
    );
  }
}
