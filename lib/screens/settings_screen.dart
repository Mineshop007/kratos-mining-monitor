import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/volt_theme.dart';
import '../services/theme_service.dart';
import '../services/miner_store.dart';

/// Settings tab — theme picker (only Circuit + Volt unlocked in 1.2.0),
/// kWh price input, support links. Real values only.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KratosColors.bg,
      appBar: AppBar(
        backgroundColor: KratosColors.bg,
        title: const Text('Settings',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KratosColors.text)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 18),
            child: Center(
                child: Text('v1.2.0',
                    style: TextStyle(
                        color: KratosColors.muted, fontSize: 13))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: const [
          _ThemeSection(),
          SizedBox(height: 18),
          _ElectricitySection(),
          SizedBox(height: 18),
          _SupportSection(),
          SizedBox(height: 18),
          _AboutSection(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: KratosColors.muted,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: KratosColors.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: KratosColors.volt.withOpacity(0.08)),
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
    final locked = !name.unlocked;
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          gradient: _gradient(name),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? KratosColors.voltBright
                : Colors.white.withOpacity(0.06),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: KratosColors.volt.withOpacity(0.4),
                      blurRadius: 14),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: locked
                    ? KratosColors.muted
                    : Colors.white.withOpacity(0.95),
                letterSpacing: 0.6,
              ),
            ),
            if (locked) ...[
              const SizedBox(height: 2),
              const Text(
                'soon',
                style: TextStyle(
                  fontSize: 9,
                  color: KratosColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  LinearGradient _gradient(KratosThemeName n) {
    switch (n) {
      case KratosThemeName.circuit:
        return const LinearGradient(
          colors: [Color(0xFF0A1816), Color(0xFF050A0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KratosThemeName.volt:
        return const LinearGradient(
          colors: [
            KratosColors.volt,
            Color(0xFF02211A),
            Color(0xFF000000),
          ],
          stops: [0.0, 0.6, 1.0],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case KratosThemeName.pulse:
        return const LinearGradient(
          colors: [Color(0xFF0A2B1F), KratosColors.volt, Color(0xFF053A28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KratosThemeName.stealth:
        return const LinearGradient(
          colors: [Colors.black, Colors.black],
        );
      case KratosThemeName.chrome:
        return const LinearGradient(
          colors: [Color(0xFF3A4A48), Color(0xFF1A2826)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
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
    final initial =
        context.read<MinerStore>().kwhPrice.toStringAsFixed(3);
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'Electricity',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            const Icon(Icons.bolt, size: 22, color: KratosColors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cost per kWh',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KratosColors.text)),
                  Text('used to compute cost & net earnings',
                      style: TextStyle(
                          fontSize: 11, color: KratosColors.muted)),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KratosColors.text,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: KratosColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: KratosColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: KratosColors.volt, width: 2),
                  ),
                ),
                onSubmitted: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed >= 0) {
                    context.read<MinerStore>().setKwhPrice(parsed);
                  } else {
                    _ctrl.text = context
                        .read<MinerStore>()
                        .kwhPrice
                        .toStringAsFixed(3);
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

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
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
          const Divider(height: 1, color: KratosColors.line),
          _LinkRow(
            icon: Icons.shopping_bag_rounded,
            label: 'Buy hardware on Mineshop',
            url: 'https://mineshop.eu/?utm_source=kratos_app',
            color: KratosColors.volt,
          ),
          const Divider(height: 1, color: KratosColors.line),
          _LinkRow(
            icon: Icons.menu_book_rounded,
            label: 'Mineshop blog — daily mining articles',
            url: 'https://mineshop.eu/blog?utm_source=kratos_app',
            color: KratosColors.cyan,
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
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
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
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KratosColors.text)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: KratosColors.muted),
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
    return _SectionShell(
      title: 'About',
      child: Column(
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, color: KratosColors.volt, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kratos · Volt — Mining monitor by Mineshop.\nReal data. No fakes. Forge your fleet.',
                    style: TextStyle(
                        fontSize: 13,
                        color: KratosColors.muted,
                        height: 1.4),
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
