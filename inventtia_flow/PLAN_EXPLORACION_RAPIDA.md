# Plan — «Exploración rápida» en el Home del cliente + 3 vistas nuevas + tutorial v2

**Ámbito:** app Flutter `inventtia_flow` (GoReserva) + esquema `flow` de Supabase.
**Creado:** 23-10-2026, a partir de auditoría del código real (no de los `.sql` del
repo, que están desactualizados) y de comprobación contra la base **release**
(`vsieeihstajlrdvpuooh`) con el MCP de Supabase.
**Petición:** sustituir el riel de «Categorías principales» del Home por la rejilla de
4 tarjetas de la referencia, y añadir tres vistas (categorías, establecimientos,
top 10) + actualizar el tutorial del cliente.
**Referencia visual:** [`docs/exploracion_rapida/referencia_exploracion_rapida.png`](docs/exploracion_rapida/referencia_exploracion_rapida.png)

> Nota de nombre: **no** sobreescribo `PLAN_TUTORIAL_Y_MEJORAS.md` (el plan del
> tutorial y los precios, ya cerrado) ni `plan.md` (auditoría del Home). Este
> documento es el plan de **esta** iteración.

---

## 0. Qué se pide y qué cambia

| # | Pedido | Qué se hace |
|---|--------|-------------|
| 1 | Rejilla «Exploración rápida» de 4 tarjetas con su mini-foto/icono | Widget nuevo `ExploracionRapidaGrid` que **reemplaza** el riel de categorías del Home. Cuatro accesos: Categorías, Servicios, Establecimientos, Más populares. |
| 2 | Actualizar el tutorial del cliente | Guion `pasosCliente()` v2 con los nuevos elementos, `TutorialDestino` nuevos para que el tutorial **navegue solo** a las 3 vistas, y `TutorialService.version = 'v2'` para republicarlo una vez. |
| 3 | Vista de listado de categorías con cuántos establecimientos, y subcategorías | `CategoriasScreen`: raíces con contadores reales, despliegue de subcategorías en línea (con sus propios contadores) y salto a establecimientos filtrado por categoría o subcategoría. |
| 4 | Vista de listado de establecimientos con foto, rating y nº de servicios, con filtros | `EstablecimientosScreen`: tarjetas de local con foto, valoración promedio ponderada, nº de servicios, provincia, abierto/cerrado y precio desde; filtros reusando el sheet existente. |
| 5 | Vista del top 10 de servicios | `TopServiciosScreen`: podio 1-3 + filas 4-10 desde `flow.cliente_ranking_semanal(p_limite := 10)` (RPC que **ya existe**). |
| 6 | Que al tocar un establecimiento se abra **la misma vista del espacio patrocinado** | Se extrae `FichaLocalScreen` (ficha comercial + todos los servicios del local) y `EspacioPatrocinadoScreen` pasa a ser un envoltorio con un `CampanaPatrocinada`. Una sola pantalla, dos entradas. |
| 7 | Consistencia y navegación correcta | Paleta extraída de la referencia **ya presente** en la app; navegación con `Navigator.push` como el resto; rejilla y tutorial comparten los mismos helpers de ruta (una sola fuente de verdad). |

---

## 1. Decisiones

### 1.1 Decisiones cerradas (las tomo yo, con la evidencia del §2)

| # | Tema | Decisión |
|---|------|----------|
| D1 | Dónde vive la rejilla | Reemplaza al sliver de categorías del Home (`home_client_screen.dart:755`). El riel de categorías y la fila de subcategorías **se retiran del Home**: su función se muda a `CategoriasScreen`. No se dejan dos formas de filtrar por categoría. |
| D2 | Estado de categoría en el Home | El Home deja de tener `_category`/`_subcategoria`: el feed del Home se filtra por búsqueda, provincia, filtros del sheet y «mejor valorados». La categoría pasa a ser parámetro **de la pantalla nueva** (`cliente_home_feed(p_id_categoria/p_id_subcategoria)` sigue filtrando en servidor, igual que hoy). Se simplifica `_aplicarCategorias` (ya no hay que recargar si la categoría activa desapareció: no hay categoría activa). |
| D3 | Conteos de categorías y establecimientos | **En servidor** (D18), con la migración **57**: `cliente_categorias_resumen()` y `cliente_locales_publicos(...)`. Los conteos respetan la misma regla de visibilidad que el feed (`flow._ls_disponible(ls.id)`) y la exclusión de `flow.entidad_categoria_oculta`, así que el número coincide **exactamente** con lo que el cliente puede reservar. La agregación del rating por local se hace en SQL (`sum(puntuacion)/count`), que es exacto — no la media de medias que haría falta en cliente. `precio_desde` **no** se calcula en SQL: la RPC devuelve el `config_precio` de cada servicio y Dart aplica `precioBaseDe()` (`lib/utils/precio_reserva.dart`), para no tener dos implementaciones de la regla de precio. |
| D4 | Top 10 | `flow.cliente_ranking_semanal(p_limite)` ya existe y solo hay que pedirlo con `limite: 10` (`HomeCatalogService.fetchRankingSemanal({limite = 5})`, `home_catalog_service.dart:396`). Devuelve los mismos ítems que el feed + `lugares_semana`, así que **no hay nada que adaptar** en el modelo. |
| D5 | Ficha del establecimiento | `EspacioPatrocinadoScreen` se parte: el cuerpo (1002 líneas) se muda a `FichaLocalScreen({required FichaLocal ficha, CampanaPatrocinada? campana})` y `EspacioPatrocinadoScreen` queda como envoltorio `const EspacioPatrocinadoScreen({required campana})`, de modo que `home_client_screen._abrirCampana` (`:1355`) **no cambia**. Sin campaña, la ficha se pinta con etiqueta «ESTABLECIMIENTO» y degradado de marca, sin el bloque «DESTACADO DEL MOMENTO». |
| D6 | Sección «Establecimientos» del Home | Su tarjeta abre ahora la **ficha** (la misma vista del espacio patrocinado), y su «Ver todos» —hoy muerto, cae al toast «Desliza…» (`:1508`)— abre `EstablecimientosScreen`. Se retira el callback `onVerEstablecimiento` y `HomeShell._abrirCatalogoDeEstablecimiento` (`home_shell.dart:463`), que existían solo para saltar al catálogo filtrado. |
| D7 | Sección «Servicios populares de la semana» del Home | Su «Ranking» —hoy también muerto— abre `TopServiciosScreen`. Es la entrada natural y arregla un botón sin destino. |
| D8 | Rutas | Todo con `Navigator.push(MaterialPageRoute)` como el resto de la app (44 usos; no hay `go_router`). La rejilla y el tutorial comparten `ExploracionNavegacion` (§4, F7) para que no haya dos mapas de «qué pantalla abre cada tarjeta». |
| D9 | Colores | Se añaden constantes a `AppTheme` con la paleta **medida** en la referencia: `exploracionIndigo 0xFF4F5C8B`, `exploracionIndigoDark 0xFF3B4A7E`, `exploracionTeal 0xFF1FA8B8`, `exploracionTealDark 0xFF1593A3`, `exploracionNavy 0xFF424A65`, `exploracionNavyDark 0xFF2C3654`, `exploracionCoral 0xFFFF4E5F`, `exploracionCoralDark 0xFFE8394C`. `0xFF1FA8B8` y `0xFF2C3654` ya se usan a mano en el Home (banner de fidelidad `:1683` y topBar `:812`) y en el mock de Stitch del repo: esto los unifica. |
| D10 | Sin dependencias nuevas ni migraciones obligatorias | Nada de paquetes nuevos; **ninguna migración es necesaria** para la funcionalidad completa. |
| D11 | Interruptores | No se añade bandera a `HomeFeatures` para la rejilla: las 4 tarjetas están respaldadas por datos reales, y apagarla dejaría el Home sin acceso a categorías. Sí se documenta en `home_features.dart` que `distancia == false` condiciona la etiqueta «Cerca de ti» (ver D13). |
| D12 | Persistencia del tutorial | `TutorialService.version` sube de `v1` a `v2` (`tutorial_service.dart:19`). Consecuencia deliberada: el tutorial **se vuelve a mostrar una vez** a todos los usuarios (es lo que hace que vean la UI nueva). No se toca Supabase. |

