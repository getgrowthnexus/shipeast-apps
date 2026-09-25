import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  chunk,
  dedupeTokens,
  targetCollections,
  parseTarget,
  broadcastData,
  isDue,
  DERIVED_SEGMENTS,
  orderCreatedContent,
  orderReofferContent,
  shouldReoffer,
  statusChangeContent,
  driverStatusContent,
  isDeadToken,
  MULTICAST_LIMIT,
  REOFFER_MIN_AGE_MS,
  REOFFER_MAX_AGE_MS
} from './notifications';
import * as OrderStatus from './orderStatus';

/* P4-04. Everything below is decidable without a database, and every one of
   these is a decision that is invisible in production until it is wrong: a
   broadcast that reaches the wrong audience, a batch FCM rejects wholesale, a
   customer told their order was delivered when it was cancelled. */

describe('chunk', () => {
  test('splits at the FCM multicast limit', () => {
    // The failure this prevents is invisible until the roster crosses 500,
    // and then EVERY driver stops receiving orders at once.
    const tokens = Array.from({ length: 1001 }, (_, i) => `t${i}`);
    const batches = chunk(tokens);
    assert.equal(batches.length, 3);
    assert.equal(batches[0].length, MULTICAST_LIMIT);
    assert.equal(batches[1].length, MULTICAST_LIMIT);
    assert.equal(batches[2].length, 1);
    assert.equal(batches.flat().length, tokens.length);
  });

  test('a roster under the limit is one batch', () => {
    assert.deepEqual(chunk(['a', 'b']), [['a', 'b']]);
  });

  test('an empty roster produces no batches, not one empty call', () => {
    assert.deepEqual(chunk([]), []);
  });

  test('preserves order and loses nothing', () => {
    assert.deepEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  });
});

describe('dedupeTokens', () => {
  test('one person, two apps, one phone gets one notification', () => {
    // A broadcast to `all` reads users AND drivers; the same token appears in
    // both when one person drives and orders from the same device.
    assert.deepEqual(dedupeTokens(['a', 'b', 'a']), ['a', 'b']);
  });

  test('drops empty and non-string entries rather than sending to them', () => {
    assert.deepEqual(dedupeTokens(['a', '', '   ', null, undefined, 42, {}]), ['a']);
  });
});

describe('targetCollections', () => {
  test('"drivers" reads drivers — the dead end this fixes', () => {
    // The admin panel has always offered this option; nothing ever read it.
    assert.deepEqual(targetCollections('drivers'), ['drivers']);
  });

  test('"customers" reads users', () => {
    assert.deepEqual(targetCollections('customers'), ['users']);
  });

  test('"all" reads both', () => {
    assert.deepEqual(targetCollections('all'), ['users', 'drivers']);
  });

  test('a missing target defaults to everyone, matching the client default', () => {
    // Both apps read `target ?? 'all'`; the server must agree or a legacy
    // document written without a target would reach nobody.
    assert.deepEqual(targetCollections(undefined), ['users', 'drivers']);
    assert.deepEqual(targetCollections(null), ['users', 'drivers']);
  });

  test('a non-keyword target is NOT a broadcast', () => {
    // Failing open here would turn one hand-edited document into a push to
    // the entire user base. An empty list tells the caller to treat the value
    // as a single uid instead (SCHEMA.md §notifications permits one).
    assert.deepEqual(targetCollections('aXk92LmQpR'), []);
    assert.deepEqual(targetCollections(''), []);
    assert.deepEqual(targetCollections(7), []);
  });
});

describe('parseTarget (NT-2)', () => {
  test('the broadcast keywords resolve to collections', () => {
    assert.deepEqual(parseTarget('all'), { kind: 'collections', collections: ['users', 'drivers'] });
    assert.deepEqual(parseTarget('customers'), { kind: 'collections', collections: ['users'] });
    assert.deepEqual(parseTarget('drivers'), { kind: 'collections', collections: ['drivers'] });
    assert.deepEqual(parseTarget(undefined), { kind: 'collections', collections: ['users', 'drivers'] });
  });

  test('a "tag:" prefix targets a customer segment (CU-4)', () => {
    assert.deepEqual(parseTarget('tag:vip'), { kind: 'tag', tag: 'vip' });
    assert.deepEqual(parseTarget('TAG:Diaspora'), { kind: 'tag', tag: 'diaspora' });
  });

  test('the derived segments are recognised', () => {
    for (const s of DERIVED_SEGMENTS) {
      assert.deepEqual(parseTarget(s), { kind: 'segment', segment: s });
    }
  });

  test('anything else is a single uid, with its case preserved', () => {
    // Firestore ids are case sensitive — lowercasing one would address a
    // different document, or none.
    assert.deepEqual(parseTarget('aB12Cd34'), { kind: 'uid', uid: 'aB12Cd34' });
    assert.deepEqual(parseTarget('  spaced  '), { kind: 'uid', uid: 'spaced' });
  });
});

