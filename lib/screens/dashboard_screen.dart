import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/miner_store.dart';
import '../models/miner.dart';
import '../widgets/miner_card.dart';
import '../widgets/fleet_summary_bar.dart';
import 'add_miner_screen.dart';
import 'miner_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const _KratosLogo(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: KratosTheme.orange, size: 28),
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AddMinerScreen())
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<MinerStore>(
        builder: (ctx, store, _) {
          if (store.miners.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            color: KratosTheme.neon,
            backgroundColor: KratosTheme.surface,
            onRefresh: store.refreshAll,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 8),
                const FleetSummaryBar(),
                const SizedBox(height: 16),
                ...store.miners.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MinerCard(
                    miner: m,
                    stats: store.stats[m.id],
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => MinerDetailScreen(miner: m))
                    ),
                  ),
                )),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
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
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: KratosTheme.textPrim)),
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
            label: const Text('Add Miner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
