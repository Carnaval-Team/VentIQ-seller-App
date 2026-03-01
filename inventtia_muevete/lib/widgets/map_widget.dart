import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';

class MapWidget extends StatelessWidget {
  final MapController? mapController;
  final LatLng center;
  final double zoom;
  final double initialRotation;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final void Function(TapPosition, LatLng)? onTap;
  final bool isDark;

  /// Perspective tilt factor: 0.0 = flat, 1.0 = max tilt (~60°).
  final double perspectiveTilt;

  const MapWidget({
    super.key,
    this.mapController,
    required this.center,
    this.zoom = 14.0,
    this.initialRotation = 0.0,
    this.markers = const [],
    this.polylines = const [],
    this.onTap,
    this.isDark = true,
    this.perspectiveTilt = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final tileUrl =
        isDark ? AppTheme.cartoDarkTileUrl : AppTheme.osmTileUrl;

    Widget map = FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        initialRotation: initialRotation,
        onTap: onTap,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.inventtia.muevete',
          tileProvider: kIsWeb
              ? null
              : fmtc.FMTCTileProvider(
                  stores: const {'mapTiles': fmtc.BrowseStoreStrategy.readUpdate},
                ),
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

    // Apply 3D perspective tilt if requested
    if (perspectiveTilt > 0.0) {
      final tiltAngle = perspectiveTilt * -0.6;
      map = ClipRect(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(tiltAngle)
            ..scale(1.45, 1.45),
          child: map,
        ),
      );
    }

    return map;
  }
}
