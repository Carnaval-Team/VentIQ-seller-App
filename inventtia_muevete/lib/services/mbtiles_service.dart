import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mbtiles/mbtiles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

import '../models/offline_map_source.dart';

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

/// Resultado de importar o descargar una fuente de mapa.
@immutable
class OfflineMapOperationResult {
  final bool ok;
  final String? message;

  const OfflineMapOperationResult.success() : ok = true, message = null;

  const OfflineMapOperationResult.failure(this.message) : ok = false;
}

/// Administra las fuentes de mapa offline (`.mbtiles` vectoriales).
///
/// Solo hay un proveedor activo a la vez: el de [activeSource]. El usuario puede
/// cambiar de fuente, descargar una nueva desde Supabase Storage o importar un
/// `.mbtiles` desde el almacenamiento del teléfono.
class MbTilesService extends ChangeNotifier {
  MbTilesService._();
  static final MbTilesService instance = MbTilesService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const _prefUseOffline = 'use_offline_map';
  static const _prefSource = 'offline_map_source';
  static const _remoteBucket = 'muevete';

  static const _brightStylePath =
      'assets/osm_offline_styles/osm-bright-gl-style/style.json';
  static const _darkStylePath =
      'assets/osm_offline_styles/dark-matter-gl-style/style.json';

  late SharedPreferences _prefs;
  String _activeSourceId = kDefaultOfflineMapSourceId;

  /// Ruta local esperada de cada fuente, resuelta en [init].
  final Map<String, String> _paths = <String, String>{};

  OfflineVectorTileProvider? _provider;
  MbTiles? _mbtiles;

  /// Bases que ya reemplazamos pero que un `VectorTileLayer` viejo todavía
  /// puede estar leyendo. No se cierran en caliente para no tumbar la UI.
  final List<MbTiles> _retired = <MbTiles>[];

  Theme? _brightTheme;
  Theme? _darkTheme;

  // ── Logs del flujo de mapas offline ───────────────────────────────────────
  //
  // Todo el módulo escribe con el prefijo `[MBTiles]` para poder seguirlo con:
  //   flutter logs | Select-String '\[MBTiles\]'
  //
  // Convención: `[MBTiles] paso: resultado · detalle`. Los pasos de importación
  // y descarga empiezan con `importar:` / `descarga:` y terminan siempre en
  // `listo` o en `FALLA`, así que un grep de esas dos palabras da el veredicto.

  static void _log(String paso, [Object? detalle]) {
    debugPrint(detalle == null ? '[MBTiles] $paso' : '[MBTiles] $paso · $detalle');
  }

