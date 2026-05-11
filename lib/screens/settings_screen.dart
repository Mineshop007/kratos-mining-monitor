import 'package:flutter/material.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/volt_theme.dart';
import '../models/bitcoin_node.dart';
import '../services/bitcoin_node_service.dart';
import '../services/theme_service.dart';
import '../services/miner_store.dart';
import '../services/haptic_service.dart';
import '../services/energy_report.dart';
import 'faq_screen.dart';
import 'circuit_monitor_screen.dart';
import 'dashboard_settings_screen.dart';
import 'fleet_oc_screen.dart';
import 'remote_access_screen.dart';
import 'pool_presets_screen.dart';

/// Settings tab — theme picker, kWh price input, support links. Real values only.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  KratosPalette get kc => KratosColors.of(context);
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/images/klaw-mascot.png',
              fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
        title: Text('Settings',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: kc.text)),
        actions: [
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(
                  child: Text(_version,
                      style: TextStyle(color: kc.muted, fontSize: 13))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: const [
          _ThemeSection(),
          SizedBox(height: 18),
          _FleetSection(),
          SizedBox(height: 18),
          _HapticsSection(),
          SizedBox(height: 18),
          _ElectricitySection(),
          SizedBox(height: 18),
          _BitcoinNodeSection(),
          SizedBox(height: 18),
          _ToolsSection(),
          SizedBox(height: 18),
          _PoolPresetsSection(),
          SizedBox(height: 18),
          _SupportSection(),
          SizedBox(height: 18),
          _AboutSection(),
        ],
      ),
    );
  }
}

