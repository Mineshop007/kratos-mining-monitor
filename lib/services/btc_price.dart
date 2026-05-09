import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bitcoin price service with 5-minute caching and per-miner earnings calculation
class BtcPriceService {
  static final BtcPriceService instance = BtcPriceService._();
  BtcPriceService._();

  double _cachedPrice = 0;
  DateTime? _lastFetch;
  static const _cacheDuration = Duration(minutes: 5);

  // Network hashrate-based profitability (live from mempool.space, 10-min cache)
  double _cachedBtcPerTh = 0.0000005; // fallback
  double _cachedNetworkHashrateThs = 700e6; // ~700 EH/s fallback
  DateTime? _lastBtcPerThFetch;
  static const _btcPerThCacheDuration = Duration(minutes: 10);

  // BCH network data
  double _cachedBchNetworkHashrateThs = 3e6; // ~3 EH/s fallback
  double _cachedBchPriceUsd = 400;           // fallback
  DateTime? _lastBchFetch;
  static const _bchCacheDuration = Duration(minutes: 15);

  /// BTC network hashrate in TH/s
  double get networkHashrateThs => _cachedNetworkHashrateThs;

  /// BCH network hashrate in TH/s
  double get bchNetworkHashrateThs => _cachedBchNetworkHashrateThs;

  /// BCH price in USD
  double get bchPriceUsd => _cachedBchPriceUsd;

  double get cachedPrice => _cachedPrice > 0 ? _cachedPrice : 93000;

  /// Live btcPerThPerDay from mempool.space network hashrate
  double get btcPerThPerDay => _cachedBtcPerTh;

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
    // Also refresh network hashrate + BCH in background
    _refreshBtcPerTh();
    _refreshBch();
    return _cachedPrice > 0 ? _cachedPrice : 93000;
  }

  Future<void> _refreshBtcPerTh() async {
    final now = DateTime.now();
    if (_lastBtcPerThFetch != null &&
        now.difference(_lastBtcPerThFetch!) < _btcPerThCacheDuration) {
      return;
    }
    try {
      final r = await http.get(
        Uri.parse('https://mempool.space/api/v1/mining/hashrate/3d'),
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final currentHashrate = ((j['currentHashrate'] as num?) ?? 0).toDouble();
        if (currentHashrate > 0) {
          // (144 blocks/day × 3.125 BTC/block) / (network_hashrate_in_TH/s)
          final networkTh = currentHashrate / 1e12;
          _cachedBtcPerTh = (144 * 3.125) / networkTh;
          _cachedNetworkHashrateThs = networkTh;
          _lastBtcPerThFetch = now;
        }
      }
    } catch (_) {
      // Keep fallback value
    }
  }

  Future<void> _refreshBch() async {
    final now = DateTime.now();
    if (_lastBchFetch != null &&
        now.difference(_lastBchFetch!) < _bchCacheDuration) return;
    try {
      // BCH price via CoinGecko
      final r = await http.get(Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin-cash&vs_currencies=usd'
      )).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final p = ((j['bitcoin-cash']?['usd']) as num?)?.toDouble() ?? 0;
        if (p > 0) _cachedBchPriceUsd = p;
      }

      // BCH network hashrate via Blockchair
      final r2 = await http.get(Uri.parse(
          'https://api.blockchair.com/bitcoin-cash/stats'
      )).timeout(const Duration(seconds: 10));
      if (r2.statusCode == 200) {
        final j2 = jsonDecode(r2.body) as Map<String, dynamic>;
        final hashes = (j2['data']?['hashrate_mean'] as num?)?.toDouble() ?? 0;
        if (hashes > 0) {
          // Blockchair returns hashes/s
          _cachedBchNetworkHashrateThs = hashes / 1e12;
        }
      }
      _lastBchFetch = now;
    } catch (_) {}
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
    return hashrateTh * _cachedBtcPerTh * btcPrice;
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
