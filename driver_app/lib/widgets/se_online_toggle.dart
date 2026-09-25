import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// The three states the driver can be in. `delivering` is derived (an active
/// order exists) and is not directly togglable.
enum DriverPresence { offline, online, delivering }

/// Hero online/offline control (PLAN §3.2 — Dashboard).
///
/// The single most-used control in the app, so it earns real weight: a large
/// tappable slab whose ground shifts ink → Ember → Sunset as presence changes,
/// with a spring-settled knob, haptic confirmation and a status word that
/// morphs OFFLINE ↔ ONLINE ↔ DELIVERING. Reduced-motion collapses the spring
/// to a cross-fade.
class SeOnlineToggle extends StatefulWidget {
  final DriverPresence presence;

  /// Called with the requested online state. Not called while `delivering`.
  final ValueChanged<bool> onChanged;

  /// Disables interaction while a write is in flight.
  final bool busy;

  const SeOnlineToggle({
    super.key,
    required this.presence,
    required this.onChanged,
    this.busy = false,
  });

  @override
  State<SeOnlineToggle> createState() => _SeOnlineToggleState();
}

class _SeOnlineToggleState extends State<SeOnlineToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _knob;
  bool _down = false;

  bool get _isOn => widget.presence != DriverPresence.offline;
  bool get _locked =>
      widget.busy || widget.presence == DriverPresence.delivering;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: SeMotion.slow,
      value: _isOn ? 1 : 0,
    );
    // Spring settle on the knob; the track colour uses the plain curve so it
    // never overshoots into an off-ramp hue.
    _knob = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
  }

  @override
  void didUpdateWidget(covariant SeOnlineToggle old) {
    super.didUpdateWidget(old);
    if (_isOn != (old.presence != DriverPresence.offline)) {
      if (SeMotion.reduced(context)) {
        _ctrl.value = _isOn ? 1 : 0;
      } else {
        _isOn ? _ctrl.forward() : _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  ({String word, String hint, Gradient ground, Color glow}) get _spec =>
      switch (widget.presence) {
        DriverPresence.offline => (
            word: 'OFFLINE',
            hint: 'Go online to start receiving delivery requests',
            ground: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeColors.ink700, SeColors.ink900],
            ),
            glow: SeColors.ink900,
          ),
        DriverPresence.online => (
            word: 'ONLINE',
            hint: 'You are visible to dispatch',
            ground: SeColors.emberGradient,
            glow: SeColors.red500,
          ),
        DriverPresence.delivering => (
            word: 'DELIVERING',
            hint: 'Finish your active order to go idle',
            ground: SeColors.sunsetGradient,
            glow: SeColors.sunset.first,
          ),
      };

  void _handleTap() {
    if (_locked) return;
    HapticFeedback.mediumImpact();
    widget.onChanged(!_isOn);
  }

  @override
  Widget build(BuildContext context) {
    final s = _spec;
    final reduced = SeMotion.reduced(context);
    final scale = (_down && !reduced && !_locked) ? 0.98 : 1.0;

    return GestureDetector(
      onTapDown: _locked ? null : (_) => setState(() => _down = true),
      onTapUp: _locked ? null : (_) => setState(() => _down = false),
      onTapCancel: _locked ? null : () => setState(() => _down = false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: scale,
        duration: SeMotion.instant,
        curve: SeMotion.emphasized,
        child: AnimatedContainer(
          duration: SeMotion.base,
          curve: SeMotion.emphasized,
          padding: const EdgeInsets.all(SeSpacing.x5),
          decoration: BoxDecoration(
            gradient: s.ground,
            borderRadius: SeRadius.all(SeRadius.lg),
            boxShadow: _down
                ? SeElevation.e0
                : SeElevation.glowColor(s.glow, opacity: 0.24),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('DRIVER STATUS',
                        style: SeType.eyebrow.copyWith(
                            color: Colors.white.withValues(alpha: 0.72))),
                    const SizedBox(height: SeSpacing.x2),
                    // The status word morphs rather than hard-cuts.
                    AnimatedSwitcher(
                      duration: reduced ? Duration.zero : SeMotion.base,
                      switchInCurve: SeMotion.decelerate,
                      switchOutCurve: SeMotion.accelerate,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        s.word,
                        key: ValueKey(s.word),
                        style: SeType.h1.copyWith(
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: SeSpacing.x1),
                    Text(
                      s.hint,
                      style: SeType.bodyS
                          .copyWith(color: Colors.white.withValues(alpha: 0.82)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SeSpacing.x4),
              _Knob(animation: _knob, locked: _locked, busy: widget.busy),
            ],
          ),
        ),
      ),
    );
  }
}

/// The physical-feeling switch: a 34dp puck that springs across a 76dp track.
class _Knob extends StatelessWidget {
  final Animation<double> animation;
  final bool locked;
  final bool busy;

  const _Knob({
    required this.animation,
    required this.locked,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    const trackW = 76.0;
    const trackH = 42.0;
    const puck = 34.0;
    const inset = (trackH - puck) / 2;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // easeOutBack can exceed [0,1]; clamp so the puck stays on its track.
        final t = animation.value.clamp(0.0, 1.0);
        return Container(
          width: trackW,
          height: trackH,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: SeRadius.pill,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Stack(
            children: [
              Positioned(
                left: inset + t * (trackW - puck - inset * 2),
                top: inset,
                child: Container(
                  width: puck,
                  height: puck,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: SeElevation.e2,
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(SeColors.red500),
                          ),
                        )
                      : Icon(
                          locked ? SeIcons.bike : SeIcons.power,
                          size: 18,
                          color: Color.lerp(
                              SeColors.ink400, SeColors.red500, t),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
