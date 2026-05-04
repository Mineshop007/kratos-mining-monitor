import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';

class PoolEditorScreen extends StatefulWidget {
  final Miner miner;
  final List<PoolInfo> currentPools;
  const PoolEditorScreen(
      {super.key, required this.miner, required this.currentPools});

  @override
  State<PoolEditorScreen> createState() => _PoolEditorScreenState();
}

class _PoolEditorScreenState extends State<PoolEditorScreen> {
  final _url1 = TextEditingController();
  final _usr1 = TextEditingController();
  final _url2 = TextEditingController();
  final _usr2 = TextEditingController();
  // Pool 3 only for non-ESP miners
  final _url3 = TextEditingController();
  final _usr3 = TextEditingController();

  bool saving = false;
  String? result;

  bool get _isEspMiner =>
      widget.miner.type.apiType == ApiType.espMinerHttp;

  // (name, url, description, defaultWorker or null)
  static const _presets = [
    ('Mineshop Solo', 'stratum+tcp://solo.mineshop.eu:3333',
        'Mineshop solo pool ★', '13oXC81RKriTDEtAWfr4QaHt7WUpqB6jL2'),
    ('CKPool Solo', 'stratum+tcp://solo.ckpool.org:3333',
        'Solo mining — win full block reward', null),
    ('Public Pool', 'stratum+tcp://public-pool.io:21496',
        'Open-source solo pool', null),
    ('ViaBTC', 'stratum+tcp://btc.viabtc.io:3333', 'Pool mining — regular payouts', null),
    ('Braiins', 'stratum+tcp://stratum.braiins.com:3333', 'Braiins pool', null),
    ('Ocean', 'stratum+tcp://mine.ocean.xyz:3334', 'Ocean decentralised pool', null),
    ('NiceHash', 'stratum+tcp://sha256.eu.nicehash.com:3334',
        'Sell hashrate for BTC', null),
  ];

  @override
  void initState() {
    super.initState();
    _prefill();
    _url1.addListener(() => setState(() {}));
    _url2.addListener(() => setState(() {}));
    _url3.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url1.dispose();
    _usr1.dispose();
    _url2.dispose();
    _usr2.dispose();
    _url3.dispose();
    _usr3.dispose();
    super.dispose();
  }

