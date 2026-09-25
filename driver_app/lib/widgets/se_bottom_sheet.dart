import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import 'se_button.dart';

/// Standard SEDS bottom sheet chrome: grab handle + title/subtitle, xl top
/// radius, keyboard-aware padding.
Future<T?> showSeBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: scheme.surface,
    barrierColor: SeColors.ink900.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(borderRadius: SeRadius.sheetTop),
    builder: builder,
  );
}

/// Grab handle used at the top of sheets.
class SeSheetHandle extends StatelessWidget {
  const SeSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: SeColors.ink200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// A confirm sheet with title, message and two actions — replaces `showDialog`
/// AlertDialogs / `confirm()` semantics.
class SeConfirmSheet {
  SeConfirmSheet._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showSeBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          top: 4,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: 12),
            Text(title, style: SeType.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: SeType.body.copyWith(color: SeColors.ink500),
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            SeButton(
              label: confirmLabel,
              variant: destructive
                  ? SeButtonVariant.destructive
                  : SeButtonVariant.primary,
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            SeButton(
              label: cancelLabel,
              variant: SeButtonVariant.ghost,
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }
}
