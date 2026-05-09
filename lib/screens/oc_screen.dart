import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/avalon_api.dart';
import '../services/autotune_service.dart';
import '../services/oc_community_service.dart';
import '../services/miner_store.dart';
import 'package:provider/provider.dart';

class OCScreen extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  const OCScreen({super.key, required this.miner, this.stats});

  @override
  State<OCScreen> createState() => _OCScreenState();
}

class _OCScreenState extends State<OCScreen> {
  KratosPalette get kc => KratosColors.of(context);

  late List<_FreqPreset> presets;
  int selectedFreq = 0;
  int selectedVoltage = 0;
  int workMode = 1;
  int selectedFan = 50;
  bool applying = false;
  String? result;

  bool get _isEsp => widget.miner.type.apiType == ApiType.espMinerHttp;
  MinerType get _resolvedType => widget.stats?.type ?? widget.miner.type;

  int get _freqMin => switch (_resolvedType) {
    MinerType.nerdqaxe || MinerType.nerdoctaxe               => 350,
    MinerType.avalonNano3s || MinerType.avalonNano3           => 480, // Nano 3S safe lower bound
    _ => _isEsp ? 300 : 400,
  };

  int get _freqMax => switch (_resolvedType) {
    MinerType.nerdqaxe || MinerType.nerdoctaxe               => 750,
    MinerType.bitaxeGamma || MinerType.bitaxeUltra || MinerType.bitaxeGT => 650,
    MinerType.avalonNano3s || MinerType.avalonNano3           => 600, // Nano 3S safe upper bound
    _ => _isEsp ? 700 : 650,
  };

  /// Avalon Q and Mini 3 — workmode control via CGMiner ascset (0=Eco,1=Standard,2=Super)
  bool get _isAvalonQ {
    final t = _resolvedType;
    return t == MinerType.avalonQ || t == MinerType.avalonMini3;
  }

  /// Avalon Nano 3S / Nano 3 — frequency control via HTTP PATCH /api/system
  bool get _isAvalonNano {
    final t = _resolvedType;
    return t == MinerType.avalonNano3s || t == MinerType.avalonNano3;
  }

  /// Any Avalon device
  bool get _isAvalon => _isAvalonQ || _isAvalonNano;

  @override
  void initState() {
    super.initState();
    _initPresets();
    if (widget.stats?.frequency != null && widget.stats!.frequency > 0) {
      selectedFreq = widget.stats!.frequency.toInt().clamp(_freqMin, _freqMax);
    } else {
      selectedFreq = presets[1].mhz;
    }
    selectedVoltage = widget.stats?.coreVoltage ?? 1150;
    if (selectedVoltage == 0) selectedVoltage = 1150;
    // Pre-select current workmode + fan from live stats (Avalon Q)
    final liveWorkMode = widget.stats?.workMode ?? -1;
    if (liveWorkMode >= 0 && liveWorkMode <= 2) workMode = liveWorkMode;
    selectedFan = (widget.stats?.fanPercent ?? 50).clamp(0, 100);
  }

