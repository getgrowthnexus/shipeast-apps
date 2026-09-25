/**
 * Notification fan-out (P4-04).
 *
 * Audit §9. Both apps collect an `fcmToken` and **nothing has ever sent to
 * one**. The admin's "Log Notification" button writes a Firestore document
 * that only the customer app reads, so choosing "All Drivers" delivered to
 * nobody — the panel reported success for a message no driver could receive.
 *
 * The trigger that matters most is `onOrderCreated`. Today a driver only
 * learns an order exists while the app is foregrounded and toggled online
 * (`dashboard_screen.dart`). A driver with the phone in their pocket misses
 * every order. For a delivery product that is a fundamental gap, not polish.
 *
 * Everything decidable without a database lives in exported pure functions at
 * the top of this file and is pinned by `notifications.test.ts`. What a
 * customer is told their order is doing should not first be observable in
 * production.
 */

import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as OrderStatus from './orderStatus';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/** FCM refuses more than this many tokens in one multicast. */
export const MULTICAST_LIMIT = 500;

export interface PushContent {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Split into FCM-sized batches.
 *
 * Exported because the failure it prevents is invisible until the driver
 * roster crosses 500: a single oversized call is rejected wholesale, so
 * *every* driver silently stops receiving orders the day the 501st signs up.
 */
export function chunk<T>(items: readonly T[], size = MULTICAST_LIMIT): T[][] {
  if (size < 1) return [items.slice()];
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

/**
 * Unique, non-empty tokens.
 *
 * Duplicates are real: a customer document and a driver document can hold the
 * same token when one person uses both apps on one phone, and an admin
 * broadcast to `all` reads both collections. Without this they get the
 * notification twice.
 */
export function dedupeTokens(tokens: readonly unknown[]): string[] {
  const seen = new Set<string>();
  for (const t of tokens) {
    if (typeof t === 'string' && t.trim() !== '') seen.add(t);
  }
  return [...seen];
}

/** Collections an admin broadcast target reads tokens from. */
export function targetCollections(target: unknown): string[] {
  switch (String(target ?? 'all').toLowerCase()) {
    case 'drivers':   return ['drivers'];
    case 'customers': return ['users'];
    case 'all':       return ['users', 'drivers'];
    // Anything else is treated by the caller as a single uid (SCHEMA.md
    // §notifications allows one), NOT as a broadcast. Failing open here would
    // turn one hand-edited document into a push to the entire user base.
    default:          return [];
  }
}

// ──────────────────────────────────────────────────────────────────────────
// NT-2 / NT-3 / NT-4 — audience segments, scheduling, deep links
// ──────────────────────────────────────────────────────────────────────────

/** Customer segments the admin can target that are DERIVED from order history
 *  rather than a stored field. */
export const DERIVED_SEGMENTS = ['ordered', 'never_ordered', 'inactive'] as const;
export type DerivedSegment = (typeof DERIVED_SEGMENTS)[number];

/** No order in this many days makes a customer "inactive" (matches the admin
 *  panel's INACTIVE_DAYS_THRESHOLD). */
export const INACTIVE_DAYS = 60;

export type ParsedTarget =
  | { kind: 'collections'; collections: string[] }
  | { kind: 'tag'; tag: string }
  | { kind: 'segment'; segment: DerivedSegment }
  | { kind: 'uid'; uid: string };

/**
 * Turns the `target` string on a notification document into what it means.
 *
 * Pure and tested because this is the line between "message the whole user
 * base" and "message one person", and a wrong branch here is invisible until
 * the wrong people get a push.
 *
 *   'all' | 'customers' | 'drivers'  → a set of collections
 *   'tag:vip'                        → customers carrying that tag (CU-4)
 *   'ordered' | 'never_ordered' | 'inactive' → a derived customer segment
 *   anything else                    → a single uid
 */
export function parseTarget(target: unknown): ParsedTarget {
  const t = String(target ?? 'all').trim();
  const lower = t.toLowerCase();
  const cols = targetCollections(lower);
  if (cols.length > 0) return { kind: 'collections', collections: cols };
  if (lower.startsWith('tag:')) {
    return { kind: 'tag', tag: lower.slice(4) };
  }
  if ((DERIVED_SEGMENTS as readonly string[]).includes(lower)) {
    return { kind: 'segment', segment: lower as DerivedSegment };
  }
  // A raw document id keeps its original case — Firestore ids are case
  // sensitive and lowercasing one would look it up as a different document.
  return { kind: 'uid', uid: t };
}

/** The FCM `data` payload for a broadcast, including any NT-4 deep link.
 *  Every value must be a string — FCM rejects non-string data. */
export function broadcastData(
  notificationId: string,
  destType?: unknown,
  destValue?: unknown
): Record<string, string> {
  const out: Record<string, string> = {
    type: 'broadcast',
    notificationId: String(notificationId),
  };
  const dt = typeof destType === 'string' ? destType.trim() : '';
  const dv = typeof destValue === 'string' ? destValue.trim() : '';
  // 'order' | 'screen' | 'search' | 'url' — a value is required for all of them.
  if (dt && dv && ['order', 'screen', 'search', 'url'].includes(dt)) {
    out.destType = dt;
    out.destValue = dv;
    // An order deep link reuses the existing orderId routing on the client.
    if (dt === 'order') out.orderId = dv;
  }
  return out;
}

/** Whether a scheduled notification is due to go out now. `null`/absent means
 *  "send immediately" (an ordinary, unscheduled broadcast). */
export function isDue(scheduledForMillis: number | null | undefined, nowMillis: number): boolean {
  if (scheduledForMillis == null) return true;
  return scheduledForMillis <= nowMillis;
}

/**
 * What a driver sees when a new order lands.
 *
 * The money figure is the order's stored `total`, never a recomputed one —
 * a driver deciding whether to take a job must be shown the same number the
 * customer was charged.
 */
export function orderCreatedContent(
  orderId: string,
  order: Record<string, unknown>
): PushContent {
  const total = Number(order.total);
  const merchant = typeof order.merchantName === 'string' && order.merchantName
    ? order.merchantName
    : 'A merchant';
  const amount = Number.isFinite(total) && total > 0
    ? ` · J$${Math.round(total).toLocaleString('en-US')}`
    : '';
  return {
    title: 'New order available',
    body: `${merchant}${amount}`,
    data: { type: 'order_created', orderId }
  };
}

/**
 * What a driver sees when an order they may already have been told about is
 * *still* unclaimed and is being re-offered.
 *
 * Deliberately different wording from [orderCreatedContent] so a driver reads
 * this as "a job is going begging", not as a second brand-new order. Same money
 * rule: the figure is the order's stored `total`.
 */
export function orderReofferContent(
  orderId: string,
  order: Record<string, unknown>
): PushContent {
  const total = Number(order.total);
  const merchant = typeof order.merchantName === 'string' && order.merchantName
    ? order.merchantName
    : 'A merchant';
  const amount = Number.isFinite(total) && total > 0
    ? ` · J$${Math.round(total).toLocaleString('en-US')}`
    : '';
  return {
    title: 'Order still needs a driver',
    body: `${merchant}${amount}`,
    data: { type: 'order_reoffer', orderId }
  };
}

/**
 * How long an unclaimed order waits before its first re-offer, and the age past
 * which re-offering stops. `onOrderCreated` already covered the first two
 * minutes, so re-offering before then would double-send; past an hour a stuck
 * order is a dispatch problem for a human, not something to keep pinging.
 */
export const REOFFER_MIN_AGE_MS = 2 * 60 * 1000;
export const REOFFER_MAX_AGE_MS = 60 * 60 * 1000;

/**
 * Whether an order this old should be re-offered now.
 *
 * Pure and tested because the window is exactly the off-by-one that stays
 * invisible until an order is either spammed the instant it is created or never
 * re-offered at all.
 */
export function shouldReoffer(ageMs: number): boolean {
  return ageMs >= REOFFER_MIN_AGE_MS && ageMs <= REOFFER_MAX_AGE_MS;
}

/**
 * What a customer is told when their order moves.
 *
 * Returns null for statuses the customer should not be pinged about:
 * `pending` is the state the order is created in — the customer is looking at
 * the confirmation screen and does not need a push telling them what they
 * just did.
 */
export function statusChangeContent(
  orderId: string,
  status: string
): PushContent | null {
  if (!OrderStatus.isValid(status) || status === OrderStatus.PENDING) return null;
  const body: Record<string, string> = {
    [OrderStatus.CONFIRMED]:  'A driver has been assigned to your order.',
    [OrderStatus.PICKED_UP]:  'Your order has been picked up.',
    [OrderStatus.IN_TRANSIT]: 'Your driver is on the way.',
    [OrderStatus.DELIVERED]:  'Your order has been delivered. Enjoy!',
    [OrderStatus.CANCELLED]:  'Your order was cancelled.'
  };
  return {
    // The label comes from the shared lifecycle module, so the push and the
    // tracking screen cannot disagree about what the order is doing.
    title: OrderStatus.label(status),
    body: body[status] ?? 'Your order status changed.',
    data: { type: 'order_status', orderId, status }
  };
}

/** What an applicant is told when the admin rules on their application. */
export function driverStatusContent(status: string): PushContent | null {
  if (status === 'approved') {
    return {
      title: 'You\'re approved',
      body: 'Your ShipEast driver account is active. Go online to start receiving orders.',
      data: { type: 'driver_status', status }
    };
  }
  if (status === 'rejected') {
    return {
      title: 'Application not approved',
      body: 'Your driver application was not approved. Contact support for details.',
      data: { type: 'driver_status', status }
    };
  }
  // 'pending' and anything unrecognised: say nothing. A driver reverted to
  // pending by an admin correction should hear it from a person.
  return null;
}

/** Error codes meaning the token is dead and should be removed. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument'
]);

export function isDeadToken(code: unknown): boolean {
  return typeof code === 'string' && DEAD_TOKEN_CODES.has(code);
}

// ──────────────────────────────────────────────────────────────────────────
// Database-touching plumbing
// ──────────────────────────────────────────────────────────────────────────

const db = () => admin.firestore();

/**
 * At-most-once guard.
 *
 * Firestore triggers are **at-least-once**: a retry after a transient error
 * re-runs the handler with the same event. Without this a customer gets "Your
 * driver is on the way" three times. `create()` fails if the document exists,
 * which makes the check and the claim a single atomic operation — a plain
 * get-then-set would race two concurrent retries.
 *
 * Returns true if this caller owns the send.
 */
async function claim(eventKey: string): Promise<boolean> {
  try {
    await db().collection('pushLog').doc(eventKey).create({
      at: admin.firestore.FieldValue.serverTimestamp()
    });
    return true;
  } catch (e) {
    const code = (e as { code?: number | string }).code;
    // 6 / ALREADY_EXISTS — another delivery of this event already sent it.
    if (code === 6 || code === 'already-exists') return false;
    // Any other failure: send anyway. A duplicate notification is an
    // annoyance; a silently dropped one is the bug this file exists to fix.
    logger.warn('pushLog claim failed, sending unguarded', { eventKey, code });
    return true;
  }
}

/** Reads token + document path so a dead token can be cleared at its source. */
async function tokensFrom(
  collections: readonly string[]
): Promise<{ token: string; ref: FirebaseFirestore.DocumentReference }[]> {
  const out: { token: string; ref: FirebaseFirestore.DocumentReference }[] = [];
  for (const name of collections) {
    const snap = await db().collection(name).where('fcmToken', '!=', '').get();
    for (const doc of snap.docs) {
      const token = doc.data().fcmToken;
      if (typeof token === 'string' && token.trim() !== '') {
        out.push({ token, ref: doc.ref });
      }
    }
  }
  return out;
}

/** A single addressee, looked up in both collections. */
async function tokenForUid(uid: string) {
  if (!uid) return [];
  const out: { token: string; ref: FirebaseFirestore.DocumentReference }[] = [];
  for (const name of ['users', 'drivers']) {
    const snap = await db().collection(name).doc(uid).get();
    const token = snap.data()?.fcmToken;
    if (typeof token === 'string' && token.trim() !== '') {
      out.push({ token, ref: snap.ref });
    }
  }
  return out;
}

type Recipient = { token: string; ref: FirebaseFirestore.DocumentReference };

/** Recipients from a `users` query snapshot. */
function usersToRecipients(snap: FirebaseFirestore.QuerySnapshot): Recipient[] {
  const out: Recipient[] = [];
  snap.docs.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (typeof token === 'string' && token.trim() !== '') {
      out.push({ token, ref: doc.ref });
    }
  });
  return out;
}

