import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/miner_store.dart';
import '../services/history_service.dart';
import 'pool_editor_screen.dart';
import 'oc_screen.dart';
import 'schedule_screen.dart';
import '../services/schedule_service.dart';

class MinerDetailScreen extends StatelessWidget {
  final Miner miner;
  const MinerDetailScreen({super.key, required this.miner});

  Future<bool> _restart() async {
    if (miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.restart(miner.ip, miner.port,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
    }
    return CGMinerAPI.instance.restart(miner.ip, miner.port, remoteUrl: miner.remoteUrl);
  }

  Future<bool> _pause() async {
    if (miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.pause(miner.ip, miner.port,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
    }
    return false;
  }

  Future<bool> _resume() async {
    if (miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.resume(miner.ip, miner.port,
          remoteUrl: miner.remoteUrl, isRemote: miner.isRemote);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final s = store.stats[miner.id];
      return Scaffold(
        backgroundColor: KratosColors.of(context).bg,
        appBar: AppBar(
          backgroundColor: KratosColors.of(context).bg,
          title: Row(children: [
            Expanded(
              child: Text(miner.name,
                  style: TextStyle(color: KratosColors.of(context).text),
                  overflow: TextOverflow.ellipsis),
            ),
            if (miner.isRemote) ...[const SizedBox(width: 6), _RemoteBadge()],
          ]),
          actions: [
            IconButton(
              icon: Icon(Icons.edit_outlined, color: KratosColors.of(context).muted),
              tooltip: 'Edit miner',
              onPressed: () => _showEditSheet(context, miner, store),
            ),
            IconButton(
              icon: Icon(Icons.refresh, color: KratosColors.of(context).muted),
              onPressed: () => store.refreshOne(miner),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero hashrate
            _HashrateHero(stats: s),
            const SizedBox(height: 12),

            // Persisted hashrate history with timeframe selector.
            _SectionLabel('HASHRATE HISTORY'),
            const SizedBox(height: 8),
            _HashrateChart(minerId: miner.id),
            const SizedBox(height: 16),

            // Stats grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _StatCard(
                  'OUTLET TEMP',
                  s?.outTemp != null && s!.outTemp > 0 ? '${s.outTemp.toInt()}°C' : '--',
                  Icons.thermostat,
                  _tempColor(s?.outTemp ?? 0),
                  onTap: s != null ? () => _showTempInfo(context, s.outTemp) : null,
                ),
                _StatCard(
                  'FAN',
                  s?.fanRPM != null && s!.fanRPM > 0
                      ? '${s.fanRPM} RPM'
                      : (s?.fanPercent != null && s!.fanPercent > 0 ? '${s.fanPercent}%' : '--'),
                  Icons.air,
                  KratosTheme.blue,
                  onTap: miner.type.apiType == ApiType.espMinerHttp && s != null
                      ? () => _showFanSheet(context, miner, s.fanPercent)
                      : null,
                ),
                _StatCard(
                  'ACCEPTED',
                  '${s?.accepted ?? 0}',
                  Icons.check_circle,
                  const Color(0xFF3FB950),
                  onTap: s != null ? () => _showShareStats(context, s.accepted, s.rejected) : null,
                ),
                _StatCard(
                  'REJECTED',
                  '${s?.rejected ?? 0}',
                  Icons.cancel,
                  (s?.rejected ?? 0) > 0 ? KratosTheme.red : KratosColors.of(context).muted,
                  onTap: s != null ? () => _showShareStats(context, s.accepted, s.rejected) : null,
                ),
                _StatCard(
                  'HW ERRORS',
                  '${s?.hardwareErrors ?? 0}',
                  Icons.warning_amber,
                  (s?.hardwareErrors ?? 0) > 0 ? KratosTheme.red : KratosColors.of(context).muted,
                  onTap: () => _showHwErrorInfo(context, s?.hardwareErrors ?? 0),
                ),
                _StatCard(
                  'UPTIME',
                  s?.uptimeFormatted ?? '--',
                  Icons.access_time,
                  KratosTheme.purple,
                  onTap: s != null ? () => _showUptimeInfo(context, s.uptime) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fan speed control (ESP-Miner only)
            if (miner.type.apiType == ApiType.espMinerHttp && s != null) ...[
              _FanSpeedControl(miner: miner, initialFanPercent: s.fanPercent),
              const SizedBox(height: 12),
            ],

            // Block ETA
            if (s != null && s.hashrateAvg > 0) ...[
              _BlockEtaRow(hashrateGhs: s.hashrateAvg),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 4),

            // Power + earnings row
            if ((s?.powerDraw ?? 0) > 0) ...[
              Row(children: [
                Expanded(
                  child: _InfoCard(
                    'POWER',
                    '${s!.powerDraw.toInt()} W',
                    icon: Icons.bolt,
                    color: KratosTheme.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    'EFFICIENCY',
                    '${s.efficiency.toStringAsFixed(1)} J/TH',
                    icon: Icons.speed,
                    color: KratosTheme.blue,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
            ],

            // Earnings & cost
            if (store.btcPrice > 0) ...[
              Row(children: [
                Expanded(
                  child: _InfoCard(
                    'EARN/DAY',
                    '\$${store.minerDailyEarningsUsd(miner.id).toStringAsFixed(3)}',
                    icon: Icons.attach_money,
                    color: const Color(0xFF39d353),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    'COST/DAY',
                    '\$${store.minerDailyCostUsd(miner.id).toStringAsFixed(3)}',
                    icon: Icons.electric_bolt,
                    color: KratosTheme.red,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              _NetProfitRow(store: store, minerId: miner.id),
              const SizedBox(height: 16),
            ],

            // Best share
            if ((s?.bestShare ?? 0) > 0) ...[
              _InfoCard('BEST SHARE', s!.bestShare.toStringAsFixed(0),
                  icon: Icons.emoji_events, color: KratosTheme.orange),
              const SizedBox(height: 12),
            ],

            // Pools
            if (s != null && s.pools.isNotEmpty) ...[
              _SectionLabel('POOLS'),
              const SizedBox(height: 8),
              ...s.pools.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PoolRow(pool: p),
                  )),
              const SizedBox(height: 8),
            ],

            // Device info
            _SectionLabel('DEVICE INFO'),
            const SizedBox(height: 8),
            _InfoRow('Model',
                s?.model.isNotEmpty == true ? s!.model : 'Unknown'),
            _InfoRow('Firmware',
                s?.firmware.isNotEmpty == true ? s!.firmware : 'Unknown'),
            _InfoRow('Type', miner.type.displayName),
            _InfoRow('API',
                miner.type.apiType == ApiType.espMinerHttp
                    ? 'ESP-Miner HTTP'
                    : 'CGMiner TCP'),
            _InfoRow('IP Address', miner.ip, copyable: true),
            _InfoRow('Port', '${miner.port}', copyable: true),
            if ((s?.frequency ?? 0) > 0)
              _InfoRow(
                  'Frequency', '${s!.frequency.toInt()} MHz'),
            const SizedBox(height: 20),

            // Actions
            _SectionLabel('ACTIONS'),
            const SizedBox(height: 8),
            _ActionBtn(
              'Configure Pools',
              Icons.dns,
              KratosTheme.orange,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PoolEditorScreen(
                    miner: miner,
                    currentPools: s?.pools ?? [],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ActionBtn(
              'OC Settings',
              Icons.bolt,
              KratosTheme.purple,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OCScreen(miner: miner, stats: s),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Avalon Q / Mini 3 extras: standby, wake, schedule
            if (miner.type == MinerType.avalonQ ||
                miner.type == MinerType.avalonMini3) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _ActionBtn(
                  s?.isStandby == true ? 'Wake Up' : 'Standby',
                  s?.isStandby == true ? Icons.wb_sunny_outlined : Icons.bedtime_outlined,
                  s?.isStandby == true ? Colors.amber : Colors.orange,
                  () => s?.isStandby == true
                      ? _confirmAction(context, 'Wake Up',
                          () => CGMinerAPI.instance.softOn(miner.ip, miner.port,
                              remoteUrl: miner.remoteUrl, isRemote: miner.isRemote))
                      : _confirmAction(context, 'Standby',
                          () => CGMinerAPI.instance.softOff(miner.ip, miner.port,
                              remoteUrl: miner.remoteUrl, isRemote: miner.isRemote)),
                )),
                const SizedBox(width: 8),
                Expanded(child: _ActionBtn(
                  'Schedule',
                  Icons.schedule,
                  const Color(0xFF9C27B0),
                  () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ScheduleScreen(miner: miner))),
                )),
              ]),
            ],
            _ActionBtn('Restart Miner', Icons.restart_alt, KratosTheme.red,
                () => _confirmRestart(context)),
            if (miner.type.apiType == ApiType.espMinerHttp) ...[
              const SizedBox(height: 8),
              _ActionBtn(
                'Pause Mining',
                Icons.pause_circle_outline,
                KratosColors.of(context).muted,
                () => _confirmAction(context, 'Pause', _pause),
              ),
              const SizedBox(height: 8),
              _ActionBtn(
                'Resume Mining',
                Icons.play_circle_outline,
                KratosColors.of(context).accent,
                () => _confirmAction(context, 'Resume', _resume),
              ),
            ],
            const SizedBox(height: 20),

            // Community
            _SectionLabel('COMMUNITY'),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5865F2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => launchUrl(
                  Uri.parse('https://discord.gg/yWtYegkDJw'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text(
                    'Join Discord — Report Bugs & Suggest Features',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      );
    });
  }

  void _confirmRestart(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: KratosColors.of(ctx).surface,
        title: Text('Restart Miner?',
            style: TextStyle(color: KratosColors.of(ctx).text)),
        content: Text(
          'Restart ${miner.name}? It will be offline for ~60 seconds.',
          style: TextStyle(color: KratosColors.of(ctx).muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: KratosColors.of(ctx).muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: KratosTheme.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _restart();
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Restart sent — back online in ~60s'
                      : 'Restart failed'),
                  backgroundColor: KratosColors.of(ctx).surface,
                ));
              }
            },
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  void _confirmAction(
      BuildContext ctx, String label, Future<bool> Function() fn) async {
    final ok = await fn();
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(ok ? '$label sent' : '$label failed'),
        backgroundColor: KratosColors.of(ctx).surface,
      ));
    }
  }

  Color _tempColor(double t) {
    if (t > 85) return KratosTheme.red;
    if (t > 75) return KratosTheme.orange;
    return KratosColors.muted;
  }
}

// ── Hashrate chart ────────────────────────────────────────────────────────────

class _HashrateChart extends StatefulWidget {
  final String minerId;
  const _HashrateChart({required this.minerId});

  @override
  State<_HashrateChart> createState() => _HashrateChartState();
}

enum _Tf { h1, h6, h24, d7 }

extension on _Tf {
  String get label => switch (this) {
        _Tf.h1 => '1H',
        _Tf.h6 => '6H',
        _Tf.h24 => '24H',
        _Tf.d7 => '7D',
      };
  Duration get duration => switch (this) {
        _Tf.h1 => const Duration(hours: 1),
        _Tf.h6 => const Duration(hours: 6),
        _Tf.h24 => const Duration(hours: 24),
        _Tf.d7 => const Duration(days: 7),
      };
}

class _HashrateChartState extends State<_HashrateChart> {
  _Tf _tf = _Tf.h6;
  bool _loading = true;
  List<HistoryPoint> _points = const [];
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh in step with poll cadence so the chart grows live.
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(_tf.duration);
    final pts = await HistoryService.instance
        .getHistory(widget.minerId, since: since);
    if (!mounted) return;
    setState(() {
      _points = pts;
      _loading = false;
    });
  }

  void _select(_Tf tf) {
    if (_tf == tf) return;
    setState(() {
      _tf = tf;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final avg = _points.isEmpty
        ? 0.0
        : _points.fold<double>(0, (a, p) => a + p.hashrate) / _points.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KratosColors.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KratosColors.of(context).line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                children: _Tf.values
                    .map((tf) => _TfPill(
                          label: tf.label,
                          selected: tf == _tf,
                          onTap: () => _select(tf),
                        ))
                    .toList(),
              ),
            ),
            if (avg > 0)
              Text('avg ${_formatHashrate(avg)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: KratosColors.of(context).muted,
                      fontFamily: 'Courier')),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: _loading
                ? Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KratosColors.of(context).accent)))
                : _points.length < 2
                    ? Center(
                        child: Text(
                            'No data yet — collecting samples…',
                            style: TextStyle(
                                fontSize: 12,
                                color: KratosColors.of(context).muted)),
                      )
                    : _buildChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final firstMs = _points.first.ts.millisecondsSinceEpoch.toDouble();
    final lastMs = _points.last.ts.millisecondsSinceEpoch.toDouble();
    final spots = _points
        .map((p) => FlSpot(
            p.ts.millisecondsSinceEpoch.toDouble(), p.hashrate))
        .toList();
    final values = _points.map((p) => p.hashrate);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxV - minV).abs() < 1e-6 ? maxV * 0.05 + 1 : (maxV - minV) * 0.1;
    final minY = (minV - pad).clamp(0, double.infinity).toDouble();
    final maxY = maxV + pad;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: KratosColors.of(context).line, strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (val, _) => Text(
                _formatHashrate(val),
                style: const TextStyle(
                    fontSize: 9, color: Color(0xFF6e7681)),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (lastMs - firstMs) / 3,
              getTitlesWidget: (val, _) {
                final dt = DateTime.fromMillisecondsSinceEpoch(val.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_formatTime(dt),
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xFF6e7681))),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: firstMs,
        maxX: lastMs,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: KratosColors.volt,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: KratosColors.volt.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    if (_tf == _Tf.d7) {
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return wd[(dt.weekday - 1) % 7];
    }
    if (_tf == _Tf.h24) {
      return '${dt.hour.toString().padLeft(2, '0')}:00';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

String _formatHashrate(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}T';
  if (v >= 1) return '${v.toStringAsFixed(0)}G';
  return '${(v * 1000).toStringAsFixed(0)}M';
}

class _TfPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TfPill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? KratosColors.of(context).accent.withOpacity(0.12)
              : KratosColors.of(context).surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? KratosColors.of(context).accent.withOpacity(0.5)
                  : KratosColors.of(context).line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: selected ? KratosColors.of(context).accent : KratosColors.of(context).muted,
          ),
        ),
      ),
    );
  }
}