### 1.2 Decisiones confirmadas por el usuario (23-10-2026)

| # | Pregunta | **Resuelto** |
|---|----------|--------------|
| D13 | Etiqueta de la tarjeta «Establecimientos» | **«Todos los locales»** (no «Cerca de ti»: no hay distancias). Se pasa a «Cerca de ti` solo si algún día `HomeFeatures.distancia`. |
| D14 | Etiqueta de la tarjeta «Más populares» | **«Tendencias de la semana»** (el ranking es semanal). |
| D15 | Interacción en categorías (revisada en el 5.º bloque) | **Dos acciones separadas, tampoco a la vez**: tocar la **tarjeta** abre la **carpeta** del rubro (sus subcategorías, con animación tipo carpeta de Android) y el pie «Ver todos» NAVEGA al listado de establecimientos filtrado por ese rubro. Tocar una subcategoría lleva al listado filtrado por ella. La presentación es un **panel lateral** (`RutaLateral`) con rejilla de tarjetas de dos en dos, iguales que las del acceso rápido. |
| D16 | Longitud del tutorial | **13 pasos**, y el guion explica el **acceso rápido** («Exploración rápida»: los 4 atajos) además de las pantallas nuevas. |
| D17 | Datos de «Más populares» | Top 10 por reservas de la semana (`cliente_ranking_semanal(p_limite := 10)`). |
| D18 | Origen de los conteos | **RPC nueva desde ya** (migración **57**): `cliente_categorias_resumen()` y `cliente_locales_publicos(...)`. Se retira de este plan el cálculo en cliente como camino principal; el §5.1 pasa a ser obligatorio, no plan B. |

---

## 2. Estado de partida verificado (evidencia)

### 2.1 El Home hoy

`home_client_screen.dart` (3702 líneas). Slivers del `CustomScrollView` en `:745-800`:
hero+buscador `:749` → **categorías `:755`** → patrocinados `:759` → ofertas `:761` →
recomendados `:763` → establecimientos `:764` → ranking `:765` → reseñas `:767` →
colecciones `:775` → fidelidad `:777` → cómo funciona `:779` → cabecera del feed `:780` →
lista `:785-796` → footer `:799`.

Lo que se toca:

- `_buildCategories()` `:1073-1146` — título «Categorías principales» + riel de 40 px de chips (radio 22) + `_buildSubcategorias()` `:1153-1211`. **Se sustituye por la rejilla.**
- `_selectCategory` `:562`, `_selectSubcategoria` `:589`, `_subcategoria` `:97`, `_category` `:92`, `_SubcategoriaChip` `:3531`, `_aplicarCategorias` `:419`. **Se retiran** (D2).
- `_iconoCategoria` `:3501` (+ `:3515`, mapa código→icono). **Se extrae** a `lib/utils/categoria_icono.dart` porque la usa también la tarjeta del feed (`:2843`) y la va a necesitar `CategoriasScreen`.
- `_buildPopularPlaces()` `:1495-1542` — `_PopularPlaceCard` `:2769` y `_abrirEstablecimiento` `:384` → pasan a abrir la ficha; «Ver todos» `:1508` → `EstablecimientosScreen` (D6).
- `_buildWeeklyPopular()` `:1544-1586` — «Ranking» `:1556` → `TopServiciosScreen` (D7).
- Ancla del tutorial `home_ver_todo` en `:1458` (dentro de `_buildRecommended`) → se **mueve** al «Ver catálogo ›» de la rejilla nueva (un `id` = un ancla).
- Ancla `home_buscar` `:946` — no se toca.
- `_abrirCampana` `:1355` — no se toca (D5 mantiene el constructor de `EspacioPatrocinadoScreen`).

Contrato público: `HomeClientScreen({onVerCatalogo, onPublicarNegocio, onVerEstablecimiento})` `:34-56`; `HomeClientScreenState` es público (lo usan las `GlobalKey` del shell).

### 2.2 Lo que NO existe (verificado con glob/grep)

- **No hay pantalla de listado de categorías para el cliente** (solo el CRUD de admin `screens/admin/config_categorias_screen.dart`, 722 líneas — no se reutiliza: es gestión, no exploración).
- **No hay pantalla de listado de establecimientos** en ninguna parte. Lo más parecido: carrusel de 4 locales del Home (`_PopularPlaceCard`), catálogo filtrado por local (`CatalogoScreenState.filtrarPorLocal` `catalogo_screen.dart:390`) y agrupación por establecimiento de `coleccion_detail_screen.dart` (`utils/coleccion_servicios.dart:49`).
- **No hay pantalla de top 10**; el máximo hoy es el riel del ranking semanal con `limite` por defecto **5**.
- **No hay tarjeta pública de servicio ni de establecimiento**: `_FeedServiceCard` `:3062`, `_PopularPlaceCard` `:2769`, `_WeeklyServiceRow` `:2974` y `_LocalServicioCard` (`catalogo_screen.dart:922`) son privadas. Reutilizar exige extraer (se hace solo lo imprescindible: el ranking se pinta con una fila propia de la pantalla nueva).
- **No hay ningún test que referencie `HomeClientScreen`** — el rediseño del Home no rompe tests existentes por sí mismo (sí los de tutorial, por los `id` y los destinos).

### 2.3 Datos disponibles (verificado contra la base release)

RPC vivas relevantes (`pg_proc` del esquema `flow`, comprobado hoy):

| RPC | Firma viva | Devuelve |
|-----|-----------|----------|
| `cliente_home_feed` | `(text, integer, text, integer, boolean, integer)` | `jsonb` con `items` (forma `servicio`/`local`/`entidad` + `rating`, `total_resenas`, `categoria_*`, `subcategoria_*`, `promocion`), `total`, `has_more`, `metadata.categorias` (raíces con `subcategorias` anidadas), `colecciones`, `patrocinados`, `contadores`. Filtra por `_ls_disponible`, categoría **incluyendo sus subcategorías** y subcategoría. `has_more` = `false` (trae todo). |
| `cliente_ranking_semanal` | `(integer = 5)` | `jsonb` array de ítems del feed + `lugares_semana`; ordena por lugares y reservas de la **semana en curso**; solo estados 1 y 3. |
| `cliente_obtener_locales` | `(integer = null)` | Locales con foto, dirección, provincia, país, coordenadas, horario y entidad. **Sin contadores ni rating**; no filtra por activo/disponible. |
| `cliente_obtener_servicios` | `(integer, integer, integer, text, text, text, text, boolean)` | Servicios de un local (`p_id_local`) con la misma forma anidada. Lo usa el detalle, el catálogo y la ficha patrocinada. |
| `resenas_por_servicio` | — | `total` y `promedio` por `local_servicio` (base del `rating` del feed). |

Conclusión de datos: **todo lo que piden las 3 vistas está ya en `cliente_home_feed`**
(nombre/foto/dirección/provincia/horario del local, servicios, rating y reseñas por
servicio, categoría y subcategoría resueltas) **más** el ranking semanal para el top 10.
No hace falta ni una tabla ni una RPC nueva (D3/D4).

### 2.4 Tutorial del cliente hoy

- Guion `tutorial_flujos.dart:26-84`: **7 pasos** (`home_buscar`, `home_ver_todo`,
  `catalogo_tarjeta`, `detalle_acciones`, `detalle_calendario`, `detalle_datos`
  [opcional], `detalle_continuar`).
- Motor: `TutorialController` navega solo cuando el paso declara `destino`
  (`tutorial_destino.dart`); hoy los destinos del cliente son `home`, `catalogo` y
  `servicio`, traducidos en `home_shell.dart:_navegarTutorial` `:199-223`. Un ancla que
  no se monta **no rompe** nada: el paso espera y el usuario puede avanzar o saltar.
- Persistencia: `SharedPreferences`, `flow_tutorial_cliente_v1_<uuid>` con `visto`/`omitido`
  (`tutorial_service.dart:15-31`). **Con `v1` ya marcado, el tutorial nuevo no se
  mostraría**: de ahí D12.
- Tests que fijan el guion: `test/tutorial_flujos_test.dart` (ids únicos, opcionales,
  destinos), `test/tutorial_navegacion_pasos_test.dart`, `test/tutorial_service_test.dart`.
- Con >8 pasos el overlay cambia solo de puntos a barra fina (`tutorial_overlay.dart:536-557`).

### 2.5 La referencia visual, medida

Paleta extraída de la imagen (cuantizada, `Pillow`, 510×324):

| Zona | Muestras | Color |
|------|----------|-------|
| Tarjeta 1 «Categorías» | `#4F5C8B` → `#3B4A7E` | índigo, degradado hacia abajo-derecha |
| Tarjeta 2 «Servicios» | `#1FA8B8` | teal (**ya en la app**: banner de fidelidad y mock de Stitch) |
| Tarjeta 3 «Establecimientos» | `#424A65` → `#2C3654` | azul noche (**ya en la app**: topBar del Home) |
| Tarjeta 4 «Más populares» | `#FF4E5F` / `#FF4D5E` | coral |
| Fondos | `#F3F4F8`, `#EBEFF4` | `AppTheme.surface` `#F5F7FA` — misma familia |

