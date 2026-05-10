import 'dart:async';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../services/lan_discovery.dart';
import '../services/miner_store.dart';
import '../widgets/miner_icon.dart';
import '../widgets/klaw.dart';

/// LAN auto-discovery screen.
///
/// Runs LanDiscoveryService.scan() on entry. Each miner is
/// **independently confirmed** via a real API probe before showing.
/// User taps "Add" to add it to the fleet — at that point the miner is
/// added to MinerStore which immediately starts polling. No silent
/// add, no fake confirmations.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  KratosPalette get kc => KratosColors.of(context);

  StreamSubscription<DiscoveredMiner>? _sub;
  final Map<String, DiscoveredMiner> _found = {};
  final Set<String> _added = {};
  bool _scanning = true;
  String _phase = 'looking up mDNS…';
  String? _currentSubnet;          // shown in UI so user knows what’s being scanned
  bool _showManualSubnet = false;  // toggle manual subnet input
  final _subnetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subnetCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start({String? manualSubnet}) async {
    // Resolve subnet for display
    if (manualSubnet != null) {
      _currentSubnet = manualSubnet;
    } else {
      try {
        final ip = await _getWifiIp();
        if (ip != null) {
          final parts = ip.split('.');
          if (parts.length == 4) _currentSubnet = '${parts[0]}.${parts[1]}.${parts[2]}.x';
        } else {
          _currentSubnet = 'fallback subnets';
        }
      } catch (_) {
        _currentSubnet = 'fallback subnets';
      }
    }
    if (mounted) setState(() {});

    try {
      _sub = LanDiscoveryService.instance
          .scan(manualSubnet: manualSubnet)
          .listen(
        (m) {
          if (!mounted) return;
          setState(() {
            _found[m.key] = m;
            _phase = 'found ${_found.length} miner${_found.length == 1 ? '' : 's'}…';
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _phase = _found.isEmpty
                ? 'no miners found — try a different subnet'
                : 'scan complete — ${_found.length} found';
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() { _scanning = false; _phase = 'scan error: $e'; });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _scanning = false; _phase = 'scan failed: $e'; });
    }
  }

  Future<String?> _getWifiIp() async {
    try { return await NetworkInfo().getWifiIP(); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final discovered = _found.values
        .where((m) => !_added.contains(m.key))
        .toList()
      ..sort((a, b) => a.ip.compareTo(b.ip));

    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        title: Text('Discover',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kc.text)),
        actions: [
          // Manual subnet button
          IconButton(
            icon: Icon(Icons.edit_outlined,
                color: _showManualSubnet ? kc.accent : kc.muted),
            tooltip: 'Set subnet manually',
            onPressed: () => setState(() => _showManualSubnet = !_showManualSubnet),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: kc.muted),
            tooltip: 'Re-scan',
            onPressed: _scanning
                ? null
                : () {
                    final manual = _subnetCtrl.text.trim().isNotEmpty
                        ? _subnetCtrl.text.trim() : null;
                    setState(() {
                      _found.clear();
                      _scanning = true;
                      _phase = 'restarting…';
                    });
                    _sub?.cancel();
                    _start(manualSubnet: manual);
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(scanning: _scanning, phase: _phase),
          // Subnet info + manual override
          if (_currentSubnet != null || _showManualSubnet)
            Container(
              color: kc.surface.withOpacity(0.5),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentSubnet != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        '📶 Scanning: $_currentSubnet',
                        style: TextStyle(
                            fontSize: 11, color: kc.muted),
                      ),
                    ),
                  if (_showManualSubnet)
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _subnetCtrl,
                          style: TextStyle(
                              color: kc.text, fontSize: 13,
                              fontFamily: 'Courier'),
                          decoration: InputDecoration(
                            hintText: 'e.g. 192.168.0  or  10.0.0',
                            hintStyle: TextStyle(
                                color: kc.muted, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: kc.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                  color: kc.accent, width: 1),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                  color: kc.accent.withOpacity(0.4)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kc.accent,
                          foregroundColor: const Color(0xFF001A0E),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _scanning ? null : () {
                          final manual = _subnetCtrl.text.trim();
                          setState(() {
                            _found.clear();
                            _scanning = true;
                            _phase = 'scanning $manual…';
                          });
                          _sub?.cancel();
                          _start(manualSubnet: manual.isNotEmpty ? manual : null);
                        },
                        child: Text('Scan',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ]),
                ],
              ),
            ),
          Expanded(
            child: discovered.isEmpty && _scanning
                ? const _ScanningHero()
                : discovered.isEmpty
                    ? const _NothingFoundHero()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: discovered.length,
                        itemBuilder: (ctx, i) =>
                            _DiscoveredCard(
                          miner: discovered[i],
                          onAdd: () => _addMiner(discovered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMiner(DiscoveredMiner d) async {
    final store = context.read<MinerStore>();
    // Avoid duplicates against existing miners.
    final dup = store.miners
        .where((m) => m.ip == d.ip && m.port == d.port)
        .firstOrNull;
    if (dup != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${d.hostname} already in fleet')),
      );
      setState(() => _added.add(d.key));
      return;
    }
    store.add(d.toMiner(), warmUp: true);
    setState(() => _added.add(d.key));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: kc.accent),
          SizedBox(width: 10),
          Expanded(child: Text('${d.hostname} added')),
        ]),
        backgroundColor: kc.surface2,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _StatusBar extends StatelessWidget {
  final bool scanning;
  final String phase;
  const _StatusBar({required this.scanning, required this.phase});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      color: kc.surface.withOpacity(0.7),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (scanning)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kc.accent,
              ),
            )
          else
            Icon(Icons.check_circle,
                size: 14, color: kc.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              phase,
              style: TextStyle(
                color: kc.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveredCard extends StatelessWidget {
  final DiscoveredMiner miner;
  final VoidCallback onAdd;
  const _DiscoveredCard({required this.miner, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kc.accent.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          MinerIcon(type: miner.type, size: 40),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miner.hostname,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kc.text)),
                SizedBox(height: 2),
                Text(
                    '${miner.type.displayName} · ${miner.ip}${miner.firmware.isNotEmpty ? " · ${miner.firmware}" : ""}',
                    style: TextStyle(
                        fontSize: 11, color: kc.muted)),
                if (miner.source != DiscoverySource.cgminerTcp)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kc.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                          miner.source == DiscoverySource.mdns
                              ? 'mDNS'
                              : 'ESP-Miner API',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: kc.accentBright,
                              letterSpacing: 0.6)),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kc.accent,
              foregroundColor: const Color(0xFF001A0E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99)),
            ),
            onPressed: onAdd,
            child: Text('Add',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.15, end: 0);
  }
}

class _ScanningHero extends StatelessWidget {
  const _ScanningHero();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Klaw(size: 120),
            )
                .animate(onPlay: (c) => c.repeat())
                .scale(
                    duration: 1400.ms,
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1.05, 1.05),
                    curve: Curves.easeInOut)
                .then()
                .scale(
                    duration: 1400.ms,
                    begin: const Offset(1.05, 1.05),
                    end: const Offset(0.95, 0.95),
                    curve: Curves.easeInOut),
            SizedBox(height: 22),
            Text(
              'Sniffing the LAN…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kc.text),
            ),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Klaw is checking every ESP-Miner and cgminer on your network. Up to ~10 seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: kc.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingFoundHero extends StatelessWidget {
  const _NothingFoundHero();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: KlawEmptyState(
        headline: 'Nothing on the network.',
        quip: "Klaw didn't find any miners.\nMake sure your phone is on the same Wi-Fi as the miner, and that the miner is powered on.",
      ),
    );
  }
}
