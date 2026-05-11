import 'dart:async';
import 'package:flutter/material.dart';
import '../models/miner.dart';
import '../services/fluminer_api.dart';
import '../theme/volt_theme.dart';

class FluMinerOCScreen extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  const FluMinerOCScreen({super.key, required this.miner, this.stats});

  @override
  State<FluMinerOCScreen> createState() => _FluMinerOCScreenState();
}

class _FluMinerOCScreenState extends State<FluMinerOCScreen> {
  KratosPalette get kc => KratosColors.of(context);

  // Current values from stats (or defaults)
  late double _freq;       // MHz
  late double _voltage;    // mV
  late FluMinerRunMode _mode;

  bool _saving = false;
  bool _autoTuning = false;
  String? _result;
  Map<String, dynamic>? _autoTuneStatus;
  Timer? _autoTunePoller;

  // Safe bounds for T3
  static const _freqMin = 300.0;
  static const _freqMax = 600.0;
  static const _voltMin = 2400.0;
  static const _voltMax = 2900.0;

  @override
  void initState() {
    super.initState();
    final s = widget.stats;
    _freq    = (s?.frequency ?? 0) > 0 ? s!.frequency : 475;
    _voltage = (s?.coreVoltage ?? 0) > 0 ? s!.coreVoltage.toDouble() : 2630;
    _mode    = FluMinerRunMode.values[((s?.workMode ?? 1)).clamp(0, 2)];
  }

  @override
  void dispose() {
    _autoTunePoller?.cancel();
    super.dispose();
  }

  // ── Run Mode ──────────────────────────────────────────────────────────────

  Future<void> _applyMode(FluMinerRunMode mode) async {
    setState(() { _saving = true; _result = '⏳ Switching to ${mode.label} mode…'; });
    final ok = await FluMinerAPI.instance.setRunMode(
        widget.miner.ip, widget.miner.port, mode);
    setState(() {
      _saving = false;
      if (ok) {
        _mode = mode;
        _result = '✅ ${mode.label} mode active.';
      } else {
        _result = '❌ Failed — check WiFi connection.';
      }
    });
  }

  // ── OC Apply ─────────────────────────────────────────────────────────────

  Future<void> _applyOC() async {
    setState(() { _saving = true; _result = '⏳ Applying OC settings…'; });
    final ok = await FluMinerAPI.instance.setFrequencyAndVoltage(
      widget.miner.ip,
      widget.miner.port,
      frequencyMHz: _freq.round(),
      voltageMv: _voltage.round(),
    );
    setState(() {
      _saving = false;
      _result = ok
          ? '✅ Applied ${_freq.round()} MHz / ${_voltage.round()} mV — miner adjusting.'
          : '❌ Failed — check WiFi connection.';
    });
  }

  // ── Autotune ─────────────────────────────────────────────────────────────

