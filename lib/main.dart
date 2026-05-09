import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/coin.dart';
import 'services/miner_store.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/coin_price_service.dart';
import 'services/haptic_service.dart';
import 'services/circuit_service.dart';
import 'services/chat_service.dart';
import 'services/history_service.dart';
import 'services/relay_service.dart';
import 'services/schedule_service.dart';
import 'screens/home_screen.dart';
import 'services/group_service.dart';
import 'theme/volt_theme.dart';
import 'widgets/klaw.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await NotificationService.instance.init();
  await HapticService.instance.init();
  await HistoryService.instance.init();
  await ScheduleService.instance.init();
  // Auto-reconnect relay if a key was saved from a previous session
  RelayService.instance.reconnectSaved();
  runApp(const KratosApp());
}

class KratosApp extends StatelessWidget {
  const KratosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => MinerStore()),
        ChangeNotifierProvider(
          create: (_) =>
              CoinPriceService()..startAutoRefresh(const [Coin.btc]),
        ),
        ChangeNotifierProvider(create: (_) => CircuitService()),
        ChangeNotifierProvider(create: (_) => GroupService.instance),
        ChangeNotifierProvider(create: (_) => ChatService()),
      ],
      child: Consumer<ThemeService>(
        builder: (ctx, theme, _) {
          return MaterialApp(
            title: 'Kratos',
            debugShowCheckedModeBanner: false,
            theme: kratosThemeData(theme.current),
            home: theme.loaded ? const HomeScreen() : const KlawSplash(),
          );
        },
      ),
    );
  }
}

// ── Legacy theme constants (still referenced by v1.0 widgets) ────────────────
// Kept verbatim so existing miner_card.dart, miner_detail_screen.dart, etc.
// keep compiling. New code uses `KratosColors` from theme/volt_theme.dart.
class KratosTheme {
  static const bg        = KratosColors.bg;
  static const surface   = KratosColors.surface;
  static const surface2  = KratosColors.surface2;
  static const border    = KratosColors.line;
  static const neon      = KratosColors.volt;
  static const orange    = Color(0xFFF7931A); // BTC accent — preserved
  static const blue      = KratosColors.info;
  static const purple    = Color(0xFFB58CFF);
  static const red       = KratosColors.danger;
  static const muted     = KratosColors.muted;
  static const textPrim  = KratosColors.text;
}