  /// `193744896` → `185 MB`, para que los logs se lean sin calculadora.
  static String _mb(int? bytes) {
    if (bytes == null) return '—';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  // ── Estado público ────────────────────────────────────────────────────────

  List<OfflineMapSource> get sources => kOfflineMapSources;

  OfflineMapSource get activeSource =>
      _sourceById(_activeSourceId) ?? kOfflineMapSources.first;

  bool get useOffline => _prefs.getBool(_prefUseOffline) ?? false;

  OfflineVectorTileProvider? get provider => _provider;

  /// ¿La fuente activa está en el teléfono y lista para dibujar?
  bool get isAvailable => isSourceAvailable(activeSource.id);

  /// ¿Esa fuente está en el teléfono?
  bool isSourceAvailable(String id) {
    final path = _paths[id];
    if (path == null) return false;
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Tamaño en disco de una fuente, o `null` si no está descargada.
  int? sourceSizeBytes(String id) {
    final path = _paths[id];
    if (path == null) return null;
    try {
      final file = File(path);
      return file.existsSync() ? file.lengthSync() : null;
    } catch (_) {
      return null;
    }
  }

  Theme getTheme({required bool isDark}) {
    if (isDark && _darkTheme != null) return _darkTheme!;
    if (!isDark && _brightTheme != null) return _brightTheme!;
    return ProvidedThemes.lightTheme();
  }

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  Future<void> init() async {
    _log('init: arrancando');
    _prefs = await SharedPreferences.getInstance();
    await _loadThemes();

    final dir = await getApplicationDocumentsDirectory();
    for (final source in kOfflineMapSources) {
      _paths[source.id] = '${dir.path}/${source.fileName}';
    }
    _log('init: directorio', dir.path);

    final stored = _prefs.getString(_prefSource);
    if (stored != null && _sourceById(stored) != null) {
      _activeSourceId = stored;
    }

    for (final source in kOfflineMapSources) {
      _log('init: fuente ${source.id}', 'archivo=${_paths[source.id]} '
          'enElTelefono=${isSourceAvailable(source.id)} '
          'tam=${_mb(sourceSizeBytes(source.id))} remote=${source.remotePath}');
    }

    for (final source in kOfflineMapSources) {
      await _ensureBundledCopy(source);
    }

    _log('init: listo', 'activa=$_activeSourceId offline=$useOffline '
        'disponible=$isAvailable');
    if (useOffline) {
      _openActiveSource();
    }
  }

  /// Copia el `.mbtiles` empaquetado al directorio de documentos si falta o si
  /// cambió la versión del asset.
  Future<void> _ensureBundledCopy(OfflineMapSource source) async {
    final assetPath = source.assetPath;
    final destPath = _paths[source.id];
    if (assetPath == null || destPath == null) return;

    final dest = File(destPath);
    // Fuera del `try` para poder registrarla en el log de abajo.
    var copiedVersion = 0;
    bool needsCopy;
    try {
      // La clave antigua (sin id) existía antes de que hubiera varias fuentes:
      // se respeta para no recopiar los 106 MB del mapa base tras actualizar.
      copiedVersion =
          _prefs.getInt(_assetVersionKey(source.id)) ??
          (source.id == kDefaultOfflineMapSourceId
              ? _prefs.getInt('mbtiles_asset_version')
              : null) ??
          0;
      needsCopy =
          !dest.existsSync() ||
          dest.lengthSync() == 0 ||
          copiedVersion < source.assetVersion;
    } catch (_) {
      needsCopy = true;
    }
    if (!needsCopy) {
      _log('init: asset ${source.id}', 'ya copiado (v$copiedVersion), se omite');
      return;
    }
    _log('init: asset ${source.id}', 'copiando $assetPath');

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await dest.writeAsBytes(bytes, flush: true);
      await _prefs.setInt(_assetVersionKey(source.id), source.assetVersion);
      _log('init: asset ${source.id}', 'copiado ${_mb(bytes.length)}');
    } catch (e) {
      // Sin asset disponible seguimos: la fuente puede bajarse del servidor.
      _log('init: asset ${source.id} FALLA', 'no se pudo copiar $assetPath: $e');
    }
  }

  // ── Selección de fuente ───────────────────────────────────────────────────

  /// Cambia la fuente activa. Devuelve `false` si ese archivo no está en el
  /// teléfono todavía (hay que descargarlo o importarlo primero).
  Future<bool> selectSource(String id) async {
    _log('seleccionar: inicio', 'id=$id');
    final source = _sourceById(id);
    if (source == null) {
      _log('seleccionar: FALLA', 'fuente desconocida: $id');
      return false;
    }
    if (!isSourceAvailable(id)) {
      _log('seleccionar: FALLA', '"$id" no está en el teléfono');
      return false;
    }
    if (_activeSourceId == id) {
      _log('seleccionar: ya era la activa', id);
      return true;
    }

    _activeSourceId = id;
    await _prefs.setString(_prefSource, id);
    if (useOffline) {
      _openActiveSource();
    }
    notifyListeners();
    _log('seleccionar: listo', 'activa=$_activeSourceId');
    return true;
  }

  Future<void> toggleOffline(bool value) async {
    _log('offline: cambio', 'value=$value disponible=$isAvailable');
    await _prefs.setBool(_prefUseOffline, value);
    if (value && isAvailable) {
      _openActiveSource();
    } else {
      // Don't dispose the db — just clear the provider reference.
      // The old VectorTileLayer will be removed from the widget tree
      // and stop requesting tiles.
      _provider = null;
      _log('offline: proveedor liberado', 'sin mapa activo');
    }
    notifyListeners();
  }

  // ── Importar desde el teléfono ────────────────────────────────────────────

  /// Copia un `.mbtiles` elegido por el usuario al almacenamiento interno y lo
  /// deja como fuente activa.
  Future<OfflineMapOperationResult> importSource(
    String id,
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    _log('importar: inicio', 'id=$id origen=$sourcePath');
    final destPath = _paths[id];
    if (destPath == null) {
      _log('importar: FALLA', 'el servicio no está inicializado (sin ruta para $id)');
      return const OfflineMapOperationResult.failure(
        'La app todavía no está lista. Inténtalo de nuevo.',
      );
    }
    _log('importar: destino', destPath);

    final origin = File(sourcePath);
    if (!origin.existsSync()) {
      _log('importar: FALLA', 'no existe el archivo elegido');
      return const OfflineMapOperationResult.failure(
        'No se encontró el archivo seleccionado.',
      );
    }
    final originSize = origin.lengthSync();
    _log('importar: origen', '$originSize bytes (${_mb(originSize)})');

    if (origin.absolute.path == File(destPath).absolute.path) {
      _log('importar: el archivo elegido YA es el destino, no hay nada que copiar');
      return const OfflineMapOperationResult.success();
    }

    _log('importar: validando antes de copiar');
    final invalid = _validateMbTiles(origin.path);
    if (invalid != null) {
      _log('importar: FALLA en la validación', invalid);
      return OfflineMapOperationResult.failure(invalid);
    }

    final temp = File('$destPath.part');
    _log('importar: copiando', 'temp=${temp.path}');
    try {
      await _copyWithProgress(origin, temp, onProgress: onProgress);
      final copiedSize = temp.existsSync() ? temp.lengthSync() : -1;
      _log('importar: copia terminada',
          '$copiedSize bytes (${_mb(copiedSize)}) en el temporal');
      if (copiedSize != originSize) {
        _log('importar: AVISO', 'el temporal no coincide con el origen: '
            '$copiedSize != $originSize');
      }
      final dest = File(destPath);
      if (dest.existsSync()) await dest.delete();
      await temp.rename(destPath);
      _log('importar: renombrado al destino', destPath);
    } catch (e, st) {
      if (temp.existsSync()) {
        try {
          await temp.delete();
          _log('importar: temporal borrado tras el fallo');
        } catch (_) {}
      } else {
        _log('importar: no había temporal que borrar');
      }
      _log('importar: FALLA copiando', e);
      _log('importar: stack', st.toString().split('\n').take(4).join(' | '));
      return const OfflineMapOperationResult.failure(
        'No se pudo copiar el archivo. Verifica que haya espacio libre.',
      );
    }

    _activeSourceId = id;
    await _prefs.setString(_prefSource, id);
    _log('importar: activando', 'activa=$_activeSourceId offline=$useOffline');
    if (useOffline) {
      _openActiveSource();
    } else {
      _log('importar: mapa offline apagado, no se abre el proveedor');
    }
    notifyListeners();
    _log('importar: listo', 'disponible=${isSourceAvailable(id)} '
        'tam=${_mb(sourceSizeBytes(id))}');
    return const OfflineMapOperationResult.success();
  }

  // ── Descargar desde Supabase Storage ──────────────────────────────────────

  /// Baja la fuente desde el bucket `muevete` y la deja lista en el teléfono.
  Future<OfflineMapOperationResult> downloadSource(
    String id, {
    void Function(double progress)? onProgress,
  }) async {
    final source = _sourceById(id);
    final destPath = _paths[id];
    _log('descarga: inicio', 'id=$id');
    if (source == null || destPath == null) {
      _log('descarga: FALLA', 'fuente o ruta desconocida (source=${source != null})');
      return const OfflineMapOperationResult.failure('Fuente desconocida.');
    }
    final remotePath = source.remotePath;
    if (remotePath == null) {
      _log('descarga: FALLA', '"$id" no tiene remotePath publicada');
      return const OfflineMapOperationResult.failure(
        'Esta fuente no está publicada en el servidor.',
      );
    }
    _log('descarga: destino', 'bucket=$_remoteBucket remotePath=$remotePath '
        'archivoLocal=$destPath');

    final temp = File('$destPath.part');
    try {
      final signedUrl = await _supabase.storage
          .from(_remoteBucket)
          .createSignedUrl(remotePath, 3600);
      _log('descarga: URL firmada OK');

      final request = http.Request('GET', Uri.parse(signedUrl));
      final response = await request.send();
      _log('descarga: respuesta', 'status=${response.statusCode} '
          'contentLength=${_mb(response.contentLength)}');
      if (response.statusCode != 200) {
        _log('descarga: FALLA', 'el servidor respondió ${response.statusCode}');
        return OfflineMapOperationResult.failure(
          'El servidor respondió ${response.statusCode}. Inténtalo más tarde.',
        );
      }

      final total = response.contentLength ?? 0;
      final sink = temp.openWrite();
      var received = 0;
      var siguienteHito = 0.25;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final p = received / total;
            onProgress?.call(p);
            if (p >= siguienteHito && siguienteHito < 1) {
              _log('descarga: ${(siguienteHito * 100).round()}%',
                  '${_mb(received)} de ${_mb(total)}');
              siguienteHito += 0.25;
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      _log('descarga: recibido', '$received bytes (${_mb(received)}) '
          'de ${total > 0 ? _mb(total) : 'tamaño desconocido'}');

      if (received < 1024 * 1024) {
        _log('descarga: FALLA', 'llegaron menos de 1 MB');
        throw const FormatException('La descarga llegó incompleta.');
      }
      if (total > 0 && received < total) {
        _log('descarga: AVISO', 'la descarga quedó corta: '
            '${_mb(received)} de ${_mb(total)}');
      }
      final invalid = _validateMbTiles(temp.path);
      if (invalid != null) throw FormatException(invalid);

      final dest = File(destPath);
      if (dest.existsSync()) await dest.delete();
      await temp.rename(destPath);
      _log('descarga: renombrado al destino', destPath);
    } on FormatException catch (e) {
      _discardTemp(temp);
      _log('descarga: FALLA', e.message);
      return OfflineMapOperationResult.failure(e.message);
    } catch (e, st) {
      _discardTemp(temp);
      _log('descarga: FALLA', e);
      _log('descarga: stack', st.toString().split('\n').take(4).join(' | '));
      return const OfflineMapOperationResult.failure(
        'No se pudo descargar el mapa. Revisa tu conexión.',
      );
    }

    await _recordRemoteVersion(id);
    if (useOffline && _activeSourceId == id) {
      _openActiveSource();
    }
    notifyListeners();
    _log('descarga: listo', 'disponible=${isSourceAvailable(id)} '
        'tam=${_mb(sourceSizeBytes(id))}');
    return const OfflineMapOperationResult.success();
  }

  /// Guarda la versión publicada en `muevete.map_versions` para no volver a
  /// bajar el mismo archivo. Es best-effort: si falla, no afecta la descarga.
  Future<void> _recordRemoteVersion(String id) async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('map_versions')
          .select('version')
          .eq('id', 1)
          .maybeSingle();
      final version = (row?['version'] as int?) ?? 0;
      if (version > 0) {
        await _prefs.setInt(_remoteVersionKey(id), version);
      }
      _log('version: registrada', 'version=$version para $id');
    } catch (e) {
      // Si falta la tabla `muevete.map_versions` esto falla siempre; el log lo
      // hace visible en vez de degradar en silencio.
      _log('version: no se pudo leer muevete.map_versions', e);
    }
  }

