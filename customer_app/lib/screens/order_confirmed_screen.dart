import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../utils/money.dart';
import '../widgets/se_button.dart';

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
  late Animation<double> _fadeAnim;
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
    _etaWindow =
        '${_clock(now.add(const Duration(minutes: 30)))} – ${_clock(now.add(const Duration(minutes: 40)))}';

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);

    _confettiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _confettiAnim =
        CurvedAnimation(parent: _confettiCtrl, curve: Curves.easeOut);

    _particles = List.generate(44, (_) => _Particle());

    _animCtrl.forward();
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 300), () {
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
        _paymentMethod =
            args['paymentMethod'] as String? ?? 'Cash on Delivery';
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

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _confettiAnim,
            builder: (_, __) => CustomPaint(
              painter: _ConfettiPainter(_confettiAnim.value, _particles),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, 30, SeSpacing.gutter, 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            gradient: SeColors.sunsetGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: SeElevation.glow,
                          ),
                          child: const Icon(SeIcons.check,
                              size: 50, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Order Placed!',
                        textAlign: TextAlign.center, style: SeType.display),
                    const SizedBox(height: 8),
                    Text(
                      'Your order is confirmed & sent to ${_merchantName.isNotEmpty ? _merchantName : 'the merchant'}. We\'ll notify you at every step.',
                      textAlign: TextAlign.center,
                      style: SeType.body.copyWith(color: SeColors.ink500),
                    ),
                    const SizedBox(height: 24),
                    _infoTile(
                      label: 'ORDER ID',
                      value: _orderId.isNotEmpty
                          ? '#${_orderId.substring(0, _orderId.length.clamp(0, 8)).toUpperCase()}'
                          : '#SE-ORDER',
                    ),
                    const SizedBox(height: 12),
                    _etaTile(),
                    const SizedBox(height: 12),
                    _addressTile(),
                    const SizedBox(height: 12),
                    _buildReceiptCard(),
                    const SizedBox(height: 20),
                    SeButton(
                      label: 'Track My Order',
                      icon: SeIcons.arrowRight,
                      onPressed: () => Navigator.pushNamed(
                          context, '/order-status',
                          arguments: {'orderId': _orderId}),
                    ),
                    const SizedBox(height: 10),
                    SeButton(
                      label: 'Back to Home',
                      variant: SeButtonVariant.ghost,
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, '/home', (route) => false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({required String label, required String value}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          boxShadow: SeElevation.e1,
        ),
        child: Column(
          children: [
            Text(label, style: SeType.eyebrow),
            const SizedBox(height: 4),
            Text(value,
                style: SeType.tabular(SeType.h2).copyWith(color: SeColors.ink900)),
          ],
        ),
      );

  Widget _etaTile() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeColors.red50,
          border: Border.all(color: SeColors.red100, width: 1.5),
          borderRadius: SeRadius.all(SeRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: SeColors.surface0, shape: BoxShape.circle),
              child: const Icon(SeIcons.clock, size: 24, color: SeColors.red500),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ESTIMATED ARRIVAL', style: SeType.eyebrow),
                const SizedBox(height: 2),
                Text(_etaWindow,
                    style: SeType.tabular(SeType.h3)
                        .copyWith(color: SeColors.red600)),
              ],
            ),
          ],
        ),
      );

  Widget _addressTile() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          boxShadow: SeElevation.e1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SeIcons.location, size: 16, color: SeColors.ink700),
                const SizedBox(width: 6),
                Text('DELIVERING TO', style: SeType.eyebrow),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _deliveryAddress.isNotEmpty
                  ? _deliveryAddress
                  : 'No address provided',
              style: SeType.body.copyWith(color: SeColors.ink700),
            ),
          ],
        ),
      );

  Widget _buildReceiptCard() => Container(
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          boxShadow: SeElevation.e1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: SeColors.ink100)),
              ),
              child: Row(
                children: [
                  const Icon(SeIcons.orders, size: 18, color: SeColors.ink700),
                  const SizedBox(width: 8),
                  Text('Order Receipt', style: SeType.title),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                children: [
                  ..._items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text('${item['name']} × ${item['qty']}',
                                  style: SeType.body
                                      .copyWith(color: SeColors.ink700)),
                            ),
                            Text(Money.format(item['price'] as int),
                                style: SeType.tabular(SeType.body)
                                    .copyWith(color: SeColors.ink700)),
                          ],
                        ),
                      )),
                  if (_items.isNotEmpty)
                    const Divider(height: 1, color: SeColors.ink100),
                  const SizedBox(height: 12),
                  _receiptRow('Subtotal', Money.format(_subtotal)),
                  _receiptRow('Delivery fee',
                      Money.deliveryFee(_deliveryFee)),
                  _receiptRow('Service fee', Money.format(_serviceFee)),
                  // The receipt has to explain the gap between the items and
                  // the amount charged, or it does not reconcile (P3-02).
                  if (_discount > 0)
                    _receiptRow('Discount', '- ${Money.format(_discount)}'),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(color: SeColors.red50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Paid', style: SeType.h3),
                  Text(Money.format(_total),
                      style: SeType.tabular(SeType.h3)
                          .copyWith(color: SeColors.red600)),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(SeIcons.cash, size: 16, color: SeColors.ink400),
                  const SizedBox(width: 8),
                  Text('Paid via $_paymentMethod',
                      style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _receiptRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: SeType.body.copyWith(color: SeColors.ink500)),
            Text(value,
                style:
                    SeType.tabular(SeType.body).copyWith(color: SeColors.ink700)),
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
        size = 4 + math.Random().nextDouble() * 8,
        color = [
          SeColors.red500,
          SeColors.red400,
          SeColors.gold500,
          const Color(0xFFFF6A3D),
          SeColors.ocean500,
        ][math.Random().nextInt(5)],
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
