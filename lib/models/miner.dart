import 'coin.dart';

// ── Miner model ───────────────────────────────────────────────────────────────

enum ApiType { espMinerHttp, avalonHttp, cgminerTcp, fluMinerHttp }

enum MinerStatus { online, offline, warning, unknown }

enum MinerType {
  bitaxeGamma,
  bitaxeUltra,
  bitaxeGT,
  nerdqaxe,
  nerdoctaxe,
  avalonNano3s,
  avalonNano3,
  avalonMini3,
  avalonQ,
  antminer,
  whatsminer,
  goldshell,
  luckyMiner,
  fluMinerT3,
  generic;

  String get displayName => switch (this) {
        bitaxeGamma => 'BitAxe Gamma',
        bitaxeUltra => 'BitAxe Ultra',
        bitaxeGT => 'BitAxe GT',
        nerdqaxe => 'NerdQaxe++',
        nerdoctaxe => 'NerdOctaxe',
        avalonNano3s => 'Avalon Nano 3S',
        avalonNano3 => 'Avalon Nano 3',
        avalonMini3 => 'Avalon Mini 3',
        avalonQ => 'Avalon Q',
        antminer => 'Antminer',
        whatsminer => 'Whatsminer',
        goldshell => 'Goldshell',
        luckyMiner => 'Lucky Miner',
        fluMinerT3 => 'FluMiner T3',
        generic => 'Miner',
      };

  // ESP-Miner HTTP (port 80) for BitAxe family
  // Avalon HTTP REST for Canaan devices
  // CGMiner TCP (port 4028) for everything else
  ApiType get apiType => switch (this) {
        bitaxeGamma ||
        bitaxeUltra ||
        bitaxeGT ||
        nerdqaxe ||
        nerdoctaxe ||
        luckyMiner =>
          ApiType.espMinerHttp,
        fluMinerT3 => ApiType.fluMinerHttp,
        // Nano 3S and Nano 3: OpenWrt-based, HTTP REST API available
        avalonNano3s || avalonNano3 => ApiType.avalonHttp,
        // Mini 3 and Q: CGMiner TCP on port 4028 (standard Canaan protocol)
        avalonMini3 || avalonQ => ApiType.cgminerTcp,
        _ => ApiType.cgminerTcp,
      };

  int get defaultPort => switch (apiType) {
        ApiType.espMinerHttp => 80,
        ApiType.avalonHttp => 80,
        ApiType.fluMinerHttp => 80,
        ApiType.cgminerTcp => 4028,
      };

  static MinerType detect(String model) {
    final m = model.toLowerCase();
    if (m.contains('gamma')) return bitaxeGamma;
    if (m.contains('bm1368') || (m.contains('ultra') && m.contains('bitaxe')))
      return bitaxeUltra;
    if (m.contains('bm1370') ||
        m.contains('bm1371') ||
        (m.contains('gt') && m.contains('bitaxe'))) return bitaxeGT;
    if (m.contains('bm1366') || m.contains('bitaxe')) return bitaxeGamma;
    // NerdAxe firmware returns deviceModel like 'NerdQAxe++' or 'NerdOCTAXE-γ'
    if (m.contains('nerdqaxe') || m.contains('nerdqax') || m.contains('nerdq'))
      return nerdqaxe;
    if (m.contains('nerdoct') || m.contains('nerdoctaxe')) return nerdoctaxe;
    if (m.contains('nano3s') || m.contains('nano 3s') || m.contains('nano-3s'))
      return avalonNano3s;
    if (m.contains('mini3') ||
        m.contains('mini 3') ||
        m.contains('mini-3') ||
        m.contains('avalonmini') ||
        m.contains('1161')) return avalonMini3;
    if (m.contains('avalonq') ||
        m.contains('avalon q') ||
        m.contains('avalon-q') ||
        m.contains('avalonq90') ||
        m.contains('avalon_q')) return avalonQ;
    if (m.contains('nano3') || m.contains('nano 3') || m.contains('nano-3'))
      return avalonNano3;
    if (m.contains('antminer') || m.contains('bitmain')) return antminer;
    if (m.contains('whatsminer') || m.contains('microbt')) return whatsminer;
    if (m.contains('goldshell')) return goldshell;
    if (m.contains('lucky')) return luckyMiner;
    if (m.contains('fluminer') || m.contains('flu miner') ||
        (m.contains('flu') && m.contains('t3')) ||
        m == 'fluminer t3' || m == 't3') return fluMinerT3;
    if (m.contains('rev6') || m.contains('nerd') && m.contains('rev'))
      return nerdqaxe;
    return generic;
  }
}

class Miner {
  final String id;
  String name;
  String ip;
  int port;
  String notes;
  MinerType type;
  String remoteUrl; // optional override URL (e.g. for tunnels/proxies)
  bool isRemote; // true = API calls routed via RelayService
  int? psuWatts; // optional PSU rating in watts for autotune safety guard
  Coin coin; // selected mining/payout coin for UI, presets, estimates

