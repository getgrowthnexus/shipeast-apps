import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';

/// The live delivery map (client request, Sep 2026): the driver, the pickup
/// and the drop-off on one map, updating as the driver moves.
///
/// OpenStreetMap tiles through flutter_map — no API key, no billing account,
/// and the same data the admin's Live Map (Leaflet) shows. Every point is
/// optional: an order without pins still shows the driver, and a driver with
/// no fix yet still shows where they are headed.
class SeLiveMap extends StatefulWidget {
  final LatLng? driver;
  final LatLng? pickup;
  final LatLng? dropoff;

  /// Whether the driver has already collected the order — the dashed line
  /// then runs driver → drop-off instead of driver → pickup.
  final bool towardsDropoff;
  final double height;

  const SeLiveMap({
    super.key,
    this.driver,
    this.pickup,
    this.dropoff,
    this.towardsDropoff = false,
    this.height = 220,
  });

  bool get hasAnything => driver != null || pickup != null || dropoff != null;

  @override
  State<SeLiveMap> createState() => _SeLiveMapState();
}

class _SeLiveMapState extends State<SeLiveMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _userMoved = false;

  List<LatLng> get _points => [
        if (widget.driver != null) widget.driver!,
        if (!widget.towardsDropoff && widget.pickup != null) widget.pickup!,
        if (widget.dropoff != null) widget.dropoff!,
      ];

  @override
  void didUpdateWidget(SeLiveMap old) {
    super.didUpdateWidget(old);
    // Follow the driver as they move, unless the customer has panned away.
    if (_ready && !_userMoved && widget.driver != old.driver) _fit();
  }

  void _fit() {
    final pts = _points;
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _controller.move(pts.first, 15);
      return;
    }
    _controller.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(48),
      maxZoom: 16,
    ));
  }

  Marker _pin(LatLng at, IconData icon, Color color) => Marker(
        point: at,
        width: 38,
        height: 38,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    final target = widget.towardsDropoff ? widget.dropoff : widget.pickup;
    return ClipRRect(
      borderRadius: SeRadius.all(SeRadius.md),
      child: SizedBox(
        height: widget.height,
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: pts.isNotEmpty
                ? pts.first
                : const LatLng(17.9712, -76.7928), // Kingston
            initialZoom: 14,
            onMapReady: () {
              _ready = true;
              _fit();
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture) _userMoved = true;
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.shipeast.customerapp',
            ),
            if (widget.driver != null && target != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: [widget.driver!, target],
                  color: SeColors.brandAction.withValues(alpha: 0.7),
                  strokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [8, 6]),
                ),
              ]),
            MarkerLayer(markers: [
              if (widget.pickup != null)
                _pin(widget.pickup!, SeIcons.storefront, SeColors.ink700),
              if (widget.dropoff != null)
                _pin(widget.dropoff!, SeIcons.home, SeColors.successInk),
              if (widget.driver != null)
                _pin(widget.driver!, SeIcons.bike, SeColors.brandAction),
            ]),
            // The tile licence requires the credit on the map itself.
            RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }
}