// ── Net profit row ────────────────────────────────────────────────────────────

class _NetProfitRow extends StatelessWidget {
  final MinerStore store;
  final String minerId;
  const _NetProfitRow({required this.store, required this.minerId});

  @override
  Widget build(BuildContext context) {
    final earn = store.minerDailyEarningsUsd(minerId);
    final cost = store.minerDailyCostUsd(minerId);
    final net = earn - cost;
    final positive = net >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: positive
            ? const Color(0xFF39d353).withOpacity(0.06)
            : KratosTheme.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: positive
              ? const Color(0xFF39d353).withOpacity(0.25)
              : KratosTheme.red.withOpacity(0.25),
        ),
      ),
      child: Row(children: [
        Icon(
          positive ? Icons.trending_up : Icons.trending_down,
          size: 16,
          color: positive ? const Color(0xFF39d353) : KratosTheme.red,
        ),
        const SizedBox(width: 8),
        Text(
          'Net ${positive ? "profit" : "loss"}/day:',
          style: const TextStyle(
              fontSize: 12, color: Color(0xFF8b949e)),
        ),
        const Spacer(),
        Text(
          '${positive ? "+" : ""}\$${net.abs().toStringAsFixed(3)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: positive
                ? const Color(0xFF39d353)
                : KratosTheme.red,
            fontFamily: 'Courier',
          ),
        ),
      ]),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _HashrateHero extends StatelessWidget {
  final MinerStats? stats;
  const _HashrateHero({this.stats});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            KratosColors.of(context).accent.withOpacity(0.05),
            Colors.transparent
          ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(children: [
          Text(
            stats?.hashrateFormatted ?? '--',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: KratosColors.of(context).accent,
              fontFamily: 'Courier',
            ),
          ),
          Text('AVG HASHRATE',
              style: TextStyle(
                  fontSize: 11,
                  color: KratosColors.of(context).muted,
                  letterSpacing: 2)),
          if (stats != null && stats!.hashrate5s > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '5s: ${_fmtHashrate(stats!.hashrate5s)}  ·  trend: ${_trendLabel(stats!.trendDirection)}',
                style: TextStyle(
                    fontSize: 12, color: KratosColors.of(context).muted),
              ),
            ),
          if (stats?.isStandby == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bedtime_outlined, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('STANDBY', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: Colors.orange, letterSpacing: 1.5)),
                ]),
              ),
            ),
        ]),
      );

  String _fmtHashrate(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(3)} TH/s';
    return '${v.toStringAsFixed(1)} GH/s';
  }

  String _trendLabel(int d) {
    if (d > 0) return 'rising';
    if (d < 0) return 'falling';
    return 'stable';
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  const _StatCard(this.label, this.value, this.icon, this.color,
      {this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final isWarning = color == KratosTheme.red;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.18),
        highlightColor: color.withOpacity(0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isWarning
                ? KratosTheme.red.withOpacity(0.07)
                : KratosColors.of(context).surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWarning
                  ? KratosTheme.red.withOpacity(0.4)
                  : KratosColors.of(context).line,
              width: isWarning ? 1.5 : 1,
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(alignment: Alignment.topRight, children: [
              Icon(icon, color: color, size: 22),
              if (onTap != null)
                Positioned(
                  right: -2, top: -2,
                  child: Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: KratosColors.of(context).text, fontFamily: 'Courier')),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 9, color: KratosColors.of(context).muted, letterSpacing: 1)),
            if (onTap != null) ...[  
              const SizedBox(height: 4),
              Text('tap for details',
                  style: TextStyle(fontSize: 7, color: KratosColors.of(context).muted,
                      letterSpacing: 0.5)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _InfoCard(this.label, this.value,
      {required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      color: KratosColors.of(context).muted,
                      letterSpacing: 1)),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontFamily: 'Courier')),
            ]),
          ),
        ]),
      );
}

