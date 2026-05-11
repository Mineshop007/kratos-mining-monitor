import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';

/// Shared AppBar with the KLAW honeybadger logo on the left.
/// Drop-in replacement for AppBar across all Kratos screens.
class KratosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showKlaw;   // false = back-navigation screens (auto leading)
  final bool centerTitle;
  final double elevation;
  final PreferredSizeWidget? bottom;

  const KratosAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showKlaw = true,
    this.centerTitle = false,
    this.elevation = 0,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final canPop = Navigator.canPop(context);

    Widget? leadingWidget = leading;
    if (leadingWidget == null) {
      if (canPop) {
        // Back-navigation screen — show back arrow, no KLAW
        // Any screen with KLAW — tapping always pops to root (home tabs)
        leadingWidget = GestureDetector(
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/klaw-mascot.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      } else if (showKlaw) {
        // Root screen — show KLAW logo (tapping still navigates home)
        leadingWidget = GestureDetector(
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/klaw-mascot.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      }
    }

    return AppBar(
      backgroundColor: kc.bg,
      elevation: elevation,
      scrolledUnderElevation: 0,
      leading: leadingWidget,
      leadingWidth: canPop ? 48 : 44,
      title: title,
      centerTitle: centerTitle,
      actions: actions,
      bottom: bottom,
      titleTextStyle: TextStyle(
        color: kc.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: IconThemeData(color: kc.text),
    );
  }
}

/// Small KLAW watermark — used in screen corners or footers.
class KlawWatermark extends StatelessWidget {
  final double size;
  const KlawWatermark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.18,
    child: Image.asset(
      'assets/images/klaw-mascot.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
    ),
  );
}
