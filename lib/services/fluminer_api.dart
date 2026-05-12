import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';
import 'relay_service.dart';

// ── Run mode enum ─────────────────────────────────────────────────────────────

enum FluMinerRunMode {
  efficiency, // mode "0" — low power, best J/TH
  normal,     // mode "1" — balanced
  turbo;      // mode "2" — max hashrate

  String get apiValue => switch (this) {
        efficiency => '0',
        normal => '1',
        turbo => '2',
      };

  String get label => switch (this) {
        efficiency => 'Efficiency',
        normal => 'Normal',
        turbo => 'Turbo',
      };

  static FluMinerRunMode fromApi(String? v) => switch (v) {
        '0' => efficiency,
        '2' => turbo,
        _ => normal,
      };
}

// ── API client ────────────────────────────────────────────────────────────────

/// HTTP REST API client for FluMiner T3 stock firmware.
///
/// Public endpoints (no auth):
///   GET  /api/overview         — device identity
///   GET  /api/summary          — live mining stats
///
/// Auth-required endpoints (POST /api/login first → session cookie):
///   GET  /api/getPools
///   POST /api/setPool
///   POST /api/updateFrequencyAndVoltage
///   POST /api/updateRunCtrl
///   POST /api/setAutoTune
///   GET  /api/getAutoTuneStatus
///
/// Default credentials: admin / admin  (configurable per-miner in notes field)
class FluMinerAPI {
  static final FluMinerAPI instance = FluMinerAPI._();
  FluMinerAPI._();

  static const _timeout = Duration(seconds: 8);
  static const defaultUsername = 'root';
  static const defaultPassword = 'root';
  // Fallback credentials tried when root/root fails
  static const _fallbackUsername = 'admin';
  static const _fallbackPassword = '123456';

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<String?> login(String ip, int port,
      {String? username, String? password}) async {
    // Try credentials in order: root/root → admin/123456
    final pairs = [
      [username ?? defaultUsername, password ?? defaultPassword],
      [_fallbackUsername, _fallbackPassword],
    ];
    for (final pair in pairs) {
      final session = await _tryLogin(ip, port, pair[0], pair[1]);
      if (session != null) return session;
    }
    return null;
  }

  Future<String?> _tryLogin(String ip, int port, String user, String pass) async {
    try {
      final resp = await http
          .post(
            Uri.parse('http://$ip:$port/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': user, 'password': pass}),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (data == null || data['code'] != 0) return null;
      final setCookie = resp.headers['set-cookie'] ?? '';
      final match = RegExp(r'session=([^;,\s]+)').firstMatch(setCookie);
      if (match != null) return match.group(1);
      final token = data['data']?['token'] as String?;
      return token ?? 'ok';
    } catch (_) {
      return null;
    }
  }

  // ── Fetch Stats ───────────────────────────────────────────────────────────

