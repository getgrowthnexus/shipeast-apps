import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../services/phone_call.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_page.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_card.dart';
import '../widgets/se_photo_tile.dart';
import '../widgets/se_step_tracker.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';

class DeliveryConfirmationScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> order;

  const DeliveryConfirmationScreen({
    super.key,
    required this.orderId,
    required this.order,
  });

  @override
  State<DeliveryConfirmationScreen> createState() =>
      _DeliveryConfirmationScreenState();
}

class _DeliveryConfirmationScreenState
    extends State<DeliveryConfirmationScreen> {
  File? _photo;
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = false;

  String get _customerName =>
      widget.order['customerName'] as String? ?? 'Customer';
  String get _customerPhone =>
      widget.order['customerPhone'] as String? ?? '';
  String get _deliveryAddress =>
      widget.order['deliveryAddress'] as String? ?? '—';
  int get _total => (widget.order['total'] as num?)?.toInt() ?? 0;
  String get _paymentMethod =>
      widget.order['paymentMethod'] as String? ?? 'COD';

  bool get _isCod =>
      _paymentMethod.toLowerCase().contains('cod') ||
      _paymentMethod.toLowerCase().contains('cash');

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1080);
    if (picked != null && mounted) {
      setState(() => _photo = File(picked.path));
    }
  }

  void _showPhotoOptions() {
    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          bottom: MediaQuery.of(ctx).padding.bottom + SeSpacing.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: SeSpacing.x3),
            Text('Proof of delivery',
                style: SeType.h3, textAlign: TextAlign.center),
            const SizedBox(height: SeSpacing.x5),
            SeButton(
              label: 'Take Photo',
              icon: SeIcons.camera,
              onPressed: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: SeSpacing.x3),
            SeButton(
              label: 'Choose from Gallery',
              icon: SeIcons.image,
              variant: SeButtonVariant.ghost,
              onPressed: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_photo != null) ...[
              const SizedBox(height: SeSpacing.x3),
              SeButton(
                label: 'Remove Photo',
                icon: SeIcons.trash,
                variant: SeButtonVariant.destructive,
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = null);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _markAsDelivered() async {
    setState(() => _isLoading = true);
    try {
      String? photoUrl;
      if (_photo != null) {
        try {
          photoUrl = await DriverFirestoreService.uploadDeliveryPhoto(
              widget.orderId, _photo!);
        } catch (_) {
          // Photo upload failed — still mark delivered, but say so rather than
          // letting the driver believe the proof was stored.
          if (mounted) {
            SeToast.info(
                context, 'Photo could not be uploaded — delivery still saved.');
          }
        }
      }
      // The commission is derived from the order's own stored total inside the
      // write transaction and returned here, so the celebration figure and the
      // earnings total can never disagree (P3-04).
      final commission = await DriverFirestoreService.confirmDelivery(
        widget.orderId,
        photoUrl: photoUrl,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (mounted) {
        HapticFeedback.mediumImpact();
        _showSuccessSheet(commission);
      }
    } on StateError catch (e) {
      // The order is not in a state this driver can complete. Name the reason
      // rather than showing a blanket "try again" that reads as an app bug.
      if (mounted) {
        setState(() => _isLoading = false);
        final String message;
        switch (e.message) {
          case DriverFirestoreService.notInTransitCode:
            message = 'This order is not ready to be marked delivered yet.';
            break;
          case DriverFirestoreService.notYourOrderCode:
            message = 'This order is no longer assigned to you.';
            break;
          case DriverFirestoreService.orderMissingCode:
            message = 'This order no longer exists.';
            break;
          default:
            message = 'Failed to confirm delivery. Try again.';
        }
        SeToast.error(context, message);
      }
    } on FirebaseException catch (e) {
      // A Firestore-level failure (rules rejection, or offline).
      if (mounted) {
        setState(() => _isLoading = false);
        SeToast.error(
          context,
          e.code == 'unavailable'
              ? 'You appear to be offline. Reconnect and try again.'
              : 'Failed to confirm delivery. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        SeToast.error(context, 'Failed to confirm delivery. Try again.');
      }
    }
  }

  /// The payoff moment — Sunset gradient with the driver's earnings counting up.
  void _showSuccessSheet(int commission) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeliverySuccessSheet(
        customerName: _customerName,
        commission: commission.toDouble(),
        orderTotal: _total,
        collectCash: _isCod,
        onDone: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).popUntil(
            (route) => route.settings.name == '/dashboard' || route.isFirst,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: 'Delivery',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x2, SeSpacing.gutter, SeSpacing.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: const SeStepTracker(
                current: 2,
                steps: [
                  SeStep('Order accepted'),
                  SeStep('Collected from merchant'),
                  SeStep('Deliver to customer',
                      caption: 'Capture proof, then mark delivered'),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x4),

            // ── Who and where ───────────────────────────────────────────
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DELIVERING TO', style: SeType.eyebrow),
                  const SizedBox(height: SeSpacing.x2),
                  Text(_customerName, style: SeType.h3),
                  const SizedBox(height: 2),
                  Text(_deliveryAddress,
                      style: SeType.body.copyWith(color: SeColors.ink500)),
                  if (_customerPhone.isNotEmpty) ...[
                    const SizedBox(height: SeSpacing.x4),
                    SeButton(
                      label: 'Call customer',
                      icon: SeIcons.phone,
                      variant: SeButtonVariant.ghost,
                      onPressed: () =>
                          callPhone(context, _customerPhone, label: 'Customer'),
                    ),
                  ],
                  const Divider(color: SeColors.ink200, height: SeSpacing.x6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payment · $_paymentMethod',
                          style:
                              SeType.bodyS.copyWith(color: SeColors.ink500)),
                      Text(Money.format(_total),
                          style: SeType.tabular(SeType.title)),
                    ],
                  ),
                  if (_isCod) ...[
                    const SizedBox(height: SeSpacing.x3),
                    Container(
                      padding: const EdgeInsets.all(SeSpacing.x3),
                      decoration: BoxDecoration(
                        color: SeColors.warningTint,
                        borderRadius: SeRadius.all(SeRadius.sm),
                      ),
                      child: Row(
                        children: [
                          const Icon(SeIcons.cash,
                              color: SeColors.warning, size: 18),
                          const SizedBox(width: SeSpacing.x2),
                          Expanded(
                            child: Text(
                              'Collect ${Money.format(_total)} in cash on arrival.',
                              style: SeType.bodyS
                                  .copyWith(color: SeColors.ink700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x3),

            // ── Proof photo ─────────────────────────────────────────────
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery photo', style: SeType.title),
                  const SizedBox(height: 2),
                  Text('Optional, but it protects you in a dispute.',
                      style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                  const SizedBox(height: SeSpacing.x4),
                  SePhotoTile(
                    photo: _photo,
                    onCapture: _showPhotoOptions,
                    emptyLabel: 'Add a photo',
                    emptyHint: 'Camera or gallery',
                  ),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x3),

            // ── Note ────────────────────────────────────────────────────
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: SeTextField(
                controller: _noteController,
                label: 'Delivery note (optional)',
                hint: 'e.g. Left with the security guard',
                icon: SeIcons.note,
                minLines: 3,
                maxLines: 4,
              ),
            ),
            const SizedBox(height: SeSpacing.x6),

            SeButton(
              label: 'Mark as Delivered',
              icon: SeIcons.checkCircle,
              loading: _isLoading,
              onPressed: _isLoading ? null : _markAsDelivered,
            ),
          ],
        ),
      ),
    );
  }
}

/// Success sheet shown once the delivery write lands.
class _DeliverySuccessSheet extends StatelessWidget {
  final String customerName;
  final double commission;
  final int orderTotal;
  final bool collectCash;
  final VoidCallback onDone;

  const _DeliverySuccessSheet({
    required this.customerName,
    required this.commission,
    required this.orderTotal,
    required this.collectCash,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = SeMotion.reduced(context);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: SeColors.shell,
        borderRadius: SeRadius.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, SeSpacing.x5,
              SeSpacing.gutter, SeSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: SeColors.shellInk.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(SeIcons.checkCircle,
                    color: SeColors.shellInk, size: 42),
              ),
              const SizedBox(height: SeSpacing.x5),
              Text('Delivery complete',
                  style: SeType.h1.copyWith(color: SeColors.shellInk)),
              const SizedBox(height: SeSpacing.x2),
              Text(
                'Handed off to $customerName. Nice work.',
                textAlign: TextAlign.center,
                style: SeType.body
                    .copyWith(color: SeColors.shellInk.withValues(alpha: 0.88)),
              ),
              const SizedBox(height: SeSpacing.x6),

              // Count-up earnings — the reward beat.
              Text('YOU EARNED',
                  style: SeType.eyebrow
                      .copyWith(color: SeColors.shellInk.withValues(alpha: 0.80))),
              const SizedBox(height: SeSpacing.x1),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: commission),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: SeMotion.decelerate,
                builder: (context, value, _) => Text(
                  Money.format(value),
                  style: SeType.tabular(SeType.display)
                      .copyWith(color: SeColors.shellInk, fontSize: 40),
                ),
              ),
              Text(
                '${DriverPay.commissionLabel} of ${Money.format(orderTotal)}',
                style: SeType.bodyS
                    .copyWith(color: SeColors.shellInk.withValues(alpha: 0.78)),
              ),

              if (collectCash) ...[
                const SizedBox(height: SeSpacing.x5),
                Container(
                  padding: const EdgeInsets.all(SeSpacing.x4),
                  decoration: BoxDecoration(
                    color: SeColors.shellInk.withValues(alpha: 0.18),
                    borderRadius: SeRadius.all(SeRadius.sm),
                  ),
                  child: Row(
                    children: [
                      const Icon(SeIcons.cash, color: SeColors.shellInk, size: 20),
                      const SizedBox(width: SeSpacing.x3),
                      Expanded(
                        child: Text(
                          'Remember to remit the ${Money.format(orderTotal)} cash you collected.',
                          style:
                              SeType.bodyS.copyWith(color: SeColors.shellInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: SeSpacing.x6),
              GestureDetector(
                onTap: onDone,
                child: Container(
                  width: double.infinity,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: SeColors.shellInk,
                    borderRadius: SeRadius.pill,
                  ),
                  child: Text(
                    'Back to dashboard',
                    style: SeType.jakarta(16, FontWeight.w600,
                        color: SeColors.shell),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
