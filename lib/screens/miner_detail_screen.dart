import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/miner_store.dart';
import 'pool_editor_screen.dart';
import 'oc_screen.dart';

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
        backgroundColor: KratosTheme.bg,
        appBar: AppBar(
          backgroundColor: KratosTheme.bg,
          title: Row(children: [
            Expanded(
              child: Text(miner.name,
                  style: const TextStyle(color: KratosTheme.textPrim),
                  overflow: TextOverflow.ellipsis),
            ),
            if (miner.isRemote) ...[const SizedBox(width: 6), _RemoteBadge()],
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: KratosTheme.muted),
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

            // Hashrate sparkline chart (24h history)
            if (s != null && s.hashrateHistory.length >= 2) ...[
              _SectionLabel('HASHRATE HISTORY'),
              const SizedBox(height: 8),
              _HashrateChart(history: s.hashrateHistory),
              const SizedBox(height: 16),
            ],

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
                  s?.outTemp != null && s!.outTemp > 0
                      ? '${s.outTemp.toInt()}°C'
                      : '--',
                  Icons.thermostat,
                  _tempColor(s?.outTemp ?? 0),
                ),
                _StatCard(
                  'FAN',
                  s?.fanRPM != null && s!.fanRPM > 0
                      ? '${s.fanRPM} RPM'
                      : (s?.fanPercent != null && s!.fanPercent > 0
                          ? '${s.fanPercent}%'
                          : '--'),
                  Icons.air,
                  KratosTheme.blue,
                ),
                _StatCard('ACCEPTED', '${s?.accepted ?? 0}',
                    Icons.check_circle, const Color(0xFF3FB950)),
                _StatCard(
                  'REJECTED',
                  '${s?.rejected ?? 0}',
                  Icons.cancel,
                  (s?.rejected ?? 0) > 0
                      ? KratosTheme.red
                      : KratosTheme.muted,
                ),
                _StatCard(
                  'HW ERRORS',
                  '${s?.hardwareErrors ?? 0}',
                  Icons.warning_amber,
                  (s?.hardwareErrors ?? 0) > 0
                      ? KratosTheme.red
                      : KratosTheme.muted,
                ),
                _StatCard('UPTIME', s?.uptimeFormatted ?? '--',
                    Icons.access_time, KratosTheme.purple),
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
            _InfoRow('IP Address', miner.ip),
            _InfoRow('Port', '${miner.port}'),
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
            _ActionBtn('Restart Miner', Icons.restart_alt, KratosTheme.red,
                () => _confirmRestart(context)),
            if (miner.type.apiType == ApiType.espMinerHttp) ...[
              const SizedBox(height: 8),
              _ActionBtn(
                'Pause Mining',
                Icons.pause_circle_outline,
                KratosTheme.muted,
                () => _confirmAction(context, 'Pause', _pause),
              ),
              const SizedBox(height: 8),
              _ActionBtn(
                'Resume Mining',
                Icons.play_circle_outline,
                KratosTheme.neon,
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
        backgroundColor: KratosTheme.surface,
        title: const Text('Restart Miner?',
            style: TextStyle(color: KratosTheme.textPrim)),
        content: Text(
          'Restart ${miner.name}? It will be offline for ~60 seconds.',
          style: const TextStyle(color: KratosTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: KratosTheme.muted)),
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
                  backgroundColor: KratosTheme.surface,
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
        backgroundColor: KratosTheme.surface,
      ));
    }
  }

  Color _tempColor(double t) {
    if (t > 85) return KratosTheme.red;
    if (t > 75) return KratosTheme.orange;
    return KratosTheme.muted;
  }
}

// ── Hashrate chart ────────────────────────────────────────────────────────────

class _HashrateChart extends StatelessWidget {
  final List<double> history;
  const _HashrateChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox.shrink();

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minY = history.reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = history.reduce((a, b) => a > b ? a : b) * 1.05;

