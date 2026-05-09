import 'package:flutter/material.dart';
import '../models/miner.dart';
import '../models/mining_schedule.dart';
import '../services/schedule_service.dart';
import '../theme/volt_theme.dart';
import 'rule_editor_sheet.dart';

class ScheduleScreen extends StatefulWidget {
  final Miner miner;
  const ScheduleScreen({super.key, required this.miner});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  MinerSchedule? _schedule;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ScheduleService.instance.load(widget.miner.ip);
    if (mounted) setState(() { _schedule = s; _loading = false; });
  }

  Future<void> _save(MinerSchedule s) async {
    await ScheduleService.instance.save(s);
    ScheduleService.instance.resetCache(widget.miner.ip);
    if (mounted) setState(() => _schedule = s);
  }

  Future<void> _addRule() async {
    final s = _schedule;
    if (s == null) return;
    final rule = await showModalBottomSheet<ScheduleRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RuleEditorSheet(ruleNumber: s.rules.length + 1),
    );
    if (rule != null) await _save(s.copyWith(rules: [...s.rules, rule]));
  }

  Future<void> _editRule(int idx) async {
    final s = _schedule;
    if (s == null) return;
    final rule = await showModalBottomSheet<ScheduleRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RuleEditorSheet(existing: s.rules[idx]),
    );
    if (rule != null) {
      final updated = List<ScheduleRule>.from(s.rules)..[idx] = rule;
      await _save(s.copyWith(rules: updated));
    }
  }

  Future<void> _deleteRule(int idx) async {
    final s = _schedule;
    if (s == null) return;
    final updated = List<ScheduleRule>.from(s.rules)..removeAt(idx);
    await _save(s.copyWith(rules: updated));
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final s = _schedule;

    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⏰ Mining Schedule',
              style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
          Text(widget.miner.name,
              style: TextStyle(color: kc.muted, fontSize: 12)),
        ]),
        actions: s == null ? [] : [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Switch(
              value: s.enabled,
              activeColor: kc.accent,
              onChanged: (v) => _save(s.copyWith(enabled: v)),
            ),
          ),
        ],
      ),
      floatingActionButton: s != null
          ? FloatingActionButton(
              backgroundColor: kc.accent,
              foregroundColor: Colors.black,
              onPressed: _addRule,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kc.accent))
          : s == null
              ? const SizedBox()
              : ListView(padding: const EdgeInsets.all(16), children: [

                  // ── Status card ────────────────────────────────────────
                  _StatusCard(schedule: s, kc: kc),
                  const SizedBox(height: 16),

                  // ── Disclaimer ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kc.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kc.line),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 16, color: kc.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Schedule runs every minute while Kratos is open. '
                        'Rules apply automatically when the app is launched.',
                        style: TextStyle(fontSize: 11, color: kc.muted, height: 1.4),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Rules ──────────────────────────────────────────────
                  if (s.rules.isEmpty)
                    _EmptyState(kc: kc, onAdd: _addRule)
                  else ...[
                    Text('RULES', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: kc.muted, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    ...s.rules.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RuleCard(
                        rule: e.value,
                        kc: kc,
                        onTap: () => _editRule(e.key),
                        onDelete: () => _deleteRule(e.key),
                        onToggle: (v) {
                          final updated = List<ScheduleRule>.from(s.rules)
                            ..[e.key] = e.value.copyWith(enabled: v);
                          _save(s.copyWith(rules: updated));
                        },
                      ),
                    )),
                  ],

                  const SizedBox(height: 80),
                ]),
    );
  }
}

// ── Status Card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final MinerSchedule schedule;
  final KratosPalette kc;
  const _StatusCard({required this.schedule, required this.kc});

  @override
  Widget build(BuildContext context) {
    final label = ScheduleService.instance.statusLabel(schedule);
    final isActive = schedule.enabled && schedule.rules.isNotEmpty;
    final color = isActive ? kc.accent : kc.muted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(isActive ? Icons.schedule : Icons.schedule_outlined,
            color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(schedule.enabled ? 'Schedule Active' : 'Schedule Disabled',
              style: TextStyle(fontWeight: FontWeight.w700,
                  color: color, fontSize: 13)),
          Text(label, style: TextStyle(fontSize: 12, color: kc.muted)),
        ])),
      ]),
    );
  }
}

// ── Rule Card ─────────────────────────────────────────────────────────────────

class _RuleCard extends StatelessWidget {
  final ScheduleRule rule;
  final KratosPalette kc;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  const _RuleCard({required this.rule, required this.kc,
      required this.onTap, required this.onDelete, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = rule.action.color(context);
    final dayNames = ['M','T','W','T','F','S','S'];
    return Dismissible(
      key: Key(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: rule.enabled ? c.withOpacity(0.06) : kc.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: rule.enabled ? c.withOpacity(0.3) : kc.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${rule.action.emoji} ', style: const TextStyle(fontSize: 16)),
              Expanded(child: Text(rule.name,
                  style: TextStyle(fontWeight: FontWeight.w700,
                      color: rule.enabled ? kc.text : kc.muted))),
              Switch(
                value: rule.enabled,
                activeColor: c,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onToggle,
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              // Days chips
              ...List.generate(7, (i) {
                final active = rule.days.contains(i);
                return Container(
                  width: 22, height: 22,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: active ? c.withOpacity(0.2) : kc.line.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(child: Text(dayNames[i],
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                          color: active ? c : kc.muted))),
                );
              }),
              const SizedBox(width: 10),
              Text(
                '${_fmt(rule.startTime)} – ${_fmt(rule.endTime)}',
                style: TextStyle(fontSize: 12,
                    color: rule.enabled ? kc.text : kc.muted,
                    fontFamily: 'Courier'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final KratosPalette kc;
  final VoidCallback onAdd;
  const _EmptyState({required this.kc, required this.onAdd});

  @override
  Widget build(BuildContext context) => Column(children: [
    const SizedBox(height: 40),
    Icon(Icons.schedule, size: 56, color: kc.muted.withOpacity(0.4)),
    const SizedBox(height: 16),
    Text('No rules yet', style: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700, color: kc.muted)),
    const SizedBox(height: 8),
    Text('Automatically switch workmode,\ngo to standby or wake up on a schedule.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: kc.muted, height: 1.4)),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('Add First Rule'),
    ),
  ]);
}
