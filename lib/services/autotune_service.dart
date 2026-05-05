import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/miner.dart';
import 'esp_miner_api.dart';

enum AutotuneState { idle, running, done, failed }

class AutotuneResult {
  final int optimalFreqMhz;
  final int optimalVoltageMv;
  final double peakHashrate;
  final double efficiency; // GH/W
  final double temperature;
  final String summary;

  const AutotuneResult({
    required this.optimalFreqMhz,
    required this.optimalVoltageMv,
    required this.peakHashrate,
    required this.efficiency,
    required this.temperature,
    required this.summary,
  });
}

class AutotuneService extends ChangeNotifier {
  AutotuneState state = AutotuneState.idle;
  String log = '';
  double progress = 0; // 0.0 to 1.0
  AutotuneResult? result;
  bool _cancelled = false;

  // Safe frequency sweep ranges per device type
  static const _ranges = <String, ({int min, int max, int step})>{
    'bitaxe': (min: 300, max: 650, step: 10),
    'nerdqaxe': (min: 400, max: 620, step: 10),
    'nerdoctaxe': (min: 400, max: 600, step: 10),
    'avalonNano': (min: 500, max: 600, step: 12),
  };

  static ({int min, int max, int step}) _getRange(MinerType type) {
    switch (type) {
      case MinerType.bitaxeGamma:
      case MinerType.bitaxeUltra:
      case MinerType.bitaxeGT:
        return _ranges['bitaxe']!;
      case MinerType.nerdqaxe:
        return _ranges['nerdqaxe']!;
      case MinerType.nerdoctaxe:
        return _ranges['nerdoctaxe']!;
      case MinerType.avalonNano3:
      case MinerType.avalonNano3s:
        return _ranges['avalonNano']!;
      default:
        return _ranges['bitaxe']!;
    }
  }

  Future<void> run(Miner miner) async {
    state = AutotuneState.running;
    _cancelled = false;
    log = '';
    progress = 0;
    result = null;
    notifyListeners();

    try {
      // 1. Read baseline
      final baseStats = await EspMinerAPI.instance.fetchAll(
        miner.ip, miner.port,
        remoteUrl: miner.remoteUrl,
        isRemote: miner.isRemote,
      );
      if (baseStats.status == MinerStatus.offline) {
        throw Exception('Miner is offline');
      }
      _addLog('Baseline: ${baseStats.hashrate5s.toStringAsFixed(1)} GH/s @ '
          '${baseStats.frequency.toInt()} MHz, ${baseStats.outTemp.toInt()}°C');

      // 2. Build frequency sweep list
      final range = _getRange(miner.type);
      final freqs = List.generate(
        (range.max - range.min) ~/ range.step + 1,
        (i) => range.min + i * range.step,
      );

      int bestFreq = baseStats.frequency.toInt();
      double bestHashrate = baseStats.hashrate5s;
      bool tempAborted = false;

      // 3. Sweep — labeled break replaces goto
      outerLoop:
      for (int i = 0; i < freqs.length; i++) {
        if (_cancelled) break;

        final freq = freqs[i];
        progress = i / freqs.length;
        _addLog('Testing ${freq} MHz...');
        notifyListeners();

        // Apply frequency
        final ok = await EspMinerAPI.instance.setFrequency(
          miner.ip, miner.port, freq,
          remoteUrl: miner.remoteUrl,
          isRemote: miner.isRemote,
        );
        if (!ok) {
          _addLog('  ⚠️ setFrequency failed — skipping');
          continue;
        }

        // Stabilisation wait (45s per the spec)
        await Future.delayed(const Duration(seconds: 45));
        if (_cancelled) break;

        // Sample hashrate 5 times, 10s apart
        final samples = <double>[];
        for (int s = 0; s < 5; s++) {
          if (_cancelled) break outerLoop;

          final st = await EspMinerAPI.instance.fetchAll(
            miner.ip, miner.port,
            remoteUrl: miner.remoteUrl,
            isRemote: miner.isRemote,
          );

          // Temperature safety guard
          if (st.outTemp > 72) {
            _addLog('⚠️ Temp ${st.outTemp.toInt()}°C too high at ${freq} MHz — stopping sweep');
            tempAborted = true;
            break outerLoop;
          }

          samples.add(st.hashrate5s);
          await Future.delayed(const Duration(seconds: 10));
        }

        if (samples.isEmpty) continue;

        final avgHashrate =
            samples.reduce((a, b) => a + b) / samples.length;
        _addLog('  ${freq} MHz → ${avgHashrate.toStringAsFixed(1)} GH/s');

        if (avgHashrate > bestHashrate * 0.98) {
          bestFreq = freq;
          bestHashrate = avgHashrate;
        } else if (avgHashrate < bestHashrate * 0.92 && i > 0) {
          // Degraded >8% — ceiling found
          final prevFreq = freqs[max(0, i - 1)];
          _addLog('Hashrate degraded — ceiling found at ${prevFreq} MHz');
          break;
        }
      }

      if (_cancelled) {
        _addLog('🚫 Autotune cancelled.');
        state = AutotuneState.failed;
        notifyListeners();
        return;
      }

      // 4. Apply optimal frequency
      await EspMinerAPI.instance.setFrequency(
        miner.ip, miner.port, bestFreq,
        remoteUrl: miner.remoteUrl,
        isRemote: miner.isRemote,
      );
      _addLog('✅ Optimal: ${bestFreq} MHz → ${bestHashrate.toStringAsFixed(1)} GH/s');
      if (tempAborted) {
        _addLog('ℹ️ Sweep stopped early due to temperature limit.');
      }

      final finalStats = await EspMinerAPI.instance.fetchAll(
        miner.ip, miner.port,
        remoteUrl: miner.remoteUrl,
        isRemote: miner.isRemote,
      );

      result = AutotuneResult(
        optimalFreqMhz: bestFreq,
        optimalVoltageMv: finalStats.coreVoltage,
        peakHashrate: bestHashrate,
        efficiency: bestHashrate / (finalStats.powerDraw > 0 ? finalStats.powerDraw : 1),
        temperature: finalStats.outTemp,
        summary: '${bestFreq} MHz · ${bestHashrate.toStringAsFixed(0)} GH/s · '
            '${finalStats.outTemp.toInt()}°C',
      );
      progress = 1.0;
      state = AutotuneState.done;
    } catch (e) {
      _addLog('❌ Error: $e');
      state = AutotuneState.failed;
    }
    notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    notifyListeners();
  }

  void reset() {
    state = AutotuneState.idle;
    log = '';
    progress = 0;
    result = null;
    _cancelled = false;
    notifyListeners();
  }

  void _addLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    log += '\n[$ts] $msg';
  }
}
