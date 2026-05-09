import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/mining_schedule.dart';
import '../models/miner.dart';
import 'cgminer_api.dart';

class ScheduleService {
  static final ScheduleService instance = ScheduleService._();
  ScheduleService._();

  Database? _db;
  final Map<String, ScheduleAction> _lastApplied = {};
  Timer? _ticker;

  Future<void> init() async {
    final dbPath = '${await getDatabasesPath()}/miner_schedules.db';
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE schedules (miner_id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
    });
    // Evaluate every minute while app is running
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tickAll());
  }

  void dispose() {
    _ticker?.cancel();
    _db?.close();
  }

  Future<MinerSchedule> load(String minerId) async {
    final db = _db;
    if (db == null) return MinerSchedule(minerId: minerId);
    final rows = await db.query('schedules',
        where: 'miner_id = ?', whereArgs: [minerId]);
    if (rows.isEmpty) return MinerSchedule(minerId: minerId);
    return MinerSchedule.fromJson(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<void> save(MinerSchedule schedule) async {
    final db = _db;
    if (db == null) return;
    await db.insert(
      'schedules',
      {'miner_id': schedule.minerId, 'data': jsonEncode(schedule.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String minerId) async {
    await _db?.delete('schedules', where: 'miner_id = ?', whereArgs: [minerId]);
    _lastApplied.remove(minerId);
  }

  /// Evaluate + apply schedule for a miner. Call on app foreground + from tick.
  Future<bool> applyIfNeeded(Miner miner) async {
    final schedule = await load(miner.ip);
    if (!schedule.enabled || schedule.rules.isEmpty) return false;
    final action = schedule.evaluate(DateTime.now());
    if (action == ScheduleAction.none) return false;
    if (_lastApplied[miner.ip] == action) return false;
    final ok = await _applyAction(miner, action);
    if (ok) _lastApplied[miner.ip] = action;
    return ok;
  }

  /// Force-clear the last-applied cache so next tick re-applies
  void resetCache(String minerId) => _lastApplied.remove(minerId);

  Future<bool> _applyAction(Miner miner, ScheduleAction action) async {
    switch (action) {
      case ScheduleAction.eco:
        return CGMinerAPI.instance.setWorkMode(miner.ip, miner.port, 0,
            remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      case ScheduleAction.standard:
        return CGMinerAPI.instance.setWorkMode(miner.ip, miner.port, 1,
            remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      case ScheduleAction.superMode:
        return CGMinerAPI.instance.setWorkMode(miner.ip, miner.port, 2,
            remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      case ScheduleAction.standby:
        return CGMinerAPI.instance.softOff(miner.ip, miner.port,
            remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      case ScheduleAction.wake:
        return CGMinerAPI.instance.softOn(miner.ip, miner.port,
            remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
      case ScheduleAction.none:
        return true;
    }
  }

  Future<void> _tickAll() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query('schedules');
    for (final row in rows) {
      try {
        final schedule = MinerSchedule.fromJson(
            jsonDecode(row['data'] as String) as Map<String, dynamic>);
        if (!schedule.enabled) continue;
        // Minimal Miner for applying action (full stats not needed here)
        final miner = Miner(
          name: schedule.minerId,
          ip: schedule.minerId,
          port: 4028,
          type: MinerType.avalonQ,
        );
        await applyIfNeeded(miner);
      } catch (_) {}
    }
  }

  /// Human-readable status: "Active: 🔥 Super" or "Next: 🌿 Eco in 2h 15m"
  String statusLabel(MinerSchedule schedule) {
    if (!schedule.enabled || schedule.rules.isEmpty) return 'Schedule off';
    final now = DateTime.now();
    final current = schedule.evaluate(now);
    if (current != ScheduleAction.none) {
      return 'Active: ${current.emoji} ${current.label}';
    }
    ScheduleRule? nextRule;
    int? minsUntil;
    for (final rule in schedule.rules.where((r) => r.enabled)) {
      for (int d = 0; d < 7; d++) {
        final candidate = now.add(Duration(days: d));
        if (!rule.days.contains(candidate.weekday - 1)) continue;
        final rStart = DateTime(candidate.year, candidate.month, candidate.day,
            rule.startTime.hour, rule.startTime.minute);
        final diff = rStart.difference(now).inMinutes;
        if (diff > 0 && (minsUntil == null || diff < minsUntil)) {
          minsUntil = diff;
          nextRule = rule;
        }
      }
    }
    if (nextRule == null) return 'No upcoming rules';
    final h = minsUntil! ~/ 60;
    final m = minsUntil % 60;
    final t = h > 0 ? '${h}h ${m}m' : '${m}m';
    return 'Next: ${nextRule.action.emoji} ${nextRule.action.label} in $t';
  }
}
