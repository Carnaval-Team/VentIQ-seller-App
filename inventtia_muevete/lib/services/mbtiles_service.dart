import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Custom provider that wraps MbTiles directly with proper gzip handling
/// and debug logging.
class DebugMbTilesVectorTileProvider extends VectorTileProvider {
  final MbTiles mbtiles;

  @override
  final int minimumZoom;
  @override
  final int maximumZoom;

  DebugMbTilesVectorTileProvider({required this.mbtiles})
      : minimumZoom = mbtiles.getMetadata().minZoom?.truncate() ?? 0,
        maximumZoom = mbtiles.getMetadata().maxZoom?.truncate() ?? 14;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final tmsY = ((1 << tile.z) - 1) - tile.y;

    // Read raw bytes (gzip: false to get untouched data)
    final stmt = mbtiles.getMetadata(); // just to confirm connection
    // Access the raw database through getTile (which with gzip:true auto-decompresses)
    final bytes = mbtiles.getTile(z: tile.z, x: tile.x, y: tmsY);

    if (bytes == null) {
      print('[MBTiles] MISS z=${tile.z} x=${tile.x} y=${tile.y} (tmsY=$tmsY)');
      throw ProviderException(
        message: 'Tile not found: ${tile.z}/${tile.x}/${tile.y}',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }

    print('[MBTiles] HIT z=${tile.z} x=${tile.x} y=${tile.y} len=${bytes.length} first4=${bytes.take(4).toList()}');

    // Check if still gzip-compressed (shouldn't be if gzip:true is working)
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      print('[MBTiles] WARNING: tile still gzip-compressed! Decompressing manually...');
      final decompressed = gzip.decode(bytes);
      return Uint8List.fromList(decompressed);
    }

    return Uint8List.fromList(bytes);
  }
}

class MbTilesService {
  MbTilesService._();
  static final MbTilesService instance = MbTilesService._();

  static const _prefKey = 'use_offline_map';
  static const _assetPath = 'assets/tiles/cuba.mbtiles';

  DebugMbTilesVectorTileProvider? _provider;
  MbTiles? _mbtiles;
  late SharedPreferences _prefs;
  String? _filePath;

  bool get useOffline => _prefs.getBool(_prefKey) ?? false;
  bool get isAvailable => _filePath != null && File(_filePath!).existsSync();
  DebugMbTilesVectorTileProvider? get provider => _provider;

  /// Bump this number whenever you replace the asset file to force re-copy.
  static const _assetVersion = 2;
  static const _versionKey = 'mbtiles_asset_version';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/cuba.mbtiles');

    final cachedVersion = _prefs.getInt(_versionKey) ?? 0;
    if (!dest.existsSync() || cachedVersion < _assetVersion) {
      try {
        final data = await rootBundle.load(_assetPath);
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await _prefs.setInt(_versionKey, _assetVersion);
        print('[MBTiles] Asset copied (v$_assetVersion), size=${dest.lengthSync()}');
      } catch (e) {
        print('[MBTiles] Asset copy failed: $e');
        return;
      }
    }

    _filePath = dest.path;
    print('[MBTiles] File ready at $_filePath, size=${dest.lengthSync()}');

    if (useOffline) {
      _openProvider();
    }
  }

  void _openProvider() {
    if (_filePath == null) return;
    _closeProvider();

    // Use gzip: true so getTile() auto-decompresses
    _mbtiles = MbTiles(mbtilesPath: _filePath!, gzip: true);
    final meta = _mbtiles!.getMetadata();
    print('[MBTiles] Opened: name=${meta.name}, format=${meta.format}, zoom=${meta.minZoom}-${meta.maxZoom}');

    _provider = DebugMbTilesVectorTileProvider(mbtiles: _mbtiles!);
    print('[MBTiles] Provider created, minZoom=${_provider!.minimumZoom}, maxZoom=${_provider!.maximumZoom}');
  }

  void _closeProvider() {
    _mbtiles?.dispose();
    _mbtiles = null;
    _provider = null;
  }

  Future<void> toggleOffline(bool value) async {
    await _prefs.setBool(_prefKey, value);
    if (value && isAvailable) {
      _openProvider();
    } else {
      _closeProvider();
    }
  }

  void dispose() {
    _closeProvider();
  }
}
