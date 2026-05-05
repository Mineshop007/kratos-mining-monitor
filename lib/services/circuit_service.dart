import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/miner.dart';
import 'miner_store.dart';

/// Circuit monitoring — group miners onto named electrical circuits and
/// alarm when total draw approaches breaker rating.
///
/// Real data only: total amps comes from each miner's actual reported
/// `MinerStats.powerDraw` (Watts) divided by configured circuit voltage.
/// Miners that never reported power show as "no data" — we never
/// estimate from nameplate ratings.
class CircuitService extends ChangeNotifier {
  static const _kKey = 'kratos_circuits_v1';

  final List<Circuit> _circuits = [];
  bool _loaded = false;
  bool _disposed = false;

  bool get loaded => _loaded;
  List<Circuit> get circuits => List.unmodifiable(_circuits);

  CircuitService() {
    _load();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _circuits
          ..clear()
          ..addAll(list.map((j) => Circuit.fromJson(j as Map<String, dynamic>)));
      } catch (_) {
        // ignore corrupt
      }
    }
    _loaded = true;
    _safeNotify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kKey, jsonEncode(_circuits.map((c) => c.toJson()).toList()));
  }

  Future<void> upsert(Circuit c) async {
    final i = _circuits.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      _circuits[i] = c;
    } else {
      _circuits.add(c);
    }
    await _save();
    _safeNotify();
  }

  Future<void> remove(String id) async {
    _circuits.removeWhere((c) => c.id == id);
    await _save();
    _safeNotify();
  }

  /// For UI: snapshot of each circuit + measured draw (real power data).
  List<CircuitSnapshot> snapshots(MinerStore store) {
    return _circuits.map((c) {
      double watts = 0;
      bool anyMeasured = false;
      int onlineCount = 0;
      for (final mid in c.minerIds) {
        final s = store.stats[mid];
        if (s == null) continue;
        if (s.status != MinerStatus.offline) onlineCount += 1;
        if (s.powerDraw > 0) {
          watts += s.powerDraw;
          anyMeasured = true;
        }
      }
      return CircuitSnapshot(
        circuit: c,
        measuredWatts: anyMeasured ? watts : null,
        onlineCount: onlineCount,
      );
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Region presets for typical residential breakers.
enum CircuitPreset {
  eu230v16a,
  eu230v10a,
  us120v15a,
  us120v20a,
  custom,
}

extension CircuitPresetExt on CircuitPreset {
  String get displayName => switch (this) {
        CircuitPreset.eu230v16a => 'EU · 230V · 16A (3.68 kW)',
        CircuitPreset.eu230v10a => 'EU · 230V · 10A (2.30 kW)',
        CircuitPreset.us120v15a => 'US · 120V · 15A (1.80 kW)',
        CircuitPreset.us120v20a => 'US · 120V · 20A (2.40 kW)',
        CircuitPreset.custom    => 'Custom',
      };

  ({double volts, double amps}) get spec => switch (this) {
        CircuitPreset.eu230v16a => (volts: 230, amps: 16),
        CircuitPreset.eu230v10a => (volts: 230, amps: 10),
        CircuitPreset.us120v15a => (volts: 120, amps: 15),
        CircuitPreset.us120v20a => (volts: 120, amps: 20),
        CircuitPreset.custom    => (volts: 230, amps: 16),
      };
}

class Circuit {
  final String id;
  String name;
  double voltage;          // V
  double breakerAmps;      // A
  double safetyFactor;     // 0..1, recommended ≤ 0.80 for continuous loads
  List<String> minerIds;

  Circuit({
    String? id,
    required this.name,
    required this.voltage,
    required this.breakerAmps,
    this.safetyFactor = 0.80,
    List<String>? minerIds,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        minerIds = minerIds ?? [];

  /// Maximum continuous watts before alerting (kW).
  double get safeWatts => voltage * breakerAmps * safetyFactor;
  double get tripWatts => voltage * breakerAmps;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'volts': voltage,
        'amps': breakerAmps,
        'safety': safetyFactor,
        'miners': minerIds,
      };

  factory Circuit.fromJson(Map<String, dynamic> j) => Circuit(
        id: j['id'] as String,
        name: j['name'] as String,
        voltage: (j['volts'] as num).toDouble(),
        breakerAmps: (j['amps'] as num).toDouble(),
        safetyFactor: (j['safety'] as num?)?.toDouble() ?? 0.80,
        minerIds: List<String>.from(j['miners'] as List? ?? []),
      );
}

class CircuitSnapshot {
  final Circuit circuit;
  /// Null when none of the miners on this circuit reported power data.
  /// **Never invented from nameplate.**
  final double? measuredWatts;
  final int onlineCount;

  CircuitSnapshot({
    required this.circuit,
    required this.measuredWatts,
    required this.onlineCount,
  });

  CircuitStatus get status {
    if (measuredWatts == null) return CircuitStatus.noData;
    final w = measuredWatts!;
    if (w >= circuit.tripWatts) return CircuitStatus.overload;
    if (w >= circuit.safeWatts) return CircuitStatus.warning;
    return CircuitStatus.ok;
  }

  double? get loadFraction =>
      measuredWatts == null ? null : measuredWatts! / circuit.tripWatts;

  double? get amps =>
      measuredWatts == null ? null : measuredWatts! / circuit.voltage;
}

enum CircuitStatus { ok, warning, overload, noData }
