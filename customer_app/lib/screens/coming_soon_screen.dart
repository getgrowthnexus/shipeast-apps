import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../widgets/se_app_bar.dart';
import '../widgets/se_empty_state.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;

  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          SeGradientHeader(title: title),
          Expanded(
            child: Center(
              child: SeEmptyState(
                icon: SeIcons.rocket,
                title: 'Coming Soon',
                message:
                    'This feature is on the way — available in a future update.',
                ctaLabel: 'Go Back',
                onCta: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