/**
 * NT-2: resolves a notification's `target` to the devices it should reach.
 *
 * Tag segments are a single indexed query. The derived segments
 * (ordered / never_ordered / inactive) read the whole `orders` collection
 * once — fine for a manual admin broadcast on a small roster, and the
 * alternative (a maintained per-user counter) is a bigger surface to keep
 * correct.
 */
async function recipientsForTarget(target: unknown): Promise<Recipient[]> {
  const parsed = parseTarget(target);
  switch (parsed.kind) {
    case 'collections':
      return tokensFrom(parsed.collections);
    case 'tag': {
      const snap = await db().collection('users')
        .where('tags', 'array-contains', parsed.tag).get();
      return usersToRecipients(snap);
    }
    case 'segment':
      return derivedCustomerSegment(parsed.segment);
    case 'uid':
      return tokenForUid(parsed.uid);
  }
}

/** ordered / never_ordered / inactive, computed from the orders collection. */
async function derivedCustomerSegment(segment: DerivedSegment): Promise<Recipient[]> {
  const orderSnap = await db().collection('orders').get();
  const lastOrderAt = new Map<string, number>();
  orderSnap.docs.forEach((d) => {
    const o = d.data();
    const uid = o.customerId;
    if (typeof uid !== 'string' || !uid) return;
    const ts = o.createdAt as FirebaseFirestore.Timestamp | undefined;
    const at = ts?.toMillis?.() ?? 0;
    if (!lastOrderAt.has(uid) || at > (lastOrderAt.get(uid) ?? 0)) {
      lastOrderAt.set(uid, at);
    }
  });

  const usersSnap = await db().collection('users').get();
  const cutoff = Date.now() - INACTIVE_DAYS * 24 * 60 * 60 * 1000;
  const out: Recipient[] = [];
  usersSnap.docs.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (typeof token !== 'string' || token.trim() === '') return;
    const last = lastOrderAt.get(doc.id);
    const hasOrdered = last !== undefined;
    const include =
      segment === 'ordered' ? hasOrdered
      : segment === 'never_ordered' ? !hasOrdered
      : /* inactive */ hasOrdered && (last as number) < cutoff;
    if (include) out.push({ token, ref: doc.ref });
  });
  return out;
}

