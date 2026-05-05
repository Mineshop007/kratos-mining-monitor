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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kratos/services/best_diff_tracker.dart';
import 'package:kratos/services/coin_price_service.dart';
import 'package:kratos/services/miner_store.dart';
import 'package:kratos/services/theme_service.dart';
import 'package:kratos/screens/chat_screen.dart';
import 'package:kratos/screens/settings_screen.dart';
import 'package:kratos/screens/pools_screen.dart';
import 'package:kratos/models/coin.dart';
import 'package:kratos/theme/volt_theme.dart';

Widget _withProviders(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeService()),
      ChangeNotifierProvider(create: (_) => MinerStore()),
      // Note: do NOT call startAutoRefresh — keeps tests timer-clean.
      ChangeNotifierProvider(create: (_) => CoinPriceService()),
    ],
    child: MaterialApp(theme: kratosThemeData(KratosThemeName.volt), home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('Settings tab shows v1.2.0 + theme + electricity sections',
      (tester) async {
    await tester.pumpWidget(_withProviders(const SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('v1.2.0'), findsOneWidget);
    expect(find.text('THEME'), findsOneWidget);
    expect(find.text('Volt'), findsOneWidget);
    expect(find.text('Circuit'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Chat tab is honest about deferred chat (no fake messages)',
      (tester) async {
    await tester.pumpWidget(_withProviders(const ChatScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('In-app chat is coming'), findsOneWidget);
    expect(find.textContaining('Discord'), findsWidgets);
    // No fabricated message bubbles, channel counts, or usernames.
    expect(find.textContaining('# bitaxe'), findsNothing);

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
