# Runbook — pase newa → main (estado 2026-11-23, audit regla de oro)

Complementa `tasks/plan_promocion_main.md`. **No autoriza** aplicar en main:
hace falta OK explícito del dueño + G4 (snapshot) el día del pase.

## Regla de oro (Fase 1)

> No `DROP` / `REVOKE` de lo que usa el cliente publicado hoy. Solo crear.
> Los nombres antiguos que el parque llama **no** reciben rechazo nuevo ni
> cuerpo M01 completo. Eso va en `_m01` (cliente nuevo) o en Fase 3.

## Estado de preparación (Fase 0)

| Ítem | Estado | Dónde |
|---|---|---|
| Scripts `_m01` (14 + helpers) | Hecho; **aplicados en newa** | `sql_updates/promocion_m01/01…06` |
| Cliente `RpcM01` (TPV + Admin) | Hecho | `ventiq_*/lib/services/rpc_m01.dart` |
| Baselines md5 14/17/56 | Hecho | preflight de esos scripts |
| G2 helpers (sin RLS tabla) | Hecho en repo | `sql_updates/fn_config_tienda_helpers_aditivos.sql` |
| G2 `puede_leer` RH+trabajador | Hecho; **newa** (S01 ya existía) | `fn_config_tienda_puede_leer_g2.sql` |
| Espejo newa (antiguas = main) | Hecho | `promocion_m01/espejo_newa/` |
| G1 compatibilidad | Documentado | `g1_resultado_2026-11-23.md` |
| H9 trigger pago_directo | **newa**; main solo con R15 (Fase 3) | `fix_m01_venta_v1_pago_directo_tg_table.sql` |
| G4 snapshot main | Pendiente día del pase | `g4_respaldo_y_reversa.md` |
| Autorización main | Pendiente | — |

## Orden en main (Fase 1)

Horario de poca carga. Tras snapshot G4.

Leyenda: **[A]** aditivo · **[R]** same-name bugfix (números/reportes) · **[DATA]** filas · **[NO]** no aplicar

### A. Prerrequisitos aditivos

| # | Script | Tag | Hallazgo |
|---|---|---|---|
| A0 | `fn_config_tienda_helpers_aditivos.sql` | **[A]** | G2 sin RLS/REVOKE en tabla |
| A0b | `fn_operacion_turno_helpers_fase1.sql` | **[A]** | `en_turno` + `completada` **sin** parchear reportes |
| A1 | `m01_r0i_idempotencia_evidencia_propuesta.sql` | **[A]** | columnas idempotencia (requiere `postgres` + GUC approved) |
| A2 | `costos_adicionales_producto_tablas_fase1.sql` | **[A]** | preflight 06 |
| A3 | `add_ticket_caja_a_tickets_a_imprimir.sql` | **[DATA]** | C2 (antes de publicar TPV) |
| A4–A8 | scripts C9–C13 / C11 / turno sin cierre | **[R]** | **Diferir** mientras se prueba sin tocar lógica de hoy |
| A9 | Columnas M01 v1 (sin triggers `m01_*`) | **[A]** | solo si hace falta para `06` |

### B. Funciones `_m01`

1. `promocion_m01/01_helpers_alineacion.sql` — incluye `fn_caja_disponible_para_egreso` (**C14** helper)
2. `02_apertura_turno_m01.sql` — incluye **H1**
3. `03_cerrar_turno_m01.sql`
4. `04_egreso_m01.sql` — **C14** `EGRESO_SIN_SALDO` solo en `_v2_m01`
5. `05_venta_pago_estado_comanda_m01.sql`
6. `06_listar_ordenes_precio_m01.sql` — **H2** (`tipo_pago`)
7. Si 01–05 se aplicaron con `search_path=pg_catalog` solo:  
   `promocion_m01/fix_m01_search_path_public.sql`  
   (sin esto, completar orden en app nueva → `app_dat_estado_operacion does not exist`)

### C. Hallazgos aditivos post-`_m01`