/** Online, approved drivers only — the people who can actually take the job. */
async function onlineDriverTokens() {
  const snap = await db().collection('drivers')
    .where('status', '==', 'approved')
    .where('isOnline', '==', true)
    .get();
  return snap.docs
    .map((d) => ({ token: d.data().fcmToken, ref: d.ref }))
    .filter((r): r is { token: string; ref: FirebaseFirestore.DocumentReference } =>
      typeof r.token === 'string' && r.token.trim() !== '');
}

/**
 * Sends, then clears every token FCM reports as dead.
 *
 * Pruning is not housekeeping. An uninstalled app leaves a token that fails on
 * every future send; left in place the roster fills with corpses, each one a
 * wasted call and a misleading "sent to 40 drivers" in the logs.
 */
async function sendTo(
  recipients: { token: string; ref: FirebaseFirestore.DocumentReference }[],
  content: PushContent
): Promise<{ delivered: number; failed: number }> {
  const owner = new Map<string, FirebaseFirestore.DocumentReference>();
  for (const r of recipients) if (!owner.has(r.token)) owner.set(r.token, r.ref);
  const tokens = dedupeTokens([...owner.keys()]);
  if (tokens.length === 0) return { delivered: 0, failed: 0 };

  let delivered = 0;
  let failed = 0;
  const dead: FirebaseFirestore.DocumentReference[] = [];

  for (const batch of chunk(tokens)) {
    const res = await admin.messaging().sendEachForMulticast({
      tokens: batch,
      notification: { title: content.title, body: content.body },
      data: content.data ?? {},
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } }
    });
    delivered += res.successCount;
    failed += res.failureCount;
    res.responses.forEach((r, i) => {
      if (!r.success && isDeadToken(r.error?.code)) {
        const ref = owner.get(batch[i]);
        if (ref) dead.push(ref);
      }
    });
  }

  if (dead.length > 0) {
    const writer = db().batch();
    for (const ref of dead) {
      writer.update(ref, { fcmToken: admin.firestore.FieldValue.delete() });
    }
    await writer.commit();
  }

  logger.info('push sent', {
    title: content.title,
    targets: tokens.length,
    delivered,
    failed,
    pruned: dead.length
  });
  return { delivered, failed };
}