Anatomía (de la imagen): tarjeta radio ≈22 con degradado; chip superior izquierdo en
mayúsculas (`12 ACTIVAS`, `CATÁLOGO`, `LOCALES`, `TOP 10`) en blanco sobre blanco al
18 %; cuadro de icono arriba a la derecha (≈34×34, radio 10, blanco al 16 %); título
≈20 w800 blanco; subtítulo ≈12.5 blanco al 78 %; marca de agua sutil. Cabecera de
sección: «EXPLORACIÓN RÁPIDA» (mayúsculas, `letterSpacing` amplio, `textPrimary`) y a la
derecha «Ver catálogo ›» (teal).

---

## 3. Diseño de lo que se construye

### 3.1 `ExploracionRapidaGrid` (reemplaza al riel de categorías)

`lib/widgets/exploracion_rapida_grid.dart` — widget **público y sin lógica de datos**
(recibe los callbacks y el contador ya resueltos), para que sea testeable sin Supabase:

```
ExploracionRapidaGrid({
  required int categoriasActivas,   // badges «N ACTIVAS»
  required VoidCallback onCategorias,
  required VoidCallback onServicios,
  required VoidCallback onEstablecimientos,
  required VoidCallback onMasPopulares,
})
```

- Cabecera con `_sectionHeading('EXPLORACIÓN RÁPIDA', trailing: 'Ver catálogo ›',
  onTrailingTap: onServicios, trailingAnchorId: 'home_ver_todo')` — reutiliza el helper
  del Home (`:2116`) y **aquí aterriza el ancla** del paso 2 del tutorial.
- `GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: NeverScrollableScrollPhysics, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.42)` con `padding: EdgeInsets.symmetric(horizontal: 16)`. El ancho típico (390 pt) da tarjetas de ≈173×122.
- `TarjetaExploracion`: `ClipRRect(22)` + `DecoratedBox` con el degradado + `Material`/`InkWell`; chip, icono, título (`maxLines: 1`, ellipsis), subtítulo (`maxLines: 1`), marca de agua (`Icon` blanco al 6 %). Ancla del tutorial `home_exploracion` sobre la rejilla y `home_card_categorias` sobre la primera tarjeta.
- Textos y destinos (los de la referencia, con D13/D14 aplicados):

| # | Chip | Título | Subtítulo | Icono | Toque |
|---|------|--------|-----------|-------|-------|
| 1 | `$categoriasActivas ACTIVAS` (dinámico; si el nomenclador viene vacío → «TODAS») | Categorías | Todos los rubros | `Icons.grid_view_rounded` | `CategoriasScreen` |
| 2 | CATÁLOGO | Servicios | Explorar catálogo | `Icons.storefront_rounded` | `widget.onVerCatalogo` (pestaña Servicios) |
| 3 | LOCALES | Establecimientos | «Todos los locales» (o «Cerca de ti» con `HomeFeatures.distancia`) | `Icons.store_mall_directory_rounded` | `EstablecimientosScreen` |
| 4 | TOP 10 | Más populares | «Tendencias de la semana» (o «Tendencias hoy» con la migración del §5.3) | `Icons.star_rounded` | `TopServiciosScreen` |

- Degradados: `[exploracionIndigo, exploracionIndigoDark]`, `[exploracionTeal,
  exploracionTealDark]`, `[exploracionNavy, exploracionNavyDark]`, `[exploracionCoral,
  exploracionCoralDark]`.
- **Estados límite que se prueban:** 320 pt de ancho (teléfono pequeño), `textScaleFactor`
  1.3 (sin overflow), 0 categorías activas (chip «TODAS» en vez de «0 ACTIVAS»).
- El número del chip será el **real**: hoy **6** raíces activas (el seed de la migración 47
  son 6 raíces + 30 subcategorías). La referencia enseña «12 ACTIVAS» porque es un mock:
  no se copia el número, se copia el diseño.

### 3.2 `CategoriasScreen` (rediseñada en el 5.º bloque: panel lateral con carpetas)

