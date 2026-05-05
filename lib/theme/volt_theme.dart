import 'package:flutter/material.dart';

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

  bool get unlocked => this == KratosThemeName.circuit || this == KratosThemeName.volt;
}

ThemeData kratosThemeData(KratosThemeName name) {
  // Both Circuit and Volt share the same palette in 1.2.0; Circuit hides
  // the grid background, Volt shows it. Other themes will diverge in 1.3.0.
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: KratosColors.bg,
    fontFamily: 'SF Pro Display',
    colorScheme: const ColorScheme.dark(
      primary: KratosColors.volt,
      onPrimary: Color(0xFF001A0E),
      secondary: KratosColors.cyan,
      surface: KratosColors.surface,
      onSurface: KratosColors.text,
      error: KratosColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KratosColors.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: KratosColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: KratosColors.surface2,
      contentTextStyle: TextStyle(color: KratosColors.text),
    ),
    dividerColor: KratosColors.line,
  );
}