// ──────────────────────────────────────────────────────────────────────────
// Triggers
// ──────────────────────────────────────────────────────────────────────────

/**
 * Sends one broadcast document and records the outcome on it.
 *
 * Shared by the create trigger (immediate sends) and the scheduler (NT-3).
 * The `pushLog` claim keyed on the document id makes it safe to call twice —
 * a trigger retry, or the scheduler racing a late trigger.
 */
async function dispatchBroadcast(
  id: string,
  data: FirebaseFirestore.DocumentData,
  ref: FirebaseFirestore.DocumentReference
): Promise<void> {
  if (!(await claim(`notification_${id}`))) return;

  const recipients = await recipientsForTarget(data.target);
  if (recipients.length === 0) {
    logger.warn('notification reached nobody', { target: data.target });
  }

  const { delivered, failed } = await sendTo(recipients, {
    title: String(data.title ?? 'ShipEast'),
    body: String(data.message ?? ''),
    // NT-4: the deep-link destination travels in the data payload.
    data: broadcastData(id, data.destType, data.destValue),
  });

  // Closes the loop between "logged" and "sent". `dispatchedAt` also tells the
  // scheduler this one is done (NT-3).
  await ref.set(
    {
      deliveredCount: delivered,
      failedCount: failed,
      dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Admin broadcast. This is the fix for the "All Drivers" dead end: the panel
 * writes the same document it always did, and it now actually goes somewhere.
 *
 * NT-3: a document with a future `scheduledFor` is left alone here — the
 * scheduler picks it up when it comes due.
 */
export const onNotificationCreated = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const scheduledFor = data.scheduledFor as FirebaseFirestore.Timestamp | undefined;
    if (!isDue(scheduledFor?.toMillis?.() ?? null, Date.now())) {
      logger.info('notification scheduled for later', {
        id: event.params.notificationId,
        scheduledFor: scheduledFor?.toDate?.()?.toISOString(),
      });
      return;
    }

    await dispatchBroadcast(event.params.notificationId, data, event.data!.ref);
  }
);

/**
 * NT-3: dispatches scheduled broadcasts that have come due.
 *
 * Runs every five minutes. A composite index on (scheduledFor asc) is enough;
 * the "not yet dispatched" filter is applied in memory because `dispatchedAt`
 * being absent is not a value Firestore can query on directly.
 */
export const dispatchScheduledNotifications = onSchedule('every 5 minutes', async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db().collection('notifications')
    .where('scheduledFor', '<=', now)
    .get();

  const due = snap.docs.filter((d) => d.data().dispatchedAt == null);
  if (due.length === 0) return;

  logger.info('dispatching scheduled notifications', { count: due.length });
  for (const doc of due) {
    await dispatchBroadcast(doc.id, doc.data(), doc.ref);
  }
});

