import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks App Store / Play Store for a newer version and notifies the UI.
/// Uses the iTunes lookup API (free JSON, no auth) as source of truth.
class UpdateCheckService extends ChangeNotifier {
  static final UpdateCheckService instance = UpdateCheckService._();
  UpdateCheckService._();

  static const _bundleId     = 'com.kratos.miningmonitor';
  static const _appStoreUrl  = 'https://apps.apple.com/app/id6762138440';
  static const _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.kratos.miningmonitor';
  static const _dismissKey   = 'update_dismissed_version';
  static const _checkInterval = Duration(hours: 24);

  String? _latestVersion;
  String? _currentVersion;
  bool _dismissed = false;

  /// Non-null and newer than current = show the banner
  String? get latestVersion => _latestVersion;
  bool get updateAvailable =>
      _latestVersion != null &&
      !_dismissed &&
      _isNewer(_latestVersion!, _currentVersion ?? '0.0.0');

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;

    // Check if user already dismissed this version
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_dismissKey);
    // Will be re-evaluated after fetch if latestVersion differs

    // Run first check after a short delay (don't block startup)
    Future.delayed(const Duration(seconds: 8), _check);
  }

  Future<void> _check() async {
    try {
      final r = await http.get(
        Uri.parse(
            'https://itunes.apple.com/lookup?bundleId=$_bundleId&country=us'),
      ).timeout(const Duration(seconds: 10));

      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final results = j['results'] as List?;
      if (results == null || results.isEmpty) return;

      final storeVersion = results.first['version'] as String?;
      if (storeVersion == null || storeVersion.isEmpty) return;

      _latestVersion = storeVersion;

      // Re-check dismissed state for this specific version
      final prefs = await SharedPreferences.getInstance();
      final dismissedVer = prefs.getString(_dismissKey);
      _dismissed = (dismissedVer == storeVersion);

      notifyListeners();
    } catch (_) {
      // Network error — silent, try again on next app open
    }
  }

  /// User tapped "Update" — open the appropriate store
  Future<void> openStore() async {
    // Use platform to decide — on iOS use App Store, Android Play Store
    // Since we can't import dart:io in a service easily, try App Store first
    for (final url in [_appStoreUrl, _playStoreUrl]) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
  }

  /// User dismissed — don't show again for this version
  Future<void> dismiss() async {
    _dismissed = true;
    if (_latestVersion != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissKey, _latestVersion!);
    }
    notifyListeners();
  }

  /// Force re-check (pull-to-refresh etc.)
  Future<void> forceCheck() async {
    _dismissed = false;
    await _check();
  }

  // Semantic version comparison: "2.1.0" > "2.0.6"
  bool _isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    for (int i = 0; i < l.length; i++) {
      if (l[i] > (i < c.length ? c[i] : 0)) return true;
      if (l[i] < (i < c.length ? c[i] : 0)) return false;
    }
    return false;
  }

  List<int> _parse(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}
