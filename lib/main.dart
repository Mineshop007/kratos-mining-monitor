import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/miner_store.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const KratosApp());
}

class KratosApp extends StatelessWidget {
  const KratosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MinerStore(),
      child: MaterialApp(
        title: 'Kratos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00FF88),
            secondary: Color(0xFFF7931A),
            surface: Color(0xFF161B22),
            background: Color(0xFF0D1117),
          ),
          fontFamily: 'SF Pro Display',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0D1117),
            elevation: 0,
            centerTitle: false,
          ),
          useMaterial3: true,
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}

// ── Theme constants ──────────────────────────────────────────────────────────
class KratosTheme {
  static const bg        = Color(0xFF0D1117);
  static const surface   = Color(0xFF161B22);
  static const surface2  = Color(0xFF21262D);
  static const border    = Color(0xFF30363D);
  static const neon      = Color(0xFF00FF88);
  static const orange    = Color(0xFFF7931A);
  static const blue      = Color(0xFF58A6FF);
  static const purple    = Color(0xFFBC8CFF);
  static const red       = Color(0xFFF85149);
  static const muted     = Color(0xFF8B949E);
  static const textPrim  = Color(0xFFE6EDF3);
}
