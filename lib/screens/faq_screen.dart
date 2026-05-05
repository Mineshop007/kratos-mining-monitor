import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';

/// Bundled FAQ — answers to the questions every BitAxe / NerdQ /
/// Avalon owner asks in their first week. Real, opinionated answers.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosColors.bg,
      appBar: AppBar(
        title: const Text('FAQ',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KratosColors.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          for (final s in _sections)
            _FaqSection(title: s.title, items: s.items),
          const SizedBox(height: 24),
          _StillStuckCard(),
        ],
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  final String title;
  final List<_FaqItem> items;
  const _FaqSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  color: KratosColors.muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: KratosColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: KratosColors.volt.withOpacity(0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: KratosColors.line),
                ExpansionTile(
                  iconColor: KratosColors.muted,
                  collapsedIconColor: KratosColors.muted,
                  title: Text(
                    items[i].q,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KratosColors.text),
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        items[i].a,
                        style: const TextStyle(
                            fontSize: 13,
                            color: KratosColors.muted,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StillStuckCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KratosColors.volt.withOpacity(0.18),
            KratosColors.volt.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KratosColors.volt.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Still stuck?',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: KratosColors.text)),
          const SizedBox(height: 6),
          const Text(
              'Hop into the Mineshop Discord. Real humans, real answers, real fast.',
              style: TextStyle(fontSize: 13, color: KratosColors.muted)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
              ),
              onPressed: () => launchUrl(
                Uri.parse('https://discord.gg/yWtYegkDJw'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Open Discord',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqSectionData {
  final String title;
  final List<_FaqItem> items;
  const _FaqSectionData({required this.title, required this.items});
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem(this.q, this.a);
}

const _sections = <_FaqSectionData>[
  _FaqSectionData(
    title: 'Getting started',
    items: [
      _FaqItem(
        'How do I add my first miner?',
        'Easiest: open the Miners tab, tap "Add", then "Auto-discover on LAN". Kratos sniffs your Wi-Fi for ESP-Miner and cgminer devices and confirms each one with a real API call before showing it. Tap Add and you\'re done.\n\nManual: enter the miner\'s IP and pick its type. Kratos auto-detects the API (HTTP for BitAxe family, TCP 4028 for cgminer-based devices).',
      ),
      _FaqItem(
        'Why doesn\'t auto-discovery find my miner?',
        '• Make sure your phone is on the same Wi-Fi network as the miner.\n• Some routers isolate Wi-Fi clients ("AP isolation" / "guest mode") — turn that off, or use the manual entry route.\n• mDNS can take 3–5 seconds; let the scan run. Subnet sweep takes up to 10 seconds total on a /24.\n• Miners on a separate subnet or VLAN won\'t show up. Add them manually with the IP.',
      ),
      _FaqItem(
        'What does "best diff" mean?',
        'Every share your miner submits has a difficulty value. The highest difficulty share you\'ve ever submitted is your "best diff." If your best diff ever beats the current network difficulty, that share IS a Bitcoin block — and you win the full reward. For solo miners, hunting bigger best diffs is the whole game.',
      ),
    ],
  ),
  _FaqSectionData(
    title: 'Hashrate & shares',
    items: [
      _FaqItem(
        'My hashrate looks lower in Kratos than on the device — why?',
        'Kratos shows the rolling 1-minute average, not the instantaneous peak. The 1-min average is what your pool credits you for. If your device displays a different value, it\'s probably the 5-second rolling rate, which fluctuates more.',
      ),
      _FaqItem(
        'What\'s a healthy accept rate?',
        '99.5% or better is normal. Anything below ~99% on a sustained basis usually means: bad PSU, weak Wi-Fi between miner and stratum, the wrong chip voltage/frequency combo, or pool latency. Check the miner\'s detail screen for accept-rate over time.',
      ),
      _FaqItem(
        'Why are my hashrate numbers different across pools?',
        'Pools and your miner each use a slightly different averaging window. Kratos reads from your miner directly, so its number is always the freshest local truth. Pool dashboards lag by 5–15 minutes typically.',
      ),
    ],
  ),
  _FaqSectionData(
    title: 'Pools & solo mining',
    items: [
      _FaqItem(
        'Should I solo mine or use a pool?',
        'Solo mining is a lottery — you win nothing for years and then you might find a full block (~3.125 BTC + fees today). Pool mining is a steady drip. If you have a hobbyist single-miner setup, pool mining (or a solo pool like ckpool / public-pool / Mineshop) is usually the right call. Industrial scale, that\'s a different conversation.',
      ),
      _FaqItem(
        'How do I switch pools?',
        'Open a miner\'s detail screen → tap the pool field → enter the new stratum URL + worker name. Kratos pushes the change to your miner via its API and the miner restarts on the new pool.',
      ),
      _FaqItem(
        'What\'s the difference between solo and pool?',
        'Pool: many miners share the work and split rewards proportionally. Solo: you mine alone — when you find a block, you keep the whole reward, but blocks are extremely rare for small operators. A "solo pool" is a hybrid: you submit shares to a coordinator that broadcasts your block solution if you find one, and you keep ~99% of the reward (the coordinator takes 1–2%).',
      ),
    ],
  ),
  _FaqSectionData(
    title: 'Heat, noise & power',
    items: [
      _FaqItem(
        'My miner is running at 85°C — should I worry?',
        '70–80°C is fine for sustained operation on most ESP-Miner devices. Above 85°C the chip is throttling itself and your hashrate drops. Drop the frequency/voltage combo or improve airflow. Above 90°C, stop and fix.',
      ),
      _FaqItem(
        'How loud are these miners?',
        'BitAxe Gamma + NerdQaxe++ are room-livable (35–45 dB). Avalon Q + Bitmain S21XP Hydro are not — they need a dedicated room or shed.',
      ),
      _FaqItem(
        'Will I make money?',
        'Depends entirely on your electricity rate. As a rough guide: a NerdOctaxe at 130W and €0.18/kWh costs ~€17/month in power. Revenue at current difficulty is roughly the same. Profit is in low-cost power, surplus solar, or treating the heat output as a feature (workshop heating, etc).',
      ),
    ],
  ),
  _FaqSectionData(
    title: 'About Kratos',
    items: [
      _FaqItem(
        'Where do the numbers come from?',
        'Every numeric value you see is sourced from your miner\'s own API (ESP-Miner HTTP, cgminer TCP), CoinGecko for prices, or — for solo blocks — public blockchain explorers like mempool.space. We never invent numbers. If a value is unknown we show a dash.',
      ),
      _FaqItem(
        'Is my data private?',
        'Yes. Your fleet, your wallets, your share counts — all stored locally on your phone. Nothing is uploaded to Kratos servers (we don\'t even run any). The only outbound traffic is to your miners (LAN), CoinGecko (anonymous price fetch), and any Discord/Telegram links you explicitly tap.',
      ),
      _FaqItem(
        'Who makes this app?',
        'Kratos is built by Mineshop (mineshop.eu) — an EU-based crypto mining hardware store. We sell BitAxe, NerdQaxe, NerdOctaxe, Avalon, Antminer, Whatsminer, Goldshell, IceRiver, Lucky Miner. The app is free; if it helps you mine better, consider buying your next miner from us.',
      ),
      _FaqItem(
        'Who is Klaw?',
        'Klaw is the Kratos honey badger — fearless, stubborn, doesn\'t care about hash-power gap, just keeps grinding. Solo mining is exactly honey-badger work. He shows up in empty states and cheers you on when you find a block.',
      ),
    ],
  ),
];
