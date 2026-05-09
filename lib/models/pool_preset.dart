/// Worker format hint — tells UI what to show in the worker field
enum WorkerFormat {
  btcAddress,        // solo pools: just your BTC address
  btcAddressWorker,  // solo/Ocean: bc1q...address.{miner}
  accountWorker,     // shared pools: username.{miner}
  account,           // some pools: username only
}

extension WorkerFormatX on WorkerFormat {
  String get hint => switch (this) {
    WorkerFormat.btcAddress       => 'Your BTC address (bc1q...)',
    WorkerFormat.btcAddressWorker => 'BTC address — worker auto-appended',
    WorkerFormat.accountWorker    => 'Pool username — worker auto-appended',
    WorkerFormat.account          => 'Your pool username',
  };
  String get label => switch (this) {
    WorkerFormat.btcAddress       => 'BTC Address',
    WorkerFormat.btcAddressWorker => 'Address.Worker',
    WorkerFormat.accountWorker    => 'Account.Worker',
    WorkerFormat.account          => 'Account',
  };
  String toJson() => name;
  static WorkerFormat fromJson(String s) =>
      WorkerFormat.values.firstWhere((e) => e.name == s,
          orElse: () => WorkerFormat.btcAddressWorker);
}

class PoolPreset {
  final String id;
  final String name;
  final String host;
  final int port;
  final String worker;       // BTC address or username; may contain {miner} template
  final String password;
  final WorkerFormat format;
  final bool isSolo;
  final DateTime createdAt;

  const PoolPreset({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.worker,
    this.password = 'x',
    this.format = WorkerFormat.btcAddressWorker,
    this.isSolo = false,
    required this.createdAt,
  });

  /// Resolve worker string for a specific miner name.
  /// {miner} → miner name (spaces→underscore, lowercased)
  /// {ip}    → last octet of miner IP
  String resolveWorker(String minerName, {String minerIp = ''}) {
    String w = worker;
    final safeName = minerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final lastOctet = minerIp.isNotEmpty ? minerIp.split('.').last : '';
    w = w.replaceAll('{miner}', safeName);
    w = w.replaceAll('{ip}', lastOctet);
    return w;
  }

  /// Full stratum URL: stratum+tcp://host:port
  String get stratumUrl => 'stratum+tcp://$host:$port';

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'host': host, 'port': port,
    'worker': worker, 'password': password,
    'format': format.toJson(), 'isSolo': isSolo,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PoolPreset.fromJson(Map<String, dynamic> j) => PoolPreset(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    worker: j['worker'] as String,
    password: j['password'] as String? ?? 'x',
    format: WorkerFormatX.fromJson(j['format'] as String? ?? ''),
    isSolo: j['isSolo'] as bool? ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  PoolPreset copyWith({
    String? name, String? host, int? port, String? worker,
    String? password, WorkerFormat? format, bool? isSolo,
  }) => PoolPreset(
    id: id, createdAt: createdAt,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    worker: worker ?? this.worker,
    password: password ?? this.password,
    format: format ?? this.format,
    isSolo: isSolo ?? this.isSolo,
  );

  /// Auto-detect worker format from host URL
  static WorkerFormat detectFormat(String host) {
    final h = host.toLowerCase();
    if (h.contains('nicehash')) return WorkerFormat.btcAddress;
    if (h.contains('solo.') || h.contains('ckpool') || h.contains('public-pool')) {
      return WorkerFormat.btcAddressWorker;
    }
    if (h.contains('ocean')) return WorkerFormat.btcAddressWorker;
    return WorkerFormat.accountWorker;
  }

  /// Auto-detect if solo pool from host
  static bool detectSolo(String host) {
    final h = host.toLowerCase();
    return h.contains('solo.') || h.contains('ckpool') ||
        h.contains('public-pool') || h.contains('solomining');
  }
}
