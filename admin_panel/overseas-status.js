/* ═══════════════════════════════════════════════════════════════
   Shop-and-deliver request handling — admin panel copy.
   Source of truth: SCHEMA.md §overseasInquiries
   ═══════════════════════════════════════════════════════════════

   A customer abroad asks us to buy from a local Jamaican store and deliver to
   their family — not shipping. The collection is still `overseasInquiries` for
   continuity; the "overseas" here means the customer, not the goods.

   Mirrors customer_app/lib/models/overseas_inquiry.dart. Edit both, or
   neither.

   Client checklist SD-1 / SD-4 / SD-5: the handling flow is now the full
   nine-stage pipeline the client specified, plus three outcomes:

     New → Reviewing → Quote Sent → Awaiting Customer → Approved →
     Shopping → Ready for Delivery → Out for Delivery → Completed
     outcomes: Declined | Cancelled | Expired

   Imports nothing on purpose, for the same reason image-upload.js and
   pricing-form.js do: the panel ships unbundled with no build step, so a
   module free of Firebase imports loads in plain Node and its logic can be
   pinned by `node --test` instead of by clicking through a browser.

   Note on labels: LABEL below is operator-facing. The customer-facing wording
   lives in the Dart mirror's `OverseasStatus.label` / `.explain` — an operator
   wants the queue state ("Quote Sent"); the customer wants to know whether
   they are waiting on us or we on them.                                    */

export const NEW = 'new';
export const REVIEWING = 'reviewing';
export const QUOTE_SENT = 'quote_sent';
export const AWAITING_CUSTOMER = 'awaiting_customer';
export const APPROVED = 'approved';
export const SHOPPING = 'shopping';
export const READY = 'ready_for_delivery';
export const OUT_FOR_DELIVERY = 'out_for_delivery';
export const COMPLETED = 'completed';
export const DECLINED = 'declined';
export const CANCELLED = 'cancelled';
export const EXPIRED = 'expired';

/** The linear handling pipeline, in order. `completed` is its successful end. */
export const PIPELINE = [
  NEW, REVIEWING, QUOTE_SENT, AWAITING_CUSTOMER, APPROVED,
  SHOPPING, READY, OUT_FOR_DELIVERY, COMPLETED
];

/** The ways a request ends other than being fulfilled. */
export const OUTCOMES = [DECLINED, CANCELLED, EXPIRED];

export const ALL = PIPELINE.concat(OUTCOMES);

/** Still somebody's responsibility — this is the working queue. */
export const OPEN = [
  NEW, REVIEWING, QUOTE_SENT, AWAITING_CUSTOMER, APPROVED,
  SHOPPING, READY, OUT_FOR_DELIVERY
];

/** SD-1: the "Closed" bucket is every terminal state, not just declined. */
export const CLOSED = [COMPLETED, DECLINED, CANCELLED, EXPIRED];
export const TERMINAL = CLOSED;

export const LABEL = {
  [NEW]: 'New',
  [REVIEWING]: 'Reviewing',
  [QUOTE_SENT]: 'Quote Sent',
  [AWAITING_CUSTOMER]: 'Awaiting Customer',
  [APPROVED]: 'Approved',
  [SHOPPING]: 'Shopping',
  [READY]: 'Ready for Delivery',
  [OUT_FOR_DELIVERY]: 'Out for Delivery',
  [COMPLETED]: 'Completed',
  [DECLINED]: 'Declined',
  [CANCELLED]: 'Cancelled',
  [EXPIRED]: 'Expired'
};

/** Badge tone, matching the .bg-* classes in styles.css. */
export const TONE = {
  [NEW]: 'brand',
  [REVIEWING]: 'info',
  [QUOTE_SENT]: 'warning',
  [AWAITING_CUSTOMER]: 'warning',
  [APPROVED]: 'info',
  [SHOPPING]: 'info',
  [READY]: 'info',
  [OUT_FOR_DELIVERY]: 'info',
  [COMPLETED]: 'success',
  [DECLINED]: 'danger',
  [CANCELLED]: 'danger',
  [EXPIRED]: 'neutral'
};

/* The pre-SD-4 vocabulary was `new | contacted | quoted | closed | declined`.
   Un-migrated documents map onto the nearest new state so they still render
   sensibly before the migration runs (tools/migrate). */
const LEGACY = {
  contacted: REVIEWING,
  quoted: QUOTE_SENT,
  closed: COMPLETED
};

