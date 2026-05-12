import 'dart:async';
import 'package:flutter/material.dart';
import '../models/miner.dart';
import '../services/fluminer_api.dart';
import '../theme/volt_theme.dart';

// ── T3 voltage presets — confirmed live data ───────────────────────────────
// 2630mV = 111 TH/s / 1955W (confirmed), 2670mV = 117 TH/s / 1960W (confirmed)
// Frequency slider removed: firmware V1.0 bug — writes config but hardware
// ignores changes until manual power cycle. Mode switching works instantly.

class _VoltPreset {
  final String name;
  final int voltage; // mV
  final double hashTH;
  final double watt;
  final bool isDefault;
  const _VoltPreset(this.name, this.voltage, this.hashTH, this.watt,
      {this.isDefault = false});
  double get jth => watt / hashTH;
}

const _presets = [
  _VoltPreset('ECO',        2550,  95.0, 1650),
  _VoltPreset('STOCK',      2630, 111.0, 1955),
  _VoltPreset('FACTORY ★', 2670, 117.0, 1960, isDefault: true),
  _VoltPreset('HIGH',       2720, 121.0, 2100),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class FluMinerOCScreen extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  const FluMinerOCScreen({super.key, required this.miner, this.stats});

  @override
  State<FluMinerOCScreen> createState() => _FluMinerOCScreenState();
}

class _FluMinerOCScreenState extends State<FluMinerOCScreen> {
  KratosPalette get kc => KratosColors.of(context);

  late double _voltage;
  late FluMinerRunMode _mode;

  bool _saving = false;
  bool _pendingRestart = false;
  String? _result;

  static const _voltMin = 2400.0;
  static const _voltMax = 2900.0;

