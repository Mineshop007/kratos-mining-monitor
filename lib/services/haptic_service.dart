import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// Fires a haptic pulse on each newly-accepted share, and a stronger
/// pattern on block-found events.
///
/// Triggered by MinerStore observing share count deltas — we **never**
/// fire on synthetic data. If a miner returns the same accepted count
/// (or the count goes down on a stratum reconnect), no haptic fires.
///
/// User toggles intensity in Settings. Default = medium.
class HapticService {
  HapticService._();
  static final HapticService instance = HapticService._();

  static const _kIntensityKey = 'kratos_haptic_intensity';
  static const _kEnabledKey = 'kratos_haptic_enabled';

  HapticIntensity intensity = HapticIntensity.medium;
  bool enabled = true;
  bool _platformHasVibrator = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kIntensityKey);
    if (raw != null) {
      final match = HapticIntensity.values
          .where((v) => v.name == raw)
          .firstOrNull;
      if (match != null) intensity = match;
    }
    enabled = prefs.getBool(_kEnabledKey) ?? true;
    _platformHasVibrator = await Vibration.hasVibrator();
  }

  Future<void> setIntensity(HapticIntensity v) async {
    intensity = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIntensityKey, v.name);
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, v);
  }

  /// Fire on a single share submit (real, observed delta).
  void onShareAccepted() {
    if (!enabled) return;
    if (intensity == HapticIntensity.off) return;
    if (Platform.isIOS) {
      switch (intensity) {
        case HapticIntensity.light:
          HapticFeedback.selectionClick();
          break;
        case HapticIntensity.medium:
          HapticFeedback.lightImpact();
          break;
        case HapticIntensity.strong:
          HapticFeedback.mediumImpact();
          break;
        case HapticIntensity.off:
          break;
      }
    } else if (Platform.isAndroid && _platformHasVibrator) {
      final ms = switch (intensity) {
        HapticIntensity.light => 12,
        HapticIntensity.medium => 24,
        HapticIntensity.strong => 50,
        HapticIntensity.off => 0,
      };
      if (ms > 0) Vibration.vibrate(duration: ms);
    }
  }

  /// Fire on block-found event — strong, unmistakable.
  Future<void> onBlockFound() async {
    if (!enabled) return;
    if (intensity == HapticIntensity.off) return;
    if (Platform.isIOS) {
      // Three quick heavy pulses.
      for (var i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } else if (Platform.isAndroid && _platformHasVibrator) {
      Vibration.vibrate(pattern: const [0, 80, 60, 80, 60, 200]);
    }
  }
}

enum HapticIntensity { off, light, medium, strong }

extension HapticIntensityExt on HapticIntensity {
  String get displayName => switch (this) {
    HapticIntensity.off    => 'Off',
    HapticIntensity.light  => 'Light',
    HapticIntensity.medium => 'Medium',
    HapticIntensity.strong => 'Strong',
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
