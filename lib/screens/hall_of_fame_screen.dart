import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/best_diff_tracker.dart';
import '../services/global_leaderboard_service.dart';
import '../services/miner_store.dart';
import '../widgets/miner_icon.dart';

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key});
  @override State<HallOfFameScreen> createState() => _HallOfFameState();
}

class _HallOfFameState extends State<HallOfFameScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _global = GlobalLeaderboardService.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _global.addListener(_onGlobal);
    _global.fetchLeaderboard();
  }

  @override
  void dispose() {
    _global.removeListener(_onGlobal);
    _tabs.dispose();
    super.dispose();
  }

  void _onGlobal() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final tracker = store.bestDiffTracker;
      final myRecords = tracker.records.values
          .where((r) => r.bestShare > 0)
          .map(BestDiffRecordView.from)
          .toList()
        ..sort((a, b) => b.bestShare.compareTo(a.bestShare));

      return Scaffold(
        backgroundColor: KratosTheme.bg,
        appBar: AppBar(
          backgroundColor: KratosTheme.bg,
          title: const Row(children: [
            Text('🏆', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text('Hall of Fame',
                style: TextStyle(color: KratosTheme.textPrim, fontWeight: FontWeight.w800)),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: KratosTheme.muted),
              onPressed: () {
                store.refreshAll();
                _global.fetchLeaderboard(force: true);
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: KratosTheme.orange,
            labelColor: KratosTheme.orange,
            unselectedLabelColor: KratosTheme.muted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            tabs: [
              const Tab(text: 'MY FLEET'),
              Tab(text: _global.stats != null
                  ? 'GLOBAL  ${_global.stats!.totalMiners}'
                  : 'GLOBAL'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            // ── Tab 1: My Fleet ──────────────────────────────────────────
            _FleetTab(records: myRecords, tracker: tracker),
            // ── Tab 2: Global ────────────────────────────────────────────
            _GlobalTab(service: _global),
          ],
        ),
      );
    });
  }
}

// ── My Fleet tab ─────────────────────────────────────────────────────────────

class _FleetTab extends StatelessWidget {
  final List<BestDiffRecordView> records;
  final BestDiffTracker tracker;
  const _FleetTab({required this.records, required this.tracker});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const _EmptyState(isGlobal: false);
    final fleet = tracker.fleetRecord;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (fleet != null) ...[
        _ChampionCard(
          name: fleet.minerName,
          model: fleet.minerModel,
          type: fleet.type,
          bestDiff: fleet.bestShare,
          achievedAt: fleet.achievedAt,
          isGlobal: false,
        ),
        const SizedBox(height: 20),
        const _SectionLabel('RANKING'),
        const SizedBox(height: 10),
      ],
      ...records.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RankCard(
            rank: e.key + 1,
            name: e.value.minerName,
            model: e.value.minerModel,
            type: e.value.type,
            bestDiff: e.value.bestShare,
            achievedAt: e.value.achievedAt,
          ))),
      const SizedBox(height: 16),
      _InfoNote('Scores update every 30s from your miner\'s API. '
          'Your records are automatically submitted to the Global leaderboard.'),
      const SizedBox(height: 32),
    ]);
  }
}

// ── Global tab ────────────────────────────────────────────────────────────────

class _GlobalTab extends StatelessWidget {
  final GlobalLeaderboardService service;
  const _GlobalTab({required this.service});

  @override
  Widget build(BuildContext context) {
    if (service.loading && service.leaderboard.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: KratosTheme.orange));
    }
    if (service.error != null && service.leaderboard.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: KratosTheme.muted, size: 48),
          const SizedBox(height: 16),
          Text(service.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KratosTheme.muted)),
        ]),
      ));
    }
    if (service.leaderboard.isEmpty) return const _EmptyState(isGlobal: true);

    final records = service.leaderboard;
    final top = records.first;

    return RefreshIndicator(
      color: KratosTheme.orange,
      backgroundColor: KratosTheme.surface,
      onRefresh: () => service.fetchLeaderboard(force: true),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Global stats bar
        if (service.stats != null)
          _GlobalStatsBar(stats: service.stats!),
        const SizedBox(height: 16),
        // Champion
        _ChampionCard(
          name: top.name,
          model: top.model,
          type: MinerType.detect(top.model.isNotEmpty ? top.model : top.type),
          bestDiff: top.bestDiff,
          achievedAt: top.achievedAt,
          isGlobal: true,
        ),
        const SizedBox(height: 20),
        const _SectionLabel('GLOBAL RANKING'),
        const SizedBox(height: 10),
        ...records.skip(1).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RankCard(
              rank: r.rank,
              name: r.name,
              model: r.model,
              type: MinerType.detect(r.model.isNotEmpty ? r.model : r.type),
              bestDiff: r.bestDiff,
              achievedAt: r.achievedAt,
            ))),
        const SizedBox(height: 16),
        _InfoNote('Global leaderboard from all Kratos users worldwide. '
            'Your best records are submitted automatically. '
            'Miner IDs are anonymised — only name and model are shared.'),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _GlobalStatsBar extends StatelessWidget {
  final GlobalStats stats;
  const _GlobalStatsBar({required this.stats});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: KratosTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: KratosTheme.border),
    ),
    child: Row(children: [
      const Text('🌍', style: TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${stats.totalMiners} miners worldwide',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                color: KratosTheme.textPrim)),
        const Text('Best difficulty submissions from Kratos users',
            style: TextStyle(fontSize: 11, color: KratosTheme.muted)),
      ]),
    ]),
  );
}

