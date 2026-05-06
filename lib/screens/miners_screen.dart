import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../widgets/miner_card.dart';
import '../widgets/fleet_summary_bar.dart';
import '../widgets/klaw.dart';
import 'add_miner_screen.dart';
import 'miner_detail_screen.dart';
import 'fleet_oc_screen.dart';

/// Fleet view tab — list / grid of all miners.
/// Logic preserved from v1.0 DashboardScreen, theme + Klaw upgraded.
class MinersScreen extends StatefulWidget {
  const MinersScreen({super.key});

  @override
  State<MinersScreen> createState() => _MinersScreenState();
}

class _MinersScreenState extends State<MinersScreen> {
  bool _grid = false;
  String? _longPressedId;

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  Future<void> _loadView() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _grid = prefs.getBool('kratos_grid_view') ?? false);
  }

  Future<void> _saveView(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kratos_grid_view', v);
  }

  void _delete(MinerStore store, Miner miner) {
    final i = store.miners.indexOf(miner);
    store.remove(miner.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: KratosColors.surface2,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        const Icon(Icons.delete_outline,
            color: KratosColors.danger, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text('${miner.name} removed',
                style: const TextStyle(color: KratosColors.text))),
      ]),
      action: SnackBarAction(
        label: 'UNDO',
        textColor: KratosColors.volt,
        onPressed: () => store.reinsert(miner, i),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_longPressedId != null) setState(() => _longPressedId = null);
      },
      child: Scaffold(
        backgroundColor: KratosColors.bg,
        appBar: AppBar(
          backgroundColor: KratosColors.bg,
          title: const Text('Miners',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: KratosColors.text)),
          actions: [
            if (context
                .watch<MinerStore>()
                .miners
                .any((m) => m.type.apiType == ApiType.espMinerHttp))
              IconButton(
                tooltip: 'Fleet OC',
                icon: const Icon(Icons.bolt,
                    color: KratosColors.volt, size: 22),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const FleetOCScreen()),
                ),
              ),
            IconButton(
              icon: Icon(
                  _grid
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                  color: KratosColors.muted,
                  size: 22),
              onPressed: () {
                setState(() {
                  _grid = !_grid;
                  _longPressedId = null;
                });
                _saveView(_grid);
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Consumer<MinerStore>(
          builder: (ctx, store, _) {
            if (store.miners.isEmpty) return const _Empty();
            return RefreshIndicator(
              color: KratosColors.volt,
              backgroundColor: KratosColors.surface,
              onRefresh: store.refreshAll,
              child: _grid ? _buildGrid(store) : _buildList(store),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(MinerStore store) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 12),
        const FleetSummaryBar(),
        const SizedBox(height: 12),
        ...store.miners.map((m) {
          final s = store.stats[m.id];
          final earnings = store.minerDailyEarningsUsd(m.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: ValueKey(m.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: KratosColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: KratosColors.danger.withOpacity(0.4)),
                ),
                child: const Icon(Icons.delete_outline,
                    color: KratosColors.danger, size: 24),
              ),
              confirmDismiss: (_) async => true,
              onDismissed: (_) => _delete(store, m),
              child: MinerCard(
                key: ValueKey('card_${m.id}'),
                miner: m,
                stats: s,
                earningsPerDay: earnings,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MinerDetailScreen(miner: m)),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGrid(MinerStore store) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: const FleetSummaryBar(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final m = store.miners[i];
                final s = store.stats[m.id];
                final earnings = store.minerDailyEarningsUsd(m.id);
                return MinerGridCard(
                  key: ValueKey('grid_${m.id}'),
                  miner: m,
                  stats: s,
                  earningsPerDay: earnings,
                  showDeleteBadge: _longPressedId == m.id,
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (_) => MinerDetailScreen(miner: m)),
                  ),
                  onLongPress: () =>
                      setState(() => _longPressedId = m.id),
                  onDeleteTap: () {
                    setState(() => _longPressedId = null);
                    _delete(store, m);
                  },
                );
              },
              childCount: store.miners.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: KlawEmptyState(
        headline: 'No miners yet',
        quip: 'Klaw needs hashing to do.\nAdd your first miner to start the forge.',
        cta: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: KratosColors.volt,
            foregroundColor: const Color(0xFF001A0E),
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99)),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMinerScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add Miner',
              style:
                  TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
    );
  }
}
