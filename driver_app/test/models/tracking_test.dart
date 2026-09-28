import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/models/order_status.dart';
import 'package:shipeast_driver/models/tracking.dart';

/// Live GPS tracking (client request, Sep 2026): the stage labels everyone
/// sees, and the distance / arrival maths behind them.
void main() {
  // Morant Bay courthouse → Yallahs: roughly 20 km along the coast.
  const morantBay = (17.8817, -76.4095);
  const yallahs = (17.8742, -76.5617);

  group('distanceM', () {
    test('is zero for the same point', () {
      expect(Tracking.distanceM(17.88, -76.41, 17.88, -76.41), 0);
    });

    test('Morant Bay to Yallahs is about 16 km in a straight line', () {
      final d = Tracking.distanceM(
          morantBay.$1, morantBay.$2, yallahs.$1, yallahs.$2);
      expect(d, inInclusiveRange(15000, 17500));
    });
  });

  group('hasArrived', () {
    test('within 150 m counts, beyond does not, no pin never does', () {
      // ~0.001° latitude ≈ 111 m.
      expect(Tracking.hasArrived(17.8817, -76.4095, 17.8827, -76.4095), isTrue);
      expect(Tracking.hasArrived(17.8817, -76.4095, 17.8847, -76.4095), isFalse);
      expect(Tracking.hasArrived(17.8817, -76.4095, null, null), isFalse);
    });
  });

  group('etaMinutes and distanceLabel', () {
    test('an honest rough estimate, never zero', () {
      expect(Tracking.etaMinutes(0), 1);
      expect(Tracking.etaMinutes(5000), inInclusiveRange(15, 18));
    });

    test('metres below a kilometre, kilometres above', () {
      expect(Tracking.distanceLabel(447), '450 m');
      expect(Tracking.distanceLabel(3240), '3.2 km');
    });
  });

  group('liveLabel', () {
    test('the driver leg to the restaurant', () {
      expect(Tracking.liveLabel(OrderStatus.confirmed, DriverStage.toPickup),
          'Driver on the way to the restaurant');
      expect(Tracking.liveLabel(OrderStatus.confirmed, DriverStage.atPickup),
          'Driver waiting at the restaurant');
      expect(
          Tracking.liveLabel(OrderStatus.confirmed, null, isPackage: true),
          'Driver on the way to the pickup');
    });

    test('the leg to the customer', () {
      expect(Tracking.liveLabel(OrderStatus.pickedUp, null), 'Order picked up');
      expect(Tracking.liveLabel(OrderStatus.inTransit, DriverStage.toDropoff),
          'On the way to you');
      expect(
          Tracking.liveLabel(OrderStatus.inTransit, DriverStage.toDropoff,
              metresToDropoff: 600),
          'Driver is nearby');
      expect(Tracking.liveLabel(OrderStatus.inTransit, DriverStage.atDropoff),
          'Driver has arrived');
    });

    test('no live line before a driver or after the end', () {
      expect(Tracking.liveLabel(OrderStatus.preparing, null), '');
      expect(Tracking.liveLabel(OrderStatus.delivered, DriverStage.atDropoff), '');
    });
  });
}
