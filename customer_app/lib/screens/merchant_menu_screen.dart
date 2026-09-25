import 'dart:async';
import '../widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

class MerchantMenuScreen extends StatefulWidget {
  const MerchantMenuScreen({super.key});

  @override
  State<MerchantMenuScreen> createState() => _MerchantMenuScreenState();
}

class _MerchantMenuScreenState extends State<MerchantMenuScreen> {
  // Merchant info from route args
  String _merchantId = '';
  String _merchantName = 'Merchant';
  String _merchantEmoji = '🍽️';
  String _merchantImageUrl = '';
  String _merchantRating = '4.5';
  String _merchantDeliveryTime = '25–35 min';
  /// Integer JMD. One field is the display value AND the charged value
  /// (P3-01) — they used to be two, and they disagreed.
  int _merchantDeliveryFee = 0;
  bool _merchantIsOpen = true;
  String _merchantCategory = 'Food';
  bool _favourite = false;

  // Menu items from Firestore
  List<Map<String, dynamic>> _menuItems = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  int _selectedTab = 0;
  bool _argsLoaded = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _merchantId = args['id'] as String? ?? '';
        _merchantName = args['name'] as String? ?? 'Merchant';
        _merchantEmoji = args['emoji'] as String? ?? '🍽️';
        _merchantImageUrl = args['imageUrl'] as String? ?? '';
        _merchantRating = args['rating'] as String? ?? '4.5';
        _merchantDeliveryTime = args['deliveryTime'] as String? ?? '25–35 min';
        _merchantDeliveryFee = args['deliveryFee'] as int? ?? 0;
        _merchantIsOpen = args['isOpen'] as bool? ?? true;
        _merchantCategory = args['category'] as String? ?? 'Food';
      }
      _subscribeMenuItems();

      final cart = Provider.of<CartProvider>(context, listen: false);
      if (cart.cartCount > 0 &&
          cart.merchantId.isNotEmpty &&
          cart.merchantId != _merchantId &&
          _merchantId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _promptNewOrder());
      } else {
        cart.setMerchant(_merchantId, _merchantName, _merchantDeliveryFee);
      }
    }
  }

  Future<void> _promptNewOrder() async {
    if (!mounted) return;
    final cart = Provider.of<CartProvider>(context, listen: false);
    final confirmed = await SeConfirmSheet.show(
      context,
      title: 'Start new order?',
      message:
          'Your cart has items from ${cart.merchantName}. Clear it to order from $_merchantName?',
      confirmLabel: 'Clear & Start New',
      cancelLabel: 'Keep Cart',
      destructive: true,
    );
    if (confirmed) {
      cart.clearCart();
      cart.setMerchant(_merchantId, _merchantName, _merchantDeliveryFee);
    }
  }

  void _subscribeMenuItems() {
    if (_merchantId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _sub = FirestoreService.menuItemsStream(_merchantId).listen((items) {
      if (mounted) {
        setState(() {
          _menuItems = items;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<String> get _categoryTabs {
    final seen = <String>{};
    final cats = <String>[];
    for (final item in _menuItems) {
      final c = item['category'] as String? ?? '';
      if (c.isNotEmpty && seen.add(c)) cats.add(c);
    }
    return cats;
  }

  List<String> get _tabLabels => ['Popular', ..._categoryTabs.map(_capitalize)];

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<Map<String, dynamic>> get _visibleItems {
    if (_selectedTab == 0) return _menuItems;
    final cat = _categoryTabs[_selectedTab - 1];
    return _menuItems.where((i) => i['category'] == cat).toList();
  }

  void _addToCart(Map<String, dynamic> item) {
    HapticFeedback.selectionClick();
    final cart = context.read<CartProvider>();
    final itemId = item['id'] as String? ?? '';
    if (itemId.isEmpty) return;
    cart.addItem(CartItem(
      id: itemId,
      name: item['name'] as String? ?? '',
      description: item['description'] as String? ?? '',
      price: (item['price'] as num?)?.toInt() ?? 0,
      imageUrl: item['imageUrl'] as String? ?? '',
      quantity: 1,
    ));
  }

  void _removeFromCart(String itemId) {
    HapticFeedback.selectionClick();
    context.read<CartProvider>().removeItem(itemId);
  }

  Color get _heroHue => switch (_merchantCategory) {
        'Grocery' => SeColors.success,
        'Pharmacy' => SeColors.ocean500,
        'Packages' => SeColors.gold500,
        _ => SeColors.red500,
      };

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: SeColors.surface50,
      bottomNavigationBar: _cartBar(cart),
      body: Column(
        children: [
          _buildHero(),
          _buildInfoBar(),
          Expanded(
            child: _loading
                ? _buildShimmerList()
                : _menuItems.isEmpty
                    ? Center(
                        child: SeEmptyState(
                          icon: SeIcons.food,
                          title: 'No menu items yet',
                          message: 'This merchant is still setting up — check back soon.',
                          hue: _heroHue,
                          tint: _heroHue.withValues(alpha: 0.12),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  SeSpacing.gutter, 16, SeSpacing.gutter, 8),
                              child: Text(
                                _selectedTab == 0
                                    ? 'MOST ORDERED'
                                    : _tabLabels[_selectedTab].toUpperCase(),
                                style: SeType.eyebrow,
                              ),
                            ),
                            ..._visibleItems
                                .map((item) => _menuItemCard(item, cart)),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_merchantImageUrl.isNotEmpty)
            AppImage(
              url: _merchantImageUrl,
              placeholder: _heroFallback(),
              errorWidget: _heroFallback(),
            )
          else
            _heroFallback(),
          const DecoratedBox(
              decoration: BoxDecoration(gradient: SeColors.inkScrim)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleBtn(SeIcons.arrowLeft, () => Navigator.pop(context)),
                  _circleBtn(
                    _favourite ? SeIcons.heartFill : SeIcons.heart,
                    () {
                      HapticFeedback.lightImpact();
                      setState(() => _favourite = !_favourite);
                      SeToast.success(
                          context,
                          _favourite
                              ? 'Added to favourites'
                              : 'Removed from favourites');
                    },
                    fg: _favourite ? SeColors.red500 : SeColors.ink700,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_heroHue.withValues(alpha: 0.9), _heroHue],
          ),
        ),
        child: Center(
          child: Text(_merchantEmoji, style: const TextStyle(fontSize: 54)),
        ),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap,
          {Color fg = SeColors.ink700}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            boxShadow: SeElevation.e1,
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      );

  Widget _buildInfoBar() {
    final tabs = _tabLabels;
    return Container(
      padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 16, SeSpacing.gutter, 14),
      decoration: const BoxDecoration(
        color: SeColors.surface0,
        border: Border(bottom: BorderSide(color: SeColors.ink100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_merchantName, style: SeType.h2),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(SeIcons.star, size: 14, color: SeColors.gold500),
                  const SizedBox(width: 3),
                  Text(_merchantRating,
                      style: SeType.tabular(SeType.bodyS)
                          .copyWith(color: SeColors.ink700)),
                ],
              ),
              _infoBit(SeIcons.clock, _merchantDeliveryTime),
              _infoBit(SeIcons.bike, Money.deliveryFee(_merchantDeliveryFee)),
              SeChip.status(
                label: _merchantIsOpen ? 'Open Now' : 'Closed',
                color: _merchantIsOpen ? SeColors.success : SeColors.danger,
                tint: _merchantIsOpen
                    ? SeColors.successTint
                    : SeColors.dangerTint,
              ),
            ],
          ),
          if (tabs.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tabs.length,
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final active = _selectedTab == i;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? SeColors.red50 : SeColors.surface50,
                        borderRadius: SeRadius.pill,
                        border: active
                            ? Border.all(color: SeColors.red500, width: 1.5)
                            : null,
                      ),
                      child: Text(
                        tabs[i],
                        style: SeType.label.copyWith(
                          color: active ? SeColors.red700 : SeColors.ink500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoBit(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SeColors.ink400),
          const SizedBox(width: 4),
          Text(text, style: SeType.bodyS.copyWith(color: SeColors.ink500)),
        ],
      );

  Widget _menuItemCard(Map<String, dynamic> item, CartProvider cart) {
    final itemId = item['id'] as String? ?? '';
    final qty = cart.items[itemId]?.quantity ?? 0;
    final price = (item['price'] as num?)?.toInt() ?? 0;
    final imageUrl = item['imageUrl'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(SeSpacing.gutter, 0, SeSpacing.gutter, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        boxShadow: SeElevation.e1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: SeRadius.all(SeRadius.sm),
            child: SizedBox(
              width: 72,
              height: 72,
              child: AppImage(
                url: imageUrl,
                placeholder: const SeShimmer(
                    child: SeSkeleton(width: 72, height: 72, radius: 12)),
                errorWidget: _itemFallback(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] as String? ?? '',
                    style: SeType.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(item['description'] as String? ?? '',
                    style: SeType.bodyS.copyWith(color: SeColors.ink500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Money.format(price),
                        style: SeType.tabular(SeType.title)
                            .copyWith(color: SeColors.red600)),
                    _qtyControl(item, itemId, qty),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemFallback() => Container(
        color: SeColors.surface50,
        child: const Icon(SeIcons.food, size: 30, color: SeColors.ink300),
      );

  Widget _qtyControl(Map<String, dynamic> item, String itemId, int qty) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: qty == 0
          ? GestureDetector(
              key: const ValueKey('add'),
              onTap: () => _addToCart(item),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: SeColors.emberGradient,
                  borderRadius: SeRadius.all(SeRadius.sm),
                  boxShadow: SeElevation.glow,
                ),
                child: const Icon(SeIcons.plus, size: 18, color: Colors.white),
              ),
            )
          : Row(
              key: const ValueKey('stepper'),
              children: [
                _stepBtn(SeIcons.minus, SeColors.surface50, SeColors.ink700,
                    () => _removeFromCart(itemId)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$qty',
                      style: SeType.tabular(SeType.title)),
                ),
                _stepBtn(SeIcons.plus, SeColors.red500, Colors.white,
                    () => _addToCart(item)),
              ],
            ),
    );
  }

  Widget _stepBtn(IconData icon, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: SeRadius.all(SeRadius.xs),
          ),
          child: Icon(icon, size: 16, color: fg),
        ),
      );

  Widget _buildShimmerList() {
    return SeShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 16, SeSpacing.gutter, 24),
        itemCount: 5,
        itemBuilder: (_, index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SeColors.surface0,
            borderRadius: SeRadius.all(SeRadius.md),
          ),
          child: Row(
            children: const [
              SeSkeleton(width: 72, height: 72, radius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 150, height: 14, radius: 6),
                    SizedBox(height: 8),
                    SeSkeleton(width: 110, height: 11, radius: 5),
                    SizedBox(height: 12),
                    SeSkeleton(width: 60, height: 14, radius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _cartBar(CartProvider cart) {
    if (cart.cartCount == 0) return null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, 0, SeSpacing.gutter, 12),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/cart'),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: SeColors.emberGradient,
            borderRadius: SeRadius.all(SeRadius.md),
            boxShadow: SeElevation.glow,
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: SeRadius.pill,
                ),
                child: Text('${cart.cartCount}',
                    style: SeType.tabular(SeType.title)
                        .copyWith(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Text('View Cart',
                  style: SeType.jakarta(16, FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              Text(Money.format(cart.cartTotal),
                  style: SeType.tabular(SeType.jakarta(16, FontWeight.w800,
                      color: Colors.white))),
              const SizedBox(width: 8),
              const Icon(SeIcons.caretRight, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
