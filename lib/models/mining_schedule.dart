import 'package:flutter/material.dart';

/// Actions a schedule rule can apply to an Avalon home miner
enum ScheduleAction { eco, standard, superMode, standby, wake, none }

extension ScheduleActionX on ScheduleAction {
  String get label => switch (this) {
    ScheduleAction.eco       => 'Eco Mode',
    ScheduleAction.standard  => 'Standard',
    ScheduleAction.superMode => 'Super',
    ScheduleAction.standby   => 'Standby',
    ScheduleAction.wake      => 'Wake Up',
    ScheduleAction.none      => 'Do Nothing',
  };
  String get emoji => switch (this) {
    ScheduleAction.eco       => '🌿',
    ScheduleAction.standard  => '⚡',
    ScheduleAction.superMode => '🔥',
    ScheduleAction.standby   => '😴',
    ScheduleAction.wake      => '☀️',
    ScheduleAction.none      => '—',
  };
  Color color(BuildContext context) => switch (this) {
    ScheduleAction.eco       => const Color(0xFF4CAF50),
    ScheduleAction.standard  => const Color(0xFF2196F3),
    ScheduleAction.superMode => const Color(0xFFF44336),
    ScheduleAction.standby   => const Color(0xFFFF9800),
    ScheduleAction.wake      => const Color(0xFFFFEB3B),
    ScheduleAction.none      => const Color(0xFF757575),
  };
  String toJson() => name;
  static ScheduleAction fromJson(String s) =>
      ScheduleAction.values.firstWhere((e) => e.name == s,
          orElse: () => ScheduleAction.none);
}

class ScheduleRule {
  final String id;
  final String name;
  final List<int> days; // 0=Mon … 6=Sun
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final ScheduleAction action;
  final bool enabled;
  final int priority;

  const ScheduleRule({
    required this.id,
    required this.name,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.action,
    this.enabled = true,
    this.priority = 0,
  });

  bool matchesNow(DateTime now) {
    if (!enabled) return false;
    if (!days.contains(now.weekday - 1)) return false;
    final t = now.hour * 60 + now.minute;
    final s = startTime.hour * 60 + startTime.minute;
    final e = endTime.hour * 60 + endTime.minute;
    if (s < e) return t >= s && t < e;
    return t >= s || t < e; // wraps midnight
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'days': days,
    'startH': startTime.hour, 'startM': startTime.minute,
    'endH': endTime.hour, 'endM': endTime.minute,
    'action': action.toJson(), 'enabled': enabled, 'priority': priority,
  };

  factory ScheduleRule.fromJson(Map<String, dynamic> j) => ScheduleRule(
    id: j['id'] as String,
    name: j['name'] as String,
    days: List<int>.from(j['days'] as List),
    startTime: TimeOfDay(hour: j['startH'] as int, minute: j['startM'] as int),
    endTime:   TimeOfDay(hour: j['endH']  as int, minute: j['endM']  as int),
    action: ScheduleActionX.fromJson(j['action'] as String),
    enabled: j['enabled'] as bool? ?? true,
    priority: j['priority'] as int? ?? 0,
  );

  ScheduleRule copyWith({
    String? name, List<int>? days, TimeOfDay? startTime,
    TimeOfDay? endTime, ScheduleAction? action, bool? enabled,
  }) => ScheduleRule(
    id: id,
    name: name ?? this.name,
    days: days ?? List.from(this.days),
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
    priority: priority,
  );
}

class MinerSchedule {
  final String minerId;
  final bool enabled;
  final ScheduleAction defaultAction;
  final List<ScheduleRule> rules;

  const MinerSchedule({
    required this.minerId,
    this.enabled = false,
    this.defaultAction = ScheduleAction.none,
    this.rules = const [],
  });

  ScheduleAction evaluate(DateTime now) {
    if (!enabled || rules.isEmpty) return ScheduleAction.none;
    final matches = rules.where((r) => r.matchesNow(now)).toList();
    if (matches.isEmpty) return defaultAction;
    matches.sort((a, b) => b.priority.compareTo(a.priority));
    return matches.first.action;
  }

  Map<String, dynamic> toJson() => {
    'minerId': minerId,
    'enabled': enabled,
    'defaultAction': defaultAction.toJson(),
    'rules': rules.map((r) => r.toJson()).toList(),
  };

  factory MinerSchedule.fromJson(Map<String, dynamic> j) => MinerSchedule(
    minerId: j['minerId'] as String,
    enabled: j['enabled'] as bool? ?? false,
    defaultAction: ScheduleActionX.fromJson(j['defaultAction'] as String? ?? 'none'),
    rules: (j['rules'] as List? ?? [])
        .map((r) => ScheduleRule.fromJson(r as Map<String, dynamic>))
        .toList(),
  );

  MinerSchedule copyWith({bool? enabled, ScheduleAction? defaultAction, List<ScheduleRule>? rules}) =>
    MinerSchedule(
      minerId: minerId,
      enabled: enabled ?? this.enabled,
      defaultAction: defaultAction ?? this.defaultAction,
      rules: rules ?? List.from(this.rules),
    );
}
