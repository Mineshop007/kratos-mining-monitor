import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import '../models/miner.dart';
import '../models/miner_group.dart';
import '../services/group_service.dart';

/// Pool editor that applies to ALL miners in a group.
/// Automatically uses the correct API per miner type:
///   - ESP-Miner (NerdAxe/BitAxe): host + port separately
///   - AvalonHttp (Nano 3S, Nano 3): host + port separately via HTTP PATCH
///   - CGMiner (Mini 3, Q, Antminer): full stratum+tcp:// URL
class GroupPoolEditorScreen extends StatefulWidget {
  final MinerGroup group;
  final List<Miner> miners;
  const GroupPoolEditorScreen(
      {super.key, required this.group, required this.miners});

  @override
  State<GroupPoolEditorScreen> createState() => _GroupPoolEditorScreenState();
}

class _GroupPoolEditorScreenState extends State<GroupPoolEditorScreen> {
  KratosPalette get kc => KratosColors.of(context);

  final _host1 = TextEditingController();
  final _port1 = TextEditingController(text: '3333');
  final _user1 = TextEditingController();
  final _host2 = TextEditingController();
  final _port2 = TextEditingController(text: '3333');
  final _user2 = TextEditingController();

  bool _showFallback = false;
  bool _applying = false;
  final List<MinerActionResult> _results = [];
  String? _workerHint;

  static const _presets = [
    ('Mineshop Solo BTC', 'solo.mineshop.eu', 3333, 'Your BTC address', true),
    ('CKPool Solo BTC', 'solo.ckpool.org', 3333, 'Your BTC address', true),
    ('Public Pool BTC', 'public-pool.io', 21496, 'Your BTC address', true),
    ('ViaBTC BCH', 'bch.viabtc.io', 3333, 'ViaBTC username.worker', false),
    (
      'ViaBTC BCH EU',
      'bch.powhashing.com',
      3333,
      'ViaBTC username.worker',
      false
    ),
    ('F2Pool BCH', 'b4c.f2pool.com', 1228, 'F2Pool account.worker', false),
    ('SoloMining BCH', 'stratum.solomining.io', 5566, 'Your BCH address', true),
    (
      'Binance SHA-256',
      'sha256.poolbinance.com',
      3333,
      'Binance account.worker',
      false
    ),
    ('Ocean BTC', 'mine.ocean.xyz', 3334, 'username.worker', false),
    ('Braiins', 'stratum.braiins.com', 3333, 'username.worker', false),
    ('ViaBTC BTC', 'btc.viabtc.io', 3333, 'username.worker', false),
    ('NiceHash', 'sha256.eu.nicehash.com', 3334, 'NiceHash wallet', false),
  ];

  @override
  void dispose() {
    for (final c in [_host1, _port1, _user1, _host2, _port2, _user2]) {
      c.dispose();
    }
    super.dispose();
  }

  // Count miners by API type for the info banner
  Map<String, int> get _apiTypeCounts {
    final m = <String, int>{};
    for (final miner in widget.miners) {
      final key = switch (miner.type.apiType) {
        ApiType.espMinerHttp => 'ESP-Miner',
        ApiType.avalonHttp => 'Avalon HTTP',
        ApiType.fluMinerHttp => 'FluMiner HTTP',
        ApiType.cgminerTcp => 'CGMiner TCP',
      };
      m[key] = (m[key] ?? 0) + 1;
    }
    return m;
  }

