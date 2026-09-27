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
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

/// A merchant and its menu.
///
/// Same two-surface shape as everywhere else, except the cap is the merchant's
/// photograph instead of the brand red — this is the one screen where the
/// business on the other end, not ShipEast, is the thing being introduced. When
/// there is no photo the cap falls back to the brand shell, so the screen still
/// belongs to the same app rather than showing a grey hole.
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

  void _removeFromCart(String itemId) =>
      context.read<CartProvider>().removeItem(itemId);

  // Mirrors the home-screen category palette so a merchant's hero reads in the
  // same hue as the chip that led here. Star-gold stays reserved for ratings.
  Color get _heroHue => switch (_merchantCategory) {
        'Grocery' => SeColors.catGrocery,
        'Pharmacy' => SeColors.catPharmacy,
        'Packages' => SeColors.catPackages,
        _ => SeColors.catFood,
      };

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: SeColors.shell,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(),
          Expanded(
            child: SeSheet(
              bottomBar: _cartBar(cart),
              child: _loading ? _shimmerList() : _menu(cart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() => SizedBox(
        // A photograph earns the full band. A fallback does not — 186dp of flat
        // colour with one glyph in it is a lot of screen spent saying nothing.
        height: _merchantImageUrl.isNotEmpty ? 186 : 148,
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
            if (_merchantImageUrl.isNotEmpty)
              const DecoratedBox(
                  decoration: BoxDecoration(gradient: SeColors.inkScrim)),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 6,
                    SeSpacing.gutter, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SeCapButton(
                        icon: SeIcons.arrowLeft,
                        onTap: () => Navigator.pop(context)),
                    SeCapButton(
                      icon: _favourite ? SeIcons.heartFill : SeIcons.heart,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _favourite = !_favourite);
                        SeToast.success(
                            context,
                            _favourite
                                ? 'Added to favourites'
                                : 'Removed from favourites');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// No photo: the brand shell, not a saturated category plate. It keeps the
  /// screen inside the same two-surface language as the rest of the app.
  Widget _heroFallback() => ColoredBox(
        color: SeColors.shell,
        child: Center(
          child: Text(_merchantEmoji, style: const TextStyle(fontSize: 52)),
        ),
      );

  Widget _menu(CartProvider cart) {
    final tabs = _tabLabels;
    final items = _visibleItems;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, 20, SeSpacing.gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(_merchantName, style: SeType.h2)),
                    const SizedBox(width: 10),
                    SeChip.status(
                      label: _merchantIsOpen ? 'Open' : 'Closed',
                      color: _merchantIsOpen
                          ? SeColors.successInk
                          : SeColors.dangerInk,
                      tint: _merchantIsOpen
                          ? SeColors.successSoft
                          : SeColors.dangerSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    SeRatingPill(rating: _merchantRating),
                    const SizedBox(width: 14),
                    SeMetaBit(
                        icon: SeIcons.clock, text: _merchantDeliveryTime),
                    const SizedBox(width: 14),
                    SeMetaBit(
                        icon: SeIcons.bike,
                        text: Money.deliveryFee(_merchantDeliveryFee)),
                  ],
                ),
                if (!_merchantIsOpen) ...[
                  const SizedBox(height: 14),
                  SeNotice.warning(
                      'This merchant is closed right now. You can look at the '
                      'menu, but orders will not go through until they open.'),
                ],
                if (tabs.length > 1) ...[
                  const SizedBox(height: 16),
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
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 15),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? SeColors.brandAction
                                  : SeColors.surface0,
                              borderRadius: SeRadius.pill,
                              border: Border.all(
                                  color: active
                                      ? SeColors.brandAction
                                      : SeColors.ink200),
                            ),
                            child: Text(
                              tabs[i],
                              style: SeType.label.copyWith(
                                color:
                                    active ? Colors.white : SeColors.ink700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (items.isNotEmpty)
                  Text(
                    _selectedTab == 0
                        ? 'MOST ORDERED'
                        : tabs[_selectedTab].toUpperCase(),
                    style: SeType.eyebrow,
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: SeEmptyState(
                  icon: SeIcons.food,
                  title: 'No menu items yet',
                  message:
                      'This merchant is still setting up — check back soon.',
                  hue: _heroHue,
                  tint: _heroHue.withValues(alpha: 0.12),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                SeSpacing.gutter, 0, SeSpacing.gutter,
                cart.cartCount > 0 ? 24 : 40),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = items[i];
                final itemId = item['id'] as String? ?? '';
                return SeMenuItemRow(
                  name: item['name'] as String? ?? '',
                  description: item['description'] as String? ?? '',
                  price: Money.format((item['price'] as num?)?.toInt() ?? 0),
                  imageUrl: item['imageUrl'] as String? ?? '',
                  quantity: cart.items[itemId]?.quantity ?? 0,
                  onAdd: () => _addToCart(item),
                  onRemove: () => _removeFromCart(itemId),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _shimmerList() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 24, SeSpacing.gutter, 24),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
            ),
            child: Row(
              children: const [
                SeSkeleton(width: 68, height: 68, radius: 12),
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

  /// The cart bar floats as a pill rather than filling a bar, so the menu is
  /// visibly still there underneath it — the order is not finished yet.
  Widget? _cartBar(CartProvider cart) {
    if (cart.cartCount == 0) return null;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(SeSpacing.gutter, 8, SeSpacing.gutter, 12),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/cart'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: SeColors.brandAction,
            borderRadius: SeRadius.pill,
            boxShadow: SeElevation.glow,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Text('${cart.cartCount}',
                    style: SeType.tabular(SeType.title)
                        .copyWith(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Text('View cart',
                  style:
                      SeType.jakarta(16, FontWeight.w700, color: Colors.white)),
              const Spacer(),
              Text(Money.format(cart.cartTotal),
                  style: SeType.tabular(SeType.jakarta(16, FontWeight.w800,
                      color: Colors.white))),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
