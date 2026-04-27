import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bitcoin price service with 5-minute caching and per-miner earnings calculation
class BtcPriceService {
  static final BtcPriceService instance = BtcPriceService._();
  BtcPriceService._();

  double _cachedPrice = 0;
  DateTime? _lastFetch;
  static const _cacheDuration = Duration(minutes: 5);

  // ~April 2026 solo/pool estimate: 144 blocks/day × 3.125 BTC / global_hashrate_EH
  // Simplified to a per-TH/s constant; adjust as network difficulty changes
  static const double btcPerThPerDay = 0.000022;

  double get cachedPrice => _cachedPrice > 0 ? _cachedPrice : 93000;

  Future<double> getBtcPrice() async {
    final now = DateTime.now();
    if (_cachedPrice > 0 &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < _cacheDuration) {
      return _cachedPrice;
    }
    try {
      final r = await http.get(
        Uri.parse(
            'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd'),
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final price = ((j['bitcoin']?['usd']) as num?)?.toDouble() ?? 0;
        if (price > 0) {
          _cachedPrice = price;
          _lastFetch = now;
        }
      }
    } catch (_) {
      // Use cached or fallback
    }
    return _cachedPrice > 0 ? _cachedPrice : 93000;
  }

  // USD/day for a miner with given hashrate (GH/s)
  Future<double> dailyEarningsUsd(double hashrateGhs) async {
    if (hashrateGhs <= 0) return 0;
    final price = await getBtcPrice();
    return dailyEarningsUsdSync(hashrateGhs, price);
  }

  double dailyEarningsUsdSync(double hashrateGhs, double btcPrice) {
    if (hashrateGhs <= 0 || btcPrice <= 0) return 0;
    final hashrateTh = hashrateGhs / 1000.0;
    return hashrateTh * btcPerThPerDay * btcPrice;
  }

  // Daily power cost in USD
  double dailyCostUsd(double powerWatts, double kwhPriceUsd) {
    if (powerWatts <= 0 || kwhPriceUsd <= 0) return 0;
    final dailyKwh = powerWatts * 24.0 / 1000.0;
    return dailyKwh * kwhPriceUsd;
  }

  // Net profit per day
  double netProfitUsd(double hashrateGhs, double powerWatts, double kwhPriceUsd, double btcPrice) {
    return dailyEarningsUsdSync(hashrateGhs, btcPrice) - dailyCostUsd(powerWatts, kwhPriceUsd);
  }
}
