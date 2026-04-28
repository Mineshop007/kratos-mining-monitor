import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/miner.dart';
import '../services/miner_store.dart';
import '../services/cgminer_api.dart';
import '../services/esp_miner_api.dart';
import 'sparkline.dart';
import 'miner_icon.dart';

// ── List Card ─────────────────────────────────────────────────────────────────

class MinerCard extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  final double earningsPerDay;
  final VoidCallback onTap;

  const MinerCard({
    super.key,
    required this.miner,
    this.stats,
    this.earningsPerDay = 0,
    required this.onTap,
  });

  @override
  State<MinerCard> createState() => _MinerCardState();
}

class _MinerCardState extends State<MinerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color _statusAccent(MinerStatus s) => switch (s) {
        MinerStatus.online => const Color(0xFF39d353),
        MinerStatus.warning => const Color(0xFFffd700),
        MinerStatus.offline => const Color(0xFFff4d4d),
        _ => const Color(0xFF6e7681),
      };

  void _showQuickActions(BuildContext ctx) {
    final store = Provider.of<MinerStore>(ctx, listen: false);
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickActionsSheet(
        miner: widget.miner,
        stats: widget.stats,
        store: store,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final status = s?.status ?? MinerStatus.unknown;
    final accentColor = _statusAccent(status);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () => _showQuickActions(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1f2e), Color(0xFF252b3b)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent border
              Container(width: 4, color: accentColor),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardHeader(
                      miner: widget.miner,
                      stats: s,
                      status: status,
                      pulseAnim: _pulseAnim,
                    ),
                    Container(height: 1, color: const Color(0xFF21262d)),
                    _CardStats(stats: s),
                    // Sparkline + earnings footer
                    if (s != null && s.hashrateHistory.length >= 2)
                      _CardFooter(
                        stats: s,
                        earningsPerDay: widget.earningsPerDay,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final Miner miner;
  final MinerStats? stats;
  final MinerStatus status;
  final Animation<double> pulseAnim;

  const _CardHeader({
    required this.miner,
    required this.stats,
    required this.status,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(children: [
        // Miner type icon badge
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0d1117),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Center(
            child: MinerIcon(type: miner.type, size: 26),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                miner.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFFe6edf3),
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                Text(
                  miner.ip,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6e7681),
                    fontFamily: 'Courier',
                  ),
                ),
                if (stats != null && stats!.pools.isNotEmpty) ...[
                  const Text('  ·  ',
                      style:
                          TextStyle(color: Color(0xFF30363D), fontSize: 11)),
                  Flexible(
                    child: Text(
                      _poolHost(stats!.pools),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF6e7681)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StatusBadge(status: status, pulseAnim: pulseAnim),
      ]),
    );
  }

  String _poolHost(List<PoolInfo> pools) {
    final active = pools.where((p) => p.active).firstOrNull ?? pools.first;
    return active.host;
  }
}

class _CardStats extends StatelessWidget {
  final MinerStats? stats;
  const _CardStats({this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        _StatCell(
          label: 'HASHRATE',
          value: s?.hashrateFormatted ?? '--',
          color: const Color(0xFF39d353),
          icon: Icons.flash_on,
          trend: s?.trendDirection,
        ),
        _VertDivider(),
        _StatCell(
          label: 'TEMP',
          value: s != null && s.outTemp > 0 ? '${s.outTemp.toInt()}°' : '--',
          color: _tempColor(s?.outTemp ?? 0),
          icon: Icons.thermostat_outlined,
        ),
        _VertDivider(),
        _StatCell(
          label: 'FAN',
          value: s != null && s.fanRPM > 0
              ? '${s.fanRPM}r'
              : (s != null && s.fanPercent > 0 ? '${s.fanPercent}%' : '--'),
          color: const Color(0xFF58a6ff),
          icon: Icons.air,
        ),
        _VertDivider(),
        _StatCell(
          label: 'ACCEPT',
          value: '${s?.accepted ?? 0}',
          color: const Color(0xFFf7931a),
          icon: Icons.check_circle_outline,
        ),
      ]),
    );
  }

  Color _tempColor(double t) {
    if (t > 85) return const Color(0xFFff4d4d);
    if (t > 75) return const Color(0xFFffd700);
    return const Color(0xFF6e7681);
  }
}

class _CardFooter extends StatelessWidget {
  final MinerStats stats;
  final double earningsPerDay;