  void _prefill() {
    final pools = widget.currentPools;
    if (pools.isNotEmpty) {
      _url1.text = pools[0].url;
      _usr1.text = pools[0].user;
    }
    if (pools.length > 1) {
      _url2.text = pools[1].url;
      _usr2.text = pools[1].user;
    }
    if (pools.length > 2 && !_isEspMiner) {
      _url3.text = pools[2].url;
      _usr3.text = pools[2].user;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('Configure Pools',
            style: TextStyle(color: KratosTheme.textPrim)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ESP-Miner notice
        if (_isEspMiner)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: KratosTheme.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KratosTheme.orange.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  color: KratosTheme.orange, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.miner.type.displayName} supports primary + fallback pool only (2 pools max).',
                  style: const TextStyle(
                      fontSize: 12, color: KratosTheme.muted),
                ),
              ),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: KratosTheme.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KratosTheme.blue.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: KratosTheme.blue, size: 18),
              SizedBox(width: 10),
              Expanded(
                  child: Text(
                'Pool 1 is primary. Pools 2 & 3 are failovers.',
                style: TextStyle(fontSize: 12, color: KratosTheme.muted),
              )),
            ]),
          ),

        // Pool entries
        _PoolEntry(index: 1, urlCtrl: _url1, userCtrl: _usr1),
        const SizedBox(height: 12),
        _PoolEntry(
          index: 2,
          urlCtrl: _url2,
          userCtrl: _usr2,
          label: _isEspMiner ? 'Pool 2 (Fallback)' : 'Pool 2 (Failover)',
        ),
        if (!_isEspMiner) ...[
          const SizedBox(height: 12),
          _PoolEntry(
              index: 3, urlCtrl: _url3, userCtrl: _usr3),
        ],

        const SizedBox(height: 20),

        // Quick presets
        const Text('QUICK PRESETS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KratosTheme.muted,
                letterSpacing: 1.5)),
        const SizedBox(height: 10),
        ..._presets.map((p) {
              final isMineshop = p.$2.contains('mineshop');
              return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  _url1.text = p.$2;
                  if (_usr1.text.isEmpty) {
                    _usr1.text = p.$4 ?? 'worker.kratos';
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMineshop
                        ? KratosTheme.neon.withOpacity(0.06)
                        : KratosTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isMineshop
                            ? KratosTheme.neon.withOpacity(0.5)
                            : KratosTheme.border,
                        width: isMineshop ? 1.5 : 1.0),
                  ),
                  child: Row(children: [
                    if (isMineshop) ...[                      const Icon(Icons.star, size: 14,
                          color: KratosTheme.neon),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(p.$1.replaceAll(' ★', ''),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isMineshop
                                      ? KratosTheme.neon
                                      : KratosTheme.textPrim)),
                          Text(p.$3.replaceAll(' ★', ''),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: KratosTheme.muted)),
                        ])),
                    Text('USE',
                        style: TextStyle(
                            fontSize: 11,
                            color: isMineshop
                                ? KratosTheme.neon
                                : KratosTheme.orange,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            );
            }).toList(),

        const SizedBox(height: 20),

        if (result != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(8)),
            child: Text(result!,
                style: TextStyle(
                    fontSize: 13,
                    color: result!.startsWith('✅')
                        ? KratosTheme.neon
                        : KratosTheme.red)),
          ),
          const SizedBox(height: 12),
        ],

        // Save button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _url1.text.isEmpty ? KratosTheme.border : KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _url1.text.isEmpty || saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black54))
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Saving...' : 'Save Pool Config',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      result = null;
    });

    bool ok;
    if (_isEspMiner) {
      // ESP-Miner: primary + optional fallback
      final primaryUrl = _url1.text.trim();
      final primaryUser = _usr1.text.isEmpty ? 'worker' : _usr1.text.trim();
      final fallbackUrl = _url2.text.trim();
      final fallbackUser = _usr2.text.isEmpty ? primaryUser : _usr2.text.trim();

      // Parse URL into host + port
      final parsedUrl = _parseStratumUrl(primaryUrl);
      final parsedFallback = fallbackUrl.isNotEmpty
          ? _parseStratumUrl(fallbackUrl)
          : null;

      ok = await EspMinerAPI.instance.setPool(
        widget.miner.ip,
        widget.miner.port,
        stratumUrl: parsedUrl.$1,
        stratumPort: parsedUrl.$2,
        stratumUser: primaryUser,
        fallbackStratumUrl: parsedFallback?.$1,
        fallbackStratumPort: parsedFallback?.$2,
        fallbackStratumUser: parsedFallback != null ? fallbackUser : null,
        remoteUrl: widget.miner.remoteUrl,
      );
    } else {
      // CGMiner: up to 3 pools
      final pools = <Map<String, String>>[];
      if (_url1.text.isNotEmpty) {
        pools.add({
          'url': _url1.text,
          'user': _usr1.text.isEmpty ? 'worker' : _usr1.text,
          'pass': 'x'
        });
      }
      if (_url2.text.isNotEmpty) {
        pools.add({
          'url': _url2.text,
          'user': _usr2.text.isEmpty ? 'worker' : _usr2.text,
          'pass': 'x'
        });
      }
      if (_url3.text.isNotEmpty) {
        pools.add({
          'url': _url3.text,
          'user': _usr3.text.isEmpty ? 'worker' : _usr3.text,
          'pass': 'x'
        });
      }
      ok = await CGMinerAPI.instance
          .setPools(widget.miner.ip, widget.miner.port, pools, remoteUrl: widget.miner.remoteUrl);
    }

    setState(() {
      saving = false;
      result =
          ok ? '✅ Pools updated successfully' : '❌ Failed to update pools';
    });
    if (ok) {
      await Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  // Parse "stratum+tcp://host:port" → (host, port)
  (String, int) _parseStratumUrl(String url) {
    final stripped = url
        .replaceAll(RegExp(r'^stratum\+(tcp|ssl)://'), '')
        .trim();
    final parts = stripped.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 3333) : 3333;
    return (host, port);
  }
}

// ── Pool entry widget ──────────────────────────────────────────────────────────

class _PoolEntry extends StatefulWidget {
  final int index;
  final TextEditingController urlCtrl, userCtrl;
  final String? label;

  const _PoolEntry({
    required this.index,
    required this.urlCtrl,
    required this.userCtrl,
    this.label,
  });

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
    final title = widget.label ??
        'Pool ${widget.index}${widget.index == 1 ? " (Primary)" : widget.index == 2 ? " (Failover)" : " (Failover 2)"}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isActive
                ? KratosTheme.orange.withOpacity(0.4)
                : KratosTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isActive ? KratosTheme.orange : KratosTheme.border,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${widget.index}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.black : KratosTheme.muted,
                  )),
            ),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: KratosTheme.textPrim)),
        ]),
        const SizedBox(height: 12),
        _Input('STRATUM URL', 'stratum+tcp://pool.example.com:3333',
            widget.urlCtrl),
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
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KratosTheme.muted,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            autocorrect: false,
            style: const TextStyle(
                color: KratosTheme.textPrim,
                fontFamily: 'Courier',
                fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: KratosTheme.muted, fontSize: 12),
              filled: true,
              fillColor: KratosTheme.bg,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: KratosTheme.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: KratosTheme.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: KratosTheme.orange)),
            ),
          ),
        ],
      );
}
