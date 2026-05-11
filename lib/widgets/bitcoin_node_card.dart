import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bitcoin_node.dart';
import '../screens/bitcoin_node_screen.dart';
import '../screens/settings_screen.dart';
import '../services/bitcoin_node_service.dart';
import '../theme/volt_theme.dart';

class BitcoinNodeCard extends StatelessWidget {
  const BitcoinNodeCard({super.key});

  static const _bitcoinOrange = Color(0xFFF7931A);

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Consumer<BitcoinNodeService>(
      builder: (context, service, _) {
        final stats = service.stats;
        final hasConfig = service.hasConfig;
        return Material(
          color: kc.bg.withValues(alpha: 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => hasConfig
                    ? const BitcoinNodeScreen()
                    : const SettingsScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kc.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: _statusColor(context, stats.status)
                        .withValues(alpha: 0.18)),
              ),
              child: hasConfig
                  ? _ConfiguredNode(stats: stats)
                  : const _SetupPrompt(),
            ),
          ),
        );
      },
    );
  }

  static Color _statusColor(BuildContext context, NodeStatus status) {
    final kc = KratosColors.of(context);
    return switch (status) {
      NodeStatus.online => kc.accent,
      NodeStatus.syncing => KratosColors.warning,
      NodeStatus.offline => KratosColors.danger,
      NodeStatus.unknown => kc.muted,
    };
  }
}

class _ConfiguredNode extends StatelessWidget {
  final BitcoinNodeStats stats;
  const _ConfiguredNode({required this.stats});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final statusColor = BitcoinNodeCard._statusColor(context, stats.status);
    final progress = stats.syncProgress.clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: BitcoinNodeCard._bitcoinOrange.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                '₿',
                style: TextStyle(
                  color: BitcoinNodeCard._bitcoinOrange,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bitcoin Node',
                style: TextStyle(
                  color: kc.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _StatusPill(status: stats.status, color: statusColor),
          ],
        ),
        const SizedBox(height: 12),
        if (stats.status == NodeStatus.offline)
          const Text(
            'Node offline',
            style: TextStyle(
              color: KratosColors.danger,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Block ${_fmtInt(stats.localBlocks)} / ${_fmtInt(stats.networkBlocks)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(progress >= 0.999 ? 0 : 2)}%',
                style: TextStyle(
                  color: stats.status == NodeStatus.syncing
                      ? KratosColors.warning
                      : kc.accentBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: kc.surface2,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${stats.totalConnections} peers  ·  ${_fmtInt(stats.mempoolTxCount)} txns in mempool',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kc.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            'Fees  ${stats.feeLow.toStringAsFixed(0)} · '
            '${stats.feeMed.toStringAsFixed(0)} · '
            '${stats.feeHigh.toStringAsFixed(0)}  sat/vB',
            style: TextStyle(
              color: kc.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  String _fmtInt(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final left = s.length - i;
      buffer.write(s[i]);
      if (left > 1 && left % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Row(
      children: [
        const Icon(Icons.dns_rounded, color: BitcoinNodeCard._bitcoinOrange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Bitcoin Node',
                style: TextStyle(
                  color: kc.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Track Core sync, fees, peers, and halving context',
                style: TextStyle(color: kc.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: kc.muted),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final NodeStatus status;
  final Color color;

  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      NodeStatus.online => 'LIVE',
      NodeStatus.syncing => 'SYNC',
      NodeStatus.offline => 'OFFLINE',
      NodeStatus.unknown => 'UNKNOWN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}