  void _initPresets() {
    presets = switch (_resolvedType) {
      MinerType.nerdqaxe => [
        _FreqPreset(450, 'ECO', '~2.6 TH/s', kc.accent),
        _FreqPreset(530, 'STD', '~3.1 TH/s', KratosTheme.blue),
        _FreqPreset(650, 'OC',  '~3.8 TH/s', KratosTheme.orange),
        _FreqPreset(750, 'MAX', '~4.8 TH/s', KratosTheme.red),
      ],
      MinerType.nerdoctaxe => [
        _FreqPreset(450, 'ECO', '~7.5 TH/s', kc.accent),
        _FreqPreset(530, 'STD', '~9.2 TH/s', KratosTheme.blue),
        _FreqPreset(650, 'OC',  '~11 TH/s',  KratosTheme.orange),
        _FreqPreset(750, 'MAX', '~12 TH/s',  KratosTheme.red),
      ],
      MinerType.bitaxeGamma => [
        _FreqPreset(400, 'ECO', '~400 GH/s', kc.accent),
        _FreqPreset(490, 'STD', '~490 GH/s', KratosTheme.blue),
        _FreqPreset(550, 'OC',  '~550 GH/s', KratosTheme.orange),
        _FreqPreset(600, 'MAX', '~600 GH/s', KratosTheme.red),
      ],
      MinerType.bitaxeUltra => [
        _FreqPreset(450, 'ECO', '~500 GH/s', kc.accent),
        _FreqPreset(525, 'STD', '~600 GH/s', KratosTheme.blue),
        _FreqPreset(575, 'OC',  '~700 GH/s', KratosTheme.orange),
        _FreqPreset(625, 'MAX', '~800 GH/s', KratosTheme.red),
      ],
      MinerType.bitaxeGT => [
        _FreqPreset(475, 'ECO', '~700 GH/s', kc.accent),
        _FreqPreset(550, 'STD', '~850 GH/s', KratosTheme.blue),
        _FreqPreset(600, 'OC',  '~950 GH/s', KratosTheme.orange),
        _FreqPreset(650, 'MAX', '~1.1 TH/s', KratosTheme.red),
      ],
      MinerType.avalonNano3s || MinerType.avalonNano3 => [
        _FreqPreset(528, 'ECO', '~5.2 TH/s', kc.accent),
        _FreqPreset(546, 'STD', '~5.8 TH/s', KratosTheme.blue),
        _FreqPreset(567, 'OC',  '~6.1 TH/s', KratosTheme.orange),
        _FreqPreset(588, 'MAX', '~6.5 TH/s', KratosTheme.red),
      ],
      _ => [
        _FreqPreset(400, 'ECO', 'Efficient', kc.accent),
        _FreqPreset(490, 'STD', 'Normal',    KratosTheme.blue),
        _FreqPreset(550, 'OC',  'OC',        KratosTheme.orange),
        _FreqPreset(600, 'MAX', 'Maximum',   KratosTheme.red),
      ],
    };
  }

