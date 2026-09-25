import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  ALL, DELETE, orders, merchants, promoCodes, drivers, overseasInquiries,
  parseMoney, parseDate
} from './migrations.mjs';

/* Migration logic (P2-05).
 *
 * The migrations are pure functions precisely so this suite can exist without
 * a database. The plan's risk register rates "migration corrupts production
 * data" as Medium likelihood / SEVERE impact, and an untested migration script
 * is the mechanism by which that happens.
 *
 * The most important property here is idempotence, asserted for every
 * migration below by running it twice. A migration that is not idempotent
 * cannot be safely resumed after a failure, and the production run WILL be
 * interrupted eventually. */

/** Applies an update map to a document the way the runner does. */
function apply(data, updates) {
  if (!updates) return { ...data };
  const next = { ...data };
  for (const [k, v] of Object.entries(updates)) {
    if (v === DELETE) delete next[k];
    else next[k] = v;
  }
  return next;
}

/** Runs a migration to a fixed point, asserting it settles after one pass. */
function assertIdempotent(migration, input) {
  const first = migration.migrate(input);
  const afterFirst = apply(input, first);
  const second = migration.migrate(afterFirst);
  assert.equal(
    second, null,
    `${migration.collection} is not idempotent — a second pass still wants ` +
    `${JSON.stringify(second)}`
  );
  return afterFirst;
}

describe('idempotence — every migration must settle in one pass', () => {
  for (const migration of ALL) {
    test(`${migration.collection} settles on a legacy document`, () => {
      const legacy = {
        orders: { status: 'accepted', amount: '$1,500' },
        merchants: { fee: '$250', hours: '9am–9pm', open: true, rating: 4.5, ordersToday: 7 },
        promoCodes: { validUntil: '2026-08-01', discount: 20, discountType: 'percentage' },
        drivers: { licensePlate: 'ABC123', rating: 4.8, todayEarnings: 900 }
      }[migration.collection];
      assertIdempotent(migration, legacy);
    });

    test(`${migration.collection} is a no-op on an already-canonical document`, () => {
      const canonical = {
        orders: { status: 'confirmed', discount: 0, promoCode: null, type: 'food', total: 1500 },
        merchants: {
          deliveryFee: 250, openingHours: '9am–9pm', deliveryTime: '25–35 min',
          isOpen: true, averageRating: 4.5
        },
        promoCodes: {
          expiresAt: new Date('2026-08-01'), discountAmount: 20, discountType: 'percent',
          minOrderTotal: 0, maxDiscount: 500, maxUses: 100, usedCount: 0
        },
        drivers: { licencePlate: 'ABC123', averageRating: 4.8, vehicleModel: 'Toyota Corolla' },
        overseasInquiries: { status: 'reviewing' }
      }[migration.collection];
      assert.equal(migration.migrate(canonical), null,
        `${migration.collection} rewrites an already-correct document`);
    });
  }
});

describe('orders', () => {
  test('the dead accepted status becomes confirmed', () => {
    assert.equal(orders.migrate({ status: 'accepted' }).status, 'confirmed');
  });

  test('a live picked_up order is NOT rewritten', () => {
    // Rewriting a live order's status underneath a driver mid-delivery is the
    // exact class of bug this project exists to remove.
    const result = orders.migrate({
      status: 'picked_up', discount: 0, promoCode: null, type: 'food'
    });
    assert.equal(result, null);
  });

  test('backfills the fields that make an order reconcile', () => {
    const r = orders.migrate({ status: 'delivered' });
    assert.equal(r.discount, 0);
    assert.equal(r.promoCode, null);
    assert.equal(r.type, 'food');
  });

  test('does not clobber an existing discount', () => {
    const r = orders.migrate({ status: 'delivered', discount: 200, promoCode: 'X', type: 'food' });
    assert.equal(r, null);
  });

  test('parses a legacy amount string into an integer total', () => {
    const r = orders.migrate({ status: 'delivered', amount: 'J$1,500' });
    assert.equal(r.total, 1500);
    assert.equal(r.amount, DELETE);
  });

  test('never overwrites a numeric total with a parsed string', () => {
    const r = orders.migrate({
      status: 'delivered', amount: 'J$9,999', total: 1500,
      discount: 0, promoCode: null, type: 'food'
    });
    assert.equal(r, null, 'total must win over the legacy display string');
  });
});

