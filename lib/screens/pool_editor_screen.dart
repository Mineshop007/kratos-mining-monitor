import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/volt_theme.dart';
import '../main.dart';
import '../models/coin.dart';
import '../models/miner.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import '../services/avalon_api.dart';
import '../services/miner_store.dart';
import '../services/pool_catalog_service.dart';
import '../services/relay_service.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class PoolEditorScreen extends StatefulWidget {
  final Miner miner;
  final List<PoolInfo> currentPools;
  const PoolEditorScreen(
      {super.key, required this.miner, required this.currentPools});

  @override
  State<PoolEditorScreen> createState() => _PoolEditorScreenState();
}

class _PoolEditorScreenState extends State<PoolEditorScreen> {
  // Pool 1
  final _host1 = TextEditingController();
  final _port1 = TextEditingController();
  final _user1 = TextEditingController();

  // Pool 2 (fallback)
  final _host2 = TextEditingController();
  final _port2 = TextEditingController();
  final _user2 = TextEditingController();

  // Pool 3 (CGMiner only)
  final _host3 = TextEditingController();
  final _port3 = TextEditingController();
  final _user3 = TextEditingController();

  bool _showFallback = false;
  bool _showPool3 = false;
  bool _saving = false;
  String? _result;
  String? _workerHint1;
  String? _workerHint2;
  String? _workerHint3;
  String _pass1 = 'x';
  String _pass2 = 'x';
  String _pass3 = 'x';
  late Coin _selectedCoin;

