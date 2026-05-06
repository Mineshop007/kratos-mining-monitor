import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/miner.dart';
import 'autotune_service.dart';

/// Community OC database client — submits autotune results and fetches
/// aggregate stats so users can see what others are running.
class OcSummary {
  final String model;
  final int count;
  final double avgFreq;
  final double avgHashrate;
  final double maxHashrate;
  final int? bestFreq;
  final int? bestVoltage;

  const OcSummary({
    required this.model,
    required this.count,
    required this.avgFreq,
    required this.avgHashrate,
    required this.maxHashrate,
    this.bestFreq,
    this.bestVoltage,
  });

  factory OcSummary.fromJson(Map<String, dynamic> j) => OcSummary(
        model: j['model'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        avgFreq: (j['avg_freq'] as num?)?.toDouble() ?? 0,
        avgHashrate: (j['avg_hashrate'] as num?)?.toDouble() ?? 0,
        maxHashrate: (j['max_hashrate'] as num?)?.toDouble() ?? 0,
        bestFreq: (j['best_freq'] as num?)?.toInt(),
        bestVoltage: (j['best_voltage'] as num?)?.toInt(),
      );
}

class OcCommunityService {
  static final OcCommunityService instance = OcCommunityService._();
  OcCommunityService._();

  static const _base = 'https://kratos.mineshop.eu/oc';

  String _modelKey(MinerType type) => type.name;

  Future<bool> submitResult(
      AutotuneResult result, MinerType type, String firmware) async {
    try {
      final body = jsonEncode({
        'model': _modelKey(type),
        'firmware': firmware,
        'freq_mhz': result.optimalFreqMhz,
        'voltage_mv': result.optimalVoltageMv,
        'hashrate_gh': result.peakHashrate,
        'temp_c': result.temperature,
        'efficiency_ghw': result.efficiency,
      });
      final res = await http
          .post(Uri.parse('$_base/submit'),
              headers: const {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 8));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<OcSummary?> getSummary(MinerType type) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/summary/${_modelKey(type)}'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return OcSummary.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
