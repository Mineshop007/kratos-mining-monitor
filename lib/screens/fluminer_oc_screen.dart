import 'dart:async';
import 'package:flutter/material.dart';
import '../models/miner.dart';
import '../services/fluminer_api.dart';
import '../theme/volt_theme.dart';

// ── Validated presets from live T3 testing ───────────────────────────────────
// Power is ~constant at 1244W regardless of frequency.
// Efficiency is entirely driven by hashrate (lower W/TH = better).

class _OcPreset {
  final String name;
  final int freq;
  final int voltage;
  final double hashTH;   // TH/s measured live
  final double efficiency; // W/TH — lower is better
  final bool isOptimal;
  const _OcPreset(this.name, this.freq, this.voltage, this.hashTH,
      this.efficiency, {this.isOptimal = false});
}

const _presets = [
  _OcPreset('ECO',         475, 2630,  91.8, 13.54),
  _OcPreset('BALANCED',    505, 2655, 101.4, 12.27),
  _OcPreset('OPTIMAL ⭐',  520, 2670, 101.6, 12.25, isOptimal: true),
  _OcPreset('FACTORY',     535, 2690, 101.4, 12.30),
  _OcPreset('HIGH',        550, 2705,  97.3, 12.80),
];

// ── Autotune sweep steps ─────────────────────────────────────────────────────
// The T3 has constant power draw (~1244W). Peak hashrate = best efficiency.
// Sweep from low → high, wait for stabilisation, pick hashrate peak.

