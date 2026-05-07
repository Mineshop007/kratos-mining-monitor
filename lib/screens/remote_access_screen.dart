import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/miner.dart';
import '../services/relay_service.dart';
import '../services/miner_store.dart';

class RemoteAccessScreen extends StatefulWidget {
  const RemoteAccessScreen({super.key});

  @override
  State<RemoteAccessScreen> createState() => _RemoteAccessScreenState();
}

class _RemoteAccessScreenState extends State<RemoteAccessScreen> {
  final _keyCtrl = TextEditingController();
  bool _connecting = false;

  final _relay = RelayService.instance;

  @override
  void initState() {
    super.initState();
    // Pre-fill saved key
    if (_relay.accessKey != null) {
      _keyCtrl.text = _relay.accessKey!;
    }
    _relay.addListener(_onRelayChange);
  }

  void _onRelayChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _relay.removeListener(_onRelayChange);
    _keyCtrl.dispose();
    super.dispose();
  }

  bool get _isConnected =>
      _relay.state != RelayState.disconnected &&
      _relay.state != RelayState.connecting;

  Future<void> _connect() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() => _connecting = true);
    await _relay.connect(key);
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _disconnect() async {
    await _relay.disconnect();
    if (mounted) setState(() {});
  }

  void _copySetupCommand() {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    Clipboard.setData(
        ClipboardData(text: 'python3 kratos_link.py --key $key'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Setup command copied to clipboard'),
        backgroundColor: Color(0xFF1A2B1A),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addToFleet(Map<String, dynamic> remoteMiner) async {
    final store = context.read<MinerStore>();
    final ip = remoteMiner['ip'] as String? ?? '';
    final port = (remoteMiner['port'] as num?)?.toInt() ?? 80;
    final model = remoteMiner['model'] as String? ?? '';
    if (ip.isEmpty) return;

    final type = MinerType.detect(model);
    final miner = Miner(
      name: model.isNotEmpty ? model : 'Remote: $ip',
      ip: ip,
      port: port,
      type: type,
      isRemote: true,
    );

    // Don't add if the same IP is already in fleet (local OR remote)
    final exists = store.miners.any((m) => m.ip == ip);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ip is already in your fleet'),
          backgroundColor: KratosTheme.surface,
        ),
      );
      return;
    }

    store.add(miner);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${miner.name} added to fleet'),
        backgroundColor: KratosTheme.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosTheme.bg,
      appBar: AppBar(
        backgroundColor: KratosTheme.bg,
        title: const Text('Remote Access',
            style: TextStyle(color: KratosTheme.textPrim)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          _InfoBanner(),
          const SizedBox(height: 16),

          // Status card
          _StatusCard(state: _relay.state),
          const SizedBox(height: 16),

          // Access key input
          _SectionLabel('ACCESS KEY'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _keyCtrl,
                enabled: !_isConnected,
                style: const TextStyle(
                    color: KratosTheme.textPrim, fontFamily: 'Courier'),
                decoration: InputDecoration(
                  hintText: 'Paste your access key here',
                  hintStyle: const TextStyle(color: KratosTheme.muted),
                  filled: true,
                  fillColor: KratosTheme.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: KratosTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: KratosTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: KratosTheme.orange),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _isConnected
                      ? KratosTheme.red
                      : KratosTheme.orange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: _connecting
                    ? null
                    : (_isConnected ? _disconnect : _connect),
                child: _connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54))
                    : Text(
                        _isConnected ? 'Disconnect' : 'Connect',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Actions row
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KratosTheme.blue,
                  side: BorderSide(
                      color: KratosTheme.blue.withOpacity(0.4)),
                  backgroundColor: KratosTheme.blue.withOpacity(0.07),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _keyCtrl.text.trim().isNotEmpty
                    ? _copySetupCommand
                    : null,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Setup Command',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KratosTheme.muted,
                  side: BorderSide(
                      color: KratosTheme.border.withOpacity(0.6)),
                  backgroundColor: KratosTheme.surface.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => launchUrl(
                  Uri.parse('https://kratos.mineshop.eu/link'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download Kratos Link',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Remote miners list (bridge online only)
          if (_relay.state == RelayState.bridgeOnline) ...[
            Row(children: [
              const Expanded(child: _SectionLabel('REMOTE MINERS')),
              TextButton.icon(
                onPressed: () {
                  _relay.requestBridgeRescan();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔍 Asking bridge to re-scan…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Rescan', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: KratosTheme.orange),
              ),
            ]),
            const SizedBox(height: 8),
            if (_relay.remoteMinersList.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KratosTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: KratosTheme.border),
                ),
                child: const Text(
                  'Bridge online but no miners reported yet. Tap Rescan.',
                  style: TextStyle(color: KratosTheme.muted, fontSize: 13),
                ),
              )
            else
              for (final m in _relay.remoteMinersList)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RemoteMinerRow(
                    minerInfo: m,
                    onAdd: () => _addToFleet(m),
                    // In-fleet for local OR remote — no more duplicate Add buttons
                    alreadyAdded: context
                        .watch<MinerStore>()
                        .miners
                        .any((fm) => fm.ip == (m['ip'] as String? ?? '')),
                  ),
                ),
          ],

          const SizedBox(height: 20),

          // How it works
          _HowItWorksSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final RelayState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final relay = RelayService.instance;

    Color stateColor;
    String stateLabel;
    switch (state) {
      case RelayState.bridgeOnline:
        stateColor = const Color(0xFF3FB950);
        stateLabel = 'Connected';
      case RelayState.bridgeOffline:
        stateColor = KratosTheme.orange;
        stateLabel = 'Relay connected';
      case RelayState.connected:
        stateColor = KratosTheme.orange;
        stateLabel = 'Connected';
      case RelayState.connecting:
        stateColor = KratosTheme.blue;
        stateLabel = 'Connecting...';
      case RelayState.disconnected:
        stateColor = KratosTheme.muted;
        stateLabel = 'Disconnected';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KratosTheme.border),
      ),
      child: Column(children: [
        _StatusRow(
          label: 'Relay',
          ok: state != RelayState.disconnected && state != RelayState.connecting,
          value: stateLabel,
          color: stateColor,
        ),
        const Divider(height: 16, color: KratosTheme.border),
        _StatusRow(
          label: 'Bridge (Kratos Link)',
          ok: relay.bridgeOnline,
          value: relay.bridgeOnline ? 'Online' : 'Offline',
          color: relay.bridgeOnline
              ? const Color(0xFF3FB950)
              : KratosTheme.muted,
        ),
        const Divider(height: 16, color: KratosTheme.border),
        _StatusRow(
          label: 'Remote miners',
          ok: relay.remoteMinersList.isNotEmpty,
          value: relay.state == RelayState.disconnected
              ? '--'
              : '${relay.remoteMinersList.length} found',
          color: relay.remoteMinersList.isNotEmpty
              ? const Color(0xFF3FB950)
              : KratosTheme.muted,
        ),
      ]),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String value;
  final Color color;
  const _StatusRow({
    required this.label,
    required this.ok,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: KratosTheme.muted)),
        const Spacer(),
        Text(ok ? '✅' : '⬜', style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
                fontFamily: 'Courier')),
      ]);
}

