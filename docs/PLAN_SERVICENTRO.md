# Plan: modo servicentro

Checklist de implementación. Marca `[x]` lo hecho, `[~]` parcial, `[ ]` pendiente.
Vamos avanzando fase por fase; no saltar dependencias.

> **Estado:** Fases 1-5 OK · config por **TPV** · SQL `03`+`04` aplicados · listo para piloto.
> **Intent confirmado:** 2026-09-16 · **alcance TPV confirmado:** 2026-09-16.
> SQL: `01_schema.sql`, `02_rpcs.sql` (histórico tienda), **`03_migracion_tpv.sql`**, **`04_rpcs_tpv.sql`**.

---

## Intent (referencia)

- **Outcome:** Modo servicentro **por TPV**: venta solo de combustible con UI de cartas; conversión litros ↔ dinero; un tipo por venta.
- **User:** Vendedor en el TPV configurado; gerente configura **por TPV** en admin (Gestión de TPVs → Servicentro).
- **Success:** Misma tienda puede tener TPV servicentro y TPV tienda normal; cada uno con su lista/orden/color/columnas.
- **Constraint:** Productos + `es_combustible`; selección explícita **por TPV**; stock normal; checkout reutilizado.
- **Out of scope:** Config desde el TPV vendedor; venta mixta en TPV servicentro; varios combustibles por ticket; hardware; tanque.

### Reglas de negocio

- [x] Con modo servicentro activo **en ese TPV** solo se vende combustible.
- [x] Combustibles = productos normales + flag `es_combustible`.
- [x] Lista de cartas = selección explícita **por TPV**.
- [x] Por TPV: orden, color, columnas.
- [x] Litros ↔ dinero (Fase 4).
- [x] Un solo tipo por venta.
- [x] Tras cobrar → grid.
- [x] Stock como producto normal.
- [x] ~~Modos excluyentes a nivel tienda~~ **Obsoleto:** servicentro es por TPV; puede coexistir con modo restaurante de tienda en *otros* TPV.
- [x] Configuración en `ventiq_admin_app` (gerente), anclada al TPV.

---

## Intent (referencia)

- **Outcome:** Modo servicentro: venta solo de combustible con UI de cartas (columnas / orden / color) y conversión litros ↔ dinero; un tipo por venta; tras cobrar vuelve al grid.
- **User:** Vendedor vende en `ventiq_app`; **gerente** configura en `ventiq_admin_app`.
- **Success:** Gerente activa modo, elige combustibles, orden, color y columnas; vendedor ve ese grid, vende un tipo con litros↔$, cobra, y listo para la siguiente.
- **Constraint:** Productos normales + flag `es_combustible`; selección explícita por tienda; modos excluyentes; stock como producto normal; reutilizar checkout.
- **Out of scope:** Config desde el TPV vendedor; venta mixta; varios combustibles por ticket; hardware surtidor; lógica de tanque; orden custom del catálogo fuera de servicentro.

### Reglas de negocio

- [x] Con modo servicentro activo solo se vende combustible (no mostrador mixto).
- [x] Combustibles = productos normales + flag `es_combustible`.
- [x] Lista de cartas = selección explícita por tienda (no auto-todos los `es_combustible`).
- [x] Por tienda: orden, color de carta, cantidad de columnas.
- [x] Entrada de venta: litros ↔ dinero sincronizados.
- [x] Un solo tipo de combustible por venta/ticket.
- [x] Tras cobrar → volver al grid de combustibles.
- [x] Stock se descuenta como producto normal.
- [x] Modos excluyentes: no se puede activar servicentro si restaurante/cocina (u otro modo) está activo, y viceversa.
- [x] Configuración solo en `ventiq_admin_app` con rol gerente.

---

## No hacer

