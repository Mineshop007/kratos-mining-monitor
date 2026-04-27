import 'package:flutter/material.dart';
import '../models/miner.dart';

// ── List Card ─────────────────────────────────────────────────────────────────

class MinerCard extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  final VoidCallback onTap;

  const MinerCard({super.key, required this.miner, this.stats, required this.onTap});

  @override
  State<MinerCard> createState() => _MinerCardState();
}

class _MinerCardState extends State<MinerCard> with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final status = s?.status ?? MinerStatus.unknown;
    final accentColor = _statusAccent(status);

    return GestureDetector(
      onTap: widget.onTap,
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
              Expanded(child: _CardContent(
                miner: widget.miner,
                stats: s,
                status: status,
                pulseAnim: _pulseAnim,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusAccent(MinerStatus s) => switch (s) {
    MinerStatus.online  => const Color(0xFF39d353),
    MinerStatus.warning => const Color(0xFFffd700),
    MinerStatus.offline => const Color(0xFFff4d4d),
    _                   => const Color(0xFF6e7681),
  };
}

class _CardContent extends StatelessWidget {
  final Miner miner;
  final MinerStats? stats;
  final MinerStatus status;
  final Animation<double> pulseAnim;

  const _CardContent({
    required this.miner,
    required this.stats,
    required this.status,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            // Miner type icon in a small badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0d1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Center(
                child: Text(miner.type.icon,
                  style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miner.name,
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
                  Text(miner.ip,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6e7681),
                      fontFamily: 'Courier',
                    ),
                  ),
                  if (s != null && s.pools.isNotEmpty) ...[
                    const Text('  ·  ', style: TextStyle(color: Color(0xFF30363D), fontSize: 11)),
                    Flexible(child: Text(
                      _poolHost(s.pools),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6e7681)),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ],
                ]),
              ],
            )),
            const SizedBox(width: 8),
            _StatusBadge(status: status, pulseAnim: pulseAnim),
          ]),
        ),

        // Divider
        Container(height: 1, color: const Color(0xFF21262d)),

        // Stats row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            _StatCell(
              label: 'HASHRATE',
              value: s?.hashrateFormatted ?? '--',
              color: const Color(0xFF39d353),
              icon: Icons.flash_on,
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
              value: s != null && s.fanRPM > 0 ? '${s.fanRPM}r' : '--',
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
        ),
      ],
    );
  }

  Color _tempColor(double t) {
    if (t > 85) return const Color(0xFFff4d4d);
    if (t > 75) return const Color(0xFFffd700);
    return const Color(0xFF6e7681);
  }

  String _poolHost(List<PoolInfo> pools) {
    final active = pools.where((p) => p.active).firstOrNull ?? pools.first;
    final clean = active.cleanUrl;
    // Show just the hostname part
    final parts = clean.split(':');
    return parts.first;
  }
}

// ── Grid Card ─────────────────────────────────────────────────────────────────

class MinerGridCard extends StatefulWidget {
  final Miner miner;
  final MinerStats? stats;
  final VoidCallback onTap;
  final bool showDeleteBadge;
  final VoidCallback? onDeleteTap;
  final VoidCallback onLongPress;

  const MinerGridCard({
    super.key,
    required this.miner,
    this.stats,
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

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final status = s?.status ?? MinerStatus.unknown;
    final accentColor = _statusAccent(status);

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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(widget.miner.type.icon,
                      style: const TextStyle(fontSize: 16)),
                    const Spacer(),
                    // Status dot
                    if (status == MinerStatus.online)
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Opacity(
                          opacity: _pulseAnim.value,
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                color: accentColor.withOpacity(0.6),
                                blurRadius: 6,
                              )],
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ]),
                  const Spacer(),
                  Text(
                    widget.miner.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFFe6edf3),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s?.hashrateFormatted ?? '--',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF39d353),
                      fontFamily: 'Courier',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.thermostat_outlined,
                      size: 11, color: Color(0xFF6e7681)),
                    const SizedBox(width: 2),
                    Text(
                      s != null && s.outTemp > 0 ? '${s.outTemp.toInt()}°C' : '--',
                      style: TextStyle(
                        fontSize: 11,
                        color: _tempColor(s?.outTemp ?? 0),
                        fontFamily: 'Courier',
                      ),
                    ),
                  ]),
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

  Color _statusAccent(MinerStatus s) => switch (s) {
    MinerStatus.online  => const Color(0xFF39d353),
    MinerStatus.warning => const Color(0xFFffd700),
    MinerStatus.offline => const Color(0xFFff4d4d),
    _                   => const Color(0xFF6e7681),
  };

  Color _tempColor(double t) {
    if (t > 85) return const Color(0xFFff4d4d);
    if (t > 75) return const Color(0xFFffd700);
    return const Color(0xFF6e7681);
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final MinerStatus status;
  final Animation<double> pulseAnim;
  const _StatusBadge({required this.status, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MinerStatus.online  => const Color(0xFF39d353),
      MinerStatus.warning => const Color(0xFFffd700),
      MinerStatus.offline => const Color(0xFFff4d4d),
      _                   => const Color(0xFF6e7681),
    };
    final label = switch (status) {
      MinerStatus.online  => 'ONLINE',
      MinerStatus.warning => 'WARN',
      MinerStatus.offline => 'OFFLINE',
      _                   => 'UNKNOWN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.15),
          blurRadius: 8,
          spreadRadius: 1,
        )],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status == MinerStatus.online)
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: color.withOpacity(pulseAnim.value),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: color.withOpacity(0.6 * pulseAnim.value),
                  blurRadius: 4,
                )],
              ),
            ),
          )
        else
          Container(width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.8,
        )),
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCell({required this.label, required this.value,
    required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 13, color: color.withOpacity(0.7)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: color,
        fontFamily: 'Courier',
      )),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
        fontSize: 8,
        color: Color(0xFF6e7681),
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      )),
    ],
  ));
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
    Container(width: 1, height: 38, color: const Color(0xFF21262d));
}
