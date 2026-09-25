#!/usr/bin/env node
/**
 * Seeds the Firebase Emulator Suite with enough data to look at.
 *
 * ## Why this is not tools/seed_staging.js
 *
 * That script (P1-09, still deferred) has to be careful: staging is a real
 * project with real quotas and a real chance of being confused for production.
 * This one targets a `demo-` project that exists only in memory and vanishes
 * when the emulator stops, so it can be blunt — wipe, write, done.
 *
 * ## The safety interlock
 *
 * It refuses to run unless FIRESTORE_EMULATOR_HOST and
 * FIREBASE_AUTH_EMULATOR_HOST are set, and unless the project id starts with
 * `demo-`. Both checks are cheap and the failure they prevent — seeding fake
 * merchants into production — is not recoverable by hand.
 *
 * ## Data shape
 *
 * Every document here follows SCHEMA.md exactly, including the parts the live
 * database gets wrong. That is the point: the preview should show the app as
 * the schema says it will be, not as the legacy data makes it look. If a
 * screen renders badly against this seed, the screen is wrong.
 *
 * Run through tools/dev-up.sh, or directly:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   node tools/seed_emulator.mjs
 */

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-shipeast';
const PASSWORD = 'shipeast123';

// ── Interlock ────────────────────────────────────────────────────────────
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error(
    'Refusing to run: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST\n' +
    'are not both set, so this would write to a real Firebase project.'
  );
  process.exit(1);
}
if (!PROJECT_ID.startsWith('demo-')) {
  console.error(`Refusing to run: project "${PROJECT_ID}" is not a demo- project.`);
  process.exit(1);
}

initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const auth = getAuth();

/** Minutes ago, as a Timestamp. Orders want a plausible spread of ages. */
const minsAgo = (m) => Timestamp.fromMillis(Date.now() - m * 60_000);

async function user({ uid, email, name, claims }) {
  await auth.createUser({ uid, email, password: PASSWORD, displayName: name })
    .catch((e) => { if (e.code !== 'auth/uid-already-exists') throw e; });
  if (claims) await auth.setCustomUserClaims(uid, claims);
  return uid;
}

