import '../services/btc_price.dart';

/// Bitcoin solo mining block probability calculator.
class BlockCalc {
  BlockCalc._();

  /// Expected days to find a block solo mining.
  /// [hashrateThs] miner hashrate in TH/s
  /// [networkHashrateThs] total network hashrate in TH/s (from BtcPriceService)
  static double expectedDays(double hashrateThs, double networkHashrateThs) {
    if (hashrateThs <= 0 || networkHashrateThs <= 0) return double.infinity;
    // 144 blocks per day, your share = hashrateThs / networkHashrateThs
    final blocksPerDay = (hashrateThs / networkHashrateThs) * 144;
    if (blocksPerDay <= 0) return double.infinity;
    return 1.0 / blocksPerDay;
  }

  /// Probability of finding at least 1 block in [days] days.
  static double probInDays(double hashrateThs, double networkHashrateThs, double days) {
    if (hashrateThs <= 0 || networkHashrateThs <= 0) return 0;
    final blocksPerDay = (hashrateThs / networkHashrateThs) * 144;
    // P(at least 1 block) = 1 - e^(-blocksPerDay * days)  [Poisson]
    return 1.0 - _exp(-blocksPerDay * days);
  }

  static double _exp(double x) {
    if (x < -100) return 0;
    return _expApprox(x);
  }

  static double _expApprox(double x) {
    // Good enough approximation for small negative x
    if (x >= 0) return 1;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
      if (term.abs() < 1e-15) break;
    }
    return result.clamp(0.0, 1.0);
  }

  /// Format expected days as human-readable string: "~47y", "~3mo", "~12d"
  static String formatExpectedTime(double days) {
    if (days == double.infinity || days <= 0) return '∞';
    if (days >= 365 * 1000) return '>${(days / 365).round() ~/ 1000}ky';
    if (days >= 365) {
      final y = days / 365;
      return y >= 100 ? '~${y.round()}y' : '~${y.toStringAsFixed(0)}y';
    }
    if (days >= 30) return '~${(days / 30).toStringAsFixed(0)}mo';
    if (days >= 1)  return '~${days.toStringAsFixed(0)}d';
    return '~${(days * 24).toStringAsFixed(0)}h';
  }

  /// Format probability as percentage string: "0.0021%"
  static String formatProbPct(double prob) {
    if (prob <= 0) return '0%';
    if (prob >= 0.01) return '${(prob * 100).toStringAsFixed(2)}%';
    if (prob >= 0.0001) return '${(prob * 100).toStringAsFixed(4)}%';
    return '<0.0001%';
  }

  /// Get current network hashrate in TH/s from BtcPriceService
  static double networkHashrateThs() {
    return BtcPriceService.instance.networkHashrateThs;
  }

  /// Determine if a pool URL is a known solo pool
  static bool isSoloPool(String url) {
    final lower = url.toLowerCase();
    return lower.contains('solo.') ||
        lower.contains('ckpool') ||
        lower.contains('public-pool') ||
        lower.contains('solo-pool') ||
        lower.contains('solomining');
  }
}
