import 'package:flutter/foundation.dart';

/// Fuente de mapa usada por defecto: viene empaquetada con la app.
const String kDefaultOfflineMapSourceId = 'cuba';

/// Una fuente de mapa offline que la app sabe cargar.
///
/// Cada fuente se materializa como un archivo `.mbtiles` (tiles vectoriales MVT
/// con esquema OpenMapTiles) dentro del directorio de documentos de la app:
///
/// * [assetPath] != null → viene dentro del APK y se copia en el primer arranque.
/// * [remotePath] != null → se puede bajar del bucket `muevete` de Supabase.
/// * Sin ninguno de los dos, solo se puede importar desde el teléfono.
///
/// Todas las fuentes comparten los mismos estilos
/// (`assets/osm_offline_styles/`), así que cualquier `.mbtiles` con el esquema
/// OpenMapTiles se dibuja igual.
@immutable
class OfflineMapSource {
  const OfflineMapSource({
    required this.id,
    required this.label,
    required this.description,
    required this.fileName,
    this.assetPath,
    this.remotePath,
    this.approxSizeBytes,
    this.assetVersion = 1,
  });

  /// Identificador estable. Se guarda en SharedPreferences.
  final String id;

  /// Nombre visible en ajustes.
  final String label;

  /// Explicación corta de qué trae este mapa.
  final String description;

  /// Nombre del archivo en el directorio de documentos de la app.
  final String fileName;

  /// Ruta del asset empaquetado, si viene con la app.
  final String? assetPath;

  /// Ruta dentro del bucket `muevete` de Supabase Storage, si está publicada.
  final String? remotePath;

  /// Tamaño aproximado, solo para mostrarlo en la UI.
  final int? approxSizeBytes;

  /// Súbelo para forzar que se vuelva a copiar el asset empaquetado.
  final int assetVersion;

  bool get isBundled => assetPath != null;
  bool get canDownload => remotePath != null;

  /// Texto tipo `106 MB` / `tamaño variable`.
  String get sizeLabel {
    final bytes = approxSizeBytes;
    if (bytes == null || bytes <= 0) return 'tamaño variable';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
}

/// Catálogo de fuentes. La primera es el valor por defecto y la única que viaja
/// dentro del APK; el resto son opcionales y el usuario decide si las baja.
const List<OfflineMapSource> kOfflineMapSources = <OfflineMapSource>[
  OfflineMapSource(
    id: kDefaultOfflineMapSourceId,
    label: 'Cuba (incluido)',
    description: 'Mapa base que viene con la app. Datos OSM 2020, zoom 0-14.',
    fileName: 'cuba.mbtiles',
    assetPath: 'assets/tiles/cuba.mbtiles',
    remotePath: 'maps/cuba.mbtiles',
    approxSizeBytes: 111276032,
    assetVersion: 2,
  ),
  OfflineMapSource(
    id: 'cuba-detalle',
    label: 'Cuba detallado (OSM reciente)',
    description:
        'Extraído de OpenStreetMap con Planetiler (zoom 0-15). Se descarga '
        'aparte o se importa desde el teléfono.',
    fileName: 'cuba-detalle.mbtiles',
    remotePath: 'maps/cuba-detalle.mbtiles',
  ),
];
