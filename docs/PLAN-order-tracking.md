# Plan — full order tracking and a restaurant (merchant) side

Client checklist item 17 (Sep 2026). Status: **planned, not started.**

## What the client asked for

The customer's tracker should read:

> Confirmed → Preparing → Rider assigned → Picked up → On the way → Delivered

and the restaurant marks the food as *preparing* (and *ready*) itself. GPS
live tracking of the rider comes later and must fit this model.

## Where it stands today

- Statuses (`SCHEMA.md` §orders): `pending → confirmed → picked_up →
  in_transit → delivered`, plus `cancelled`. **`confirmed` means a driver
  accepted the order** — driver assignment and "confirmed" are the same event.
- No restaurant involvement at all: nobody accepts or prepares on the
  merchant's side. The customer tracker shows *Order placed → Driver assigned
  → Picked up → On the way → Delivered*.
- The status vocabulary exists in four copies, checked by
  `tools/check-status-parity.mjs`: both apps' `models/order_status.dart`,
  `admin_panel/order-status.js`, `functions/src/orderStatus.ts`. Transitions
  are enforced in `firestore.rules` and tested in `test/rules/`.
- The driver already streams `driverLoc` onto the order during delivery
  (DriverLocationService); the customer screen reads it. That is the base for
  the future GPS map.
- Firebase is on the free Spark plan: no Cloud Functions, so no custom claims
  and no push notifications. Everything below works without them.

## Target model

Split *restaurant progress* (the status) from *rider assignment* (a field):

```
pending ─► confirmed ─► preparing ─► ready ─► picked_up ─► in_transit ─► delivered
 (placed)   (restaurant   (restaurant  (restaurant  (driver)      (driver)      (driver)
             accepted)     cooking)     done)
                              driverId set at any point up to `ready` = "Rider assigned"
```

- `confirmed`, `preparing`, `ready` are set by the **merchant** (or admin).
- A driver claims an order by setting `driverId` + `assignedAt`; the status
  does not change. Claimable while `status in [confirmed, preparing, ready]`
  and `driverId == null`. Picking up requires `ready` (admin can override).
- Orders with no merchant (Packages, Pickup & Delivery, Errands requests)
  skip the kitchen stages: `pending → confirmed` by admin/driver, then as now.
- Customer tracker steps map to data:
  Confirmed (`confirmed`) → Preparing (`preparing`) → Rider assigned
  (`driverId != null`) → Picked up → On the way (`in_transit`) → Delivered.
  "Rider heading to you" copy on `in_transit` + the `driverLoc` map later.

## The restaurant side

Recommendation: a **web merchant portal** first, built like the admin panel
(same stack, same design tokens) at e.g. `merchant.shipeastja.com`. A
restaurant runs it on a counter tablet or phone browser; no store install,
works the day it ships, and can become a Flutter app later with the same data.

- Screens: login; live incoming orders with a sound; order detail with
  Accept / Preparing / Ready buttons; today's history; open/closed switch.
- Accounts: admin creates a merchant login in the admin panel. Without Cloud
  Functions there are no custom claims, so rules check a mapping document
  `merchantUsers/{uid} → { merchantId }` written by admin only.
- Rules: a merchant user may read orders where `merchantId` matches theirs
  and may only move `status` along `pending → confirmed → preparing → ready`
  (or cancel with a reason before `ready`), touching no money fields.

## Work breakdown (in order)

1. **Schema + vocabulary** — add `preparing`, `ready`; add `assignedAt`,
   `preparingAt`, `readyAt`; change "driver claims" to set `driverId`
   without changing status. Update all four status copies, the parity check,
   `SCHEMA.md`, and write a migration for live orders currently `confirmed`
   with a driver.
2. **Rules + tests** — merchant transitions via `merchantUsers`, new driver
   claim rule, pick-up requires `ready`. Extend `test/rules/`.
3. **Driver app** — offer list = claimable orders (not just `pending`);
   show kitchen state ("Preparing — ready soon"); Pick-up enabled at `ready`.
4. **Customer app** — tracker steps as above; "Rider assigned" shows the
   driver card; "Rider heading to you" on `in_transit`.
5. **Admin panel** — new statuses in filters/badges/legal transitions;
   merchant login management (`merchantUsers`); manual override.
6. **Merchant portal** — new `merchant_panel/` folder, hosting target, CI
   deploy job.
7. **Later: GPS** — customer map from `driverLoc`, ETA; iOS needs the
   location permission string (`docs/IOS-STATUS.md`).

Deploy note: steps 1–2 change `firestore.rules`, which CI does not deploy —
publish rules and apps together, or old apps will hit refused writes.

## Decisions for the owner before starting

- Web portal first (recommended) or a Flutter restaurant app?
- Who accepts when a restaurant never responds — does the order auto-cancel
  or does admin step in after N minutes?
- Should the restaurant see the customer's name/phone, or only order items?
