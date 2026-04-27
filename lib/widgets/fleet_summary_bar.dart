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
          ? '${(total/1000).toStringAsFixed(2)} TH/s'
          : '${total.toStringAsFixed(1)} GH/s';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Row(children: [
          _Pill(label: 'TOTAL', value: totalStr, color: KratosTheme.neon),
          const Spacer(),
          _Pill(label: 'ONLINE', value: '${store.onlineCount}/${store.miners.length}', color: KratosTheme.orange),
          const Spacer(),
          _Pill(label: 'MINERS', value: '${store.miners.length}', color: KratosTheme.blue),
        ]),
      );
    });
  }
}

class _Pill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Pill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
      color: color, fontFamily: 'Courier')),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 9, color: KratosTheme.muted, letterSpacing: 1.5)),
  ]);
}