- [ ] No poner la config de servicentro en Settings del vendedor (`ventiq_app`).
- [ ] No inventar checkout paralelo: reutilizar preorden/checkout actuales (o atajo equivalente a 1 línea).
- [ ] No lógica de tanque / totalizador / hardware.
- [ ] No varios combustibles en el mismo ticket.
- [ ] No orden custom del catálogo general (solo lista servicentro).
- [x] **Nunca** crear tablas nuevas sin `ENABLE ROW LEVEL SECURITY` + policies (regla proyecto).
- [ ] No asumir que `store_config` sync basta para la lista satélite: hay que sincronizar `app_dat_servicentro_producto` aparte.

---

## Modelo de datos propuesto

```
app_dat_producto
  + es_combustible boolean DEFAULT false

app_dat_configuracion_tienda
  + modo_servicentro boolean DEFAULT false
  + servicentro_columnas int DEFAULT 2   -- UI grid del vendedor

app_dat_servicentro_producto   (NUEVA)
  id
  id_tienda      → app_dat_tienda
  id_producto    → app_dat_producto  (debe tener es_combustible = true)
  orden          int
  color          text   -- hex, ej. #2E7D32
  UNIQUE (id_tienda, id_producto)
```

**Exclusión de modos** (en servicio admin + constraints/validación):

| Al intentar activar | Bloquear si está activo |
|---------------------|-------------------------|
| `modo_servicentro`  | `modo_restaurante` o `cocina_activa` |
| `modo_restaurante`  | `modo_servicentro` |
| `cocina_activa`     | `modo_servicentro` |

---

## Fase 0 · Alineación (hecho)

- [x] Entrevista de requisitos y confirmación de intent.
- [x] Plan escrito en `docs/PLAN_SERVICENTRO.md`.

**Entrega:** este archivo como fuente de verdad del progreso.

---

## Fase 1 · Schema / SQL

> Base de datos y RPCs mínimas.

### 1.1 Schema — `funcionalidad_servicentro/01_schema.sql`

- [x] `ALTER` `app_dat_producto.es_combustible` (script).
- [x] `ALTER` `app_dat_configuracion_tienda.modo_servicentro` (script).
- [x] `ALTER` `app_dat_configuracion_tienda.servicentro_columnas` default 2, CHECK 1–4 (script).
- [x] Tabla `app_dat_servicentro_producto` (tienda, producto, orden, color hex) (script).
- [x] Índices / UNIQUE `(id_tienda, id_producto)` (script).
- [x] Comentarios SQL en columnas (script).
- [x] **RLS habilitado** + policies select (acceso tienda) / write (gerente|superadmin).
- [x] Helpers `fn_user_can_read_tienda` / `fn_user_is_gerente_or_superadmin`.
- [x] Script en `funcionalidad_servicentro/01_schema.sql`.
- [x] **Aplicar `01_schema.sql` en proyecto Supabase VentiQ** (SQL Editor).
  - Verificado: RLS on, 4 policies, columnas `es_combustible` / `modo_servicentro` / `servicentro_columnas`.

### 1.2 Validación / RPCs — `funcionalidad_servicentro/02_rpcs.sql`

- [x] Trigger `trg_config_tienda_modos_excluyentes` (servicentro vs restaurante/cocina).
- [x] Trigger producto válido (`es_combustible` + misma tienda).
- [x] `fn_set_modo_servicentro` (gerente; rechazo `MODO_EXCLUYENTE`).
- [x] `fn_get_servicentro_config` (lectura completa).
- [x] `fn_listar_servicentro_productos` (grid vendedor + precio/stock opcional TPV).
- [x] `fn_upsert_servicentro_producto` / `fn_eliminar_servicentro_producto` / `fn_reordenar_servicentro_productos`.
- [x] **Aplicar `02_rpcs.sql` en proyecto Supabase VentiQ** (SQL Editor).
  - Verificado: 9 funciones servicentro presentes.

**Dependencias:** ninguna.
**Entrega:** schema + RPCs aplicados; lectura de config servicentro posible vía Supabase.

---

## Fase 2 · Admin (`ventiq_admin_app`) — configuración gerente

