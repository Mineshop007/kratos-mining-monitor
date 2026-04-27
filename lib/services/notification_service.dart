import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Push notification service for miner alerts
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Per-type toggles (loaded/saved via MinerStore preferences)
  bool notifyOffline = true;
  bool notifyHighTemp = true;
  bool notifyBlockFound = true;
  bool notifyPoolSwitch = true;

  Future<void> init() async {
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> _show(int id, String title, String body) async {
    if (!_initialized) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'kratos_alerts',
          'Kratos Miner Alerts',
          channelDescription: 'Miner status and event alerts',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }

  void notifyMinerOffline(String minerName) {
    if (!notifyOffline) return;
    _show(
      minerName.hashCode & 0x7FFFFFFF,
      'Miner Offline',
      '$minerName went offline',
    );
  }

  void notifyHighTemperature(String minerName, double temp) {
    if (!notifyHighTemp) return;
    _show(
      (minerName.hashCode + 1) & 0x7FFFFFFF,
      'High Temperature Alert',
      '$minerName: ${temp.toInt()}C — check cooling!',
    );
  }

  void notifyBlockFoundAlert(String minerName) {
    if (!notifyBlockFound) return;
    _show(
      (minerName.hashCode + 2) & 0x7FFFFFFF,
      'BLOCK FOUND!',
      '$minerName found a Bitcoin block!',
    );
  }

  void notifyPoolSwitched(String minerName) {
    if (!notifyPoolSwitch) return;
    _show(
      (minerName.hashCode + 3) & 0x7FFFFFFF,
      'Pool Switched',
      '$minerName switched to fallback stratum',
    );
  }
}
