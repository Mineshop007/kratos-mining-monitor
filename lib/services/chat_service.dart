import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Live chat client for the Kratos Discord-bridged community.
///
/// Talks to the bridge service at `https://kratos.mineshop.eu/kratos/chat/`.
/// All messages displayed are real Discord messages from the
/// Mineshop / Kratos DEV Discord server — never invented.
///
/// Auth: per-device random token, persisted in SharedPreferences.
/// Server registers the token on first contact and rate-limits per
/// token. No user account required for v1.5; OAuth Discord login is
/// a follow-up.
class ChatService extends ChangeNotifier {
  static const _baseUrl = 'https://kratos.mineshop.eu/kratos/chat';
  static const _wsUrl   = 'wss://kratos.mineshop.eu/kratos/chat/stream';

  static const _kTokenKey = 'kratos_chat_token_v1';
  static const _kDisplayNameKey = 'kratos_chat_display_name_v1';

  String? _token;
  String _displayName = '';
  bool _disposed = false;

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _connected = false;
  bool _ready = false;
  String? _lastError;

  /// channel slug → list of messages (newest at end)
  final Map<String, List<ChatMessage>> _byChannel = {};
  /// channels exposed by server. Empty until /channels probe completes.
  final List<ChatChannel> _channels = [];
  /// Channels marked read-only by the server (block-feed et al.)
  final Set<String> _readOnly = {};

  ChatService();

  // ── Public API ──────────────────────────────────────────────────────

  bool get connected => _connected;
  bool get ready => _ready;
  String? get lastError => _lastError;
  String get displayName => _displayName;
  List<ChatChannel> get channels => List.unmodifiable(_channels);
  Set<String> get readOnly => Set.unmodifiable(_readOnly);

  List<ChatMessage> messagesFor(String channel) =>
      List.unmodifiable(_byChannel[channel] ?? const []);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenKey);
    if (_token == null) {
      _token = _newToken();
      await prefs.setString(_kTokenKey, _token!);
    }
    _displayName = prefs.getString(_kDisplayNameKey) ?? '';
    _safeNotify();
  }

  /// Connect to the bridge: fetch channel list, open WebSocket.
  Future<void> connect() async {
    if (_token == null) await init();
    if (_connected) return;
    _lastError = null;

    try {
      // Fetch channel list (also confirms bridge is alive).
      final resp = await http
          .get(Uri.parse('$_baseUrl/channels'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw 'channels probe ${resp.statusCode}';
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (body['channels'] as List)
          .map((e) => ChatChannel.fromJson(e as Map<String, dynamic>))
          .toList();
      _channels
        ..clear()
        ..addAll(list);
      _readOnly
        ..clear()
        ..addAll(list.where((c) => c.readOnly).map((c) => c.slug));
    } catch (e) {
      _lastError = 'Could not reach Kratos chat: $e';
      _safeNotify();
      return;
    }

    _openWebSocket();
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.length > 32) return;
    _displayName = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayNameKey, trimmed);
    _safeNotify();
  }

  /// Fetch most recent messages for a channel via REST.
  Future<void> loadHistory(String slug, {int limit = 50}) async {
    if (_token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/$slug/messages?limit=$limit'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 503) {
        _lastError = 'Discord offline';
        _safeNotify();
        return;
      }
      if (resp.statusCode != 200) {
        _lastError = 'history $slug: ${resp.statusCode}';
        _safeNotify();
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final msgs = (body['messages'] as List)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList()
        // Server sends newest-first; UI wants oldest-first.
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _byChannel[slug] = msgs;
      _safeNotify();
    } catch (e) {
      _lastError = 'history $slug: $e';
      _safeNotify();
    }
  }

  /// Post a message to the given channel.
  Future<bool> send(String slug, String text) async {
    if (_token == null) return false;
    if (_readOnly.contains(slug)) return false;
    if (text.trim().isEmpty) return false;
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/$slug/send'),
        headers: {
          ..._authHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'displayName': _displayName.isEmpty ? null : _displayName,
        }),
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        // Server will broadcast through WS too; that's authoritative.
        return true;
      }
      _lastError = 'send: ${resp.statusCode} ${resp.body}';
      _safeNotify();
      return false;
    } catch (e) {
      _lastError = 'send: $e';
      _safeNotify();
      return false;
    }
  }

  // ── Internal ────────────────────────────────────────────────────────

  Map<String, String> _authHeaders() => {
        'X-Kratos-Token': _token ?? '',
        if (_displayName.isNotEmpty) 'X-Kratos-DisplayName': _displayName,
      };

  void _openWebSocket() {
    final uri = Uri.parse('$_wsUrl?token=${Uri.encodeQueryComponent(_token!)}');
    try {
      final ws = WebSocketChannel.connect(uri);
      _ws = ws;
      _connected = true;
      _safeNotify();
      _wsSub = ws.stream.listen(
        _onWsMessage,
        onDone: _onWsDone,
        onError: (e) {
          _lastError = 'ws: $e';
          _onWsDone();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _connected = false;
      _ready = false;
      _lastError = 'ws connect: $e';
      _safeNotify();
    }
  }

  void _onWsMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final kind = body['kind'] as String?;
      if (kind == 'hello') {
        _ready = true;
        _safeNotify();
      } else if (kind == 'message') {
        final m = ChatMessage.fromJson(body);
        final list = _byChannel.putIfAbsent(m.channel, () => []);
        // Skip duplicates (server may broadcast same id twice on
        // Discord retries).
        if (list.any((x) => x.id == m.id)) return;
        list.add(m);
        // Bound list at 200 to keep memory in check; older messages
        // can be re-fetched via loadHistory(before:).
        while (list.length > 200) {
          list.removeAt(0);
        }
        _safeNotify();
      }
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _onWsDone() {
    _connected = false;
    _ready = false;
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
    _safeNotify();
    if (_disposed) return;
    // Auto-reconnect with simple backoff.
    Future.delayed(const Duration(seconds: 5), () {
      if (_disposed) return;
      connect();
    });
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  static String _newToken() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  void dispose() {
    _disposed = true;
    _wsSub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }
}

class ChatChannel {
  final String slug;
  final String id;
  final bool readOnly;
  const ChatChannel({
    required this.slug,
    required this.id,
    required this.readOnly,
  });
  factory ChatChannel.fromJson(Map<String, dynamic> j) => ChatChannel(
        slug: j['slug'] as String,
        id: j['id'].toString(),
        readOnly: j['readOnly'] == true,
      );
}

class ChatMessage {
  final String id;
  final String channel;
  final String authorName;
  final bool authorIsBot;
  final bool authorIsWebhook;
  final String text;
  final DateTime createdAt;
  final String? replyToId;

  const ChatMessage({
    required this.id,
    required this.channel,
    required this.authorName,
    required this.authorIsBot,
    required this.authorIsWebhook,
    required this.text,
    required this.createdAt,
    required this.replyToId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final author = (j['author'] as Map<String, dynamic>?) ?? const {};
    return ChatMessage(
      id: j['id'].toString(),
      channel: j['channel'] as String? ?? '',
      authorName: author['displayName'] as String? ?? '?',
      authorIsBot: author['isBot'] == true,
      authorIsWebhook: author['isWebhook'] == true,
      text: j['text'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
      replyToId: j['replyTo'] as String?,
    );
  }
}
