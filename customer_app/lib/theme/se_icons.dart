import 'package:flutter/material.dart';

/// ShipEast Design System — Icon façade (SEDS §1.5).
///
/// Every screen references icons through this single class so the app has ONE
/// icon vocabulary and ONE swap point for the underlying family.
///
/// Backed by Material's **rounded/outlined** icon set: it ships inside Flutter
/// (no external dependency, no version-skew risk) and reads as one cohesive,
/// friendly family. `*Fill` names map to the filled/rounded variant used for
/// active nav and selected states; the plain names map to the outlined variant.
///
/// (Phosphor was the original intent but its current release extends the now
/// `final` `IconData` class and cannot compile against modern Flutter; if a
/// fixed Phosphor release lands, only this file changes.)
class SeIcons {
  SeIcons._();

  // Bottom navigation
  static const IconData home = Icons.home_outlined;
  static const IconData homeFill = Icons.home_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData searchFill = Icons.search_rounded;
  static const IconData orders = Icons.receipt_long_outlined;
  static const IconData ordersFill = Icons.receipt_long_rounded;
  static const IconData bell = Icons.notifications_outlined;
  static const IconData bellFill = Icons.notifications_rounded;
  static const IconData user = Icons.person_outline_rounded;
  static const IconData userFill = Icons.person_rounded;

  // Categories
  static const IconData food = Icons.restaurant_rounded;
  static const IconData grocery = Icons.shopping_basket_outlined;
  static const IconData packages = Icons.inventory_2_outlined;
  static const IconData pharmacy = Icons.local_pharmacy_outlined;
  static const IconData foodFill = Icons.restaurant_rounded;
  static const IconData groceryFill = Icons.shopping_basket_rounded;
  static const IconData packagesFill = Icons.inventory_2_rounded;
  static const IconData pharmacyFill = Icons.local_pharmacy_rounded;

  // Home / merchant
  static const IconData location = Icons.location_on_outlined;
  static const IconData locationFill = Icons.location_on_rounded;
  static const IconData locationLine = Icons.location_on_outlined;
  static const IconData plane = Icons.flight_takeoff_rounded;
  static const IconData storefront = Icons.storefront_outlined;
  static const IconData heart = Icons.favorite_border_rounded;
  static const IconData heartFill = Icons.favorite_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData starOutline = Icons.star_border_rounded;
  static const IconData clock = Icons.access_time_rounded;
  static const IconData bike = Icons.delivery_dining_rounded;
  static const IconData scales = Icons.monitor_weight_outlined;
  static const IconData box = Icons.inventory_2_rounded;

  // Cart / checkout / payment
  static const IconData cart = Icons.shopping_cart_outlined;
  static const IconData cartFill = Icons.shopping_cart_rounded;
  static const IconData creditCard = Icons.credit_card_rounded;
  static const IconData cash = Icons.payments_outlined;
  static const IconData tag = Icons.local_offer_rounded;
  static const IconData note = Icons.notes_rounded;

  // Actions
  static const IconData plus = Icons.add_rounded;
  static const IconData minus = Icons.remove_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData checkCircle = Icons.check_circle_rounded;
  static const IconData refresh = Icons.refresh_rounded; // reorder / retry

  /// Unselected state for the cancellation reason picker (P5-03). Paired
  /// with [checkCircle] rather than a Material Radio so the row stays one
  /// tappable surface instead of a small circle beside dead text.
  static const IconData radioOff = Icons.radio_button_unchecked;
  static const IconData trash = Icons.delete_outline_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData camera = Icons.photo_camera_rounded;
  static const IconData phone = Icons.phone_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData share = Icons.share_rounded;
  // Submitting a request to a person rather than to a queue — the overseas
  // enquiry form, where nothing is bought and something is sent.
  static const IconData send = Icons.send_rounded;

  // Chevrons / arrows
  static const IconData caretRight = Icons.chevron_right_rounded;
  static const IconData caretLeft = Icons.chevron_left_rounded;
  static const IconData caretDown = Icons.expand_more_rounded;
  static const IconData arrowLeft = Icons.arrow_back_rounded;
  static const IconData arrowRight = Icons.arrow_forward_rounded;

  // Profile / menu
  static const IconData settings = Icons.settings_rounded;
  static const IconData signOut = Icons.logout_rounded;
  static const IconData shield = Icons.shield_outlined;
  static const IconData help = Icons.help_outline_rounded;
  static const IconData chat = Icons.chat_bubble_outline_rounded;
  static const IconData addresses = Icons.location_on_outlined;
  static const IconData sun = Icons.light_mode_rounded;
  static const IconData moon = Icons.dark_mode_rounded;

  // Auth
  static const IconData envelope = Icons.mail_outline_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData eye = Icons.visibility_outlined;
  static const IconData eyeSlash = Icons.visibility_off_outlined;
  static const IconData google = Icons.g_mobiledata_rounded;
  static const IconData userCircle = Icons.account_circle_outlined;

  // States / feedback
  static const IconData warning = Icons.warning_rounded;
  static const IconData warningCircle = Icons.error_rounded;
  static const IconData info = Icons.info_rounded;
  static const IconData noConnection = Icons.wifi_off_rounded;
  static const IconData filter = Icons.filter_list_rounded;
  static const IconData list = Icons.list_rounded;
  static const IconData rocket = Icons.rocket_launch_outlined;
  static const IconData sparkle = Icons.auto_awesome_rounded;
  static const IconData confetti = Icons.celebration_rounded;
}
