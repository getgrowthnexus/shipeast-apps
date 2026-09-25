import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_card.dart';
import '../widgets/se_app_bar.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    {
      'q': 'How does ShipEast work?',
      'a':
          'ShipEast connects you with local merchants and delivery drivers in St. Thomas, Jamaica. Browse merchants, add items to cart, checkout, and track your delivery in real time.',
    },
    {
      'q': 'How do I track my order?',
      'a':
          'After placing an order, tap Orders in the bottom navigation. You can view real-time status updates including when your order is being prepared, picked up, and delivered.',
    },
    {
      'q': 'What payment methods are accepted?',
      'a':
          'Currently we support Cash on Delivery. Card payments and mobile money are coming in the next update.',
    },
    {
      'q': 'How long does delivery take?',
      'a':
          'Delivery times vary by merchant, typically 15–50 minutes. Estimated delivery time is shown on each merchant card before you order.',
    },
    {
      'q': 'Can I cancel my order?',
      'a':
          'You can cancel within 2 minutes of placing your order. After that, contact us via WhatsApp for assistance as the merchant may have already started preparing your order.',
    },
  ];

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          const SeGradientHeader(
            title: 'Help & Support',
            subtitle: "We're here to help",
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildContactCard(),
                  const SizedBox(height: 14),
                  _buildFaqSection(),
                  const SizedBox(height: 14),
                  _buildVersionCard(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact Us', style: SeType.title),
            const SizedBox(height: 4),
            Text('Reach us on WhatsApp or Email — we respond within 1 hour.',
                style: SeType.bodyS.copyWith(color: SeColors.ink500)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _contactBtn(
                    label: 'WhatsApp',
                    icon: SeIcons.chat,
                    color: const Color(0xFF25D366),
                    onTap: () => _launch('https://wa.me/18765559988'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _contactBtn(
                    label: 'Email Us',
                    icon: SeIcons.envelope,
                    color: SeColors.red500,
                    onTap: () => _launch('mailto:info@shipeastja.com'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _contactBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: color, borderRadius: SeRadius.all(SeRadius.md)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: SeType.jakarta(14, FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
      );

  Widget _buildFaqSection() => SeCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Frequently Asked Questions', style: SeType.title),
            ),
            ..._faqs.map(
              (faq) => _FaqItem(question: faq['q']!, answer: faq['a']!),
            ),
            const SizedBox(height: 4),
          ],
        ),
      );

  Widget _buildVersionCard() => SeCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SeColors.surface50,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child: const Icon(SeIcons.info, size: 20, color: SeColors.ink500),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ShipEast Customer App', style: SeType.title),
                Text('Version ${SeBrand.version}',
                    style: SeType.bodyS.copyWith(color: SeColors.ink400)),
              ],
            ),
          ],
        ),
      );
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, color: SeColors.ink100),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.question,
                      style: SeType.body.copyWith(
                          color: SeColors.ink900,
                          fontWeight: FontWeight.w600)),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(SeIcons.caretDown,
                      size: 18, color: SeColors.ink400),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(widget.answer,
                style: SeType.body.copyWith(color: SeColors.ink500)),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
