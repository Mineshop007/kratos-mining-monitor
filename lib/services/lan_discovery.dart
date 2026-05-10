import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/miner.dart';

/// LAN miner discovery — three concurrent strategies:
///
/// 1. **mDNS** — `_http._tcp.local` and `_esp-miner._tcp.local` lookups.
/// 2. **Subnet ping sweep + ESP-Miner probe** — probes every host on the
///    detected subnet(s) with `GET /api/system/info` on port 80 (8080 as
///    sequential fallback, not concurrent — ESP32 has a tiny HTTP server).
/// 3. **cgminer probe** — port 4028 TCP → Avalon / Antminer / Whatsminer.
///
/// **Multi-subnet**: scans the phone's /24 PLUS the adjacent /24 (common
/// when miners are on 192.168.0.x and phone on 192.168.1.x). Falls back to
/// scanning all common home subnets when the WiFi IP cannot be read.
///
/// **Two-pass sweep**: pass 1 is fast; pass 2 retries missed hosts with a
/// longer timeout (miners under full load can be slow to respond).
class LanDiscoveryService {
  LanDiscoveryService._();
  static final instance = LanDiscoveryService._();

  // Timeouts — sequential probing so these don't stack on the ESP32.
  static const _httpProbeTimeout = Duration(milliseconds: 1500);
  static const _tcpProbeTimeout  = Duration(milliseconds: 900);

  // Common home subnets used as fallback when WiFi IP is unavailable.
  static const _fallbackSubnets = [
    '192.168.1', '192.168.0', '192.168.2',
    '10.0.0',    '10.0.1',    '10.1.1',
    '172.16.0',
  ];

