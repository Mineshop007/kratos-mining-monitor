import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/miner.dart';

/// Persists per-miner best-diff history and detects milestone crossings.
///
/// Source: `MinerStats.bestShare` already populated by EspMinerAPI
/// (`bestDiff` field) and CGMinerAPI (`Best Share`).  No invented values.
///
/// Milestones (units = same as bestShare, raw difficulty number):
///   1G = 1e9, 5G, 10G, 25G, 50G, 100G, 250G, 1T = 1e12, 10T, 100T
///
/// On any cross, we emit a `MilestoneEvent`. UI listens via `onEvent`
/// stream. Block-found is detected separately by `MinerStore` already.
class BestDiffTracker extends ChangeNotifier {
  static const _kStorageKey = 'kratos_best_diff_records_v1';

  static const List<double> milestoneThresholds = [
    1e9,    // 1G
    5e9,    // 5G
    1e10,   // 10G
    2.5e10, // 25G
    5e10,   // 50G
    1e11,   // 100G
    2.5e11, // 250G
    1e12,   // 1T
    1e13,   // 10T
    1e14,   // 100T
  ];

  /// Per-miner all-time best (stable across app restarts).
  final Map<String, _BestDiffRecord> _records = {};

  final StreamController<MilestoneEvent> _eventCtrl =
      StreamController<MilestoneEvent>.broadcast();

  Stream<MilestoneEvent> get onEvent => _eventCtrl.stream;

  Map<String, _BestDiffRecord> get records => Map.unmodifiable(_records);

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _disposed = false;

  BestDiffTracker() {
    _load();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStorageKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          _records[e.key] = _BestDiffRecord.fromJson(
              e.value as Map<String, dynamic>);
        }
      } catch (_) {
        // Silently ignore corrupt cache; never invent values.
      }
    }
    _loaded = true;
    _safeNotify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {for (final e in _records.entries) e.key: e.value.toJson()};
    await prefs.setString(_kStorageKey, jsonEncode(map));
  }

  /// Called by MinerStore on every refresh of a miner. Pure observation —
  /// we never mutate bestShare upward unless the miner reported it.
  void observe({
    required String minerId,
    required String minerName,
    required MinerType type,
    required double bestShare,
    String minerModel = '',
  }) {
    if (bestShare <= 0) return;
    final prev = _records[minerId];

    if (prev == null || bestShare > prev.bestShare) {
      final previousMax = prev?.bestShare ?? 0;
      final crossed = <double>[];
      for (final t in milestoneThresholds) {
        if (previousMax < t && bestShare >= t) crossed.add(t);
      }

      _records[minerId] = _BestDiffRecord(
        minerId: minerId,
        minerName: minerName,
        minerModel: minerModel,
        type: type,
        bestShare: bestShare,
        achievedAt: DateTime.now(),
      );
      _save();
      _safeNotify();

      for (final t in crossed) {
        _eventCtrl.add(MilestoneEvent(
          minerId: minerId,
          minerName: minerName,
          type: type,
          threshold: t,
          actual: bestShare,
          at: DateTime.now(),
        ));
      }
    } else {
      // Keep name + model fresh even if no new record.
      if (prev.minerName != minerName || (minerModel.isNotEmpty && prev.minerModel != minerModel)) {
        _records[minerId] = prev.withMeta(minerName, minerModel);
        _save();
      }
    }
  }

  /// Fleet record across all miners (highest single bestShare ever seen).
  _BestDiffRecord? get fleetRecord {
    if (_records.isEmpty) return null;
    return _records.values.reduce(
      (a, b) => a.bestShare >= b.bestShare ? a : b,
    );
  }

  void forgetMiner(String minerId) {
    _records.remove(minerId);
    _save();
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventCtrl.close();
    super.dispose();
  }
}

class _BestDiffRecord {
  final String minerId;
  final String minerName;
  final String minerModel;
  final MinerType type;
  final double bestShare;
  final DateTime achievedAt;

  _BestDiffRecord({
    required this.minerId,
    required this.minerName,
    this.minerModel = '',
    required this.type,
    required this.bestShare,
    required this.achievedAt,
  });

  _BestDiffRecord withMeta(String name, String model) => _BestDiffRecord(
        minerId: minerId,
        minerName: name,
        minerModel: model.isNotEmpty ? model : minerModel,
        type: type,
        bestShare: bestShare,
        achievedAt: achievedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': minerId,
        'name': minerName,
        'model': minerModel,
        'type': type.name,
        'best': bestShare,
        'at': achievedAt.toIso8601String(),
      };

  factory _BestDiffRecord.fromJson(Map<String, dynamic> j) => _BestDiffRecord(
        minerId: j['id'] as String,
        minerName: j['name'] as String,
        minerModel: j['model'] as String? ?? '',
        type: MinerType.values.firstWhere(
          (t) => t.name == (j['type'] as String? ?? ''),
          orElse: () => MinerType.generic,
        ),
        bestShare: (j['best'] as num).toDouble(),
        achievedAt: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class MilestoneEvent {
  final String minerId;
  final String minerName;
  final MinerType type;
  final double threshold;
  final double actual;
  final DateTime at;

  MilestoneEvent({
    required this.minerId,
    required this.minerName,
    required this.type,
    required this.threshold,
    required this.actual,
    required this.at,
  });

  /// Pretty units for the threshold (e.g. "10G", "1T").
  String get thresholdLabel => formatBestDiff(threshold);

  /// Pretty units for the actual value.
  String get actualLabel => formatBestDiff(actual);
}

/// Formats raw difficulty to short units. Real numbers only.
String formatBestDiff(double v) {
  if (v <= 0) return '—';
  if (v >= 1e15) return '${(v / 1e15).toStringAsFixed(1)}P';
  if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9)  return '${(v / 1e9).toStringAsFixed(2)}G';
  if (v >= 1e6)  return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3)  return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

/// Pretty‑typed export of a record for UI use without leaking the
/// private class.
class BestDiffRecordView {
  final String minerId;
  final String minerName;
  final String minerModel;
  final MinerType type;
  final double bestShare;
  final DateTime achievedAt;

  const BestDiffRecordView({
    required this.minerId,
    required this.minerName,
    this.minerModel = '',
    required this.type,
    required this.bestShare,
    required this.achievedAt,
  });

  factory BestDiffRecordView.from(_BestDiffRecord r) => BestDiffRecordView(
        minerId: r.minerId,
        minerName: r.minerName,
        minerModel: r.minerModel,
        type: r.type,
        bestShare: r.bestShare,
        achievedAt: r.achievedAt,
      );
}