async function main() {
  console.log(`Seeding ${PROJECT_ID} …`);

  // ── Accounts ───────────────────────────────────────────────────────────
  // The admin claim is what firestore.rules checks (isAdmin() reads
  // request.auth.token.admin). Setting it here is the only way the panel can
  // read anything — there is no admin bootstrap path in the app itself.
  await user({ uid: 'admin-1', email: 'admin@shipeast.test', name: 'Admin', claims: { admin: true } });
  await user({ uid: 'cust-marcia', email: 'marcia@example.com', name: 'Marcia Brown' });
  await user({ uid: 'cust-devon', email: 'devon@example.com', name: 'Devon Clarke' });
  await user({ uid: 'drv-delroy', email: 'delroy@example.com', name: 'Delroy Foster' });
  await user({ uid: 'drv-anita', email: 'anita@example.com', name: 'Anita Green' });

  const batch = db.batch();
  const set = (path, data) => batch.set(db.doc(path), data);

  // ── Pricing ────────────────────────────────────────────────────────────
  // Without this document the Packages feature stays switched off by design
  // (PackagePricing.fromSettings returns null rather than inventing a price).
  // Seeding it is what lets the preview show that screen at all.
  set('settings/pricing', {
    serviceFee: 150,
    driverCommissionRate: 0.1,
    packageBands: [
      { maxKg: 2, price: 600 },
      { maxKg: 5, price: 950 },
      { maxKg: 10, price: 1600 },
      { maxKg: null, price: 2400 },
    ],
    packageOveragePerKg: 120,
    packingSurcharge: 250,
    packageMaxWeightKg: 50,
    updatedAt: Timestamp.now(),
  });

  // ── Customers ──────────────────────────────────────────────────────────
  set('users/cust-marcia', {
    name: 'Marcia Brown', phone: '876 555 0110', email: 'marcia@example.com',
    createdAt: minsAgo(60 * 24 * 90),
  });
  set('users/cust-devon', {
    name: 'Devon Clarke', phone: '876 555 0188', email: 'devon@example.com',
    createdAt: minsAgo(60 * 24 * 12),
  });
  set('users/cust-marcia/addresses/addr-1', {
    label: 'Home', text: '14 Bay Street, Morant Bay', createdAt: minsAgo(60 * 24 * 80),
  });

  // ── Drivers ────────────────────────────────────────────────────────────
  // One approved and online, one still pending — the pending row is the only
  // way to see the approval flow in the panel.
  set('drivers/drv-delroy', {
    name: 'Delroy Foster', phone: '876 555 0134', email: 'delroy@example.com',
    vehicleType: 'Motorcycle', vehicleModel: 'Honda CG 125', licencePlate: 'AB1234',
    status: 'approved', isOnline: true, onDelivery: false,
    totalTrips: 128, totalRatings: 592, ratingCount: 124, averageRating: 4.77,
    createdAt: minsAgo(60 * 24 * 200),
  });
  set('drivers/drv-delroy/private/identity', { licenceNumber: 'JM-4471902' });
  set('drivers/drv-anita', {
    name: 'Anita Green', phone: '876 555 0177', email: 'anita@example.com',
    vehicleType: 'Car', vehicleModel: 'Toyota Corolla', licencePlate: 'CD5678',
    status: 'pending', isOnline: false, onDelivery: false,
    totalTrips: 0, totalRatings: 0, ratingCount: 0, averageRating: 0,
    createdAt: minsAgo(60 * 6),
  });

  // ── Merchants ──────────────────────────────────────────────────────────
  // Kingston coordinates are carried on each merchant so the driver app can
  // rank pending offers by how near the pickup is (nearest-first dispatch).
  const merchants = [
    { id: 'm-tastee', name: 'Tastee Patties', category: 'Food', emoji: '🥟',
      address: '108 Hope Road, Kingston 6', lat: 18.0179, lng: -76.7836,
      openingHours: '8am–9pm',
      deliveryTime: '20–30 min', deliveryFee: 350, promo: '🔥 Popular',
      menu: [
        { name: 'Beef Patty', price: 250, category: 'mains' },
        { name: 'Chicken Patty', price: 250, category: 'mains' },
        { name: 'Cheese Patty', price: 280, category: 'mains' },
        { name: 'Coco Bread', price: 120, category: 'sides' },
        { name: 'Box Drink', price: 100, category: 'drinks' },
      ] },
    { id: 'm-juici', name: 'Juici Beef', category: 'Food', emoji: '🍔',
      address: '22 Constant Spring Road, Kingston 10', lat: 18.0286, lng: -76.7975,
      openingHours: '9am–10pm',
      deliveryTime: '25–35 min', deliveryFee: 400,
      menu: [
        { name: 'Curry Goat with Rice', price: 890, category: 'mains' },
        { name: 'Jerk Chicken Meal', price: 780, category: 'mains' },
        { name: 'Festival (2)', price: 180, category: 'sides' },
        { name: 'Sky Juice', price: 150, category: 'drinks' },
      ] },
    { id: 'm-hilo', name: 'Hi-Lo Food Stores', category: 'Grocery', emoji: '🛒',
      address: 'Manor Park Plaza, Kingston 8', lat: 18.0512, lng: -76.7889,
      openingHours: '7am–8pm',
      deliveryTime: '40–60 min', deliveryFee: 500,
      menu: [
        { name: 'Rice 5kg', price: 1250, category: 'mains' },
        { name: 'Ackee (tin)', price: 690, category: 'mains' },
        { name: 'Milk 1L', price: 320, category: 'drinks' },
      ] },
    { id: 'm-fontana', name: 'Fontana Pharmacy', category: 'Pharmacy', emoji: '💊',
      address: 'Barbican Centre, Kingston 6', lat: 18.0244, lng: -76.7717,
      openingHours: '8am–7pm',
      deliveryTime: '30–45 min', deliveryFee: 450, isOpen: false,
      menu: [
        { name: 'Paracetamol 500mg', price: 420, category: 'mains' },
        { name: 'Vitamin C 1000mg', price: 980, category: 'mains' },
      ] },
  ];

  for (const m of merchants) {
    set(`merchants/${m.id}`, {
      name: m.name, category: m.category, address: m.address,
      lat: m.lat, lng: m.lng,
      openingHours: m.openingHours, deliveryTime: m.deliveryTime,
      deliveryFee: m.deliveryFee, isOpen: m.isOpen !== false,
      emoji: m.emoji, promo: m.promo || null,
      owner: null, phone: '876 555 0100', email: null, imageUrl: null,
      totalRatings: 0, ratingCount: 0, averageRating: 0,
      createdAt: minsAgo(60 * 24 * 120),
    });
    m.menu.forEach((item, i) => {
      set(`merchants/${m.id}/menuItems/item-${i + 1}`, {
        name: item.name, description: null, price: item.price,
        category: item.category, imageUrl: null, available: true,
      });
    });
  }

  // ── Promo codes ────────────────────────────────────────────────────────
  // usedCount is server-only in production; seeding it directly is fine here
  // because there is no server to disagree with yet.
  set('promoCodes/WELCOME10', {
    code: 'WELCOME10', discountType: 'percent', discountAmount: 10,
    minOrderTotal: 500, maxDiscount: 300, expiresAt: null,
    maxUses: 100, usedCount: 7, lastRedeemedAt: minsAgo(300),
    active: true, createdAt: minsAgo(60 * 24 * 30),
  });
  set('promoCodes/EXPIRED', {
    code: 'EXPIRED', discountType: 'fixed', discountAmount: 200,
    minOrderTotal: 0, maxDiscount: null, expiresAt: minsAgo(60 * 24 * 5),
    maxUses: 50, usedCount: 50, lastRedeemedAt: minsAgo(60 * 24 * 6),
    active: true, createdAt: minsAgo(60 * 24 * 60),
  });

  // ── Orders ─────────────────────────────────────────────────────────────
  // One per status, so every screen in all three apps has something to show:
  // pending is what the driver app offers, the driver-held ones are what its
  // active-job screen shows, delivered feeds history and earnings.
  const order = (id, o) => set(`orders/${id}`, {
    customerId: 'cust-marcia', customerName: 'Marcia Brown',
    customerPhone: '876 555 0110',
    merchantId: 'm-tastee', merchantName: 'Tastee Patties',
    merchantAddr: '108 Hope Road, Kingston 6',
    pickupLat: 18.0179, pickupLng: -76.7836,
    items: [{ name: 'Beef Patty', price: 250, quantity: 2 },
            { name: 'Coco Bread', price: 120, quantity: 2 }],
    subtotal: 740, deliveryFee: 350, serviceFee: 150, discount: 0,
    promoCode: null, total: 1240,
    paymentMethod: 'Cash on Delivery',
    deliveryAddress: '14 Bay Street, Morant Bay',
    type: 'food', package: null,
    driverId: null, driverName: null, driverPhone: null,
    rated: false, driverRating: null, merchantRating: null,
    comment: null, tags: [],
    ...o,
  });

  const claimed = {
    driverId: 'drv-delroy', driverName: 'Delroy Foster', driverPhone: '876 555 0134',
  };

  order('ord-pending', { status: 'pending', createdAt: minsAgo(4) });
  order('ord-pending-2', {
    status: 'pending', createdAt: minsAgo(11),
    customerId: 'cust-devon', customerName: 'Devon Clarke', customerPhone: '876 555 0188',
    merchantId: 'm-juici', merchantName: 'Juici Beef',
    merchantAddr: '22 Constant Spring Road, Kingston 10',
    pickupLat: 18.0286, pickupLng: -76.7975,
    items: [{ name: 'Curry Goat with Rice', price: 890, quantity: 1 }],
    subtotal: 890, deliveryFee: 400, total: 1440,
    deliveryAddress: '9 Shortwood Road, Kingston 8',
  });
  order('ord-confirmed', {
    status: 'confirmed', ...claimed,
    createdAt: minsAgo(25), acceptedAt: minsAgo(22),
  });
  order('ord-transit', {
    status: 'in_transit', ...claimed,
    createdAt: minsAgo(48), acceptedAt: minsAgo(44),
    pickedUpAt: minsAgo(38), inTransitAt: minsAgo(36),
  });
  order('ord-delivered', {
    status: 'delivered', ...claimed,
    createdAt: minsAgo(60 * 26), acceptedAt: minsAgo(60 * 26),
    pickedUpAt: minsAgo(60 * 25), inTransitAt: minsAgo(60 * 25),
    deliveredAt: minsAgo(60 * 24),
    driverCommission: 124, commissionRate: 0.1,
    rated: true, driverRating: 5, merchantRating: 4,
    comment: 'Reached quick and everything still hot.', tags: ['On time', 'Polite'],
    ratedAt: minsAgo(60 * 23),
  });
  order('ord-cancelled', {
    status: 'cancelled', createdAt: minsAgo(60 * 50),
    cancelledAt: minsAgo(60 * 49), cancelledBy: 'customer',
    cancellationReason: 'Ordered by mistake',
  });

  // A package order — no merchant, no goods, only work. This is the shape
  // P5-01 introduced, and the one most likely to render badly if a screen
  // still assumes every order has a merchant.
  set('orders/ord-package', {
    customerId: 'cust-devon', customerName: 'Devon Clarke',
    customerPhone: '876 555 0188',
    merchantId: null, merchantName: 'Package delivery',
    merchantAddr: '5 Trafalgar Road, Kingston 5',
    items: [], subtotal: 0,
    deliveryFee: 950, serviceFee: 400, discount: 0, promoCode: null, total: 1350,
    paymentMethod: 'Cash on Delivery',
    deliveryAddress: '77 Red Hills Road, Kingston 19',
    type: 'package',
    package: {
      itemCategory: 'Documents', pickupAddress: '5 Trafalgar Road, Kingston 5',
      weightKg: 3.5, weightBand: '2–5 kg', packingRequired: true,
      instructions: 'Ask for Sandra at the front desk.',
    },
    status: 'pending', driverId: null, driverName: null, driverPhone: null,
    rated: false, driverRating: null, merchantRating: null, comment: null, tags: [],
    createdAt: minsAgo(18),
  });

  // ── Overseas enquiries ─────────────────────────────────────────────────
  // One per handling state, so the panel's filter tabs and the customer's
  // own status list both have something to show.
  const inquiry = (id, o) => set(`overseasInquiries/${id}`, {
    customerId: 'cust-marcia', customerName: 'Marcia Brown',
    contactEmail: 'marcia@example.com', contactPhone: '+1 718 555 0134',
    originCountry: 'Brooklyn, USA',
    recipientName: 'Delroy Brown', recipientPhone: '876 555 0110',
    recipientAddress: '14 Bay Street, Morant Bay', recipientParish: 'St. Thomas',
    itemCategory: 'Food & groceries',
    itemDescription: '3 tins of ackee, 2 packs of rice',
    estimatedWeightKg: 6.5, notes: '', status: 'new',
    createdAt: minsAgo(90), updatedAt: minsAgo(90),
    ...o,
  });
  inquiry('inq-new', {});
  inquiry('inq-contacted', {
    status: 'contacted', itemCategory: 'Clothing & shoes',
    itemDescription: 'Winter coats and two pairs of school shoes',
    estimatedWeightKg: 12, recipientParish: 'Manchester',
    adminNote: 'Called — waiting on dimensions.',
    handledBy: 'admin-1', handledAt: minsAgo(120),
    createdAt: minsAgo(60 * 30), updatedAt: minsAgo(120),
  });
  inquiry('inq-quoted', {
    status: 'quoted', customerId: 'cust-devon', customerName: 'Devon Clarke',
    contactEmail: 'devon@example.com', originCountry: 'London, UK',
    itemCategory: 'Electronics', itemDescription: 'One laptop, boxed',
    estimatedWeightKg: 2.4, recipientParish: 'St. Andrew',
    recipientAddress: '9 Shortwood Road, Kingston 8',
    adminNote: 'Quoted £74 all-in. Awaiting reply.',
    handledBy: 'admin-1', handledAt: minsAgo(60 * 5),
    createdAt: minsAgo(60 * 60), updatedAt: minsAgo(60 * 5),
  });
  inquiry('inq-declined', {
    status: 'declined', itemCategory: 'Other',
    itemDescription: 'A car battery',
    estimatedWeightKg: 18, notes: 'For my uncle’s pickup.',
    adminNote: 'Prohibited — no carrier will take wet-cell batteries by air.',
    handledBy: 'admin-1', handledAt: minsAgo(60 * 70),
    createdAt: minsAgo(60 * 80), updatedAt: minsAgo(60 * 70),
  });

  // ── Notifications ──────────────────────────────────────────────────────
  set('notifications/notif-1', {
    title: 'Free delivery this weekend',
    message: 'No delivery fee on orders over J$1,500, Saturday and Sunday.',
    target: 'customers', sentBy: 'admin@shipeast.test',
    deliveredCount: 2, createdAt: minsAgo(60 * 20),
  });
  set('notifications/notif-2', {
    title: 'Reminder: update your vehicle details',
    message: 'Please confirm your licence plate is current before your next trip.',
    target: 'drivers', sentBy: 'admin@shipeast.test',
    deliveredCount: null, createdAt: minsAgo(60 * 3),
  });

  await batch.commit();

  console.log(`
Seeded.

  Admin panel   admin@shipeast.test  / ${PASSWORD}
  Customer      marcia@example.com   / ${PASSWORD}
                devon@example.com    / ${PASSWORD}
  Driver        delroy@example.com   / ${PASSWORD}   (approved, online)
                anita@example.com    / ${PASSWORD}   (pending approval)
`);
}

main().catch((e) => { console.error(e); process.exit(1); });