class _FleetSection extends StatelessWidget {
  const _FleetSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Fleet',
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.bolt_rounded, color: kc.accent),
            title: Text('Fleet OC',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: kc.text)),
            trailing: Icon(Icons.chevron_right_rounded, color: kc.muted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FleetOCScreen()),
            ),
          ),
          Divider(height: 1, color: kc.line),
          ListTile(
            leading: Icon(Icons.tune_rounded, color: kc.secondary),
            title: Text('Customize Dashboard',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: kc.text)),
            trailing: Icon(Icons.chevron_right_rounded, color: kc.muted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DashboardSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kc.muted,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: kc.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kc.accent.withOpacity(0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Theme',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Consumer<ThemeService>(
          builder: (ctx, theme, _) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.62,
            children: [
              for (final t in KratosThemeName.values)
                _ThemeTile(
                  name: t,
                  active: t == theme.current,
                  onTap: () => theme.set(t),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final KratosThemeName name;
  final bool active;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.name,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final locked = !name.unlocked;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          gradient: _gradient(name),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                active ? _accentForTheme(name) : Colors.white.withOpacity(0.06),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: _accentForTheme(name).withOpacity(0.5),
                      blurRadius: 16),
                ]
              : null,
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              name.displayName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _gradient(KratosThemeName n) {
    switch (n) {
      case KratosThemeName.circuit:
        return const LinearGradient(
          colors: [Color(0xFF0D2018), Color(0xFF050A0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KratosThemeName.volt:
        return const LinearGradient(
          colors: [Color(0xFF00E676), Color(0xFF02211A), Color(0xFF000000)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case KratosThemeName.pulse:
        return const LinearGradient(
          colors: [Color(0xFF3D0060), Color(0xFFE040FB), Color(0xFF090010)],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case KratosThemeName.stealth:
        return const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KratosThemeName.chrome:
        return const LinearGradient(
          colors: [Color(0xFF4A6A80), Color(0xFF1A2A38), Color(0xFF080C10)],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _accentForTheme(KratosThemeName n) => switch (n) {
        KratosThemeName.circuit => const Color(0xFF39FFA0),
        KratosThemeName.volt => const Color(0xFF5DFFB0),
        KratosThemeName.pulse => const Color(0xFFF8A0FF),
        KratosThemeName.stealth => const Color(0xFFFFFFFF),
        KratosThemeName.chrome => const Color(0xFF9ADAF8),
      };
}

class _HapticsSection extends StatefulWidget {
  const _HapticsSection();

  @override
  State<_HapticsSection> createState() => _HapticsSectionState();
}

class _HapticsSectionState extends State<_HapticsSection> {
  KratosPalette get kc => KratosColors.of(context);

  HapticIntensity _intensity = HapticService.instance.intensity;

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Haptics',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vibration_rounded, size: 22, color: kc.secondary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vibrate on share submit',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kc.text)),
                      Text('one quick pulse per accepted share',
                          style: TextStyle(fontSize: 11, color: kc.muted)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in HapticIntensity.values)
                  ChoiceChip(
                    label: Text(v.displayName),
                    selected: _intensity == v,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() => _intensity = v);
                      HapticService.instance.setIntensity(v);
                      HapticService.instance.onShareAccepted();
                    },
                    selectedColor: kc.accent.withOpacity(0.20),
                    backgroundColor: kc.surface2,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _intensity == v ? kc.accentBright : kc.muted,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                      side: BorderSide(
                        color: _intensity == v ? kc.accent : kc.line,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ElectricitySection extends StatefulWidget {
  const _ElectricitySection();

  @override
  State<_ElectricitySection> createState() => _ElectricitySectionState();
}

class _ElectricitySectionState extends State<_ElectricitySection> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final initial = context.read<MinerStore>().kwhPrice.toStringAsFixed(3);
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Electricity',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 22, color: KratosColors.warning),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cost per kWh',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kc.text)),
                  Text('used to compute cost & net earnings',
                      style: TextStyle(fontSize: 11, color: kc.muted)),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kc.text,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kc.accent, width: 2),
                  ),
                ),
                onSubmitted: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed >= 0) {
                    context.read<MinerStore>().setKwhPrice(parsed);
                  } else {
                    _ctrl.text =
                        context.read<MinerStore>().kwhPrice.toStringAsFixed(3);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BitcoinNodeSection extends StatelessWidget {
  const _BitcoinNodeSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Bitcoin Node',
      child: Consumer<BitcoinNodeService>(
        builder: (context, service, _) {
          final config = service.config;
          final status = service.stats.status;
          if (config == null) {
            return _ActionRow(
              icon: Icons.dns_rounded,
              color: KratosTheme.orange,
              label: 'Add Bitcoin Node',
              sub: 'Connect Bitcoin Core RPC for sync, peers, and fees',
              onTap: () => _showBitcoinNodeDialog(context),
            );
          }
          return ListTile(
            leading: _StatusDot(status: status),
            title: Text(
              '${config.host}:${config.port}',
              style: TextStyle(
                color: kc.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              _statusLabel(status),
              style: TextStyle(color: kc.muted, fontSize: 11),
            ),
            trailing: Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: Icon(Icons.edit_rounded, color: kc.accent, size: 20),
                  onPressed: () =>
                      _showBitcoinNodeDialog(context, initial: config),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: KratosColors.danger,
                    size: 20,
                  ),
                  onPressed: service.clearConfig,
                ),
              ],
            ),
            onTap: () => _showBitcoinNodeDialog(context, initial: config),
          );
        },
      ),
    );
  }

  static String _statusLabel(NodeStatus status) => switch (status) {
        NodeStatus.online => 'Online',
        NodeStatus.syncing => 'Syncing',
        NodeStatus.offline => 'Offline',
        NodeStatus.unknown => 'Unknown',
      };
}

class _StatusDot extends StatelessWidget {
  final NodeStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final color = switch (status) {
      NodeStatus.online => kc.accent,
      NodeStatus.syncing => KratosColors.warning,
      NodeStatus.offline => KratosColors.danger,
      NodeStatus.unknown => kc.muted,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

Future<void> _showBitcoinNodeDialog(
  BuildContext context, {
  BitcoinNodeConfig? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KratosColors.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _BitcoinNodeConfigSheet(initial: initial),
  );
}

class _BitcoinNodeConfigSheet extends StatefulWidget {
  final BitcoinNodeConfig? initial;
  const _BitcoinNodeConfigSheet({this.initial});

  @override
  State<_BitcoinNodeConfigSheet> createState() =>
      _BitcoinNodeConfigSheetState();
}

class _BitcoinNodeConfigSheetState extends State<_BitcoinNodeConfigSheet> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _hostCtrl = TextEditingController(text: initial?.host ?? '192.168.1.1');
    _portCtrl = TextEditingController(text: '${initial?.port ?? 8332}');
    _userCtrl = TextEditingController(text: initial?.rpcUser ?? '');
    _passCtrl = TextEditingController(text: initial?.rpcPass ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, color: KratosTheme.orange),
              const SizedBox(width: 10),
              Text(
                widget.initial == null
                    ? 'Add Bitcoin Node'
                    : 'Edit Bitcoin Node',
                style: TextStyle(
                  color: kc.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _NodeField(
            controller: _hostCtrl,
            label: 'Host',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 10),
          _NodeField(
            controller: _portCtrl,
            label: 'Port',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          _NodeField(controller: _userCtrl, label: 'RPC Username'),
          const SizedBox(height: 10),
          _NodeField(
            controller: _passCtrl,
            label: 'RPC Password',
            obscureText: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: kc.muted,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kc.accent,
                foregroundColor: kc.bg,
              ),
              icon: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kc.bg,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving...' : 'Save'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8332;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Host, username, and password are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<BitcoinNodeService>().configure(
          BitcoinNodeConfig(
            host: host,
            port: port,
            rpcUser: user,
            rpcPass: pass,
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}

class _NodeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;

  const _NodeField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(color: kc.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: kc.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: kc.surface2.withValues(alpha: 0.72),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kc.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kc.accent, width: 2),
        ),
      ),
    );
  }
}