  const _CardFooter({required this.stats, this.earningsPerDay = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        children: [
          Container(height: 1, color: const Color(0xFF21262d)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Sparkline(
                  data: stats.hashrateHistory,
                  color: _trendColor(stats.trendDirection),
                  height: 24,
                ),
              ),
              if (earningsPerDay > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFf7931a).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFf7931a).withOpacity(0.3)),
                  ),
                  child: Text(
                    '\$${earningsPerDay.toStringAsFixed(2)}/d',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFf7931a),
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _trendColor(int dir) {
    if (dir > 0) return const Color(0xFF39d353);
    if (dir < 0) return const Color(0xFFff4d4d);
    return const Color(0xFF58a6ff);
  }
}

// ── Grid Card ─────────────────────────────────────────────────────────────────

class MinerGridCard extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  final double earningsPerDay;
  final VoidCallback onTap;
  final bool showDeleteBadge;
  final VoidCallback? onDeleteTap;
  final VoidCallback onLongPress;

  const MinerGridCard({
    super.key,
    required this.miner,
    this.stats,
    this.earningsPerDay = 0,
    required this.onTap,
    this.showDeleteBadge = false,
    this.onDeleteTap,
    required this.onLongPress,
  });

  @override
  State<MinerGridCard> createState() => _MinerGridCardState();
}

