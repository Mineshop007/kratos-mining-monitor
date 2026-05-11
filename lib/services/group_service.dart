import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/miner.dart';
import '../models/miner_group.dart';
import '../services/esp_miner_api.dart';
import '../services/cgminer_api.dart';
import '../services/avalon_api.dart';
import '../services/fluminer_api.dart';

// ── Pool config passed to bulk apply ─────────────────────────────────────────

class GroupPoolConfig {
  final String host1;
  final int port1;
  final String user1;
  final String? host2;
  final int? port2;
  final String? user2;

  const GroupPoolConfig({
    required this.host1,
    required this.port1,
    required this.user1,
    this.host2,
    this.port2,
    this.user2,
  });
}

// ── Result per miner ──────────────────────────────────────────────────────────

class MinerActionResult {
  final String minerId;
  final String minerName;
  final bool success;
  final String? error;
  const MinerActionResult({
    required this.minerId,
    required this.minerName,
    required this.success,
    this.error,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class GroupService extends ChangeNotifier {
  static final GroupService instance = GroupService._();
  GroupService._() { _load(); }

  List<MinerGroup> _groups = [];
  List<MinerGroup> get groups => List.unmodifiable(_groups);

  bool _loaded = false;
  bool get loaded => _loaded;

  static const _key = 'kratos_miner_groups';

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _groups = list.map((e) => MinerGroup.fromJson(e as Map<String, dynamic>)).toList();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_groups.map((g) => g.toJson()).toList()));
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────────

  Future<MinerGroup> createGroup(String name, {String emoji = '⚡', int colorValue = 0xFFF7931A}) async {
    final g = MinerGroup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      emoji: emoji,
      colorValue: colorValue,
    );
    _groups.add(g);
    await _save();
    notifyListeners();
    return g;
  }

