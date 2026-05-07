import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';
import 'relay_service.dart';

/// HTTP REST API client for ESP-Miner devices: BitAxe Gamma/Ultra/GT, NerdQaxe, NerdOctaxe
/// Firmware: https://github.com/bitaxeorg/ESP-Miner
/// Endpoint: GET /api/system/info  (port 80 by default)
class EspMinerAPI {
  static final EspMinerAPI instance = EspMinerAPI._();
  EspMinerAPI._();

  static const _timeout = Duration(seconds: 8);      // ESP-Miner can be slow under load
  static const _retryTimeout = Duration(seconds: 5);  // retry attempt gets a shorter budget

  String _base(String ip, int port, {String remoteUrl = ''}) =>
      remoteUrl.isNotEmpty ? remoteUrl : 'http://$ip:$port';

  Future<MinerStats> fetchAll(String ip, int port, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      // Relay path: try once; on timeout/error retry once with a fresh request.
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final result = await RelayService.instance.command(
            minerIp: ip, minerPort: port, method: 'GET', path: '/api/system/info');
          // Bridge echoes back 'data' OR sometimes nests under 'response'.
          final data = result['data'] ?? result['response'];
          if (data is Map<String, dynamic>) return _parseSystemInfo(data);
          // If the bridge relayed an HTTP error body, log and retry.
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 800));
            continue;
          }
          return MinerStats.offline;
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 800));
            continue;
          }
          return MinerStats.offline;
        }
      }
      return MinerStats.offline;
    }
    // Direct HTTP path: try port given, then try the alternate port if it fails
    // (handles firmware that switched to 8080).
    final ports = port == 80 ? [80, 8080] : [port];
    for (final p in ports) {
      try {
        final res = await http.get(
          Uri.parse('${_base(ip, p, remoteUrl: remoteUrl)}/api/system/info'),
          headers: {'Accept': 'application/json'},
        ).timeout(p == ports.first ? _timeout : _retryTimeout);
        if (res.statusCode != 200) continue;
        final body = res.body.trim();
        if (body.isEmpty) continue;
        final j = jsonDecode(body) as Map<String, dynamic>;
        return _parseSystemInfo(j);
      } catch (_) {
        continue;
      }
    }
    return MinerStats.offline;
  }

  /// Safe numeric accessor — handles int, double, and unexpected types gracefully.
  static double _n(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
  static int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

  MinerStats _parseSystemInfo(Map<String, dynamic> j) {
    // hashRate from ESP-Miner is in GH/s (matches MinerStats unit)
    // Some firmware (Luckyminer) uses avgHashRate instead of hashRate_1m
    final hr   = _n(j['hashRate']);
    final hr1m = _n(j['hashRate_1m'] ?? j['avgHashRate']);
    final hr1h = _n(j['hashRate_1h']);

    final sharesAccepted = _i(j['sharesAccepted']);
    final sharesRejected = _i(j['sharesRejected']);
    final temp = _n(j['temp']);

    // isUsingFallbackStratum can be bool (newer NerdAxe fw) OR int (0/1) — handle both
    final rawFallback = j['isUsingFallbackStratum'];
    final usingFallback = rawFallback == true ||
        (rawFallback is num && rawFallback.toInt() == 1);
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
      // fanrpm / fanRpm / fanRPM — firmware inconsistency across NerdAxe/BitAxe/Luckyminer
      fanRPM: _i(j['fanrpm'] ?? j['fanRpm'] ?? j['fanRPM']),
      // fanspeed (%) — NerdAxe uses lowercase; BitAxe uses camelCase
      fanPercent: _i(j['fanspeed'] ?? j['fanSpeed'] ?? j['fan_speed']),
      accepted: sharesAccepted,
      rejected: sharesRejected,
      hardwareErrors: 0,
      uptime: _i(j['uptimeSeconds']),
      pools: pools,
      frequency: _n(j['frequency']),
      powerDraw: _n(j['power']),
      status: status,
      lastUpdated: DateTime.now(),
      firmware: j['version'] as String? ?? '',
      // deviceModel gives human name (NerdOCTAXE-γ); ASICModel gives chip (BM1370)
      model: (j['deviceModel'] as String? ?? '').isNotEmpty
          ? j['deviceModel'] as String
          : asicModel.isNotEmpty ? asicModel : (j['hostname'] as String? ?? ''),
      type: MinerType.detect(j['deviceModel'] as String? ?? asicModel),
      bestShare: 0,
      // blockFound can be bool or int depending on firmware version
      blockFound: j['blockFound'] == true || _i(j['blockFound']) == 1,
      isUsingFallbackStratum: usingFallback,
      coreVoltage: _i(j['coreVoltage']),
    );
  }

  Future<bool> restart(String ip, int port, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'POST', path: '/api/system/restart');
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .post(Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system/restart'))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pause(String ip, int port, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'POST', path: '/api/system/pause');
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .post(Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system/pause'))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resume(String ip, int port, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'POST', path: '/api/system/resume');
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .post(Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system/resume'))
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
    String remoteUrl = '',
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
            Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setFanSpeed(String ip, int port, int percent, {String remoteUrl = '', bool isRemote = false}) async {
    final body = {
      'manualFanSpeed': percent,
      'fanSpeed': percent,
      'fanspeed': percent,
      'autofanspeed': 0,
    };
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'PATCH', path: '/api/system', body: body);
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .patch(
            Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setFrequency(String ip, int port, int mhz, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'PATCH', path: '/api/system',
          body: {'frequency': mhz});
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .patch(
            Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'frequency': mhz}),
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setCoreVoltage(String ip, int port, int millivolts, {String remoteUrl = '', bool isRemote = false}) async {
    if (isRemote) {
      try {
        await RelayService.instance.command(
          minerIp: ip, minerPort: port, method: 'PATCH', path: '/api/system',
          body: {'coreVoltage': millivolts});
        return true;
      } catch (_) { return false; }
    }
    try {
      final r = await http
          .patch(
            Uri.parse('${_base(ip, port, remoteUrl: remoteUrl)}/api/system'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'coreVoltage': millivolts}),
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
