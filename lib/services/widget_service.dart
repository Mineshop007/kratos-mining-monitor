import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';

/// Pushes live fleet data to the Android/iOS home screen widget.
/// Call [update] from MinerStore whenever stats refresh.
class WidgetService {
  WidgetService._();
  static final instance = WidgetService._();

  static const _appGroupId = 'group.com.kratos.miningmonitor';
  static const _androidName = 'com.kratos.kratos.KratosWidget';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _initialized = true;
  }

  /// Push current MinerStore state to the home screen widget.
  Future<void> update(MinerStore store) async {
    await init();

    final stats = store.stats.values.toList();
    final online  = stats.where((s) => s.status == MinerStatus.online).length;
    final offline = stats.where((s) => s.status == MinerStatus.offline).length;

    final totalGH = stats.fold<double>(0, (sum, s) => sum + s.hashrateDisplay);
    final bestShare = stats.fold<double>(
        0, (best, s) => s.bestShare > best ? s.bestShare : best);

    final hashrateStr = _fmtHashrate(totalGH);
    final bestStr     = _fmtDiff(bestShare);
    final updatedStr  = DateFormat('HH:mm').format(DateTime.now());

    await HomeWidget.saveWidgetData('hashrate',  hashrateStr);
    await HomeWidget.saveWidgetData('online',    online.toString());
    await HomeWidget.saveWidgetData('offline',   offline.toString());
    await HomeWidget.saveWidgetData('bestShare', bestStr);
    await HomeWidget.saveWidgetData('updated',   updatedStr);

    await HomeWidget.updateWidget(
      androidName: _androidName,
      iOSName: 'KratosWidget',
    );
  }

  String _fmtHashrate(double gh) {
    if (gh >= 1000) return '${(gh / 1000).toStringAsFixed(2)} TH/s';
    if (gh >= 1)    return '${gh.toStringAsFixed(1)} GH/s';
    if (gh > 0)     return '${(gh * 1000).toStringAsFixed(0)} MH/s';
    return '-- GH/s';
  }

  String _fmtDiff(double v) {
    if (v <= 0)     return '--';
    if (v >= 1e12)  return '${(v / 1e12).toStringAsFixed(1)}T';
    if (v >= 1e9)   return '${(v / 1e9).toStringAsFixed(1)}G';
    if (v >= 1e6)   return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3)   return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
