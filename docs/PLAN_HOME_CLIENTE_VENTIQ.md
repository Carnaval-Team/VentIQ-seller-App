# Plan: Home tipo «cliente» para el TPV + detalle de producto optimizado

Rediseño del **home de `ventiq_app`** (web y APK) para que se vea y se sienta como el
home de cliente de `inventtia_flow`, con **categorías especiales** configurables desde
`ventiq_admin_app`, agrupación del resto bajo una categoría virtual **«Tienda»**, un
**drawer jerárquico a pantalla completa** y un **detalle de producto** que aproveche el
100 % de la pantalla en móvil.

Checklist de implementación. Marca `[x]` lo hecho, `[~]` parcial, `[ ]` pendiente.
Vamos avanzando fase por fase; no saltar dependencias.

> **Estado:** migraciones **aplicadas en producción y verificadas** (incluidas las 2 de la fase 4:
> contadores del Home y venta de elaborados por receta) · limpieza de duplicados **descartada** ·
> **Fases 1–5 completas + unificación visual del resto de la app** (198 tests en verde; incluye
> tema global, detalle, preorden, órdenes, settings, drawer y notificaciones) · pendiente: revisión
> visual en dispositivo y **Fase 6 (admin de categorías)**.
> **Fecha:** 2026-11-02 (última actualización) · **Alcance:** `ventiq_app` (web + apk), `ventiq_admin_app`, `supabase/migrations`.
> **Decisiones abiertas:** solo **D2** (nombre fijo «Tienda»). D3/D5/D6 quedaron implementadas de hecho:
> `orden_home`, un único `HomeShellScreen` y búsqueda inline.

---

## 1. Intent (referencia)

- **Outcome:** El vendedor que abre `ventiq_app` ve un home de catálogo tipo marketplace:
  hero con saludo, **buscador siempre visible**, tarjetas grandes de las categorías que el
  gerente marcó como **especiales** (p. ej. Combustibles, Servicios) y una tarjeta
  **Tienda** que agrupa el resto. Un toque abre un **drawer a pantalla completa** que baja
  por categoría → subcategoría → productos, con vuelta atrás evidente, y desde ahí se salta
  al **detalle del producto** sin pasar por el listado.
- **User:** Vendedor de mostrador en `ventiq_app` (móvil y navegador del TPV); **gerente**
  que marca las especiales en `ventiq_admin_app`.
- **Success:** (a) el home se ve como el de `inventtia_flow`; (b) llegar a un producto desde
  el home requiere **≤ 3 toques** (categoría → subcategoría → producto) y **≤ 2** si la
  categoría no tiene subcategorías; (c) no hay ninguna pantalla intermedia obligatoria;
  (d) una sola petición de red para pintar el home; (e) el gerente cambia qué es especial
  sin tocar SQL.
- **Constraint:** no romper venta, preorden, mesas, cocina, servicentro ni offline;
  `ventiq_app` no tiene gestor de estado (solo `setState` + servicios) y no se le va a meter
  uno pesado; SDK del TPV `^3.7.0`.
- **Out of scope:** reservas/turnos/sala de espera, reseñas, patrocinados, colecciones
  curadas, horarios comerciales, multi-moneda del marketplace, reescribir el checkout.

### Reglas de negocio

- [ ] Una categoría es **especial** en una tienda si `app_dat_categoria_tienda.especial = true`.
- [ ] Las especiales se pintan como tarjetas destacadas, ordenadas por `orden_home` y luego por nombre.
- [ ] **Todas** las no especiales (con productos vendibles en el TPV) se agrupan bajo la tarjeta virtual **«Tienda»**.
- [ ] Tocar una especial **sin** subcategorías → productos de esa categoría.
- [ ] Tocar una especial **con** subcategorías → drawer en su nivel de subcategorías.
- [ ] Tocar **«Tienda»** → drawer en el nivel de categorías no especiales.
- [ ] Dentro del drawer: categoría **con** subcategorías → baja un nivel; **sin** subcategorías → sus productos.
- [ ] Dentro del drawer: subcategoría → productos de la subcategoría, en el mismo drawer.
- [ ] Se puede **volver un nivel** sin cerrar el drawer, y **salir** sin usar la «X».
- [ ] Tocar un producto → **detalle directo**, con los datos ya cargados.
- [ ] Siempre hay un camino explícito al **listado completo** (`ProductsScreen`).

---

## 2. Decisiones a confirmar

| # | Pregunta | Recomendación | Alternativa | Impacto si cambia |
|---|---|---|---|---|
| **D1** | ¿Dónde vive el flag «especial»? | **`app_dat_categoria_tienda.especial`** — es la tabla puente por tienda; `app_dat_categoria` es un **nomenclador global compartido** y marcarlo ahí filtraría entre tiendas (ver §3.2) | `app_dat_categoria.es_especial` (1 `ALTER`, pero la marca se filtra a todas las tiendas que compartan la categoría) | Cambia la migración, el `update` del admin y la RPC |
| **D2** | ¿«Tienda» es nombre fijo? | Sí, constante (`kNombreTienda = 'Tienda'`) | Columna `app_dat_configuracion_tienda.nombre_categoria_tienda` | Añade columna + UI |
| **D3** | ¿Orden de las especiales? | `orden_home smallint` en `app_dat_categoria_tienda`, editable en el admin | Orden alfabético puro | Simplifica la migración |
| **D4** | ¿Qué hacemos con `FluidModeScreen`? | **Deprecar**: prototipo morado con `Future.delayed` de mentira y `_processOrder` sin `await` (`fluid_mode_screen.dart:49,94`). Su idea se absorbe en el drawer + detalle | Arreglarlo y rebrandearlo | Cambia el destino del toque en categoría con «modo fluido» |
| **D5** | ¿Web y móvil comparten pantalla? | **Sí**: una `HomeShellScreen` responsive; se elimina la duplicación `categories_screen.dart` / `categories_web_screen.dart` | Mantener dos pantallas | Duplica el rediseño ×2 |
| **D6** | ¿Buscador: resultados inline u overlay? | **Inline**: reemplazan el lienzo, con «limpiar» para volver (patrón de `catalogo_screen.dart`) | Conservar el overlay actual | Cambia el estado, no los widgets |
| **D7** | Hay **1056 categorías para 343 nombres** y una tienda con **208 homónimas** (§5.6). ¿Qué hacemos? | **Defensa en la RPC** (colapsar por nombre, sumar contadores, `grupo_ids`) **ya**, y limpieza de datos **después** con respaldo | Bloquear el rediseño hasta limpiar los datos | Sin defensa, el home de esa tienda es inutilizable |

> Sin respuesta a D1–D6 se implementa la columna «Recomendación».

### 2.1 Decisiones confirmadas (2026-10-31)

| # | Decisión | Efecto |
|---|---|---|
| **D1** | **Por tienda** | El flag vive en `app_dat_categoria_tienda.especial` + `orden_home`. ⚠️ `app_dat_categoria` **no tiene** `id_tienda`: es un nomenclador global; la relación por tienda es la tabla puente. Mismo resultado que pediste, pero en la tabla correcta (marcar en una tienda no afecta a otra). |
| **D4** | **Deprecar `FluidModeScreen`** | Se elimina en Fase 7 junto con `fluid_product_details_widget.dart` y `product_search_widget.dart`. Hasta entonces no se toca. |
| **D7** | **Sí: mitigar la duplicación** — solo con el colapso por denominación en `get_home_catalogo_tpv` (§5.3). **La limpieza de datos queda DESCARTADA** por decisión del usuario (2026-10-31): no se ejecuta. Ver §5.6.1 |

---

## 3. Hallazgos del reconocimiento

> Verificado **contra la base viva** (Supabase MCP) y contra el código. Las RPC de
> categorías **no tienen `CREATE FUNCTION` en el repo** — se volcaron con
> `pg_get_functiondef()` y ese volcado es la fuente de verdad (§5.4).

### 3.1 `ventiq_app` — home actual

| Aspecto | Hoy |
|---|---|
| Pantallas | `categories_screen.dart` (1780 líneas, móvil) y `categories_web_screen.dart` (1216, web) — **casi duplicadas** |
| Ruteo | `main.dart:133` → `/categories` ⇒ `PlatformAwareCategoriesScreen` (`main.dart:237-246`) elige web/móvil |
| Datos | `CategoryService.getCategories()` → RPC **`get_categorias_by_tienda_tpv`** (`category_service.dart:33-42`), con `idTienda`/`idTpv` de preferencias |
| Modelo | `Category {id, name, description, imageUrl, color, isActive, productCount}` (`category_service.dart:91`) |
| Lo visual | `GridView.builder` 2 columnas, `childAspectRatio: 0.85`, spacing 8, padding 16 (`categories_screen.dart:1118-1124`); card = `Container` de **color plano** derivado de un hash del nombre (`_generateCategoryColor`, `category_service.dart:69`), con imagen rotada de marca de agua (`:1585`), borde gris 0.5 y escala 1→0.95 al pulsar |
| Toque | `ProductsScreen(categoryId:, categoryName:, categoryColor:)` o `FluidModeScreen` si «modo fluido» (`categories_screen.dart:1530-1551`) |
| Buscador | Vive en `AppBar.bottom` (`PreferredSize` 72), **oculto por defecto**: se abre con el `IconButton(Icons.search)` de `actions` (`categories_screen.dart:942-962`). Debounce 320 ms; resultados en un **overlay** a pantalla completa (velo negro 0.25, tarjeta radio 16, `maxHeight` 55 %). No es un widget reutilizable y está **duplicado** en web. `product_search_widget.dart` es otro camino peor (RPC sin `text_search` que baja el catálogo completo) y solo lo usa el modo fluido |
| Estado | `setState` puro; **cero** `ChangeNotifier`/`Provider` en todo `lib/` (verificado por grep) |

Nada de esto soporta categorías especiales, agrupación «Tienda» ni subcategorías en el home.

### 3.2 Backend real — esquema y multi-tenant

```
public.app_dat_categoria                  ── NOMENCLADOR GLOBAL (1056 filas)
  id bigint PK · denominacion varchar NOT NULL · descripcion varchar
  sku_codigo text NOT NULL · image text · created_at timestamptz
  visible_vendedor boolean DEFAULT true · para_catalogo boolean DEFAULT false
  ← NO tiene id_tienda / id_empresa, ni orden, ni padre, ni flag de destacada

public.app_dat_categoria_tienda            ── PUENTE por tienda (1154 filas, 106 tiendas)
  id bigint PK · id_categoria → app_dat_categoria(id) · id_tienda → app_dat_tienda(id)
  id_cocina → app_dat_cocina(id) · created_at
  ← aquí vive la config POR TIENDA (ya existe `id_cocina`) ⇒ aquí va `especial`

public.app_dat_subcategorias               ── 2 niveles, tabla aparte (2016 filas)
  id · idcategoria → app_dat_categoria(id)   ← ojo: `idcategoria`, sin guion bajo
  denominacion · sku_codigo · created_at

public.app_dat_productos_subcategorias     ── N:M producto ↔ subcategoría (9513 filas)
  id · id_producto · id_sub_categoria · created_at
```

⚠️ **Corrección importante:** `app_dat_categoria` **no es por tienda**. Es un nomenclador
global; el vínculo multi-tenant vive en `app_dat_categoria_tienda`. Hoy 98 categorías están
compartidas entre más de una tienda ⇒ poner el flag en `app_dat_categoria` haría que marcar
«Combustibles» como especial en un servicentro la marcaría también en cualquier otra tienda
que la use. **Por eso D1 recomienda la tabla puente.**

Además: un producto tiene **una** categoría (`app_dat_producto.id_categoria`) y **varias**
subcategorías (vía `app_dat_productos_subcategorias`). El listado devuelve ambas.

Índices reales: solo PKs + `idx_subcategorias_categoria (idcategoria, id)` y tres índices en
`app_dat_productos_subcategorias`. **No hay `UNIQUE (id_categoria, id_tienda)`** — pero se
comprobó que **hoy no hay duplicados** (0 pares) ⇒ el índice único del §5.1 es seguro.

### 3.3 RLS, GRANTs y permisos (verificado en vivo)

| Tabla | RLS | Policy | `authenticated` UPDATE | `anon` SELECT |
|---|---|---|---|---|
| `app_dat_categoria` | ON | `prod_cat` · ALL · public · `true` | ✅ `true` | ✅ `true` |
| `app_dat_categoria_tienda` | ON | `category_tienda` · ALL · public · `true` | ✅ `true` | (n/d) |
| `app_dat_subcategorias` | ON | `subcategoria` · ALL · public · `true` | — | — |
| `app_dat_productos_subcategorias` | ON | `prodcuto subcategoria` · ALL · public · `true` | — | — |

- Como las policies son `ALL` (incluye `UPDATE`), **el admin sí puede actualizar
  `app_dat_categoria_tienda`** — es el punto que el reconocimiento marcó como riesgo de
  «fallo silencioso» y quedó **descartado**: el permiso existe. Aun así, `updateCategory`
  atrapa la excepción y devuelve `false` (`category_service.dart:368-371`), así que **hay
  que registrar el error del update nuevo**, no solo devolver `false`.
- **Deuda de seguridad preexistente:** `anon` puede leer todo el nomenclador de categorías.
  Fuera del alcance, pero anotarlo.
- No hay `SELECT *` sobre `app_dat_categoria` en el código ⇒ añadir columnas no rompe nada.
  El único `SELECT *` (`subcategory_service.dart:71`) es sobre subcategorías y es tolerante.

### 3.4 RPCs — firmas reales (volcadas de la BD)

| Función | Firma real | Consumidor |
|---|---|---|
| `get_categorias_by_tienda_tpv(p_tienda_id, p_tpv_id)` | `id, nombre, descripcion, tienda_id, imagen, total_productos` | **home del TPV** |
| `get_categorias_by_tienda_tpv2(...)` | ídem | variante |
| `get_categorias_by_tienda_complete(p_id_tienda)` | `id, denominacion, descripcion, sku_codigo, image, created_at, categoria_tienda_id, categoria_tienda_created_at` — `SECURITY DEFINER`, `INNER JOIN app_dat_categoria_tienda` | **admin** |
| `get_subcategorias_by_categoria(p_id_categoria)` | `id, denominacion, sku_codigo, created_at, total_productos` | admin + TPV; **sin filtro de TPV ni stock** |
| `get_productos_by_categoria_tpv_meta2(id_categoria, id_tienda, id_tpv, solo_disponibles)` | `…, precio_venta, imagen, stock_disponible, tiene_stock, metadata jsonb` | listado |
| `get_productos_by_categoria_tpv_search_meta_v3(...)` | ídem + `text_search` | búsqueda |
| `get_productos_by_subcategoria(id_tienda, id_subcategoria, solo_disponibles)` | **sin `imagen`, sin `stock_disponible`, sin `metadata`** | ⚠️ **hueco**: hoy no se puede pintar una card de producto por subcategoría |
| `sync_bundle(id_tienda, id_tpv)` | `jsonb`; agrega con `to_jsonb(c)` sobre la RPC del TPV (`ventiq_app/sql_offline/03_sync_bundle.sql:28-46`) | caché offline ⇒ **propaga columnas nuevas solo** |

`metadata jsonb` trae `{es_elaborado, es_servicio, …}` ⇒ la card puede pintar su badge sin
pedir nada más.

### 3.5 Caché offline — el eslabón que hay que tocar

`ventiq_app/lib/services/offline_database_service.dart`:
`offline_categories (id, denominacion, payload TEXT, updated_at)` (`:134-141`); al guardar,
`payload = jsonEncode(map)` completo (`:525`) ⇒ **no hace falta migrar SQLite ni subir
`_dbVersion`**. Pero hay **tres sitios con listas explícitas de campos** que descartan
cualquier campo no listado:

