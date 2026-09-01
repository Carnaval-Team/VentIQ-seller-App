import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;
import 'package:mbtiles/mbtiles.dart';

/// Shared cache for map tile providers.
///
/// Online and offline tile providers are expensive to create. Keeping a single
/// instance and reusing it across every [FlutterMap] in the app avoids
/// recreating the network/cache machinery every time the user navigates.
class MapTileProviderCache {
  MapTileProviderCache._();
  static final instance = MapTileProviderCache._();

  TileProvider? _onlineProvider;
  MbTiles? _offlineMbTiles;
  String? _offlinePath;

  /// Returns the shared online tile provider (with FMTC cache).
  /// Safe to use on web (returns a [NetworkTileProvider] there).
  TileProvider get onlineProvider {
    if (kIsWeb) return NetworkTileProvider();
    _onlineProvider ??= fmtc.FMTCTileProvider(
      stores: const {'mapTiles': fmtc.BrowseStoreStrategy.readUpdate},
    );
    return _onlineProvider!;
  }

  /// Clears the online provider in case the cache store is reset.
  void clearOnlineProvider() {
    _onlineProvider = null;
  }

  /// Opens and keeps a single [MbTiles] instance for the given path.
  /// The same instance is reused while the path stays the same.
  MbTiles offlineMbTiles(String path) {
    if (_offlinePath == path && _offlineMbTiles != null) {
      return _offlineMbTiles!;
    }
    _offlinePath = path;
    _offlineMbTiles?.dispose();
    _offlineMbTiles = MbTiles(mbtilesPath: path, gzip: true);
    return _offlineMbTiles!;
  }

  void dispose() {
    _offlineMbTiles?.dispose();
    _offlineMbTiles = null;
    _offlinePath = null;
    _onlineProvider = null;
  }
}
