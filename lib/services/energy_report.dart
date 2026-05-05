import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/miner.dart';
import 'miner_store.dart';

/// Generates an energy report (CSV) for the current fleet snapshot.
///
/// **Real data only.** Every row is a current observation from each
/// miner's API + the user-configured kWh price. No back-fill, no
/// estimation — only the live `MinerStats.powerDraw` and current
/// hashrate. If a miner has never reported power, we emit an empty
/// row for that field rather than guessing from nameplate.
class EnergyReportService {
  /// Generate the CSV string. Returns the bytes plus filename.
  ({String csv, String filename}) buildCsv(MinerStore store) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}-${_pad(now.hour)}${_pad(now.minute)}';
    final filename = 'kratos-energy-report-$stamp.csv';

    final buf = StringBuffer();
    buf.writeln(
        'Generated,Miner,Type,Status,Hashrate (GH/s),Power (W),Efficiency (W/TH),'
        'Daily kWh,Daily cost (kWh price ${store.kwhPrice} USD),'
        'Daily revenue (USD),Daily net (USD),Last updated');

    final headerNote = '"Real-data export. '
        'Power=0 means the device firmware did not report power; '
        'no nameplate fallback. Daily values extrapolate the current '
        'measurement to 24h."';
    buf.writeln(headerNote);

    for (final m in store.miners) {
      final s = store.stats[m.id];
      final isMeasured = s != null && s.status != MinerStatus.offline;
      final hashrate = isMeasured ? s.hashrateAvg : null;
      final power = isMeasured ? s.powerDraw : null;
      final dailyKwh = power != null ? (power / 1000.0) * 24.0 : null;
      final dailyCost =
          dailyKwh != null ? dailyKwh * store.kwhPrice : null;
      final dailyRevenue = isMeasured
          ? store.minerDailyEarningsUsd(m.id)
          : null;
      final dailyNet = (dailyRevenue != null && dailyCost != null)
          ? dailyRevenue - dailyCost
          : null;

      buf.writeln([
        _csv(now.toIso8601String()),
        _csv(m.name),
        _csv(m.type.displayName),
        _csv(s?.status.name ?? 'unknown'),
        _f(hashrate),
        _f(power),
        _f(_efficiency(power, hashrate)),
        _f(dailyKwh, decimals: 3),
        _f(dailyCost, decimals: 2),
        _f(dailyRevenue, decimals: 2),
        _f(dailyNet, decimals: 2),
        _csv(s?.lastUpdated.toIso8601String() ?? ''),
      ].join(','));
    }

    // Fleet totals row
    buf.writeln(_fleetRow(store));

    return (csv: buf.toString(), filename: filename);
  }

  /// Save and present share sheet.
  Future<void> exportAndShare(MinerStore store) async {
    final r = buildCsv(store);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${r.filename}';
    final file = File(path);
    await file.writeAsString(r.csv);
    await Share.shareXFiles([XFile(path, mimeType: 'text/csv')],
        subject: 'Kratos energy report ${r.filename}');
  }

  // ── helpers ──────────────────────────────────────────────────────────

  String _csv(String s) {
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _f(double? v, {int decimals = 2}) =>
      v == null ? '' : v.toStringAsFixed(decimals);

  String _pad(int v) => v.toString().padLeft(2, '0');

  double? _efficiency(double? watts, double? hashrateGh) {
    if (watts == null || hashrateGh == null) return null;
    if (hashrateGh <= 0) return null;
    final th = hashrateGh / 1000.0;
    return watts / th;
  }

  String _fleetRow(MinerStore store) {
    final totalH = store.totalHashrate;
    final totalW = store.totalPower;
    final dailyKwh = (totalW / 1000.0) * 24.0;
    final dailyCost = store.totalDailyCostUsd;
    final dailyRev = store.totalDailyEarningsUsd;
    return [
      '',
      _csv('FLEET TOTAL'),
      '', '',
      _f(totalH), _f(totalW),
      _f(_efficiencyTotal(totalW, totalH)),
      _f(dailyKwh, decimals: 3),
      _f(dailyCost, decimals: 2),
      _f(dailyRev, decimals: 2),
      _f(dailyRev - dailyCost, decimals: 2),
      '',
    ].join(',');
  }

  double? _efficiencyTotal(double watts, double hashrateGh) {
    if (hashrateGh <= 0) return null;
    return watts / (hashrateGh / 1000.0);
  }
}
