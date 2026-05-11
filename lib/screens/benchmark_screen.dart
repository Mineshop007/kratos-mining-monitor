import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../services/benchmark_service.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  KratosPalette get kc => KratosColors.of(context);

  String? _selectedModel;
  BenchmarkModelStats? _stats;
  List<BenchmarkConfig> _topConfigs = [];
  List<BenchmarkDeviceModel> _models = [];
  BenchmarkGlobalStats? _globalStats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = BenchmarkService.instance;
    final models = await svc.getModels();
    final global = await svc.getGlobalStats();
    setState(() {
      _models = models;
      _globalStats = global;
      if (models.isNotEmpty && _selectedModel == null) {
        _selectedModel = models.first.model;
      }
      _loading = false;
    });
    if (_selectedModel != null) await _loadModel(_selectedModel!);
  }

  Future<void> _loadModel(String model) async {
    setState(() { _loading = true; });
    final svc = BenchmarkService.instance;
    final stats = await svc.getStats(model);
    final top = await svc.getTopConfigs(model);
    setState(() {
      _stats = stats;
      _topConfigs = top;
      _selectedModel = model;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('Community Benchmarks',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
        leading: BackButton(color: kc.muted),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: kc.muted, size: 22),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading && _models.isEmpty
          ? Center(child: CircularProgressIndicator(color: kc.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Global stats
                if (_globalStats != null) _GlobalStatsBar(stats: _globalStats!),
                const SizedBox(height: 16),

                // Model selector
                if (_models.isNotEmpty) ...[
                  Text('DEVICE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: kc.muted, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _models.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = _models[i];
                        final selected = m.model == _selectedModel;
                        return GestureDetector(
                          onTap: () => _loadModel(m.model),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? kc.accent.withValues(alpha: 0.15) : kc.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                  color: selected ? kc.accent : kc.line,
                                  width: selected ? 1.5 : 1),
                            ),
                            child: Text(m.model,
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: selected ? kc.accent : kc.muted)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Community stats
                if (_stats != null && !_loading) ...[
                  _CommunityStatsCard(stats: _stats!),
                  const SizedBox(height: 16),
                  Text('TOP CONFIGS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: kc.muted, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  ..._topConfigs.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ConfigRow(config: c),
                  )),
                ] else if (_loading) ...[
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )),
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Global stats bar ──────────────────────────────────────────────────────────

class _GlobalStatsBar extends StatelessWidget {
  final BenchmarkGlobalStats stats;
  const _GlobalStatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kc.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat('${stats.totalSamples}', 'samples', kc),
          _Divider(kc),
          _Stat('${stats.totalDevices}', 'devices', kc),
          _Divider(kc),
          _Stat('${stats.modelCount}', 'models', kc),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final KratosPalette kc;
  const _Stat(this.value, this.label, this.kc);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kc.accent, fontFamily: 'Courier')),
    Text(label, style: TextStyle(fontSize: 10, color: kc.muted)),
  ]);
}

class _Divider extends StatelessWidget {
  final KratosPalette kc;
  const _Divider(this.kc);
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 32, color: kc.line);
}

// ── Community stats card ──────────────────────────────────────────────────────

class _CommunityStatsCard extends StatelessWidget {
  final BenchmarkModelStats stats;
  const _CommunityStatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final hashTH = stats.avgHashrateGh / 1000;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kc.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(stats.model,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kc.text)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kc.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${stats.sampleCount} samples',
                style: TextStyle(fontSize: 11, color: kc.accent, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        _Row('Avg Hashrate', '${hashTH.toStringAsFixed(2)} TH/s', kc),
        _Row('Avg Efficiency', '${stats.avgEfficiencyJTh.toStringAsFixed(1)} J/TH', kc),
        _Row('Avg Power', '${stats.avgPowerW.toStringAsFixed(0)} W', kc),
        _Row('Avg Temp (board)', '${stats.avgTempBoard.toStringAsFixed(0)}°C', kc),
        _Row('Avg Stability', '${stats.avgStabilityPct.toStringAsFixed(1)}%', kc),
        if (stats.topFreqMhz > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kc.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kc.accent.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Text('⭐', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text('Community sweet spot: ${stats.topFreqMhz} MHz / ${stats.topVoltageMv} mV',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kc.accent)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final KratosPalette kc;
  const _Row(this.label, this.value, this.kc);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 13, color: kc.muted)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: kc.text, fontFamily: 'Courier')),
    ]),
  );
}

// ── Config row ────────────────────────────────────────────────────────────────

class _ConfigRow extends StatelessWidget {
  final BenchmarkConfig config;
  const _ConfigRow({required this.config});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final hasBadge = config.badge.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasBadge ? kc.accent.withValues(alpha: 0.06) : kc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: hasBadge ? kc.accent.withValues(alpha: 0.3) : kc.line,
            width: hasBadge ? 1.5 : 1),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasBadge)
            Text(config.badge,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kc.accent)),
          Text('${config.freqMhz} MHz / ${config.voltageMv} mV',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kc.text,
                  fontFamily: 'Courier')),
          Text('${config.sampleCount} samples  ·  ${config.avgStabilityPct.toStringAsFixed(1)}% stable',
              style: TextStyle(fontSize: 11, color: kc.muted)),
        ]),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(config.avgHashrateGh / 1000).toStringAsFixed(2)} TH/s',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: kc.text, fontFamily: 'Courier')),
          Text('${config.avgEfficiencyJTh.toStringAsFixed(1)} J/TH',
              style: TextStyle(fontSize: 11, color: kc.muted)),
        ]),
      ]),
    );
  }
}
