import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../widgets/miner_card.dart';
import '../widgets/fleet_summary_bar.dart';
import '../widgets/klaw.dart';
import 'add_miner_screen.dart';
import 'miner_detail_screen.dart';
import 'hall_of_fame_screen.dart';
import '../services/dashboard_prefs.dart';
import '../services/group_service.dart';
import '../models/miner_group.dart';
import 'group_detail_screen.dart';

/// Fleet view tab — list / grid of all miners.
/// Logic preserved from v1.0 DashboardScreen, theme + Klaw upgraded.
class MinersScreen extends StatefulWidget {
  const MinersScreen({super.key});

  @override
  State<MinersScreen> createState() => _MinersScreenState();
}

class _MinersScreenState extends State<MinersScreen> {
  KratosPalette get kc => KratosColors.of(context);

  bool _grid = false;
  bool _showGroups = false;
  String? _longPressedId;
  _SortBy _sortBy = _SortBy.none;
  bool _sortAsc = false; // desc by default (highest hashrate first)

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  Future<void> _loadView() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _grid = prefs.getBool('kratos_grid_view') ?? false);
  }

  Future<void> _saveView(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kratos_grid_view', v);
  }

  List<Miner> _sorted(MinerStore store) {
    if (_sortBy == _SortBy.none) return store.miners;
    final list = [...store.miners];
    list.sort((a, b) {
      final sa = store.stats[a.id];
      final sb = store.stats[b.id];
      double va = 0, vb = 0;
      switch (_sortBy) {
        case _SortBy.hashrate:
          va = sa?.hashrateAvg ?? 0;
          vb = sb?.hashrateAvg ?? 0;
        case _SortBy.efficiency:
          va = sa?.efficiency ?? 0;
          vb = sb?.efficiency ?? 0;
          // lower J/TH = better; invert so ascending = most efficient
          if (va > 0 && vb > 0) {
            final tmp = va;
            va = vb;
            vb = tmp;
          }
        case _SortBy.model:
          final cmp = (a.type.displayName).compareTo(b.type.displayName);
          return _sortAsc ? cmp : -cmp;
        case _SortBy.status:
          va = (sa?.status == MinerStatus.online)
              ? 2
              : (sa?.status == MinerStatus.warning)
                  ? 1
                  : 0;
          vb = (sb?.status == MinerStatus.online)
              ? 2
              : (sb?.status == MinerStatus.warning)
                  ? 1
                  : 0;
        case _SortBy.none:
          return 0;
      }
      return _sortAsc ? va.compareTo(vb) : vb.compareTo(va);
    });
    return list;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _sortBy,
        asc: _sortAsc,
        onSelect: (by, asc) {
          setState(() {
            _sortBy = by;
            _sortAsc = asc;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _delete(MinerStore store, Miner miner) {
    final i = store.miners.indexOf(miner);
    store.remove(miner.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kc.surface2,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        Icon(Icons.delete_outline, color: KratosColors.danger, size: 18),
        SizedBox(width: 10),
        Expanded(
            child: Text('${miner.name} removed',
                style: TextStyle(color: kc.text))),
      ]),
      action: SnackBarAction(
        label: 'UNDO',
        textColor: kc.accent,
        onPressed: () => store.reinsert(miner, i),
      ),
    ));
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
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/images/klaw-mascot.png',
                fit: BoxFit.contain, filterQuality: FilterQuality.medium),
          ),
          title: Text('Miners',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kc.text)),
          actions: [
            IconButton(
              tooltip: 'Hall of Fame',
              icon: Icon(Icons.emoji_events, color: kc.accent, size: 22),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HallOfFameScreen())),
            ),
            IconButton(
              tooltip: 'Sort miners',
              icon: Icon(
                Icons.sort_rounded,
                color: _sortBy != _SortBy.none ? kc.accent : kc.muted,
                size: 22,
              ),
              onPressed: _showSortSheet,
            ),
            // Groups view toggle
            IconButton(
              tooltip: 'Fleet Groups',
              icon: Icon(Icons.workspaces_rounded,
                  color: _showGroups ? kc.accent : kc.muted, size: 22),
              onPressed: () => setState(() => _showGroups = !_showGroups),
            ),
            // Grid/List toggle (only when not in groups view)
            if (!_showGroups)
              IconButton(
                icon: Icon(
                    _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    color: kc.muted,
                    size: 22),
                onPressed: () {
                  setState(() {
                    _grid = !_grid;
                    _longPressedId = null;
                  });
                  _saveView(_grid);
                },
              ),
            SizedBox(width: 4),
          ],
        ),
        body: ListenableBuilder(
          listenable: DashboardPrefs.instance,
          builder: (_, __) => Consumer<MinerStore>(
            builder: (ctx, store, _) {
              if (_showGroups) return _buildGroupsView(store);
              if (store.miners.isEmpty) return const _Empty();
              return RefreshIndicator(
                color: kc.accent,
                backgroundColor: kc.surface,
                onRefresh: store.refreshAll,
                child: _grid ? _buildGrid(store) : _buildList(store),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(MinerStore store) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SizedBox(height: 12),
        const _ShareBrandBanner(),
        SizedBox(height: 12),
        if (DashboardPrefs.instance.showFleetTotals) const FleetSummaryBar(),
        SizedBox(height: 12),
        ..._sorted(store).map((m) {
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
                  border:
                      Border.all(color: KratosColors.danger.withOpacity(0.4)),
                ),
                child: Icon(Icons.delete_outline,
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
        SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGrid(MinerStore store) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                const _ShareBrandBanner(),
                if (DashboardPrefs.instance.showFleetTotals) ...[
                  const SizedBox(height: 12),
                  const FleetSummaryBar(),
                ],
              ],
            ),
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
                final miners = _sorted(store);
                final m = miners[i];
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
                  onLongPress: () => setState(() => _longPressedId = m.id),
                  onDeleteTap: () {
                    setState(() => _longPressedId = null);
                    _delete(store, m);
                  },
                );
              },
              childCount: _sorted(store).length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupsView(MinerStore store) {
    return Consumer<GroupService>(builder: (ctx, gs, _) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── New group button ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kc.accent.withOpacity(0.4)),
                foregroundColor: kc.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create New Group',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _showCreateGroupSheet(context, gs),
            ),
          ),
          const SizedBox(height: 16),

          if (gs.groups.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kc.line),
              ),
              child: Column(children: [
                Icon(Icons.workspaces_outlined, size: 48, color: kc.muted),
                const SizedBox(height: 12),
                Text('No groups yet',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kc.text)),
                const SizedBox(height: 6),
                Text(
                    'Create a group to manage miners together.\nApply pool settings or OC to all at once.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: kc.muted, fontSize: 13, height: 1.5)),
              ]),
            )
          else
            ...gs.groups.map((group) {
              final groupMiners = store.miners
                  .where((m) => group.minerIds.contains(m.id))
                  .toList();
              final onlineCount = groupMiners
                  .where((m) => store.stats[m.id]?.status == MinerStatus.online)
                  .length;
              final totalGh = groupMiners.fold<double>(
                  0, (s, m) => s + (store.stats[m.id]?.hashrateAvg ?? 0));
              final accentColor = group.color;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => GroupDetailScreen(group: group)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.1),
                          kc.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      // Emoji badge
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: accentColor.withOpacity(0.3)),
                        ),
                        child: Center(
                            child: Text(group.emoji,
                                style: const TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(group.name,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: kc.text)),
                              const SizedBox(height: 3),
                              Row(children: [
                                Text(
                                  '${groupMiners.length} miners',
                                  style:
                                      TextStyle(fontSize: 12, color: kc.muted),
                                ),
                                Text(' · ', style: TextStyle(color: kc.line)),
                                Text(
                                  '$onlineCount online',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: onlineCount > 0
                                          ? const Color(0xFF39d353)
                                          : kc.muted),
                                ),
                              ]),
                              if (totalGh > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  totalGh >= 1000
                                      ? '${(totalGh / 1000).toStringAsFixed(2)} TH/s'
                                      : '${totalGh.toStringAsFixed(1)} GH/s',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: accentColor,
                                      fontFamily: 'Courier'),
                                ),
                              ],
                            ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: kc.muted),
                    ]),
                  ),
                ),
              );
            }),
        ],
      );
    });
  }

  void _showCreateGroupSheet(BuildContext ctx, GroupService gs) {
    final nameCtrl = TextEditingController();
    String selectedEmoji = '⚡';
    int selectedColor = 0xFFF7931A;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: kc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx2).viewInsets.bottom + 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New Group',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kc.text)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(color: kc.text, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'e.g. Basement, NerdQAxe, Attic',
                    hintStyle: TextStyle(color: kc.muted),
                    filled: true,
                    fillColor: kc.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Color(selectedColor), width: 2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Pick an icon',
                    style: TextStyle(
                        fontSize: 12,
                        color: kc.muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kGroupEmojis.map((e) {
                    final sel = e == selectedEmoji;
                    return GestureDetector(
                      onTap: () => setS(() => selectedEmoji = e),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: sel
                              ? Color(selectedColor).withOpacity(0.2)
                              : kc.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? Color(selectedColor) : kc.line),
                        ),
                        child: Center(
                            child:
                                Text(e, style: const TextStyle(fontSize: 20))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Pick a color',
                    style: TextStyle(
                        fontSize: 12,
                        color: kc.muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kGroupColors.map((c) {
                    final sel = c == selectedColor;
                    return GestureDetector(
                      onTap: () => setS(() => selectedColor = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: sel
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Color(selectedColor),
                        foregroundColor: Colors.black),
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      final g = await gs.createGroup(
                        name,
                        emoji: selectedEmoji,
                        colorValue: selectedColor,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => GroupDetailScreen(group: g)),
                        );
                      }
                    },
                    child: const Text('Create Group',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ]),
        );
      }),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: KlawEmptyState(
        headline: 'No miners yet',
        quip:
            'Klaw needs hashing to do.\nAdd your first miner to start the forge.',
        cta: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kc.accent,
            foregroundColor: const Color(0xFF001A0E),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMinerScreen()),
          ),
          icon: Icon(Icons.add),
          label: Text('Add Miner',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
    );
  }
}

