/// Merchant categories — the one list every screen reads.
///
/// [value] is what is stored on `merchants/{id}.category` and what category
/// queries match on; it is shared with the admin panel's merchant form and
/// never changes when the copy does. [display] is the word a customer reads.
/// The client asked for "Groceries" on screen (checklist, Sep 2026); renaming
/// the stored "Grocery" would have emptied that category for every existing
/// merchant.
///
/// Home shows [primary] as tiles plus a "More" tile that opens [more]. Hues
/// reuse the design system's five families rather than adding new colours.
library;

import 'package:flutter/widgets.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';

class MerchantCategory {
  final String value;
  final String display;
  final IconData icon;
  final Color hue;
  final Color tint;

  const MerchantCategory._(
      this.value, this.display, this.icon, this.hue, this.tint);

  static const food = MerchantCategory._(
      'Food', 'Food', SeIcons.food, SeColors.catFood, SeColors.catFoodTint);
  static const grocery = MerchantCategory._('Grocery', 'Groceries',
      SeIcons.grocery, SeColors.catGrocery, SeColors.catGroceryTint);
  static const packages = MerchantCategory._('Packages', 'Packages',
      SeIcons.packages, SeColors.catPackages, SeColors.catPackagesTint);
  static const pharmacy = MerchantCategory._('Pharmacy', 'Pharmacy',
      SeIcons.pharmacy, SeColors.catPharmacy, SeColors.catPharmacyTint);
  static const cookingGas = MerchantCategory._('Cooking Gas', 'Cooking Gas',
      SeIcons.cookingGas, SeColors.warning, SeColors.warningSoft);
  static const hardware = MerchantCategory._('Hardware', 'Hardware',
      SeIcons.hardware, SeColors.ink500, SeColors.ink100);
  static const errands = MerchantCategory._('Errands', 'Errands',
      SeIcons.errands, SeColors.success, SeColors.successSoft);
  static const gifts = MerchantCategory._('Gifts/Balloons', 'Gifts/Balloons',
      SeIcons.balloons, SeColors.brand, SeColors.brandSoft);
  static const pickupDelivery = MerchantCategory._('Pickup & Delivery',
      'Pickup & Delivery', SeIcons.pickupDelivery, SeColors.warning,
      SeColors.warningSoft);
  static const businessServices = MerchantCategory._('Business Services',
      'Business Services', SeIcons.business, SeColors.info, SeColors.infoSoft);

  /// Home tiles before "More". Packages is a request form, not a merchant list.
  static const primary = [food, grocery, packages];

  /// Listed when the customer taps "More", in the client's order.
  static const more = [
    pharmacy,
    cookingGas,
    hardware,
    errands,
    gifts,
    pickupDelivery,
    businessServices,
  ];

  /// Every category a merchant can be listed under (search chips).
  static const all = [food, grocery, packages, ...more];

  /// The entry for a stored value, or null for one this build does not know.
  static MerchantCategory? of(String stored) {
    for (final c in all) {
      if (c.value == stored) return c;
    }
    return null;
  }

  /// The on-screen label for a stored category value.
  static String label(String stored) => of(stored)?.display ?? stored;
}
