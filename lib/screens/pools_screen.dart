import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../services/best_diff_tracker.dart';
import '../widgets/klaw.dart';
import 'miner_detail_screen.dart';
import 'sha256_switchboard_screen.dart';

/// Pools tab — universal best-diff hero + multi-pool fleet split.
/// Block-found feed (Discord-bridged) layers in once the server endpoint
/// ships in v1.3. For now we show only **real, observed values**:
///  • Each miner's bestShare (live from API),
///  • Fleet all-time best (persisted by BestDiffTracker),
///  • Pool split derived from each miner's active stratum URL.
class PoolsScreen extends StatelessWidget {
  const PoolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('Pools',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: kc.text)),
        actions: [
          IconButton(
            tooltip: 'SHA-256 switchboard',
            icon: Icon(Icons.swap_horiz_rounded, color: kc.accent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const Sha256SwitchboardScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<MinerStore>(
        builder: (ctx, store, _) {
          if (store.miners.isEmpty) {
            return Center(
              child: KlawEmptyState(
                headline: 'Pools live here',
                quip:
                    'Add a miner first.\nKlaw will track every share, on every pool, on every coin.',
              ),
            );
          }
          return _Body(store: store);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final MinerStore store;
  const _Body({required this.store});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return RefreshIndicator(
      color: kc.accent,
      backgroundColor: kc.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          _SwitchboardTeaser(),
          SizedBox(height: 14),
          _BestDiffHero(store: store),
          SizedBox(height: 14),
          _FleetByPoolCard(store: store),
          SizedBox(height: 14),
          _PerMinerBestList(store: store),
        ],
      ),
    );
  }
}

class _SwitchboardTeaser extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Sha256SwitchboardScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              KratosColors.cyan.withOpacity(0.18),
              KratosColors.coinBtc.withOpacity(0.10),
              kc.surface.withOpacity(0.75),
            ],
          ),
          border: Border.all(color: KratosColors.cyan.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: KratosColors.cyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: KratosColors.cyan.withOpacity(0.35)),
            ),
            child: Icon(Icons.swap_horiz_rounded, color: KratosColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SHA-256 Switchboard',
                  style: TextStyle(
                      color: kc.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
              const SizedBox(height: 3),
              Text('BTC, BCH and smart pool presets in one simple view',
                  style: TextStyle(color: kc.muted, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: kc.muted),
        ]),
      ),
    );
  }
}

class _BestDiffHero extends StatelessWidget {
  final MinerStore store;
  const _BestDiffHero({required this.store});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final fleet = store.bestDiffTracker.fleetRecord;
    final has = fleet != null && fleet.bestShare > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kc.accent.withOpacity(0.18),
            kc.accent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kc.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🎯 BEST DIFF · FLEET ALL-TIME',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: kc.muted,
                ),
              ),
              if (has)
                Text(
                  _agoLabel(fleet.achievedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: kc.muted,
                  ),
                ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => LinearGradient(colors: [
                  kc.accentBright,
                  kc.accent,
                ]).createShader(r),
                child: Text(
                  has ? formatBestDiff(fleet.bestShare) : '—',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            has
                ? '${fleet.minerName} · ${fleet.type.displayName}'
                : 'Awaiting first share with measurable difficulty',
            style: TextStyle(
              fontSize: 12,
              color: kc.muted,
            ),
          ),
        ],
      ),
    );
  }

  static String _agoLabel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${d.inDays ~/ 30}mo ago';
  }
}

class _FleetByPoolCard extends StatelessWidget {
  final MinerStore store;
  const _FleetByPoolCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    // Group active miners by their currently active stratum host.
    final byHost = <String, _PoolBucket>{};
    for (final m in store.miners) {
      final s = store.stats[m.id];
      if (s == null) continue;
      final activePool = s.pools.firstWhere(
        (p) => p.active,
        orElse: () => s.pools.isEmpty
            ? const PoolInfo(index: 0, url: 'unknown', user: '')
            : s.pools.first,
      );
      final host = activePool.host.isEmpty ? 'unknown' : activePool.host;
      final bucket = byHost.putIfAbsent(host, () => _PoolBucket(host: host));
      bucket.count += 1;
      if (s.status != MinerStatus.offline) {
        bucket.hashrateGh += s.hashrateAvg;
      }
    }

