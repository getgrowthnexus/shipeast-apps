import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../services/firestore_service.dart';
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

/// The full list of merchants in a category — the screen behind "See all".
///
/// Home only shows a truncated strip; this streams every merchant the admin has
/// published in [category] so the customer can browse the whole category rather
/// than the handful the home screen has room for.
///
/// The row is [SeMerchantRow], the same one search uses: two browse surfaces
/// that show the same thing should not look like two different products.
class AllMerchantsScreen extends StatelessWidget {
  final String category;
  const AllMerchantsScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: 'All $category',
      subtitle: 'Every partner near you',
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreService.merchantsByCategory(category),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _loading();
          }
          final merchants = snap.data ?? const [];
          if (merchants.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: SeEmptyState(
                  icon: SeIcons.storefront,
                  title: 'No merchants yet',
                  message: 'We are onboarding $category partners near you — '
                      'check back soon.',
                ),
              ),
            );
          }
          // Open merchants first, then by name, so a browsing customer sees
          // what they can actually order from at the top.
          final sorted = [...merchants]..sort((a, b) {
              final ao = (a['isOpen'] as bool? ?? true) ? 0 : 1;
              final bo = (b['isOpen'] as bool? ?? true) ? 0 : 1;
              if (ao != bo) return ao - bo;
              return (a['name'] as String? ?? '')
                  .toLowerCase()
                  .compareTo((b['name'] as String? ?? '').toLowerCase());
            });
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, 20, SeSpacing.gutter, 28),
            itemCount: sorted.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return SeSectionTitle(
                  title: '${sorted.length} '
                      '${sorted.length == 1 ? 'merchant' : 'merchants'}',
                );
              }
              return _row(context, sorted[i - 1]);
            },
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> m) {
    final imageUrl = m['imageUrl'] as String? ?? '';
    final isOpen = m['isOpen'] as bool? ?? true;
    final rating = m['rating'];
    final ratingStr = rating is double
        ? rating.toStringAsFixed(1)
        : rating?.toString() ?? '4.5';
    // Integer JMD (P3-01) — displayed and charged from one field.
    final deliveryFee = (m['deliveryFee'] as num?)?.toInt() ?? 0;
    final deliveryTime = m['deliveryTime'] as String? ?? '25–35 min';
    final cat = m['category'] as String? ?? category;

    return SeMerchantRow(
      name: m['name'] as String? ?? '',
      imageUrl: imageUrl,
      category: cat,
      rating: ratingStr,
      deliveryTime: deliveryTime,
      deliveryFee: deliveryFee,
      isOpen: isOpen,
      onTap: () => Navigator.pushNamed(context, '/merchant', arguments: {
        'id': m['id'] ?? '',
        'name': m['name'] ?? '',
        'emoji': m['emoji'] as String? ?? '🍽️',
        'imageUrl': imageUrl,
        'category': cat,
        'rating': ratingStr,
        'deliveryTime': deliveryTime,
        'deliveryFee': deliveryFee,
        'isOpen': isOpen,
      }),
    );
  }

  Widget _loading() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 20, SeSpacing.gutter, 28),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
              border: Border.all(color: SeColors.ink200),
            ),
            child: Row(
              children: const [
                SeSkeleton(width: 56, height: 56, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeSkeleton(width: 150, height: 14, radius: 6),
                      SizedBox(height: 8),
                      SeSkeleton(width: 200, height: 11, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