class _PoolRow extends StatelessWidget {
  final PoolInfo pool;
  const _PoolRow({required this.pool});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KratosColors.of(context).surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KratosColors.of(context).line),
        ),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: pool.active ? KratosColors.of(context).accent : KratosColors.of(context).muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(pool.cleanUrl,
                style: TextStyle(
                    fontSize: 13,
                    color: KratosColors.of(context).text,
                    fontFamily: 'Courier'),
                overflow: TextOverflow.ellipsis),
            Text(pool.user,
                style: TextStyle(
                    fontSize: 11, color: KratosColors.of(context).muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(pool.status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: pool.active
                        ? KratosColors.of(context).accent
                        : KratosTheme.red)),
            Text('${pool.accepted}A / ${pool.rejected}R',
                style: TextStyle(
                    fontSize: 10,
                    color: KratosColors.of(context).muted,
                    fontFamily: 'Courier')),
          ]),
        ]),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: KratosColors.of(context).muted,
          letterSpacing: 1.5));
}

// ── Stat card tap actions ────────────────────────────────────────────────────

void _showTempInfo(BuildContext ctx, double temp) {
  final label = temp < 60 ? '🟢 Cool' : temp < 72 ? '🟡 Warm' : '🔴 Hot!';
  final msg = temp < 60 ? 'Running great. No action needed.'
      : temp < 72 ? 'Normal range. Keep an eye on airflow.'
      : 'High temp! Check fan speed and airflow. Risk of throttling.';
  final color = temp < 60 ? KratosColors.of(ctx).accent : temp < 72 ? KratosTheme.orange : KratosTheme.red;
  showDialog(context: ctx, builder: (_) => AlertDialog(
    backgroundColor: KratosColors.of(ctx).surface,
    title: Text('🌡️  ${temp.toInt()}°C', style: TextStyle(color: KratosColors.of(ctx).text)),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 8),
      Text(msg, style: TextStyle(color: KratosColors.of(ctx).muted, height: 1.5)),
      const SizedBox(height: 12),
      Divider(color: KratosColors.of(ctx).line),
      for (final r in [('🟢 Cool', '< 60°C'), ('🟡 Warm', '60–72°C'), ('🔴 Hot', '> 72°C')])
        Padding(padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Text(r.$1, style: TextStyle(fontSize: 13, color: KratosColors.of(ctx).text)),
              const Spacer(),
              Text(r.$2, style: TextStyle(fontSize: 12, color: KratosColors.of(ctx).muted, fontFamily: 'Courier')),
            ])),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('OK', style: TextStyle(color: KratosTheme.orange)))],
  ));
}