const _sweepSteps = [
  (freq: 475, voltage: 2630),
  (freq: 490, voltage: 2640),
  (freq: 505, voltage: 2655),
  (freq: 520, voltage: 2670),
  (freq: 535, voltage: 2690),
  (freq: 550, voltage: 2705),
];
const _stabSeconds = 1200; // 20 minutes per step — ASIC needs full thermal stabilisation

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

  late double _freq;
  late double _voltage;
  late FluMinerRunMode _mode;

  bool _saving = false;
  bool _autoTuning = false;
  String? _result;

  // Autotune state
  int _autoStep = 0;
  int _autoCountdown = 0;
  Timer? _autoTimer;
  final List<({int freq, int voltage, double hashTH})> _autoResults = [];
  ({int freq, int voltage, double hashTH})? _autoBest;

  static const _freqMin = 400.0;
  static const _freqMax = 600.0;
  static const _voltMin = 2400.0;
  static const _voltMax = 2900.0;

  @override
  void initState() {
    super.initState();
    final s = widget.stats;
    _freq    = (s?.frequency ?? 0) > 0 ? s!.frequency : 535;
    _voltage = (s?.coreVoltage ?? 0) > 0 ? s!.coreVoltage.toDouble() : 2690;
    _mode    = FluMinerRunMode.values[((s?.workMode ?? 1)).clamp(0, 2)];
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
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

  // ── Preset apply ─────────────────────────────────────────────────────────

  Future<void> _applyPreset(_OcPreset p) async {
    setState(() {
      _freq = p.freq.toDouble();
      _voltage = p.voltage.toDouble();
    });
    await _applyOC();
  }

  // ── Manual OC ────────────────────────────────────────────────────────────

  Future<void> _applyOC() async {
    setState(() { _saving = true; _result = '⏳ Applying ${_freq.round()} MHz / ${_voltage.round()} mV…'; });
    final ok = await FluMinerAPI.instance.setFrequencyAndVoltage(
      widget.miner.ip, widget.miner.port,
      frequencyMHz: _freq.round(), voltageMv: _voltage.round(),
    );
    setState(() {
      _saving = false;
      _result = ok
          ? '✅ Applied! Hashrate stabilises in ~60s.'
          : '❌ Failed — check WiFi connection.';
    });
  }

  // ── In-app Autotune sweep ─────────────────────────────────────────────────
  // Since T3 power is ~constant, peak hashrate = peak efficiency.
  // Sweep: apply each step, wait for stabilisation, sample hashrate, compare.

  Future<void> _startAutoTune() async {
    setState(() {
      _autoTuning = true;
      _autoStep = 0;
      _autoResults.clear();
      _autoBest = null;
      _result = '⏳ Autotune: testing login…';
    });

    final session = await FluMinerAPI.instance.login(
        widget.miner.ip, widget.miner.port);
    if (session == null) {
      setState(() {
        _autoTuning = false;
        _result = '❌ Login failed. Default creds: root/root or admin/123456.';
      });
      return;
    }

    _runNextStep();
  }

  void _runNextStep() {
    if (_autoStep >= _sweepSteps.length) {
      _finishAutoTune();
      return;
    }

    final step = _sweepSteps[_autoStep];
    setState(() => _result =
        '🔄 Step ${_autoStep + 1}/${_sweepSteps.length}: '
        'Testing ${step.freq} MHz / ${step.voltage} mV…');

    FluMinerAPI.instance.setFrequencyAndVoltage(
      widget.miner.ip, widget.miner.port,
      frequencyMHz: step.freq, voltageMv: step.voltage,
    ).then((ok) {
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _autoTuning = false;
          _result = '❌ OC apply failed at step ${_autoStep + 1}. Stopping.';
        });
        return;
      }
      // Wait for stabilisation then sample hashrate
      _autoCountdown = _stabSeconds;
      _autoTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) { t.cancel(); return; }
        _autoCountdown--;
        final _mins = _autoCountdown ~/ 60;
        final _secs = _autoCountdown % 60;
        final _timeStr = _mins > 0
            ? '${_mins}m ${_secs.toString().padLeft(2, '0')}s'
            : '${_secs}s';
        setState(() => _result =
            '⏱ Step ${_autoStep + 1}/${_sweepSteps.length} — '
            '${step.freq} MHz: stabilising… $_timeStr remaining');

        if (_autoCountdown <= 0) {
          t.cancel();
          await _sampleAndAdvance(step.freq, step.voltage);
        }
      });
    });
  }

  Future<void> _sampleAndAdvance(int freq, int voltage) async {
    final stats = await FluMinerAPI.instance.fetchStats(
        widget.miner.ip, port: widget.miner.port);
    if (!mounted) return;

    final hashTH = stats.hashrate5s / 1000; // GH→TH
    _autoResults.add((freq: freq, voltage: voltage, hashTH: hashTH));

    // Track best hashrate (= best efficiency since power is constant)
    if (_autoBest == null || hashTH > _autoBest!.hashTH) {
      _autoBest = (freq: freq, voltage: voltage, hashTH: hashTH);
    }

    setState(() => _result =
        '📊 ${freq} MHz → ${hashTH.toStringAsFixed(1)} TH/s  '
        '(best so far: ${_autoBest!.freq} MHz)');

    _autoStep++;
    _runNextStep();
  }

  void _finishAutoTune() async {
    final best = _autoBest;
    if (best == null) {
      setState(() { _autoTuning = false; _result = '❌ No results collected.'; });
      return;
    }

    setState(() => _result = '⏳ Applying best: ${best.freq} MHz / ${best.voltage} mV…');
    await FluMinerAPI.instance.setFrequencyAndVoltage(
      widget.miner.ip, widget.miner.port,
      frequencyMHz: best.freq, voltageMv: best.voltage,
    );

    setState(() {
      _autoTuning = false;
      _freq = best.freq.toDouble();
      _voltage = best.voltage.toDouble();
      _result = '✅ Autotune complete!\n'
          'Optimal: ${best.freq} MHz / ${best.voltage} mV '
          '→ ${best.hashTH.toStringAsFixed(1)} TH/s';
    });
  }

  void _cancelAutoTune() {
    _autoTimer?.cancel();
    setState(() {
      _autoTuning = false;
      _result = '⛔ Autotune cancelled.';
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('FluMiner T3 — OC & Autotune',
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
                onTap: (_saving || _autoTuning) ? null : () => _applyMode(m),
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

          // ── Quick Presets ─────────────────────────────────────────────────
          _sectionLabel('QUICK PRESETS',
              sub: 'Live-tested values from your T3. Power ~1244W constant.'),
          const SizedBox(height: 10),
          ...List.generate(_presets.length, (i) {
            final p = _presets[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: (_saving || _autoTuning) ? null : () => _applyPreset(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.isOptimal
                        ? kc.accent.withValues(alpha: 0.08)
                        : kc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isOptimal
                          ? kc.accent.withValues(alpha: 0.4)
                          : kc.line,
                      width: p.isOptimal ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(p.name,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: p.isOptimal ? kc.accent : kc.text))),
                    Expanded(child: Text(
                        '${p.freq} MHz / ${p.voltage} mV',
                        style: TextStyle(fontSize: 11,
                            color: kc.muted, fontFamily: 'Courier'))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min, children: [
                      Text('${p.hashTH.toStringAsFixed(1)} TH/s',
                          style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w800, color: kc.text,
                              fontFamily: 'Courier')),
                      Text('${p.efficiency} W/TH',
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

          // ── In-app Autotune ───────────────────────────────────────────────
          _sectionLabel('AUTOTUNE',
              sub: 'Sweeps ${_sweepSteps.length} steps × 20 min each '
                  '(~${(_sweepSteps.length * _stabSeconds / 3600).toStringAsFixed(1)} hrs total). '
                  'ASIC needs full thermal stabilisation per step. '
                  'Picks peak hashrate = best efficiency.'),
          const SizedBox(height: 10),

          // Autotune results table (while running)
          if (_autoResults.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: kc.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kc.line)),
              child: Column(
                children: _autoResults.map((r) {
                  final isBest = _autoBest?.freq == r.freq;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(isBest ? Icons.star : Icons.circle,
                          size: 10,
                          color: isBest ? kc.accent : kc.muted),
                      const SizedBox(width: 8),
                      Text('${r.freq} MHz',
                          style: TextStyle(
                              fontSize: 11, color: kc.muted,
                              fontFamily: 'Courier',
                              fontWeight: isBest ? FontWeight.w800 : null)),
                      const Spacer(),
                      Text('${r.hashTH.toStringAsFixed(1)} TH/s',
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Courier',
                              fontWeight: isBest ? FontWeight.w800 : null,
                              color: isBest ? kc.accent : kc.text)),
                    ]),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Start / Cancel button
          GestureDetector(
            onTap: _saving ? null
                : _autoTuning ? _cancelAutoTune : _startAutoTune,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _autoTuning
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _autoTuning
                        ? Colors.red.withValues(alpha: 0.4)
                        : Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_autoTuning) ...[
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.blue)),
                  const SizedBox(width: 10),
                  const Icon(Icons.stop_circle_outlined,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  const Text('Stop Autotune',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: Colors.red)),
                ] else ...[
                  const Icon(Icons.auto_fix_high, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Text('Start Autotune',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: Colors.blue)),
                ],
              ]),
            ),
          ),

          const SizedBox(height: 24),

          // ── Manual OC ─────────────────────────────────────────────────────
          _sectionLabel('MANUAL OC',
              sub: 'Set frequency and voltage directly.'),
          const SizedBox(height: 14),

          _SliderRow(
            label: 'Frequency',
            value: _freq,
            min: _freqMin, max: _freqMax,
            divisions: ((_freqMax - _freqMin) / 5).round(),
            unit: 'MHz', color: kc.accent,
            onChanged: (v) => setState(() => _freq = v),
          ),
          const SizedBox(height: 16),
          _SliderRow(
            label: 'Core Voltage',
            value: _voltage,
            min: _voltMin, max: _voltMax,
            divisions: ((_voltMax - _voltMin) / 10).round(),
            unit: 'mV', color: Colors.purple,
            onChanged: (v) => setState(() => _voltage = v),
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 15),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'T3 power is ~constant (1244W). Efficiency = hashrate ÷ 1244. '
                  'Peak hash at 520 MHz — sweet spot confirmed live.',
                  style: TextStyle(
                      fontSize: 11, color: kc.muted, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: (_saving || _autoTuning) ? null : _applyOC,
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
                        'Apply ${_freq.round()} MHz / ${_voltage.round()} mV',
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
