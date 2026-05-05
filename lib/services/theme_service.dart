import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/volt_theme.dart';

/// Persists the user's selected theme. Default = Circuit.
/// Only unlocked themes can be selected; locked ones snap back.
class ThemeService extends ChangeNotifier {
  static const _key = 'kratos_theme_name';

  KratosThemeName _current = KratosThemeName.circuit;
  KratosThemeName get current => _current;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _disposed = false;

  ThemeService() {
    _load();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    if (name != null) {
      final match = KratosThemeName.values
          .where((t) => t.name == name)
          .firstOrNull;
      if (match != null && match.unlocked) {
        _current = match;
      }
    }
    _loaded = true;
    _safeNotify();
  }

  Future<void> set(KratosThemeName name) async {
    if (!name.unlocked) return;
    if (_current == name) return;
    _current = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name.name);
    _safeNotify();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
