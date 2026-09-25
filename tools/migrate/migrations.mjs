/* Data migrations (P2-05).
 *
 * Every schema decision in Phase 1 left legacy documents behind. Without this,
 * old orders render as "Processing" forever and old merchants keep the broken
 * fee fields that make the displayed, charged and configured delivery fee
 * three different numbers.
 *
 * Each migration is a pure function: given a document's data, return either
 * the field updates to apply, or null for "already correct, skip".
 *
 * Purity is what makes this testable without a database, and what makes the
 * dry-run report trustworthy — the same code produces the preview and the
 * write.
 *
 * IDEMPOTENCE IS NOT OPTIONAL. Every migration must return null on a document
 * it has already converted, so a resumed or re-run migration is a no-op.
 * tools/migrate/migrations.test.mjs asserts this for all of them by running
 * each twice.
 */

/** Sentinel for a value that must be deleted rather than written. */
export const DELETE = Symbol('delete-field');

/** Parses '$250', '250', 'J$1,250', 'Free delivery' → integer JMD. */
export function parseMoney(value) {
  if (value == null) return null;
  if (typeof value === 'number') return Math.round(value);
  const text = String(value);
  if (/free/i.test(text)) return 0;
  const digits = text.replace(/[^0-9.]/g, '');
  if (digits === '' || digits === '.') return null;
  const n = Number.parseFloat(digits);
  return Number.isFinite(n) ? Math.round(n) : null;
}

/** Parses '2026-08-01' → Date. Returns null if unparseable. */
export function parseDate(value) {
  if (value == null || value === '') return null;
  if (value instanceof Date) return value;
  // Firestore Timestamp — already migrated.
  if (typeof value === 'object' && typeof value.toDate === 'function') {
    return value.toDate();
  }
  const d = new Date(String(value));
  return Number.isNaN(d.getTime()) ? null : d;
}

// ── orders ─────────────────────────────────────────────────────────────────

export const orders = {
  collection: 'orders',
  describe: 'Retire the dead "accepted" status; backfill discount/promoCode/type.',

  migrate(data) {
    const updates = {};

    // 'accepted' was offered by the admin dropdown but understood by nothing.
    if (data.status === 'accepted') updates.status = 'confirmed';

    // Without these the order does not reconcile and analytics under-report.
    if (data.discount === undefined) updates.discount = 0;
    if (data.promoCode === undefined) updates.promoCode = null;

    // Packages and overseas need to be distinguishable (P5-01).
    if (data.type === undefined) updates.type = 'food';

    // Legacy pre-formatted 'amount' string alongside a numeric total.
    if (typeof data.amount === 'string' && data.total == null) {
      const parsed = parseMoney(data.amount);
      if (parsed != null) {
        updates.total = parsed;
        updates.amount = DELETE;
      }
    }

    return Object.keys(updates).length ? updates : null;
  },

  /* Deliberately NOT migrated: orders sitting in 'picked_up'. A driver can
     still deliver from there — the client walks them through in_transit — and
     rewriting a live order's status underneath a driver mid-delivery is
     exactly the class of bug this whole project exists to remove. */
};

// ── merchants ──────────────────────────────────────────────────────────────

export const merchants = {
  collection: 'merchants',
  describe: 'fee → deliveryFee (int), hours → openingHours, open → isOpen, rating → averageRating.',

  migrate(data) {
    const updates = {};

    // The revenue leak: 'fee' was a display string like '$250', read by
    // nothing, while the customer app scraped a number out of a different
    // field and silently charged J$100.
    if (data.fee !== undefined) {
      const parsed = parseMoney(data.fee);
      if (parsed != null && data.deliveryFee === undefined) {
        updates.deliveryFee = parsed;
      }
      updates.fee = DELETE;
    }
    if (typeof data.deliveryFee === 'string') {
      const parsed = parseMoney(data.deliveryFee);
      if (parsed != null) updates.deliveryFee = parsed;
    }

    // Two different things that were conflated: business hours vs delivery ETA.
    if (data.hours !== undefined) {
      if (data.openingHours === undefined) updates.openingHours = String(data.hours);
      updates.hours = DELETE;
    }

    // deliveryTime cannot be derived — it is an ETA nobody ever recorded.
    // Set a default and FLAG it, rather than inventing a per-merchant number.
    if (data.deliveryTime === undefined) {
      updates.deliveryTime = '25–35 min';
      updates._needsReview = 'deliveryTime defaulted — confirm with the merchant';
    }

    // Both were written to the same value; isOpen wins (SCHEMA.md §e).
    if (data.open !== undefined) {
      if (data.isOpen === undefined) updates.isOpen = data.open === true;
      updates.open = DELETE;
    }

    // Seed the aggregate from the placeholder so nothing renders blank; real
    // values arrive once P3-05 starts rolling ratings up.
    if (data.averageRating === undefined && data.rating !== undefined) {
      updates.averageRating = Number(data.rating) || 5.0;
    }

    // A stored counter named "Today" has no reset mechanism (SCHEMA.md §f).
    if (data.ordersToday !== undefined) updates.ordersToday = DELETE;

    return Object.keys(updates).length ? updates : null;
  }
};

