import 'package:shared_preferences/shared_preferences.dart';
import '../utils/block_calc.dart';

/// Stores solo/pool display mode per miner (keyed by IP).
/// Defaults: auto-detect from pool URL — solo pool → solo mode, else pool mode.
class MinerModePrefs {
  static final MinerModePrefs instance = MinerModePrefs._();
  MinerModePrefs._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String _key(String minerIp) => 'miner_mode_$minerIp';

  /// null = auto (infer from pool URL)
  bool? getOverride(String minerIp) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final val = prefs.getString(_key(minerIp));
    if (val == 'solo') return true;
    if (val == 'pool') return false;
    return null; // auto
  }

  /// true = solo, false = pool, considering override + auto-detect
  bool isSolo(String minerIp, {String poolUrl = ''}) {
    final override = getOverride(minerIp);
    if (override != null) return override;
    // Auto-detect from pool URL
    return poolUrl.isNotEmpty && BlockCalc.isSoloPool(poolUrl);
  }

  Future<void> setSolo(String minerIp, bool solo) async {
    await _prefs?.setString(_key(minerIp), solo ? 'solo' : 'pool');
  }

  Future<void> clearOverride(String minerIp) async {
    await _prefs?.remove(_key(minerIp));
  }
}