1. `auto_sync_service.dart:441-454` → `{'id','name','imageUrl','color'}` ⇒ **aquí se pierde el
   flag antes de llegar a SQLite**.
2. `settings_screen.dart:4578-4597` → **una segunda copia del mismo mapeo** (misma lista de 4
   campos). Si solo se arregla la primera, el flag se sigue perdiendo por este camino.
3. `categories_screen.dart:300-318` → reconstruye desde el JSON leyendo solo `nombre`,
   `imageUrl`/`imagen`/`image`, `descripcion`, `activo`, `total_productos`.

⇒ **Los tres hay que tocar.** Con uno solo, la categoría se ve correcta online y pierde el flag
offline (o lo pierde según por qué camino se sincronizó).

### 3.6 `inventtia_flow` — el look & feel a replicar

**Jerarquía del home** (`home_client_screen.dart:660-737`, `CustomScrollView` de 13 slivers,
**sin `SliverAppBar`**): top bar degradado → buscador + chips → exploración rápida →
patrocinados → ofertas → servicios → establecimientos → ranking → reseñas → colecciones →
fidelidad → cómo funciona → feed paginado.

**La card del inicio** (`widgets/exploracion_rapida_grid.dart:178-314`) — el ADN a copiar:

```dart
ClipRRect(borderRadius: BorderRadius.circular(22),
  child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colores)),
    child: Material(color: Colors.transparent, child: InkWell(onTap: onTap,
      child: Stack(children: [
        Positioned(right: -10, bottom: -14,
          child: Icon(icono, size: 76, color: Colors.white.withValues(alpha: 0.08))),
        // chip 9/w800/ls .7 · tile de icono 32×32 radio 10 · título 19/w800/-0.3
        // subtítulo 12/w500/white .80 · pastilla de pie opcional 10/w800
      ])))));
```

| Token | Valor |
|---|---|
| Radio de tarjeta | **22** (16 theme · 17 cards de riel · 20-24 bloques · 14 campo · 8-10 chip) |
| Gradiente | 2 colores `topLeft → bottomRight`; marca de agua `76`, `white .08`, `right -10 / bottom -14` |
| Chip superior | `padding 8/4`, radio 8, `white .18`, borde `white .22`, texto `9/w800/ls .7` |
| Tile de icono | `32×32`, radio 10, `white .16`, borde `white .22`, icono 17 |
| Título / subtítulo | `19 / w800 / h 1.1 / ls -0.3` · `12 / w500 / h 1.15 / white .80` |
| Rejilla | 2 columnas, spacing 12, `mainAxisExtent = 122 * textScale` (134 en categorías) |
| Rótulo de bloque | `12.5 / w800 / ls 1.6` + acción `11 / w800 / #00BCD4` |
| Sombra canónica | `0x0D2B3A67 blur 12 offset(0,5)` |
| Paleta | `primary #405F90` · `accent #00BCD4` · `surface #F5F7FA` · `textPrimary #1A237E` · `textSecondary #546E7A` · `border #E0E6ED` |
| Gradientes | indigo `#4F5C8B→#3B4A7E` · teal `#1FA8B8→#1593A3` · navy `#424A65→#2C3654` · coral `#FF4E5F→#E8394C` |
| Tipografía | Inter (`GoogleFonts.interTextTheme()`) |

**Buscador «entre el appbar y el lienzo blanco»** (`home_hero_header.dart:6-38` + `:825-971`):
`Column[ topBar, Stack[ Positioned(h:26, color #3E4E80), searchCard ] ]`. La tarjeta blanca
(radio 20, sombra `0x1A2B3A67 blur22 dy9`, padding 12/12/12/10) **tapa los primeros 26 px de
la banda índigo** y deja 16 px de gutter ⇒ «flota» sobre la costura hero/lienzo. Dentro:
campo `surface` radio 14 + `TextField(prefixIcon: search_rounded, suffix: [voz, tune_rounded
con Badge.count])`, y debajo chips horizontales de 28 px. Ojo: **en el home de flow el
buscador NO es sticky** (se va con el scroll); el que sí es fijo es el de `catalogo_screen.dart:499-580`
(`Column` fuera del `ListView`). **Para este plan se quiere el patrón fijo del catálogo.**

**El drawer jerárquico** (`screens/categorias_screen.dart` + `utils/ruta_lateral.dart`):
- **Ruta lateral** (`PageRouteBuilder` transparente, slide `-1,0 → 0`, 260/190 ms) con velo
  `black .42` y panel `width: min(372, ancho*0.88)`. **No es `Drawer` de Scaffold** — el
  comentario de `ruta_lateral.dart:5-15` explica que un `Scaffold.drawer` rompería el botón
  atrás del sistema y el `popUntil` del tutorial.
- **Un solo nivel de estado**: `CategoriaConConteo? _abierta`. `AnimatedSwitcher(300 ms)` entre
  `KeyedSubtree('rejilla-rubros')` y `KeyedSubtree('carpeta-<id>')`, con `Fade + Scale(0.90→1, easeOutBack)`.
- **«Boom» al abrir**: marca `_boom`, espera **190 ms** (la tarjeta late `0.86→1` en 240 ms
  `easeOutBack`) y luego cambia de nivel. Sin ese latido el toque no tiene respuesta visual.
- **Cascada** de subcategorías: `Interval(min(0.14*i, 0.55), 1)`, 430 ms, `easeOutBack`.
- **Volver**: `IconButton(Icons.arrow_back_rounded, 'Volver a los rubros')`. **No hay swipe-back
  ni breadcrumb** — justo lo que el usuario pide mejorar.
- **Cerrar**: solo «X», tap en velo o botón atrás. **No hay drag-down**.
- **Dos acciones que no se mezclan**: tocar tarjeta = abrir carpeta; tocar el pie «Ver todos» =
  ir al listado, con su propio `GestureDetector` (`exploracion_rapida_grid.dart:396-400`).
- El nivel de servicios **no** está en el drawer: es un drawer de **2 niveles**.

> Molde alternativo del repo: `mostrarFiltrosServicios` (`filtros_servicios_sheet.dart:319`),
> `showModalBottomSheet(isScrollControlled, useSafeArea, transparent)` +
> `DraggableScrollableSheet(initial .84, min .45, max .96, snap)`. Sirve para pickers, no para
> el drawer principal.

### 3.7 `ventiq_admin_app` — dónde se gestiona categorías

- Modelo `Category` (`models/category.dart`) con `visibleVendedor` — **el precedente exacto**.
  ⚠️ Tiene campos **muertos** que la RPC no devuelve y quedan en default: `isActive`,
  `sortOrder`, `level`, `parentId`, `commission`, `tags` (`:58-64`). **No imitar ese patrón**:
  el flag nuevo debe ir de verdad a `fromJson`/`toJson`.
- `CategoryService` (`services/category_service.dart`, 444 líneas):
  `getCategoriesByStore()` → RPC `get_categorias_by_tienda_complete` (`:28`);
  `createCategoryWithId()` inserta en `app_dat_categoria` (`:287-298`) y **luego** en
  `app_dat_categoria_tienda` (`:307-310`);
  `updateCategory()` hace `.update()` **solo** sobre `app_dat_categoria` (`:361-364`) —
  **nunca toca la puente**, y con D1 el flag vive en la puente ⇒ hay que añadir esa escritura.
- ⚠️ **`screens/categories_screen.dart` es un MOCK**: `_loadCategoriesData()` carga
  `MockDataService.getMockCategories()` (`:38-47`) y la ruta `/categories` (`main.dart:217`)
  apunta ahí. **La gestión real está en `widgets/categories_tab_view.dart`**, embebido en
  Ajustes (`settings_screen.dart:216`). El switch va en `categories_tab_view.dart`.
- Puntos exactos de inserción en `categories_tab_view.dart`:
  - `_AddCategoryDialog`: estado `_visibleVendedor` en `:1044`; bloque a clonar `:1218-1264`;
    insertar después de `:1264`; envío `_createCategory()` `:1112-1134`.
  - `_EditCategoryDialog`: estado en `:1394`; `initState` que hidrata `:1397-1403`;
    bloque a clonar `:1522-1568`; insertar después de `:1568`; envío `_updateCategory()` `:1413-1434`.
  - `_ChangeImageDialog` vuelve a llamar `updateCategory` en `:2622` ⇒ si el flag es
    **nullable** sigue compilando; si es `required`, hay que tocarlo.
  - `CategoryGenerationService.createCategories` (`category_generation_service.dart:122-127`)
    llama `createCategoryWithId` ⇒ con default `= false` sigue compilando.

### 3.8 Detalle de producto actual — por qué es lento y desperdicia pantalla

`screens/product_details_screen.dart` — **4090 líneas** reales, `AppBar` + `AppBottomNavigation`
+ `SingleChildScrollView` (`:1591`, `:1648`, `:1715`). Fuentes: `get_detalle_producto`,
`app_dat_producto_presentacion`, `PromotionService`, `CurrencyService`, `OrderService`,
`PreviewRebalanceoService`, `DesarmeBultoLocal`, `PriceChangeService` y `ElaboratedProductChip`.

**Desperdicio de pantalla (medido sobre §4.A del reconocimiento):**

| # | Problema | Cifra |
|---|---|---|
| 1 | «Chrome» permanente antes de ver contenido: `AppBar` 56 + `AppBottomNavigation` 56 + barra TOTAL/Agregar ~74 | **~186 px de ~640-700 útiles (≈29 %)**. La barra de navegación está **duplicada** con la barra de acción, y en el detalle el tab activo no existe |
| 2 | **Los controles de venta no existen hasta tocar una variante**: `_buildSelectedProductItem` (que contiene el selector de presentación, el de incremento y los botones −/cantidad/+) solo se pinta si `selectedQuantity > 0` (`:1929-1930`, `:1941-1943`). Con variantes la cantidad arranca en 0 ⇒ el vendedor ve la lista «UBICACIONES» **sin ningún control de venta** | bloquea la venta hasta un toque «a ciegas» |
| 3 | Aire acumulado antes del primer control: padding 16 + imagen fija 120×120 + `SizedBox` 24/16/16 + 12/8/8 + padding 16 | **~110-130 px** |
| 4 | El bloque «UBICACIONES» completo va **antes** de cualquier control y solo hay auto-selección cuando hay **una** ubicación (`:3172`) | con 2-3 almacenes, obliga a elegir almacén antes de poder vender |
| 5 | Listado con `ListView` horizontal anidado de columnas de 3 (`products_screen.dart:867-911`, ancho `screenWidth*0.85`) + `MarqueeText` animado por tarjeta + `addAutomaticKeepAlives: true` en web | scroll anidado y N animaciones vivas |

**Lentitud de acceso:**

| # | Problema | Detalle |
|---|---|---|
| 1 | **El listado entrega `variantes: []` hardcodeado** (`product_service.dart:372`) ⇒ el detalle **siempre** re-consulta `get_detalle_producto` + presentaciones. Cerrar y reabrir el mismo producto lo vuelve a pagar | es el punto central para «acceso rápido» |
| 2 | **`ElaboratedProductChip` montado en la cabecera** (`:1872-1876`) dispara una cascada **serial** en **toda** apertura: `isProductElaborated` (un `SELECT … single()` **aunque el detalle ya trajo `es_elaborado`/`es_servicio`**) + `isProductServicio` + `getProductIngredients` → `SELECT` a `app_dat_producto_ingredientes` + **N RPC `fn_stock_producto_almacen_detalle` en bucle `await`** (`elaborated_product_chip.dart:34-52`, `product_detail_service.dart:630-729`) | un plato de 8 ingredientes = **8 RPC seriales + 4 queries** por apertura, aunque nadie toque el chip |
| 3 | Parseo offline O(categorías × productos) **dos veces** por apertura (`:631-643` y `:1055-1069`) | en tiendas con catálogo grande, coste lineal |
| 4 | `_loadProductDetails` reconstruye las variantes a mano (**~140 líneas**, `:661-801`) duplicando `ProductDetailService._transformInventoryToVariants` (`:324-470`) | dos implementaciones a mantener en sincronía |
| 5 | 7 fetches sin `await` en `initState` (`:160-166`) + **`_loadUsdRate` cuyo resultado no se muestra** (`_buildUsdRateChip :4001-4041` está muerto) + doble validación de stock (`:119-144` y `:887-914`) | red gratis en cada apertura |

**Código muerto confirmado** (candidato a borrar en Fase 7):
`_buildUsdRateChip` (`:4001-4041`, 41 líneas), `_getTotalItems` (`:2979-2989`), el estado
`_selectedPresentation` (`:81`, nunca se lee), el `ElaboratedProductChip` comentado en la AppBar
(`:1616-1620`), y en `products_screen.dart` `_ProductCard` + `_PropertyIcon` (`:1387-1759`,
**~373 líneas** que nunca se instancian).

**Huecos funcionales que bloquean requisitos del usuario:**
- `ProductsScreen` **no acepta subcategoría** (`products_screen.dart:32-46`) ⇒ para «ver el
  listado completo» de una subcategoría hay que añadir el parámetro.
- **`id_subcategoria` se descarta**: la RPC lo devuelve (`43_catalogo_stock_mixto_v3.sql:209`)
  pero `_convertSupabaseToProduct` (`product_service.dart:324-395`) **nunca lo lee**; solo usa el
  nombre como clave de agrupación ⇒ sin tocar el parser no se puede filtrar por subcategoría.
- Como la agrupación es por clave de `Map` sin `GROUP BY`, un producto en dos subcategorías
  **aparece repetido en dos secciones**.
- Etiqueta inconsistente online/offline: `'Sin subcategoría'` (`product_service.dart:99`) vs
  `'General'` (`:159`).

### 3.9 Alcance real en el monorepo

| App | Referencias a las tablas | Impacto |
|---|---|---|
| `ventiq_admin_app` | muchas | origen del cambio |
| `ventiq_app` | varias | consumidor |
| `ventiq_marketplace` | 10 | hereda columnas; sus `.select()` son explícitos ⇒ **no se rompe**. `ensureCategoriaTiendaLink` (`store_management_service.dart:231-248`) inserta sin `especial` ⇒ default `false`, correcto |
| `ventiq_superadmin`, `inventtia_flow` (esquema `flow.*` aparte), `ventiq_licencer_express`, `inventtia_muevete` | **0** | sin impacto |

**No son 7 apps sobre estas tablas: son 3.**

### 3.10 Inventario de duplicación a eliminar

El rediseño unifica web y móvil en `HomeShellScreen`, así que la mayor parte de esta
duplicación se va sola. Se deja inventariada para no perderla de vista:

| Bloque repetido | Móvil | Web | ≈ líneas |
|---|---|---|---|
| `_buildSearchResultsOverlay` | `categories_screen.dart:622-856` | `categories_web_screen.dart:401-615` | **450** |
| `_buildSearchBar` | `:579-620` | `:358-399` | 84 |
| `_buildSearchStockChip` | `:900-919` | `:667-684` | 38 |
| `_buildUsdRateChip` | `:858-898` | `:617-657` | 82 |
| `_toggleSearch` + `_onSearchChanged` + `_performProductSearch` (debounce 320 ms) | `:450-577` | `:246-356` | 239 |
| `_loadCategories` + mapeo offline→`Category` | `:266-361` | `:119-187` | 165 |
| `_loadUsdRate` / `_loadShowSkuSetting` / `_loadOfflineModeSettings` / `_setupSmartOfflineListener` / `_redirectIfInventoryOnly` | `:104-174`, `:363-381` | `:71-76`, `:189-243` | 230 |
| `_getCategoryIcon` (copia literal, mismos 6 casos) | `:1720-1737` | `:1198-1214` | 35 |
| Card de categoría | `_CategoryCard` `:1473-1777` (**305**) | `_CategoryWebCard` `:953-1215` (**263**) | **568** |
| `_onBottomNavTap` (mismos 4 casos) | `:1145-1180` | `:916-950` | 71 |
| Mapeo de categorías para caché offline | `auto_sync_service.dart:441-453` | `settings_screen.dart:4578-4597` | 33 |
| Reconstrucción de variantes desde inventario | `product_details_screen.dart:661-801` | `product_detail_service.dart:324-470` | **~140** |