  /// Streams discovered miners as they are confirmed.
  Stream<DiscoveredMiner> scan({String? manualSubnet}) async* {
    final controller = StreamController<DiscoveredMiner>();

    // Determine subnets to scan.
    final subnets = <String>[];
    if (manualSubnet != null && manualSubnet.isNotEmpty) {
      subnets.add(manualSubnet);
    } else {
      try {
        final wifiIp = await NetworkInfo().getWifiIP();
        final primary = _subnetFor(wifiIp);
        if (primary != null) {
          subnets.add(primary);
          // Also scan the adjacent /24 — e.g. miners on .0.x, phone on .1.x
          final adjacent = _adjacentSubnet(primary);
          if (adjacent != null && adjacent != primary) subnets.add(adjacent);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('LAN: failed to read Wi-Fi IP: $e');
      }
      // Fallback: scan common home subnets when IP is unavailable.
      if (subnets.isEmpty) {
        subnets.addAll(_fallbackSubnets);
        if (kDebugMode) debugPrint('LAN: WiFi IP unavailable — scanning fallback subnets');
      }
    }

    final futures = <Future<void>>[
      _runMdnsScan(controller).catchError((e) {
        if (kDebugMode) debugPrint('LAN: mDNS error: $e');
      }),
      for (final s in subnets)
        _runSubnetSweep(s, controller).catchError((e) {
          if (kDebugMode) debugPrint('LAN: sweep error ($s): $e');
        }),
    ];

    Future.wait(futures).whenComplete(() {
      if (!controller.isClosed) controller.close();
    });

    yield* controller.stream;
  }

  void _safeAdd(StreamController<DiscoveredMiner> sink, DiscoveredMiner m) {
    if (!sink.isClosed) sink.add(m);
  }

  String? _subnetFor(String? ip) {
    if (ip == null || !ip.contains('.')) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Returns the adjacent /24 (flips last digit of the third octet ±1).
  /// 192.168.1 → 192.168.0 ; 192.168.0 → 192.168.1 ; 10.0.0 → 10.0.1
  String? _adjacentSubnet(String subnet) {
    final parts = subnet.split('.');
    if (parts.length != 3) return null;
    final third = int.tryParse(parts[2]) ?? 0;
    final adj = third == 0 ? 1 : third - 1;
    return '${parts[0]}.${parts[1]}.$adj';
  }

  // ── mDNS ────────────────────────────────────────────────────────────

  Future<void> _runMdnsScan(StreamController<DiscoveredMiner> sink) async {
    final mdns = MDnsClient(rawDatagramSocketFactory: (
      dynamic host, int port, {
      bool? reuseAddress, bool? reusePort, int? ttl,
    }) => RawDatagramSocket.bind(
      host, port,
      reuseAddress: reuseAddress ?? true,
      reusePort: false,
      ttl: ttl ?? 1,
    ));

    try {
      await mdns.start();
      const services = ['_http._tcp.local', '_esp-miner._tcp.local'];
      for (final svc in services) {
        final found = mdns.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(svc),
          timeout: const Duration(seconds: 3),
        );
        await for (final ptr in found) {
          await for (final srv in mdns.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
              timeout: const Duration(seconds: 1))) {
            await for (final addr in mdns.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: const Duration(seconds: 1))) {
              final probed = await _probeEspMinerHttp(addr.address.address, srv.port);
              if (probed != null) _safeAdd(sink, probed);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('mDNS scan error: $e');
    } finally {
      mdns.stop();
    }
  }

  // ── Subnet sweep ────────────────────────────────────────────────────

  Future<void> _runSubnetSweep(
    String subnet,
    StreamController<DiscoveredMiner> sink,
  ) async {
    // 16 hosts per batch — small enough that each probe gets good bandwidth,
    // large enough to finish a /24 in reasonable time.
    const batchSize = 16;
    final hosts = List<int>.generate(254, (i) => i + 1);
    final missed = <int>[];

    // ── Pass 1: 1.5 s timeout ───────────────────────────────────────────
    for (var i = 0; i < hosts.length; i += batchSize) {
      final batch = hosts.skip(i).take(batchSize);
      await Future.wait(batch.map((h) async {
        final ip = '$subnet.$h';
        // Sequential port probing: try 80 first, then 8080 only if 80 fails.
        // This avoids flooding the ESP32's tiny HTTP server with simultaneous
        // connections which caused "no data" immediately after discovery.
        var esp = await _probeEspMinerHttp(ip, 80);
        esp ??= await _probeEspMinerHttp(ip, 8080);
        if (esp != null) { _safeAdd(sink, esp); return; }

        // Avalon HTTP probe (port 80, different endpoints)
        final av = await _probeAvalonHttp(ip, 80);
        if (av != null) { _safeAdd(sink, av); return; }

        final cg = await _probeCgminerTcp(ip, 4028);
        if (cg != null) { _safeAdd(sink, cg); return; }

        missed.add(h);
      }));
    }

    // ── Pass 2: retry missed hosts at 2.5 s ────────────────────────────
    if (missed.isNotEmpty) {
      const retryBatch = 8;
      final retryTimeout = const Duration(milliseconds: 2500);
      for (var i = 0; i < missed.length; i += retryBatch) {
        final batch = missed.skip(i).take(retryBatch);
        await Future.wait(batch.map((h) async {
          final ip = '$subnet.$h';
          var esp = await _probeEspMinerHttp(ip, 80,  timeout: retryTimeout);
          esp ??= await _probeEspMinerHttp(ip, 8080, timeout: retryTimeout);
          if (esp != null) { _safeAdd(sink, esp); return; }
          final cg = await _probeCgminerTcp(ip, 4028,
              timeout: const Duration(milliseconds: 1500));
          if (cg != null) _safeAdd(sink, cg);
        }));
      }
    }
  }

  // ── Probes ──────────────────────────────────────────────────────────

  Future<DiscoveredMiner?> _probeEspMinerHttp(String ip, int port,
      {Duration? timeout}) async {
    try {
      final resp = await http
          .get(Uri.parse('http://$ip:$port/api/system/info'),
              headers: {'Accept': 'application/json'})
          .timeout(timeout ?? _httpProbeTimeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;

      final hostname    = (body['hostname']    as String?)?.trim() ?? '';
      final deviceModel = (body['deviceModel'] as String?) ?? '';
      final asicModel   = (body['ASICModel']   as String?)
          ?? (body['model'] as String?) ?? '';

      // Type detection priority:
      // 1. deviceModel → "NerdOCTAXE-γ", "NerdQAxe++"  (most specific)
      // 2. hostname    → "nerdqaxe-XXXX", "bitaxe-XXXX"
      // 3. ASICModel   → "BM1370", "BM1368"
      // 4. Never stay generic — this device speaks ESP-Miner HTTP, so
      //    default to bitaxeGamma (same API) rather than cgminerTcp.
      var type = MinerType.detect(deviceModel);
      if (type == MinerType.generic) type = MinerType.detect(hostname);
      if (type == MinerType.generic && asicModel.isNotEmpty) {
        type = MinerType.detect(asicModel);
      }
      if (type == MinerType.generic) type = MinerType.bitaxeGamma;

      final displayName = deviceModel.isNotEmpty ? deviceModel
          : hostname.isNotEmpty   ? hostname
          : asicModel.isNotEmpty  ? asicModel
          : 'BitAxe';

      return DiscoveredMiner(
        ip: ip,
        port: port,
        type: type,
        hostname: displayName,
        firmware: (body['version'] as String?) ?? '',
        source: DiscoverySource.espMinerHttp,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DiscoveredMiner?> _probeAvalonHttp(String ip, int port,
      {Duration? timeout}) async {
    // Canaan Avalon devices: try known LuCI/REST endpoints
    const endpoints = [
      '/cgi-bin/luci/admin/miner/api/status',
      '/api/miner/status',
      '/api/v1/status',
    ];
    for (final ep in endpoints) {
      try {
        final resp = await http
            .get(Uri.parse('http://$ip:$port$ep'),
                headers: {'Accept': 'application/json'})
            .timeout(timeout ?? _httpProbeTimeout);
        if (resp.statusCode != 200) continue;
        final body = jsonDecode(resp.body);
        if (body is! Map<String, dynamic>) continue;
        // Detect Avalon by presence of Canaan-specific fields
        final isAvalon = body.containsKey('GHs') || body.containsKey('GHs5s') ||
            body.containsKey('hashrate') || body.containsKey('miner') ||
            (body['model'] as String? ?? '').toLowerCase().contains('nano') ||
            (body['model'] as String? ?? '').toLowerCase().contains('avalon');
        if (!isAvalon) continue;
        final modelStr = (body['model'] as String? ??
            (body['miner'] as Map?)?['model'] as String? ?? '').toLowerCase();
        var type = MinerType.detect(modelStr);
        if (type == MinerType.generic) type = MinerType.avalonNano3s;
        final name = body['hostname'] as String? ??
            body['model'] as String? ?? 'Avalon Miner';
        return DiscoveredMiner(
          ip: ip, port: port, type: type,
          hostname: name, firmware: body['version'] as String? ?? '',
          source: DiscoverySource.avalonHttp,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<DiscoveredMiner?> _probeCgminerTcp(String ip, int port,
      {Duration? timeout}) async {
    Socket? sock;
    try {
      sock = await Socket.connect(ip, port,
          timeout: timeout ?? _tcpProbeTimeout);
      sock.write('{"command":"summary"}\n');
      await sock.flush();
      final completer = Completer<String>();
      final buf = StringBuffer();
      sock.timeout(const Duration(milliseconds: 1200)).listen(
        (data) {
          buf.write(utf8.decode(data));
          if (buf.toString().contains('SUMMARY')) {
            if (!completer.isCompleted) completer.complete(buf.toString());
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buf.toString());
        },
        onError: (_) {
          if (!completer.isCompleted) completer.completeError('err');
        },
        cancelOnError: true,
      );
      final s = await completer.future
          .timeout(const Duration(seconds: 1), onTimeout: () => '');
      if (!s.contains('SUMMARY')) return null;
      return DiscoveredMiner(
        ip: ip, port: port,
        type: MinerType.generic,
        hostname: ip, firmware: '',
        source: DiscoverySource.cgminerTcp,
      );
    } catch (_) {
      return null;
    } finally {
      sock?.destroy();
    }
  }
}

class DiscoveredMiner {
  final String ip;
  final int port;
  final MinerType type;
  final String hostname;
  final String firmware;
  final DiscoverySource source;

  DiscoveredMiner({
    required this.ip,
    required this.port,
    required this.type,
    required this.hostname,
    required this.firmware,
    required this.source,
  });

  String get key => '$ip:$port';

  Miner toMiner() => Miner(
    name: hostname.isNotEmpty ? hostname : 'Miner at $ip',
    ip: ip,
    port: port,
    type: type,
  );
}

enum DiscoverySource { mdns, espMinerHttp, avalonHttp, cgminerTcp }