  Future<void> _apply() async {
    final host1 = _host1.text.trim();
    if (host1.isEmpty) return;
    final port1 = int.tryParse(_port1.text.trim()) ?? 3333;
    final user1 = _user1.text.trim().isEmpty ? 'worker' : _user1.text.trim();
    final host2 = _showFallback ? _host2.text.trim() : null;
    final port2 =
        _showFallback ? (int.tryParse(_port2.text.trim()) ?? 3333) : null;
    final user2 = _showFallback
        ? (_user2.text.trim().isEmpty ? user1 : _user2.text.trim())
        : null;

    final config = GroupPoolConfig(
      host1: host1,
      port1: port1,
      user1: user1,
      host2: host2,
      port2: port2,
      user2: user2,
    );

    setState(() {
      _applying = true;
      _results.clear();
    });

    await GroupService.instance.applyPoolToGroup(
      widget.group.id,
      widget.miners,
      config,
      onProgress: (r) => setState(() => _results.add(r)),
    );

    setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.group.color;
    final counts = _apiTypeCounts;

    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        leading: Navigator.canPop(context) ? BackButton(color: kc.text) : null,
        iconTheme: IconThemeData(color: kc.text),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apply Pool to Group',
              style: TextStyle(
                  color: kc.text, fontWeight: FontWeight.w900, fontSize: 16)),
          Text(
              '${widget.group.emoji} ${widget.group.name} · ${widget.miners.length} miners',
              style: TextStyle(color: kc.muted, fontSize: 11)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── API type breakdown ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: accentColor, size: 16),
                  const SizedBox(width: 8),
                  Text('Pool format is applied automatically per miner type:',
                      style: TextStyle(
                          color: kc.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                if (counts.containsKey('ESP-Miner'))
                  _ApiTypeRow(
                      '⚡ ESP-Miner (NerdAxe, BitAxe)',
                      '${counts["ESP-Miner"]} miners',
                      'Host + Port sent separately',
                      kc),
                if (counts.containsKey('Avalon HTTP'))
                  _ApiTypeRow(
                      '🔷 Avalon HTTP (Nano 3S)',
                      '${counts["Avalon HTTP"]} miners',
                      'Host + Port via HTTP PATCH',
                      kc),
                if (counts.containsKey('CGMiner TCP'))
                  _ApiTypeRow(
                      '⛏️ CGMiner TCP (Mini 3, Q, Antminer)',
                      '${counts["CGMiner TCP"]} miners',
                      'Full stratum+tcp:// URL',
                      kc),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick Presets ─────────────────────────────────────────────
          Text('QUICK PRESETS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: kc.muted,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final p = _presets[i];
                final isMineshop = p.$2.contains('mineshop');
                return GestureDetector(
                  onTap: () => setState(() {
                    _host1.text = p.$2;
                    _port1.text = p.$3.toString();
                    _workerHint = p.$4;
                    if (_user1.text.isEmpty) _user1.text = '';
                  }),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: isMineshop
                          ? accentColor.withOpacity(0.08)
                          : kc.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isMineshop
                              ? accentColor.withOpacity(0.5)
                              : kc.line,
                          width: isMineshop ? 1.5 : 1),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.$1,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isMineshop ? accentColor : kc.text),
                              overflow: TextOverflow.ellipsis),
                          Text('${p.$2}:${p.$3}',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: kc.muted,
                                  fontFamily: 'Courier'),
                              overflow: TextOverflow.ellipsis),
                          const Spacer(),
                          Text(p.$5 ? '🎯 SOLO' : '🏊 POOL',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: p.$5
                                      ? const Color(0xFFffd700)
                                      : kc.secondary)),
                        ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Primary pool ───────────────────────────────────────────────
          _SectionLabel('PRIMARY POOL'),
          const SizedBox(height: 8),
          _PoolInputCard(
            hostCtrl: _host1,
            portCtrl: _port1,
            userCtrl: _user1,
            workerHint: _workerHint ?? 'BTC address or username.worker',
            accentColor: accentColor,
          ),
          const SizedBox(height: 14),

          // ── Fallback toggle ────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _showFallback = !_showFallback),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color:
                    _showFallback ? kc.secondary.withOpacity(0.06) : kc.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _showFallback
                        ? kc.secondary.withOpacity(0.4)
                        : kc.line),
              ),
              child: Row(children: [
                Icon(
                  _showFallback ? Icons.shield : Icons.shield_outlined,
                  size: 20,
                  color: _showFallback ? kc.secondary : kc.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add Fallback Pool',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _showFallback ? kc.secondary : kc.text,
                                fontSize: 14)),
                        Text('Miners switch here if Pool 1 fails',
                            style: TextStyle(fontSize: 11, color: kc.muted)),
                      ]),
                ),
                Switch(
                  value: _showFallback,
                  activeColor: kc.secondary,
                  onChanged: (v) => setState(() => _showFallback = v),
                ),
              ]),
            ),
          ),

          if (_showFallback) ...[
            const SizedBox(height: 12),
            _SectionLabel('FALLBACK POOL'),
            const SizedBox(height: 8),
            _PoolInputCard(
              hostCtrl: _host2,
              portCtrl: _port2,
              userCtrl: _user2,
              workerHint: _workerHint ?? 'BTC address or username.worker',
              accentColor: kc.secondary,
            ),
          ],
          const SizedBox(height: 20),

          // ── Results ────────────────────────────────────────────────────
          if (_results.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kc.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RESULTS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kc.muted,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  ..._results.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(
                            r.success
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 16,
                            color: r.success
                                ? const Color(0xFF39d353)
                                : const Color(0xFFff4d4d),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(r.minerName,
                                  style:
                                      TextStyle(color: kc.text, fontSize: 13))),
                          Text(
                            r.success ? '✅ Saved' : '❌ Failed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: r.success
                                  ? const Color(0xFF39d353)
                                  : const Color(0xFFff4d4d),
                            ),
                          ),
                        ]),
                      )),
                  if (!_applying) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_results.where((r) => r.success).length}/${_results.length} miners updated',
                      style: TextStyle(
                          color: kc.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Apply button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _host1.text.trim().isEmpty
                    ? kc.line
                    : const Color(0xFFf7931a),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed:
                  _host1.text.trim().isEmpty || _applying ? null : _apply,
              child: _applying
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black54)),
                      const SizedBox(width: 10),
                      Text('Applying to ${widget.miners.length} miners...',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ])
                  : Text(
                      'Apply to All ${widget.miners.length} Miners',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _PoolInputCard extends StatefulWidget {
  final TextEditingController hostCtrl, portCtrl, userCtrl;
  final String workerHint;
  final Color accentColor;
  const _PoolInputCard({
    required this.hostCtrl,
    required this.portCtrl,
    required this.userCtrl,
    required this.workerHint,
    required this.accentColor,
  });

  @override
  State<_PoolInputCard> createState() => _PoolInputCardState();
}

class _PoolInputCardState extends State<_PoolInputCard> {
  @override
  void initState() {
    super.initState();
    widget.hostCtrl.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.hostCtrl.text.isNotEmpty
                ? widget.accentColor.withOpacity(0.35)
                : kc.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Host
        _Label('POOL ADDRESS (HOST)', kc),
        const SizedBox(height: 4),
        _Field(
          ctrl: widget.hostCtrl,
          hint: 'e.g. solo.mineshop.eu',
          accent: widget.accentColor,
          keyboardType: TextInputType.url,
        ),
        // Live preview
        if (widget.hostCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'stratum+tcp://${widget.hostCtrl.text}:${widget.portCtrl.text.isEmpty ? "3333" : widget.portCtrl.text}',
              style: TextStyle(
                  fontSize: 11,
                  color: widget.accentColor,
                  fontFamily: 'Courier'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(height: 10),
        // Port
        _Label('PORT', kc),
        const SizedBox(height: 4),
        SizedBox(
          width: 110,
          child: _Field(
            ctrl: widget.portCtrl,
            hint: '3333',
            accent: widget.accentColor,
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 10),
        // Worker
        _Label('WORKER / USERNAME', kc),
        const SizedBox(height: 4),
        _Field(
          ctrl: widget.userCtrl,
          hint: widget.workerHint,
          accent: widget.accentColor,
        ),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final KratosPalette kc;
  const _Label(this.text, this.kc);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: kc.muted,
          letterSpacing: 1.5));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final Color accent;
  final TextInputType keyboardType;
  const _Field(
      {required this.ctrl,
      required this.hint,
      required this.accent,
      this.keyboardType = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return TextField(
      controller: ctrl,
      autocorrect: false,
      keyboardType: keyboardType,
      style: TextStyle(color: kc.text, fontFamily: 'Courier', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: kc.muted, fontSize: 12),
        filled: true,
        fillColor: kc.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: kc.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: kc.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: KratosColors.of(context).muted,
          letterSpacing: 1.5));
}

class _ApiTypeRow extends StatelessWidget {
  final String label, count, detail;
  final KratosPalette kc;
  const _ApiTypeRow(this.label, this.count, this.detail, this.kc);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(
              child:
                  Text(label, style: TextStyle(fontSize: 11, color: kc.text))),
          Text(count,
              style: TextStyle(
                  fontSize: 10, color: kc.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(detail,
              style: TextStyle(
                  fontSize: 10, color: kc.muted, fontFamily: 'Courier')),
        ]),
      );
}