describe('merchants — the revenue leak', () => {
  test("'$250' becomes the integer 250", () => {
    const r = merchants.migrate({ fee: '$250' });
    assert.equal(r.deliveryFee, 250);
    assert.equal(r.fee, DELETE);
  });

  test("'Free delivery' becomes 0, not null", () => {
    assert.equal(parseMoney('Free delivery'), 0);
  });

  test('hours becomes openingHours, not deliveryTime', () => {
    // These are two different things that were conflated because the admin
    // panel read `o.hours || o.deliveryTime`.
    const r = merchants.migrate({ hours: '9am–9pm' });
    assert.equal(r.openingHours, '9am–9pm');
    assert.notEqual(r.deliveryTime, '9am–9pm');
  });

  test('deliveryTime is defaulted AND flagged for review', () => {
    const r = merchants.migrate({ name: 'X' });
    assert.equal(r.deliveryTime, '25–35 min');
    assert.match(r._needsReview, /deliveryTime/);
  });

  test('open consolidates onto isOpen', () => {
    const r = merchants.migrate({ open: false });
    assert.equal(r.isOpen, false);
    assert.equal(r.open, DELETE);
  });

  test('the stale ordersToday counter is deleted, not zeroed', () => {
    assert.equal(merchants.migrate({ ordersToday: 7 }).ordersToday, DELETE);
  });

  test('an existing deliveryFee is never overwritten by the legacy fee', () => {
    const r = merchants.migrate({ fee: '$999', deliveryFee: 250 });
    assert.equal(r.deliveryFee, undefined, 'must not clobber the canonical value');
    assert.equal(r.fee, DELETE);
  });
});

describe('promoCodes', () => {
  test('a string validUntil becomes a real date', () => {
    const r = promoCodes.migrate({ validUntil: '2026-08-01' });
    assert.ok(r.expiresAt instanceof Date);
    assert.equal(r.validUntil, DELETE);
  });

  test('an unparseable expiry is flagged, not guessed', () => {
    const r = promoCodes.migrate({ validUntil: 'next tuesday' });
    assert.equal(r.expiresAt, null);
    assert.match(r._needsReview, /could not be parsed/);
  });

  test("'percentage' is normalised to 'percent'", () => {
    // The customer compared against 'percentage'; the admin wrote 'percent',
    // so the type never matched and every code fell to the fixed-amount branch.
    assert.equal(promoCodes.migrate({ discountType: 'percentage' }).discountType, 'percent');
  });

  test("'discount' is renamed to 'discountAmount'", () => {
    // This mismatch is why every promo code applied exactly J$0.
    const r = promoCodes.migrate({ discount: 20 });
    assert.equal(r.discountAmount, 20);
    assert.equal(r.discount, DELETE);
  });

  test('the usage cap fields are backfilled so the cap can be enforced', () => {
    const r = promoCodes.migrate({ code: 'X' });
    assert.equal(r.usedCount, 0);
    assert.equal(r.minOrderTotal, 0);
    assert.equal(r.maxUses, 0);
    assert.equal(r.maxDiscount, null);
  });

  test('an uncapped percentage code is FLAGGED, not silently capped', () => {
    // Capping it at a number nobody chose would quietly change what an
    // existing code is worth. A 100%-off code with no cap is a real
    // liability, so it goes in front of a human instead.
    const r = promoCodes.migrate({ code: 'X', discountType: 'percent', discountAmount: 20 });
    assert.equal(r.maxDiscount, null);
    assert.match(r._needsReview, /uncapped/);
  });

  test('an uncapped FIXED code is not flagged — it is self-limiting', () => {
    const r = promoCodes.migrate({ code: 'X', discountType: 'fixed', discountAmount: 200 });
    assert.equal(r.maxDiscount, null);
    assert.equal(r._needsReview, undefined);
  });

  test("a legacy 'percentage' code is flagged too, after normalisation", () => {
    const r = promoCodes.migrate({ code: 'X', discountType: 'percentage', discountAmount: 20 });
    assert.equal(r.discountType, 'percent');
    assert.match(r._needsReview, /uncapped/);
  });
});

