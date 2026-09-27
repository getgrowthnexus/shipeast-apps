import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/order_status.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _activeTab = 0;
  static const _tabs = ['All', 'Completed', 'Cancelled'];

  String _formatDate(dynamic ts) {
    if (ts == null) return '—';
    final dt = (ts as Timestamp).toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);
    final timeStr =
        '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:'
        '${dt.minute.toString().padLeft(2, '0')} '
        '${dt.hour >= 12 ? 'PM' : 'AM'}';
    if (day == today) return 'Today, $timeStr';
    if (day == yesterday) return 'Yesterday, $timeStr';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, $timeStr';
  }

  ({String label, Color hue, Color tint, IconData icon}) _statusSpec(
      String status) {
    switch (status) {
      case OrderStatus.delivered:
        return (
          label: 'Completed',
          hue: SeColors.success,
          tint: SeColors.successTint,
          icon: SeIcons.checkCircle
        );
      case OrderStatus.cancelled:
        return (
          label: 'Cancelled',
          hue: SeColors.danger,
          tint: SeColors.dangerTint,
          icon: SeIcons.close
        );
      default:
        return (
          label: 'In progress',
          hue: SeColors.info,
          tint: SeColors.infoSoft,
          icon: SeIcons.bike
        );
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    if (_activeTab == 0) return all;
    if (_activeTab == 1) {
      return all.where((o) => o['status'] == OrderStatus.delivered).toList();
    }
    return all.where((o) => o['status'] == OrderStatus.cancelled).toList();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return SePageScaffold(
      showBack: false,
      title: 'Delivery history',
      subtitle: 'Your past deliveries',
      // The filter lives ON the cap, where it belongs: it scopes the whole
      // page, so it should not scroll away with the results it is scoping.
      capBottom: SeShellTabs(
        tabs: _tabs,
        selected: _activeTab,
        onSelect: (i) => setState(() => _activeTab = i),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DriverFirestoreService.driverOrderHistoryStream(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SeEmptyState(
              icon: SeIcons.noConnection,
              title: 'Could not load history',
              message: 'Check your connection and try again.',
              hue: SeColors.danger,
              tint: SeColors.dangerTint,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }

          final all = snapshot.data ?? [];
          final displayOrders = _filtered(all);
          final completed =
              all.where((o) => o['status'] == OrderStatus.delivered).length;

          return Column(
            children: [
              _summaryStrip(all.length, completed),
              Expanded(child: _list(displayOrders)),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryStrip(int total, int completed) {
    final rate = total > 0 ? (completed / total * 100).toStringAsFixed(0) : '0';
    return SeCard(
      margin: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, SeSpacing.x4, SeSpacing.gutter, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: SeSpacing.x4, vertical: SeSpacing.x4),
      child: Row(
        children: [
          _summaryItem('$total', 'Total Deliveries', SeColors.ink900),
          _vDivider(),
          _summaryItem('$completed', 'Completed', SeColors.success),
          _vDivider(),
          _summaryItem('$rate%', 'Completion', SeColors.info),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: SeType.tabular(SeType.h3).copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: SeType.bodyS.copyWith(color: SeColors.ink500)),
          ],
        ),
      );

  Widget _vDivider() =>
      Container(width: 1, height: 34, color: SeColors.ink200);

  Widget _skeleton() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(height: SeSpacing.x3),
          itemBuilder: (_, _) =>
              const SeSkeleton(height: 118, radius: SeRadius.md),
        ),
      );

  Widget _list(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      // The Cancelled tab is legitimately empty for most drivers — say something
      // reassuring there rather than reusing the generic "nothing here".
      final cancelledTab = _activeTab == 2;
      return SingleChildScrollView(
        child: SeEmptyState(
          icon: cancelledTab ? SeIcons.checkCircle : SeIcons.history,
          title: cancelledTab ? 'No cancellations' : 'No deliveries yet',
          message: cancelledTab
              ? 'You have not had a delivery cancelled. Keep it up.'
              : 'Your completed and cancelled deliveries will appear here',
          hue: cancelledTab ? SeColors.success : SeColors.brand,
          tint: cancelledTab ? SeColors.successTint : SeColors.brandSoft,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, SeSpacing.x4, SeSpacing.gutter, 100),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: SeSpacing.x3),
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Widget _card(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    final spec = _statusSpec(status);
    final isCompleted = status == OrderStatus.delivered;
    final merchant = order['merchantName'] as String? ?? 'Merchant';
    final id = order['id'] as String? ?? '';
    final shortId =
        id.length > 8 ? '#${id.substring(0, 8).toUpperCase()}' : '#$id';
    final pickupAddr = order['merchantAddress'] as String? ??
        order['address'] as String? ??
        '—';
    final deliverAddr = order['deliveryAddress'] as String? ?? '—';
    final total = (order['total'] as num?)?.toInt() ?? 0;
    final commission = DriverPay.creditedOn(order);
    final dateStr = _formatDate(
        order['deliveredAt'] ?? order['createdAt'] ?? order['acceptedAt']);

    return SeCard(
      padding: const EdgeInsets.all(SeSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: spec.tint, shape: BoxShape.circle),
                child: Icon(spec.icon, color: spec.hue, size: 20),
              ),
              const SizedBox(width: SeSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(merchant, style: SeType.title),
                    Text(shortId,
                        style: SeType.tabular(SeType.bodyS)
                            .copyWith(color: SeColors.ink400)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Completed trips show what the driver kept; anything else
                  // shows the order value, since no commission was earned.
                  Text(
                    Money.format(isCompleted ? commission : total),
                    style: SeType.tabular(SeType.h3).copyWith(
                        color:
                            isCompleted ? SeColors.success : SeColors.ink400),
                  ),
                  if (isCompleted)
                    Text('of ${Money.format(total)}',
                        style: SeType.tabular(SeType.eyebrow)
                            .copyWith(color: SeColors.ink400)),
                ],
              ),
            ],
          ),
          const SizedBox(height: SeSpacing.x3),
          Row(
            children: [
              const Icon(SeIcons.locationLine, size: 14, color: SeColors.ink300),
              const SizedBox(width: SeSpacing.x1),
              Expanded(
                child: Text('$pickupAddr → $deliverAddr',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ),
            ],
          ),
          const SizedBox(height: SeSpacing.x3),
          Row(
            children: [
              const Icon(SeIcons.clock, size: 14, color: SeColors.ink300),
              const SizedBox(width: SeSpacing.x1),
              Text(dateStr,
                  style: SeType.bodyS.copyWith(color: SeColors.ink400)),
              const Spacer(),
              SeChip.status(
                  label: spec.label, color: spec.hue, tint: spec.tint),
            ],
          ),
        ],
      ),
    );
  }
}
