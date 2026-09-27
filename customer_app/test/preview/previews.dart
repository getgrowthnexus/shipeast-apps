import 'package:flutter/material.dart';
import 'package:shipeast_customer/screens/notifications_screen.dart';
import 'package:shipeast_customer/screens/order_history_screen.dart';
import 'package:shipeast_customer/widgets/se_button.dart';
import 'package:shipeast_customer/theme/se_colors.dart';
import 'package:shipeast_customer/theme/se_icons.dart';
import 'package:shipeast_customer/theme/se_spacing.dart';
import 'package:shipeast_customer/theme/se_typography.dart';
import 'package:shipeast_customer/utils/money.dart';
import 'package:shipeast_customer/widgets/se_bottom_sheet.dart';
import 'package:shipeast_customer/widgets/se_chip.dart';
import 'package:shipeast_customer/widgets/se_empty_state.dart';
import 'package:shipeast_customer/widgets/se_listing.dart';
import 'package:shipeast_customer/widgets/se_page.dart';
import 'package:shipeast_customer/widgets/se_skeleton.dart';
import 'package:shipeast_customer/widgets/se_text_field.dart';

import 'fake.dart' as fake;

/// Stand-ins for the screens that cannot be pumped.
///
/// Every one of these reaches for `FirebaseAuth.instance` or a Firestore stream
/// in `initState`, and there is no Firebase app in a widget test — the plugins
/// went to pigeon channels, so the old method-channel mock does not reach them
/// either. So each preview rebuilds a screen's COMPOSITION out of the very same
/// public widgets the screen uses: `SePageScaffold`, `SeShellField`,
/// `SeMerchantRow`, `SeNotificationRow` and so on.
///
/// That is the part worth guarding. What is NOT covered is each screen's own
/// wiring of those pieces, so when a screen's build method changes, its preview
/// has to change with it or the picture starts lying.

Widget homePreview() => SePageScaffold(
      showBack: false,
      capTitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(SeIcons.locationFill,
                  size: 13, color: SeColors.shellMark),
              const SizedBox(width: 4),
              Text('St. Thomas, Jamaica',
                  style: SeType.label.copyWith(color: SeColors.shellMark)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Good evening, Andre',
              style: SeType.h2.copyWith(color: SeColors.shellInk)),
        ],
      ),
      trailing: Container(
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
          child: Center(
            child: Text('AB',
                style:
                    SeType.jakarta(14, FontWeight.w800, color: SeColors.shellInk)),
          ),
        ),
      ),
      capBottom: const SeShellField(hint: 'Search restaurants, shops, items…'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 110),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
            child: Row(
              children: [
                for (final c in const [
                  ('Food', SeIcons.food, SeColors.catFood, SeColors.catFoodTint),
                  ('Grocery', SeIcons.grocery, SeColors.catGrocery,
                      SeColors.catGroceryTint),
                  ('Packages', SeIcons.packages, SeColors.catPackages,
                      SeColors.catPackagesTint),
                  ('Pharmacy', SeIcons.pharmacy, SeColors.catPharmacy,
                      SeColors.catPharmacyTint),
                ])
                  Expanded(
                    child: SeCategoryTile(
                      label: c.$1,
                      icon: c.$2,
                      hue: c.$3,
                      tint: c.$4,
                      selected: c.$1 == 'Food',
                      onTap: () {},
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SeSpacing.gutter, 0, SeSpacing.gutter, 24),
            child: SePanel(
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
                        Text('Send to family back home', style: SeType.title),
                        const SizedBox(height: 2),
                        Text('We shop in Jamaica and deliver to them.',
                            style:
                                SeType.bodyS.copyWith(color: SeColors.ink500)),
                      ],
                    ),
                  ),
                  const Icon(SeIcons.caretRight,
                      size: 20, color: SeColors.ink300),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
            child: SeSectionTitle(
                title: 'Popular near you',
                actionLabel: 'See all',
                onAction: () {}),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SeSpacing.gutter),
            child: Column(
              children: [
                for (final m in fake.merchants)
                  SeMerchantCard(
                    name: m['name'] as String,
                    imageUrl: '',
                    rating: m['rating'] as String,
                    deliveryTime: m['deliveryTime'] as String,
                    deliveryFee: m['deliveryFee'] as int,
                    isOpen: m['isOpen'] as bool,
                    promo: m['promo'] as String?,
                    hue: SeColors.catFood,
                    favourite: m['name'] == 'Juici Patties',
                    onFavourite: () {},
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ],
      ),
    );