**Orden de extracción por retorno** (todo entra en el rediseño salvo lo marcado):
1. `TarjetaExploracion` único — con `isWeb` para hover/gradiente/radio y **mostrando `productCount`**
   (hoy el RPC lo calcula y `_CategoryCard` lo descarta: `categories_screen.dart:1128-1138`).
2. `HomeBuscador` + `HomeSearchController` — barra, debounce y resultados en un solo sitio
   (elimina ~450 líneas duplicadas y de paso arregla que la web no valide stock).
3. `UsdRateChip(tamaño)` — 3 copias (2 vivas + 1 muerta).
4. `CategoriaIconoResolver` — el mismo `switch` en 2 archivos.
5. `ProductDetailsLoader` — unifica `ProductDetailService` con el parseo offline (§8).
6. `BottomNavHandler` — 4 `switch` idénticos.

---

## 4. Arquitectura propuesta

### 4.1 Archivos nuevos en `ventiq_app`

```
lib/theme/ventiq_home_theme.dart        # ✅ tokens del home
lib/utils/categoria_icono.dart          # ✅ categoría → IconData por palabra clave (es)
lib/utils/categoria_gradiente.dart      # ✅ id/nombre → par de colores estable
lib/models/home_catalogo.dart           # ✅ HomeCatalogo, HomeCategoria, HomeSubcategoria, HomeProducto
lib/services/home_catalog_service.dart  # ✅ gateway + RPC + caché memoria + snapshot
lib/controllers/home_controller.dart    # ✅ ChangeNotifier: agrupación, búsqueda, pila del drawer
lib/widgets/home/
  home_hero_header.dart                 # ✅ banda degradada + saludo + campana/avatar
  home_buscador.dart                    # ✅ buscador "flotante" siempre visible
  home_catalogo_view.dart               # ✅ el contenido, puro y probable
  home_quick_chips.dart                 # ✅ chips rápidos
  tarjeta_exploracion.dart              # ✅ LA card (port de flow + modo imagen)
  home_seccion_titulo.dart              # ✅ rótulo 12.5/w800/ls 1.6 + acción cyan
  ventiq_skeleton.dart                  # ✅ placeholder con pulso (sustituye a shimmer)
  tienda_card.dart                      # ✅ tarjeta virtual "Tienda"
  categoria_drawer.dart                 # drawer full-screen jerárquico   ← pieza central
  drawer_nivel_categorias.dart          # nivel 0
  drawer_nivel_productos.dart           # nivel 1
  producto_tile.dart                    # fila compacta de producto
  home_estado_vacio.dart                # ✅ sin categorías / sin resultados / error
lib/widgets/usd_rate_chip.dart          # ✅ chip de tasa (3 copias → 1)
lib/screens/home_shell_screen.dart      # ✅ pantalla única web+móvil
lib/screens/product_details_screen.dart # rediseñada (§8)
```

`main.dart:133` pasa a `'/categories': (_) => const HomeShellScreen()`, y `/categories-mobile`
y `/categories-web` apuntan al mismo shell para no romper deep links ni `NavigationHelper`.

### 4.2 Estado, sin meter provider

`HomeController extends ChangeNotifier` (de `package:flutter/foundation.dart`, sin dependencias
nuevas) + `ListenableBuilder`. El resto de la app sigue con `setState`; no se migra nada.

```dart
class HomeController extends ChangeNotifier {
  HomeEstado estado = HomeEstado.cargando;
  List<HomeCategoria> especiales = const [];
  List<HomeCategoria> tienda = const [];        // no especiales, bajo "Tienda"
  String query = '';
  List<HomeProducto> resultados = const [];
  List<HomeCategoria>? nivelCategorias;         // drawer, nivel 0
  List<HomeProducto>? nivelProductos;           // drawer, nivel 1
  Future<void> cargarHome({bool forceRefresh = false});
  Future<void> abrirTienda();
  Future<void> abrirEspecial(HomeCategoria c);
  Future<void> abrirCategoria(HomeCategoria c);  // baja nivel o va a productos
  Future<void> abrirSubcategoria(HomeSubcategoria s);
  void volverNivel();
  void buscar(String q);                         // debounce 250 ms
}
```

### 4.3 RPC nuevas (aditivas; no se toca ninguna RPC del TPV en uso)

- **`get_home_catalogo_tpv(p_tienda_id, p_tpv_id)`** → una sola llamada para todo el home:
  `(id, nombre, descripcion, imagen, especial, orden_home, total_productos, total_subcategorias)`.
- **`get_subcategorias_by_categoria_tpv(p_id_categoria, p_tienda_id, p_tpv_id)`** → subcategorías
  con `total_productos` **real del TPV** (la actual no filtra stock ni almacén ⇒ números inflados).
- **`get_productos_by_subcategoria_tpv_meta(p_tienda_id, p_tpv_id, p_id_subcategoria, p_text_search, p_solo_disponibles)`**
  → mismo `RETURNS TABLE` que `get_productos_by_categoria_tpv_meta2`; cierra el hueco de §3.4.
- `get_categorias_by_tienda_tpv` **se deja intacta** (la usan TPV y `sync_bundle`).

---

## 5. Modelo de datos y migración

### 5.1 Migración 1 — flag por tienda

`supabase/migrations/20261101120000_add_especial_categoria_tienda.sql`

```sql
-- ============================================================================
-- Categorías "especiales" POR TIENDA para el home tipo cliente del TPV.
-- El home muestra las especiales como tarjetas destacadas y agrupa TODAS las
-- no especiales bajo la categoría virtual "Tienda".
-- Aditivo: no cambia columnas existentes ni el RETURNS TABLE de ninguna RPC
-- que use el TPV.
-- ============================================================================

-- 1. Flags en la tabla puente (config por tienda).
alter table public.app_dat_categoria_tienda
  add column if not exists especial   boolean  not null default false,
  add column if not exists orden_home smallint not null default 0;

comment on column public.app_dat_categoria_tienda.especial is
  'Home del TPV: true = tarjeta destacada; el resto se agrupa bajo "Tienda".';
comment on column public.app_dat_categoria_tienda.orden_home is
  'Orden de las tarjetas especiales (menor primero). 0 = desempata por denominación.';

-- 2. Índice parcial: el home solo pregunta por las especiales de una tienda.
create index if not exists idx_app_dat_categoria_tienda_especial
  on public.app_dat_categoria_tienda (id_tienda)
  where especial;

-- 3. Red de seguridad multi-tenant: un solo vínculo por (tienda, categoría).
--    Verificado: hoy hay 0 pares duplicados, así que es seguro crearlo.
create unique index if not exists uq_app_dat_categoria_tienda_cat_tienda
  on public.app_dat_categoria_tienda (id_tienda, id_categoria);

-- RLS: ya existe policy ALL/public/true y `authenticated` tiene UPDATE
-- (verificado con has_table_privilege) ⇒ NO hay que crear policies.
```

### 5.2 Migración 2 — RPC del admin

`get_categorias_by_tienda_complete` alimenta la pantalla de gestión de categorías del admin
y necesita devolver `especial` / `orden_home`.

**Se crea `get_categorias_by_tienda_complete_v2` en vez de reemplazar la v1.** Motivo:
`CREATE OR REPLACE` no permite cambiar el `RETURNS TABLE`, y `DROP` + `CREATE` deja una
ventana en la que el admin ya desplegado se queda sin RPC. Con `_v2` el despliegue es sin
corte: se aplica la migración, luego se cambia el Dart, y la v1 se borra en una migración
posterior. Las columnas nuevas van **al final** para que `Category.fromJson` (que lee por
nombre) siga funcionando sin tocar el orden.

Archivo: `supabase/migrations/20261101120100_get_categorias_by_tienda_complete_v2.sql`.
Además del flag, ordena por `especial desc, orden_home asc, denominacion asc` — el mismo
criterio que el Home, así el gerente ve el listado en el orden real en que saldrá.

### 5.3 Migración 3 — RPC nuevas del home y del drawer

`supabase/migrations/20261101120200_get_home_catalogo_tpv.sql` — **ya escrito** (§5.3.1).

```sql
-- ── Home: una sola llamada para pintar todas las tarjetas ──────────────────
-- El cuerpo completo, con el colapso por denominación, está en
-- supabase/migrations/20261101120200_get_home_catalogo_tpv.sql
```

`get_subcategorias_by_categoria_tpv` (también en ese archivo) **acepta un array**
`p_id_categorias bigint[]` para resolver el grupo entero del colapso en **una sola llamada**,
y cuenta `total_productos` filtrando por tienda y `es_vendible` (la RPC existente
`get_subcategorias_by_categoria` no filtra y devuelve números inflados).

**No se crea ninguna RPC de productos.** El drawer reutiliza
`get_productos_by_categoria_tpv_search_meta_v3` (que ya devuelve `id_subcategoria`, `imagen`,
`stock_disponible`, `tiene_stock` y `metadata`) y filtra por subcategoría **en el cliente**.
Eso exige el cambio de §3.8: `_convertSupabaseToProduct` hoy **descarta `id_subcategoria`** y
hay que empezar a leerlo.

#### 5.3.1 Decisiones concretas del archivo escrito

| Punto | Decisión | Motivo |
|---|---|---|
| Colapso | `group by c.denominacion`, `id = min(c.id)`, `bool_or(especial)`, `min(orden_home)`, contadores sumados, `miembros` + `grupo_ids` | Mitigación D7. `min(id)` es determinista y explicable; evita depender de cuál duplicado tenga imagen |
| Seguridad | `security definer` + `set search_path = ''` + `set_config('search_path','public, pg_catalog', false)` antes de la guarda | Es el patrón obligatorio del repo: con `search_path = ''`, `check_user_has_access_to_tienda` fallaba con 42P01 (documentado en `43_catalogo_stock_mixto_v3.sql:231-237`) |
| Sin suscripción | Devuelve la fila `CONTACTAR ADMIN` | Paridad de comportamiento con `get_categorias_by_tienda_tpv2` |
| Inventario | **No** filtra por existencias del almacén del TPV | El Home debe mostrar la categoría aunque hoy no haya stock; el chip de stock va en el producto |
| Join de subcategorías | `LEFT JOIN` (no `INNER`) | La RPC actual usa `INNER JOIN app_dat_subcategorias` ⇒ hoy hay categorías que **nunca** aparecen. Es una mejora, pero **cambia lo que se ve**: validar con el gerente |

> ⚠️ `get_home_catalogo_tpv` **no** replica el filtro de existencias del almacén del TPV (el
> `EXISTS` sobre `app_dat_inventario_productos` que sí tiene `get_categorias_by_tienda_tpv2`).
> Motivo: el home debe enseñar la categoría aunque hoy no haya stock; el chip de stock se pinta
> en el producto. Si se quiere paridad exacta con los contadores de `ProductsScreen`, añadir el
> `EXISTS` — **medir con `EXPLAIN (ANALYZE)` antes**, porque es justo lo que hace lenta la RPC actual.
>
> ⚠️ La RPC actual del home hace `INNER JOIN app_dat_subcategorias` ⇒ **hoy hay categorías que
> nunca aparecen** (las que no tienen subcategorías). La nueva usa `LEFT JOIN` ⇒ aparecerán
> más categorías. Validar con el gerente que no sale basura (el `HAVING` descarta las que no
> tienen productos).

### 5.4 Migración 4 — caché offline

`ventiq_app/lib/services/auto_sync_service.dart:441-454`

```dart
return categories.map((cat) => {
  'id': cat.id,
  'name': cat.name,
  'imageUrl': cat.imageUrl,
  'color': cat.color.value,
  'especial': cat.esEspecial,     // ← NUEVO (sin esto el flag se pierde offline)
}).toList();
```

Repetir el mismo cambio en **`settings_screen.dart:4578-4597`** (segunda copia del mapeo) y
añadir `especial` al JSON reconstruido en **`categories_screen.dart:300-318`**.

`sync_bundle` **no se toca**: agrega con `to_jsonb(c)` y propaga solo.
`offline_database_service` **no se toca**: el flag viaja dentro del `payload`; `_dbVersion` sigue en 2.

### 5.5 Backfill

Ninguno. `especial` arranca en `false` ⇒ el home se comporta como hoy (todo dentro de «Tienda»)
hasta que el gerente marque sus categorías.

### 5.6 ⚠️ Hallazgo bloqueante: duplicación masiva de categorías

Medido en la base viva:

| Métrica | Valor |
|---|---|
| Categorías totales en `app_dat_categoria` | **1056** |
| Nombres distintos (`denominacion`) | **343** |
| Pares `(id_tienda, denominacion)` con más de una categoría | **31** |
| Máximo de categorías con el mismo nombre en **una misma tienda** | **208** |

Caso extremo: la tienda `148` tiene **334 vínculos, 334 categorías distintas y solo 11 nombres
distintos** — un import que duplicó el nomenclador. El nombre más repetido es «Alimentos» con
208 filas.

**Por qué bloquea:** el home está diseñado como *una tarjeta por categoría*. Sin mitigación,
esa tienda vería cientos de tarjetas llamadas «Alimentos». Lo mismo, en menor escala, en 31
pares tienda/nombre.

**Mitigación aprobada (D7):** colapso por nombre en la RPC del Home, más un script de limpieza
separado cuyo alcance quedó acotado tras verificar los datos (§5.6.1).

- **(A) Defensa inmediata, no destructiva — en la RPC del home.** Colapsar por nombre: agrupar
  por `(ct.id_tienda, c.denominacion)`, quedarse con el `id` de la categoría canónica
  (la de menor `id`, o la primera con imagen) y **sumar** `total_productos` y
  `total_subcategorias`. Añadir `grupo_ids bigint[]` al retorno para que el drawer pueda pedir
  los productos de **todas** las categorías del grupo con un `IN`, no solo de la canónica.
  Esto se puede hacer ya y no toca datos.

  ```sql
  -- dentro de get_home_catalogo_tpv, en lugar del GROUP BY por c.id
  select min(c.id)                       as id,
         c.denominacion::text,
         (array_agg(c.image order by c.id) filter (where c.image is not null))[1] as imagen,
         coalesce(bool_or(ct.especial), false) as especial,
         min(coalesce(ct.orden_home, 0))      as orden_home,
         count(distinct p.id)::bigint         as total_productos,
         count(distinct sc.id)::bigint        as total_subcategorias,
         array_agg(distinct c.id)             as grupo_ids
  -- ... mismos joins ...
  group by c.denominacion
  having count(distinct p.id) > 0
  ```

- **(B) Limpieza de datos.** ❌ **DESCARTADA** (decisión del usuario, 2026-10-31): no se
  ejecuta. Se eliminó el script `sql_updates/limpieza_categorias_duplicadas.sql` del repo
  para que nadie lo corra por error. El motivo técnico está en §5.6.1.

#### 5.6.1 Por qué la limpieza se descartó y por qué el colapso basta

