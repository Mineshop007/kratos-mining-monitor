import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
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
  late List<_FreqPreset> presets;
  int selectedFreq = 0;
  int selectedVoltage = 0;
  double powerLimit = 760;
  int workMode = 1; // 0=eco, 1=normal, 2=performance
  bool applying = false;
  String? result;

  bool get _isEsp =>
      widget.miner.type.apiType == ApiType.espMinerHttp;

  // Resolved type (prefer live stats type — more accurate after API response)
  MinerType get _resolvedType => widget.stats?.type ?? widget.miner.type;

  // Avalon miners only expose Work Modes (Eco/Normal/Turbo) — no raw MHz control.
  // Frequency slider range is type-aware: NerdOctaxe/NerdQAxe++ rated to 750 MHz.
  int get _freqMin {
    switch (_resolvedType) {
      case MinerType.nerdqaxe:
      case MinerType.nerdoctaxe:
        return 350;
      default:
        return _isEsp ? 300 : 400;
    }
  }

  int get _freqMax {
    switch (_resolvedType) {
      case MinerType.nerdqaxe:
      case MinerType.nerdoctaxe:
        return 750;   // Rev6 / NerdOctaxe certified max
      case MinerType.bitaxeGamma:
        return 650;
      case MinerType.bitaxeUltra:
      case MinerType.bitaxeGT:
        return 650;
      default:
        return _isEsp ? 700 : 650;
    }
  }

  bool get _isAvalon {
    final t = widget.stats?.type ?? widget.miner.type;
    return t == MinerType.avalonNano3s ||
        t == MinerType.avalonNano3 ||
        t == MinerType.avalonMini3 ||
        t == MinerType.avalonQ;
  }

  @override
  void initState() {
    super.initState();
    _initPresets();
    if (widget.stats?.frequency != null && widget.stats!.frequency > 0) {
      final curr = widget.stats!.frequency;
      selectedFreq = presets
          .reduce(
              (a, b) => (a.mhz - curr).abs() < (b.mhz - curr).abs() ? a : b)
          .mhz;
    } else {
      selectedFreq = presets[1].mhz;
    }
    selectedVoltage = widget.stats?.coreVoltage ?? 0;
    if (selectedVoltage == 0) selectedVoltage = 1150; // default STD
  }

  void _initPresets() {
    final type = widget.stats?.type ?? widget.miner.type;
    presets = switch (type) {
      MinerType.avalonNano3s || MinerType.avalonNano3 => [
          _FreqPreset(528, 'ECO', '~5.2 TH/s'),
          _FreqPreset(546, 'STD', '~5.8 TH/s'),
          _FreqPreset(567, 'OC', '~6.1 TH/s'),
          _FreqPreset(588, 'MAX', '~6.5 TH/s'),
        ],
      MinerType.bitaxeGamma => [
          _FreqPreset(400, 'ECO', '~400 GH/s'),
          _FreqPreset(490, 'STD', '~490 GH/s'),
          _FreqPreset(550, 'OC', '~550 GH/s'),
          _FreqPreset(600, 'MAX', '~600 GH/s'),
        ],
      MinerType.bitaxeUltra => [
          _FreqPreset(450, 'ECO', '~500 GH/s'),
          _FreqPreset(525, 'STD', '~600 GH/s'),
          _FreqPreset(575, 'OC', '~700 GH/s'),
          _FreqPreset(625, 'MAX', '~800 GH/s'),
        ],
      MinerType.bitaxeGT => [
          _FreqPreset(475, 'ECO', '~700 GH/s'),
          _FreqPreset(550, 'STD', '~850 GH/s'),
          _FreqPreset(600, 'OC', '~950 GH/s'),
          _FreqPreset(650, 'MAX', '~1.1 TH/s'),
        ],
      MinerType.nerdqaxe => [
          _FreqPreset(450, 'ECO', '~2.6 TH/s'),
          _FreqPreset(530, 'STD', '~3.1 TH/s'),
          _FreqPreset(650, 'OC',  '~3.8 TH/s'),
          _FreqPreset(750, 'MAX', '~4.8 TH/s'),  // Rev6 certified 750 MHz
        ],
      MinerType.nerdoctaxe => [
          _FreqPreset(450, 'ECO', '~7.5 TH/s'),
          _FreqPreset(530, 'STD', '~9.2 TH/s'),
          _FreqPreset(650, 'OC',  '~11 TH/s'),
          _FreqPreset(750, 'MAX', '~12 TH/s'),   // NerdOctaxe certified 750 MHz
        ],
      _ => [
          _FreqPreset(400, 'ECO', 'Eco'),
          _FreqPreset(490, 'STD', 'Normal'),
          _FreqPreset(550, 'OC', 'OC'),
          _FreqPreset(600, 'MAX', 'Max'),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('OC Settings',
            style: TextStyle(color: KratosTheme.textPrim)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // API type badge
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _isEsp
                ? KratosTheme.orange.withOpacity(0.08)
                : KratosTheme.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _isEsp
                    ? KratosTheme.orange.withOpacity(0.3)
                    : KratosTheme.blue.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber,
                color: KratosTheme.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isEsp
                    ? 'ESP-Miner device — frequency via PATCH /api/system. Miner restarts automatically.'
                    : _isAvalon
                        ? 'Avalon miner — work mode change via CGMiner ascset. Takes effect immediately.'
                        : 'CGMiner device — overclocking via ascset commands.',
                style: const TextStyle(
                    fontSize: 12, color: KratosTheme.muted),
              ),
            ),
          ]),
        ),

        // Current stats
        if (widget.stats != null) ...[
          Row(children: [
            _MiniStat('CURRENT',
                '${widget.stats!.frequency.toInt()} MHz', KratosTheme.blue),
            const SizedBox(width: 8),
            _MiniStat('HASHRATE', widget.stats!.hashrateFormatted,
                KratosTheme.neon),
            const SizedBox(width: 8),
            _MiniStat('TEMP',
                '${widget.stats!.outTemp.toInt()}°C', KratosTheme.orange),
          ]),
          const SizedBox(height: 16),
        ],

        // Frequency selector — hidden for Avalon miners (work modes only)
        if (!_isAvalon) ...[         
        Row(children: [
          const Text('FREQUENCY',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KratosTheme.muted,
                  letterSpacing: 1.5)),
          const Spacer(),
          Text('$selectedFreq MHz',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: KratosTheme.orange,
                  fontFamily: 'Courier')),
        ]),
        const SizedBox(height: 4),
        // Continuous slider — user can dial any freq from min to max
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
            value: selectedFreq.clamp(_freqMin, _freqMax).toDouble(),
            min: _freqMin.toDouble(),
            max: _freqMax.toDouble(),
            divisions: (_freqMax - _freqMin) ~/ 5,  // 5 MHz steps
            label: '$selectedFreq MHz',
            onChanged: (v) => setState(() => selectedFreq = v.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$_freqMin MHz',
                style: const TextStyle(fontSize: 10, color: KratosTheme.muted)),
            Text('Default: ${widget.stats?.frequency.toInt() ?? selectedFreq} MHz',
                style: const TextStyle(fontSize: 10, color: KratosTheme.muted)),
            Text('$_freqMax MHz',
                style: const TextStyle(fontSize: 10, color: KratosTheme.muted)),
          ],
        ),
        const SizedBox(height: 20),
        ], // end if (!_isAvalon)

        // Voltage presets (ESP-Miner only)
        if (_isEsp) ...[
          const Text('CORE VOLTAGE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KratosTheme.muted,
                  letterSpacing: 1.5)),
          if (widget.stats?.coreVoltage != null && widget.stats!.coreVoltage > 0) ...[
            const SizedBox(height: 4),
            Text('Current: ${widget.stats!.coreVoltage} mV',
                style: const TextStyle(fontSize: 12, color: KratosTheme.muted, fontFamily: 'Courier')),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              for (final p in [
                (1100, 'ECO'),
                (1150, 'STD'),
                (1200, 'OC'),
                (1250, 'MAX'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () async {
                        setState(() => selectedVoltage = p.$1);
                        await EspMinerAPI.instance.setCoreVoltage(
                            widget.miner.ip, widget.miner.port, p.$1,
                            remoteUrl: widget.miner.remoteUrl);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selectedVoltage == p.$1
                              ? KratosTheme.orange
                              : KratosTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selectedVoltage == p.$1
                                  ? KratosTheme.orange
                                  : KratosTheme.border),
                        ),
                        child: Column(children: [
                          Text('${p.$1}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: selectedVoltage == p.$1
                                      ? Colors.black
                                      : KratosTheme.textPrim,
                                  fontFamily: 'Courier')),
                          Text('mV',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: selectedVoltage == p.$1
                                      ? Colors.black54
                                      : KratosTheme.muted)),
                          const SizedBox(height: 2),
                          Text(p.$2,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: selectedVoltage == p.$1
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
          const SizedBox(height: 20),
        ],

        // Work mode — Avalon only; ESP-Miner (NerdOctaxe/BitAxe) uses fan slider in detail screen
        if (_isAvalon) ...[        
        const Text('WORK MODE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KratosTheme.muted,
                letterSpacing: 1.5)),
        const SizedBox(height: 10),
        ...[
          (0, Icons.eco_outlined, 'Eco Mode', 'Lower power, quieter fans',
              const Color(0xFF3FB950)),
          (1, Icons.balance, 'Normal', 'Balanced performance',
              KratosTheme.orange),
          (2, Icons.bolt, 'Performance', 'Maximum hashrate, higher power',
              KratosTheme.red),
        ].map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => workMode = m.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: workMode == m.$1
                        ? m.$5.withOpacity(0.08)
                        : KratosTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: workMode == m.$1
                            ? m.$5.withOpacity(0.4)
                            : KratosTheme.border),
                  ),
                  child: Row(children: [
                    Icon(m.$2, color: m.$5, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(m.$3,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: KratosTheme.textPrim)),
                          Text(m.$4,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: KratosTheme.muted)),
                        ])),
                    if (workMode == m.$1)
                      Icon(Icons.check_circle, color: m.$5, size: 20),
                  ]),
                ),
              ),
            )),
        const SizedBox(height: 24),
        ], // end if (_isAvalon) work mode

        if (result != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(8)),
            child: Text(result!,
                style: TextStyle(
                    fontSize: 13,
                    color: result!.startsWith('✅')
                        ? KratosTheme.neon
                        : KratosTheme.red)),
          ),
          const SizedBox(height: 12),
        ],

        // Apply button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  applying ? KratosTheme.border : KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: applying ? null : _apply,
            icon: applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black54))
                : const Icon(Icons.bolt),
            label: Text(applying ? 'Applying...' : 'Apply OC Settings',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),

        // Autotune button — ESP-Miner devices only
        if (_isEsp) ...[          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: KratosTheme.purple,
                side: BorderSide(
                    color: KratosTheme.purple.withOpacity(0.4)),
                backgroundColor: KratosTheme.purple.withOpacity(0.07),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: applying ? null : _startAutotune,
              icon: const Text('🤖',
                  style: TextStyle(fontSize: 18)),
              label: const Text('Autotune',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }

  void _startAutotune() {
    final m = widget.miner;
    void openSheet() {
      // Default hint = current freq if known, else midpoint
      final defaultHint = (widget.stats?.frequency != null && widget.stats!.frequency > 0)
          ? widget.stats!.frequency.toInt()
          : ((_freqMin + _freqMax) ~/ 2);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: KratosTheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _AutotuneSheet(
          miner: m,
          freqMin: _freqMin,
          freqMax: _freqMax,
          defaultHint: defaultHint,
        ),
      );
    }

    if (m.psuWatts == null) {
      showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: KratosTheme.surface,
          title: const Text('No PSU rating set',
              style: TextStyle(color: KratosTheme.textPrim, fontSize: 16)),
          content: const Text(
            '⚠️ Autotune may exceed nominal power. Set PSU watts to enable the 90% safety cap, or continue without protection.',
            style: TextStyle(color: KratosTheme.muted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _showSetPsuDialog();
              },
              child: const Text('Set PSU',
                  style: TextStyle(color: KratosTheme.orange)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dCtx);
                openSheet();
              },
              child: const Text('Continue Anyway',
                  style: TextStyle(color: KratosTheme.muted)),
            ),
          ],
        ),
      );
    } else {
      openSheet();
    }
  }

  void _showSetPsuDialog() {
    final ctrl = TextEditingController(
        text: widget.miner.psuWatts?.toString() ?? '');
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: KratosTheme.surface,
        title: const Text('PSU Rating (Watts)',
            style: TextStyle(color: KratosTheme.textPrim, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: KratosTheme.textPrim),
          decoration: const InputDecoration(
            hintText: 'e.g. 200',
            hintStyle: TextStyle(color: KratosTheme.muted),
            suffixText: 'W',
            suffixStyle: TextStyle(color: KratosTheme.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel',
                style: TextStyle(color: KratosTheme.muted)),
          ),
          TextButton(
            onPressed: () {
              final w = int.tryParse(ctrl.text.trim());
              if (w != null && w > 0) {
                widget.miner.psuWatts = w;
                // Persist via MinerStore if available in tree
                try {
                  Provider.of<MinerStore>(context, listen: false).save();
                } catch (_) {}
                Navigator.pop(dCtx);
                setState(() {});
              }
            },
            child: const Text('Save',
                style: TextStyle(color: KratosTheme.orange)),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    setState(() {
      applying = true;
      result = null;
    });
    bool ok;

    if (_isAvalon) {
      // Avalon: only send work mode, no raw MHz (matches stock Avalon app)
      ok = await CGMinerAPI.instance
          .setWorkMode(widget.miner.ip, widget.miner.port, workMode, remoteUrl: widget.miner.remoteUrl);
    } else if (_isEsp) {
      // ESP-Miner (NerdOctaxe/BitAxe): frequency + voltage only.
      // Fan is controlled separately from the miner detail screen.
      ok = await EspMinerAPI.instance
          .setFrequency(widget.miner.ip, widget.miner.port, selectedFreq,
              remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      // Also apply voltage if changed from default
      if (ok && selectedVoltage > 0) {
        await EspMinerAPI.instance
            .setCoreVoltage(widget.miner.ip, widget.miner.port, selectedVoltage,
                remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
      }
    } else {
      // Generic CGMiner device: frequency + fan
      const fanPctGeneric = 70;
      ok = await CGMinerAPI.instance
          .setFrequency(widget.miner.ip, widget.miner.port, selectedFreq, remoteUrl: widget.miner.remoteUrl);
      await CGMinerAPI.instance
          .setFanSpeed(widget.miner.ip, widget.miner.port, fanPctGeneric, remoteUrl: widget.miner.remoteUrl);
    }

    final modeNames = ['Eco', 'Normal', 'Performance'];
    setState(() {
      applying = false;
      result = ok
          ? _isAvalon
              ? '✅ Work mode set to ${modeNames[workMode]} — updating in ~30s'
              : '✅ Applied $selectedFreq MHz — updating in ~30s'
          : '❌ Failed to apply. Check miner connection.';
    });
    if (ok) {
      await Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }
}

class _FreqPreset {
  final int mhz;
  final String label;
  final String estimate;
  const _FreqPreset(this.mhz, this.label, this.estimate);
}

// ── Autotune progress bottom sheet ──────────────────────────────────────────

class _AutotuneSheet extends StatefulWidget {
  final Miner miner;
  final int freqMin;
  final int freqMax;
  final int defaultHint;
  const _AutotuneSheet({
    required this.miner,
    required this.freqMin,
    required this.freqMax,
    required this.defaultHint,
  });

  @override
  State<_AutotuneSheet> createState() => _AutotuneSheetState();
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
    // If autotune is already running for this miner, don't restart it
    if (_svc.state == AutotuneState.running &&
        _svc.activeMinerName == widget.miner.name) {
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
    await _svc.run(
      widget.miner,
      psuWatts: widget.miner.psuWatts,
      hintFreqMhz: _hintFreq,
    );
    // After done, optionally submit
    if (_svc.state == AutotuneState.done &&
        _svc.result != null &&
        _shareToCommunity &&
        !_submitted) {
      _submitted = true;
      OcCommunityService.instance.submitResult(
        _svc.result!,
        widget.miner.type,
        '', // firmware unknown here
      );
      _loadSummary();
    }
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
      // Auto-scroll log to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollCtrl.hasClients) {
          _logScrollCtrl.animateTo(
            _logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onUpdate);
    // Singleton — don't dispose
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyResult() async {
    final r = _svc.result;
    if (r == null) return;
    await EspMinerAPI.instance.setFrequency(
      widget.miner.ip, widget.miner.port, r.optimalFreqMhz,
      remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    if (r.optimalVoltageMv > 0) {
      await EspMinerAPI.instance.setCoreVoltage(
        widget.miner.ip, widget.miner.port, r.optimalVoltageMv,
        remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = _svc.state;
    final result = _svc.result;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        decoration: const BoxDecoration(
          color: KratosTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: KratosTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Row(children: [
            const Text('🤖',
                style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Autotune',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: KratosTheme.textPrim)),
                  Text('Sweep frequencies, find peak hashrate',
                      style: TextStyle(
                          fontSize: 11, color: KratosTheme.muted)),
                ],
              ),
            ),
            if (state == AutotuneState.running)
              TextButton(
                onPressed: _svc.cancel,
                child: const Text('Cancel',
                    style: TextStyle(color: KratosTheme.red)),
              ),
            if (state != AutotuneState.running)
              IconButton(
                icon: const Icon(Icons.close,
                    color: KratosTheme.muted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
          ]),
          const SizedBox(height: 12),

          // ── Pre-start: hint slider ────────────────────────────────
          if (!_started) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KratosTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KratosTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Starting hint',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: KratosTheme.muted,
                            letterSpacing: 0.8)),
                    const Spacer(),
                    Text('$_hintFreq MHz',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: KratosTheme.purple,
                            fontFamily: 'Courier')),
                  ]),
                  Slider(
                    activeColor: KratosTheme.purple,
                    inactiveColor: KratosTheme.border,
                    value: _hintFreq
                        .clamp(widget.freqMin, widget.freqMax)
                        .toDouble(),
                    min: widget.freqMin.toDouble(),
                    max: widget.freqMax.toDouble(),
                    divisions: (widget.freqMax - widget.freqMin) ~/ 5,
                    label: '$_hintFreq MHz',
                    onChanged: (v) =>
                        setState(() => _hintFreq = v.round()),
                  ),
                  const Text(
                    'Narrows sweep to ±40 MHz, ~10 min vs ~33 min',
                    style: TextStyle(
                        fontSize: 10, color: KratosTheme.muted),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Switch(
                      value: _shareToCommunity,
                      activeColor: KratosTheme.purple,
                      onChanged: (v) =>
                          setState(() => _shareToCommunity = v),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Share result to community OC database',
                        style: TextStyle(
                            fontSize: 11, color: KratosTheme.muted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: KratosTheme.purple,
                        foregroundColor: Colors.black,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Autotune',
                          style: TextStyle(
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            if (_summary != null && _summary!.count > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KratosTheme.blue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: KratosTheme.blue.withOpacity(0.25)),
                ),
                child: Text(
                  'Community results for ${widget.miner.type.displayName}: '
                  'avg ${_summary!.avgFreq.toStringAsFixed(0)} MHz · '
                  'best ${(_summary!.bestFreq ?? 0)} MHz · '
                  '${_summary!.count} results',
                  style: const TextStyle(
                      fontSize: 11, color: KratosTheme.blue),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state == AutotuneState.running
                  ? _svc.progress
                  : (state == AutotuneState.done ? 1.0 : null),
              backgroundColor: KratosTheme.border,
              valueColor: AlwaysStoppedAnimation(
                state == AutotuneState.done
                    ? KratosTheme.neon
                    : state == AutotuneState.failed
                        ? KratosTheme.red
                        : KratosTheme.purple,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),

          // Log output
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KratosTheme.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KratosTheme.border),
              ),
              child: SingleChildScrollView(
                controller: _logScrollCtrl,
                child: Text(
                  _svc.log.isEmpty
                      ? 'Starting autotune...'
                      : _svc.log,
                  style: const TextStyle(
                      fontSize: 11,
                      color: KratosTheme.muted,
                      fontFamily: 'Courier',
                      height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Result card (done state)
          if (result != null) ...[            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KratosTheme.neon.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: KratosTheme.neon.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    color: KratosTheme.neon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.summary,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: KratosTheme.neon,
                              fontFamily: 'Courier')),
                      Text(
                        '${result.efficiency.toStringAsFixed(1)} GH/W  ·  '                        '${result.temperature.toInt()}°C',
                        style: const TextStyle(
                            fontSize: 11, color: KratosTheme.muted),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KratosTheme.orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _applyResult,
                icon: const Icon(Icons.bolt),
                label: const Text('Apply These Settings',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],

          if (state == AutotuneState.failed && result == null) ...[            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KratosTheme.muted,
                  side: BorderSide(
                      color: KratosTheme.border.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  _svc.reset();
                  _svc.run(widget.miner);
                },
                child: const Text('Retry'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: KratosTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KratosTheme.border)),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'Courier')),
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: KratosTheme.muted,
                    letterSpacing: 1)),
          ]),
        ),
      );
}