Widget searchPreview() => SePageScaffold(
      title: 'Search',
      showBack: false,
      capBottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SeShellField(hint: 'Restaurants, shops, items…'),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SeShellChip(
                    label: 'Food',
                    icon: SeIcons.food,
                    selected: true,
                    onTap: () {}),
                const SizedBox(width: 8),
                SeShellChip(
                    label: 'Grocery',
                    icon: SeIcons.grocery,
                    selected: false,
                    onTap: () {}),
                const SizedBox(width: 8),
                SeShellChip(
                    label: 'Pharmacy',
                    icon: SeIcons.pharmacy,
                    selected: false,
                    onTap: () {}),
                const SizedBox(width: 8),
                SeShellChip(
                    label: 'Packages',
                    icon: SeIcons.packages,
                    selected: false,
                    onTap: () {}),
              ],
            ),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 18, SeSpacing.gutter, 110),
        itemCount: fake.merchants.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: SeSectionTitle(title: '3 results'),
            );
          }
          final m = fake.merchants[i - 1];
          return SeMerchantRow(
            name: m['name'] as String,
            imageUrl: '',
            category: 'Food',
            rating: m['rating'] as String,
            deliveryTime: m['deliveryTime'] as String,
            deliveryFee: m['deliveryFee'] as int,
            isOpen: m['isOpen'] as bool,
            onTap: () {},
          );
        },
      ),
    );

Widget alertsPreview() => SePageScaffold(
      title: 'Alerts',
      subtitle: '1 new update',
      showBack: false,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 110),
        itemCount: fake.notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final n = fake.notifications[i];
          return SeNotificationRow(
            title: n['title'] as String,
            message: n['body'] as String,
            type: n['kind'] as String,
            when: n['when'] as String,
            unread: n['unread'] as bool,
          );
        },
      ),
    );

Widget ordersPreview() => SePageScaffold(
      title: 'Orders',
      subtitle: '1 in progress',
      showBack: false,
      capBottom: SeShellTabs(
        tabs: const ['All', 'Active', 'Completed', 'Cancelled'],
        selected: 0,
        onSelect: (_) {},
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 110),
        itemCount: fake.orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final o = fake.orders[i];
          final status = o['status'] as String;
          final finished = status == 'delivered' || status == 'cancelled';
          return SeOrderCard(
            merchantName: o['merchant'] as String,
            reference: '#${o['id']}',
            status: status,
            itemsLabel: 'Curry Goat with Rice & Peas, Festival, Ting',
            date: o['when'] as String,
            total: Money.format(o['total'] as int),
            onTap: () {},
            onReorder: finished ? () {} : null,
          );
        },
      ),
    );

