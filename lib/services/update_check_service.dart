import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks App Store (iOS) or Play Store (Android) for a newer version.
/// iOS  → iTunes lookup API (free, no auth)
/// Android → Play Store HTML scrape (fallback: same iTunes version as proxy)
class UpdateCheckService extends ChangeNotifier {
  static final UpdateCheckService instance = UpdateCheckService._();
  UpdateCheckService._();

  static const _bundleId     = 'com.kratos.miningmonitor';
  static const _appStoreUrl  = 'https://apps.apple.com/app/id6762138440';
  static const _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.kratos.miningmonitor';
  static const _dismissKey   = 'update_dismissed_version';

  String? _latestVersion;
  String? _currentVersion;
  bool _dismissed = false;

  String? get latestVersion => _latestVersion;
  bool get updateAvailable =>
      _latestVersion != null &&
      !_dismissed &&
      _isNewer(_latestVersion!, _currentVersion ?? '0.0.0');

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    // Delay so we don't slow down startup
    Future.delayed(const Duration(seconds: 8), _check);
  }

  Future<void> _check() async {
    try {
      final version = Platform.isAndroid
          ? await _fetchAndroidVersion()
          : await _fetchIosVersion();

      if (version == null || version.isEmpty) return;

      _latestVersion = version;

      final prefs = await SharedPreferences.getInstance();
      final dismissedVer = prefs.getString(_dismissKey);
      _dismissed = (dismissedVer == version);

      notifyListeners();
    } catch (_) {
      // Silent — network errors are expected offline
    }
  }

  /// iTunes lookup — returns version string or null
  Future<String?> _fetchIosVersion() async {
    final r = await http.get(
      Uri.parse('https://itunes.apple.com/lookup?bundleId=$_bundleId&country=us'),
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final results = j['results'] as List?;
    if (results == null || results.isEmpty) return null;
    return results.first['version'] as String?;
  }

  /// Play Store HTML scrape — parses the version from the store page
  Future<String?> _fetchAndroidVersion() async {
    final r = await http.get(
      Uri.parse(_playStoreUrl),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;

    // Play Store encodes the version in a JSON-LD block or data- attributes.
    // Most reliable pattern: [["X.Y.Z"]] near the version label.
    final match = RegExp(r'\[\["(\d+\.\d+(?:\.\d+)?)"\]\]').firstMatch(r.body);
    if (match != null) return match.group(1);

    // Fallback: look for softwareVersion meta tag
    final meta = RegExp(r'"softwareVersion"\s*:\s*"([\d.]+)"').firstMatch(r.body);
    return meta?.group(1);
  }

  /// Open the correct store for the current platform
  Future<void> openStore() async {
    final url = Platform.isAndroid ? _playStoreUrl : _appStoreUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Dismiss for this version — won't show again until a newer version drops
  Future<void> dismiss() async {
    _dismissed = true;
    if (_latestVersion != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissKey, _latestVersion!);
    }
    notifyListeners();
  }

  Future<void> forceCheck() async {
    _dismissed = false;
    await _check();
  }

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
