import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';

/// HTTP REST API client for FluMiner T3 stock firmware.
///
/// API reference (reverse-engineered from pyasic + Fluminer firmware):
///   GET  /api/overview   — device identity (no auth)
///   GET  /api/summary    — mining stats (no auth)
///   GET  /api/getPools   — configured pools (auth required)
///   POST /api/login      — authenticate → session cookie
///   POST /api/setPool    — update pool config (auth required)
///
/// Default credentials: root / root
class FluMinerAPI {
  static final FluMinerAPI instance = FluMinerAPI._();
  FluMinerAPI._();

  static const _timeout = Duration(seconds: 8);
  static const _defaultUser = 'root';
  static const _defaultPass = 'root';

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<String?> _login(String ip, int port) async {
    try {
      final resp = await http.post(
        Uri.parse('http://$ip:$port/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _defaultUser, 'password': _defaultPass}),
      ).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (data?['code'] != 0) return null;
      // Session cookie returned as Set-Cookie header
      final cookie = resp.headers['set-cookie'];
      if (cookie != null) {
        final match = RegExp(r'session=([^;]+)').firstMatch(cookie);
        if (match != null) return match.group(1);
      }
      return 'authenticated'; // some firmware just sets status 200
    } catch (_) {
      return null;
    }
  }

  // ── Fetch Stats ───────────────────────────────────────────────────────────

  Future<MinerStats> fetchStats(String ip, {int port = 80}) async {
    try {
      // Parallel fetch for speed
      final results = await Future.wait([
        _getJson('http://$ip:$port/api/summary'),
        _getJson('http://$ip:$port/api/overview'),
      ]);

      final summaryResp = results[0];
      final overviewResp = results[1];

      // ── Parse summary ────────────────────────────────────────────────────
      final summaryData = summaryResp?['data'] as Map<String, dynamic>?;
      final summaries = summaryData?['summary'] as List?;
      final s = (summaries != null && summaries.isNotEmpty)
          ? summaries[0] as Map<String, dynamic>
          : <String, dynamic>{};

      // Hashrate: 'hrt' field in GH/s
      final hashrateGH = _toDouble(s['hrt']) ?? 0.0;

      // Temp: "boardTemp|chipTemp" pipe-separated
      final temps = _splitPipe(s['temp'] as String?);
      final outTemp = temps.isNotEmpty ? temps[0] : 0.0;

      // Fans: "r1|r2|r3|r4" pipe-separated RPM
      final fanSpeeds = _splitPipe(s['fan'] as String?);
      final fanRPM = fanSpeeds.isNotEmpty ? fanSpeeds[0].toInt() : 0;

      // Power
      final powerDraw = _toDouble(s['power']) ?? 0.0;

      // Uptime (seconds)
      final uptime = _toInt(s['uptime']) ?? 0;

      // Shares
      final accepted = _toInt(s['acc']) ?? 0;
      final rejected = _toInt(s['rej']) ?? 0;

      // Pool (active)
      final poolHost = s['pool'] as String? ?? '';
      final poolPort = s['port']?.toString() ?? '3333';
      final poolAlive = s['poolAlive'] == '1';
      final pools = poolHost.isNotEmpty
          ? [
              PoolInfo(
                index: 0,
                url: 'stratum+tcp://$poolHost:$poolPort',
                user: s['worker'] as String? ?? '',
                status: poolAlive ? 'Alive' : 'Dead',
                active: true,
              )
            ]
          : <PoolInfo>[];

      // ── Parse overview ────────────────────────────────────────────────────
      final overviewData = overviewResp?['data'] as Map<String, dynamic>?;
      final minerInfo = overviewData?['minerInfo'] as Map<String, dynamic>? ?? {};
      final firmware = minerInfo['minerVersion'] as String? ?? '';

      // Status
      final status = hashrateGH > 0
          ? (outTemp > 85 ? MinerStatus.warning : MinerStatus.online)
          : MinerStatus.warning;

      return MinerStats(
        hashrate5s: hashrateGH,    // stored in GH/s
        hashrateAvg: hashrateGH,
        outTemp: outTemp,
        fanRPM: fanRPM,
        fanPercent: 0,
        accepted: accepted,
        rejected: rejected,
        pools: pools,
        uptime: uptime,
        frequency: 0,
        powerDraw: powerDraw,
        bestShare: 0,
        status: status,
        lastUpdated: DateTime.now(),
        model: firmware.isNotEmpty ? 'FluMiner T3 ($firmware)' : 'FluMiner T3',
        type: MinerType.fluMinerT3,
      );
    } catch (_) {
      return MinerStats.offline;
    }
  }

  // ── Set Pool ──────────────────────────────────────────────────────────────

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
    try {
      final session = await _login(ip, port);
      if (session == null) return false;

      final cookies = session != 'authenticated' ? 'session=$session' : '';
      final pools = <Map<String, String>>[
        {'url': 'stratum+tcp://$host:$poolPort', 'user': user, 'pass': pass},
        if (fallbackHost != null && fallbackHost.isNotEmpty)
          {
            'url': 'stratum+tcp://$fallbackHost:${fallbackPort ?? 3333}',
            'user': fallbackUser ?? user,
            'pass': pass,
          },
      ];

      final body = jsonEncode({'pools': pools});
      final resp = await http.post(
        Uri.parse('http://$ip:$port/api/setPool'),
        headers: {
          'Content-Type': 'application/json',
          if (cookies.isNotEmpty) 'Cookie': cookies,
        },
        body: body,
      ).timeout(_timeout);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>?;
        return data?['code'] == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Fingerprint (for scanner) ─────────────────────────────────────────────

  /// Returns non-null DiscoveredMiner if IP is a FluMiner device.
  static Future<Map<String, dynamic>?> probe(String ip, {int port = 80}) async {
    try {
      final resp = await http.get(
        Uri.parse('http://$ip:$port/api/overview'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 1800));

      if (resp.statusCode != 200) return null;
      final body = resp.body.trim();
      if (body.isEmpty) return null;
      final data = jsonDecode(body) as Map<String, dynamic>?;
      if (data == null) return null;

      // FluMiner always returns {code: 0, data: {minerInfo: {...}}}
      final code = data['code'];
      final innerData = data['data'] as Map<String, dynamic>?;
      if (code != 0 || innerData == null) return null;
      if (!innerData.containsKey('minerInfo')) return null;

      final minerInfo = innerData['minerInfo'] as Map<String, dynamic>? ?? {};
      return {
        'firmware': minerInfo['minerVersion'] as String? ?? '',
        'hostname': 'FluMiner T3',
        'model': 'T3',
      };
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
