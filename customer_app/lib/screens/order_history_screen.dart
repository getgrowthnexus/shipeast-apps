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
import '../widgets/se_chip.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_toast.dart';

/// Orders.
///
/// The filter lives in the cap as a segmented control, so the list underneath
/// is the whole sheet. Each order is one flat panel: who, what state, what it
/// cost. Tapping anywhere on it opens tracking — the old card carried a
/// separate "Track" pill that did the same thing as the card it sat inside.
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
      statusBarIconBrightness: Brightness.light,
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

  String _formatDate(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = (createdAt as Timestamp).toDate();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
        'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final hour12 =
          dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      final now = DateTime.now();
      final sameDay =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      // "Today, 6:42 PM" is what a customer checking a live order wants; the
      // full date only earns its space once the order is history.
      if (sameDay) return 'Today, $hour12:$minute $ampm';
      return '${months[dt.month]} ${dt.day}, $hour12:$minute $ampm';
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
    final live = _orders.where((o) =>
        OrderStatus.isActive(o['status'] as String? ?? '')).length;
    return SePageScaffold(
      title: 'Orders',
      subtitle: _loading
          ? null
          : live > 0
              ? '$live in progress'
              : null,
      capBottom: SeShellTabs(
        tabs: _tabs,
        selected: _activeTab,
        onSelect: (i) => setState(() => _activeTab = i),
      ),
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading) return _loadingList();
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.orders,
            title: _activeTab == 0 ? 'No orders yet' : 'Nothing here',
            message: _activeTab == 0
                ? 'Your orders will show up here once you place one.'
                : 'You have no ${_tabs[_activeTab].toLowerCase()} orders.',
            ctaLabel: _activeTab == 0 ? 'Start an order' : null,
            onCta: _activeTab == 0
                ? () => Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (r) => false)
                : null,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, 20, SeSpacing.gutter, 110),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _orderCard(items[index]),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? OrderStatus.pending;
    final orderId = order['id'] as String? ?? '';
    final rawItems = order['items'] as List? ?? [];
    final shortId = orderId.length > 8
        ? '#${orderId.substring(0, 8).toUpperCase()}'
        : '#${orderId.toUpperCase()}';
    final finished =
        status == OrderStatus.delivered || status == OrderStatus.cancelled;

    return SeOrderCard(
      merchantName: order['merchantName'] as String? ?? 'Merchant',
      reference: shortId,
      status: status,
      itemsLabel: _itemsLabel(rawItems),
      date: _formatDate(order['createdAt']),
      total: Money.format((order['total'] as num?) ?? 0),
      onTap: () => Navigator.pushNamed(context, '/order-status',
          arguments: {'orderId': orderId}),
      onReorder:
          finished && _canReorder(order) ? () => _reorder(order) : null,
    );
  }

  Widget _loadingList() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 20, SeSpacing.gutter, 24),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
            ),
            child: Row(
              children: const [
                SeSkeleton(width: 40, height: 40, radius: SeRadius.sm),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeSkeleton(width: 140, height: 13, radius: 5),
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

/// One order, as a flat panel.
///
/// The status chip and the total are the two things a customer scans for, so
/// they sit at opposite corners with everything else between them.
class SeOrderCard extends StatelessWidget {
  final String merchantName;
  final String reference;
  final String status;
  final String itemsLabel;
  final String date;
  final String total;
  final VoidCallback onTap;
  final VoidCallback? onReorder;

  const SeOrderCard({
    super.key,
    required this.merchantName,
    required this.reference,
    required this.status,
    required this.itemsLabel,
    required this.date,
    required this.total,
    required this.onTap,
    this.onReorder,
  });

  /// Keyed off the canonical sets rather than individual statuses, so a status
  /// added later inherits a sensible colour instead of falling through to grey.
  static ({Color color, Color tint}) toneFor(String status) {
    if (status == OrderStatus.cancelled) {
      return (color: SeColors.dangerInk, tint: SeColors.dangerSoft);
    }
    if (status == OrderStatus.delivered) {
      return (color: SeColors.successInk, tint: SeColors.successSoft);
    }
    if (OrderStatus.isActive(status)) {
      return (color: SeColors.brandInk, tint: SeColors.brandSoft);
    }
    return (color: SeColors.ink500, tint: SeColors.surface50);
  }

  static IconData iconFor(String status) {
    if (status == OrderStatus.cancelled) return SeIcons.close;
    if (status == OrderStatus.delivered) return SeIcons.checkCircle;
    if (OrderStatus.isActive(status)) return SeIcons.bike;
    return SeIcons.orders;
  }

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(status);
    return SePanel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: SeRadius.all(SeRadius.sm),
                ),
                child: Icon(iconFor(status), size: 20, color: tone.color),
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
                    const SizedBox(height: 2),
                    Text(reference,
                        style: SeType.tabular(SeType.label)
                            .copyWith(color: SeColors.ink400)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SeChip.status(
                // Names the actual state ("Order Picked Up"), never the coarse
                // bucket and never the raw database value.
                label: OrderStatus.label(status),
                color: tone.color,
                tint: tone.tint,
              ),
            ],
          ),
          if (itemsLabel.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(itemsLabel,
                style: SeType.bodyS.copyWith(color: SeColors.ink500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: SeColors.ink100),
          const SizedBox(height: 11),
          Row(
            children: [
              if (date.isNotEmpty)
                Expanded(
                  child: Text(date,
                      style: SeType.label.copyWith(color: SeColors.ink400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              Text(total,
                  style: SeType.tabular(SeType.title)
                      .copyWith(color: SeColors.ink900)),
              if (onReorder != null) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onReorder,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(SeIcons.refresh,
                          size: 15, color: SeColors.brandAction),
                      const SizedBox(width: 4),
                      Text('Reorder',
                          style: SeType.label
                              .copyWith(color: SeColors.brandAction)),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                const Icon(SeIcons.caretRight,
                    size: 18, color: SeColors.ink300),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
