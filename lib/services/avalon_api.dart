import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';
import 'relay_service.dart';

/// HTTP REST API client for Avalon devices (Nano 3S, Mini 3, Q)
class AvalonAPI {
  static final AvalonAPI instance = AvalonAPI._();
  AvalonAPI._();

  static const _timeout = Duration(seconds: 8);

  // Endpoints tried in order — different Canaan firmware versions use different paths
  static const _endpoints = [
    '/cgi-bin/luci/admin/miner/api/status',
    '/api/miner/status',
    '/api/v1/status',
    '/cgi-bin/luci/api/miner/status',
  ];

  Future<MinerStats> fetchStats(String ip, MinerType type,
      {String remoteUrl = '', bool isRemote = false}) async {
    // ── Remote path via relay bridge ──────────────────────────────────────
    if (isRemote) {
      return _fetchRemote(ip, type);
    }
    // ── Direct HTTP path ──────────────────────────────────────────────────
    final baseUrl = remoteUrl.isNotEmpty ? remoteUrl : 'http://$ip';
    for (final endpoint in _endpoints) {
      try {
        final resp = await http.get(
          Uri.parse('$baseUrl$endpoint'),
          headers: {'Accept': 'application/json'},
        ).timeout(_timeout);
        if (resp.statusCode != 200) continue;
        final body = resp.body.trim();
        if (body.isEmpty) continue;
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          final stats = _parse(data, type);
          if (stats.status != MinerStatus.offline) return stats;
        }
      } catch (_) {
        continue;
      }
    }
    return MinerStats.offline;
  }

  /// Fetch stats via the Kratos relay bridge (for remote monitoring).
  /// Tries each known endpoint through RelayService until one succeeds.
  Future<MinerStats> _fetchRemote(String ip, MinerType type) async {
    for (final endpoint in _endpoints) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final result = await RelayService.instance.command(
            minerIp: ip,
            minerPort: 80,
            method: 'GET',
            path: endpoint,
            protocol: 'avalon_http',
          );
          // Relay returns {data: {...}} or {response: {...}} or the body directly
          final raw = result['data'] ?? result['response'] ?? result;
          Map<String, dynamic>? parsed;
          if (raw is Map<String, dynamic>) {
            parsed = raw;
          } else if (raw is String) {
            try { parsed = jsonDecode(raw) as Map<String, dynamic>?; } catch (_) {}
          }
          if (parsed != null) {
            final stats = _parse(parsed, type);
            if (stats.status != MinerStatus.offline) return stats;
          }
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 600));
            continue;
          }
        }
        break;
      }
    }
    return MinerStats.offline;
  }

  /// Parse best difficulty — handles "2.5G", "890M", "1.2T" or raw numbers.
  double _parseBestDiff(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is! String || v.isEmpty) return 0;
    final s = v.trim().toUpperCase();
    const suffixes = {'P': 1e15, 'T': 1e12, 'G': 1e9, 'M': 1e6, 'K': 1e3};
    for (final entry in suffixes.entries) {
      if (s.endsWith(entry.key)) {
        final n = double.tryParse(s.substring(0, s.length - 1));
        if (n != null) return n * entry.value;
      }
    }
    return double.tryParse(s) ?? 0;
  }

  MinerStats _parse(Map<String, dynamic> data, MinerType type) {
    try {
      // Unwrap nested 'miner' object if present (some Canaan firmware)
      final d = (data['miner'] is Map) ? (data['miner'] as Map<String, dynamic>) : data;

      // Hashrate — try multiple field names across firmware versions
      double hashrate = 0;
      for (final key in ['hashrate', 'GHs', 'GHs5s', 'GHsAv', 'rate',
                         'MHs5s', 'MHs av', 'TH', 'THs']) {
        final v = d[key] ?? data[key];
        if (v != null && v is num && v > 0) {
          final val = v.toDouble();
          // Detect unit from value magnitude and key name
          if (key.startsWith('MH') || val > 100000) {
            hashrate = val / 1000.0; // MH/s → GH/s
          } else if (key.startsWith('TH') || (val < 100 && val > 0)) {
            hashrate = val * 1000.0; // TH/s → GH/s
          } else {
            hashrate = val; // already GH/s
          }
          break;
        }
      }

      // Temperature — try multiple sources across firmware variants
      double temp = 0;
      // Nested DEVS list
      final devs = d["DEVS"] ?? data["DEVS"];
      if (devs is List && devs.isNotEmpty) {
        final t = devs[0]["Temperature"] ?? devs[0]["temp"] ?? devs[0]["Temp"];
        if (t != null) temp = (t as num).toDouble();
      }
      // STATS list
      if (temp == 0) {
        final statList = d["STATS"] ?? data["STATS"];
        if (statList is List && statList.isNotEmpty) {
          final t = statList[0]["temp1"] ?? statList[0]["temp2"] ?? statList[0]["Temp"];
          if (t != null) temp = (t as num).toDouble();
        }
      }
      // Flat keys (covers Nano 3S /api/miner/status response)
      if (temp == 0) {
        const tempKeys = ["Temp", "oTemp", "temperature", "temp", "outtemp",
                          "chip_temp", "temperature1", "PCB Temp", "temp_chip",
                          "boardTemp", "board_temp"];
        for (final k in tempKeys) {
          final v = d[k] ?? data[k];
          if (v != null) { temp = (v as num).toDouble(); break; }
        }
      }
      // Average temp\d+ keys
      if (temp == 0) {
        final vals = <double>[];
        for (final k in {...d.keys, ...data.keys}) {
          if (RegExp(r"^temp\d+$").hasMatch(k)) {
            final v = d[k] ?? data[k];
            if (v != null) vals.add((v as num).toDouble());
          }
        }
        if (vals.isNotEmpty) temp = vals.reduce((a, b) => a + b) / vals.length;
      }

      // Fan — try all known field names
      int fanRPM = 0;
      for (final k in ['fanspeed', 'fan', 'fan_speed', 'fan1', 'Fan', 'fanRPM', 'fan_rpm']) {
        final v = d[k] ?? data[k];
        if (v != null) { fanRPM = (v as num).toInt(); break; }
      }

      int fanPercent = 0;
      for (final k in ['fanpercent', 'fan_percent', 'FanR', 'fanPercent']) {
        final v = d[k] ?? data[k];
        if (v != null) { fanPercent = (v as num).toInt(); break; }
      }

      // Pools — handle multiple response formats:
      // 1. Root-level stratumURL/stratumPort (Canaan Avalon Nano 3S, same as ESP-Miner)
      // 2. Nested pool/pools object
      final pools = <PoolInfo>[];

      // Format 1: root-level stratumURL (most Canaan devices)
      final sUrl  = d['stratumURL']  ?? data['stratumURL']  as String? ?? '';
      final sPort = ((d['stratumPort'] ?? data['stratumPort']) as num?)?.toInt() ?? 3333;
      final sUser = d['stratumUser'] ?? data['stratumUser'] as String? ?? '';
      final sUrl2  = d['fallbackStratumURL']  ?? data['fallbackStratumURL']  as String? ?? '';
      final sPort2 = ((d['fallbackStratumPort'] ?? data['fallbackStratumPort']) as num?)?.toInt() ?? 3333;
      final sUser2 = d['fallbackStratumUser'] ?? data['fallbackStratumUser'] as String? ?? '';

      if (sUrl is String && sUrl.isNotEmpty) {
        pools.add(PoolInfo(
          index: 0,
          url: 'stratum+tcp://$sUrl:$sPort',
          user: sUser is String ? sUser : '',
          status: 'Alive',
          active: true,
        ));
        if (sUrl2 is String && sUrl2.isNotEmpty) {
          pools.add(PoolInfo(
            index: 1,
            url: 'stratum+tcp://$sUrl2:$sPort2',
            user: sUser2 is String ? sUser2 : (sUser is String ? sUser : ''),
            status: 'Standby',
            active: false,
          ));
        }
      } else {
        // Format 2: nested pool/pools object
        final poolRaw = d['pool'] ?? d['pools'] ?? data['pool'] ?? data['pools'];
        if (poolRaw is Map) {
          final pUrl = poolRaw['url'] as String? ?? poolRaw['stratumURL'] as String? ?? '';
          final pPort = (poolRaw['port'] as num?)?.toInt() ?? (poolRaw['stratumPort'] as num?)?.toInt() ?? 3333;
          final builtUrl = pUrl.contains('://') ? pUrl : 'stratum+tcp://$pUrl:$pPort';
          pools.add(PoolInfo(
            index: 0, url: builtUrl,
            user: poolRaw['user'] as String? ?? poolRaw['stratumUser'] as String? ?? '',
            status: 'Alive', active: true,
          ));
        } else if (poolRaw is List) {
          for (int i = 0; i < poolRaw.length; i++) {
            final p = poolRaw[i] as Map;
            final pUrl = p['url'] as String? ?? p['stratumURL'] as String? ?? '';
            final pPort = (p['port'] as num?)?.toInt() ?? 3333;
            final builtUrl = pUrl.contains('://') ? pUrl : 'stratum+tcp://$pUrl:$pPort';
            pools.add(PoolInfo(
              index: i, url: builtUrl,
              user: p['user'] as String? ?? p['stratumUser'] as String? ?? '',
              status: p['status'] as String? ?? 'Alive',
              active: i == 0,
            ));
          }
        }
      }

      // Uptime
      int uptime = 0;
      final uptimeRaw = d['uptime'] ?? d['elapsed'] ?? d['runtime']
                     ?? data['uptime'] ?? data['elapsed'] ?? data['runtime'];
      if (uptimeRaw != null) uptime = (uptimeRaw as num).toInt();

      // Frequency
      double frequency = 0;
      final freqRaw = d['frequency'] ?? d['freq'] ?? d['chip_freq']
                   ?? data['frequency'] ?? data['freq'] ?? data['chip_freq'];
      if (freqRaw != null) frequency = (freqRaw as num).toDouble();

      // Accepted shares
      int accepted = 0;
      final accRaw = d['accepted'] ?? d['accept'] ?? d['shares'] ?? d['sharesAccepted']
                  ?? data['accepted'] ?? data['accept'] ?? data['shares'];
      if (accRaw != null) accepted = (accRaw as num).toInt();

      // Best diff
      // Best diff — handles string suffixes like "2.5G", "890M", "1.2T" (Avalon Nano 3S)
      final bsRaw = d['bestDiff'] ?? d['best_diff'] ?? d['sessionDiff']
                 ?? d['BestDiff'] ?? data['bestDiff'] ?? data['best_diff']
                 ?? data['sessionDiff'] ?? data['BestDiff'];
      final bestShare = _parseBestDiff(bsRaw);

      // Power
      double powerDraw = 0;
      final pwRaw = d['power'] ?? d['powerDraw'] ?? d['watt']
                 ?? data['power'] ?? data['powerDraw'];
      if (pwRaw != null) powerDraw = (pwRaw as num).toDouble();

      // Status
      MinerStatus status = MinerStatus.online;
      if (hashrate == 0) status = MinerStatus.warning;
      if (temp > 85) status = MinerStatus.warning;

      return MinerStats(
        hashrate5s: hashrate,
        hashrateAvg: hashrate,
        outTemp: temp,
        fanRPM: fanRPM,
        fanPercent: fanPercent,
        accepted: accepted,
        pools: pools,
        uptime: uptime,
        frequency: frequency,
        powerDraw: powerDraw,
        bestShare: bestShare,
        status: status,
        lastUpdated: DateTime.now(),
        model: type.displayName,
        type: type,
      );
    } catch (_) {
      return MinerStats.offline;
    }
  }

  /// Set frequency on Avalon Nano 3S via HTTP PATCH to /api/system.
  /// The Nano 3S shares the same REST API shape as ESP-Miner.
  Future<bool> setFrequency(
    String ip,
    int port,
    int mhz, {
    String remoteUrl = '',
    bool isRemote = false,
  }) async {
    try {
      final body = <String, dynamic>{'frequency': mhz};
      if (isRemote) {
        final result = await RelayService.instance.command(
          minerIp: ip, minerPort: port,
          method: 'PATCH', path: '/api/system', body: body,
        );
        return (result['status'] as num?)?.toInt() == 200;
      }
      final baseUrl = remoteUrl.isNotEmpty ? remoteUrl : 'http://$ip';
      final r = await http.patch(
        Uri.parse('$baseUrl/api/system'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Set pool on Avalon Nano 3S / Nano 3 via HTTP PATCH (same endpoint as ESP-Miner).
  /// host = just the hostname, e.g. "solo.mineshop.eu"
  Future<bool> setPool(
    String ip,
    int port, {
    required String host,
    required int poolPort,
    required String user,
    String? fallbackHost,
    int? fallbackPort,
    String? fallbackUser,
    String remoteUrl = '',
    bool isRemote = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'stratumURL': host,
        'stratumPort': poolPort,
        'stratumUser': user,
        if (fallbackHost != null && fallbackHost.isNotEmpty) ...{
          'fallbackStratumURL': fallbackHost,
          'fallbackStratumPort': fallbackPort ?? 3333,
          'fallbackStratumUser': fallbackUser ?? user,
        },
      };
      if (isRemote) {
        final result = await RelayService.instance.command(
          minerIp: ip, minerPort: port,
          method: 'PATCH', path: '/api/system', body: body,
        );
        return (result['status'] as num?)?.toInt() == 200;
      }
      final baseUrl = remoteUrl.isNotEmpty ? remoteUrl : 'http://$ip';
      final r = await http.patch(
        Uri.parse('$baseUrl/api/system'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