void _showFanSheet(BuildContext ctx, Miner miner, int fanPct) {
  showModalBottomSheet(context: ctx, isScrollControlled: true,
    backgroundColor: KratosColors.of(ctx).surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FanControlSheet(miner: miner, initialPercent: fanPct));
}

void _showShareStats(BuildContext ctx, int accepted, int rejected) {
  final total = accepted + rejected;
  final rate = total > 0 ? accepted / total * 100.0 : 100.0;
  final color = rate >= 99 ? KratosColors.of(ctx).accent : rate >= 95 ? KratosTheme.orange : KratosTheme.red;
  showDialog(context: ctx, builder: (_) => AlertDialog(
    backgroundColor: KratosColors.of(ctx).surface,
    title: Text('⚡ Share Stats', style: TextStyle(color: KratosColors.of(ctx).text)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final r in [('Accepted', '$accepted', Color(0xFF3FB950)), ('Rejected', '$rejected', KratosTheme.red), ('Total', '$total', KratosColors.of(ctx).muted)])
        Padding(padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Text(r.$1, style: TextStyle(color: KratosColors.of(ctx).muted, fontSize: 13)),
              const Spacer(),
              Text(r.$2, style: TextStyle(color: r.$3, fontFamily: 'Courier', fontSize: 14, fontWeight: FontWeight.bold)),
            ])),
      Divider(color: KratosColors.of(ctx).line, height: 20),
      Text('${rate.toStringAsFixed(2)}%', style: TextStyle(fontSize: 28,
          fontWeight: FontWeight.bold, color: color, fontFamily: 'Courier')),
      Text('acceptance rate', style: TextStyle(fontSize: 12, color: KratosColors.of(ctx).muted)),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('Close', style: TextStyle(color: KratosTheme.orange)))],
  ));
}

