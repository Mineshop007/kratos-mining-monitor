import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/miner_store.dart';
import '../utils/block_calc.dart';
import '../services/btc_price.dart';

class FleetSummaryBar extends StatelessWidget {
  const FleetSummaryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MinerStore>(builder: (ctx, store, _) {
      final total = store.totalHashrate;
      final totalStr = total >= 1000
          ? '${(total / 1000).toStringAsFixed(1)} TH'
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
        child: Column(children: [
          // Row 1: hashrate | online | warning | offline
          Row(children: [
            _StatBlock(
              label: 'TOTAL HASHRATE',
              value: totalStr,
              color: KratosColors.of(context).accent,
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
          // Row 2: total power | fleet efficiency
          if (store.totalPower > 0) ...[  
            Container(height: 1, color: const Color(0xFF21262d)),
            Row(children: [
              _StatBlock(
                label: 'TOTAL POWER',
                value: store.totalPower >= 1000
                    ? '${(store.totalPower / 1000).toStringAsFixed(2)} kW'
                    : '${store.totalPower.toStringAsFixed(0)} W',
                color: const Color(0xFFffa657),
                icon: Icons.power,
              ),
              _Separator(),
              _StatBlock(
                label: 'FLEET J/TH',
                value: store.fleetEfficiency > 0
                    ? '${store.fleetEfficiency.toStringAsFixed(1)}'
                    : '--',
                color: _effColor(store.fleetEfficiency),
                icon: Icons.speed,
              ),
              _Separator(),
              _StatBlock(
                label: 'DAILY COST',
                value: store.totalDailyCostUsd > 0
                    ? '\$${store.totalDailyCostUsd.toStringAsFixed(2)}'
                    : '--',
                color: const Color(0xFF8b949e),
                icon: Icons.attach_money,
              ),
              _Separator(),
              // Show SOLO LUCK (expected block time) for fleet
              Builder(builder: (ctx) {
                final networkThs = BlockCalc.networkHashrateThs();
                final fleetThs = total / 1000.0;
                final hasSoloPools = store.stats.values.any((s) =>
                  s.pools.any((p) => BlockCalc.isSoloPool(p.url)));
                if (hasSoloPools && networkThs > 0 && fleetThs > 0) {
                  final days = BlockCalc.expectedDays(fleetThs, networkThs);
                  return _StatBlock(
                    label: 'SOLO LUCK',
                    value: BlockCalc.formatExpectedTime(days),
                    color: KratosTheme.orange,
                    icon: Icons.casino_outlined,
                  );
                }
                final net = store.totalDailyEarningsUsd - store.totalDailyCostUsd;
                return _StatBlock(
                  label: 'NET/DAY',
                  value: net >= 0 ? '\$${net.toStringAsFixed(2)}' : '-\$${net.abs().toStringAsFixed(2)}',
                  color: net >= 0 ? const Color(0xFF39d353) : const Color(0xFFff4d4d),
                  icon: Icons.trending_up,
                );
              }),
            ]),
          ],
        ]),
      );
    });
  }
}

Color _effColor(double jth) {
  if (jth <= 0)  return const Color(0xFF6e7681);
  if (jth < 15)  return const Color(0xFF39d353); // excellent
  if (jth < 22)  return const Color(0xFFffd700); // good
  if (jth < 30)  return const Color(0xFFffa657); // average
  return const Color(0xFFff4d4d);                // hot
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
              Flexible(child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFamily: 'Courier',
                ))),
              if (subValue != null)
                Text(subValue!, style: const TextStyle(
                  fontSize: 10,
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
