import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../widgets/falling_block.dart';
import 'miners_screen.dart';
import 'pools_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'add_miner_screen.dart';

/// Kratos v2 root: 5-tab IndexedStack hub. No "Shop" tab.
/// Tabs: Volt (overview) · Miners · Pools · Chat · Settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  Miner? _celebratedMiner; // currently shown FallingBlockOverlay (if any)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // After every build, check if a real block-found event landed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = Provider.of<MinerStore>(context, listen: false);
      if (store.pendingBlockFoundMiner != null && _celebratedMiner == null) {
        setState(() => _celebratedMiner = store.pendingBlockFoundMiner);
        store.clearBlockFound();
      }
    });
  }

  static const _tabs = <_TabSpec>[
    _TabSpec(label: 'Volt',     icon: Icons.bolt_rounded),
    _TabSpec(label: 'Miners',   icon: Icons.memory_rounded),
    _TabSpec(label: 'Pools',    icon: Icons.waves_rounded),
    _TabSpec(label: 'Chat',     icon: Icons.forum_rounded),
    _TabSpec(label: 'Settings', icon: Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      VoltOverviewTab(),
      MinersScreen(),
      PoolsScreen(),
      ChatScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: KratosColors.bg,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (_celebratedMiner != null)
            FallingBlockOverlay(
              minerName: _celebratedMiner!.name,
              coinTicker: 'BTC',
              onDone: () => setState(() => _celebratedMiner = null),
            ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        tabs: _tabs,
        onTap: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
      ),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              backgroundColor: KratosColors.volt,
              foregroundColor: const Color(0xFF001A0E),
              elevation: 0,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddMinerScreen()),
              ),
              child: const Icon(Icons.add, size: 28),
            )
          : null,
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  const _TabSpec({required this.label, required this.icon});
}

class _BottomBar extends StatelessWidget {
  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onTap;