Al ejecutar la previsualización contra la base real apareció algo que la dejaba sin efecto útil:

**Las categorías duplicadas de las tiendas ACTIVAS no son propias: se comparten entre
sucursales del mismo dueño.**

| Categoría | Nombre | Tiendas que la usan |
|---|---|---|
| 846 | Alimentos | 173, 174, 177, 208 |
| 847 | Bebidas | 173, 174, 177 |
| 849 | Cuidado Personal | 173, 174 |
| 851 | Hogar Y Oficinas | 173, 174 |

⇒ El grupo «Alimentos» de la tienda 173 es `{827 (propia), 846 (compartida con 4 tiendas)}`.
Fusionarlos le cambiaría el catálogo a **cuatro** tiendas a la vez. La guarda del script
(«saltar si el sobrante está compartido») **saltaba todos los grupos de las tiendas con
suscripción** — es decir, la limpieza no habría tocado nada de lo que importa.

**Estado final de D7:**

| | Alcance | Estado |
|---|---|---|
| **(A) Colapso por denominación en `get_home_catalogo_tpv`** | **Todas** las tiendas, incluidas las activas | ✅ **Aplicado en producción y verificado.** Es la solución completa; no toca datos. En la tienda 173 «Alimentos» pasa de 2 tarjetas (50 + 22 productos) a **1 tarjeta con 72** |
| **(B) Limpieza de datos** | Solo grupos no compartidos = tiendas sin suscripción (148: 208 miembros, 153: 61, 160: 31…) | ❌ **Descartada.** No aportaba nada al Home: esas tiendas tienen 0 suscripciones activas y la RPC les devuelve la fila `CONTACTAR ADMIN` |
| **(C) Unificar el catálogo entre sucursales del mismo dueño** | Decisión de negocio | Fuera de alcance. Migración aparte si algún día se quiere |

**Caso que ninguna cubre:** casi-duplicados por nombre. La tienda 174 tiene «Confituras»
(53 productos) y «Confitura» (25) — nombres distintos, así que el colapso por igualdad tampoco
los une. Decisión de negocio, no de SQL.


### 5.7 ⚠️ El historial de migraciones quedó desincronizado

Los objetos **existen** en la base de datos, pero `list_migrations` **no registra** las tres
versiones nuevas: la última entrada del historial es `20261012150148`. Es decir, las
migraciones se aplicaron **a mano** (editor SQL), no con `supabase db push`.

Consecuencia: si más adelante alguien corre `supabase db push` o `supabase migration up`, el
CLI intentará aplicar de nuevo `20261101120000`, `…120100` y `…120200`.

**No es peligroso: los tres archivos son idempotentes.**

| Archivo | Por qué es seguro re-ejecutarlo |
|---|---|
| `…120000` | `add column if not exists` / `create index if not exists` |
| `…120100` | `create or replace function` |
| `…120200` | `create or replace function` (sin cambio de firma de retorno) |

Lo peor que puede pasar es que el CLI se queje o que el `COMMENT ON` se reescriba igual.

**Pero conviene reconciliarlo**, porque un historial desincronizado vuelve impredecible el
próximo despliegue. Opciones, de menos a más intervencionista:

1. **Aceptar el desfase** y seguir aplicando a mano (lo más simple, pero frágil).
2. **Marcar las versiones como aplicadas** sin ejecutarlas:
   `supabase migration repair --status applied 20261101120000 20261101120100 20261101120200`
   (requiere CLI enlazado al proyecto; conviene hacerlo con el historial a la vista).
3. **Dejarlas correr de nuevo** en el próximo `db push` sabiendo que son idempotentes.

Recomendación: **opción 2** antes de la Fase 6 (que vuelve a tocar SQL). Anotarlo como tarea.

---

## 6. La vista Home

### 6.1 Estructura (una sola implementación, web y móvil)

```
Scaffold(backgroundColor: surface #F5F7FA)
└ RefreshIndicator(color: #194B8C)
  └ CustomScrollView
    ├ SliverToBoxAdapter → HomeHeroHeader
    │     Stack:
    │       · banda degradada #1E3A6E → #194B8C (alto 190 + safe area)
    │       · saludo "Hola, {nombre}" + chip de conexión + campana + avatar
    │       · HomeBuscador (tarjeta blanca radio 20, sombra 0x1A2B3A67)
    │           ↳ tapa los últimos 26 px de la banda ← "entre el appbar y el lienzo"
    ├ SliverToBoxAdapter → chips rápidos (Solo con stock · Promociones · USD) [28 px]
    ├ SliverToBoxAdapter → rótulo "CATEGORÍAS" + acción "Ver tienda ›"
    ├ SliverToBoxAdapter → grilla de especiales (2 col, spacing 12, extent 122·scale)
    ├ SliverToBoxAdapter → TiendaCard (full width, navy, "N rubros")
    ├ SliverToBoxAdapter → rótulo "MÁS VENDIDOS" + riel horizontal   ← opcional, fase 7
    └ SliverFillRemaining → estado vacío / error / sin conexión
```

Con `query` activa el lienzo cambia a **resultados inline** (`ProductoTile`), con cabecera
«N resultados para “q”» y «Limpiar».

### 6.2 La tarjeta («card del inicio»)

Port fiel de `TarjetaExploracion` con **un modo nuevo: imagen de fondo**.

| Modo | Cuándo | Cómo |
|---|---|---|
| **Imagen** (preferente) | `categoria.imagen != null` | `Image.network` `BoxFit.cover` + velo `transparent → black .62` (stops `[.25,.62,1]`) + título `Shadow(0x73000000 blur10 dy2)` — garantiza contraste con cualquier foto |
| **Gradiente** (fallback) | sin imagen | par de colores estable desde `id` sobre 8 pares curados; marca de agua icono 76 `white .08` |

Capas en orden: fondo → marca de agua (solo gradiente) → velo → `Row[chip, tile-icono 32]` →
`Spacer` → título 19/w800 → subtítulo 12/w500 → pastilla de pie opcional. `ClipRRect(22)` +
`Material(transparent)` + `InkWell` + `HapticFeedback.selectionClick()`.

**Dos acciones, gestos separados** (igual que la referencia): tocar la **tarjeta** abre el
drawer; tocar la **pastilla de pie** («Ver todos») va a `ProductsScreen`.

La tarjeta virtual **«Tienda»** es la misma card con `Icons.storefront_rounded`, navy
`#424A65→#2C3654`, chip `'N RUBROS'`, subtítulo `'Todo lo demás'`.

### 6.3 Buscador siempre visible

```dart
HomeBuscador({
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  required VoidCallback onLimpiar,
  required VoidCallback onAbrirFiltros,
  int filtrosActivos = 0,
  String hint = 'Buscar producto, categoría o SKU…',
});
```

- Vive **fuera** del área scrolleable, dentro del hero ⇒ siempre visible entre el appbar y el
  lienzo (patrón ya probado en `catalogo_screen.dart:499-580`).
- Radio 20, borde `#E0E6ED`, sombra `0x1A2B3A67 blur22 dy9`; campo interno `surface` radio 14;
  `prefixIcon search_rounded 21`; `suffix` = `limpiar` (con texto) + `tune_rounded` con
  `Badge.count(backgroundColor: accent)`.
- Debounce **250 ms**; reutiliza `get_productos_by_categoria_tpv_search_meta_v3`.

---

## 7. El drawer jerárquico (pieza central)

### 7.1 Cómo se abre

```dart
Navigator.of(context).push(PageRouteBuilder(
  opaque: false,
  barrierColor: const Color(0x6B0B1226),
  transitionDuration: const Duration(milliseconds: 280),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, __, ___) => CategoriaDrawer(nivelInicial: inicial),
  transitionsBuilder: (_, anim, __, child) {
    final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(c),
      child: child);
  },
));
```

Ruta propia: **no** `Drawer` de `Scaffold` (rompería el botón atrás del sistema, como documenta
`ruta_lateral.dart:5-15`) y **no** `showModalBottomSheet` (no permite drag libre ni control de
niveles).

### 7.2 Ocupa toda la pantalla

`Container` con `borderRadius: BorderRadius.vertical(top: Radius.circular(28))`,
`color: surface`, alto `MediaQuery.sizeOf(context).height` (safe-area incluida), sin márgenes
laterales. Al hacer scroll al tope se activa el gesto de arrastre para cerrar.

### 7.3 Niveles

```
┌ CategoriaDrawer ───────────────────────────────┐
│  grabber 40×4 · breadcrumb · [↩] · [X]         │  ← cabecera fija
├────────────────────────────────────────────────┤
│  Nivel 0 · rejilla de categorías               │  "Tienda" o especial con hijas
│  Nivel 1 · banner de la categoría + subcategorías
│  Nivel 2 · lista de productos (inline)         │  + "Ver listado completo"
└────────────────────────────────────────────────┘
```

- **Estado**: `List<HomeDrawerPaso> _pila` — una **pila real** (la referencia solo guarda un
  nivel). `volverNivel()` hace `pop()`.
- **Transición**: `AnimatedSwitcher(280 ms)` con `Fade + Slide`; la dirección depende de si la
  pila creció o decreció. Reduce-motion ⇒ `Duration.zero`.
- **«Boom» + cascada**: se conserva el latido de 190 ms al entrar a una carpeta y la cascada
  `Interval(0.14*i, 1)` en las subcategorías.

### 7.4 Volver atrás «fácil» (requisito 1)

Cinco caminos, ninguno obliga a la «X»:

1. **Botón atrás del sistema / gesto de Android**: `PopScope(canPop: false, onPopInvokedWithResult:)`
   → si `_pila.length > 1` ⇒ `volverNivel()`; en la raíz deja cerrar.
2. **Flecha ↩ en la cabecera**, junto al breadcrumb, visible cuando hay pila.
3. **Breadcrumb tocable**: `Tienda › Bebidas › Colas` — cada migaja salta a ese nivel.
4. **Swipe desde el borde izquierdo** (`onHorizontalDragUpdate`, umbral 72 px) ⇒ sube un nivel.
5. **Cerrar**: arrastrar hacia abajo (>120 px o velocidad >700 px/s) · tap en el velo · «X».

### 7.5 Los productos dentro del drawer (requisito 2)

`drawer_nivel_productos.dart`:
- Carga en el momento con `get_productos_by_subcategoria_tpv_meta` o
  `get_productos_by_categoria_tpv_meta2`, con `VentiqSkeleton` (placeholder propio, ver §10).
- `ProductoTile`: miniatura 56×56 radio 12 (`Image.network` + fallback con icono),
  nombre 13.5/w800 (2 líneas), subcategoría 10.5/textSecondary, precio 14/w900/primary, chip de
  stock (verde/ámbar/rojo) y **«+» de 36×36** a la derecha.
- **Toque en el tile** ⇒ cierra el drawer y `Navigator.push(ProductDetailsScreen(producto: p, …))`
  **con el objeto ya cargado** ⇒ el detalle pinta real en el primer frame.
- **Toque en «+»** ⇒ suma 1 a la orden sin abrir el detalle (venta rápida) + `HapticFeedback` +
  SnackBar «Añadido · N en el carrito».
- **Pie fijo**: «Ver listado completo (N)» ⇒ `ProductsScreen(categoryId:, categoryName:, categoryColor:, subcategoriaId:, subcategoriaNombre:)`.

  ⚠️ Para esto hay que **añadir el parámetro de subcategoría a `ProductsScreen`**
  (`products_screen.dart:32-46` no lo acepta hoy) y **leer `id_subcategoria` en
  `_convertSupabaseToProduct`** (`product_service.dart:324-395`, hoy lo descarta) para poder
  filtrar por id en vez de por el nombre de la sección.

⇒ `Tienda → Bebidas → Colas → producto` = **3 toques**; `Combustibles → producto` = **2**.

---

## 8. Detalle de producto rediseñado

| Hoy | Propuesto |
|---|---|
| `AppBar` fijo + `AppBottomNavigation` + `SingleChildScrollView` (`:1591`, `:1648`, `:1715`) | `SliverAppBar(pinned: true, expandedHeight: 38 % del alto, flexibleSpace: imagen + velo + título colapsable)` **y quitar la barra de navegación inferior del detalle** (duplicaba la de acción; hoy el tab activo ni existe) |
| **Los controles de venta no aparecen hasta tocar una variante** (§3.8-2) | Los controles (**stepper −/cantidad/+**, presentación e incremento) están **siempre visibles** en la barra inferior, con la primera ubicación/variante preseleccionada (`_autoSelectSingleLocation` pasa a auto-seleccionar también cuando hay varias, eligiendo la de más stock) |
| `~186 px` de «chrome» + `~110-130 px` de aire antes del primer control | Barra inferior fija única y secciones compactas: objetivo **imagen + precio + «Agregar» visibles sin scroll en 360 px** |
| El bloque «UBICACIONES» completo va antes de cualquier control | Se mueve **debajo** de la barra de acción y se colapsa en un `ExpansionTile` (abierto solo si hay varias ubicaciones con stock) |
| Imagen fija 120×120, sin galería | Hero de imagen en el `SliverAppBar` con `Hero(tag: 'prod-{id}')` desde `ProductoTile`; galería si `multimedias` trae más de una |
| Skeleton completo en cada apertura | Con `producto` inyectado el primer frame es real; variantes/presentaciones/stock cargan en segundo plano con skeleton propio solo en sus bloques |
| Web: una columna estirada | `LayoutBuilder`: `> 900 px` ⇒ **dos columnas** (imagen izquierda sticky, info derecha) |

**Lentitud — los tres arreglos de más impacto:**

1. **Caché de detalle con TTL corto.** `ProductDetailService` gana un
   `Map<int, _DetalleCache>` con TTL ~60 s (mismo patrón que `ProductService._productsCache`,
   `product_service.dart:71-73`, TTL 5 min). Cerrar y reabrir el mismo producto deja de pagar
   `get_detalle_producto` + presentaciones. **Causa raíz a documentar: el listado entrega
   `variantes: []` hardcodeado (`product_service.dart:372`)** — mientras siga así, el detalle
   siempre re-consulta; la caché es la mitigación sin tocar el contrato del listado.
2. **`ElaboratedProductChip` perezoso + sin cascada.** El chip pasa a ser un `StatelessWidget`
   que recibe `esElaborado`/`esServicio` **ya resueltos por `get_detalle_producto`** (que los
   trae) y solo consulta ingredientes **al tocarlo**, no al montarse. Se eliminan el `SELECT`
   redundante, el `isProductServicio` y las N RPC seriales de `fn_stock_producto_almacen_detalle`
   → pasa de 8 RPC + 4 queries a **0 red** en la apertura.
3. **Borrar el fetch muerto.** Quitar `_loadUsdRate()` del `initState` del detalle
   (`:160-166`) y el `_buildUsdRateChip` muerto (`:4001-4041`), o pintarlo de verdad en la
   barra inferior. Y eliminar la **doble validación de stock** (`:119-144` y `:887-914`) para no
   pagar la RPC y luego descartar el resultado.

**Unificar la reconstrucción de variantes:** extraer `ProductDetailsLoader` y borrar las ~140
líneas duplicadas de `:661-801`, reutilizando `ProductDetailService._transformInventoryToVariants`.


Detalles:
- `SliverAppBar` `backgroundColor`/`surfaceTintColor` transparentes, scrim `black .55`, título
  que aparece al colapsar (`LayoutBuilder` + `Opacity`).
- Imagen: `Image.network` (con `cacheWidth`) + `VentiqSkeleton`; sin imagen ⇒ gradiente de la categoría + icono grande.
- **Chips de estado** bajo el título: `Elaborado`, `Servicio`, `Sin stock`, `Promo`, usando
  `metadata.es_elaborado` / `metadata.es_servicio` que la RPC ya devuelve.
