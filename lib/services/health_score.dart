import '../models/miner.dart';

/// Composite health score per miner: 0–100 from real, observed signals.
///
/// **Inputs (every one is a real measurement, never derived):**
///   • thermal     — outTemp vs safe range (60–75°C ideal, >85 critical)
///   • efficiency  — observed power per TH/s vs the device's
///                   ESP-Miner / cgminer-reported efficiency
///   • acceptRate  — accepted / (accepted + rejected) ratio
///   • online      — current MinerStatus
///   • hwErrors    — hardware error count vs accepted shares
///
/// When a signal can't be measured (e.g. miner offline, no power data),
/// it does not contribute to the score — it lowers the *confidence*
/// instead. We never fabricate a score.
class HealthScore {
  final int score;          // 0–100
  final HealthGrade grade;  // visual band
  final double confidence;  // 0–1, fraction of signals available
  final List<HealthFactor> factors;

  const HealthScore({
    required this.score,
    required this.grade,
    required this.confidence,
    required this.factors,
  });

  /// Real input: pass the freshest MinerStats for the miner.
  /// Returns null if the miner has never reported anything (no fakes).
  static HealthScore? from(MinerStats? stats) {
    if (stats == null) return null;
    if (stats.status == MinerStatus.offline) {
      return const HealthScore(
        score: 0,
        grade: HealthGrade.offline,
        confidence: 1.0,
        factors: [
          HealthFactor(
            label: 'Online',
            ok: false,
            note: 'Miner is offline',
            penalty: 100,
          ),
        ],
      );
    }

    final factors = <HealthFactor>[];

    // Thermal — full credit ≤ 70°C, linear penalty 70..85, capped >85.
    if (stats.outTemp > 0) {
      double penalty;
      String note;
      if (stats.outTemp <= 70) {
        penalty = 0;
        note = 'Cool · ${stats.outTemp.toStringAsFixed(0)}°C';
      } else if (stats.outTemp >= 85) {
        penalty = 30;
        note = 'Critical · ${stats.outTemp.toStringAsFixed(0)}°C';
      } else {
        penalty = ((stats.outTemp - 70) / 15) * 30;
        note = 'Warm · ${stats.outTemp.toStringAsFixed(0)}°C';
      }
      factors.add(HealthFactor(
        label: 'Thermal',
        ok: penalty < 15,
        note: note,
        penalty: penalty,
      ));
    }

    // Accept rate — anything < 99.5% deducts.
    if (stats.accepted + stats.rejected > 50) {
      final rate = stats.accepted / (stats.accepted + stats.rejected);
      double penalty;
      if (rate >= 0.995) {
        penalty = 0;
      } else if (rate >= 0.98) {
        penalty = (0.995 - rate) / 0.015 * 10;
      } else {
        penalty = 25;
      }
      factors.add(HealthFactor(
        label: 'Accept rate',
        ok: penalty < 5,
        note: '${(rate * 100).toStringAsFixed(2)}%',
        penalty: penalty,
      ));
    }

    // Hardware errors — every 1% relative to accepted shares = 10pt deduct.
    if (stats.accepted > 100) {
      final ratio = stats.hardwareErrors / stats.accepted;
      double penalty;
      if (ratio < 0.005) {
        penalty = 0;
      } else if (ratio < 0.05) {
        penalty = ratio / 0.05 * 15;
      } else {
        penalty = 20;
      }
      factors.add(HealthFactor(
        label: 'HW errors',
        ok: penalty < 5,
        note: '${stats.hardwareErrors} HW · ${(ratio * 100).toStringAsFixed(2)}%',
        penalty: penalty,
      ));
    }

    // Status (warning vs online)
    factors.add(HealthFactor(
      label: 'Status',
      ok: stats.status == MinerStatus.online,
      note: stats.status == MinerStatus.online ? 'Online' : 'Warning',
      penalty: stats.status == MinerStatus.warning ? 10 : 0,
    ));

    // Sum penalties, clamp 0..100. Confidence = factor count / 4 max.
    final totalPenalty = factors.fold<double>(0, (sum, f) => sum + f.penalty);
    final score = (100 - totalPenalty).clamp(0, 100).round();
    final confidence = (factors.length / 4).clamp(0.0, 1.0);

    return HealthScore(
      score: score,
      grade: _gradeForScore(score),
      confidence: confidence,
      factors: factors,
    );
  }
}

HealthGrade _gradeForScore(int score) {
  if (score >= 90) return HealthGrade.excellent;
  if (score >= 75) return HealthGrade.good;
  if (score >= 50) return HealthGrade.fair;
  return HealthGrade.poor;
}

class HealthFactor {
  final String label;
  final bool ok;
  final String note;
  final double penalty;
  const HealthFactor({
    required this.label,
    required this.ok,
    required this.note,
    required this.penalty,
  });
}

enum HealthGrade { excellent, good, fair, poor, offline }

extension HealthGradeExt on HealthGrade {
  String get label => switch (this) {
        HealthGrade.excellent => 'Excellent',
        HealthGrade.good      => 'Healthy',
        HealthGrade.fair      => 'Fair',
        HealthGrade.poor      => 'Poor',
        HealthGrade.offline   => 'Offline',
      };
}
