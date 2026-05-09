import 'dart:async';
import 'package:flutter/material.dart';
import '../models/miner.dart';

/// Live-ticking uptime — increments every second between polls.
class UptimeTicker extends StatefulWidget {
  final MinerStats? stats;
  final TextStyle? style;
  final bool compact; // "47m 03s" vs "47m"
  const UptimeTicker({super.key, this.stats, this.style, this.compact = false});

  @override
  State<UptimeTicker> createState() => _UptimeTickerState();
}

class _UptimeTickerState extends State<UptimeTicker> {
  Timer? _t;
  int _extra = 0;
  DateTime? _base;

  @override
  void initState() {
    super.initState();
    _reset();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _base != null) {
        setState(() => _extra = DateTime.now().difference(_base!).inSeconds);
      }
    });
  }

  @override
  void didUpdateWidget(UptimeTicker old) {
    super.didUpdateWidget(old);
    if (widget.stats?.lastUpdated != old.stats?.lastUpdated) _reset();
  }

  void _reset() {
    _extra = 0;
    _base = DateTime.now();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    if (s == null || s.uptime <= 0) return Text('--', style: widget.style);
    final total = s.uptime + _extra;
    return Text(_fmt(total), style: widget.style);
  }

  String _fmt(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return widget.compact
          ? '${h}h ${m.toString().padLeft(2,'0')}m'
          : '${h}h ${m.toString().padLeft(2,'0')}m ${s.toString().padLeft(2,'0')}s';
    }
    return widget.compact
        ? '${m}m'
        : '${m}m ${s.toString().padLeft(2,'0')}s';
  }
}