Widget profilePreview() => SePageScaffold(
      showBack: false,
      capTitle: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35), width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('AB',
                    style: SeType.jakarta(15.5, FontWeight.w800,
                        color: SeColors.shellInk)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Andre Brown',
                    style: SeType.h2.copyWith(color: SeColors.shellInk)),
                const SizedBox(height: 3),
                Text('+1 876 555 0142',
                    style: SeType.bodyS.copyWith(
                        color: SeColors.shellInk.withValues(alpha: 0.76))),
              ],
            ),
          ),
        ],
      ),
      trailing: SeCapButton(icon: SeIcons.edit, onTap: () {}),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 110),
        children: [
          Row(
            children: [
              const Expanded(
                child: SeStat(
                    icon: SeIcons.orders,
                    value: '24',
                    label: 'Orders',
                    hue: SeColors.brand),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: SeStat(
                    icon: SeIcons.star,
                    value: '4.9',
                    label: 'Rating',
                    hue: SeColors.star),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: SeStat(
                    icon: SeIcons.heartFill,
                    value: '6',
                    label: 'Saved',
                    hue: SeColors.info),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SeRowGroup(
            children: [
              SeRow(
                  icon: SeIcons.addresses,
                  label: 'Saved addresses',
                  subtitle: 'Where we deliver to',
                  onTap: () {}),
              SeRow(
                  icon: SeIcons.bell,
                  label: 'Notifications',
                  subtitle: 'Order updates and offers',
                  onTap: () {}),
              SeRow(
                  icon: SeIcons.creditCard,
                  label: 'Payment methods',
                  subtitle: 'Cash on delivery today',
                  onTap: () {}),
              SeRow(
                  icon: SeIcons.shield,
                  label: 'Privacy & security',
                  subtitle: 'Password, data and permissions',
                  onTap: () {}),
              SeRow(
                  icon: SeIcons.help,
                  label: 'Help & support',
                  subtitle: 'FAQs, WhatsApp and email',
                  onTap: () {}),
            ],
          ),
          const SizedBox(height: 20),
          SeButton(
              label: 'Sign out',
              variant: SeButtonVariant.destructive,
              onPressed: () {}),
          const SizedBox(height: 18),
          Center(
            child: Text('ShipEast · v1.1.2',
                style: SeType.bodyS.copyWith(color: SeColors.ink400)),
          ),
        ],
      ),
    );

Widget menuPreview() => Scaffold(
      backgroundColor: SeColors.shell,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 186,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(
                  color: SeColors.shell,
                  child: Center(
                      child: Text('🍽️', style: TextStyle(fontSize: 52))),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        SeSpacing.gutter, 6, SeSpacing.gutter, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SeCapButton(icon: SeIcons.arrowLeft, onTap: () {}),
                        SeCapButton(icon: SeIcons.heart, onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SeSheet(
              bottomBar: Padding(
                padding: const EdgeInsets.fromLTRB(
                    SeSpacing.gutter, 8, SeSpacing.gutter, 12),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: SeColors.brandAction,
                    borderRadius: SeRadius.pill,
                    boxShadow: SeElevation.glow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Text('6',
                            style: SeType.tabular(SeType.title)
                                .copyWith(color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      Text('View cart',
                          style: SeType.jakarta(16, FontWeight.w700,
                              color: Colors.white)),
                      const Spacer(),
                      Text('\$3,850',
                          style: SeType.tabular(SeType.jakarta(
                              16, FontWeight.w800,
                              color: Colors.white))),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          SeSpacing.gutter, 20, SeSpacing.gutter, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text('Island Grill Morant Bay',
                                      style: SeType.h2)),
                              const SizedBox(width: 10),
                              SeChip.status(
                                  label: 'Open',
                                  color: SeColors.successInk,
                                  tint: SeColors.successSoft),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: const [
                              SeRatingPill(rating: '4.8'),
                              SizedBox(width: 14),
                              SeMetaBit(
                                  icon: SeIcons.clock, text: '25–35 min'),
                              SizedBox(width: 14),
                              SeMetaBit(icon: SeIcons.bike, text: '\$350'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final t in const [
                                  ('Popular', true),
                                  ('Mains', false),
                                  ('Sides', false),
                                  ('Drinks', false),
                                ]) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 15),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: t.$2
                                          ? SeColors.brandAction
                                          : SeColors.surface0,
                                      borderRadius: SeRadius.pill,
                                      border: Border.all(
                                          color: t.$2
                                              ? SeColors.brandAction
                                              : SeColors.ink200),
                                    ),
                                    child: Text(t.$1,
                                        style: SeType.label.copyWith(
                                            color: t.$2
                                                ? Colors.white
                                                : SeColors.ink700)),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text('MOST ORDERED', style: SeType.eyebrow),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        SeSpacing.gutter, 0, SeSpacing.gutter, 24),
                    sliver: SliverList.separated(
                      itemCount: fake.cartItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final it = fake.cartItems[i];
                        return SeMenuItemRow(
                          name: it['name'] as String,
                          description:
                              'Slow-cooked and seasoned the way it should be.',
                          price: Money.format(it['price'] as int),
                          imageUrl: '',
                          quantity: i == 0 ? 2 : 0,
                          onAdd: () {},
                          onRemove: () {},
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

Widget cartPreview() => SePageScaffold(
      title: 'Your cart',
      subtitle: '6 items from Island Grill Morant Bay',
      bottomBar: SeBottomBar(
        child: SeButton(label: 'Checkout · \$4,585', onPressed: () {}),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          for (final it in fake.cartItems) ...[
            SePanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: SeRadius.all(SeRadius.sm),
                    child: Container(
                      width: 56,
                      height: 56,
                      color: SeColors.surface50,
                      child: const Icon(SeIcons.food,
                          size: 24, color: SeColors.ink300),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it['name'] as String,
                            style: SeType.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(
                          (it['qty'] as int) > 1
                              ? '\$${(it['price'] as int) * (it['qty'] as int)}   ·   \$${it['price']} each'
                              : '\$${it['price']}',
                          style: SeType.tabular(SeType.bodyS)
                              .copyWith(color: SeColors.ink500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SeQtyStepper(
                    quantity: it['qty'] as int,
                    large: true,
                    onAdd: () {},
                    onRemove: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Center(
            child: SeButton(
              label: 'Add more items',
              icon: SeIcons.plus,
              variant: SeButtonVariant.ghost,
              size: SeButtonSize.medium,
              expand: false,
              onPressed: () {},
            ),
          ),
          const SizedBox(height: 20),
          SePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SPECIAL INSTRUCTIONS', style: SeType.eyebrow),
                const SizedBox(height: 6),
                Text('e.g. extra spicy, no onions…',
                    style: SeType.body.copyWith(color: SeColors.ink400)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: const [
                SeMoneyLine(label: 'Subtotal', value: '\$3,850'),
                SeMoneyLine(label: 'Delivery fee', value: '\$350'),
                SeMoneyLine(label: 'Service fee', value: '\$385'),
                Divider(height: 20, color: SeColors.ink200),
                SeMoneyLine(label: 'Total', value: '\$4,585', strong: true),
              ],
            ),
          ),
        ],
      ),
    );

Widget checkoutPreview() => SePageScaffold(
      title: 'Checkout',
      subtitle: 'Island Grill Morant Bay',
      bottomBar: SeBottomBar(
        child: SeButton(label: 'Choose payment · \$4,585', onPressed: () {}),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          SeSectionTitle(
              title: 'Deliver to', actionLabel: 'Manage', onAction: () {}),
          const SizedBox(height: 10),
          SeRowGroup(
            children: [
              _addressRow('Home', '14 Yallahs Main Road, St. Thomas',
                  SeIcons.home, true),
              _addressRow('Work', 'Shop 4, Morant Bay Square, Morant Bay',
                  SeIcons.box, false),
            ],
          ),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Order summary'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: const [
                SeMoneyLine(
                    label: 'Curry Goat with Rice & Peas × 2', value: '\$2,900'),
                SeMoneyLine(label: 'Festival (2 pcs) × 1', value: '\$300'),
                SeMoneyLine(label: 'Ting × 3', value: '\$750'),
                Divider(height: 18, color: SeColors.ink100),
                SeMoneyLine(label: 'Delivery fee', value: '\$350'),
                SeMoneyLine(label: 'Service fee (10%)', value: '\$385'),
                Divider(height: 18, color: SeColors.ink200),
                SeMoneyLine(label: 'Total', value: '\$4,585', strong: true),
              ],
            ),
          ),
        ],
      ),
    );

Widget _addressRow(String label, String text, IconData icon, bool selected) =>
    Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      color: selected ? SeColors.brandSoft : Colors.transparent,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? SeColors.brandAction : SeColors.ink300,
                width: 2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: SeColors.brandAction, shape: BoxShape.circle),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon,
                        size: 13,
                        color: selected ? SeColors.brandInk : SeColors.ink400),
                    const SizedBox(width: 5),
                    Text(label,
                        style: SeType.label.copyWith(
                            color:
                                selected ? SeColors.brandInk : SeColors.ink500)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(text,
                    style: SeType.bodyS.copyWith(color: SeColors.ink700)),
              ],
            ),
          ),
        ],
      ),
    );