  @override
  void initState() {
    super.initState();
    final s = widget.stats;
    _voltage = (s?.coreVoltage ?? 0) > 0 ? s!.coreVoltage.toDouble() : 2670;
    _mode    = FluMinerRunMode.values[((s?.workMode ?? 1)).clamp(0, 2)];
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Preset apply ─────────────────────────────────────────────────────────

  Future<void> _applyPreset(_VoltPreset p) async {
    setState(() { _voltage = p.voltage.toDouble(); });
    await _applyVoltage();
  }

  // ── Run Mode ─────────────────────────────────────────────────────────────

  Future<void> _applyMode(FluMinerRunMode mode) async {
    setState(() { _saving = true; _result = '⏳ Switching to ${mode.label}…'; });
    final ok = await FluMinerAPI.instance.setRunMode(
        widget.miner.ip, widget.miner.port, mode);
    setState(() {
      _saving = false;
      _mode = ok ? mode : _mode;
      _result = ok ? '✅ ${mode.label} mode active.' : '❌ Failed — check WiFi.';
    });
  }

  // ── Voltage OC ───────────────────────────────────────────────────────────
  // Saves to miner config. Power cycle required to apply (firmware V1.0 bug).

  Future<void> _applyVoltage() async {
    setState(() {
      _saving = true;
      _pendingRestart = false;
      _result = '⏳ Saving ${_voltage.round()} mV to config…';
    });
    final ok = await FluMinerAPI.instance.setFrequencyAndVoltage(
      widget.miner.ip, widget.miner.port,
      frequencyMHz: 0, voltageMv: _voltage.round(),
    );
    setState(() {
      _saving = false;
      _pendingRestart = ok;
      _result = ok
          ? '✅ Saved — power cycle miner to apply new voltage.'
          : '❌ Failed — check WiFi.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('FluMiner T3 — Mode & Voltage',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
        leading: BackButton(color: kc.muted),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Run Mode ──────────────────────────────────────────────────────
          _sectionLabel('RUN MODE'),
          const SizedBox(height: 10),
          Row(children: FluMinerRunMode.values.map((m) {
            final selected = m == _mode;
            final color = switch (m) {
              FluMinerRunMode.efficiency => Colors.green,
              FluMinerRunMode.normal => kc.accent,
              FluMinerRunMode.turbo => Colors.orange,
            };
            final icon = switch (m) {
              FluMinerRunMode.efficiency => Icons.eco,
              FluMinerRunMode.normal => Icons.bolt,
              FluMinerRunMode.turbo => Icons.local_fire_department,
            };
            return Expanded(child: Padding(
              padding: EdgeInsets.only(right: m != FluMinerRunMode.turbo ? 8 : 0),
              child: GestureDetector(
                onTap: _saving ? null : () => _applyMode(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? color.withValues(alpha: 0.15) : kc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected ? color : kc.line,
                        width: selected ? 1.5 : 1),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: selected ? color : kc.muted, size: 20),
                    const SizedBox(height: 4),
                    Text(m.label, style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: selected ? color : kc.muted)),
                  ]),
                ),
              ),
            ));
          }).toList()),

          const SizedBox(height: 24),

          // ── Voltage Presets ───────────────────────────────────────────────
          _sectionLabel('VOLTAGE PRESETS',
              sub: 'Saved to config. Power cycle miner to apply voltage change.'),
          const SizedBox(height: 10),
          ...List.generate(_presets.length, (i) {
            final p = _presets[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: _saving ? null : () => _applyPreset(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.isDefault ? kc.accent.withValues(alpha: 0.08) : kc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isDefault ? kc.accent.withValues(alpha: 0.4) : kc.line,
                      width: p.isDefault ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(p.name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                            color: p.isDefault ? kc.accent : kc.text))),
                    Expanded(child: Text('${p.voltage} mV',
                        style: TextStyle(fontSize: 11, color: kc.muted, fontFamily: 'Courier'))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min,
                        children: [
                      Text('~${p.hashTH.toStringAsFixed(0)} TH/s',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                              color: kc.text, fontFamily: 'Courier')),
                      Text('~${p.watt.toStringAsFixed(0)}W / ${p.jth.toStringAsFixed(1)} J/TH',
                          style: TextStyle(fontSize: 10, color: kc.muted)),
                    ]),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: kc.muted, size: 16),
                  ]),
                ),
              ),
            );
          }),

          const SizedBox(height: 24),


          // ── Power cycle reminder ──────────────────────────────────────────
          if (_pendingRestart) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.power_settings_new, color: Colors.orange, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '⚡ Voltage saved — power cycle the T3 to apply. '
                  'Unplug from wall for 5 sec, then plug back in.',
                  style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── Manual voltage ────────────────────────────────────────────────
          _sectionLabel('MANUAL VOLTAGE',
              sub: 'Drag to set, then tap Apply. Power cycle to take effect.'),
          const SizedBox(height: 14),

          _SliderRow(
            label: 'Core Voltage',
            value: _voltage,
            min: _voltMin, max: _voltMax,
            divisions: ((_voltMax - _voltMin) / 10).round(),
            unit: 'mV', color: Colors.purple,
            onChanged: (v) => setState(() { _voltage = v; _pendingRestart = false; }),
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: _saving ? null : _applyVoltage,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: kc.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kc.accent.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: _saving
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kc.accent))
                    : Text(
                        'Apply ${_voltage.round()} mV',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 13, color: kc.accent)),
              ),
            ),
          ),


          // Result banner
          if (_result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _result!.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.1)
                    : _result!.startsWith('❌')
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _result!.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.3)
                    : _result!.startsWith('❌')
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.blue.withValues(alpha: 0.25)),
              ),
              child: Text(_result!,
                  style: TextStyle(fontSize: 13, color: kc.muted, height: 1.4)),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, {String? sub}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
        color: kc.muted, letterSpacing: 1.5)),
    if (sub != null) ...[
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(fontSize: 11,
          color: kc.muted.withValues(alpha: 0.65))),
    ],
  ]);
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final String unit;
  final Color color;
  final ValueChanged<double> onChanged;

  const _SliderRow({required this.label, required this.value,
    required this.min, required this.max, required this.divisions,
    required this.unit, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, color: kc.text)),
        const Spacer(),
        Text('${value.round()} $unit', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w900,
            color: color, fontFamily: 'Courier')),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: color, thumbColor: color,
          inactiveTrackColor: color.withValues(alpha: 0.2),
          overlayColor: color.withValues(alpha: 0.12),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          onChanged: onChanged,
        ),
      ),
      Row(children: [
        Text('${min.round()} $unit',
            style: TextStyle(fontSize: 9, color: kc.muted)),
        const Spacer(),
        Text('${max.round()} $unit',
            style: TextStyle(fontSize: 9, color: kc.muted)),
      ]),
    ]);
  }
}