`lib/screens/categorias_screen.dart`. Ya **no** es una pantalla de filas: es un **panel
lateral** que entra desde la izquierda (`RutaLateral`: 260 ms, no opaca, 88 % del ancho con
tope 372 px) con velo detrás que cierra al tocarlo, X en la cabecera y el gesto de atrás.
Sigue siendo una **ruta** (no un `Scaffold.drawer`) porque el botón atrás, el
`popUntil` del tutorial y el cambio de pestaña de la barra inferior dependen del
`Navigator`.

- Cabecera con degradado de marca, «Categorías», «Todos los rubros» y la pastilla de
  totales globales («6 categorías · 8 establecimientos · 11 servicios»), que no se pinta si
  no hay nada que contar. Ancla `categorias_lista` aquí (montada en todos los estados).
- Rejilla de **dos en dos** con las MISMAS tarjetas del acceso rápido
  (`TarjetaExploracion`): chip `3 LOCALES` / `1 LOCAL` / `SIN LOCALES`, nombre del rubro,
  `N servicios` y pie «Ver todos» (`accionEtiqueta` + `onAccion`; apagado y sin toque si el
  rubro está vacío, para que todas midan igual). Los cuatro degradados de «Exploración
  rápida» en ciclo: misma familia visual.
- **Dos acciones separadas**: tocar la tarjeta abre la carpeta; «Ver todos» navega al
  listado filtrado por el rubro. Una fila «Otras» (servicios sin categoría) cierra la
  rejilla cuando la RPC reporta `otros_*`.
- **Carpetas**: al tocar, la tarjeta hace un «boom» (escala 0.86→1 con `easeOutBack`,
  240 ms) durante 190 ms y después entra la vista del rubro con `AnimatedSwitcher`
  (fade + escala 0.90→1, 300 ms); las subcategorías aparecen en **cascada** (`Interval` +
  `easeOutBack` por índice). Dentro: cabecera «Subcategorías de X», banner grande del rubro
  (mismo degradado, contadores y «Ver todos los establecimientos») y la rejilla de
  subcategorías → listado filtrado por (rubro, subcategoría). Un rubro sin hijas lo dice.
- Con `MediaQuery.disableAnimations` (accesibilidad) no se anima: la carpeta se abre en el
  mismo frame.
- Estados: carga, error real, migración 57 pendiente y vacío («El catálogo todavía no tiene
  categorías publicadas»), todos dentro del panel.
- Sin barra inferior propia: es un cajón que flota sobre la pantalla anterior, así que la
  barra del shell se ve detrás atenuada por el velo. Un cajón con su propia barra de
  pestañas serían dos navegaciones a la vez.
- Estados: carga, error (con Reintentar) y vacío («El catálogo todavía no tiene
  categorías publicadas»).
- Anclas: `categorias_lista` sobre el **encabezado** (siempre montado; nunca sobre la
  primera tarjeta, que es de una lista perezosa y puede no existir).

### 3.3 `EstablecimientosScreen`

`lib/screens/establecimientos_screen.dart` — `({HomeCatalogCategory? categoria,
HomeCatalogCategory? subcategoria, String? provincia})`:

- Tarjeta de local: foto del local (`NetImage` con respaldo degradado como
  `_MediaPreview`), nombre, «provincia · dirección», chips (`Abierto ahora`/`Cerrado`
  con `HorarioAtencion`, «N servicios», «Reserva directa» si alguno la permite),
  `Estrellas` + promedio (1 decimal) + `(N reseñas)` **solo si hay reseñas**, y «Desde
  {precio} {moneda}» (mínimo real del local).
- Barra de filtros: chips de subcategorías cuando hay categoría activa + botón «Filtros»
  que reusa `mostrarFiltrosServicios` con `OpcionesFiltros` deducidas de los locales
  cargados (provincias, valoración, abierto ahora) + selector de orden (Mejor valorados ·
  Más servicios · A-Z). Muestra el contador de filtros activos con `Badge.count`, igual
  que el Home (`:996`).
- Orden por defecto: mejor valorados con desempate por nº de servicios, y los locales
  **sin reseñas al final** (nunca se les supone una valoración — misma regla que
  `cliente_home_feed(p_mejor_valorados)` y `HomeCatalogItem.tieneValoracion`).
- Toque en la tarjeta → `FichaLocalScreen` (la vista del espacio patrocinado, D5).
- Anclas: `establecimientos_lista` y `establecimientos_filtros` (encabezado y botón,
  siempre montados).

### 3.4 `FichaLocalScreen` (refactor de la pantalla patrocinada)

`lib/models/ficha_local.dart`:

```
FichaLocal { idLocal, nombre, descripcion, direccion, pais, provincia,
             horarioAtencion, horarioDetalle, foto,
             entidad, entidadTelefono,
             rating, totalResenas, totalServicios, precioDesde, monedaDesde }
  factory FichaLocal.desdeCampana(CampanaPatrocinada)
  factory FichaLocal.desdeResumen(EstablecimientoResumen)
```

`lib/screens/ficha_local_screen.dart`: el cuerpo actual de `espacio_patrocinado_screen.dart`
(hero con `SliverAppBar`, chips de datos reales, «Sobre {local}», contacto, y la lista
`_TarjetaServicioLocal` de **todos** los servicios del local vía
`cliente_obtener_servicios(p_id_local)`), con:

- `campana != null` → etiqueta «ESPACIO PATROCINADO», degradado de la campaña y bloque
  «DESTACADO DEL MOMENTO» (comportamiento actual intacto).
- `campana == null` → etiqueta «ESTABLECIMIENTO», degradado `primaryDark → primary`, sin
  bloque de campaña, y los chips de valoración y de «N servicios» (que en modo campaña
  ya existen, `:289-295`).
- `espacio_patrocinado_screen.dart` se queda con
  `class EspacioPatrocinadoScreen extends StatelessWidget` → devuelve `FichaLocalScreen`.
  **Mismo constructor público**, así que `_abrirCampana` y el carrusel no cambian.

### 3.5 `TopServiciosScreen`

`lib/screens/top_servicios_screen.dart` — cabecera con degradado coral y «TOP 10 ·
Tendencias de la semana»; podio para los puestos 1-3 (tarjeta grande con medalla,
foto, título, local, `Estrellas`, precio y «N lugares reservados») y filas compactas
4-10 reusando el lenguaje de `_WeeklyServiceRow`. Toque → `LocalServicioDetailScreen`.

- Datos: `HomeCatalogService.fetchRankingSemanal(limite: 10)` (D4).
- Estados honestos: vacío («Todavía no hay reservas esta semana») con CTA «Ver el
  catálogo», error con Reintentar, y si la migración 36 no está aplicada el bloque no
  se pinta en vez de rellenarse con el orden del catálogo.
- Ancla: `top_servicios` sobre el encabezado.

---

## 4. Fases

Regla de trabajo (igual que el plan anterior): cada fase se implementa, se analiza con
`mcp__dart__analyze_files` y se verifica con `mcp__dart__run_tests`. Nada se da por hecho
sin evidencia. `flutter test` por PowerShell se cuelga en este entorno: usar el MCP.

