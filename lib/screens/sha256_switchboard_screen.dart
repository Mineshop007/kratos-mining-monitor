import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coin.dart';
import '../models/miner.dart';
import '../services/address_validator.dart';
import '../services/btc_price.dart';
import '../services/coin_price_service.dart';
import '../services/miner_store.dart';
import '../services/pool_apply_service.dart';
import '../services/pool_catalog_service.dart';
import '../theme/volt_theme.dart';
import 'pool_editor_screen.dart';

class Sha256SwitchboardScreen extends StatelessWidget {
  const Sha256SwitchboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('SHA-256 Switchboard',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w900)),
      ),
      body: Consumer2<MinerStore, CoinPriceService>(
        builder: (ctx, store, prices, _) {
          final miners = store.miners
              .where((m) =>
                  m.type.apiType == ApiType.espMinerHttp ||
                  m.type.apiType == ApiType.avalonHttp ||
                  m.type.apiType == ApiType.cgminerTcp)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Hero(store: store, prices: prices),
              const SizedBox(height: 14),
              _CoinCompare(store: store, prices: prices),
              const SizedBox(height: 14),
              _PoolRail(),
              const SizedBox(height: 18),
              Text('Switch miners',
                  style: TextStyle(
                      color: kc.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
              const SizedBox(height: 8),
              if (miners.isEmpty)
                _Empty(kc: kc)
              else
                for (final miner in miners)
                  _MinerSwitchRow(
                    miner: miner,
                    stats: store.stats[miner.id],
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final MinerStore store;
  final CoinPriceService prices;
  const _Hero({required this.store, required this.prices});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final th = store.totalHashrate / 1000.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KratosColors.cyan.withOpacity(0.22),
            Coin.bch.color.withOpacity(0.12),
            kc.surface.withOpacity(0.9),
          ],
        ),
        border: Border.all(color: KratosColors.cyan.withOpacity(0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, color: KratosColors.cyan),
          const SizedBox(width: 8),
          Text('BTC ⇄ BCH CONTROL',
              style: TextStyle(
                color: KratosColors.cyan,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w900,
              )),
        ]),
        const SizedBox(height: 10),
        Text('Point your SHA-256 fleet where it makes sense.',
            style: TextStyle(
              color: kc.text,
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 10),
        Text(
          'Compare BTC, BCH and smart SHA-256 pools, then open any miner to apply the right preset without hunting for stratum URLs.',
          style: TextStyle(color: kc.muted, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _StatPill(
              label: 'Fleet',
              value: '${th.toStringAsFixed(th >= 10 ? 1 : 2)} TH/s'),
          const SizedBox(width: 8),
          _StatPill(label: 'BTC', value: _price(prices, Coin.btc)),
          const SizedBox(width: 8),
          _StatPill(label: 'BCH', value: _price(prices, Coin.bch)),
        ]),
      ]),
    );
  }

  static String _price(CoinPriceService prices, Coin coin) {
    final p = prices.priceFor(coin);
    if (p == null) return '—';
    if (p >= 1000)
      return '${prices.fiat.toUpperCase()} ${p.toStringAsFixed(0)}';
    return '${prices.fiat.toUpperCase()} ${p.toStringAsFixed(2)}';
  }
}

class _CoinCompare extends StatelessWidget {
  final MinerStore store;
  final CoinPriceService prices;
  const _CoinCompare({required this.store, required this.prices});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: _CoinCard(
              coin: Coin.btc,
              host: 'solo.mineshop.eu',
              price: prices.priceFor(Coin.btc),
              dailyUsd: BtcPriceService.instance
                  .dailyEarningsUsdForCoin(store.totalHashrate, Coin.btc))),
      const SizedBox(width: 10),
      Expanded(
          child: _CoinCard(
              coin: Coin.bch,
              host: 'bch.viabtc.io',
              price: prices.priceFor(Coin.bch),
              dailyUsd: BtcPriceService.instance
                  .dailyEarningsUsdForCoin(store.totalHashrate, Coin.bch))),
    ]);
  }
}

