import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bitcoin_node.dart';

class BitcoinNodeService extends ChangeNotifier {
  static final BitcoinNodeService instance = BitcoinNodeService._();
  BitcoinNodeService._();

  static const _prefsKey = 'btc_node_config';
  static const _pollInterval = Duration(seconds: 30);

  BitcoinNodeConfig? _config;
  BitcoinNodeStats _stats = BitcoinNodeStats.offline;
  Timer? _timer;
  bool _disposed = false;
  bool _initialized = false;

  BitcoinNodeConfig? get config => _config;
  BitcoinNodeStats get stats => _stats;
  bool get hasConfig => _config != null;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _config = BitcoinNodeConfig.fromJson(json);
        _startPolling();
        unawaited(refresh());
      } catch (_) {
        await prefs.remove(_prefsKey);
      }
    }
    notifyListeners();
  }

  Future<void> configure(BitcoinNodeConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
    _startPolling();
    notifyListeners();
    await refresh();
  }

  Future<void> clearConfig() async {
    _timer?.cancel();
    _timer = null;
    _config = null;
    _stats = BitcoinNodeStats.offline;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  Future<void> refresh() async {
    final cfg = _config;
    if (cfg == null) {
      _stats = BitcoinNodeStats.offline;
      notifyListeners();
      return;
    }

    try {
      final rpcResults = await Future.wait([
        _rpc(cfg, 'getblockchaininfo'),
        _rpc(cfg, 'getnetworkinfo'),
        _rpc(cfg, 'getmempoolinfo'),
      ]).timeout(const Duration(seconds: 12));

      final chain = rpcResults[0];
      final network = rpcResults[1];
      final mempool = rpcResults[2];

      final externalResults = await Future.wait<Object>([
        _getText('https://mempool.space/api/blocks/tip/height')
            .catchError((_) => ''),
        _getJson('https://mempool.space/api/v1/fees/recommended')
            .catchError((_) => <String, dynamic>{}),
        _getJson('https://mempool.space/api/v1/difficulty-adjustment')
            .catchError((_) => <String, dynamic>{}),
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () => <Object>['', <String, dynamic>{}, <String, dynamic>{}],
      );

      final tipText = externalResults[0] as String;
      final fees = externalResults[1] as Map<String, dynamic>;
      final adjustment = externalResults[2] as Map<String, dynamic>;

      final localBlocks = _asInt(chain['blocks']);
      final headers = _asInt(chain['headers']);
      final networkBlocks = int.tryParse(tipText.trim()) ?? headers;
      final progress = _asDouble(chain['verificationprogress']).clamp(0, 1);
      final connections = _asInt(network['connections']);
      final connectionsIn = _asInt(network['connections_in']);
      final connectionsOut = _asInt(network['connections_out']);
      final resolvedIn = connectionsIn > 0 ? connectionsIn : 0;
      final resolvedOut = connectionsOut > 0
          ? connectionsOut
          : max(0, connections - resolvedIn);
      final minFeeBtcKb = _asDouble(mempool['mempoolminfee']);
      final nextHalving = _nextHalving(localBlocks);

      _stats = BitcoinNodeStats(
        localBlocks: localBlocks,
        networkBlocks: networkBlocks,
        syncProgress: progress.toDouble(),
        connectionsIn: resolvedIn,
        connectionsOut: resolvedOut,
        version: network['subversion'] as String? ?? '',
        mempoolTxCount: _asInt(mempool['size']),
        mempoolMinFeeSatVb: minFeeBtcKb * 100000,
        feeLow: _asDouble(fees['hourFee'], fallback: _stats.feeLow),
        feeMed: _asDouble(fees['halfHourFee'], fallback: _stats.feeMed),
        feeHigh: _asDouble(fees['fastestFee'], fallback: _stats.feeHigh),
        blocksToHalving: max(0, nextHalving - localBlocks),
        difficultyAdjustmentPct: _asDouble(
          adjustment['difficultyChange'],
          fallback: _stats.difficultyAdjustmentPct,
        ),
        blocksUntilAdjustment: _asInt(
          adjustment['remainingBlocks'],
          fallback: _stats.blocksUntilAdjustment,
        ),
        status: progress < 0.9999 ? NodeStatus.syncing : NodeStatus.online,
        lastUpdated: DateTime.now(),
      );
    } catch (_) {
      _stats = BitcoinNodeStats(
        localBlocks: _stats.localBlocks,
        networkBlocks: _stats.networkBlocks,
        syncProgress: _stats.syncProgress,
        connectionsIn: 0,
        connectionsOut: 0,
        version: _stats.version,
        mempoolTxCount: _stats.mempoolTxCount,
        mempoolMinFeeSatVb: _stats.mempoolMinFeeSatVb,
        feeLow: _stats.feeLow,
        feeMed: _stats.feeMed,
        feeHigh: _stats.feeHigh,
        blocksToHalving: _stats.blocksToHalving,
        difficultyAdjustmentPct: _stats.difficultyAdjustmentPct,
        blocksUntilAdjustment: _stats.blocksUntilAdjustment,
        status: NodeStatus.offline,
        lastUpdated: DateTime.now(),
      );
    }

    if (!_disposed) notifyListeners();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => refresh());
  }

  Future<Map<String, dynamic>> _rpc(
    BitcoinNodeConfig cfg,
    String method,
  ) async {
    final uri = Uri.parse(cfg.rpcUrl);
    final headers = <String, String>{'content-type': 'application/json'};
    // Only add Basic auth for direct RPC (not proxy URL which has token baked in)
    if (!cfg.isProxy && cfg.rpcUser.isNotEmpty) {
      final auth = base64Encode(utf8.encode('${cfg.rpcUser}:${cfg.rpcPass}'));
      headers['authorization'] = 'Basic $auth';
    }
    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'jsonrpc': '1.0',
            'id': 'kratos',
            'method': method,
            'params': <dynamic>[],
          }),
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw Exception('RPC $method failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    return json['result'] as Map<String, dynamic>;
  }

  Future<String> _getText(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw Exception('GET $url failed: ${response.statusCode}');
    }
    return response.body;
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final body = await _getText(url);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  int _nextHalving(int localBlocks) {
    const interval = 210000;
    var next = (localBlocks / interval).ceil() * interval;
    if (next <= localBlocks) next += interval;
    return next;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