    if (byHost.isEmpty) {
      return _emptyShell(
        context,
        text: 'No pool data yet — Klaw is waiting for the first share.',
      );
    }

    final buckets = byHost.values.toList()
      ..sort((a, b) => b.hashrateGh.compareTo(a.hashrateGh));
    final palette = [
      kc.accent,
      kc.secondary,
      KratosColors.info,
      KratosColors.warning,
      KratosColors.coinCkb,
      KratosColors.coinDoge,
    ];

    final totalGh = buckets.fold<double>(0, (sum, b) => sum + b.hashrateGh);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kc.accent.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fleet by pool',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kc.text)),
              Text('${store.miners.length} miners',
                  style: TextStyle(fontSize: 11, color: kc.muted)),
            ],
          ),
          SizedBox(height: 12),
          if (totalGh > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < buckets.length; i++)
                      Expanded(
                        flex: ((buckets[i].hashrateGh / totalGh) * 1000)
                            .round()
                            .clamp(1, 1000),
                        child: Container(color: palette[i % palette.length]),
                      ),
                  ],
                ),
              ),
            ),
          SizedBox(height: 12),
          for (var i = 0; i < buckets.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette[i % palette.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      buckets[i].host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: kc.text,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${buckets[i].count} · ${_hashLabel(buckets[i].hashrateGh)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: kc.muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _hashLabel(double gh) {
    if (gh <= 0) return '0';
    if (gh >= 1000) return '${(gh / 1000).toStringAsFixed(2)} TH/s';
    if (gh >= 1) return '${gh.toStringAsFixed(1)} GH/s';
    return '${(gh * 1000).toStringAsFixed(0)} MH/s';
  }

  static Widget _emptyShell(BuildContext context, {required String text}) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kc.line),
      ),
      child: Text(text, style: TextStyle(color: kc.muted, fontSize: 13)),
    );
  }
}

class _PoolBucket {
  final String host;
  int count = 0;
  double hashrateGh = 0;
  _PoolBucket({required this.host});
}

class _PerMinerBestList extends StatelessWidget {
  final MinerStore store;
  const _PerMinerBestList({required this.store});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final entries = store.miners.map((m) {
      final s = store.stats[m.id];
      final tracked = store.bestDiffTracker.records[m.id];
      return _MinerLine(
        miner: m,
        bestShare: (tracked?.bestShare ?? s?.bestShare ?? 0).toDouble(),
        sessionShare: s?.bestShare ?? 0,
        online:
            s?.status == MinerStatus.online || s?.status == MinerStatus.warning,
      );
    }).toList()
      ..sort((a, b) => b.bestShare.compareTo(a.bestShare));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kc.accent.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Per-miner best diff',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: kc.text)),
          SizedBox(height: 12),
          for (final e in entries) ...[
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MinerDetailScreen(miner: e.miner)),
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: e.online ? kc.accent : kc.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.miner.name,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: kc.text)),
                          Text(e.miner.type.displayName,
                              style: TextStyle(fontSize: 11, color: kc.muted)),
                        ],
                      ),
                    ),
                    Text(
                      e.bestShare > 0 ? formatBestDiff(e.bestShare) : '—',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kc.accentBright,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: kc.line, height: 14),
          ],
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline, size: 12, color: kc.muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: each miner\'s local API. Updated every 30s. Block-found notifications fire when bestDiff ≥ network difficulty.',
                  style: TextStyle(
                      fontSize: 10,
                      color: kc.muted.withOpacity(0.85),
                      height: 1.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MinerLine {
  final Miner miner;
  final double bestShare;
  final double sessionShare;
  final bool online;
  _MinerLine({
    required this.miner,
    required this.bestShare,
    required this.sessionShare,
    required this.online,
  });
}
