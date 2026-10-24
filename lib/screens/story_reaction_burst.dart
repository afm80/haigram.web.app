import 'dart:math' as math;

import 'package:flutter/material.dart';

/// يُظهر انفجاراً قصيراً من الإيموجي يرتفع فوق الشاشة (كتفاعل القصص في إنستغرام).
/// لا يلتقط اللمس، ويزيل نفسه بعد انتهاء الحركة.
void showEmojiBurst(BuildContext context, String emoji) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _EmojiBurst(emoji: emoji, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Particle {
  final double dx; // -1..1 انحراف أفقي
  final double delay; // 0..0.3 من مدة الحركة
  final double size;
  final double wobble;
  _Particle(this.dx, this.delay, this.size, this.wobble);
}

class _EmojiBurst extends StatefulWidget {
  final String emoji;
  final VoidCallback onDone;
  const _EmojiBurst({required this.emoji, required this.onDone});

  @override
  State<_EmojiBurst> createState() => _EmojiBurstState();
}

class _EmojiBurstState extends State<_EmojiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _ps = List.generate(
        9,
        (i) => _Particle((r.nextDouble() - 0.5) * 2, r.nextDouble() * 0.3,
            26 + r.nextDouble() * 24, r.nextDouble() * math.pi * 2));
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(
            children: [
              for (final p in _ps) _particle(p, w, h),
            ],
          ),
        );
      }),
    );
  }

  Widget _particle(_Particle p, double w, double h) {
    final t = ((_c.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0).toDouble();
    if (t <= 0) return const SizedBox.shrink();
    final rise = Curves.easeOut.transform(t);
    final y = h - 110 - rise * h * 0.5;
    final x = w / 2 +
        p.dx * w * 0.38 * (0.25 + rise) +
        math.sin(t * 6 + p.wobble) * 10;
    final opacity = t < 0.65 ? 1.0 : ((1 - t) / 0.35).clamp(0.0, 1.0).toDouble();
    final scale = 0.5 + 0.7 * Curves.easeOutBack.transform(math.min(t * 3, 1.0));
    return Positioned(
      left: x - p.size,
      top: y,
      width: p.size * 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Center(
            child: Text(widget.emoji,
                style: TextStyle(
                    fontSize: p.size,
                    decoration: TextDecoration.none,
                    color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
