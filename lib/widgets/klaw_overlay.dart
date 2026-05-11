import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/klaw_service.dart';
import 'klaw.dart';

/// Global KLAW pop-up overlay — wrap [MaterialApp]'s builder with this.
/// Fires automatically on a timer; screens call [KlawService.instance.trigger]
/// for celebrations or context-specific messages.
class KlawGlobalOverlay extends StatefulWidget {
  final Widget child;
  const KlawGlobalOverlay({super.key, required this.child});

  @override
  State<KlawGlobalOverlay> createState() => _KlawGlobalOverlayState();
}

class _KlawGlobalOverlayState extends State<KlawGlobalOverlay> {
  @override
  void initState() {
    super.initState();
    // Start the auto-fire timer once the widget is alive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KlawService.instance.startAuto();
    });
  }

  @override
  void dispose() {
    KlawService.instance.stopAuto();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // KLAW floats above everything
        ChangeNotifierProvider.value(
          value: KlawService.instance,
          child: Consumer<KlawService>(
            builder: (_, svc, __) => _KlawPopup(
              visible: svc.isVisible,
              message: svc.currentMessage,
              position: svc.position,
              onDismiss: svc.dismiss,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _KlawPopup extends StatefulWidget {
  final bool visible;
  final String message;
  final int position;
  final VoidCallback onDismiss;

  const _KlawPopup({
    required this.visible,
    required this.message,
    required this.position,
    required this.onDismiss,
  });

  @override
  State<_KlawPopup> createState() => _KlawPopupState();
}

class _KlawPopupState extends State<_KlawPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _wobble;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _wobble = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void didUpdateWidget(_KlawPopup old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _ctrl.forward(from: 0);
    } else if (!widget.visible) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Position mapping
    double? left, right, top, bottom;
    bool bubbleRight;

    switch (widget.position) {
      case 0: // bottom-left
        left = 14;
        bottom = 88;
        bubbleRight = true;
        break;
      case 1: // bottom-right
        right = 14;
        bottom = 88;
        bubbleRight = false;
        break;
      case 2: // left-mid
        left = 14;
        top = size.height * 0.36;
        bubbleRight = true;
        break;
      case 3: // right-mid
      default:
        right = 14;
        top = size.height * 0.36;
        bubbleRight = false;
        break;
    }

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: ScaleTransition(
          scale: _scale,
          alignment:
              bubbleRight ? Alignment.bottomLeft : Alignment.bottomRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bubbleRight
                ? [
                    _KlawCharacter(wobble: _wobble),
                    const SizedBox(width: 6),
                    _KlawBubble(
                        message: widget.message, pointLeft: bubbleRight),
                  ]
                : [
                    _KlawBubble(
                        message: widget.message, pointLeft: bubbleRight),
                    const SizedBox(width: 6),
                    _KlawCharacter(wobble: _wobble),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── KLAW character with glow + wobble ────────────────────────────────────────

class _KlawCharacter extends StatelessWidget {
  final Animation<double> wobble;
  const _KlawCharacter({required this.wobble});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: wobble,
      builder: (_, child) {
        final dy = math.sin(wobble.value * math.pi * 3) * 5;
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: const Klaw(size: 64, glow: false),
    );
  }
}

// ── Speech bubble with 3D depth ───────────────────────────────────────────────

class _KlawBubble extends StatelessWidget {
  final String message;
  final bool pointLeft;

  const _KlawBubble({required this.message, required this.pointLeft});

  @override
  Widget build(BuildContext context) {
    // Clean dark pill — no border, no glow, no lines. Just text.
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6121220), // ~90% opaque near-black
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFF2F2FF),
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.0,
          ),
        ),
      ),
    );
  }
}


