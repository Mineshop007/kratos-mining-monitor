// ── Miner model ───────────────────────────────────────────────────────────────

enum MinerStatus { online, offline, warning, unknown }

enum MinerType {
  bitaxeGamma,
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

  String get icon => switch (this) {
    bitaxeGamma  => '⚡',
    nerdqaxe     => '🔧',
    nerdoctaxe   => '🔩',
    avalonNano3s => '🟢',
    avalonNano3  => '🟢',
    avalonMini3  => '🟢',
    avalonQ      => '🟢',
    antminer     => '🟠',
    whatsminer   => '🔵',
    goldshell    => '🟡',
    generic      => '⛏️',
  };

  bool get isAvalonHttp =>
    this == avalonNano3s || this == avalonMini3 || this == avalonQ;

  int get defaultPort => isAvalonHttp ? 80 : 4028;

  // Detect type from model string
  static MinerType detect(String model) {
    final m = model.toLowerCase();
    if (m.contains('gamma') || m.contains('bitaxe')) return bitaxeGamma;
    if (m.contains('nerdqaxe') || m.contains('nerdq')) return nerdqaxe;
    if (m.contains('nerdoct')) return nerdoctaxe;
    if (m.contains('nano3s') || m.contains('nano 3s')) return avalonNano3s;
    if (m.contains('mini3') || m.contains('mini 3')) return avalonMini3;
    if (m.contains('avalon q') || m.contains('avalonq')) return avalonQ;
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

  Miner({
    String? id,
    required this.name,
    required this.ip,
    this.port = 4028,
    this.notes = '',
    this.type = MinerType.generic,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'ip': ip, 'port': port, 'notes': notes,
    'type': type.name,
  };

  factory Miner.fromJson(Map<String, dynamic> j) => Miner(
    id: j['id'], name: j['name'], ip: j['ip'],
    port: j['port'] ?? 4028, notes: j['notes'] ?? '',
    type: MinerType.values.firstWhere(
      (t) => t.name == (j['type'] as String? ?? ''),
      orElse: () => MinerType.generic,
    ),
  );
}

class MinerStats {
  final double hashrate5s;      // GH/s
  final double hashrateAvg;     // GH/s
  final double outTemp;
  final int fanRPM;
  final int fanPercent;
  final int accepted;
  final int rejected;
  final int hardwareErrors;
  final int uptime;             // seconds
  final List<PoolInfo> pools;
  final double frequency;       // MHz
  final double powerDraw;       // Watts
  final MinerStatus status;
  final DateTime lastUpdated;
  final String firmware;
  final String model;
  final MinerType type;
  final double bestShare;
  final List<double> hashrateHistory; // last 20 readings

  const MinerStats({
    this.hashrate5s = 0,
    this.hashrateAvg = 0,
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
  }) : lastUpdated = lastUpdated ?? const _DateTimeNow();

  static const MinerStats offline = MinerStats(status: MinerStatus.offline);

  // Computed
  double get efficiency => powerDraw > 0 ? (hashrateAvg * 1000) / powerDraw : 0;
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
}

// Hack to allow const
class _DateTimeNow implements DateTime {
  const _DateTimeNow();
  @override dynamic noSuchMethod(Invocation i) => DateTime.now();
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

  String get workerName {
    final parts = user.split('.');
    return parts.length > 1 ? parts.last : user;
  }
}
