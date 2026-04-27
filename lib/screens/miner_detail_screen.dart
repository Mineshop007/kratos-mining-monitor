import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/miner_store.dart';
import 'pool_editor_screen.dart';
import 'oc_screen.dart';

class MinerDetailScreen extends StatelessWidget {
  final Miner miner;
  const MinerDetailScreen({super.key, required this.miner});

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final s = store.stats[miner.id];
      return Scaffold(
        backgroundColor: KratosTheme.bg,
        appBar: AppBar(
          backgroundColor: KratosTheme.bg,
          title: Text(miner.name, style: const TextStyle(color: KratosTheme.textPrim)),
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
                _StatCard('OUTLET TEMP', s?.outTemp != null && s!.outTemp > 0 ? '${s.outTemp.toInt()}°C' : '--',
                  Icons.thermostat, _tempColor(s?.outTemp ?? 0)),
                _StatCard('FAN SPEED', s?.fanRPM != null && s!.fanRPM > 0 ? '${s.fanRPM} RPM' : '--',
                  Icons.air, KratosTheme.blue),
                _StatCard('ACCEPTED', '${s?.accepted ?? 0}', Icons.check_circle, const Color(0xFF3FB950)),
                _StatCard('REJECTED', '${s?.rejected ?? 0}', Icons.cancel,
                  (s?.rejected ?? 0) > 0 ? KratosTheme.red : KratosTheme.muted),
                _StatCard('HW ERRORS', '${s?.hardwareErrors ?? 0}', Icons.warning_amber,
                  (s?.hardwareErrors ?? 0) > 0 ? KratosTheme.red : KratosTheme.muted),
                _StatCard('UPTIME', s?.uptimeFormatted ?? '--', Icons.access_time, KratosTheme.purple),
              ],
            ),
            const SizedBox(height: 16),