Widget overseasPreview() => SePageScaffold(
      title: 'Send to family in Jamaica',
      subtitle: 'We shop locally and deliver to them',
      bottomBar: SeBottomBar(
        child: SeButton(
            label: 'Send request', icon: SeIcons.send, onPressed: () {}),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 28),
        children: [
          SePanel(
            color: SeColors.infoSoft,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(SeIcons.info, size: 18, color: SeColors.info),
                    const SizedBox(width: 8),
                    Text('How this works',
                        style: SeType.title
                            .copyWith(fontSize: 15, color: SeColors.infoInk)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Living abroad? Tell us what to buy and who to deliver it to '
                  'in Jamaica. We shop at a local supermarket or hardware store '
                  'and drop it to your family. The total depends on the store '
                  'and the day’s prices, so a member of the team will confirm '
                  'it with you first — nothing is charged until you agree.',
                  style:
                      SeType.bodyS.copyWith(color: SeColors.infoInk, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SeSectionTitle(title: 'Where we reach you'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: const [
                SeTextField(
                    label: 'Your email',
                    hint: 'you@example.com',
                    icon: SeIcons.envelope),
                SizedBox(height: 14),
                SeTextField(
                    label: 'Your phone',
                    hint: '+1 555 123 4567',
                    icon: SeIcons.phone),
                SizedBox(height: 14),
                SeTextField(
                    label: 'Where you’re based',
                    hint: 'City and country, e.g. Brooklyn, USA',
                    icon: SeIcons.location),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Who receives it in Jamaica'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                const SeTextField(
                    label: 'Recipient name',
                    hint: 'Full name',
                    icon: SeIcons.user),
                const SizedBox(height: 14),
                const SeTextField(
                    label: 'Delivery address',
                    hint: 'Street, town, any landmark',
                    icon: SeIcons.location,
                    minLines: 2,
                    maxLines: 3),
                const SizedBox(height: 14),
                _pickerPreview('Parish', 'St. Thomas', SeIcons.locationLine),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SeNotice.info(
            'We shop for everyday supermarket and hardware goods. Alcohol, '
            'tobacco and prescription medicine are the exceptions.',
          ),
        ],
      ),
    );

Widget _pickerPreview(String label, String value, IconData icon) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SeType.label.copyWith(color: SeColors.ink700)),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: SeColors.field,
            borderRadius: SeRadius.inputRadius,
            border: Border.all(color: SeColors.ink200, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: SeColors.ink400),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(value,
                      style: SeType.body.copyWith(color: SeColors.ink900))),
              const Icon(SeIcons.caretDown, size: 20, color: SeColors.ink400),
            ],
          ),
        ),
      ],
    );