class _CoinCard extends StatelessWidget {
  final Coin coin;
  final String host;
  final double? price;
  final double dailyUsd;
  const _CoinCard(
      {required this.coin,
      required this.host,
      required this.price,
      required this.dailyUsd});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: coin.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: coin.color.withOpacity(0.24)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(coin.ticker,
            style: TextStyle(
                color: coin.color, fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 4),
        Text(host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kc.muted, fontSize: 11)),
        const SizedBox(height: 8),
        Text(
            price == null
                ? 'price syncing'
                : price!.toStringAsFixed(price! > 1000 ? 0 : 2),
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text('\$${dailyUsd.toStringAsFixed(dailyUsd >= 10 ? 1 : 2)}/day fleet',
            style: TextStyle(
                color: coin.color, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _PoolRail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final pools = PoolCatalogService.sha256;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Curated pools',
          style: TextStyle(
              color: kc.text, fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 8),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: pools.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = pools[i];
            return GestureDetector(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _ApplyCatalogSheet(pool: p),
              ),
              child: Container(
                width: 150,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kc.surface.withOpacity(0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.coin.color.withOpacity(0.25)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.coin.color,
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(p.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: kc.muted,
                              fontFamily: 'monospace',
                              fontSize: 10)),
                      const Spacer(),
                      Row(children: [
                        Expanded(
                          child: Text(
                              p.isSolo
                                  ? '${p.coin.ticker} SOLO'
                                  : '${p.coin.ticker} POOL',
                              style: TextStyle(
                                  color: kc.muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                        ),
                        Icon(Icons.touch_app_rounded,
                            size: 13, color: p.coin.color),
                      ]),
                    ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ApplyCatalogSheet extends StatefulWidget {
  final PoolCatalogEntry pool;
  const _ApplyCatalogSheet({required this.pool});

  @override
  State<_ApplyCatalogSheet> createState() => _ApplyCatalogSheetState();
}

class _ApplyCatalogSheetState extends State<_ApplyCatalogSheet> {
  final _worker = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _applying = false;
  bool _initializedSelection = false;
  List<PoolApplyResult> _results = [];

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  Future<void> _apply(MinerStore store) async {
    final miners =
        store.miners.where((m) => _selectedIds.contains(m.id)).toList();
    if (miners.isEmpty || _worker.text.trim().isEmpty) return;
    setState(() {
      _applying = true;
      _results = [];
    });

    final results = <PoolApplyResult>[];
    for (final miner in miners) {
      final result = await PoolApplyService.applyCatalogPool(
        miner: miner,
        pool: widget.pool,
        worker: _worker.text,
      );
      results.add(result);
      setState(() => _results = List.of(results));
    }
    await store.save();
    await store.refreshAll();
    if (mounted) setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final pool = widget.pool;
    return Consumer<MinerStore>(
      builder: (context, store, _) {
        final miners = store.miners
            .where((m) =>
                m.type.apiType == ApiType.espMinerHttp ||
                m.type.apiType == ApiType.avalonHttp ||
                m.type.apiType == ApiType.cgminerTcp)
            .toList();
        if (!_initializedSelection && miners.isNotEmpty) {
          _selectedIds.addAll(miners.map((m) => m.id));
          _initializedSelection = true;
        }
        final validation = AddressValidator.validateForPool(
          coin: pool.coin,
          format: pool.format,
          worker: _worker.text,
        );
        final canApply = _worker.text.trim().isNotEmpty &&
            _selectedIds.isNotEmpty &&
            !_applying;

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: kc.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                  top: BorderSide(color: pool.coin.color.withOpacity(0.35))),
            ),
            child: SafeArea(
              top: false,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: kc.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: pool.coin.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: pool.coin.color.withOpacity(0.35)),
                      ),
                      child: Center(
                        child: Text(pool.coin.ticker,
                            style: TextStyle(
                                color: pool.coin.color,
                                fontWeight: FontWeight.w900,
                                fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pool.name,
                                style: TextStyle(
                                    color: kc.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 19)),
                            const SizedBox(height: 2),
                            Text(pool.stratumUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: kc.muted,
                                    fontFamily: 'monospace',
                                    fontSize: 11)),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Text('Wallet / account',
                      style: TextStyle(
                          color: kc.muted,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.4)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _worker,
                    onChanged: (_) => setState(() {}),
                    autocorrect: false,
                    style: TextStyle(color: kc.text, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: pool.workerHint,
                      hintStyle: TextStyle(color: kc.muted, fontSize: 12),
                      filled: true,
                      fillColor: kc.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kc.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: pool.coin.color),
                      ),
                    ),
                  ),
                  if (!validation.ok && _worker.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(validation.message,
                        style: TextStyle(
                            color: KratosColors.warning,
                            fontSize: 11,
                            height: 1.35)),
                  ],
                  if (pool.password != 'x') ...[
                    const SizedBox(height: 8),
                    Text('Password: ${pool.password}',
                        style: TextStyle(
                            color: kc.muted,
                            fontFamily: 'monospace',
                            fontSize: 11)),
                  ],
                  const SizedBox(height: 16),
                  Text('Apply to miners',
                      style: TextStyle(
                          color: kc.muted,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  for (final miner in miners)
                    CheckboxListTile(
                      value: _selectedIds.contains(miner.id),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: pool.coin.color,
                      title: Text(miner.name,
                          style: TextStyle(
                              color: kc.text, fontWeight: FontWeight.w700)),
                      subtitle: Text(miner.type.displayName,
                          style: TextStyle(color: kc.muted, fontSize: 11)),
                      onChanged: _applying
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selectedIds.add(miner.id);
                                } else {
                                  _selectedIds.remove(miner.id);
                                }
                              }),
                    ),
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final r in _results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(children: [
                          Icon(
                              r.success
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 15,
                              color:
                                  r.success ? kc.accent : KratosColors.danger),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text('${r.miner.name}: ${r.message}',
                                style: TextStyle(
                                    color: r.success
                                        ? kc.text
                                        : KratosColors.danger,
                                    fontSize: 12)),
                          ),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canApply ? () => _apply(store) : null,
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(_applying
                        ? 'Applying...'
                        : 'Apply to ${_selectedIds.length} miner${_selectedIds.length == 1 ? '' : 's'}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: pool.coin.color,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MinerSwitchRow extends StatelessWidget {
  final Miner miner;
  final MinerStats? stats;
  const _MinerSwitchRow({required this.miner, required this.stats});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final coin = miner.coin.isSha256 ? miner.coin : Coin.btc;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kc.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: coin.color.withOpacity(0.20)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: coin.color.withOpacity(0.13),
            border: Border.all(color: coin.color.withOpacity(0.35)),
          ),
          child: Center(
              child: Text(coin.ticker,
                  style: TextStyle(
                      color: coin.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11))),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(miner.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('${stats?.hashrateFormatted ?? 'waiting'} · ${_poolHost(stats)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: kc.muted, fontSize: 11)),
        ])),
        IconButton(
          tooltip: 'Open pool switcher',
          icon: Icon(Icons.tune_rounded, color: kc.accent),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PoolEditorScreen(
                miner: miner,
                currentPools: stats?.pools ?? const [],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static String _poolHost(MinerStats? stats) {
    if (stats == null || stats.pools.isEmpty) return 'no pool yet';
    final active =
        stats.pools.where((p) => p.active).firstOrNull ?? stats.pools.first;
    return active.host;
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: kc.bg.withOpacity(0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kc.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: kc.muted, fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: kc.text, fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final KratosPalette kc;
  const _Empty({required this.kc});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kc.line),
        ),
        child: Text(
            'Add a SHA-256 miner first. Bitaxe, NerdQaxe, Avalon, Antminer and Whatsminer will appear here.',
            style: TextStyle(color: kc.muted, height: 1.4)),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
