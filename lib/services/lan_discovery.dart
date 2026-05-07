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
///    Most BitAxe / NerdAxe firmware advertises an mDNS service.
/// 2. **Subnet ping sweep + ESP-Miner probe** — for the user's `/24`
///    subnet, probe every host on port 80 with `GET /api/system/info`.
///    Confirms BitAxe-family devices in <8 s on a typical home LAN.
/// 3. **cgminer probe** — same subnet, port 4028 TCP open + JSON
///    `summary` request → confirms Avalon / Antminer / Whatsminer /
///    Goldshell / Lucky Miner.
///
/// **Real data only.** A discovered miner is reported only when its API
/// actually responds with valid stats. No optimistic guesses.
class LanDiscoveryService {
  LanDiscoveryService._();
  static final instance = LanDiscoveryService._();

  // Generous timeouts — NerdOctaxe/NerdQAxe can be slow under load.
  // 1.5 s for HTTP (was 800 ms), 900 ms for cgminer TCP (was 600 ms).
  static const _httpProbeTimeout = Duration(milliseconds: 1500);
  static const _tcpProbeTimeout = Duration(milliseconds: 900);

  /// Streams discovered miners as they're confirmed. Caller is
  /// responsible for de-duplicating against existing miners.
  Stream<DiscoveredMiner> scan() async* {
    final controller = StreamController<DiscoveredMiner>();

    // Get the LAN subnet we're attached to. Wrapped because
    // network_info_plus can throw on some Android devices.
    String? subnet;
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      subnet = _subnetFor(wifiIp);
    } catch (e) {
      if (kDebugMode) debugPrint('LAN: failed to read Wi-Fi IP: $e');
    }

    // Run mDNS + sweep concurrently. Each future swallows its own errors
    // so a single platform hiccup never bubbles up as an unhandled
    // exception that would also skip controller.close().
    final futures = <Future<void>>[
      _runMdnsScan(controller).catchError((e) {
        if (kDebugMode) debugPrint('LAN: mDNS error swallowed: $e');
      }),
      if (subnet != null)
        _runSubnetSweep(subnet, controller).catchError((e) {
          if (kDebugMode) debugPrint('LAN: sweep error swallowed: $e');
        }),
    ];

    // Close stream when both finish. Guard against double-close.
    Future.wait(futures).whenComplete(() {
      if (!controller.isClosed) controller.close();
    });

    yield* controller.stream;
  }

  void _safeAdd(
      StreamController<DiscoveredMiner> sink, DiscoveredMiner m) {
    if (!sink.isClosed) sink.add(m);
  }

  String? _subnetFor(String? ip) {
    if (ip == null || !ip.contains('.')) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  // ── mDNS ────────────────────────────────────────────────────────────

  Future<void> _runMdnsScan(
      StreamController<DiscoveredMiner> sink) async {
    final mdns = MDnsClient(rawDatagramSocketFactory: (
      dynamic host,
      int port, {
      bool? reuseAddress,
      bool? reusePort,
      int? ttl,
    }) =>
        RawDatagramSocket.bind(
          host,
          port,
          reuseAddress: reuseAddress ?? true,
          reusePort: false,
          ttl: ttl ?? 1,
        ));

    try {
      await mdns.start();
      // Some firmware advertises `_http._tcp`, others `_esp-miner._tcp`.
      const services = [
        '_http._tcp.local',
        '_esp-miner._tcp.local',
      ];
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
              final probed = await _probeEspMinerHttp(
                  addr.address.address, srv.port);
              if (probed != null) _safeAdd(sink, probed);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('mDNS scan error: $e');
      }
    } finally {
      mdns.stop();
    }
  }

  // ── Subnet sweep ────────────────────────────────────────────────────

  Future<void> _runSubnetSweep(
    String subnet,
    StreamController<DiscoveredMiner> sink,
  ) async {
    // Concurrency: 20 hosts in flight at once (reduced from 32 so each
    // probe gets more bandwidth — helps on congested Wi-Fi with many miners).
    const batchSize = 20;
    final hosts = List<int>.generate(254, (i) => i + 1);
    for (var i = 0; i < hosts.length; i += batchSize) {
      final batch = hosts.skip(i).take(batchSize);
      await Future.wait(batch.map((h) async {
        final ip = '$subnet.$h';
        // Probe port 80 AND 8080 concurrently — some NerdAxe firmware
        // uses 8080. First hit wins; skip cgminer if ESP-Miner replied.
        final results = await Future.wait([
          _probeEspMinerHttp(ip, 80),
          _probeEspMinerHttp(ip, 8080),
        ]);
        final esp = results.firstWhere((r) => r != null, orElse: () => null);
        if (esp != null) {
          _safeAdd(sink, esp);
          return;
        }
        final cg = await _probeCgminerTcp(ip, 4028);
        if (cg != null) _safeAdd(sink, cg);
      }));
    }
  }

  // ── Probes ──────────────────────────────────────────────────────────

  Future<DiscoveredMiner?> _probeEspMinerHttp(String ip, int port) async {
    try {
      final resp = await http
          .get(Uri.parse('http://$ip:$port/api/system/info'),
              headers: {'Accept': 'application/json'})
          .timeout(_httpProbeTimeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;
      final hostname = (body['hostname'] as String?)?.trim() ?? 'BitAxe';
      final model = (body['ASICModel'] as String?) ??
          (body['model'] as String?) ??
          '';
      final type = MinerType.detect(hostname.isNotEmpty ? hostname : model);
      return DiscoveredMiner(
        ip: ip,
        port: port,
        type: type,
        hostname: hostname.isNotEmpty ? hostname : model,
        firmware: (body['version'] as String?) ?? '',
        source: DiscoverySource.espMinerHttp,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DiscoveredMiner?> _probeCgminerTcp(String ip, int port) async {
    Socket? sock;
    try {
      sock = await Socket.connect(ip, port, timeout: _tcpProbeTimeout);
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
      // Parse minimal model identification — cgminer summary doesn't
      // always include device model; auto-detect later in MinerStore.
      return DiscoveredMiner(
        ip: ip,
        port: port,
        type: MinerType.generic,
        hostname: ip,
        firmware: '',
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

  /// Stable key for deduplication.
  String get key => '$ip:$port';

  Miner toMiner() => Miner(
        name: hostname.isNotEmpty ? hostname : 'Miner at $ip',
        ip: ip,
        port: port,
        type: type,
      );
}

enum DiscoverySource {
  mdns,
  espMinerHttp,
  cgminerTcp,
}
