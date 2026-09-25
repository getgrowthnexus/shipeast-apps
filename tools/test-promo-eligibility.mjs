#!/usr/bin/env node
/* Promo discount eligibility (admin panel).
 *
 * `admin_panel/promo-eligibility.js` imports nothing, so plain Node can load
 * it — the same arrangement as overseas-status.js and order-status.js.
 *
 * Client checklist PR-5. Source of truth is `functions/src/eligibility.ts`;
 * `eligibility.test.ts` there covers `checkEligibility`'s condition logic in
 * full. This file's job is narrower: prove the admin copy of that same logic
 * agrees with it on the cases that matter, and — the part unique to this
 * file — that the create/edit form's own helpers (buildEligibility,
 * parseAreas, describeEligibility) do the right thing with what an admin
 * actually types into the picker.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  checkEligibility, discountBaseAmount, INELIGIBLE_MESSAGE,
  buildEligibility, parseAreas, describeEligibility
} from '../admin_panel/promo-eligibility.js';

const ctx = (over = {}) => ({
  customerId: 'cust-1',
  priorOrderCount: 3,
  merchantId: 'merch-1',
  merchantCategory: 'Food',
  deliveryArea: '14 Bay Street, Morant Bay, St. Thomas',
  orderKind: 'food',
  ...over,
});

describe('checkEligibility agrees with the functions-side engine', () => {
  test('no rules means open to everyone', () => {
    assert.equal(checkEligibility(null, ctx()).eligible, true);
    assert.equal(checkEligibility({}, ctx()).eligible, true);
  });

  test('customer scope: new / existing / selected', () => {
    assert.equal(checkEligibility({ customerScope: 'new' }, ctx({ priorOrderCount: 0 })).eligible, true);
    assert.equal(checkEligibility({ customerScope: 'new' }, ctx({ priorOrderCount: 1 })).eligible, false);
    assert.equal(checkEligibility({ customerScope: 'existing' }, ctx({ priorOrderCount: 0 })).eligible, false);
    assert.equal(checkEligibility({ customerScope: 'selected' }, ctx()).eligible, false, 'no ids admits nobody');
    assert.equal(checkEligibility({ customerScope: 'selected', customerIds: ['cust-1'] }, ctx()).eligible, true);
  });

  test('merchant / category / area scope', () => {
    assert.equal(checkEligibility({ merchantIds: ['merch-9'] }, ctx()).eligible, false);
    assert.equal(checkEligibility({ categories: ['Grocery'] }, ctx({ merchantCategory: 'Food' })).eligible, false);
    assert.equal(checkEligibility({ deliveryAreas: ['St. Thomas'] }, ctx()).eligible, true);
    assert.equal(checkEligibility({ deliveryAreas: ['Portland'] }, ctx()).eligible, false);
  });

  test('firstOrderOnly is distinct from customerScope "new"', () => {
    const elig = { customerScope: 'new', firstOrderOnly: true };
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 0 })).eligible, true);
    assert.equal(checkEligibility(elig, ctx({ priorOrderCount: 1 })).eligible, false);
  });

  test('order kinds, including shop_deliver', () => {
    assert.equal(checkEligibility({ orderKinds: ['shop_deliver'] }, ctx({ orderKind: 'food' })).eligible, false);
    assert.equal(checkEligibility({ orderKinds: ['shop_deliver'] }, ctx({ orderKind: 'shop_deliver' })).eligible, true);
  });

  test('every rejection reason has a customer-safe message', () => {
    const reasons = [
      'not_new_customer', 'not_existing_customer', 'customer_not_selected',
      'merchant_not_eligible', 'category_not_eligible', 'area_not_eligible',
      'not_first_order', 'order_kind_not_eligible'
    ];
    for (const r of reasons) assert.ok(INELIGIBLE_MESSAGE[r], r);
  });
});

describe('discountBaseAmount', () => {
  test('defaults to the subtotal; "deliveryFee" switches the base', () => {
    assert.equal(discountBaseAmount(null, 5000, 300), 5000);
    assert.equal(discountBaseAmount({ discountBase: 'deliveryFee' }, 5000, 300), 300);
  });
});

describe('parseAreas — the Delivery areas free-text field', () => {
  test('splits on commas, trims, drops empties', () => {
    assert.deepEqual(parseAreas('St. Thomas, Portland ,  '), ['St. Thomas', 'Portland']);
  });
  test('de-duplicates case-insensitively, keeping the first spelling typed', () => {
    assert.deepEqual(parseAreas('St. Thomas, st. thomas, ST. THOMAS'), ['St. Thomas']);
  });
  test('blank input is an empty array, not [""]', () => {
    assert.deepEqual(parseAreas(''), []);
    assert.deepEqual(parseAreas(null), []);
  });
});

describe('buildEligibility — reading the form back into a promo doc field', () => {
  const blankForm = () => ({
    customerScope: '', customerIds: [], merchantIds: [], categories: [],
    deliveryAreas: [], firstOrderOnly: false, discountBase: 'subtotal',
    orderKinds: ['food', 'package', 'shop_deliver'],
  });

  test('every control at its default builds null, not an empty object', () => {
    // A promo nobody scoped must read exactly like a pre-PR-5 code — that
    // only holds if this writes `null`, since `{}` and `null` are NOT the
    // same value to a merge:true Firestore write the second time around.
    assert.equal(buildEligibility(blankForm()), null);
  });

  test('customerScope "selected" only keeps customerIds when that scope is chosen', () => {
    const form = { ...blankForm(), customerScope: 'selected', customerIds: ['c1', 'c2'] };
    assert.deepEqual(buildEligibility(form), { customerScope: 'selected', customerIds: ['c1', 'c2'] });

    // Switching back to "All customers" without clearing a stale selection
    // must not leak customerIds onto an unscoped code.
    const form2 = { ...blankForm(), customerScope: '', customerIds: ['c1'] };
    assert.equal(buildEligibility(form2), null);
  });

  test('checking all three order kinds is "any kind" — orderKinds is omitted', () => {
    // Confirmed via a form that is otherwise scoped, so the result isn't the
    // all-defaults `null` case covered above.
    const form = { ...blankForm(), firstOrderOnly: true };
    assert.equal(buildEligibility(form).orderKinds, undefined);
  });

  test('unchecking one order kind narrows it', () => {
    const form = { ...blankForm(), orderKinds: ['food', 'package'] };
    assert.deepEqual(buildEligibility(form), { orderKinds: ['food', 'package'] });
  });

  test('every axis composes into one object when several are set', () => {
    const form = {
      customerScope: 'new', customerIds: [], merchantIds: ['m1'], categories: [],
      deliveryAreas: ['St. Thomas'], firstOrderOnly: true, discountBase: 'deliveryFee',
      orderKinds: ['food', 'package', 'shop_deliver'],
    };
    assert.deepEqual(buildEligibility(form), {
      customerScope: 'new', merchantIds: ['m1'], deliveryAreas: ['St. Thomas'],
      firstOrderOnly: true, discountBase: 'deliveryFee',
    });
  });
});

describe('describeEligibility — the promo table summary line', () => {
  test('an unrestricted code (null, or a malformed value) describes as nothing', () => {
    assert.equal(describeEligibility(null), null);
    assert.equal(describeEligibility(undefined), null);
    assert.equal(describeEligibility('not an object'), null);
  });

  test('names the restrictions that are actually set', () => {
    const s = describeEligibility({ customerScope: 'new', firstOrderOnly: true });
    assert.match(s, /new customers/);
    assert.match(s, /first order only/);
  });

  test('"selected" reports a count, not the raw id list', () => {
    const s = describeEligibility({ customerScope: 'selected', customerIds: ['a', 'b', 'c'] });
    assert.match(s, /3 selected customers/);
  });
});