### F0 — Baseline
- Registrar en §9 el resultado de `analyze` y el conteo de la suite **antes** de tocar nada
  (referencia del cierre anterior: **468/468 en verde**, análisis sin errores).
- **Criterio:** baseline anotado.

### F1 — Modelos, agregación pura y servicio (sin UI)
**Nuevos:** `lib/models/establecimiento_resumen.dart`,
`lib/models/categoria_con_conteo.dart`, `lib/utils/exploracion_resumen.dart`,
`lib/services/exploracion_service.dart`, `test/exploracion_resumen_test.dart`.

1. `resumenCategorias({nomenclador, items})` → raíces con `servicios` y
   `establecimientos` (locales distintos por `idLocal`) y sus subcategorías con los
   mismos contadores; los ítems de una categoría **suman los de sus subcategorías**
   (misma regla que el filtro del servidor, `48_...sql:139-146`). Un servicio sin
   nomenclador activo cae en «Otras» (`categoria` vacía) en vez de desaparecer.
2. `establecimientosDesdeItems(items)` → **extiende** `agruparPorEstablecimiento()`
   (`lib/utils/coleccion_servicios.dart:49`, que ya agrupa por local con `total` y
   `ubicacion`): nombre, provincia, dirección, foto del local, horario, entidad,
   `totalServicios`, `ratingPromedio` **ponderado por `totalResenas`**
   (`Σ(rating·reseñas)/Σ(reseñas)`; `null` si no hay ninguna reseña), `totalResenas`,
   `precioDesde`/`monedaDesde`, `tieneReservaDirecta`, categorías presentes, y
   `abiertoAhora` recalculado con `HorarioAtencion` y un `DateTime.now()` inyectable
   (igual que `_pasaFiltros`, `home_client_screen.dart:263-282`).
3. `topServicios(ranking, {limite = 10})` y `etiquetaLugares(int)`.
4. `ExploracionService`: cachea la lectura sin filtros de `cliente_home_feed()` (reusa
   `HomeCatalogService.fetchFeed()`), expone `categorias()`, `establecimientos()`,
   `topServicios({limite})`, `clearCache()`, y degrada a lista vacía si el RPC falla
   (nunca lanza a la UI).

**Criterio:** los tests puros pasan con datos reales copiados (13 servicios, 11 locales,
6 raíces) y con casos límite (vacío, servicio sin reseñas, local con 1 servicio, ítem
fuera del nomenclador). `analyze` limpio.

### F2 — Tema + rejilla en el Home
**Nuevos:** `lib/widgets/exploracion_rapida_grid.dart`, `lib/utils/categoria_icono.dart`,
`test/exploracion_rapida_grid_test.dart`.
**Modificados:** `lib/config/app_theme.dart`, `lib/screens/home_client_screen.dart`.

1. Constantes de color en `AppTheme` (D9).
2. Extraer `iconoCategoria` a `lib/utils/categoria_icono.dart` y usarla en las 2 llamadas
   del Home (`:1116`, `:2843`).
3. `_buildExploracionRapida()` en el Home: sustituye el sliver `:755`; recibe
   `categoriasActivas` de `_categories` y los 4 callbacks.
4. Retirar `_buildCategories`, `_buildSubcategorias`, `_selectCategory`,
   `_selectSubcategoria`, `_SubcategoriaChip`, el estado `_category`/`_subcategoria` y su
   rama de `_loadPage`; simplificar `_aplicarCategorias` para que solo guarde el
   nomenclador (el badge y la pantalla de categorías lo necesitan).
5. Mover el ancla `home_ver_todo` al «Ver catálogo ›» de la rejilla y añadir
   `home_exploracion` y `home_card_categorias`.

**Criterio:** la rejilla se ve como la referencia (2×2, 4 tarjetas, badges y colores);
sin overflow a 320 pt y con texto a 1.3; los 4 toques navegan (los 3 pendientes, en F7);
el Home ya no muestra el riel de categorías; `home_ver_todo` existe **exactamente una vez**.

### F3 — `CategoriasScreen`  · depende de F1
**Nuevos:** `lib/screens/categorias_screen.dart`, `test/categorias_screen_test.dart`.
**Criterio:** cada raíz muestra su conteo real y despliega subcategorías con el suyo; el
CTA y las subcategorías navegan al listado filtrado (F7 los conecta); estados de carga,
error y vacío.

### F4 — `EstablecimientosScreen` · depende de F1
**Nuevos:** `lib/screens/establecimientos_screen.dart`,
`test/establecimientos_screen_test.dart`.
**Criterio:** tarjetas con foto, valoración (solo con reseñas), nº de servicios,
provincia y precio desde; orden y filtros funcionan sobre datos inyectados; sin reseñas
no aparecen estrellas ni «0.0».

### F5 — `FichaLocalScreen` + envoltorio patrocinado · depende de F1
**Nuevos:** `lib/models/ficha_local.dart`, `lib/screens/ficha_local_screen.dart`,
`test/ficha_local_test.dart`.
**Modificado:** `lib/screens/espacio_patrocinado_screen.dart`.
**Criterio:** el carrusel patrocinado se comporta **igual** que antes (misma cabecera,
mismos chips, mismos servicios); la misma pantalla abierta desde un establecimiento
normal pinta la etiqueta «ESTABLECIMIENTO», su foto/valoración y sus servicios; sin
servicios sigue el estado vacío actual.

### F6 — `TopServiciosScreen` · depende de F1
**Nuevos:** `lib/screens/top_servicios_screen.dart` (+ test de widget con datos falsos).
**Criterio:** 10 ítems como máximo con el número de lugares reservados de cada uno; vacío
y error degradan con mensaje; toque abre el detalle.

### F7 — Navegación y enlaces existentes · depende de F2-F6
**Nuevos:** `lib/utils/exploracion_navegacion.dart`.
**Modificados:** `lib/screens/home_client_screen.dart`, `lib/screens/home_shell.dart`,
`lib/screens/top_servicios_screen.dart` (callback de retorno al catálogo si hace falta).

1. `ExploracionNavegacion.abrirCategorias(context)`,
   `.abrirEstablecimientos(context, {categoria, subcategoria, provincia})`,
   `.abrirTopServicios(context)`, `.abrirFicha(context, resumen)` — **única fuente de
   verdad** de las rutas nuevas, usada por la rejilla, por las pantallas nuevas y por el
   tutorial (D8).
2. Home: `_buildPopularPlaces` → ficha y «Ver todos» → establecimientos; ranking
   «Ranking» → top 10; retirar `onVerEstablecimiento` del contrato del Home y
   `_abrirCatalogoDeEstablecimiento` del shell.
3. Limpieza: `grep` de `filtrarPorLocal` antes de decidir si se retira de
   `CatalogoScreenState` (hoy su único llamador es el shell); si se retira, quitar
   también el método y su comentario.

**Criterio:** las 4 tarjetas, el «Ver todos» de establecimientos y el «Ranking» navegan;
volver atrás deja el Home intacto; `analyze` sin avisos nuevos.