> Toda la gestión de config vive aquí.

### 2.1 Producto: flag combustible

- [x] Campo `es_combustible` en modelo producto admin.
- [x] Toggle en alta/edición de producto (gerente).
- [x] Persistencia en create/update de producto (update directo; create con patch post-RPC).

### 2.2 Config tienda: modo + columnas + exclusión

- [x] `ServicentroService` + RPCs (`fn_set_modo_servicentro`, etc.).
- [x] UI en config global (junto a restaurante / cocina).
- [x] Al activar servicentro: si restaurante o cocina activos → bloquear (no auto-apagar).
- [x] Al activar restaurante o cocina: si servicentro activo → bloquear.
- [x] Gestión accesible a gerente (ruta `/servicentro-management` + drawer).

### 2.3 Lista servicentro por tienda

- [x] Pantalla `ServicentroManagementScreen`.
- [x] Agregar producto: solo `es_combustible` y no en lista.
- [x] Quitar producto de la lista.
- [x] Reordenar (subir/bajar) → `fn_reordenar_servicentro_productos`.
- [x] Color por ítem (swatches + hex).
- [x] Selector de columnas (1–4).
- [x] Preview simple del grid.

**Dependencias:** Fase 1.
**Entrega:** gerente puede marcar productos, activar modo (si no hay otro), armar lista orden/color/columnas.

---

## Fase 3 · Vendedor (`ventiq_app`) — consumir config + navegación

> Sin UI de venta todavía: solo flags, cache y home.

### 3.1 Store config + sync

- [x] Extender `StoreConfigService` / prefs: `modo_servicentro`, `servicentro_columnas` (+ cache sync).
- [x] `syncStoreConfig` ya trae `select('*')` → flags nuevos en cache.
- [x] Sync dedicado de lista satélite: `fn_listar_servicentro_productos` → prefs.
- [x] Enganchar sync en `_syncStoreConfig` de `AutoSyncService`.
- [x] Prep offline hereda el sync vía `storeConfig` module.
- [x] Cargar lista en runtime desde red/cache.

### 3.2 Navegación

- [x] `NavigationHelper.homeRoute()` → `/servicentro` si modo activo.
- [x] Drawer: Combustibles; oculta mesas/catálogo en modo servicentro.
- [x] Sin config servicentro en Settings del TPV.
- [x] Ruta `/servicentro` + `ServicentroScreen` (grid placeholder).

**Dependencias:** Fase 1 (Fase 2 puede ir en paralelo, pero hace falta data real para probar).
**Entrega:** con modo activo, la app abre en pantalla servicentro (placeholder OK).

---

## Fase 4 · Vendedor — UI venta

> Grid → cantidad/monto → checkout de una línea → volver.

### 4.1 Grid de combustibles

- [x] Pantalla `ServicentroScreen`: grid con `servicentro_columnas`.
- [x] Cartas con color configurado, nombre, precio/L (o UM).
- [x] Orden según `orden` de la tienda.
- [x] Tap → pantalla de cantidad.

### 4.2 Litros ↔ dinero

- [x] Input dual: cantidad (litros) y monto ($).
- [x] Cambio en uno recalcula el otro con precio unitario del producto.
- [x] Validaciones: > 0, precisión según presentación fraccionable / redondeo de tienda.
- [x] Confirmar → una sola línea de venta.

### 4.3 Cobro y retorno

- [x] Reutilizar flujo de checkout existente (1 `OrderItem`).
- [x] Tras venta exitosa → navegar de vuelta al grid servicentro (limpiar estado).
- [x] Stock: camino normal de registro de venta (sin lógica nueva de tanque).

**Dependencias:** Fase 3.
**Entrega:** venta completa de un combustible extremo a extremo.

---

## Fase 5 · Hardening / offline / QA

