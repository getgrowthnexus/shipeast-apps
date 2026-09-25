import '../widgets/app_image.dart';
import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../widgets/se_app_bar.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

/// The full list of merchants in a category — the screen behind "See all".
///
/// Home only shows a truncated "Popular Near You" strip; this streams every
/// merchant the admin has published in [category] so the customer can browse
/// the whole category rather than the handful the home screen has room for.
class AllMerchantsScreen extends StatelessWidget {
  final String category;
  const AllMerchantsScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          SeGradientHeader(
            title: 'All $category',
            subtitle: 'Browse every partner near you',
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService.merchantsByCategory(category),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildLoading();
                }
                final merchants = snap.data ?? const [];
                if (merchants.isEmpty) {
                  return Center(
                    child: SeEmptyState(
                      icon: SeIcons.storefront,
                      title: 'No merchants yet',
                      message:
                          'We\'re onboarding $category partners near you — check back soon.',
                    ),
                  );
                }
                // Open merchants first, then by name, so a browsing customer
                // sees what they can actually order from at the top.
                final sorted = [...merchants]..sort((a, b) {
                    final ao = (a['isOpen'] as bool? ?? true) ? 0 : 1;
                    final bo = (b['isOpen'] as bool? ?? true) ? 0 : 1;
                    if (ao != bo) return ao - bo;
                    return (a['name'] as String? ?? '')
                        .toLowerCase()
                        .compareTo((b['name'] as String? ?? '').toLowerCase());
                  });
                return ListView.separated(
                  padding: const EdgeInsets.all(SeSpacing.gutter),
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _MerchantRow(m: sorted[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => Row(
            children: const [
              SeSkeleton(width: 60, height: 60, radius: 12),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 160, height: 15, radius: 6),
                    SizedBox(height: 8),
                    SeSkeleton(width: 210, height: 12, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// One merchant, rendered as the same list row the search screen uses so the
/// two browse surfaces stay visually identical.
class _MerchantRow extends StatelessWidget {
  final Map<String, dynamic> m;
  const _MerchantRow({required this.m});

  @override
  Widget build(BuildContext context) {
    final imageUrl = m['imageUrl'] as String? ?? '';
    final isOpen = m['isOpen'] as bool? ?? true;
    final rating = m['rating'];
    final ratingStr = rating is double
        ? rating.toStringAsFixed(1)
        : rating?.toString() ?? '4.5';
    // Integer JMD (P3-01) — displayed and charged from one field.
    final deliveryFee = (m['deliveryFee'] as num?)?.toInt() ?? 0;
    final deliveryTime = m['deliveryTime'] as String? ?? '25–35 min';
    final category = m['category'] as String? ?? '';

    return SeCard(
      onTap: () => Navigator.pushNamed(context, '/merchant', arguments: {
        'id': m['id'] ?? '',
        'name': m['name'] ?? '',
        'emoji': m['emoji'] as String? ?? '🍽️',
        'imageUrl': imageUrl,
        'category': category,
        'rating': ratingStr,
        'deliveryTime': deliveryTime,
        'deliveryFee': deliveryFee,
        'isOpen': isOpen,
      }),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: SeRadius.all(SeRadius.sm),
            child: SizedBox(
              width: 60,
              height: 60,
              child: AppImage(
                url: imageUrl,
                placeholder: const SeShimmer(
                    child: SeSkeleton(width: 60, height: 60, radius: 12)),
                errorWidget: _iconFallback(category),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m['name'] as String? ?? '',
                          style: SeType.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (!isOpen)
                      SeChip.status(
                        label: 'Closed',
                        color: SeColors.ink500,
                        tint: SeColors.surface50,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(SeIcons.star, size: 13, color: SeColors.gold500),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                          '$ratingStr · $deliveryTime · ${Money.deliveryFee(deliveryFee)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(SeIcons.caretRight, size: 18, color: SeColors.ink300),
        ],
      ),
    );
  }

  Widget _iconFallback(String category) => Container(
        color: SeColors.surface50,
        child: Icon(_categoryIcon(category), size: 26, color: SeColors.ink400),
      );

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food':
        return SeIcons.food;
      case 'Grocery':
        return SeIcons.grocery;
      case 'Pharmacy':
        return SeIcons.pharmacy;
      default:
        return SeIcons.storefront;
    }
  }
}
