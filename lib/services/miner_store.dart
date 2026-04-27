import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/miner.dart';
import 'cgminer_api.dart';
import 'avalon_api.dart';

class MinerStore extends ChangeNotifier {
  final List<Miner> miners = [];
  final Map<String, MinerStats> stats = {};
  final Map<String, Timer> _timers = {};

  MinerStore() { _load(); }

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
    miners.removeWhere((m) => m.id == id);
    _save();
    notifyListeners();
  }

  // Re-insert a miner at a specific index (used for undo delete)
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

  Future<void> _fetch(Miner miner) async {
    final MinerStats s;
    if (miner.type.isAvalonHttp) {
      s = await AvalonAPI.instance.fetchStats(miner.ip, miner.type);
    } else {
      s = await CGMinerAPI.instance.fetchAll(miner.ip, miner.port);
    }
    stats[miner.id] = s;
    // Auto-detect name from model if not customised
    if (s.model.isNotEmpty && miner.name.startsWith('Miner at ')) {
      miner.name = s.model;
      _save();
    }
    notifyListeners();
  }

  void _startPolling(Miner miner) {
    _timers[miner.id]?.cancel();
    _fetch(miner);
    _timers[miner.id] = Timer.periodic(const Duration(seconds: 30), (_) => _fetch(miner));
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
      miners.addAll(list.map((j) => Miner.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
      for (final m in miners) { _startPolling(m); }
    }
  }

  // ── Computed ─────────────────────────────────────────────────────────────

  double get totalHashrate => stats.values
    .where((s) => s.status == MinerStatus.online)
    .fold(0, (sum, s) => sum + s.hashrateAvg);

  int get onlineCount => stats.values
    .where((s) => s.status == MinerStatus.online).length;

  int get warningCount => stats.values
    .where((s) => s.status == MinerStatus.warning).length;

  int get offlineCount => stats.values
    .where((s) => s.status == MinerStatus.offline).length;

  @override
  void dispose() {
    for (final t in _timers.values) { t.cancel(); }
    super.dispose();
  }
}
