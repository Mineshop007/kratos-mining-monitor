import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/miner.dart';
import 'cgminer_api.dart';
import 'esp_miner_api.dart';
import 'btc_price.dart';
import 'notification_service.dart';
import 'best_diff_tracker.dart';
import 'haptic_service.dart';

class MinerStore extends ChangeNotifier {
  final List<Miner> miners = [];
  final Map<String, MinerStats> stats = {};
  final Map<String, Timer> _timers = {};
  final Map<String, MinerStats> _prevStats = {};
  Timer? _priceTimer;

  // BTC price (cached, refreshed periodically)
  double btcPrice = 0;
  double kwhPrice = 0.12; // $/kWh — user-configurable

  // Block-found notification for UI (cleared after dialog shown)
  Miner? pendingBlockFoundMiner;

  /// Cross-cutting tracker for per-miner best-diff records and milestone
  /// detection. Lives on MinerStore so every poll updates it from the
  /// already-fetched MinerStats.bestShare. Real numbers only.
  final BestDiffTracker bestDiffTracker = BestDiffTracker();

  MinerStore() {
    _load();
    _schedulePriceRefresh();
  }

  void add(Miner miner) {
    miners.add(miner);
    _save();
    _startPolling(miner);
    notifyListeners();
  }

  void remove(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    stats.remove(id);
    _prevStats.remove(id);
    miners.removeWhere((m) => m.id == id);
    _save();
    notifyListeners();
  }

  void reinsert(Miner miner, int index) {
    miners.insert(index.clamp(0, miners.length), miner);
    _save();
    _startPolling(miner);
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await Future.wait(miners.map(_fetch));
  }

  void refreshOne(Miner miner) => _fetch(miner);

  void clearBlockFound() {
    pendingBlockFoundMiner = null;
    notifyListeners();
  }

  Future<void> _fetch(Miner miner) async {
    final MinerStats rawStats;
    if (miner.type.apiType == ApiType.espMinerHttp) {
      rawStats = await EspMinerAPI.instance.fetchAll(miner.ip, miner.port, remoteUrl: miner.remoteUrl);
    } else {
      rawStats = await CGMinerAPI.instance.fetchAll(miner.ip, miner.port, remoteUrl: miner.remoteUrl);
    }

    // Accumulate hashrate history (last 30 readings)
    final prev = stats[miner.id];
    final history = List<double>.from(prev?.hashrateHistory ?? []);
    if (rawStats.status != MinerStatus.offline && rawStats.hashrateAvg > 0) {
      history.add(rawStats.hashrateAvg);
      if (history.length > 30) history.removeAt(0);
    }
    final s = rawStats.withHistory(history);

    // Notification + block-found checks
    final prevStat = _prevStats[miner.id];
    if (prevStat != null) {
      if (prevStat.status != MinerStatus.offline &&
          s.status == MinerStatus.offline) {
        NotificationService.instance.notifyMinerOffline(miner.name);
      }
      if (prevStat.outTemp <= 85 && s.outTemp > 85) {
        NotificationService.instance.notifyHighTemperature(miner.name, s.outTemp);
      }
      if (!prevStat.blockFound && s.blockFound) {
        NotificationService.instance.notifyBlockFoundAlert(miner.name);
        pendingBlockFoundMiner = miner;
        HapticService.instance.onBlockFound();
      }
      if (!prevStat.isUsingFallbackStratum && s.isUsingFallbackStratum) {
        NotificationService.instance.notifyPoolSwitched(miner.name);
      }
      // Haptic on each newly-accepted share. Real delta only — never
      // fire on stratum-reconnect resets (count went down) or stale data.
      if (s.status != MinerStatus.offline &&
          s.accepted > prevStat.accepted &&
          (s.accepted - prevStat.accepted) <= 50 /* sanity bound */) {
        final delta = s.accepted - prevStat.accepted;
        for (var i = 0; i < delta && i < 3; i++) {
          // Stagger up to 3 quick pulses for batched share deltas.
          Future.delayed(Duration(milliseconds: 80 * i), () {
            HapticService.instance.onShareAccepted();
          });
        }
      }
    }

    _prevStats[miner.id] = s;
    stats[miner.id] = s;

    // Feed the best-diff tracker with the real, observed value only.
    bestDiffTracker.observe(
      minerId: miner.id,
      minerName: miner.name,
      type: miner.type,
      bestShare: s.bestShare,
    );

    // Auto-detect name from model if default name
    if (s.model.isNotEmpty && miner.name.startsWith('Miner at ')) {
      miner.name = s.model;
      _save();
    }
    notifyListeners();
  }

  void _startPolling(Miner miner) {
    _timers[miner.id]?.cancel();
    _fetch(miner);
    _timers[miner.id] =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetch(miner));
  }

  void _schedulePriceRefresh() {
    _refreshPrice();
    _priceTimer?.cancel();
    _priceTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _refreshPrice());
  }

  Future<void> _refreshPrice() async {
    final price = await BtcPriceService.instance.getBtcPrice();
    if (price != btcPrice) {
      btcPrice = price;
      notifyListeners();
    }
  }

  Future<void> setKwhPrice(double price) async {
    kwhPrice = price;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('kratos_kwh_price', price);
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(miners.map((m) => m.toJson()).toList());
    await prefs.setString('kratos_miners', data);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('kratos_miners');
    if (data != null) {
      final list = jsonDecode(data) as List;
      miners.addAll(
          list.map((j) => Miner.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
      for (final m in miners) {
        _startPolling(m);
      }
    }
    kwhPrice = prefs.getDouble('kratos_kwh_price') ?? 0.12;
  }

  // ── Computed ─────────────────────────────────────────────────────────────

  double get totalHashrate => stats.values
      .where((s) =>
          s.status == MinerStatus.online || s.status == MinerStatus.warning)
      .fold(0, (sum, s) => sum + s.hashrateAvg);

  double get totalPower => stats.values
      .where((s) => s.status != MinerStatus.offline)
      .fold(0, (sum, s) => sum + s.powerDraw);

  double get totalDailyEarningsUsd =>
      BtcPriceService.instance.dailyEarningsUsdSync(totalHashrate, btcPrice);

  double get totalDailyCostUsd =>
      BtcPriceService.instance.dailyCostUsd(totalPower, kwhPrice);

  double minerDailyEarningsUsd(String minerId) {
    final s = stats[minerId];
    if (s == null) return 0;
    return BtcPriceService.instance.dailyEarningsUsdSync(s.hashrateAvg, btcPrice);
  }

  double minerDailyCostUsd(String minerId) {
    final s = stats[minerId];
    if (s == null) return 0;
    return BtcPriceService.instance.dailyCostUsd(s.powerDraw, kwhPrice);
  }

  int get onlineCount => stats.values
      .where((s) =>
          s.status == MinerStatus.online || s.status == MinerStatus.warning)
      .length;

  int get warningCount =>
      stats.values.where((s) => s.status == MinerStatus.warning).length;

  int get offlineCount =>
      stats.values.where((s) => s.status == MinerStatus.offline).length;

  @override
  void dispose() {
    _priceTimer?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    bestDiffTracker.dispose();
    super.dispose();
  }
}
