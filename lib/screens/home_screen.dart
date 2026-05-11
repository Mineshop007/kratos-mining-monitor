import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../services/history_service.dart';
import '../widgets/falling_block.dart';
import 'miners_screen.dart';
import 'circuit_monitor_screen.dart';
import 'pools_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'add_miner_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/relay_service.dart';
import '../widgets/update_banner.dart';
import 'hall_of_fame_screen.dart';
import 'giveaway_screen.dart';

/// Kratos v2 root: 5-tab IndexedStack hub. No "Shop" tab.
/// Tabs: Volt (overview) · Miners · Pools · Chat · Settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  KratosPalette get kc => KratosColors.of(context);

  int _index = 0;
  Miner? _celebratedMiner; // currently shown FallingBlockOverlay (if any)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reconnect relay if it was dropped while app was in background
      final relay = RelayService.instance;
      if (relay.state == RelayState.disconnected && relay.accessKey != null) {
        relay.reconnectSaved();
      }
    }
  }

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
    final kc = KratosColors.of(context);
    final pages = [
      VoltOverviewTab(onSwitchTab: (i) => setState(() => _index = i)),
      MinersScreen(),
      PoolsScreen(),
      ChatScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: kc.bg,
      body: UpdateBanner(
        child: Stack(
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
              backgroundColor: kc.accent,
              foregroundColor: const Color(0xFF001A0E),
              elevation: 0,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddMinerScreen()),
              ),
              child: Icon(Icons.add, size: 28),
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
    final kc = KratosColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: kc.bg,
        border: Border(top: BorderSide(color: kc.line)),
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
    final kc = KratosColors.of(context);
    final color = active ? kc.accentBright : kc.muted;
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
                          color: kc.accent.withOpacity(0.8),
                          blurRadius: 8),
                    ]
                  : null,
            ),
            SizedBox(height: 3),
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
  final Function(int) onSwitchTab;
  const VoltOverviewTab({super.key, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Consumer<MinerStore>(
      builder: (ctx, store, _) {
        if (store.miners.isEmpty) {
          return _OverviewEmpty(onSwitchTab: onSwitchTab);
        }
        return _OverviewBody(store: store, onSwitchTab: onSwitchTab);
      },
    );
  }
}

