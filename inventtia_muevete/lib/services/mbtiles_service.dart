import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

/// Custom provider that wraps MbTiles with proper gzip handling.
class OfflineVectorTileProvider extends VectorTileProvider {
  final MbTiles mbtiles;

  @override
  final int minimumZoom;
  @override
  final int maximumZoom;

  OfflineVectorTileProvider({required this.mbtiles})
      : minimumZoom = mbtiles.getMetadata().minZoom?.truncate() ?? 0,
        maximumZoom = mbtiles.getMetadata().maxZoom?.truncate() ?? 14;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final tmsY = ((1 << tile.z) - 1) - tile.y;
    final bytes = mbtiles.getTile(z: tile.z, x: tile.x, y: tmsY);

    if (bytes == null) {
      throw ProviderException(
        message: 'Tile not found: ${tile.z}/${tile.x}/${tile.y}',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }

    // Fallback: manual gzip decompress if still compressed
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      final decompressed = gzip.decode(bytes);
      return Uint8List.fromList(decompressed);
    }

    return Uint8List.fromList(bytes);
  }
}

class MbTilesService extends ChangeNotifier {
  MbTilesService._();
  static final MbTilesService instance = MbTilesService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const _prefKey = 'use_offline_map';
  static const _assetPath = 'assets/tiles/cuba.mbtiles';
  static const _brightStylePath =
      'assets/osm_offline_styles/osm-bright-gl-style/style.json';
  static const _darkStylePath =
      'assets/osm_offline_styles/dark-matter-gl-style/style.json';

  // Supabase remote storage
  static const _remoteBucket = 'muevete';
  static const _remotePath = 'maps/cuba.mbtiles';
  static const _remoteVersionKey = 'mbtiles_remote_version';

  OfflineVectorTileProvider? _provider;
  MbTiles? _mbtiles;
  late SharedPreferences _prefs;
  String? _filePath;

  Theme? _brightTheme;
  Theme? _darkTheme;

  bool get useOffline => _prefs.getBool(_prefKey) ?? false;
  bool get isAvailable => _filePath != null && File(_filePath!).existsSync();
  OfflineVectorTileProvider? get provider => _provider;

  int? get _localVersion => _prefs.getInt(_remoteVersionKey);

  Theme getTheme({required bool isDark}) {
    if (isDark && _darkTheme != null) return _darkTheme!;
    if (!isDark && _brightTheme != null) return _brightTheme!;
    return ProvidedThemes.lightTheme();
  }

  static const _assetVersion = 2;
  static const _versionKey = 'mbtiles_asset_version';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadThemes();

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
      } catch (_) {
        return;
      }
    }

    _filePath = dest.path;

    if (useOffline) {
      _openProvider();
    }
  }

  /// Uploads a local .mbtiles file to Supabase Storage and records the version.
  /// Use this from an admin tool to publish a new map.
  Future<void> uploadMbtilesToSupabase(
    String localFilePath, {
    int version = 1,
  }) async {
    final file = File(localFilePath);
    if (!file.existsSync()) {
      throw Exception('Local file not found: $localFilePath');
    }
    final bytes = await file.readAsBytes();

    await _supabase.storage.from(_remoteBucket).uploadBinary(
          _remotePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    try {
      await _supabase.schema('muevete').from('map_versions').upsert({
        'id': 1,
        'version': version,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[MBTiles] Could not record version in map_versions: $e');
    }
  }

  /// Downloads the .mbtiles file from Supabase Storage and stores it locally.
  Future<bool> downloadMbtilesFromSupabase() async {
    try {
      final bytes = await _supabase.storage
          .from(_remoteBucket)
          .download(_remotePath);

      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/cuba.mbtiles');
      await dest.writeAsBytes(bytes, flush: true);

      _filePath = dest.path;
      debugPrint('[MBTiles] Downloaded $_filePath (${bytes.length} bytes)');

      if (useOffline) {
        _openProvider();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[MBTiles] downloadMbtilesFromSupabase error: $e');
      return false;
    }
  }

  /// Checks the remote version stored in `muevete.map_versions` and downloads
  /// the map only when the remote version is newer than the local one.
  Future<bool> syncMbtilesFromSupabase() async {
    int remoteVersion = 0;
    try {
      final row = await _supabase
          .schema('muevete')
          .from('map_versions')
          .select('version')
          .eq('id', 1)
          .maybeSingle();
      remoteVersion = row?['version'] as int? ?? 0;
    } catch (e) {
      debugPrint('[MBTiles] Could not read remote version: $e');
      // Fallback: download if not available locally.
      if (!isAvailable) return downloadMbtilesFromSupabase();
      return true;
    }

    final localVersion = _localVersion ?? 0;
    if (remoteVersion > localVersion || !isAvailable) {
      final ok = await downloadMbtilesFromSupabase();
      if (ok) {
        await _prefs.setInt(_versionKey, remoteVersion);
      }
      return ok;
    }

    return true;
  }

  Future<void> _loadThemes() async {
    try {
      final brightJson = await rootBundle.loadString(_brightStylePath);
      final brightData = json.decode(brightJson) as Map<String, dynamic>;
      _brightTheme = ThemeReader().read(brightData);
    } catch (e) {
      debugPrint('[MBTiles] Could not load bright theme: $e');
    }
    try {
      final darkJson = await rootBundle.loadString(_darkStylePath);
      final darkData = json.decode(darkJson) as Map<String, dynamic>;
      _darkTheme = ThemeReader().read(darkData);
    } catch (e) {
      debugPrint('[MBTiles] Could not load dark theme: $e');
    }
  }

  void _openProvider() {
    if (_filePath == null) return;
    // Don't dispose old mbtiles — VectorTileLayer may still reference it.
    // Just create a fresh instance.
    _mbtiles = MbTiles(mbtilesPath: _filePath!, gzip: true);
    _provider = OfflineVectorTileProvider(mbtiles: _mbtiles!);
  }

  Future<void> toggleOffline(bool value) async {
    await _prefs.setBool(_prefKey, value);
    if (value && isAvailable) {
      _openProvider();
    } else {
      // Don't dispose the db — just clear the provider reference.
      // The old VectorTileLayer will be removed from the widget tree
      // and stop requesting tiles.
      _provider = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _mbtiles?.dispose();
    _mbtiles = null;
    _provider = null;
    super.dispose();
  }
}
