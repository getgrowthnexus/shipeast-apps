import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/se_colors.dart';
import '../utils/category.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../services/firestore_service.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';
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

  // Client checklist filters: "Nearest, Highest rated, Lowest delivery fee,
  // Free delivery, Open now". The three sorts are exclusive; the two
  // conditions narrow the list and combine with anything.
  _Sort? _sort;
  bool _freeOnly = false;
  bool _openOnly = false;

  /// The phone's position, fetched once when "Nearest" is first chosen.
  Position? _here;
  bool _locating = false;

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
    // …or with a category chip selected (admin round: "20% off groceries"
    // opens Groceries). Only a known category — a stale value is ignored.
    if (args is Map && args['category'] is String) {
      final cat = MerchantCategory.of(args['category'] as String);
      if (cat != null) _category = cat.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _sub?.cancel();
    super.dispose();
  }

  /// The typed query, the category chips and the filter chips all narrow the
  /// same list, so picking "Groceries", "Open now" and typing "hi-lo" composes
  /// instead of one replacing another.
  List<Map<String, dynamic>> get _results {
    final q = _query.trim().toLowerCase();
    final list = _allMerchants.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final cat = (m['category'] as String? ?? '');
      if (_category.isNotEmpty && cat != _category) return false;
      if (_freeOnly && _fee(m) != 0) return false;
      if (_openOnly && !(m['isOpen'] as bool? ?? true)) return false;
      if (q.isEmpty) return true;
      return name.contains(q) ||
          cat.toLowerCase().contains(q) ||
          MerchantCategory.label(cat).toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _Sort.nearest:
        // Merchants with no pickup coordinates (admin never set a location)
        // sort after every one we can measure.
        list.sort((a, b) =>
            (_distance(a) ?? double.infinity)
                .compareTo(_distance(b) ?? double.infinity));
      case _Sort.rated:
        list.sort((a, b) => _rating(b).compareTo(_rating(a)));
      case _Sort.fee:
        list.sort((a, b) => _fee(a).compareTo(_fee(b)));
      case null:
        break;
    }
    return list;
  }

  static int _fee(Map<String, dynamic> m) =>
      (m['deliveryFee'] as num?)?.toInt() ?? 0;

  /// SCHEMA.md §merchants: `averageRating` is the field of record; older
  /// documents carry `rating`. Unrated merchants sort last.
  static double _rating(Map<String, dynamic> m) =>
      ((m['averageRating'] ?? m['rating']) as num?)?.toDouble() ?? 0;

  /// Metres from the phone to the merchant, or null when either is unknown.
  double? _distance(Map<String, dynamic> m) {
    final here = _here;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (here == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(
        here.latitude, here.longitude, lat, lng);
  }

  bool get _filtering =>
      _query.trim().isNotEmpty ||
      _category.isNotEmpty ||
      _sort != null ||
      _freeOnly ||
      _openOnly;

  Future<void> _toggleSort(_Sort s) async {
    if (_sort == s) {
      setState(() => _sort = null);
      return;
    }
    if (s == _Sort.nearest && _here == null) {
      final pos = await _locate();
      if (pos == null) return;
      _here = pos;
    }
    if (mounted) setState(() => _sort = s);
  }

  /// Asks for the phone's location once; explains itself if it cannot.
  Future<Position?> _locate() async {
    if (_locating) return null;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          SeToast.info(context, 'Turn on location to sort by nearest.');
        }
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          SeToast.info(context,
              'Allow location access to see the nearest merchants first.');
        }
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      if (mounted) {
        SeToast.info(context, 'Could not get your location. Try again.');
      }
      return null;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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
          _chipRow([
            for (final c in MerchantCategory.all)
              SeShellChip(
                label: c.display,
                icon: c.icon,
                selected: _category == c.value,
                onTap: () => setState(
                    () => _category = _category == c.value ? '' : c.value),
              ),
          ]),
          const SizedBox(height: 8),
          _chipRow([
            SeShellChip(
              label: _locating ? 'Locating…' : 'Nearest',
              icon: SeIcons.location,
              selected: _sort == _Sort.nearest,
              onTap: () => _toggleSort(_Sort.nearest),
            ),
            SeShellChip(
              label: 'Highest rated',
              icon: SeIcons.star,
              selected: _sort == _Sort.rated,
              onTap: () => _toggleSort(_Sort.rated),
            ),
            SeShellChip(
              label: 'Lowest delivery fee',
              icon: SeIcons.bike,
              selected: _sort == _Sort.fee,
              onTap: () => _toggleSort(_Sort.fee),
            ),
            SeShellChip(
              label: 'Free delivery',
              icon: SeIcons.gift,
              selected: _freeOnly,
              onTap: () => setState(() => _freeOnly = !_freeOnly),
            ),
            SeShellChip(
              label: 'Open now',
              icon: SeIcons.clock,
              selected: _openOnly,
              onTap: () => setState(() => _openOnly = !_openOnly),
            ),
          ]),
        ],
      );

  Widget _chipRow(List<Widget> chips) => SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => chips[i],
        ),
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
                  message: _query.trim().isNotEmpty
                      ? 'No merchants match “${_query.trim()}”. '
                          'Try a shorter word.'
                      : (_freeOnly || _openOnly)
                          ? 'No merchants match these filters right now.'
                          : _category.isNotEmpty
                              ? 'No ${MerchantCategory.label(_category)} '
                                  'merchants are listed yet.'
                              : 'No merchants are listed yet.',
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

/// The exclusive sort chips on the search screen.
enum _Sort { nearest, rated, fee }
