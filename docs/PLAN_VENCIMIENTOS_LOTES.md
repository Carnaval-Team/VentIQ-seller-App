# Plan: Vencimientos y lotes de inventario

Checklist operativo para implementar caducidad de punta a punta.
Basado en estudio schema **supabase-main** + código admin/TPV (2026-03).

**Veredicto de partida:** solo existen flags de producto (`es_por_lotes`, `dias_alert_caducidad`). No hay stock fechado. Sin P0 el resto no sirve.

### Regla de despliegue (obligatoria)

- **Todo el desarrollo y las pruebas van en Supabase `newa`.**
- **No aplicar nada en `main` hasta completar el proyecto completo** (fases 0–7 cerradas y validadas en newa).
- Al final: un solo pase a main (scripts SQL + apps) con checklist de smoke previo.

**Fuera de alcance / no confundir**
- [ ] ~~Lotes de cocina / `modo_elaboracion = por_tanda`~~ → dominio distinto
- [ ] Vencimiento de suscripciones, licencias, notificaciones, pre-asignaciones
- [ ] FEFO de CxC / KDS

---

## Estado global

| Fase | Nombre | Estado |
|------|--------|--------|
| 0 | Modelo de datos + RLS | ✅ Verificado newa |
| 1 | Captura en recepción (y ajuste+) | ✅ Verificado newa |
| 2 | Lectura de stock por lote / UI almacén | ✅ Verificado newa |
| 3 | Alertas “por vencer / vencido” | ✅ Verificado newa |
| 4 | FEFO en extracción / venta | ✅ Verificado newa |
| 5 | Reportes y export | ✅ Verificado (UI) |
| 6 | TPV + sync offline (si aplica) | ✅ Flags online (offline lote fuera de alcance) |
| 7 | Import Excel / bulk + pulido | ✅ Verificado newa |

### Scripts en newa — aplicados y verificados

1. ~~`01_lotes_vencimiento_schema.sql`~~ ✅  
2. ~~`02_lotes_recepcion_rpc.sql`~~ ✅  
3. ~~`03_lotes_fases_2_3_ajuste.sql`~~ ✅  
4. ~~`04_lotes_fefo_egresos.sql`~~ ✅  
5. ~~`05_lotes_bulk_import.sql`~~ ✅  

**Siguiente:** pase único a **main** (misma lista, mismo orden).

Leyenda: 🔲 pendiente · 🟡 en curso · ✅ hecho · ⏸️ bloqueado

---

## Decisiones de diseño (cerrar antes / durante P0)

- [x] **D0.** Modelo elegido: tabla `app_dat_lote` + `id_lote` en recepción/inventario/extracción
- [x] **D1.** `es_por_lotes = true` → **obligatorio** lote + fecha en recepción (Fase 1)
- [x] **D2.** Unicidad: `(id_tienda, id_producto, lower(codigo))`
- [x] **D3.** Stock: saldo por lote desde ledger (`app_dat_inventario_productos.id_lote`)
- [x] **D4.** Productos sin flag: `id_lote` null (como hoy)
- [x] **D5.** Transferencias: el lote viaja intacto origen→destino (Fase 4)
- [x] **D6.** Política venta vencida: avisar primero; bloquear después si se pide
- [x] **D7.** Offline TPV: online primero (P6 después)

*(Defaults adoptados 2026-03-21; cambiar aquí si el negocio decide otra cosa.)*

---

## Fase 0 — Modelo de datos + RLS

> Objetivo: poder persistir un lote con fecha de vencimiento y enlazarlo al movimiento de inventario.

### 0.1 Schema

- [x] Crear `public.app_dat_lote`
  - [x] `id` bigserial PK
  - [x] `id_tienda` bigint NOT NULL → `app_dat_tienda`
  - [x] `id_producto` bigint NOT NULL → `app_dat_producto`
  - [x] `codigo` text NOT NULL (nro de lote del proveedor / interno)
  - [x] `fecha_vencimiento` date NOT NULL
  - [x] `fecha_fabricacion` date NULL
  - [x] `observaciones` text NULL
  - [x] `created_at` timestamptz NOT NULL DEFAULT now()
  - [x] `created_by` uuid NULL
  - [x] UNIQUE `(id_tienda, id_producto, lower(codigo))`
  - [x] CHECK `fecha_fabricacion IS NULL OR fecha_fabricacion <= fecha_vencimiento`
