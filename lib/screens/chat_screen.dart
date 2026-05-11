import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';
import '../services/chat_service.dart';
import '../widgets/klaw.dart';

const _kDiscordInvite = 'https://discord.gg/yWtYegkDJw';

/// Live Discord-bridged community chat.
/// Talks to https://kratos.mineshop.eu/kratos/chat — every message is a
/// real Discord message from the Mineshop / Kratos DEV community.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  KratosPalette get kc => KratosColors.of(context);

  String? _activeSlug;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _lastScrolledSlug;
  int _lastScrolledMessageCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final svc = context.read<ChatService>();
      await svc.init();
      await svc.connect();
      if (!mounted) return;
      if (svc.channels.isNotEmpty && _activeSlug == null) {
        setState(() => _activeSlug = svc.channels.first.slug);
        await svc.loadHistory(svc.channels.first.slug);
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _switchChannel(String slug) async {
    setState(() => _activeSlug = slug);
    await context.read<ChatService>().loadHistory(slug);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final slug = _activeSlug;
    if (slug == null) return;
    final svc = context.read<ChatService>();
    if (svc.displayName.isEmpty) {
      final picked = await _pickDisplayName(context);
      if (picked == null || picked.isEmpty) return;
      await svc.setDisplayName(picked);
    }
    final ok = await svc.send(slug, text);
    if (ok && mounted) {
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Chat',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: kc.text)),
            SizedBox(width: 10),
            Consumer<ChatService>(
              builder: (ctx, svc, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: svc.connected
                      ? kc.accent.withOpacity(0.16)
                      : kc.muted.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: svc.connected
                          ? kc.accent.withOpacity(0.4)
                          : kc.muted.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      svc.connected ? Icons.link : Icons.link_off,
                      size: 11,
                      color: svc.connected ? kc.accent : kc.muted,
                    ),
                    SizedBox(width: 4),
                    Text(
                      svc.connected ? 'Discord' : 'offline',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: svc.connected ? kc.accentBright : kc.muted,
                          letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => launchUrl(Uri.parse(_kDiscordInvite),
                mode: LaunchMode.externalApplication),
            icon: Icon(Icons.open_in_new_rounded, color: kc.muted, size: 20),
            tooltip: 'Open in Discord app',
          ),
        ],
      ),
      body: Consumer<ChatService>(
        builder: (ctx, svc, _) {
          if (svc.lastError != null && svc.channels.isEmpty) {
            return _OfflineHero(error: svc.lastError!);
          }
          if (svc.channels.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: kc.accent),
            );
          }
          final activeSlug = _activeSlug ?? svc.channels.first.slug;
          final messages = svc.messagesFor(activeSlug);
          final readOnly = svc.readOnly.contains(activeSlug);
          final channelChanged = _lastScrolledSlug != activeSlug;
          final messageCountChanged =
              _lastScrolledMessageCount != messages.length;
          if (channelChanged || messageCountChanged) {
            _lastScrolledSlug = activeSlug;
            _lastScrolledMessageCount = messages.length;
            _scrollToBottom(animated: !channelChanged);
          }
          return Column(
            children: [
              _ChannelPills(
                channels: svc.channels,
                active: activeSlug,
                onTap: _switchChannel,
              ),
              Expanded(
                child: messages.isEmpty
                    ? _ChannelEmpty(slug: activeSlug)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = messages[i];
                          final previous = i == 0 ? null : messages[i - 1];
                          final grouped = previous != null &&
                              previous.authorName == msg.authorName &&
                              previous.authorIsBot == msg.authorIsBot &&
                              previous.authorIsWebhook == msg.authorIsWebhook;
                          return _MessageBubble(
                            msg: msg,
                            grouped: grouped,
                          );
                        },
                      ),
              ),
              _Composer(
                slug: activeSlug,
                readOnly: readOnly,
                controller: _input,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChannelPills extends StatelessWidget {
  final List<ChatChannel> channels;
  final String active;
  final ValueChanged<String> onTap;

  const _ChannelPills({
    required this.channels,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        itemCount: channels.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final c = channels[i];
          final isActive = c.slug == active;
          return InkWell(
            onTap: () => onTap(c.slug),
            borderRadius: BorderRadius.circular(99),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? kc.accent : kc.surface2,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color:
                        isActive ? kc.accentBright.withOpacity(0.7) : kc.line),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: kc.accent.withOpacity(0.22),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.bolt_rounded,
                          size: 11,
                          color: isActive ? const Color(0xFF001A0E) : kc.muted),
                    ),
                  Text(
                    '#${c.slug}',
                    style: TextStyle(
                      color: isActive ? const Color(0xFF001A0E) : kc.muted,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool grouped;
  const _MessageBubble({
    required this.msg,
    required this.grouped,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final initials = (msg.authorName.isEmpty ? '?' : msg.authorName)
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((p) => p.isEmpty ? '' : p[0])
        .join()
        .toUpperCase();
    return Padding(
      padding: EdgeInsets.only(
        top: grouped ? 1 : 7,
        bottom: grouped ? 1 : 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (grouped)
            const SizedBox(width: 39)
          else ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  kc.accent.withOpacity(0.6),
                  kc.accentDeep,
                ]),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF001A0E)),
              ),
            ),
            SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!grouped) ...[
                  Row(
                    children: [
                      Text(
                        msg.authorName,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: kc.accentBright),
                      ),
                      if (msg.authorIsBot || msg.authorIsWebhook)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: kc.muted.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('BOT',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: kc.muted,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                        ),
                      SizedBox(width: 6),
                      Text(
                        _shortTime(msg.createdAt),
                        style: TextStyle(fontSize: 10, color: kc.muted),
                      ),
                    ],
                  ),
                  SizedBox(height: 1),
                ],
                if (msg.text.isNotEmpty)
                  Text(
                    msg.text,
                    style:
                        TextStyle(fontSize: 13.5, color: kc.text, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${t.day}/${t.month}';
  }
}

class _ChannelEmpty extends StatelessWidget {
  final String slug;
  const _ChannelEmpty({required this.slug});
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Klaw(size: 100),
            SizedBox(height: 14),
            Text(
              '#$slug is quiet.',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: kc.text),
            ),
            SizedBox(height: 4),
            Text(
              'Send the first message — Klaw approves.',
              style: TextStyle(fontSize: 13, color: kc.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final String slug;
  final bool readOnly;
  final TextEditingController controller;
  final Future<void> Function() onSend;

  const _Composer({
    required this.slug,
    required this.readOnly,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    if (readOnly) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        color: kc.surface.withOpacity(0.5),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: kc.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '#$slug is read-only — populated automatically when blocks are found.',
                style: TextStyle(fontSize: 11, color: kc.muted, height: 1.3),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: kc.bg,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: TextStyle(color: kc.text),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message #$slug',
                  hintStyle: TextStyle(color: kc.muted),
                  filled: true,
                  fillColor: kc.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Material(
              color: kc.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.arrow_upward_rounded,
                      color: Color(0xFF001A0E), size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineHero extends StatelessWidget {
  final String error;
  const _OfflineHero({required this.error});
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Klaw(size: 140),
            SizedBox(height: 18),
            Text(
              "Can't reach the bridge.",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: kc.text),
            ),
            SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: kc.muted, height: 1.4),
            ),
            SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
              ),
              onPressed: () => launchUrl(Uri.parse(_kDiscordInvite),
                  mode: LaunchMode.externalApplication),
              icon: Icon(Icons.chat_bubble_outline, size: 16),
              label: Text('Open Discord directly',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _pickDisplayName(BuildContext context) async {
  final kc = KratosColors.of(context);
  final ctrl = TextEditingController();
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kc.surface,
      title: Text('Pick a display name', style: TextStyle(color: kc.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is how you appear in Discord. Anything within reason — 32 chars max.',
            style: TextStyle(fontSize: 12, color: kc.muted, height: 1.4),
          ),
          SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 32,
            style: TextStyle(color: kc.text),
            decoration: InputDecoration(
              hintText: 'e.g. NerdMiner42',
              hintStyle: TextStyle(color: kc.muted),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: TextStyle(color: kc.muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kc.accent,
            foregroundColor: const Color(0xFF001A0E),
          ),
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child:
              Text('Set name', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return picked;
}
