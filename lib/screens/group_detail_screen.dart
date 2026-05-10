import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../models/miner_group.dart';
import '../services/group_service.dart';
import '../services/miner_store.dart';
import '../widgets/miner_card.dart';
import 'miner_detail_screen.dart';
import 'group_pool_editor_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final MinerGroup group;
  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  KratosPalette get kc => KratosColors.of(context);

  // Frequency OC sheet state
  final _freqCtrl = TextEditingController();

  @override
  void dispose() {
    _freqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GroupService, MinerStore>(
      builder: (ctx, gs, store, _) {
        // Always use the latest group from service
        final group = gs.groups.firstWhere(
          (g) => g.id == widget.group.id,
          orElse: () => widget.group,
        );
        final groupMiners = store.miners
            .where((m) => group.minerIds.contains(m.id))
            .toList();
        final onlineCount =
            groupMiners.where((m) => store.stats[m.id]?.status == MinerStatus.online).length;
        final totalGh = groupMiners.fold<double>(
            0, (s, m) => s + (store.stats[m.id]?.hashrateAvg ?? 0));
        final totalW = groupMiners.fold<double>(
            0, (s, m) => s + (store.stats[m.id]?.powerDraw ?? 0));
        final accentColor = group.color;

        return Scaffold(
          backgroundColor: kc.bg,
          appBar: AppBar(
            backgroundColor: kc.bg,
            title: Row(children: [
              Text(group.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.name,
                    style: TextStyle(
                        color: kc.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 17)),
                Text('${groupMiners.length} miners',
                    style: TextStyle(color: kc.muted, fontSize: 12)),
              ]),
            ]),
            actions: [
              IconButton(
                icon: Icon(Icons.edit_outlined, color: kc.muted),
                onPressed: () => _showEditSheet(context, group, gs),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Group stats ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withOpacity(0.12),
                      kc.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Row(children: [
                  _StatPill('HASHRATE',
                      totalGh >= 1000
                          ? '${(totalGh / 1000).toStringAsFixed(2)} TH/s'
                          : '${totalGh.toStringAsFixed(1)} GH/s',
                      accentColor),
                  const SizedBox(width: 8),
                  _StatPill('ONLINE', '$onlineCount / ${groupMiners.length}',
                      const Color(0xFF39d353)),
                  const SizedBox(width: 8),
                  _StatPill('POWER',
                      totalW > 0 ? '${totalW.toStringAsFixed(0)} W' : '--',
                      const Color(0xFFffa657)),
                ]),
              ),
              const SizedBox(height: 16),

              // ── Action buttons ───────────────────────────────────────────
              Text('GROUP ACTIONS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: kc.muted,
                      letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.dns_outlined,
                    label: 'Apply Pool',
                    subtitle: 'Set pool for all',
                    color: const Color(0xFFf7931a),
                    onTap: groupMiners.isEmpty
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroupPoolEditorScreen(
                                  group: group,
                                  miners: groupMiners,
                                ),
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.speed,
                    label: 'Set Frequency',
                    subtitle: 'OC all miners',
                    color: kc.accent,
                    onTap: groupMiners.isEmpty
                        ? null
                        : () => _showFrequencySheet(context, group, groupMiners, gs),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.restart_alt,
                    label: 'Restart All',
                    subtitle: 'Reboot group',
                    color: const Color(0xFFff4d4d),
                    onTap: groupMiners.isEmpty
                        ? null
                        : () => _confirmRestart(context, group, groupMiners, gs),
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Miners in group ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MINERS IN GROUP',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: kc.muted,
                          letterSpacing: 1.5)),
                  TextButton.icon(
                    onPressed: () => _showAddMinersSheet(context, group, store, gs),
                    icon: Icon(Icons.add, size: 16, color: accentColor),
                    label: Text('Add / Remove',
                        style: TextStyle(color: accentColor, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (groupMiners.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kc.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kc.line),
                  ),
                  child: Column(children: [
                    Icon(Icons.group_outlined, size: 40, color: kc.muted),
                    const SizedBox(height: 8),
                    Text('No miners in this group yet',
                        style: TextStyle(color: kc.muted, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Tap "Add / Remove" to assign miners',
                        style: TextStyle(color: kc.muted, fontSize: 12)),
                  ]),
                )
              else
                ...groupMiners.map((m) {
                  final s = store.stats[m.id];
                  final earnings = store.minerDailyEarningsUsd(m.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MinerCard(
                      key: ValueKey('grp_${m.id}'),
                      miner: m,
                      stats: s,
                      earningsPerDay: earnings,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MinerDetailScreen(miner: m)),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),

              // Danger zone
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: const Color(0xFFff4d4d).withOpacity(0.4)),
                  foregroundColor: const Color(0xFFff4d4d),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('Delete Group "${group.name}"'),
                onPressed: () => _confirmDelete(context, group, gs),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  // ── Sheets & dialogs ────────────────────────────────────────────────────────

  void _showEditSheet(BuildContext ctx, MinerGroup group, GroupService gs) {
    final nameCtrl = TextEditingController(text: group.name);
    String selectedEmoji = group.emoji;
    int selectedColor = group.colorValue;

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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Edit Group',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kc.text)),
            const SizedBox(height: 16),
            // Name field
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: kc.text, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: TextStyle(color: kc.muted),
                filled: true,
                fillColor: kc.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            // Emoji picker
            Text('Icon', style: TextStyle(color: kc.muted, fontSize: 12)),
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
                      color: sel ? Color(selectedColor).withOpacity(0.2) : kc.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: sel
                              ? Color(selectedColor)
                              : kc.line),
                    ),
                    child: Center(
                        child: Text(e,
                            style: const TextStyle(fontSize: 20))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Color picker
            Text('Color', style: TextStyle(color: kc.muted, fontSize: 12)),
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
                  await gs.updateGroup(group.id,
                      name: nameCtrl.text.trim().isEmpty
                          ? group.name
                          : nameCtrl.text.trim(),
                      emoji: selectedEmoji,
                      colorValue: selectedColor);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
      }),
    );
  }

  void _showAddMinersSheet(
      BuildContext ctx, MinerGroup group, MinerStore store, GroupService gs) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: kc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setS) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Add / Remove Miners',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kc.text)),
            const SizedBox(height: 4),
            Text('Tap to toggle miner membership',
                style: TextStyle(color: kc.muted, fontSize: 12)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx2).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: store.miners.map((m) {
                  final inGroup = group.minerIds.contains(m.id);
                  final s = store.stats[m.id];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: inGroup
                            ? group.color.withOpacity(0.15)
                            : kc.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: inGroup
                                ? group.color.withOpacity(0.5)
                                : kc.line),
                      ),
                      child: Icon(
                        inGroup ? Icons.check : Icons.add,
                        size: 16,
                        color: inGroup ? group.color : kc.muted,
                      ),
                    ),
                    title: Text(m.name,
                        style: TextStyle(
                            color: kc.text, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${m.type.displayName} · ${s?.hashrateFormatted ?? 'offline'}',
                        style: TextStyle(color: kc.muted, fontSize: 11)),
                    onTap: () async {
                      if (inGroup) {
                        await gs.removeMinerFromGroup(group.id, m.id);
                      } else {
                        await gs.addMinerToGroup(group.id, m.id);
                      }
                      setS(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ]),
        );
      }),
    );
  }

  void _showFrequencySheet(BuildContext ctx, MinerGroup group,
      List<Miner> miners, GroupService gs) {
    _freqCtrl.text = '400';
    showModalBottomSheet(
      context: ctx,
      backgroundColor: kc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setS) {
        bool applying = false;
        List<MinerActionResult> results = [];

        return StatefulBuilder(builder: (ctx3, setS2) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx3).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Set Frequency — ${group.emoji} ${group.name}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: kc.text)),
              const SizedBox(height: 4),
              Text(
                  'Applies to ESP-Miner and CGMiner devices (${miners.length} miners)',
                  style: TextStyle(color: kc.muted, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: _freqCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(
                    color: kc.text, fontFamily: 'Courier', fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Frequency (MHz)',
                  labelStyle: TextStyle(color: kc.muted),
                  suffixText: 'MHz',
                  suffixStyle: TextStyle(color: kc.muted),
                  filled: true,
                  fillColor: kc.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: kc.accent)),
                ),
              ),
              const SizedBox(height: 8),
              Text('⚠️ Test on one miner before applying to the group',
                  style: TextStyle(
                      color: const Color(0xFFffd700), fontSize: 11)),
              if (results.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...results.map((r) => _ResultRow(r)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kc.accent,
                      foregroundColor: Colors.black),
                  onPressed: applying
                      ? null
                      : () async {
                          final mhz = int.tryParse(_freqCtrl.text.trim());
                          if (mhz == null || mhz < 100 || mhz > 900) return;
                          setS2(() { applying = true; results = []; });
                          await gs.applyFrequencyToGroup(
                            group.id,
                            miners,
                            mhz,
                            onProgress: (r) =>
                                setS2(() => results = [...results, r]),
                          );
                          setS2(() => applying = false);
                        },
                  child: applying
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black54)),
                            SizedBox(width: 8),
                            Text('Applying...'),
                          ],
                        )
                      : const Text('Apply to All Miners',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          );
        });
      }),
    );
  }

  void _confirmRestart(BuildContext ctx, MinerGroup group,
      List<Miner> miners, GroupService gs) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: kc.surface,
        title: Text('Restart ${group.emoji} ${group.name}?',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
        content: Text(
            'This will restart all ${miners.length} miners in this group. They will be offline for ~60 seconds.',
            style: TextStyle(color: kc.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: kc.muted))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFff4d4d),
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await gs.restartGroup(group.id, miners);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('Restart sent to ${miners.length} miners'),
                  backgroundColor: kc.surface2,
                ));
              }
            },
            child: const Text('Restart All'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, MinerGroup group, GroupService gs) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: kc.surface,
        title: Text('Delete "${group.name}"?',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
        content: Text(
            'The group will be deleted. Your miners are not affected.',
            style: TextStyle(color: kc.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: kc.muted))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFff4d4d),
                foregroundColor: Colors.white),
            onPressed: () async {
              await gs.deleteGroup(group.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFamily: 'Courier')),
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFF6e7681),
                  letterSpacing: 1.2)),
        ]),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.08) : kc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: enabled ? color.withOpacity(0.35) : kc.line),
        ),
        child: Column(children: [
          Icon(icon, color: enabled ? color : kc.muted, size: 22),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: enabled ? color : kc.muted)),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: kc.muted)),
        ]),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final MinerActionResult r;
  const _ResultRow(this.r);

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(
          r.success ? Icons.check_circle : Icons.error_outline,
          size: 14,
          color: r.success ? const Color(0xFF39d353) : const Color(0xFFff4d4d),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(r.minerName,
              style: TextStyle(fontSize: 12, color: kc.text)),
        ),
        Text(r.success ? 'OK' : 'Failed',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: r.success
                    ? const Color(0xFF39d353)
                    : const Color(0xFFff4d4d))),
      ]),
    );
  }
}