class _MinerGridCardState extends State<MinerGridCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color _statusAccent(MinerStatus s) => switch (s) {
        MinerStatus.online => const Color(0xFF39d353),
        MinerStatus.warning => const Color(0xFFffd700),
        MinerStatus.offline => const Color(0xFFff4d4d),
        _ => const Color(0xFF6e7681),
      };

  Color _tempColor(double t) {
    if (t > 85) return const Color(0xFFff4d4d);
    if (t > 75) return const Color(0xFFffd700);
    return const Color(0xFF6e7681);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final status = s?.status ?? MinerStatus.unknown;
    final accentColor = _statusAccent(status);
    final trend = s?.trendDirection ?? 0;

    return GestureDetector(
      onTap: widget.showDeleteBadge ? null : widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1a1f2e), Color(0xFF252b3b)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: accentColor, width: 3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: icon + name + status dot
                  Row(children: [
                    MinerIcon(type: widget.miner.type, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.miner.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFFe6edf3),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _PulseDot(status: status, pulseAnim: _pulseAnim),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    widget.miner.ip,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF6e7681),
                      fontFamily: 'Courier',
                    ),
                  ),
                  const Spacer(),
                  // Hashrate hero + trend
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          s?.hashrateFormatted ?? '--',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF39d353),
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                      if (trend != 0)
                        Icon(
                          trend > 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 14,
                          color: trend > 0
                              ? const Color(0xFF39d353)
                              : const Color(0xFFff4d4d),
                        ),
                    ],
                  ),
                  // Sparkline
                  if (s != null && s.hashrateHistory.length >= 2) ...[
                    const SizedBox(height: 4),
                    Sparkline(
                      data: s.hashrateHistory,
                      height: 20,
                      color: trend < 0
                          ? const Color(0xFFff4d4d)
                          : const Color(0xFF39d353),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // 4 mini stats
                  Row(children: [
                    _MiniStat(
                        icon: Icons.thermostat_outlined,
                        value: s != null && s.outTemp > 0
                            ? '${s.outTemp.toInt()}°'
                            : '--',
                        color: _tempColor(s?.outTemp ?? 0)),
                    const SizedBox(width: 6),
                    _MiniStat(
                        icon: Icons.air,
                        value: s != null && s.fanPercent > 0
                            ? '${s.fanPercent}%'
                            : '--',
                        color: const Color(0xFF58a6ff)),
                    const SizedBox(width: 6),
                    _MiniStat(
                        icon: Icons.check_circle_outline,
                        value: '${s?.accepted ?? 0}',
                        color: const Color(0xFF3fb950)),
                    const SizedBox(width: 6),
                    _MiniStat(
                        icon: Icons.access_time,
                        value: s != null && s.uptime > 0
                            ? s.uptimeFormatted
                            : '--',
                        color: const Color(0xFF8b949e)),
                  ]),
                  // Pool footer
                  if (s != null && s.pools.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.pools.where((p) => p.active).firstOrNull?.host ??
                          s.pools.first.host,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF6e7681),
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Earnings pill
                  if (widget.earningsPerDay > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf7931a).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '\$${widget.earningsPerDay.toStringAsFixed(2)}/d',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFf7931a),
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Delete badge overlay
          if (widget.showDeleteBadge)
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDeleteTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFff4d4d).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(Icons.delete_outline,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Quick Actions Bottom Sheet ─────────────────────────────────────────────────

class _QuickActionsSheet extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  final MinerStore store;

  const _QuickActionsSheet({
    required this.miner,
    required this.stats,
    required this.store,
  });

  @override
  State<_QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<_QuickActionsSheet> {
  bool _loading = false;
  String? _result;

  Future<bool> _restart() async {
    if (widget.miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.restart(widget.miner.ip, widget.miner.port);
    }
    return CGMinerAPI.instance.restart(widget.miner.ip, widget.miner.port);
  }

  Future<bool> _pause() async {
    if (widget.miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.pause(widget.miner.ip, widget.miner.port);
    }
    return false; // CGMiner doesn't have a pause command
  }

  Future<bool> _resume() async {
    if (widget.miner.type.apiType == ApiType.espMinerHttp) {
      return EspMinerAPI.instance.resume(widget.miner.ip, widget.miner.port);
    }
    return false;
  }

  Future<void> _action(Future<bool> Function() fn, String successMsg) async {
    setState(() { _loading = true; _result = null; });
    final ok = await fn();
    if (mounted) {
      setState(() {
        _loading = false;
        _result = ok ? '✅ $successMsg' : '❌ Command failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEsp = widget.miner.type.apiType == ApiType.espMinerHttp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF30363D),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.miner.name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFFe6edf3),
            ),
          ),
          Text(
            widget.miner.ip,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6e7681)),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: CircularProgressIndicator(
                  color: Color(0xFFF7931A), strokeWidth: 2),
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_result!,
                style: TextStyle(
                  fontSize: 13,
                  color: _result!.startsWith('✅')
                      ? const Color(0xFF39d353)
                      : const Color(0xFFf85149),
                )),
            ),
          // Pause / Resume (ESP-Miner only)
          if (isEsp) ...[
            _SheetAction(
              icon: Icons.pause_circle_outline,
              label: 'Pause Mining',
              color: const Color(0xFF8b949e),
              onTap: _loading ? null : () => _action(_pause, 'Mining paused'),
            ),
            _SheetAction(
              icon: Icons.play_circle_outline,
              label: 'Resume Mining',
              color: const Color(0xFF39d353),
              onTap: _loading ? null : () => _action(_resume, 'Mining resumed'),
            ),
          ],
          _SheetAction(
            icon: Icons.restart_alt,
            label: 'Restart Miner',
            color: const Color(0xFFffd700),
            onTap: _loading ? null : () => _action(_restart, 'Restart sent'),
          ),
          _SheetAction(
            icon: Icons.dns_outlined,
            label: 'Edit Pools',
            color: const Color(0xFF58a6ff),
            onTap: () {
              Navigator.pop(context);
              // Navigation handled by parent
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Open miner detail to edit pools'),
                  backgroundColor: Color(0xFF21262D),
                ),
              );
            },
          ),
          _SheetAction(
            icon: Icons.delete_outline,
            label: 'Delete Miner',
            color: const Color(0xFFf85149),
            onTap: () {
              Navigator.pop(context);
              final index = widget.store.miners.indexOf(widget.miner);
              widget.store.remove(widget.miner.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${widget.miner.name} removed'),
                  backgroundColor: const Color(0xFF21262D),
                  action: SnackBarAction(
                    label: 'UNDO',
                    textColor: const Color(0xFFF7931A),
                    onPressed: () => widget.store.reinsert(widget.miner, index),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.3)),
          backgroundColor: color.withOpacity(0.07),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    ),
  );
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final MinerStatus status;
  final Animation<double> pulseAnim;
  const _StatusBadge({required this.status, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MinerStatus.online => const Color(0xFF39d353),
      MinerStatus.warning => const Color(0xFFffd700),
      MinerStatus.offline => const Color(0xFFff4d4d),
      _ => const Color(0xFF6e7681),
    };
    final label = switch (status) {
      MinerStatus.online => 'ONLINE',
      MinerStatus.warning => 'WARN',
      MinerStatus.offline => 'OFFLINE',
      _ => 'UNKNOWN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status == MinerStatus.online)
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withOpacity(pulseAnim.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.6 * pulseAnim.value),
                    blurRadius: 4,
                  )
                ],
              ),
            ),
          )
        else
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.8,
            )),
      ]),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final MinerStatus status;
  final Animation<double> pulseAnim;
  const _PulseDot({required this.status, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MinerStatus.online => const Color(0xFF39d353),
      MinerStatus.warning => const Color(0xFFffd700),
      MinerStatus.offline => const Color(0xFFff4d4d),
      _ => const Color(0xFF6e7681),
    };
    if (status == MinerStatus.online) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, __) => Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: color.withOpacity(pulseAnim.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)
            ],
          ),
        ),
      );
    }
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  final int? trend;

  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.trend,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: color.withOpacity(0.7)),
                if (trend != null && trend != 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    trend! > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 10,
                    color: trend! > 0
                        ? const Color(0xFF39d353)
                        : const Color(0xFFff4d4d),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFamily: 'Courier',
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFF6e7681),
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 38, color: const Color(0xFF21262d));
}
