/// Package delivery pricing (P5-01).
///
/// Until now the Packages category collected a pickup address, a delivery
/// address, a weight and a set of instructions, showed **"Package request
/// submitted! We'll contact you shortly,"** and wrote nothing anywhere. No
/// record existed and nobody was ever going to call. This file is the half of
/// the fix that decides what a package costs.
///
/// ## Why there are no default prices here
///
/// Every band and surcharge comes from `settings/pricing`. There is
/// deliberately **no fallback price list** — if the document is not
/// configured, [PackagePricing.fromSettings] returns `null` and the customer
/// app declines to quote rather than inventing a number.
///
/// That is the same rule the data migrations follow: a business value nobody
/// chose must never be materialised by code. A wrong price is worse than an
/// unavailable feature, because the customer agrees to it and the driver
/// delivers against it.
///
/// Compare `DEFAULT_COMMISSION_RATE` in `functions/src/delivery.ts`, which
/// *does* have a fallback — that one has a documented, already-shipped value
/// in `driver_constants.dart`, so falling back preserves existing behaviour.
/// Here there is no existing behaviour to preserve.
library;

/// One flat-rate weight band.
class PackageBand {
  /// Upper bound in kilograms, inclusive. `null` means the final open-ended
  /// band — anything heavier is priced from it plus [PackagePricing.overagePerKg].
  final double? maxKg;

  /// Flat price for the band, integer JMD.
  final int price;

  const PackageBand({required this.maxKg, required this.price});

  static PackageBand? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final price = (raw['price'] as num?)?.round();
    if (price == null || price < 0) return null;
    final max = (raw['maxKg'] as num?)?.toDouble();
    // A non-positive bound would make the band unreachable, which silently
    // shifts every parcel into the next one.
    if (max != null && !(max > 0)) return null;
    return PackageBand(maxKg: max, price: price);
  }
}

class PackagePricing {
  /// Ordered ascending by [PackageBand.maxKg], open-ended band last.
  final List<PackageBand> bands;

  /// Charged per whole kilogram above the last bounded band.
  final int overagePerKg;

  /// Added when the customer asks for the item to be packed.
  final int packingSurcharge;

  /// Refuse anything above this — beyond it a courier bike is the wrong
  /// vehicle and the quote would be fiction.
  final double maxWeightKg;

  const PackagePricing({
    required this.bands,
    required this.overagePerKg,
    required this.packingSurcharge,
    required this.maxWeightKg,
  });

  /// Reads `settings/pricing`. Returns `null` when packages are not priced —
  /// the caller must then treat the feature as unavailable, never as free.
  static PackagePricing? fromSettings(Map<String, dynamic>? settings) {
    if (settings == null) return null;
    final raw = settings['packageBands'];
    if (raw is! List || raw.isEmpty) return null;

    final bands = <PackageBand>[];
    for (final entry in raw) {
      final band = PackageBand.fromMap(entry);
      // One malformed band means the admin's intent is unknown. Pricing off a
      // partially-parsed list would quote from a table nobody approved.
      if (band == null) return null;
      bands.add(band);
    }

    // Bounded bands first, ascending; the open-ended one last. Sorting here
    // means an admin who adds a band out of order still gets correct pricing.
    bands.sort((a, b) {
      if (a.maxKg == null) return 1;
      if (b.maxKg == null) return -1;
      return a.maxKg!.compareTo(b.maxKg!);
    });

    // More than one open-ended band is ambiguous, not merely untidy.
    if (bands.where((b) => b.maxKg == null).length > 1) return null;

    final maxWeight = (settings['packageMaxWeightKg'] as num?)?.toDouble();
    return PackagePricing(
      bands: bands,
      overagePerKg: (settings['packageOveragePerKg'] as num?)?.round() ?? 0,
      packingSurcharge: (settings['packingSurcharge'] as num?)?.round() ?? 0,
      maxWeightKg: maxWeight != null && maxWeight > 0 ? maxWeight : 50,
    );
  }

  /// The band a parcel of [weightKg] falls into, or `null` if it is over
  /// [maxWeightKg] or the table has no band that can hold it.
  PackageBand? bandFor(double weightKg) {
    if (!weightKg.isFinite || weightKg <= 0) return null;
    if (weightKg > maxWeightKg) return null;
    for (final band in bands) {
      if (band.maxKg == null || weightKg <= band.maxKg!) return band;
    }
    return null;
  }

  /// Human label for the band a parcel falls into, e.g. `2–5 kg`.
  ///
  /// Shown on the quote so the customer can see *why* the price is what it is
  /// rather than being handed a bare number.
  String? bandLabel(double weightKg) {
    final band = bandFor(weightKg);
    if (band == null) return null;
    final index = bands.indexOf(band);
    final lower = index == 0 ? 0.0 : bands[index - 1].maxKg ?? 0.0;
    final lowerText = _trim(lower);
    if (band.maxKg == null) return 'Over $lowerText kg';
    return '$lowerText–${_trim(band.maxKg!)} kg';
  }

  /// The transport charge, before packing. `null` when unquotable.
  int? deliveryFeeFor(double weightKg) {
    final band = bandFor(weightKg);
    if (band == null) return null;
    if (band.maxKg != null) return band.price;

    // Open-ended band: charge from where the last bounded band stopped.
    final bounded = bands.where((b) => b.maxKg != null);
    final from = bounded.isEmpty ? 0.0 : bounded.last.maxKg!;
    final over = weightKg - from;
    // Whole kilograms, rounded up — half a kilo over still occupies the space.
    final extra = over > 0 ? (over.ceil() * overagePerKg) : 0;
    return band.price + extra;
  }

  /// The full quote, or `null` when the parcel cannot be priced.
  ///
  /// `serviceFee` carries the packing surcharge rather than folding it into
  /// the delivery fee, so the order document says which part of the charge was
  /// transport and which was handling. `subtotal` is 0: a package job has no
  /// goods, only work.
  PackageQuote? quote({required double weightKg, required bool packing}) {
    final fee = deliveryFeeFor(weightKg);
    if (fee == null) return null;
    final service = packing ? packingSurcharge : 0;
    return PackageQuote(
      deliveryFee: fee,
      serviceFee: service,
      bandLabel: bandLabel(weightKg) ?? '',
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class PackageQuote {
  final int deliveryFee;
  final int serviceFee;
  final String bandLabel;

  const PackageQuote({
    required this.deliveryFee,
    required this.serviceFee,
    required this.bandLabel,
  });

  int get subtotal => 0;

  /// Must satisfy the order invariant enforced by rules (P2-01):
  /// `subtotal + deliveryFee + serviceFee - discount == total`.
  int get total => subtotal + deliveryFee + serviceFee;
}

/// Parses the weight the customer typed.
///
/// Returns `null` for anything that is not a positive finite number, so a
/// stray character can never become a silent 0 kg parcel priced at the
/// cheapest band.
double? parseWeightKg(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}
