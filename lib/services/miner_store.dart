import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coin.dart';
import '../models/miner.dart';
import 'cgminer_api.dart';
import 'esp_miner_api.dart';
import 'avalon_api.dart';
import 'relay_service.dart';
import 'global_leaderboard_service.dart';
import 'btc_price.dart';
import 'notification_service.dart';
import 'best_diff_tracker.dart';
import 'haptic_service.dart';
import 'widget_service.dart';
import 'history_service.dart';

class MinerStore extends ChangeNotifier {
  final List<Miner> miners = [];
  final Map<String, MinerStats> stats = {};
  final Map<String, Timer> _timers = {};
  final Map<String, MinerStats> _prevStats = {};
  final Map<String, int> _offlineStreaks = {};
  final Set<String> _offlineAlertSent = {};
  final Set<String> _seenOnline = {};
  Timer? _priceTimer;
  bool _disposed = false;

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

  void add(Miner miner, {bool warmUp = false}) {
    miners.add(miner);
    _save();
    _startPolling(miner, warmUp: warmUp);
    notifyListeners();
  }

  void remove(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    stats.remove(id);
    _prevStats.remove(id);
    _offlineStreaks.remove(id);
    _offlineAlertSent.remove(id);
    _seenOnline.remove(id);
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
    MinerStats rawStats;
    if (miner.type.apiType == ApiType.espMinerHttp) {
      rawStats = await EspMinerAPI.instance.fetchAll(miner.ip, miner.port,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
    } else if (miner.type.apiType == ApiType.avalonHttp) {
      // Canaan Avalon devices: HTTP REST first, supplement missing fields from CGMiner
      rawStats = await AvalonAPI.instance.fetchStats(miner.ip, miner.type,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      // On LAN: always query CGMiner TCP too — HTTP doesn't return bestShare/pools on all firmware
      if (!miner.isRemote) {
        final cgStats = await CGMinerAPI.instance
            .fetchAll(miner.ip, 4028, remoteUrl: miner.remoteUrl);
        if (cgStats.status == MinerStatus.offline) {
          // CGMiner unavailable — use HTTP stats only (already have them)
        } else if (rawStats.status == MinerStatus.offline ||
            (rawStats.hashrate5s == 0 && rawStats.hashrateAvg == 0)) {
          // HTTP failed entirely — use CGMiner
          rawStats = cgStats;
        } else {
          // HTTP has hashrate — supplement any missing fields from CGMiner
          // (bestShare, pools, power, frequency all may be missing from HTTP)
          rawStats = rawStats.supplement(cgStats);
        }
      }
    } else {
      rawStats = await CGMinerAPI.instance.fetchAll(miner.ip, miner.port,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
    }

    // Relay fallback: if direct fetch failed (offline) and this miner was
    // added locally (isRemote=false), try routing through the relay bridge.
    // This makes locally-scanned miners work transparently on mobile data
    // without the user needing to re-add them as remote.
    if (rawStats.status == MinerStatus.offline &&
        !miner.isRemote &&
        RelayService.instance.state == RelayState.bridgeOnline) {
      // For Avalon devices via relay: use isRemote=true (relay forwards HTTP)
      if (miner.type.apiType == ApiType.avalonHttp) {
        final fallback = await AvalonAPI.instance
            .fetchStats(miner.ip, miner.type, isRemote: true);
        if (fallback.status != MinerStatus.offline) {
          rawStats = fallback;
        }
      } else if (miner.type.apiType == ApiType.cgminerTcp) {
        final fallback = await CGMinerAPI.instance
            .fetchAll(miner.ip, miner.port, isRemote: true);
        if (fallback.status != MinerStatus.offline) rawStats = fallback;
      } else {
        final fallback = await EspMinerAPI.instance
            .fetchAll(miner.ip, miner.port, isRemote: true);
        if (fallback.status != MinerStatus.offline) rawStats = fallback;
      }
    }

    // Accumulate hashrate history (last 30 readings)
    final prev = stats[miner.id];
    final history = List<double>.from(prev?.hashrateHistory ?? []);
    if (rawStats.status != MinerStatus.offline &&
        rawStats.hashrateDisplay > 0) {
      history.add(rawStats.hashrateDisplay);
      if (history.length > 30) history.removeAt(0);
    }
    final s = rawStats.withHistory(history);

    // Notification + block-found checks
    final prevStat = _prevStats[miner.id];
    final offlineStreak = _updateOfflineTracking(miner.id, s);
    if (prevStat != null) {
      if (s.status == MinerStatus.offline &&
          _seenOnline.contains(miner.id) &&
          !_offlineAlertSent.contains(miner.id) &&
          offlineStreak >= 3 &&
          _relayReadyForOfflineAlerts()) {
        _offlineAlertSent.add(miner.id);
        NotificationService.instance.notifyMinerOffline(miner.name);
      }
      if (prevStat.outTemp <= 85 && s.outTemp > 85) {
        NotificationService.instance
            .notifyHighTemperature(miner.name, s.outTemp);
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
          // Guard against firing after store is disposed.
          Future.delayed(Duration(milliseconds: 80 * i), () {
            if (_disposed) return;
            HapticService.instance.onShareAccepted();
          });
        }
      }
    }

    _prevStats[miner.id] = s;
    stats[miner.id] = s;

    // Auto-upgrade stored miner type if stats reveal a more specific type
    // (e.g. miner was saved as 'generic' before Avalon detection was added).
    if (s.status != MinerStatus.offline &&
        s.type != MinerType.generic &&
        s.type != miner.type) {
      miner.type = s.type;
      // ignore: unawaited_futures
      save();
    }

    // Persist hashrate sample (real readings only).
    if (s.status != MinerStatus.offline && s.hashrateAvg > 0) {
      // ignore: unawaited_futures
      HistoryService.instance.record(miner.id, s.hashrateAvg, s.outTemp);
    }

    // Feed the best-diff tracker with the real, observed value only.
    final prevBest = bestDiffTracker.records[miner.id]?.bestShare ?? 0;
    bestDiffTracker.observe(
      minerId: miner.id,
      minerName: miner.name,
      minerModel: s.model.isNotEmpty ? s.model : miner.type.displayName,
      type: s.type != MinerType.generic ? s.type : miner.type,
      bestShare: s.bestShare,
    );
    // Submit to global leaderboard when a new personal record is set
    if (s.bestShare > prevBest && s.bestShare > 0) {
      GlobalLeaderboardService.instance.submit(
        minerId: miner.id,
        minerName: miner.name,
        minerModel: s.model.isNotEmpty ? s.model : miner.type.displayName,
        type: s.type != MinerType.generic ? s.type : miner.type,
        bestDiff: s.bestShare,
        achievedAt: DateTime.now(),
      );
    }

    // Auto-detect name from model if default name
    if (s.model.isNotEmpty && miner.name.startsWith('Miner at ')) {
      miner.name = s.model;
      _save();
    }
    notifyListeners();
    // Push latest stats to home screen widget (fire-and-forget)
    WidgetService.instance.update(this).catchError((_) {});
  }

  int _updateOfflineTracking(String minerId, MinerStats current) {
    if (current.status == MinerStatus.offline) {
      final streak = (_offlineStreaks[minerId] ?? 0) + 1;
      _offlineStreaks[minerId] = streak;
      return streak;
    }

    _offlineStreaks[minerId] = 0;
    _offlineAlertSent.remove(minerId);
    _seenOnline.add(minerId);
    return 0;
  }

  bool _relayReadyForOfflineAlerts() {
    final relay = RelayService.instance;
    final hasRelayKey = relay.accessKey != null && relay.accessKey!.isNotEmpty;

    // When the phone is away from the LAN, saved local miners can briefly fail
    // direct polling while the relay reconnects. Do not notify until the bridge
    // is confirmed online, otherwise app startup creates false offline bursts.
    if (hasRelayKey && relay.state != RelayState.bridgeOnline) {
      return false;
    }

    return true;
  }

  void _startPolling(Miner miner, {bool warmUp = false}) {
    _timers[miner.id]?.cancel();
    if (warmUp) {
      // Freshly discovered miner: give the ESP32 a 2 s breather after being
      // probed by the scanner, then retry quickly if still offline.
      Future.delayed(const Duration(seconds: 2), () {
        if (_disposed) return;
        _fetch(miner);
        // Fast-retry: if still offline after 5 s, try once more before
        // settling into the regular 30 s cadence.
        Future.delayed(const Duration(seconds: 5), () {
          if (_disposed) return;
          if (stats[miner.id]?.status == MinerStatus.offline ||
              stats[miner.id] == null) {
            _fetch(miner);
          }
          _timers[miner.id] =
              Timer.periodic(const Duration(seconds: 5), (_) => _fetch(miner));
        });
      });
    } else {
      _fetch(miner);
      _timers[miner.id] =
          Timer.periodic(const Duration(seconds: 5), (_) => _fetch(miner));
    }
  }

  void _schedulePriceRefresh() {
    _refreshPrice();
    _priceTimer?.cancel();
    _priceTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _refreshPrice());
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

  /// Public save — call after mutating a miner's mutable fields in place.
  Future<void> save() => _save();

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
      miners.addAll(list.map((j) => Miner.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
      for (final m in miners) {
        _startPolling(m);
      }
    }
    kwhPrice = prefs.getDouble('kratos_kwh_price') ?? 0.12;
  }

  // ── Computed ─────────────────────────────────────────────────────────────

  // Use live 5s hashrate when available
  double get totalHashrate => stats.values
      .where((s) =>
          s.status == MinerStatus.online || s.status == MinerStatus.warning)
      .fold(0, (sum, s) => sum + s.hashrateDisplay);

  double get totalPower => stats.values
      .where((s) => s.status != MinerStatus.offline)
      .fold(0, (sum, s) => sum + s.powerDraw);

  /// Fleet-wide efficiency in J/TH. 0 when no power data available.
  double get fleetEfficiency {
    final th = totalHashrate / 1000.0; // TH/s
    return (th > 0 && totalPower > 0) ? totalPower / th : 0;
  }

  double get totalDailyEarningsUsd =>
      miners.fold(0, (sum, m) => sum + minerDailyEarningsUsd(m.id));

  double get totalDailyCostUsd =>
      BtcPriceService.instance.dailyCostUsd(totalPower, kwhPrice);

  double minerDailyEarningsUsd(String minerId) {
    final s = stats[minerId];
    if (s == null) return 0;
    Miner? miner;
    for (final m in miners) {
      if (m.id == minerId) {
        miner = m;
        break;
      }
    }
    return BtcPriceService.instance.dailyEarningsUsdForCoin(
      s.hashrateDisplay,
      miner?.coin ?? Coin.btc,
    );
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
    _disposed = true;
    _priceTimer?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    bestDiffTracker.dispose();
    super.dispose();
  }
}
