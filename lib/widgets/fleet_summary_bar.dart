import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/miner_store.dart';
import '../utils/block_calc.dart';
import '../services/btc_price.dart';
import '../screens/solo_luck_sheet.dart';

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
              GestureDetector(
                onTap: store.totalDailyCostUsd > 0
                    ? () => showModalBottomSheet(
                          context: ctx,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _CostBreakdownSheet(
                            dailyCostUsd: store.totalDailyCostUsd,
                            dailyEarningsUsd: store.totalDailyEarningsUsd,
                            totalPowerW: store.totalPower,
                            kwhPrice: store.kwhPrice,
                          ),
                        )
                    : null,
                child: _StatBlock(
                  label: 'DAILY COST',
                  value: store.totalDailyCostUsd > 0
                      ? '\$${store.totalDailyCostUsd.toStringAsFixed(2)}'
                      : '--',
                  color: const Color(0xFF8b949e),
                  icon: Icons.attach_money,
                  tappable: store.totalDailyCostUsd > 0,
                ),
              ),
              _Separator(),
              // Show SOLO LUCK (expected block time) for fleet
              Builder(builder: (ctx) {
                final networkThs = BlockCalc.networkHashrateThs();
                final fleetThs = total / 1000.0;
                final hasSoloPools = store.stats.values.any((s) =>
                  s.pools.any((p) => BlockCalc.isSoloPool(p.url)));
                if (hasSoloPools && networkThs > 0 && fleetThs > 0) {
                  return GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: ctx,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => SoloLuckSheet(fleetHashrateThs: fleetThs),
                    ),
                    child: _StatBlock(
                      label: 'SOLO/MO',
                      value: BlockCalc.formatOneInX(fleetThs, networkThs),
                      color: KratosTheme.orange,
                      icon: Icons.casino_outlined,
                      tappable: true,
                    ),
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
  final bool tappable;

  const _StatBlock({
    required this.label,
    required this.value,
    this.subValue,
    required this.color,
    required this.icon,
    this.tappable = false,
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
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: const TextStyle(
              fontSize: 8,
              color: Color(0xFF6e7681),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            )),
            if (tappable) ...[  
              const SizedBox(width: 2),
              const Icon(Icons.touch_app, size: 7,
                  color: Color(0xFF6e7681)),
            ],
          ]),
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

// ── Cost Breakdown Sheet ─────────────────────────────────────────────────────

class _CostBreakdownSheet extends StatelessWidget {
  final double dailyCostUsd;
  final double dailyEarningsUsd;
  final double totalPowerW;
  final double kwhPrice;

  const _CostBreakdownSheet({
    required this.dailyCostUsd,
    required this.dailyEarningsUsd,
    required this.totalPowerW,
    required this.kwhPrice,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final monthlyCost  = dailyCostUsd * 30;
    final yearlyCost   = dailyCostUsd * 365;
    final monthlyEarn  = dailyEarningsUsd * 30;
    final yearlyEarn   = dailyEarningsUsd * 365;
    final netDay       = dailyEarningsUsd - dailyCostUsd;
    final netMonth     = monthlyEarn - monthlyCost;
    final netYear      = yearlyEarn  - yearlyCost;
    final dailyKwh     = totalPowerW * 24 / 1000;

    String fmt(double v) => v >= 0
        ? '\$${v.toStringAsFixed(2)}'
        : '-\$${v.abs().toStringAsFixed(2)}';
    Color netColor(double v) =>
        v >= 0 ? kc.accent : const Color(0xFFff4d4d);

    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: kc.line,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),

        // Header
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cost & Earnings Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: kc.text)),
            Text('${totalPowerW.toStringAsFixed(0)} W  ·  '
                '${dailyKwh.toStringAsFixed(1)} kWh/day  ·  '
                '\$$kwhPrice/kWh',
                style: TextStyle(fontSize: 11, color: kc.muted)),
          ])),
        ]),
        const SizedBox(height: 20),

        // Table header
        _TableRow('Period', 'Cost', 'Earnings', 'Net', kc, isHeader: true),
        Divider(height: 8, color: kc.line),

        // Rows
        _TableRow('Daily',
            '\$${dailyCostUsd.toStringAsFixed(2)}',
            '\$${dailyEarningsUsd.toStringAsFixed(2)}',
            fmt(netDay), kc, netColor: netColor(netDay)),
        const SizedBox(height: 4),
        _TableRow('Monthly (30d)',
            '\$${monthlyCost.toStringAsFixed(2)}',
            '\$${monthlyEarn.toStringAsFixed(2)}',
            fmt(netMonth), kc, netColor: netColor(netMonth)),
        const SizedBox(height: 4),
        _TableRow('Yearly',
            '\$${yearlyCost.toStringAsFixed(0)}',
            '\$${yearlyEarn.toStringAsFixed(0)}',
            fmt(netYear), kc, netColor: netColor(netYear),
            bold: true),

        const SizedBox(height: 16),
        Divider(height: 1, color: kc.line),
        const SizedBox(height: 12),

        // kWh detail
        _DetailRow('Electricity rate', '\$$kwhPrice / kWh', kc),
        _DetailRow('Daily consumption',
            '${dailyKwh.toStringAsFixed(1)} kWh', kc),
        _DetailRow('Monthly consumption',
            '${(dailyKwh * 30).toStringAsFixed(0)} kWh', kc),
        _DetailRow('Yearly consumption',
            '${(dailyKwh * 365).toStringAsFixed(0)} kWh', kc),
      ]),
    );
  }
}

class _TableRow extends StatelessWidget {
  final String period, cost, earnings, net;
  final KratosPalette kc;
  final Color? netColor;
  final bool isHeader;
  final bool bold;

  const _TableRow(this.period, this.cost, this.earnings, this.net, this.kc,
      {this.netColor, this.isHeader = false, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: isHeader ? 10 : 13,
      fontWeight: (isHeader || bold) ? FontWeight.w800 : FontWeight.w600,
      color: isHeader ? kc.muted : kc.text,
      fontFamily: isHeader ? null : 'Courier',
      letterSpacing: isHeader ? 1 : 0,
    );
    return Row(children: [
      Expanded(flex: 4, child: Text(period, style: style)),
      Expanded(flex: 3, child: Text(cost, style: style.copyWith(
          color: isHeader ? kc.muted : const Color(0xFFff4d4d)),
          textAlign: TextAlign.right)),
      Expanded(flex: 3, child: Text(earnings, style: style.copyWith(
          color: isHeader ? kc.muted : kc.accent),
          textAlign: TextAlign.right)),
      Expanded(flex: 3, child: Text(net, style: style.copyWith(
          color: isHeader ? kc.muted : (netColor ?? kc.text)),
          textAlign: TextAlign.right)),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final KratosPalette kc;
  const _DetailRow(this.label, this.value, this.kc);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: kc.muted)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: kc.text, fontFamily: 'Courier')),
    ]),
  );
}
