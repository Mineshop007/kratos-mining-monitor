import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../services/circuit_service.dart';
import '../widgets/klaw.dart';

/// Circuit Monitor screen.
///
/// Shows each user-defined circuit, the **measured** load on it (real
/// MinerStats.powerDraw, never estimated), and a 3-state health
/// indicator (ok / warning / overload / no-data).
class CircuitMonitorScreen extends StatelessWidget {
  const CircuitMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        title: Text('Circuit Monitor',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kc.text)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: kc.accent),
            onPressed: () => _editCircuit(context),
          ),
        ],
      ),
      body: Consumer2<CircuitService, MinerStore>(
        builder: (ctx, svc, store, _) {
          if (svc.circuits.isEmpty) {
            return Center(
              child: KlawEmptyState(
                headline: 'No circuits yet',
                quip: 'Group your miners by which breaker they share.\nKlaw will alarm before a circuit pops.',
                cta: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kc.accent,
                    foregroundColor: const Color(0xFF001A0E),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99)),
                  ),
                  icon: Icon(Icons.add),
                  label: Text('Add circuit',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  onPressed: () => _editCircuit(ctx),
                ),
              ),
            );
          }

          final snaps = svc.snapshots(store);
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              for (final snap in snaps)
                _CircuitCard(
                  snap: snap,
                  store: store,
                  onEdit: () => _editCircuit(ctx, existing: snap.circuit),
                  onDelete: () => svc.remove(snap.circuit.id),
                ),
              SizedBox(height: 16),
              _Footnote(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCircuit(BuildContext context, {Circuit? existing}) async {
    final kc = KratosColors.of(context);
    final svc = context.read<CircuitService>();
    final store = context.read<MinerStore>();
    final result = await showModalBottomSheet<Circuit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _CircuitEditor(
        existing: existing,
        availableMiners: store.miners,
      ),
    );
    if (result != null) {
      await svc.upsert(result);
    }
  }
}