- [x] `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` (+ policies) **en el mismo script**
- [x] Policies: SELECT acceso tienda; INSERT/UPDATE gerente/supervisor/almacenero; sin `USING (true)`
- [x] Índices: `(id_producto)`, `(fecha_vencimiento)`, `(id_tienda, fecha_vencimiento)`

### 0.2 Enlaces en tablas existentes

- [x] `app_dat_recepcion_productos.id_lote` bigint NULL → `app_dat_lote`
- [x] `app_dat_inventario_productos.id_lote` bigint NULL → `app_dat_lote`
- [x] `app_dat_extraccion_productos.id_lote` bigint NULL → `app_dat_lote`
- [ ] (Opcional P0) `app_dat_control_productos.id_lote` si ajustes+ deben fechar stock
- [x] Índices en las 3 FKs

### 0.3 Helpers / contratos

- [x] RPC `fn_obtener_o_crear_lote(...)` idempotente
- [ ] Extender helpers de ingreso/egreso con `p_id_lote` opcional **o** post-update del snapshot (Fase 1 al cablear recepción)
- [x] Documentar: productos legacy sin `id_lote` siguen válidos (saldo agregado) — ver comentarios SQL

### 0.4 Entregables

- [x] Script SQL: `ventiq_admin_app/lib/sql/01_lotes_vencimiento_schema.sql`
- [x] Aplicar **solo en newa** (main al cierre del proyecto)
- [ ] Smoke en newa: llamar `fn_obtener_o_crear_lote` con un producto de prueba

**Archivos previstos**
- `ventiq_admin_app/lib/sql/01_lotes_vencimiento_schema.sql`
- (opcional) patch helpers en `presentaciones_inventario/`

---

## Fase 1 — Captura en recepción (y ajuste+)

> Objetivo: si el producto es por lotes, al recibir se guarda código + fecha y nace el enlace en inventario.

### 1.1 Admin UI — recepción

- [x] En selector/línea de producto: si `es_por_lotes`, mostrar campos **Código de lote** y **Fecha de vencimiento** (`product_quantity_dialog.dart`)
- [x] Validación: obligatorios en diálogo + submit recepción
- [x] Payload incluye `codigo_lote` + `fecha_vencimiento`
- [x] Lista de productos muestra lote/vence; merge no junta lotes distintos

### 1.2 RPC recepción

- [x] RPC viva: `fn_registrar_recepcion_con_inventario` (+ `fn_contabilizar_linea_recepcion_inventario`)
- [x] Script listo: `ventiq_admin_app/lib/sql/02_lotes_recepcion_rpc.sql`
- [x] **Aplicar 02 en newa**
- [x] Por línea: si `es_por_lotes` → `fn_obtener_o_crear_lote` → `id_lote` en recepción
- [x] Al completar: ledger copia `id_lote` y saldo particionado por lote
- [x] Smoke manual en newa (usuario confirmó que guarda la información)

### 1.3 Ajuste positivo / entrada manual

- [x] Misma regla cuando se suma stock a producto por lotes (`fn_insertar_ajuste_inventario2` + UI)
- [x] Ajuste negativo: FEFO automático si no mandan lote (recomendado)
- [ ] **Aplicar `03` en newa** y smoke ajuste+ con lote

### 1.4 Entregables

- [x] UI recepción + RPC aplicados en newa
- [x] Checklist: recepción producto con flag → inventario con `id_lote` no null

**Archivos**
- `ventiq_admin_app/lib/widgets/product_quantity_dialog.dart`
- `ventiq_admin_app/lib/screens/inventory_reception_screen.dart`
- `ventiq_admin_app/lib/sql/02_lotes_recepcion_rpc.sql`

