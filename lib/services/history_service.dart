import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One persisted hashrate sample for a miner.
class HistoryPoint {
  final DateTime ts;
  final double hashrate; // GH/s
  final double temp;     // °C
  const HistoryPoint({required this.ts, required this.hashrate, required this.temp});
}

/// SQLite-backed rolling history of miner hashrate + temperature.
/// Stores readings for up to 7 days, pruned on init.
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  Database? _db;
  bool _initStarted = false;
  Completer<void>? _ready;

  Future<void> init() async {
    if (_db != null) return;
    if (_ready != null) return _ready!.future;
    _ready = Completer<void>();
    _initStarted = true;
    try {
      final dbPath = p.join(await getDatabasesPath(), 'kratos_history.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE hashrate_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              miner_id TEXT NOT NULL,
              ts INTEGER NOT NULL,
              hashrate REAL NOT NULL,
              temp REAL NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_history_miner_ts ON hashrate_history (miner_id, ts)');
        },
      );
      await pruneOlderThan(const Duration(days: 7));
      _ready!.complete();
    } catch (e) {
      _ready!.completeError(e);
      _db = null;
      _initStarted = false;
      rethrow;
    }
  }

  /// Record a single sample. Silent no-op if DB unavailable or hashrate invalid.
  Future<void> record(String minerId, double hashrate, double temp) async {
    if (hashrate <= 0) return;
    final db = _db;
    if (db == null) {
      // Try lazy init but never throw to caller — hot path.
      if (!_initStarted) {
        // ignore: unawaited_futures
        init();
      }
      return;
    }
    try {
      await db.insert('hashrate_history', {
        'miner_id': minerId,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'hashrate': hashrate,
        'temp': temp,
      });
    } catch (_) {/* swallow — non-critical */}
  }

  /// Return readings for [minerId] from [since] (inclusive) to now, ascending by time.
  Future<List<HistoryPoint>> getHistory(String minerId,
      {required DateTime since}) async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await db.query(
        'hashrate_history',
        where: 'miner_id = ? AND ts >= ?',
        whereArgs: [minerId, since.millisecondsSinceEpoch],
        orderBy: 'ts ASC',
      );
      return rows
          .map((r) => HistoryPoint(
                ts: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
                hashrate: (r['hashrate'] as num).toDouble(),
                temp: (r['temp'] as num).toDouble(),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Return summed fleet hashrate samples across [minerIds] from [since] to now.
  /// Samples are bucketed per [bucket] (default 5 minutes); within a bucket the
  /// last reading from each miner is summed. Empty buckets are skipped.
  Future<List<HistoryPoint>> getFleetHistory(
    List<String> minerIds, {
    required DateTime since,
    Duration bucket = const Duration(minutes: 5),
  }) async {
    if (minerIds.isEmpty) return const [];
    final db = _db;
    if (db == null) return const [];
    try {
      final placeholders = List.filled(minerIds.length, '?').join(',');
      final rows = await db.query(
        'hashrate_history',
        where: 'miner_id IN ($placeholders) AND ts >= ?',
        whereArgs: [...minerIds, since.millisecondsSinceEpoch],
        orderBy: 'ts ASC',
      );
      if (rows.isEmpty) return const [];
      final bucketMs = bucket.inMilliseconds;
      // bucketStart -> minerId -> latest hashrate in that bucket
      final Map<int, Map<String, double>> agg = {};
      for (final r in rows) {
        final ts = r['ts'] as int;
        final b = (ts ~/ bucketMs) * bucketMs;
        final mid = r['miner_id'] as String;
        final hr = (r['hashrate'] as num).toDouble();
        agg.putIfAbsent(b, () => {})[mid] = hr;
      }
      final keys = agg.keys.toList()..sort();
      return keys
          .map((b) => HistoryPoint(
                ts: DateTime.fromMillisecondsSinceEpoch(b),
                hashrate: agg[b]!.values.fold(0.0, (a, v) => a + v),
                temp: 0,
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> pruneOlderThan(Duration age) async {
    final db = _db;
    if (db == null) return;
    final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
    try {
      await db.delete('hashrate_history',
          where: 'ts < ?', whereArgs: [cutoff]);
    } catch (_) {}
  }
}