- Stepper integrado en la barra inferior (no en un diálogo), `- / +` de 44×44.
- `routeObserver` (ya existe en `main.dart:101`) para pausar animaciones y refrescar stock al volver.
- Accesibilidad: contraste ≥ 4.5:1, `Semantics` en «Agregar», targets ≥ 48 px.

---

## 9. Administración (`ventiq_admin_app`)

- `models/category.dart`: `+ final bool especial;` `+ final int ordenHome;` en constructor,
  `fromJson` (`json['especial'] ?? false`, `json['orden_home'] ?? 0`), `toJson`, `copyWith`.
- `services/category_service.dart`:
  - `createCategoryWithId({..., bool especial = false})` → añade `'especial': especial` al
    `INSERT` de `app_dat_categoria_tienda` (`:307-310`).
  - `updateCategory({..., bool? especial, int? ordenHome})` → **nuevo bloque** que actualiza la
    **puente** (hoy solo actualiza `app_dat_categoria`), leyendo `idTienda` como en `:273`:
    ```dart
    if (especial != null || ordenHome != null) {
      final idTienda = await _userPrefs.getIdTienda();
      await _supabase.from('app_dat_categoria_tienda').update({
        if (especial  != null) 'especial':   especial,
        if (ordenHome != null) 'orden_home': ordenHome,
      }).eq('id_categoria', categoryId).eq('id_tienda', idTienda!);
    }
    ```
    **Registrar el error** en el `catch` (`:368-371`): hoy devuelve `false` en silencio y el
    switch parecería no hacer nada.
  - `Future<bool> setEspecial(int id, bool valor)` y `setOrdenHome(int id, int orden)` como atajos.
- UI en **`widgets/categories_tab_view.dart`** (no en `screens/categories_screen.dart`, que es un mock):
  - `Switch.adaptive` con título **«Categoría especial»** y subtítulo dinámico
    («Se mostrará como tarjeta destacada en el TPV» / «Se agrupará bajo “Tienda” en el TPV»).
  - Puntos de inserción exactos: `_AddCategoryDialog` tras `:1264` (estado en `:1044`, envío
    `:1112-1134`); `_EditCategoryDialog` tras `:1568` (estado `:1394`, hidratación `:1397-1403`,
    envío `:1413-1434`); añadir `especial: widget.category.especial` en `_ChangeImageDialog:2622`.
  - `Chip` `ESPECIAL` (fondo `#194B8C`, blanco 10/w800) en la tarjeta del listado y en el
    bottom sheet de detalle.
  - `ReorderableListView` (o `↑/↓`) **solo dentro del grupo de especiales** para fijar `orden_home`.
  - Contador en la cabecera: «N especiales de M categorías».
- Guardarraíl: marcar especial una categoría **sin productos vendibles** ⇒ aviso no bloqueante
  («No aparecerá en el Home hasta que tenga productos»).
- ⚠️ La ruta `/categories` (`main.dart:217` → `screens/categories_screen.dart`) **sigue siendo un
  mock**; conviene arreglarla o retirarla en una fase aparte para que el gerente no caiga ahí.

---

## 10. Rendimiento y «dinamizar»

| Acción | Detalle |
|---|---|
| **1 request para el home** | `get_home_catalogo_tpv` devuelve especiales + resto + contadores + nº de subcategorías |
| **Pintado instantáneo** | Snapshot JSON del último catálogo en `shared_preferences`; se pinta de caché y se revalida en segundo plano (stale-while-revalidate). Encaja con el énfasis offline de la app |
| **Imágenes** | `Image.network` con `cacheWidth` calculado del layout, para no decodificar 1080 px en una miniatura de 56. `VentiqSkeleton` (widget propio de ~30 líneas: un `AnimatedBuilder` con pulso de opacidad) hace de placeholder sin traer `shimmer` |
| **Precarga** | Al abrir una categoría se piden subcategorías **y** los productos de la primera subcategoría en paralelo |
| **Búsqueda** | Debounce 250 ms + cancelación por token de secuencia de la petición anterior |
| **Listas** | `GridView.builder`/`ListView.builder` con extensión fija (evita re-medir) |
| **Rebuilds** | `ListenableBuilder` solo en las secciones afectadas; `const` en lo estático; `RepaintBoundary` en tarjetas con degradado |
| **Reduce motion** | `MediaQuery.disableAnimationsOf` ⇒ `Duration.zero` (accesibilidad + TPV de gama baja) |
| **Dependencias nuevas** | **NINGUNA.** Se evaluaron `cached_network_image` y `shimmer` (las que usa `inventtia_flow`) y se **descartaron**: obligaban a resolver paquetes y a verificar builds de web y Windows justo en la fase más barata del rediseño, a cambio de caché en disco que el TPV no necesita (vive en red local) y de un placeholder que son 20 líneas propias. `TarjetaExploracion` usa `Image.network` con `cacheWidth` calculado del layout ⇒ la `ImageCache` en memoria de Flutter es suficiente. **Reevaluar solo si se mide** que hace falta caché en disco |

---

## 11. Fases

### Fase 0 — Decisiones y esquema ✅ (salvo D2/D3/D5/D6)
- [x] Confirmar D1/D4/D7 (§2.1) — **confirmadas 2026-10-31**
- [x] Decidir la mitigación de §5.6 — **colapso en la RPC; limpieza descartada**
- [x] Escribir las 3 migraciones
- [x] **Aplicadas en producción** y verificadas contra la base viva:
  - `especial boolean NOT NULL DEFAULT false` y `orden_home smallint NOT NULL DEFAULT 0` ✓
  - `idx_app_dat_categoria_tienda_especial` (parcial `WHERE especial`) y `uq_app_dat_categoria_tienda_cat_tienda` ✓
  - `get_home_catalogo_tpv(bigint,bigint)` → `…, miembros integer, grupo_ids bigint[]`, `SECURITY DEFINER`, `search_path=""` ✓
  - `get_subcategorias_by_categoria_tpv(bigint[],bigint,bigint)` ✓
  - `get_categorias_by_tienda_complete_v2(bigint)` ✓ y la v1 sigue viva ✓
  - El cuerpo de `get_home_catalogo_tpv` **parsea y ejecuta**: llega hasta la guarda y
    deniega la sesión sin usuario de tienda (P0001 «Acceso denegado»), sin error 42P01 ⇒
    el patrón `search_path = ''` + `set_config` es correcto