/** An unrecognised or missing status is a document that was just written. */
export function normalise(raw) {
  if (ALL.indexOf(raw) > -1) return raw;
  if (LEGACY[raw]) return LEGACY[raw];
  return NEW;
}

export function isOpen(raw) {
  return OPEN.indexOf(normalise(raw)) > -1;
}
export function isClosed(raw) {
  return CLOSED.indexOf(normalise(raw)) > -1;
}
export function isTerminal(raw) {
  return isClosed(raw);
}

/* The statuses the panel offers next.

   Every status stays reachable — an operator who marks the wrong request
   'declined' must be able to put it back, and a rule that traps them there
   just moves the correction into the Firebase console. What this does is order
   the list so the likely next step is first: the next pipeline stage(s), then
   the three outcomes, then the earlier stages in case of a correction. The
   current status is dropped (selecting it is not a change). */
export function nextStatuses(current) {
  const from = normalise(current);
  const idx = PIPELINE.indexOf(from);
  let ordered;
  if (idx > -1) {
    ordered = PIPELINE.slice(idx + 1)
      .concat(OUTCOMES)
      .concat(PIPELINE.slice(0, idx).reverse());
  } else {
    // `from` is an outcome — the likely correction is straight back into the
    // pipeline from the top, then the other outcomes.
    ordered = PIPELINE.concat(OUTCOMES);
  }
  return ordered.filter(function (s, i) {
    return s !== from && ordered.indexOf(s) === i;
  });
}

/** Counts per status, plus the totals the page headline reports. */
export function summarise(list) {
  const counts = {};
  ALL.forEach(function (s) { counts[s] = 0; });
  let open = 0, closed = 0;
  (list || []).forEach(function (i) {
    const s = normalise(i && i.status);
    counts[s] += 1;
    if (isOpen(s)) open += 1;
    else if (isClosed(s)) closed += 1;
  });
  return {
    counts: counts,
    open: open,
    closed: closed,
    total: (list || []).length,
    // Convenience figures the SD-2 / SD-3 / SD-3b cards read directly.
    newCount: counts[NEW],
    awaitingCustomer: counts[AWAITING_CUSTOMER]
  };
}

/* SD-5: a rough item count from the free-text shopping list — one per line, or
   comma-separated on a single line. It is an estimate for the operator's
   glance, not a structured quantity, so it is deliberately forgiving. */
export function itemCount(description) {
  const text = String(description == null ? '' : description).trim();
  if (!text) return 0;
  const lines = text.split(/\n+/).map(function (l) { return l.trim(); })
    .filter(function (l) { return l.length > 0; });
  if (lines.length > 1) return lines.length;
  // A single line — count comma / semicolon / " and " separated fragments.
  return text.split(/\s*(?:,|;|\band\b|\+)\s*/i)
    .filter(function (p) { return p.trim().length > 0; }).length;
}

/* Free-text search across the fields an operator actually has to hand: a
   customer on the phone gives their name or the reference; a courier partner
   gives the recipient or the parish. */
export function matches(inquiry, term) {
  const q = String(term == null ? '' : term).trim().toLowerCase();
  if (!q) return true;
  const haystack = [
    inquiry.id,
    inquiry.customerName,
    inquiry.contactEmail,
    inquiry.contactPhone,
    inquiry.recipientName,
    inquiry.recipientPhone,
    inquiry.recipientParish,
    inquiry.originCountry,
    inquiry.itemCategory,
    inquiry.itemDescription
  ].map(function (v) { return String(v == null ? '' : v).toLowerCase(); }).join(' ');
  return haystack.indexOf(q) > -1;
}

/* Filter + sort in one place so the table and the counts cannot disagree.
   `status` is a single status slug, 'open' for the working queue, 'closed'
   for every terminal state, or 'all'. Newest first, and a request whose
   serverTimestamp has not resolved yet sorts to the top rather than vanishing
   — it is the newest thing there is. */
export function filterInquiries(list, opts) {
  const o = opts || {};
  const status = o.status || 'open';
  const rows = (list || []).filter(function (i) {
    const s = normalise(i.status);
    if (status === 'all') return matches(i, o.q);
    if (status === 'open') return isOpen(s) && matches(i, o.q);
    if (status === 'closed') return isClosed(s) && matches(i, o.q);
    return s === status && matches(i, o.q);
  });
  return rows.sort(function (a, b) {
    const at = a.createdAt ? a.createdAt.getTime() : Infinity;
    const bt = b.createdAt ? b.createdAt.getTime() : Infinity;
    return bt - at;
  });
}
