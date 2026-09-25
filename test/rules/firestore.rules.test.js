import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc, serverTimestamp
} from 'firebase/firestore';

/* Firestore security rules (P2-01).
 *
 * Every case here maps to a hole that was genuinely open before this file
 * existed. The plan calls this suite non-negotiable, and the reason is in its
 * own risk register: "rules deploy blocks a legitimate flow" is the
 * highest-likelihood launch failure. So this tests both directions — what must
 * be denied, and what must keep working. */

let testEnv;

const CUSTOMER = 'customer_uid';
const OTHER_CUSTOMER = 'other_customer_uid';
const DRIVER = 'driver_uid';
const OTHER_DRIVER = 'other_driver_uid';
const ADMIN = 'admin_uid';

const asCustomer = () => testEnv.authenticatedContext(CUSTOMER).firestore();
const asOtherCustomer = () => testEnv.authenticatedContext(OTHER_CUSTOMER).firestore();
const asDriver = () => testEnv.authenticatedContext(DRIVER).firestore();
const asOtherDriver = () => testEnv.authenticatedContext(OTHER_DRIVER).firestore();
const asAdmin = () => testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

/** A well-formed order that satisfies the arithmetic invariant. */
function order(overrides = {}) {
  return {
    customerId: CUSTOMER,
    customerName: 'Test Customer',
    merchantId: 'm1',
    merchantName: 'Island Jerk Palace',
    items: [{ name: 'Jerk Chicken', price: 1200, quantity: 1 }],
    subtotal: 1200,
    deliveryFee: 250,
    serviceFee: 50,
    discount: 0,
    total: 1500,
    paymentMethod: 'Cash on Delivery',
    deliveryAddress: '15 Harbour Street',
    status: 'pending',
    driverId: null,
    rated: false,
    ...overrides
  };
}

/** Seeds a document bypassing rules, for testing reads and updates. */
async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'shipeast-rules-test',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080
    }
  });
});