  bool get _isEsp => widget.miner.type.apiType == ApiType.espMinerHttp;
  bool get _isAvalon => widget.miner.type.apiType == ApiType.avalonHttp;

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.miner.coin.isSha256 ? widget.miner.coin : Coin.btc;
    _prefill();
  }

  @override
  void dispose() {
    for (final c in [
      _host1,
      _port1,
      _user1,
      _host2,
      _port2,
      _user2,
      _host3,
      _port3,
      _user3
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill() {
    final pools = widget.currentPools;
    if (pools.isNotEmpty) {
      final p = _parseUrl(pools[0].url);
      _host1.text = p.$1;
      _port1.text = p.$2.toString();
      _user1.text = pools[0].user;
    }
    if (pools.length > 1 && pools[1].url.isNotEmpty) {
      final p = _parseUrl(pools[1].url);
      _host2.text = p.$1;
      _port2.text = p.$2.toString();
      _user2.text = pools[1].user;
      _showFallback = true;
    }
    if (pools.length > 2 && pools[2].url.isNotEmpty && !_isEsp) {
      final p = _parseUrl(pools[2].url);
      _host3.text = p.$1;
      _port3.text = p.$2.toString();
      _user3.text = pools[2].user;
      _showPool3 = true;
    }
  }

  // ── URL parsing ─────────────────────────────────────────────────────────────

  /// Parse any stratum URL format → (host, port)
  /// Handles: "stratum+tcp://host:3333", "host:3333", "host", "ssl://host:3333"
  (String, int) _parseUrl(String raw) {
    var s = raw.trim();
    // Strip scheme
    s = s.replaceAll(RegExp(r'^stratum\+tcp://'), '');
    s = s.replaceAll(RegExp(r'^stratum\+ssl://'), '');
    s = s.replaceAll(RegExp(r'^tcp://'), '');
    s = s.replaceAll(RegExp(r'^ssl://'), '');
    final parts = s.split(':');
    final host = parts[0].trim();
    final port =
        parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 3333) : 3333;
    return (host, port);
  }

  /// Build full stratum URL from host + port (for CGMiner)
  String _buildUrl(String host, String portStr) {
    final port = int.tryParse(portStr.trim()) ?? 3333;
    return 'stratum+tcp://$host:$port';
  }

  // ── Preset tap ───────────────────────────────────────────────────────────────

  void _applyPreset(PoolCatalogEntry p, int poolIndex) {
    setState(() {
      _selectedCoin = p.coin;
      switch (poolIndex) {
        case 1:
          _host1.text = p.host;
          _port1.text = p.port.toString();
          if (_user1.text.isEmpty) _user1.text = '';
          _workerHint1 = p.workerHint;
          _pass1 = p.password;
        case 2:
          _host2.text = p.host;
          _port2.text = p.port.toString();
          if (_user2.text.isEmpty) _user2.text = '';
          _workerHint2 = p.workerHint;
          _pass2 = p.password;
          _showFallback = true;
        case 3:
          _host3.text = p.host;
          _port3.text = p.port.toString();
          if (_user3.text.isEmpty) _user3.text = '';
          _workerHint3 = p.workerHint;
          _pass3 = p.password;
          _showPool3 = true;
      }
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final host1 = _host1.text.trim();
    if (host1.isEmpty) return;

    final isRemoteOp = !widget.miner.isRemote &&
        (RelayService.instance.state == RelayState.bridgeOnline ||
            RelayService.instance.state == RelayState.connected);
    setState(() {
      _saving = true;
      _result = isRemoteOp
          ? '⏳ Sending via relay bridge... miner will reboot (~15-20s)'
          : '⏳ Sending pool config to miner...';
    });

    bool ok;
    if (_isEsp) {
      final port1 = int.tryParse(_port1.text.trim()) ?? 3333;
      final user1 = _user1.text.trim().isEmpty ? 'worker' : _user1.text.trim();
      final host2 = _showFallback ? _host2.text.trim() : null;
      final port2 =
          _showFallback ? (int.tryParse(_port2.text.trim()) ?? 3333) : null;
      final user2 = _showFallback
          ? (_user2.text.trim().isEmpty ? user1 : _user2.text.trim())
          : null;

      ok = await EspMinerAPI.instance.setPool(
        widget.miner.ip,
        widget.miner.port,
        stratumUrl: host1,
        stratumPort: port1,
        stratumUser: user1,
        stratumPass: _pass1,
        fallbackStratumUrl: host2,
        fallbackStratumPort: port2,
        fallbackStratumUser: user2,
        remoteUrl: widget.miner.remoteUrl,
        isRemote: widget.miner.isRemote,
      );
      // Relay fallback: miner added via LAN but user is now remote
      if (!ok &&
          !widget.miner.isRemote &&
          (RelayService.instance.state == RelayState.bridgeOnline ||
              RelayService.instance.state == RelayState.connected)) {
        ok = await EspMinerAPI.instance.setPool(
          widget.miner.ip,
          widget.miner.port,
          stratumUrl: host1,
          stratumPort: port1,
          stratumUser: user1,
          stratumPass: _pass1,
          fallbackStratumUrl: host2,
          fallbackStratumPort: port2,
          fallbackStratumUser: user2,
          isRemote: true,
        );
      }
    } else if (_isAvalon) {
      // Avalon Nano 3S / Nano 3 — HTTP PATCH with host+port (same format as ESP-Miner)
      final port1 = int.tryParse(_port1.text.trim()) ?? 3333;
      final user1 = _user1.text.trim().isEmpty ? 'worker' : _user1.text.trim();
      final host2 = _showFallback ? _host2.text.trim() : null;
      final port2 =
          _showFallback ? (int.tryParse(_port2.text.trim()) ?? 3333) : null;
      final user2 = _showFallback
          ? (_user2.text.trim().isEmpty ? user1 : _user2.text.trim())
          : null;

      ok = await AvalonAPI.instance.setPool(
        widget.miner.ip,
        widget.miner.port,
        host: host1,
        poolPort: port1,
        user: user1,
        fallbackHost: host2,
        fallbackPort: port2,
        fallbackUser: user2,
        remoteUrl: widget.miner.remoteUrl,
        isRemote: widget.miner.isRemote,
      );
      // Relay fallback
      if (!ok &&
          !widget.miner.isRemote &&
          (RelayService.instance.state == RelayState.bridgeOnline ||
              RelayService.instance.state == RelayState.connected)) {
        ok = await AvalonAPI.instance.setPool(
          widget.miner.ip,
          widget.miner.port,
          host: host1,
          poolPort: port1,
          user: user1,
          fallbackHost: host2,
          fallbackPort: port2,
          fallbackUser: user2,
          isRemote: true,
        );
      }
    } else {
      final isAvalonDevice = widget.miner.type == MinerType.avalonQ ||
          widget.miner.type == MinerType.avalonMini3;

      if (isAvalonDevice) {
        // ── Avalon Q / Mini 3: use ascset|0,setpool native command + reboot ──
        // addpool/removepool are NOT supported; only setpool via ascset works.
        // Pool changes take effect after reboot — we send the reboot automatically.
        setState(() =>
            _result = '⏳ Saving pool — miner will reboot to apply (~30s)...');

        final user1 =
            _user1.text.trim().isEmpty ? 'worker' : _user1.text.trim();
        final primaryUrl = _buildUrl(host1, _port1.text);
        final fallbackUrl = _showFallback && _host2.text.trim().isNotEmpty
            ? _buildUrl(_host2.text.trim(), _port2.text)
            : null;
        final fallbackUser = _showFallback ? _user2.text.trim() : null;

        ok = await CGMinerAPI.instance.setPoolAscset(
          widget.miner.ip,
          widget.miner.port,
          primaryUrl: primaryUrl,
          primaryUser: user1,
          fallbackUrl: fallbackUrl,
          fallbackUser: fallbackUser,
          rebootAfterSave: true,
          remoteUrl: widget.miner.remoteUrl,
          isRemote: widget.miner.isRemote,
        );
        // Relay fallback
        if (!ok &&
            !widget.miner.isRemote &&
            (RelayService.instance.state == RelayState.bridgeOnline ||
                RelayService.instance.state == RelayState.connected)) {
          ok = await CGMinerAPI.instance.setPoolAscset(
            widget.miner.ip,
            widget.miner.port,
            primaryUrl: primaryUrl,
            primaryUser: user1,
            fallbackUrl: fallbackUrl,
            fallbackUser: fallbackUser,
            rebootAfterSave: true,
            isRemote: true,
          );
        }
      } else {
        // ── Other CGMiner devices (Antminer, etc.) — standard addpool flow ──
        final pools = <Map<String, String>>[];
        void addPool(String host, String portStr, String user, String pass) {
          if (host.isEmpty) return;
          pools.add({
            'url': _buildUrl(host, portStr),
            'user': user.isEmpty ? 'worker' : user,
            'pass': pass.isEmpty ? 'x' : pass,
          });
        }

        addPool(host1, _port1.text, _user1.text.trim(), _pass1);
        if (_showFallback)
          addPool(_host2.text.trim(), _port2.text, _user2.text.trim(), _pass2);
        if (_showPool3)
          addPool(_host3.text.trim(), _port3.text, _user3.text.trim(), _pass3);

        ok = await CGMinerAPI.instance.setPools(
          widget.miner.ip,
          widget.miner.port,
          pools,
          remoteUrl: widget.miner.remoteUrl,
          isRemote: widget.miner.isRemote,
        );
        if (!ok &&
            !widget.miner.isRemote &&
            (RelayService.instance.state == RelayState.bridgeOnline ||
                RelayService.instance.state == RelayState.connected)) {
          ok = await CGMinerAPI.instance.setPools(
            widget.miner.ip,
            widget.miner.port,
            pools,
            isRemote: true,
          );
        }
      }
    }

    final isAvalonReboot = !_isEsp &&
        !_isAvalon &&
        (widget.miner.type == MinerType.avalonQ ||
            widget.miner.type == MinerType.avalonMini3);
    setState(() {
      _saving = false;
      _result = ok
          ? (isAvalonReboot
              ? '✅ Pool saved! Miner is rebooting — will start mining in ~30s.'
              : '✅ Pool saved! Miner is connecting to new pool now.')
          : '❌ Failed. Make sure you are on the same WiFi as the miner, then try again.';
    });

    if (ok) {
      widget.miner.coin = _selectedCoin == Coin.sha256Auto
          ? PoolCatalogService.inferCoinFromHost(host1)
          : _selectedCoin;
      // ignore: use_build_context_synchronously
      await Provider.of<MinerStore>(context, listen: false).save();
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final presets = PoolCatalogService.forCoin(_selectedCoin);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configure Pools',
                style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
            Text(widget.miner.name,
                style: TextStyle(color: kc.muted, fontSize: 12)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── How pools work banner ──────────────────────────────────────────
          _InfoBanner(
            icon: Icons.info_outline,
            color: kc.secondary,
            text: (_isEsp || _isAvalon)
                ? 'Pool 1 is your PRIMARY pool. Pool 2 is the FALLBACK — your miner switches to it automatically if Pool 1 is unreachable.'
                : 'Pool 1 is PRIMARY. Pools 2 & 3 are FAILOVERS. Your miner tries them in order.',
          ),
          const SizedBox(height: 16),

          // ── Coin rail ─────────────────────────────────────────────────────
          _SectionLabel('COIN / SHA-256 MODE'),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: PoolCatalogService.sha256Coins.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final coin = PoolCatalogService.sha256Coins[i];
                final selected = coin == _selectedCoin;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCoin = coin),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color:
                          selected ? coin.color.withOpacity(0.18) : kc.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? coin.color.withOpacity(0.7) : kc.line,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: coin.color,
                          shape: BoxShape.circle,
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                      color: coin.color.withOpacity(0.6),
                                      blurRadius: 10)
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        coin.ticker,
                        style: TextStyle(
                          color: selected ? coin.color : kc.muted,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick Presets ──────────────────────────────────────────────────
          _SectionLabel('⚡ ${_selectedCoin.ticker} PRESETS — TAP TO FILL'),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final p = presets[i];
                final isMineshop = p.host.contains('mineshop');
                return GestureDetector(
                  onTap: () => _showPresetSheet(p),
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          isMineshop ? kc.accent.withOpacity(0.08) : kc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMineshop
                            ? kc.accent.withOpacity(0.5)
                            : p.coin.color.withOpacity(0.35),
                        width: isMineshop ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (isMineshop)
                            Icon(Icons.star, size: 11, color: kc.accent),
                          if (p.isSolo && !isMineshop)
                            Icon(Icons.emoji_events,
                                size: 11, color: const Color(0xFFffd700)),
                          SizedBox(width: isMineshop || p.isSolo ? 4 : 0),
                          Expanded(
                            child: Text(p.name,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        isMineshop ? kc.accent : p.coin.color),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        Text(p.host,
                            style: TextStyle(
                                fontSize: 10,
                                color: kc.muted,
                                fontFamily: 'Courier'),
                            overflow: TextOverflow.ellipsis),
                        Text('Port: ${p.port}',
                            style: TextStyle(
                                fontSize: 10,
                                color: kc.muted,
                                fontFamily: 'Courier')),
                        const Spacer(),
                        Text(
                            p.isSolo
                                ? '🎯 ${p.coin.ticker} SOLO'
                                : '🏊 ${p.coin.ticker} POOL',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: p.isSolo
                                    ? const Color(0xFFffd700)
                                    : kc.secondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Pool 1 ─────────────────────────────────────────────────────────
          _SectionLabel('PRIMARY POOL'),
          const SizedBox(height: 8),
          _PoolCard(
            index: 1,
            isPrimary: true,
            hostCtrl: _host1,
            portCtrl: _port1,
            userCtrl: _user1,
            workerHint: _workerHint1,
          ),
          const SizedBox(height: 16),

          // ── Fallback toggle ────────────────────────────────────────────────
          _FallbackToggle(
            label: 'Add Fallback Pool',
            subtitle: 'Miner switches here if Pool 1 goes down',
            value: _showFallback,
            onChanged: (v) => setState(() => _showFallback = v),
            color: kc.secondary,
          ),

          if (_showFallback) ...[
            const SizedBox(height: 12),
            _SectionLabel('FALLBACK POOL'),
            const SizedBox(height: 8),
            _PoolCard(
              index: 2,
              isPrimary: false,
              hostCtrl: _host2,
              portCtrl: _port2,
              userCtrl: _user2,
              workerHint: _workerHint2,
            ),
          ],

          // Pool 3 (CGMiner only)
          if (!_isEsp && !_isAvalon) ...[
            const SizedBox(height: 12),
            _FallbackToggle(
              label: 'Add Second Fallback',
              subtitle: 'Last resort if Pool 1 & 2 both fail',
              value: _showPool3,
              onChanged: (v) => setState(() => _showPool3 = v),
              color: KratosTheme.purple,
            ),
            if (_showPool3) ...[
              const SizedBox(height: 12),
              _SectionLabel('SECOND FALLBACK'),
              const SizedBox(height: 8),
              _PoolCard(
                index: 3,
                isPrimary: false,
                hostCtrl: _host3,
                portCtrl: _port3,
                userCtrl: _user3,
                workerHint: _workerHint3,
              ),
            ],
          ],

          const SizedBox(height: 20),

          // ── Result ─────────────────────────────────────────────────────────
          if (_result != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _result!.startsWith('✅')
                      ? kc.accent.withOpacity(0.4)
                      : KratosTheme.red.withOpacity(0.4),
                ),
              ),
              child: Text(_result!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        _result!.startsWith('✅') ? kc.accent : KratosTheme.red,
                  )),
            ),
            const SizedBox(height: 12),
          ],

          // ── Save button ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _host1.text.trim().isEmpty ? kc.line : KratosTheme.orange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _host1.text.trim().isEmpty || _saving ? null : _save,
              child: _saving
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.black54)),
                          SizedBox(width: 10),
                          Text('Sending & verifying...',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ])
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.check_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text('Save Pool Configuration',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ]),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              widget.miner.isRemote
                  ? '📡 Saving via remote relay'
                  : (RelayService.instance.state == RelayState.bridgeOnline ||
                          RelayService.instance.state == RelayState.connected)
                      ? '📡 Relay connected — will try local then relay'
                      : '📶 Saving over local network',
              style: TextStyle(fontSize: 11, color: kc.muted),
            ),
          ),
        ],
      ),
    );
  }

  // ── Preset bottom sheet ───────────────────────────────────────────────────

  void _showPresetSheet(PoolCatalogEntry p) {
    final kc = KratosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: kc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: p.coin.color)),
              const SizedBox(height: 4),
              Text(p.description,
                  style: TextStyle(fontSize: 13, color: kc.muted)),
              const SizedBox(height: 12),
              // Pool details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kc.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kc.line),
                ),
                child: Column(children: [
                  _DetailRow('Host', p.host, kc),
                  const SizedBox(height: 6),
                  _DetailRow('Port', p.port.toString(), kc),
                  const SizedBox(height: 6),
                  _DetailRow(
                      'Full URL', 'stratum+tcp://${p.host}:${p.port}', kc),
                  const SizedBox(height: 6),
                  _DetailRow('Coin', p.coin.displayName, kc),
                  const SizedBox(height: 6),
                  _DetailRow('Worker', p.workerHint, kc),
                  if (p.password != 'x') ...[
                    const SizedBox(height: 6),
                    _DetailRow('Password', p.password, kc),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              Text('Apply to which pool?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kc.muted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _ApplyButton(
                    label: 'Pool 1\n(Primary)',
                    color: KratosTheme.orange,
                    onTap: () {
                      Navigator.pop(context);
                      _applyPreset(p, 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ApplyButton(
                    label: 'Pool 2\n(Fallback)',
                    color: kc.secondary,
                    onTap: () {
                      Navigator.pop(context);
                      _applyPreset(p, 2);
                    },
                  ),
                ),
                if (!_isEsp && !_isAvalon) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ApplyButton(
                      label: 'Pool 3\n(Failover 2)',
                      color: KratosTheme.purple,
                      onTap: () {
                        Navigator.pop(context);
                        _applyPreset(p, 3);
                      },
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _DetailRow(String label, String value, KratosPalette kc) => Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12, color: kc.muted, fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12, color: kc.text, fontFamily: 'Courier'),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _PoolCard extends StatefulWidget {
  final int index;
  final bool isPrimary;
  final TextEditingController hostCtrl, portCtrl, userCtrl;
  final String? workerHint;

  const _PoolCard({
    required this.index,
    required this.isPrimary,
    required this.hostCtrl,
    required this.portCtrl,
    required this.userCtrl,
    this.workerHint,
  });

  @override
  State<_PoolCard> createState() => _PoolCardState();
}

class _PoolCardState extends State<_PoolCard> {
  @override
  void initState() {
    super.initState();
    widget.hostCtrl.addListener(() => setState(() {}));
  }

  void _pasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) return;
    // Smart parse — handle any format user might paste
    var s = raw
        .replaceAll(RegExp(r'^stratum\+tcp://'), '')
        .replaceAll(RegExp(r'^stratum\+ssl://'), '')
        .replaceAll(RegExp(r'^tcp://'), '');
    final parts = s.split(':');
    final host = parts[0].trim();
    final port = parts.length > 1
        ? (int.tryParse(parts[1].trim()) ?? 3333).toString()
        : widget.portCtrl.text.isEmpty
            ? '3333'
            : widget.portCtrl.text;
    setState(() {
      widget.hostCtrl.text = host;
      widget.portCtrl.text = port;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final accentColor = widget.isPrimary ? KratosTheme.orange : kc.secondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.hostCtrl.text.isNotEmpty
                ? accentColor.withOpacity(0.4)
                : kc.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // HOST field
        _FieldLabel('POOL ADDRESS (HOST)', kc),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: _StyledField(
              controller: widget.hostCtrl,
              hint: 'e.g. solo.mineshop.eu',
              keyboardType: TextInputType.url,
              accentColor: accentColor,
            ),
          ),
          const SizedBox(width: 8),
          // Paste button
          GestureDetector(
            onTap: _pasteUrl,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.content_paste, size: 14, color: accentColor),
                  const SizedBox(width: 4),
                  Text('PASTE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentColor)),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            '💡 You can also paste a full stratum URL — it will be parsed automatically',
            style: TextStyle(fontSize: 10, color: kc.muted)),

        const SizedBox(height: 12),

        // PORT field
        _FieldLabel('PORT', kc),
        const SizedBox(height: 4),
        SizedBox(
          width: 120,
          child: _StyledField(
            controller: widget.portCtrl,
            hint: '3333',
            keyboardType: TextInputType.number,
            accentColor: accentColor,
          ),
        ),
        const SizedBox(height: 4),
        Text('Common ports: 3333, 21496, 3334',
            style: TextStyle(fontSize: 10, color: kc.muted)),

        const SizedBox(height: 12),

        // WORKER field
        _FieldLabel('WORKER / USERNAME', kc),
        const SizedBox(height: 4),
        _StyledField(
          controller: widget.userCtrl,
          hint: widget.workerHint ?? 'username.workername or BTC address',
          accentColor: accentColor,
        ),

        // Preview
        if (widget.hostCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withOpacity(0.15)),
            ),
            child: Row(children: [
              Icon(Icons.check_circle, size: 12, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'stratum+tcp://${widget.hostCtrl.text}:${widget.portCtrl.text.isEmpty ? "3333" : widget.portCtrl.text}',
                  style: TextStyle(
                      fontSize: 11,
                      color: accentColor,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _FallbackToggle extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  const _FallbackToggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? color.withOpacity(0.06) : kc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value ? color.withOpacity(0.4) : kc.line),
        ),
        child: Row(children: [
          Icon(value ? Icons.shield : Icons.shield_outlined,
              size: 20, color: value ? color : kc.muted),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: value ? color : kc.text,
                      fontSize: 14)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: kc.muted)),
            ]),
          ),
          Switch(
            value: value,
            activeColor: color,
            onChanged: onChanged,
          ),
        ]),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final Color accentColor;

  const _StyledField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return TextField(
      controller: controller,
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
            borderSide: BorderSide(color: accentColor, width: 1.5)),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  final KratosPalette kc;
  const _FieldLabel(this.text, this.kc);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: kc.muted,
          letterSpacing: 1.5));
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: kc.muted, height: 1.4))),
      ]),
    );
  }
}

class _ApplyButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ApplyButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.4)),
          ),
        ),
      );
}
