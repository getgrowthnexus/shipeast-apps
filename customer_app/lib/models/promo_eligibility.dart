/// Promo discount eligibility (checklist PR-5).
///
/// Mirrors `functions/src/eligibility.ts` — the server is authoritative; this
/// is the checkout-time preview so a customer sees "this code doesn't apply
/// here" instantly instead of after a round trip. Edit both, or neither.
///
/// "Give me options for who can get the discount" — twelve conditions in the
/// client's own words: all / new / existing / selected customers, selected
/// merchants, selected categories, selected delivery areas, first order only,
/// delivery fee only, order subtotal, Shop & Deliver requests, specific
/// dates/times. The date/time pair is `PromoCode`'s existing `startsAt` /
/// `expiresAt`; everything else lives here.
library;

enum CustomerScope { new_, existing, selected }

/// What kind of request this discount can be redeemed against. `shopDeliver`
/// is a Shop & Deliver quote, not an order.
enum OrderKind { food, package, shopDeliver }

enum DiscountBase { subtotal, deliveryFee }

enum IneligibleReason {
  notNewCustomer,
  notExistingCustomer,
  customerNotSelected,
  merchantNotEligible,
  categoryNotEligible,
  areaNotEligible,
  notFirstOrder,
  orderKindNotEligible,
}

const Map<IneligibleReason, String> ineligibleMessage = {
  IneligibleReason.notNewCustomer: 'This code is for new customers only.',
  IneligibleReason.notExistingCustomer:
      'This code is for returning customers only.',
  IneligibleReason.customerNotSelected:
      'This code is not available on your account.',
  IneligibleReason.merchantNotEligible:
      'This code does not apply to this merchant.',
  IneligibleReason.categoryNotEligible:
      'This code does not apply to this category.',
  IneligibleReason.areaNotEligible:
      'This code is not available for your delivery area.',
  IneligibleReason.notFirstOrder: 'This code is for your first order only.',
  IneligibleReason.orderKindNotEligible:
      'This code does not apply to this kind of request.',
};

class PromoEligibility {
  final CustomerScope? customerScope;
  final List<String>? customerIds;
  final List<String>? merchantIds;
  final List<String>? categories;
  final List<String>? deliveryAreas;
  final bool firstOrderOnly;
  final DiscountBase discountBase;
  final List<OrderKind>? orderKinds;

  const PromoEligibility({
    this.customerScope,
    this.customerIds,
    this.merchantIds,
    this.categories,
    this.deliveryAreas,
    this.firstOrderOnly = false,
    this.discountBase = DiscountBase.subtotal,
    this.orderKinds,
  });

  /// Reads the `eligibility` map stored on a promo document. Absent or
  /// malformed data reads as "no restriction" on every axis — the same
  /// fail-open-to-existing-behaviour choice the server makes, because a promo
  /// created before PR-5 has no `eligibility` field at all.
  factory PromoEligibility.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PromoEligibility();
    return PromoEligibility(
      customerScope: _scopeOf(map['customerScope']),
      customerIds: _stringList(map['customerIds']),
      merchantIds: _stringList(map['merchantIds']),
      categories: _stringList(map['categories']),
      deliveryAreas: _stringList(map['deliveryAreas']),
      firstOrderOnly: map['firstOrderOnly'] == true,
      discountBase: map['discountBase'] == 'deliveryFee'
          ? DiscountBase.deliveryFee
          : DiscountBase.subtotal,
      orderKinds: _kindList(map['orderKinds']),
    );
  }

  static CustomerScope? _scopeOf(Object? v) => switch (v) {
        'new' => CustomerScope.new_,
        'existing' => CustomerScope.existing,
        'selected' => CustomerScope.selected,
        _ => null,
      };

  static List<String>? _stringList(Object? v) {
    if (v is! List) return null;
    final out = v.whereType<String>().toList();
    return out.isEmpty ? null : out;
  }

  static List<OrderKind>? _kindList(Object? v) {
    if (v is! List) return null;
    final out = v
        .whereType<String>()
        .map((s) => switch (s) {
              'food' => OrderKind.food,
              'package' => OrderKind.package,
              'shop_deliver' => OrderKind.shopDeliver,
              _ => null,
            })
        .whereType<OrderKind>()
        .toList();
    return out.isEmpty ? null : out;
  }
}

class EligibilityContext {
  final String customerId;
  final int priorOrderCount;
  final String? merchantId;
  final String? merchantCategory;
  final String? deliveryArea;
  final OrderKind orderKind;

  const EligibilityContext({
    required this.customerId,
    required this.priorOrderCount,
    this.merchantId,
    this.merchantCategory,
    this.deliveryArea,
    this.orderKind = OrderKind.food,
  });
}

class EligibilityResult {
  final bool eligible;
  final IneligibleReason? reason;
  final String? message;
  const EligibilityResult.ok()
      : eligible = true,
        reason = null,
        message = null;
  const EligibilityResult.rejected(this.reason)
      : eligible = false,
        message = null;
  String? get displayMessage =>
      eligible ? null : (message ?? ineligibleMessage[reason]);
}

/// All specified conditions must pass (AND). See `checkEligibility` in
/// `functions/src/eligibility.ts` for the reasoning behind each one.
EligibilityResult checkEligibility(
  PromoEligibility elig,
  EligibilityContext ctx,
) {
  if (elig.customerScope == CustomerScope.new_ && ctx.priorOrderCount > 0) {
    return const EligibilityResult.rejected(IneligibleReason.notNewCustomer);
  }
  if (elig.customerScope == CustomerScope.existing &&
      ctx.priorOrderCount <= 0) {
    return const EligibilityResult.rejected(
        IneligibleReason.notExistingCustomer);
  }
  if (elig.customerScope == CustomerScope.selected) {
    final ids = elig.customerIds ?? const [];
    if (!ids.contains(ctx.customerId)) {
      return const EligibilityResult.rejected(
          IneligibleReason.customerNotSelected);
    }
  }

  if (elig.merchantIds != null && elig.merchantIds!.isNotEmpty) {
    if (ctx.merchantId == null || !elig.merchantIds!.contains(ctx.merchantId)) {
      return const EligibilityResult.rejected(
          IneligibleReason.merchantNotEligible);
    }
  }

  if (elig.categories != null && elig.categories!.isNotEmpty) {
    if (ctx.merchantCategory == null ||
        !elig.categories!.contains(ctx.merchantCategory)) {
      return const EligibilityResult.rejected(
          IneligibleReason.categoryNotEligible);
    }
  }

  if (elig.deliveryAreas != null && elig.deliveryAreas!.isNotEmpty) {
    final area = (ctx.deliveryArea ?? '').trim().toLowerCase();
    final matches = area.isNotEmpty &&
        elig.deliveryAreas!.any((a) => area.contains(a.trim().toLowerCase()));
    if (!matches) {
      return const EligibilityResult.rejected(IneligibleReason.areaNotEligible);
    }
  }

  if (elig.firstOrderOnly && ctx.priorOrderCount > 0) {
    return const EligibilityResult.rejected(IneligibleReason.notFirstOrder);
  }

  if (elig.orderKinds != null && elig.orderKinds!.isNotEmpty) {
    if (!elig.orderKinds!.contains(ctx.orderKind)) {
      return const EligibilityResult.rejected(
          IneligibleReason.orderKindNotEligible);
    }
  }

  return const EligibilityResult.ok();
}

/// Checklist PR-5 "Delivery fee only" / "Order subtotal".
int discountBaseAmount(PromoEligibility elig, int subtotal, int deliveryFee) =>
    elig.discountBase == DiscountBase.deliveryFee ? deliveryFee : subtotal;
