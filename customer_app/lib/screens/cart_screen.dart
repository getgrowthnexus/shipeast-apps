import '../widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../utils/money.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

/// The cart.
///
/// The total and the way forward are docked to the bottom of the sheet rather
/// than parked at the end of the scroll. On a long order the old layout put the
/// one thing you came here to press below three screens of items — you had to
/// scroll to find out what it cost.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _instructionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final items = cart.itemList;
    final subtotal = cart.cartTotal;
    final deliveryFee = cart.deliveryFeeAmount;
    final serviceFee = (subtotal * 0.1).round();
    final total = subtotal + deliveryFee + serviceFee;
    final empty = items.isEmpty;

    return SePageScaffold(
      title: 'Your cart',
      subtitle: empty
          ? null
          : '${cart.cartCount} '
              '${cart.cartCount == 1 ? 'item' : 'items'}'
              '${cart.merchantName.isEmpty ? '' : ' from ${cart.merchantName}'}',
      bottomBar: empty ? null : _checkoutBar(cart, subtotal, deliveryFee, serviceFee, total),
      child: empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: SeEmptyState(
                  icon: SeIcons.cart,
                  title: 'Your cart is empty',
                  message: 'Add items from a merchant to get started.',
                  ctaLabel: 'Browse merchants',
                  onCta: () => Navigator.pop(context),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, 20, SeSpacing.gutter, 24),
              children: [
                for (final item in items) ...[
                  _itemRow(item, cart),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 2),
                // Hug-width secondary action — a full-bleed ghost bar read as
                // heavy next to the item rows.
                Center(
                  child: SeButton(
                    label: 'Add more items',
                    icon: SeIcons.plus,
                    variant: SeButtonVariant.ghost,
                    size: SeButtonSize.medium,
                    expand: false,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 20),
                _instructions(),
                const SizedBox(height: 14),
                _summary(subtotal, deliveryFee, serviceFee, total),
              ],
            ),
    );
  }

  Widget _itemRow(CartItem item, CartProvider cart) => SePanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: SeRadius.all(SeRadius.sm),
              child: SizedBox(
                width: 56,
                height: 56,
                child: item.imageUrl.isEmpty
                    ? _fallback()
                    : AppImage(
                        url: item.imageUrl,
                        placeholder: const SeShimmer(
                            child:
                                SeSkeleton(width: 56, height: 56, radius: 12)),
                        errorWidget: _fallback(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: SeType.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  // The line total, not the unit price. Two of something at
                  // J$1,450 is J$2,900, and that is the number the customer is
                  // checking against the total at the bottom.
                  Text(
                    item.quantity > 1
                        ? '${Money.format(item.price * item.quantity)}'
                            '   ·   ${Money.format(item.price)} each'
                        : Money.format(item.price),
                    style: SeType.tabular(SeType.bodyS)
                        .copyWith(color: SeColors.ink500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SeQtyStepper(
              quantity: item.quantity,
              large: true,
              onAdd: () => cart.incrementItem(item.id),
              onRemove: () => cart.removeItem(item.id),
            ),
          ],
        ),
      );

  Widget _fallback() => Container(
        color: SeColors.surface50,
        child: const Icon(SeIcons.food, size: 24, color: SeColors.ink300),
      );

  Widget _instructions() => SePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SPECIAL INSTRUCTIONS', style: SeType.eyebrow),
            const SizedBox(height: 6),
            TextField(
              controller: _instructionsController,
              maxLines: 2,
              style: SeType.body.copyWith(color: SeColors.ink900),
              cursorColor: SeColors.brandAction,
              decoration: InputDecoration(
                hintText: 'e.g. extra spicy, no onions…',
                hintStyle: SeType.body.copyWith(color: SeColors.ink400),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );

  Widget _summary(int subtotal, int deliveryFee, int serviceFee, int total) =>
      SePanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SeMoneyLine(label: 'Subtotal', value: Money.format(subtotal)),
            SeMoneyLine(
                label: 'Delivery fee', value: Money.deliveryFee(deliveryFee)),
            SeMoneyLine(label: 'Service fee', value: Money.format(serviceFee)),
            const Divider(height: 20, color: SeColors.ink200),
            SeMoneyLine(
                label: 'Total', value: Money.format(total), strong: true),
          ],
        ),
      );

  /// Docked, so the amount is readable from any scroll position.
  ///
  /// The figure lives ON the button rather than on a line above it: the summary
  /// panel a few centimetres up already has a "Total" row, and printing the
  /// word twice on one screen makes a reader stop and check whether the two
  /// numbers are supposed to differ.
  Widget _checkoutBar(CartProvider cart, int subtotal, int deliveryFee,
          int serviceFee, int total) =>
      SeBottomBar(
        child: SeButton(
          label: 'Checkout · ${Money.format(total)}',
          onPressed: () =>
              Navigator.pushNamed(context, '/checkout', arguments: {
            'merchantId': cart.merchantId,
            'merchantName': cart.merchantName,
            'items': cart.toOrderItems(),
            'subtotal': subtotal,
            'deliveryFee': deliveryFee,
            'serviceFee': serviceFee,
            'total': total,
            'instructions': _instructionsController.text.trim(),
          }),
        ),
      );
}
