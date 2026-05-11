import 'package:flutter/material.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/volt_theme.dart';
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
