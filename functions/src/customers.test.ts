import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { normaliseDisable, disableFields, MAX_REASON_LENGTH } from './customers';

/* P5-05. The callable needs Auth and a database, but the two decisions worth
   pinning are pure:

     - what counts as a well-formed request to remove somebody's access, and
     - what is recorded about it afterwards.

   The second matters because a stale disable reason left on a re-enabled
   account is a false accusation sitting in a record an admin will read later. */

const at = 'SERVER_TIMESTAMP' as unknown as FirebaseFirestore.FieldValue;

describe('normaliseDisable', () => {
  test('accepts a well-formed disable request', () => {
    const r = normaliseDisable({ uid: 'u1', disabled: true, reason: 'repeated chargebacks' });
    assert.deepEqual(r, { uid: 'u1', disabled: true, reason: 'repeated chargebacks' });
  });

  test('accepts a re-enable with no reason', () => {
    // Restoring access needs no justification; removing it does.
    const r = normaliseDisable({ uid: 'u1', disabled: false });
    assert.deepEqual(r, { uid: 'u1', disabled: false, reason: '' });
  });

  test('refuses a missing uid', () => {
    for (const uid of [undefined, '', '   ']) {
      assert.throws(() => normaliseDisable({ uid, disabled: false }), /uid/i, String(uid));
    }
  });

  test('refuses a uid longer than an Auth uid can be', () => {
    assert.throws(
      () => normaliseDisable({ uid: 'x'.repeat(129), disabled: false }),
      /identifier/i
    );
  });

  test('`disabled` must be a real boolean, not a truthy value', () => {
    /* The important case is the string 'false', which is truthy. A hand-rolled
       call or a form value passed straight through would otherwise LOCK
       SOMEBODY OUT while asking to let them back in. */
    for (const disabled of ['false', 'true', 1, 0, null, undefined] as unknown[]) {
      assert.throws(
        () => normaliseDisable({ uid: 'u1', disabled: disabled as boolean }),
        /true or false/i,
        String(disabled)
      );
    }
  });

  test('requires a reason when disabling', () => {
    for (const reason of [undefined, '', '    ']) {
      assert.throws(
        () => normaliseDisable({ uid: 'u1', disabled: true, reason }),
        /reason/i,
        String(reason)
      );
    }
  });

  test('trims the reason, and a whitespace-only reason is no reason', () => {
    const r = normaliseDisable({ uid: 'u1', disabled: true, reason: '  fraud  ' });
    assert.equal(r.reason, 'fraud');
  });

  test('caps the reason rather than rejecting a long one', () => {
    // Rejecting would lose the admin's typing at the moment they are trying to
    // stop something. Truncating keeps the action and the gist.
    const r = normaliseDisable({
      uid: 'u1',
      disabled: true,
      reason: 'x'.repeat(MAX_REASON_LENGTH + 200)
    });
    assert.equal(r.reason.length, MAX_REASON_LENGTH);
  });
});

describe('disableFields', () => {
  test('disabling records the reason and when', () => {
    const f = disableFields({ uid: 'u1', disabled: true, reason: 'fraud' }, at);
    assert.equal(f.disabled, true);
    assert.equal(f.disabledReason, 'fraud');
    assert.equal(f.disabledAt, at);
  });

  test('re-enabling CLEARS the previous reason', () => {
    /* The defect this prevents: an account disabled for "fraudulent orders",
       investigated, cleared and re-enabled — still carrying "fraudulent
       orders" in a field the next admin reads as current. Merging without
       clearing would leave it there forever. */
    const f = disableFields({ uid: 'u1', disabled: false, reason: '' }, at);
    assert.equal(f.disabled, false);
    assert.equal(f.disabledReason, null);
    assert.equal(f.disabledAt, null);
  });

  test('every key is present in both directions', () => {
    // set(..., {merge:true}) only removes what it explicitly overwrites, so an
    // omitted key would silently keep its old value.
    const on = Object.keys(disableFields({ uid: 'u', disabled: true, reason: 'r' }, at)).sort();
    const off = Object.keys(disableFields({ uid: 'u', disabled: false, reason: '' }, at)).sort();
    assert.deepEqual(on, off);
  });
});
