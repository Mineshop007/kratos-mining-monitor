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
  String? _activeSlug;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

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
    return Scaffold(
      backgroundColor: KratosColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Chat',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: KratosColors.text)),
            const SizedBox(width: 10),
            Consumer<ChatService>(
              builder: (ctx, svc, _) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: svc.connected
                      ? KratosColors.volt.withOpacity(0.16)
                      : KratosColors.muted.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: svc.connected
                          ? KratosColors.volt.withOpacity(0.4)
                          : KratosColors.muted.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      svc.connected ? Icons.link : Icons.link_off,
                      size: 11,
                      color: svc.connected
                          ? KratosColors.volt
                          : KratosColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      svc.connected ? 'Discord' : 'offline',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: svc.connected
                              ? KratosColors.voltBright
                              : KratosColors.muted,
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
            icon: const Icon(Icons.open_in_new_rounded,
                color: KratosColors.muted, size: 20),
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
            return const Center(
              child: CircularProgressIndicator(color: KratosColors.volt),
            );
          }
          final activeSlug = _activeSlug ?? svc.channels.first.slug;
          final messages = svc.messagesFor(activeSlug);
          final readOnly = svc.readOnly.contains(activeSlug);
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
                        itemBuilder: (ctx, i) =>
                            _MessageBubble(msg: messages[i]),
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final c = channels[i];
          final isActive = c.slug == active;
          return InkWell(
            onTap: () => onTap(c.slug),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isActive
                    ? KratosColors.volt.withOpacity(0.18)
                    : KratosColors.surface2,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: isActive
                        ? KratosColors.volt.withOpacity(0.5)
                        : KratosColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.bolt_rounded,
                          size: 11,
                          color: isActive
                              ? KratosColors.volt
                              : KratosColors.muted),
                    ),
                  Text(
                    '#${c.slug}',
                    style: TextStyle(
                      color: isActive
                          ? KratosColors.voltBright
                          : KratosColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.3,
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
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final initials = (msg.authorName.isEmpty ? '?' : msg.authorName)
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((p) => p.isEmpty ? '' : p[0])
        .join()
        .toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                KratosColors.volt.withOpacity(0.6),
                KratosColors.voltDeep,
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
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      msg.authorName,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: KratosColors.voltBright),
                    ),
                    if (msg.authorIsBot || msg.authorIsWebhook)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: KratosColors.muted.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text('BOT',
                            style: TextStyle(
                                fontSize: 8,
                                color: KratosColors.muted,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      _shortTime(msg.createdAt),
                      style: const TextStyle(
                          fontSize: 10, color: KratosColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                if (msg.text.isNotEmpty)
                  Text(
                    msg.text,
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: KratosColors.text,
                        height: 1.4),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Klaw(size: 100),
            const SizedBox(height: 14),
            Text(
              '#$slug is quiet.',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: KratosColors.text),
            ),
            const SizedBox(height: 4),
            const Text(
              'Send the first message — Klaw approves.',
              style: TextStyle(fontSize: 13, color: KratosColors.muted),
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
    if (readOnly) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        color: KratosColors.surface.withOpacity(0.5),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 14, color: KratosColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '#$slug is read-only — populated automatically when blocks are found.',
                style: const TextStyle(
                    fontSize: 11, color: KratosColors.muted, height: 1.3),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: KratosColors.bg,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: KratosColors.text),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message #$slug',
                  hintStyle:
                      const TextStyle(color: KratosColors.muted),
                  filled: true,
                  fillColor: KratosColors.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: KratosColors.volt,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: const SizedBox(
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Klaw(size: 140),
            const SizedBox(height: 18),
            const Text(
              "Can't reach the bridge.",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: KratosColors.text),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: KratosColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
              ),
              onPressed: () => launchUrl(Uri.parse(_kDiscordInvite),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Open Discord directly',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _pickDisplayName(BuildContext context) async {
  final ctrl = TextEditingController();
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: KratosColors.surface,
      title: const Text('Pick a display name',
          style: TextStyle(color: KratosColors.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is how you appear in Discord. Anything within reason — 32 chars max.',
            style:
                TextStyle(fontSize: 12, color: KratosColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 32,
            style: const TextStyle(color: KratosColors.text),
            decoration: const InputDecoration(
              hintText: 'e.g. NerdMiner42',
              hintStyle: TextStyle(color: KratosColors.muted),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel',
              style: TextStyle(color: KratosColors.muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: KratosColors.volt,
            foregroundColor: const Color(0xFF001A0E),
          ),
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Set name',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return picked;
}
