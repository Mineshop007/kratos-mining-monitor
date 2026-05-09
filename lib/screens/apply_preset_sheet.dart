import 'package:flutter/material.dart';
import '../main.dart';
import '../models/miner.dart';
import '../models/pool_preset.dart';
import '../services/pool_preset_service.dart';
import '../services/esp_miner_api.dart';
import '../services/cgminer_api.dart';
import '../theme/volt_theme.dart';

/// Bottom sheet: pick a pool preset and apply it to a miner in one tap.
class ApplyPresetSheet extends StatefulWidget {
  final Miner miner;
  const ApplyPresetSheet({super.key, required this.miner});
  @override
  State<ApplyPresetSheet> createState() => _ApplyPresetSheetState();
}

class _ApplyPresetSheetState extends State<ApplyPresetSheet> {
  List<PoolPreset> _presets = [];
  bool _loading = true;
  String? _applying; // preset id being applied
  String? _result;

  @override
  void initState() {
    super.initState();
    PoolPresetService.instance.loadAll().then((p) {
      if (mounted) setState(() { _presets = p; _loading = false; });
    });
  }

  bool get _isCgminer =>
      widget.miner.type.apiType == ApiType.cgminerTcp;
  bool get _isEsp =>
      widget.miner.type.apiType == ApiType.espMinerHttp;

  Future<void> _apply(PoolPreset preset) async {
    setState(() { _applying = preset.id; _result = null; });
    final worker = preset.resolveWorker(widget.miner.name, minerIp: widget.miner.ip);
    bool ok = false;
    try {
      if (_isEsp) {
        ok = await EspMinerAPI.instance.setPool(
          widget.miner.ip, widget.miner.port,
          stratumUrl: preset.host,
          stratumPort: preset.port,
          stratumUser: worker,
          remoteUrl: widget.miner.remoteUrl,
          isRemote: widget.miner.isRemote,
        );
      } else if (_isCgminer) {
        ok = await CGMinerAPI.instance.setPools(
          widget.miner.ip, widget.miner.port,
          [{'url': preset.stratumUrl, 'user': worker, 'pass': preset.password}],
          remoteUrl: widget.miner.remoteUrl,
          isRemote: widget.miner.isRemote,
        );
      }
    } catch (_) {}
    setState(() {
      _applying = null;
      _result = ok
          ? '✅ Applied "${preset.name}" to ${widget.miner.name}'
          : '❌ Failed — check miner is reachable on same WiFi';
    });
    if (ok) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: kc.line,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Apply Pool Preset',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: kc.text)),
            Text('→ ${widget.miner.name}',
                style: TextStyle(fontSize: 12, color: kc.muted)),
          ])),
        ]),
        const SizedBox(height: 16),

        if (_result != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _result!.startsWith('✅')
                  ? kc.accent.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _result!.startsWith('✅')
                      ? kc.accent.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3)),
            ),
            child: Text(_result!,
                style: TextStyle(fontSize: 13,
                    color: _result!.startsWith('✅') ? kc.accent : Colors.red)),
          ),
          const SizedBox(height: 12),
        ],

        if (_loading)
          const Padding(padding: EdgeInsets.all(24),
              child: CircularProgressIndicator())
        else if (_presets.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.dns_outlined, size: 40, color: kc.muted),
              const SizedBox(height: 8),
              Text('No presets saved yet',
                  style: TextStyle(color: kc.muted)),
            ]),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _presets[i];
                final color = p.isSolo ? KratosTheme.orange : KratosTheme.blue;
                final isApplying = _applying == p.id;
                return GestureDetector(
                  onTap: isApplying ? null : () => _apply(p),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.25)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(p.isSolo ? 'SOLO' : 'POOL',
                            style: TextStyle(fontSize: 8,
                                fontWeight: FontWeight.w800, color: color,
                                letterSpacing: 1)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: TextStyle(
                                fontWeight: FontWeight.w700, color: kc.text)),
                            Text(
                              '${p.host}:${p.port}  ·  '
                              '${p.resolveWorker(widget.miner.name, minerIp: widget.miner.ip)}',
                              style: TextStyle(fontSize: 11, color: kc.muted,
                                  fontFamily: 'Courier'),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ])),
                      if (isApplying)
                        SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: color))
                      else
                        Icon(Icons.bolt, color: color, size: 20),
                    ]),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}
