import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { normaliseDriver, splitPrivate } from './drivers';

/* P4-05. The callable itself needs Auth and a database, but the two decisions
   that matter are pure and are pinned here:

     - what counts as a usable driver record, and
     - which fields are allowed onto a document EVERY SIGNED-IN USER CAN READ.

   The second is a privacy control, not a formatting preference. */

describe('normaliseDriver', () => {
  test('lowercases and trims the email — it is the account key', () => {
    // Auth treats addresses case-insensitively; storing the admin's typed
    // casing would make the document and the account disagree on lookup.
    assert.equal(normaliseDriver({ email: '  Devon@Example.COM ', name: 'Devon' }).email,
      'devon@example.com');
  });

  test('refuses a missing or malformed email', () => {
    // Without a real address the driver never receives the invite, and the
    // record is exactly the un-loginable ghost this function exists to end.
    for (const email of [undefined, '', '   ', 'devon', 'devon@', '@example.com', 'a b@c.com']) {
      assert.throws(() => normaliseDriver({ email, name: 'Devon' }), /email/i, String(email));
    }
  });

  test('refuses a missing name', () => {
    assert.throws(() => normaliseDriver({ email: 'd@e.com', name: '  ' }), /name/i);
    assert.throws(() => normaliseDriver({ email: 'd@e.com' }), /name/i);
  });

  test('uppercases the licence plate so the roster is searchable', () => {
    assert.equal(normaliseDriver({ email: 'd@e.com', name: 'D', licencePlate: 'pb 2341' })
      .licencePlate, 'PB 2341');
  });

  test('an unrecognised vehicle type falls back rather than blocking onboarding', () => {
    assert.equal(normaliseDriver({ email: 'd@e.com', name: 'D', vehicleType: 'Hovercraft' })
      .vehicleType, 'Car');
    assert.equal(normaliseDriver({ email: 'd@e.com', name: 'D', vehicleType: 'Van' })
      .vehicleType, 'Van');
  });

  test('optional fields become empty strings, never undefined', () => {
    // An `undefined` reaches Firestore as a field-delete or an error
    // depending on settings; neither is what the admin asked for.
    const d = normaliseDriver({ email: 'd@e.com', name: 'D' });
    for (const v of Object.values(d)) assert.equal(typeof v, 'string');
  });
});

describe('splitPrivate', () => {
  const driver = normaliseDriver({
    email: 'devon@example.com',
    name: 'Devon Campbell',
    phone: '876-555-0101',
    licencePlate: 'pb 2341',
    licenceNumber: 'JA-DL-99887'
  });

  test('the licence number NEVER lands on the public document', () => {
    // `drivers/{uid}` is readable by any signed-in user, because the
    // customer's tracking card shows the driver's name and vehicle. A licence
    // number there is readable by every customer who ever placed an order.
    const { publicDoc } = splitPrivate(driver);
    assert.equal('licenceNumber' in publicDoc, false);
    assert.equal(JSON.stringify(publicDoc).includes('JA-DL-99887'), false);
  });

  test('it lands in the private document instead', () => {
    assert.deepEqual(splitPrivate(driver).privateDoc, { licenceNumber: 'JA-DL-99887' });
  });

  test('no private document is written when there is no licence number', () => {
    // An empty placeholder would be indistinguishable from a real record that
    // failed to save.
    const d = normaliseDriver({ email: 'd@e.com', name: 'D' });
    assert.equal(splitPrivate(d).privateDoc, null);
  });

  test('the driver starts pending, offline, and with nothing earned', () => {
    // An admin-created driver is still an application. Approval stays a
    // separate, deliberate act — that is the invariant the whole rules file
    // was written to protect.
    const { publicDoc } = splitPrivate(driver);
    assert.equal(publicDoc.status, 'pending');
    assert.equal(publicDoc.isOnline, false);
    assert.equal(publicDoc.totalTrips, 0);
    assert.equal(publicDoc.todayEarnings, 0);
  });

  test('a new driver has no rating, not a perfect one', () => {
    // The old panel wrote rating 5.0 on creation, so an untested driver
    // displayed five stars to customers before their first delivery.
    const { publicDoc } = splitPrivate(driver);
    assert.equal(publicDoc.averageRating, 0);
    assert.equal(publicDoc.ratingCount, 0);
  });

  test('the public document keeps what the customer tracking card needs', () => {
    const { publicDoc } = splitPrivate(driver);
    assert.equal(publicDoc.name, 'Devon Campbell');
    assert.equal(publicDoc.licencePlate, 'PB 2341');
    assert.equal(publicDoc.vehicleType, 'Car');
  });
});
