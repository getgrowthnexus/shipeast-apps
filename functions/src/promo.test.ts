import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { evaluatePromo, PromoDoc } from './promo';

/* P3-03. Each rejection below corresponds to a rule that did not exist: every
   code discounted J$0, never expired, and ignored its cap. */

const NOW = Date.UTC(2026, 6, 21);
const DAY = 86_400_000;

function promo(overrides: Partial<PromoDoc> = {}): PromoDoc {
  return {
    code: 'SAVE200',
    discountType: 'fixed',
    discountAmount: 200,
    minOrderTotal: 0,
    maxDiscount: null,
    startsAtMillis: null,
    expiresAtMillis: null,
    maxUses: 100,
    usedCount: 0,
    active: true,
    ...overrides,
  };
}

describe('the discount actually applies', () => {
  test('a J$200-off code takes off J$200', () => {
    // This is the acceptance criterion. It used to take off J$0.
    const r = evaluatePromo(promo(), 1500, NOW);
    assert.equal(r.ok, true);
    assert.equal(r.discount, 200);
  });

  test('a percentage code discounts the subtotal', () => {
    const r = evaluatePromo(
      promo({ discountType: 'percent', discountAmount: 20 }), 1500, NOW);
    assert.equal(r.discount, 300);
  });

  test('a discount never exceeds the subtotal', () => {
    // Otherwise the order total goes negative.
    const r = evaluatePromo(promo({ discountAmount: 5000 }), 1500, NOW);
    assert.equal(r.discount, 1500);
  });
});

describe('the cap on percentage codes', () => {
  test('maxDiscount caps a percentage discount', () => {
    const r = evaluatePromo(
      promo({ discountType: 'percent', discountAmount: 50, maxDiscount: 500 }),
      10000, NOW);
    assert.equal(r.discount, 500, 'a 50% code on J$10,000 must cap at J$500');
  });

  test('an uncapped percentage code still applies in full', () => {
    const r = evaluatePromo(
      promo({ discountType: 'percent', discountAmount: 50, maxDiscount: null }),
      10000, NOW);
    assert.equal(r.discount, 5000);
  });

  test('a typo\'d percentage over 100 clamps rather than going negative', () => {
    // Refusing the code at checkout would punish the customer for the admin's
    // typo; a negative total would be worse still.
    const r = evaluatePromo(
      promo({ discountType: 'percent', discountAmount: 150 }), 1000, NOW);
    assert.equal(r.discount, 1000);
  });
});

describe('rejections', () => {
  test('an unknown code is rejected', () => {
    assert.equal(evaluatePromo(null, 1500, NOW).reason, 'not_found');
  });

  test('an inactive code is rejected', () => {
    assert.equal(evaluatePromo(promo({ active: false }), 1500, NOW).reason, 'inactive');
  });

  test('an expired code is rejected', () => {
    const r = evaluatePromo(promo({ expiresAtMillis: NOW - DAY }), 1500, NOW);
    assert.equal(r.reason, 'expired');
    assert.equal(r.discount, 0);
  });

  test('a code expiring tomorrow still works', () => {
    assert.equal(evaluatePromo(promo({ expiresAtMillis: NOW + DAY }), 1500, NOW).ok, true);
  });

  test('a null expiry means never expires', () => {
    assert.equal(evaluatePromo(promo({ expiresAtMillis: null }), 1500, NOW).ok, true);
  });

  test('a code with a future start date is not redeemable yet (PR-6)', () => {
    const r = evaluatePromo(promo({ startsAtMillis: NOW + DAY }), 1500, NOW);
    assert.equal(r.reason, 'not_yet_started');
    assert.equal(r.discount, 0);
  });

  test('a code whose start has passed works', () => {
    assert.equal(evaluatePromo(promo({ startsAtMillis: NOW - DAY }), 1500, NOW).ok, true);
  });

  test('a null start means it is live immediately', () => {
    assert.equal(evaluatePromo(promo({ startsAtMillis: null }), 1500, NOW).ok, true);
  });

  test('an exhausted code is rejected', () => {
    const r = evaluatePromo(promo({ maxUses: 5, usedCount: 5 }), 1500, NOW);
    assert.equal(r.reason, 'exhausted');
  });

  test('the last available use still works', () => {
    // Off-by-one here either burns a use the customer paid for or gives one away.
    assert.equal(evaluatePromo(promo({ maxUses: 5, usedCount: 4 }), 1500, NOW).ok, true);
  });

  test('an order below the minimum is rejected', () => {
    const r = evaluatePromo(promo({ minOrderTotal: 2000 }), 1500, NOW);
    assert.equal(r.reason, 'below_minimum');
  });

  test('an order exactly at the minimum is accepted', () => {
    assert.equal(evaluatePromo(promo({ minOrderTotal: 1500 }), 1500, NOW).ok, true);
  });

  test('a misconfigured discountType is rejected, not silently applied', () => {
    const bad = promo({ discountType: 'percentage' as unknown as 'percent' });
    assert.equal(evaluatePromo(bad, 1500, NOW).reason, 'malformed');
  });

  test('a negative discount amount is rejected', () => {
    assert.equal(evaluatePromo(promo({ discountAmount: -100 }), 1500, NOW).reason, 'malformed');
  });

  test('PR-5: a delivery-fee-only code discounts the delivery fee, not the subtotal', () => {
    // 20% off a J$300 delivery fee, on a J$5,000 order — the discount must be
    // J$60, not J$1,000.
    const p = promo({ discountType: 'percent', discountAmount: 20, maxDiscount: 10000 });
    const r = evaluatePromo(p, 5000, NOW, 300);
    assert.equal(r.ok, true);
    assert.equal(r.discount, 60);
  });

  test('PR-5: the minimum-order check still runs against the real subtotal', () => {
    // Even though the discount comes off the delivery fee, "spend at least
    // J$2,000" means the order total, not the fee.
    const p = promo({ minOrderTotal: 2000 });
    const r = evaluatePromo(p, 1500, NOW, 300);
    assert.equal(r.reason, 'below_minimum');
  });

  test('PR-5: a delivery-fee discount cannot exceed the delivery fee itself', () => {
    const p = promo({ discountType: 'fixed', discountAmount: 9999 });
    const r = evaluatePromo(p, 5000, NOW, 300);
    assert.equal(r.ok, true);
    assert.equal(r.discount, 300);
  });

  test('every rejection returns a zero discount', () => {
    const cases: PromoDoc[] = [
      promo({ active: false }),
      promo({ expiresAtMillis: NOW - DAY }),
      promo({ maxUses: 1, usedCount: 1 }),
      promo({ minOrderTotal: 99999 }),
    ];
    for (const c of cases) {
      const r = evaluatePromo(c, 1500, NOW);
      assert.equal(r.ok, false);
      assert.equal(r.discount, 0);
      assert.ok(r.message, 'a rejection must carry a message the customer can read');
    }
  });
});
