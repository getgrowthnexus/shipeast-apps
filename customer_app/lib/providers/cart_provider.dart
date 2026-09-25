import 'package:flutter/foundation.dart';

class CartItem {
  final String id;
  final String name;
  final String description;
  final int price;
  final String imageUrl;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.imageUrl = '',
    required this.quantity,
  });
}

class CartProvider extends ChangeNotifier {
  String _merchantId = '';
  String _merchantName = '';
  int _deliveryFeeAmount = 0;
  final Map<String, CartItem> _items = {};

  String get merchantId => _merchantId;
  String get merchantName => _merchantName;
  int get deliveryFeeAmount => _deliveryFeeAmount;
  Map<String, CartItem> get items => Map.unmodifiable(_items);

  int get cartCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);

  int get cartTotal =>
      _items.values.fold(0, (sum, item) => sum + item.price * item.quantity);

  List<CartItem> get itemList => _items.values.toList();

  void setMerchant(String id, String name, int fee) {
    _merchantId = id;
    _merchantName = name;
    _deliveryFeeAmount = fee;
    notifyListeners();
  }

  void addItem(CartItem item) {
    if (_items.containsKey(item.id)) {
      _items[item.id]!.quantity++;
    } else {
      _items[item.id] = item;
    }
    notifyListeners();
  }

  void removeItem(String itemId) {
    final qty = _items[itemId]?.quantity ?? 0;
    if (qty > 1) {
      _items[itemId]!.quantity--;
    } else {
      _items.remove(itemId);
    }
    notifyListeners();
  }

  void removeItemCompletely(String itemId) {
    _items.remove(itemId);
    notifyListeners();
  }

  void incrementItem(String itemId) {
    if (_items.containsKey(itemId)) {
      _items[itemId]!.quantity++;
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    _merchantId = '';
    _merchantName = '';
    _deliveryFeeAmount = 0;
    notifyListeners();
  }

  List<Map<String, dynamic>> toOrderItems() {
    return _items.values
        .map((i) => {
              'id': i.id,
              'name': i.name,
              'description': i.description,
              'price': i.price,
              'quantity': i.quantity,
              'imageUrl': i.imageUrl,
            })
        .toList();
  }
}