/** The one that matters most — see the file header. */
export const onOrderCreated = onDocumentCreated('orders/{orderId}', async (event) => {
  const order = event.data?.data();
  if (!order) return;
  const orderId = event.params.orderId;
  if (!(await claim(`order_created_${orderId}`))) return;

  await sendTo(await onlineDriverTokens(), orderCreatedContent(orderId, order));
});

/**
 * Re-offers orders that are still unclaimed after the initial push.
 *
 * `onOrderCreated` fires exactly once. If every online driver was mid-delivery,
 * backgrounded, or simply ignored it, the order sits `pending` with no further
 * signal ever sent — the largest hole in dispatch, and the counterpart to the
 * driver app's client-side re-offer (which only helps a driver with the app
 * open). This sweeps the pending pool on a schedule and re-notifies online
 * drivers about jobs going begging, until one is claimed or the order ages past
 * [REOFFER_MAX_AGE_MS] (beyond which it is a human dispatch problem, not an
 * endless ping).
 *
 * The per-order, per-window [claim] keeps an at-least-once scheduler retry from
 * double-sending within the same window. The query reuses the pendingOrders
 * composite index (status + driverId); staleness is filtered in memory because
 * the pending pool is small and a range on `createdAt` would need its own index.
 */
export const reofferPendingOrders = onSchedule('every 2 minutes', async () => {
  const now = Date.now();

  const snap = await db().collection('orders')
    .where('status', '==', OrderStatus.PENDING)
    .where('driverId', '==', null)
    .get();

  const stale = snap.docs.filter((d) => {
    const created = d.data().createdAt as FirebaseFirestore.Timestamp | undefined;
    if (!created) return false;
    return shouldReoffer(now - created.toMillis());
  });
  if (stale.length === 0) return;

  // One roster lookup: every stale order is offered to the same online drivers.
  const recipients = await onlineDriverTokens();
  if (recipients.length === 0) {
    logger.info('reoffer: orders waiting but no driver online', {
      waiting: stale.length
    });
    return;
  }

  // A window aligned to the schedule interval, so each run claims a fresh key
  // per order (re-sending) while a retry inside the same run cannot.
  const window = Math.floor(now / REOFFER_MIN_AGE_MS);
  let reoffered = 0;
  for (const doc of stale) {
    if (!(await claim(`order_reoffer_${doc.id}_${window}`))) continue;
    await sendTo(recipients, orderReofferContent(doc.id, doc.data()));
    reoffered++;
  }

  logger.info('reoffer sweep', { waiting: stale.length, reoffered });
});