  const _BottomBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KratosColors.bg,
        border: Border(top: BorderSide(color: KratosColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom * 0.5,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabButton(
                spec: tabs[i],
                active: i == index,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _TabSpec spec;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? KratosColors.voltBright : KratosColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              spec.icon,
              size: 22,
              color: color,
              shadows: active
                  ? [
                      Shadow(
                          color: KratosColors.volt.withOpacity(0.8),
                          blurRadius: 8),
                    ]
                  : null,
            ),
            const SizedBox(height: 3),
            Text(
              spec.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Volt Overview tab — fleet health summary at a glance.
// All numbers come from the existing MinerStore + BtcPriceService.
// No invented values: zero miners ⇒ Klaw empty state.
// ============================================================================

class VoltOverviewTab extends StatelessWidget {
  const VoltOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(
      builder: (ctx, store, _) {
        if (store.miners.isEmpty) {
          return const _OverviewEmpty();
        }
        return _OverviewBody(store: store);
      },
    );
  }
}

class _OverviewEmpty extends StatelessWidget {
  const _OverviewEmpty();

  @override
  Widget build(BuildContext context) {
    // Reuses Klaw empty-state pattern; CTA flips to the Miners tab.
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const _Logo(),
          const Spacer(flex: 2),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'No miners yet — Klaw is bored.\nTap the ⛏ tab to add your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KratosColors.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final MinerStore store;
  const _OverviewBody({required this.store});

  @override
  Widget build(BuildContext context) {
    final hashTh = store.totalHashrate / 1000.0;
    final earnings = store.totalDailyEarningsUsd;
    final cost = store.totalDailyCostUsd;
    final net = earnings - cost;

    return SafeArea(
      child: RefreshIndicator(
        color: KratosColors.volt,
        backgroundColor: KratosColors.surface,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            const _Logo(),
            const SizedBox(height: 18),
            _HeroCard(
              hashTh: hashTh,
              online: store.onlineCount,
              total: store.miners.length,
              dailyNetUsd: net,
              avgTempC: _avgTemp(store),
            ),
            const SizedBox(height: 14),
            _TileGrid(store: store),
          ],
        ),
      ),
    );
  }

  double _avgTemp(MinerStore store) {
    final temps = store.stats.values
        .where((s) => s.outTemp > 0)
        .map((s) => s.outTemp)
        .toList();
    if (temps.isEmpty) return 0;
    return temps.reduce((a, b) => a + b) / temps.length;
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            'KRA',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: KratosColors.text,
              letterSpacing: 1.5,
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: _gradient,
            child: Text(
              'TOS',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Shader _gradient(Rect bounds) =>
      const LinearGradient(colors: [
        KratosColors.voltBright,
        KratosColors.volt,
      ]).createShader(bounds);
}

class _HeroCard extends StatelessWidget {
  final double hashTh;
  final int online;
  final int total;
  final double dailyNetUsd;
  final double avgTempC;

  const _HeroCard({
    required this.hashTh,
    required this.online,
    required this.total,
    required this.dailyNetUsd,
    required this.avgTempC,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KratosColors.volt.withOpacity(0.18),
            KratosColors.volt.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: KratosColors.volt.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL HASHRATE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: KratosColors.muted,
                ),
              ),
              _OnlinePill(online: online, total: total),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(colors: [
                  KratosColors.voltBright,
                  KratosColors.volt,
                ]).createShader(r),
                child: Text(
                  hashTh > 0 ? hashTh.toStringAsFixed(2) : '—',
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text(
                  'TH/s',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KratosColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCell(
                label: 'NET / DAY',
                value: dailyNetUsd != 0
                    ? '\$${dailyNetUsd.toStringAsFixed(2)}'
                    : '—',
                color: dailyNetUsd >= 0
                    ? KratosColors.voltBright
                    : KratosColors.danger,
              ),
              _StatCell(
                label: 'AVG TEMP',
                value: avgTempC > 0
                    ? '${avgTempC.toStringAsFixed(0)}°C'
                    : '—',
                color: avgTempC > 75
                    ? KratosColors.warning
                    : KratosColors.text,
              ),
              _StatCell(
                label: 'ONLINE',
                value: total > 0 ? '$online / $total' : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  final int online;
  final int total;
  const _OnlinePill({required this.online, required this.total});

  @override
  Widget build(BuildContext context) {
    final allUp = online == total && total > 0;
    final color = allUp ? KratosColors.volt : KratosColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$online / $total online',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatCell({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: KratosColors.volt.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KratosColors.volt.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: KratosColors.muted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color ?? KratosColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  final MinerStore store;
  const _TileGrid({required this.store});

  @override
  Widget build(BuildContext context) {
    final fleet = store.bestDiffTracker.fleetRecord;
    final bestDiff = fleet?.bestShare ?? 0;
    final activeMiners = store.onlineCount;

    final tiles = <_Tile>[
      _Tile(
        icon: Icons.memory_rounded,
        title: 'Miners',
        subtitle: store.miners.isEmpty
            ? 'Add one'
            : '$activeMiners active',
        color: KratosColors.volt,
      ),
      _Tile(
        icon: Icons.gps_fixed_rounded,
        title: 'Best Diff',
        subtitle: bestDiff > 0
            ? _formatDiff(bestDiff)
            : 'Awaiting share',
        color: KratosColors.cyan,
      ),
      _Tile(
        icon: Icons.show_chart_rounded,
        title: 'Charts',
        subtitle: 'Live',
        color: KratosColors.info,
      ),
      _Tile(
        icon: Icons.thermostat_rounded,
        title: 'Thermal',
        subtitle: store.miners.isEmpty
            ? 'No data'
            : '${store.miners.length} sensors',
        color: KratosColors.warning,
      ),
      _Tile(
        icon: Icons.shield_rounded,
        title: 'Status',
        subtitle: store.offlineCount > 0
            ? '${store.offlineCount} offline'
            : 'All up',
        color: store.offlineCount > 0
            ? KratosColors.danger
            : KratosColors.volt,
      ),
      _Tile(
        icon: Icons.forum_rounded,
        title: 'Hangout',
        subtitle: 'Discord',
        color: KratosColors.cyan,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 11,
      crossAxisSpacing: 11,
      children: tiles,
    );
  }

  String _formatDiff(double v) {
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}G';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(0)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KratosColors.surface2.withOpacity(0.7),
            KratosColors.surface.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KratosColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: KratosColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
