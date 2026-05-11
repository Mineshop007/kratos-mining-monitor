import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bitcoin_node.dart';
import '../services/bitcoin_node_service.dart';
import '../theme/volt_theme.dart';

class BitcoinNodeScreen extends StatelessWidget {
  const BitcoinNodeScreen({super.key});

  static const _bitcoinOrange = Color(0xFFF7931A);

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('Bitcoin Node', style: TextStyle(color: kc.text)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: kc.accent),
            onPressed: () => context.read<BitcoinNodeService>().refresh(),
          ),
        ],
      ),
      body: Consumer<BitcoinNodeService>(
        builder: (context, service, _) {
          final stats = service.stats;
          if (!service.hasConfig) {
            return Center(
              child: Text(
                'No Bitcoin node configured',
                style: TextStyle(color: kc.muted, fontSize: 14),
              ),
            );
          }
          return RefreshIndicator(
            color: kc.accent,
            backgroundColor: kc.surface,
            onRefresh: service.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              children: [
                _StatusSection(stats: stats),
                const SizedBox(height: 14),
                _NetworkSection(stats: stats),
                const SizedBox(height: 14),
                _MiningContextSection(stats: stats),
                const SizedBox(height: 14),
                _MempoolSection(stats: stats),
                const SizedBox(height: 14),
                _PeersSection(stats: stats),
              ],
            ),
          );
        },
      ),
    );
  }

  static Color statusColor(BuildContext context, NodeStatus status) {
    final kc = KratosColors.of(context);
    return switch (status) {
      NodeStatus.online => kc.accent,
      NodeStatus.syncing => KratosColors.warning,
      NodeStatus.offline => KratosColors.danger,
      NodeStatus.unknown => kc.muted,
    };
  }
}

class _StatusSection extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _StatusSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final color = BitcoinNodeScreen.statusColor(context, stats.status);
    final progress = stats.syncProgress.clamp(0, 1).toDouble();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_rounded,
                color: BitcoinNodeScreen._bitcoinOrange,
              ),
              const SizedBox(width: 10),
              Text(
                'Status',
                style: TextStyle(
                  color: kc.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              _StatusChip(status: stats.status, color: color),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            stats.localBlocks > 0 ? _fmtInt(stats.localBlocks) : '—',
            style: TextStyle(
              color: kc.text,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            stats.status == NodeStatus.offline
                ? 'Node offline'
                : 'current local block height',
            style: TextStyle(color: kc.muted, fontSize: 12),
          ),
          if (stats.status == NodeStatus.syncing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: kc.surface2,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(2)}%',
                  style: const TextStyle(
                    color: KratosColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _NetworkSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final behind = (stats.networkBlocks - stats.localBlocks).clamp(0, 1 << 31);
    return _Panel(
      title: 'Network',
      child: Row(
        children: [
          _Metric(label: 'LOCAL', value: _fmtInt(stats.localBlocks)),
          _Metric(label: 'TIP', value: _fmtInt(stats.networkBlocks)),
          _Metric(label: 'BEHIND', value: '$behind'),
        ],
      ),
    );
  }
}

class _MiningContextSection extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _MiningContextSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final pct = stats.difficultyAdjustmentPct;
    final sign = pct >= 0 ? '+' : '';
    return _Panel(
      title: 'Mining Context',
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.trending_up_rounded,
            label: 'Next difficulty adjustment',
            value:
                '$sign${pct.toStringAsFixed(1)}% in ${_fmtInt(stats.blocksUntilAdjustment)} blocks (${_days(stats.blocksUntilAdjustment)})',
            color: pct >= 0 ? KratosColors.warning : KratosColors.success,
          ),
          Divider(height: 22, color: KratosColors.of(context).line),
          _InfoRow(
            icon: Icons.event_rounded,
            label: 'Blocks to next halving',
            value:
                '${_fmtInt(stats.blocksToHalving)} blocks (${_days(stats.blocksToHalving)})',
            color: BitcoinNodeScreen._bitcoinOrange,
          ),
        ],
      ),
    );
  }
}

class _MempoolSection extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _MempoolSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Mempool',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Metric(label: 'TRANSACTIONS', value: _fmtInt(stats.mempoolTxCount)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeeChip(
                  label: 'Low',
                  value: stats.feeLow,
                  color: KratosColors.success),
              _FeeChip(
                  label: 'Med',
                  value: stats.feeMed,
                  color: KratosColors.warning),
              _FeeChip(
                  label: 'High',
                  value: stats.feeHigh,
                  color: BitcoinNodeScreen._bitcoinOrange),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeersSection extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _PeersSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Peers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Metric(label: 'IN', value: '${stats.connectionsIn}'),
              _Metric(label: 'OUT', value: '${stats.connectionsOut}'),
              _Metric(label: 'TOTAL', value: '${stats.totalConnections}'),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.code_rounded,
            label: 'Version',
            value: stats.version.isEmpty ? '—' : stats.version,
            color: KratosColors.info,
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Panel({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kc.accent.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!.toUpperCase(),
              style: TextStyle(
                color: kc.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: kc.muted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kc.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: kc.muted, fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: kc.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeeChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _FeeChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$label ${value.toStringAsFixed(0)} sat/vB',
        style: TextStyle(
          color: kc.text,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final NodeStatus status;
  final Color color;

  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      NodeStatus.online => 'Online',
      NodeStatus.syncing => 'Syncing',
      NodeStatus.offline => 'Offline',
      NodeStatus.unknown => 'Unknown',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _fmtInt(int value) {
  if (value <= 0) return '—';
  final s = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final left = s.length - i;
    buffer.write(s[i]);
    if (left > 1 && left % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

String _days(int blocks) {
  if (blocks <= 0) return '—';
  final days = blocks / 144.0;
  if (days < 2) return '~${(days * 24).round()} hours';
  return '~${days.round()} days';
}
