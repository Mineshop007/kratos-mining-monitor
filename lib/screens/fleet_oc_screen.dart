import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/esp_miner_api.dart';
import '../services/miner_store.dart';

/// Apply a single OC preset (frequency + voltage) across every ESP-Miner
/// compatible miner in the fleet. CGMiner / Avalon devices are skipped.
class FleetOCScreen extends StatefulWidget {
  const FleetOCScreen({super.key});

  @override
  State<FleetOCScreen> createState() => _FleetOCScreenState();
}

enum _ApplyState { idle, applying, ok, failed }

class _FleetOCScreenState extends State<FleetOCScreen> {
  // Generic presets — using nerdoctaxe defaults which span the most common
  // ESP-Miner range. Same MHz values as the per-miner OCScreen for that type.
  static const _presets = <_Preset>[
    _Preset(490, 'ECO', 'lower power'),
    _Preset(530, 'STD', 'balanced'),
    _Preset(560, 'OC',  'higher hash'),
    _Preset(590, 'MAX', 'maximum'),
  ];

  int _selectedFreq = 530;
  int _selectedVoltage = 1150;
  bool _applying = false;
  final Map<String, _ApplyState> _results = {};

  bool _isEsp(Miner m) => m.type.apiType == ApiType.espMinerHttp;

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final all = store.miners;
      final espMiners = all.where(_isEsp).toList();
      final skipped = all.where((m) => !_isEsp(m)).toList();

      return Scaffold(
        backgroundColor: KratosTheme.bg,
        appBar: AppBar(
          backgroundColor: KratosTheme.bg,
          title: const Text('Fleet OC',
              style: TextStyle(color: KratosTheme.textPrim)),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KratosTheme.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: KratosTheme.orange.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber,
                  color: KratosTheme.orange, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Applies settings to all ESP-Miner compatible miners (BitAxe, NerdAxe, LuckyMiner). Avalon and Antminer miners are skipped.',
                  style: TextStyle(
                      fontSize: 12, color: KratosTheme.muted),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // PRESET section
          const _SectionLabel('PRESET'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final p in _presets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: _applying
                          ? null
                          : () => setState(() => _selectedFreq = p.mhz),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedFreq == p.mhz
                              ? KratosTheme.orange
                              : KratosTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _selectedFreq == p.mhz
                                  ? KratosTheme.orange
                                  : KratosTheme.border),
                        ),
                        child: Column(children: [
                          Text('${p.mhz}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedFreq == p.mhz
                                      ? Colors.black
                                      : KratosTheme.textPrim,
                                  fontFamily: 'Courier')),
                          Text('MHz',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: _selectedFreq == p.mhz
                                      ? Colors.black54
                                      : KratosTheme.muted)),
                          const SizedBox(height: 2),
                          Text(p.label,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedFreq == p.mhz
                                      ? Colors.black54
                                      : KratosTheme.muted,
                                  letterSpacing: 0.5)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _presets
                  .firstWhere((p) => p.mhz == _selectedFreq,
                      orElse: () => _presets[1])
                  .hint,
              style: const TextStyle(
                  fontSize: 11, color: KratosTheme.muted),
            ),
          ),
          const SizedBox(height: 20),

          // VOLTAGE section
          Row(children: [
            const _SectionLabel('VOLTAGE'),
            const Spacer(),
            Text('$_selectedVoltage mV',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: KratosTheme.orange,
                    fontFamily: 'Courier')),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: KratosTheme.orange,
              thumbColor: KratosTheme.orange,
              inactiveTrackColor: KratosTheme.border,
              overlayColor: KratosTheme.orange.withOpacity(0.15),
              valueIndicatorColor: KratosTheme.orange,
              valueIndicatorTextStyle:
                  const TextStyle(color: Colors.black, fontFamily: 'Courier'),
            ),
            child: Slider(
              value: _selectedVoltage.toDouble(),
              min: 1100,
              max: 1250,
              divisions: 30,
              label: '$_selectedVoltage mV',
              onChanged: _applying
                  ? null
                  : (v) => setState(() => _selectedVoltage = v.round()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1100 mV',
                    style: TextStyle(
                        fontSize: 10, color: KratosTheme.muted)),
                Text('1250 mV',
                    style: TextStyle(
                        fontSize: 10, color: KratosTheme.muted)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // TARGET MINERS section
          _SectionLabel('TARGET MINERS · ${espMiners.length}'),
          const SizedBox(height: 8),
          if (espMiners.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KratosTheme.border),
              ),
              child: const Text(
                'No ESP-Miner compatible miners found.',
                style: TextStyle(
                    fontSize: 12, color: KratosTheme.muted),
              ),
            )
          else
            ...espMiners.map((m) => _MinerRow(
                  miner: m,
                  enabled: true,
                  state: _results[m.id] ?? _ApplyState.idle,
                )),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...skipped.map((m) => _MinerRow(
                  miner: m,
                  enabled: false,
                  state: _ApplyState.idle,
                )),
          ],
          const SizedBox(height: 24),

          // Apply button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: (_applying || espMiners.isEmpty)
                    ? KratosTheme.border
                    : KratosTheme.orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_applying || espMiners.isEmpty)
                  ? null
                  : () => _confirmAndApply(espMiners),
              icon: _applying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black54))
                  : const Icon(Icons.bolt),
              label: Text(
                _applying
                    ? 'Applying…'
                    : 'APPLY TO ALL ${espMiners.length} MINER${espMiners.length == 1 ? '' : 'S'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      );
    });
  }

  Future<void> _confirmAndApply(List<Miner> miners) async {
    final preset = _presets.firstWhere(
      (p) => p.mhz == _selectedFreq,
      orElse: () => _presets[1],
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KratosTheme.surface,
        title: const Text('Apply to fleet?',
            style: TextStyle(color: KratosTheme.textPrim)),
        content: Text(
          'Apply ${preset.label} (${preset.mhz} MHz) @ ${_selectedVoltage} mV to ${miners.length} miner${miners.length == 1 ? '' : 's'}?',
          style: const TextStyle(color: KratosTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: KratosTheme.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KratosTheme.orange,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _applyToAll(miners);
  }

  Future<void> _applyToAll(List<Miner> miners) async {
    setState(() {
      _applying = true;
      for (final m in miners) {
        _results[m.id] = _ApplyState.applying;
      }
    });

    int success = 0;
    int failed = 0;
    for (final m in miners) {
      final ok = await _applyOne(m);
      if (!mounted) return;
      setState(() {
        _results[m.id] = ok ? _ApplyState.ok : _ApplyState.failed;
      });
      if (ok) {
        success++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _applying = false);

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      backgroundColor: KratosTheme.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      content: Text(
        failed == 0
            ? '✅ Applied to all $success miner${success == 1 ? '' : 's'}'
            : '⚠️  $success applied · $failed failed',
        style: const TextStyle(color: KratosTheme.textPrim),
      ),
    ));
  }

  Future<bool> _applyOne(Miner m) async {
    try {
      final freqOk = await EspMinerAPI.instance.setFrequency(
        m.ip,
        m.port,
        _selectedFreq,
        remoteUrl: m.remoteUrl,
        isRemote: m.isRemote,
      );
      if (!freqOk) return false;
      final voltOk = await EspMinerAPI.instance.setCoreVoltage(
        m.ip,
        m.port,
        _selectedVoltage,
        remoteUrl: m.remoteUrl,
        isRemote: m.isRemote,
      );
      return voltOk;
    } catch (_) {
      return false;
    }
  }
}

class _Preset {
  final int mhz;
  final String label;
  final String hint;
  const _Preset(this.mhz, this.label, this.hint);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: KratosTheme.muted,
            letterSpacing: 1.5),
      );
}

