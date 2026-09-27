import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_page.dart';

/// Help.
///
/// Two ways to reach a person at the top, because somebody who opens this
/// screen usually has a problem happening right now; the FAQ is underneath for
/// everyone else.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    {
      'q': 'How does ShipEast work?',
      'a':
          'ShipEast connects you with local merchants and delivery drivers in '
              'St. Thomas, Jamaica. Browse merchants, add items to your cart, '
              'check out, and follow your delivery as it happens.',
    },
    {
      'q': 'How do I track my order?',
      'a':
          'Tap Orders in the bottom navigation and open the order. You will see '
              'each step as it happens — driver assigned, picked up, on the way '
              '— and how far away your driver is once they are carrying it.',
    },
    {
      'q': 'What payment methods are accepted?',
      'a':
          'Cash on delivery, for now. Card and mobile money are coming.',
    },
    {
      'q': 'How long does delivery take?',
      'a':
          'It varies by merchant, typically 15–50 minutes. The estimate is '
              'shown on each merchant before you order.',
    },
    {
      'q': 'Can I cancel my order?',
      // Corrected copy. The old answer promised a two-minute window that has
      // never existed in this system: rules allow a customer cancellation only
      // while the order is still unclaimed (firestore.rules,
      // `customerCancelling()`), which may be seconds or many minutes.
      'a':
          'Yes, while the order is still waiting for a driver — open the order '
              'and tap Cancel order. Once a driver has accepted it they are '
              'already on their way to the merchant, so from that point message '
              'us and we will sort it out.',
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
    return SePageScaffold(
      title: 'Help & support',
      subtitle: 'We usually reply within the hour',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 28),
        children: [
          const SeSectionTitle(title: 'Talk to us'),
          const SizedBox(height: 10),
          SeRowGroup(
            children: [
              SeRow(
                icon: SeIcons.chat,
                hue: const Color(0xFF25D366),
                label: 'WhatsApp',
                subtitle: 'Fastest — message the team directly',
                onTap: () => _launch('https://wa.me/18765559988'),
              ),
              SeRow(
                icon: SeIcons.envelope,
                label: 'Email',
                subtitle: 'info@shipeastja.com',
                onTap: () => _launch('mailto:info@shipeastja.com'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Common questions'),
          const SizedBox(height: 10),
          SeRowGroup(
            children: [
              for (final faq in _faqs)
                _FaqItem(question: faq['q']!, answer: faq['a']!),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: Text('ShipEast · version ${SeBrand.version}',
                style: SeType.bodyS.copyWith(color: SeColors.ink400)),
          ),
        ],
      ),
    );
  }
}

/// One question, expanding in place.
///
/// Kept inside a [SeRowGroup] so the FAQ is one surface with hairlines rather
/// than five separate cards — a list of five shadowed cards reads as five
/// unrelated things.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.question,
                      style: SeType.title.copyWith(fontSize: 15)),
                ),
                const SizedBox(width: 10),
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
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Text(widget.answer,
                style: SeType.bodyS
                    .copyWith(color: SeColors.ink500, height: 1.5)),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
