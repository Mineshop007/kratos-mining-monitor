import 'package:flutter/material.dart';
import '../models/miner.dart';
import '../services/health_score.dart';
import '../theme/volt_theme.dart';

/// Compact health badge shown next to a miner's name on the fleet card
/// and detail screens. Real value or '—' (no fakes).
class HealthBadge extends StatelessWidget {
  final MinerStats? stats;
  final bool compact;

  const HealthBadge({super.key, required this.stats, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final h = HealthScore.from(stats);
    if (h == null) {
      return _Pill(
        label: '—',
        sub: compact ? null : 'no data',
        color: KratosColors.muted,
      );
    }

    final color = switch (h.grade) {
      HealthGrade.excellent => KratosColors.volt,
      HealthGrade.good      => KratosColors.cyan,
      HealthGrade.fair      => KratosColors.warning,
      HealthGrade.poor      => KratosColors.danger,
      HealthGrade.offline   => KratosColors.muted,
    };

    return _Pill(
      label: '${h.score}',
      sub: compact ? null : h.grade.label,
      color: color,
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String? sub;
  final Color color;

  const _Pill({required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(width: 4),
            Text(
              sub!,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.85),
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