| # | Script | Tag | Hallazgo |
|---|---|---|---|
| C1 | `fn_registrar_egreso_fondo_caja_v2_moneda.sql` | **[A]** | **C6** (llama `_v2_m01`) |
| C2 | `fn_reporte_ventas_producto_por_moneda.sql` | **[A]** | **C17a** |
| C3 | `fn_fdi_crear_liquidacion_depositar_inversion.sql` | **[A]** | **C17b** (11 params **sin** DEFAULT en `p_repartir_igual`; conserva la de 10) |

### D. Same-name con rechazo nuevo — solo con OK explícito

| Script | Riesgo | Nota |
|---|---|---|
| `fix_cambio_estado_operacion_mejorado_recepcion.sql` | `RECEPCION_INVENTARIO_USADO` | Protege inventario; Admin viejo no muestra el código. Preferible publicar Admin junto o diferir. |

### E. Clientes

Publicar TPV + Admin con `RpcM01`. Clientes viejos en nombres antiguos.
No encender `permitir_moneda_por_producto` hasta flota de esa tienda actualizada.

### F. Verificación inmediata

- Errores 4xx/5xx venta/turno/sync ≈ hora anterior.
- `fn_check_update` + venta + egreso + listar órdenes (cliente nuevo → `_m01`).
- Egreso con cliente **viejo** sigue sin `EGRESO_SIN_SALDO` (nombre antiguo intacto).

## NO aplicar en Fase 1 (viola regla de oro o es contrato)

| Script / bloque | Motivo |
|---|---|
| `configuracion_tienda_rls_propuesta.sql` **completo** (S01) | `ENABLE RLS` + `REVOKE ALL` en tabla en uso (`rls=false` hoy en main) |
| `fn_egreso_validar_saldo_caja.sql` | REPLACE del `_v2` publicado → Fase 3 (`…_fase3_nombre_antiguo.sql`) |
| `costos_adicionales_producto.sql` completo | DROP EXPRESSION + trigger + REPLACE `_v2` |
| `fix_apertura_turno_offline_id_turno.sql` | H1 same-name; preflight R33 aborta en main; H1 va en `02_*_m01` |
| `fix_listar_ordenes_tipo_pago.sql` | H2; main ya emite `tipo_pago` |
| R15/R16/R17 + H9 + trigger R12 sobre ventas | Triggers `m01_*` → Fase 3 |
| R0a–R0i `REVOKE` / policies endurecidas | Fase 3 |
| `newa_traer_*_main.sql`, `newa_contabilizacion_firmas.sql` | Solo newa / DROP firmas |
| `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql` | `DROP` firma FDI de 10 |
| `fondo_inversion_*` full DROP paths | Contrato |

## Hallazgos → dónde viven en el pase

| # | SQL en Fase 1 | Notas |
|---|---|---|
| H1 | `02_apertura_turno_m01` | No same-name en main |
| H2 | `06_listar_ordenes_precio_m01` | |
| H9 | **No** (con R15 en Fase 3) | |
| C2 | `add_ticket_caja_…` | |
| C6 | `fn_registrar_egreso_fondo_caja_v2_moneda` → `_m01` | |
| C9→C13 | A5–A8 en orden | |
| C11 | A8 | |
| C14 | `01` helper + `04` `_v2_m01` | Nombre antiguo en Fase 3 |
| C17 | C2 + C3 arriba | FDI sin DEFAULT 11º |
| G2 | A0 helpers | S01 RLS diferido |

## Diferencias G1 justificadas (no son regresiones)

| Caso | Diff | Motivo |
|---|---|---|
| Apertura reutiliza turno | `idempotent` true (main) vs false (`_m01`) | Evidencia M01 |
| Egreso v2 monto absurdo | main acepta; `_m01` → `EGRESO_SIN_SALDO` | C14 solo en `_m01` |
| listar_ordenes | `_m01` añade campos nativos | Superconjunto |
| Venta v4 con flag ON | ambas 42501 R17 | Esperado |

## Reversa

Fase 1 aditiva → `DROP` de `*_m01` y helpers nuevos; ver `g4_respaldo_y_reversa.md`.
Los **[R]** same-name de reportes sí modificaron cuerpos: restaurar desde el volcado G4 si hace falta.
