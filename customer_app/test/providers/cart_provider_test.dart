import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/providers/cart_provider.dart';

/// Cart arithmetic.
///
/// This file replaces `test/widget_test.dart`, which pumped `ShipEastApp()`
/// without initialising Firebase. That test could never have passed — the
/// splash screen reaches `FirebaseAuth.instance` on its first frame — and it
/// only ever appeared green because CI never ran it. It was removed rather
/// than repaired: pumping the whole app is an integration concern, and
/// mocking Firebase to assert nothing in particular is not coverage.
///
/// `CartProvider` is pure Dart with no Firebase dependency, and it computes
/// the money that reaches the order document, so it is worth far more per line.
/// Listed as a P6-01 priority ("Cart arithmetic — currently untested").
CartItem _item(String id, {int price = 100, int quantity = 1}) =>
    CartItem(id: id, name: 'Item $id', price: price, quantity: quantity);

void main() {
  late CartProvider cart;

  setUp(() => cart = CartProvider());

  group('empty cart', () {
    test('starts empty with zeroed totals', () {
      expect(cart.itemList, isEmpty);
      expect(cart.cartCount, 0);
      expect(cart.cartTotal, 0);
      expect(cart.merchantId, '');
      expect(cart.deliveryFeeAmount, 0);
    });

    test('removing from an empty cart is a no-op, not an error', () {
      cart.removeItem('nope');
      cart.removeItemCompletely('nope');
      cart.incrementItem('nope');
      expect(cart.cartCount, 0);
    });
  });

  group('addItem', () {
    test('adds a new item', () {
      cart.addItem(_item('a', price: 250, quantity: 2));
      expect(cart.cartCount, 2);
      expect(cart.cartTotal, 500);
    });

    test('adding an existing id increments by one, ignoring its quantity', () {
      // Pinning real behaviour: the incoming item's quantity is discarded on a
      // duplicate. Worth asserting because it is surprising — a caller passing
      // quantity: 5 for an id already in the cart adds 1, not 5.
      cart.addItem(_item('a', price: 100, quantity: 1));
      cart.addItem(_item('a', price: 100, quantity: 5));
      expect(cart.cartCount, 2);
      expect(cart.cartTotal, 200);
    });

    test('tracks distinct items separately', () {
      cart.addItem(_item('a', price: 100));
      cart.addItem(_item('b', price: 250));
      expect(cart.itemList, hasLength(2));
      expect(cart.cartCount, 2);
      expect(cart.cartTotal, 350);
    });
  });

  group('totals', () {
    test('cartTotal multiplies price by quantity across items', () {
      cart.addItem(_item('a', price: 1200, quantity: 2)); // 2400
      cart.addItem(_item('b', price: 350, quantity: 3)); //  1050
      expect(cart.cartCount, 5);
      expect(cart.cartTotal, 3450);
    });

    test('handles a zero-price item without corrupting the total', () {
      cart.addItem(_item('free', price: 0, quantity: 3));
      cart.addItem(_item('paid', price: 500, quantity: 1));
      expect(cart.cartCount, 4);
      expect(cart.cartTotal, 500);
    });

    test('totals stay integral — money is never a double (SCHEMA.md §a)', () {
      cart.addItem(_item('a', price: 333, quantity: 3));
      expect(cart.cartTotal, isA<int>());
      expect(cart.cartTotal, 999);
    });
  });

  group('removeItem', () {
    test('decrements when more than one remains', () {
      cart.addItem(_item('a', price: 100, quantity: 3));
      cart.removeItem('a');
      expect(cart.cartCount, 2);
      expect(cart.itemList, hasLength(1));
    });

    test('drops the item entirely at the last unit', () {
      cart.addItem(_item('a', price: 100, quantity: 1));
      cart.removeItem('a');
      expect(cart.itemList, isEmpty);
      expect(cart.cartTotal, 0);
    });

    test('removeItemCompletely drops every unit at once', () {
      cart.addItem(_item('a', price: 100, quantity: 9));
      cart.removeItemCompletely('a');
      expect(cart.itemList, isEmpty);
      expect(cart.cartCount, 0);
    });
  });

  group('incrementItem', () {
    test('increments an item already in the cart', () {
      cart.addItem(_item('a', price: 100));
      cart.incrementItem('a');
      expect(cart.cartCount, 2);
      expect(cart.cartTotal, 200);
    });

    test('does not create an item that is not in the cart', () {
      cart.incrementItem('ghost');
      expect(cart.itemList, isEmpty);
    });
  });

  group('merchant', () {
    test('setMerchant records the id, name, and delivery fee', () {
      cart.setMerchant('m1', 'Island Jerk Palace', 250);
      expect(cart.merchantId, 'm1');
      expect(cart.merchantName, 'Island Jerk Palace');
      expect(cart.deliveryFeeAmount, 250);
    });

    test('clearCart resets items and merchant together', () {
      cart.setMerchant('m1', 'Island Jerk Palace', 250);
      cart.addItem(_item('a', price: 100, quantity: 2));
      cart.clearCart();

      expect(cart.itemList, isEmpty);
      expect(cart.cartTotal, 0);
      // The delivery fee must reset with the merchant. If it survived, the next
      // order could be charged the previous merchant's fee.
      expect(cart.merchantId, '');
      expect(cart.merchantName, '');
      expect(cart.deliveryFeeAmount, 0);
    });
  });

  group('encapsulation', () {
    test('items map is unmodifiable', () {
      cart.addItem(_item('a'));
      expect(() => cart.items['b'] = _item('b'), throwsUnsupportedError);
    });
  });

  group('toOrderItems', () {
    test('is empty for an empty cart', () {
      expect(cart.toOrderItems(), isEmpty);
    });

    test('carries the fields the order document needs', () {
      cart.addItem(_item('a', price: 1200, quantity: 2));
      final items = cart.toOrderItems();

      expect(items, hasLength(1));
      // SCHEMA.md §OrderItem: name, price, quantity are what placeOrder writes.
      expect(items.single['name'], 'Item a');
      expect(items.single['price'], 1200);
      expect(items.single['quantity'], 2);
    });

    test('emits one entry per distinct item, not per unit', () {
      cart.addItem(_item('a', quantity: 3));
      cart.addItem(_item('b', quantity: 2));
      expect(cart.toOrderItems(), hasLength(2));
    });
  });

  group('change notification', () {
    test('every mutation notifies listeners', () {
      var notifications = 0;
      cart.addListener(() => notifications++);

      cart.setMerchant('m1', 'M', 250);
      cart.addItem(_item('a'));
      cart.incrementItem('a');
      cart.removeItem('a');
      cart.removeItemCompletely('a');
      cart.clearCart();

      // Six mutations; incrementItem/removeItem on a present item each notify.
      expect(notifications, 6);
    });

    test('a no-op increment does not notify', () {
      var notifications = 0;
      cart.addListener(() => notifications++);
      cart.incrementItem('ghost');
      expect(notifications, 0);
    });
  });
}