/**
 * Status changes: the customer always, plus the assigned driver on a
 * cancellation — a driver already en route needs to be told to stop, and
 * nothing told them before this.
 */
export const onOrderStatusChanged = onDocumentUpdated('orders/{orderId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const status = String(after.status ?? '');
  if (String(before.status ?? '') === status) return;

  const orderId = event.params.orderId;
  if (!(await claim(`order_status_${orderId}_${status}`))) return;

  const content = statusChangeContent(orderId, status);
  if (content) {
    // `customerId` is canonical (SCHEMA.md §orders, enforced by the create
    // rule). `userId` is only read as a fallback for pre-migration documents.
    const userId = after.customerId ?? after.userId;
    if (typeof userId === 'string' && userId) {
      const snap = await db().collection('users').doc(userId).get();
      const token = snap.data()?.fcmToken;
      if (typeof token === 'string' && token) {
        await sendTo([{ token, ref: snap.ref }], content);
      }
    }
  }

  if (status === OrderStatus.CANCELLED) {
    const driverId = after.driverId;
    if (typeof driverId === 'string' && driverId) {
      const snap = await db().collection('drivers').doc(driverId).get();
      const token = snap.data()?.fcmToken;
      if (typeof token === 'string' && token) {
        await sendTo([{ token, ref: snap.ref }], {
          title: 'Order cancelled',
          body: 'An order assigned to you was cancelled. Do not continue the delivery.',
          data: { type: 'order_cancelled', orderId }
        });
      }
    }
  }
});

/**
 * Approval and rejection.
 *
 * A driver applying today learns their fate by opening the app and guessing;
 * `pending_approval_screen.dart` polls, so the answer arrives only while they
 * happen to be watching.
 */
export const onDriverStatusChanged = onDocumentUpdated('drivers/{driverId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const status = String(after.status ?? '');
  if (String(before.status ?? '') === status) return;

  const content = driverStatusContent(status);
  if (!content) return;

  const token = after.fcmToken;
  if (typeof token !== 'string' || !token) return;
  if (!(await claim(`driver_status_${event.params.driverId}_${status}`))) return;

  await sendTo([{ token, ref: event.data!.after.ref }], content);
});
