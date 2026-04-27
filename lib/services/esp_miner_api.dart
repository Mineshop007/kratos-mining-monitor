import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';

/// HTTP REST API client for ESP-Miner devices: BitAxe Gamma/Ultra/GT, NerdQaxe, NerdOctaxe
/// Firmware: https://github.com/bitaxeorg/ESP-Miner
/// Endpoint: GET /api/system/info  (port 80 by default)
class EspMinerAPI {
  static final EspMinerAPI instance = EspMinerAPI._();
  EspMinerAPI._();

  static const _timeout = Duration(seconds: 5);

  Future<MinerStats> fetchAll(String ip, int port) async {
    try {
      final res = await http.get(
        Uri.parse('http://$ip:$port/api/system/info'),
        headers: {'Accept': 'application/json'},
      ).timeout(_timeout);
      if (res.statusCode != 200) return MinerStats.offline;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return _parseSystemInfo(j);
    } catch (_) {
      return MinerStats.offline;
    }
  }

  MinerStats _parseSystemInfo(Map<String, dynamic> j) {
    // hashRate from ESP-Miner is in GH/s (matches MinerStats unit)
    final hr = ((j['hashRate'] as num?) ?? 0).toDouble();
    final hr1m = ((j['hashRate_1m'] as num?) ?? 0).toDouble();
    final hr1h = ((j['hashRate_1h'] as num?) ?? 0).toDouble();

    final sharesAccepted = (j['sharesAccepted'] as num?)?.toInt() ?? 0;
    final sharesRejected = (j['sharesRejected'] as num?)?.toInt() ?? 0;
    final temp = ((j['temp'] as num?) ?? 0).toDouble();
    final usingFallback = (j['isUsingFallbackStratum'] as num?)?.toInt() == 1;
    final stratumUrl = j['stratumURL'] as String? ?? '';
    final stratumPort = (j['stratumPort'] as num?)?.toInt() ?? 0;
    final fallbackUrl = j['fallbackStratumURL'] as String? ?? '';
    final fallbackPort = (j['fallbackStratumPort'] as num?)?.toInt() ?? 0;

    final pools = <PoolInfo>[
      PoolInfo(
        index: 0,
        url: 'stratum+tcp://$stratumUrl:$stratumPort',
        user: j['stratumUser'] as String? ?? '',
        status: usingFallback ? 'Standby' : 'Alive',
        accepted: sharesAccepted,
        rejected: sharesRejected,
        active: !usingFallback,
      ),
      if (fallbackUrl.isNotEmpty)
        PoolInfo(
          index: 1,
          url: 'stratum+tcp://$fallbackUrl:$fallbackPort',
          user: j['fallbackStratumUser'] as String? ?? '',
          status: usingFallback ? 'Alive' : 'Standby',
          accepted: 0,
          rejected: 0,
          active: usingFallback,
        ),
    ];

    MinerStatus status = MinerStatus.online;
    if (temp > 85) status = MinerStatus.warning;
    if (hr == 0 && hr1m == 0) status = MinerStatus.warning;

    final asicModel = j['ASICModel'] as String? ?? '';

    return MinerStats(
      hashrate5s: hr,
      hashrateAvg: hr1m > 0 ? hr1m : hr,
      hashRate1h: hr1h,
      outTemp: temp,
      fanRPM: (j['fanRpm'] as num?)?.toInt() ?? 0,
      fanPercent: (j['fanSpeed'] as num?)?.toInt() ?? 0,
      accepted: sharesAccepted,
      rejected: sharesRejected,
      hardwareErrors: 0,
      uptime: (j['uptimeSeconds'] as num?)?.toInt() ?? 0,
      pools: pools,
      frequency: ((j['frequency'] as num?) ?? 0).toDouble(),
      powerDraw: ((j['power'] as num?) ?? 0).toDouble(),
      status: status,
      lastUpdated: DateTime.now(),
      firmware: j['version'] as String? ?? '',
      model: asicModel.isNotEmpty ? asicModel : (j['hostname'] as String? ?? ''),
      type: MinerType.detect(asicModel),
      bestShare: 0,
      blockFound: (j['blockFound'] as num?)?.toInt() == 1,
      isUsingFallbackStratum: usingFallback,
    );
  }

  Future<bool> restart(String ip, int port) async {
    try {
      final r = await http
          .post(Uri.parse('http://$ip:$port/api/system/restart'))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pause(String ip, int port) async {
    try {
      final r = await http
          .post(Uri.parse('http://$ip:$port/api/system/pause'))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resume(String ip, int port) async {
    try {
      final r = await http
          .post(Uri.parse('http://$ip:$port/api/system/resume'))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setPool(
    String ip,
    int port, {
    required String stratumUrl,
    required int stratumPort,
    required String stratumUser,
    String? stratumPass,
    String? fallbackStratumUrl,
    int? fallbackStratumPort,
    String? fallbackStratumUser,
  }) async {
    try {
      final hostOnly = _stripScheme(stratumUrl);
      final body = <String, dynamic>{
        'stratumURL': hostOnly,
        'stratumPort': stratumPort,
        'stratumUser': stratumUser,
        if (stratumPass != null && stratumPass.isNotEmpty)
          'stratumPassword': stratumPass,
        if (fallbackStratumUrl != null && fallbackStratumUrl.isNotEmpty) ...{
          'fallbackStratumURL': _stripScheme(fallbackStratumUrl),
          'fallbackStratumPort': fallbackStratumPort ?? 3333,
          'fallbackStratumUser': fallbackStratumUser ?? stratumUser,
        },
      };
      final r = await http
          .patch(
            Uri.parse('http://$ip:$port/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setFanSpeed(String ip, int port, int percent) async {
    try {
      final r = await http
          .patch(
            Uri.parse('http://$ip:$port/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fanSpeed': percent, 'autofanspeed': percent == 0}),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setFrequency(String ip, int port, int mhz) async {
    try {
      final r = await http
          .patch(
            Uri.parse('http://$ip:$port/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'frequency': mhz}),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _stripScheme(String url) {
    return url
        .replaceAll(RegExp(r'^stratum\+(tcp|ssl)://'), '')
        .split(':')
        .first;
  }
}
