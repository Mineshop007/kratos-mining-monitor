import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';
import '../main.dart';
import '../services/dashboard_prefs.dart';

class DashboardSettingsScreen extends StatefulWidget {
  const DashboardSettingsScreen({super.key});

  @override
  State<DashboardSettingsScreen> createState() => _DashboardSettingsState();
}

class _DashboardSettingsState extends State<DashboardSettingsScreen> {
  KratosPalette get kc => KratosColors.of(context);

  final _prefs = DashboardPrefs.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: AppBar(
        backgroundColor: kc.bg,
        title: Text('Customize Dashboard',
            style: TextStyle(color: kc.text, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('MINER CARDS'),
          SizedBox(height: 8),
          _tile(
            icon: Icons.speed,
            color: KratosTheme.blue,
            title: 'Hashrate',
            subtitle: 'Avg hashrate on every card',
            value: _prefs.showHashrate,
            key: 'hashrate',
          ),
          _tile(
            icon: Icons.thermostat,
            color: KratosTheme.orange,
            title: 'Temperature',
            subtitle: 'Outlet temp',
            value: _prefs.showTemp,
            key: 'temp',
          ),
          _tile(
            icon: Icons.bolt,
            color: KratosTheme.orange,
            title: 'Power Draw',
            subtitle: 'Watts consumed',
            value: _prefs.showPowerDraw,
            key: 'power',
          ),
          _tile(
            icon: Icons.flash_on,
            color: KratosTheme.blue,
            title: 'Efficiency',
            subtitle: 'J/TH ratio',
            value: _prefs.showEfficiency,
            key: 'efficiency',
          ),
          _tile(
            icon: Icons.air,
            color: KratosTheme.blue,
            title: 'Fan Speed',
            subtitle: 'RPM or %',
            value: _prefs.showFanSpeed,
            key: 'fan',
          ),
          _tile(
            icon: Icons.emoji_events,
            color: KratosTheme.orange,
            title: 'Best Difficulty',
            subtitle: 'All-time best share per miner',
            value: _prefs.showBestDiff,
            key: 'bestdiff',
          ),
          _tile(
            icon: Icons.memory,
            color: kc.accent,
            title: 'Frequency',
            subtitle: 'Current ASIC clock speed',
            value: _prefs.showFrequency,
            key: 'freq',
          ),
          _tile(
            icon: Icons.access_time,
            color: KratosTheme.purple,
            title: 'Uptime',
            subtitle: 'Time since last restart',
            value: _prefs.showUptime,
            key: 'uptime',
          ),
          SizedBox(height: 20),
          _sectionHeader('LAYOUT'),
          SizedBox(height: 8),
          _tile(
            icon: Icons.view_agenda_outlined,
            color: kc.accent,
            title: 'Wide Miner Cards',
            subtitle: 'Full-width single-column layout',
            value: _prefs.wideCards,
            key: 'wide',
          ),
          _tile(
            icon: Icons.bar_chart,
            color: KratosTheme.blue,
            title: 'Fleet Totals Bar',
            subtitle: 'Show total hashrate & power at top',
            value: _prefs.showFleetTotals,
            key: 'fleet',
          ),
          SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kc.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kc.line),
            ),
            child: Text(
              '💡 Changes apply immediately. At least one stat must remain visible per card.',
              style: TextStyle(fontSize: 12, color: kc.muted, height: 1.5),
            ),
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Text(label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          color: kc.muted, letterSpacing: 1.5));

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required String key,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? color.withOpacity(0.3) : kc.line),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: kc.text)),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: kc.muted)),
        ])),
        Switch(
          value: value,
          activeColor: color,
          onChanged: (v) => _prefs.toggle(key, v),
        ),
      ]),
    );
  }
}
