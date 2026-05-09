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
import 'hall_of_fame_screen.dart';
import 'dashboard_settings_screen.dart';
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
      backgroundColor: kc.surface2,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        Icon(Icons.delete_outline,
            color: KratosColors.danger, size: 18),
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
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium),
          ),
          title: Text('Miners',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kc.text)),
          actions: [
            if (context
                .watch<MinerStore>()
                .miners
                .any((m) => m.type.apiType == ApiType.espMinerHttp))
              IconButton(
                tooltip: 'Fleet OC',
                icon: Icon(Icons.bolt,
                    color: kc.accent, size: 22),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const FleetOCScreen()),
                ),
              ),
            IconButton(
              tooltip: 'Hall of Fame',
              icon: Icon(Icons.emoji_events, color: kc.accent, size: 22),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HallOfFameScreen())),
            ),
            IconButton(
              tooltip: 'Customize dashboard',
              icon: Icon(Icons.tune, color: kc.muted, size: 22),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardSettingsScreen())),
            ),
            // Groups view toggle
            IconButton(
              tooltip: 'Fleet Groups',
              icon: Icon(
                  Icons.workspaces_rounded,
                  color: _showGroups ? kc.accent : kc.muted,
                  size: 22),
              onPressed: () => setState(() => _showGroups = !_showGroups),
            ),
            // Grid/List toggle (only when not in groups view)
            if (!_showGroups)
              IconButton(
                icon: Icon(
                    _grid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
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
        if (DashboardPrefs.instance.showFleetTotals) const FleetSummaryBar(),
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
                  color: KratosColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: KratosColors.danger.withOpacity(0.4)),
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
            child: DashboardPrefs.instance.showFleetTotals ? const FleetSummaryBar() : const SizedBox.shrink(),
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
                    style: TextStyle(
                        color: kc.muted, fontSize: 13, height: 1.5)),
              ]),
            )
          else
            ...gs.groups.map((group) {
              final groupMiners = store.miners
                  .where((m) => group.minerIds.contains(m.id))
                  .toList();
              final onlineCount = groupMiners
                  .where((m) =>
                      store.stats[m.id]?.status == MinerStatus.online)
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
                        builder: (_) =>
                            GroupDetailScreen(group: group)),
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
                      border: Border.all(
                          color: accentColor.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      // Emoji badge
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: accentColor.withOpacity(0.3)),
                        ),
                        child: Center(
                            child: Text(group.emoji,
                                style:
                                    const TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                              style: TextStyle(
                                  fontSize: 12,
                                  color: kc.muted),
                            ),
                            Text(' · ',
                                style: TextStyle(
                                    color: kc.line)),
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
                      Icon(Icons.chevron_right_rounded,
                          color: kc.muted),
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
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx2).viewInsets.bottom + 20),
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
                        borderSide: BorderSide(
                            color: Color(selectedColor), width: 2)),
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
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: sel
                              ? Color(selectedColor).withOpacity(0.2)
                              : kc.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel
                                  ? Color(selectedColor)
                                  : kc.line),
                        ),
                        child: Center(
                            child: Text(e,
                                style: const TextStyle(
                                    fontSize: 20))),
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
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: sel
                              ? Border.all(
                                  color: Colors.white, width: 3)
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
                              builder: (_) =>
                                  GroupDetailScreen(group: g)),
                        );
                      }
                    },
                    child: const Text('Create Group',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
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
        quip: 'Klaw needs hashing to do.\nAdd your first miner to start the forge.',
        cta: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kc.accent,
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
          icon: Icon(Icons.add),
          label: Text('Add Miner',
              style:
                  TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
    );
  }
}