// ── promoCodes ─────────────────────────────────────────────────────────────

export const promoCodes = {
  collection: 'promoCodes',
  describe: 'validUntil (string) → expiresAt (Timestamp); normalise discount fields.',

  migrate(data) {
    const updates = {};

    if (data.validUntil !== undefined) {
      const parsed = parseDate(data.validUntil);
      if (data.expiresAt === undefined) {
        // A null here means "never expires", which is the safe reading of an
        // unparseable value: the alternative is silently expiring a live code.
        // Every failure is logged for manual review.
        updates.expiresAt = parsed;
        if (parsed == null && data.validUntil !== '') {
          updates._needsReview =
            `validUntil "${data.validUntil}" could not be parsed — expiry not enforced`;
        }
      }
      updates.validUntil = DELETE;
    }

    // The customer read 'discount'; the admin wrote 'discountAmount'.
    if (data.discountAmount === undefined && data.discount !== undefined) {
      updates.discountAmount = Number(data.discount) || 0;
      updates.discount = DELETE;
    }

    // The customer compared against 'percentage'; the admin wrote 'percent'.
    if (data.discountType === 'percentage') updates.discountType = 'percent';

    if (data.minOrderTotal === undefined) updates.minOrderTotal = 0;
    if (data.usedCount === undefined) updates.usedCount = 0;
    if (data.maxUses === undefined) updates.maxUses = 0;

    /* maxDiscount caps a percentage code (P3-03). An existing uncapped
       percentage code is an unbounded liability — 100% off with nothing to
       stop it — so it is flagged rather than capped at a number nobody chose.
       Fixed-amount codes are self-limiting and take a plain null. */
    if (data.maxDiscount === undefined) {
      updates.maxDiscount = null;
      const type = updates.discountType ?? data.discountType;
      if (type === 'percent' || type === 'percentage') {
        updates._needsReview =
          'percentage code has no maxDiscount — uncapped discount liability';
      }
    }

    return Object.keys(updates).length ? updates : null;
  }
};

// ── drivers ────────────────────────────────────────────────────────────────

export const drivers = {
  collection: 'drivers',
  describe: 'licensePlate → licencePlate; licenceNumber → private/identity; ' +
            'seed averageRating; drop todayEarnings.',

  migrate(data) {
    const updates = {};

    // American → British (SCHEMA.md §c).
    if (data.licensePlate !== undefined) {
      if (data.licencePlate === undefined) updates.licencePlate = data.licensePlate;
      updates.licensePlate = DELETE;
    }

    if (data.averageRating === undefined && data.rating !== undefined) {
      updates.averageRating = Number(data.rating) || 5.0;
    }

    /* PII off the parent document (P4-05). drivers/{uid} is readable by every
       signed-in user — it has to be, because the customer's tracking card
       shows the driver's name and vehicle — so a licence number here was
       readable by every customer who had ever placed an order.

       The copy is written FIRST and the parent field deleted in the same
       batch, so an interrupted run can never leave the number nowhere. */
    const licence = typeof data.licenceNumber === 'string'
      ? data.licenceNumber.trim() : '';
    // '—' is the admin panel's placeholder for "not provided", written by
    // saveDriver for every blank field. Copying it would create a private
    // record that says nothing.
    if (licence !== '' && licence !== '—') {
      updates._subdocs = [{
        path: ['private', 'identity'],
        data: { licenceNumber: licence }
      }];
      updates.licenceNumber = DELETE;
    } else if (data.licenceNumber !== undefined) {
      // An empty placeholder is worse than nothing: indistinguishable from a
      // real record that failed to save.
      updates.licenceNumber = DELETE;
    }

    // Derived at read time from today's delivered orders (SCHEMA.md §f).
    if (data.todayEarnings !== undefined) updates.todayEarnings = DELETE;

    // Flag rather than invent: the driver completes it at next login (P1-08
    // makes it required at registration).
    if (data.vehicleModel === undefined || data.vehicleModel === '—') {
      updates.vehicleModel = null;
      updates._needsReview = 'vehicleModel missing — driver must complete it';
    }

    return Object.keys(updates).length ? updates : null;
  }
};

// ── overseasInquiries ──────────────────────────────────────────────────────

export const overseasInquiries = {
  collection: 'overseasInquiries',
  describe: 'SD-4: 5-state vocabulary → the 9-stage pipeline + 3 outcomes.',

  migrate(data) {
    if (!data) return null;
    // The pre-SD-4 slugs map onto the nearest new state. `closed` was the
    // catch-all end; it becomes `completed` (SD-1 folds declined/cancelled/
    // expired into the "Closed" bucket, but a document that only says `closed`
    // most likely means it was fulfilled — a decline was written as `declined`).
    const map = {
      contacted: 'reviewing',
      quoted: 'quote_sent',
      closed: 'completed',
    };
    const next = map[data.status];
    return next ? { status: next } : null;
  },
};

export const ALL = [orders, merchants, promoCodes, drivers, overseasInquiries];