void _showHwErrorInfo(BuildContext ctx, int errors) {
  showDialog(context: ctx, builder: (_) => AlertDialog(
    backgroundColor: KratosColors.of(ctx).surface,
    title: Text(errors > 0 ? '⚠️ HW Errors: $errors' : '✅ No HW Errors',
        style: TextStyle(color: KratosColors.of(ctx).text)),
    content: Text(errors == 0
        ? 'ASIC is working cleanly. HW errors = failed nonce calculations at chip level.'
        : 'HW errors = failed nonce calculations.\nA few/hour is normal. High counts suggest:\n\n• OC too high → reduce frequency\n• Core voltage too low\n• ASIC degradation or overheating',
        style: TextStyle(color: KratosColors.of(ctx).muted, height: 1.5)),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('OK', style: TextStyle(color: KratosTheme.orange)))],
  ));
}

void _showUptimeInfo(BuildContext ctx, int secs) {
  final started = DateTime.now().subtract(Duration(seconds: secs));
  final d = secs ~/ 86400; final h = (secs % 86400) ~/ 3600; final m = (secs % 3600) ~/ 60;
  showDialog(context: ctx, builder: (_) => AlertDialog(
    backgroundColor: KratosColors.of(ctx).surface,
    title: Text('⏱ Uptime', style: TextStyle(color: KratosColors.of(ctx).text)),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${d}d ${h}h ${m}m', style: TextStyle(fontSize: 24,
          fontWeight: FontWeight.bold, color: KratosColors.of(ctx).text, fontFamily: 'Courier')),
      const SizedBox(height: 8),
      Text('Since: ${started.day.toString().padLeft(2,'0')}/${started.month.toString().padLeft(2,'0')}/${started.year}  '
          '${started.hour.toString().padLeft(2,'0')}:${started.minute.toString().padLeft(2,'0')}',
          style: TextStyle(color: KratosColors.of(ctx).muted, fontFamily: 'Courier')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('OK', style: TextStyle(color: KratosTheme.orange)))],
  ));
}

