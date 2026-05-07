import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RelayState { disconnected, connecting, connected, bridgeOffline, bridgeOnline }

class RelayService extends ChangeNotifier {
  static final RelayService instance = RelayService._();
  RelayService._();

  static const _wsBase = 'wss://kratos.mineshop.eu/relay/app/';
  static const _prefKey = 'kratos_relay_key';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool bridgeOnline = false;
  List<Map<String, dynamic>> remoteMinersList = [];
  String? accessKey;
  RelayState _state = RelayState.disconnected;
  final _commandCompleters = <String, Completer<Map<String, dynamic>>>{};
  final _stateController = StreamController<RelayState>.broadcast();

  Stream<RelayState> get stateStream => _stateController.stream;
  RelayState get state => _state;

  /// Connect to relay; persists the key.
  Future<void> connect(String key) async {
    if (_state == RelayState.connecting || _state == RelayState.connected ||
        _state == RelayState.bridgeOffline || _state == RelayState.bridgeOnline) {
      await disconnect();
    }
    accessKey = key.trim();
    _setState(RelayState.connecting);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, accessKey!);

    final uri = Uri.parse('$_wsBase$accessKey');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.catchError((_) {});
    } catch (e) {
      _setState(RelayState.disconnected);
      return;
    }

    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        _setState(RelayState.disconnected);
        _failPendingCompleters('WebSocket error: $e');
        _scheduleAutoReconnect();
      },
      onDone: () {
        _setState(RelayState.disconnected);
        _failPendingCompleters('WebSocket closed');
        _scheduleAutoReconnect();
      },
    );

    _setState(RelayState.connected);

    // Start keepalive pings
    _schedulePing();
  }

  /// Load saved key and reconnect if available.
  Future<void> reconnectSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.isNotEmpty) {
      await connect(saved);
    }
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    bridgeOnline = false;
    remoteMinersList = [];
    _failPendingCompleters('Disconnected');
    _setState(RelayState.disconnected);
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String? ?? '';

    switch (type) {
      case 'connected':
        final bo = msg['bridge_online'];
        bridgeOnline = bo == true || bo == 1;
        final miners = msg['miners'];
        if (miners is List) {
          remoteMinersList = miners.cast<Map<String, dynamic>>();
        }
        _setState(bridgeOnline ? RelayState.bridgeOnline : RelayState.bridgeOffline);

      case 'miners':
        // Bridge updated its miner list — MERGE by IP (never shrink the list).
        // If scan 1 found 7 miners and scan 2 found 6, we keep all 7.
        final miners = msg['miners'];
        if (miners is List) {
          final incoming = miners.cast<Map<String, dynamic>>();
          final merged = <String, Map<String, dynamic>>{};
          // Seed with existing entries
          for (final m in remoteMinersList) {
            final ip = m['ip'] as String? ?? '';
            if (ip.isNotEmpty) merged[ip] = m;
          }
          // Overwrite / add with fresh data from bridge
          for (final m in incoming) {
            final ip = m['ip'] as String? ?? '';
            if (ip.isNotEmpty) merged[ip] = m;
          }
          remoteMinersList = merged.values.toList();
        }
        bridgeOnline = true;
        _setState(RelayState.bridgeOnline);

      case 'response':
        final reqId = msg['request_id']?.toString();
        if (reqId != null && _commandCompleters.containsKey(reqId)) {
          final c = _commandCompleters.remove(reqId)!;
          final err = msg['error'];
          if (err != null) {
            c.completeError(Exception(err.toString()));
          } else {
            c.complete(msg);
          }
        }

      case 'bridge_status':
        final online = msg['online'];
        bridgeOnline = online == true || online == 1;
        if (!bridgeOnline) remoteMinersList = [];
        _setState(bridgeOnline ? RelayState.bridgeOnline : RelayState.bridgeOffline);

      case 'pong':
        // keepalive response — ignore
        break;

      case 'scan_result':
        // Treat same as 'miners' — handled by fall-through below.
        // (Bridge v1.2 sends 'miners' for both periodic and manual rescans)
        final scanMiners = msg['miners'];
        if (scanMiners is List) {
          final incoming2 = scanMiners.cast<Map<String, dynamic>>();
          final merged2 = <String, Map<String, dynamic>>{};
          for (final m in remoteMinersList) {
            final ip = m['ip'] as String? ?? '';
            if (ip.isNotEmpty) merged2[ip] = m;
          }
          for (final m in incoming2) {
            final ip = m['ip'] as String? ?? '';
            if (ip.isNotEmpty) merged2[ip] = m;
          }
          remoteMinersList = merged2.values.toList();
        }
        bridgeOnline = true;
        _setState(RelayState.bridgeOnline);
        break;
    }

    notifyListeners();
  }

  /// Send a command to a miner via the relay and await the response.
  Future<Map<String, dynamic>> command({
    required String minerIp,
    required int minerPort,
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    if (_channel == null ||
        _state == RelayState.disconnected ||
        _state == RelayState.connecting) {
      throw StateError('Relay not connected');
    }

    final reqId = _randomId();
    final completer = Completer<Map<String, dynamic>>();
    _commandCompleters[reqId] = completer;

    final payload = <String, dynamic>{
      'type': 'command',
      'request_id': reqId,
      'method': method,
      'path': path,
      'miner_ip': minerIp,
      'miner_port': minerPort,
    };
    if (body != null) payload['body'] = body;

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      _commandCompleters.remove(reqId);
      throw StateError('Failed to send command: $e');
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _commandCompleters.remove(reqId);
        throw TimeoutException('Relay command timed out', const Duration(seconds: 15));
      },
    );
  }

  // ── Auto-reconnect ─────────────────────────────────────────────────────────

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  void _scheduleAutoReconnect() {
    _reconnectTimer?.cancel();
    if (accessKey == null || accessKey!.isEmpty) return;
    // Exponential backoff: 3s, 6s, 12s… capped at 60s
    final delay = Duration(seconds: (3 * (1 << _reconnectAttempts.clamp(0, 4))));
    _reconnectTimer = Timer(delay, () async {
      if (_state == RelayState.disconnected && accessKey != null) {
        _reconnectAttempts++;
        await connect(accessKey!);
        if (_state != RelayState.disconnected) _reconnectAttempts = 0;
      }
    });
  }

  // ── Ping / keepalive ──────────────────────────────────────────────────────

  Timer? _pingTimer;

  void _schedulePing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setState(RelayState s) {
    _state = s;
    _stateController.add(s);
    notifyListeners();
  }

  void _failPendingCompleters(String reason) {
    for (final c in _commandCompleters.values) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _commandCompleters.clear();
  }

  /// Ask the bridge to re-scan its local network and send back a fresh
  /// miner list. The result arrives as a 'scan_result' or 'miners' message.
  void requestBridgeRescan() {
    if (_channel == null || _state == RelayState.disconnected) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'rescan'}));
    } catch (_) {}
  }

  String _randomId() =>
      Random().nextInt(999999).toString().padLeft(6, '0');

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    super.dispose();
  }
}
