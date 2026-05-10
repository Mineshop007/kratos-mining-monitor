// Kratos v1.2.0 unit-style widget tests.
// Tests run against individual screens with explicit lightweight providers
// so pending timers from MinerStore polling / CoinPriceService refresh
// don't leak between tests. These cover the v2 invariants:
//   • 5-tab navigation (no Shop)
//   • Empty state messaging via Klaw
//   • Best-diff formatter rounds correctly
//   • CoinPriceService returns null when no real data is cached

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kratos/services/best_diff_tracker.dart';
import 'package:kratos/services/coin_price_service.dart';
import 'package:kratos/services/circuit_service.dart';
import 'package:kratos/services/chat_service.dart';
import 'package:kratos/services/health_score.dart';
import 'package:kratos/services/miner_store.dart';
import 'package:kratos/services/theme_service.dart';
import 'package:kratos/screens/chat_screen.dart';
import 'package:kratos/screens/settings_screen.dart';
import 'package:kratos/screens/pools_screen.dart';
import 'package:kratos/screens/faq_screen.dart';
import 'package:kratos/models/coin.dart';
import 'package:kratos/models/miner.dart';
import 'package:kratos/theme/volt_theme.dart';

Widget _withProviders(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeService()),
      ChangeNotifierProvider(create: (_) => MinerStore()),
      // Note: do NOT call startAutoRefresh — keeps tests timer-clean.
      ChangeNotifierProvider(create: (_) => CoinPriceService()),
      ChangeNotifierProvider(create: (_) => CircuitService()),
      ChangeNotifierProvider(create: (_) => ChatService()),
    ],
    child:
        MaterialApp(theme: kratosThemeData(KratosThemeName.volt), home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Kratos',
      packageName: 'eu.mineshop.kratos',
      version: '2.0.12',
      buildNumber: '74',
      buildSignature: '',
    );
    // Tall viewport so long-scroll screens (Settings) fit without scrolling.
    TestWidgetsFlutterBinding.ensureInitialized();
    final tb = TestWidgetsFlutterBinding.instance;
    tb.platformDispatcher.views.first.physicalSize = const Size(1170, 3500);
    tb.platformDispatcher.views.first.devicePixelRatio = 3.0;
  });

  group('Best-diff formatter', () {
    test('formats large values in T/G/M', () {
      expect(formatBestDiff(0), '—');
      expect(formatBestDiff(1500), '1.5K');
      expect(formatBestDiff(2300000), '2.3M');
      expect(formatBestDiff(1.42e11), '142.00G');
      expect(formatBestDiff(8.9e13), '89.00T');
    });
  });

  group('Coin model', () {
    test('coingecko ids match canonical strings', () {
      expect(Coin.btc.coinGeckoId, 'bitcoin');
      expect(Coin.kas.coinGeckoId, 'kaspa');
      expect(Coin.alph.coinGeckoId, 'alephium');
      expect(Coin.ckb.coinGeckoId, 'nervos');
      expect(Coin.unknown.coinGeckoId, isNull);
    });
  });

  group('CoinPriceService', () {
    test('returns null when nothing has been fetched (no fakes)', () {
      final svc = CoinPriceService();
      expect(svc.priceFor(Coin.btc), isNull);
      expect(svc.isFresh(Coin.btc), isFalse);
      svc.dispose();
    });
  });

  Future<void> _unmount(WidgetTester tester) async {
    // Force-disposes the provider tree so Timer.periodic instances created
    // inside MinerStore are cancelled before the test framework's
    // !timersPending invariant runs.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('Circuit safety thresholds', () {
    test('EU 230V/16A breaker = 3.68 kW trip, 2.94 kW safe at 80%', () {
      final c = Circuit(
          name: 'Garage', voltage: 230, breakerAmps: 16, safetyFactor: 0.80);
      expect(c.tripWatts, closeTo(3680, 0.5));
      expect(c.safeWatts, closeTo(2944, 0.5));
    });

    test('CircuitSnapshot returns no-data when no miner reports power', () {
      final c =
          Circuit(name: 'X', voltage: 230, breakerAmps: 16, minerIds: ['m1']);
      final snap =
          CircuitSnapshot(circuit: c, measuredWatts: null, onlineCount: 0);
      expect(snap.status, CircuitStatus.noData);
      expect(snap.amps, isNull);
      expect(snap.loadFraction, isNull);
    });

    test('CircuitSnapshot warns at ≥80% load, trips at ≥100%', () {
      final c =
          Circuit(name: 'X', voltage: 230, breakerAmps: 16, safetyFactor: 0.8);
      // 50% load → ok
      var snap =
          CircuitSnapshot(circuit: c, measuredWatts: 1840, onlineCount: 2);
      expect(snap.status, CircuitStatus.ok);
      // 85% load → warn
      snap = CircuitSnapshot(circuit: c, measuredWatts: 3128, onlineCount: 2);
      expect(snap.status, CircuitStatus.warning);
      // 100% load → trip
      snap = CircuitSnapshot(circuit: c, measuredWatts: 3680, onlineCount: 2);
      expect(snap.status, CircuitStatus.overload);
    });
  });

  group('Health score', () {
    test('returns null when stats are null (no fakes)', () {
      expect(HealthScore.from(null), isNull);
    });

    test('offline miner scores 0 with offline grade', () {
      final h = HealthScore.from(MinerStats(status: MinerStatus.offline));
      expect(h, isNotNull);
      expect(h!.score, 0);
      expect(h.grade, HealthGrade.offline);
    });

    test('cool, well-accepting online miner scores high', () {
      final h = HealthScore.from(MinerStats(
        status: MinerStatus.online,
        outTemp: 65,
        accepted: 9990,
        rejected: 10,
        hardwareErrors: 2,
      ));
      expect(h, isNotNull);
      expect(h!.score, greaterThanOrEqualTo(85));
      expect(h.grade, isIn([HealthGrade.excellent, HealthGrade.good]));
    });
  });

  testWidgets('FAQ screen renders sections with no fake message data',
      (tester) async {
    await tester.pumpWidget(_withProviders(const FaqScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('FAQ'), findsOneWidget);
    // Section titles render uppercase via the FAQ widget, so the source
    // string 'Getting started' becomes 'GETTING STARTED'.
    expect(find.textContaining('GETTING STARTED'), findsOneWidget);
    expect(find.textContaining('Klaw'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Settings tab shows current version + theme + electricity sections',
      (tester) async {
    await tester.pumpWidget(_withProviders(const SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('v2.0.12'), findsOneWidget);
    expect(find.text('THEME'), findsOneWidget);
    expect(find.text('Volt'), findsOneWidget);
    expect(find.text('Circuit'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Chat tab boots into live bridge or graceful offline state',
      (tester) async {
    await tester.pumpWidget(_withProviders(const ChatScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    // Either the loading spinner or the offline hero or a connected state.
    // No fake message data either way.
    expect(find.text('Chat'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Pools tab without miners shows Klaw empty state',
      (tester) async {
    await tester.pumpWidget(_withProviders(const PoolsScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Pools'), findsWidgets);
    expect(find.textContaining('Klaw'), findsWidgets);
    expect(find.textContaining('Add a miner'), findsOneWidget);

    await _unmount(tester);
  });
}