  Future<void> _startAutoTune() async {
    setState(() { _autoTuning = true; _result = '⏳ Logging in…'; });
    // Test auth first so we can give a specific error
    final session = await FluMinerAPI.instance.login(
        widget.miner.ip, widget.miner.port);
    if (session == null) {
      setState(() {
        _autoTuning = false;
        _result = '❌ Login failed — check miner is on same WiFi. '
            'Default creds: root/root or admin/123456.';
      });
      return;
    }
    setState(() => _result = '⏳ Starting autotune…');
    final ok = await FluMinerAPI.instance.startAutoTune(
        widget.miner.ip, widget.miner.port);
    if (!ok) {
      setState(() {
        _autoTuning = false;
        _result = '❌ Autotune endpoint failed — '
            'your firmware may not support it. '
            'Try OC manually instead.';
      });
      return;
    }
    setState(() => _result = '🔄 Autotune running… polling status every 10s');
    // Poll status every 10 seconds
    _autoTunePoller = Timer.periodic(const Duration(seconds: 10), (_) async {
      final status = await FluMinerAPI.instance.getAutoTuneStatus(
          widget.miner.ip, widget.miner.port);
      if (!mounted) return;
      setState(() => _autoTuneStatus = status);
      // Check if done
      final done = status?['done'] == true ||
          status?['status'] == 'done' ||
          status?['finished'] == true;
      if (done) {
        _autoTunePoller?.cancel();
        final bestFreq = status?['bestFrequency'] ?? status?['frequency'];
        final bestVolt = status?['bestVoltage'] ?? status?['voltage'];
        setState(() {
          _autoTuning = false;
          if (bestFreq != null) _freq = (bestFreq as num).toDouble();
          if (bestVolt != null) _voltage = (bestVolt as num).toDouble();
          _result = '✅ Autotune complete! '
              'Best: ${_freq.round()} MHz / ${_voltage.round()} mV';
        });
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('FluMiner T3 — OC & Mode',
            style: TextStyle(
                color: kc.text,
                fontWeight: FontWeight.w800)),
        leading: BackButton(color: kc.muted),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Run mode selector ───────────────────────────────────────────
          _Section('RUN MODE',
              'Controls power draw and hashrate target.'),
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
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: m != FluMinerRunMode.turbo ? 8 : 0),
                child: GestureDetector(
                  onTap: _saving ? null : () => _applyMode(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.15)
                          : kc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? color
                            : kc.line,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon,
                            color: selected ? color : kc.muted, size: 22),
                        const SizedBox(height: 6),
                        Text(m.label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: selected ? color : kc.muted)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList()),

          const SizedBox(height: 24),

          // ── Autotune ────────────────────────────────────────────────────
          _Section('AUTOTUNE',
              'Finds optimal frequency + voltage for best efficiency. Takes 5–15 minutes.'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: (_saving || _autoTuning) ? null : _startAutoTune,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _autoTuning
                    ? Colors.blue.withValues(alpha: 0.12)
                    : kc.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _autoTuning ? Colors.blue : kc.line,
                  width: _autoTuning ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_autoTuning) ...[
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.blue)),
                    const SizedBox(width: 10),
                  ] else
                    const Icon(Icons.auto_fix_high, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _autoTuning ? 'Autotune Running…' : 'Start Autotune',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),

          if (_autoTuneStatus != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kc.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AUTOTUNE STATUS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kc.muted,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 6),
                  ..._autoTuneStatus!.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('${e.key}: ${e.value}',
                            style: TextStyle(
                                fontSize: 12,
                                color: kc.muted,
                                fontFamily: 'Courier')),
                      )),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Manual OC ───────────────────────────────────────────────────
          _Section('MANUAL OC',
              'Set frequency and voltage directly. Use with caution.'),
          const SizedBox(height: 14),

          // Frequency slider
          _SliderRow(
            label: 'Frequency',
            value: _freq,
            min: _freqMin,
            max: _freqMax,
            divisions: ((_freqMax - _freqMin) / 5).round(),
            unit: 'MHz',
            color: kc.accent,
            onChanged: (v) => setState(() => _freq = v),
          ),
          const SizedBox(height: 16),

          // Voltage slider
          _SliderRow(
            label: 'Core Voltage',
            value: _voltage,
            min: _voltMin,
            max: _voltMax,
            divisions: ((_voltMax - _voltMin) / 10).round(),
            unit: 'mV',
            color: Colors.purple,
            onChanged: (v) => setState(() => _voltage = v),
          ),
          const SizedBox(height: 6),

          // Warning
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Higher voltage = more heat. Keep temp below 85°C. '
                  'Run Autotune for best efficiency settings.',
                  style: TextStyle(fontSize: 11, color: kc.muted, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // Apply OC button
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
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kc.accent))
                    : Text(
                        'Apply ${_freq.round()} MHz / ${_voltage.round()} mV',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: kc.accent)),
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
                        : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _result!.startsWith('✅')
                      ? Colors.green.withValues(alpha: 0.3)
                      : _result!.startsWith('❌')
                          ? Colors.red.withValues(alpha: 0.3)
                          : Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Text(_result!,
                  style: TextStyle(fontSize: 13, color: kc.muted)),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Section(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kc.muted,
              letterSpacing: 1.5)),
      const SizedBox(height: 3),
      Text(subtitle,
          style: TextStyle(fontSize: 11, color: kc.muted.withValues(alpha: 0.7))),
    ]);
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final Color color;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: kc.text)),
        const Spacer(),
        Text('${value.round()} $unit',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
                fontFamily: 'Courier')),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: color,
          inactiveTrackColor: color.withValues(alpha: 0.2),
          thumbColor: color,
          overlayColor: color.withValues(alpha: 0.15),
          trackHeight: 3,
          thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
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