  Future<void> updateGroup(String id, {String? name, String? emoji, int? colorValue}) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i < 0) return;
    _groups[i] = _groups[i].copyWith(name: name, emoji: emoji, colorValue: colorValue);
    await _save();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    _groups.removeWhere((g) => g.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> addMinerToGroup(String groupId, String minerId) async {
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i < 0) return;
    if (!_groups[i].minerIds.contains(minerId)) {
      _groups[i].minerIds.add(minerId);
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeMinerFromGroup(String groupId, String minerId) async {
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i < 0) return;
    _groups[i].minerIds.remove(minerId);
    await _save();
    notifyListeners();
  }

  /// Remove miner from ALL groups (called when miner is deleted)
  Future<void> removeMinerFromAll(String minerId) async {
    for (final g in _groups) {
      g.minerIds.remove(minerId);
    }
    await _save();
    notifyListeners();
  }

  /// Get all groups a specific miner belongs to
  List<MinerGroup> groupsForMiner(String minerId) =>
      _groups.where((g) => g.minerIds.contains(minerId)).toList();

  // ── Bulk actions ──────────────────────────────────────────────────────────────

  /// Apply pool config to all miners in a group.
  /// Handles ESP-Miner, AvalonHttp and CGMiner automatically.
  /// Calls [onProgress] after each miner attempt.
  Future<List<MinerActionResult>> applyPoolToGroup(
    String groupId,
    List<Miner> allMiners,
    GroupPoolConfig config, {
    void Function(MinerActionResult)? onProgress,
  }) async {
    final group = _groups.firstWhere((g) => g.id == groupId);
    final miners = allMiners.where((m) => group.minerIds.contains(m.id)).toList();
    final results = <MinerActionResult>[];

    for (final miner in miners) {
      bool ok = false;
      String? error;
      try {
        switch (miner.type.apiType) {
          case ApiType.espMinerHttp:
            ok = await EspMinerAPI.instance.setPool(
              miner.ip, miner.port,
              stratumUrl: config.host1,
              stratumPort: config.port1,
              stratumUser: config.user1,
              fallbackStratumUrl: config.host2,
              fallbackStratumPort: config.port2,
              fallbackStratumUser: config.user2,
              remoteUrl: miner.remoteUrl,
              isRemote: miner.isRemote,
            );
          case ApiType.avalonHttp:
            // Avalon Nano 3S / Nano 3 — HTTP REST, same field format as ESP-Miner
            ok = await AvalonAPI.instance.setPool(
              miner.ip, miner.port,
              host: config.host1,
              poolPort: config.port1,
              user: config.user1,
              fallbackHost: config.host2,
              fallbackPort: config.port2,
              fallbackUser: config.user2,
              remoteUrl: miner.remoteUrl,
              isRemote: miner.isRemote,
            );
          case ApiType.fluMinerHttp:
            ok = await FluMinerAPI.instance.setPool(
              miner.ip, miner.port,
              host: config.host1,
              poolPort: config.port1,
              user: config.user1,
              fallbackHost: config.host2,
              fallbackPort: config.port2,
              fallbackUser: config.user2,
            );
          case ApiType.cgminerTcp:
            // Avalon Mini 3, Q, Antminer etc — CGMiner TCP, needs full stratum URL
            final pools = <Map<String, String>>[
              {
                'url': 'stratum+tcp://${config.host1}:${config.port1}',
                'user': config.user1,
                'pass': 'x',
              },
              if (config.host2 != null && config.host2!.isNotEmpty)
                {
                  'url': 'stratum+tcp://${config.host2}:${config.port2 ?? 3333}',
                  'user': config.user2 ?? config.user1,
                  'pass': 'x',
                },
            ];
            ok = await CGMinerAPI.instance.setPools(
              miner.ip, miner.port, pools,
              remoteUrl: miner.remoteUrl,
              isRemote: miner.isRemote,
            );
        }
      } catch (e) {
        error = e.toString();
      }

      final result = MinerActionResult(
        minerId: miner.id,
        minerName: miner.name,
        success: ok,
        error: error,
      );
      results.add(result);
      onProgress?.call(result);
    }
    return results;
  }

  /// Apply frequency to all ESP-Miner and CGMiner devices in a group.
  Future<List<MinerActionResult>> applyFrequencyToGroup(
    String groupId,
    List<Miner> allMiners,
    int frequencyMhz, {
    void Function(MinerActionResult)? onProgress,
  }) async {
    final group = _groups.firstWhere((g) => g.id == groupId);
    final miners = allMiners.where((m) => group.minerIds.contains(m.id)).toList();
    final results = <MinerActionResult>[];

    for (final miner in miners) {
      bool ok = false;
      String? error;
      try {
        if (miner.type.apiType == ApiType.espMinerHttp) {
          ok = await EspMinerAPI.instance.setFrequency(
              miner.ip, miner.port, frequencyMhz,
              remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
        } else {
          ok = await CGMinerAPI.instance.setFrequency(
              miner.ip, miner.port, frequencyMhz,
              remoteUrl: miner.remoteUrl);
        }
      } catch (e) {
        error = e.toString();
      }
      final r = MinerActionResult(
          minerId: miner.id, minerName: miner.name, success: ok, error: error);
      results.add(r);
      onProgress?.call(r);
    }
    return results;
  }

  /// Restart all miners in a group.
  Future<List<MinerActionResult>> restartGroup(
    String groupId,
    List<Miner> allMiners, {
    void Function(MinerActionResult)? onProgress,
  }) async {
    final group = _groups.firstWhere((g) => g.id == groupId);
    final miners = allMiners.where((m) => group.minerIds.contains(m.id)).toList();
    final results = <MinerActionResult>[];

    for (final miner in miners) {
      bool ok = false;
      try {
        if (miner.type.apiType == ApiType.espMinerHttp) {
          ok = await EspMinerAPI.instance.restart(
              miner.ip, miner.port,
              remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
        } else {
          ok = await CGMinerAPI.instance.restart(
              miner.ip, miner.port, remoteUrl: miner.remoteUrl);
        }
      } catch (_) {}
      final r = MinerActionResult(
          minerId: miner.id, minerName: miner.name, success: ok);
      results.add(r);
      onProgress?.call(r);
    }
    return results;
  }

  /// Apply Avalon work mode (Eco=0, Normal=1, Performance=2) to all CGMiner devices.
  Future<List<MinerActionResult>> applyWorkModeToGroup(
    String groupId,
    List<Miner> allMiners,
    int mode, {
    void Function(MinerActionResult)? onProgress,
  }) async {
    final group = _groups.firstWhere((g) => g.id == groupId);
    final miners = allMiners
        .where((m) =>
            group.minerIds.contains(m.id) &&
            m.type.apiType == ApiType.cgminerTcp)
        .toList();
    final results = <MinerActionResult>[];
    for (final miner in miners) {
      bool ok = false;
      try {
        ok = await CGMinerAPI.instance.setWorkMode(
            miner.ip, miner.port, mode,
            remoteUrl: miner.remoteUrl);
      } catch (_) {}
      final r = MinerActionResult(
          minerId: miner.id, minerName: miner.name, success: ok);
      results.add(r);
      onProgress?.call(r);
    }
    return results;
  }
}
