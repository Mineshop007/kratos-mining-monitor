import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/miner.dart';

final _ipAddressPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

String _safeLeaderboardName(String name,
    {String model = '', String type = ''}) {
  final trimmed = name.trim();
  final fallback = model.trim().isNotEmpty
      ? model.trim()
      : (type.trim().isNotEmpty ? type.trim() : 'Kratos miner');
  if (trimmed.isEmpty ||
      _ipAddressPattern.hasMatch(trimmed) ||
      trimmed.toLowerCase().startsWith('miner at ')) {
    return fallback;
  }
  return trimmed;
}

/// Submits best-diff records to the global Kratos leaderboard and
/// fetches the worldwide top list for display in the Hall of Fame.
class GlobalLeaderboardService extends ChangeNotifier {
  static final GlobalLeaderboardService instance = GlobalLeaderboardService._();
  GlobalLeaderboardService._();

  static const _base = 'https://kratos.mineshop.eu/bestdiff';
  static const _timeout = Duration(seconds: 10);

  List<GlobalDiffRecord> leaderboard = [];
  GlobalStats? stats;
  bool loading = false;
  String? error;
  DateTime? lastFetched;

  // ── Submit a new personal record ─────────────────────────────────────────

  Future<void> submit({
    required String minerId,
    required String minerName,
    required String minerModel,
    required MinerType type,
    required double bestDiff,
    required DateTime achievedAt,
    String appVersion = '1.9.1',
  }) async {
    if (bestDiff <= 0) return;
    try {
      final safeName = _safeLeaderboardName(
        minerName,
        model: minerModel,
        type: type.name,
      );
      await http
          .post(
            Uri.parse('$_base/submit'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'miner_id': minerId,
              'miner_name': safeName,
              'miner_model': minerModel,
              'miner_type': type.name,
              'best_diff': bestDiff,
              'achieved_at': achievedAt.millisecondsSinceEpoch ~/ 1000,
              'app_version': appVersion,
            }),
          )
          .timeout(_timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('GlobalLeaderboard: submit error: $e');
    }
  }

  // ── Fetch global leaderboard ──────────────────────────────────────────────

  Future<void> fetchLeaderboard({bool force = false}) async {
    // Don't re-fetch within 60 seconds unless forced
    if (!force &&
        lastFetched != null &&
        DateTime.now().difference(lastFetched!) < const Duration(seconds: 60)) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      final res = await http
          .get(
            Uri.parse('$_base/leaderboard?limit=100'),
          )
          .timeout(_timeout);

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        leaderboard = list.map((j) => GlobalDiffRecord.fromJson(j)).toList();
        lastFetched = DateTime.now();
        error = null;
      } else {
        error = 'Server error ${res.statusCode}';
      }

      // Also fetch stats
      final sRes = await http.get(Uri.parse('$_base/stats')).timeout(_timeout);
      if (sRes.statusCode == 200) {
        stats = GlobalStats.fromJson(jsonDecode(sRes.body));
      }
    } catch (e) {
      error = 'Could not load global leaderboard';
      if (kDebugMode) debugPrint('GlobalLeaderboard: fetch error: $e');
    }

    loading = false;
    notifyListeners();
  }
}

class GlobalDiffRecord {
  final int rank;
  final String name;
  final String model;
  final String type;
  final double bestDiff;
  final DateTime achievedAt;

  const GlobalDiffRecord({
    required this.rank,
    required this.name,
    required this.model,
    required this.type,
    required this.bestDiff,
    required this.achievedAt,
  });

  factory GlobalDiffRecord.fromJson(Map<String, dynamic> j) => GlobalDiffRecord(
        rank: (j['rank'] as num).toInt(),
        name: _safeLeaderboardName(
          j['name'] as String? ?? '',
          model: j['model'] as String? ?? '',
          type: j['type'] as String? ?? '',
        ),
        model: j['model'] as String? ?? '',
        type: j['type'] as String? ?? '',
        bestDiff: (j['best_diff'] as num).toDouble(),
        achievedAt: DateTime.fromMillisecondsSinceEpoch(
            ((j['achieved_at'] as num?)?.toInt() ?? 0) * 1000),
      );
}

class GlobalStats {
  final int totalMiners;
  final GlobalDiffRecord? allTimeRecord;

  const GlobalStats({required this.totalMiners, this.allTimeRecord});

  factory GlobalStats.fromJson(Map<String, dynamic> j) {
    final rec = j['all_time_record'];
    return GlobalStats(
      totalMiners: (j['total_miners'] as num?)?.toInt() ?? 0,
      allTimeRecord:
          rec != null ? GlobalDiffRecord.fromJson({...rec, 'rank': 1}) : null,
    );
  }
}
