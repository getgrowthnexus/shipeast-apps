import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../utils/money.dart';
import 'app_image.dart';
import 'se_skeleton.dart';

/// How a merchant is drawn, everywhere a merchant is drawn.
///
/// Home, search and the all-merchants list each used to carry their own
/// version of this — same data, three different paddings, three different
/// shadows, two different rating treatments. Three cards drifting apart is
/// precisely how an app stops looking designed, so there is now one card and
/// one row, and every list picks one of them.
///
/// Flat by default: a hairline and a photo, no drop shadow. On a blush ground
/// a shadowed card reads as a sticker, and a page holds a lot of these.
class SeMerchantCard extends StatelessWidget {
  final String name;
  final String imageUrl;
  final String rating;
  final String deliveryTime;
  final int deliveryFee;
  final bool isOpen;
  final String? promo;

  /// Category hue — used only for the photoless fallback plate.
  final Color hue;
  final bool favourite;
  final VoidCallback? onFavourite;
  final VoidCallback onTap;

  const SeMerchantCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.rating,
    required this.deliveryTime,
    required this.deliveryFee,
    required this.isOpen,
    required this.hue,
    required this.onTap,
    this.promo,
    this.favourite = false,
    this.onFavourite,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: SeColors.surface0,
            borderRadius: SeRadius.all(SeRadius.md),
            border: Border.all(color: SeColors.ink200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                // A photo gets the full 16:9. A merchant with no photo yet —
                // which, early on, is most of them — gets a shallow band
                // instead: three empty half-screen plates down a list is a lot
                // of nothing to scroll past.
                aspectRatio: imageUrl.isNotEmpty ? 16 / 9 : 3 / 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      AppImage(
                        url: imageUrl,
                        placeholder:
                            const SeShimmer(child: SeSkeleton(height: 150)),
                        errorWidget: _fallback(),
                      )
                    else
                      _fallback(),
                    if (imageUrl.isNotEmpty)
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: SeColors.inkScrim),
                      ),
                    // A closed merchant is dimmed rather than hidden: knowing
                    // the place exists and shuts at nine is information.
                    if (!isOpen) Container(color: const Color(0x73140F12)),
                    if (promo != null && isOpen)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: SeColors.brandAction,
                            borderRadius: SeRadius.all(SeRadius.xs),
                          ),
                          child: Text(promo!,
                              style: SeType.inter(10, FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    if (!isOpen)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: const BoxDecoration(
                            color: SeColors.surfaceRaised,
                            borderRadius: SeRadius.pill,
                          ),
                          child: Text('Closed',
                              style: SeType.label
                                  .copyWith(color: SeColors.ink900)),
                        ),
                      ),
                    if (onFavourite != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: onFavourite,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              favourite ? SeIcons.heartFill : SeIcons.heart,
                              size: 18,
                              color:
                                  favourite ? SeColors.red500 : SeColors.ink500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: SeType.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        SeRatingPill(rating: rating),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        SeMetaBit(icon: SeIcons.clock, text: deliveryTime),
                        const SizedBox(width: 14),
                        SeMetaBit(
                            icon: SeIcons.bike,
                            text: Money.deliveryFee(deliveryFee)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// Shown when a merchant has no photo yet. A saturated plate of the category
  /// hue is an enormous amount of colour to repeat down a list; this is the
  /// same hue as a tint, so a photoless list reads quiet rather than alarming.
  Widget _fallback() => Container(
        color: Color.alphaBlend(hue.withValues(alpha: 0.10), SeColors.surface0),
        child: Center(
          child: Icon(SeIcons.storefront,
              size: 34, color: hue.withValues(alpha: 0.55)),
        ),
      );
}

/// The compact merchant listing — a square thumb and two lines.
///
/// Used where the job is scanning a list of names (search results, "all
/// merchants") rather than browsing photography. A 16:9 card per result turns
/// eight results into eight screens of scrolling.
class SeMerchantRow extends StatelessWidget {
  final String name;
  final String imageUrl;
  final String category;
  final String rating;
  final String deliveryTime;
  final int deliveryFee;
  final bool isOpen;
  final VoidCallback onTap;

  const SeMerchantRow({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.category,
    required this.rating,
    required this.deliveryTime,
    required this.deliveryFee,
    required this.isOpen,
    required this.onTap,
  });

  static IconData iconFor(String category) => switch (category) {
        'Food' => SeIcons.food,
        'Grocery' => SeIcons.grocery,
        'Pharmacy' => SeIcons.pharmacy,
        'Packages' => SeIcons.packages,
        _ => SeIcons.storefront,
      };

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SeColors.surface0,
            borderRadius: SeRadius.all(SeRadius.md),
            border: Border.all(color: SeColors.ink200),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: SeRadius.all(SeRadius.sm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: imageUrl.isEmpty
                      ? _thumbFallback()
                      : AppImage(
                          url: imageUrl,
                          placeholder: const SeShimmer(
                              child: SeSkeleton(
                                  width: 56, height: 56, radius: 12)),
                          errorWidget: _thumbFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              style: SeType.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (!isOpen) ...[
                          const SizedBox(width: 6),
                          Text('· Closed',
                              style: SeType.bodyS
                                  .copyWith(color: SeColors.danger)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    // One line of facts, not a wrap of chips. The category is
                    // already implied by where you are; rating, time and fee
                    // are what a customer actually chooses on.
                    Row(
                      children: [
                        const Icon(SeIcons.star, size: 13, color: SeColors.star),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '$rating · $deliveryTime · '
                            '${Money.deliveryFee(deliveryFee)}',
                            style:
                                SeType.bodyS.copyWith(color: SeColors.ink500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(SeIcons.caretRight, size: 18, color: SeColors.ink300),
            ],
          ),
        ),
      );

  Widget _thumbFallback() => Container(
        color: SeColors.surface50,
        child: Icon(iconFor(category), size: 24, color: SeColors.ink400),
      );
}

/// Star + number. The one place gold is allowed in this palette.
class SeRatingPill extends StatelessWidget {
  final String rating;
  const SeRatingPill({super.key, required this.rating});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(SeIcons.star, size: 15, color: SeColors.star),
          const SizedBox(width: 3),
          Text(rating,
              style: SeType.tabular(
                  SeType.inter(13, FontWeight.w700, color: SeColors.ink900))),
        ],
      );
}

/// Small glyph + value pair used for metadata (time, fee, distance, count).
class SeMetaBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const SeMetaBit({super.key, required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? SeColors.ink400),
          const SizedBox(width: 5),
          Text(text,
              style: SeType.bodyS.copyWith(color: color ?? SeColors.ink500)),
        ],
      );
}

