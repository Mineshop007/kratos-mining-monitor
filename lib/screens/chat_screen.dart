import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';
import '../widgets/klaw.dart';

/// Chat tab placeholder for v1.2.0.
///
/// The Discord-bridged in-app chat lands in v1.4.0 (Sprint 4).
/// Until then, this tab tells the truth: we don't have an in-app chat
/// **yet**, here's the live Discord. No fake message lists, no fake
/// counters. Real link to a real community.
const _kDiscordInvite = 'https://discord.gg/yWtYegkDJw';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosColors.bg,
      appBar: AppBar(
        backgroundColor: KratosColors.bg,
        title: const Text('Chat',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KratosColors.text)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Klaw(size: 160),
            const SizedBox(height: 22),
            const Text(
              'In-app chat is coming.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: KratosColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "Bridged Discord chat ships in 1.4. Until then, hop\ninto the real Discord — Klaw's already there.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: KratosColors.muted,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99)),
                  ),
                  onPressed: () => launchUrl(
                    Uri.parse(_kDiscordInvite),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text(
                    'Open Mineshop Discord',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
