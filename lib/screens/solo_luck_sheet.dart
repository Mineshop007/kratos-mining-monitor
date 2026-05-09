import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import '../utils/block_calc.dart';
import '../services/btc_price.dart';

/// Bottom sheet showing BTC + BCH solo block probability for the fleet.
class SoloLuckSheet extends StatelessWidget {
  final double fleetHashrateThs;
  const SoloLuckSheet({super.key, required this.fleetHashrateThs});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final btcNetwork = BtcPriceService.instance.networkHashrateThs;
    final bchNetwork = BtcPriceService.instance.bchNetworkHashrateThs;
    final btcPrice   = BtcPriceService.instance.cachedPrice;
    final bchPrice   = BtcPriceService.instance.bchPriceUsd;

    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: kc.line,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            const Text('🎲', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Solo Block Probability',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kc.text)),
              Text('Fleet: ${_fmtThs(fleetHashrateThs)} TH/s',
                  style: TextStyle(fontSize: 12, color: kc.muted)),
            ])),
          ]),
          const SizedBox(height: 20),

          // BTC section
          _CoinSection(
            coin: 'Bitcoin',
            ticker: 'BTC',
            emoji: '₿',
            color: const Color(0xFFF7931A),
            networkHashrateThs: btcNetwork,
            fleetHashrateThs: fleetHashrateThs,
            blockRewardUsd: 3.125 * btcPrice,
            coinPrice: btcPrice,
            ticker2: 'USD',
            kc: kc,
          ),
          const SizedBox(height: 16),

          // BCH section
          _CoinSection(
            coin: 'Bitcoin Cash',
            ticker: 'BCH',
            emoji: '₿',
            color: const Color(0xFF8DC351),
            networkHashrateThs: bchNetwork,
            fleetHashrateThs: fleetHashrateThs,
            blockRewardUsd: 3.125 * bchPrice,
            coinPrice: bchPrice,
            ticker2: 'USD',
            kc: kc,
            note: 'SHA-256 miners can mine BCH with same hardware',
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kc.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kc.line),
            ),
            child: Text(
              '⚠️  Solo mining is a game of luck. Expected times are averages — '
              'you could win on day 1 or wait much longer.',
              style: TextStyle(fontSize: 11, color: kc.muted, height: 1.4),
            ),
          ),
        ],
      )),
    );
  }

  String _fmtThs(double ths) {
    if (ths >= 1000) return (ths / 1000).toStringAsFixed(1) + 'k';
    return ths.toStringAsFixed(1);
  }
}

class _CoinSection extends StatelessWidget {
  final String coin, ticker, emoji, ticker2;
  final Color color;
  final double networkHashrateThs;
  final double fleetHashrateThs;
  final double blockRewardUsd;
  final double coinPrice;
  final String? note;
  final KratosPalette kc;

  const _CoinSection({
    required this.coin, required this.ticker, required this.emoji,
    required this.color, required this.networkHashrateThs,
    required this.fleetHashrateThs, required this.blockRewardUsd,
    required this.coinPrice, required this.ticker2, required this.kc,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final days     = BlockCalc.expectedDays(fleetHashrateThs, networkHashrateThs);
    final oneInMo  = BlockCalc.formatOneInX(fleetHashrateThs, networkHashrateThs);
    final probDay  = BlockCalc.probInDays(fleetHashrateThs, networkHashrateThs, 1);
    final probWeek = BlockCalc.probInDays(fleetHashrateThs, networkHashrateThs, 7);
    final probMo   = BlockCalc.probInDays(fleetHashrateThs, networkHashrateThs, 30);

    // Network EH/s display
    final netEhs = networkHashrateThs / 1e6;
    final netStr = netEhs >= 1
        ? '${netEhs.toStringAsFixed(1)} EH/s'
        : '${(networkHashrateThs / 1000).toStringAsFixed(0)} PH/s';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Coin header
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withOpacity(0.15),
                shape: BoxShape.circle),
            child: Center(child: Text(emoji,
                style: TextStyle(fontSize: 16, color: color))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(coin, style: TextStyle(fontWeight: FontWeight.w800,
                color: kc.text, fontSize: 15)),
            Text('Network: $netStr',
                style: TextStyle(fontSize: 11, color: kc.muted)),
          ]),
          const Spacer(),
          // Big "1 in X" badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Column(children: [
              Text(oneInMo, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w900, color: color,
                  fontFamily: 'Courier')),
              Text('monthly', style: TextStyle(fontSize: 9, color: color)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),

        // Stats grid
        _Row('Expected time', BlockCalc.formatExpectedTime(days), kc),
        _Row('Chance today', BlockCalc.formatProbPct(probDay), kc),
        _Row('Chance this week', BlockCalc.formatProbPct(probWeek), kc),
        _Row('Chance this month', BlockCalc.formatProbPct(probMo), kc),
        const Divider(height: 16),
        _Row('Block reward',
            '\$${blockRewardUsd >= 1000 ? (blockRewardUsd / 1000).toStringAsFixed(0) + "k" : blockRewardUsd.toStringAsFixed(0)}',
            kc, highlight: true, color: color),
        _Row('$ticker price',
            '\$${coinPrice >= 1000 ? (coinPrice / 1000).toStringAsFixed(1) + "k" : coinPrice.toStringAsFixed(0)}',
            kc),

        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: TextStyle(fontSize: 10, color: kc.muted,
              fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final KratosPalette kc;
  final bool highlight;
  final Color? color;
  const _Row(this.label, this.value, this.kc,
      {this.highlight = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: kc.muted)),
      const Spacer(),
      Text(value, style: TextStyle(
          fontSize: 12,
          fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
          color: highlight ? (color ?? kc.accent) : kc.text,
          fontFamily: 'Courier')),
    ]),
  );
}