---

## Fase 2 — Lectura de stock por lote / UI

> Objetivo: ver en almacén/stock qué cantidad hay por lote y cuándo vence.

### 2.1 Lecturas

- [x] RPC `fn_stock_lotes_en_ubicacion` (código, fecha_vencimiento, cantidad, estado)
- [x] Saldo = último snapshot por `(producto, ubicación, presentación, id_lote)`
- [x] Productos sin lotes: una sola fila como hoy

### 2.2 UI

- [x] Quitar hardcode `lote: null` / `fecha_vencimiento: null` en `warehouse_service.dart`
- [x] Chips reales en `warehouse_detail_screen.dart` (color por `estado_caducidad`)
- [ ] En `inventory_stock_screen` (detalle): expander o subtítulo “Lote X · vence DD/MM” (opcional; almacén ya muestra)
- [x] Badge visual: verde / ámbar / rojo vía `estado_caducidad`

### 2.3 Entregables

- [ ] Smoke UI tras aplicar `03` en newa

---

## Fase 3 — Alertas “por vencer / vencido”

> Objetivo: usar por fin `dias_alert_caducidad` contra fechas reales.

### 3.1 Motor

- [x] Extender `fn_analytics_stock_alerts` con tipos:
  - [x] `expiring` — dentro de `dias_alert_caducidad` (fallback 30d)
  - [x] `expired` — `fecha_vencimiento < today` y cantidad > 0
- [x] Solo filas con `id_lote` y saldo > 0

### 3.2 UI / notificaciones

- [x] Labels “Por Vencer” / “Vencido” + icono expired
- [ ] (Opcional) notificación push/in-app con `fecha_expiracion` de la notificación

### 3.3 Entregables

- [ ] Smoke alertas tras aplicar `03` en newa

---

## Fase 4 — FEFO en extracción / venta

> Objetivo: al salir stock, preferir el lote que vence antes.

### 4.1 Extracción admin

- [x] `fn_crear_extraccion_con_movimiento`: FEFO o `id_lote` explícito en JSON
- [x] Escribe `id_lote` en `app_dat_extraccion_productos` + ledger

### 4.2 Venta TPV (online)

- [x] `fn_descontar_venta_enrutada`: FEFO automático si `es_por_lotes`
- [ ] (D6) Warning UI si lote vencido (servidor ya descuenta FEFO; aviso TPV opcional)

### 4.3 Transferencias

- [x] Helper `fn_transfer_asignar_lote_fefo` (callers pueden setear `id_lote`)
- [ ] Cablear helper dentro de `fn_transferir_inventario_entre_layouts` (opcional follow-up)

### 4.4 Entregables

- [ ] Smoke FEFO tras aplicar `04` en newa

---

## Fase 5 — Reportes y export

- [x] Export inventario simple: columnas Lote / Fecha Vencimiento si vienen en filas
- [x] Filtro operativo vía alertas `expiring` / `expired` (Fase 3)
- [ ] Kardex: mostrar lote en movimientos cuando exista `id_lote` (follow-up)

---

## Fase 6 — TPV + sync offline

> Solo si D7 lo requiere para el negocio. **Online primero (D7).**

- [x] Dejar de hardcodear `esPorLotes: false` donde el mapa trae `es_por_lotes`
- [ ] Sync satélite de lotes/saldos por lote si FEFO offline (fuera de alcance D7)
- [ ] Prep offline: qué pasa si modo lotes ON y cache vacío
- [ ] Warning en TPV offline si no hay datos de lote

---

## Fase 7 — Import / pulido

- [x] `bulk_import_productos_excel`: persistir `es_por_lotes` y `dias_alert_caducidad` (`05`)
- [ ] (Opcional) import de recepción con columnas lote / fecha
- [x] AI product gen ya mapea `es_por_lotes`
- [x] Plan actualizado con scripts y checklist
- [ ] **Aplicar `05` en newa**

---

## Criterios de “hecho” por fase

