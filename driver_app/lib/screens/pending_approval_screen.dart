import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/driver_firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_step_tracker.dart';
import '../widgets/se_toast.dart';
import 'login_screen.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _watchStatus();
  }

  /// Audit §7.5: this screen used to be a dead end — a driver approved while
  /// looking at it had to force-quit the app. It now watches its own status
  /// doc, so approval advances the tracker and unlocks the app in place.
  void _watchStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _statusSub = DriverFirestoreService.driverStream(uid).listen(
      (doc) {
        if (!mounted) return;
        final next = doc.data()?['status'] as String? ?? 'pending';
        if (next == _status) return;
        setState(() => _status = next);

        if (next == 'approved') {
          // Let the tracker's completion animation land before routing.
          Future.delayed(SeMotion.deliberate, () {
            if (!mounted) return;
            Navigator.pushNamedAndRemoveUntil(
                context, '/dashboard', (route) => false);
          });
        }
      },
      onError: (_) {
        // A rules/network error must not leave the screen looking "live".
        if (mounted) SeToast.error(context, 'Could not check approval status.');
      },
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _approved => _status == 'approved';
  bool get _rejected => _status == 'rejected';
  // DV-2: an approved driver the admin has temporarily stopped, vs. a hard
  // conduct/safety suspension. Both land here; the copy differs.
  bool get _paused => _status == 'paused';
  bool get _suspended => _status == 'suspended';

  ({Color hue, Color tint, IconData icon, String label}) get _badge {
    if (_approved) {
      return (
        hue: SeColors.success,
        tint: SeColors.successTint,
        icon: SeIcons.checkCircle,
        label: 'Approved — opening your dashboard'
      );
    }
    if (_suspended) {
      return (
        hue: SeColors.danger,
        tint: SeColors.dangerTint,
        icon: SeIcons.warningCircle,
        label: 'Account suspended'
      );
    }
    if (_paused) {
      return (
        hue: SeColors.warning,
        tint: SeColors.warningTint,
        icon: SeIcons.pause,
        label: 'Account paused'
      );
    }
    if (_rejected) {
      return (
        hue: SeColors.danger,
        tint: SeColors.dangerTint,
        icon: SeIcons.warningCircle,
        label: 'Application not approved'
      );
    }
    return (
      hue: SeColors.warning,
      tint: SeColors.warningTint,
      icon: SeIcons.hourglass,
      label: 'Application under review'
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;

    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: SeSpacing.x6),
          child: Column(
            children: [
              const SizedBox(height: SeSpacing.x10),

              // ── Pulsing brand medallion ─────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(
                  scale: SeMotion.reduced(context) ? 1.0 : _pulseAnim.value,
                  child: child,
                ),
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: badge.tint,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: SeColors.surface0,
                        shape: BoxShape.circle,
                        boxShadow: SeElevation.e2,
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(SeSpacing.x3),
                          child: Image.asset('assets/logo.png',
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SeSpacing.x8),

              // ── Live status pill ────────────────────────────────────────
              AnimatedContainer(
                duration: SeMotion.base,
                curve: SeMotion.emphasized,
                padding: const EdgeInsets.symmetric(
                    horizontal: SeSpacing.x4, vertical: SeSpacing.x2),
                decoration: BoxDecoration(
                  color: badge.tint,
                  borderRadius: SeRadius.pill,
                  border: Border.all(
                      color: badge.hue.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icon, color: badge.hue, size: 16),
                    const SizedBox(width: SeSpacing.x2),
                    Text(badge.label,
                        style: SeType.label.copyWith(color: badge.hue)),
                  ],
                ),
              ),
              const SizedBox(height: SeSpacing.x5),

              Text(
                _approved
                    ? 'You\'re approved!'
                    : _suspended
                        ? 'Account suspended'
                        : _paused
                            ? 'Account paused'
                            : _rejected
                                ? 'Application declined'
                                : 'Application submitted',
                textAlign: TextAlign.center,
                style: SeType.display,
              ),
              const SizedBox(height: SeSpacing.x3),
              Text(
                _approved
                    ? 'Everything checks out. Taking you to your dashboard…'
                    : _suspended
                        ? 'Your ShipEast driver account has been suspended and you cannot accept deliveries. Contact ShipEast support to find out more.'
                        : _paused
                            ? 'Your account is paused, so you are not receiving delivery requests right now. This screen updates the moment it is reactivated — no need to reopen the app.'
                            : _rejected
                                ? 'Our team could not approve this application. Contact ShipEast support for the details.'
                                : 'Your driver application is with our team. This screen updates the moment a decision is made — no need to reopen the app.',
                textAlign: TextAlign.center,
                style: SeType.body.copyWith(color: SeColors.ink500),
              ),
              const SizedBox(height: SeSpacing.x8),

              // ── Live tracker ────────────────────────────────────────────
              // The application tracker only makes sense for a new applicant.
              // A paused or suspended driver already cleared it.
              if (!_paused && !_suspended && !_rejected)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(SeSpacing.x5),
                  decoration: BoxDecoration(
                    color: SeColors.surface0,
                    borderRadius: SeRadius.all(SeRadius.lg),
                    boxShadow: SeElevation.e1,
                  ),
                  child: SeStepTracker(
                    current: _approved ? 2 : 1,
                    allComplete: _approved,
                    steps: const [
                      SeStep('Application received',
                          caption: 'We have your registration details'),
                      SeStep('Background check',
                          caption: 'Our team is reviewing your documents'),
                      SeStep('Account activated',
                          caption: 'Start accepting deliveries'),
                    ],
                  ),
                ),
              const SizedBox(height: SeSpacing.x8),

              SeButton(
                label: 'Back to Login',
                variant: SeButtonVariant.ghost,
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: SeSpacing.x3),
              Text(
                'Applications are reviewed by our team before drivers are approved to begin accepting deliveries',
                textAlign: TextAlign.center,
                style: SeType.bodyS.copyWith(color: SeColors.ink400),
              ),
              const SizedBox(height: SeSpacing.x8),
            ],
          ),
        ),
      ),
    );
  }
}