  Miner({
    String? id,
    required this.name,
    required this.ip,
    this.port = 4028,
    this.notes = '',
    this.type = MinerType.generic,
    this.remoteUrl = '',
    this.isRemote = false,
    this.psuWatts,
    this.coin = Coin.btc,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'notes': notes,
        'type': type.name,
        'remoteUrl': remoteUrl,
        'isRemote': isRemote,
        'coin': coin.name,
        if (psuWatts != null) 'psuWatts': psuWatts,
      };

  factory Miner.fromJson(Map<String, dynamic> j) => Miner(
        id: j['id'],
        name: j['name'],
        ip: j['ip'],
        port: j['port'] ?? 4028,
        notes: j['notes'] ?? '',
        remoteUrl: j['remoteUrl'] as String? ?? '',
        isRemote: j['isRemote'] as bool? ?? false,
        psuWatts: (j['psuWatts'] as num?)?.toInt(),
        coin: Coin.values.firstWhere(
          (c) => c.name == (j['coin'] as String? ?? ''),
          orElse: () => Coin.btc,
        ),
        type: MinerType.values.firstWhere(
          (t) => t.name == (j['type'] as String? ?? ''),
          orElse: () => MinerType.generic,
        ),
      );
}

class MinerStats {
  final double hashrate5s; // GH/s — instantaneous
  final double hashrateAvg; // GH/s — 1-min avg (or rolling avg for CGMiner)
  final double hashRate1h; // GH/s — 1h average (ESP-Miner only)
  final double outTemp; // °C
  final int fanRPM;
  final int fanPercent;
  final int accepted;
  final int rejected;
  final int hardwareErrors;
  final int uptime; // seconds
  final List<PoolInfo> pools;
  final double frequency; // MHz
  final double powerDraw; // Watts
  final MinerStatus status;
  final DateTime lastUpdated;
  final String firmware;
  final String model;
  final MinerType type;
  final double bestShare;
  final List<double> hashrateHistory; // last 30 readings in GH/s
  final bool blockFound;
  final bool isUsingFallbackStratum;
  final int coreVoltage; // mV (ESP-Miner devices)
  final double vrTemp; // °C — voltage regulator / MOSFET temperature
  final int workMode; // Avalon Q: 0=Eco, 1=Standard, 2=Super (-1=unknown)
  final int minerState; // Avalon Q: 0=init, 1=working, 2=standby (-1=unknown)
  final double inletTemp; // Avalon Q ITemp — chassis/inlet temperature (°C)
  bool get isStandby => minerState == 2;

