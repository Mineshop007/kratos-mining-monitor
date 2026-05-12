import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/avalon_api.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/fluminer_api.dart';
import '../services/miner_store.dart';
import '../widgets/miner_icon.dart';
import 'discover_screen.dart';

class AddMinerScreen extends StatefulWidget {
  const AddMinerScreen({super.key});

  @override
  State<AddMinerScreen> createState() => _AddMinerScreenState();
}

class _AddMinerScreenState extends State<AddMinerScreen> {
  KratosPalette get kc => KratosColors.of(context);

  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '4028');
  final _remoteUrlCtrl = TextEditingController();

  MinerType _selectedType = MinerType.generic;
  bool _testing = false;
  bool _scanning = false;
  bool _autoDetecting = false; // background probe running
  bool _autoDetected = false; // probe succeeded — type was set automatically
  String? _testResult;
  List<String> _discovered = [];
  Timer? _detectDebounce;

  @override
  void initState() {
    super.initState();
    _ipCtrl.addListener(_onIpChanged);
  }

  void _onIpChanged() {
    setState(() {
      _autoDetected = false; // IP changed — invalidate previous detection
    });
    _detectDebounce?.cancel();
    final ip = _ipCtrl.text.trim();
    // Auto-detect after 700 ms of no typing, only when IP looks valid
    if (_isValidIp(ip)) {
      _detectDebounce =
          Timer(const Duration(milliseconds: 700), () => _autoDetect(ip));
    }
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Silently probe the IP and auto-fill type + name. Runs in background.
  Future<void> _autoDetect(String ip) async {
    if (!mounted) return;
    setState(() {
      _autoDetecting = true;
      _testResult = null;
    });

    MinerType detected = MinerType.generic;
    String detectedName = '';

    // Try ESP-Miner HTTP first (port 80, then 8080)
    for (final port in [80, 8080]) {
      final s = await EspMinerAPI.instance.fetchAll(ip, port).timeout(
          const Duration(seconds: 4),
          onTimeout: () => MinerStats.offline);
      if (s.status != MinerStatus.offline) {
        detected =
            s.type != MinerType.generic ? s.type : MinerType.detect(s.model);
        if (detected == MinerType.generic) detected = MinerType.bitaxeGamma;
        detectedName = s.model.isNotEmpty ? s.model : detected.displayName;
        if (port == 8080) _portCtrl.text = '8080';
        break;
      }
    }

    // Fallback: FluMiner T3 HTTP API
    if (detected == MinerType.generic) {
      final s = await FluMinerAPI.instance.fetchStats(ip, port: 80).timeout(
          const Duration(seconds: 4),
          onTimeout: () => MinerStats.offline);
      if (s.status != MinerStatus.offline) {
        detected = MinerType.fluMinerT3;
        detectedName = 'FluMiner T3';
      }
    }

    // Fallback: Avalon HTTP
    if (detected == MinerType.generic) {
      final s = await AvalonAPI.instance.fetchStats(ip, MinerType.avalonNano3s).timeout(
          const Duration(seconds: 4),
          onTimeout: () => MinerStats.offline);
      if (s.status != MinerStatus.offline) {
        detected = MinerType.avalonNano3s;
        detectedName = s.model.isNotEmpty ? s.model : 'Avalon';
      }
    }

    // Fallback: CGMiner TCP
    if (detected == MinerType.generic) {
      final s = await CGMinerAPI.instance.fetchAll(ip, 4028).timeout(
          const Duration(seconds: 3),
          onTimeout: () => MinerStats.offline);
      if (s.status != MinerStatus.offline) {
        detected = MinerType.detect(s.model);
        if (detected.apiType != ApiType.cgminerTcp)
          detected = MinerType.generic;
        detectedName = s.model.isNotEmpty ? s.model : detected.displayName;
        _portCtrl.text = '4028';
      }
    }

    if (!mounted) return;
    setState(() {
      _autoDetecting = false;
      if (detected != MinerType.generic) {
        _selectedType = detected;
        _autoDetected = true;
        if (_nameCtrl.text.trim().isEmpty && detectedName.isNotEmpty) {
          _nameCtrl.text = detectedName;
        }
        _testResult = '✅ Auto-detected: ${detected.displayName}';
      }
    });
  }

  static const _presets = [
    ('Mineshop Solo BTC', 'stratum+tcp://solo.mineshop.eu:3333'),
    ('CKPool Solo', 'stratum+tcp://solo.ckpool.org:3333'),
    ('Public Pool', 'stratum+tcp://public-pool.io:21496'),
    ('ViaBTC BTC', 'stratum+tcp://btc.viabtc.io:3333'),
    ('ViaBTC BCH', 'stratum+tcp://bch.viabtc.io:3333'),
    ('F2Pool BCH', 'stratum+tcp://b4c.f2pool.com:1228'),
    ('SoloMining BCH', 'stratum+tcp://stratum.solomining.io:5566'),
    ('Braiins', 'stratum+tcp://stratum.braiins.com:3333'),
    ('Ocean', 'stratum+tcp://mine.ocean.xyz:3334'),
    ('Binance SHA-256', 'stratum+tcp://sha256.poolbinance.com:3333'),
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
    _detectDebounce?.cancel();
    _ipCtrl.removeListener(_onIpChanged);
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _remoteUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('Add Miner', style: TextStyle(color: kc.text)),
        leading: IconButton(
          icon: Icon(Icons.close, color: kc.muted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _ipCtrl.text.trim().isNotEmpty ? _addMiner : null,
            child: Text('Add',
                style: TextStyle(
                  color: _ipCtrl.text.trim().isNotEmpty
                      ? KratosTheme.orange
                      : kc.muted,
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
                  kc.accent.withOpacity(0.18),
                  kc.accent.withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kc.accent.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.radar_rounded, color: kc.accent, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-discover on LAN',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: kc.text)),
                      SizedBox(height: 2),
                      Text('mDNS + subnet sweep · ~10s',
                          style: TextStyle(fontSize: 11, color: kc.muted)),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kc.accent,
                    foregroundColor: const Color(0xFF001A0E),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoverScreen()),
                  ),
                  child: Text('Scan',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          // Auto-detecting indicator
          if (_autoDetecting)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KratosTheme.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KratosTheme.orange.withOpacity(0.3)),
              ),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: KratosTheme.orange)),
                SizedBox(width: 10),
                Text('Detecting miner type…',
                    style: TextStyle(fontSize: 13, color: KratosTheme.orange)),
              ]),
            ),

          // Auto-detected badge
          if (_autoDetected && !_autoDetecting)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kc.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kc.accent.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: kc.accent, size: 16),
                SizedBox(width: 8),
                Text('Auto-detected: ${_selectedType.displayName}',
                    style: TextStyle(
                        fontSize: 13,
                        color: kc.accent,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('tap chip to override',
                    style: TextStyle(fontSize: 10, color: kc.muted)),
              ]),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? KratosTheme.orange.withOpacity(0.15)
                          : kc.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? KratosTheme.orange : kc.line,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MinerIcon(type: t, size: 18),
                        SizedBox(width: 6),
                        Text(
                          t.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? KratosTheme.orange : kc.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 8),
            // API type indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedType.apiType == ApiType.espMinerHttp
                    ? kc.accent.withOpacity(0.08)
                    : KratosTheme.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedType.apiType == ApiType.espMinerHttp
                      ? kc.accent.withOpacity(0.3)
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
                      ? kc.accent
                      : KratosTheme.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),

          SizedBox(height: 12),

          // Manual entry
          _Section(title: 'CONNECTION', icon: Icons.edit_outlined, children: [
            _Field('MINER NAME', 'e.g. BitAxe Living Room', _nameCtrl),
            SizedBox(height: 12),
            _Field('IP ADDRESS', _ipHint, _ipCtrl,
                type: TextInputType.url, onChanged: (_) => setState(() {})),
            SizedBox(height: 12),
            _Field('PORT', _selectedType.defaultPort.toString(), _portCtrl,
                type: TextInputType.number),
          ]),

          SizedBox(height: 12),

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
                color: kc.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                      fontSize: 13,
                      color: _testResult!.startsWith('✅')
                          ? kc.accent
                          : KratosTheme.red,
                      fontFamily: 'Courier')),
            ),

          SizedBox(height: 16),

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
              SizedBox(height: 10),
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

          SizedBox(height: 16),

          // Pool presets info
          _Section(
              title: 'QUICK POOL PRESETS',
              icon: Icons.pool_outlined,
              children: [
                Text(
                  'You can set pools after adding the miner.',
                  style: TextStyle(fontSize: 12, color: kc.muted),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _presets.map((p) => _PresetChip(name: p.$1)).toList(),
                ),
              ]),

          SizedBox(height: 12),

          // Advanced section
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kc.line),
              ),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                leading:
                    Icon(Icons.settings_ethernet, size: 14, color: kc.muted),
                title: Text('ADVANCED',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kc.muted,
                        letterSpacing: 1.5)),
                iconColor: kc.muted,
                collapsedIconColor: kc.muted,
                children: [
                  _Field('REMOTE URL (OPTIONAL)', 'http://yourip:4028',
                      _remoteUrlCtrl,
                      type: TextInputType.url),
                  SizedBox(height: 4),
                  Text(
                    'Use when the miner is behind a tunnel or reverse proxy.',
                    style: TextStyle(fontSize: 11, color: kc.muted),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 32),
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

    if (_selectedType.apiType == ApiType.fluMinerHttp) {
      // FluMiner T3 — uses its own HTTP REST API
      s = await FluMinerAPI.instance.fetchStats(ip, port: port);
    } else if (_selectedType.apiType == ApiType.avalonHttp) {
      // Avalon Nano — HTTP REST API
      s = await AvalonAPI.instance.fetchStats(ip, _selectedType);
    } else if (_selectedType.apiType == ApiType.espMinerHttp) {
      s = await EspMinerAPI.instance.fetchAll(ip, port);
      if (s.status == MinerStatus.offline) {
        // Fallback: try CGMiner TCP in case user selected wrong type
        s = await CGMinerAPI.instance.fetchAll(ip, 4028);
        if (s.status != MinerStatus.offline) {
          detectedType = MinerType.detect(s.model);
          if (detectedType.apiType == ApiType.espMinerHttp)
            detectedType = MinerType.generic;
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
          if (detectedType.apiType != ApiType.espMinerHttp)
            detectedType = MinerType.bitaxeGamma;
        }
      }
    }

    setState(() {
      _testing = false;
      if (s.status != MinerStatus.offline) {
        final modelStr =
            s.model.isNotEmpty ? s.model : detectedType.displayName;
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
      final espStats = await EspMinerAPI.instance.fetchAll(ip, 80).timeout(
          const Duration(seconds: 2),
          onTimeout: () => MinerStats.offline);
      if (espStats.status != MinerStatus.offline) return ip;
      // Try CGMiner (port 4028)
      final cgStats = await CGMinerAPI.instance.fetchAll(ip, 4028).timeout(
          const Duration(seconds: 2),
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

  Future<void> _addMiner() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;

    // Duplicate IP check
    final store = context.read<MinerStore>();
    final duplicate = store.miners.any((m) => m.ip == ip);
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ip is already in your fleet'),
          backgroundColor: kc.surface,
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

    // If type is still generic (user never touched it and auto-detect didn't
    // fire yet), run a quick probe now before saving.
    var typeToSave = _selectedType;
    if (typeToSave == MinerType.generic && _isValidIp(ip)) {
      _detectDebounce?.cancel();
      await _autoDetect(ip);
      typeToSave = _selectedType; // updated by _autoDetect
    }
    // Last safety net: still generic after probe — default to bitaxeGamma
    // so it routes through ESP-Miner HTTP (works for all NerdAxe/BitAxe).
    if (typeToSave == MinerType.generic) typeToSave = MinerType.bitaxeGamma;

    if (!mounted) return;
    final miner = Miner(
      name: _nameCtrl.text.trim().isEmpty
          ? 'Miner at $ip'
          : _nameCtrl.text.trim(),
      ip: ip,
      port: int.tryParse(_portCtrl.text) ?? typeToSave.defaultPort,
      type: typeToSave,
      remoteUrl: _remoteUrlCtrl.text.trim(),
    );
    store.add(miner, warmUp: true);
    Navigator.pop(context);
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kc.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: kc.muted),
          SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kc.muted,
                  letterSpacing: 1.5)),
        ]),
        SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final TextInputType type;
  final ValueChanged<String>? onChanged;
  const _Field(this.label, this.hint, this.ctrl,
      {this.type = TextInputType.text, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kc.muted,
                letterSpacing: 1.5)),
        SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: type,
          style: TextStyle(color: kc.text, fontFamily: 'Courier'),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kc.muted),
            filled: true,
            fillColor: kc.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kc.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kc.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: KratosTheme.orange),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.4)),
          backgroundColor: color.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DiscoveredItem extends StatelessWidget {
  final String ip;
  final VoidCallback onTap;
  const _DiscoveredItem({required this.ip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kc.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kc.line),
        ),
        child: Row(children: [
          Icon(Icons.memory, color: kc.accent, size: 16),
          SizedBox(width: 10),
          Text(ip, style: TextStyle(color: kc.text, fontFamily: 'Courier')),
          const Spacer(),
          Text('TAP TO ADD',
              style:
                  TextStyle(fontSize: 10, color: kc.muted, letterSpacing: 0.8)),
        ]),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String name;
  const _PresetChip({required this.name});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kc.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kc.line),
      ),
      child: Text(name, style: TextStyle(fontSize: 12, color: kc.muted)),
    );
  }
}
