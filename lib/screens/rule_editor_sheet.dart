import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/mining_schedule.dart';
import '../theme/volt_theme.dart';

class RuleEditorSheet extends StatefulWidget {
  final ScheduleRule? existing;
  final int ruleNumber;
  const RuleEditorSheet({super.key, this.existing, this.ruleNumber = 1});
  @override
  State<RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<RuleEditorSheet> {
  late TextEditingController _nameCtrl;
  late List<int> _days;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late ScheduleAction _action;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(
        text: e?.name ?? 'Rule ${widget.ruleNumber}');
    _days   = e != null ? List.from(e.days) : [0, 1, 2, 3, 4]; // weekdays
    _start  = e?.startTime ?? const TimeOfDay(hour: 22, minute: 0);
    _end    = e?.endTime   ?? const TimeOfDay(hour: 6,  minute: 0);
    _action = e?.action    ?? ScheduleAction.superMode;
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  void _save() {
    final id = widget.existing?.id ?? const Uuid().v4();
    final rule = ScheduleRule(
      id: id,
      name: _nameCtrl.text.trim().isEmpty
          ? 'Rule ${widget.ruleNumber}' : _nameCtrl.text.trim(),
      days: _days,
      startTime: _start,
      endTime: _end,
      action: _action,
    );
    Navigator.pop(context, rule);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4CAF50),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { if (isStart) _start = picked; else _end = picked; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [

            // ── Handle ────────────────────────────────────────────────
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: kc.line,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            Text(widget.existing == null ? 'Add Rule' : 'Edit Rule',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: kc.text)),
            const SizedBox(height: 20),

            // ── Name ──────────────────────────────────────────────────
            _Label('RULE NAME', kc),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: kc.text),
              decoration: InputDecoration(
                hintText: 'e.g. Night Super Mode',
                hintStyle: TextStyle(color: kc.muted),
                filled: true, fillColor: kc.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.line)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.accent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),

            // ── Days ──────────────────────────────────────────────────
            _Label('ACTIVE DAYS', kc),
            const SizedBox(height: 8),
            Row(children: List.generate(7, (i) {
              final active = _days.contains(i);
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (active) _days.remove(i); else _days.add(i);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 38,
                    decoration: BoxDecoration(
                      color: active ? kc.accent.withOpacity(0.2) : kc.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: active ? kc.accent : kc.line, width: 1.2),
                    ),
                    child: Center(child: Text(dayNames[i].substring(0, 1),
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: active ? kc.accent : kc.muted))),
                  ),
                ),
              );
            })),
            const SizedBox(height: 20),

            // ── Time range ────────────────────────────────────────────
            _Label('TIME WINDOW', kc),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _TimeTile(
                label: 'START', time: _start, kc: kc,
                onTap: () => _pickTime(true))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 18, color: kc.muted),
              ),
              Expanded(child: _TimeTile(
                label: 'END', time: _end, kc: kc,
                onTap: () => _pickTime(false))),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _start.hour * 60 + _start.minute >= _end.hour * 60 + _end.minute
                    ? 'Window wraps midnight (e.g. 22:00 → 06:00 next day)'
                    : '',
                style: TextStyle(fontSize: 10, color: kc.muted),
              ),
            ),
            const SizedBox(height: 20),

            // ── Action ────────────────────────────────────────────────
            _Label('ACTION', kc),
            const SizedBox(height: 8),
            ...ScheduleAction.values
                .where((a) => a != ScheduleAction.none)
                .map((a) {
              final c = a.color(context);
              final sel = _action == a;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _action = a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? c.withOpacity(0.12) : kc.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? c.withOpacity(0.5) : kc.line,
                          width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Text(a.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(a.label,
                          style: TextStyle(fontWeight: FontWeight.w600,
                              color: sel ? c : kc.muted))),
                      if (sel)
                        Icon(Icons.check_circle, color: c, size: 18),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),

            // ── Save ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kc.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _days.isEmpty ? null : _save,
                child: Text(
                  widget.existing == null ? 'Add Rule' : 'Save Rule',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final KratosPalette kc;
  final VoidCallback onTap;
  const _TimeTile(
      {required this.label, required this.time,
       required this.kc, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          color: kc.bg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kc.line)),
      child: Column(children: [
        Text(label,
            style: TextStyle(fontSize: 9, color: kc.muted,
                fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          '${time.hour.toString().padLeft(2,'0')}:'
          '${time.minute.toString().padLeft(2,'0')}',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
              color: kc.text, fontFamily: 'Courier'),
        ),
      ]),
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  final KratosPalette kc;
  const _Label(this.text, this.kc);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
          color: kc.muted, letterSpacing: 1.5));
}
