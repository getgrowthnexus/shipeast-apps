/* ═══════════════════════════════════════════════════════════════
   Promo discount eligibility — admin panel copy.
   Source of truth: functions/src/eligibility.ts (SCHEMA.md `promoCodes.eligibility`)
   ═══════════════════════════════════════════════════════════════

   Mirrors functions/src/eligibility.ts and
   customer_app/lib/models/promo_eligibility.dart. This copy is used two ways:
   the create/edit form reads it back out as a plain object to write to
   Firestore (buildEligibility), and the promo table renders it as a summary
   badge (describeEligibility) — it is never used to *gate* a redemption here,
   that authority stays server-side in redeemPromo (P3-03 / PR-5).

   Edit all three, or none. Deliberately no Firebase import — pure functions
   only, so this is testable the same way order-status.js is
   (tools/test-promo-eligibility.mjs, plain `node --test`, no build step). */

export const INELIGIBLE_MESSAGE = {
  not_new_customer: 'This code is for new customers only.',
  not_existing_customer: 'This code is for returning customers only.',
  customer_not_selected: 'This code is not available on your account.',
  merchant_not_eligible: 'This code does not apply to this merchant.',
  category_not_eligible: 'This code does not apply to this category.',
  area_not_eligible: 'This code is not available for your delivery area.',
  not_first_order: 'This code is for your first order only.',
  order_kind_not_eligible: 'This code does not apply to this kind of request.',
};

function norm(s) { return String(s || '').trim().toLowerCase(); }

/** Same rules as functions/src/eligibility.ts checkEligibility — kept here so
 *  the promo table can preview "would this code apply" without a round trip,
 *  and so a future admin-side redemption tool has one place to call. */
export function checkEligibility(elig, ctx) {
  if (!elig) return { eligible: true };

  if (elig.customerScope === 'new' && ctx.priorOrderCount > 0) return fail('not_new_customer');
  if (elig.customerScope === 'existing' && ctx.priorOrderCount <= 0) return fail('not_existing_customer');
  if (elig.customerScope === 'selected') {
    var ids = elig.customerIds || [];
    if (ids.indexOf(ctx.customerId) === -1) return fail('customer_not_selected');
  }

  if (elig.merchantIds && elig.merchantIds.length > 0) {
    if (!ctx.merchantId || elig.merchantIds.indexOf(ctx.merchantId) === -1) return fail('merchant_not_eligible');
  }

  if (elig.categories && elig.categories.length > 0) {
    if (!ctx.merchantCategory || elig.categories.indexOf(ctx.merchantCategory) === -1) return fail('category_not_eligible');
  }

  if (elig.deliveryAreas && elig.deliveryAreas.length > 0) {
    var area = norm(ctx.deliveryArea);
    var matches = area !== '' && elig.deliveryAreas.some(function (a) { return area.indexOf(norm(a)) > -1; });
    if (!matches) return fail('area_not_eligible');
  }

  if (elig.firstOrderOnly && ctx.priorOrderCount > 0) return fail('not_first_order');

  if (elig.orderKinds && elig.orderKinds.length > 0) {
    if (elig.orderKinds.indexOf(ctx.orderKind) === -1) return fail('order_kind_not_eligible');
  }

  return { eligible: true };
}

function fail(reason) { return { eligible: false, reason: reason, message: INELIGIBLE_MESSAGE[reason] }; }

/** Checklist PR-5 "Delivery fee only" / "Order subtotal". */
export function discountBaseAmount(elig, subtotal, deliveryFee) {
  return (elig && elig.discountBase === 'deliveryFee') ? deliveryFee : subtotal;
}

/** Reads the create/edit form's eligibility controls into the plain object
 *  written to `promoCodes/{code}.eligibility`. Returns `null` — not an empty
 *  object — when every control is at its "no restriction" default, so a code
 *  nobody scoped keeps behaving exactly like a pre-PR-5 code (SCHEMA.md).
 *
 *  `pick(id)` reads a <select multiple>'s selected option values; passed in
 *  rather than touching the DOM directly, so this stays pure and testable. */
export function buildEligibility(form) {
  var elig = {};

  if (form.customerScope) elig.customerScope = form.customerScope;
  if (form.customerScope === 'selected' && form.customerIds && form.customerIds.length) {
    elig.customerIds = form.customerIds;
  }
  if (form.merchantIds && form.merchantIds.length) elig.merchantIds = form.merchantIds;
  if (form.categories && form.categories.length) elig.categories = form.categories;
  if (form.deliveryAreas && form.deliveryAreas.length) elig.deliveryAreas = form.deliveryAreas;
  if (form.firstOrderOnly) elig.firstOrderOnly = true;
  if (form.discountBase === 'deliveryFee') elig.discountBase = 'deliveryFee';
  // All three kinds checked (or none touched) means "any kind" — only write
  // orderKinds when the admin has actually narrowed it.
  if (form.orderKinds && form.orderKinds.length && form.orderKinds.length < 3) {
    elig.orderKinds = form.orderKinds;
  }

  return Object.keys(elig).length ? elig : null;
}

/** Turns a comma-separated free-text field into a trimmed, de-duplicated,
 *  non-empty string array — the shared parser behind the Delivery areas
 *  field, so "St. Thomas, , Portland,St. Thomas" reads as two areas. */
export function parseAreas(text) {
  if (!text) return [];
  var seen = {};
  var out = [];
  String(text).split(',').forEach(function (part) {
    var t = part.trim();
    if (!t) return;
    var key = t.toLowerCase();
    if (seen[key]) return;
    seen[key] = true;
    out.push(t);
  });
  return out;
}

/** One short line for the promo table / side panel — "Restricted: new
 *  customers · 2 merchants · St. Thomas" — or null when the code is open to
 *  everyone. Never throws on a malformed/legacy `eligibility` value. */
export function describeEligibility(elig) {
  if (!elig || typeof elig !== 'object') return null;
  var parts = [];
  if (elig.customerScope === 'new') parts.push('new customers');
  else if (elig.customerScope === 'existing') parts.push('existing customers');
  else if (elig.customerScope === 'selected') {
    var n = (elig.customerIds || []).length;
    parts.push(n + ' selected customer' + (n === 1 ? '' : 's'));
  }
  if (elig.firstOrderOnly) parts.push('first order only');
  if (elig.merchantIds && elig.merchantIds.length) parts.push(elig.merchantIds.length + ' merchant' + (elig.merchantIds.length === 1 ? '' : 's'));
  if (elig.categories && elig.categories.length) parts.push(elig.categories.join('/'));
  if (elig.deliveryAreas && elig.deliveryAreas.length) parts.push(elig.deliveryAreas.join(', '));
  if (elig.orderKinds && elig.orderKinds.length) parts.push(elig.orderKinds.join('/'));
  if (elig.discountBase === 'deliveryFee') parts.push('delivery fee only');
  return parts.length ? 'Restricted: ' + parts.join(' · ') : null;
}