  Future<MinerStats> fetchStats(String ip,
      {int port = 80, bool isRemote = false}) async {
    try {
      final results = isRemote
          ? await Future.wait([
              _getJsonRelay(ip, port, '/api/summary'),
              _getJsonRelay(ip, port, '/api/overview'),
            ])
          : await Future.wait([
              _getJson('http://$ip:$port/api/summary'),
              _getJson('http://$ip:$port/api/overview'),
            ]);

      final summaryResp = results[0];
      final overviewResp = results[1];

      // Try authenticated pool stats + session stats for bestDiff (best-effort)
      Map<String, dynamic>? poolsResp;
      Map<String, dynamic>? hourResp;
      try {
        final session = await login(ip, port);
        if (session != null) {
          final extras = await Future.wait([
            _getJsonAuthed('http://$ip:$port/api/getPools', session),
            _getJsonAuthed('http://$ip:$port/api/getHashAndTempHour', session),
          ]);
          poolsResp = extras[0];
          hourResp  = extras[1];
        }
      } catch (_) {}

      // ── Summary ───────────────────────────────────────────────────────────
      final summaryData = summaryResp?['data'] as Map<String, dynamic>?;
      final summaries = summaryData?['summary'] as List?;
      final s = (summaries != null && summaries.isNotEmpty)
          ? summaries[0] as Map<String, dynamic>
          : <String, dynamic>{};

      final hashrateGH = _toDouble(s['hrt']) ?? 0.0;

      // temp: "boardTemp|chipTemp" pipe-separated
      final temps = _splitPipe(s['temp'] as String?);
      final outTemp = temps.isNotEmpty ? temps[0] : 0.0;

      // fan: "r1|r2|r3|r4" pipe-separated RPM
      final fanSpeeds = _splitPipe(s['fan'] as String?);
      final fanRPM = fanSpeeds.isNotEmpty ? fanSpeeds[0].toInt() : 0;

      final powerDraw = _toDouble(s['power']) ?? 0.0;
      final uptime = _toInt(s['uptime']) ?? 0;
      final accepted = _toInt(s['acc']) ?? 0;
      final rejected = _toInt(s['rej']) ?? 0;

      // Best difficulty — check all known field names across all endpoints.
      // FluMiner T3 field name not yet confirmed; we cast a wide net.
      final bestShare = _parseBestDiff(
          // summary[0] level (most common location)
          s['bestDiff'] ?? s['best_diff'] ?? s['bestShare'] ??
          s['best_share'] ?? s['sessionDiff'] ?? s['BestDiff'] ??
          s['maxDiff'] ?? s['topDiff'] ?? s['highestDiff'] ??
          s['best'] ?? s['diffBest'] ?? s['sessionBestDiff'] ??
          // data level (parent of summary array)
          summaryData?['bestDiff'] ?? summaryData?['best_diff'] ??
          summaryData?['bestShare'] ?? summaryData?['sessionBest'] ??
          summaryData?['best'] ?? summaryData?['highestDiff'] ??
          // hourly stats endpoint
          _hourBestDiff(hourResp) ??
          // pools endpoint
          _poolsBestDiff(poolsResp));

      // Frequency & voltage (may or may not be in summary)
      final frequency = _toDouble(s['frequency']) ?? 0.0;
      final voltageRaw = _toInt(s['voltage']) ?? 0; // mV

      // Run mode
      final runMode = FluMinerRunMode.fromApi(s['mode']?.toString());

      // Active pool
      final poolHost = s['pool'] as String? ?? '';
      final poolPort = s['port']?.toString() ?? '3333';
      final poolAlive = s['poolAlive'] == '1' || s['poolAlive'] == 1;
      final pools = poolHost.isNotEmpty
          ? [
              PoolInfo(
                index: 0,
                url: 'stratum+tcp://$poolHost:$poolPort',
                user: s['user'] as String? ?? '',
                status: poolAlive ? 'Alive' : 'Dead',
                active: true,
              )
            ]
          : <PoolInfo>[];

      // ── Overview ──────────────────────────────────────────────────────────
      final overviewData = overviewResp?['data'] as Map<String, dynamic>?;
      final minerInfo =
          overviewData?['minerInfo'] as Map<String, dynamic>? ?? {};
      final firmware = minerInfo['minerVersion'] as String? ?? '';

      final status = hashrateGH > 0
          ? (outTemp > 85 ? MinerStatus.warning : MinerStatus.online)
          : MinerStatus.warning;

      return MinerStats(
        hashrate5s: hashrateGH,
        hashrateAvg: hashrateGH,
        outTemp: outTemp,
        fanRPM: fanRPM,
        accepted: accepted,
        rejected: rejected,
        pools: pools,
        uptime: uptime,
        frequency: frequency,
        powerDraw: powerDraw,
        firmware: firmware,
        model: 'FluMiner T3',
        type: MinerType.fluMinerT3,
        coreVoltage: voltageRaw,
        workMode: runMode.index,  // 0=efficiency 1=normal 2=turbo
        bestShare: bestShare,
        status: status,
        lastUpdated: DateTime.now(),
      );
    } catch (_) {
      return MinerStats.offline;
    }
  }

  // ── OC: Frequency + Voltage ───────────────────────────────────────────────