class _MinerRow extends StatelessWidget {
  final Miner miner;
  final bool enabled;
  final _ApplyState state;
  const _MinerRow({
    required this.miner,
    required this.enabled,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? KratosTheme.textPrim : KratosTheme.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enabled
            ? KratosTheme.surface
            : KratosTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: enabled
                ? KratosTheme.border
                : KratosTheme.border.withOpacity(0.5)),
      ),
      child: Row(children: [
        Icon(
          enabled ? Icons.memory : Icons.block,
          size: 16,
          color: enabled ? KratosTheme.neon : KratosTheme.muted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            miner.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: KratosTheme.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: KratosTheme.border),
          ),
          child: Text(
            _typeLabel(miner.type),
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontFamily: 'Courier',
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 22, child: Center(child: _badge(enabled))),
      ]),
    );
  }

  Widget _badge(bool enabled) {
    if (!enabled) {
      return const Text('—',
          style: TextStyle(color: KratosTheme.muted, fontSize: 14));
    }
    switch (state) {
      case _ApplyState.idle:
        return const SizedBox.shrink();
      case _ApplyState.applying:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: KratosTheme.orange),
        );
      case _ApplyState.ok:
        return const Text('✅', style: TextStyle(fontSize: 14));
      case _ApplyState.failed:
        return const Text('❌', style: TextStyle(fontSize: 14));
    }
  }

  String _typeLabel(MinerType t) {
    switch (t) {
      case MinerType.bitaxeGamma:
        return 'BitAxe γ';
      case MinerType.bitaxeUltra:
        return 'BitAxe U';
      case MinerType.bitaxeGT:
        return 'BitAxe GT';
      case MinerType.nerdqaxe:
        return 'NerdQAxe';
      case MinerType.nerdoctaxe:
        return 'NerdOctaxe';
      case MinerType.avalonNano3:
      case MinerType.avalonNano3s:
        return 'Avalon Nano';
      case MinerType.avalonMini3:
        return 'Avalon Mini';
      case MinerType.avalonQ:
        return 'Avalon Q';
      default:
        return t.name;
    }
  }
}
