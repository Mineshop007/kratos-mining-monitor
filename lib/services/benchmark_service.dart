import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/miner.dart';
import 'miner_store.dart';

class BenchmarkModelStats {
  final String model;
  final int sampleCount;
  final int deviceCount;
  final double avgHashrateGh;
  final double avgEfficiencyJTh;
  final double avgTempBoard;
  final double avgTempChip;
  final double avgPowerW;
  final double avgStabilityPct;
  final int topFreqMhz;
  final int topVoltageMv;

  const BenchmarkModelStats({
    required this.model,
    required this.sampleCount,
    required this.deviceCount,
    required this.avgHashrateGh,
    required this.avgEfficiencyJTh,
    required this.avgTempBoard,
    required this.avgTempChip,
    required this.avgPowerW,
    required this.avgStabilityPct,
    required this.topFreqMhz,
    required this.topVoltageMv,
  });

  factory BenchmarkModelStats.fromJson(Map<String, dynamic> json) {
    return BenchmarkModelStats(
      model: json['model'] as String? ?? '',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      deviceCount: (json['deviceCount'] as num?)?.toInt() ?? 0,
      avgHashrateGh: (json['avgHashrateGh'] as num?)?.toDouble() ?? 0,
      avgEfficiencyJTh: (json['avgEfficiencyJTh'] as num?)?.toDouble() ?? 0,
      avgTempBoard: (json['avgTempBoard'] as num?)?.toDouble() ?? 0,
      avgTempChip: (json['avgTempChip'] as num?)?.toDouble() ?? 0,
      avgPowerW: (json['avgPowerW'] as num?)?.toDouble() ?? 0,
      avgStabilityPct: (json['avgStabilityPct'] as num?)?.toDouble() ?? 0,
      topFreqMhz: (json['topFreqMhz'] as num?)?.toInt() ?? 0,
      topVoltageMv: (json['topVoltageMv'] as num?)?.toInt() ?? 0,
    );
  }
}

class BenchmarkConfig {
  final int freqMhz;
  final int voltageMv;
  final int sampleCount;
  final double avgHashrateGh;
  final double avgEfficiencyJTh;
  final double avgTempBoard;
  final double avgStabilityPct;
  final String badge;

  const BenchmarkConfig({
    required this.freqMhz,
    required this.voltageMv,
    required this.sampleCount,
    required this.avgHashrateGh,
    required this.avgEfficiencyJTh,
    required this.avgTempBoard,
    required this.avgStabilityPct,
    required this.badge,
  });

