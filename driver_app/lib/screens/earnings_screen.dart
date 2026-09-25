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
import '../widgets/se_earnings_chart.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_stat_tile.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  int _selectedPeriod = 0;
  static const _periods = ['Today', 'This Week', 'This Month'];

  DateTime _periodStart(int period) {
    final now = DateTime.now();
    if (period == 0) return DateTime(now.year, now.month, now.day);
    if (period == 1) {
      return DateTime(now.year, now.month, now.day - (now.weekday - 1));
    }
    return DateTime(now.year, now.month, 1);
  }

  List<Map<String, dynamic>> _filterByPeriod(
      List<Map<String, dynamic>> orders, int period) {
    final start = _periodStart(period);
    return orders.where((o) {
      if (o['status'] != OrderStatus.delivered) return false;
      final ts = o['deliveredAt'] as Timestamp?;
      if (ts == null) return false;
      return ts.toDate().isAfter(start);
    }).toList();
  }

  /// Bucketed driver commission (not gross order value) per period slot.
  List<double> _computeBars(
      List<Map<String, dynamic>> periodOrders, int period) {
    final int slots = period == 0
        ? 8
        : period == 1
            ? 7
            : 4;
    final bars = List<double>.filled(slots, 0);

    for (final o in periodOrders) {
      final ts = (o['deliveredAt'] as Timestamp?)?.toDate();
      if (ts == null) continue;
      final int idx = switch (period) {
        0 => ((ts.hour - 6) / 2).floor().clamp(0, 7).toInt(),
        1 => (ts.weekday - 1).clamp(0, 6).toInt(),
        _ => ((ts.day - 1) ~/ 7).clamp(0, 3).toInt(),
      };
      bars[idx] += DriverPay.creditedOn(o);
    }
    return bars;
  }

  List<String> _barLabels(int period) => switch (period) {
        0 => ['6a', '8a', '10a', '12p', '2p', '4p', '6p', '8p'],
        1 => ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        _ => ['Wk1', 'Wk2', 'Wk3', 'Wk4'],
      };

  String _chartTitle(int period) => switch (period) {
        0 => 'Hourly breakdown',
        1 => 'Daily breakdown',
        _ => 'Weekly breakdown',
      };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _header(),
          _periodTabs(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DriverFirestoreService.driverOrderHistoryStream(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SeEmptyState(
                    icon: SeIcons.noConnection,
                    title: 'Could not load earnings',
                    message:
                        'Check your connection and pull the screen to retry.',
                    hue: SeColors.danger,
                    tint: SeColors.dangerTint,
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }

                final allOrders = snapshot.data ?? [];
                final periodOrders = _filterByPeriod(allOrders, _selectedPeriod);
                final totalEarnings = periodOrders.fold<double>(
                  0,
                  (acc, o) => acc + DriverPay.creditedOn(o),
                );
                final bars = _computeBars(periodOrders, _selectedPeriod);

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(SeSpacing.gutter,
                      SeSpacing.x5, SeSpacing.gutter, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SeStatTile(
                              icon: SeIcons.trendUp,
                              label: 'Earned · ${_periods[_selectedPeriod]}',
                              value: totalEarnings.round(),
                              prefix: Money.symbol,
                            ),
                          ),
                          const SizedBox(width: SeSpacing.x3),
                          Expanded(
                            child: SeStatTile(
                              icon: SeIcons.bike,
                              label: 'Deliveries',
                              value: periodOrders.length,
                              hue: SeColors.ocean500,
                              tint: SeColors.oceanTint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SeSpacing.x5),

                      SeCard(
                        padding: const EdgeInsets.all(SeSpacing.x5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_chartTitle(_selectedPeriod),
                                style: SeType.title),
                            const SizedBox(height: SeSpacing.x5),
                            SeEarningsChart(
                              values: bars,
                              labels: _barLabels(_selectedPeriod),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: SeSpacing.x5),

                      Text('RECENT DELIVERIES', style: SeType.eyebrow),
                      const SizedBox(height: SeSpacing.x3),
                      _recentTrips(periodOrders),
                      const SizedBox(height: SeSpacing.x5),

                      _payoutCard(totalEarnings),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(gradient: SeColors.emberGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, SeSpacing.x4,
                SeSpacing.gutter, SeSpacing.x5),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(SeIcons.walletFill,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: SeSpacing.x3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Earnings',
                        style: SeType.h2.copyWith(color: Colors.white)),
                    Text('Your earnings, delivery by delivery',
                        style: SeType.bodyS.copyWith(
                            color: Colors.white.withValues(alpha: 0.82))),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  // Calm segmented control on a single track (no glow / gradient / shadow
  // animation) — matches the History tabs and never flashes on tap.
  Widget _periodTabs() => Container(
        color: SeColors.surface0,
        padding: const EdgeInsets.symmetric(
            horizontal: SeSpacing.gutter, vertical: SeSpacing.x3),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: SeColors.surface50,
            borderRadius: SeRadius.all(SeRadius.full),
            border: Border.all(color: SeColors.ink200, width: 1),
          ),
          child: Row(
            children: List.generate(_periods.length, (i) {
              final selected = _selectedPeriod == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPeriod = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? SeColors.red500 : Colors.transparent,
                      borderRadius: SeRadius.all(SeRadius.full),
                    ),
                    child: Center(
                      child: Text(
                        _periods[i],
                        style: SeType.label.copyWith(
                          color: selected ? Colors.white : SeColors.ink500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );

  Widget _skeleton() => SeShimmer(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(
                      child: SeSkeleton(height: 96, radius: SeRadius.md)),
                  SizedBox(width: SeSpacing.x3),
                  Expanded(
                      child: SeSkeleton(height: 96, radius: SeRadius.md)),
                ],
              ),
              const SizedBox(height: SeSpacing.x5),
              const SeSkeleton(height: 240, radius: SeRadius.md),
              const SizedBox(height: SeSpacing.x5),
              const SeSkeleton(height: 160, radius: SeRadius.md),
            ],
          ),
        ),
      );

  Widget _recentTrips(List<Map<String, dynamic>> orders) {
    final trips = orders.take(5).toList();
    if (trips.isEmpty) {
      return SeCard(
        padding: const EdgeInsets.symmetric(vertical: SeSpacing.x5),
        child: SeEmptyState(
          icon: SeIcons.bike,
          title: 'No deliveries yet',
          message: 'Deliveries you complete in this period will appear here.',
          padding: const EdgeInsets.symmetric(horizontal: SeSpacing.x5),
        ),
      );
    }

    return SeCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(trips.length, (i) {
          final o = trips[i];
          final id = o['id'] as String? ?? '';
          final shortId =
              id.length > 8 ? '#${id.substring(0, 8).toUpperCase()}' : '#$id';
          final merchant = o['merchantName'] as String? ?? 'Merchant';
          final addr = o['deliveryAddress'] as String? ?? '—';
          final commission = DriverPay.creditedOn(o);

          return Column(
            children: [
              if (i > 0)
                const Divider(
                    height: 1,
                    color: SeColors.ink100,
                    indent: SeSpacing.x5,
                    endIndent: SeSpacing.x5),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: SeSpacing.x5, vertical: SeSpacing.x4),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: SeColors.red50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(SeIcons.bike,
                          color: SeColors.red700, size: 18),
                    ),
                    const SizedBox(width: SeSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(merchant, style: SeType.title),
                          const SizedBox(height: 2),
                          Text(addr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SeType.bodyS
                                  .copyWith(color: SeColors.ink500)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(Money.format(commission),
                            style: SeType.tabular(SeType.title)
                                .copyWith(color: SeColors.success)),
                        const SizedBox(height: 2),
                        Text(shortId,
                            style: SeType.tabular(SeType.eyebrow)
                                .copyWith(color: SeColors.ink400)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Payout ledger card.
  ///
  /// Labelled as the period's accrued commission rather than a promised
  /// transfer: the app has no payout schedule data, and the old "Every Friday"
  /// string was a hardcoded claim the backend never backed up (audit §7.14).
  Widget _payoutCard(double total) => Container(
        padding: const EdgeInsets.all(SeSpacing.x5),
        decoration: BoxDecoration(
          gradient: SeColors.emberGradient,
          borderRadius: SeRadius.all(SeRadius.lg),
          boxShadow: SeElevation.glow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(SeIcons.receipt,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: SeSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EARNINGS DUE',
                          style: SeType.eyebrow.copyWith(
                              color:
                                  Colors.white.withValues(alpha: 0.82))),
                      Text(_periods[_selectedPeriod],
                          style: SeType.title.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                Text(Money.format(total),
                    style: SeType.tabular(SeType.h2)
                        .copyWith(color: Colors.white)),
              ],
            ),
            const SizedBox(height: SeSpacing.x3),
            Text(
              'Payouts are arranged by the ShipEast office — check with dispatch for your schedule.',
              style: SeType.bodyS
                  .copyWith(color: Colors.white.withValues(alpha: 0.80)),
            ),
          ],
        ),
      );
}
