#!/usr/bin/env node
/* Overseas / Shop-and-Deliver request queue (admin panel).
 *
 * `admin_panel/overseas-status.js` imports nothing, so plain Node can load it —
 * the same arrangement as pricing-form.js and image-upload.js, and the only
 * reason the panel's logic is testable at all given it ships unbundled with no
 * build step.
 *
 * What is being protected: a request is a person waiting to hear back about
 * shopping for their family. The failure that matters is not a crash — it is a
 * request that quietly does not appear in the queue an operator works from.
 * Every case below is a way one could go missing.
 *
 * Client checklist SD-1 / SD-4 / SD-5: the vocabulary is now the nine-stage
 * pipeline plus three outcomes.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  ALL, PIPELINE, OUTCOMES, OPEN, CLOSED, TERMINAL, LABEL, TONE,
  NEW, REVIEWING, QUOTE_SENT, AWAITING_CUSTOMER, APPROVED, SHOPPING,
  READY, OUT_FOR_DELIVERY, COMPLETED, DECLINED, CANCELLED, EXPIRED,
  normalise, isOpen, isClosed, nextStatuses, summarise, matches, filterInquiries,
  itemCount
} from '../admin_panel/overseas-status.js';

const inq = (over = {}) => ({
  id: 'i1',
  customerName: 'Marcia Brown',
  contactEmail: 'marcia@example.com',
  contactPhone: '+1 718 555 0134',
  originCountry: 'Brooklyn, USA',
  recipientName: 'Delroy Brown',
  recipientPhone: '876 555 0110',
  recipientParish: 'St. Thomas',
  itemCategory: 'Food & groceries',
  itemDescription: '3 tins of ackee',
  status: NEW,
  createdAt: new Date('2026-07-01T10:00:00Z'),
  ...over
});

describe('the status vocabulary', () => {
  test('the pipeline is the client\'s nine stages, in order', () => {
    assert.deepEqual(PIPELINE, [
      NEW, REVIEWING, QUOTE_SENT, AWAITING_CUSTOMER, APPROVED,
      SHOPPING, READY, OUT_FOR_DELIVERY, COMPLETED
    ]);
    assert.deepEqual(OUTCOMES, [DECLINED, CANCELLED, EXPIRED]);
    assert.equal(ALL.length, 12);
  });

  test('open and terminal partition every status', () => {
    assert.deepEqual([...OPEN, ...TERMINAL].sort(), [...ALL].sort());
    assert.equal(OPEN.filter((s) => TERMINAL.includes(s)).length, 0);
  });

  test('SD-1: the "Closed" bucket is every terminal state, not just declined', () => {
    assert.deepEqual([...CLOSED].sort(), [COMPLETED, DECLINED, CANCELLED, EXPIRED].sort());
    assert.equal(isClosed(COMPLETED), true);
    assert.equal(isClosed(CANCELLED), true);
    assert.equal(isClosed(EXPIRED), true);
    assert.equal(isClosed(SHOPPING), false);
  });

  test('every status has an operator label and a badge tone', () => {
    for (const s of ALL) {
      assert.ok(LABEL[s], s);
      assert.ok(TONE[s], s);
    }
  });

  test('an unknown or missing status is treated as new', () => {
    assert.equal(normalise(undefined), NEW);
    assert.equal(normalise(null), NEW);
    assert.equal(normalise('shipped'), NEW);
    assert.equal(normalise(''), NEW);
    assert.equal(isOpen('shipped'), true);
  });

  test('the pre-SD-4 slugs map onto the nearest new state', () => {
    assert.equal(normalise('contacted'), REVIEWING);
    assert.equal(normalise('quoted'), QUOTE_SENT);
    assert.equal(normalise('closed'), COMPLETED);
  });
});

describe('nextStatuses', () => {
  test('never offers the status the request is already in', () => {
    for (const s of ALL) {
      assert.ok(!nextStatuses(s).includes(s), s);
    }
  });

  test('offers every other status, so a mistake is always correctable', () => {
    for (const s of ALL) {
      assert.equal(nextStatuses(s).length, ALL.length - 1, s);
    }
  });

  test('leads with the likely next step down the pipeline', () => {
    assert.equal(nextStatuses(NEW)[0], REVIEWING);
    assert.equal(nextStatuses(REVIEWING)[0], QUOTE_SENT);
    assert.equal(nextStatuses(QUOTE_SENT)[0], AWAITING_CUSTOMER);
    assert.equal(nextStatuses(OUT_FOR_DELIVERY)[0], COMPLETED);
  });

  test('after the last pipeline step the likely move is an outcome', () => {
    // `completed` has no forward step, so the outcomes come first.
    assert.equal(nextStatuses(COMPLETED)[0], DECLINED);
  });

  test('an outcome can be corrected straight back into the pipeline', () => {
    assert.equal(nextStatuses(DECLINED)[0], NEW);
    assert.ok(nextStatuses(CANCELLED).includes(SHOPPING));
  });
});

describe('summarise', () => {
  test('counts each status, the open queue and the closed bucket', () => {
    const s = summarise([
      inq({ status: NEW }), inq({ status: NEW }),
      inq({ status: AWAITING_CUSTOMER }),
      inq({ status: SHOPPING }),
      inq({ status: COMPLETED }),
      inq({ status: DECLINED })
    ]);
    assert.equal(s.total, 6);
    assert.equal(s.open, 4);            // 2 new + awaiting + shopping
    assert.equal(s.closed, 2);          // completed + declined
    assert.equal(s.newCount, 2);
    assert.equal(s.awaitingCustomer, 1);
    assert.equal(s.counts[COMPLETED], 1);
  });

  test('an empty list reports zeroes, not blanks', () => {
    const s = summarise([]);
    assert.equal(s.total, 0);
    assert.equal(s.open, 0);
    assert.equal(s.closed, 0);
    assert.equal(s.counts[QUOTE_SENT], 0);
  });
});

describe('itemCount (SD-5)', () => {
  test('counts one item per line', () => {
    assert.equal(itemCount('3 tins of ackee\n2 packs of rice\n1 box of milk'), 3);
    assert.equal(itemCount('  bread\n\n  eggs  \n'), 2);
  });

  test('falls back to separators on a single line', () => {
    assert.equal(itemCount('ackee, rice, milk'), 3);
    assert.equal(itemCount('bread and butter and jam'), 3);
  });

  test('an empty list is zero, not one', () => {
    assert.equal(itemCount(''), 0);
    assert.equal(itemCount('   '), 0);
    assert.equal(itemCount(null), 0);
    assert.equal(itemCount(undefined), 0);
  });

  test('a single item is one', () => {
    assert.equal(itemCount('a big bag of rice'), 1);
  });
});

describe('matches', () => {
  test('an empty search matches everything', () => {
    assert.equal(matches(inq(), ''), true);
    assert.equal(matches(inq(), '   '), true);
    assert.equal(matches(inq(), null), true);
  });

  test('finds a request by any handle an operator has on the phone', () => {
    assert.equal(matches(inq(), 'marcia'), true);
    assert.equal(matches(inq(), 'DELROY'), true);
    assert.equal(matches(inq(), '876 555'), true);
    assert.equal(matches(inq(), 'st. thomas'), true);
    assert.equal(matches(inq(), 'ackee'), true);
    assert.equal(matches(inq(), 'i1'), true);
  });

  test('does not match something that is not there', () => {
    assert.equal(matches(inq(), 'portland'), false);
  });

  test('survives a request with missing fields', () => {
    assert.equal(matches({ id: 'x' }, 'x'), true);
    assert.equal(matches({ id: 'x' }, 'marcia'), false);
  });
});

describe('filterInquiries', () => {
  const list = [
    inq({ id: 'a', status: NEW, createdAt: new Date('2026-07-01') }),
    inq({ id: 'b', status: QUOTE_SENT, createdAt: new Date('2026-07-03') }),
    inq({ id: 'c', status: COMPLETED, createdAt: new Date('2026-07-02') }),
    inq({ id: 'd', status: DECLINED, createdAt: new Date('2026-06-30') })
  ];

  test('defaults to the working queue', () => {
    assert.deepEqual(filterInquiries(list, {}).map((i) => i.id), ['b', 'a']);
  });

  test('"all" includes the finished ones, newest first', () => {
    assert.deepEqual(
      filterInquiries(list, { status: 'all' }).map((i) => i.id),
      ['b', 'c', 'a', 'd']
    );
  });

  test('"closed" is every terminal state', () => {
    assert.deepEqual(
      filterInquiries(list, { status: 'closed' }).map((i) => i.id).sort(),
      ['c', 'd']
    );
  });

  test('a single status filters to exactly that status', () => {
    assert.deepEqual(filterInquiries(list, { status: COMPLETED }).map((i) => i.id), ['c']);
  });

  test('search and status filter compose', () => {
    const rows = filterInquiries(
      [...list, inq({ id: 'e', status: NEW, recipientName: 'Pauline' })],
      { status: 'open', q: 'pauline' }
    );
    assert.deepEqual(rows.map((i) => i.id), ['e']);
  });

  test('a request whose timestamp has not resolved sorts first, not last', () => {
    const rows = filterInquiries(
      [...list, inq({ id: 'fresh', status: NEW, createdAt: null })],
      { status: 'open' }
    );
    assert.equal(rows[0].id, 'fresh');
  });

  test('an empty list is not an error', () => {
    assert.deepEqual(filterInquiries([], {}), []);
    assert.deepEqual(filterInquiries(null, {}), []);
  });
});