class _FanControlSheet extends StatefulWidget {
  final Miner miner; final int initialPercent;
  const _FanControlSheet({required this.miner, required this.initialPercent});
  @override State<_FanControlSheet> createState() => _FanControlSheetState();
}
class _FanControlSheetState extends State<_FanControlSheet> {
  late int _fan; bool _applying = false;
  @override void initState() { super.initState(); _fan = widget.initialPercent; }
  Future<void> _apply() async {
    setState(() => _applying = true);
    await EspMinerAPI.instance.setFanSpeed(widget.miner.ip, widget.miner.port, _fan,
        remoteUrl: widget.miner.remoteUrl, isRemote: widget.miner.isRemote);
    if (mounted) { setState(() => _applying = false); Navigator.pop(context); }
  }
  @override
  Widget build(BuildContext ctx) {
    final bot = MediaQuery.of(ctx).viewInsets.bottom;
    return Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bot),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(
            color: KratosColors.of(ctx).line, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.air, color: KratosTheme.blue),
          const SizedBox(width: 10),
          Text('Fan Speed', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800, color: KratosColors.of(ctx).text)),
          const Spacer(),
          Text('$_fan%', style: const TextStyle(fontSize: 20,
              fontWeight: FontWeight.bold, color: KratosTheme.blue, fontFamily: 'Courier')),
        ]),
        const SizedBox(height: 12),
        SliderTheme(data: SliderTheme.of(ctx).copyWith(
            activeTrackColor: KratosTheme.blue, thumbColor: KratosTheme.blue,
            inactiveTrackColor: KratosColors.of(ctx).line,
            overlayColor: KratosTheme.blue.withOpacity(0.15)),
          child: Slider(value: _fan.toDouble(), min: 0, max: 100, divisions: 20,
              onChanged: (v) => setState(() => _fan = v.round()))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0% (auto)', style: TextStyle(fontSize: 10, color: KratosColors.of(ctx).muted)),
          Text('100% (max)', style: TextStyle(fontSize: 10, color: KratosColors.of(ctx).muted)),
        ]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KratosTheme.blue,
              foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _applying ? null : _apply,
          child: _applying
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
              : const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)))),
      ]));
  }
}

// ── Edit miner sheet ────────────────────────────────────────────────────────

void _showEditSheet(BuildContext context, Miner miner, MinerStore store) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: KratosColors.of(context).surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EditMinerSheet(miner: miner, store: store),
  );
}

class _EditMinerSheet extends StatefulWidget {
  final Miner miner;
  final MinerStore store;
  const _EditMinerSheet({required this.miner, required this.store});
  @override State<_EditMinerSheet> createState() => _EditMinerSheetState();
}

