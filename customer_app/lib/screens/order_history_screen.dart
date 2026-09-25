import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../models/order_status.dart';
import '../providers/cart_provider.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_toast.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  int _activeTab = 0;
  static const _tabs = ['All', 'Active', 'Completed', 'Cancelled'];

  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _subscribe();
  }

  void _subscribe() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _sub = FirestoreService.orderHistoryStream(uid).listen((orders) {
      if (mounted) {
        setState(() {
          _orders = orders;
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

  List<Map<String, dynamic>> get _filtered {
    if (_activeTab == 0) return _orders;
    final label = _tabs[_activeTab];
    return _orders.where((o) {
      final status = o['status'] as String? ?? '';
      // Driven by the canonical sets, so a new status cannot silently match no
      // tab. Previously 'confirmed' and 'picked_up' matched none of the three,
      // so an order vanished from this list for the whole delivery — exactly
      // the window the customer is most likely to be checking.
      if (label == 'Active') return OrderStatus.isActive(status);
      if (label == 'Completed') return status == OrderStatus.delivered;
      if (label == 'Cancelled') return status == OrderStatus.cancelled;
      return false;
    }).toList();
  }

  /// The badge on each order card.
  ///
  /// Delegates to the canonical label, so the badge now names the actual state
  /// ("Picked Up") rather than the coarse bucket ("Active"). The old switch had
  /// a `default: return status` branch that rendered the raw database value —
  /// which is how the literal text "picked_up" reached the customer.
  String _displayStatus(String status) => OrderStatus.label(status);

  ({Color color, Color tint}) _statusColors(String status) {
    // Keyed off the canonical sets rather than individual statuses, so a status
    // added later inherits a sensible colour instead of falling through to
    // neutral grey.
    if (status == OrderStatus.cancelled) {
      return (color: SeColors.danger, tint: SeColors.dangerTint);
    }
    if (status == OrderStatus.delivered) {
      return (color: SeColors.ocean500, tint: SeColors.oceanTint);
    }
    if (OrderStatus.isActive(status)) {
      return (color: SeColors.success, tint: SeColors.successTint);
    }
    return (color: SeColors.ink500, tint: SeColors.surface50);
  }

  String _formatDate(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = (createdAt as Timestamp).toDate();
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
        'August', 'September', 'October', 'November', 'December'
      ];
      final month = months[dt.month];
      final day = dt.day;
      final year = dt.year;
      final hour12 =
          dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$month $day, $year at $hour12:$minute $ampm';
    } catch (_) {
      return '';
    }
  }

  String _itemsLabel(List<dynamic> items) {
    if (items.isEmpty) return '';
    return items
        .take(3)
        .map((i) => i['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
  }

  String _formatTotal(dynamic total) => Money.format((total as num?) ?? 0);

  /// An order can be reordered only if it came from a merchant and still has
  /// its line items. Package and overseas jobs carry neither, so "Reorder"
  /// would have nothing to put in the cart.
  bool _canReorder(Map<String, dynamic> order) {
    final merchantId = order['merchantId'] as String? ?? '';
    final items = order['items'] as List? ?? const [];
    return merchantId.isNotEmpty && items.isNotEmpty;
  }

  /// Rebuilds the cart from a past order and drops the customer into it to
  /// review before checkout. Prices come from the historical order; the cart
  /// and checkout screens recompute fees and totals from there, so a stale
  /// price is corrected the moment they proceed rather than silently charged.
  void _reorder(Map<String, dynamic> order) {
    final rawItems = order['items'] as List? ?? const [];
    final merchantId = order['merchantId'] as String? ?? '';
    if (merchantId.isEmpty || rawItems.isEmpty) {
      SeToast.info(context, "This order can't be reordered.");
      return;
    }
    final cart = context.read<CartProvider>();
    cart.clearCart();
    cart.setMerchant(
      merchantId,
      order['merchantName'] as String? ?? 'Merchant',
      (order['deliveryFee'] as num?)?.toInt() ?? 0,
    );
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final i = Map<String, dynamic>.from(raw);
      final name = i['name'] as String? ?? '';
      if (name.isEmpty) continue;
      // Stored order items keep only name/price/quantity (see placeOrder), so
      // fall back to the name as a stable cart key when no id was persisted.
      final id = (i['id'] as String?)?.isNotEmpty == true
          ? i['id'] as String
          : name;
      cart.addItem(CartItem(
        id: id,
        name: name,
        description: i['description'] as String? ?? '',
        price: (i['price'] as num?)?.toInt() ?? 0,
        imageUrl: i['imageUrl'] as String? ?? '',
        quantity: (i['quantity'] as num?)?.toInt() ?? 1,
      ));
    }
    Navigator.pushNamed(context, '/cart');
    SeToast.success(context, 'Added to your cart — review and check out.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 14, SeSpacing.gutter, 14),
        decoration: const BoxDecoration(color: SeColors.surface0),
        child: Row(
          children: [
            if (Navigator.canPop(context)) ...[
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
            ],
            Text('Order History', style: SeType.h1),
          ],
        ),
      );

  // A calm segmented control on a single tinted track. The selected segment is
  // a solid red fill with no glow and no shadow animation — the old glowing
  // gradient pill that lifted/dropped on every tap was the "annoying fast hover"
  // and the loudest AI tell on this screen.
  Widget _buildTabs() => Container(
        color: SeColors.surface0,
        padding:
            const EdgeInsets.fromLTRB(SeSpacing.gutter, 0, SeSpacing.gutter, 14),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: SeColors.surface50,
            borderRadius: SeRadius.pill,
            border: Border.all(color: SeColors.ink200, width: 1),
          ),
          child: Row(
            children: _tabs.asMap().entries.map((e) {
              final selected = _activeTab == e.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeTab = e.key),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? SeColors.red500 : Colors.transparent,
                      borderRadius: SeRadius.pill,
                    ),
                    child: Center(
                      child: Text(
                        e.value,
                        style: SeType.label.copyWith(
                          color: selected ? Colors.white : SeColors.ink500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );

  Widget _buildList() {
    if (_loading) {
      return SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: SeRadius.all(SeRadius.md),
            ),
            child: Row(
              children: const [
                SeSkeleton(width: 42, height: 42, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeSkeleton(width: 130, height: 13, radius: 5),
                      SizedBox(height: 8),
                      SeSkeleton(width: 90, height: 10, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: SeEmptyState(
          icon: SeIcons.orders,
          title: 'No orders here yet',
          message:
              'Your ${_tabs[_activeTab].toLowerCase()} orders will appear here.',
          ctaLabel: _activeTab == 0 ? 'Start an order' : null,
          onCta: _activeTab == 0
              ? () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false)
              : null,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(SeSpacing.gutter),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildOrderCard(items[index]),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? OrderStatus.pending;
    final displayStatus = _displayStatus(status);
    final colors = _statusColors(status);
    final merchantName = order['merchantName'] as String? ?? 'Merchant';
    final orderId = order['id'] as String? ?? '';
    final rawItems = order['items'] as List? ?? [];
    final itemsLabel = _itemsLabel(rawItems);
    final dateStr = _formatDate(order['createdAt']);
    final totalStr = _formatTotal(order['total']);
    final shortId = orderId.length > 8
        ? '#${orderId.substring(0, 8).toUpperCase()}'
        : '#${orderId.toUpperCase()}';

    return SeCard(
      shadow: SeElevation.e1,
      border: Border.all(color: SeColors.ink200, width: 1),
      onTap: () => Navigator.pushNamed(context, '/order-status',
          arguments: {'orderId': orderId}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.tint,
                  borderRadius: SeRadius.all(SeRadius.sm),
                ),
                child: Icon(SeIcons.orders, size: 21, color: colors.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(merchantName,
                        style: SeType.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(shortId,
                        style: SeType.tabular(SeType.label)
                            .copyWith(color: SeColors.ink400)),
                  ],
                ),
              ),
              SeChip.status(
                label: displayStatus,
                color: colors.color,
                tint: colors.tint,
              ),
            ],
          ),
          if (itemsLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(itemsLabel,
                style: SeType.bodyS.copyWith(color: SeColors.ink500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: SeColors.ink100),
          const SizedBox(height: 12),
          Row(
            children: [
              if (dateStr.isNotEmpty)
                Expanded(
                  child: Text(dateStr,
                      style: SeType.label.copyWith(color: SeColors.ink400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(width: 8),
              Text(totalStr,
                  style: SeType.tabular(SeType.title)
                      .copyWith(color: SeColors.ink900)),
              const SizedBox(width: 10),
              _cardAction(order, status, orderId),
            ],
          ),
        ],
      ),
    );
  }

  /// The trailing pill on an order card. An order still in flight gets "Track";
  /// a finished (delivered/cancelled) order that has line items gets "Reorder"
  /// instead, since tracking a completed delivery has nothing left to show.
  Widget _cardAction(
      Map<String, dynamic> order, String status, String orderId) {
    final finished =
        status == OrderStatus.delivered || status == OrderStatus.cancelled;
    if (finished && _canReorder(order)) {
      return GestureDetector(
        onTap: () => _reorder(order),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: SeColors.red50,
            borderRadius: SeRadius.pill,
            border: Border.all(color: SeColors.red100, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(SeIcons.refresh, size: 14, color: SeColors.red500),
              const SizedBox(width: 5),
              Text('Reorder',
                  style: SeType.label.copyWith(
                      color: SeColors.red600, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/order-status',
          arguments: {'orderId': orderId}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: SeColors.emberGradient,
          borderRadius: SeRadius.pill,
        ),
        child: Text('Track',
            style: SeType.label
                .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
