import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/pool_preset.dart';

class PoolPresetService {
  static final PoolPresetService instance = PoolPresetService._();
  PoolPresetService._();

  Database? _db;

  Future<void> init() async {
    final path = '${await getDatabasesPath()}/pool_presets.db';
    _db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE presets (id TEXT PRIMARY KEY, data TEXT NOT NULL, sort_order INTEGER DEFAULT 0)',
      );
    });
  }

  Future<List<PoolPreset>> loadAll() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query('presets', orderBy: 'sort_order ASC, rowid ASC');
    return rows.map((r) =>
        PoolPreset.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(PoolPreset preset) async {
    final db = _db;
    if (db == null) return;
    await db.insert('presets',
        {'id': preset.id, 'data': jsonEncode(preset.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db?.delete('presets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorder(List<String> orderedIds) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    for (int i = 0; i < orderedIds.length; i++) {
      batch.update('presets', {'sort_order': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
  }
}