  factory BenchmarkConfig.fromJson(Map<String, dynamic> json) {
    return BenchmarkConfig(
      freqMhz: (json['freqMhz'] as num?)?.toInt() ?? 0,
      voltageMv: (json['voltageMv'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      avgHashrateGh: (json['avgHashrateGh'] as num?)?.toDouble() ?? 0,
      avgEfficiencyJTh: (json['avgEfficiencyJTh'] as num?)?.toDouble() ?? 0,
      avgTempBoard: (json['avgTempBoard'] as num?)?.toDouble() ?? 0,
      avgStabilityPct: (json['avgStabilityPct'] as num?)?.toDouble() ?? 0,
      badge: json['badge'] as String? ?? '',
    );
  }
}

class BenchmarkGlobalStats {
  final int totalSamples;
  final int totalDevices;
  final int modelCount;

  const BenchmarkGlobalStats({
    required this.totalSamples,
    required this.totalDevices,
    required this.modelCount,
  });

  factory BenchmarkGlobalStats.fromJson(Map<String, dynamic> json) {
    return BenchmarkGlobalStats(
      totalSamples: (json['totalSamples'] as num?)?.toInt() ?? 0,
      totalDevices: (json['totalDevices'] as num?)?.toInt() ?? 0,
      modelCount: (json['modelCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class BenchmarkDeviceModel {
  final String model;
  final int sampleCount;

  const BenchmarkDeviceModel({required this.model, required this.sampleCount});

  factory BenchmarkDeviceModel.fromJson(Map<String, dynamic> json) {
    return BenchmarkDeviceModel(
      model: json['model'] as String? ?? '',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class BenchmarkService extends ChangeNotifier {
  static final BenchmarkService instance = BenchmarkService._();
  BenchmarkService._();

  static const _apiBase = 'https://soloblocks.io/api/benchmark';
  static const _collectInterval = Duration(minutes: 30);
  static const _settleDelay = Duration(minutes: 5);
  static const _prefKey = 'benchmark_enabled';

  MinerStore? _store;
  Timer? _timer;
  bool _enabled = true;
  bool _initialized = false;
  DateTime? _lastSubmittedAt;
  final Map<String, BenchmarkModelStats> _statsCache = {};
  final Map<String, List<BenchmarkConfig>> _topCache = {};

  bool get enabled => _enabled;

  void attachStore(MinerStore store) {
    _store = store;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
    _startCollection();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (value) {
      _startCollection();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  Future<BenchmarkModelStats?> getStats(String model) async {
    final key = model.trim();
    if (key.isEmpty) return null;
    final cached = _statsCache[key];
    if (cached != null) return cached;
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/${Uri.encodeComponent(key)}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final stats =
          BenchmarkModelStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      _statsCache[key] = stats;
      return stats;
    } catch (_) {
      return null;
    }
  }

  Future<List<BenchmarkConfig>> getTopConfigs(String model) async {
    final key = model.trim();
    if (key.isEmpty) return const [];
    final cached = _topCache[key];
    if (cached != null) return cached;
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/${Uri.encodeComponent(key)}/top'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final list = (jsonDecode(res.body) as List)
          .map((item) => BenchmarkConfig.fromJson(item as Map<String, dynamic>))
          .toList();
      _topCache[key] = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<BenchmarkGlobalStats> getGlobalStats() async {
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/stats'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return BenchmarkGlobalStats.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const BenchmarkGlobalStats(
      totalSamples: 0,
      totalDevices: 0,
      modelCount: 0,
    );
  }

  Future<List<BenchmarkDeviceModel>> getModels() async {
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/models'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      return (jsonDecode(res.body) as List)
          .map((item) => BenchmarkDeviceModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _startCollection() {
    _timer?.cancel();
    if (!_enabled) return;
    _timer = Timer.periodic(_collectInterval, (_) => _collectAndSubmit());
    Future.delayed(const Duration(seconds: 20), _collectAndSubmit);
  }

  Future<void> _collectAndSubmit() async {
    if (!_enabled) return;
    if (_lastSubmittedAt != null &&
        DateTime.now().difference(_lastSubmittedAt!) < _settleDelay) {
      return;
    }
    final store = _store;
    if (store == null) return;

    final samples = <Map<String, dynamic>>[];
    for (final miner in store.miners) {
      final stats = store.stats[miner.id];
      if (stats == null) continue;
      if (stats.status != MinerStatus.online && stats.status != MinerStatus.warning) {
        continue;
      }
      final hashrate = stats.hashrateDisplay;
      final power = stats.powerDraw;
      final efficiency = power > 0 && hashrate > 0 ? power / (hashrate / 1000) : 0;
      if (hashrate <= 0 || efficiency <= 0 || efficiency >= 500) continue;
      final shares = stats.accepted + stats.rejected;
      final model = stats.model.isNotEmpty ? stats.model : miner.type.displayName;
      samples.add({
        'model': model,
        'firmware': stats.firmware,
        'freq_mhz': stats.frequency > 0 ? stats.frequency.round() : null,
        'voltage_mv': stats.coreVoltage > 0 ? stats.coreVoltage : null,
        'hashrate_gh': hashrate,
        'power_w': power > 0 ? power : null,
        'efficiency_j_th': efficiency,
        'temp_board': stats.outTemp > 0 ? stats.outTemp : null,
        'temp_chip': stats.vrTemp > 0 ? stats.vrTemp : null,
        'fan_rpm': stats.fanRPM > 0 ? stats.fanRPM : null,
        'accepted': stats.accepted,
        'rejected': stats.rejected,
        'uptime_seconds': stats.uptime,
        'stability_pct': shares > 0 ? stats.accepted / shares * 100 : null,
        if (_regionFromIp(miner.ip) != null) 'region': _regionFromIp(miner.ip),
      });
      if (samples.length >= 20) break;
    }
    if (samples.isEmpty) return;

    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/ingest'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'samples': samples}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _lastSubmittedAt = DateTime.now();
        _statsCache.clear();
        _topCache.clear();
      }
    } catch (_) {}
  }

  String? _regionFromIp(String ip) {
    final parts = ip.split('.');
    if (parts.length < 2) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return null;
    return '$a.$b';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
