import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/miner.dart';
import 'relay_service.dart';

/// CGMiner API client — works with ANY cgminer-compatible miner
class CGMinerAPI {
  static final CGMinerAPI instance = CGMinerAPI._();
  CGMinerAPI._();

  /// Parse host and port from a remoteUrl (e.g. "http://1.2.3.4:4028") or fall back to ip/port.
  (String, int) _effectiveTarget(String ip, int port, String remoteUrl) {
    if (remoteUrl.isNotEmpty) {
      final uri = Uri.tryParse(remoteUrl);
      if (uri != null) {
        final h = uri.host.isNotEmpty ? uri.host : ip;
        final p = uri.hasPort ? uri.port : port;
        return (h, p);
      }
    }
    return (ip, port);
  }

  Future<Map<String, dynamic>?> sendCommand(
    String command, String ip, int port, {Duration timeout = const Duration(seconds: 5)}
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.write('$command\n');
      await socket.flush();

      final buffer = StringBuffer();
      await for (final data in socket.timeout(timeout)) {
        buffer.write(utf8.decode(data));
        if (buffer.toString().contains('"id":')) break;
      }
      final raw = buffer.toString().replaceAll('\x00', '').trim();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// Send a raw (non-JSON) command — e.g. Avalon Q pipe format: "ascset|0,setpool,..."
  /// Reads until the miner closes the connection; returns the raw response string.
  Future<String> _sendRaw(String command, String ip, int port,
      {Duration timeout = const Duration(seconds: 8)}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.write('$command\n');
      await socket.flush();
      final buffer = StringBuffer();
      await for (final data in socket.timeout(timeout)) {
        buffer.write(utf8.decode(data, allowMalformed: true));
      }
      return buffer.toString().replaceAll('\x00', '').trim();
    } catch (_) {
      return '';
    } finally {
      socket?.destroy();
    }
  }

  /// Check a plain-text CGMiner/Avalon ascset response (STATUS=S/I = ok).
  bool _isRawOK(String raw) {
    if (raw.isEmpty) return false;
    final upper = raw.toUpperCase();
    // Standard: STATUS=S or STATUS=I at the start
    if (upper.startsWith('STATUS=S') || upper.startsWith('STATUS=I')) return true;
    // Wrapped in STATUS array: {"STATUS":[{"STATUS":"S"...
    if (upper.contains('"STATUS":"S"') || upper.contains('"STATUS":"I"')) return true;
    return false;
  }

  /// Set pool on Avalon Q / Mini 3 using the native ascset command.
  /// Confirmed wire format from avalon-q-controller source:
  ///   ascset|0,setpool,stratum+tcp://host:port,worker,pass
  /// Fallback pool via setpool2 if supported.
  /// Sends reboot after save — the Q applies pool changes on next restart.
  Future<bool> setPoolAscset(
    String ip,
    int port, {
    required String primaryUrl,
    required String primaryUser,
    String primaryPass = 'x',
    String? fallbackUrl,
    String? fallbackUser,
    String fallbackPass = 'x',
    bool rebootAfterSave = true,
    String remoteUrl = '',
    bool isRemote = false,
  }) async {
    final (h, p) = isRemote ? (ip, port) : _effectiveTarget(ip, port, remoteUrl);

    // 1. Set primary pool via ascset pipe command
    final r1 = await _sendRaw('ascset|0,setpool,$primaryUrl,$primaryUser,$primaryPass', h, p);
    final ok1 = _isRawOK(r1);

    // 2. Set fallback pool if provided (some firmware supports setpool2)
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      final fu = fallbackUser?.isNotEmpty == true ? fallbackUser! : primaryUser;
      await _sendRaw('ascset|0,setpool2,$fallbackUrl,$fu,$fallbackPass', h, p);
    }

