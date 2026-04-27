import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/miner_store.dart';

class AddMinerScreen extends StatefulWidget {
  const AddMinerScreen({super.key});

  @override
  State<AddMinerScreen> createState() => _AddMinerScreenState();
}

class _AddMinerScreenState extends State<AddMinerScreen> {
  final _nameCtrl = TextEditingController();
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController(text: '4028');

  bool _testing = false;
  bool _scanning = false;
  String? _testResult;
  List<String> _discovered = [];

  // Pool presets
  static const presets = [
    ('CKPool Solo',    'stratum+tcp://solo.ckpool.org:3333'),
    ('Public Pool',    'stratum+tcp://public-pool.io:21496'),
    ('ViaBTC',         'stratum+tcp://btc.viabtc.io:3333'),
    ('Braiins',        'stratum+tcp://stratum.braiins.com:3333'),
    ('Ocean',          'stratum+tcp://mine.ocean.xyz:3334'),
    ('NiceHash',       'stratum+tcp://sha256.eu.nicehash.com:3334'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('Add Miner', style: TextStyle(color: KratosTheme.textPrim)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: KratosTheme.muted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _ipCtrl.text.isNotEmpty ? _addMiner : null,
            child: Text('Add', style: TextStyle(
              color: _ipCtrl.text.isNotEmpty ? KratosTheme.orange : KratosTheme.muted,
              fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Manual entry
          _Section(title: 'MANUAL SETUP', icon: Icons.edit_outlined, children: [
            _Field('MINER NAME', 'e.g. Nano 3S Living Room', _nameCtrl),
            const SizedBox(height: 12),
            _Field('IP ADDRESS', '192.168.1.104', _ipCtrl,
              type: TextInputType.url,
              onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            _Field('PORT', '4028', _portCtrl, type: TextInputType.number),
          ]),

          const SizedBox(height: 12),

          // Test connection
          _OutlinedButton(
            icon: Icons.network_check,
            label: _testing ? 'Testing...' : 'Test Connection',
            color: KratosTheme.orange,
            loading: _testing,
            onPressed: _ipCtrl.text.isNotEmpty ? _test : null,
          ),

          if (_testResult != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_testResult!,
                style: TextStyle(fontSize: 13,
                  color: _testResult!.startsWith('✅') ? KratosTheme.neon : KratosTheme.red,
                  fontFamily: 'Courier')),
            ),

          const SizedBox(height: 16),

          // Auto-discover
          _Section(title: 'AUTO-DISCOVER', icon: Icons.search, children: [
            _OutlinedButton(
              icon: Icons.wifi,
              label: _scanning ? 'Scanning network...' : 'Scan Local Network',
              color: KratosTheme.blue,
              loading: _scanning,
              onPressed: _scanning ? null : _scan,
            ),
            if (_discovered.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._discovered.map((ip) => _DiscoveredItem(ip: ip, onTap: () {
                _ipCtrl.text = ip;
                _nameCtrl.text = 'Miner at $ip';
                setState(() {});
              })),
            ],
          ]),

          const SizedBox(height: 16),

          // Pool presets info
          _Section(title: 'QUICK POOL PRESETS', icon: Icons.pool_outlined, children: [
            Text('You can set pools after adding the miner.',
              style: const TextStyle(fontSize: 12, color: KratosTheme.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: presets.map((p) =>
              _PresetChip(name: p.$1),
            ).toList()),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    final port = int.tryParse(_portCtrl.text) ?? 4028;
    final s = await CGMinerAPI.instance.fetchAll(_ipCtrl.text, port);
    setState(() {
      _testing = false;
      if (s.status != MinerStatus.offline) {
        _testResult = '✅ Connected! ${s.model.isNotEmpty ? s.model : 'Miner'} · ${s.hashrateFormatted}';
        if (_nameCtrl.text.isEmpty && s.model.isNotEmpty) _nameCtrl.text = s.model;
      } else {
        _testResult = '❌ Cannot connect. Check IP and that port ${_portCtrl.text} is reachable.';
      }
    });
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _discovered = []; });
    // Scan common home subnet
    final subnet = _getSubnet();
    final futures = List.generate(254, (i) async {
      final ip = '$subnet.${i + 1}';
      final s = await CGMinerAPI.instance.fetchAll(ip, 4028)
        .timeout(const Duration(seconds: 2), onTimeout: () => MinerStats.offline);
      return s.status != MinerStatus.offline ? ip : null;
    });
    final results = await Future.wait(futures);
    setState(() {
      _discovered = results.whereType<String>().toList()..sort();
      _scanning = false;
    });
  }

  String _getSubnet() {
    if (_ipCtrl.text.isNotEmpty) {
      final parts = _ipCtrl.text.split('.');
      if (parts.length >= 3) return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return '192.168.1';
  }

  void _addMiner() {
    final miner = Miner(
      name: _nameCtrl.text.isEmpty ? 'Miner at ${_ipCtrl.text}' : _nameCtrl.text,
      ip: _ipCtrl.text,
      port: int.tryParse(_portCtrl.text) ?? 4028,
    );
    context.read<MinerStore>().add(miner);
    Navigator.pop(context);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: KratosTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: KratosTheme.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: KratosTheme.muted),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: KratosTheme.muted, letterSpacing: 1.5)),
      ]),
      const SizedBox(height: 12),
      ...children,
    ]),
  );
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final TextInputType type;
  final ValueChanged<String>? onChanged;
  const _Field(this.label, this.hint, this.ctrl,
    {this.type = TextInputType.text, this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: KratosTheme.muted, letterSpacing: 1.5)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: KratosTheme.textPrim, fontFamily: 'Courier'),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: KratosTheme.muted),
          filled: true,
          fillColor: KratosTheme.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: KratosTheme.orange),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    ],
  );
}

class _OutlinedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;
  const _OutlinedButton({required this.icon, required this.label,
    required this.color, this.loading = false, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        backgroundColor: color.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: loading
        ? SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: color))
        : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

class _DiscoveredItem extends StatelessWidget {
  final String ip;
  final VoidCallback onTap;
  const _DiscoveredItem({required this.ip, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KratosTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KratosTheme.border),
      ),
      child: Row(children: [
        const Icon(Icons.memory, color: KratosTheme.neon, size: 16),
        const SizedBox(width: 10),
        Text(ip, style: const TextStyle(color: KratosTheme.textPrim, fontFamily: 'Courier')),
        const Spacer(),
        const Text('TAP TO ADD', style: TextStyle(fontSize: 10,
          color: KratosTheme.muted, letterSpacing: 0.8)),
      ]),
    ),
  );
}

class _PresetChip extends StatelessWidget {
  final String name;
  const _PresetChip({required this.name});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: KratosTheme.bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: KratosTheme.border),
    ),
    child: Text(name, style: const TextStyle(fontSize: 12, color: KratosTheme.muted)),
  );
}