    return Container(
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KratosTheme.border),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: KratosTheme.border, strokeWidth: 0.5),
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
            bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: KratosTheme.neon,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: KratosTheme.neon.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatHashrate(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}T';
    if (v >= 1) return '${v.toStringAsFixed(0)}G';
    return '${(v * 1000).toStringAsFixed(0)}M';
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
            KratosTheme.neon.withOpacity(0.05),
            Colors.transparent
          ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(children: [
          Text(
            stats?.hashrateFormatted ?? '--',
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: KratosTheme.neon,
              fontFamily: 'Courier',
            ),
          ),
          const Text('AVG HASHRATE',
              style: TextStyle(
                  fontSize: 11,
                  color: KratosTheme.muted,
                  letterSpacing: 2)),
          if (stats != null && stats!.hashrate5s > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '5s: ${_fmtHashrate(stats!.hashrate5s)}  ·  trend: ${_trendLabel(stats!.trendDirection)}',
                style: const TextStyle(
                    fontSize: 12, color: KratosTheme.muted),
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
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: KratosTheme.textPrim,
                  fontFamily: 'Courier')),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: KratosTheme.muted,
                  letterSpacing: 1)),
        ]),
      );
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
                  style: const TextStyle(
                      fontSize: 9,
                      color: KratosTheme.muted,
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
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: pool.active ? KratosTheme.neon : KratosTheme.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(pool.cleanUrl,
                style: const TextStyle(
                    fontSize: 13,
                    color: KratosTheme.textPrim,
                    fontFamily: 'Courier'),
                overflow: TextOverflow.ellipsis),
            Text(pool.user,
                style: const TextStyle(
                    fontSize: 11, color: KratosTheme.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(pool.status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: pool.active
                        ? KratosTheme.neon
                        : KratosTheme.red)),
            Text('${pool.accepted}A / ${pool.rejected}R',
                style: const TextStyle(
                    fontSize: 10,
                    color: KratosTheme.muted,
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
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: KratosTheme.muted,
          letterSpacing: 1.5));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: KratosTheme.surface,
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 13, color: KratosTheme.muted)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  color: KratosTheme.textPrim,
                  fontFamily: 'Courier')),
        ]),
      );
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
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.air, size: 14, color: KratosTheme.muted),
            const SizedBox(width: 6),
            const Text('FAN SPEED',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KratosTheme.muted,
                    letterSpacing: 1.5)),
            const Spacer(),
            Text('${_value.round()}%',
                style: const TextStyle(
                    fontSize: 13,
                    color: KratosTheme.textPrim,
                    fontFamily: 'Courier')),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: KratosTheme.blue,
              thumbColor: KratosTheme.blue,
              inactiveTrackColor: KratosTheme.border,
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
                      _setting ? KratosTheme.border : KratosTheme.blue,
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
                        ? KratosTheme.neon
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

  @override
  State<_BlockEtaRow> createState() => _BlockEtaRowState();
}

class _BlockEtaRowState extends State<_BlockEtaRow> {
  static double? _cachedDifficulty;
  static DateTime? _difficultyFetchTime;

  String _blockEta = '--';

  @override
  void initState() {
    super.initState();
    _loadEta();
  }

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
      setState(() => _blockEta = '--');
      return;
    }
    final hashrateHs = widget.hashrateGhs * 1e9; // GH/s → H/s
    final days = diff * 4294967296.0 / hashrateHs / 86400.0;
    setState(() => _blockEta = _formatDays(days));
  }

  String _formatDays(double days) {
    if (days < 1) return '~${(days * 24).round()} hours';
    if (days < 30) return '~${days.round()} days';
    if (days < 365) return '~${(days / 30.4).round()} months';
    return '~${(days / 365.25).toStringAsFixed(0)} years';
  }

  @override
  Widget build(BuildContext context) => _InfoRow('Block ETA', _blockEta);
}
