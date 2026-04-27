import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';

class MinerCard extends StatelessWidget {
  final Miner miner;
  final MinerStats? stats;
  final VoidCallback onTap;

  const MinerCard({super.key, required this.miner, this.stats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final status = s?.status ?? MinerStatus.unknown;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor(status), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Text(miner.type.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(miner.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: KratosTheme.textPrim)),
                    Text(miner.ip,
                      style: const TextStyle(fontSize: 11, color: KratosTheme.muted, fontFamily: 'Courier')),
                  ],
                )),
                _StatusBadge(status: status),
              ]),
            ),

            const Divider(height: 1, color: KratosTheme.border),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                _StatCell(label: 'HASHRATE', value: s?.hashrateFormatted ?? '--', color: KratosTheme.neon),
                _Divider(),
                _StatCell(label: 'TEMP', value: s != null && s.outTemp > 0 ? '${s.outTemp.toInt()}°C' : '--',
                  color: _tempColor(s?.outTemp ?? 0)),
                _Divider(),
                _StatCell(label: 'FAN', value: s != null && s.fanRPM > 0 ? '${s.fanRPM}rpm' : '--', color: KratosTheme.blue),
                _Divider(),
                _StatCell(label: 'ACCEPT', value: '${s?.accepted ?? 0}', color: const Color(0xFF3FB950)),
              ]),
            ),

            // Active pool
            if (s != null && s.pools.isNotEmpty)
              ...[
                const Divider(height: 1, color: KratosTheme.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(children: [
                    Container(width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: s.pools.any((p) => p.active) ? KratosTheme.neon : KratosTheme.muted,
                        shape: BoxShape.circle,
                      )),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      _activePool(s.pools),
                      style: const TextStyle(fontSize: 11, color: KratosTheme.muted, fontFamily: 'Courier'),
                      overflow: TextOverflow.ellipsis,
                    )),
                    Text(_workerName(s.pools),
                      style: const TextStyle(fontSize: 11, color: KratosTheme.orange)),
                  ]),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Color _borderColor(MinerStatus s) => switch (s) {
    MinerStatus.online  => KratosTheme.border,
    MinerStatus.warning => KratosTheme.orange.withOpacity(0.5),
    MinerStatus.offline => KratosTheme.red.withOpacity(0.3),
    _                   => KratosTheme.border,
  };

  Color _tempColor(double t) {
    if (t > 85) return KratosTheme.red;
    if (t > 75) return KratosTheme.orange;
    return KratosTheme.muted;
  }

  String _activePool(List<PoolInfo> pools) {
    final active = pools.where((p) => p.active).firstOrNull ?? pools.first;
    return active.cleanUrl;
  }

  String _workerName(List<PoolInfo> pools) {
    final active = pools.where((p) => p.active).firstOrNull ?? pools.first;
    return active.workerName;
  }
}

class _StatusBadge extends StatelessWidget {
  final MinerStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MinerStatus.online  => KratosTheme.neon,
      MinerStatus.warning => KratosTheme.orange,
      MinerStatus.offline => KratosTheme.red,
      _                   => KratosTheme.muted,
    };
    final label = switch (status) {
      MinerStatus.online  => 'ONLINE',
      MinerStatus.warning => 'WARNING',
      MinerStatus.offline => 'OFFLINE',
      _                   => 'UNKNOWN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.8)),
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCell({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
      color: color, fontFamily: 'Courier')),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 8, color: KratosTheme.muted, letterSpacing: 1)),
  ]));
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
    Container(width: 1, height: 36, color: KratosTheme.border);
}
