import 'dart:async';
import '../widgets/app_image.dart';
import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  List<Map<String, dynamic>> _allMerchants = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  bool _argsApplied = false;

  @override
  void initState() {
    super.initState();
    _sub = FirestoreService.allMerchantsStream().listen((merchants) {
      if (mounted) setState(() => _allMerchants = merchants);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A notification can deep-link here with a term pre-filled (checklist NT-4).
    if (_argsApplied) return;
    _argsApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['query'] is String) {
      final q = (args['query'] as String).trim();
      if (q.isNotEmpty) {
        _ctrl.text = q;
        _query = q;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _sub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return const [];
    final q = _query.toLowerCase();
    return _allMerchants
        .where((m) =>
            (m['name'] as String? ?? '').toLowerCase().contains(q) ||
            (m['category'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _query.trim().isEmpty
                ? _buildBrowse()
                : results.isEmpty
                    ? _buildNoResults()
                    : _buildResults(results),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: SeColors.emberGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, SeSpacing.gutter, 16),
            child: Row(
              children: [
                if (Navigator.canPop(context)) ...[
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(SeIcons.arrowLeft,
                          size: 20, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: SeRadius.all(SeRadius.md),
                      boxShadow: SeElevation.e2,
                    ),
                    child: Row(
                      children: [
                        const Icon(SeIcons.search,
                            size: 20, color: SeColors.ink400),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            style: SeType.body.copyWith(color: SeColors.ink900),
                            cursorColor: SeColors.red500,
                            decoration: InputDecoration(
                              hintText: 'Search merchants, food, items...',
                              hintStyle:
                                  SeType.body.copyWith(color: SeColors.ink400),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            },
                            child: const Icon(SeIcons.close,
                                size: 18, color: SeColors.ink400),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  static const List<(String, IconData, Color)> _quickCats = [
    ('Food', SeIcons.food, SeColors.red500),
    ('Grocery', SeIcons.grocery, SeColors.success),
    ('Pharmacy', SeIcons.pharmacy, SeColors.ocean500),
  ];

  void _setQuery(String q) {
    _ctrl.text = q;
    setState(() => _query = q);
  }

  /// An idle search screen shouldn't be a blank page with one icon. Show quick
  /// category filters and the full merchant list so there's always something to
  /// browse — the search box narrows it down, it doesn't gate the whole page.
  Widget _buildBrowse() {
    if (_allMerchants.isEmpty) {
      return Center(
        child: SeEmptyState(
          icon: SeIcons.search,
          title: 'Search merchants',
          message: 'Food, grocery, pharmacy & more',
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, SeSpacing.gutter, SeSpacing.gutter, 4),
            child: Row(
              children: [
                Text('Browse by category', style: SeType.section),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 10, SeSpacing.gutter, 0),
              itemCount: _quickCats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (label, icon, hue) = _quickCats[i];
                return SeChip(
                  label: label,
                  icon: icon,
                  fg: hue,
                  bg: SeColors.surface0,
                  onTap: () => _setQuery(label),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, 22, SeSpacing.gutter, 4),
            child: Text('All merchants', style: SeType.section),
          ),
        ),
        _buildResultsSliver(_allMerchants),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildNoResults() => Center(
        child: SeEmptyState(
          icon: SeIcons.noConnection,
          title: 'No results for "$_query"',
          message: 'Try a different search term',
          hue: SeColors.ink500,
          tint: SeColors.surface50,
        ),
      );

  Widget _buildResults(List<Map<String, dynamic>> results) =>
      ListView.separated(
        padding: const EdgeInsets.all(SeSpacing.gutter),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _merchantTile(results[i]),
      );

  Widget _buildResultsSliver(List<Map<String, dynamic>> results) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 12, SeSpacing.gutter, 0),
        sliver: SliverList.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _merchantTile(results[i]),
        ),
      );

  Widget _merchantTile(Map<String, dynamic> m) {
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
            shadow: SeElevation.e1,
            border: Border.all(color: SeColors.ink200, width: 1),
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
                          child:
                              SeSkeleton(width: 60, height: 60, radius: 12)),
                      errorWidget: _iconFallback(category),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['name'] as String? ?? '',
                          style: SeType.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (category.isNotEmpty)
                            SeChip.status(
                              label: category,
                              color: SeColors.red700,
                              tint: SeColors.red50,
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(SeIcons.star,
                                  size: 13, color: SeColors.gold500),
                              const SizedBox(width: 3),
                              Text(
                                  '$ratingStr · $deliveryTime · ${Money.deliveryFee(deliveryFee)}',
                                  style: SeType.bodyS
                                      .copyWith(color: SeColors.ink500)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(SeIcons.caretRight,
                    size: 18, color: SeColors.ink300),
              ],
            ),
          );
  }

  Widget _iconFallback(String category) => Container(
        color: SeColors.surface50,
        child: Icon(_categoryIcon(category),
            size: 26, color: SeColors.ink400),
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
