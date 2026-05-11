import 'package:flutter/material.dart';

import '../models/miner.dart';
import '../services/benchmark_service.dart';
import '../services/esp_miner_api.dart';
import '../services/fluminer_api.dart';
import '../theme/volt_theme.dart';

class BenchmarkCard extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;

  const BenchmarkCard({
    super.key,
    required this.miner,
    required this.stats,
  });

  @override
  State<BenchmarkCard> createState() => _BenchmarkCardState();
}

class _BenchmarkCardState extends State<BenchmarkCard> {
  late Future<_BenchmarkCardData?> _future;
  bool _applying = false;

  String get _model {
    final statsModel = widget.stats?.model ?? '';
    return statsModel.isNotEmpty ? statsModel : widget.miner.type.displayName;
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant BenchmarkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldModel = oldWidget.stats?.model.isNotEmpty == true
        ? oldWidget.stats!.model
        : oldWidget.miner.type.displayName;
    if (oldModel != _model) _future = _load();
  }

  Future<_BenchmarkCardData?> _load() async {
    final service = BenchmarkService.instance;
    final stats = await service.getStats(_model);
    if (stats == null || stats.sampleCount <= 10) return null;
    final top = await service.getTopConfigs(_model);
    return _BenchmarkCardData(stats: stats, topConfigs: top);
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.stats;
    if (live == null) return const SizedBox.shrink();
    final kc = KratosColors.of(context);
    return FutureBuilder<_BenchmarkCardData?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _BenchmarkSkeleton(kc: kc);
        }
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final community = data.stats;
        final sweetSpot = data.topConfigs.isNotEmpty ? data.topConfigs.first : null;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kc.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kc.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.query_stats_rounded, color: kc.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Community Benchmark',
                      style: TextStyle(
                        color: kc.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_comma(community.sampleCount)} samples',
                    style: TextStyle(color: kc.muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CompareRow(
                label: 'Hashrate',
                value: _formatHashrate(live.hashrateDisplay),
                average: 'avg ${_formatHashrate(community.avgHashrateGh)}',
                delta: _delta(live.hashrateDisplay, community.avgHashrateGh,
                    higherIsBetter: true),
              ),
              const SizedBox(height: 8),
              _CompareRow(
                label: 'Efficiency',
                value: '${live.efficiency.toStringAsFixed(1)} J/TH',
                average:
                    'avg ${community.avgEfficiencyJTh.toStringAsFixed(1)}',
                delta: _delta(live.efficiency, community.avgEfficiencyJTh,
                    higherIsBetter: false),
              ),
              const SizedBox(height: 8),
              _CompareRow(
                label: 'Temp',
                value: live.outTemp > 0 ? '${live.outTemp.toInt()}°C' : '--',
                average: 'avg ${community.avgTempBoard.toStringAsFixed(0)}°C',
                delta: live.outTemp > 0 &&
                        community.avgTempBoard > 0 &&
                        live.outTemp <= community.avgTempBoard
                    ? 'OK'
                    : '',
              ),
              if (sweetSpot != null) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: kc.line),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${sweetSpot.badge.isNotEmpty ? sweetSpot.badge : '⭐ Sweet spot'}: '
                        '${sweetSpot.freqMhz}MHz/${sweetSpot.voltageMv}mV',
                        style: TextStyle(
                          color: kc.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_canApply(widget.miner)) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kc.accent,
                        foregroundColor: kc.bg,
                      ),
                      icon: _applying
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kc.bg,
                              ),
                            )
                          : const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(_applying
                          ? 'Applying...'
                          : 'Apply to this miner'),
                      onPressed:
                          _applying ? null : () => _applyConfig(sweetSpot),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  bool _canApply(Miner miner) {
    return miner.type.apiType == ApiType.espMinerHttp ||
        miner.type.apiType == ApiType.fluMinerHttp;
  }

  Future<void> _applyConfig(BenchmarkConfig config) async {
    setState(() => _applying = true);
    bool ok = false;
    if (widget.miner.type.apiType == ApiType.fluMinerHttp) {
      ok = await FluMinerAPI.instance.setFrequencyAndVoltage(
        widget.miner.ip,
        widget.miner.port,
        frequencyMHz: config.freqMhz,
        voltageMv: config.voltageMv,
      );
    } else if (widget.miner.type.apiType == ApiType.espMinerHttp) {
      ok = await EspMinerAPI.instance.setFrequency(
        widget.miner.ip,
        widget.miner.port,
        config.freqMhz,
        remoteUrl: widget.miner.remoteUrl,
        isRemote: widget.miner.isRemote,
      );
      if (ok && config.voltageMv > 0) {
        ok = await EspMinerAPI.instance.setCoreVoltage(
          widget.miner.ip,
          widget.miner.port,
          config.voltageMv,
          remoteUrl: widget.miner.remoteUrl,
          isRemote: widget.miner.isRemote,
        );
      }
    }
    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Benchmark config applied' : 'Apply failed')),
    );
  }

  String _delta(double current, double average, {required bool higherIsBetter}) {
    if (current <= 0 || average <= 0) return '';
    final pct = ((current - average) / average * 100).round();
    final good = higherIsBetter ? pct >= 0 : pct <= 0;
    final sign = pct > 0 ? '+' : '';
    return '$sign$pct%${good ? ' ↑' : ' ↓'}';
  }

  String _formatHashrate(double gh) {
    if (gh >= 1000) return '${(gh / 1000).toStringAsFixed(2)} TH/s';
    return '${gh.toStringAsFixed(0)} GH/s';
  }

  String _comma(int value) {
    final raw = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return out.toString();
  }
}

class _BenchmarkCardData {
  final BenchmarkModelStats stats;
  final List<BenchmarkConfig> topConfigs;

  const _BenchmarkCardData({required this.stats, required this.topConfigs});
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String value;
  final String average;
  final String delta;

  const _CompareRow({
    required this.label,
    required this.value,
    required this.average,
    required this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: TextStyle(color: kc.muted, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: kc.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Text(average, style: TextStyle(color: kc.muted, fontSize: 11)),
        if (delta.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            delta,
            style: TextStyle(
              color: delta.contains('-') ? KratosColors.danger : kc.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _BenchmarkSkeleton extends StatelessWidget {
  final KratosPalette kc;
  const _BenchmarkSkeleton({required this.kc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kc.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            Container(
              height: i == 0 ? 18 : 12,
              decoration: BoxDecoration(
                color: kc.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            if (i < 3) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