  Future<bool> setFrequencyAndVoltage(
    String ip,
    int port, {
    required int frequencyMHz,
    required int voltageMv,
  }) async {
    final session = await login(ip, port);
    if (session == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('http://$ip:$port/api/updateFrequencyAndVoltage'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'session=$session',
            },
            body: jsonEncode(
                {'frequency': frequencyMHz, 'voltage': voltageMv}),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      return data?['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Run Mode ──────────────────────────────────────────────────────────────

  Future<bool> setRunMode(String ip, int port, FluMinerRunMode mode) async {
    final session = await login(ip, port);
    if (session == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('http://$ip:$port/api/updateRunCtrl'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'session=$session',
            },
            body: jsonEncode({'fan': '1', 'mode': mode.apiValue}),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      return data?['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Autotune ──────────────────────────────────────────────────────────────

  Future<bool> startAutoTune(String ip, int port) async {
    final session = await login(ip, port);
    if (session == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('http://$ip:$port/api/setAutoTune'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'session=$session',
            },
            body: jsonEncode({}),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      return data?['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAutoTuneStatus(String ip, int port) async {
    try {
      final resp = await http
          .get(
            Uri.parse('http://$ip:$port/api/getAutoTuneStatus'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (data?['code'] != 0) return null;
      return data?['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Pool Config ───────────────────────────────────────────────────────────

  Future<bool> setPool(
    String ip,
    int port, {
    required String host,
    required int poolPort,
    required String user,
    String pass = 'x',
    String? fallbackHost,
    int? fallbackPort,
    String? fallbackUser,
  }) async {
    final session = await login(ip, port);
    if (session == null) return false;
    try {
      final pools = <Map<String, String>>[
        {'url': 'stratum+tcp://$host:$poolPort', 'user': user, 'pass': pass},
        if (fallbackHost != null && fallbackHost.isNotEmpty)
          {
            'url':
                'stratum+tcp://$fallbackHost:${fallbackPort ?? 3333}',
            'user': fallbackUser ?? user,
            'pass': pass,
          },
      ];
      final resp = await http
          .post(
            Uri.parse('http://$ip:$port/api/setPool'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'session=$session',
            },
            body: jsonEncode({'pools': pools}),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      return data?['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Scanner fingerprint (no auth) ─────────────────────────────────────────

  static Future<Map<String, dynamic>?> probe(String ip,
      {int port = 80}) async {
    try {
      final resp = await http
          .get(
            Uri.parse('http://$ip:$port/api/overview'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(milliseconds: 2000));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (data?['code'] != 0) return null;
      final innerData = data?['data'] as Map<String, dynamic>?;
      if (innerData == null || !innerData.containsKey('minerInfo')) return null;
      final minerInfo = innerData['minerInfo'] as Map<String, dynamic>? ?? {};
      // Identify: model == "T3" OR macAddress starts with "70:69:79"
      final model = minerInfo['model'] as String? ?? '';
      final mac = (minerInfo['macAddress'] as String? ?? '').toLowerCase();
      if (model != 'T3' && !mac.startsWith('70:69:79')) return null;
      return {
        'firmware': minerInfo['minerVersion'] as String? ?? '',
        'hostname': 'FluMiner T3',
        'model': model,
        'mac': mac,
      };
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extract best difficulty from hourly stats response
  static dynamic _hourBestDiff(Map<String, dynamic>? resp) {
    if (resp == null) return null;
    final data = resp['data'];
    if (data is! Map) return null;
    return data['bestDiff'] ?? data['best_diff'] ?? data['bestShare'] ??
        data['highestDiff'] ?? data['sessionBest'] ?? data['best'];
  }

  /// Extract best difficulty from pools response (per-pool stats)
  static dynamic _poolsBestDiff(Map<String, dynamic>? poolsResp) {
    if (poolsResp == null) return null;
    final data = poolsResp['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    // Check top-level data fields
    final topLevel = data['bestDiff'] ?? data['best_diff'] ??
        data['bestShare'] ?? data['sessionBestDiff'];
    if (topLevel != null) return topLevel;
    // Check inside each pool entry
    final pools = data['pools'] as List?;
    if (pools == null) return null;
    dynamic best;
    for (final pool in pools) {
      if (pool is! Map) continue;
      final v = pool['bestDiff'] ?? pool['best_diff'] ??
          pool['bestShare'] ?? pool['best_share'];
      if (v != null) {
        final parsed = _parseBestDiff(v);
        if (best == null || parsed > _parseBestDiff(best)) best = v;
      }
    }
    return best;
  }

  Future<Map<String, dynamic>?> _getJsonAuthed(
      String url, String session) async {
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Cookie': 'session=$session',
        },
      ).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = resp.body.trim();
      if (body.isEmpty) return null;
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch via relay bridge (when isRemote == true)
  Future<Map<String, dynamic>?> _getJsonRelay(
      String ip, int port, String path) async {
    try {
      final result = await RelayService.instance.command(
        minerIp: ip,
        minerPort: port,
        method: 'GET',
        path: path,
        protocol: 'fluminer_http',
      );
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = resp.body.trim();
      if (body.isEmpty) return null;
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// Parses best difficulty — handles "2.5G", "890M", "1.2T" or raw number
  static double _parseBestDiff(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is! String || v.isEmpty) return 0;
    final s = v.trim().toUpperCase();
    const suffixes = <String, double>{
      'P': 1e15, 'T': 1e12, 'G': 1e9, 'M': 1e6, 'K': 1e3
    };
    for (final entry in suffixes.entries) {
      if (s.endsWith(entry.key)) {
        final n = double.tryParse(s.substring(0, s.length - 1));
        if (n != null) return n * entry.value;
      }
    }
    return double.tryParse(s) ?? 0;
  }

  static List<double> _splitPipe(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split('|')
        .map((v) => double.tryParse(v.trim()) ?? 0.0)
        .toList();
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
