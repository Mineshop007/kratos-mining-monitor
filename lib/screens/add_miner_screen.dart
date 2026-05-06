import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/miner_store.dart';
import '../widgets/miner_icon.dart';
import 'discover_screen.dart';

class AddMinerScreen extends StatefulWidget {
  const AddMinerScreen({super.key});

  @override
  State<AddMinerScreen> createState() => _AddMinerScreenState();
}

class _AddMinerScreenState extends State<AddMinerScreen> {
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '4028');
  final _remoteUrlCtrl = TextEditingController();

  MinerType _selectedType = MinerType.generic;
  bool _testing = false;
  bool _scanning = false;
  String? _testResult;
  List<String> _discovered = [];

  @override
  void initState() {
    super.initState();
    // Listen to controller so Add button reacts to typing, paste, autocomplete.
    _ipCtrl.addListener(_onIpChanged);
  }

  void _onIpChanged() => setState(() {});

  static const _presets = [
    ('CKPool Solo', 'stratum+tcp://solo.ckpool.org:3333'),
    ('Public Pool', 'stratum+tcp://public-pool.io:21496'),
    ('ViaBTC', 'stratum+tcp://btc.viabtc.io:3333'),
    ('Braiins', 'stratum+tcp://stratum.braiins.com:3333'),
    ('Ocean', 'stratum+tcp://mine.ocean.xyz:3334'),
    ('NiceHash', 'stratum+tcp://sha256.eu.nicehash.com:3334'),
  ];

  void _onTypeChanged(MinerType? type) {
    if (type == null) return;
    setState(() {
      _selectedType = type;
      _portCtrl.text = type.defaultPort.toString();
    });
  }

  String get _ipHint {
    if (_selectedType.apiType == ApiType.espMinerHttp) {
      return '192.168.1.108';
    }
    return '192.168.1.104';
  }

  @override
  void dispose() {
    _ipCtrl.removeListener(_onIpChanged);
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _remoteUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('Add Miner',
            style: TextStyle(color: KratosTheme.textPrim)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: KratosTheme.muted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _ipCtrl.text.trim().isNotEmpty ? _addMiner : null,
            child: Text('Add',
                style: TextStyle(
                  color: _ipCtrl.text.trim().isNotEmpty
                      ? KratosTheme.orange
                      : KratosTheme.muted,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Auto-discover banner — one tap launches LAN scan.
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KratosTheme.neon.withOpacity(0.18),
                  KratosTheme.neon.withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: KratosTheme.neon.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_rounded,
                    color: KratosTheme.neon, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-discover on LAN',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: KratosTheme.textPrim)),
                      SizedBox(height: 2),
                      Text('mDNS + subnet sweep · ~10s',
                          style: TextStyle(
                              fontSize: 11,
                              color: KratosTheme.muted)),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KratosTheme.neon,
                    foregroundColor: const Color(0xFF001A0E),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DiscoverScreen()),
                  ),
                  child: const Text('Scan',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          // Miner type picker (visual chips)
          _Section(title: 'MINER TYPE', icon: Icons.memory, children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MinerType.values.map((t) {
                final selected = t == _selectedType;
                return GestureDetector(
                  onTap: () => _onTypeChanged(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? KratosTheme.orange.withOpacity(0.15)
                          : KratosTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? KratosTheme.orange
                            : KratosTheme.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MinerIcon(type: t, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          t.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? KratosTheme.orange
                                : KratosTheme.textPrim,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // API type indicator
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedType.apiType == ApiType.espMinerHttp
                    ? KratosTheme.neon.withOpacity(0.08)
                    : KratosTheme.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedType.apiType == ApiType.espMinerHttp
                      ? KratosTheme.neon.withOpacity(0.3)
                      : KratosTheme.blue.withOpacity(0.3),
                ),
              ),
              child: Text(
                _selectedType.apiType == ApiType.espMinerHttp
                    ? 'ESP-Miner HTTP API  ·  default port ${_selectedType.defaultPort}'
                    : 'CGMiner TCP API  ·  default port ${_selectedType.defaultPort}',
                style: TextStyle(
                  fontSize: 11,
                  color: _selectedType.apiType == ApiType.espMinerHttp
                      ? KratosTheme.neon
                      : KratosTheme.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // Manual entry
          _Section(
              title: 'CONNECTION',
              icon: Icons.edit_outlined,
              children: [
                _Field('MINER NAME', 'e.g. BitAxe Living Room',
                    _nameCtrl),
                const SizedBox(height: 12),
                _Field('IP ADDRESS', _ipHint, _ipCtrl,
                    type: TextInputType.url,
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                _Field(
                    'PORT',
                    _selectedType.defaultPort.toString(),
                    _portCtrl,
                    type: TextInputType.number),
              ]),

          const SizedBox(height: 12),

          // Test connection
          _OutlinedButton(
            icon: Icons.network_check,
            label: _testing ? 'Testing...' : 'Test Connection',
            color: KratosTheme.orange,
            loading: _testing,
            onPressed: _ipCtrl.text.trim().isNotEmpty ? _test : null,
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
                  style: TextStyle(
                      fontSize: 13,
                      color: _testResult!.startsWith('✅')
                          ? KratosTheme.neon
                          : KratosTheme.red,
                      fontFamily: 'Courier')),
            ),

          const SizedBox(height: 16),

          // Auto-discover
          _Section(
              title: 'AUTO-DISCOVER',
              icon: Icons.search,
              children: [
                _OutlinedButton(
                  icon: Icons.wifi,
                  label: _scanning
                      ? 'Scanning network...'
                      : 'Scan Local Network',
                  color: KratosTheme.blue,
                  loading: _scanning,
                  onPressed: _scanning ? null : _scan,
                ),
                if (_discovered.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ..._discovered.map((ip) => _DiscoveredItem(
                        ip: ip,
                        onTap: () {
                          _ipCtrl.text = ip;
                          _nameCtrl.text = 'Miner at $ip';
                          setState(() {});
                        },
                      )),
                ],
              ]),

          const SizedBox(height: 16),

          // Pool presets info
          _Section(
              title: 'QUICK POOL PRESETS',
              icon: Icons.pool_outlined,
              children: [
                const Text(
                  'You can set pools after adding the miner.',
                  style: TextStyle(fontSize: 12, color: KratosTheme.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presets
                      .map((p) => _PresetChip(name: p.$1))
                      .toList(),
                ),
              ]),

          const SizedBox(height: 12),

          // Advanced section
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(
                color: KratosTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KratosTheme.border),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                leading: const Icon(Icons.settings_ethernet, size: 14, color: KratosTheme.muted),
                title: const Text('ADVANCED',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KratosTheme.muted,
                        letterSpacing: 1.5)),
                iconColor: KratosTheme.muted,
                collapsedIconColor: KratosTheme.muted,
                children: [
                  _Field('REMOTE URL (OPTIONAL)', 'http://yourip:4028',
                      _remoteUrlCtrl, type: TextInputType.url),
                  const SizedBox(height: 4),
                  const Text(
                    'Use when the miner is behind a tunnel or reverse proxy.',
                    style: TextStyle(fontSize: 11, color: KratosTheme.muted),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ip = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text) ?? _selectedType.defaultPort;

    // Try the selected type first, then auto-detect the other protocol
    MinerStats s;
    MinerType detectedType = _selectedType;

    if (_selectedType.apiType == ApiType.espMinerHttp) {
      s = await EspMinerAPI.instance.fetchAll(ip, port);
      if (s.status == MinerStatus.offline) {
        // Fallback: try CGMiner TCP in case user selected wrong type
        s = await CGMinerAPI.instance.fetchAll(ip, 4028);
        if (s.status != MinerStatus.offline) {
          detectedType = MinerType.detect(s.model);
          if (detectedType.apiType == ApiType.espMinerHttp) detectedType = MinerType.generic;
        }
      } else {
        detectedType = MinerType.detect(s.model);
      }
    } else {
      s = await CGMinerAPI.instance.fetchAll(ip, port);
      if (s.status == MinerStatus.offline) {
        // Fallback: try ESP-Miner HTTP in case user selected wrong type
        s = await EspMinerAPI.instance.fetchAll(ip, 80);
        if (s.status != MinerStatus.offline) {
          detectedType = MinerType.detect(s.model);
          if (detectedType.apiType != ApiType.espMinerHttp) detectedType = MinerType.bitaxeGamma;
        }
      }
    }

    setState(() {
      _testing = false;
      if (s.status != MinerStatus.offline) {
        final modelStr = s.model.isNotEmpty ? s.model : detectedType.displayName;
        final switchedType = detectedType != _selectedType;
        _testResult = '✅ Connected! $modelStr · ${s.hashrateFormatted}'
            '${switchedType ? '\nAuto-detected as ${detectedType.displayName} — type updated' : ''}';
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = modelStr;
        }
        // Auto-update the selected type if we detected a different protocol
        if (switchedType) {
          _onTypeChanged(detectedType);
        }
      } else {
        _testResult = '❌ Cannot connect. Check IP, port and miner type.';
      }
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _discovered = [];
    });
    final subnet = _getSubnet();
    // Try both ESP-Miner (port 80) and CGMiner (port 4028) probes
    final futures = List.generate(254, (i) async {
      final ip = '$subnet.${i + 1}';
      // Try ESP-Miner first (port 80)
      final espStats = await EspMinerAPI.instance
          .fetchAll(ip, 80)
          .timeout(const Duration(seconds: 2),
              onTimeout: () => MinerStats.offline);
      if (espStats.status != MinerStatus.offline) return ip;
      // Try CGMiner (port 4028)
      final cgStats = await CGMinerAPI.instance
          .fetchAll(ip, 4028)
          .timeout(const Duration(seconds: 2),
              onTimeout: () => MinerStats.offline);
      return cgStats.status != MinerStatus.offline ? ip : null;
    });
    final results = await Future.wait(futures);
    setState(() {
      _discovered = results.whereType<String>().toList()..sort();
      _scanning = false;
    });
  }

  String _getSubnet() {
    if (_ipCtrl.text.trim().isNotEmpty) {
      final parts = _ipCtrl.text.split('.');
      if (parts.length >= 3) return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return '192.168.1';
  }

  void _addMiner() {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;

    // Duplicate IP check
    final store = context.read<MinerStore>();
    final duplicate = store.miners.any((m) => m.ip == ip);
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ip is already in your fleet'),
          backgroundColor: KratosTheme.surface,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OK',
            textColor: KratosTheme.orange,
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    final miner = Miner(
      name: _nameCtrl.text.trim().isEmpty
          ? 'Miner at $ip'
          : _nameCtrl.text.trim(),
      ip: ip,
      port: int.tryParse(_portCtrl.text) ?? _selectedType.defaultPort,
      type: _selectedType,
      remoteUrl: _remoteUrlCtrl.text.trim(),
    );
    store.add(miner);
    Navigator.pop(context);
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section(
      {required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KratosTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 14, color: KratosTheme.muted),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KratosTheme.muted,
                        letterSpacing: 1.5)),
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
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KratosTheme.muted,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: type,
            style: const TextStyle(
                color: KratosTheme.textPrim, fontFamily: 'Courier'),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: KratosTheme.muted),
              filled: true,
              fillColor: KratosTheme.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: KratosTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: KratosTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: KratosTheme.orange),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
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
  const _OutlinedButton(
      {required this.icon,
      required this.label,
      required this.color,
      this.loading = false,
      this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.4)),
            backgroundColor: color.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onPressed,
          icon: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KratosTheme.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KratosTheme.border),
          ),
          child: Row(children: [
            const Icon(Icons.memory,
                color: KratosTheme.neon, size: 16),
            const SizedBox(width: 10),
            Text(ip,
                style: const TextStyle(
                    color: KratosTheme.textPrim,
                    fontFamily: 'Courier')),
            const Spacer(),
            const Text('TAP TO ADD',
                style: TextStyle(
                    fontSize: 10,
                    color: KratosTheme.muted,
                    letterSpacing: 0.8)),
          ]),
        ),
      );
}

class _PresetChip extends StatelessWidget {
  final String name;
  const _PresetChip({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: KratosTheme.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: KratosTheme.border),
        ),
        child: Text(name,
            style: const TextStyle(
                fontSize: 12, color: KratosTheme.muted)),
      );
}
