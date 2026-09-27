import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';

/// Rating.
///
/// One required question — how was the delivery — and everything else optional
/// and below it. The follow-up chips change with the score: offering "Friendly"
/// and "Food was hot" to somebody who just gave one star reads as not listening.
class RateDriverScreen extends StatefulWidget {
  const RateDriverScreen({super.key});

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  int _driverRating = 0;
  int _merchantRating = 0;
  final Set<String> _selectedTags = {};
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  String _orderId = '';
  String _driverId = '';
  String _merchantName = '';
  bool _argsLoaded = false;

  Map<String, dynamic>? _driver;
  StreamSubscription<Map<String, dynamic>?>? _driverSub;

  static const _goodTags = [
    'Fast delivery',
    'Friendly',
    'Food was hot',
    'Professional',
    'Careful handling',
    'On time',
  ];

  static const _badTags = [
    'Took too long',
    'Order was cold',
    'Items missing',
    'Hard to reach',
    'Rude or careless',
    'Wrong address',
  ];

  bool get _positive => _driverRating >= 4;
  List<String> get _tags => _positive ? _goodTags : _badTags;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
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

  void _setDriverRating(int stars) {
    setState(() {
      final wasPositive = _positive;
      _driverRating = stars;
      // The chip list swaps at four stars, so a selection made under the old
      // list would be submitted against a question that is no longer on screen.
      if (wasPositive != _positive) _selectedTags.clear();
    });
    HapticFeedback.selectionClick();
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
          tags: _selectedTags.toList(),
        );
      }
      if (!mounted) return;
      SeToast.success(context, 'Thank you — that helps.');
      await Future.delayed(const Duration(milliseconds: 1200));
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
    return SePageScaffold(
      title: 'How did we do?',
      subtitle: 'Ten seconds, and it changes who we send next time',
      bottomBar: SeBottomBar(
        child: SeButton(
          label: 'Submit rating',
          loading: _submitting,
          onPressed: _submitting ? null : _submitRating,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          _driverPanel(),
          if (_driverRating > 0) ...[
            const SizedBox(height: 22),
            SeSectionTitle(
                title: _positive ? 'What went well?' : 'What went wrong?'),
            const SizedBox(height: 10),
            _tagWrap(),
          ],
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'And the merchant?'),
          const SizedBox(height: 10),
          _merchantPanel(),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Anything else'),
          const SizedBox(height: 10),
          SeTextField(
            controller: _commentCtrl,
            hint: 'Optional — tell us what happened',
            icon: SeIcons.chat,
            minLines: 3,
            maxLines: 5,
          ),
        ],
      ),
    );
  }

  Widget _driverPanel() {
    final driverName = _driver?['name'] as String? ??
        (_driverId.isNotEmpty ? 'Your driver' : 'Your driver');

    return SePanel(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(
              color: SeColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(SeIcons.user, size: 32, color: SeColors.brandAction),
          ),
          const SizedBox(height: 12),
          Text(driverName,
              style: SeType.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text('Delivered your order',
              style: SeType.bodyS.copyWith(color: SeColors.ink500)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => _star(i, _driverRating, 36, () => _setDriverRating(i + 1)),
            ),
          ),
          const SizedBox(height: 10),
          // Reserved height, so choosing a score does not shove the rest of the
          // page down under the reader's thumb.
          SizedBox(
            height: 20,
            child: Text(
              _driverRating == 0 ? 'Tap a star' : _ratingLabel(_driverRating),
              style: SeType.title.copyWith(
                fontSize: 15,
                color:
                    _driverRating == 0 ? SeColors.ink400 : SeColors.brandInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagWrap() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _tags.map((tag) {
          final selected = _selectedTags.contains(tag);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _selectedTags.remove(tag);
              } else {
                _selectedTags.add(tag);
              }
            }),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? SeColors.brandSoft : SeColors.surface0,
                borderRadius: SeRadius.pill,
                border: Border.all(
                  color: selected ? SeColors.brandAction : SeColors.ink200,
                ),
              ),
              child: Text(tag,
                  style: SeType.label.copyWith(
                      color: selected ? SeColors.brandInk : SeColors.ink500)),
            ),
          );
        }).toList(),
      );

  Widget _merchantPanel() => SePanel(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeColors.brandAction.withValues(alpha: 0.10),
                borderRadius: SeRadius.all(SeRadius.xs),
              ),
              child: const Icon(SeIcons.storefront,
                  size: 20, color: SeColors.brandAction),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  _merchantName.isNotEmpty ? _merchantName : 'The merchant',
                  style: SeType.title.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                5,
                (i) => _star(i, _merchantRating, 21,
                    () => setState(() => _merchantRating = i + 1)),
              ),
            ),
          ],
        ),
      );

  Widget _star(int index, int rating, double size, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size > 28 ? 5 : 2),
          child: Icon(
            index < rating ? SeIcons.star : SeIcons.starOutline,
            size: size,
            color: index < rating ? SeColors.star : SeColors.ink300,
          ),
        ),
      );

  String _ratingLabel(int rating) => switch (rating) {
        1 => 'Poor',
        2 => 'Not great',
        3 => 'Fine',
        4 => 'Good',
        5 => 'Excellent',
        _ => '',
      };
}
