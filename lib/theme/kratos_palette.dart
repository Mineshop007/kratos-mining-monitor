import 'package:flutter/material.dart';
import 'volt_theme.dart';

/// Per-theme color palette injected as a ThemeExtension.
/// Access via: KratosColors.of(context)
class KratosPalette extends ThemeExtension<KratosPalette> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color accent;       // primary neon (green / magenta / silver / chrome blue)
  final Color accentBright; // glow / highlight
  final Color accentDeep;   // shadow
  final Color secondary;    // secondary accent (cyan equivalent)
  final Color text;
  final Color muted;

  const KratosPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.secondary,
    required this.text,
    required this.muted,
  });

  // ── Palettes ────────────────────────────────────────────────────────────────

  static const circuit = KratosPalette(
    bg:           Color(0xFF050A0B),
    surface:      Color(0xFF0F1817),
    surface2:     Color(0xFF162421),
    line:         Color(0xFF1A2826),
    accent:       Color(0xFF00C864),
    accentBright: Color(0xFF39FFA0),
    accentDeep:   Color(0xFF007840),
    secondary:    Color(0xFF00D4A0),
    text:         Color(0xFFD8EDE5),
    muted:        Color(0xFF6A8880),
  );

  static const volt = KratosPalette(
    bg:           Color(0xFF050A0B),
    surface:      Color(0xFF0F1817),
    surface2:     Color(0xFF162421),
    line:         Color(0xFF1A2826),
    accent:       Color(0xFF00E676),
    accentBright: Color(0xFF5DFFB0),
    accentDeep:   Color(0xFF00A85A),
    secondary:    Color(0xFF00FFB2),
    text:         Color(0xFFE8F5EE),
    muted:        Color(0xFF8A9A92),
  );

  static const pulse = KratosPalette(
    bg:           Color(0xFF090010),
    surface:      Color(0xFF120018),
    surface2:     Color(0xFF1A0024),
    line:         Color(0xFF280030),
    accent:       Color(0xFFE040FB),
    accentBright: Color(0xFFF8A0FF),
    accentDeep:   Color(0xFF9900CC),
    secondary:    Color(0xFFFF4FC8),
    text:         Color(0xFFF5E8FF),
    muted:        Color(0xFF9070A8),
  );

  static const stealth = KratosPalette(
    bg:           Color(0xFF000000),
    surface:      Color(0xFF0A0A0A),
    surface2:     Color(0xFF111111),
    line:         Color(0xFF1C1C1C),
    accent:       Color(0xFFCCCCCC),
    accentBright: Color(0xFFFFFFFF),
    accentDeep:   Color(0xFF888888),
    secondary:    Color(0xFFAAAAAA),
    text:         Color(0xFFE8E8E8),
    muted:        Color(0xFF505050),
  );

  static const chrome = KratosPalette(
    bg:           Color(0xFF080C10),
    surface:      Color(0xFF111820),
    surface2:     Color(0xFF192330),
    line:         Color(0xFF1E2E3A),
    accent:       Color(0xFF60B8E0),
    accentBright: Color(0xFF9ADAF8),
    accentDeep:   Color(0xFF2E7FA8),
    secondary:    Color(0xFF48D4C8),
    text:         Color(0xFFDDE8F0),
    muted:        Color(0xFF5E7888),
  );

  static KratosPalette forTheme(KratosThemeName name) => switch (name) {
    KratosThemeName.circuit => circuit,
    KratosThemeName.volt    => volt,
    KratosThemeName.pulse   => pulse,
    KratosThemeName.stealth => stealth,
    KratosThemeName.chrome  => chrome,
  };

  // ── ThemeExtension boilerplate ───────────────────────────────────────────────

  @override
  KratosPalette copyWith({
    Color? bg, Color? surface, Color? surface2, Color? line,
    Color? accent, Color? accentBright, Color? accentDeep,
    Color? secondary, Color? text, Color? muted,
  }) => KratosPalette(
    bg:           bg           ?? this.bg,
    surface:      surface      ?? this.surface,
    surface2:     surface2     ?? this.surface2,
    line:         line         ?? this.line,
    accent:       accent       ?? this.accent,
    accentBright: accentBright ?? this.accentBright,
    accentDeep:   accentDeep   ?? this.accentDeep,
    secondary:    secondary    ?? this.secondary,
    text:         text         ?? this.text,
    muted:        muted        ?? this.muted,
  );

  @override
  KratosPalette lerp(KratosPalette? other, double t) {
    if (other == null) return this;
    return KratosPalette(
      bg:           Color.lerp(bg,           other.bg,           t)!,
      surface:      Color.lerp(surface,      other.surface,      t)!,
      surface2:     Color.lerp(surface2,     other.surface2,     t)!,
      line:         Color.lerp(line,         other.line,         t)!,
      accent:       Color.lerp(accent,       other.accent,       t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentDeep:   Color.lerp(accentDeep,   other.accentDeep,   t)!,
      secondary:    Color.lerp(secondary,    other.secondary,    t)!,
      text:         Color.lerp(text,         other.text,         t)!,
      muted:        Color.lerp(muted,        other.muted,        t)!,
    );
  }
}
