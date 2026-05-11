enum NodeStatus { online, syncing, offline, unknown }

class BitcoinNodeConfig {
  final String host;
  final int port;
  final String rpcUser;
  final String rpcPass;

  const BitcoinNodeConfig({
    required this.host,
    required this.port,
    required this.rpcUser,
    required this.rpcPass,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'rpcUser': rpcUser,
        'rpcPass': rpcPass,
      };

  factory BitcoinNodeConfig.fromJson(Map<String, dynamic> json) =>
      BitcoinNodeConfig(
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 8332,
        rpcUser: json['rpcUser'] as String? ?? '',
        rpcPass: json['rpcPass'] as String? ?? '',
      );
}

class BitcoinNodeStats {
  final int localBlocks;
  final int networkBlocks;
  final double syncProgress;
  final int connectionsIn;
  final int connectionsOut;
  final String version;
  final int mempoolTxCount;
  final double mempoolMinFeeSatVb;
  final double feeLow;
  final double feeMed;
  final double feeHigh;
  final int blocksToHalving;
  final double difficultyAdjustmentPct;
  final int blocksUntilAdjustment;
  final NodeStatus status;
  final DateTime lastUpdated;

  const BitcoinNodeStats({
    required this.localBlocks,
    required this.networkBlocks,
    required this.syncProgress,
    required this.connectionsIn,
    required this.connectionsOut,
    required this.version,
    required this.mempoolTxCount,
    required this.mempoolMinFeeSatVb,
    required this.feeLow,
    required this.feeMed,
    required this.feeHigh,
    required this.blocksToHalving,
    required this.difficultyAdjustmentPct,
    required this.blocksUntilAdjustment,
    required this.status,
    required this.lastUpdated,
  });

  int get totalConnections => connectionsIn + connectionsOut;

  static BitcoinNodeStats get offline => BitcoinNodeStats(
        localBlocks: 0,
        networkBlocks: 0,
        syncProgress: 0,
        connectionsIn: 0,
        connectionsOut: 0,
        version: '',
        mempoolTxCount: 0,
        mempoolMinFeeSatVb: 0,
        feeLow: 0,
        feeMed: 0,
        feeHigh: 0,
        blocksToHalving: 0,
        difficultyAdjustmentPct: 0,
        blocksUntilAdjustment: 0,
        status: NodeStatus.offline,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
      );
}
