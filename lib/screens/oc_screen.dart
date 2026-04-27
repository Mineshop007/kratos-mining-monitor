import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';

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
  double powerLimit = 760;
  int workMode = 1; // 0=eco, 1=normal, 2=performance
  bool applying = false;
  String? result;

  bool get _isEsp =>
      widget.miner.type.apiType == ApiType.espMinerHttp;

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
          _FreqPreset(490, 'ECO', '~2.8 TH/s'),
          _FreqPreset(530, 'STD', '~3.1 TH/s'),
          _FreqPreset(560, 'OC', '~3.4 TH/s'),
          _FreqPreset(590, 'MAX', '~3.7 TH/s'),
        ],
      MinerType.nerdoctaxe => [
          _FreqPreset(490, 'ECO', '~8.5 TH/s'),
          _FreqPreset(530, 'STD', '~9.6 TH/s'),
          _FreqPreset(560, 'OC', '~10.2 TH/s'),
          _FreqPreset(590, 'MAX', '~11 TH/s'),
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

        // Frequency selector
        const Text('FREQUENCY',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KratosTheme.muted,
                letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(
          children: presets
              .map((p) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => selectedFreq = p.mhz),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selectedFreq == p.mhz
                                ? KratosTheme.orange
                                : KratosTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: selectedFreq == p.mhz
                                    ? KratosTheme.orange
                                    : KratosTheme.border),
                          ),
                          child: Column(children: [
                            Text('${p.mhz}',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: selectedFreq == p.mhz
                                        ? Colors.black
                                        : KratosTheme.textPrim,
                                    fontFamily: 'Courier')),
                            Text('MHz',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: selectedFreq == p.mhz
                                        ? Colors.black54
                                        : KratosTheme.muted)),
                            const SizedBox(height: 2),
                            Text(p.label,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: selectedFreq == p.mhz
                                        ? Colors.black54
                                        : KratosTheme.muted,
                                    letterSpacing: 0.5)),
                          ]),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Est. ${presets.firstWhere((p) => p.mhz == selectedFreq, orElse: () => presets[1]).estimate}',
            style: const TextStyle(
                fontSize: 13,
                color: KratosTheme.neon,
                fontFamily: 'Courier'),
          ),
        ),
        const SizedBox(height: 20),

        // Work mode (fan speed)
        const Text('FAN / WORK MODE',
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
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _apply() async {
    setState(() {
      applying = true;
      result = null;
    });
    final fanPct =
        workMode == 0 ? 50 : workMode == 2 ? 100 : 70;
    bool ok;

    if (_isEsp) {
      ok = await EspMinerAPI.instance
          .setFrequency(widget.miner.ip, widget.miner.port, selectedFreq);
      if (ok) {
        await EspMinerAPI.instance
            .setFanSpeed(widget.miner.ip, widget.miner.port, fanPct);
      }
    } else {
      ok = await CGMinerAPI.instance
          .setFrequency(widget.miner.ip, widget.miner.port, selectedFreq);
      await CGMinerAPI.instance
          .setFanSpeed(widget.miner.ip, widget.miner.port, fanPct);
    }

    setState(() {
      applying = false;
      result = ok
          ? '✅ Applied $selectedFreq MHz — updating in ~30s'
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