after(async () => { if (testEnv) await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

// ═══════════════════════════════════════════════════════════════════════════
describe('drivers — self-approval is the hole this closes', () => {
  test('a driver CANNOT approve themselves', async () => {
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'pending', totalTrips: 0 });
    await assertFails(
      updateDoc(doc(asDriver(), `drivers/${DRIVER}`), { status: 'approved' })
    );
  });

  test('a driver CANNOT inflate their own trips or rating', async () => {
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'approved', totalTrips: 0 });
    const db = asDriver();
    await assertFails(updateDoc(doc(db, `drivers/${DRIVER}`), { totalTrips: 9999 }));
    await assertFails(updateDoc(doc(db, `drivers/${DRIVER}`), { averageRating: 5 }));
    await assertFails(updateDoc(doc(db, `drivers/${DRIVER}`), { todayEarnings: 100000 }));
  });

  test('a driver CAN edit their own profile fields', async () => {
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'approved', totalTrips: 0 });
    await assertSucceeds(
      updateDoc(doc(asDriver(), `drivers/${DRIVER}`), {
        name: 'New Name', phone: '876-555-0000', isOnline: true,
        // onlineSince rides along on the presence toggle (SCHEMA.md §drivers).
        onlineSince: new Date()
      })
    );
  });

  test('a driver registers only as pending with zero trips', async () => {
    await assertSucceeds(
      setDoc(doc(asDriver(), `drivers/${DRIVER}`), {
        name: 'D', status: 'pending', totalTrips: 0
      })
    );
  });

  test('a driver CANNOT self-register as approved', async () => {
    await assertFails(
      setDoc(doc(asDriver(), `drivers/${OTHER_DRIVER}`), {
        name: 'D', status: 'approved', totalTrips: 0
      })
    );
    await assertFails(
      setDoc(doc(asDriver(), `drivers/${DRIVER}`), {
        name: 'D', status: 'approved', totalTrips: 0
      })
    );
  });

  test('an admin CAN approve a driver', async () => {
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'pending', totalTrips: 0 });
    await assertSucceeds(
      updateDoc(doc(asAdmin(), `drivers/${DRIVER}`), { status: 'approved' })
    );
  });

  test('a driver cannot write another driver document', async () => {
    await seed(`drivers/${OTHER_DRIVER}`, { name: 'O', status: 'approved', totalTrips: 0 });
    await assertFails(
      updateDoc(doc(asDriver(), `drivers/${OTHER_DRIVER}`), { name: 'Hacked' })
    );
  });

  test('driver PII in the private subcollection is not readable by others', async () => {
    await seed(`drivers/${DRIVER}/private/licence`, { licenceNumber: 'DL-123' });
    await assertFails(getDoc(doc(asCustomer(), `drivers/${DRIVER}/private/licence`)));
    await assertFails(getDoc(doc(asOtherDriver(), `drivers/${DRIVER}/private/licence`)));
    await assertSucceeds(getDoc(doc(asDriver(), `drivers/${DRIVER}/private/licence`)));
    await assertSucceeds(getDoc(doc(asAdmin(), `drivers/${DRIVER}/private/licence`)));
  });

  test('the customer CAN read the driver profile bringing their order', async () => {
    // Legitimate flow — the tracking screen shows name, rating and vehicle.
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'approved', totalTrips: 0 });
    await assertSucceeds(getDoc(doc(asCustomer(), `drivers/${DRIVER}`)));
  });

  test('an anonymous client cannot read drivers at all', async () => {
    await seed(`drivers/${DRIVER}`, { name: 'D', status: 'approved', totalTrips: 0 });
    await assertFails(getDoc(doc(asAnon(), `drivers/${DRIVER}`)));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('orders — money cannot be rewritten by a client', () => {
  test('a customer CANNOT modify the total after creation', async () => {
    await seed('orders/o1', order());
    await assertFails(updateDoc(doc(asCustomer(), 'orders/o1'), { total: 1 }));
  });

  test('a driver CANNOT modify the total of an order they hold', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertFails(updateDoc(doc(asDriver(), 'orders/o1'), { total: 999999 }));
  });

  test('an order whose total does not reconcile is rejected at creation', async () => {
    // subtotal 1200 + fee 250 + service 50 - discount 0 = 1500, not 100.
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({ total: 100 }))
    );
  });

  test('a discounted order must still reconcile', async () => {
    await assertSucceeds(
      addDoc(collection(asCustomer(), 'orders'),
        order({ discount: 200, total: 1300 }))
    );
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'),
        order({ discount: 200, total: 1500 }))
    );
  });

  test('a well-formed order is accepted', async () => {
    await assertSucceeds(addDoc(collection(asCustomer(), 'orders'), order()));
  });

  test('a customer cannot create an order as someone else', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({ customerId: OTHER_CUSTOMER }))
    );
  });

  test('a customer cannot create an order pre-claimed or already advanced', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({ driverId: DRIVER }))
    );
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({ status: 'delivered' }))
    );
  });

  test('a discounted order must still reconcile', async () => {
    /* P3-02. The whole point of recording `discount` is that the arithmetic
       closes: subtotal + deliveryFee + serviceFee - discount == total. */
    await assertSucceeds(
      addDoc(collection(asCustomer(), 'orders'), order({
        subtotal: 1200, deliveryFee: 250, serviceFee: 50,
        discount: 200, promoCode: 'SAVE200', total: 1300
      }))
    );
  });

  test('a customer cannot claim a discount the total does not reflect', async () => {
    // Claiming a discount without lowering the total, or lowering the total
    // without declaring a discount, both leave an order that does not add up.
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({
        subtotal: 1200, deliveryFee: 250, serviceFee: 50,
        discount: 200, total: 1500
      }))
    );
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({
        subtotal: 1200, deliveryFee: 250, serviceFee: 50,
        discount: 0, total: 900
      }))
    );
  });

  test('an order is deletable only by an admin (the data wipe), never a client', async () => {
    // A financial record: no lifecycle path deletes one, and no customer or
    // driver ever can. The sole exception is an admin running the Settings →
    // Danger Zone "Erase all data" wipe, which resets the whole system.
    await seed('orders/o1', order());
    await assertFails(deleteDoc(doc(asCustomer(), 'orders/o1')));
    await seed('orders/o2', order());
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'orders/o2')));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('orders — claiming and the lifecycle', () => {
  test('a driver CAN claim an unclaimed pending order', async () => {
    await seed('orders/o1', order());
    await assertSucceeds(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        driverId: DRIVER, driverName: 'D', driverPhone: '876',
        status: 'confirmed', acceptedAt: new Date()
      })
    );
  });

  test('a driver CANNOT claim an order another driver already holds', async () => {
    await seed('orders/o1', order({ driverId: OTHER_DRIVER, status: 'confirmed' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        driverId: DRIVER, driverName: 'D', status: 'confirmed'
      })
    );
  });

  test('a driver advances their order one legal step at a time', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertSucceeds(
      updateDoc(doc(asDriver(), 'orders/o1'), { status: 'picked_up' })
    );
  });

  test('a driver CANNOT skip the transit step', async () => {
    // picked_up -> delivered would make the customer's "On the Way" step
    // unreachable, which is the defect P1-05 fixed in the client.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'picked_up' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), { status: 'delivered' })
    );
  });

  /* Delivery finalisation used to be denied to the client entirely and handled
     by the confirmDelivery callable (P3-04). That function needs the Blaze
     plan and is not deployed, so the guarantee it enforced — a driver cannot
     pay itself more than the order's own total warrants — now lives in the
     rules (driverDelivering). The order's total is immutable, and the write is
     accepted only with a bounded commission, so the anti-fraud property is
     preserved without the backend. */
  test('a driver CAN complete their own in_transit order with a correct commission', async () => {
    // order() total is 1500; 10% is 150.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'in_transit' }));
    await assertSucceeds(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        status: 'delivered',
        deliveredAt: serverTimestamp(),
        driverCommission: 150,
        commissionRate: 0.1,
      })
    );
  });

  test('a driver CANNOT overpay themselves on delivery', async () => {
    // 10% of 1500 is 150; anything meaningfully above it is refused. This is
    // the exact exploit P3-04 closed, now closed by rules instead of a function.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'in_transit' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        status: 'delivered',
        deliveredAt: serverTimestamp(),
        driverCommission: 900,
        commissionRate: 0.1,
      })
    );
  });

  test('a driver CANNOT forge the delivery time', async () => {
    // deliveredAt must be the server clock, not a client-chosen instant.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'in_transit' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        status: 'delivered',
        deliveredAt: new Date('2020-01-01'),
        driverCommission: 150,
        commissionRate: 0.1,
      })
    );
  });

  test('a driver CANNOT alter the total while completing the order', async () => {
    // Bumping the total to lift the commission ceiling is blocked: total is not
    // in the touchable set, so the whole write is rejected.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'in_transit' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        status: 'delivered',
        deliveredAt: serverTimestamp(),
        driverCommission: 150,
        total: 100000,
      })
    );
  });

  test('a driver CANNOT complete an order they do not hold', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'in_transit' }));
    await assertFails(
      updateDoc(doc(asOtherDriver(), 'orders/o1'), {
        status: 'delivered',
        deliveredAt: serverTimestamp(),
        driverCommission: 150,
        commissionRate: 0.1,
      })
    );
  });

  test('a driver CAN still advance to in_transit', async () => {
    // The step before delivery must keep working — closing the delivered path
    // must not close the whole forward walk.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'picked_up' }));
    await assertSucceeds(
      updateDoc(doc(asDriver(), 'orders/o1'), { status: 'in_transit' })
    );
  });

  test('a driver CANNOT run the lifecycle backwards', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'delivered' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), { status: 'pending' })
    );
  });

  test('terminal orders are terminal, even for an admin', async () => {
    await seed('orders/o1', order({ status: 'delivered' }));
    await assertFails(updateDoc(doc(asAdmin(), 'orders/o1'), { status: 'pending' }));
    await seed('orders/o2', order({ status: 'cancelled' }));
    await assertFails(updateDoc(doc(asAdmin(), 'orders/o2'), { status: 'confirmed' }));
  });

  test('a driver cannot touch an order they do not hold', async () => {
    await seed('orders/o1', order({ driverId: OTHER_DRIVER, status: 'confirmed' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), { status: 'picked_up' })
    );
  });

  test('the holding driver CAN stream their live driverLoc onto the order', async () => {
    // The live position lives on the order (readable only by this order's
    // customer, driver and an admin) rather than on the world-readable driver
    // document. It must ride on the existing driver-update rule with no status
    // change and no touch of a protected field.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'picked_up' }));
    await assertSucceeds(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        driverLoc: { lat: 18.0179, lng: -76.8099, accuracy: 12, updatedAt: new Date() }
      })
    );
  });

  test('a driver CANNOT write driverLoc onto an order they do not hold', async () => {
    // The whole point: a driver could otherwise plant a position on any order.
    await seed('orders/o1', order({ driverId: OTHER_DRIVER, status: 'picked_up' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), {
        driverLoc: { lat: 18.0179, lng: -76.8099, accuracy: 12, updatedAt: new Date() }
      })
    );
  });

  test('an admin CAN assign a driver and confirm in one write', async () => {
    // The P1-07 black-hole fix must be permitted by rules.
    await seed('orders/o1', order());
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'orders/o1'), {
        driverId: DRIVER, driverName: 'D', status: 'confirmed'
      })
    );
  });

  test('an admin CAN unassign, returning the order to the pool', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'orders/o1'), { driverId: null, status: 'pending' })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('orders — customer cancellation and rating', () => {
  test('a customer CAN cancel their own pending order', async () => {
    await seed('orders/o1', order());
    await assertSucceeds(
      updateDoc(doc(asCustomer(), 'orders/o1'), {
        status: 'cancelled', cancelledAt: new Date(),
        cancelledBy: 'customer', cancellationReason: 'Changed my mind'
      })
    );
  });

  test('a customer CANNOT cancel once a driver has committed', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o1'), { status: 'cancelled' })
    );
  });

  test('a customer cannot smuggle a price change into a cancellation', async () => {
    await seed('orders/o1', order());
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o1'), { status: 'cancelled', total: 0 })
    );
  });

  test('a customer CANNOT write a rating directly', async () => {
    // P3-05 moved rating into the submitRating callable so the stars roll up
    // into the driver and merchant aggregates in one transaction. Leaving this
    // path open would let a customer mark an order `rated` with no roll-up —
    // losing the rating permanently — or re-rate and double-count it.
    await seed('orders/o1', order({ status: 'delivered' }));
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o1'), {
        rated: true, driverRating: 5, merchantRating: 4, comment: 'Great', tags: []
      })
    );
  });

  test('a customer cannot rate someone else\'s order either', async () => {
    await seed('orders/o1', order({ status: 'delivered' }));
    await assertFails(
      updateDoc(doc(asOtherCustomer(), 'orders/o1'), { rated: true, driverRating: 5 })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('orders — read isolation', () => {
  test('a customer CANNOT read another customer\'s order', async () => {
    await seed('orders/o1', order());
    await assertFails(getDoc(doc(asOtherCustomer(), 'orders/o1')));
  });

  test('a customer CAN read their own order', async () => {
    await seed('orders/o1', order());
    await assertSucceeds(getDoc(doc(asCustomer(), 'orders/o1')));
  });

  test('the assigned driver CAN read the order', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertSucceeds(getDoc(doc(asDriver(), 'orders/o1')));
  });

  test('an unassigned driver CANNOT read someone else\'s order', async () => {
    await seed('orders/o1', order({ driverId: OTHER_DRIVER, status: 'confirmed' }));
    await assertFails(getDoc(doc(asDriver(), 'orders/o1')));
  });

  test('an anonymous client can read nothing in orders', async () => {
    await seed('orders/o1', order());
    await assertFails(getDoc(doc(asAnon(), 'orders/o1')));
  });

  test('an admin CAN read any order', async () => {
    await seed('orders/o1', order());
    await assertSucceeds(getDoc(doc(asAdmin(), 'orders/o1')));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('users — profile and address isolation', () => {
  test('a customer CANNOT read another customer\'s profile', async () => {
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com' });
    await assertFails(getDoc(doc(asOtherCustomer(), `users/${CUSTOMER}`)));
  });

  test('a customer CANNOT read another customer\'s address', async () => {
    await seed(`users/${CUSTOMER}/addresses/a1`, { label: 'Home', text: '15 Harbour St' });
    await assertFails(getDoc(doc(asOtherCustomer(), `users/${CUSTOMER}/addresses/a1`)));
  });

  test('a customer CAN manage their own addresses', async () => {
    await assertSucceeds(
      setDoc(doc(asCustomer(), `users/${CUSTOMER}/addresses/a1`),
        { label: 'Home', text: '15 Harbour St' })
    );
  });

  test('a customer cannot disable or re-enable their own account', async () => {
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com', disabled: true });
    await assertFails(
      updateDoc(doc(asCustomer(), `users/${CUSTOMER}`), { disabled: false })
    );
  });

  test('an admin CAN disable an account but not rewrite the profile', async () => {
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com' });
    await assertSucceeds(
      updateDoc(doc(asAdmin(), `users/${CUSTOMER}`), { disabled: true })
    );
    await assertFails(
      updateDoc(doc(asAdmin(), `users/${CUSTOMER}`), { name: 'Changed' })
    );
  });

  test('CU-4: an admin CAN set segment tags; a customer cannot tag themselves', async () => {
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com' });
    await assertSucceeds(
      updateDoc(doc(asAdmin(), `users/${CUSTOMER}`), {
        tags: ['vip', 'diaspora'],
        tagsUpdatedAt: new Date(),
        tagsUpdatedBy: ADMIN
      })
    );
    await assertFails(
      updateDoc(doc(asCustomer(), `users/${CUSTOMER}`), { tags: ['vip'] })
    );
    // Still can't smuggle a profile edit alongside the tags.
    await assertFails(
      updateDoc(doc(asAdmin(), `users/${CUSTOMER}`), { tags: ['vip'], email: 'x@y.com' })
    );
  });

  test('an admin CAN read a customer profile (Customers page)', async () => {
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com' });
    await assertSucceeds(getDoc(doc(asAdmin(), `users/${CUSTOMER}`)));
  });

  test('an admin CAN delete a customer and their addresses (the data wipe)', async () => {
    // Delete exists for the Settings → Danger Zone "Erase all data" wipe. A
    // saved address is a subcollection doc and must be swept explicitly — the
    // parent delete does not cascade — so both need the admin-delete clause.
    await seed(`users/${CUSTOMER}`, { name: 'C', email: 'c@x.com' });
    await seed(`users/${CUSTOMER}/addresses/a1`, { label: 'Home', text: '15 Harbour St' });
    await assertFails(deleteDoc(doc(asOtherCustomer(), `users/${CUSTOMER}`)));
    await assertSucceeds(deleteDoc(doc(asAdmin(), `users/${CUSTOMER}/addresses/a1`)));
    await assertSucceeds(deleteDoc(doc(asAdmin(), `users/${CUSTOMER}`)));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('merchants, promos, notifications', () => {
  test('anyone can read merchants; nobody but an admin can write them', async () => {
    await seed('merchants/m1', { name: 'Island Jerk Palace', isOpen: true });
    await assertSucceeds(getDoc(doc(asAnon(), 'merchants/m1')));
    await assertFails(setDoc(doc(asCustomer(), 'merchants/m2'), { name: 'Fake' }));
    await assertSucceeds(setDoc(doc(asAdmin(), 'merchants/m2'), { name: 'Real' }));
  });

  test('the client seeder can never come back', async () => {
    // audit §13 — the customer app wrote 15 demo merchants into production.
    await assertFails(setDoc(doc(asCustomer(), 'merchants/seeded'), { name: 'Demo' }));
    await assertFails(
      setDoc(doc(asCustomer(), 'merchants/m1/menuItems/i1'), { name: 'Item', price: 100 })
    );
  });

  test('a customer can read a promo code but not create or redeem one', async () => {
    await seed('promoCodes/SAVE20', {
      code: 'SAVE20', discountType: 'percent', discountAmount: 20,
      usedCount: 0, maxUses: 100, active: true
    });
    await assertSucceeds(getDoc(doc(asCustomer(), 'promoCodes/SAVE20')));
    await assertFails(
      updateDoc(doc(asCustomer(), 'promoCodes/SAVE20'), { usedCount: 0, maxUses: 99999 })
    );
    await assertFails(
      setDoc(doc(asCustomer(), 'promoCodes/FREE100'), {
        discountType: 'percent', discountAmount: 100, active: true
      })
    );
  });

  test('a customer cannot broadcast a notification', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'notifications'), {
        title: 'Spam', message: 'x', target: 'all'
      })
    );
  });

  test('a client cannot rewrite the commission rate', async () => {
    // settings/pricing feeds server-side payout (P3-04).
    await seed('settings/pricing', { serviceFee: 50, driverCommissionRate: 0.1 });
    await assertFails(
      updateDoc(doc(asDriver(), 'settings/pricing'), { driverCommissionRate: 0.9 })
    );
    await assertSucceeds(getDoc(doc(asAnon(), 'settings/pricing')));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('default deny', () => {
  test('an unmatched collection is denied even to an admin', async () => {
    await assertFails(setDoc(doc(asAdmin(), 'somethingNew/x'), { a: 1 }));
    await assertFails(getDoc(doc(asCustomer(), 'somethingNew/x')));
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('admin unassignment is a reversal, not a lifecycle transition', () => {
  test('an admin CANNOT push an order backwards without unassigning', async () => {
    // The narrow exception must not become a general backwards door.
    await seed('orders/o1', order({ driverId: DRIVER, status: 'picked_up' }));
    await assertFails(
      updateDoc(doc(asAdmin(), 'orders/o1'), { status: 'confirmed' })
    );
  });

  test('unassignment must actually clear the driver', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertFails(
      updateDoc(doc(asAdmin(), 'orders/o1'), { status: 'pending' })
    );
  });

  test('unassignment can only return an order to pending', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'picked_up' }));
    await assertFails(
      updateDoc(doc(asAdmin(), 'orders/o1'), { driverId: null, status: 'confirmed' })
    );
  });

  test('a driver cannot unassign themselves off a held order', async () => {
    await seed('orders/o1', order({ driverId: DRIVER, status: 'confirmed' }));
    await assertFails(
      updateDoc(doc(asDriver(), 'orders/o1'), { driverId: null, status: 'pending' })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
describe('Phase 4 — push plumbing and driver PII', () => {
  test('pushLog is invisible and unwritable to every client, admin included', async () => {
    // The fan-out functions (P4-04) claim an event key here to make an
    // at-least-once trigger send at most once. A client that could forge a key
    // would silently suppress a real notification — a customer never told
    // their order was cancelled. The Admin SDK bypasses rules, so denying
    // everything costs the server nothing.
    await assertFails(setDoc(doc(asAdmin(), 'pushLog/order_created_o1'), { at: 1 }));
    await assertFails(setDoc(doc(asDriver(), 'pushLog/order_created_o1'), { at: 1 }));
    await assertFails(getDoc(doc(asAdmin(), 'pushLog/order_created_o1')));
    await assertFails(getDoc(doc(asCustomer(), 'pushLog/order_created_o1')));
  });

  test('a customer can store and clear their own push token', async () => {
    // P4-03 writes it on sign-in and deletes it on sign-out. If the delete
    // failed, the next person to use a shared phone would receive the previous
    // customer's order updates.
    await seed(`users/${CUSTOMER}`, { name: 'Ann', email: 'a@e.com' });
    await assertSucceeds(
      updateDoc(doc(asCustomer(), `users/${CUSTOMER}`), { fcmToken: 'tok-1' })
    );
    await assertSucceeds(
      updateDoc(doc(asCustomer(), `users/${CUSTOMER}`), { fcmToken: null })
    );
  });

  test('a customer cannot write a push token onto someone else', async () => {
    // Otherwise anyone could redirect another customer's order notifications
    // to their own device.
    await seed(`users/${OTHER_CUSTOMER}`, { name: 'Bea', email: 'b@e.com' });
    await assertFails(
      updateDoc(doc(asCustomer(), `users/${OTHER_CUSTOMER}`), { fcmToken: 'tok-mine' })
    );
  });

  test('a driver licence number is readable by its owner and an admin only', async () => {
    // P4-05 moved it off drivers/{uid}, which every signed-in user can read
    // because the customer's tracking card shows the driver's name and
    // vehicle. On the parent document, every customer who had ever placed an
    // order could read every driver's licence.
    await seed(`drivers/${DRIVER}/private/identity`, { licenceNumber: 'JA-DL-99887' });
    await assertSucceeds(getDoc(doc(asDriver(), `drivers/${DRIVER}/private/identity`)));
    await assertSucceeds(getDoc(doc(asAdmin(), `drivers/${DRIVER}/private/identity`)));
    await assertFails(getDoc(doc(asCustomer(), `drivers/${DRIVER}/private/identity`)));
    await assertFails(getDoc(doc(asOtherDriver(), `drivers/${DRIVER}/private/identity`)));
    await assertFails(getDoc(doc(asAnon(), `drivers/${DRIVER}/private/identity`)));
  });

  test('an admin can record a licence number without touching the public doc', async () => {
    await assertSucceeds(
      setDoc(doc(asAdmin(), `drivers/${DRIVER}/private/identity`), { licenceNumber: 'JA-DL-1' })
    );
  });
});

describe('Phase 5 — order types, cancellation and overseas enquiries', () => {
  test('a customer CAN place a package order', async () => {
    // P5-01. A package job has no merchant and no goods: subtotal is 0, the
    // weight-band rate is the delivery fee and packing is the service fee.
    // It still has to satisfy the same arithmetic invariant.
    await assertSucceeds(
      addDoc(collection(asCustomer(), 'orders'), order({
        type: 'package',
        merchantId: null,
        merchantName: 'Package pickup',
        merchantAddr: '12 Bay Street',
        items: [],
        subtotal: 0,
        deliveryFee: 900,
        serviceFee: 350,
        discount: 0,
        total: 1250
      }))
    );
  });

  test('an order with no type is still accepted', async () => {
    // Every order written before Phase 5 has no `type`, and the rule defaults
    // rather than requires so the field can be adopted without a flag day.
    await assertSucceeds(addDoc(collection(asCustomer(), 'orders'), order()));
  });

  test('an invented order type is rejected', async () => {
    // 'overseas' is the interesting case: that feature is an enquiry an admin
    // prices by hand, never an order, so an order of that type could only come
    // from a client that made it up.
    for (const type of ['overseas', 'freight', '', 'FOOD']) {
      await assertFails(
        addDoc(collection(asCustomer(), 'orders'), order({ type }))
      );
    }
  });

  test('a package order still cannot lie about its total', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'orders'), order({
        type: 'package',
        items: [],
        subtotal: 0,
        deliveryFee: 900,
        serviceFee: 350,
        total: 100
      }))
    );
  });

  test('a customer CAN cancel their own pending order', async () => {
    // P5-03, audit §15. The app has always rendered a "Cancelled" tab that no
    // customer action could produce. This is the write behind that action.
    await seed('orders/o-cancel', order());
    await assertSucceeds(
      updateDoc(doc(asCustomer(), 'orders/o-cancel'), {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelledBy: 'customer',
        cancellationReason: 'Ordered by mistake'
      })
    );
  });

  test('a customer cannot cancel once a driver has accepted', async () => {
    // The driver is already riding to the merchant. Cancelling out from under
    // them is an operational decision, not a customer one.
    await seed('orders/o-claimed', order({ status: 'confirmed', driverId: DRIVER }));
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o-claimed'), {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelledBy: 'customer',
        cancellationReason: 'Changed my mind'
      })
    );
  });

  test('a customer cannot cancel somebody else’s order', async () => {
    await seed('orders/o-theirs', order({ customerId: OTHER_CUSTOMER }));
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o-theirs'), {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelledBy: 'customer',
        cancellationReason: 'Nope'
      })
    );
  });

  test('cancelling cannot smuggle a price change through with it', async () => {
    // `hasOnly` is what stops this. Without it, cancellation would be a
    // customer-writable path onto the money fields.
    await seed('orders/o-smuggle', order());
    await assertFails(
      updateDoc(doc(asCustomer(), 'orders/o-smuggle'), {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelledBy: 'customer',
        cancellationReason: 'Too slow',
        total: 1
      })
    );
  });

  // ── Overseas enquiries ──
  // The customer owns the request; the admin owns the handling. Neither can
  // write the other's half, and the enquiry carries a household's name, phone
  // and street address in Jamaica — so the read rule matters as much as the
  // write rules.

  const inquiry = (over = {}) => ({
    customerId: CUSTOMER,
    customerName: 'Marcia Brown',
    contactEmail: 'marcia@example.com',
    contactPhone: '+1 718 555 0134',
    originCountry: 'Brooklyn, USA',
    recipientName: 'Delroy Brown',
    recipientPhone: '876 555 0110',
    recipientAddress: '14 Bay Street, Morant Bay',
    recipientParish: 'St. Thomas',
    itemCategory: 'Food & groceries',
    itemDescription: '3 tins of ackee, 2 packs of rice',
    estimatedWeightKg: 4.5,
    notes: '',
    status: 'new',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...over
  });

  test('a signed-in customer CAN file an overseas enquiry', async () => {
    await assertSucceeds(
      addDoc(collection(asCustomer(), 'overseasInquiries'), inquiry())
    );
  });

  test('an enquiry cannot be attributed to somebody else', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'overseasInquiries'),
        inquiry({ customerId: OTHER_CUSTOMER }))
    );
  });

  test('an anonymous visitor cannot file an enquiry', async () => {
    await assertFails(
      addDoc(collection(asAnon(), 'overseasInquiries'),
        inquiry({ customerId: null }))
    );
  });

  test('an enquiry cannot be created already handled', async () => {
    // Both of these would let a modified client file a request that never
    // enters the queue it exists to enter.
    await assertFails(
      addDoc(collection(asCustomer(), 'overseasInquiries'),
        inquiry({ status: 'completed' }))
    );
    await assertFails(
      addDoc(collection(asCustomer(), 'overseasInquiries'),
        inquiry({ adminNote: 'already dealt with' }))
    );
  });

  test('an enquiry cannot carry unbounded text', async () => {
    await assertFails(
      addDoc(collection(asCustomer(), 'overseasInquiries'),
        inquiry({ itemDescription: 'x'.repeat(1001) }))
    );
    await assertFails(
      addDoc(collection(asCustomer(), 'overseasInquiries'),
        inquiry({ notes: 'x'.repeat(1001) }))
    );
  });

  test('only the author and an admin can read an enquiry', async () => {
    await seed('overseasInquiries/i1', inquiry());
    await assertSucceeds(getDoc(doc(asCustomer(), 'overseasInquiries/i1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'overseasInquiries/i1')));
    // Another customer's household address and phone number.
    await assertFails(getDoc(doc(asOtherCustomer(), 'overseasInquiries/i1')));
    await assertFails(getDoc(doc(asAnon(), 'overseasInquiries/i1')));
  });

  test('an admin CAN work the enquiry through its statuses', async () => {
    await seed('overseasInquiries/i2', inquiry());
    // SD-4 vocabulary: New → Reviewing → Quote Sent → … → Completed.
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i2'), {
        status: 'reviewing',
        adminNote: 'Called, quoting for a 5kg box',
        handledBy: ADMIN,
        handledAt: new Date(),
        updatedAt: new Date()
      })
    );
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i2'), {
        status: 'out_for_delivery',
        updatedAt: new Date()
      })
    );
    // SD-7: the quote sub-fields are additive and admin-only.
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i2'), {
        quoteItemsCost: 8000, quoteServiceFee: 1500, quoteDeliveryFee: 900,
        quoteTotal: 10400, quotePaymentStatus: 'pending',
        quotedBy: ADMIN, quotedAt: new Date(), updatedAt: new Date()
      })
    );
    // A customer still cannot touch them.
    await assertFails(
      updateDoc(doc(asCustomer(), 'overseasInquiries/i2'), { quoteTotal: 0 })
    );
  });

  test('an admin cannot rewrite what the customer said they are sending', async () => {
    // The customer's own description is what the carrier and customs are
    // quoted against. A wrong one is a new enquiry, not an edit.
    await seed('overseasInquiries/i3', inquiry());
    await assertFails(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i3'), {
        status: 'quote_sent',
        itemDescription: 'one envelope'
      })
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i3'), {
        recipientAddress: 'somewhere else'
      })
    );
  });

  test('an admin cannot invent a status', async () => {
    await seed('overseasInquiries/i4', inquiry());
    await assertFails(
      updateDoc(doc(asAdmin(), 'overseasInquiries/i4'), { status: 'shipped' })
    );
  });

  test('the customer cannot handle their own enquiry', async () => {
    // Otherwise "quoted" would mean nothing: the person waiting on a price
    // could set it themselves.
    await seed('overseasInquiries/i5', inquiry());
    await assertFails(
      updateDoc(doc(asCustomer(), 'overseasInquiries/i5'), { status: 'quote_sent' })
    );
    await assertFails(
      updateDoc(doc(asCustomer(), 'overseasInquiries/i5'), { adminNote: 'ship it free' })
    );
  });

  test('an enquiry is deletable only by an admin (the data wipe), never a client', async () => {
    // It is the only record of what somebody asked us to ship, including the
    // ones we refused and the reason we gave — so no client ever deletes one.
    // An admin may, but only as part of the Danger Zone "Erase all data" wipe.
    await seed('overseasInquiries/i6', inquiry());
    await assertFails(deleteDoc(doc(asCustomer(), 'overseasInquiries/i6')));
    await seed('overseasInquiries/i7', inquiry());
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'overseasInquiries/i7')));
  });
});
