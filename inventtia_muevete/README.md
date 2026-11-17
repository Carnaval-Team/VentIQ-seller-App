# inventtia_muevete

A new Flutter project.

## Mapas offline

La app guarda el mapa en el teléfono como `.mbtiles` con tiles vectoriales
(`format=pbf`, esquema OpenMapTiles) y lo dibuja con `vector_map_tiles` + los
estilos de `assets/osm_offline_styles/`.

Fuentes disponibles (`lib/models/offline_map_source.dart`):

| id | Fuente | Dónde vive |
|---|---|---|
| `cuba` | Cuba (incluido) | `assets/tiles/cuba.mbtiles` → se copia al primer arranque. Es la opción por defecto. |
| `cuba-detalle` | Cuba detallado (OSM reciente) | No viaja en el APK: se descarga desde Supabase Storage (`muevete/maps/cuba-detalle.mbtiles`) o se importa desde el teléfono. |

El usuario elige la fuente en **Mi Perfil → Mapa Offline**. Si la fuente elegida
no está descargada, la tarjeta ofrece descargarla o importar un `.mbtiles`.

### Construir el mapa opcional

Un `.osm.pbf` de Geofabrik **no** se puede dibujar directamente: hay que
convertirlo a tiles.

```powershell
# desde la raíz del repo
.\tools\build_offline_map.ps1            # genera dist/cuba-detalle.mbtiles
.\tools\build_offline_map.ps1 -Upload    # además lo publica en Supabase
```

El script usa [Planetiler](https://github.com/onthegomap/planetiler) (requiere
Java 25+). El `.zip` con `.gpkg` de Geofabrik es la misma data en formato SIG
para QGIS; no aporta nada aquí.

No pongas el resultado en `assets/tiles/`: se empaquetaría en el APK. El mapa
grande va a `dist/` (ignorado por git, igual que cualquier `*.mbtiles`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
