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
import '../widgets/app_image.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_button.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_bottom_sheet.dart';
import 'all_merchants_screen.dart';

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

  static const List<Map<String, dynamic>> _packageCategories = [
    {'icon': SeIcons.food, 'label': 'Food Items', 'color': Color(0xFFF97316)},
    {'icon': SeIcons.box, 'label': 'Clothing', 'color': Color(0xFF8B5CF6)},
    {'icon': SeIcons.box, 'label': 'Glassware', 'color': SeColors.ocean500},
    {'icon': SeIcons.box, 'label': 'Electronics', 'color': Color(0xFF3B82F6)},
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
              style: SeType.jakarta(14, FontWeight.w800, color: Colors.white))
          : const Icon(SeIcons.user, size: 20, color: Colors.white),
    );
  }

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
                const SizedBox(height: 12),
                Text('Package Request', style: SeType.h2),
                const SizedBox(height: 4),
                Text(
                  'Fill in the details below to submit your package request.',
                  style: SeType.body.copyWith(color: SeColors.ink500),
                ),
                const SizedBox(height: 20),
                Text('Item Category',
                    style: SeType.label.copyWith(color: SeColors.ink700)),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: SeColors.surface50,
                    borderRadius: SeRadius.inputRadius,
                    border: Border.all(color: SeColors.ink200, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(SeIcons.packages,
                          size: 20, color: SeColors.ink400),
                      const SizedBox(width: 10),
                      Text(category,
                          style:
                              SeType.body.copyWith(color: SeColors.ink900)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: pickupCtrl,
                  label: 'Pickup Location',
                  hint: 'Enter pickup address',
                  icon: SeIcons.locationLine,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: deliveryCtrl,
                  label: 'Delivery Location',
                  hint: 'Enter delivery address',
                  icon: SeIcons.location,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: weightCtrl,
                  label: 'Estimated Weight (kg)',
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
                Text('Packing Required',
                    style: SeType.label.copyWith(color: SeColors.ink700)),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: SeColors.surface50,
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
                      Switch(
                        value: packingRequired,
                        onChanged: (v) =>
                            setModalState(() => packingRequired = v),
                        activeThumbColor: SeColors.red500,
                      ),
                      if (pricing.packingSurcharge > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '+${Money.format(pricing.packingSurcharge)}',
                            style: SeType.bodyS
                                .copyWith(color: SeColors.ink500),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SeTextField(
                  controller: instructionsCtrl,
                  label: 'Special Instructions',
                  hint: 'Any special handling instructions...',
                  icon: SeIcons.note,
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 18),
                _quoteBlock(pricing, weightCtrl.text, packingRequired),
                const SizedBox(height: 18),
                SeButton(
                  label: submitting ? 'Placing order…' : 'Place Package Order',
                  icon: SeIcons.check,
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
      return _quoteShell(
        SeColors.oceanTint,
        Row(
          children: [
            const Icon(SeIcons.info, size: 18, color: SeColors.ocean500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enter a weight to see the price.',
                style: SeType.bodyS.copyWith(color: SeColors.ocean500),
              ),
            ),
          ],
        ),
      );
    }

    if (quote == null) {
      return _quoteShell(
        SeColors.dangerTint,
        Row(
          children: [
            const Icon(SeIcons.warningCircle, size: 18, color: SeColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'We carry parcels up to ${pricing.maxWeightKg.round()} kg. '
                'Contact support for anything heavier.',
                style: SeType.bodyS.copyWith(color: SeColors.danger),
              ),
            ),
          ],
        ),
      );
    }

    Widget line(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: strong
                        ? SeType.title
                        : SeType.bodyS.copyWith(color: SeColors.ink500)),
              ),
              Text(value,
                  style: SeType.tabular(strong ? SeType.title : SeType.bodyS)
                      .copyWith(
                          color: strong ? SeColors.ink900 : SeColors.ink700)),
            ],
          ),
        );

    return _quoteShell(
      SeColors.surface50,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Delivery (${quote.bandLabel})', Money.format(quote.deliveryFee)),
          if (quote.serviceFee > 0)
            line('Packing', Money.format(quote.serviceFee)),
          const Divider(height: 14, color: SeColors.ink200),
          line('Total', Money.format(quote.total), strong: true),
          const SizedBox(height: 4),
          Text('Cash on delivery. Nothing is charged now.',
              style: SeType.bodyS.copyWith(color: SeColors.ink400)),
        ],
      ),
    );
  }

  Widget _quoteShell(Color background, Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: SeRadius.all(SeRadius.md),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOverseasBanner(),
                  _buildCategories(),
                  if (_selectedCategory == 2)
                    _buildPackagesGrid()
                  else
                    _buildMerchants(),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: SeColors.emberGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 14, SeSpacing.gutter, 20),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(SeIcons.locationFill,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 4),
                            Text(
                              'St. Thomas, Jamaica',
                              style: SeType.label.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _userName.isEmpty
                              ? _greeting
                              : '$_greeting, $_firstName',
                          style: SeType.h2.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _goToProfile,
                    child: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.5),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: _avatarUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: _avatarUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (ctx, url) => _avatarInitials(),
                                  errorWidget: (ctx, url, err) =>
                                      _avatarInitials(),
                                )
                              : _avatarInitials(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/search'),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: SeRadius.all(SeRadius.sm),
                    boxShadow: SeElevation.e1,
                  ),
                  child: Row(
                    children: [
                      const Icon(SeIcons.search,
                          size: 19, color: SeColors.ink400),
                      const SizedBox(width: 9),
                      Text(
                        'Search food, merchants, items…',
                        style:
                            SeType.body.copyWith(color: SeColors.ink400),
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
  }

  Widget _buildOverseasBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 16, SeSpacing.gutter, 0),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/overseas-order'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E9488), Color(0xFF0B6E66)],
            ),
            borderRadius: SeRadius.all(SeRadius.md),
            boxShadow: SeElevation.glowColor(SeColors.ocean500, opacity: 0.28),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(SeIcons.packages, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The total is confirmed by hand, so the banner promises
                    // what the screen behind it actually does: a request to
                    // shop and deliver, answered by a person.
                    Text('Send to Family in Jamaica',
                        style: SeType.title.copyWith(color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('Abroad? We’ll shop locally & deliver to them',
                        style: SeType.bodyS.copyWith(
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(SeIcons.caretRight,
                  size: 20, color: Colors.white.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 22, SeSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Categories', style: SeType.section),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_categories.length, (i) {
              final c = _categories[i];
              return SeCategoryTile(
                label: c['label'] as String,
                icon: c['icon'] as IconData,
                hue: c['hue'] as Color,
                tint: c['tint'] as Color,
                selected: _selectedCategory == i,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategory = i);
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 24, SeSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Package Type', style: SeType.section),
          const SizedBox(height: 4),
          Text('Choose what you need shipped and fill in the details.',
              style: SeType.body.copyWith(color: SeColors.ink500)),
          const SizedBox(height: 14),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: _packageCategories.length,
            itemBuilder: (context, i) {
              final pkg = _packageCategories[i];
              final color = pkg['color'] as Color;
              return SeCard(
                onTap: () => _showPackageForm(pkg['label'] as String),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: Icon(pkg['icon'] as IconData,
                          size: 24, color: color),
                    ),
                    const SizedBox(height: 10),
                    Text(pkg['label'] as String,
                        textAlign: TextAlign.center,
                        style: SeType.title.copyWith(fontSize: 14)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMerchants() {
    final merchants = _merchantsFor(_selectedCategory);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, 24, SeSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Popular Near You', style: SeType.section),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AllMerchantsScreen(
                        category: _categoryLabels[_selectedCategory]),
                  ),
                ),
                child: Row(
                  children: [
                    Text('See all',
                        style:
                            SeType.label.copyWith(color: SeColors.red500)),
                    const Icon(SeIcons.caretRight,
                        size: 14, color: SeColors.red500),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (merchants == null)
            SeShimmer(
              child: Column(
                children: List.generate(3, (_) => _shimmerMerchantCard()),
              ),
            )
          else if (merchants.isEmpty)
            SeEmptyState(
              icon: SeIcons.storefront,
              title: 'No merchants yet',
              message: 'We\'re onboarding partners near you — check back soon.',
              hue: _categories[_selectedCategory]['hue'] as Color,
              tint: _categories[_selectedCategory]['tint'] as Color,
            )
          else
            ...merchants
                .asMap()
                .entries
                .map((e) => _merchantCard(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _shimmerMerchantCard() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: SeRadius.all(SeRadius.md),
          boxShadow: SeElevation.e1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
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

  Widget _merchantCard(int index, Map<String, dynamic> m) {
    final rating = m['rating'];
    final ratingStr = rating is double
        ? rating.toStringAsFixed(1)
        : rating?.toString() ?? '4.5';
    final isOpen = m['isOpen'] as bool? ?? true;
    // P3-01: read the integer directly. This used to regex-scrape a number out
    // of a display string and fall back to a hardcoded 100 when that failed —
    // the source of the J$100 phantom charge.
    final deliveryFee = (m['deliveryFee'] as num?)?.toInt() ?? 0;
    final promo = m['promo'] as String?;
    final imageUrl = m['imageUrl'] as String? ?? '';
    final id = (m['id'] ?? '').toString();
    final fav = _favourites.contains(id);
    final hue = _catHue(_selectedCategory);

    return SeCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      clip: true,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 hero
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  AppImage(
                    url: imageUrl,
                    placeholder:
                        const SeShimmer(child: SeSkeleton(height: 150)),
                    errorWidget: _fallbackHero(hue),
                  )
                else
                  _fallbackHero(hue),
                if (imageUrl.isNotEmpty)
                  const DecoratedBox(
                      decoration: BoxDecoration(gradient: SeColors.inkScrim)),
                if (promo != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: SeColors.red500,
                        borderRadius: SeRadius.all(SeRadius.xs),
                        boxShadow: SeElevation.e1,
                      ),
                      child: Text(promo,
                          style: SeType.inter(10, FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => _toggleFavourite(id),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: SeElevation.e1,
                      ),
                      child: Icon(
                        fav ? SeIcons.heartFill : SeIcons.heart,
                        size: 18,
                        color: fav ? SeColors.red500 : SeColors.ink500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                    _ratingPill(ratingStr),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _infoBit(SeIcons.clock, m['deliveryTime'] as String? ?? ''),
                    _infoBit(SeIcons.bike, Money.deliveryFee(deliveryFee)),
                    SeChip.status(
                      label: isOpen ? 'Open' : 'Closed',
                      color: isOpen ? SeColors.success : SeColors.danger,
                      tint: isOpen ? SeColors.successTint : SeColors.dangerTint,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackHero(Color hue) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [hue.withValues(alpha: 0.9), hue],
          ),
        ),
        child: Center(
          child: Icon(SeIcons.storefront,
              size: 44, color: Colors.white.withValues(alpha: 0.85)),
        ),
      );

  Widget _ratingPill(String rating) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: SeColors.goldTint,
          borderRadius: SeRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(SeIcons.star, size: 13, color: SeColors.gold500),
            const SizedBox(width: 3),
            Text(rating,
                style: SeType.tabular(SeType.inter(12, FontWeight.w700,
                    color: SeColors.ink700))),
          ],
        ),
      );

  Widget _infoBit(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SeColors.ink400),
          const SizedBox(width: 4),
          Text(text, style: SeType.bodyS.copyWith(color: SeColors.ink500)),
        ],
      );
}