// ─── Gap-fill previews ───────────────────────────────────────────────────────
// The five screens the instrument never photographed, plus the STATES a design
// has to survive: a list still loading, a list with nothing in it, a sheet, a
// toast. A design system built only from happy-path screens has no answer for
// the empty cart, and the empty cart is where products feel cheap.

/// The "See all" category list — [AllMerchantsScreen], which streams Firestore
/// in `build`, so its composition is rebuilt here from the same `SeMerchantRow`.
Widget allMerchantsPreview() => SePageScaffold(
      title: 'All Food',
      subtitle: 'Every partner near you',
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 28),
        itemCount: fake.merchants.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return SeSectionTitle(title: '${fake.merchants.length} merchants');
          }
          final m = fake.merchants[i - 1];
          return SeMerchantRow(
            name: m['name'] as String,
            imageUrl: '',
            category: 'Food',
            rating: m['rating'] as String,
            deliveryTime: m['deliveryTime'] as String,
            deliveryFee: m['deliveryFee'] as int,
            isOpen: m['isOpen'] as bool,
            onTap: () {},
          );
        },
      ),
    );

/// The same screen while the stream is still cold — the shimmer tier.
Widget allMerchantsLoadingPreview() => SePageScaffold(
      title: 'All Food',
      subtitle: 'Every partner near you',
      child: SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 20, SeSpacing.gutter, 28),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
              border: Border.all(color: SeColors.ink200),
            ),
            child: Row(
              children: const [
                SeSkeleton(width: 56, height: 56, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeSkeleton(width: 150, height: 14, radius: 6),
                      SizedBox(height: 8),
                      SeSkeleton(width: 200, height: 11, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// A category with no published partners yet.
Widget allMerchantsEmptyPreview() => SePageScaffold(
      title: 'All Pharmacy',
      subtitle: 'Every partner near you',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.storefront,
            title: 'No merchants yet',
            message: 'We are onboarding Pharmacy partners near you — '
                'check back soon.',
          ),
        ),
      ),
    );

/// Saved addresses — [SavedAddressesScreen] opens a Firestore subscription in
/// `initState`, so the list is rebuilt from the same `SeRowGroup` composition.
Widget savedAddressesPreview() => SePageScaffold(
      title: 'Saved addresses',
      subtitle: '3 addresses saved',
      bottomBar: SeBottomBar(
        child: SeButton(
          label: 'Add another address',
          icon: SeIcons.plus,
          variant: SeButtonVariant.secondary,
          onPressed: () {},
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          SeRowGroup(
            children: [
              _savedAddrRow(
                  'Home', '14 Yallahs Main Road, St. Thomas', SeIcons.home),
              _savedAddrRow('Work', 'Shop 3, Morant Bay Plaza, St. Thomas',
                  SeIcons.box),
              _savedAddrRow(
                  'Mom',
                  'Lot 27 Retreat District, Seaforth P.O., St. Thomas',
                  SeIcons.location),
            ],
          ),
        ],
      ),
    );

/// The same screen before a single address exists — the state a new customer
/// actually meets first.
Widget savedAddressesEmptyPreview() => SePageScaffold(
      title: 'Saved addresses',
      subtitle: 'Where we bring your orders',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.addresses,
            title: 'No saved addresses',
            message: 'Save a delivery address to check out faster.',
            ctaLabel: 'Add an address',
            onCta: () {},
          ),
        ),
      ),
    );

