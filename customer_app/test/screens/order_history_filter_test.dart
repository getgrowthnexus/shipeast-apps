import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/order_status.dart';

/// Order-history tab filtering (P1-04).
///
/// The regression: the filter matched 'pending', 'accepted' and 'in_transit'.
/// Two of those were never written by any app, and the two that *are* written
/// during a delivery — 'confirmed' and 'picked_up' — matched no tab at all. An
/// order therefore disappeared from the customer's list for the entire
/// delivery, the exact window they are most likely to open it.
///
/// This mirrors the screen's filter predicate rather than pumping the widget,
/// which would need Firebase. The predicate is the part that was wrong.
bool _matches(String tab, String status) => switch (tab) {
      'Active' => OrderStatus.isActive(status),
      'Completed' => status == OrderStatus.delivered,
      'Cancelled' => status == OrderStatus.cancelled,
      _ => false,
    };

void main() {
  const tabs = ['Active', 'Completed', 'Cancelled'];

  test('every canonical status matches exactly one tab', () {
    for (final status in OrderStatus.all) {
      final matched = tabs.where((t) => _matches(t, status)).toList();
      expect(matched, hasLength(1),
          reason: '"$status" matched $matched — must be exactly one tab');
    }
  });

  test('the statuses that used to vanish now appear under Active', () {
    for (final status in [OrderStatus.confirmed, OrderStatus.pickedUp]) {
      expect(_matches('Active', status), isTrue, reason: status);
    }
  });

  test('in_transit appears under Active', () {
    expect(_matches('Active', OrderStatus.inTransit), isTrue);
  });

  test('terminal statuses are not Active', () {
    expect(_matches('Active', OrderStatus.delivered), isFalse);
    expect(_matches('Active', OrderStatus.cancelled), isFalse);
  });

  test('delivered is Completed only; cancelled is Cancelled only', () {
    expect(_matches('Completed', OrderStatus.delivered), isTrue);
    expect(_matches('Cancelled', OrderStatus.delivered), isFalse);
    expect(_matches('Cancelled', OrderStatus.cancelled), isTrue);
    expect(_matches('Completed', OrderStatus.cancelled), isFalse);
  });

  test('the tab counts sum to the total number of statuses', () {
    final total = tabs
        .map((t) => OrderStatus.all.where((s) => _matches(t, s)).length)
        .fold(0, (a, b) => a + b);
    expect(total, OrderStatus.all.length);
  });

  test('an unknown status matches no tab rather than defaulting to Active', () {
    // A legacy 'accepted' row should not be silently presented as a live order.
    for (final s in ['accepted', '', 'nonsense']) {
      expect(tabs.where((t) => _matches(t, s)), isEmpty, reason: '"$s"');
    }
  });

  group('badge label', () {
    test('names the actual state, never the coarse bucket or raw value', () {
      expect(OrderStatus.label(OrderStatus.pickedUp), 'Order Picked Up');
      expect(OrderStatus.label(OrderStatus.inTransit), 'On the Way');
      expect(OrderStatus.label(OrderStatus.confirmed), 'Driver Assigned');
    });

    test('never leaks a raw database value to the UI', () {
      for (final s in [...OrderStatus.all, 'accepted', '', 'nonsense']) {
        expect(OrderStatus.label(s), isNot(contains('_')), reason: '"$s"');
      }
    });
  });
}