class _CircuitCard extends StatelessWidget {
  final CircuitSnapshot snap;
  final MinerStore store;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CircuitCard({
    required this.snap,
    required this.store,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final c = snap.circuit;
    final color = switch (snap.status) {
      CircuitStatus.ok       => kc.accent,
      CircuitStatus.warning  => KratosColors.warning,
      CircuitStatus.overload => KratosColors.danger,
      CircuitStatus.noData   => kc.muted,
    };
    final loadFraction = (snap.loadFraction ?? 0).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color, blurRadius: 8, spreadRadius: 1),
                  ],
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(c.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kc.text)),
              ),
              IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined,
                      color: kc.muted)),
              IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline,
                      color: KratosColors.danger)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '${c.voltage.toStringAsFixed(0)}V · ${c.breakerAmps.toStringAsFixed(0)}A breaker · '
            '${(c.safetyFactor * 100).toStringAsFixed(0)}% safety',
            style: TextStyle(fontSize: 11, color: kc.muted),
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: kc.surface2),
                  FractionallySizedBox(
                    widthFactor: loadFraction,
                    child: Container(color: color),
                  ),
                  // Safety threshold mark
                  Positioned(
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment(c.safetyFactor * 2 - 1, 0),
                      child: Container(
                        width: 2,
                        height: 10,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: 'Load',
                  value: snap.measuredWatts == null
                      ? '—'
                      : '${(snap.measuredWatts! / 1000).toStringAsFixed(2)} kW',
                  color: color,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  label: 'Amps',
                  value: snap.amps == null
                      ? '—'
                      : '${snap.amps!.toStringAsFixed(1)} A',
                  color: kc.text,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  label: 'Breaker',
                  value: '${c.breakerAmps.toStringAsFixed(0)} A',
                  color: kc.muted,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  label: 'Status',
                  value: switch (snap.status) {
                    CircuitStatus.ok       => 'OK',
                    CircuitStatus.warning  => 'WARN',
                    CircuitStatus.overload => 'TRIP!',
                    CircuitStatus.noData   => 'no data',
                  },
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '${c.minerIds.length} miners attached · ${snap.onlineCount} online',
            style: TextStyle(fontSize: 11, color: kc.muted),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricCell({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 9,
                color: kc.muted,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800)),
        SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kc.line),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: kc.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Load is measured from each miner's reported power draw — never from nameplate values. Miners that don't report power are excluded; the circuit shows 'no data' until at least one miner on it reports.",
              style: TextStyle(
                  fontSize: 11, color: kc.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircuitEditor extends StatefulWidget {
  final Circuit? existing;
  final List<Miner> availableMiners;

  const _CircuitEditor({
    required this.existing,
    required this.availableMiners,
  });

  @override
  State<_CircuitEditor> createState() => _CircuitEditorState();
}

class _CircuitEditorState extends State<_CircuitEditor> {
  KratosPalette get kc => KratosColors.of(context);

  late final TextEditingController _name;
  CircuitPreset _preset = CircuitPreset.eu230v16a;
  late double _volts;
  late double _amps;
  late double _safety;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? 'Circuit');
    _volts = e?.voltage ?? 230;
    _amps = e?.breakerAmps ?? 16;
    _safety = e?.safetyFactor ?? 0.80;
    _selected = e?.minerIds.toSet() ?? {};
    // Match preset if it lines up
    for (final p in CircuitPreset.values) {
      if (p.spec.volts == _volts && p.spec.amps == _amps) {
        _preset = p;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kc.muted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 18),
            Text(
              isEdit ? 'Edit circuit' : 'New circuit',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kc.text),
            ),
            SizedBox(height: 18),
            TextField(
              controller: _name,
              style: TextStyle(color: kc.text),
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Garage 16A',
                hintStyle: TextStyle(color: kc.muted),
                labelStyle: TextStyle(color: kc.muted),
              ),
            ),
            SizedBox(height: 18),
            Text('PRESET',
                style: TextStyle(
                    fontSize: 11,
                    color: kc.muted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in CircuitPreset.values)
                  ChoiceChip(
                    label: Text(p.displayName),
                    selected: _preset == p,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _preset = p;
                        if (p != CircuitPreset.custom) {
                          _volts = p.spec.volts;
                          _amps = p.spec.amps;
                        }
                      });
                    },
                    selectedColor: kc.accent.withOpacity(0.18),
                    backgroundColor: kc.surface2,
                    labelStyle: TextStyle(
                        color: _preset == p
                            ? kc.accentBright
                            : kc.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                      side: BorderSide(
                          color: _preset == p
                              ? kc.accent
                              : kc.line),
                    ),
                  ),
              ],
            ),
            if (_preset == CircuitPreset.custom) ...[
              SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                        text: _volts.toStringAsFixed(0)),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: kc.text),
                    decoration: InputDecoration(
                        labelText: 'Volts',
                        labelStyle:
                            TextStyle(color: kc.muted)),
                    onChanged: (v) =>
                        _volts = double.tryParse(v) ?? _volts,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                        text: _amps.toStringAsFixed(0)),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: kc.text),
                    decoration: InputDecoration(
                        labelText: 'Amps',
                        labelStyle:
                            TextStyle(color: kc.muted)),
                    onChanged: (v) =>
                        _amps = double.tryParse(v) ?? _amps,
                  ),
                ),
              ]),
            ],
            SizedBox(height: 18),
            Text('MINERS ON THIS CIRCUIT',
                style: TextStyle(
                    fontSize: 11,
                    color: kc.muted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            SizedBox(height: 8),
            if (widget.availableMiners.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('No miners in fleet yet.',
                    style:
                        TextStyle(color: kc.muted, fontSize: 13)),
              )
            else
              for (final m in widget.availableMiners)
                CheckboxListTile(
                  value: _selected.contains(m.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(m.id);
                      } else {
                        _selected.remove(m.id);
                      }
                    });
                  },
                  title: Text(m.name,
                      style:
                          TextStyle(color: kc.text)),
                  subtitle: Text('${m.type.displayName} · ${m.ip}',
                      style: TextStyle(
                          fontSize: 11, color: kc.muted)),
                  activeColor: kc.accent,
                  contentPadding: EdgeInsets.zero,
                ),
            SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kc.accent,
                  foregroundColor: const Color(0xFF001A0E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99)),
                ),
                onPressed: () {
                  Navigator.pop(
                    context,
                    Circuit(
                      id: widget.existing?.id,
                      name: _name.text.trim().isEmpty
                          ? 'Circuit'
                          : _name.text.trim(),
                      voltage: _volts,
                      breakerAmps: _amps,
                      safetyFactor: _safety,
                      minerIds: _selected.toList(),
                    ),
                  );
                },
                child: Text(isEdit ? 'Save' : 'Create circuit',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
