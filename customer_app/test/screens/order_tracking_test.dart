import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/order_status.dart';

/// Customer live-tracking behaviour (P1-03).
///
/// The plan calls this "the single most important test in the project — it is
/// the regression that broke the product."
///
/// The regression: `_currentStep` mapped 'pending', 'accepted', 'in_transit',
/// 'delivered'. Two of those were never written by any app. So from the moment
/// a driver accepted until delivery, the tracker sat frozen on step 0 —
/// "Order Confirmed", ETA "~40 min" — while the driver collected the food and
/// drove it across town. Then it jumped straight to the final step.
///
/// These assert the step/label mapping rather than pumping the widget, which
/// would require Firebase. The mapping is what was wrong.
void main() {
  group('the tracker advances once per transition', () {
    test('each forward step increments the index by exactly one', () {
      const happyPath = [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.pickedUp,
        OrderStatus.inTransit,
        OrderStatus.delivered,
      ];

      for (var i = 0; i < happyPath.length; i++) {
        expect(OrderStatus.step(happyPath[i]), i,
            reason: '${happyPath[i]} should be step $i');
      }
    });

    test('the statuses that used to freeze the tracker now advance it', () {
      // Both previously fell to the `default: return 0` branch.
      expect(OrderStatus.step(OrderStatus.confirmed), greaterThan(0));
      expect(OrderStatus.step(OrderStatus.pickedUp), greaterThan(0));
    });

    test('every happy-path status maps to a distinct step', () {
      final steps = OrderStatus.all
          .where((s) => s != OrderStatus.cancelled)
          .map(OrderStatus.step)
          .toList();
      expect(steps.toSet(), hasLength(steps.length));
    });

    test('the walk from pending to delivered visits every step exactly once', () {
      var status = OrderStatus.pending;
      final visited = <int>[OrderStatus.step(status)];

      while (status != OrderStatus.delivered) {
        // Follow the non-cancelling branch.
        final next = OrderStatus.transitions[status]!
            .firstWhere((s) => s != OrderStatus.cancelled);
        status = next;
        visited.add(OrderStatus.step(status));
      }

      expect(visited, [0, 1, 2, 3, 4]);
    });
  });

  group('step count and the stepper widget contract', () {
    test('stepCount matches the number of rendered rows', () {
      // _buildStepper does List.generate(OrderStatus.stepCount, ...) and
      // _stepNames / _stepIcons must line up with it, or the row builder
      // range-errors.
      expect(OrderStatus.stepCount, 5);
    });

    test('the delivered check used by build() is the final index', () {
      expect(OrderStatus.step(OrderStatus.delivered),
          OrderStatus.stepCount - 1);
    });

    test('the route-bar fraction stays within 0..1 for every happy status', () {
      for (final s in OrderStatus.all) {
        if (s == OrderStatus.cancelled) continue;
        final progress = OrderStatus.step(s) / (OrderStatus.stepCount - 1);
        expect(progress, inInclusiveRange(0.0, 1.0), reason: s);
      }
    });
  });

  group('cancelled is a terminal state, not a frozen step', () {
    test('step() returns -1 rather than folding to 0', () {
      // Folding to 0 is what made a cancelled order display "Order Confirmed".
      expect(OrderStatus.step(OrderStatus.cancelled), -1);
      expect(OrderStatus.step(OrderStatus.cancelled),
          isNot(OrderStatus.step(OrderStatus.pending)));
    });

    test('a negative step would produce an invalid width factor', () {
      // Documents why build() must branch before reaching _routeBar:
      // FractionallySizedBox asserts widthFactor >= 0.
      final progress =
          OrderStatus.step(OrderStatus.cancelled) / (OrderStatus.stepCount - 1);
      expect(progress, lessThan(0));
    });

    test('cancelled has its own label, not a step name', () {
      expect(OrderStatus.label(OrderStatus.cancelled), 'Cancelled');
    });
  });

  group('labels', () {
    test('every status the hero can display has a human label', () {
      for (final s in OrderStatus.all) {
        expect(OrderStatus.label(s), isNotEmpty, reason: s);
        expect(OrderStatus.label(s), isNot(contains('_')), reason: s);
      }
    });

    test('an unknown or legacy status degrades to a neutral label', () {
      // A legacy 'accepted' row must not crash or show a raw value.
      expect(OrderStatus.label('accepted'), 'Processing');
      expect(OrderStatus.step('accepted'), 0);
    });

    test('the hero label distinguishes assignment from placement', () {
      // The old screen showed "Order Confirmed" for both, which is why the
      // customer could not tell whether a driver had actually accepted.
      expect(OrderStatus.label(OrderStatus.pending),
          isNot(OrderStatus.label(OrderStatus.confirmed)));
    });
  });
}
