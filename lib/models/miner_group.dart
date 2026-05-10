import 'package:flutter/material.dart';

class MinerGroup {
  final String id;
  String name;
  String emoji;
  int colorValue; // Color.value
  List<String> minerIds;
  DateTime createdAt;

  MinerGroup({
    required this.id,
    required this.name,
    this.emoji = '⚡',
    this.colorValue = 0xFFF7931A,
    List<String>? minerIds,
    DateTime? createdAt,
  })  : minerIds = minerIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
        'minerIds': minerIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory MinerGroup.fromJson(Map<String, dynamic> j) => MinerGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String? ?? '⚡',
        colorValue: j['colorValue'] as int? ?? 0xFFF7931A,
        minerIds: (j['minerIds'] as List?)?.cast<String>() ?? [],
        createdAt: j['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int)
            : DateTime.now(),
      );

  MinerGroup copyWith({String? name, String? emoji, int? colorValue, List<String>? minerIds}) =>
      MinerGroup(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        minerIds: minerIds ?? List.from(this.minerIds),
        createdAt: createdAt,
      );
}

/// Available group emoji options
const kGroupEmojis = [
  '⚡', '🏠', '🏗️', '🏭', '🔷', '🔶', '🟢', '🔴',
  '💎', '🚀', '🔥', '❄️', '⛏️', '🦾', '🛡️', '🎯',
];

/// Available group accent colors
const kGroupColors = [
  0xFFF7931A, // Bitcoin orange
  0xFF00E676, // Volt green
  0xFF5BB6FF, // Blue
  0xFFE040FB, // Magenta
  0xFFFFD700, // Gold
  0xFF00FFB2, // Cyan
  0xFFFF4757, // Red
  0xFFB58CFF, // Purple
];
