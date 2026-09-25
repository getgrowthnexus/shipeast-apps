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
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

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
      statusBarIconBrightness: Brightness.dark,
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

    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(cart.cartCount),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: SeEmptyState(
                        icon: SeIcons.cart,
                        title: 'Your cart is empty',
                        message: 'Add items from a merchant to get started.',
                        ctaLabel: 'Browse Merchants',
                        onCta: () => Navigator.pop(context),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          SeSpacing.gutter, 16, SeSpacing.gutter, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (cart.merchantName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  const Icon(SeIcons.storefront,
                                      size: 15, color: SeColors.ink400),
                                  const SizedBox(width: 6),
                                  Text(cart.merchantName.toUpperCase(),
                                      style: SeType.eyebrow),
                                ],
                              ),
                            ),
                          ...items.map((item) => _itemCard(item, cart)),
                          const SizedBox(height: 4),
                          SeButton(
                            label: 'Add More Items',
                            icon: SeIcons.plus,
                            variant: SeButtonVariant.ghost,
                            size: SeButtonSize.medium,
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(height: 12),
                          _buildInstructionsCard(),
                          const SizedBox(height: 12),
                          _buildSummaryCard(
                              subtotal, deliveryFee, serviceFee, total),
                          const SizedBox(height: 16),
                          _buildCheckoutButton(
                              cart, subtotal, deliveryFee, serviceFee, total),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int totalItems) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, SeSpacing.gutter, 12),
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(bottom: BorderSide(color: SeColors.ink100)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: SeColors.surface50, shape: BoxShape.circle),
                child: const Icon(SeIcons.arrowLeft,
                    size: 20, color: SeColors.ink900),
              ),
            ),
            const SizedBox(width: 12),
            Text('My Cart', style: SeType.h2),
            const SizedBox(width: 10),
            if (totalItems > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: SeColors.red50, borderRadius: SeRadius.pill),
                child: Text('$totalItems items',
                    style: SeType.label.copyWith(color: SeColors.red700)),
              ),
          ],
        ),
      );

  Widget _itemCard(CartItem item, CartProvider cart) => SeCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: SeRadius.all(SeRadius.sm),
              child: SizedBox(
                width: 56,
                height: 56,
                child: AppImage(
                  url: item.imageUrl,
                  placeholder: const SeShimmer(
                      child: SeSkeleton(width: 56, height: 56, radius: 12)),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(Money.format(item.price),
                      style: SeType.tabular(SeType.title)
                          .copyWith(color: SeColors.red600)),
                ],
              ),
            ),
            Row(
              children: [
                _qtyBtn(SeIcons.minus, SeColors.surface50, SeColors.ink700,
                    () => cart.removeItem(item.id)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('${item.quantity}',
                      style: SeType.tabular(SeType.title)),
                ),
                _qtyBtn(SeIcons.plus, SeColors.red500, Colors.white,
                    () => cart.incrementItem(item.id)),
              ],
            ),
          ],
        ),
      );

  Widget _fallback() => Container(
        color: SeColors.surface50,
        child: const Icon(SeIcons.food, size: 24, color: SeColors.ink300),
      );

  Widget _qtyBtn(IconData icon, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 30,
          height: 30,
          decoration:
              BoxDecoration(color: bg, borderRadius: SeRadius.all(SeRadius.xs)),
          child: Icon(icon, size: 16, color: fg),
        ),
      );

  Widget _buildInstructionsCard() => SeCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SPECIAL INSTRUCTIONS', style: SeType.eyebrow),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsController,
              maxLines: 2,
              style: SeType.body.copyWith(color: SeColors.ink900),
              cursorColor: SeColors.red500,
              decoration: InputDecoration(
                hintText: 'e.g. Extra spicy, no onions...',
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

  Widget _buildSummaryCard(
          int subtotal, int deliveryFee, int serviceFee, int total) =>
      SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryRow('Subtotal', Money.format(subtotal)),
            _summaryRow('Delivery fee', Money.deliveryFee(deliveryFee)),
            _summaryRow('Service fee', Money.format(serviceFee)),
            const SizedBox(height: 6),
            const Divider(height: 1, color: SeColors.ink100),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: SeType.h3),
                Text(Money.format(total),
                    style: SeType.tabular(SeType.h3)
                        .copyWith(color: SeColors.red600)),
              ],
            ),
          ],
        ),
      );

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: SeType.body.copyWith(color: SeColors.ink500)),
            Text(value,
                style: SeType.tabular(SeType.body)
                    .copyWith(color: SeColors.ink700)),
          ],
        ),
      );

  Widget _buildCheckoutButton(CartProvider cart, int subtotal, int deliveryFee,
          int serviceFee, int total) =>
      SeButton(
        label: 'Proceed to Checkout · ${Money.format(total)}',
        icon: SeIcons.arrowRight,
        onPressed: () => Navigator.pushNamed(context, '/checkout', arguments: {
          'merchantId': cart.merchantId,
          'merchantName': cart.merchantName,
          'items': cart.toOrderItems(),
          'subtotal': subtotal,
          'deliveryFee': deliveryFee,
          'serviceFee': serviceFee,
          'total': total,
          'instructions': _instructionsController.text.trim(),
        }),
      );
}
