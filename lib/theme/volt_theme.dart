import 'package:flutter/material.dart';
import 'kratos_palette.dart';
export 'kratos_palette.dart';

/// Kratos v2 — "Volt" electro-green design language.
///
/// Two themes ship in 1.2.0:
///  • Circuit (default, dark teal-black with subtle green grid)
///  • Volt    (signature electric green palette)
///
/// Three more (Pulse, Stealth, Chrome) ship in 1.3.0.
///
/// Changing this palette automatically updates anywhere `KratosColors`
/// is used. Existing `KratosTheme.*` constants in main.dart remain as
/// legacy aliases for back-compat with v1.0 widgets.
class KratosColors {
  // --- Brand core ---
  static const volt        = Color(0xFF00E676);   // primary electric green
  static const voltBright  = Color(0xFF5DFFB0);   // glow
  static const voltDeep    = Color(0xFF00A85A);   // shadow
  static const cyan        = Color(0xFF00FFB2);   // cyan accent

  // --- Surface ---
  static const bg          = Color(0xFF050A0B);   // deep charcoal teal
  static const surface     = Color(0xFF0F1817);
  static const surface2    = Color(0xFF162421);
  static const line        = Color(0xFF1A2826);

  // --- Type ---
  static const text        = Color(0xFFE8F5EE);   // off-white with green tint
  static const muted       = Color(0xFF8A9A92);

  // --- Semantic ---
  static const danger      = Color(0xFFFF4757);
  static const warning     = Color(0xFFFFD66B);
  static const info        = Color(0xFF5BB6FF);
  static const success     = volt;

  // --- Coin badges ---
  static const coinBtc     = Color(0xFFFFD66B);   // gold
  static const coinKas     = Color(0xFF7DFFCB);
  static const coinAlph    = cyan;
  static const coinCkb     = Color(0xFFB58CFF);
  static const coinLtc     = Color(0xFF5BB6FF);
  static const coinDoge    = Color(0xFFD4A45B);

  // Hard rule: coin colors are never "estimated" — they are fixed brand
  // tokens used only for chips/badges. They are not data.

  /// Returns the active palette for the current theme.
  /// Falls back to Volt if no extension found.
  static KratosPalette of(BuildContext context) =>
      Theme.of(context).extension<KratosPalette>() ?? KratosPalette.volt;
}

/// Five named themes. Only Circuit and Volt are unlocked in 1.2.0.
enum KratosThemeName {
  circuit,
  volt,
  pulse,
  stealth,
  chrome,
}

extension KratosThemeNameExt on KratosThemeName {
  String get displayName => switch (this) {
    KratosThemeName.circuit  => 'Circuit',
    KratosThemeName.volt     => 'Volt',
    KratosThemeName.pulse    => 'Pulse',
    KratosThemeName.stealth  => 'Stealth',
    KratosThemeName.chrome   => 'Chrome',
  };

  bool get unlocked => true; // all 5 themes unlocked
}

ThemeData kratosThemeData(KratosThemeName name) {
  final p = KratosPalette.forTheme(name);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: p.bg,
    fontFamily: 'SF Pro Display',
    extensions: [p],
    colorScheme: ColorScheme.dark(
      primary: p.accent,
      onPrimary: Color.lerp(p.bg, Colors.black, 0.5)!,
      secondary: p.secondary,
      surface: p.surface,
      onSurface: p.text,
      error: KratosColors.danger,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface2,
      contentTextStyle: TextStyle(color: p.text),
    ),
    dividerColor: p.line,
  );
}