- [ ] **Reconciliar el historial de migraciones** (ver §5.7)
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` de las 3 RPC con una tienda grande (173 o 174)
- [ ] **Prueba funcional de la RPC desde la app** autenticada (mi sesión de MCP no puede:
      la guarda la deniega, que es el comportamiento correcto)
- [ ] Regresión: `get_categorias_by_tienda_tpv` y `sync_bundle` devuelven lo mismo
- [ ] Verificar que `ventiq_marketplace` sigue cargando categorías
- [ ] Confirmar D2/D3/D5/D6 (§2) — no bloquean la Fase 1

### Fase 1 — Tokens y widgets base (sin red) ✅ (falta el golden)
- [x] `lib/theme/ventiq_home_theme.dart` — paleta VentIQ + escala de inventtia_flow (radios 22/20/14/10/8, 3 sombras, 8 degradados, tipografía, `cardExtent` que respeta el escalado de texto, `reduceMotion`)
- [x] `lib/utils/categoria_icono.dart` — 60 reglas por palabra clave en español, sin acentos; **coincidencia por límite de palabra** en fragmentos cortos; `null`-safe y con fallback encadenado al SKU
- [x] `lib/utils/categoria_gradiente.dart` — degradado determinista por `id` (no por nombre)
- [x] `lib/widgets/home/tarjeta_exploracion.dart` — la card: modo degradado + modo imagen con velo, chip, tile de icono, pie con gesto propio, `Hero` opcional, semántica de botón
- [x] `lib/widgets/home/home_seccion_titulo.dart`
- [x] `lib/widgets/home/home_estado_vacio.dart` (+ `HomeEstadoError` con reintento)
- [x] `mcp__dart__analyze_files` sin errores en los 6 archivos de `lib/` y los 3 de `test/`
- [x] **32 tests en verde** (`test/home/*`): mapeo de iconos, degradado, tarjeta, gestos, accesibilidad, escalado de texto
- [ ] **Golden test** de la tarjeta (degradado × imagen, 360 y 1280) — pendiente; requiere `flutter test --update-goldens` y revisar la imagen a ojo
- [x] ~~`flutter build web`/`windows` con `cached_network_image` + `shimmer`~~ → **ya no aplica: no se añaden dependencias** (§10)

### Fase 2 — Datos y estado ✅
- [x] `lib/models/home_catalogo.dart` — `HomeContexto`, `HomeCategoria` (+`grupoIds`), `HomeSubcategoria` (+`grupoIds`), `HomeProducto`, `HomeCatalogo`; `fromJson`/`toJson` tolerantes (PostgREST manda `numeric` como texto a veces)
- [x] `lib/services/home_catalog_service.dart` — interfaz `HomeCatalogoGateway` + implementación con las 3 RPC, caché en memoria (TTL 5 min), invalidación y snapshot en `SharedPreferences` para arrancar sin red
- [x] `lib/controllers/home_controller.dart` — `ChangeNotifier` (sin `provider`): agrupación, búsqueda con debounce y **pila real** del drawer, con `volverNivel()` devolviendo si sigue abierto (lo que necesita el `PopScope`)
- [x] **88 tests en verde** en `test/home/` (32 de Fase 1 + 56 nuevos)
- [x] `mcp__dart__analyze_files` sin errores en los 5 archivos nuevos
- [x] Unit test de agrupación, ampliado a colapso, orden, serialización y tolerancia de tipos
- [x] Test del controlador con un gateway doble: 0 especiales ⇒ todo en Tienda; todas especiales ⇒ se oculta la tarjeta; debounce; respuesta vieja que no pisa a la nueva; navegación de la pila

### Fase 3 — Home nuevo ✅ (con dos cosas pendientes, ver abajo)
- [x] `home_hero_header.dart` — banda degradada + saludo + acciones, con el buscador flotando sobre la costura
- [x] `home_buscador.dart` — card blanca siempre visible, botón de limpiar y badge de filtros
- [x] `home_quick_chips.dart` · `ventiq_skeleton.dart` · `tienda_card.dart`
- [x] `widgets/usd_rate_chip.dart` — **una** implementación (antes había 3 copias, una muerta)
- [x] `widgets/home/home_catalogo_view.dart` — el contenido, puro: datos entran, gestos salen
- [x] `screens/home_shell_screen.dart` — armazón: `HomeController`, búsqueda, navegación, `AppDrawer`,
      `AppBottomNavigation`, `SalesMonitorFAB`, chip USD y `SyncStatusChip`
- [x] Responsive: 2 / 3 / 4 / 5 columnas según ancho (probado)
- [x] `main.dart` → `/categories` devuelve `HomeShellScreen`; **las pantallas viejas siguen vivas**
      en `/categories-mobile` y `/categories-web` como vuelta atrás
- [x] Portado de la lógica no visual: `isInventoryOnlySession` → `/admin-home`, ajustes de ahorro de
      datos / modo fluido / SKU, listener de `SmartOfflineManager`, `_onBottomNavTap` (incluido el
      salto a `/mesas` en modo restaurante) y el escáner de barras
- [x] **128 tests en verde**
- [x] ❌ ~~Caché offline en `auto_sync_service` / `settings_screen`~~ → **ya no hace falta**: el Home
      nuevo tiene su propio snapshot en `HomeCatalogService`, así que el flag `especial` nunca
      viaja por la caché vieja. Dos archivos menos que tocar
- [ ] **Diálogo de actualización**: **no** se ha portado. Vivía en `categories_screen.dart:1182+`
      y era la **tercera** copia (splash y ajustes ya lo hacen). Decisión pendiente: dejarlo solo
      en splash, que es donde tiene sentido, o portarlo
- [ ] **Búsqueda**: sigue usando `ProductService.searchProducts` (devuelve `Product` completo, y
      así el toque lleva al detalle como hoy). El `HomeController` ya tiene su búsqueda probada
      con `HomeProducto`; unificar las dos exige un mapeo `HomeProducto → Product` que la RPC no
      cubre del todo (`esPeligroso`, `esComprable`, `esInventariable`, `esPorLotes`). Se decide
      en la Fase 4/5, al construir el drawer
- [ ] Golden tests: home 360 / 412 / 1280

### Fase 4 — Drawer jerárquico ✅ (dos desviaciones anotadas)
- [x] `categoria_drawer.dart` — ruta propia (`categoria_drawer_route.dart`, velo `0x6B0B1226`, slide desde
      abajo 280/200 ms), `PopScope`, breadcrumb tocable, ↩, «X», arrastre de cabecera para cerrar y
      franja de borde izquierdo para subir nivel. **Los tres niveles viven en el mismo archivo**
      (no se crearon `drawer_nivel_categorias.dart` / `drawer_nivel_productos.dart`: comparten
      cabecera, pila y transición, y separarlos obligaba a inventar un contrato de props entre
      hermanos para ~250 líneas de UI)
- [x] `producto_tile.dart` — fila compacta: miniatura 48×48 radio 12 (el plan decía 56; en 360 px
      con precio + «+» 48 deja respirar el nombre), chip de stock verde/rojo, etiqueta ELAB/SERVICIO,
      SKU opcional, «+» de 32 con `Semantics('Agregar a la venta')`
- [x] Animaciones: **boom** de 190 ms antes de cambiar de nivel (la tarjeta late `0.86→1` en 240 ms
      con `easeOutBack`), **cascada** `Interval(min(0.14·i, 0.55), 1)` de 430 ms en las subcategorías
      y `AnimatedSwitcher` **direccional** de 280 ms según la pila crezca o decrezca. Reduce-motion ⇒
      sin animación
- [x] **19 `testWidgets`** en `test/home/categoria_drawer_test.dart` (nivel 0, bajar de nivel,
      atrás del sistema sube / en la raíz cierra, breadcrumb, swipe de borde largo y corto, arrastre
      de cabecera, «X» en nivel profundo, «Ver listado completo» con categoría+subcategoría,
      «Ver todos», tocar producto sin cerrar, «+», agotado sin «+», `ProductoTile` con SKU/Agotado/
      Semantics). Se monta el drawer **real** con `abrirCategoriaDrawer` y un doble de gateway
- [x] `SalesModeService`/`NavigationHelper`: el drawer **no** se abre en flujo mesa. `_abrirDesdeHome`
      desvía a `/mesas` igual que la barra inferior (razón: en mesa la cuenta activa se ve dentro de
      la mesa, no en el Home)
- [x] **La «X» cierra de verdad en cualquier nivel**: era un bug real. `_cerrar()` usaba
      `Navigator.maybePop()`, que consulta al `PopScope`; con pila > 1 el `PopScope` lo bloqueaba
      para subir nivel y la «X» **no cerraba**. Ahora usa `Navigator.pop()` directo (el botón atrás
      del sistema sigue pasando por el `PopScope`)

**Desviaciones / pendientes de la fase:**
- **Venta rápida «+» sin cablear.** El drawer ya acepta `onAgregarProducto` y pinta el «+», pero
  `HomeShellScreen` no lo pasa: para vender de verdad hace falta resolver `Product` completo +
  almacén/variante, que es el mismo problema del mapeo `HomeProducto → Product` (§16, Fase 5). Sin
  cablear, el «+» no aparece; no hay riesgo de vender mal.
- **El detalle se apila ENCIMA del drawer** (el plan §7.5 decía «cierra el drawer y push»). Se
  mantiene encima a propósito: volver del detalle devuelve al vendedor al nivel donde estaba, no al
  Home. El objeto aún se resuelve contra el listado (`getProductsByCategory`); la inyección directa
  llega en Fase 5 con la caché de detalle.
- **Cerrar arrastrando se hace desde la cabecera**, no «al llegar al tope del scroll» (§7.2): el
  arrastre de cabecera es descubrible (grabber) y no compite con el scroll de la rejilla/lista, que
  en Android es justo el gesto que el usuario hace para seguir mirando. El velo y la «X» cubren el
  resto.

### Fase 4.1 — Correcciones del 2026-11-02 (feedback del TPV) ✅ (1 pendiente de BD)

Cambios pedidos al probar el Home en el TPV real (tienda 223, TPV 224/225):

- [x] **Fuera el rótulo «EXPLORA»** del hero. El saludo es ahora `Hola, {nombre del trabajador}`.
- [x] **El nombre del vendedor no se mostraba**: el Home saludaba con `'Hola 👋'` fijo aunque el
      login ya guarda `nombres` en `SharedPreferences`. `_cargarPerfil()` lo lee con
      `getWorkerProfile()` y `_saludo` compone `Hola, perlanegraco`. Sin perfil guardado (sesión
      vieja) cae a `Hola 👋`; nunca rompe.
- [x] **App bar reorganizado**: el chip «Online/Offline» ya no comparte fila con el saludo (quedaba
      todo apretado y se leía centrado). Ahora el nombre ocupa la izquierda y la derecha son dos
      pisos: acciones (escáner, campana) arriba y `ConnectionStatusWidget` abajo. `HomeHeroHeader`
      cambia `leading` por `estadoConexion`.
- [x] **«Solo con stock» vaciaba el Home.** `_hayBusqueda` incluía el chip, así que al tocarlo se
      activaba el lienzo de resultados con la consulta vacía y salía «No hay productos que
      coincidan con “”». Ahora `_hayBusqueda` es solo `texto.trim().isNotEmpty`: el chip filtra la
      búsqueda, no la sustituye.
- [x] **Sin especiales, las categorías salen sueltas.** Se eliminó la tarjeta «Tienda» en ese caso
      (era un toque extra para ver las únicas categorías que hay): `HomeCatalogoView` pinta
      directamente `catalogo.tienda` en la rejilla con rótulo «CATEGORÍAS» y sin acción «Ver
      tienda ›». La tarjeta «Tienda» sigue existiendo cuando convive con especiales.
- [x] **Fotos de categoría**: la tarjeta ya recibía `imagenUrl: c.imagen` (modo foto con velo). Se
      añadió test que lo fija. Ojo: en la base viva, las **dos** categorías de la tienda 223 tienen
      `app_dat_categoria.image = null`, así que ahí no hay nada que pintar; cuando el gerente suba
      la foto (el admin escribe en `app_dat_categoria.image`) aparecerá sola. 97 de 1056 categorías
      del nomenclador tienen foto.
- [x] **Contadores que no cuadraban** («elaboracion» decía 6 y listaba 4; «Alimentos» 13 vs 4).
      Causa: `get_home_catalogo_tpv` contaba productos vendibles de la tienda, pero la RPC del
      listado exige además que el producto esté en el **almacén del TPV**. Nueva migración
      `supabase/migrations/20261102120000_fix_conteos_home_tpv.sql` con el mismo `EXISTS` en las dos
      RPC (Home y subcategorías). Verificado por SELECT contra la base viva: tienda 223 pasa a
      4 y 4, exactamente lo que lista el drawer. El `EXISTS` **no** exige stock > 0 (un agotado con
      fila de inventario sigue contando y sigue en el Home), así que no contradice §5.3: solo deja
      de contar lo que ese TPV no tiene cargado.
      ✅ **Aplicada en producción** (2026-11-02), tras verificarla por SELECT. Los contadores del
      Home ya coinciden con el listado.
- [x] Tests: 6 nuevos (layout del hero con conexión abajo-derecha, categorías sueltas + toque,
      `imagenUrl` en la tarjeta, dos del saludo con/sin nombre y la regresión de «Solo con stock»)
      ⇒ **154 en verde** en `test/home`.

### Fase 4.2 — Venta rápida desde el listado del drawer ✅

Encargo del 2026-11-02: si el producto tiene **una sola presentación y una sola ubicación**
(ej.: `10808` Jugo de Limón Concentrado), se debe poder **poner cantidad y añadir al carrito sin
abrir el detalle**. Si tiene más de una presentación, al detalle. Además: «Ver listado completo» del
drawer ya no se usa; al añadir debe salir un diálogo con **Ir al carrito** o **Continuar añadiendo**.
Y «rubros» pasa a decir **«categ»**.

- [x] **`Product.presentacionesCount`** (campo nuevo, default `0`): lo rellena
      `ProductDetailService._transformToProduct` desde `producto.presentaciones` de
      `get_detalle_producto`. Así el alta rápida sabe si hay 1 o varias presentaciones **sin RPC
      extra** (y también en offline, con el detalle cacheado).
- [x] **`lib/services/quick_add_service.dart`** — decisión pura `QuickAddService.decidir`:
  - se añade directo solo si `variantes.length == 1` (la RPC de detalle ya filtra al almacén del
    TPV y solo devuelve filas con `cantidad_final > 0` ⇒ una única combinación
    presentación/ubicación con stock), `presentacionesCount <= 1`, stock > 0, no es
    elaborado/servicio/paquete y **no hay promoción aplicable**;
  - si no, `requiereDetalle` con el `Product` ya cargado (no se vuelve a pedir);
  - el precio unitario es `precio × factor de presentación` (mismo criterio que el detalle) y el
    `inventoryData` lleva los ids de la fila de inventario (`id_ubicacion`, `id_presentacion`,
    `id_variante`, `presentacion_factor_rel`, sku…), igual que `_buildInventoryData` del detalle.
- [x] **`QuickAddService.agregar`**: revalida stock y promoción **con la cantidad final** (una
      promoción «3x2» no aplica con 1 pero sí con 3 ⇒ en ese caso devuelve `requiereDetalle` en vez
      de vender con precio base), respeta la guarda de la tienda
      `need_all_orders_completed_to_continue` (misma que el detalle) y llama a
      `OrderService.addItemToCurrentOrder`. Caché de detalle 60 s que se invalida al agregar (el
      stock acaba de cambiar).
- [x] **`lib/widgets/home/quick_add_sheet.dart`** — hoja de cantidad: nombre, presentación única,
      ubicación, disponible, −/+ y cantidad tecleable, total y «Agregar al carrito». Mientras evalúa
      enseña progreso; si el producto no es inequívoco se cierra sola y el Home abre el detalle.
- [x] **Drawer**: el «+» de cada fila abre la hoja (`onAgregarProducto`). El pie **deja de abrir
      `ProductsScreen`**: ahora es **«Seguir añadiendo»** (sube a la raíz del drawer sin cerrarlo,
      `HomeController.volverARaiz`) + **«Carrito (N)»** (`ValueNotifier`, se actualiza al agregar).
      Se quitaron también los atajos «Ver todos» dentro del drawer (tarjeta y banner de categoría).
- [x] **Diálogo posterior al alta**: «Añadido al carrito · producto × cantidad» con
      **«Continuar añadiendo»** (vuelve al nivel de categorías del drawer) e **«Ir al carrito»**
      (cierra el drawer y abre el carrito). Es lo que se pidió: que quede claro qué hacer después.
- [x] **«rubros» → «categ»** en `TiendaCard` (chip «N CATEG» y subtítulo «N productos en M categ»).
- [x] **El Home conserva «Ver todos» → `ProductsScreen`** en las tarjetas de categoría: el plan
      exige un camino explícito al listado completo (útil para agotados/búsqueda); lo que se retiró
      es el salto desde el drawer, donde molesta al vender.
- [x] Tests: **34 nuevos** (los de 4.2 + los 10 de 4.3) ⇒ **188 en verde** en `test/home`.

**Límites deliberados:**
- Con **promoción** aplicable el alta rápida manda al detalle: el detalle ya calcula precio
  oferta/recargo y no se duplica esa lógica (un precio mal calculado en un TPV es peor que un toque
  extra).
- El alta rápida **no promete stock exacto**: la hoja enseña el saldo del momento y revalida contra
  él; la autoridad sigue siendo el servidor al registrar la venta (igual que en el detalle).

#### Correcciones del 2026-11-02 (probado en el TPV)

- [x] **«Seguir añadiendo» decía que la categoría no tenía subcategorías.** Bug real:
      `HomeController.volverARaiz()` subía a la raíz pero llamaba a `_limpiarNivel()`, que borra
      `_subcategorias`. Cuando la raíz del drawer es una **especial con hijas**, el nivel quedaba
      vacío y pintaba el mensaje de «esta categoría no tiene subcategorías» aunque sí las tuviera.
      Ahora `volverARaiz` limpia solo lo que corresponde al nivel de destino: en
      `subcategorias` conserva la lista (y la recarga si faltara), en `productos` mantiene el
      listado y en `categorias` limpia. Además, «Seguir añadiendo» se oculta cuando ya se está en la
      raíz (no hay nivel al que subir); ahí queda solo «Carrito». Regresión cubierta en
      `home_controller_test` y en `categoria_drawer_test`.
- [x] **Los productos elaborados iban al detalle aunque tuvieran 1 presentación y 1 ubicación.**
      Era una exclusión deliberada de la primera versión (`esElaborado || esServicio || esPaquete`).
      Se quitó: un **elaborado inequívoco ahora se añade directo**. El pedido a cocina y el consumo
      de ingredientes los resuelve `OrderService.addItemToCurrentOrder` igual que desde el detalle
      (en mostrador esa ruta solo inserta la línea; la comanda se dispara al cobrar). Se mantienen
      en el detalle **servicios y paquetes**, y un **elaborado sin saldo propio** (puede venderse
      por ingredientes) también va al detalle. Comprobado contra la base viva: en la tienda 223,
      `tacos` y `cerdo grille` tienen 1 presentación y 1 ubicación en el almacén del TPV ⇒ entran
      por el alta rápida; `caipiroska` no tiene inventario en ese almacén ⇒ sigue yendo al detalle.
- [x] **Alta rápida también en la búsqueda global del Home.** Los resultados de la búsqueda ya no
      son filas propias: usan el mismo `ProductoTile` del drawer (miniatura, precio, chip de stock)
      y el mismo «+» de alta rápida. Se añade `HomeProducto.desdeProducto(Product)` para adaptar el
      `Product` que devuelve `ProductService.searchProducts` a la fila ligera del Home. El «+» se
      oculta para servicios y para lo no vendible; si el producto tiene varias presentaciones,
      ubicaciones o promoción, la hoja se cierra y abre el detalle, igual que en el drawer.
      Tras agregar, el diálogo cambia según el contexto:
      **drawer** → «Continuar añadiendo» (sube a categorías); **búsqueda** → «Seguir comprando»,
      que **limpia el filtro** (y cierra el teclado) para volver al lienzo de categorías.
      «Ir al carrito» funciona igual en los dos casos.

### Fase 4.3 — Elaborados: venta por receta y disponibilidad real ✅ (1 migración pendiente)

Reportado al probar el TPV (2026-11-02) con una orden real de **12 tacos**:

```json
{"status":"error","message":"Stock insuficiente (disponible: 1.000000, requerido: 12.000000)",
 "error_code":"INSUFFICIENT_STOCK","origen":"barra","id_producto":10800,"id_almacen":331}
```

**Diagnóstico (contra la base viva):**

| Dato | Valor |
|---|---|
| `10800 tacos` | `es_elaborado=true`, `id_cocina=39` («Cocina caliente», activa, almacén 333), `modo_elaboracion=al_pedido`, receta: harina 0.03 kg + sal 0.003 kg por taco |
| Stock propio de `10800` en barra (almacén 331) | **1** unidad suelta (sobrante de una recepción) |
| Materia prima en cocina (333) | harina 1230 kg ⇒ `floor(1230/0.03) = 41000` tacos; sal de sobra |
| `10813 cerdo grille` | barra **0**, cocina 3 porciones + materia prima (carne 7.9 kg ⇒ 26 unidades) |

**Causa raíz (servidor):** `fn_resolver_origen_venta` aplicaba la «excepción de barra» (si hay
stock propio en la barra, se sirve de ahí con `descontar='sku'`) **antes** de la ruta de cocina.
Un elaborado con 1 unidad suelta en barra quedaba atado a su SKU y la venta de 12 fallaba, cuando
debía consumir la receta en la cocina. `fn_disponibilidad_plato` ya calculaba bien (41000), pero la
venta no coincidía con el catálogo.

**Arreglo:**

- [x] **Migración `20261102140000_fix_origen_venta_elaborado.sql`** — `fn_resolver_origen_venta`:
      la excepción de stock propio de barra deja de aplicar a productos **elaborados**
      (`AND NOT v_prod.es_elaborado`). Un elaborado sigue siempre su ruta: `al_pedido` consume
      receta en la cocina, `por_tanda` vende la porción hecha, sin cocina consume la MP del TPV.
      `fn_registrar_venta_v3` y `fn_descontar_venta_enrutada_v2` no cambian.
      ✅ **Aplicada en producción** (2026-11-02): la orden de 12 tacos ya consume receta de cocina.
- [x] **`ElaboratedAvailabilityService`** (`lib/services/`): llama a `fn_disponibilidad_plato(id,
      tpv)` y devuelve la cantidad máxima preparable. Tolerante: si falla o está offline devuelve
      vacío y se conserva el stock que ya había; tope de 20 productos por pantalla.
- [x] **Listado del Home (drawer) y búsqueda**: para elaborados se sustituye el stock propio por la
      **disponibilidad real**. `HomeCatalogService` enriquece los productos del drawer;
      la búsqueda global pide la disponibilidad en segundo plano (`_disponibilidadElaborados`).
      El chip del producto pasa a decir **«Elaborable: N»** (o «Sin materia prima») en vez de
      «Stock: 1/0».
- [x] **Alta rápida de elaborados**: `QuickAddService` ahora vende por **materia prima**:
      usa la disponibilidad como stock máximo, no exige fila de inventario propia (`variante`
      puede ser `null`) y manda `inventoryData` **sin ubicación** para que el servidor resuelva la
      de la cocina; con más de una presentación manda al detalle. Se aplica también en la búsqueda.
- [x] Tests: **10 nuevos** (5 de la regla de elaborados, 4 del servicio de disponibilidad y 1 del
      chip «Elaborable») ⇒ **188 en verde** en `test/home`.

**Respuesta al caso concreto:** con la migración aplicada, la orden de 12 tacos consumirá harina y
sal de la cocina (hay para 41000) y se registrará con `origen: cocina_al_pedido`; el listado
mostrará «Elaborable: 41000» para tacos y «Elaborable: 26» para cerdo grille. El `0` de cerdo en
barra era real (última salida lo dejó a 0), pero irrelevante: su venta también va por receta.

### Fase 5 — Detalle de producto ✅ (rediseño completo; pendiente prueba en dispositivo)

- [x] **Fuera la `AppBottomNavigation`** del detalle (duplicaba la barra de acción y el tab
      activo no existía): se liberan ~56 px y se elimina `_onBottomNavTap`, que solo existía para
      esa barra.
- [x] **Barra inferior fija con stepper + «Agregar»**: la barra ahora lleva un stepper
      −/cantidad/+ que actúa sobre la variante auto-seleccionada (o la cantidad base si no hay
      variantes) y sigue mostrando el total y «Agregar». No hay que bajar por el cuerpo para
      cambiar la cantidad.
- [x] **Controles visibles desde el primer frame**: mientras carga el detalle ya se pinta el
      `SliverAppBar` con el producto inyectado y una barra de progreso fina (antes era una pantalla
      blanca con spinner); la barra inferior está siempre presente.
- [x] **`SliverAppBar` colapsable con hero de imagen**: la foto ocupa la cabecera
      (`expandedHeight` 220-320 px), se colapsa al hacer scroll y el título queda legible con un velo
      degradado. El fallback (sin foto o modo ahorro de datos) es el degradado de la categoría.
- [x] **`Hero` desde el listado**: `ProductoTile` acepta `heroTag` y la miniatura del drawer/drawer
      de búsqueda viaja al hero del detalle con el tag `prod-{id}`.
- [x] **`LayoutBuilder` de dos columnas ≥ 900 px**: en pantallas anchas la imagen va en un panel
      fijo a la izquierda y la ficha + controles en una columna derecha con barra compacta
      (`_buildPanelImagenWide`, `_buildHeroSliver(expandido:false)`). En móvil se mantiene el hero a
      pantalla completa.
- [x] **Revisión de los 4 modos (estática)**: `_buildFractionStepSelector` y
      `_buildPresentationSelector` no se han tocado; el modo **fluido** usa
      `FluidProductDetailsWidget` (otra pantalla) y no pasa por aquí; normal, restaurante y
      servicentro comparten este detalle y conservan la barra de acción y el botón atrás (la
      `AppBottomNavigation` eliminada solo duplicaba navegación). **Falta confirmación en dispositivo
      real.**
- [x] **Auto-selección de la mejor variante** aunque haya varias ubicaciones: se elige la ubicación
      con más stock y, dentro, la variante con más saldo, con cantidad 1. Antes, con varias
      ubicaciones, el vendedor veía «UBICACIONES» **sin ningún control de venta** y tenía que tocar
      una variante a ciegas.
- [x] **«UBICACIONES» plegada y debajo de los controles**: `ExpansionTile` que se abre solo cuando
      hay más de una ubicación con stock; los controles de venta se pintan antes.
- [x] **Parámetro `producto` preinyectado**: el constructor ya recibía `product`; ahora ese objeto
      pinta el **primer frame** (hero + nombre + progreso) en lugar de una pantalla en blanco. La
      carga de variantes/presentaciones/stock sigue en segundo plano.
- [x] **Caché de detalle TTL 60 s** en `ProductDetailService` (R13), con `TtlCache` propio
      (`lib/utils/ttl_cache.dart`, reloj inyectable y tests) e invalidación al vender
      (`QuickAddService` y `_addToCart`). Cerrar y reabrir el mismo producto ya no paga
      `get_detalle_producto` + presentaciones.
- [x] **`ElaboratedProductChip` perezoso** (R14): recibe `esElaborado`/`esServicio` ya resueltos
      —el detalle los tiene— y **solo consulta ingredientes al tocarlo**. Se elimina la cascada
      `isProductElaborated` + `isProductServicio` + ingredientes + N RPC al abrir el detalle.
- [x] **Borrados los restos de USD**: `_loadUsdRate()` fuera del `initState`, `_buildUsdRateChip`
      muerto, el estado `_usdRate`/`_isLoadingUsdRate` y los imports que quedaban sin uso.
- [x] **Doble validación de stock eliminada**: se conserva la guarda rápida del `initState` (sin
      red) y se quita la segunda comprobación tras cargar el detalle, que pagaba la RPC para
      descartar su resultado.
- [x] **Parser compartido**: `ProductDetailService.productoDesdeRespuestaDetalle` (estático) sustituye
      las ~200 líneas que la pantalla duplicaba para reconstruir variantes desde el cache offline.
      El mismo parser se usa online y offline (tests en `product_detail_phase5_test.dart`).
- [x] **`UsdRateChip` único**: el chip compartido ya vive en `lib/widgets/usd_rate_chip.dart`;
      con el borrado del muerto del detalle quedan solo las copias vivas de Home/Ajustes.

**Tests añadidos en esta pasada:** `ttl_cache_test` (4) y `product_detail_phase5_test` (5) ⇒
**197 en verde** en `test/home`. El detalle completo sigue compilando (lo cubre el smoke del Home).

### Fase 5.1 — Unificación visual del resto de la app ✅ (pendiente revisión en dispositivo)

Encargo: que el **detalle de producto**, **preorden**, **listado de órdenes**, **settings**,
**drawer** y **notificaciones** se sientan de la misma familia que el Home y el listado nuevos,
manteniendo profesionalidad.

**Base común**

- [x] **`ThemeData` global** (`main.dart`): superficie `#F5F7FA`, AppBar primary con título w700,
      `CardTheme` blanco radio 18 con borde, botones (filled/elevated/outlined/text) radio 12,
      inputs radio 14 con borde/foco, chips radio 8, `DialogTheme` radio 20, bottom sheet radio 24,
      snackbars flotantes, `ListTileTheme` primary, divider y progreso tokenizados. A partir de aquí
      cualquier pantalla hereda el lenguaje aunque no se toque a mano.
- [x] Tests: el nuevo `test/home/app_compile_test.dart` importa `main.dart` y **compila toda la app**
      (detecta roturas en cualquier pantalla, no solo en Home). `test/home`: **198 en verde**.

**Pantallas**

- [x] **Detalle de producto**: barrido de tokens (`0xFF4A90E2` → `primary`, grises → `border`/
      `textPrimary`/`textSecondary`, fondos → `surface`), tarjetas radio 16-20 con `shadowCard`,
      barra inferior blanca con borde y sombra suave, stepper sobre `surface`, rótulo «UBICACIONES»
      con `rotuloBloque`, appbar compacta de escritorio en `card`.
- [x] **Preorden** (+426/−245): superficie, AppBar primary, estado vacío con icono en círculo
      primary, cabecera/tarjetas de ítem radio 16 con `shadowCard`, selectores de pago con tintes
      semánticos, footer con botones radio 12, 5 diálogos y snackbars tokenizados. Cero colores
      ad-hoc restantes.
- [x] **Listado de órdenes** (listado + detalle de orden): superficie y AppBar primary, buscador
      con campo `filled` radio 14, estado vacío, cabeceras de sección con `tituloSeccion` y contador
      en chip, tarjeta de orden radio 18 con `shadowCard`, badges de estado pastel, `_getStatusColor`
      y colores de medio de pago con tokens, secciones/filas del detalle, botones de acción radio 12,
      desglose de pagos y hoja de descuento. La hoja interna de edición de productos pendiente
      (`_showEditPendingOrderSheet`) quedó fuera.
- [x] **Settings**: `_buildSectionHeader` con `rotuloBloque` (mayúsculas), tarjetas radio 18 con
      borde/sombra, `_settingsIcon()` 38×38 primary al 10 %, tiles y switches con tokens, badges y
      botón de logout con `danger`, diálogos de sync/actualización/almacenamiento tokenizados.
- [x] **AppDrawer**: cabecera con `heroGradient` y textos blancos, items radio 12 con icono en
      contenedor primary al 8 %, separadores suaves, footer `card`. (Sin estado de selección: no hay
      noción de ruta actual; `selectedTileColor` pre-cableado.)
- [x] **Notificaciones**: campana con badge `danger`, panel radio 20 con borde/sombra suave, header
      con icono en contenedor primary, chips primary, lista con iconos semánticos por tipo, fondo de
      no leído primary al 4 %, swipe de borrado `danger`, estado vacío limpio.

**Notas**

- Los cambios fueron **solo visuales** (colores, radios, bordes, sombras, paddings, tipografía);
  no se tocaron servicios, lógica, callbacks, keys ni textos. Verificado por compilación completa.
- **No verificado en emulador** en esta sesión (el CLI de Flutter está bloqueado por el sandbox):
  hace falta una pasada visual real en móvil y web.
- `dart format` de Dart 3.12 no es canónico con el baseline del repo; se evitó reformatear en masa
  para no mezclar ruido con el rediseño (pendiente un formateo global aparte).

**Pantallas pendientes de revisar** (ver informe de la sesión): checkout, venta total, cierre,
apertura, paquetes, mesas/cuenta, `products_screen`, servicentro, login/splash y pantallas técnicas.

### Fase 6 — Admin
- [ ] `models/category.dart` + `services/category_service.dart` (incluye escribir en la puente)
- [ ] `widgets/categories_tab_view.dart`: switch, chip, reorden, contador
- [ ] Aviso si la categoría no tiene productos vendibles
- [ ] Probar el admin contra la base real antes de cerrar la fase

### Fase 7 — Extras y limpieza (tras validar)
- [ ] Riel «Más vendidos» (necesita RPC de ranking por TPV)
- [ ] Promociones vigentes como riel
- [ ] Deprecar y borrar `fluid_mode_screen.dart` + `fluid_product_details_widget.dart` + `product_search_widget.dart`
- [ ] Renombrar «Tienda» desde `app_dat_configuracion_tienda` (D2)
- [ ] Arreglar o retirar la ruta mock `/categories` del admin
- [ ] **Borrar código muerto**: `_ProductCard` + `_PropertyIcon` (`products_screen.dart:1387-1759`, ~373 líneas),
      `_buildUsdRateChip` (`product_details_screen.dart:4001-4041`), `_getTotalItems` (`:2979-2989`),
      estado `_selectedPresentation` (`:81`)
- [ ] Arreglar los bugs de §R16 (`admin_inventory_service.dart:1665`, `product_details_screen.dart:3134`,
      etiqueta `'Sin subcategoría'` vs `'General'`, changelog web con `'1.0.0'`)

### Fase 8 — QA y rollout
- [ ] `flutter analyze` limpio en `ventiq_app` y `ventiq_admin_app`
- [ ] Golden tests: home (360, 412, 1280) y drawer en sus 3 niveles
- [ ] Prueba manual en APK real: 1 mano, 360 px, teclado abierto
- [ ] Prueba en Chrome del TPV: redimensionar, zoom 125 %
- [ ] Modo sin conexión: home desde caché, drawer desde caché, **flag `especial` presente offline**
- [ ] Medir: tiempo hasta primer frame, nº de requests, tamaño del JSON
- [ ] Marcar las especiales de las tiendas piloto y validar con el gerente

---

## 12. No hacer

- [ ] No crear tablas nuevas.
- [ ] **No ejecutar ninguna limpieza/fusión de categorías duplicadas**: descartada por decisión
      del usuario. El script se eliminó del repo. La duplicación se resuelve **solo** en la
      lectura, con el colapso por denominación de `get_home_catalogo_tpv`.
- [ ] No poner el flag en `app_dat_categoria` (global) salvo decisión explícita: filtraría entre tiendas.
- [ ] No cambiar el `RETURNS TABLE` de `get_categorias_by_tienda_tpv` ni de las
      `get_productos_by_categoria_tpv_*` que usa el TPV: obligaría a `DROP`+`CREATE` y
      rompería el TPV entero si algo falla. Todo lo nuevo va en funciones nuevas.
- [ ] No reescribir `sync_bundle`: propaga columnas nuevas solo.
- [ ] No subir `_dbVersion` de SQLite: el flag viaja en el `payload`.
- [ ] No tocar RLS: ya existe policy `ALL` con UPDATE para `authenticated`.
- [ ] No meter `provider`/`riverpod`/`bloc` en `ventiq_app`.
- [ ] No cambiar el flujo de venta, checkout, mesas, cocina ni servicentro.
- [ ] No «arreglar» `FluidModeScreen` en esta fase: se depreca (D4).
- [ ] No prometer horarios, reseñas, distancias ni multi-moneda: el TPV no los tiene.

---

## 13. Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | **Regresión en el flujo de venta**: `categories_screen.dart` contiene lógica no visual (`SalesModeService`, `_checkForUpdatesAfterNavigation`, `_loadOfflineModeSettings`, `_loadDataUsageSettings`, `_loadFluidModeSettings`) | Extraerla a `HomeController` **antes** de borrar las pantallas; §11-Fase 3; mantener las viejas un release |
| R2 | **`app_dat_categoria` es global**: si se elige la alternativa de D1, la marca se filtra entre tiendas | Usar `app_dat_categoria_tienda` (recomendado) |
| R3 | **`updateCategory` del admin falla en silencio** (devuelve `false` sin log, `:368-371`) → el switch «no hace nada» | Añadir log del error + verificar tras guardar que `especial` cambió. El permiso UPDATE **sí existe** (verificado) |
| R4 | **El flag se pierde offline** por los dos `map` explícitos | §5.4: tocar `auto_sync_service.dart:441-454` y `categories_screen.dart:300-318` |
| R5 | La RPC nueva es más lenta que la actual | Índice parcial + `EXPLAIN ANALYZE` en Fase 0; si hace falta, contar con `EXISTS` en vez de `LEFT JOIN` + `count(distinct)` |
| R6 | La RPC actual usa `INNER JOIN` a subcategorías ⇒ aparecerán categorías que antes no salían | Validar con el gerente; el `HAVING count > 0` descarta las vacías |
| R7 | Contadores de subcategorías inflados (la RPC actual no filtra stock) | Usar `get_subcategorias_by_categoria_tpv` (nueva) |
| R8 | El drawer choca con el gesto «atrás» del sistema | `PopScope` probado en Android físico en Fase 4 |
| ~~R9~~ | ~~`cached_network_image` + `shimmer` rompen web/Windows~~ | **Cerrado: no se añaden dependencias.** Se descartaron ambas (§10) |
| R10 | La pantalla `/categories` del admin es un mock: el gerente no encontrará el switch | Fase 6 apunta a `categories_tab_view.dart`; Fase 7 arregla o retira la ruta mock |
| R11 | Deuda preexistente que puede confundir el diagnóstico | `subcategory_service.dart:148` consulta `app_dat_productos` (tabla inexistente) ⇒ la guarda «tiene productos» nunca se activa. `marketplace/category_service.dart:64` selecciona `imagen` cuando la columna es `image` |
| **R12** | **Duplicación de categorías (§5.6)**: 1056 filas para 343 nombres; una tienda con 208 «Alimentos» ⇒ el home mostraría cientos de tarjetas idénticas | Colapsar por nombre en la RPC con `grupo_ids` (defensa no destructiva) **antes** de la Fase 3; limpieza de datos como tarea aparte con respaldo |
| **R13** | **El detalle siempre re-consulta** porque el listado entrega `variantes: []` (`product_service.dart:372`). Sin caché, «salto directo al detalle» no se siente rápido | Caché de detalle con TTL 60 s en `ProductDetailService` (§8). No cambiar el `RETURNS TABLE` del listado en esta fase |
| **R14** | `ElaboratedProductChip` en la cabecera dispara 8 RPC seriales + 4 queries por apertura (§3.8-2) | Hacerlo perezoso: recibir `es_elaborado`/`es_servicio` del detalle y consultar ingredientes solo al tocar |
| **R15** | **No se puede filtrar por subcategoría** sin leer `id_subcategoria` (hoy descartado en `product_service.dart:324-395`) ni pasa `ProductsScreen` un parámetro de subcategoría | Añadir ambos en Fase 3/4; sin eso el requisito «ver el listado completo de la subcategoría» no se puede cumplir |
| **R16** | Bugs preexistentes que pueden confundirse con regresiones nuestras | `categories_web_screen.dart:98,111` (changelog con versión `'1.0.0'` hardcodeada), `:588-602` (el overlay web no valida stock y el móvil sí), `admin_inventory_service.dart:1665` (usa `id_categoria` como `id_sub_categoria`, con `catch (_)` que lo silencia), `product_details_screen.dart:3134` (identifica la variante con `contains` sobre el nombre) |
| **R17** | **Historial de migraciones desincronizado**: los objetos están aplicados pero `list_migrations` no los registra (última: `20261012150148`) ⇒ un futuro `supabase db push` los re-ejecutará | Los 3 archivos son idempotentes (verificado), así que re-ejecutarlos es inocuo. Aun así, reconciliar con `supabase migration repair --status applied …` antes de la Fase 6 (§5.7) |
| **R18** | La Fase 0 se cerró **sin `EXPLAIN (ANALYZE)`** de las RPC nuevas ni prueba funcional desde la app autenticada | El cuerpo de `get_home_catalogo_tpv` sí se validó (parsea y la guarda deniega correctamente), pero el rendimiento con una tienda grande (173/174) está sin medir. Hacerlo antes de la Fase 3 |

---

## 14. Criterios de aceptación

1. Con `Combustibles` y `Servicios` especiales y `Comida`/`Recreación` no especiales, el home
   muestra **3 tarjetas**: Combustibles, Servicios y Tienda.
2. La tarjeta Tienda lista exactamente Comida y Recreación al abrirse.
3. Tocar Combustibles abre el drawer **a pantalla completa**; si tiene subcategorías, las muestra.
4. Desde el drawer: `atrás` del sistema sube un nivel; desde la raíz cierra. La «X» no es la única salida.
5. Tocar una subcategoría muestra sus productos sin salir del drawer.
6. Tocar un producto abre el detalle **sin** pasar por `ProductsScreen`, y el detalle pinta datos
   reales en el primer frame.
7. «Ver listado completo» lleva a `ProductsScreen` de esa categoría.
8. El buscador está visible en todo momento, sin scroll, entre el hero y el lienzo.
9. En un móvil de 360 px el detalle muestra imagen, precio y **los controles de venta**
   (stepper −/cantidad/+) **sin scroll y sin tener que tocar antes una variante**.
10. El gerente marca/desmarca «especial» y el cambio se ve en el TPV tras refrescar.
11. **En modo offline** el flag `especial` sigue presente y el home se agrupa igual.
12. Marcar una categoría especial en la tienda A **no** la marca especial en la tienda B.
13. `flutter analyze` sin nuevos warnings en las dos apps.
14. El home pinta con **una** petición de red (verificable en el log del TPV).
15. En la tienda `148` (208 categorías homónimas) el home muestra **11 tarjetas**, una por
    nombre, con los contadores sumados — no cientos de tarjetas repetidas.

---

## 15. Anexo — mapa de archivos

### Modificar
| Archivo | Cambio |
|---|---|
| `ventiq_app/lib/main.dart` | `:133` → `HomeShellScreen`; rutas viejas al mismo shell |
| `ventiq_app/lib/services/category_service.dart` | `+ esEspecial` en el modelo inline (`:91-142`), o deprecarlo en favor de `home_catalog_service.dart` |
| `ventiq_app/lib/services/auto_sync_service.dart` | `:441-454` → incluir `especial` |
| `ventiq_app/lib/screens/settings_screen.dart` | `:4578-4597` → **segunda copia** del mapeo; incluir `especial` |
| `ventiq_app/lib/services/product_service.dart` | `_convertSupabaseToProduct` (`:324-395`): leer `id_subcategoria` (hoy se descarta) |
| `ventiq_app/lib/screens/products_screen.dart` | `:32-46`: aceptar `subcategoriaId`/`subcategoriaNombre` e `initialProducto` |
| `ventiq_app/lib/screens/product_details_screen.dart` | §8 |
| `ventiq_app/pubspec.yaml` | **sin cambios**: no se añaden dependencias (§10) |
| `ventiq_admin_app/lib/models/category.dart` | `especial`, `ordenHome` (de verdad, no como los campos muertos `:58-64`) |
| `ventiq_admin_app/lib/services/category_service.dart` | `createCategoryWithId`, `updateCategory` (escribir en la puente), `setEspecial`, `setOrdenHome` |
| `ventiq_admin_app/lib/widgets/categories_tab_view.dart` | switch + chip + reorden + contador |

### Crear
**Escritas y YA APLICADAS en producción** (verificadas contra la base viva, §5.7):
- `supabase/migrations/20261101120000_add_especial_categoria_tienda.sql` — flags por tienda, índice parcial y único.
- `supabase/migrations/20261101120100_get_categorias_by_tienda_complete_v2.sql` — RPC del admin con `especial`/`orden_home`.
- `supabase/migrations/20261101120200_get_home_catalogo_tpv.sql` — RPC del Home (con colapso por nombre) + RPC de subcategorías del grupo.
- ⚠️ Aplicadas a mano: **no figuran en el historial de migraciones**. Reconciliar (§5.7).

**Descartado:**
- ~~`sql_updates/limpieza_categorias_duplicadas.sql`~~ — eliminado del repo (D7-B descartada, §5.6.1).

**Pendientes de crear (Dart, §4.1):** los 15 archivos de `lib/`.

### Eliminar (Fase 7)
`ventiq_app/lib/screens/categories_screen.dart`,
`ventiq_app/lib/screens/categories_web_screen.dart`,
`ventiq_app/lib/screens/fluid_mode_screen.dart`,
`ventiq_app/lib/widgets/fluid_product_details_widget.dart`,
`ventiq_app/lib/widgets/product_search_widget.dart` (solo lo usa el modo fluido; usa una RPC
peor, sin `text_search`, que descarga el catálogo completo y filtra en cliente),
y el código muerto listado en §3.8.

---

## 16. Notas de método

- Esquema, RLS, GRANTs, índices, duplicados y definiciones de RPC se verificaron **contra la
  base viva** con el MCP de Supabase, no contra `VentiQ.sql` (que se autodeclara *«for context
  only»*, no trae RLS ni GRANTs y puede estar obsoleto).
- Las RPC de categorías **no tienen `CREATE FUNCTION` en el repo**; los cuerpos de
  `get_categorias_by_tienda_complete`, `get_categorias_by_tienda_tpv2` y
  `get_subcategorias_by_categoria` se volcaron con `pg_get_functiondef()` y están reflejados
  en §3.4/§5.
- Los conteos de línea citados son los reales del repo (difieren de los del encargo inicial en
  algunos archivos del admin).
- Los tres reconocimientos (home de `inventtia_flow`, home/detalle de `ventiq_app`,
  categorías admin + backend) se hicieron en paralelo y **se cruzaron**: donde el análisis
  estático del `.sql` y la verificación en vivo discrepaban, manda la verificación en vivo.
  Las RPC se volcaron con `pg_get_functiondef()`; RLS e índices con `pg_policies` / `pg_indexes`;
  GRANTs con `has_table_privilege`.
- **Las 3 migraciones están aplicadas en producción.** Verificado en vivo: columnas, índices y
  firmas de las RPC coinciden exactamente con los archivos, `SECURITY DEFINER` y
  `search_path=""` incluidos. El cuerpo de `get_home_catalogo_tpv` llega hasta la guarda de
  acceso y deniega mi sesión de MCP (sin usuario de tienda) sin error 42P01 ⇒ el patrón
  `search_path = ''` + `set_config` es correcto.
- **Lo que NO se ha validado todavía:** el rendimiento de las RPC nuevas con una tienda grande,
  y su comportamiento end-to-end desde la app autenticada (mi sesión de MCP no puede pasar la
  guarda, que es justo lo que debe hacer). Ver R18.
- **Fase 1 completada** (salvo el golden test): 6 archivos nuevos en `ventiq_app/lib/`
  (`theme/ventiq_home_theme.dart`, `utils/categoria_icono.dart`, `utils/categoria_gradiente.dart`,
  `widgets/home/tarjeta_exploracion.dart`, `widgets/home/home_seccion_titulo.dart`,
  `widgets/home/home_estado_vacio.dart`) y 3 archivos de test con **32 pruebas en verde**.
  `mcp__dart__analyze_files` sin errores. `pubspec.yaml` **sin cambios**.
- **Un bug real encontrado por los tests:** el mapeo de iconos por palabra clave usaba
  `contains`, así que el fragmento `ron` (Ron) casaba dentro de «elect**rón**ica» y `te` (Té)
  dentro de «textil». Se corrigió exigiendo **límite de palabra** a los fragmentos de menos de
  5 letras, con dos pruebas de regresión.
- **Fase 2 completada:** 3 archivos nuevos (`models/home_catalogo.dart`,
  `services/home_catalog_service.dart`, `controllers/home_controller.dart`) y 2 de test.
  **88 pruebas en verde** en total en `test/home/`.
- **Dos bugs reales encontrados por los tests de la Fase 2:**
  1. `ordenHome` del grupo colapsado. Tomar el mínimo parecía lo natural, pero `0` significa
     «sin orden manual», así que un grupo con `[0, 3]` quedaba en `0` y perdía el orden que
     había elegido el gerente. Ahora se toma el menor de los **no cero**.
  2. El controlador ordenaba la lista de resultados de búsqueda en su sitio, y el gateway
     puede devolver una lista cacheada **inmutable** ⇒ `Unsupported operation` en producción.
     Ahora copia antes de ordenar.
- **El colapso por nombre existe en tres capas** (backend + `HomeCatalogo.agrupar` +
  `HomeSubcategoria.agruparPorNombre`). Es deliberado: con 1056 filas para 343 nombres, una
  sola capa no basta, y el cliente no debe depender de que el backend lo haga.
- **Ningún archivo Dart preexistente se ha modificado**: Fases 1 y 2 son solo archivos nuevos.
  El Home actual sigue intacto y funcionando.
- **Fase 3 completada:** 6 archivos nuevos más (`home_hero_header`, `home_buscador`,
  `home_quick_chips`, `ventiq_skeleton`, `tienda_card`, `home_catalogo_view`), la pantalla
  `home_shell_screen.dart`, el chip compartido `usd_rate_chip.dart`, y **3 cambios en archivos
  preexistentes**: `main.dart` (la ruta `/categories` apunta al Home nuevo) y 2 de test.
  ⚠️ **La cifra «128 pruebas en verde» de esta fase no era verificable**: `home_shell_test.dart` no
  compilaba (faltaba el parámetro `onAbrirListado`) y **`home_shell_screen.dart` tampoco compilaba**
  (ver Fase 4). La suite real que corría eran 106 pruebas de los widgets puros. Corregido en Fase 4.
- **`mcp__dart__analyze_files` no es fiable.** Dijo «No errors» dos veces sobre código que el
  compilador rechazó (`_home.tieneBusquedaActiva` inexistente, un `typedef` a un tipo que no
  existía). **Regla a partir de ahora: los tests son la verificación, el analizador es solo un
  primer filtro.**
- **Hallazgo de arquitectura (afecta a todo el plan):** los servicios de la app construyen
  `Supabase.instance` **en el constructor**, y varios widgets del armazón
  (`AppBottomNavigation` → `MesaCuentaService`; `ConnectionStatusWidget` → `SmartOfflineManager`
  → `AutoSyncService` → `ReauthenticationService` → `PromotionService` → `ProductService`)
  lo arrastran. Consecuencias:
  1. Montar la pantalla entera en un test obliga a inicializar Supabase, y
     `Supabase.initialize` **cuelga el runner** (probado: dos timeouts). Por eso el Home viejo
     no tenía ni un test.
  2. La solución aplicada: los servicios del shell se crean **de forma perezosa** (el Home
     pinta aunque Supabase no esté listo) y el contenido se extrajo a `HomeCatalogoView`, que
     no toca ningún servicio y se prueba entero.
- **Dos tareas del plan que se caen por sí solas:** la caché offline en `auto_sync_service` /
  `settings_screen` **ya no hace falta** (el Home nuevo tiene su propio snapshot, el flag
  `especial` no viaja por la caché vieja), y la unificación de la búsqueda queda para la Fase 4
  porque exige decidir el mapeo `HomeProducto → Product`.
- **Cambio de comportamiento a confirmar:** el diálogo de actualización **no** se portó al Home
  nuevo. Era la tercera copia (splash y ajustes ya lo hacen) y el Home no es su sitio. Si se
  quiere mantener el aviso al entrar, hay que decirlo.
- Artefactos escritos: este documento + las 3 migraciones (aplicadas). La limpieza de
  duplicados se descartó y su script se eliminó del repo.
- **Fase 4 completada.** 3 archivos nuevos (`categoria_drawer.dart` 850 líneas,
  `categoria_drawer_route.dart`, `producto_tile.dart`), 1 archivo de test nuevo con **19
  `testWidgets`** y 2 arreglos en archivos existentes (`home_shell_screen.dart`,
  `home_shell_test.dart`) más 1 smoke test. Suite `test/home`: **148 pruebas en verde**
  (106 previas + 22 de `home_shell_test` que ya compila + 19 del drawer + 1 smoke del armazón).
- **⚠️ Hallazgo grave de la Fase 4: el armazón del Home no compilaba y la Fase 3 se cerró como
  «128 en verde» sin serlo.** El compilador encontró dos errores que el analizador no vio:
  1. `home_shell_screen.dart` usaba `HomeSeccionTitulo` **sin importarlo**.
  2. `_abrirProducto(Product p)` pasaba un `Product` (resultado de búsqueda) a un método que
     espera `HomeProducto`. Se separó en `_abrirProductoCompleto(Product)`.
  Ninguno de los 106 tests existentes importaba `home_shell_screen.dart`, así que la suite no lo
  compilaba. **Medida añadida:** `test/home/home_smoke_test.dart`, que importa y construye el
  armazón (sin montarlo) para que un error de compilación del shell rompa la suite.
  También `home_shell_test.dart` no compilaba (faltaba `onAbrirListado` en `HomeCatalogoView`) y
  el test de «Ver todos» seguía esperando `onTapCategoria`; ambos corregidos.
- **La regla «el analizador no es fiable» se queda corta: tampoco lo es para errores de
  compilación.** `mcp__dart__analyze_files` respondió «No errors» sobre `home_shell_screen.dart`
  mientras `flutter test` fallaba con dos errores de compilación en ese archivo. La verificación
  es **compilar ejecutando tests** que importen el archivo; para el armazón, el smoke test.
- **Bug real de UX encontrado por los tests del drawer:** la «X» no cerraba en niveles
  profundos. `_cerrar()` usaba `Navigator.maybePop()`, que consulta al `PopScope`; con pila > 1
  el `PopScope` bloquea el pop para subir nivel, así que la «X» **subía** en vez de cerrar. Ahora
  `Navigator.pop()` directo. (El velo y el arrastre de cabecera usan el mismo `_cerrar`.)
- **⚠️ El entorno de esta sesión no puede ejecutar `flutter`/`dart` desde pwsh**: el sandbox de
  escritura bloquea el lockfile de Flutter (`bin/cache/lockfile`) y, con
  `FLUTTER_ALREADY_LOCKED=true`, falla al lanzar `cmd /c ver` (`CreateFile failed 5`). **Vía que
  funciona: el MCP de Dart** (`mcp__dart__run_tests`, con `roots` y `arguments`), que ejecuta
  `flutter test` real fuera del sandbox. Los `analyze_files` de ese MCP sí son sospechosos (ver
  arriba).
- **Para la Fase 5 queda decidido el punto que la Fase 3 dejó abierto:** el mapeo
  `HomeProducto → Product` no se hace antes del detalle. El drawer abre el detalle apilado
  encima y resuelve el `Product` con `ProductService.getProductsByCategory` (caché 5 min); con
  la caché de detalle TTL 60 s de la Fase 5 ese paso desaparece. La venta rápida «+» queda
  cableada a ese mismo mapeo.