class _ShareBrandBanner extends StatefulWidget {
  const _ShareBrandBanner();

  @override
  State<_ShareBrandBanner> createState() => _ShareBrandBannerState();
}

class _ShareBrandBannerState extends State<_ShareBrandBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openSite() async {
    await launchUrl(
      Uri.parse('https://kratos.mineshop.eu'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return InkWell(
      onTap: _openSite,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 126),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kc.accent.withOpacity(0.28)),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF071F16),
              kc.surface,
              const Color(0xFF25170B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: kc.accent.withOpacity(0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -10,
              bottom: -18,
              child: Opacity(
                opacity: 0.11,
                child: Icon(
                  Icons.memory_rounded,
                  size: 126,
                  color: kc.accentBright,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            'KRATOS',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kc.text,
                              fontSize: 25,
                              height: 0.95,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: kc.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(7),
                            border:
                                Border.all(color: kc.accent.withOpacity(0.32)),
                          ),
                          child: Text(
                            'OPEN SOURCE',
                            style: TextStyle(
                              color: kc.accentBright,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 7),
                      Text(
                        'Mining monitor for home SHA-256 fleets',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kc.text.withOpacity(0.86),
                          fontSize: 13,
                          height: 1.22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.public_rounded, color: kc.accent, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'kratos.mineshop.eu',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kc.accentBright,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  height: 102,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Klaw(size: 82, glow: false),
                      ),
                      Positioned(
                        right: 42,
                        top: 19,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) {
                            final glow = 0.45 + (_pulse.value * 0.35);
                            final scale = 0.92 + (_pulse.value * 0.12);
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 23,
                                height: 23,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kc.accent.withOpacity(glow),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Transform.rotate(
                                  angle: math.pi / 4,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          kc.accentBright,
                                          kc.accent,
                                          const Color(0xFFF7931A),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.42),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort ─────────────────────────────────────────────────────────────────────

enum _SortBy { none, hashrate, efficiency, model, status }

class _SortSheet extends StatefulWidget {
  final _SortBy current;
  final bool asc;
  final void Function(_SortBy, bool) onSelect;
  const _SortSheet(
      {required this.current, required this.asc, required this.onSelect});
  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late _SortBy _by;
  late bool _asc;

  @override
  void initState() {
    super.initState();
    _by = widget.current;
    _asc = widget.asc;
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);

    final options = [
      (_SortBy.none, Icons.format_list_numbered, 'Default order', 'As added'),
      (_SortBy.hashrate, Icons.bolt, 'Hashrate', 'Highest first'),
      (
        _SortBy.efficiency,
        Icons.speed,
        'Efficiency',
        'Most efficient first (J/TH)'
      ),
      (_SortBy.model, Icons.memory, 'Model / Type', 'Alphabetical'),
      (
        _SortBy.status,
        Icons.circle_outlined,
        'Status',
        'Online → Warning → Offline'
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: kc.line, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: Text('Sort Miners',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kc.text))),
          if (_by != _SortBy.none &&
              _by != _SortBy.model &&
              _by != _SortBy.status)
            GestureDetector(
              onTap: () => setState(() => _asc = !_asc),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kc.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kc.accent.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 13, color: kc.accent),
                  const SizedBox(width: 4),
                  Text(_asc ? 'Ascending' : 'Descending',
                      style: TextStyle(
                          fontSize: 11,
                          color: kc.accent,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        ...options.map((opt) {
          final sel = _by == opt.$1;
          return GestureDetector(
            onTap: () {
              setState(() => _by = opt.$1);
              widget.onSelect(opt.$1, _asc);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? kc.accent.withOpacity(0.08) : kc.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? kc.accent.withOpacity(0.4) : kc.line),
              ),
              child: Row(children: [
                Icon(opt.$2, color: sel ? kc.accent : kc.muted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(opt.$3,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: sel ? kc.text : kc.muted)),
                      Text(opt.$4,
                          style: TextStyle(fontSize: 11, color: kc.muted)),
                    ])),
                if (sel) Icon(Icons.check_circle, color: kc.accent, size: 18),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}
