import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';

class MapWidget extends StatelessWidget {
  final MapController? mapController;
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final void Function(TapPosition, LatLng)? onTap;
  final bool isDark;

  const MapWidget({
    super.key,
    this.mapController,
    required this.center,
    this.zoom = 14.0,
    this.markers = const [],
    this.polylines = const [],
    this.onTap,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final tileUrl =
        isDark ? AppTheme.cartoDarkTileUrl : AppTheme.osmTileUrl;

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onTap: onTap,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.inventtia.muevete',
        ),
        if (polylines.isNotEmpty)
          PolylineLayer(
            polylines: polylines,
          ),
        if (markers.isNotEmpty)
          MarkerLayer(
            markers: markers,
          ),
      ],
    );
  }
}