class _ChampionCard extends StatelessWidget {
  final String name, model;
  final MinerType type;
  final double bestDiff;
  final DateTime achievedAt;
  final bool isGlobal;
  const _ChampionCard({required this.name, required this.model,
    required this.type, required this.bestDiff,
    required this.achievedAt, required this.isGlobal});

  @override
  Widget build(BuildContext context) {
    final diff  = formatBestDiff(bestDiff);
    final color = _diffColor(bestDiff);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(isGlobal ? '🌍' : '👑', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(isGlobal ? 'WORLD RECORD' : 'FLEET RECORD',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: color, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          MinerIcon(type: type, size: 44),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: KratosTheme.textPrim)),
            if (model.isNotEmpty)
              Text(model, style: const TextStyle(fontSize: 12, color: KratosTheme.muted)),
            const SizedBox(height: 4),
            Text(_fmtDate(achievedAt),
                style: const TextStyle(fontSize: 11, color: KratosTheme.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(diff, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
                color: color, fontFamily: 'Courier')),
            const Text('best difficulty',
                style: TextStyle(fontSize: 9, color: KratosTheme.muted, letterSpacing: 0.5)),
          ]),
        ]),
      ]),
    );
  }
}

class _RankCard extends StatelessWidget {
  final int rank;
  final String name, model;
  final MinerType type;
  final double bestDiff;
  final DateTime achievedAt;
  const _RankCard({required this.rank, required this.name, required this.model,
    required this.type, required this.bestDiff, required this.achievedAt});

  @override
  Widget build(BuildContext context) {
    final diff  = formatBestDiff(bestDiff);
    final color = _diffColor(bestDiff);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: rank == 1 ? color.withOpacity(0.06) : KratosTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank <= 3 ? color.withOpacity(0.3) : KratosTheme.border,
          width: rank == 1 ? 1.5 : 1),
      ),
      child: Row(children: [
        SizedBox(width: 36, child: Center(child: _RankBadge(rank: rank))),
        const SizedBox(width: 12),
        MinerIcon(type: type, size: 34),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: KratosTheme.textPrim), overflow: TextOverflow.ellipsis),
          if (model.isNotEmpty)
            Text(model, style: const TextStyle(fontSize: 11, color: KratosTheme.muted),
                overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(diff, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
              color: color, fontFamily: 'Courier')),
          Text(_fmtDate(achievedAt),
              style: const TextStyle(fontSize: 10, color: KratosTheme.muted)),
        ]),
      ]),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});
  @override
  Widget build(BuildContext context) {
    if (rank == 1) return const Text('🥇', style: TextStyle(fontSize: 24));
    if (rank == 2) return const Text('🥈', style: TextStyle(fontSize: 22));
    if (rank == 3) return const Text('🥉', style: TextStyle(fontSize: 22));
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: KratosTheme.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KratosTheme.border)),
      alignment: Alignment.center,
      child: Text('$rank', style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w800, color: KratosTheme.muted, fontFamily: 'Courier')),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800,
      color: KratosTheme.muted, letterSpacing: 1.5));
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KratosTheme.border)),
    child: Text(text, style: const TextStyle(
        fontSize: 12, color: KratosTheme.muted, height: 1.5)),
  );
}

class _EmptyState extends StatelessWidget {
  final bool isGlobal;
  const _EmptyState({required this.isGlobal});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏆', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 20),
        Text(isGlobal ? 'Global leaderboard is empty' : 'Your fleet has no records yet',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                color: KratosTheme.textPrim)),
        const SizedBox(height: 10),
        Text(
          isGlobal
              ? 'Be the first to submit a difficulty record.\nStart mining and it appears automatically.'
              : 'Keep mining! Your best difficulty shares\nwill appear here automatically.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: KratosTheme.muted, height: 1.5),
        ),
      ]),
    ),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _diffColor(double v) {
  if (v >= 1e15) return const Color(0xFFFFD700);
  if (v >= 1e12) return KratosTheme.orange;
  if (v >= 1e9)  return KratosTheme.neon;
  return KratosTheme.blue;
}

String _fmtDate(DateTime dt) {
  const m = ['Jan','Feb','Mar','Apr','May','Jun',
              'Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
}