class _ToolsSection extends StatelessWidget {
  const _ToolsSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Tools',
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.bolt_rounded,
            color: KratosColors.warning,
            label: 'Circuit Monitor',
            sub: 'Group miners by breaker, alarm before trip',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CircuitMonitorScreen()),
            ),
          ),
          Divider(height: 1, color: kc.line),
          _ExportRow(),
          Divider(height: 1, color: kc.line),
          Divider(height: 1, color: kc.line),
          _ActionRow(
            icon: Icons.lan_outlined,
            color: KratosColors.info,
            label: 'Remote Access',
            sub: 'Monitor miners outside your home network',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RemoteAccessScreen()),
            ),
          ),
          Divider(height: 1, color: kc.line),
          _ActionRow(
            icon: Icons.menu_book_rounded,
            color: kc.secondary,
            label: 'FAQ',
            sub: 'Real answers to first-week questions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FaqScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kc.text)),
                  SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 11, color: kc.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: kc.muted),
          ],
        ),
      ),
    );
  }
}

class _ExportRow extends StatefulWidget {
  @override
  State<_ExportRow> createState() => _ExportRowState();
}

class _ExportRowState extends State<_ExportRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _ActionRow(
      icon: Icons.ios_share_rounded,
      color: kc.accent,
      label: 'Export energy report (CSV)',
      sub: _busy
          ? 'Building report…'
          : 'Live snapshot of every miner + kWh + cost',
      onTap: _busy ? () {} : _doExport,
    );
  }

  Future<void> _doExport() async {
    setState(() => _busy = true);
    try {
      final store = context.read<MinerStore>();
      if (store.miners.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No miners in fleet — add one first.')));
        return;
      }
      await EnergyReportService().exportAndShare(store);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PoolPresetsSection extends StatelessWidget {
  const _PoolPresetsSection();
  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Mining',
      child: _ActionRow(
        icon: Icons.dns_rounded,
        label: 'Pool Presets',
        sub: 'Save pool configs, apply to any miner in one tap',
        color: KratosTheme.orange,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PoolPresetsScreen())),
      ),
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'Support',
      child: Column(
        children: [
          _LinkRow(
            icon: Icons.forum_rounded,
            label: 'Discord — bug reports & ideas',
            url: 'https://discord.gg/yWtYegkDJw',
            color: const Color(0xFF5865F2),
          ),
          Divider(height: 1, color: kc.line),
          _LinkRow(
            icon: Icons.shopping_bag_rounded,
            label: 'Buy hardware on Mineshop',
            url: 'https://mineshop.eu/?utm_source=kratos_app',
            color: kc.accent,
          ),
          Divider(height: 1, color: kc.line),
          _LinkRow(
            icon: Icons.workspace_premium_rounded,
            label: 'Mining Chest — earn points on solo pool',
            url: 'https://solo.mineshop.eu?utm_source=kratos_app',
            color: const Color(0xFFFFB300),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final Color color;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kc.text)),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: kc.muted),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return _SectionShell(
      title: 'About',
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, color: kc.accent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kratos · Volt — Mining monitor by Mineshop.\nReal data. No fakes. Forge your fleet.',
                    style:
                        TextStyle(fontSize: 13, color: kc.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