| Fase | Done when |
|------|-----------|
| 0 | Tabla + FKs + RLS en DB; lote creable por SQL |
| 1 | Recepción con flag guarda `id_lote` en recepción e inventario |
| 2 | Admin ve lote/vence con cantidad real (no null) |
| 3 | Alerta `expiring`/`expired` con datos reales |
| 4 | Extracción/venta descuenta el lote FEFO |
| 5 | Export/filtro muestran vencimientos |
| 6 | TPV offline/online coherente (si aplica) |
| 7 | Import y docs cerrados |

---

## Orden de trabajo inmediato (sprint 1)

1. [x] **D0–D7** adoptados (defaults)
2. [x] **0.1 + 0.2** script schema + RLS
3. [x] **0.3** `fn_obtener_o_crear_lote`
4. [x] Aplicar `01_lotes_vencimiento_schema.sql` **en newa** (verificado: tabla, RLS×3, FKs, fn)
5. [x] Smoke recepción + lote en newa (02 aplicado, datos guardados)
6. [x] Código fases 1.3–7 listo (scripts `03`/`04`/`05` + Dart)
7. [x] Aplicar `03`→`04`→`05` en **newa** y verificación (usuario + MCP)
8. [ ] _(Al cerrar)_ pase único a **main**

### Cierre → main

- [x] Todas las fases 0–7 ✅ en newa
- [x] Verificación newa (RPCs + import/flags; smoke operativo confirmado por usuario)
- [x] Lista de scripts SQL a aplicar en main (orden):

  1. `ventiq_admin_app/lib/sql/01_lotes_vencimiento_schema.sql`
  2. `ventiq_admin_app/lib/sql/02_lotes_recepcion_rpc.sql`
  3. `ventiq_admin_app/lib/sql/03_lotes_fases_2_3_ajuste.sql`
  4. `ventiq_admin_app/lib/sql/04_lotes_fefo_egresos.sql`
  5. `ventiq_admin_app/lib/sql/05_lotes_bulk_import.sql`

- [ ] Aplicar SQL en **main** (SQL Editor; MCP main también read-only DDL)
- [ ] Smoke rápido en main (recepción con lote → stock → alerta)
- [ ] Release apps admin + TPV con el Dart de lotes

---

## Notas de implementación (reglas del repo)

- Toda tabla nueva: `ENABLE ROW LEVEL SECURITY` + policies en el **mismo** script.
- Datos que el TPV necesite offline → pipeline de sync (`StoreConfig` / satélite / productos), no solo Supabase.
- No mezclar con tandas de cocina.
- Preferir columnas nullable + flag `es_por_lotes` para no romper el 99% de productos actuales (~2 con flag hoy en main).

---

## Registro de progreso

| Fecha | Qué | Quién / nota |
|-------|-----|--------------|
| 2026-03-21 | Plan creado; estudio schema main | — |
| 2026-03-21 | Script Fase 0 listo (`01_lotes_vencimiento_schema.sql`) | — |
| 2026-03-21 | Regla: no tocar main hasta proyecto completo | Solo newa durante el desarrollo |
| 2026-03-21 | Schema Fase 0 aplicado y verificado en **newa** | tabla + RLS + id_lote + fn |
| 2026-03-21 | Fase 1 UI + script RPC recepción | Aplicar `02_lotes_recepcion_rpc.sql` en newa |
| 2026-03-21 | Fix UI: diálogo no pedía lote | `es_por_lotes` no venía del selector; se lee de BD al abrir |
| 2026-03-21 | 02 aplicado en newa + smoke OK | Recepción guarda lote/vence en recepción e inventario |
| 2026-03-21 | Fases 1.3–7 código + SQL listos | Scripts `03`/`04`/`05`; Dart admin/TPV; MCP DDL read-only → aplicar en SQL Editor newa |
| 2026-03-22 | newa 01–05 verificados | Usuario confirmó; MCP: ajuste+lote, FEFO, stock lotes, bulk flags OK. Pendiente: pase a main |
