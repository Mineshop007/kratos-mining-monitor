import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
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
  StreamSubscription<DiscoveredMiner>? _sub;
  final Map<String, DiscoveredMiner> _found = {};
  final Set<String> _added = {};
  bool _scanning = true;
  String _phase = 'looking up mDNS…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _sub = LanDiscoveryService.instance.scan().listen(
        (m) {
          if (!mounted) return;
          setState(() {
            _found[m.key] = m;
            _phase = 'sweeping subnet…';
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _phase = _found.isEmpty
                ? 'no miners found on your LAN'
                : 'scan complete';
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _phase = 'scan error: $e';
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _phase = 'scan failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final discovered = _found.values
        .where((m) => !_added.contains(m.key))
        .toList()
      ..sort((a, b) => a.ip.compareTo(b.ip));

    return Scaffold(
      backgroundColor: KratosColors.bg,
      appBar: AppBar(
        title: const Text('Discover',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KratosColors.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: KratosColors.muted),
            tooltip: 'Re-scan',
            onPressed: _scanning
                ? null
                : () {
                    setState(() {
                      _found.clear();
                      _scanning = true;
                      _phase = 'restarting…';
                    });
                    _sub?.cancel();
                    _start();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(scanning: _scanning, phase: _phase),
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
    store.add(d.toMiner());
    setState(() => _added.add(d.key));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: KratosColors.volt),
          const SizedBox(width: 10),
          Expanded(child: Text('${d.hostname} added')),
        ]),
        backgroundColor: KratosColors.surface2,
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
    return Container(
      color: KratosColors.surface.withOpacity(0.7),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (scanning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: KratosColors.volt,
              ),
            )
          else
            const Icon(Icons.check_circle,
                size: 14, color: KratosColors.volt),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phase,
              style: const TextStyle(
                color: KratosColors.muted,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KratosColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KratosColors.volt.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          MinerIcon(type: miner.type, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miner.hostname,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KratosColors.text)),
                const SizedBox(height: 2),
                Text(
                    '${miner.type.displayName} · ${miner.ip}${miner.firmware.isNotEmpty ? " · ${miner.firmware}" : ""}',
                    style: const TextStyle(
                        fontSize: 11, color: KratosColors.muted)),
                if (miner.source != DiscoverySource.cgminerTcp)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KratosColors.volt.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                          miner.source == DiscoverySource.mdns
                              ? 'mDNS'
                              : 'ESP-Miner API',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: KratosColors.voltBright,
                              letterSpacing: 0.6)),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KratosColors.volt,
              foregroundColor: const Color(0xFF001A0E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99)),
            ),
            onPressed: onAdd,
            child: const Text('Add',
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
            const SizedBox(height: 22),
            const Text(
              'Sniffing the LAN…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KratosColors.text),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Klaw is checking every ESP-Miner and cgminer on your network. Up to ~10 seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: KratosColors.muted, height: 1.4),
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
    return Center(
      child: KlawEmptyState(
        headline: 'Nothing on the network.',
        quip: "Klaw didn't find any miners.\nMake sure your phone is on the same Wi-Fi as the miner, and that the miner is powered on.",
      ),
    );
  }
}
