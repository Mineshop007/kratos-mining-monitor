import '../models/coin.dart';
import '../models/pool_preset.dart';

class PoolCatalogEntry {
  final String id;
  final String name;
  final String host;
  final int port;
  final String description;
  final String workerHint;
  final String password;
  final WorkerFormat format;
  final bool isSolo;
  final Coin coin;
  final String region;

  const PoolCatalogEntry({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.description,
    required this.workerHint,
    this.password = 'x',
    this.format = WorkerFormat.accountWorker,
    this.isSolo = false,
    required this.coin,
    this.region = 'global',
  });

  String get stratumUrl => 'stratum+tcp://$host:$port';
  bool get isAutoExchange => coin == Coin.sha256Auto;

  PoolPreset toPreset({String worker = ''}) => PoolPreset(
        id: id,
        name: name,
        host: host,
        port: port,
        worker: worker,
        password: password,
        format: format,
        isSolo: isSolo,
        coin: coin,
        algo: MiningAlgo.sha256,
        region: region,
        isCurated: true,
        createdAt: DateTime.now(),
      );
}

class PoolCatalogService {
  static const List<PoolCatalogEntry> sha256 = [
    PoolCatalogEntry(
      id: 'btc-mineshop-solo',
      name: 'Mineshop Solo',
      host: 'solo.mineshop.eu',
      port: 3333,
      description: 'Mineshop solo pool — win the full BTC block reward.',
      workerHint: 'Your BTC address',
      format: WorkerFormat.btcAddressWorker,
      isSolo: true,
      coin: Coin.btc,
      region: 'EU',
    ),
    PoolCatalogEntry(
      id: 'btc-ckpool-solo',
      name: 'CKPool Solo',
      host: 'solo.ckpool.org',
      port: 3333,
      description: 'Original Bitcoin solo pool.',
      workerHint: 'Your BTC address',
      format: WorkerFormat.btcAddressWorker,
      isSolo: true,
      coin: Coin.btc,
    ),
    PoolCatalogEntry(
      id: 'btc-public-pool',
      name: 'Public Pool BTC',
      host: 'public-pool.io',
      port: 21496,
      description: 'Open-source Bitcoin solo pool.',
      workerHint: 'Your BTC address',
      format: WorkerFormat.btcAddressWorker,
      isSolo: true,
      coin: Coin.btc,
    ),
    PoolCatalogEntry(
      id: 'btc-ocean',
      name: 'Ocean BTC',
      host: 'mine.ocean.xyz',
      port: 3334,
      description: 'Bitcoin pool focused on template transparency.',
      workerHint: 'BTC address or Ocean username.worker',
      format: WorkerFormat.btcAddressWorker,
      coin: Coin.btc,
    ),
    PoolCatalogEntry(
      id: 'btc-braiins',
      name: 'Braiins BTC',
      host: 'stratum.braiins.com',
      port: 3333,
      description: 'Regular Bitcoin pool payouts.',
      workerHint: 'username.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.btc,
    ),
    PoolCatalogEntry(
      id: 'btc-viabtc',
      name: 'ViaBTC BTC',
      host: 'btc.viabtc.io',
      port: 3333,
      description: 'ViaBTC Bitcoin pool.',
      workerHint: 'username.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.btc,
    ),
    PoolCatalogEntry(
      id: 'btc-nicehash',
      name: 'NiceHash SHA-256',
      host: 'sha256.eu.nicehash.com',
      port: 3334,
      description: 'Sell SHA-256 hashrate for BTC.',
      workerHint: 'NiceHash BTC wallet',
      format: WorkerFormat.btcAddress,
      coin: Coin.btc,
      region: 'EU',
    ),
    PoolCatalogEntry(
      id: 'bch-viabtc',
      name: 'ViaBTC BCH',
      host: 'bch.viabtc.io',
      port: 3333,
      description: 'Dedicated Bitcoin Cash pool endpoint.',
      workerHint: 'ViaBTC username.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.bch,
    ),
    PoolCatalogEntry(
      id: 'bch-viabtc-eu',
      name: 'ViaBTC BCH EU',
      host: 'bch.powhashing.com',
      port: 3333,
      description: 'ViaBTC European BCH endpoint.',
      workerHint: 'ViaBTC username.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.bch,
      region: 'EU',
    ),
    PoolCatalogEntry(
      id: 'bch-f2pool',
      name: 'F2Pool BCH',
      host: 'b4c.f2pool.com',
      port: 1228,
      description: 'F2Pool Bitcoin Cash mining endpoint.',
      workerHint: 'F2Pool account.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.bch,
    ),
    PoolCatalogEntry(
      id: 'bch-solomining',
      name: 'SoloMining BCH',
      host: 'stratum.solomining.io',
      port: 5566,
      description: 'Anonymous Bitcoin Cash solo pool.',
      workerHint: 'Your BCH address',
      format: WorkerFormat.bchAddressWorker,
      isSolo: true,
      coin: Coin.bch,
    ),
    PoolCatalogEntry(
      id: 'sha256-binance',
      name: 'Binance SHA-256',
      host: 'sha256.poolbinance.com',
      port: 3333,
      description: 'Binance SHA-256 pool for BTC/BCH/BSV accounts.',
      workerHint: 'Binance mining account.worker',
      format: WorkerFormat.accountWorker,
      coin: Coin.sha256Auto,
    ),
    PoolCatalogEntry(
      id: 'sha256-zergpool-bch',
      name: 'Zergpool BCH Auto',
      host: 'sha256.mine.zergpool.com',
      port: 3333,
      description: 'Auto-exchange SHA-256 pool, locked to BCH mining.',
      workerHint: 'BCH wallet, password c=BCH,mc=BCH',
      password: 'c=BCH,mc=BCH',
      format: WorkerFormat.autoExchangeWallet,
      coin: Coin.sha256Auto,
    ),
  ];

  static List<PoolCatalogEntry> forCoin(Coin coin) {
    if (coin == Coin.sha256Auto) {
      return sha256.where((p) => p.coin == Coin.sha256Auto).toList();
    }
    return sha256.where((p) => p.coin == coin).toList();
  }

  static List<Coin> get sha256Coins => const [
        Coin.btc,
        Coin.bch,
        Coin.sha256Auto,
      ];

  static Coin inferCoinFromHost(String host) {
    final h = host.toLowerCase();
    if (h.contains('bch') || h.contains('b4c') || h.contains('bitcoin-cash')) {
      return Coin.bch;
    }
    if (h.contains('zergpool') ||
        h.contains('zpool') ||
        h.contains('binance')) {
      return Coin.sha256Auto;
    }
    return Coin.btc;
  }
}
