import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coin.dart';

/// Multi-coin price service. Source of truth: CoinGecko free tier.
/// Cache horizon: 60s (in-memory) + 5 min (persisted) to survive restarts.
///
/// **Real data only.** If a coin's price isn't in cache and the network
/// call fails, the getter returns null. UI must render an explicit
/// "—" / "no data" state instead of inventing a value.
class CoinPriceService extends ChangeNotifier {
  static const _kPersistKey = 'kratos_coin_prices_v1';
  static const _baseUrl = 'https://api.coingecko.com/api/v3';
  static const _maxStale = Duration(minutes: 5);

  /// Fiat the user views prices in. UI changes via Settings.
  String _fiat = 'eur';
  String get fiat => _fiat;

  final Map<Coin, _CachedPrice> _cache = {};

  Timer? _refresh;
  bool _disposed = false;

  CoinPriceService() {
    _loadFiat();
    _restoreCache();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Exposes a snapshot for the UI. Null when we have no real data.
  double? priceFor(Coin coin) {
    final c = _cache[coin];
    if (c == null) return null;
    if (DateTime.now().difference(c.fetchedAt) > _maxStale) return null;
    return c.fiatValue;
  }

  /// True when the cached price was refreshed within the last 60 seconds.
  bool isFresh(Coin coin) {
    final c = _cache[coin];
    if (c == null) return false;
    return DateTime.now().difference(c.fetchedAt) < const Duration(seconds: 60);
  }

  DateTime? lastFetched(Coin coin) => _cache[coin]?.fetchedAt;

  Future<void> setFiat(String code) async {
    final lc = code.toLowerCase();
    if (lc == _fiat) return;
    _fiat = lc;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kratos_fiat', _fiat);
    _cache.clear();
    _safeNotify();
    await refresh(<Coin>[]); // fresh fetch after fiat change
  }

  Future<void> _loadFiat() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _fiat = prefs.getString('kratos_fiat') ?? 'eur';
    _safeNotify();
  }

  Future<void> _restoreCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPersistKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final coin = Coin.values
            .where((c) => c.name == e.key)
            .firstOrNull;
        if (coin == null) continue;
        _cache[coin] = _CachedPrice.fromJson(e.value as Map<String, dynamic>);
      }
      _safeNotify();
    } catch (_) {
      // ignore corrupt cache
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPersistKey,
      jsonEncode({for (final e in _cache.entries) e.key.name: e.value.toJson()}),
    );
  }

  /// Refreshes prices for the supplied coins (or all known if empty).
  Future<void> refresh(Iterable<Coin> coins) async {
    final wanted = (coins.isEmpty
            ? Coin.values.where((c) => c.coinGeckoId != null)
            : coins.where((c) => c.coinGeckoId != null))
        .toList();
    if (wanted.isEmpty) return;

    final ids = wanted.map((c) => c.coinGeckoId!).join(',');
    final uri = Uri.parse('$_baseUrl/simple/price?ids=$ids&vs_currencies=$_fiat');

    try {
      final resp = await http.get(uri,
          headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final now = DateTime.now();
      for (final c in wanted) {
        final id = c.coinGeckoId!;
        final entry = body[id];
        if (entry is Map<String, dynamic>) {
          final raw = entry[_fiat];
          if (raw is num) {
            _cache[c] = _CachedPrice(
              coinGeckoId: id,
              fiat: _fiat,
              fiatValue: raw.toDouble(),
              fetchedAt: now,
            );
          }
        }
      }
      await _persist();
      _safeNotify();
    } catch (_) {
      // Network failure: keep prior cache; UI shows stale chip / dash.
    }
  }

  /// Auto-refresh while the app is foregrounded.
  void startAutoRefresh(Iterable<Coin> coins, {
    Duration interval = const Duration(minutes: 1),
  }) {
    _refresh?.cancel();
    refresh(coins);
    _refresh = Timer.periodic(interval, (_) => refresh(coins));
  }

  void stopAutoRefresh() {
    _refresh?.cancel();
    _refresh = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _refresh?.cancel();
    super.dispose();
  }
}

class _CachedPrice {
  final String coinGeckoId;
  final String fiat;
  final double fiatValue;
  final DateTime fetchedAt;

  _CachedPrice({
    required this.coinGeckoId,
    required this.fiat,
    required this.fiatValue,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': coinGeckoId,
        'fiat': fiat,
        'val': fiatValue,
        'at': fetchedAt.toIso8601String(),
      };

  factory _CachedPrice.fromJson(Map<String, dynamic> j) => _CachedPrice(
        coinGeckoId: j['id'] as String,
        fiat: j['fiat'] as String,
        fiatValue: (j['val'] as num).toDouble(),
        fetchedAt:
            DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