class _EditMinerSheetState extends State<_EditMinerSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _ipCtrl;
  late TextEditingController _portCtrl;
  late MinerType _type;
  bool _detecting = false;
  bool _detected = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.miner.name);
    _ipCtrl   = TextEditingController(text: widget.miner.ip);
    _portCtrl = TextEditingController(text: '${widget.miner.port}');
    _type = widget.miner.type;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose(); _ipCtrl.dispose(); _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetect() async {
    final ip = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text) ?? 80;
    setState(() { _detecting = true; _detected = false; });
    final s = await EspMinerAPI.instance
        .fetchAll(ip, port)
        .timeout(const Duration(seconds: 5), onTimeout: () => MinerStats.offline);
    MinerType detected = _type;
    if (s.status != MinerStatus.offline) {
      detected = s.type != MinerType.generic ? s.type : MinerType.detect(s.model);
      if (detected == MinerType.generic) detected = MinerType.bitaxeGamma;
    } else {
      // Try CGMiner
      final cs = await CGMinerAPI.instance
          .fetchAll(ip, 4028)
          .timeout(const Duration(seconds: 3), onTimeout: () => MinerStats.offline);
      if (cs.status != MinerStatus.offline) {
        detected = MinerType.detect(cs.model);
        _portCtrl.text = '4028';
      }
    }
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _detected = detected != _type;
      _type = detected;
    });
  }

  Future<void> _save() async {
    widget.miner.name = _nameCtrl.text.trim().isEmpty
        ? 'Miner at ${_ipCtrl.text.trim()}' : _nameCtrl.text.trim();
    widget.miner.ip   = _ipCtrl.text.trim();
    widget.miner.port = int.tryParse(_portCtrl.text) ?? _type.defaultPort;
    widget.miner.type = _type;
    await widget.store.save();
    widget.store.refreshOne(widget.miner);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: KratosColors.of(context).line,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Edit Miner',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: KratosColors.of(context).text)),
          const SizedBox(height: 16),

          // Name
          _editLabel('NAME'),
          const SizedBox(height: 6),
          _editField(_nameCtrl, 'Miner name'),
          const SizedBox(height: 12),

          // IP + Port row
          Row(children: [
            Expanded(flex: 3, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editLabel('IP ADDRESS'),
                const SizedBox(height: 6),
                _editField(_ipCtrl, '192.168.1.x', type: TextInputType.url),
              ],
            )),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editLabel('PORT'),
                const SizedBox(height: 6),
                _editField(_portCtrl, '80', type: TextInputType.number),
              ],
            )),
          ]),
          const SizedBox(height: 16),

          // Auto-detect button
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: KratosTheme.orange,
                side: BorderSide(color: KratosTheme.orange.withOpacity(0.4)),
                backgroundColor: KratosTheme.orange.withOpacity(0.07),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _detecting ? null : _autoDetect,
              icon: _detecting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: KratosTheme.orange))
                  : const Icon(Icons.radar_rounded, size: 18),
              label: Text(_detecting ? 'Detecting…' : 'Auto-detect type from IP',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          if (_detected) ...[  
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: KratosColors.of(context).accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KratosColors.of(context).accent.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: KratosColors.of(context).accent, size: 15),
                const SizedBox(width: 8),
                Text('Detected: ${_type.displayName}',
                    style: TextStyle(fontSize: 13, color: KratosColors.of(context).accent,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // Type chips
          _editLabel('MINER TYPE'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            children: MinerType.values.map((t) {
              final sel = t == _type;
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? KratosTheme.orange.withOpacity(0.15) : KratosColors.of(context).bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? KratosTheme.orange : KratosColors.of(context).line),
                  ),
                  child: Text(t.displayName,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: sel ? KratosTheme.orange : KratosColors.of(context).text)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _type.apiType == ApiType.espMinerHttp
                  ? KratosColors.of(context).accent.withOpacity(0.07)
                  : KratosTheme.blue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _type.apiType == ApiType.espMinerHttp
                  ? KratosColors.of(context).accent.withOpacity(0.25) : KratosTheme.blue.withOpacity(0.25)),
            ),
            child: Text(
              _type.apiType == ApiType.espMinerHttp
                  ? 'ESP-Miner HTTP API · port ${_type.defaultPort}'
                  : 'CGMiner TCP API · port ${_type.defaultPort}',
              style: TextStyle(fontSize: 11,
                  color: _type.apiType == ApiType.espMinerHttp
                      ? KratosColors.of(context).accent : KratosTheme.blue,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: KratosTheme.orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _save,
              child: const Text('Save Changes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _editLabel(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: KratosColors.of(context).muted, letterSpacing: 1.5));

  Widget _editField(TextEditingController ctrl, String hint,
      {TextInputType type = TextInputType.text}) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: TextStyle(color: KratosColors.of(context).text, fontFamily: 'Courier'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: KratosColors.of(context).muted),
          filled: true, fillColor: KratosColors.of(context).bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: KratosColors.of(context).line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: KratosColors.of(context).line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: KratosTheme.orange)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label, value;
  final bool copyable;
  const _InfoRow(this.label, this.value, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: KratosColors.of(context).surface, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 13, color: KratosColors.of(context).muted)),
        const Spacer(),
        Text(value, style: TextStyle(
            fontSize: 13, color: KratosColors.of(context).text, fontFamily: 'Courier')),
        if (copyable) ...[  
          const SizedBox(width: 8),
          Icon(Icons.copy, size: 13, color: KratosColors.of(context).muted),
        ],
      ]),
    );
    if (!copyable) return row;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$label copied'),
            duration: const Duration(seconds: 1)));
      },
      child: row,
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _ActionBtn(this.label, this.icon, this.color, this.onPressed);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.3)),
            backgroundColor: color.withOpacity(0.07),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      );
}

// ── Fan Speed Control (ESP-Miner) ─────────────────────────────────────────────

class _RemoteBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: KratosTheme.blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KratosTheme.blue.withOpacity(0.4)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lan_outlined, size: 10, color: KratosTheme.blue),
          SizedBox(width: 3),
          Text('Remote',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KratosTheme.blue,
                  letterSpacing: 0.3)),
        ]),
      );
}

class _FanSpeedControl extends StatefulWidget {
  final Miner miner;
  final int initialFanPercent;
  const _FanSpeedControl(
      {required this.miner, required this.initialFanPercent});

  @override
  State<_FanSpeedControl> createState() => _FanSpeedControlState();
}

class _FanSpeedControlState extends State<_FanSpeedControl> {
  late double _value;
  bool _setting = false;
  String? _fanResult;

  @override
  void initState() {
    super.initState();
    // Start at 100% if miner reports no fan data (common on NerdOctaxe)
    final init = widget.initialFanPercent;
    _value = (init > 0 ? init : 100).clamp(0, 100).toDouble();
  }

