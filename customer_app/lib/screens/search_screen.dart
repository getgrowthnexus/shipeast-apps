import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../utils/category.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../services/firestore_service.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';

/// Search.
///
/// The live field lives in the brand cap, where home's fake one points. The
/// sheet below it is never blank: with no query it is a browsable list of
/// every merchant, so the box NARROWS the page rather than gating it. A search
/// screen that shows nothing until you type is a dead end for anyone who does
/// not already know what they want.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  String _category = '';
  List<Map<String, dynamic>> _allMerchants = [];
  bool _loaded = false;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  bool _argsApplied = false;

  static const List<(String, IconData, Color)> _quickCats = [
    ('Food', SeIcons.food, SeColors.catFood),
    ('Grocery', SeIcons.grocery, SeColors.catGrocery),
    ('Pharmacy', SeIcons.pharmacy, SeColors.catPharmacy),
    ('Packages', SeIcons.packages, SeColors.catPackages),
  ];

  @override
  void initState() {
    super.initState();
    _sub = FirestoreService.allMerchantsStream().listen((merchants) {
      if (mounted) {
        setState(() {
          _allMerchants = merchants;
          _loaded = true;
        });
      }
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

  /// The typed query and the category chips narrow the same list, so picking
  /// "Grocery" and typing "hi-lo" composes instead of one replacing the other.
  List<Map<String, dynamic>> get _results {
    final q = _query.trim().toLowerCase();
    return _allMerchants.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final cat = (m['category'] as String? ?? '');
      if (_category.isNotEmpty && cat != _category) return false;
      if (q.isEmpty) return true;
      return name.contains(q) || cat.toLowerCase().contains(q);
    }).toList();
  }

  bool get _filtering => _query.trim().isNotEmpty || _category.isNotEmpty;

  void _openMerchant(Map<String, dynamic> m) {
    final rating = m['rating'];
    final ratingStr = rating is double
        ? rating.toStringAsFixed(1)
        : rating?.toString() ?? '4.5';
    Navigator.pushNamed(context, '/merchant', arguments: {
      'id': m['id'] ?? '',
      'name': m['name'] ?? '',
      'emoji': m['emoji'] as String? ?? '🍽️',
      'imageUrl': m['imageUrl'] as String? ?? '',
      'category': m['category'] as String? ?? '',
      'rating': ratingStr,
      'deliveryTime': m['deliveryTime'] ?? '25–35 min',
      // Integer JMD (P3-01) — displayed and charged from one field.
      'deliveryFee': (m['deliveryFee'] as num?)?.toInt() ?? 0,
      'isOpen': m['isOpen'] as bool? ?? true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SePageScaffold(
      title: 'Search',
      capBottom: _field(),
      child: !_loaded
          ? _loadingList()
          : results.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      SeSpacing.gutter, 18, SeSpacing.gutter, 110),
                  itemCount: results.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SeSectionTitle(
                          title: _filtering
                              ? '${results.length} '
                                  '${results.length == 1 ? 'result' : 'results'}'
                              : 'All merchants',
                        ),
                      );
                    }
                    final m = results[i - 1];
                    final rating = m['rating'];
                    return SeMerchantRow(
                      name: m['name'] as String? ?? '',
                      imageUrl: m['imageUrl'] as String? ?? '',
                      category: m['category'] as String? ?? '',
                      rating: rating is double
                          ? rating.toStringAsFixed(1)
                          : rating?.toString() ?? '4.5',
                      deliveryTime: m['deliveryTime'] as String? ?? '25–35 min',
                      deliveryFee: (m['deliveryFee'] as num?)?.toInt() ?? 0,
                      isOpen: m['isOpen'] as bool? ?? true,
                      onTap: () => _openMerchant(m),
                    );
                  },
                ),
    );
  }

  /// The cap's field and its filter chips — both shared widgets, so the fake
  /// field on home and this real one are literally the same component.
  Widget _field() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeShellField(
            hint: 'Search stores, food, groceries, items…',
            controller: _ctrl,
            focusNode: _focus,
            onChanged: (v) => setState(() => _query = v),
            showClear: _query.isNotEmpty,
            onClear: () {
              _ctrl.clear();
              setState(() => _query = '');
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickCats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (label, icon, _) = _quickCats[i];
                final on = _category == label;
                return SeShellChip(
                  label: MerchantCategory.label(label),
                  icon: icon,
                  selected: on,
                  onTap: () => setState(() => _category = on ? '' : label),
                );
              },
            ),
          ),
        ],
      );

  Widget _loadingList() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 24, SeSpacing.gutter, 24),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Row(
            children: const [
              SeSkeleton(width: 56, height: 56, radius: SeRadius.sm),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 160, height: 14, radius: 5),
                    SizedBox(height: 8),
                    SeSkeleton(width: 220, height: 11, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: _filtering
              ? SeEmptyState(
                  icon: SeIcons.search,
                  title: 'Nothing matched',
                  message: _query.trim().isEmpty
                      ? 'No ${MerchantCategory.label(_category)} merchants are listed yet.'
                      : 'No merchants match “${_query.trim()}”. '
                          'Try a shorter word.',
                  hue: SeColors.ink500,
                  tint: SeColors.surface0,
                )
              : SeEmptyState(
                  icon: SeIcons.storefront,
                  title: 'No merchants yet',
                  message:
                      'We are onboarding partners near you — check back soon.',
                ),
        ),
      );
}
