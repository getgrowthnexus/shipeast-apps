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
import '../widgets/se_card.dart';
import '../widgets/se_page.dart';
import '../widgets/se_step_tracker.dart';
import '../widgets/se_toast.dart';
import 'welcome_screen.dart';

/// Where an applicant waits, and where an unapproved driver lands on launch.
///
/// 2026 rebuild. This was the last screen in the app still building its own
/// chrome: a bare blush scaffold with no cap, everything centred, and a pulsing
/// medallion made of `logo.png` inside a white circle inside a tinted circle —
/// a logo in a box on a box, the exact pattern the splash rebuild threw out for
/// reading as a placeholder rather than as a brand. It now sits on the same cap
/// and sheet as every other screen, and the status it is reporting is stated in
/// the cap instead of being decorated below it.
///
/// The tracker is the hero here. It is the only thing on the screen that
/// answers the question the applicant actually has — where in the queue am I —
/// so it gets the sheet to itself rather than third billing under an animation.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  bool get _approved => _status == 'approved';
  bool get _rejected => _status == 'rejected';
  // DV-2: an approved driver the admin has temporarily stopped, vs. a hard
  // conduct/safety suspension. Both land here; the copy differs.
  bool get _paused => _status == 'paused';
  bool get _suspended => _status == 'suspended';

  /// Sign out for real.
  ///
  /// This button used to say "Back to Login" and push the login screen without
  /// touching the session — so the applicant was still authenticated, and the
  /// next launch resolved their status and dropped them straight back here.
  /// A way out that does not let you out is worse than no button.
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  ({Color hue, Color tint, IconData icon, String label}) get _badge {
    if (_approved) {
      return (
        hue: SeColors.successInk,
        tint: SeColors.successSoft,
        icon: SeIcons.checkCircle,
        label: 'Approved — opening your dashboard'
      );
    }
    if (_suspended) {
      return (
        hue: SeColors.dangerInk,
        tint: SeColors.dangerSoft,
        icon: SeIcons.warningCircle,
        label: 'Account suspended'
      );
    }
    if (_paused) {
      return (
        hue: SeColors.warningInk,
        tint: SeColors.warningSoft,
        icon: SeIcons.pause,
        label: 'Account paused'
      );
    }
    if (_rejected) {
      return (
        hue: SeColors.dangerInk,
        tint: SeColors.dangerSoft,
        icon: SeIcons.warningCircle,
        label: 'Application not approved'
      );
    }
    return (
      hue: SeColors.warningInk,
      tint: SeColors.warningSoft,
      icon: SeIcons.hourglass,
      label: 'Under review'
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;

    return SePageScaffold(
      // No back button: an applicant has nowhere to go back TO, and the only
      // way off this screen is forward (approval) or out (sign out).
      showBack: false,
      title: _approved
          ? "You're approved"
          : _suspended
              ? 'Account suspended'
              : _paused
                  ? 'Account paused'
                  : _rejected
                      ? 'Application declined'
                      : 'Application submitted',
      subtitle: _approved
          ? 'Everything checks out. Taking you to your dashboard…'
          : _suspended
              ? 'Your ShipEast driver account has been suspended and you '
                  'cannot accept deliveries. Contact ShipEast support to find '
                  'out more.'
              : _paused
                  ? 'Your account is paused, so you are not receiving delivery '
                      'requests right now. This screen updates the moment it '
                      'is reactivated — no need to reopen the app.'
                  : _rejected
                      ? 'Dispatch could not approve this application.'
                      : 'This screen updates the moment a decision is made — '
                          'there is no need to reopen the app.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x6, SeSpacing.gutter, SeSpacing.x8),
        children: [
          // The live pill. It is the one element on the page that changes
          // without the applicant doing anything, so it leads.
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: SeMotion.base,
              curve: SeMotion.emphasized,
              padding: const EdgeInsets.symmetric(
                  horizontal: SeSpacing.x4, vertical: SeSpacing.x2),
              decoration: BoxDecoration(
                color: badge.tint,
                borderRadius: SeRadius.pill,
                border: Border.all(color: badge.hue.withValues(alpha: 0.28)),
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
          ),
          const SizedBox(height: SeSpacing.x5),

          // The application tracker only makes sense for a new applicant.
          // A paused or suspended driver already cleared it.
          if (!_paused && !_suspended && !_rejected) ...[
            const SeSectionTitle(title: 'Where you are'),
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: SeStepTracker(
                current: _approved ? 2 : 1,
                allComplete: _approved,
                steps: const [
                  SeStep('Application received',
                      caption: 'We have your registration details'),
                  SeStep('Background check',
                      caption: 'Dispatch is reviewing your documents'),
                  SeStep('Account activated',
                      caption: 'Start accepting deliveries'),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x5),
          ],

          if (_rejected)
            SeNotice.danger(
              'Contact ShipEast dispatch for the details, or apply again with '
              'corrected documents.',
            )
          else if (!_paused && !_suspended)
            SeNotice.info(
              'Applications are reviewed by our team before drivers are '
              'approved to begin accepting deliveries',
            ),
          const SizedBox(height: SeSpacing.x8),

          SeButton(
            label: 'Sign out',
            variant: SeButtonVariant.ghost,
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }
}