Widget _savedAddrRow(String label, String text, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: SeColors.brandAction.withValues(alpha: 0.10),
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: Icon(icon, size: 18, color: SeColors.brandAction),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SeType.title.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(text,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(
              width: 40,
              height: 40,
              child: Icon(SeIcons.edit, size: 18, color: SeColors.ink500)),
          const SizedBox(
              width: 40,
              height: 40,
              child: Icon(SeIcons.trash, size: 18, color: SeColors.danger)),
        ],
      ),
    );

/// An empty cart. The screen every food app gets wrong.
Widget cartEmptyPreview() => SePageScaffold(
      title: 'Your cart',
      subtitle: 'Nothing here yet',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.cart,
            title: 'Your cart is empty',
            message: 'Browse merchants near you and add a few things — '
                'we will bring them over.',
            ctaLabel: 'Browse merchants',
            onCta: () {},
          ),
        ),
      ),
    );

/// The add/edit address bottom sheet, docked over its page so the scrim and the
/// sheet's top radius are both visible.
Widget addressSheetPreview() => Stack(
      children: [
        savedAddressesPreview(),
        const Positioned.fill(child: ColoredBox(color: Color(0x8C140F12))),
        // `showSeBottomSheet` puts the sheet on a modal route, and a modal route
        // brings its own Material. Standing one up by hand does not, and every
        // TextField inside asserts without a Material ancestor.
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: SeColors.surface0,
            borderRadius: SeRadius.sheetTop,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, 4, SeSpacing.gutter, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SeSheetHandle(),
                  const SizedBox(height: 14),
                  Text('Add an address', style: SeType.h2),
                  const SizedBox(height: 18),
                  const SeFieldLabel('LABEL'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (ql, sel) in const [
                        ('Home', true),
                        ('Work', false),
                        ('Mom', false),
                        ('Dad', false),
                        ('School', false),
                        ('Other', false),
                      ])
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                sel ? SeColors.brandSoft : SeColors.surface50,
                            borderRadius: SeRadius.pill,
                            border: Border.all(
                                color: sel
                                    ? SeColors.brandAction
                                    : SeColors.ink200),
                          ),
                          child: Text(ql,
                              style: SeType.label.copyWith(
                                  color: sel
                                      ? SeColors.brandInk
                                      : SeColors.ink500)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SeTextField(
                      hint: 'Or type your own label…', icon: SeIcons.tag),
                  const SizedBox(height: 16),
                  const SeTextField(
                    label: 'ADDRESS',
                    hint: 'e.g. 14 Yallahs Main Road, St. Thomas',
                    icon: SeIcons.location,
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  SeButton(label: 'Add address', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      ],
    );

/// All four toast kinds at once. They are an overlay in the app, so they can
/// never appear in a screen shot — but they are the app's entire feedback
/// vocabulary, and a design system that omits them leaves every error state to
/// be invented twice.
Widget toastGalleryPreview() => ColoredBox(
      color: SeColors.surface50,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 48, SeSpacing.gutter, 24),
        children: [
          Text('Toasts', style: SeType.h1),
          const SizedBox(height: 4),
          Text('Docked under the status bar, tap to dismiss.',
              style: SeType.bodyS),
          const SizedBox(height: 20),
          _toast(SeColors.success, SeColors.successTint, SeIcons.checkCircle,
              'Address saved'),
          const SizedBox(height: 12),
          _toast(SeColors.danger, SeColors.dangerTint, SeIcons.warningCircle,
              'Please fill in both fields'),
          const SizedBox(height: 12),
          _toast(SeColors.info, SeColors.infoTint, SeIcons.info,
              'Your driver is 5 minutes away'),
          const SizedBox(height: 12),
          _toast(SeColors.brand, SeColors.brandSoft, SeIcons.info,
              'Promo code ISLAND20 applied'),
        ],
      ),
    );

Widget _toast(Color color, Color tint, IconData icon, String message) =>
    Container(
      decoration: BoxDecoration(
        color: SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        boxShadow: SeElevation.e3,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 5, color: color),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 19, color: color),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                child: Text(message,
                    style: SeType.body.copyWith(
                        color: SeColors.ink900, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
