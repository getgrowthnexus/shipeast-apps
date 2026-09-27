import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_typography.dart';

/// Sweeping countdown ring for the incoming-order screen (PLAN §3.2).
///
/// Replaces the stepped 60→0 text with a continuous conic sweep whose colour
/// travels white → amber → danger as time runs out, so urgency is legible at a
/// glance without reading the number.
///
/// [remaining] is the authoritative value (driven by the screen's 1s tick);
/// this widget interpolates *between* ticks so the arc glides rather than
/// jumping a sixtieth each second.
class SeCountdownRing extends StatefulWidget {
  final int remaining;
  final int total;
  final double size;

  /// On the brand shell the track has to be light; on a sheet card, dark.
  final bool onShell;

  const SeCountdownRing({
    super.key,
    required this.remaining,
    this.total = 60,
    this.size = 168,
    this.onShell = true,
  });

  @override
  State<SeCountdownRing> createState() => _SeCountdownRingState();
}

class _SeCountdownRingState extends State<SeCountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    // One-second loop that smooths the arc between authoritative ticks.
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SeCountdownRing old) {
    super.didUpdateWidget(old);
    if (old.remaining != widget.remaining) _tick.forward(from: 0);
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final total = widget.total <= 0 ? 1 : widget.total;
        // Glide from `remaining` toward `remaining - 1` across the second.
        final smooth =
            (widget.remaining - _tick.value).clamp(0.0, total.toDouble());
        final progress = smooth / total;

        // Colour travels with urgency, not with the brand.
        final Color arc = progress > 0.5
            ? SeColors.shellInk
            : progress > 0.25
                ? Color.lerp(SeColors.warning, SeColors.shellInk,
                    (progress - 0.25) / 0.25)!
                : Color.lerp(SeColors.danger, SeColors.warning,
                    progress / 0.25)!;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: progress,
              arc: arc,
              track: widget.onShell
                  ? Colors.white.withValues(alpha: 0.22)
                  : SeColors.ink200,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.remaining}',
                    style: SeType.tabular(SeType.display).copyWith(
                      color: widget.onShell ? SeColors.shellInk : SeColors.ink900,
                      fontSize: widget.size * 0.30,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    'SECONDS',
                    style: SeType.eyebrow.copyWith(
                      color: widget.onShell
                          ? SeColors.shellInk.withValues(alpha: 0.78)
                          : SeColors.ink500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color arc;
  final Color track;

  _RingPainter({
    required this.progress,
    required this.arc,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Sweep anticlockwise from 12 o'clock so the ring "drains".
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      -2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.arc != arc || old.track != track;
}