describe('broadcastData (NT-4)', () => {
  test('always carries the type and the notification id', () => {
    const d = broadcastData('n1');
    assert.equal(d.type, 'broadcast');
    assert.equal(d.notificationId, 'n1');
    assert.equal(d.destType, undefined);
  });

  test('a valid destination is passed through as strings', () => {
    const d = broadcastData('n1', 'search', 'grocery');
    assert.equal(d.destType, 'search');
    assert.equal(d.destValue, 'grocery');
  });

  test('an order destination also fills orderId, reusing the existing routing', () => {
    const d = broadcastData('n1', 'order', 'order-9');
    assert.equal(d.orderId, 'order-9');
  });

  test('an unknown or half-filled destination is dropped, not forwarded', () => {
    assert.equal(broadcastData('n1', 'weird', 'x').destType, undefined);
    assert.equal(broadcastData('n1', 'search', '').destType, undefined);
    assert.equal(broadcastData('n1', '', 'grocery').destType, undefined);
  });
});

describe('isDue (NT-3)', () => {
  const NOW = Date.UTC(2026, 8, 11, 12, 0, 0);
  test('an unscheduled broadcast is always due', () => {
    assert.equal(isDue(null, NOW), true);
    assert.equal(isDue(undefined, NOW), true);
  });
  test('a future schedule is not due yet; a past one is', () => {
    assert.equal(isDue(NOW + 60_000, NOW), false);
    assert.equal(isDue(NOW - 1, NOW), true);
    assert.equal(isDue(NOW, NOW), true);
  });
});

describe('orderCreatedContent', () => {
  test('names the merchant and the money', () => {
    const c = orderCreatedContent('o1', { merchantName: 'Island Grill', total: 2450 });
    assert.equal(c.body, 'Island Grill · J$2,450');
    assert.equal(c.data?.orderId, 'o1');
  });

  test('shows the order\'s stored total, never a recomputed one', () => {
    // A driver deciding whether to take a job must see the same figure the
    // customer was charged.
    assert.match(orderCreatedContent('o1', { total: 1500 }).body, /J\$1,500/);
  });

  test('rounds to whole units — money is stored as integers', () => {
    assert.match(orderCreatedContent('o1', { total: 1500.6 }).body, /J\$1,501/);
  });

  test('a missing total is omitted rather than shown as $0 or NaN', () => {
    // "$0" reads as a free order and would have drivers racing for nothing.
    assert.equal(orderCreatedContent('o1', { merchantName: 'Juici' }).body, 'Juici');
    assert.equal(orderCreatedContent('o1', { merchantName: 'Juici', total: 'x' }).body, 'Juici');
    assert.equal(orderCreatedContent('o1', { merchantName: 'Juici', total: 0 }).body, 'Juici');
  });

  test('a missing merchant name still produces a usable message', () => {
    assert.equal(orderCreatedContent('o1', {}).body, 'A merchant');
  });

  test('always carries the orderId so the tap can deep-link', () => {
    assert.equal(orderCreatedContent('abc', {}).data?.orderId, 'abc');
  });
});

describe('orderReofferContent', () => {
  test('reads as a re-offer, not a second brand-new order', () => {
    const c = orderReofferContent('o1', { merchantName: 'Juici', total: 1440 });
    assert.equal(c.title, 'Order still needs a driver');
    assert.equal(c.body, 'Juici · J$1,440');
  });

  test('is distinguishable from the first alert by its data type', () => {
    // The app routes on data.type; a re-offer must not look identical to the
    // original push.
    assert.equal(orderReofferContent('o1', {}).data?.type, 'order_reoffer');
    assert.equal(orderCreatedContent('o1', {}).data?.type, 'order_created');
  });

  test('carries the orderId and applies the same money rules', () => {
    assert.equal(orderReofferContent('abc', {}).data?.orderId, 'abc');
    assert.equal(orderReofferContent('o1', { merchantName: 'Juici', total: 0 }).body, 'Juici');
  });
});

