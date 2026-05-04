// ── Miner model ───────────────────────────────────────────────────────────────

enum ApiType { espMinerHttp, cgminerTcp }

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
  generic;

  String get displayName => switch (this) {
    bitaxeGamma  => 'BitAxe Gamma',
    bitaxeUltra  => 'BitAxe Ultra',
    bitaxeGT     => 'BitAxe GT',
    nerdqaxe     => 'NerdQaxe++',
    nerdoctaxe   => 'NerdOctaxe',
    avalonNano3s => 'Avalon Nano 3S',
    avalonNano3  => 'Avalon Nano 3',
    avalonMini3  => 'Avalon Mini 3',
    avalonQ      => 'Avalon Q',
    antminer     => 'Antminer',
    whatsminer   => 'Whatsminer',
    goldshell    => 'Goldshell',
    generic      => 'Miner',
  };

  // ESP-Miner HTTP (port 80) for BitAxe family; cgminer TCP (port 4028) for everything else
  ApiType get apiType => switch (this) {
    bitaxeGamma || bitaxeUltra || bitaxeGT || nerdqaxe || nerdoctaxe =>
        ApiType.espMinerHttp,
    _ => ApiType.cgminerTcp,
  };

  int get defaultPort => apiType == ApiType.espMinerHttp ? 80 : 4028;

  static MinerType detect(String model) {
    final m = model.toLowerCase();
    if (m.contains('gamma')) return bitaxeGamma;
    if (m.contains('bm1368') || (m.contains('ultra') && m.contains('bitaxe'))) return bitaxeUltra;
    if (m.contains('bm1370') || m.contains('bm1371') || (m.contains('gt') && m.contains('bitaxe'))) return bitaxeGT;
    if (m.contains('bm1366') || m.contains('bitaxe')) return bitaxeGamma;
    // NerdAxe firmware returns deviceModel like 'NerdQAxe++' or 'NerdOCTAXE-γ'
    if (m.contains('nerdqaxe') || m.contains('nerdqax') || m.contains('nerdq')) return nerdqaxe;
    if (m.contains('nerdoct') || m.contains('nerdoctaxe')) return nerdoctaxe;
    if (m.contains('nano3s') || m.contains('nano 3s')) return avalonNano3s;
    if (m.contains('mini3') || m.contains('mini 3')) return avalonMini3;
    if (m.contains('avalonq') || m.contains('avalon q')) return avalonQ;
    if (m.contains('nano3') || m.contains('nano 3')) return avalonNano3;
    if (m.contains('antminer') || m.contains('bitmain')) return antminer;
    if (m.contains('whatsminer') || m.contains('microbt')) return whatsminer;
    if (m.contains('goldshell')) return goldshell;
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

  Miner({
    String? id,
    required this.name,
    required this.ip,
    this.port = 4028,
    this.notes = '',
    this.type = MinerType.generic,
    this.remoteUrl = '',
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'ip': ip, 'port': port, 'notes': notes,
    'type': type.name, 'remoteUrl': remoteUrl,
  };

  factory Miner.fromJson(Map<String, dynamic> j) => Miner(
    id: j['id'], name: j['name'], ip: j['ip'],
    port: j['port'] ?? 4028, notes: j['notes'] ?? '',
    remoteUrl: j['remoteUrl'] as String? ?? '',
    type: MinerType.values.firstWhere(
      (t) => t.name == (j['type'] as String? ?? ''),
      orElse: () => MinerType.generic,
    ),
  );
}

class MinerStats {
  final double hashrate5s;       // GH/s — instantaneous
  final double hashrateAvg;      // GH/s — 1-min avg (or rolling avg for CGMiner)
  final double hashRate1h;       // GH/s — 1h average (ESP-Miner only)
  final double outTemp;          // °C
  final int fanRPM;
  final int fanPercent;
  final int accepted;
  final int rejected;
  final int hardwareErrors;
  final int uptime;              // seconds
  final List<PoolInfo> pools;
  final double frequency;        // MHz
  final double powerDraw;        // Watts
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
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  static MinerStats get offline => MinerStats(status: MinerStatus.offline);

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
  );

  // Computed
  double get efficiency => powerDraw > 0 && hashrateAvg > 0 ? powerDraw / (hashrateAvg / 1000.0) : 0;
  double get rejectRate => accepted > 0 ? rejected / (accepted + rejected) * 100 : 0;

  String get uptimeFormatted {
    if (uptime < 60) return '${uptime}s';
    if (uptime < 3600) return '${uptime ~/ 60}m';
    if (uptime < 86400) return '${uptime ~/ 3600}h ${(uptime % 3600) ~/ 60}m';
    return '${uptime ~/ 86400}d ${(uptime % 86400) ~/ 3600}h';
  }

  String get hashrateFormatted {
    if (hashrateAvg >= 1000) return '${(hashrateAvg / 1000).toStringAsFixed(3)} TH/s';
    if (hashrateAvg >= 1) return '${hashrateAvg.toStringAsFixed(1)} GH/s';
    return '${(hashrateAvg * 1000).toStringAsFixed(0)} MH/s';
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

  String get cleanUrl => url
      .replaceAll('stratum+tcp://', '')
      .replaceAll('stratum+ssl://', '');

  String get host {
    final clean = cleanUrl;
    return clean.split(':').first;
  }

  String get workerName {
    final parts = user.split('.');
    return parts.length > 1 ? parts.last : user;
  }
}
