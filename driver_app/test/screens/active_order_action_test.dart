import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/models/order_status.dart';

/// The driver's active-order action card (P1-05).
///
/// Two defects are pinned here.
///
/// 1. `activeOrderStream` filtered `whereIn: ['confirmed', 'picked_up']`. The
///    moment an order became `in_transit` it left that query and the driver's
///    dashboard blanked mid-delivery — goods already in the vehicle, no
///    customer address, no delivery button, no recovery path in the UI.
///
/// 2. There was no `in_transit` write at all. `picked_up` jumped straight to
///    delivery confirmation, so the customer's "On the Way" step was
///    unreachable: their tracker went from "Picked Up" to "Delivered" with no
///    signal the driver had set off.

/// Mirrors `_continueActiveOrder`'s dispatch.
String _action(String status) {
  if (status == OrderStatus.confirmed) return 'go-to-merchant';
  if (status == OrderStatus.pickedUp) return 'start-delivery';
  if (status == OrderStatus.inTransit) return 'confirm-delivery';
  return 'none';
}

void main() {
  group('activeOrderStream coverage', () {
    test('driverHeld includes in_transit', () {
      // The single-line fix for the mid-delivery blanking.
      expect(OrderStatus.driverHeld, contains(OrderStatus.inTransit));
    });

    test('every driver-held state has an action card', () {
      for (final s in OrderStatus.driverHeld) {
        expect(_action(s), isNot('none'),
            reason: '$s is in the active-order query but renders no action');
      }
    });

    test('every state with an action is in the query', () {
      // The converse: an action the query never delivers is dead code, and an
      // order stuck in it would be invisible to the driver holding it.
      for (final s in OrderStatus.all) {
        if (_action(s) != 'none') {
          expect(OrderStatus.driverHeld, contains(s), reason: s);
        }
      }
    });

    test('pending is not driver-held — it belongs to the available pool', () {
      expect(OrderStatus.driverHeld, isNot(contains(OrderStatus.pending)));
      expect(_action(OrderStatus.pending), 'none');
    });

    test('terminal states render no action', () {
      expect(_action(OrderStatus.delivered), 'none');
      expect(_action(OrderStatus.cancelled), 'none');
    });
  });

  group('the three-way action progression', () {
    test('each held state maps to a distinct action', () {
      final actions = OrderStatus.driverHeld.map(_action).toList();
      expect(actions, ['go-to-merchant', 'start-delivery', 'confirm-delivery']);
      expect(actions.toSet(), hasLength(3));
    });

    test('start-delivery is what makes in_transit reachable', () {
      expect(_action(OrderStatus.pickedUp), 'start-delivery');
      expect(OrderStatus.canTransition(
          OrderStatus.pickedUp, OrderStatus.inTransit), isTrue);
    });

    test('delivery can only be confirmed from in_transit', () {
      expect(_action(OrderStatus.inTransit), 'confirm-delivery');
      expect(OrderStatus.canTransition(
          OrderStatus.inTransit, OrderStatus.delivered), isTrue);
      // picked_up must go through in_transit first, so the customer sees it.
      expect(OrderStatus.canTransition(
          OrderStatus.pickedUp, OrderStatus.delivered), isFalse);
    });

    test('the driver walks the full lifecycle without a gap', () {
      var status = OrderStatus.pending;
      final path = <String>[status];
      while (status != OrderStatus.delivered) {
        status = OrderStatus.transitions[status]!
            .firstWhere((s) => s != OrderStatus.cancelled);
        path.add(status);
      }
      expect(path, [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.pickedUp,
        OrderStatus.inTransit,
        OrderStatus.delivered,
      ]);
    });
  });

  group('order claiming', () {
    test('a driver claims from pending into confirmed', () {
      expect(OrderStatus.canTransition(
          OrderStatus.pending, OrderStatus.confirmed), isTrue);
    });

    test('cancellation is reachable from every held state', () {
      // The driver may lose an order at any point they hold it.
      for (final s in OrderStatus.driverHeld) {
        expect(OrderStatus.canTransition(s, OrderStatus.cancelled), isTrue,
            reason: s);
      }
    });
  });
}