describe('shouldReoffer', () => {
  test('says no before the first push has had time to work', () => {
    // onOrderCreated already covered the opening window; re-offering now would
    // double-send.
    assert.equal(shouldReoffer(0), false);
    assert.equal(shouldReoffer(REOFFER_MIN_AGE_MS - 1), false);
  });

  test('says yes across the whole re-offer window, inclusive of both edges', () => {
    assert.equal(shouldReoffer(REOFFER_MIN_AGE_MS), true);
    assert.equal(shouldReoffer((REOFFER_MIN_AGE_MS + REOFFER_MAX_AGE_MS) / 2), true);
    assert.equal(shouldReoffer(REOFFER_MAX_AGE_MS), true);
  });

  test('stops once an order is old enough to be a human dispatch problem', () => {
    // Past the ceiling a stuck order should be surfaced to a person, not pinged
    // forever.
    assert.equal(shouldReoffer(REOFFER_MAX_AGE_MS + 1), false);
  });
});

describe('statusChangeContent', () => {
  test('titles come from the shared lifecycle module', () => {
    // So the push and the tracking screen cannot disagree about what the
    // order is doing.
    for (const s of [OrderStatus.CONFIRMED, OrderStatus.PICKED_UP,
      OrderStatus.IN_TRANSIT, OrderStatus.DELIVERED, OrderStatus.CANCELLED]) {
      assert.equal(statusChangeContent('o1', s)?.title, OrderStatus.label(s));
    }
  });

  test('every non-pending canonical status produces a message', () => {
    for (const s of OrderStatus.ALL) {
      const c = statusChangeContent('o1', s);
      if (s === OrderStatus.PENDING) assert.equal(c, null, s);
      else assert.ok(c && c.body.length > 0, s);
    }
  });

  test('says nothing on pending — the customer is looking at the receipt', () => {
    assert.equal(statusChangeContent('o1', OrderStatus.PENDING), null);
  });

  test('a status outside the lifecycle sends nothing', () => {
    // 'accepted' was never written by any app but appears in old docs and
    // old notes. It must not produce a message with a raw status in it.
    assert.equal(statusChangeContent('o1', 'accepted'), null);
    assert.equal(statusChangeContent('o1', ''), null);
  });

  test('a cancellation is never phrased as good news', () => {
    const c = statusChangeContent('o1', OrderStatus.CANCELLED);
    assert.match(c!.body, /cancelled/i);
    assert.doesNotMatch(c!.body, /enjoy|on the way|delivered/i);
  });

  test('carries orderId and status for deep-linking', () => {
    const c = statusChangeContent('o9', OrderStatus.IN_TRANSIT);
    assert.equal(c?.data?.orderId, 'o9');
    assert.equal(c?.data?.status, OrderStatus.IN_TRANSIT);
  });
});

describe('driverStatusContent', () => {
  test('tells an approved driver they can go online', () => {
    assert.match(driverStatusContent('approved')!.body, /go online/i);
  });

  test('tells a rejected driver plainly', () => {
    assert.match(driverStatusContent('rejected')!.title, /not approved/i);
  });

  test('says nothing for pending or anything unrecognised', () => {
    // A driver reverted to pending by an admin correction should hear it
    // from a person, not from a push with no explanation.
    assert.equal(driverStatusContent('pending'), null);
    assert.equal(driverStatusContent('suspended'), null);
    assert.equal(driverStatusContent(''), null);
  });
});

describe('isDeadToken', () => {
  test('recognises the codes that mean the app is gone', () => {
    assert.equal(isDeadToken('messaging/registration-token-not-registered'), true);
    assert.equal(isDeadToken('messaging/invalid-registration-token'), true);
  });

  test('does NOT prune on a transient failure', () => {
    // Deleting a live token because FCM was briefly unavailable would make a
    // working driver permanently unreachable until they reinstall.
    assert.equal(isDeadToken('messaging/server-unavailable'), false);
    assert.equal(isDeadToken('messaging/internal-error'), false);
    assert.equal(isDeadToken('messaging/quota-exceeded'), false);
    assert.equal(isDeadToken(undefined), false);
    assert.equal(isDeadToken(null), false);
  });
});