// ── Remote miner row ──────────────────────────────────────────────────────────

class _RemoteMinerRow extends StatelessWidget {
  final Map<String, dynamic> minerInfo;
  final VoidCallback onAdd;
  final bool alreadyAdded;
  const _RemoteMinerRow({
    required this.minerInfo,
    required this.onAdd,
    required this.alreadyAdded,
  });

  @override
  Widget build(BuildContext context) {
    final ip = minerInfo['ip'] as String? ?? '?';
    final port = (minerInfo['port'] as num?)?.toInt() ?? 80;
    final model = minerInfo['model'] as String? ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KratosTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KratosTheme.border),
      ),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF3FB950),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(model,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KratosTheme.textPrim)),
            Text('$ip : $port',
                style: const TextStyle(
                    fontSize: 11,
                    color: KratosTheme.muted,
                    fontFamily: 'Courier')),
          ]),
        ),
        if (alreadyAdded)
          const Text('In fleet',
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF3FB950),
                  fontWeight: FontWeight.w600))
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KratosTheme.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: onAdd,
            child: const Text('Add to fleet'),
          ),
      ]),
    );
  }
}

// ── Info banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KratosTheme.blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KratosTheme.blue.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lan_outlined,
                color: KratosTheme.blue, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Remote Access lets you monitor and control miners outside your '
                'home network via a secure relay. Run Kratos Link on the same '
                'network as your miners, then paste the key here.',
                style: TextStyle(
                    fontSize: 12,
                    color: KratosTheme.muted,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
}

// ── How it works ──────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
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
            const _SectionLabel('HOW IT WORKS'),
            const SizedBox(height: 12),
            _Step('1', 'Download Kratos Link (Python script) to your home PC / Pi'),
            _Step('2', 'Run: python3 kratos_link.py --key <your-key>'),
            _Step('3', 'Copy the key, paste above, tap Connect'),
            _Step('4', 'Your miners appear — add them to your fleet'),
          ],
        ),
      );
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step(this.num, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: KratosTheme.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(num,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: KratosTheme.orange)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      color: KratosTheme.muted,
                      height: 1.4)),
            ),
          ],
        ),
      );
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: KratosTheme.muted,
          letterSpacing: 1.5));
}
