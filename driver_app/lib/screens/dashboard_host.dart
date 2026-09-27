import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import 'dashboard_screen.dart';
import 'earnings_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// The signed-in app: four tabs behind one nav bar.
///
/// Lives here rather than in `main.dart` because the splash screen has to be
/// able to route to it, and a screen reaching back into `main.dart` for a
/// widget is the kind of import loop that only gets worse.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  final ValueNotifier<String> _driverNameNotifier =
      ValueNotifier<String>('Driver');

  @override
  void initState() {
    super.initState();
    _loadDriverName();
  }

  Future<void> _loadDriverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        _driverNameNotifier.value = doc.data()?['name'] as String? ?? 'Driver';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _driverNameNotifier.dispose();
    super.dispose();
  }

  static const List<Map<String, dynamic>> _navItems = [
    {'label': 'Home', 'icon': SeIcons.home, 'active': SeIcons.homeFill},
    {'label': 'History', 'icon': SeIcons.history, 'active': SeIcons.history},
    {'label': 'Earnings', 'icon': SeIcons.wallet, 'active': SeIcons.walletFill},
    {'label': 'Profile', 'icon': SeIcons.user, 'active': SeIcons.userFill},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(
            onTabSwitch: (i) => setState(() => _selectedIndex = i),
            driverNameNotifier: _driverNameNotifier,
          ),
          const HistoryScreen(),
          const EarningsScreen(),
          ProfileScreen(driverNameNotifier: _driverNameNotifier),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(top: BorderSide(color: SeColors.ink200)),
          boxShadow: SeElevation.e2,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final active = _selectedIndex == i;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedIndex = i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The icon lifts a couple of pixels and swaps to its
                        // filled variant on selection.
                        AnimatedSlide(
                          offset: Offset(0, active ? -0.06 : 0),
                          duration: SeMotion.fast,
                          curve: SeMotion.emphasized,
                          child: Icon(
                            (active
                                ? _navItems[i]['active']
                                : _navItems[i]['icon']) as IconData,
                            size: 24,
                            // The action red, not the identity red: this is a
                            // control, and the two tones are not
                            // interchangeable (see SeColors).
                            color:
                                active ? SeColors.brandAction : SeColors.ink400,
                          ),
                        ),
                        const SizedBox(height: SeSpacing.x1),
                        Text(
                          _navItems[i]['label'] as String,
                          style: SeType.eyebrow.copyWith(
                            color:
                                active ? SeColors.brandAction : SeColors.ink400,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