/// Add / quantity control, shared by the menu and the cart.
///
/// At zero it is a single square "+" — one target, no ambiguity. Above zero it
/// becomes minus / count / plus. The two screens used to carry near-identical
/// copies of this, with different sizes and different corner radii on the same
/// button.
class SeQtyStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// Larger touch targets for the cart, where editing is the whole job.
  final bool large;

  const SeQtyStepper({
    super.key,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final side = large ? 32.0 : 30.0;
    if (quantity == 0) {
      return _Btn(
        icon: SeIcons.plus,
        bg: SeColors.brandAction,
        fg: Colors.white,
        side: large ? 36 : 34,
        radius: SeRadius.sm,
        onTap: onAdd,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(
          icon: SeIcons.minus,
          bg: SeColors.surface50,
          fg: SeColors.ink700,
          side: side,
          radius: SeRadius.xs,
          onTap: onRemove,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Text('$quantity', style: SeType.tabular(SeType.title)),
        ),
        _Btn(
          icon: SeIcons.plus,
          bg: SeColors.brandAction,
          fg: Colors.white,
          side: side,
          radius: SeRadius.xs,
          onTap: onAdd,
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final double side;
  final double radius;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.side,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: SeRadius.all(radius),
          ),
          child: Icon(icon, size: side * 0.52, color: fg),
        ),
      );
}

/// One line on a menu: thumbnail, name, description, price, add control.
class SeMenuItemRow extends StatelessWidget {
  final String name;
  final String description;
  final String price;
  final String imageUrl;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const SeMenuItemRow({
    super.key,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(
            // An item already in the cart says so quietly, by its edge, rather
            // than by turning the whole row a different colour.
            color: quantity > 0 ? SeColors.red200 : SeColors.ink200,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: SeRadius.all(SeRadius.sm),
              child: SizedBox(
                width: 68,
                height: 68,
                child: imageUrl.isEmpty
                    ? _fallback()
                    : AppImage(
                        url: imageUrl,
                        placeholder: const SeShimmer(
                            child:
                                SeSkeleton(width: 68, height: 68, radius: 12)),
                        errorWidget: _fallback(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: SeType.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(description,
                        style: SeType.bodyS.copyWith(color: SeColors.ink500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(price,
                            style: SeType.tabular(SeType.title)
                                .copyWith(color: SeColors.brandInk)),
                      ),
                      SeQtyStepper(
                        quantity: quantity,
                        onAdd: onAdd,
                        onRemove: onRemove,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _fallback() => Container(
        color: SeColors.surface50,
        child: const Icon(SeIcons.food, size: 28, color: SeColors.ink300),
      );
}