describe('drivers', () => {
  test('American spelling is migrated to British', () => {
    const r = drivers.migrate({ licensePlate: 'ABC123' });
    assert.equal(r.licencePlate, 'ABC123');
    assert.equal(r.licensePlate, DELETE);
  });

  test('the derived todayEarnings counter is deleted', () => {
    assert.equal(drivers.migrate({ todayEarnings: 900 }).todayEarnings, DELETE);
  });

  test('a missing vehicle model is flagged, never invented', () => {
    const r = drivers.migrate({ name: 'D' });
    assert.equal(r.vehicleModel, null);
    assert.match(r._needsReview, /vehicleModel/);
  });

  test("the placeholder '—' counts as missing", () => {
    const r = drivers.migrate({ vehicleModel: '—' });
    assert.equal(r.vehicleModel, null);
  });

  test('the licence number moves to private/identity and leaves the parent', () => {
    // drivers/{uid} is readable by every signed-in user, so a licence number
    // there is readable by every customer who ever placed an order (P4-05).
    const r = drivers.migrate({ licenceNumber: ' JA-DL-99887 ' });
    assert.deepEqual(r._subdocs, [
      { path: ['private', 'identity'], data: { licenceNumber: 'JA-DL-99887' } }
    ]);
    assert.equal(r.licenceNumber, DELETE);
  });

  test('the copy and the delete are one unit of work', () => {
    // The runner queues both into a single batch. If they could land
    // separately, an interrupted run would leave the number nowhere.
    const r = drivers.migrate({ licenceNumber: 'JA-DL-1' });
    assert.ok(r._subdocs && r.licenceNumber === DELETE);
  });

  test('an empty licence number is dropped, not copied as a blank record', () => {
    // A blank private document is indistinguishable from a real one that
    // failed to save.
    for (const v of ['', '   ', '—']) {
      const r = drivers.migrate({ licenceNumber: v });
      assert.equal(r.licenceNumber, DELETE, JSON.stringify(v));
      assert.equal(r._subdocs, undefined, JSON.stringify(v));
    }
  });

  test('a driver already migrated is left alone', () => {
    // Idempotence: the second run finds no licenceNumber on the parent and
    // must not resurrect or blank the private copy.
    const r = drivers.migrate({ name: 'D', vehicleModel: 'Axio', licencePlate: 'PB1' });
    // No updates at all — the migration returns null rather than an empty
    // object, which is what stops the runner writing a no-op batch.
    assert.equal(r, null);
  });
});

describe('overseasInquiries (SD-4)', () => {
  test('the pre-SD-4 slugs map onto the new pipeline', () => {
    assert.equal(overseasInquiries.migrate({ status: 'contacted' }).status, 'reviewing');
    assert.equal(overseasInquiries.migrate({ status: 'quoted' }).status, 'quote_sent');
    assert.equal(overseasInquiries.migrate({ status: 'closed' }).status, 'completed');
  });

  test('a request already on the new vocabulary is left alone', () => {
    assert.equal(overseasInquiries.migrate({ status: 'shopping' }), null);
    assert.equal(overseasInquiries.migrate({ status: 'new' }), null);
    assert.equal(overseasInquiries.migrate({ status: 'declined' }), null);
  });

  test('a missing document body does not throw', () => {
    assert.equal(overseasInquiries.migrate(null), null);
    assert.equal(overseasInquiries.migrate(undefined), null);
    assert.equal(overseasInquiries.migrate({}), null);
  });
});

describe('parsers', () => {
  test('parseMoney handles the formats actually present in production', () => {
    assert.equal(parseMoney('$250'), 250);
    assert.equal(parseMoney('J$1,250'), 1250);
    assert.equal(parseMoney('150 delivery'), 150);
    assert.equal(parseMoney(250), 250);
    assert.equal(parseMoney(249.6), 250);
    assert.equal(parseMoney('Free delivery'), 0);
    assert.equal(parseMoney(''), null);
    assert.equal(parseMoney('—'), null);
    assert.equal(parseMoney(null), null);
  });

  test('parseDate returns null rather than an Invalid Date', () => {
    assert.ok(parseDate('2026-08-01') instanceof Date);
    assert.equal(parseDate('nonsense'), null);
    assert.equal(parseDate(''), null);
    assert.equal(parseDate(null), null);
  });

  test('parseDate passes an existing Timestamp straight through', () => {
    const d = new Date('2026-08-01');
    assert.equal(parseDate({ toDate: () => d }), d);
  });
});