  /// Descarga el mapa de la fuente activa. Se mantiene por compatibilidad con
  /// las pantallas antiguas.
  Future<bool> downloadMbtilesFromSupabase() async {
    final result = await downloadSource(activeSource.id);
    return result.ok;
  }

  /// Baja la fuente activa solo si el servidor tiene una versión más nueva.
  Future<bool> syncMbtilesFromSupabase() async {
    final source = activeSource;
    if (source.remotePath == null) return isAvailable;

    int remoteVersion = 0;
    try {
      final row = await _supabase
          .schema('muevete')
          .from('map_versions')
          .select('version')
          .eq('id', 1)
          .maybeSingle();
      remoteVersion = (row?['version'] as int?) ?? 0;
    } catch (e) {
      debugPrint('[MBTiles] Could not read remote version: $e');
      if (!isAvailable) return downloadMbtilesFromSupabase();
      return true;
    }

    final localVersion = _prefs.getInt(_remoteVersionKey(source.id)) ?? 0;
    if (remoteVersion > localVersion || !isAvailable) {
      final result = await downloadSource(source.id);
      return result.ok;
    }
    return true;
  }

  /// Publica un `.mbtiles` local en Supabase Storage.
  /// Pensado para una utilidad de administración, no para el usuario final.
  Future<void> uploadMbtilesToSupabase(
    String localFilePath, {
    int version = 1,
    String? sourceId,
  }) async {
    final file = File(localFilePath);
    if (!file.existsSync()) {
      throw Exception('Local file not found: $localFilePath');
    }
    final source = _sourceById(sourceId ?? kDefaultOfflineMapSourceId);
    final remotePath = source?.remotePath ?? 'maps/cuba.mbtiles';
    final bytes = await file.readAsBytes();

    await _supabase.storage
        .from(_remoteBucket)
        .uploadBinary(
          remotePath,
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

  // ── Borrar una fuente descargada ──────────────────────────────────────────

  /// Elimina una fuente del teléfono. Solo aplica a fuentes no empaquetadas.
  Future<bool> deleteSource(String id) async {
    _log('eliminar: inicio', 'id=$id');
    final source = _sourceById(id);
    final path = _paths[id];
    if (source == null || path == null || source.isBundled) {
      _log('eliminar: no aplica', 'bundled=${source?.isBundled} path=$path');
      return false;
    }

    if (_activeSourceId == id) {
      _activeSourceId = kDefaultOfflineMapSourceId;
      await _prefs.setString(_prefSource, _activeSourceId);
      _log('eliminar: la activa vuelve a', _activeSourceId);
    }
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
      _log('eliminar: archivo borrado', path);
    } catch (e) {
      _log('eliminar: FALLA borrando', e);
      return false;
    }
    await _prefs.remove(_remoteVersionKey(id));

    if (useOffline) {
      _openActiveSource();
    } else {
      _provider = null;
    }
    notifyListeners();
    return true;
  }

  // ── Interno ───────────────────────────────────────────────────────────────

  String _assetVersionKey(String id) => 'mbtiles_asset_version_$id';
  String _remoteVersionKey(String id) => 'mbtiles_remote_version_$id';

  OfflineMapSource? _sourceById(String id) {
    for (final source in kOfflineMapSources) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// Abre (o reabre) la base de la fuente activa sin cerrar la anterior.
  void _openActiveSource() {
    final path = _paths[_activeSourceId];
    if (path == null || !isSourceAvailable(_activeSourceId)) {
      _provider = null;
      _log('abrir: nada que abrir', 'fuente=$_activeSourceId sin archivo');
      return;
    }
    final previous = _mbtiles;
    try {
      final opened = MbTiles(mbtilesPath: path, gzip: true);
      _mbtiles = opened;
      _provider = OfflineVectorTileProvider(mbtiles: opened);
      if (previous != null) _retired.add(previous);
      _log('abrir: listo', 'fuente=$_activeSourceId '
          'zoom=${_provider!.minimumZoom}-${_provider!.maximumZoom}');
    } catch (e, st) {
      // Se registra con stack y se relanza: el comportamiento no cambia, pero
      // el log dice exactamente qué archivo no se pudo abrir y por qué.
      _provider = null;
      _log('abrir: FALLA', 'no se pudo abrir $path: $e');
      _log('abrir: stack', st.toString().split('\n').take(4).join(' | '));
      rethrow;
    }
  }

  Future<void> _copyWithProgress(
    File origin,
    File dest, {
    void Function(double progress)? onProgress,
  }) async {
    final total = origin.lengthSync();
    _log('copia: inicio', '$total bytes (${_mb(total)})');
    final sink = dest.openWrite();
    var copied = 0;
    var siguienteHito = 0.25;
    try {
      await for (final chunk in origin.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        if (total > 0) {
          final p = copied / total;
          onProgress?.call(p);
          if (p >= siguienteHito && siguienteHito < 1) {
            _log('copia: ${(siguienteHito * 100).round()}%',
                '${_mb(copied)} de ${_mb(total)}');
            siguienteHito += 0.25;
          }
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    _log('copia: fin', '$copied de $total bytes');
  }

  void _discardTemp(File temp) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } catch (_) {}
  }

  /// Devuelve un mensaje de error si el archivo no es un `.mbtiles` vectorial
  /// que la app pueda dibujar, o `null` si es válido.
  String? _validateMbTiles(String path) {
    _log('validacion: inicio', path);
    final file = File(path);
    try {
      if (!file.existsSync()) {
        _log('validacion: FALLA', 'el archivo no existe');
        return 'El archivo no existe.';
      }
      final size = file.lengthSync();
      if (size < 4096) {
        _log('validacion: FALLA', 'demasiado pequeño: $size bytes');
        return 'El archivo es demasiado pequeño para ser un mapa.';
      }
      _log('validacion: tamaño OK', '$size bytes (${_mb(size)})');
      final raf = file.openSync();
      try {
        final header = raf.readSync(16);
        const magic = <int>[
          0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
          0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
        ];
        for (var i = 0; i < magic.length; i++) {
          if (i >= header.length || header[i] != magic[i]) {
            final crudo = header
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            _log('validacion: FALLA', 'cabecera no SQLite: $crudo');
            return 'El archivo no es un .mbtiles (no es una base SQLite).';
          }
        }
        _log('validacion: cabecera SQLite OK');
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      _log('validacion: FALLA leyendo', e);
      return 'No se pudo leer el archivo: $e';
    }

    MbTiles? db;
    try {
      _log('validacion: abriendo metadatos con el paquete mbtiles');
      db = MbTiles(mbtilesPath: path, gzip: true);
      final meta = db.getMetadata();
      _log('validacion: metadata', 'name="${meta.name}" format="${meta.format}" '
          'type=${meta.type} minzoom=${meta.minZoom} maxzoom=${meta.maxZoom} '
          'version=${meta.version} '
          'center=${meta.defaultCenter?.latitude},${meta.defaultCenter?.longitude}');
      if (meta.format != 'pbf') {
        _log('validacion: FALLA', 'no es vectorial: format="${meta.format}"');
        return 'El mapa no es vectorial (formato "${meta.format}"). '
            'Solo se aceptan .mbtiles con tiles pbf.';
      }
      if (meta.maxZoom == null) {
        _log('validacion: FALLA', 'falta metadata.maxzoom');
        return 'Al archivo le faltan los metadatos de zoom.';
      }
      _log('validacion: OK', 'zoom ${meta.minZoom?.toInt()}-${meta.maxZoom?.toInt()}');
      return null;
    } on FormatException catch (e) {
      // El paquete `mbtiles` hace `double.parse` de varios metadatos. El caso
      // real: Planetiler escribe `metadata.version = "3.16.0"` y el parseo
      // revienta con dos puntos. El mensaje de la excepción ya dice el valor
      // exacto ("Invalid double 3.16.0"), así que se registra tal cual.
      _log('validacion: FALLA parseando metadata', e.message);
      return 'El archivo no es un .mbtiles válido.';
    } catch (e, st) {
      _log('validacion: FALLA inesperada', e);
      _log('validacion: stack', st.toString().split('\n').take(4).join(' | '));
      return 'El archivo no es un .mbtiles válido.';
    } finally {
      try {
        db?.dispose();
      } catch (_) {}
    }
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

  @override
  void dispose() {
    _mbtiles?.dispose();
    _mbtiles = null;
    for (final retired in _retired) {
      try {
        retired.dispose();
      } catch (_) {}
    }
    _retired.clear();
    _provider = null;
    super.dispose();
  }
}