  Future<void> _setFan() async {
    setState(() { _setting = true; _fanResult = null; });
    final ok = await EspMinerAPI.instance.setFanSpeed(
        widget.miner.ip, widget.miner.port, _value.round(),
        remoteUrl: widget.miner.remoteUrl,
        isRemote: widget.miner.isRemote);
    if (mounted) setState(() {
      _setting = false;
      _fanResult = ok ? '✅ Fan set to ${_value.round()}%' : '❌ Failed — check miner connection';
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KratosColors.of(context).surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KratosColors.of(context).line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.air, size: 14, color: KratosColors.of(context).muted),
            const SizedBox(width: 6),
            Text('FAN SPEED',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KratosColors.of(context).muted,
                    letterSpacing: 1.5)),
            const Spacer(),
            Text('${_value.round()}%',
                style: TextStyle(
                    fontSize: 13,
                    color: KratosColors.of(context).text,
                    fontFamily: 'Courier')),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: KratosTheme.blue,
              thumbColor: KratosTheme.blue,
              inactiveTrackColor: KratosColors.of(context).line,
              overlayColor: KratosTheme.blue.withOpacity(0.15),
            ),
            child: Slider(
              value: _value,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 34,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _setting ? KratosColors.of(context).line : KratosTheme.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _setting ? null : _setFan,
                child: Text(_setting ? 'Setting...' : 'Set',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          if (_fanResult != null) ...[            const SizedBox(height: 6),
            Text(_fanResult!,
                style: TextStyle(
                    fontSize: 12,
                    color: _fanResult!.startsWith('✅')
                        ? KratosColors.of(context).accent
                        : KratosTheme.red,
                    fontFamily: 'Courier')),
          ],
        ]),
      );
}

// ── Block ETA (solo mining expected time) ─────────────────────────────────────

class _BlockEtaRow extends StatefulWidget {
  final double hashrateGhs;
  const _BlockEtaRow({required this.hashrateGhs});
  @override State<_BlockEtaRow> createState() => _BlockEtaRowState();
}

class _BlockEtaRowState extends State<_BlockEtaRow>
    with SingleTickerProviderStateMixin {
  static double? _cachedDifficulty;
  static DateTime? _difficultyFetchTime;
  String _blockEta = '--';
  bool _loading = true;
  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 2))..repeat();
    _loadEta();
  }

  @override
  void dispose() { _spinCtrl.dispose(); super.dispose(); }

  Future<void> _loadEta() async {
    double diff;
    final now = DateTime.now();
    if (_cachedDifficulty != null &&
        _difficultyFetchTime != null &&
        now.difference(_difficultyFetchTime!) < const Duration(hours: 1)) {
      diff = _cachedDifficulty!;
    } else {
      try {
        final r = await http
            .get(Uri.parse('https://blockchain.info/q/getdifficulty'))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          diff = double.tryParse(r.body.trim()) ?? 0;
          if (diff > 0) {
            _cachedDifficulty = diff;
            _difficultyFetchTime = now;
          } else {
            diff = _cachedDifficulty ?? 0;
          }
        } else {
          diff = _cachedDifficulty ?? 0;
        }
      } catch (_) {
        diff = _cachedDifficulty ?? 0;
      }
    }
    if (!mounted) return;
    if (diff <= 0 || widget.hashrateGhs <= 0) {
      setState(() { _blockEta = '--'; _loading = false; });
      return;
    }
    final hashrateHs = widget.hashrateGhs * 1e9;
    final days = diff * 4294967296.0 / hashrateHs / 86400.0;
    setState(() { _blockEta = _formatDays(days); _loading = false; });
    if (!_loading) _spinCtrl.stop();
  }

  String _formatDays(double days) {
    if (days < 1) return '~${(days * 24).round()} hours';
    if (days < 30) return '~${days.round()} days';
    if (days < 365) return '~${(days / 30.4).round()} months';
    return '~${(days / 365.25).toStringAsFixed(0)} years';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _blockEta != '--' ? () {
        Clipboard.setData(ClipboardData(text: _blockEta));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Block ETA copied'), duration: Duration(seconds: 1)));
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KratosColors.of(context).surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KratosColors.of(context).line),
        ),
        child: Row(children: [
          RotationTransition(
            turns: _spinCtrl,
            child: Icon(
              _loading ? Icons.sync : Icons.access_time_outlined,
              color: KratosTheme.orange, size: 16),
          ),
          const SizedBox(width: 10),
          Text('BLOCK ETA',
              style: TextStyle(fontSize: 11, color: KratosColors.of(context).muted,
                  letterSpacing: 1, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(_loading ? 'calculating…' : _blockEta,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold,
                  color: _loading ? KratosColors.of(context).muted : KratosTheme.orange,
                  fontFamily: 'Courier')),
        ]),
      ),
    );
  }
}
