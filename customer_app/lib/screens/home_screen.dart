import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../utils/money.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../models/package_pricing.dart';
import '../services/firestore_service.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_button.dart';
import '../widgets/se_listing.dart';
import '../widgets/se_page.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_bottom_sheet.dart';
import 'all_merchants_screen.dart';

/// The storefront.
///
/// Built on [SePageScaffold] like everything else, with the greeting and the
/// search field living in the brand cap. Putting search ON the red rather than
/// in the scrolling sheet is deliberate: it is the one control a customer
/// reaches for from any scroll position, so it does not get to scroll away.
///
/// The sheet leads with categories, because choosing what kind of errand this
/// is comes before choosing who runs it. Everything below reacts to that one
/// choice.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategory = 0;
  String _userName = '';
  String? _avatarUrl;
  final Set<String> _favourites = {};

  StreamSubscription<Map<String, dynamic>?>? _nameSub;

  /// Weight-band pricing from `settings/pricing` (P5-01).
  ///
  /// Null means packages are not priced. The form then refuses to take a
  /// request rather than quoting a number nobody configured — see
  /// [PackagePricing.fromSettings].
  PackagePricing? _packagePricing;
  bool _packagePricingLoaded = false;

  // Firestore merchants by category index
  final Map<int, List<Map<String, dynamic>>> _firestoreMerchants = {};
  final Map<int, bool> _merchantsLoaded = {};
  final Map<int, StreamSubscription<List<Map<String, dynamic>>>> _subs = {};

  static const _categoryLabels = ['Food', 'Grocery', 'Packages', 'Pharmacy'];

  // Category tile spec: icon + per-category hue (SEDS §1.5).
  static const List<Map<String, dynamic>> _categories = [
    {'icon': SeIcons.food, 'label': 'Food', 'hue': SeColors.catFood, 'tint': SeColors.catFoodTint},
    {'icon': SeIcons.grocery, 'label': 'Grocery', 'hue': SeColors.catGrocery, 'tint': SeColors.catGroceryTint},
    {'icon': SeIcons.packages, 'label': 'Packages', 'hue': SeColors.catPackages, 'tint': SeColors.catPackagesTint},
    {'icon': SeIcons.pharmacy, 'label': 'Pharmacy', 'hue': SeColors.catPharmacy, 'tint': SeColors.catPharmacyTint},
  ];

  // Package-type accents drawn from the brand palette (no off-palette hues).
  static const List<Map<String, dynamic>> _packageCategories = [
    {'icon': SeIcons.food, 'label': 'Food Items', 'color': SeColors.warning},
    {'icon': SeIcons.box, 'label': 'Clothing', 'color': SeColors.brand},
    {'icon': SeIcons.box, 'label': 'Glassware', 'color': SeColors.info},
    {'icon': SeIcons.box, 'label': 'Electronics', 'color': SeColors.info},
    {'icon': SeIcons.note, 'label': 'Documents', 'color': SeColors.success},
    {'icon': SeIcons.packages, 'label': 'Custom Package', 'color': SeColors.ink500},
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _loadUserName();
    _loadPackagePricing();
    _subscribeMerchants(0);
    _subscribeMerchants(1);
    _subscribeMerchants(3);
  }

  @override
  void dispose() {
    _nameSub?.cancel();
    for (final sub in _subs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  void _subscribeMerchants(int catIndex) {
    final label = _categoryLabels[catIndex];
    _subs[catIndex] =
        FirestoreService.merchantsByCategory(label).listen((merchants) {
      if (mounted) {
        setState(() {
          _firestoreMerchants[catIndex] = merchants;
          _merchantsLoaded[catIndex] = true;
        });
      }
    });
  }

  void _loadUserName() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _nameSub = FirestoreService.watchUserProfile(uid).listen((data) {
      if (!mounted) return;
      setState(() {
        final name = data?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          _userName = name;
        }
        _avatarUrl = data?['avatarUrl'] as String?;
      });
    });
  }

  String get _firstName {
    final parts = _userName.trim().split(' ');
    return parts.isNotEmpty ? parts[0] : _userName;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _goToProfile() => Navigator.pushNamed(context, '/profile');

  // Returns null when still loading, empty list when loaded but no merchants
  List<Map<String, dynamic>>? _merchantsFor(int catIndex) {
    if (_merchantsLoaded[catIndex] != true) return null;
    return _firestoreMerchants[catIndex] ?? [];
  }

  void _toggleFavourite(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_favourites.contains(id)) {
        _favourites.remove(id);
        SeToast.info(context, 'Removed from favourites');
      } else {
        _favourites.add(id);
        SeToast.success(context, 'Added to favourites');
      }
    });
  }

  Future<void> _loadPackagePricing() async {
    final pricing = await FirestoreService.packagePricing();
    if (!mounted) return;
    setState(() {
      _packagePricing = pricing;
      _packagePricingLoaded = true;
    });
  }

  // ── Package request sheet ─────────────────────────────────────────────────
  //
  // P5-01, audit §10 — the most serious honesty defect in the codebase. This
  // form used to validate two addresses, pop the sheet, show "Package request
  // submitted! We'll contact you shortly," and write NOTHING. No order, no
  // record, no queue, nobody to call. It was reachable from one of four
  // top-level home categories.
  //
  // It now quotes a price from the admin-configured weight bands and writes a
  // real order that runs the ordinary pending → delivered lifecycle.
  void _showPackageForm(String category) {
    // No price list, no quote. Taking the request anyway would re-create the
    // original defect in a politer voice: the customer would still be left
    // waiting for a call that has no queue behind it.
    final pricing = _packagePricing;
    if (pricing == null) {
      SeToast.info(
        context,
        _packagePricingLoaded
            ? 'Package delivery is not available yet.'
            : 'Still loading package pricing — one moment.',
      );
      return;
    }

    final pickupCtrl = TextEditingController();
    final deliveryCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final instructionsCtrl = TextEditingController();
    bool packingRequired = false;
    bool submitting = false;

    showSeBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: SeSpacing.gutter,
            right: SeSpacing.gutter,
            top: 4,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SeSheetHandle(),
                const SizedBox(height: 14),
                Text('Package request', style: SeType.h2),
                const SizedBox(height: 4),
                Text(
                  'Tell us what is moving and where, and we will price it.',
                  style: SeType.bodyS.copyWith(color: SeColors.ink500),
                ),
                const SizedBox(height: 20),
                const SeFieldLabel('Item category'),
                _ReadOnlyField(icon: SeIcons.packages, value: category),
                const SizedBox(height: 14),
                SeTextField(
                  controller: pickupCtrl,
                  label: 'Pickup location',
                  hint: 'Enter pickup address',
                  icon: SeIcons.locationLine,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: deliveryCtrl,
                  label: 'Delivery location',
                  hint: 'Enter delivery address',
                  icon: SeIcons.location,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: weightCtrl,
                  label: 'Estimated weight (kg)',
                  hint: 'e.g. 2.5',
                  icon: SeIcons.scales,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // The price depends on this field, so the quote has to move
                  // with it. A customer who only sees the figure after
                  // submitting cannot decide whether to send the parcel.
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 14),
                const SeFieldLabel('Packing required'),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: SeColors.field,
                    borderRadius: SeRadius.inputRadius,
                    border: Border.all(color: SeColors.ink200, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(SeIcons.box, size: 20, color: SeColors.ink400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(packingRequired ? 'Yes' : 'No',
                            style:
                                SeType.body.copyWith(color: SeColors.ink900)),
                      ),
                      if (pricing.packingSurcharge > 0)
                        Text(
                          '+${Money.format(pricing.packingSurcharge)}',
                          style:
                              SeType.bodyS.copyWith(color: SeColors.ink500),
                        ),
                      Switch(
                        value: packingRequired,
                        onChanged: (v) =>
                            setModalState(() => packingRequired = v),
                        activeThumbColor: SeColors.brandAction,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: instructionsCtrl,
                  label: 'Special instructions',
                  hint: 'Anything the driver should know…',
                  icon: SeIcons.note,
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 18),
                _quoteBlock(pricing, weightCtrl.text, packingRequired),
                const SizedBox(height: 18),
                SeButton(
                  label: submitting ? 'Placing order…' : 'Place package order',
                  onPressed: submitting
                      ? null
                      : () async {
                          if (pickupCtrl.text.trim().isEmpty ||
                              deliveryCtrl.text.trim().isEmpty) {
                            SeToast.error(ctx,
                                'Please add pickup and delivery addresses');
                            return;
                          }
                          final weight = parseWeightKg(weightCtrl.text);
                          if (weight == null) {
                            SeToast.error(
                                ctx, 'Enter the weight in kilograms, e.g. 2.5');
                            return;
                          }
                          final quote = pricing.quote(
                              weightKg: weight, packing: packingRequired);
                          if (quote == null) {
                            SeToast.error(
                                ctx,
                                'We cannot carry a parcel that heavy — '
                                'up to ${pricing.maxWeightKg.round()} kg.');
                            return;
                          }
                          setModalState(() => submitting = true);
                          try {
                            final orderId =
                                await FirestoreService.placePackageOrder(
                              itemCategory: category,
                              pickupAddress: pickupCtrl.text.trim(),
                              deliveryAddress: deliveryCtrl.text.trim(),
                              weightKg: weight,
                              packingRequired: packingRequired,
                              instructions: instructionsCtrl.text.trim(),
                              quote: quote,
                              paymentMethod: 'Cash on Delivery',
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            // The tracking screen, not a toast. The whole point
                            // of P5-01 is that there is now something to track.
                            Navigator.pushNamed(context, '/order-status',
                                arguments: {'orderId': orderId});
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setModalState(() => submitting = false);
                            SeToast.error(ctx,
                                'Could not place the package order. Please try again.');
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Live price for what the customer has typed so far.
  ///
  /// Three distinct states, deliberately not collapsed into one: nothing typed
  /// yet, a weight we cannot carry, and a real quote. The middle one used to be
  /// indistinguishable from the last, because there was no price at all.
  Widget _quoteBlock(
      PackagePricing pricing, String weightText, bool packingRequired) {
    final weight = parseWeightKg(weightText);
    final quote = weight == null
        ? null
        : pricing.quote(weightKg: weight, packing: packingRequired);

    if (weight == null) {
      return SeNotice.info('Enter a weight to see the price.');
    }

    if (quote == null) {
      return SeNotice.danger(
          'We carry parcels up to ${pricing.maxWeightKg.round()} kg. '
          'Contact support for anything heavier.');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(color: SeColors.ink200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeMoneyLine(
              label: 'Delivery (${quote.bandLabel})',
              value: Money.format(quote.deliveryFee)),
          if (quote.serviceFee > 0)
            SeMoneyLine(
                label: 'Packing', value: Money.format(quote.serviceFee)),
          const Divider(height: 16, color: SeColors.ink200),
          SeMoneyLine(
              label: 'Total', value: Money.format(quote.total), strong: true),
          const SizedBox(height: 6),
          Text('Cash on delivery. Nothing is charged now.',
              style: SeType.bodyS.copyWith(color: SeColors.ink400)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      showBack: false,
      capTitle: _greetingBlock(),
      trailing: _avatar(),
      capBottom: _searchField(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 110),
        children: [
          _categoryRow(),
          const SizedBox(height: 24),
          if (_selectedCategory == 2) _packagesGrid() else _merchantList(),
        ],
      ),
    );
  }

  // ── Cap ───────────────────────────────────────────────────────────────────

  Widget _greetingBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(SeIcons.locationFill,
                  size: 13, color: SeColors.shellMark),
              const SizedBox(width: 4),
              Text('St. Thomas, Jamaica',
                  style: SeType.label.copyWith(color: SeColors.shellMark)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _userName.isEmpty ? _greeting : '$_greeting, $_firstName',
            style: SeType.h2.copyWith(color: SeColors.shellInk),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );

  Widget _avatar() => GestureDetector(
        onTap: _goToProfile,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: _avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (ctx, url) => _avatarInitials(),
                      errorWidget: (ctx, url, err) => _avatarInitials(),
                    )
                  : _avatarInitials(),
            ),
          ),
        ),
      );

  Widget _avatarInitials() {
    final initials = _userName.isNotEmpty
        ? _userName
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : '';
    return Center(
      child: initials.isNotEmpty
          ? Text(initials,
              style: SeType.jakarta(14, FontWeight.w800,
                  color: SeColors.shellInk))
          : const Icon(SeIcons.user, size: 20, color: SeColors.shellInk),
    );
  }

  /// Not a real field — a button dressed as one, and dressed by the same
  /// widget the search screen uses live. Typing happens there, which owns the
  /// results; a live field here would need to own them too, and then there
  /// would be two.
  Widget _searchField() => SeShellField(
        hint: 'Search restaurants, shops, items…',
        onTap: () => Navigator.pushNamed(context, '/search'),
      );

  // ── Sheet ─────────────────────────────────────────────────────────────────

  Widget _categoryRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
        child: Row(
          children: List.generate(_categories.length, (i) {
            final c = _categories[i];
            // Equal slots, not intrinsic widths — see SeCategoryTile.
            return Expanded(
              child: SeCategoryTile(
                label: c['label'] as String,
                icon: c['icon'] as IconData,
                hue: c['hue'] as Color,
                tint: c['tint'] as Color,
                selected: _selectedCategory == i,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategory = i);
                },
              ),
            );
          }),
        ),
      );

  Widget _overseasCard() => Padding(
        padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 0, SeSpacing.gutter, 24),
        child: GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/overseas-order'),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
              border: Border.all(color: SeColors.ink200),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SeColors.brandSoft,
                    borderRadius: SeRadius.all(SeRadius.sm),
                  ),
                  child: const Icon(SeIcons.plane,
                      size: 22, color: SeColors.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The total is confirmed by hand, so the card promises
                      // what the screen behind it actually does: a request to
                      // shop and deliver, answered by a person.
                      Text('Send to family back home', style: SeType.title),
                      const SizedBox(height: 2),
                      Text('We shop in Jamaica and deliver to them.',
                          style: SeType.bodyS.copyWith(color: SeColors.ink500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(SeIcons.caretRight,
                    size: 20, color: SeColors.ink300),
              ],
            ),
          ),
        ),
      );

  Widget _packagesGrid() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SeSectionTitle(title: 'What are you sending?'),
            const SizedBox(height: 4),
            Text('Pick a type and we will quote it by weight.',
                style: SeType.bodyS.copyWith(color: SeColors.ink500)),
            const SizedBox(height: 14),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              itemCount: _packageCategories.length,
              itemBuilder: (context, i) {
                final pkg = _packageCategories[i];
                final color = pkg['color'] as Color;
                return GestureDetector(
                  onTap: () => _showPackageForm(pkg['label'] as String),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SeColors.surface0,
                      borderRadius: SeRadius.all(SeRadius.md),
                      border: Border.all(color: SeColors.ink200),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: SeRadius.all(SeRadius.sm),
                          ),
                          child: Icon(pkg['icon'] as IconData,
                              size: 21, color: color),
                        ),
                        const SizedBox(height: 10),
                        Text(pkg['label'] as String,
                            textAlign: TextAlign.center,
                            style: SeType.title.copyWith(fontSize: 14)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      );

  Widget _merchantList() {
    final merchants = _merchantsFor(_selectedCategory);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _overseasCard(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
          child: SeSectionTitle(
            title: 'Popular near you',
            actionLabel: 'See all',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AllMerchantsScreen(
                    category: _categoryLabels[_selectedCategory]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
          child: merchants == null
              ? SeShimmer(
                  child: Column(
                    children: List.generate(2, (_) => _shimmerCard()),
                  ),
                )
              : merchants.isEmpty
                  ? SeEmptyState(
                      icon: SeIcons.storefront,
                      title: 'No merchants yet',
                      message:
                          'We are onboarding partners near you — check back soon.',
                      hue: _categories[_selectedCategory]['hue'] as Color,
                      tint: _categories[_selectedCategory]['tint'] as Color,
                    )
                  : Column(
                      children: [
                        for (final m in merchants) _merchantCard(m),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _shimmerCard() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(color: SeColors.ink200),
        ),
        clipBehavior: Clip.antiAlias,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeSkeleton(width: double.infinity, height: 150, radius: 0),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SeSkeleton(width: 170, height: 16, radius: 6),
                  SizedBox(height: 10),
                  SeSkeleton(width: 230, height: 12, radius: 5),
                ],
              ),
            ),
          ],
        ),
      );

  Color _catHue(int i) => (_categories[i]['hue'] as Color);

  Widget _merchantCard(Map<String, dynamic> m) {
    final rating = m['rating'];
    final ratingStr = rating is double
        ? rating.toStringAsFixed(1)
        : rating?.toString() ?? '4.5';
    final isOpen = m['isOpen'] as bool? ?? true;
    // P3-01: read the integer directly. This used to regex-scrape a number out
    // of a display string and fall back to a hardcoded 100 when that failed —
    // the source of the J$100 phantom charge.
    final deliveryFee = (m['deliveryFee'] as num?)?.toInt() ?? 0;
    final id = (m['id'] ?? '').toString();

    return SeMerchantCard(
      name: m['name'] as String? ?? '',
      imageUrl: m['imageUrl'] as String? ?? '',
      rating: ratingStr,
      deliveryTime: m['deliveryTime'] as String? ?? '25–35 min',
      deliveryFee: deliveryFee,
      isOpen: isOpen,
      promo: m['promo'] as String?,
      hue: _catHue(_selectedCategory),
      favourite: _favourites.contains(id),
      onFavourite: () => _toggleFavourite(id),
      onTap: () {
        Navigator.pushNamed(context, '/merchant', arguments: {
          'id': m['id'] ?? '',
          'name': m['name'] ?? '',
          'emoji': m['emoji'] as String? ?? '🍽️',
          'imageUrl': m['imageUrl'] as String? ?? '',
          'category': _categoryLabels[_selectedCategory],
          'rating': ratingStr,
          'deliveryTime': m['deliveryTime'] ?? '25–35 min',
          'deliveryFee': deliveryFee,
          'isOpen': isOpen,
        });
      },
    );
  }
}

/// The chosen package type, shown as a filled-in field rather than a heading.
/// It is a value the customer picked on the previous step, so it belongs in the
/// form reading like the fields around it — just one they cannot edit here.
class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String value;
  const _ReadOnlyField({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: SeColors.field,
          borderRadius: SeRadius.inputRadius,
          border: Border.all(color: SeColors.ink200, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: SeColors.ink400),
            const SizedBox(width: 10),
            Text(value, style: SeType.body.copyWith(color: SeColors.ink900)),
          ],
        ),
      );
}
