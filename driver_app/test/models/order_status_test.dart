import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/models/order_status.dart';

/// Tests for the canonical order lifecycle (P1-01).
///
/// The legal-transition set below is written out by hand rather than derived
/// from [OrderStatus.transitions]. Deriving it would make the test tautological
/// — it would pass for any map, including a wrong one. Hardcoding it means a
/// change to the lifecycle must be made deliberately in two places.
void main() {
  /// Every legal edge, per SCHEMA.md §orders.status.
  const legal = <(String, String)>[
    (OrderStatus.pending, OrderStatus.confirmed),
    (OrderStatus.pending, OrderStatus.cancelled),
    (OrderStatus.confirmed, OrderStatus.pickedUp),
    (OrderStatus.confirmed, OrderStatus.cancelled),
    (OrderStatus.pickedUp, OrderStatus.inTransit),
    (OrderStatus.pickedUp, OrderStatus.cancelled),
    (OrderStatus.inTransit, OrderStatus.delivered),
    (OrderStatus.inTransit, OrderStatus.cancelled),
  ];

  group('values', () {
    test('the canonical set is exactly six statuses', () {
      expect(OrderStatus.all, hasLength(6));
      expect(OrderStatus.all.toSet(), hasLength(6), reason: 'no duplicates');
    });

    test("'accepted' is not in the vocabulary", () {
      // It was offered by the admin dropdown but never written by any app.
      expect(OrderStatus.all, isNot(contains('accepted')));
      expect(OrderStatus.isValid('accepted'), isFalse);
    });

    test('isValid accepts canonical statuses and rejects anything else', () {
      for (final s in OrderStatus.all) {
        expect(OrderStatus.isValid(s), isTrue, reason: s);
      }
      for (final s in ['', 'accepted', 'PENDING', 'pickedUp', 'delivered ']) {
        expect(OrderStatus.isValid(s), isFalse, reason: '"$s"');
      }
    });
  });

  group('sets', () {
    test('active is the non-terminal statuses', () {
      expect(OrderStatus.active, [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.pickedUp,
        OrderStatus.inTransit,
      ]);
    });

    test('driverHeld covers every state in which a driver holds the order', () {
      // The regression this guards: the driver's active-order query listed only
      // confirmed and picked_up, so moving an order to in_transit blanked the
      // driver's screen mid-delivery.
      expect(OrderStatus.driverHeld, contains(OrderStatus.inTransit));
      expect(OrderStatus.driverHeld, [
        OrderStatus.confirmed,
        OrderStatus.pickedUp,
        OrderStatus.inTransit,
      ]);
    });

    test('active and terminal partition the canonical set', () {
      expect({...OrderStatus.active, ...OrderStatus.terminal},
          OrderStatus.all.toSet());
      expect(
        OrderStatus.active.toSet().intersection(OrderStatus.terminal.toSet()),
        isEmpty,
      );
    });

    test('driverHeld is a subset of active', () {
      expect(
        OrderStatus.driverHeld.toSet().difference(OrderStatus.active.toSet()),
        isEmpty,
      );
    });

    test('pending is active but not driver-held', () {
      expect(OrderStatus.isActive(OrderStatus.pending), isTrue);
      expect(OrderStatus.isDriverHeld(OrderStatus.pending), isFalse);
    });

    test('membership helpers agree with their lists', () {
      for (final s in OrderStatus.all) {
        expect(OrderStatus.isActive(s), OrderStatus.active.contains(s));
        expect(OrderStatus.isDriverHeld(s), OrderStatus.driverHeld.contains(s));
        expect(OrderStatus.isTerminal(s), OrderStatus.terminal.contains(s));
      }
    });
  });

  group('canTransition', () {
    test('accepts every legal edge', () {
      for (final (from, to) in legal) {
        expect(OrderStatus.canTransition(from, to), isTrue,
            reason: '$from -> $to should be legal');
      }
    });

    test('rejects every edge not in the legal set', () {
      for (final from in OrderStatus.all) {
        for (final to in OrderStatus.all) {
          final isLegal = legal.contains((from, to));
          expect(OrderStatus.canTransition(from, to), isLegal,
              reason: '$from -> $to');
        }
      }
    });

    test('terminal states have no way out', () {
      for (final terminal in [OrderStatus.delivered, OrderStatus.cancelled]) {
        for (final to in OrderStatus.all) {
          expect(OrderStatus.canTransition(terminal, to), isFalse,
              reason: '$terminal -> $to must be rejected');
        }
        expect(OrderStatus.transitions[terminal], isEmpty);
      }
    });

    test('no status can transition to itself', () {
      for (final s in OrderStatus.all) {
        expect(OrderStatus.canTransition(s, s), isFalse, reason: s);
      }
    });

    test('the lifecycle never runs backwards', () {
      // delivered -> pending was writable before this landed.
      expect(OrderStatus.canTransition(OrderStatus.delivered, OrderStatus.pending),
          isFalse);
      expect(OrderStatus.canTransition(OrderStatus.inTransit, OrderStatus.pickedUp),
          isFalse);
      expect(OrderStatus.canTransition(OrderStatus.confirmed, OrderStatus.pending),
          isFalse);
    });

    test('unknown statuses cannot transition in either direction', () {
      expect(OrderStatus.canTransition('accepted', OrderStatus.confirmed), isFalse);
      expect(OrderStatus.canTransition('', OrderStatus.pending), isFalse);
      expect(OrderStatus.canTransition(OrderStatus.pending, 'accepted'), isFalse);
      expect(OrderStatus.canTransition(OrderStatus.pending, 'nonsense'), isFalse);
    });

    test('every canonical status is reachable from pending', () {
      // Walk the happy path plus the cancel branch; nothing should be orphaned.
      final seen = <String>{OrderStatus.pending};
      final queue = <String>[OrderStatus.pending];
      while (queue.isNotEmpty) {
        final next = OrderStatus.transitions[queue.removeAt(0)] ?? const [];
        for (final s in next) {
          if (seen.add(s)) queue.add(s);
        }
      }
      expect(seen, OrderStatus.all.toSet());
    });
  });

  group('step', () {
    test('advances one index per forward transition', () {
      expect(OrderStatus.step(OrderStatus.pending), 0);
      expect(OrderStatus.step(OrderStatus.confirmed), 1);
      expect(OrderStatus.step(OrderStatus.pickedUp), 2);
      expect(OrderStatus.step(OrderStatus.inTransit), 3);
      expect(OrderStatus.step(OrderStatus.delivered), 4);
    });

    test('cancelled is -1, not a step on the happy path', () {
      // Callers must branch on this. A negative widthFactor throws.
      expect(OrderStatus.step(OrderStatus.cancelled), -1);
    });

    test('unknown statuses fall back to 0 rather than throwing', () {
      for (final s in ['accepted', '', 'nonsense']) {
        expect(OrderStatus.step(s), 0, reason: '"$s"');
      }
    });

    test('every non-cancelled status maps into the tracker', () {
      for (final s in OrderStatus.all) {
        final i = OrderStatus.step(s);
        if (s == OrderStatus.cancelled) continue;
        expect(i, greaterThanOrEqualTo(0), reason: s);
        expect(i, lessThan(OrderStatus.stepCount), reason: s);
      }
    });

    test('stepCount matches the number of happy-path steps', () {
      final steps = OrderStatus.all
          .where((s) => s != OrderStatus.cancelled)
          .map(OrderStatus.step)
          .toSet();
      expect(steps, hasLength(OrderStatus.stepCount));
    });
  });

  group('label', () {
    test('every canonical status has a human label', () {
      for (final s in OrderStatus.all) {
        final l = OrderStatus.label(s);
        expect(l, isNotEmpty, reason: s);
        // The raw value must never leak to the UI — "picked_up" reached the
        // customer's order list this way.
        expect(l, isNot(equals(s)), reason: s);
        expect(l, isNot(contains('_')), reason: s);
      }
    });

    test('labels are distinct', () {
      final labels = OrderStatus.all.map(OrderStatus.label).toSet();
      expect(labels, hasLength(OrderStatus.all.length));
    });

    test('unknown statuses get a neutral fallback, never the raw string', () {
      for (final s in ['accepted', '', 'nonsense']) {
        expect(OrderStatus.label(s), 'Processing', reason: '"$s"');
      }
    });
  });
}
