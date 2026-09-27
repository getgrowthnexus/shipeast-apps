import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../utils/money.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';

/// The moment screen.
///
/// It has one job — make it unmistakable that the order went through — and one
/// question to answer immediately after: when, and where. There is no back
/// button, because there is nowhere sensible to go back TO; the cap's close
/// returns home and the docked action goes to tracking.
class OrderConfirmedScreen extends StatefulWidget {
  const OrderConfirmedScreen({super.key});

  @override
  State<OrderConfirmedScreen> createState() => _OrderConfirmedScreenState();
}

class _OrderConfirmedScreenState extends State<OrderConfirmedScreen>
    with TickerProviderStateMixin {
  late AnimationController _animCtrl;
  late AnimationController _confettiCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _confettiAnim;

  late List<_Particle> _particles;

  String _orderId = '';
  String _merchantName = '';
  String _deliveryAddress = '';
  String _paymentMethod = 'Cash on Delivery';
  List<Map<String, dynamic>> _items = const [];
  int _subtotal = 0;
  int _deliveryFee = 0;
  int _serviceFee = 0;
  int _discount = 0;
  int _total = 0;
  bool _argsLoaded = false;
  late final String _etaWindow;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    final now = DateTime.now();
    _etaWindow = _window(
        now.add(const Duration(minutes: 30)), now.add(const Duration(minutes: 40)));

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 620));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);

    _confettiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _confettiAnim =
        CurvedAnimation(parent: _confettiCtrl, curve: Curves.easeOut);

    _particles = List.generate(30, (_) => _Particle());

    _animCtrl.forward();
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _confettiCtrl.forward();
    });
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
        _merchantName = args['merchantName'] as String? ?? '';
        _deliveryAddress = args['deliveryAddress'] as String? ?? '';
        _paymentMethod = args['paymentMethod'] as String? ?? 'Cash on Delivery';
        _subtotal = args['subtotal'] as int? ?? 0;
        _deliveryFee = args['deliveryFee'] as int? ?? 0;
        _serviceFee = args['serviceFee'] as int? ?? 0;
        _discount = args['discount'] as int? ?? 0;
        _total = args['total'] as int? ?? 0;
        final rawItems = args['items'] as List?;
        if (rawItems != null && rawItems.isNotEmpty) {
          _items = rawItems
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((e) => {
                    'name': e['name'] ?? '',
                    'qty': e['quantity'] ?? 1,
                    'price': e['price'] ?? 0,
                  })
              .toList();
        }
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  String _clock(DateTime t, {bool meridiem = true}) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return meridiem ? '$h:$m $ap' : '$h:$m';
  }

  /// "6:05 – 6:15 PM", not "6:05 PM – 6:15 PM". Printing the meridiem twice
  /// pushes a ten-minute window onto two lines for no information at all.
  String _window(DateTime from, DateTime to) {
    final sameHalf = (from.hour < 12) == (to.hour < 12);
    return '${_clock(from, meridiem: !sameHalf)} – ${_clock(to)}';
  }

  String get _reference => _orderId.isEmpty
      ? 'SE-ORDER'
      : _orderId.substring(0, _orderId.length.clamp(0, 8)).toUpperCase();

  void _goHome() =>
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SePageScaffold(
          showBack: false,
          capTitle: _celebration(),
          bottomBar: SeBottomBar(
            child: SeButton(
              label: 'Track my order',
              icon: SeIcons.arrowRight,
              onPressed: () => Navigator.pushNamed(context, '/order-status',
                  arguments: {'orderId': _orderId}),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, 20, SeSpacing.gutter, 24),
            children: [
              _reference2Up(),
              const SizedBox(height: 12),
              if (_deliveryAddress.isNotEmpty) ...[
                _addressPanel(),
                const SizedBox(height: 12),
              ],
              _receipt(),
            ],
          ),
        ),
        // Purely decorative and short-lived, so it must never eat a tap on the
        // buttons underneath it.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _confettiAnim,
            builder: (_, _) => CustomPaint(
              painter: _ConfettiPainter(_confettiAnim.value, _particles),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }

  Widget _celebration() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The close sits level with the tick rather than beside the
          // headline: as `trailing` it centred itself against the whole block
          // and floated in the middle of the sentence.
          Row(
            children: [
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: const Icon(SeIcons.check,
                      size: 30, color: SeColors.shellInk),
                ),
              ),
              const Spacer(),
              SeCapButton(icon: SeIcons.close, onTap: _goHome),
            ],
          ),
          const SizedBox(height: 14),
          Text('Order placed',
              style: SeType.display
                  .copyWith(color: SeColors.shellInk, height: 1.1)),
          const SizedBox(height: 6),
          Text(
            _merchantName.isEmpty
                ? 'We are letting the merchant know now.'
                : '$_merchantName is getting it ready. We will tell you at every step.',
            style: SeType.bodyS.copyWith(
                color: SeColors.shellInk.withValues(alpha: 0.78), height: 1.45),
          ),
        ],
      );

  /// The two facts wanted first, side by side: when it lands, and what to quote
  /// if something goes wrong.
  // IntrinsicHeight, because the two panels must match each other's height and
  // `stretch` alone inside a ListView asks for an infinite one.
  Widget _reference2Up() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Expanded(
            child: SePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(SeIcons.clock,
                          size: 15, color: SeColors.brandAction),
                      const SizedBox(width: 6),
                      Text('ARRIVES', style: SeType.eyebrow),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_etaWindow,
                      style: SeType.tabular(SeType.title)
                          .copyWith(color: SeColors.ink900)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SePanel(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _reference));
                SeToast.success(context, 'Order number copied');
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(SeIcons.copy, size: 14, color: SeColors.ink400),
                      const SizedBox(width: 6),
                      Text('ORDER', style: SeType.eyebrow),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('#$_reference',
                      style: SeType.tabular(SeType.title)
                          .copyWith(color: SeColors.ink900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          ],
        ),
      );

  Widget _addressPanel() => SePanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(SeIcons.location, size: 18, color: SeColors.brandAction),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DELIVERING TO', style: SeType.eyebrow),
                  const SizedBox(height: 3),
                  Text(_deliveryAddress,
                      style: SeType.bodyS.copyWith(
                          color: SeColors.ink700, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _receipt() => SePanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RECEIPT', style: SeType.eyebrow),
            const SizedBox(height: 8),
            for (final item in _items)
              SeMoneyLine(
                label: '${item['name']} × ${item['qty']}',
                value: Money.format(item['price'] as int),
              ),
            if (_items.isNotEmpty)
              const Divider(height: 18, color: SeColors.ink100),
            SeMoneyLine(label: 'Subtotal', value: Money.format(_subtotal)),
            SeMoneyLine(
                label: 'Delivery fee', value: Money.deliveryFee(_deliveryFee)),
            SeMoneyLine(label: 'Service fee', value: Money.format(_serviceFee)),
            // The receipt has to explain the gap between the items and the
            // amount charged, or it does not reconcile (P3-02).
            if (_discount > 0)
              SeMoneyLine(
                label: 'Discount',
                value: '− ${Money.format(_discount)}',
                valueColor: SeColors.success,
              ),
            const Divider(height: 18, color: SeColors.ink200),
            SeMoneyLine(
                label: 'Total', value: Money.format(_total), strong: true),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(SeIcons.cash, size: 15, color: SeColors.ink400),
                const SizedBox(width: 7),
                Text(_paymentMethod,
                    style: SeType.bodyS.copyWith(color: SeColors.ink400)),
              ],
            ),
          ],
        ),
      );
}

class _Particle {
  final double x;
  final double speedY;
  final double speedX;
  final double size;
  final Color color;
  final double startY;

  _Particle()
      : x = math.Random().nextDouble(),
        speedY = 0.3 + math.Random().nextDouble() * 0.7,
        speedX = (math.Random().nextDouble() - 0.5) * 0.3,
        size = 4 + math.Random().nextDouble() * 7,
        color = [
          SeColors.red500,
          SeColors.star,
          SeColors.success,
          SeColors.info,
        ][math.Random().nextInt(4)],
        startY = -0.1 - math.Random().nextDouble() * 0.3;
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_Particle> particles;

  _ConfettiPainter(this.progress, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final currentY = p.startY + p.speedY * progress;
      if (currentY < 0 || currentY > 1.1) continue;
      final currentX = p.x + p.speedX * progress;
      final opacity = (1.0 - progress * 0.8).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: opacity);
      final rect = Rect.fromCenter(
        center: Offset(currentX * size.width, currentY * size.height),
        width: p.size,
        height: p.size * 0.6,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(progress * math.pi * 4 * p.speedX);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
