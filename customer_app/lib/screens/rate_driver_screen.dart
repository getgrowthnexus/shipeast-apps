import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_toast.dart';

class RateDriverScreen extends StatefulWidget {
  const RateDriverScreen({super.key});

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  int _driverRating = 0;
  int _merchantRating = 0;
  final Set<int> _selectedTags = {};
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  String _orderId = '';
  String _driverId = '';
  String _merchantName = '';
  bool _argsLoaded = false;

  Map<String, dynamic>? _driver;
  StreamSubscription<Map<String, dynamic>?>? _driverSub;

  static const _tags = [
    'Fast delivery',
    'Friendly',
    'Food was hot',
    'Professional',
    'Careful handling',
    'On time',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _orderId = args['orderId'] as String? ?? '';
        _driverId = args['driverId'] as String? ?? '';
        _merchantName = args['merchantName'] as String? ?? '';
      }
      if (_driverId.isNotEmpty) {
        _driverSub = FirestoreService.watchDriver(_driverId).listen((driver) {
          if (mounted) setState(() => _driver = driver);
        });
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _driverSub?.cancel();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_driverRating == 0) {
      SeToast.error(context, 'Please rate the driver');
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_orderId.isNotEmpty) {
        await FirestoreService.submitRating(
          orderId: _orderId,
          driverRating: _driverRating,
          // null, not 5 — a skipped question is not a five-star review.
          merchantRating: _merchantRating > 0 ? _merchantRating : null,
          comment: _commentCtrl.text.trim(),
          tags: _selectedTags.map((i) => _tags[i]).toList(),
        );
      }
      if (!mounted) return;
      SeToast.success(context, 'Thank you for your rating!');
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        SeToast.error(context, 'Failed to submit rating. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDriverRatingCard(),
                    const SizedBox(height: 14),
                    _buildTagsCard(),
                    const SizedBox(height: 14),
                    _buildMerchantRatingCard(),
                    const SizedBox(height: 14),
                    _buildCommentCard(),
                    const SizedBox(height: 20),
                    SeButton(
                      label: 'Submit Rating',
                      icon: SeIcons.check,
                      loading: _submitting,
                      onPressed: _submitting ? null : _submitRating,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, SeSpacing.gutter, 12),
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(bottom: BorderSide(color: SeColors.ink100)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: SeColors.surface50, shape: BoxShape.circle),
                child: const Icon(SeIcons.arrowLeft,
                    size: 20, color: SeColors.ink900),
              ),
            ),
            const SizedBox(width: 12),
            Text('Rate Your Experience', style: SeType.h3),
          ],
        ),
      );

  Widget _star(int index, int rating, double size, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            index < rating ? SeIcons.star : SeIcons.starOutline,
            size: size,
            color: index < rating ? SeColors.gold500 : SeColors.ink300,
          ),
        ),
      );

  Widget _buildDriverRatingCard() {
    final driverName = _driver?['name'] as String? ??
        (_driverId.isNotEmpty ? 'Your Driver' : 'Driver');

    return SeCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: SeColors.emberGradient,
              borderRadius: SeRadius.all(SeRadius.lg),
              boxShadow: SeElevation.glow,
            ),
            child: const Icon(SeIcons.user, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(driverName, style: SeType.h3),
          const SizedBox(height: 2),
          Text('Your delivery driver',
              style: SeType.bodyS.copyWith(color: SeColors.ink500)),
          const SizedBox(height: 18),
          Text('How was your delivery?', style: SeType.title),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                5,
                (i) => _star(i, _driverRating, 38,
                    () => setState(() => _driverRating = i + 1))),
          ),
          if (_driverRating > 0) ...[
            const SizedBox(height: 10),
            Text(_ratingLabel(_driverRating),
                style: SeType.title.copyWith(color: SeColors.red500)),
          ],
        ],
      ),
    );
  }

  Widget _buildTagsCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What did you love?', style: SeType.title),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.asMap().entries.map((e) {
                final selected = _selectedTags.contains(e.key);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedTags.remove(e.key);
                    } else {
                      _selectedTags.add(e.key);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? SeColors.red50 : SeColors.surface50,
                      borderRadius: SeRadius.pill,
                      border: Border.all(
                        color: selected ? SeColors.red500 : SeColors.ink200,
                        width: 1.5,
                      ),
                    ),
                    child: Text(e.value,
                        style: SeType.label.copyWith(
                            color: selected
                                ? SeColors.red700
                                : SeColors.ink500,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _buildMerchantRatingCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: SeColors.red50,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child: const Icon(SeIcons.storefront,
                  size: 22, color: SeColors.red500),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_merchantName.isNotEmpty ? _merchantName : 'Restaurant',
                      style: SeType.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('Rate the merchant',
                      style: SeType.bodyS.copyWith(color: SeColors.ink400)),
                ],
              ),
            ),
            Row(
              children: List.generate(
                  5,
                  (i) => _star(i, _merchantRating, 22,
                      () => setState(() => _merchantRating = i + 1))),
            ),
          ],
        ),
      );

  Widget _buildCommentCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SeIcons.chat, size: 16, color: SeColors.ink700),
                const SizedBox(width: 8),
                Text('Leave a comment (optional)', style: SeType.title),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: SeColors.surface50,
                borderRadius: SeRadius.inputRadius,
                border: Border.all(color: SeColors.ink200, width: 1.5),
              ),
              child: TextField(
                controller: _commentCtrl,
                maxLines: 3,
                style: SeType.body.copyWith(color: SeColors.ink900),
                cursorColor: SeColors.red500,
                decoration: InputDecoration(
                  hintText: 'Tell us more about your experience...',
                  hintStyle: SeType.body.copyWith(color: SeColors.ink400),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      );

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}