            // Best share
            if ((s?.bestShare ?? 0) > 0) ...[
              _InfoCard('🎯 BEST SHARE', s!.bestShare.toStringAsFixed(0)),
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
            _InfoRow('Model', s?.model.isNotEmpty == true ? s!.model : 'Unknown'),
            _InfoRow('Firmware', s?.firmware.isNotEmpty == true ? s!.firmware : 'Unknown'),
            _InfoRow('IP Address', miner.ip),
            _InfoRow('Port', '${miner.port}'),
            if ((s?.frequency ?? 0) > 0) _InfoRow('Frequency', '${s!.frequency.toInt()} MHz'),
            if ((s?.powerDraw ?? 0) > 0) _InfoRow('Power Draw', '${s!.powerDraw.toInt()} W'),
            if ((s?.efficiency ?? 0) > 0)
              _InfoRow('Efficiency', '${s!.efficiency.toStringAsFixed(2)} MH/J'),
            const SizedBox(height: 20),

            // Actions
            _SectionLabel('ACTIONS'),
            const SizedBox(height: 8),
            _ActionBtn('Configure Pools', Icons.dns, KratosTheme.orange, () =>
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PoolEditorScreen(miner: miner, currentPools: s?.pools ?? [])))),
            const SizedBox(height: 8),
            _ActionBtn('OC Settings', Icons.bolt, KratosTheme.purple, () =>
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => OCScreen(miner: miner, stats: s)))),
            const SizedBox(height: 8),
            _ActionBtn('Restart Miner', Icons.restart_alt, KratosTheme.red, () =>
              _confirmRestart(context)),
            const SizedBox(height: 8),
            _ActionBtn('Stop Mining', Icons.stop_circle_outlined, KratosTheme.muted, () =>
              _confirmStop(context)),
            const SizedBox(height: 32),
          ],
        ),
      );
    });
  }

  void _confirmRestart(BuildContext ctx) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: KratosTheme.surface,
      title: const Text('Restart Miner?', style: TextStyle(color: KratosTheme.textPrim)),
      content: Text('Restart ${miner.name}? It will be offline for ~60 seconds.',
        style: const TextStyle(color: KratosTheme.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: KratosTheme.muted))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KratosTheme.red),
          onPressed: () async {
            Navigator.pop(ctx);
            await CGMinerAPI.instance.restart(miner.ip, miner.port);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('✅ Restart sent — back online in ~60s'),
                backgroundColor: KratosTheme.surface,
              ));
            }
          },
          child: const Text('Restart'),
        ),
      ],
    ));
  }

  void _confirmStop(BuildContext ctx) {
    showModalBottomSheet(context: ctx, backgroundColor: KratosTheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Mining Control', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: KratosTheme.textPrim)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: KratosTheme.muted.withOpacity(0.2),
              foregroundColor: KratosTheme.muted, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              Navigator.pop(ctx);
              await CGMinerAPI.instance.setFanSpeed(miner.ip, miner.port, 0);
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop Mining', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: KratosTheme.neon.withOpacity(0.15),
              foregroundColor: KratosTheme.neon, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              Navigator.pop(ctx);
              await CGMinerAPI.instance.restart(miner.ip, miner.port);
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Resume Mining', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 10),
        ]),
    ));
  }

  Color _tempColor(double t) {
    if (t > 85) return KratosTheme.red;
    if (t > 75) return KratosTheme.orange;
    return KratosTheme.muted;
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _HashrateHero extends StatelessWidget {
  final MinerStats? stats;
  const _HashrateHero({this.stats});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        KratosTheme.neon.withOpacity(0.05), Colors.transparent
      ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
    ),
    child: Column(children: [
      Text(stats?.hashrateFormatted ?? '--',
        style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900,
          color: KratosTheme.neon, fontFamily: 'Courier')),
      const Text('AVG HASHRATE', style: TextStyle(fontSize: 11,
        color: KratosTheme.muted, letterSpacing: 2)),
      if (stats != null && stats!.hashrate5s > 0)
        Padding(padding: const EdgeInsets.only(top: 4), child:
          Text('5s: ${stats!.hashrate5s >= 1000 ? "${(stats!.hashrate5s/1000).toStringAsFixed(3)} TH/s" : "${stats!.hashrate5s.toStringAsFixed(1)} GH/s"}',
            style: const TextStyle(fontSize: 13, color: KratosTheme.muted))),
    ]),
  );
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
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
        color: KratosTheme.textPrim, fontFamily: 'Courier')),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 9, color: KratosTheme.muted, letterSpacing: 1)),
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
      Container(width: 7, height: 7,
        decoration: BoxDecoration(
          color: pool.active ? KratosTheme.neon : KratosTheme.muted,
          shape: BoxShape.circle,
        )),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pool.cleanUrl, style: const TextStyle(fontSize: 13,
          color: KratosTheme.textPrim, fontFamily: 'Courier'),
          overflow: TextOverflow.ellipsis),
        Text(pool.user, style: const TextStyle(fontSize: 11, color: KratosTheme.muted)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(pool.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
          color: pool.status == 'Alive' ? KratosTheme.neon : KratosTheme.red)),
        Text('${pool.accepted}A / ${pool.rejected}R',
          style: const TextStyle(fontSize: 10, color: KratosTheme.muted, fontFamily: 'Courier')),
      ]),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
      color: KratosTheme.muted, letterSpacing: 1.5));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: KratosTheme.surface, borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: KratosTheme.muted)),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 13,
        color: KratosTheme.textPrim, fontFamily: 'Courier')),
    ]),
  );
}

class _InfoCard extends StatelessWidget {
  final String label, value;
  const _InfoCard(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: KratosTheme.orange.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: KratosTheme.orange.withOpacity(0.2)),
    ),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: KratosTheme.muted, letterSpacing: 1)),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
        color: KratosTheme.orange, fontFamily: 'Courier')),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    ),
  );
}
