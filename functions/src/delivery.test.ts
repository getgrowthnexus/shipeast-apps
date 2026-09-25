import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { commissionOn, DEFAULT_COMMISSION_RATE } from './delivery';

/* P3-04. The acceptance criterion is that a driver client modified to claim a
   J$999,999 order cannot inflate their earnings. That is enforced by reading
   the total from the order document rather than from the caller — a property
   of the callable, not of this function. What IS testable here is the
   arithmetic it applies, and the clamps that keep a bad rate from becoming a
   bad payout. */

describe('commissionOn', () => {
  test('pays the default 10% of the order total', () => {
    assert.equal(commissionOn(1500, DEFAULT_COMMISSION_RATE), 150);
  });

  test('rounds to whole JMD — money is stored as integers', () => {
    assert.equal(commissionOn(1505, 0.1), 151);
    assert.equal(commissionOn(1504, 0.1), 150);
  });

  test('honours a rate configured in settings/pricing', () => {
    assert.equal(commissionOn(1000, 0.15), 150);
  });

  test('a rate above 1 cannot pay out more than the order was worth', () => {
    // An admin typing 15 instead of 0.15 must not create a 15x payout.
    assert.equal(commissionOn(1000, 15), 1000);
  });

  test('a zero or negative rate pays nothing rather than throwing', () => {
    assert.equal(commissionOn(1000, 0), 0);
    assert.equal(commissionOn(1000, -0.1), 0);
  });

  test('a missing or nonsensical total pays nothing', () => {
    assert.equal(commissionOn(0, 0.1), 0);
    assert.equal(commissionOn(-500, 0.1), 0);
    assert.equal(commissionOn(NaN, 0.1), 0);
  });

  test('matches the driver app\'s display estimate for ordinary orders', () => {
    // DriverPay.commissionOn is `total * 0.10`, shown before a job is taken.
    // If these disagreed, the driver would see one figure on the job card and
    // be paid another.
    for (const total of [500, 1500, 2350, 9999]) {
      assert.equal(
        commissionOn(total, DEFAULT_COMMISSION_RATE),
        Math.round(total * 0.1)
      );
    }
  });
});
