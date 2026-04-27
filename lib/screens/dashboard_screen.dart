import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../widgets/miner_card.dart';
import '../widgets/fleet_summary_bar.dart';
import 'add_miner_screen.dart';
import 'miner_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isGridView = false;
  String? _longPressedId; // grid delete badge

  @override
  void initState() {
    super.initState();
    _loadViewPref();
  }

  Future<void> _loadViewPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { _isGridView = prefs.getBool('kratos_grid_view') ?? false; });
  }

  Future<void> _saveViewPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kratos_grid_view', value);
  }

  void _deleteMiner(BuildContext context, MinerStore store, Miner miner) {
    final index = store.miners.indexOf(miner);
    store.remove(miner.id);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: const Color(0xFF21262D),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const Icon(Icons.delete_outline, color: Color(0xFFff4d4d), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text('${miner.name} removed',
            style: const TextStyle(color: Color(0xFFe6edf3)))),
        ]),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: KratosTheme.orange,
          onPressed: () => store.reinsert(miner, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_longPressedId != null) setState(() => _longPressedId = null);
      },
      child: Scaffold(
        backgroundColor: KratosTheme.bg,
        appBar: AppBar(
          backgroundColor: KratosTheme.bg,
          title: const _KratosLogo(),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF7931A), Color(0xFFFF6B00), Colors.transparent],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          actions: [
            // Grid / List toggle
            IconButton(
              icon: Icon(
                _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                color: KratosTheme.muted,
                size: 22,
              ),
              tooltip: _isGridView ? 'List view' : 'Grid view',
              onPressed: () {
                setState(() {
                  _isGridView = !_isGridView;
                  _longPressedId = null;
                });
                _saveViewPref(_isGridView);
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: KratosTheme.orange, size: 28),
              onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AddMinerScreen())
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Consumer<MinerStore>(
          builder: (ctx, store, _) {
            if (store.miners.isEmpty) return const _EmptyState();
            return RefreshIndicator(
              color: KratosTheme.neon,
              backgroundColor: KratosTheme.surface,
              onRefresh: store.refreshAll,
              child: _isGridView
                ? _buildGrid(ctx, store)
                : _buildList(ctx, store),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, MinerStore store) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 12),
        const FleetSummaryBar(),
        const SizedBox(height: 16),
        ...store.miners.map((m) {
          final stats = store.stats[m.id];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: ValueKey(m.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFff4d4d).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFff4d4d).withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.delete_outline, color: Color(0xFFff4d4d), size: 24),
                    SizedBox(width: 8),
                    Text('DELETE', style: TextStyle(
                      color: Color(0xFFff4d4d),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    )),
                    SizedBox(width: 4),
                  ],
                ),
              ),
              confirmDismiss: (_) async => true,
              onDismissed: (_) => _deleteMiner(context, store, m),
              child: MinerCard(
                key: ValueKey('card_${m.id}'),
                miner: m,
                stats: stats,
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => MinerDetailScreen(miner: m))),
              ),
            ),
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, MinerStore store) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: const FleetSummaryBar(),
        )),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final m = store.miners[i];
                final stats = store.stats[m.id];
                return MinerGridCard(
                  key: ValueKey('grid_${m.id}'),
                  miner: m,
                  stats: stats,
                  showDeleteBadge: _longPressedId == m.id,
                  onTap: () => Navigator.push(ctx,
                    MaterialPageRoute(builder: (_) => MinerDetailScreen(miner: m))),
                  onLongPress: () => setState(() => _longPressedId = m.id),
                  onDeleteTap: () {
                    setState(() => _longPressedId = null);
                    _deleteMiner(context, store, m);
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

class _KratosLogo extends StatelessWidget {
  const _KratosLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, color: KratosTheme.orange, size: 22),
        const SizedBox(width: 6),
        Text(
          'KRATOS',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: KratosTheme.textPrim,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_outlined, size: 80, color: KratosTheme.border),
          const SizedBox(height: 24),
          Text('No Miners Yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: KratosTheme.textPrim,
            )),
          const SizedBox(height: 8),
          Text('Add your first miner to start monitoring',
            style: TextStyle(fontSize: 15, color: KratosTheme.muted),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddMinerScreen())),
            icon: const Icon(Icons.add),
            label: const Text('Add Miner',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