  MinerStats({
    this.hashrate5s = 0,
    this.hashrateAvg = 0,
    this.hashRate1h = 0,
    this.outTemp = 0,
    this.fanRPM = 0,
    this.fanPercent = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.hardwareErrors = 0,
    this.uptime = 0,
    this.pools = const [],
    this.frequency = 0,
    this.powerDraw = 0,
    this.status = MinerStatus.unknown,
    DateTime? lastUpdated,
    this.firmware = '',
    this.model = '',
    this.type = MinerType.generic,
    this.bestShare = 0,
    this.hashrateHistory = const [],
    this.blockFound = false,
    this.isUsingFallbackStratum = false,
    this.coreVoltage = 0,
    this.vrTemp = 0,
    this.workMode = -1,
    this.minerState = -1,
    this.inletTemp = 0,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  static MinerStats get offline => MinerStats(status: MinerStatus.offline);

  /// Fill in zero/empty fields from [other] — used when HTTP gives hashrate
  /// but CGMiner gives bestShare, pools, etc.
  MinerStats supplement(MinerStats other) => MinerStats(
        hashrate5s: hashrate5s > 0 ? hashrate5s : other.hashrate5s,
        hashrateAvg: hashrateAvg > 0 ? hashrateAvg : other.hashrateAvg,
        hashRate1h: hashRate1h > 0 ? hashRate1h : other.hashRate1h,
        outTemp: outTemp > 0 ? outTemp : other.outTemp,
        fanRPM: fanRPM > 0 ? fanRPM : other.fanRPM,
        fanPercent: fanPercent > 0 ? fanPercent : other.fanPercent,
        accepted: accepted > 0 ? accepted : other.accepted,
        rejected: rejected > 0 ? rejected : other.rejected,
        hardwareErrors:
            hardwareErrors > 0 ? hardwareErrors : other.hardwareErrors,
        uptime: uptime > 0 ? uptime : other.uptime,
        pools: pools.isNotEmpty ? pools : other.pools,
        frequency: frequency > 0 ? frequency : other.frequency,
        powerDraw: powerDraw > 0 ? powerDraw : other.powerDraw,
        bestShare: bestShare > 0 ? bestShare : other.bestShare,
        hashrateHistory: hashrateHistory,
        status: status,
        lastUpdated: lastUpdated,
        firmware: firmware.isNotEmpty ? firmware : other.firmware,
        model: model.isNotEmpty ? model : other.model,
        type: type != MinerType.generic ? type : other.type,
        blockFound: blockFound || other.blockFound,
        isUsingFallbackStratum: isUsingFallbackStratum,
        coreVoltage: coreVoltage > 0 ? coreVoltage : other.coreVoltage,
        workMode: workMode >= 0 ? workMode : other.workMode,
        minerState: minerState >= 0 ? minerState : other.minerState,
        inletTemp: inletTemp > 0 ? inletTemp : other.inletTemp,
      );

  MinerStats withHistory(List<double> history) => MinerStats(
        hashrate5s: hashrate5s,
        hashrateAvg: hashrateAvg,
        hashRate1h: hashRate1h,
        outTemp: outTemp,
        fanRPM: fanRPM,
        fanPercent: fanPercent,
        accepted: accepted,
        rejected: rejected,
        hardwareErrors: hardwareErrors,
        uptime: uptime,
        pools: pools,
        frequency: frequency,
        powerDraw: powerDraw,
        status: status,
        lastUpdated: lastUpdated,
        firmware: firmware,
        model: model,
        type: type,
        bestShare: bestShare,
        hashrateHistory: history,
        blockFound: blockFound,
        isUsingFallbackStratum: isUsingFallbackStratum,
        coreVoltage: coreVoltage,
        vrTemp: vrTemp,
        workMode: workMode,
        minerState: minerState,
        inletTemp: inletTemp,
      );

  // Computed
  double get efficiency => powerDraw > 0 && hashrateDisplay > 0
      ? powerDraw / (hashrateDisplay / 1000.0)
      : 0;
  double get rejectRate =>
      accepted > 0 ? rejected / (accepted + rejected) * 100 : 0;

  /// Format bestShare as human-readable difficulty string (T / G / M / K)
  String get bestShareFormatted {
    if (bestShare <= 0) return '--';
    if (bestShare >= 1e12) return '${(bestShare / 1e12).toStringAsFixed(2)}T';
    if (bestShare >= 1e9) return '${(bestShare / 1e9).toStringAsFixed(1)}G';
    if (bestShare >= 1e6) return '${(bestShare / 1e6).toStringAsFixed(1)}M';
    if (bestShare >= 1e3) return '${(bestShare / 1e3).toStringAsFixed(1)}K';
    return bestShare.toStringAsFixed(0);
  }

  String get uptimeFormatted {
    if (uptime < 60) return '${uptime}s';
    if (uptime < 3600) return '${uptime ~/ 60}m';
    if (uptime < 86400) return '${uptime ~/ 3600}h ${(uptime % 3600) ~/ 60}m';
    return '${uptime ~/ 86400}d ${(uptime % 86400) ~/ 3600}h';
  }

  /// Live hashrate — prefer 5s instantaneous, fall back to rolling avg.
  double get hashrateDisplay => hashrate5s > 0 ? hashrate5s : hashrateAvg;

  String get hashrateFormatted {
    final v = hashrateDisplay;
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)} TH/s';
    if (v >= 1) return '${v.toStringAsFixed(1)} GH/s';
    return '${(v * 1000).toStringAsFixed(0)} MH/s';
  }

  // +1 = up, 0 = flat, -1 = down
  int get trendDirection {
    final ref = hashRate1h > 0
        ? hashRate1h
        : (hashrateHistory.length >= 6
            ? hashrateHistory.take(6).reduce((a, b) => a + b) / 6
            : 0.0);
    if (ref <= 0 || hashrateAvg <= 0) return 0;
    final diff = (hashrateAvg - ref) / ref * 100;
    if (diff > 1.0) return 1;
    if (diff < -1.0) return -1;
    return 0;
  }

  // Daily earnings estimate in BTC (simplified)
  double dailyBtc(double networkBtcPerThPerDay) {
    final hashrateTh = hashrateAvg / 1000.0;
    return hashrateTh * networkBtcPerThPerDay;
  }
}

class PoolInfo {
  final int index;
  final String url;
  final String user;
  final String status;
  final int accepted;
  final int rejected;
  final bool active;
  final double bestShare;

  const PoolInfo({
    required this.index,
    required this.url,
    required this.user,
    this.status = 'Unknown',
    this.accepted = 0,
    this.rejected = 0,
    this.active = false,
    this.bestShare = 0,
  });

  String get cleanUrl =>
      url.replaceAll('stratum+tcp://', '').replaceAll('stratum+ssl://', '');

  String get host {
    final clean = cleanUrl;
    return clean.split(':').first;
  }

  String get workerName {
    final parts = user.split('.');
    return parts.length > 1 ? parts.last : user;
  }
}