  String _fmtBestDiff(double v) {
    if (v <= 0) return '--';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)} T';
    if (v >= 1e9)  return '${(v / 1e9).toStringAsFixed(2)} G';
    if (v >= 1e6)  return '${(v / 1e6).toStringAsFixed(2)} M';
    if (v >= 1e3)  return '${(v / 1e3).toStringAsFixed(1)} K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final s = widget.stats;
    final currentFreq = s?.frequency.toInt() ?? 0;
    final isChanged = selectedFreq != currentFreq && currentFreq > 0;

    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text(
          '⚡ ${widget.miner.name}',
          style: TextStyle(color: kc.text, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Hero stats bar ────────────────────────────────────────────
        if (s != null) ...[
          Row(children: [
            _HeroStat('FREQ', '${s.frequency.toInt()} MHz', KratosTheme.blue),
            SizedBox(width: 8),
            _HeroStat('HASHRATE', s.hashrateFormatted, kc.accent),
            SizedBox(width: 8),
            _HeroStat('TEMP', '${s.outTemp.toInt()}°C', _tempColor(s.outTemp)),
            SizedBox(width: 8),
            _HeroStat('BEST DIFF', _fmtBestDiff(s.bestShare), KratosTheme.orange),
          ]),
          SizedBox(height: 16),
        ],

        // ── Presets ───────────────────────────────────────────────────
        if (!_isAvalonQ) ...[
          _label('QUICK PRESETS'),
          SizedBox(height: 8),
          Row(children: presets.map((p) {
            final sel = selectedFreq == p.mhz;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => selectedFreq = p.mhz),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? p.color.withOpacity(0.15) : kc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? p.color : kc.line,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(children: [
                      Text(p.label,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800,
                              color: sel ? p.color : kc.muted,
                              letterSpacing: 0.5)),
                      SizedBox(height: 3),
                      Text('${p.mhz}', style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold,
                          color: sel ? p.color : kc.text,
                          fontFamily: 'Courier')),
                      Text('MHz', style: TextStyle(
                          fontSize: 8,
                          color: sel ? p.color.withOpacity(0.7) : kc.muted)),
                      SizedBox(height: 3),
                      Text(p.estimate, style: TextStyle(
                          fontSize: 8,
                          color: sel ? p.color.withOpacity(0.8) : kc.muted)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList()),
          SizedBox(height: 20),

          // ── Fine-tune slider ──────────────────────────────────────
          _label('FINE-TUNE FREQUENCY'),
          SizedBox(height: 4),
          Row(children: [
            Text('$selectedFreq MHz',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: isChanged ? KratosTheme.orange : kc.text,
                    fontFamily: 'Courier')),
            if (isChanged) ...[
              SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KratosTheme.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KratosTheme.orange.withOpacity(0.4)),
                ),
                child: Text('was $currentFreq MHz',
                    style: const TextStyle(fontSize: 11, color: KratosTheme.orange)),
              ),
            ],
          ]),
          SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: KratosTheme.orange,
              thumbColor: KratosTheme.orange,
              inactiveTrackColor: kc.line,
              overlayColor: KratosTheme.orange.withOpacity(0.15),
              valueIndicatorColor: KratosTheme.orange,
              valueIndicatorTextStyle:
                  const TextStyle(color: Colors.black, fontFamily: 'Courier'),
            ),
            child: Slider(
              value: selectedFreq.clamp(_freqMin, _freqMax).toDouble(),
              min: _freqMin.toDouble(),
              max: _freqMax.toDouble(),
              divisions: (_freqMax - _freqMin) ~/ 5,
              label: '$selectedFreq MHz',
              onChanged: (v) => setState(() => selectedFreq = v.round()),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$_freqMin MHz', style: TextStyle(fontSize: 10, color: kc.muted)),
            Text('$_freqMax MHz', style: TextStyle(fontSize: 10, color: kc.muted)),
          ]),
          SizedBox(height: 20),
        ],

        // ── Work mode (Avalon) ────────────────────────────────────────
        if (_isAvalonQ) ...[
          _label('WORK MODE'),
          SizedBox(height: 10),
          for (final m in [
            (0, Icons.eco_outlined, 'Eco Mode', 'Lower power, quiet', kc.accent),
            (1, Icons.balance, 'Normal', 'Balanced performance', KratosTheme.blue),
            (2, Icons.bolt, 'Performance', 'Max hashrate, more power', KratosTheme.red),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => workMode = m.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: workMode == m.$1 ? m.$5.withOpacity(0.08) : kc.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: workMode == m.$1 ? m.$5.withOpacity(0.4) : kc.line),
                  ),
                  child: Row(children: [
                    Icon(m.$2, color: m.$5, size: 22),
                    SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.$3, style: TextStyle(fontWeight: FontWeight.w600, color: kc.text)),
                      Text(m.$4, style: TextStyle(fontSize: 12, color: kc.muted)),
                    ])),
                    if (workMode == m.$1) Icon(Icons.check_circle, color: m.$5, size: 20),
                  ]),
                ),
              ),
            ),
          SizedBox(height: 20),
        ],

        // ── Fan speed (Avalon Q) ──────────────────────────────────────────
        if (_isAvalonQ) ...[
          _label('FAN SPEED'),
          SizedBox(height: 4),
          Row(children: [
            Text('$selectedFan%',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                    color: KratosTheme.blue, fontFamily: 'Courier')),
            SizedBox(width: 8),
            Text('(live: ${s?.fanPercent ?? 0}%)',
                style: TextStyle(fontSize: 11, color: kc.muted)),
          ]),
          SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: KratosTheme.blue,
              thumbColor: KratosTheme.blue,
              inactiveTrackColor: kc.line,
              overlayColor: KratosTheme.blue.withOpacity(0.15),
            ),
            child: Slider(
              value: selectedFan.toDouble(),
              min: 0, max: 100, divisions: 20,
              label: '$selectedFan%',
              onChanged: (v) => setState(() => selectedFan = v.round()),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Auto (0%)', style: TextStyle(fontSize: 10, color: kc.muted)),
            Text('100%',     style: TextStyle(fontSize: 10, color: kc.muted)),
          ]),
          SizedBox(height: 20),
        ],

        // ── Core voltage (ESP-Miner) ───────────────────────────────────
        if (_isEsp) ...[
          Row(children: [
            _label('CORE VOLTAGE'),
            const Spacer(),
            if (s?.coreVoltage != null && s!.coreVoltage > 0)
              Text('current: ${s.coreVoltage} mV',
                  style: TextStyle(fontSize: 11, color: kc.muted,
                      fontFamily: 'Courier')),
          ]),
          SizedBox(height: 10),
          Row(children: [
            for (final p in [(1100, 'ECO', kc.accent), (1150, 'STD', KratosTheme.blue),
                             (1200, 'OC', KratosTheme.orange), (1250, 'MAX', KratosTheme.red)])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() => selectedVoltage = p.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selectedVoltage == p.$1 ? p.$3.withOpacity(0.15) : kc.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selectedVoltage == p.$1 ? p.$3 : kc.line,
                            width: selectedVoltage == p.$1 ? 1.5 : 1),
                      ),
                      child: Column(children: [
                        Text(p.$2, style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800,
                            color: selectedVoltage == p.$1 ? p.$3 : kc.muted)),
                        SizedBox(height: 3),
                        Text('${p.$1}', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold,
                            color: selectedVoltage == p.$1 ? p.$3 : kc.text,
                            fontFamily: 'Courier')),
                        Text('mV', style: TextStyle(
                            fontSize: 8,
                            color: selectedVoltage == p.$1 ? p.$3.withOpacity(0.7) : kc.muted)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          SizedBox(height: 20),
        ],

        // ── Result ────────────────────────────────────────────────────
        if (result != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: result!.startsWith('✅')
                  ? kc.accent.withOpacity(0.07)
                  : KratosTheme.red.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: result!.startsWith('✅')
                    ? kc.accent.withOpacity(0.3)
                    : KratosTheme.red.withOpacity(0.3),
              ),
            ),
            child: Text(result!,
                style: TextStyle(
                    fontSize: 13,
                    color: result!.startsWith('✅') ? kc.accent : KratosTheme.red)),
          ),
          SizedBox(height: 12),
        ],

        // ── Apply button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: applying ? kc.line : KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: applying ? null : _apply,
            icon: applying
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                : Icon(Icons.bolt),
            label: Text(
              applying
                  ? 'Applying…'
                  : _isAvalonQ
                      ? 'Apply Work Mode'
                      : 'Apply  $selectedFreq MHz${_isEsp ? '  ·  ${selectedVoltage} mV' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),

        // ── Autotune ──────────────────────────────────────────────────
        if (_isEsp) ...[
          SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: KratosTheme.purple,
                side: BorderSide(color: KratosTheme.purple.withOpacity(0.4)),
                backgroundColor: KratosTheme.purple.withOpacity(0.07),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: applying ? null : _startAutotune,
              icon: Text('🤖', style: TextStyle(fontSize: 18)),
              label: Text('Autotune — find optimal settings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
        SizedBox(height: 32),
      ]),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: kc.muted, letterSpacing: 1.5));

  Color _tempColor(double t) {
    if (t > 75) return KratosTheme.red;
    if (t > 65) return KratosTheme.orange;
    return kc.accent;
  }

  void _startAutotune() {
    final defaultHint = (widget.stats?.frequency != null && widget.stats!.frequency > 0)
        ? widget.stats!.frequency.toInt()
        : ((_freqMin + _freqMax) ~/ 2);

    void openSheet() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AutotuneSheet(
          miner: widget.miner, freqMin: _freqMin, freqMax: _freqMax, defaultHint: defaultHint),
    );

    if (widget.miner.psuWatts == null) {
      showDialog<void>(context: context, builder: (dCtx) => AlertDialog(
        backgroundColor: kc.surface,
        title: Text('No PSU rating set',
            style: TextStyle(color: kc.text, fontSize: 16)),
        content: Text('⚠️ Autotune may exceed nominal power. Set PSU watts to enable the 90% safety cap.',
            style: TextStyle(color: kc.muted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () { Navigator.pop(dCtx); _showSetPsuDialog(); },
              child: Text('Set PSU', style: TextStyle(color: KratosTheme.orange))),
          TextButton(onPressed: () { Navigator.pop(dCtx); openSheet(); },
              child: Text('Continue Anyway', style: TextStyle(color: kc.muted))),
        ],
      ));
    } else {
      openSheet();
    }
  }

  void _showSetPsuDialog() {
    final ctrl = TextEditingController(text: widget.miner.psuWatts?.toString() ?? '');
    showDialog<void>(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: kc.surface,
      title: Text('PSU Rating (Watts)',
          style: TextStyle(color: kc.text, fontSize: 16)),
      content: TextField(
        controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
        style: TextStyle(color: kc.text),
        decoration: InputDecoration(hintText: 'e.g. 200',
            hintStyle: TextStyle(color: kc.muted), suffixText: 'W',
            suffixStyle: TextStyle(color: kc.muted)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
            child: Text('Cancel', style: TextStyle(color: kc.muted))),
        TextButton(onPressed: () {
          final w = int.tryParse(ctrl.text.trim());
          if (w != null && w > 0) {
            widget.miner.psuWatts = w;
            try { Provider.of<MinerStore>(context, listen: false).save(); } catch (_) {}
            Navigator.pop(dCtx); setState(() {});
          }
        }, child: Text('Save', style: TextStyle(color: KratosTheme.orange))),
      ],
    ));
  }

  Future<void> _apply() async {
    setState(() { applying = true; result = null; });
    bool ok;
    if (_isAvalonQ) {
      // Avalon Q / Mini 3 — workmode + optional fan via CGMiner ascset
      ok = await CGMinerAPI.instance.setWorkMode(
          widget.miner.ip, widget.miner.port, workMode,
          remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      if (selectedFan != (widget.stats?.fanPercent ?? -1)) {
        await CGMinerAPI.instance.setFanSpeed(
            widget.miner.ip, widget.miner.port, selectedFan,
            remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      }
    } else if (_isAvalonNano) {
      // Avalon Nano 3S / Nano 3 — frequency via HTTP PATCH /api/system
      ok = await AvalonAPI.instance.setFrequency(
          widget.miner.ip, widget.miner.port, selectedFreq,
          remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    } else if (_isEsp) {
      // BitAxe / NerdQaxe / NerdOctaxe — frequency + voltage via ESP-Miner HTTP
      ok = await EspMinerAPI.instance.setFrequency(
          widget.miner.ip, widget.miner.port, selectedFreq,
          remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      if (ok && selectedVoltage > 0) {
        await EspMinerAPI.instance.setCoreVoltage(
            widget.miner.ip, widget.miner.port, selectedVoltage,
            remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      }
    } else {
      // Other CGMiner devices
      ok = await CGMinerAPI.instance.setFrequency(
          widget.miner.ip, widget.miner.port, selectedFreq, remoteUrl: widget.miner.remoteUrl);
    }
    setState(() {
      applying = false;
      result = ok
          ? _isAvalonQ
              ? '✅ Work mode applied — miner updating in ~30s'
              : _isAvalonNano
                  ? '✅ Applied $selectedFreq MHz — miner restarting…'
                  : '✅ Applied $selectedFreq MHz · ${selectedVoltage} mV — miner restarting…'
          : '❌ Failed to apply. Check miner connection.';
    });
    if (ok) Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.pop(context); });
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _HeroStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
            color: color, fontFamily: 'Courier'), overflow: TextOverflow.ellipsis),
        SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 7, color: KratosColors.of(context).muted,
            letterSpacing: 0.8), overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

class _FreqPreset {
  final int mhz;
  final String label, estimate;
  final Color color;
  const _FreqPreset(this.mhz, this.label, this.estimate, this.color);
}

// ── Autotune sheet ────────────────────────────────────────────────────────────

class _AutotuneSheet extends StatefulWidget {
  final Miner miner;
  final int freqMin, freqMax, defaultHint;
  const _AutotuneSheet({required this.miner, required this.freqMin,
      required this.freqMax, required this.defaultHint});
  @override State<_AutotuneSheet> createState() => _AutotuneSheetState();
}

class _AutotuneSheetState extends State<_AutotuneSheet> {
  final _svc = AutotuneService.instance;
  final _logScrollCtrl = ScrollController();
  late int _hintFreq = widget.defaultHint;
  bool _started = false;
  bool _shareToCommunity = true;
  bool _submitted = false;
  OcSummary? _summary;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onUpdate);
    if (_svc.state == AutotuneState.running && _svc.activeMinerName == widget.miner.name) {
      _started = true;
    }
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final s = await OcCommunityService.instance.getSummary(widget.miner.type);
    if (mounted) setState(() => _summary = s);
  }

  Future<void> _start() async {
    setState(() => _started = true);
    await _svc.run(widget.miner, psuWatts: widget.miner.psuWatts, hintFreqMhz: _hintFreq);
    if (_svc.state == AutotuneState.done && _svc.result != null && _shareToCommunity && !_submitted) {
      _submitted = true;
      OcCommunityService.instance.submitResult(_svc.result!, widget.miner.type, '');
      _loadSummary();
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() { _svc.removeListener(_onUpdate); _logScrollCtrl.dispose(); super.dispose(); }

  Future<void> _applyResult() async {
    final r = _svc.result; if (r == null) return;
    await EspMinerAPI.instance.setFrequency(widget.miner.ip, widget.miner.port, r.optimalFreqMhz,
        remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    if (r.optimalVoltageMv > 0)
      await EspMinerAPI.instance.setCoreVoltage(widget.miner.ip, widget.miner.port, r.optimalVoltageMv,
          remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final state = _svc.state;
    final result = _svc.result;
    return DraggableScrollableSheet(
      initialChildSize: 0.65, maxChildSize: 0.92, minChildSize: 0.4, expand: false,
      builder: (_, sc) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        decoration: BoxDecoration(color: kc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: kc.line, borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Text('🤖', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Autotune', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kc.text)),
              Text('Sweep frequencies, find peak hashrate', style: TextStyle(fontSize: 11, color: kc.muted)),
            ])),
            if (state == AutotuneState.running)
              TextButton(onPressed: _svc.cancel,
                  child: Text('Cancel', style: TextStyle(color: KratosTheme.red)))
            else
              IconButton(icon: Icon(Icons.close, color: kc.muted, size: 20),
                  onPressed: () => Navigator.pop(context)),
          ]),
          SizedBox(height: 12),
          if (!_started) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kc.bg, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kc.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Starting hint', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: kc.muted, letterSpacing: 0.8)),
                  const Spacer(),
                  Text('$_hintFreq MHz', style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.bold, color: KratosTheme.purple, fontFamily: 'Courier')),
                ]),
                Slider(activeColor: KratosTheme.purple, inactiveColor: kc.line,
                    value: _hintFreq.clamp(widget.freqMin, widget.freqMax).toDouble(),
                    min: widget.freqMin.toDouble(), max: widget.freqMax.toDouble(),
                    divisions: (widget.freqMax - widget.freqMin) ~/ 5,
                    label: '$_hintFreq MHz',
                    onChanged: (v) => setState(() => _hintFreq = v.round())),
                Text('Narrows sweep ±40 MHz — ~10 min vs ~33 min full sweep',
                    style: TextStyle(fontSize: 10, color: kc.muted)),
                SizedBox(height: 10),
                Row(children: [
                  Switch(value: _shareToCommunity, activeColor: KratosTheme.purple,
                      onChanged: (v) => setState(() => _shareToCommunity = v)),
                  SizedBox(width: 6),
                  Expanded(child: Text('Share result to community OC database',
                      style: TextStyle(fontSize: 11, color: kc.muted))),
                ]),
                SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: KratosTheme.purple,
                      foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: _start,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Start Autotune', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ),
            if (_summary != null && _summary!.count > 0) ...[
              SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: KratosTheme.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: KratosTheme.blue.withOpacity(0.25))),
                child: Text('Community: avg ${_summary!.avgFreq.toStringAsFixed(0)} MHz · '
                    'best ${_summary!.bestFreq ?? 0} MHz · ${_summary!.count} results',
                    style: const TextStyle(fontSize: 11, color: KratosTheme.blue)),
              ),
            ],
            SizedBox(height: 12),
          ],
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state == AutotuneState.running ? _svc.progress
                  : state == AutotuneState.done ? 1.0 : null,
              backgroundColor: kc.line,
              valueColor: AlwaysStoppedAnimation(state == AutotuneState.done
                  ? kc.accent : state == AutotuneState.failed ? KratosTheme.red : KratosTheme.purple),
              minHeight: 6),
          ),
          SizedBox(height: 12),
          Expanded(child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kc.bg, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kc.line)),
            child: SingleChildScrollView(controller: _logScrollCtrl,
              child: Text(_svc.log.isEmpty ? 'Starting autotune…' : _svc.log,
                  style: TextStyle(fontSize: 11, color: kc.muted,
                      fontFamily: 'Courier', height: 1.5))),
          )),
          SizedBox(height: 12),
          if (result != null) ...[
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kc.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kc.accent.withOpacity(0.25))),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: kc.accent, size: 18),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(result.summary, style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.bold, color: kc.accent, fontFamily: 'Courier')),
                  Text('${result.efficiency.toStringAsFixed(1)} GH/W  ·  ${result.temperature.toInt()}°C',
                      style: TextStyle(fontSize: 11, color: kc.muted)),
                ])),
              ])),
            SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: KratosTheme.orange,
                  foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _applyResult,
              icon: Icon(Icons.bolt),
              label: Text('Apply These Settings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            )),
          ],
          if (state == AutotuneState.failed && result == null)
            SizedBox(width: double.infinity, child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: kc.muted,
                  side: BorderSide(color: kc.line.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () { _svc.reset(); _svc.run(widget.miner); },
              child: Text('Retry'),
            )),
        ]),
      ),
    );
  }
}
