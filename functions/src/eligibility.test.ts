import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  checkEligibility, discountBaseAmount, INELIGIBLE_MESSAGE,
  PromoEligibility, EligibilityContext
} from './eligibility';

/* PR-5. Each case is a condition the client asked for; the failure this
   protects against is a promo that lets in someone it was scoped to exclude
   (a free-money leak) or shuts out someone it was meant to include (a broken
   campaign nobody notices until support tickets show up). */

const ctx = (over: Partial<EligibilityContext> = {}): EligibilityContext => ({
  customerId: 'cust-1',
  priorOrderCount: 3,
  merchantId: 'merch-1',
  merchantCategory: 'Food',
  deliveryArea: '14 Bay Street, Morant Bay, St. Thomas',
  orderKind: 'food',
  ...over,
});

describe('no eligibility rules', () => {
  test('null and undefined both mean "open to everyone"', () => {
    assert.equal(checkEligibility(null, ctx()).eligible, true);
    assert.equal(checkEligibility(undefined, ctx()).eligible, true);
  });

  test('an empty object is the same as no rules', () => {
    assert.equal(checkEligibility({}, ctx()).eligible, true);
  });
});

describe('customer scope', () => {
  test('"new" admits a customer with no prior orders', () => {
    const elig: PromoEligibility = { customerScope: 'new' };
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 0 })).eligible, true);
  });

  test('"new" rejects a customer who has ordered before', () => {
    const elig: PromoEligibility = { customerScope: 'new' };
    const r = checkEligibility(elig, ctx({ priorOrderCount: 1 }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'not_new_customer');
  });

  test('"existing" is the mirror image', () => {
    const elig: PromoEligibility = { customerScope: 'existing' };
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 0 })).eligible, false);
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 1 })).eligible, true);
  });

  test('"selected" admits only the listed customer ids', () => {
    const elig: PromoEligibility = { customerScope: 'selected', customerIds: ['cust-1', 'cust-2'] };
    assert.equal(checkEligibility(elig, ctx({ customerId: 'cust-1' })).eligible, true);
    const r = checkEligibility(elig, ctx({ customerId: 'cust-9' }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'customer_not_selected');
  });

  test('"selected" with no ids admits nobody, not everybody', () => {
    // An admin who picked "Selected customers" but forgot to pick any must not
    // accidentally get an open code.
    const elig: PromoEligibility = { customerScope: 'selected' };
    assert.equal(checkEligibility(elig, ctx()).eligible, false);
  });
});

describe('merchant / category / area scope', () => {
  test('selected merchants narrows to that list', () => {
    const elig: PromoEligibility = { merchantIds: ['merch-1', 'merch-2'] };
    assert.equal(checkEligibility(elig, ctx({ merchantId: 'merch-1' })).eligible, true);
    assert.equal(checkEligibility(elig, ctx({ merchantId: 'merch-9' })).eligible, false);
  });

  test('a null merchantId (e.g. a package order) fails a merchant-scoped code', () => {
    const elig: PromoEligibility = { merchantIds: ['merch-1'] };
    const r = checkEligibility(elig, ctx({ merchantId: null }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'merchant_not_eligible');
  });

  test('selected categories narrows by the merchant\'s category', () => {
    const elig: PromoEligibility = { categories: ['Grocery', 'Pharmacy'] };
    assert.equal(checkEligibility(elig, ctx({ merchantCategory: 'Grocery' })).eligible, true);
    assert.equal(checkEligibility(elig, ctx({ merchantCategory: 'Food' })).eligible, false);
  });

  test('selected delivery areas match the address case-insensitively', () => {
    const elig: PromoEligibility = { deliveryAreas: ['St. Thomas', 'Portland'] };
    assert.equal(checkEligibility(elig, ctx({ deliveryArea: '12 Main Rd, st. thomas' })).eligible, true);
    const r = checkEligibility(elig, ctx({ deliveryArea: '5 Half Way Tree, Kingston' }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'area_not_eligible');
  });

  test('an empty delivery address fails an area-scoped code rather than matching by accident', () => {
    const elig: PromoEligibility = { deliveryAreas: ['St. Thomas'] };
    assert.equal(checkEligibility(elig, ctx({ deliveryArea: '' })).eligible, false);
    assert.equal(checkEligibility(elig, ctx({ deliveryArea: null })).eligible, false);
  });
});

describe('first order only', () => {
  test('admits a customer with zero prior orders', () => {
    const elig: PromoEligibility = { firstOrderOnly: true };
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 0 })).eligible, true);
  });

  test('rejects once there is any order history', () => {
    const elig: PromoEligibility = { firstOrderOnly: true };
    const r = checkEligibility(elig, ctx({ priorOrderCount: 1 }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'not_first_order');
  });

  test('is a distinct condition from customerScope "new" — both can be set', () => {
    const elig: PromoEligibility = { customerScope: 'new', firstOrderOnly: true };
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 0 })).eligible, true);
    // Fails on the first check it hits; either reason is a correct rejection.
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 2 })).eligible, false);
  });
});

describe('order kind — including Shop & Deliver', () => {
  test('restricts to the listed kinds', () => {
    const elig: PromoEligibility = { orderKinds: ['shop_deliver'] };
    assert.equal(checkEligibility(elig, ctx({ orderKind: 'shop_deliver' })).eligible, true);
    const r = checkEligibility(elig, ctx({ orderKind: 'food' }));
    assert.equal(r.eligible, false);
    assert.equal(r.reason, 'order_kind_not_eligible');
  });

  test('an unrestricted code applies to every kind, Shop & Deliver included', () => {
    for (const kind of ['food', 'package', 'shop_deliver'] as const) {
      assert.equal(checkEligibility({}, ctx({ orderKind: kind })).eligible, true, kind);
    }
  });
});

describe('conditions compose (AND, not OR)', () => {
  test('a code narrowed on two axes needs both to pass', () => {
    const elig: PromoEligibility = { customerScope: 'new', categories: ['Grocery'] };
    // Right customer, wrong category.
    assert.equal(
      checkEligibility(elig, ctx({ priorOrderCount: 0, merchantCategory: 'Food' })).eligible,
      false
    );
    // Right category, wrong customer.
    assert.equal(
      checkEligibility(elig, ctx({ priorOrderCount: 5, merchantCategory: 'Grocery' })).eligible,
      false
    );
    // Both right.
    assert.equal(
      checkEligibility(elig, ctx({ priorOrderCount: 0, merchantCategory: 'Grocery' })).eligible,
      true
    );
  });
});

describe('every rejection carries a customer-safe message', () => {
  test('INELIGIBLE_MESSAGE covers every reason', () => {
    const reasons = [
      'not_new_customer', 'not_existing_customer', 'customer_not_selected',
      'merchant_not_eligible', 'category_not_eligible', 'area_not_eligible',
      'not_first_order', 'order_kind_not_eligible'
    ] as const;
    for (const r of reasons) assert.ok(INELIGIBLE_MESSAGE[r], r);
  });
});

describe('discountBaseAmount', () => {
  test('defaults to the subtotal', () => {
    assert.equal(discountBaseAmount(null, 5000, 300), 5000);
    assert.equal(discountBaseAmount({}, 5000, 300), 5000);
    assert.equal(discountBaseAmount({ discountBase: 'subtotal' }, 5000, 300), 5000);
  });

  test('"deliveryFee" uses the delivery fee instead', () => {
    assert.equal(discountBaseAmount({ discountBase: 'deliveryFee' }, 5000, 300), 300);
  });
});
