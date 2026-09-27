import 'package:flutter/material.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_page.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;

  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.rocket,
            title: 'Coming soon',
            message: 'This one is on the way — it will arrive in an update.',
            ctaLabel: 'Go back',
            onCta: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }
}
