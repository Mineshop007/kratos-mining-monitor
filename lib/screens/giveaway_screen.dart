import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';
import '../services/global_leaderboard_service.dart';
import '../services/best_diff_tracker.dart';

class GiveawayScreen extends StatefulWidget {
  const GiveawayScreen({super.key});
  @override State<GiveawayScreen> createState() => _GiveawayScreenState();
}

class _GiveawayScreenState extends State<GiveawayScreen>
    with TickerProviderStateMixin {
  late AnimationController _particleCtrl;
  late AnimationController _pulseCtrl;
  late Timer _countdownTimer;
  Duration _remaining = Duration.zero;
  final _global = GlobalLeaderboardService.instance;
  List<GlobalDiffRecord> _monthRecords = [];

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 8))..repeat();
    _pulseCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _updateCountdown());
    });
    _global.addListener(_onGlobal);
    _global.fetchLeaderboard(force: true);
  }

  void _onGlobal() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _monthRecords = _global.leaderboard
          .where((r) =>
              r.achievedAt.year == now.year &&
              r.achievedAt.month == now.month)
          .take(10)
          .toList();
    });
  }

  void _updateCountdown() {
    final now = DateTime.now();
    final endOfMonth = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    _remaining = endOfMonth.difference(now);
    if (_remaining.isNegative) _remaining = Duration.zero;
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _pulseCtrl.dispose();
    _countdownTimer.cancel();
    _global.removeListener(_onGlobal);
    super.dispose();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = _remaining.inDays;
    final h = _remaining.inHours % 24;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;

    return Scaffold(
      backgroundColor: KratosColors.bg,
      body: Stack(children: [
        // Animated gold particles background
        AnimatedBuilder(
          animation: _particleCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticlePainter(_particleCtrl.value),
            child: const SizedBox.expand(),
          ),
        ),
        // Main content
        SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: KratosColors.text),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Monthly Challenge',
                  style: TextStyle(color: KratosColors.text,
                      fontWeight: FontWeight.w800)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: KratosColors.warning),
                  onPressed: _share,
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                child: Column(children: [

                  // ── Hero Prize Card ──────────────────────────────────
                  _buildPrizeHero(d, h, m, s),
                  const SizedBox(height: 24),

                  // ── How it works ─────────────────────────────────────
                  _buildHowItWorks(),
                  const SizedBox(height: 24),

                  // ── Leaderboard ───────────────────────────────────────
                  _buildLeaderboard(),
                  const SizedBox(height: 24),

                  // ── Rules ─────────────────────────────────────────────
                  _buildRules(),
                  const SizedBox(height: 24),

                  // ── CTAs ──────────────────────────────────────────────
                  _buildCTAs(),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPrizeHero(int d, int h, int m, int s) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) {
        final glow = 0.2 + _pulseCtrl.value * 0.25;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: KratosColors.warning.withOpacity(glow + 0.3), width: 1.5),
            boxShadow: [BoxShadow(
                color: KratosColors.warning.withOpacity(glow),
                blurRadius: 30, spreadRadius: 2)],
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                KratosColors.warning.withOpacity(0.12),
                KratosColors.bg.withOpacity(0.95),
                const Color(0xFF1a1200).withOpacity(0.9),
              ],
            ),
          ),
          padding: const EdgeInsets.all(22),
          child: child!,
        );
      },
      child: Column(children: [
        // Trophy + title
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🏆', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MONTHLY MINING CHALLENGE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: KratosColors.warning, letterSpacing: 1.5)),
            const SizedBox(height: 2),
            Text(_monthName(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                    color: KratosColors.text)),
          ]),
        ]),
        const SizedBox(height: 18),
        // Prize
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KratosColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KratosColors.warning.withOpacity(0.25)),
          ),
          child: Column(children: [
            const Text('PRIZE', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800, color: KratosColors.warning,
                letterSpacing: 1.5)),
            const SizedBox(height: 8),
            const Text('Avalon Nano 3S', style: TextStyle(fontSize: 24,
                fontWeight: FontWeight.w900, color: KratosColors.text)),
            const Text('6.5 TH/s Bitcoin Miner · €399 value',
                style: TextStyle(fontSize: 13, color: KratosColors.muted)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _prizeChip('⚡ 6.5 TH/s'),
              const SizedBox(width: 8),
              _prizeChip('🔇 Whisper quiet'),
              const SizedBox(width: 8),
              _prizeChip('🏠 Home friendly'),
            ]),
          ]),
        ),
        const SizedBox(height: 18),
        // Countdown
        Column(children: [
          const Text('ENDS IN', style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w800, color: KratosColors.muted,
              letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _countdownBox('$d', 'DAYS'),
            const _CountdownSep(),
            _countdownBox(_pad(h), 'HRS'),
            const _CountdownSep(),
            _countdownBox(_pad(m), 'MIN'),
            const _CountdownSep(),
            _countdownBox(_pad(s), 'SEC'),
          ]),
        ]),
      ]),
    );
  }

  Widget _prizeChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: KratosColors.warning.withOpacity(0.1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: KratosColors.warning.withOpacity(0.2)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: KratosColors.warning)),
  );

  Widget _countdownBox(String value, String label) => Container(
    width: 64,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: KratosColors.surface2,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: KratosColors.warning.withOpacity(0.3)),
    ),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
          color: KratosColors.warning, fontFamily: 'Courier')),
      Text(label, style: const TextStyle(fontSize: 8, color: KratosColors.muted,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ]),
  );

  Widget _buildHowItWorks() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: KratosColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: KratosColors.line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('HOW TO WIN', style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w800, color: KratosColors.volt,
          letterSpacing: 1.5)),
      const SizedBox(height: 14),
      _howStep('1', '📱', 'Download Kratos',
          'Free app — iOS App Store, Android beta'),
      const SizedBox(height: 12),
      _howStep('2', '⛏️', 'Mine with any supported miner',
          'BitAxe, NerdQaxe, NerdOctaxe, Avalon, Antminer & more'),
      const SizedBox(height: 12),
      _howStep('3', '🏆', 'Highest difficulty share wins',
          'Automatically tracked — no signup, no manual entry'),
    ]),
  );

  Widget _howStep(String num, String emoji, String title, String sub) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: KratosColors.volt.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(num, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: KratosColors.volt)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: KratosColors.text)),
          ]),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 12,
              color: KratosColors.muted, height: 1.4)),
        ])),
      ]);

  Widget _buildLeaderboard() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('THIS MONTH · TOP 10', style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800, color: KratosColors.muted,
            letterSpacing: 1.5)),
        const Spacer(),
        if (_global.loading)
          const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2,
                  color: KratosColors.volt)),
      ]),
      const SizedBox(height: 10),
      if (_monthRecords.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KratosColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KratosColors.line),
          ),
          child: const Column(children: [
            Text('🏆', style: TextStyle(fontSize: 48)),
            SizedBox(height: 10),
            Text('No entries yet this month',
                style: TextStyle(fontWeight: FontWeight.w800,
                    color: KratosColors.text, fontSize: 15)),
            SizedBox(height: 6),
            Text('Be the first! The top spot is yours.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: KratosColors.muted)),
          ]),
        )
      else
        ...(_monthRecords.asMap().entries.map((e) {
          final r = e.value;
          final isFirst = e.key == 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isFirst
                    ? KratosColors.warning.withOpacity(0.06)
                    : KratosColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFirst
                      ? KratosColors.warning.withOpacity(0.35)
                      : KratosColors.line,
                  width: isFirst ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                SizedBox(width: 32, child: Center(child:
                  e.key == 0 ? const Text('🥇', style: TextStyle(fontSize: 22))
                  : e.key == 1 ? const Text('🥈', style: TextStyle(fontSize: 20))
                  : e.key == 2 ? const Text('🥉', style: TextStyle(fontSize: 20))
                  : Text('${e.key + 1}', style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: KratosColors.muted)),
                )),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: KratosColors.text),
                      overflow: TextOverflow.ellipsis),
                  if (r.model.isNotEmpty)
                    Text(r.model, style: const TextStyle(
                        fontSize: 10, color: KratosColors.muted),
                        overflow: TextOverflow.ellipsis),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatBestDiff(r.bestDiff),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                          color: isFirst ? KratosColors.warning : KratosColors.volt,
                          fontFamily: 'Courier')),
                  Text(_shortDate(r.achievedAt),
                      style: const TextStyle(fontSize: 9, color: KratosColors.muted)),
                ]),
              ]),
            ),
          );
        })),
    ]);
  }

  Widget _buildRules() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: KratosColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: KratosColors.line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('RULES', style: TextStyle(fontSize: 10,
          fontWeight: FontWeight.w800, color: KratosColors.muted,
          letterSpacing: 1.5)),
      const SizedBox(height: 10),
      for (final rule in [
        'One entry per miner — best difficulty in the calendar month',
        'All supported miners eligible: BitAxe, NerdQaxe, NerdOctaxe, Avalon, Antminer, Whatsminer',
        'Winner announced on Discord on the first working day of next month',
        'No purchase necessary — Kratos is completely free',
        'Miner IDs are anonymised. Only name, model and difficulty stored.',
        'Mineshop reserves the right to verify winning entries',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•', style: TextStyle(color: KratosColors.volt,
                fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Expanded(child: Text(rule, style: const TextStyle(
                fontSize: 12, color: KratosColors.muted, height: 1.4))),
          ]),
        ),
    ]),
  );

  Widget _buildCTAs() => Column(children: [
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: KratosColors.warning,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _share,
        icon: const Icon(Icons.share_rounded),
        label: const Text('Share this contest',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF5865F2),
          side: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
          backgroundColor: const Color(0xFF5865F2).withOpacity(0.08),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => launchUrl(Uri.parse('https://discord.gg/yWtYegkDJw'),
            mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.chat_bubble_rounded),
        label: const Text('Join Discord — see winner announced',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ),
  ]);

  void _share() {
    final text =
        '🏆 Monthly Mining Challenge — win an Avalon Nano 3S (€399)!\n\n'
        'Best difficulty share this month wins. All miners eligible.\n'
        'Track yours free with Kratos:\n'
        'iOS: https://apps.apple.com/app/id6762138440\n'
        'Android: https://play.google.com/apps/testing/com.kratos.miningmonitor\n\n'
        'https://kratos.mineshop.eu';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('📋 Contest link copied — share it!'),
      duration: Duration(seconds: 2),
    ));
  }

  String _monthName() {
    const months = ['January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    return months[DateTime.now().month - 1];
  }

  String _shortDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month-1]} ${dt.day}';
  }
}

class _CountdownSep extends StatelessWidget {
  const _CountdownSep();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
        color: KratosColors.warning, fontFamily: 'Courier')),
  );
}

// ── Particle background painter ───────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double t;
  static final _rng = Random(42);
  static final _particles = List.generate(30, (_) => [
    _rng.nextDouble(), // x
    _rng.nextDouble(), // y
    _rng.nextDouble() * 0.4 + 0.1, // size
    _rng.nextDouble(), // phase
  ]);

  _ParticlePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final x = p[0] * size.width;
      final y = ((p[1] + t * (0.1 + p[3] * 0.05)) % 1.0) * size.height;
      final r = p[2] * 3;
      final opacity = (sin((t + p[3]) * 2 * pi) + 1) / 2 * 0.25;
      canvas.drawCircle(
        Offset(x, y), r,
        Paint()..color = KratosColors.warning.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