- [x] Incluir flags servicentro en cache offline de `store_config` (verificado en sync real).
- [x] Lista satélite disponible offline tras sync; mensaje claro si modo ON y lista vacía/stale.
- [x] Producto quitado del catálogo o sin `es_combustible`: no romper el grid.
- [x] Exclusión tienda vs restaurante: **N/A** (modo por TPV; coexistencia permitida).
- [x] Prueba columnas 1–4 en móvil/tablet.
- [x] Verificar RLS: vendedor no escribe en `app_dat_servicentro_producto`; gerente sí.
- [x] (Opcional) guía corta `docs/TUTORIAL_PRUEBAS_SERVICENTRO.md`.

**Dependencias:** Fase 4.
**Entrega:** listo para uso real en una tienda piloto.

---

## Orden de trabajo sugerido (sesiones)

| # | Sesión | Criterio de “listo” |
|---|--------|---------------------|
| 1 | Fase 1 schema | SQL aplicado / migraciones en repo |
| 2 | Fase 2.1 + 2.2 | Flag producto + toggle modo con exclusión |
| 3 | Fase 2.3 | Lista orden/color/columnas en admin |
| 4 | Fase 3 | Vendedor detecta modo y abre `/servicentro` |
| 5 | Fase 4 | Venta litros↔$ + checkout + return |
| 6 | Fase 5 | QA / edge cases |

---

## Archivos clave a tocar (mapa)

| Área | Archivos / zonas |
|------|------------------|
| SQL | `funcionalidad_servicentro/*.sql`, `VentiQ.sql` (ref) |
| Admin config | `ventiq_admin_app/lib/services/store_config_service.dart`, `widgets/global_config_tab_view.dart` |
| Admin producto | modelos/pantallas de producto (`es_combustible`) |
| Admin lista | nueva pantalla/widget servicentro |
| Seller config | `ventiq_app/lib/services/store_config_service.dart`, prefs |
| Seller nav | `navigation_helper.dart`, `main.dart` routes, drawer/bottom nav |
| Seller UI | nuevas pantallas servicentro + cantidad dual |
| Checkout | `checkout_screen.dart` / `order_service.dart` (reuso) |

---

## Decisiones abiertas menores (no bloquean Fase 1–2)

Asumir por defecto; cambiar solo si el gerente lo pide en implementación:

| Tema | Default |
|------|---------|
| Default columnas | `2` |
| Rango columnas | `1–4` |
| Color default carta | color de marca / gris neutro si no se elige |
| UM | la presentación de venta del producto (idealmente litros + fraccionable) |
| Preview grid en admin | sí, simple |

---

## Log de progreso

| Fecha | Qué se cerró |
|-------|----------------|
| 2026-09-16 | Intent confirmado; plan creado. |
| 2026-09-16 | Fase 1: scripts `01_schema.sql` + `02_rpcs.sql` escritos. Aplicación en DB pendiente (MCP sin DDL write). |
| 2026-09-16 | Corrección: RLS + policies en `01_schema.sql`. Regla agente `.cursor/rules/supabase-rls-and-sync.mdc`. Plan actualizado con sync satélite. |
| 2026-09-16 | Fase 1 aplicada y verificada en Supabase (RLS + 4 policies + RPCs). |
| 2026-09-16 | Fase 2 admin: flag producto, modo excluyente, pantalla combustibles, drawer/ruta gerente. |
| 2026-09-16 | Fase 3 vendedor: home `/servicentro`, sync lista, drawer, cache flags. |
| 2026-09-16 | **Cambio:** modo/lista/columnas pasan a **por TPV**. Scripts `03_migracion_tpv.sql` + `04_rpcs_tpv.sql`. Apps actualizadas. Pendiente aplicar SQL. |
| 2026-09-16 | SQL TPV aplicado. Fase 4: `ServicentroCantidadScreen` (litros↔$), checkout 1 línea, retorno a `/servicentro`. |
| 2026-09-16 | Fase 5: cache por TPV, mensajes offline/stale, grid defensivo, tutorial pruebas. |
