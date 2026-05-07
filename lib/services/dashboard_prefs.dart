import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted dashboard display preferences.
/// Controls what's visible on miner cards and fleet layout.
class DashboardPrefs extends ChangeNotifier {
  static final DashboardPrefs instance = DashboardPrefs._();
  DashboardPrefs._() { _load(); }

  // ── Miner card toggles ────────────────────────────────────────────────────
  bool showEfficiency  = true;
  bool showPowerDraw   = true;
  bool showFanSpeed    = true;
  bool showBestDiff    = true;
  bool showFrequency   = true;
  bool showUptime      = false;
  bool showTemp        = true;
  bool showHashrate    = true;

  // ── Layout ────────────────────────────────────────────────────────────────
  bool wideCards       = false;   // single-column full-width cards
  bool showFleetTotals = true;    // scrolling totals bar

  // ── Loaded flag ───────────────────────────────────────────────────────────
  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    showEfficiency  = p.getBool('dp_efficiency')  ?? true;
    showPowerDraw   = p.getBool('dp_power')        ?? true;
    showFanSpeed    = p.getBool('dp_fan')          ?? true;
    showBestDiff    = p.getBool('dp_bestdiff')     ?? true;
    showFrequency   = p.getBool('dp_freq')         ?? true;
    showUptime      = p.getBool('dp_uptime')       ?? false;
    showTemp        = p.getBool('dp_temp')         ?? true;
    showHashrate    = p.getBool('dp_hashrate')     ?? true;
    wideCards       = p.getBool('dp_wide')         ?? false;
    showFleetTotals = p.getBool('dp_fleet_totals') ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('dp_efficiency',  showEfficiency);
    await p.setBool('dp_power',       showPowerDraw);
    await p.setBool('dp_fan',         showFanSpeed);
    await p.setBool('dp_bestdiff',    showBestDiff);
    await p.setBool('dp_freq',        showFrequency);
    await p.setBool('dp_uptime',      showUptime);
    await p.setBool('dp_temp',        showTemp);
    await p.setBool('dp_hashrate',    showHashrate);
    await p.setBool('dp_wide',        wideCards);
    await p.setBool('dp_fleet_totals', showFleetTotals);
  }

  void toggle(String key, bool value) {
    switch (key) {
      case 'efficiency':  showEfficiency  = value;
      case 'power':       showPowerDraw   = value;
      case 'fan':         showFanSpeed    = value;
      case 'bestdiff':    showBestDiff    = value;
      case 'freq':        showFrequency   = value;
      case 'uptime':      showUptime      = value;
      case 'temp':        showTemp        = value;
      case 'hashrate':    showHashrate    = value;
      case 'wide':        wideCards       = value;
      case 'fleet':       showFleetTotals = value;
    }
    notifyListeners();
    _save();
  }
}