### F8 — Tutorial del cliente v2 · depende de F2-F7
**Modificados:** `lib/tutorial/tutorial_destino.dart`, `lib/tutorial/tutorial_flujos.dart`,
`lib/tutorial/tutorial_navegacion.dart`, `lib/screens/home_shell.dart`,
`lib/services/tutorial_service.dart`, `test/tutorial_flujos_test.dart`,
`test/tutorial_navegacion_pasos_test.dart`, `test/tutorial_service_test.dart`.

1. `TutorialDestino`: `listaCategorias`, `listaEstablecimientos`, `fichaEstablecimiento`,
   `topServicios` (nombres distintos de `categorias`, que ya es del admin).
2. `TutorialNavegacion.irACliente(context, destino)`: `volverAlShell` y empuja las
   pantallas nuevas con `ExploracionNavegacion` (para la ficha, la del primer
   establecimiento con servicios). Espejo de `irAAdmin`.
3. `home_shell._navegarTutorial`: delega los destinos nuevos en `irACliente`.
4. Guion v2 (13 pasos, D16/D17):

| # | id | destino | Notas |
|---|----|---------|-------|
| 1 | `home_buscar` | home | igual |
| 2 | `home_exploracion` | home | **nuevo**: la rejilla y sus 4 atajos |
| 3 | `home_ver_todo` | home | mismo id, ancla nueva («Ver catálogo ›») |
| 4 | `home_card_categorias` | home | **nuevo**: «cuántos establecimientos tiene cada rubro» |
| 5 | `categorias_lista` | listaCategorias | **nuevo** |
| 6 | `establecimientos_lista` | listaEstablecimientos | **nuevo** |
| 7 | `establecimiento_ficha` | fichaEstablecimiento | **nuevo**, `opcional: true` (sin locales no hay ficha) |
| 8 | `top_servicios` | topServicios | **nuevo**, `opcional: true` (sin reservas esta semana no hay lista) |
| 9 | `catalogo_tarjeta` | catalogo | igual |
| 10 | `detalle_acciones` | servicio | igual |
| 11 | `detalle_calendario` | — | igual (hoja) |
| 12 | `detalle_datos` | — | igual, `opcional: true` |
| 13 | `detalle_continuar` | — | igual |

5. `TutorialService.version = 'v2'` (D12) y su test de claves.
6. Anclas nuevas: `home_exploracion`, `home_card_categorias` (rejilla);
   `categorias_lista`; `establecimientos_lista`, `establecimientos_filtros`;
   `top_servicios`; `ficha_local_servicios`. **Todas sobre elementos siempre montados**
   (encabezados, filtros), no sobre la primera tarjeta: así el paso no depende de que la
   lista tenga datos (lección de `catalogo_tarjeta`, `catalogo_screen.dart:556`).

**Criterio:** un `id` = un `TutorialAnchor`; el recorrido recorre los 13 pasos, navega
solo a las 3 vistas nuevas, se puede saltar, y no vuelve a aparecer tras completarlo
(clave `v2`); «Ver el tutorial otra vez» del perfil lo relanza y muestra la UI nueva.

### F9 — Verificación final
- `analyze` de `inventtia_flow`: **0 errores** (los avisos preexistentes de `print`,
  `withOpacity` y deprecaciones pueden seguir).
- `mcp__dart__run_tests`: baseline + nuevos, todo en verde.
- Revisión del diff completo por el Lead, incluido que **no** se aplicó SQL solo.
- Prueba manual (§7.3) y entrega al usuario de lo que hay que probar.

---

## 5. SQL — migración **57** (pendiente de aplicar por el usuario)

### 5.1 Qué hay que aplicar
`docs/flow_schema/migraciones/57_categorias_y_locales_cliente.sql` (nuevo). Crea dos
funciones y **no** toca ninguna tabla:

| Función | Firma | Devuelve |
|---------|-------|----------|
| `flow.cliente_categorias_resumen` | `()` | `{categorias:[{id,codigo,nombre,servicios,establecimientos,subcategorias:[{…,servicios,establecimientos}]}], total_servicios, total_establecimientos, otros_servicios, otros_establecimientos}` |
| `flow.cliente_locales_publicos` | `(p_id_categoria int, p_id_subcategoria int, p_provincia text)`, los tres con `default null` | array de locales con `foto`, `horario_atencion`, `horario_detalle`, `coordenadas`, `entidad{…}`, `total_servicios`, `tiene_reserva_directa`, `precios[]` (`config_precio` crudo), `total_resenas` y `rating` (promedio **real** por local, `null` sin reseñas) |

Las dos son `language sql`, `stable`, `security invoker`, con `search_path = flow, public`,
`revoke` de `public`/`anon` y `grant` a `authenticated, service_role` — igual que
`cliente_home_feed`. Llevan `notify pgrst, 'reload schema'` al final: sin eso la app
recibiría `PGRST202` durante un rato después de aplicarla.

Decisiones dentro del SQL:
- **Misma regla de visibilidad que el feed**: `flow._ls_disponible(ls.id)` (local, servicio,
  par y entidad al día) y exclusión de `flow.entidad_categoria_oculta` (hoja **y** padre).
  Así el contador de una categoría coincide con lo que se ve al entrar.
- **Categoría incluye subcategorías** (`s.id_tipo_actividad = p_id_categoria OR ta.id_padre
  = p_id_categoria`), y la subcategoría manda si llegan las dos.
- **El precio no se calcula en SQL**: la RPC devuelve el `config_precio` de cada servicio y
  Dart aplica `precioBaseDe` (`lib/utils/precio_reserva.dart`). Repetir la regla en SQL
  sería una tercera implementación de lo mismo.
- **El rating sí se agrega en SQL** (`sum(puntuacion)/count` por local): es el dato exacto,
  no la media de medias que habría que hacer en cliente.

### 5.2 Verificación hecha antes de escribir la función
Agregación validada con SQL de solo lectura contra `vsieeihstajlrdvpuooh` (sustituyendo
`_ls_disponible` por las columnas `activo`, porque el rol del MCP no puede ejecutar
`flow.entidad_activa`): **6 raíces** (Alojamiento 2/2, Gastronomía 0/0, Belleza 5/3,
Transporte 4/4, Recreación 0/0, Jurídicos 0/0) y **8 locales** con algo visible, de los
cuales solo «Salon 2 Cejas» tiene valoración (2.5 con 2 reseñas). El fichero lleva esas
mismas consultas en su bloque `VERIFICACION`.

### 5.3 Cómo aplicarla
A mano en el SQL Editor del proyecto **release** (D9 del plan anterior), y también en el de
debug si se quiere probar con `flutter run` (a ese le faltan las 40–56, así que el feed ni
se pinta). Mientras no esté aplicada, las tres pantallas nuevas muestran un aviso honesto
—«Esta vista necesita la migración 57 (categorías y establecimientos con contadores)»— con
botón de reintentar, en vez de un error de red genérico.

---

## 6. Tests

