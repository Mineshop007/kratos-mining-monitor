import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/miner.dart';

/// CGMiner API client — works with ANY cgminer-compatible miner
class CGMinerAPI {
  static final CGMinerAPI instance = CGMinerAPI._();
  CGMinerAPI._();

  Future<Map<String, dynamic>?> sendCommand(
    String command, String ip, int port, {Duration timeout = const Duration(seconds: 5)}
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.write('$command\n');
      await socket.flush();

      final buffer = StringBuffer();
      await for (final data in socket.timeout(timeout)) {
        buffer.write(utf8.decode(data));
        if (buffer.toString().contains('"id":')) break;
      }
      final raw = buffer.toString().replaceAll('\x00', '').trim();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<MinerStats> fetchAll(String ip, int port) async {
    // Fetch in parallel for speed
    final results = await Future.wait([
      sendCommand('{"command":"summary"}', ip, port),
      sendCommand('{"command":"pools"}', ip, port),
      sendCommand('{"command":"stats"}', ip, port),
      sendCommand('{"command":"version"}', ip, port),
    ]);

    final summaryResp = results[0];
    final poolsResp   = results[1];
    final statsResp   = results[2];
    final versionResp = results[3];

    if (summaryResp == null) return MinerStats.offline;

    // Parse summary
    final sum = (summaryResp['SUMMARY'] as List?)?.first as Map? ?? {};
    final hashrate5s  = ((sum['MHS 5s']  as num?) ?? 0).toDouble() / 1000.0;
    final hashrateAvg = ((sum['MHS av']  as num?) ?? 0).toDouble() / 1000.0;
    final accepted    = (sum['Accepted'] as num?)?.toInt() ?? 0;
    final rejected    = (sum['Rejected'] as num?)?.toInt() ?? 0;
    final hwErrors    = (sum['Hardware Errors'] as num?)?.toInt() ?? 0;
    final uptime      = (sum['Elapsed'] as num?)?.toInt() ?? 0;
    final bestShare   = ((sum['Best Share'] as num?) ?? 0).toDouble();

    // Parse pools
    final poolsList = (poolsResp?['POOLS'] as List?) ?? [];
    final pools = poolsList.map((p) {
      final pm = p as Map;
      return PoolInfo(
        index:     (pm['POOL'] as num?)?.toInt() ?? 0,
        url:       pm['URL'] as String? ?? '',
        user:      pm['User'] as String? ?? '',
        status:    pm['Status'] as String? ?? 'Unknown',
        accepted:  (pm['Accepted'] as num?)?.toInt() ?? 0,
        rejected:  (pm['Rejected'] as num?)?.toInt() ?? 0,
        active:    pm['Stratum Active'] as bool? ?? false,
        bestShare: ((pm['Best Share'] as num?) ?? 0).toDouble(),
      );
    }).toList();

    // Parse device stats
    double outTemp = 0, frequency = 0, powerDraw = 0;
    int fanRPM = 0, fanPercent = 0;
    String firmware = '', model = '';

    final statsList = (statsResp?['STATS'] as List?) ?? [];
    for (final stat in statsList) {
      final sm = stat as Map;
      final mmid = sm['MM ID0'] as String? ?? '';
      if (mmid.isNotEmpty) {
        outTemp    = _parseField(mmid, 'OTemp');
        fanRPM     = _parseField(mmid, 'Fan1').toInt();
        fanPercent = _parseField(mmid, 'FanR').toInt();
        frequency  = _parseField(mmid, 'Freq');
        powerDraw  = _parsePower(mmid);
        firmware   = _parseStringField(mmid, 'Ver');
        model      = _parseModel(firmware);
      }
      // Standard temp fallback
      if (outTemp == 0) {
        outTemp = ((sm['Temperature'] as num?) ?? 0).toDouble();
      }
    }

    // Parse version
    final verList = (versionResp?['VERSION'] as List?) ?? [];
    if (verList.isNotEmpty) {
      final v = verList.first as Map;
      if (model.isEmpty) model = v['PROD'] as String? ?? v['MODEL'] as String? ?? '';
      if (firmware.isEmpty) firmware = v['CGVERSION'] as String? ?? v['LVERSION'] as String? ?? '';
    }

    // Determine status
    MinerStatus status = MinerStatus.online;
    if (outTemp > 85 || fanRPM < 300 && fanRPM > 0) status = MinerStatus.warning;
    if (hwErrors > 10) status = MinerStatus.warning;

    return MinerStats(
      hashrate5s: hashrate5s,
      hashrateAvg: hashrateAvg,
      outTemp: outTemp,
      fanRPM: fanRPM,
      fanPercent: fanPercent,
      accepted: accepted,
      rejected: rejected,
      hardwareErrors: hwErrors,
      uptime: uptime,
      pools: pools,
      frequency: frequency,
      powerDraw: powerDraw,
      status: status,
      lastUpdated: DateTime.now(),
      firmware: firmware,
      model: model,
      type: MinerType.detect(model),
      bestShare: bestShare,
    );
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  Future<bool> restart(String ip, int port) async {
    final r = await sendCommand('{"command":"ascset","parameter":"0,reboot,0"}', ip, port);
    return _isOK(r);
  }

  Future<bool> setFrequency(String ip, int port, int mhz) async {
    final r = await sendCommand('{"command":"ascset","parameter":"0,frequency,$mhz"}', ip, port);
    return _isOK(r);
  }

  Future<bool> setFanSpeed(String ip, int port, int percent) async {
    final r = await sendCommand('{"command":"ascset","parameter":"0,fan-spd,$percent"}', ip, port);
    return _isOK(r);
  }

  Future<bool> setPools(String ip, int port, List<Map<String, String>> pools) async {
    // Remove old pools
    for (int i = 0; i < 3; i++) {
      await sendCommand('{"command":"removepool","parameter":"$i"}', ip, port);
    }
    // Add new pools
    for (final pool in pools) {
      final url  = pool['url'] ?? '';
      final user = pool['user'] ?? 'worker';
      final pass = pool['pass'] ?? 'x';
      await sendCommand('{"command":"addpool","parameter":"$url,$user,$pass"}', ip, port);
    }
    await sendCommand('{"command":"saveconfig"}', ip, port);
    return true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _parseField(String mmid, String key) {
    final r = RegExp('$key\\[([0-9.\\-]+)\\]');
    final m = r.firstMatch(mmid);
    return m != null ? double.tryParse(m.group(1)!) ?? 0 : 0;
  }

  String _parseStringField(String mmid, String key) {
    final r = RegExp('$key\\[([^\\]]+)\\]');
    final m = r.firstMatch(mmid);
    return m?.group(1) ?? '';
  }

  String _parseModel(String fw) {
    // "Nano3s-26032122_ffec1e9" → "Nano3s"
    if (fw.contains('-')) return fw.split('-').first;
    return fw;
  }

  double _parsePower(String mmid) {
    // PS field: PS[0 0 27315 5 0 3496 142] — index 5 is power in W*10
    final r = RegExp(r'PS\[([^\]]+)\]');
    final m = r.firstMatch(mmid);
    if (m == null) return 0;
    final parts = m.group(1)!.trim().split(RegExp(r'\s+'));
    if (parts.length > 5) return (int.tryParse(parts[5]) ?? 0).toDouble();
    return 0;
  }

  bool _isOK(Map<String, dynamic>? resp) {
    if (resp == null) return false;
    final status = (resp['STATUS'] as List?)?.first as Map?;
    return status?['STATUS'] == 'S';
  }
}
