import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/best_diff_tracker.dart';
import '../services/miner_store.dart';
import '../widgets/miner_icon.dart';

class HallOfFameScreen extends StatelessWidget {
  const HallOfFameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final tracker = store.bestDiffTracker;
      final records = tracker.records.values
          .where((r) => r.bestShare > 0)
          .map(BestDiffRecordView.from)
          .toList()
        ..sort((a, b) => b.bestShare.compareTo(a.bestShare));

      final fleet = tracker.fleetRecord;

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
              onPressed: () => store.refreshAll(),
            ),
          ],
        ),
        body: records.isEmpty
            ? _EmptyState()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Fleet champion card ──────────────────────────────
                  if (fleet != null) ...[
                    _ChampionCard(record: BestDiffRecordView.from(fleet)),
                    const SizedBox(height: 20),
                    const Text('LEADERBOARD',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800,
                            color: KratosTheme.muted, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                  ],
                  // ── Ranked list ──────────────────────────────────────
                  ...records.asMap().entries.map((e) =>
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RankCard(rank: e.key + 1, record: e.value),
                      )),
                  const SizedBox(height: 20),
                  // Footer note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KratosTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: KratosTheme.border),
                    ),
                    child: const Text(
                      '💡 Best difficulty is read directly from your miner\'s API. '
                      'Records persist across app restarts. '
                      'Higher = closer to finding a block.',
                      style: TextStyle(fontSize: 12, color: KratosTheme.muted, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      );
    });
  }
}

// ── Champion banner ──────────────────────────────────────────────────────────

class _ChampionCard extends StatelessWidget {
  final BestDiffRecordView record;
  const _ChampionCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final diff = formatBestDiff(record.bestShare);
    final color = _diffColor(record.bestShare);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('👑', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text('ALL-TIME FLEET RECORD',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: color, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          MinerIcon(type: record.type, size: 44),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.minerName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                    color: KratosTheme.textPrim)),
            if (record.minerModel.isNotEmpty)
              Text(record.minerModel,
                  style: const TextStyle(fontSize: 12, color: KratosTheme.muted)),
            const SizedBox(height: 4),
            Text(_fmtDate(record.achievedAt),
                style: const TextStyle(fontSize: 11, color: KratosTheme.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(diff,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
                    color: color, fontFamily: 'Courier')),
            Text('best difficulty',
                style: const TextStyle(fontSize: 9, color: KratosTheme.muted,
                    letterSpacing: 0.5)),
          ]),
        ]),
      ]),
    );
  }
}

// ── Rank card ────────────────────────────────────────────────────────────────

class _RankCard extends StatelessWidget {
  final int rank;
  final BestDiffRecordView record;
  const _RankCard({required this.rank, required this.record});

  @override
  Widget build(BuildContext context) {
    final diff = formatBestDiff(record.bestShare);
    final color = _diffColor(record.bestShare);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: rank == 1
            ? color.withOpacity(0.06)
            : KratosTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank <= 3 ? color.withOpacity(0.3) : KratosTheme.border,
          width: rank == 1 ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        // Rank badge
        SizedBox(
          width: 36,
          child: Center(child: _RankBadge(rank: rank)),
        ),
        const SizedBox(width: 12),
        // Miner icon
        MinerIcon(type: record.type, size: 34),
        const SizedBox(width: 12),
        // Name + model
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record.minerName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: KratosTheme.textPrim),
              overflow: TextOverflow.ellipsis),
          if (record.minerModel.isNotEmpty)
            Text(record.minerModel,
                style: const TextStyle(fontSize: 11, color: KratosTheme.muted),
                overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 10),
        // Diff + date
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(diff,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                  color: color, fontFamily: 'Courier')),
          Text(_fmtDate(record.achievedAt),
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
      decoration: BoxDecoration(
        color: KratosTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KratosTheme.border),
      ),
      alignment: Alignment.center,
      child: Text('$rank',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
              color: KratosTheme.muted, fontFamily: 'Courier')),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏆', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          const Text('Hall of Fame is empty',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                  color: KratosTheme.textPrim)),
          const SizedBox(height: 10),
          const Text(
            'Mine your first share to appear here.\nThe higher the difficulty, the closer you are to a block.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: KratosTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KratosTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KratosTheme.border),
            ),
            child: const Text(
              'Records update automatically every 30s\nfrom your miner\'s API.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: KratosTheme.muted, height: 1.5),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Color _diffColor(double v) {
  if (v >= 1e15) return const Color(0xFFFFD700); // Gold — Petahash
  if (v >= 1e12) return KratosTheme.orange;       // Orange — Terahash
  if (v >= 1e9)  return KratosTheme.neon;         // Green — Gigahash
  return KratosTheme.blue;                         // Blue — Megahash and below
}

String _fmtDate(DateTime dt) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