    // 3. Reboot to apply — Avalon Q applies pool changes only after restart
    if (rebootAfterSave) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendRaw('ascset|0,reboot,0', h, p);
    }

    return ok1;
  }

  Future<MinerStats> fetchAll(String ip, int port,
      {String remoteUrl = '', bool isRemote = false}) async {
    // ── Remote path: route CGMiner commands through relay bridge ─────────────
    if (isRemote) {
      return _fetchAllRemote(ip, port);
    }
    final (effectiveIp, effectivePort) = _effectiveTarget(ip, port, remoteUrl);
    // Fetch in parallel for speed
    final results = await Future.wait([
      sendCommand('{"command":"summary"}', effectiveIp, effectivePort),
      sendCommand('{"command":"pools"}', effectiveIp, effectivePort),
      sendCommand('{"command":"stats"}', effectiveIp, effectivePort),
      sendCommand('{"command":"version"}', effectiveIp, effectivePort),
    ]);

    final summaryResp = results[0];
    final poolsResp   = results[1];
    final statsResp   = results[2];
    final versionResp = results[3];

    return _parseStats(
      summaryResp: summaryResp,
      poolsResp: poolsResp,
      statsResp: statsResp,
      versionResp: versionResp,
    );
  }

  /// Shared parsing logic used by both local and remote (relay) fetch paths.
  MinerStats _parseStats({
    required Map<String, dynamic>? summaryResp,
    Map<String, dynamic>? poolsResp,
    Map<String, dynamic>? statsResp,
    Map<String, dynamic>? versionResp,
  }) {
    if (summaryResp == null) return MinerStats.offline;

    // Parse summary
    final sum = (summaryResp['SUMMARY'] as List?)?.first as Map? ?? {};
    // Canaan/Avalon reports GHS; Antminer/Whatsminer report MHS; some report KHS/THS
    final hashrate5s  = _parseHashrateField(sum, '5s');
    final hashrateAvg = _parseHashrateField(sum, 'av');
    final accepted    = (sum['Accepted'] as num?)?.toInt() ?? 0;
    final rejected    = (sum['Rejected'] as num?)?.toInt() ?? 0;
    final hwErrors    = (sum['Hardware Errors'] as num?)?.toInt() ?? 0;
    final uptime      = (sum['Elapsed'] as num?)?.toInt() ?? 0;
    // 'Best Share' can be a number (standard CGMiner) or a string like "2.5G" (Avalon)
    // Avalon Mini 3 / Q also use 'Best Share' in SUMMARY; fallback to pool-level max
    final bestShare = _parseBestDiff(
        sum['Best Share'] ?? sum['bestDiff'] ?? sum['best_diff'] ??
        sum['BestDiff'] ?? sum['best_share'] ?? 0);

    // Parse pools
    final poolsList = (poolsResp?['POOLS'] as List?) ?? [];
    final pools = poolsList.map((p) {
      final pm = p as Map;
      return PoolInfo(
        index:     (pm['POOL'] as num?)?.toInt() ?? 0,
        url:       pm['URL'] as String? ?? '',
        user:      pm['User'] as String? ?? '',
        status:    pm['Status'] as String? ?? 'Unknown',
        accepted:  (pm['Accepted'] as num?)?.toInt() ?? 0,
        rejected:  (pm['Rejected'] as num?)?.toInt() ?? 0,
        active:    pm['Stratum Active'] as bool? ?? false,
        bestShare: _parseBestDiff(pm['Best Share'] ?? pm['bestDiff'] ?? 0),
      );
    }).toList();

    // Parse device stats — supports multi-board devices (Avalon Q has 4 boards)
    double outTemp = 0, frequency = 0, powerDraw = 0;
    int fanRPM = 0, fanPercent = 0;
    String firmware = '', model = '';

    final statsList = (statsResp?['STATS'] as List?) ?? [];
    final boardTemps  = <double>[];  // collect per-board temps for averaging
    final boardPowers = <double>[];  // sum per-board power
    int boardCount = 0;
    int workMode = -1;   // Avalon Q: 0=Eco, 1=Standard, 2=Super
    int minerState = -1; // Avalon Q: 0=init, 1=working, 2=standby
    final inletTemps  = <double>[];  // Avalon Q ITemp (chassis/inlet)

    for (final stat in statsList) {
      final sm = stat as Map;

      // ── Collect all MM ID payloads from this STATS entry ─────────────
      // Avalon Q firmware uses key "MM ID0:Summary" (with :Summary suffix).
      // Older Avalon / Nano 3S use "MM ID0". We support both:
      // 1. Try numbered keys with and without :Summary suffix.
      // 2. Fallback: scan all string values for ones containing Avalon markers.
      final mmids = <String>[];

      // Pass 1: numbered keys (both formats)
      for (int boardIdx = 0; boardIdx < 6; boardIdx++) {
        for (final key in ['MM ID$boardIdx', 'MM ID$boardIdx:Summary']) {
          final v = sm[key];
          if (v is String && v.isNotEmpty) { mmids.add(v); break; }
        }
      }

      // Pass 2: scan all string values if nothing found yet
      if (mmids.isEmpty) {
        for (final v in sm.values) {
          if (v is String && (
              v.contains('ITemp[') || v.contains('WORKMODE[') ||
              v.contains('GHSspd[') || v.contains('THSspd[') ||
              v.contains('TMax['))) {
            mmids.add(v);
          }
        }
      }

      for (int i = 0; i < mmids.length; i++) {
        final mmid = mmids[i];
        boardCount++;

        // ── Temperature ────────────────────────────────────────────────
        // Avalon Q: TMax = max chip temp (primary), ITemp = chassis/inlet
        // Older Avalon / generic: OTemp, Temp
        double chipTemp = _parseField(mmid, 'TMax');      // Avalon Q max chip
        if (chipTemp == 0) chipTemp = _parseField(mmid, 'TAvg');  // avg fallback
        if (chipTemp == 0) chipTemp = _parseField(mmid, 'OTemp'); // older Avalon
        if (chipTemp == 0) chipTemp = _parseField(mmid, 'Temp');  // generic
        if (chipTemp > 0) boardTemps.add(chipTemp);

        // Inlet / chassis temperature (second temp shown in HashWatcher)
        double iTemp = _parseField(mmid, 'ITemp');
        if (iTemp == 0) iTemp = _parseField(mmid, 'HBOTemp'); // outlet fallback
        if (iTemp > 0 && inletTemps.isEmpty) inletTemps.add(iTemp); // board 0 only

        // ── Power ─────────────────────────────────────────────────────
        // Avalon Q: Cur_Load[N] = current watts (simplest)
        double bPower = _parseField(mmid, 'Cur_Load');
        if (bPower == 0) bPower = _parsePower(mmid); // PS[...] fallback
        if (bPower > 0) boardPowers.add(bPower);

        // ── Board 0: fan, freq, firmware, workmode, state ─────────────
        if (i == 0) {
          // Fan RPM — Avalon Q has Fan1..Fan4; use Fan1 or average
          fanRPM = _parseField(mmid, 'Fan1').toInt();
          if (fanRPM == 0) fanRPM = _parseField(mmid, 'Fan').toInt();
          // Fan percent
          fanPercent = _parseField(mmid, 'FanR').toInt();
          // Frequency
          frequency  = _parseField(mmid, 'Freq');
          if (frequency == 0) frequency = _parseField(mmid, 'T1F');
          // Firmware / model
          firmware   = _parseStringField(mmid, 'Ver');
          if (firmware.isEmpty) firmware = _parseStringField(mmid, 'VERS');
          model      = _parseModel(firmware);
          // Workmode + state (Avalon Q)
          final wm = _parseField(mmid, 'WORKMODE').toInt();
          if (wm >= 0 && wm <= 2) workMode = wm;
          final st = _parseField(mmid, 'STATE').toInt();
          if (st >= 0 && st <= 3) minerState = st;
        }
      }

      // Standard temp fallback (non-Avalon CGMiner devices)
      if (boardTemps.isEmpty) {
        final t = ((sm['Temperature'] as num?) ?? 0).toDouble();
        if (t > 0) boardTemps.add(t);
      }
    }

    // Aggregate across boards
    if (boardTemps.isNotEmpty) {
      // Use max temp (conservative — catches the hottest board)
      outTemp = boardTemps.reduce((a, b) => a > b ? a : b);
    }
    if (boardPowers.isNotEmpty) {
      powerDraw = boardPowers.reduce((a, b) => a + b); // sum all boards
    }
    final inletTemp = inletTemps.isNotEmpty ? inletTemps.first : 0.0;

    // Parse version
    final verList = (versionResp?['VERSION'] as List?) ?? [];
    if (verList.isNotEmpty) {
      final v = verList.first as Map;
      if (model.isEmpty) model = v['PROD'] as String? ?? v['MODEL'] as String? ?? '';
      if (firmware.isEmpty) firmware = v['CGVERSION'] as String? ?? v['LVERSION'] as String? ?? '';
    }

    // Pool-level best share fallback — take max across all pools
    // Avalon Mini 3 and Q often report best diff only at the pool level
    double bestShareFinalFromPools = 0;
    for (final pool in pools) {
      if (pool.bestShare > bestShareFinalFromPools) {
        bestShareFinalFromPools = pool.bestShare;
      }
    }

    // Best diff fallback from MM ID0 — Avalon stores it as BestDiff[2.5G]
    double bestShareFinal = bestShare;
    if (bestShareFinal == 0) {
      for (final stat in statsList) {
        final sm = stat as Map;
        for (int i = 0; i < 6; i++) {
          final mmid = sm['MM ID$i'] as String? ?? '';
          if (mmid.isEmpty) continue;
          final raw = _parseStringField(mmid, 'BestDiff');
          if (raw.isNotEmpty) {
            bestShareFinal = _parseBestDiff(raw);
            if (bestShareFinal > 0) break;
          }
        }
        if (bestShareFinal > 0) break;
      }
    }

    // Apply pool-level best share if better than SUMMARY
    if (bestShareFinalFromPools > bestShareFinal) {
      bestShareFinal = bestShareFinalFromPools;
    }

    // Board-level hashrate fallback when SUMMARY reports 0
    // Avalon Q uses GHSspd[N] (GH/s). Older Avalon: GHSmm.
    double hashrate5sFinal = hashrate5s;
    double hashrateAvgFinal = hashrateAvg;
    if (hashrate5sFinal == 0 && hashrateAvgFinal == 0) {
      double ghsTotal = 0;
      for (final stat in statsList) {
        final sm = stat as Map;
        // Collect mmids same way as above
        final mmids = <String>[];
        for (int boardIdx = 0; boardIdx < 6; boardIdx++) {
          for (final key in ['MM ID$boardIdx', 'MM ID$boardIdx:Summary']) {
            final v = sm[key];
            if (v is String && v.isNotEmpty) { mmids.add(v); break; }
          }
        }
        if (mmids.isEmpty) {
          for (final v in sm.values) {
            if (v is String && (v.contains('GHSspd[') || v.contains('THSspd[') || v.contains('GHSmm['))) mmids.add(v);
          }
        }
        for (final mmid in mmids) {
          // GHSspd = Avalon Q CGI (GH/s). THSspd = ha_avalonq firmware (TH/s). GHSmm = older Avalon (GH/s).
          double ghs = _parseField(mmid, 'GHSspd');
          if (ghs == 0) {
            final ths = _parseField(mmid, 'THSspd'); // TH/s → GH/s
            if (ths > 0) ghs = ths * 1000.0;
          }
          if (ghs == 0) ghs = _parseField(mmid, 'GHSmm');
          if (ghs > 0) ghsTotal += ghs;
        }
      }
      if (ghsTotal > 0) {
        hashrate5sFinal = ghsTotal;
        hashrateAvgFinal = ghsTotal;
      }
    }

    // Determine status
    MinerStatus status = MinerStatus.online;
    if (outTemp > 85 || fanRPM < 300 && fanRPM > 0) status = MinerStatus.warning;
    if (hwErrors > 10) status = MinerStatus.warning;

    return MinerStats(
      hashrate5s: hashrate5sFinal,
      hashrateAvg: hashrateAvgFinal,
      outTemp: outTemp,
      fanRPM: fanRPM,
      fanPercent: fanPercent,
      accepted: accepted,
      rejected: rejected,
      hardwareErrors: hwErrors,
      uptime: uptime,
      pools: pools,
      frequency: frequency,
      powerDraw: powerDraw,
      status: status,
      lastUpdated: DateTime.now(),
      firmware: firmware,
      model: model,
      type: MinerType.detect(model),
      bestShare: bestShareFinal,
      workMode: workMode,
      minerState: minerState,
      inletTemp: inletTemp,
    );
  }

  // ── Remote relay fetch ──────────────────────────────────────────────────────

  /// Fetch CGMiner stats via relay bridge. The bridge at home opens a
  /// raw TCP socket to port 4028 and forwards the JSON commands.
  Future<MinerStats> _fetchAllRemote(String ip, int port) async {
    try {
      // The bridge converts path to CGMiner command:
      // path='/summary' → {"command":"summary"}
      final results = await Future.wait([
        RelayService.instance.command(
            minerIp: ip, minerPort: port, method: 'GET', path: '/summary'),
        RelayService.instance.command(
            minerIp: ip, minerPort: port, method: 'GET', path: '/pools'),
        RelayService.instance.command(
            minerIp: ip, minerPort: port, method: 'GET', path: '/stats'),
        RelayService.instance.command(
            minerIp: ip, minerPort: port, method: 'GET', path: '/version'),
      ].map((f) => f.catchError((_) => <String, dynamic>{})).toList());

      // Relay wraps response in 'data' key
      Map unwrap(Map r) => (r['data'] is Map) ? r['data'] as Map : r;

      final summaryResp = unwrap(results[0]);
      final poolsResp   = unwrap(results[1]);
      final statsResp   = unwrap(results[2]);
      final versionResp = unwrap(results[3]);

      // Reuse the same parsing logic by reconstructing expected shape
      return _parseStats(
        summaryResp: summaryResp.isEmpty ? null : Map<String, dynamic>.from(summaryResp),
        poolsResp:   poolsResp.isEmpty   ? null : Map<String, dynamic>.from(poolsResp),
        statsResp:   statsResp.isEmpty   ? null : Map<String, dynamic>.from(statsResp),
        versionResp: versionResp.isEmpty ? null : Map<String, dynamic>.from(versionResp),
      );
    } catch (_) {
      return MinerStats.offline;
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  Future<bool> restart(String ip, int port, {String remoteUrl = ''}) async {
    final (h, p) = _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,reboot,0', h, p);
    return _isRawOK(r);
  }

  Future<bool> setFrequency(String ip, int port, int mhz, {String remoteUrl = ''}) async {
    final (h, p) = _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,frequency,$mhz', h, p);
    return _isRawOK(r);
  }

  Future<bool> setFanSpeed(String ip, int port, int percent,
      {String remoteUrl = '', bool isRemote = false}) async {
    final (h, p) = isRemote ? (ip, port) : _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,fan,$percent', h, p);
    return _isRawOK(r);
  }

  /// Avalon Q soft-off (standby). Firmware applies ~5s after call.
  Future<bool> softOff(String ip, int port,
      {String remoteUrl = '', bool isRemote = false}) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 5;
    final (h, p) = isRemote ? (ip, port) : _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,softoff,1:$ts', h, p);
    return _isRawOK(r);
  }

  /// Avalon Q soft-on (wake from standby). Firmware applies ~5s after call.
  Future<bool> softOn(String ip, int port,
      {String remoteUrl = '', bool isRemote = false}) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 5;
    final (h, p) = isRemote ? (ip, port) : _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,softon,1:$ts', h, p);
    return _isRawOK(r);
  }

  /// Avalon work mode: 0=Eco, 1=Standard, 2=Super
  Future<bool> setWorkMode(String ip, int port, int mode,
      {String remoteUrl = '', bool isRemote = false}) async {
    final (h, p) = isRemote ? (ip, port) : _effectiveTarget(ip, port, remoteUrl);
    final r = await _sendRaw('ascset|0,workmode,set,$mode', h, p);
    return _isRawOK(r);
  }

  Future<bool> setPools(String ip, int port, List<Map<String, String>> pools,
      {String remoteUrl = '', bool isRemote = false, bool rebootAfterSave = false}) async {
    final (effectiveIp, effectivePort) = isRemote
        ? (ip, port)
        : _effectiveTarget(ip, port, remoteUrl);

    // Remove old pools (ignore errors — fewer pools than 3 is fine)
    for (int i = 0; i < 3; i++) {
      await sendCommand('{"command":"removepool","parameter":"$i"}',
          effectiveIp, effectivePort);
    }
    // Add new pools
    bool anyAdded = false;
    for (final pool in pools) {
      final url  = pool['url'] ?? '';
      final user = pool['user'] ?? 'worker';
      final pass = pool['pass'] ?? 'x';
      final r = await sendCommand(
          '{"command":"addpool","parameter":"$url,$user,$pass"}',
          effectiveIp, effectivePort);
      if (_isOK(r)) anyAdded = true;
    }
    await sendCommand('{"command":"saveconfig"}', effectiveIp, effectivePort);

    // Avalon Q (and Mini 3) apply pool changes only after a reboot
    if (rebootAfterSave) {
      await Future.delayed(const Duration(milliseconds: 400));
      await sendCommand('{"command":"ascset","parameter":"0,reboot,0"}',
          effectiveIp, effectivePort);
    }

    return anyAdded;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parse best difficulty — handles both raw numbers and string suffixes (G/T/M/K).
  /// Avalon Nano 3S returns strings like "2.5G"; standard CGMiner returns a number.
  double _parseBestDiff(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is! String || v.isEmpty) return 0;
    final s = v.trim().toUpperCase();
    const suffixes = {'P': 1e15, 'T': 1e12, 'G': 1e9, 'M': 1e6, 'K': 1e3};
    for (final entry in suffixes.entries) {
      if (s.endsWith(entry.key)) {
        final n = double.tryParse(s.substring(0, s.length - 1));
        if (n != null) return n * entry.value;
      }
    }
    return double.tryParse(s) ?? 0;
  }

  /// Parse hashrate from SUMMARY map — handles MHS/GHS/KHS/THS suffixes.
  /// Always returns GH/s.
  double _parseHashrateField(Map sum, String suffix) {
    final mhs = (sum['MHS $suffix'] as num?)?.toDouble();
    if (mhs != null && mhs > 0) return mhs / 1000.0; // MH/s → GH/s
    final ghs = (sum['GHS $suffix'] as num?)?.toDouble();
    if (ghs != null && ghs > 0) return ghs;           // GH/s as-is
    final ths = (sum['THS $suffix'] as num?)?.toDouble();
    if (ths != null && ths > 0) return ths * 1000.0;  // TH/s → GH/s
    final khs = (sum['KHS $suffix'] as num?)?.toDouble();
    if (khs != null && khs > 0) return khs / 1000000.0; // KH/s → GH/s
    return 0;
  }

  double _parseField(String mmid, String key) {
    // Allow optional trailing % (e.g. FanR[44%]) and strip it before parsing
    final r = RegExp('$key\\[([0-9.\\-]+)%?\\]');
    final m = r.firstMatch(mmid);
    return m != null ? double.tryParse(m.group(1)!) ?? 0 : 0;
  }

  String _parseStringField(String mmid, String key) {
    final r = RegExp('$key\\[([^\\]]+)\\]');
    final m = r.firstMatch(mmid);
    return m?.group(1) ?? '';
  }

  String _parseModel(String fw) {
    // Examples seen in the wild:
    //   "Nano3s-26032122_ffec1e9"      → "Nano3s"
    //   "Mini3-26041500_abc1234"       → "Mini3"
    //   "1161-1_avalonMINI3-26041500"  → "avalonMINI3"
    //   "AvalonQ-26041500"             → "AvalonQ"
    // Strategy: find the first segment that looks like a model name
    // (contains letters and doesn't look like a pure version number)
    final lower = fw.toLowerCase();
    // Direct model prefix before first hyphen
    if (fw.contains('-')) {
      final parts = fw.split('-');
      for (final p in parts) {
        final pl = p.toLowerCase();
        if (pl.contains('nano') || pl.contains('mini') ||
            pl.contains('avalonq') || pl.contains('avalon')) {
          return p;
        }
      }
      // Underscore-separated variant: "1161-1_avalonMINI3-26041500"
      for (final seg in fw.split(RegExp(r'[_\-]'))) {
        final sl = seg.toLowerCase();
        if (sl.contains('nano') || sl.contains('mini') ||
            sl.contains('avalonq') || sl.contains('avalon')) {
          return seg;
        }
      }
      return parts.first;
    }
    return fw;
  }

  double _parsePower(String mmid) {
    // Confirmed from live Avalon Nano 3S data:
    // PS[0 0 27272 5 0 3756 140]  →  parts[6] = 140 W (actual watts)
    // parts[5] = raw ADC reading (NOT watts), parts[6] = watts
    final r = RegExp(r'PS\[([^\]]+)\]');
    final m = r.firstMatch(mmid);
    if (m == null) return 0;
    final parts = m.group(1)!.trim().split(RegExp(r'\s+'));
    if (parts.length > 6) return (int.tryParse(parts[6]) ?? 0).toDouble();
    // Older firmware: only 6 elements, fall back to parts[5] as-is
    if (parts.length > 5) return (int.tryParse(parts[5]) ?? 0).toDouble();
    return 0;
  }

  bool _isOK(Map<String, dynamic>? resp) {
    if (resp == null) return false;
    final status = (resp['STATUS'] as List?)?.first as Map?;
    return status?['STATUS'] == 'S';
  }
}