| Test | Qué cubre |
|------|-----------|
| `test/exploracion_resumen_test.dart` | contadores por categoría/subcategoría (los servicios de una hija suman a la raíz), `distinct` de locales, ítems sin nomenclador, local con 1 servicio, rating ponderado por reseñas, `null` sin reseñas, `precioDesde` por moneda, `abiertoAhora` con reloj inyectado, `topServicios` con límite y vacío |
| `test/exploracion_rapida_grid_test.dart` | 2×2 con 4 tarjetas, textos y badges de la referencia, chip «TODAS» sin nomenclador, los 4 callbacks, sin overflow a 320 pt y con `textScaleFactor` 1.3 |
| `test/categorias_screen_test.dart` | conteos pintados, despliegue de subcategorías, CTA con el número correcto, estados carga/error/vacío |
| `test/establecimientos_screen_test.dart` | orden por valoración con los sin reseñas al final, sin estrellas si no hay reseñas, filtros en memoria, chip de horario |
| `test/ficha_local_test.dart` | `FichaLocal.desdeCampana`/`desdeResumen`, envoltorio patrocinado con etiqueta «ESPACIO PATROCINADO», ficha normal con «ESTABLECIMIENTO» |
| `test/tutorial_flujos_test.dart` (actualizado) | 13 ids únicos, lista explícita de opcionales, destinos del cliente coherentes |
| `test/tutorial_navegacion_pasos_test.dart` (actualizado) | cada destino del cliente tiene traducción a pantalla |
| `test/tutorial_service_test.dart` (actualizado) | claves `v2` y visto/omitido/reiniciar |

Se conservan los **46 ficheros de test existentes** (47 `.dart` en `test/` menos
`flutter_test_config.dart`), en particular `home_feed_test.dart`,
`home_subcategorias_test.dart`, `coleccion_servicios_test.dart`,
`dropdown_sin_solape_test.dart`, `filtros_servicios_sheet_test.dart`,
`pista_busqueda_avanzada_test.dart`, `carrusel_tarjetas_test.dart` y
`appbar_contraste_test.dart`.

---

## 7. Riesgos, degradación y verificación manual

### 7.1 Riesgos
1. **El Home pierde el riel de categorías.** Es el cambio de flujo más visible: quien
   filtraba por categoría desde el Home ahora entra por la tarjeta «Categorías» (o por
   los filtros del sheet). Mitigación: el tutorial v2 abre esa ruta en los pasos 4-5 y el
   sheet de filtros sigue teniendo subcategorías.
2. **La migración 57 hay que aplicarla a mano.** Es el único paso que no controla el
   código: hasta que esté en Supabase, las dos pantallas nuevas avisan de que falta y el
   top 10 (que depende de la 36) sigue funcionando. Se degrada con mensaje, no con un error
   técnico.
3. **El rating por local viene del SQL** (`sum(puntuacion)/count` sobre `flow.resena`), así
   que es exacto, pero hoy hay **2 reseñas en toda la base**: los locales sin ninguna se
   pintan sin estrellas y van al final en «Mejor valorados». No se les supone una nota.
4. **Badge «N ACTIVAS» sin nomenclador.** Si la migración 47 no está aplicada,
   `metadata.categorias` llega vacío: el chip dirá «TODAS» y la pantalla de categorías
   mostrará su estado vacío, en vez de «0 ACTIVAS» o de inventar rubros.
5. **Refactor de la pantalla patrocinada.** Es la vista que más se ha tocado en el repo
   (49/56) y la rompe un cambio de constructor. Mitigación: envoltorio con la **misma**
   firma, test del envoltorio y `_abrirCampana` intacto.
6. **Tutorial republicado.** `v2` hará que el tutorial vuelva a salir una vez a todos los
   usuarios; es intencionado (D12) y hay que avisarlo en la entrega.
7. **13 pasos.** El overlay cambia a barra de progreso a partir de 8; el riesgo es de
   fatiga, no técnico. Recorte en D16 si lo prefieres.
8. **Anclas y listas perezosas.** Regla adoptada: anclar encabezados y filtros, nunca la
   primera tarjeta.
9. **Proyecto de debug.** Le faltan las migraciones 40-56 (§9 del plan anterior), así que
   **`flutter run` contra el proyecto debug no puede pintar el feed ni el ranking**.
   La prueba manual va contra release, o hay que aplicar la cola al proyecto debug.

### 7.2 Degradación honesta (regla del proyecto)
Ninguna tarjeta nueva muestra datos no respaldados: contadores reales, valoración solo si
hay reseñas, «Cerca de ti» solo con distancias, «Tendencias de la semana» mientras el RPC
sea semanal, y estados vacíos con mensaje en las tres pantallas. Es la misma regla que
sacó del Home los `_mockCatalog`, «Luna Studio» y el «20 % de descuento» inexistente.

### 7.3 Verificación manual (tras implementar)
1. Home: la rejilla sustituye al riel; los 4 chips y los 4 colores son los de la
   referencia; «N ACTIVAS» coincide con las raíces reales (6 con la 47 aplicada).
2. `Categorías` → lista con contadores; desplegar una categoría; tocar una subcategoría →
   establecimientos filtrados (comprobar que el filtro por categoría **incluye** las
   subcategorías).
3. `Establecimientos` → tarjetas con foto/valoración/servicios; filtrar por provincia y
   por «abierto ahora»; ordenar por mejor valorados y comprobar que los locales sin
   reseñas van al final.
4. Tocar un establecimiento → **la misma vista** que el espacio patrocinado, sin el sello
   «ESPACIO PATROCINADO», con todos sus servicios, y desde ahí reservar.
5. `Más populares` → 10 puestos con el número de lugares de la semana.
6. Tutorial: perfil → «Ver el tutorial otra vez»; recorrerlo entero, incluidos los saltos
   automáticos a las 3 pantallas nuevas; salir y volver a entrar: no se repite.
7. `dart analyze` y la suite, en verde.

---

## 8. Reparto sugerido (si se implementa en equipo)

Tras F1 (modelos + helpers, un solo escritor: es la base de todo), F3/F4/F5/F6 tocan
**ficheros disjuntos** y pueden ir en paralelo; F2 y F7 comparten
`home_client_screen.dart` y por eso van **en serie** (F2 → F7); F8 depende de F2-F7
porque sus anclas viven en las pantallas nuevas.

| Fase | Ficheros que escribe | Depende de |
|------|----------------------|------------|
| F1 | `lib/models/*`, `lib/utils/exploracion_resumen.dart`, `lib/services/exploracion_service.dart`, `test/exploracion_resumen_test.dart` | — |
| F2 | `lib/config/app_theme.dart`, `lib/utils/categoria_icono.dart`, `lib/widgets/exploracion_rapida_grid.dart`, `lib/screens/home_client_screen.dart` | F1 |
| F3 | `lib/screens/categorias_screen.dart` | F1 |
| F4 | `lib/screens/establecimientos_screen.dart` | F1 |
| F5 | `lib/models/ficha_local.dart`, `lib/screens/ficha_local_screen.dart`, `lib/screens/espacio_patrocinado_screen.dart` | F1 |
| F6 | `lib/screens/top_servicios_screen.dart` | F1 |
| F7 | `lib/utils/exploracion_navegacion.dart`, `lib/screens/home_client_screen.dart`, `lib/screens/home_shell.dart` | F2-F6 |
| F8 | `lib/tutorial/*`, `lib/services/tutorial_service.dart`, `lib/screens/home_shell.dart` | F2-F7 |
| F9 | verificación (Lead) | F1-F8 |

