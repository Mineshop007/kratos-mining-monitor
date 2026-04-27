import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';

class PoolEditorScreen extends StatefulWidget {
  final Miner miner;
  final List<PoolInfo> currentPools;
  const PoolEditorScreen({super.key, required this.miner, required this.currentPools});

  @override
  State<PoolEditorScreen> createState() => _PoolEditorScreenState();
}

class _PoolEditorScreenState extends State<PoolEditorScreen> {
  final _url1 = TextEditingController();
  final _usr1 = TextEditingController();
  final _url2 = TextEditingController();
  final _usr2 = TextEditingController();
  final _url3 = TextEditingController();
  final _usr3 = TextEditingController();
  bool saving = false;
  String? result;

  static const _presets = [
    ('CKPool Solo',  'stratum+tcp://solo.ckpool.org:3333',           '⛏️ Solo mining — win full block reward'),
    ('Public Pool',  'stratum+tcp://public-pool.io:21496',           '⛏️ Open-source solo pool'),
    ('ViaBTC',       'stratum+tcp://btc.viabtc.io:3333',             '🏊 Pool mining — regular payouts'),
    ('Braiins',      'stratum+tcp://stratum.braiins.com:3333',       '🏊 Braiins pool'),
    ('Ocean',        'stratum+tcp://mine.ocean.xyz:3334',            '🌊 Ocean decentralised pool'),
    ('NiceHash',     'stratum+tcp://sha256.eu.nicehash.com:3334',    '💱 Sell hashrate for BTC'),
  ];

  @override
  void initState() {
    super.initState();
    _prefill();
    // Listeners so Save button state updates as user types
    _url1.addListener(() => setState(() {}));
    _url2.addListener(() => setState(() {}));
    _url3.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url1.dispose(); _usr1.dispose();
    _url2.dispose(); _usr2.dispose();
    _url3.dispose(); _usr3.dispose();
    super.dispose();
  }

  void _prefill() {
    final pools = widget.currentPools;
    if (pools.isNotEmpty) { _url1.text = pools[0].url; _usr1.text = pools[0].user; }
    if (pools.length > 1) { _url2.text = pools[1].url; _usr2.text = pools[1].user; }
    if (pools.length > 2) { _url3.text = pools[2].url; _usr3.text = pools[2].user; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('Configure Pools', style: TextStyle(color: KratosTheme.textPrim)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KratosTheme.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KratosTheme.blue.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.info_outline, color: KratosTheme.blue, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Pool 1 is primary. Pools 2 & 3 are failovers. Changes apply immediately.',
              style: TextStyle(fontSize: 12, color: KratosTheme.muted))),
          ]),
        ),
        const SizedBox(height: 16),

        // Pool entries
        _PoolEntry(index: 1, urlCtrl: _url1, userCtrl: _usr1),
        const SizedBox(height: 12),
        _PoolEntry(index: 2, urlCtrl: _url2, userCtrl: _usr2),
        const SizedBox(height: 12),
        _PoolEntry(index: 3, urlCtrl: _url3, userCtrl: _usr3),
        const SizedBox(height: 20),

        // Quick presets
        const Text('QUICK PRESETS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: KratosTheme.muted, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        ..._presets.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() {
              _url1.text = p.$2;
              if (_usr1.text.isEmpty) _usr1.text = 'worker.kratos';
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KratosTheme.border)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.$1, style: const TextStyle(fontWeight: FontWeight.w600,
                    color: KratosTheme.textPrim)),
                  Text(p.$3, style: const TextStyle(fontSize: 11, color: KratosTheme.muted)),
                ])),
                const Text('USE', style: TextStyle(fontSize: 11,
                  color: KratosTheme.orange, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        )),

        const SizedBox(height: 20),

        if (result != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: KratosTheme.surface, borderRadius: BorderRadius.circular(8)),
            child: Text(result!, style: TextStyle(fontSize: 13,
              color: result!.startsWith('✅') ? KratosTheme.neon : KratosTheme.red)),
          ),
          const SizedBox(height: 12),
        ],

        // Save button
        SizedBox(width: double.infinity, child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _url1.text.isEmpty ? KratosTheme.border : KratosTheme.orange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _url1.text.isEmpty || saving ? null : _save,
          icon: saving
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
            : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Saving...' : 'Save Pool Config',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        )),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _save() async {
    setState(() { saving = true; result = null; });
    final pools = <Map<String, String>>[];
    if (_url1.text.isNotEmpty) pools.add({'url': _url1.text, 'user': _usr1.text.isEmpty ? 'worker' : _usr1.text, 'pass': 'x'});
    if (_url2.text.isNotEmpty) pools.add({'url': _url2.text, 'user': _usr2.text.isEmpty ? 'worker' : _usr2.text, 'pass': 'x'});
    if (_url3.text.isNotEmpty) pools.add({'url': _url3.text, 'user': _usr3.text.isEmpty ? 'worker' : _usr3.text, 'pass': 'x'});
    final ok = await CGMinerAPI.instance.setPools(widget.miner.ip, widget.miner.port, pools);
    setState(() {
      saving = false;
      result = ok ? '✅ Pools updated successfully' : '❌ Failed to update pools';
    });
    if (ok) await Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }
}

// ── StatefulWidget so TextField changes trigger parent rebuild ─────────────────

class _PoolEntry extends StatefulWidget {
  final int index;
  final TextEditingController urlCtrl, userCtrl;
  const _PoolEntry({required this.index, required this.urlCtrl, required this.userCtrl});

  @override
  State<_PoolEntry> createState() => _PoolEntryState();
}

class _PoolEntryState extends State<_PoolEntry> {
  @override
  void initState() {
    super.initState();
    widget.urlCtrl.addListener(_rebuild);
    widget.userCtrl.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.urlCtrl.removeListener(_rebuild);
    widget.userCtrl.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isActive = widget.index == 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive
          ? KratosTheme.orange.withOpacity(0.4) : KratosTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: isActive ? KratosTheme.orange : KratosTheme.border,
              shape: BoxShape.circle),
            child: Center(child: Text('${widget.index}', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.black : KratosTheme.muted))),
          ),
          const SizedBox(width: 10),
          Text('Pool ${widget.index}${widget.index == 1 ? " (Primary)" : widget.index == 2 ? " (Failover)" : " (Failover 2)"}',
            style: const TextStyle(fontWeight: FontWeight.w600, color: KratosTheme.textPrim)),
        ]),
        const SizedBox(height: 12),
        _Input('STRATUM URL', 'stratum+tcp://pool.example.com:3333', widget.urlCtrl),
        const SizedBox(height: 8),
        _Input('WORKER / USERNAME', 'username.workername', widget.userCtrl),
      ]),
    );
  }
}

class _Input extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  const _Input(this.label, this.hint, this.ctrl);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
        color: KratosTheme.muted, letterSpacing: 1.5)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        autocorrect: false,
        style: const TextStyle(color: KratosTheme.textPrim, fontFamily: 'Courier', fontSize: 13),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: KratosTheme.muted, fontSize: 12),
          filled: true, fillColor: KratosTheme.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.orange)),
        ),
      ),
    ],
  );
}
