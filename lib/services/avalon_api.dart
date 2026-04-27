import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';

/// HTTP REST API client for Avalon devices (Nano 3S, Mini 3, Q)
class AvalonAPI {
  static final AvalonAPI instance = AvalonAPI._();
  AvalonAPI._();

  static const _timeout = Duration(seconds: 8);

  Future<MinerStats> fetchStats(String ip, MinerType type) async {
    try {
      final uri = Uri.parse('http://$ip/cgi-bin/luci/admin/miner/api/status');
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return MinerStats.offline;
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) return _parse(data, type);
      return MinerStats.offline;
    } catch (_) {
      return MinerStats.offline;
    }
  }

  MinerStats _parse(Map<String, dynamic> data, MinerType type) {
    try {
      // Hashrate — firmware variants use different keys
      double hashrate = 0;
      final hrRaw = data['hashrate'] ?? data['GHs'] ?? data['rate'] ??
          data['MHs5s'] ?? data['MHs av'];
      if (hrRaw != null) {
        final hrVal = (hrRaw as num).toDouble();
        // Convert MH/s to GH/s if value looks like MH/s
        hashrate = hrVal > 100000 ? hrVal / 1000.0 : hrVal;
      }

      // Temperature
      double temp = 0;
      final tempRaw = data['oTemp'] ?? data['temperature'] ?? data['temp'] ??
          data['outtemp'] ?? data['chip_temp'];
      if (tempRaw != null) temp = (tempRaw as num).toDouble();

      // Fan
      int fanRPM = 0;
      final fanRaw = data['fanspeed'] ?? data['fan'] ?? data['fan_speed'] ??
          data['fan1'];
      if (fanRaw != null) fanRPM = (fanRaw as num).toInt();

      int fanPercent = 0;
      final fanPctRaw = data['fanpercent'] ?? data['fan_percent'];
      if (fanPctRaw != null) fanPercent = (fanPctRaw as num).toInt();

      // Pools
      final pools = <PoolInfo>[];
      final poolRaw = data['pool'] ?? data['pools'];
      if (poolRaw is Map) {
        pools.add(PoolInfo(
          index: 0,
          url: poolRaw['url'] as String? ?? '',
          user: poolRaw['user'] as String? ?? '',
          status: 'Alive',
          active: true,
        ));
      } else if (poolRaw is List) {
        for (int i = 0; i < poolRaw.length; i++) {
          final p = poolRaw[i] as Map;
          pools.add(PoolInfo(
            index: i,
            url: p['url'] as String? ?? '',
            user: p['user'] as String? ?? '',
            status: p['status'] as String? ?? 'Alive',
            active: i == 0,
          ));
        }
      }

      // Uptime
      int uptime = 0;
      final uptimeRaw = data['uptime'] ?? data['elapsed'] ?? data['runtime'];
      if (uptimeRaw != null) uptime = (uptimeRaw as num).toInt();

      // Frequency
      double frequency = 0;
      final freqRaw = data['frequency'] ?? data['freq'] ?? data['chip_freq'];
      if (freqRaw != null) frequency = (freqRaw as num).toDouble();

      // Accepted shares
      int accepted = 0;
      final accRaw = data['accepted'] ?? data['accept'] ?? data['shares'];
      if (accRaw != null) accepted = (accRaw as num).toInt();

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
        status: status,
        lastUpdated: DateTime.now(),
        model: type.displayName,
        type: type,
      );
    } catch (_) {
      return MinerStats.offline;
    }
  }
}