class _OverviewEmpty extends StatelessWidget {
  final Function(int) onSwitchTab;
  const _OverviewEmpty({required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    // Reuses Klaw empty-state pattern; CTA flips to the Miners tab.
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const _Logo(),
          const Spacer(flex: 2),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'No miners yet — Klaw is bored.\nTap the ⛏ tab to add your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kc.muted,
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
  final Function(int) onSwitchTab;
  const _OverviewBody({required this.store, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final hashTh = store.totalHashrate / 1000.0;
    final earnings = store.totalDailyEarningsUsd;
    final cost = store.totalDailyCostUsd;
    final net = earnings - cost;

    return SafeArea(
      child: RefreshIndicator(
        color: kc.accent,
        backgroundColor: kc.surface,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            const _Logo(),
            SizedBox(height: 18),
            _HeroCard(
              hashTh: hashTh,
              online: store.onlineCount,
              total: store.miners.length,
              dailyNetUsd: net,
              avgTempC: _avgTemp(store),
              minerIds: store.miners.map((m) => m.id).toList(),
            ),
            SizedBox(height: 14),
            _TileGrid(store: store, onSwitchTab: onSwitchTab),
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

class _Logo extends StatefulWidget {
  const _Logo();
  @override State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo> with SingleTickerProviderStateMixin {
  late AnimationController _btcCtrl;

  @override
  void initState() {
    super.initState();
    _btcCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() { _btcCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        // Klaw mascot image
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            boxShadow: [BoxShadow(
                color: kc.accent.withOpacity(0.45),
                blurRadius: 12, spreadRadius: 1)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/images/klaw-mascot.png',
                fit: BoxFit.cover),
          ),
        ),
        SizedBox(width: 10),
        // KRATOS text
        Row(children: [
          Text('KRA', style: TextStyle(fontSize: 26,
              fontWeight: FontWeight.w900, color: kc.text,
              letterSpacing: 1.5)),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => LinearGradient(
                colors: [kc.accentBright, kc.accent])
                .createShader(b),
            child: Text('TOS', style: TextStyle(fontSize: 26,
                fontWeight: FontWeight.w900, letterSpacing: 1.5,
                color: Colors.white)),
          ),
        ]),
        const Spacer(),
        // Spinning 3D Bitcoin coin
        AnimatedBuilder(
          animation: _btcCtrl,
          builder: (_, __) {
            final angle = _btcCtrl.value * 2 * 3.14159;
            final scaleX = (0.4 * (1 + (angle % 3.14159 < 1.5708
                ? angle % 3.14159 / 1.5708
                : 1 - (angle % 3.14159 - 1.5708) / 1.5708))).clamp(0.08, 1.0);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scale(scaleX, 1.0),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFFFD700),
                    const Color(0xFFF7931A),
                    const Color(0xFFE67300),
                  ]),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFFF7931A).withOpacity(0.5),
                      blurRadius: 10)],
                ),
                alignment: Alignment.center,
                child: Text('₿', style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 4)])),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final double hashTh;
  final int online;
  final int total;
  final double dailyNetUsd;
  final double avgTempC;
  final List<String> minerIds;

  const _HeroCard({
    required this.hashTh,
    required this.online,
    required this.total,
    required this.dailyNetUsd,
    required this.avgTempC,
    required this.minerIds,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kc.accent.withOpacity(0.18),
            kc.accent.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kc.accent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL HASHRATE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: kc.muted,
                ),
              ),
              _OnlinePill(online: online, total: total),
            ],
          ),
          SizedBox(height: 4),
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
                  hashTh > 0 ? hashTh.toStringAsFixed(2) : '—',
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text(
                  'TH/s',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kc.muted,
                  ),
                ),
              ),
            ],
          ),
          if (minerIds.isNotEmpty) ...[
            SizedBox(height: 10),
            _FleetSparkline(minerIds: minerIds),
          ],
          SizedBox(height: 12),
          Row(
            children: [
              _StatCell(
                label: 'NET / DAY',
                value: dailyNetUsd != 0
                    ? '\$${dailyNetUsd.toStringAsFixed(2)}'
                    : '—',
                color: dailyNetUsd >= 0
                    ? kc.accentBright
                    : KratosColors.danger,
              ),
              _StatCell(
                label: 'AVG TEMP',
                value: avgTempC > 0
                    ? '${avgTempC.toStringAsFixed(0)}°C'
                    : '—',
                color: avgTempC > 75
                    ? KratosColors.warning
                    : kc.text,
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
    final kc = KratosColors.of(context);
    final allUp = online == total && total > 0;
    final color = allUp ? kc.accent : KratosColors.warning;
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
          SizedBox(width: 6),
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
    final kc = KratosColors.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: kc.accent.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kc.accent.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: kc.muted,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color ?? kc.text,
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
  final Function(int) onSwitchTab;
  const _TileGrid({required this.store, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final fleet = store.bestDiffTracker.fleetRecord;
    final bestDiff = fleet?.bestShare ?? 0;
    final activeMiners = store.onlineCount;

    final tiles = <_Tile>[
      _Tile(
        icon: Icons.memory_rounded,
        title: 'Miners',
        subtitle: store.miners.isEmpty ? 'Add one' : '$activeMiners active',
        color: kc.accent,
        onTap: () => onSwitchTab(1),
      ),
      _Tile(
        icon: Icons.emoji_events_rounded,
        title: 'Best Diff',
        subtitle: bestDiff > 0 ? _formatDiff(bestDiff) : 'Awaiting share',
        color: kc.secondary,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const HallOfFameScreen())),
      ),
      _Tile(
        icon: Icons.show_chart_rounded,
        title: 'Charts',
        subtitle: 'Live history',
        color: KratosColors.info,
        onTap: () => onSwitchTab(1), // miners tab has per-miner charts
      ),
      _Tile(
        icon: Icons.thermostat_rounded,
        title: 'Thermal',
        subtitle: store.miners.isEmpty ? 'No data' : '${store.miners.length} sensors',
        color: KratosColors.warning,
        onTap: () => onSwitchTab(1),
      ),
      _Tile(
        icon: Icons.bolt_rounded,
        title: 'Circuit',
        subtitle: 'Breaker monitor',
        color: KratosColors.warning,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CircuitMonitorScreen())),
      ),
      _Tile(
        icon: Icons.shield_rounded,
        title: 'Status',
        subtitle: store.offlineCount > 0 ? '${store.offlineCount} offline' : 'All up',
        color: store.offlineCount > 0 ? KratosColors.danger : kc.accent,
        onTap: () => onSwitchTab(1),
      ),
      _Tile(
        icon: Icons.card_giftcard_rounded,
        title: 'Giveaway',
        subtitle: 'Win Nano 3S!',
        color: KratosColors.coinBtc, // gold
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GiveawayScreen())),
      ),
      _Tile(
        icon: Icons.forum_rounded,
        title: 'Chat',
        subtitle: 'Discord live',
        color: const Color(0xFF5865F2),
        onTap: () => onSwitchTab(3),
      ),
      _Tile(
        icon: Icons.language_rounded,
        title: 'Community',
        subtitle: 'Discord',
        color: kc.secondary,
        onTap: () => launchUrl(Uri.parse('https://discord.gg/yWtYegkDJw'),
            mode: LaunchMode.externalApplication),
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
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kc.surface2.withOpacity(0.7),
            kc.surface.withOpacity(0.85),
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kc.text,
                ),
              ),
              SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: kc.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: tile,
      ),
    );
  }
}

class _FleetSparkline extends StatefulWidget {
  final List<String> minerIds;
  const _FleetSparkline({required this.minerIds});

  @override
  State<_FleetSparkline> createState() => _FleetSparklineState();
}

class _FleetSparklineState extends State<_FleetSparkline> {
  List<HistoryPoint> _pts = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant _FleetSparkline old) {
    super.didUpdateWidget(old);
    if (old.minerIds.length != widget.minerIds.length) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(hours: 6));
    final pts = await HistoryService.instance.getFleetHistory(
      widget.minerIds,
      since: since,
      bucket: const Duration(minutes: 5),
    );
    if (!mounted) return;
    setState(() => _pts = pts);
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    if (_pts.length < 2) {
      return SizedBox(
        height: 36,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('FLEET 6H · collecting…',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: kc.muted)),
        ),
      );
    }
    final spots = _pts
        .map((p) => FlSpot(
            p.ts.millisecondsSinceEpoch.toDouble(), p.hashrate / 1000.0))
        .toList();
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final ys = spots.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1e-6 ? maxY * 0.05 + 0.01 : (maxY - minY) * 0.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FLEET · LAST 6H',
            style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: kc.muted)),
        SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: LineChart(
            LineChartData(
              backgroundColor: Colors.transparent,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minX: minX,
              maxX: maxX,
              minY: (minY - pad).clamp(0, double.infinity).toDouble(),
              maxY: maxY + pad,
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: kc.accentBright,
                  barWidth: 1.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: kc.accent.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
