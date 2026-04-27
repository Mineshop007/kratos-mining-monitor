import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/miner_store.dart';

class FleetSummaryBar extends StatelessWidget {
  const FleetSummaryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final total = store.totalHashrate;
      final totalStr = total >= 1000
          ? '${(total / 1000).toStringAsFixed(2)} TH/s'
          : '${total.toStringAsFixed(1)} GH/s';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1a1f2e).withOpacity(0.95),
              const Color(0xFF252b3b).withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF30363D).withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          _StatBlock(
            label: 'TOTAL HASHRATE',
            value: totalStr,
            color: KratosTheme.neon,
            icon: Icons.flash_on,
          ),
          _Separator(),
          _StatBlock(
            label: 'ONLINE',
            value: '${store.onlineCount}',
            subValue: '/ ${store.miners.length}',
            color: const Color(0xFF39d353),
            icon: Icons.check_circle_outline,
          ),
          _Separator(),
          _StatBlock(
            label: 'WARNING',
            value: '${store.warningCount}',
            color: const Color(0xFFffd700),
            icon: Icons.warning_amber_outlined,
          ),
          _Separator(),
          _StatBlock(
            label: 'OFFLINE',
            value: '${store.offlineCount}',
            color: const Color(0xFFff4d4d),
            icon: Icons.power_off_outlined,
          ),
        ]),
      );
    });
  }
}

class _StatBlock extends StatelessWidget {
  final String label, value;
  final String? subValue;
  final Color color;
  final IconData icon;

  const _StatBlock({
    required this.label,
    required this.value,
    this.subValue,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withOpacity(0.8)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
                fontFamily: 'Courier',
              )),
              if (subValue != null)
                Text(subValue!, style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6e7681),
                  fontFamily: 'Courier',
                )),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
            fontSize: 8,
            color: Color(0xFF6e7681),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          )),
        ],
      ),
    ),
  );
}

class _Separator extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
    Container(width: 1, height: 40, color: const Color(0xFF21262d));
}