---

## 9. Bitácora de ejecución

| Fecha | Fase | Resultado |
|-------|------|-----------|
| 23-10-2026 | Plan | Auditoría del código real + verificación de RPC contra release. Referencia visual copiada a `docs/exploracion_rapida/`. **Sin cambios en `lib/`.** |
| 23-10-2026 | F1 | Modelos (`categoria_con_conteo`, `establecimiento_resumen`, `ficha_local`), helpers puros (`exploracion_resumen`, `categoria_icono`) y `ExploracionService`, con stubs de las 4 pantallas para que el proyecto compilara durante el reparto. **20/20 tests** de `exploracion_resumen_test.dart` en verde. Migración **57** escrita y su agregación validada antes con SQL de solo lectura contra release (6 raíces, 8 locales, Salon 2 Cejas 2.5 con 2 reseñas). |
| 23-10-2026 | F2 + F7 | `ExploracionRapidaGrid` (2×2, `mainAxisExtent` escalado con el texto para no desbordar a 320 pt ni al 130 %): 6/6 tests. Integración en el Home: fuera el riel de categorías, la fila de subcategorías y el estado `_category`/`_subcategoria`; `_aplicarCategorias` ya solo guarda el nomenclador; `_buildNoResults` sin las ramas de categoría. Las 4 tarjetas, el «Ver todos» de establecimientos y el «Ranking» navegan por `ExploracionNavegacion`. La sección de establecimientos del Home abre la **ficha**; se retiraron `onVerEstablecimiento` (Home y shell) y el ya huérfano `CatalogoScreenState.filtrarPorLocal`. |
| 23-10-2026 | F3–F6 (compañeros) | `CategoriasScreen` (CTA «Ver los N establecimientos» + chevron que despliega subcategorías, separados como pidió el usuario), `EstablecimientosScreen` (foto, valoración solo con reseñas, nº de servicios, orden y filtros), `FichaLocalScreen` compartida + envoltorio `EspacioPatrocinadoScreen` con la misma firma, y `TopServiciosScreen` (podio + 4-10, «Tendencias de la semana»). Cada uno con su test; analyze sin errores en sus ficheros. |
| 23-10-2026 | F8 | Tutorial del cliente **v2 de 13 pasos**: rejilla, «Ver catálogo», tarjeta Categorías, las tres pantallas nuevas y el top 10, con los 4 destinos nuevos (`listaCategorias`, `listaEstablecimientos`, `fichaEstablecimiento`, `topServicios`) resueltos por `TutorialNavegacion.irACliente` con las mismas rutas que las tarjetas. `TutorialService.version = 'v2'` para republicarlo una vez. Anclas nuevas sobre elementos siempre montados. |
| 23-10-2026 | F10 (3.er bloque) | **Barra inferior en las vistas nuevas.** `BarraNavegacionCliente` (widget compartido, extraído del shell junto con `IconoReservaConBadge`) + `ShellNavegacion` (puente estático que registra el shell: cierra lo apilado y cambia de pestaña). Las 4 pantallas la pintan con `BarraNavegacionCliente.dePantalla()` —`null` fuera del shell, así que los tests que las montan solas no cambian— y `HomeShell` usa la misma barra para el cliente puro. Además, «Ver el catálogo» del estado vacío del top 10 ahora cambia a la pestaña Servicios en vez de solo volver atrás. **8 tests nuevos** (`barra_navegacion_cliente_test.dart`); analyze sin errores y suite **600/600**. |
| 23-10-2026 | F11 (4.º bloque) | **Ajustes de la tarjeta del listado de establecimientos** (reportados al probar en la app): (1) el precio salía «picado» —«Desde 2500 CUP» en una línea dentro de una columna de 92 px se recortaba con puntos suspensivos—; ahora va en dos líneas («Desde» pequeño + importe) y el importe se reduce con `FittedBox` si hace falta, en vez de recortarse. Además el «desde» se calcula **en una sola moneda** (la del local, la de la mayoría de sus servicios) para no comparar importes de monedas distintas. (2) los chips pasan de `Wrap` (varias filas → tarjetas de alturas distintas) a **una fila con scroll horizontal**, y la tarjeta tiene alto fijo escalado con el texto del sistema, así que todas miden igual. **6 tests nuevos** (`establecimientos_tarjeta_test.dart`) y 2 en `exploracion_resumen_test.dart`; uno de ellos encontró el recorte real (92 px pintados vs 99.5 necesarios) antes de arreglarlo. Suite **608/608**. |
| 23-10-2026 | F12 (5.º bloque) | **La vista de categorías pasa a panel lateral con carpetas animadas.** `RutaLateral` (entra desde la izquierda, no opaca, 88 % con tope 372, velo que cierra) pero sigue siendo ruta: el `popUntil` del tutorial y la barra inferior no cambian. Dentro: rejilla de rubros **de dos en dos** con las mismas tarjetas del acceso rápido (`TarjetaExploracion` + `accionEtiqueta`/`onAccion`), chip `N LOCALES`, «Ver todos» por rubro, y al tocar la tarjeta se abre la **carpeta** del rubro: «boom» de la tarjeta (240 ms) → `AnimatedSwitcher` (fade + escala) → subcategorías en **cascada** (`Interval` + `easeOutBack`), con banner del rubro y «Ver todos los establecimientos». Con `disableAnimations` se abre sin animar. Tests reescritos (`categorias_screen_test.dart`, 9) y analyze limpio; suite **610/610**. Verificación independiente en `task-6`. |
| 23-10-2026 | F13 (5.º bloque) | **Verificación independiente** del panel (task-6, `panel-verifier`): `test/categorias_panel_extra_test.dart` con **20 tests** (ancho 343/372 medido, velo y X, ancla visible en carga/vacío/datos/error, las dos acciones separadas, `disableAnimations` abre en el mismo frame, doble toque rápido, rubros sin locales/sin hijas/nombres largos, 320 pt al 130 % y al 200 %, y `popUntil` con ruta NO opaca). 20/20 en verde. **Hallazgos corregidos**: (R1) `vacia` usaba «sin locales Y sin servicios» mientras el chip usa «sin locales» → ahora `establecimientos <= 0`; (R2) la carpeta abierta no se reconciliaba si el host cambiaba el resumen → `didUpdateWidget` la cierra y el índice del banner se guarda al abrir (sin `indexOf`); (R3) `RutaLateral` ignoraba `disableAnimations` → sin movimiento con el flag. Queda documentado (R4): el pie apagado de un rubro vacío deja pasar el toque a la tarjeta y abre la carpeta, que es preferible a una zona muerta. |
| 23-10-2026 | F9 | `mcp__dart__analyze_files` de todo el proyecto: **0 errores** (solo los avisos preexistentes de `print`, `withOpacity`, deprecaciones e imports muertos de HEAD; ninguno en los ficheros nuevos). **SQL no aplicado** (lo aplica el usuario, §5.3). |

Pendiente **fuera del código**: aplicar la migración **57** en release (y en debug si se
quiere probar con `flutter run`, que además necesita la cola 40–56).