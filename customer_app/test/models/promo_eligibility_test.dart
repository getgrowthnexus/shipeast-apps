import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/promo_eligibility.dart';

/// PR-5. Mirrors `functions/src/eligibility.test.ts` case for case — this is
/// the checkout-time preview, and if it disagrees with the server the
/// customer sees "eligible" right up until redemption fails.
void main() {
  EligibilityContext ctx({
    String customerId = 'cust-1',
    int priorOrderCount = 3,
    String? merchantId = 'merch-1',
    String? merchantCategory = 'Food',
    String? deliveryArea = '14 Bay Street, Morant Bay, St. Thomas',
    OrderKind orderKind = OrderKind.food,
  }) =>
      EligibilityContext(
        customerId: customerId,
        priorOrderCount: priorOrderCount,
        merchantId: merchantId,
        merchantCategory: merchantCategory,
        deliveryArea: deliveryArea,
        orderKind: orderKind,
      );

  group('no eligibility rules', () {
    test('the default PromoEligibility() is open to everyone', () {
      expect(checkEligibility(const PromoEligibility(), ctx()).eligible, isTrue);
    });
  });

  group('customer scope', () {
    test('"new" admits a customer with no prior orders', () {
      const elig = PromoEligibility(customerScope: CustomerScope.new_);
      expect(
        checkEligibility(elig, ctx(priorOrderCount: 0)).eligible,
        isTrue,
      );
    });

    test('"new" rejects a customer who has ordered before', () {
      const elig = PromoEligibility(customerScope: CustomerScope.new_);
      final r = checkEligibility(elig, ctx(priorOrderCount: 1));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.notNewCustomer);
    });

    test('"existing" is the mirror image', () {
      const elig = PromoEligibility(customerScope: CustomerScope.existing);
      expect(checkEligibility(elig, ctx(priorOrderCount: 0)).eligible, isFalse);
      expect(checkEligibility(elig, ctx(priorOrderCount: 1)).eligible, isTrue);
    });

    test('"selected" admits only the listed customer ids', () {
      const elig = PromoEligibility(
        customerScope: CustomerScope.selected,
        customerIds: ['cust-1', 'cust-2'],
      );
      expect(checkEligibility(elig, ctx(customerId: 'cust-1')).eligible, isTrue);
      final r = checkEligibility(elig, ctx(customerId: 'cust-9'));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.customerNotSelected);
    });

    test('"selected" with no ids admits nobody, not everybody', () {
      const elig = PromoEligibility(customerScope: CustomerScope.selected);
      expect(checkEligibility(elig, ctx()).eligible, isFalse);
    });
  });

  group('merchant / category / area scope', () {
    test('selected merchants narrows to that list', () {
      const elig = PromoEligibility(merchantIds: ['merch-1', 'merch-2']);
      expect(checkEligibility(elig, ctx(merchantId: 'merch-1')).eligible, isTrue);
      expect(checkEligibility(elig, ctx(merchantId: 'merch-9')).eligible, isFalse);
    });

    test('a null merchantId (e.g. a package order) fails a merchant-scoped code', () {
      const elig = PromoEligibility(merchantIds: ['merch-1']);
      final r = checkEligibility(elig, ctx(merchantId: null));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.merchantNotEligible);
    });

    test("selected categories narrows by the merchant's category", () {
      const elig = PromoEligibility(categories: ['Grocery', 'Pharmacy']);
      expect(checkEligibility(elig, ctx(merchantCategory: 'Grocery')).eligible, isTrue);
      expect(checkEligibility(elig, ctx(merchantCategory: 'Food')).eligible, isFalse);
    });

    test('selected delivery areas match the address case-insensitively', () {
      const elig = PromoEligibility(deliveryAreas: ['St. Thomas', 'Portland']);
      expect(
        checkEligibility(elig, ctx(deliveryArea: '12 Main Rd, st. thomas')).eligible,
        isTrue,
      );
      final r = checkEligibility(elig, ctx(deliveryArea: '5 Half Way Tree, Kingston'));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.areaNotEligible);
    });

    test('an empty delivery address fails an area-scoped code rather than matching by accident', () {
      const elig = PromoEligibility(deliveryAreas: ['St. Thomas']);
      expect(checkEligibility(elig, ctx(deliveryArea: '')).eligible, isFalse);
      expect(checkEligibility(elig, ctx(deliveryArea: null)).eligible, isFalse);
    });
  });

  group('first order only', () {
    test('admits a customer with zero prior orders', () {
      const elig = PromoEligibility(firstOrderOnly: true);
      expect(checkEligibility(elig, ctx(priorOrderCount: 0)).eligible, isTrue);
    });

    test('rejects once there is any order history', () {
      const elig = PromoEligibility(firstOrderOnly: true);
      final r = checkEligibility(elig, ctx(priorOrderCount: 1));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.notFirstOrder);
    });

    test('is a distinct condition from customerScope "new" — both can be set', () {
      const elig = PromoEligibility(
        customerScope: CustomerScope.new_,
        firstOrderOnly: true,
      );
      expect(checkEligibility(elig, ctx(priorOrderCount: 0)).eligible, isTrue);
      expect(checkEligibility(elig, ctx(priorOrderCount: 2)).eligible, isFalse);
    });
  });

  group('order kind — including Shop & Deliver', () {
    test('restricts to the listed kinds', () {
      const elig = PromoEligibility(orderKinds: [OrderKind.shopDeliver]);
      expect(
        checkEligibility(elig, ctx(orderKind: OrderKind.shopDeliver)).eligible,
        isTrue,
      );
      final r = checkEligibility(elig, ctx(orderKind: OrderKind.food));
      expect(r.eligible, isFalse);
      expect(r.reason, IneligibleReason.orderKindNotEligible);
    });

    test('an unrestricted code applies to every kind, Shop & Deliver included', () {
      for (final kind in OrderKind.values) {
        expect(
          checkEligibility(const PromoEligibility(), ctx(orderKind: kind)).eligible,
          isTrue,
          reason: kind.toString(),
        );
      }
    });
  });

  group('conditions compose (AND, not OR)', () {
    test('a code narrowed on two axes needs both to pass', () {
      const elig = PromoEligibility(
        customerScope: CustomerScope.new_,
        categories: ['Grocery'],
      );
      expect(
        checkEligibility(
          elig,
          ctx(priorOrderCount: 0, merchantCategory: 'Food'),
        ).eligible,
        isFalse,
      );
      expect(
        checkEligibility(
          elig,
          ctx(priorOrderCount: 5, merchantCategory: 'Grocery'),
        ).eligible,
        isFalse,
      );
      expect(
        checkEligibility(
          elig,
          ctx(priorOrderCount: 0, merchantCategory: 'Grocery'),
        ).eligible,
        isTrue,
      );
    });
  });

  group('discountBaseAmount', () {
    test('defaults to the subtotal', () {
      expect(discountBaseAmount(const PromoEligibility(), 5000, 300), 5000);
      expect(
        discountBaseAmount(
          const PromoEligibility(discountBase: DiscountBase.subtotal),
          5000,
          300,
        ),
        5000,
      );
    });

    test('"deliveryFee" uses the delivery fee instead', () {
      expect(
        discountBaseAmount(
          const PromoEligibility(discountBase: DiscountBase.deliveryFee),
          5000,
          300,
        ),
        300,
      );
    });
  });

  group('PromoEligibility.fromMap', () {
    test('a null map reads as no restriction on any axis', () {
      final elig = PromoEligibility.fromMap(null);
      expect(checkEligibility(elig, ctx()).eligible, isTrue);
    });

    test('reads every field back out of a Firestore-shaped map', () {
      final elig = PromoEligibility.fromMap({
        'customerScope': 'selected',
        'customerIds': ['cust-1'],
        'merchantIds': ['merch-1'],
        'categories': ['Food'],
        'deliveryAreas': ['St. Thomas'],
        'firstOrderOnly': true,
        'discountBase': 'deliveryFee',
        'orderKinds': ['shop_deliver'],
      });
      expect(elig.customerScope, CustomerScope.selected);
      expect(elig.customerIds, ['cust-1']);
      expect(elig.discountBase, DiscountBase.deliveryFee);
      expect(elig.orderKinds, [OrderKind.shopDeliver]);
      // firstOrderOnly is set above, so the context must be a first order.
      expect(
        checkEligibility(
          elig,
          ctx(
            customerId: 'cust-1',
            priorOrderCount: 0,
            orderKind: OrderKind.shopDeliver,
          ),
        ).eligible,
        isTrue,
      );
    });

    test('an unrecognised customerScope string is ignored, not thrown', () {
      final elig = PromoEligibility.fromMap({'customerScope': 'literally anything'});
      expect(elig.customerScope, isNull);
    });
  });
}
