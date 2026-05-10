import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../widgets/miner_card.dart';
import '../widgets/fleet_summary_bar.dart';
import '../widgets/kratos_logo.dart';
import 'add_miner_screen.dart';
import 'miner_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  KratosPalette get kc => KratosColors.of(context);

  bool _isGridView = false;
  String? _longPressedId; // grid delete badge

  @override
  void initState() {
    super.initState();
    _loadViewPref();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for pending block-found event after each build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = Provider.of<MinerStore>(context, listen: false);
      if (store.pendingBlockFoundMiner != null) {
        _showBlockFoundDialog(store.pendingBlockFoundMiner!);
        store.clearBlockFound();
      }
    });
  }

  Future<void> _loadViewPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isGridView = prefs.getBool('kratos_grid_view') ?? false;
      });
    }
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
          Icon(Icons.delete_outline,
              color: Color(0xFFff4d4d), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text('${miner.name} removed',
                style: const TextStyle(color: Color(0xFFe6edf3))),
          ),
        ]),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: KratosTheme.orange,
          onPressed: () => store.reinsert(miner, index),
        ),
      ),
    );
  }

  void _showBlockFoundDialog(Miner miner) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BlockFoundDialog(miner: miner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return GestureDetector(
      onTap: () {
        if (_longPressedId != null) setState(() => _longPressedId = null);
      },
      child: Scaffold(
        backgroundColor: kc.bg,
        appBar: AppBar(
          backgroundColor: kc.bg,
          title: const _KratosLogo(),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF7931A),
                    Color(0xFFFF6B00),
                    Colors.transparent
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                color: kc.muted,
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
              icon: Icon(Icons.add_circle,
                  color: KratosTheme.orange, size: 28),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddMinerScreen())),
            ),
            SizedBox(width: 4),
          ],
        ),
        body: Consumer<MinerStore>(
          builder: (ctx, store, _) {
            if (store.miners.isEmpty) return const _EmptyState();
            return RefreshIndicator(
              color: kc.accent,
              backgroundColor: kc.surface,
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
      key: const ValueKey('list'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SizedBox(height: 12),
        const FleetSummaryBar(),
        SizedBox(height: 10),
        // Thermal strip
        _ThermalStrip(store: store),
        SizedBox(height: 12),
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
                  color: const Color(0xFFff4d4d).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFff4d4d).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.delete_outline,
                        color: Color(0xFFff4d4d), size: 24),
                    SizedBox(width: 8),
                    Text('DELETE',
                        style: TextStyle(
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
        SizedBox(height: 16),
        const _DiscordButton(),
        SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, MinerStore store) {
    return CustomScrollView(
      key: const ValueKey('grid'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              const FleetSummaryBar(),
              SizedBox(height: 8),
              _ThermalStrip(store: store),
            ]),
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
                    _deleteMiner(context, store, m);
                  },
                );
              },
              childCount: store.miners.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: _DiscordButton(),
          ),
        ),
      ],
    );
  }
}

// ── Thermal Strip ─────────────────────────────────────────────────────────────

class _ThermalStrip extends StatelessWidget {
  final MinerStore store;
  const _ThermalStrip({required this.store});

  Color _tempDotColor(MinerStats? s) {
    if (s == null || s.status == MinerStatus.offline) {
      return const Color(0xFF6e7681);
    }
    final t = s.outTemp;
    if (t > 85) return const Color(0xFFff4d4d);
    if (t > 75) return const Color(0xFFffd700);
    if (t > 60) return const Color(0xFFf7931a);
    if (t > 0) return const Color(0xFF39d353);
    return const Color(0xFF58a6ff);
  }

  String _summary() {
    final hot = store.miners
        .where((m) => (store.stats[m.id]?.outTemp ?? 0) > 85)
        .length;
    final offline = store.miners
        .where((m) => store.stats[m.id]?.status == MinerStatus.offline)
        .length;
    if (hot == 0 && offline == 0) return 'all healthy';
    final parts = <String>[];
    if (hot > 0) parts.add('$hot hot');
    if (offline > 0) parts.add('$offline off');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    if (store.miners.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat, size: 12, color: Color(0xFF6e7681)),
          SizedBox(width: 6),
          ...store.miners.map((m) {
            final color = _tempDotColor(store.stats[m.id]);
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Tooltip(
                message:
                    '${m.name}: ${store.stats[m.id]?.outTemp.toInt() ?? '--'}°C',
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.4), blurRadius: 4)
                    ],
                  ),
                ),
              ),
            );
          }),
          SizedBox(width: 4),
          Text(
            _summary(),
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6e7681),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Block Found Dialog ────────────────────────────────────────────────────────

class _BlockFoundDialog extends StatelessWidget {
  final Miner miner;
  const _BlockFoundDialog({required this.miner});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1f2e), Color(0xFF252b3b)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: const Color(0xFFf7931a).withOpacity(0.5), width: 2),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFf7931a).withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 4),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₿', style: TextStyle(fontSize: 64)),
            SizedBox(height: 12),
            Text(
              'BLOCK FOUND!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFFf7931a),
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              miner.name,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFe6edf3),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Just mined a Bitcoin block!\n3.125 BTC block reward.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF8b949e),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFf7931a),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('Celebrate!',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App bar logo ──────────────────────────────────────────────────────────────

class _KratosLogo extends StatelessWidget {
  const _KratosLogo();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KratosShield(size: 28),
        SizedBox(width: 8),
        Text(
          'KRATOS',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: kc.text,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ── Discord Button ────────────────────────────────────────────────────────────

class _DiscordButton extends StatelessWidget {
  const _DiscordButton();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5865F2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => launchUrl(
          Uri.parse('https://discord.gg/yWtYegkDJw'),
          mode: LaunchMode.externalApplication,
        ),
        icon: Icon(Icons.chat_bubble_outline, size: 18),
        label: Text('Join Discord — Report Bugs & Suggest Features',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_outlined, size: 80, color: kc.line),
          SizedBox(height: 24),
          Text('No Miners Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: kc.text,
              )),
          SizedBox(height: 8),
          Text('Add your first miner to start monitoring',
              style:
                  TextStyle(fontSize: 15, color: kc.muted),
              textAlign: TextAlign.center),
          SizedBox(height: 32),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const AddMinerScreen())),
            icon: Icon(Icons.add),
            label: Text('Add Miner',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
