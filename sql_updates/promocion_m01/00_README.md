# Promoción M01 — scripts aditivos `_m01` (newa → main)

Generados 2026-11-23 desde los cuerpos **vigentes de newa** (`pg_get_functiondef`).
**No se han aplicado en main. No hay commit.**
Applied on newa 2026-11-23 (additive _m01 only; scripts 01-06; 14 `_m01` functions verified).
Plan: `tasks/plan_promocion_main.md`;
nombres: `docs/plan-multimoneda/promocion_fase0_nombres_m01.md`.

## Regla

- Los nombres antiguos (`fn_apertura_turno_offline`, `fn_registrar_venta_offline_v4`, …)
  **no se tocan**: siguen con el cuerpo de main.
- Las 14 funciones nuevas se crean con sufijo `_m01` (`CREATE OR REPLACE` solo sobre
  el nombre `_m01`, para poder repetir el script).
- Las `_m01` se llaman entre sí, nunca a la función antigua:
  `apertura: monedas_m01 → usd_m01 → apertura_m01`,
  `cierre: cerrar_monedas_m01 → cerrar_usd_m01 → cerrar_m01`.
- Todas: `SECURITY DEFINER`, mismo `search_path` y firmas que newa;
  `REVOKE ALL … FROM PUBLIC, anon`; `GRANT EXECUTE … TO authenticated, service_role`
  (excepción: `fn_turno_alinear_fecha_apertura`, interno, solo `service_role`).
- Cada script (02–06) empieza con un bloque `preflight` que **aborta** si falta una
  dependencia en el proyecto destino.

## Orden de aplicación en main

| # | Script | Crea |
|---|---|---|
| 1 | `01_helpers_alineacion.sql` | `fn_turno_alinear_fecha_apertura`, `fn_alinear_apertura_turno_offline`, `fn_caja_disponible_para_egreso` (nombres nuevos para main; no hay versión previa) |
| 2 | `02_apertura_turno_m01.sql` | `fn_apertura_turno_offline_m01`, `_usd_m01`, `_monedas_m01` (con H1: `id_turno` en la respuesta idempotente) |
| 3 | `03_cerrar_turno_m01.sql` | `fn_cerrar_turno_offline_m01`, `_usd_m01`, `_monedas_m01` |
| 4 | `04_egreso_m01.sql` | `fn_registrar_egreso_offline_m01`, `fn_registrar_egreso_offline_v2_m01` (C14 `EGRESO_SIN_SALDO`) |
| 5 | `05_venta_pago_estado_comanda_m01.sql` | `fn_registrar_venta_offline_v4_m01`, `fn_registrar_pago_venta_offline_m01`, `fn_registrar_cambio_estado_offline_m01`, `fn_cambiar_estado_comanda_item_offline_m01` |
| 6 | `06_listar_ordenes_precio_m01.sql` | `fn_listar_ordenes_m01`, `fn_actualizar_precio_promedio_recepcion_v2_m01` |

El 01 no tiene preflight (plpgsql no valida las llamadas al crear), pero sus
helpers solo funcionan con las dependencias de abajo.

## Prerrequisitos que main NO tiene hoy (comprobado solo-lectura el 2026-11-23)

Los preflight de 02–06 abortarán en main hasta que existan. Estos scripts **no** los crean:

| Falta en main | Lo exigen | Dónde está en el repo |
|---|---|---|
| `public.fn_config_tienda_puede_escribir(bigint)` | 01 (alinear), 02, 03, 04, 05 | `sql_updates/fn_config_tienda_helpers_aditivos.sql` (Fase 1; **no** S01 RLS) |
| `public.fn_operacion_completada(bigint)`, `public.fn_operacion_en_turno(bigint,bigint,timestamptz)` | 01 (caja disponible), 04 | `sql_updates/reportes_turno_completadas_y_por_moneda.sql` / `fix_reportes_turno_ventas_offline.sql` |
| Columnas `m01_solicitud`, `m01_id_tienda` en `app_dat_operacion_offline_idempotencia` | 02–05 | `docs/plan-multimoneda/m01_r0i_idempotencia_evidencia_propuesta.sql` |
| Columnas v1 en `app_dat_extraccion_productos` / `app_dat_operacion_venta` (`version_monetaria`, `snapshot_*`, …) | 06 (`listar_ordenes_m01`) | esquema multimoneda M01 |
| Tablas `app_dat_producto_costo`, `app_dat_recepcion_producto_costo` | 06 (`precio_promedio_v2_m01`) | `sql_updates/costos_adicionales_producto_tablas_fase1.sql` |

Sí existen en main: `fn_jsonb_monto`, `registrar_apertura_turno_v3`, `fn_cerrar_turno_tpv`,
`fn_esperado_turno_por_moneda`, `registrar_egreso_parcial_v2`, `fn_registrar_venta_v3`,
`fn_registrar_pago_venta(_v2)`, `fn_registrar_cambio_estado_operacion`,
`fn_cambiar_estado_comanda_item`, `app_dat_caja_turno_moneda`, columnas `*_usd` de `app_dat_caja_turno`.

Comprobar antes de aplicar (solo lectura): ejecutar los bloques `preflight` de cada
script en una transacción con `ROLLBACK`, o aplicar primero en el espejo (abajo).

## Notas de contenido

- **v2 de egreso no envuelve a la v1** en newa: llama a `registrar_egreso_parcial_v2`.
  `v2_m01` copia ese cuerpo (incluye `fn_caja_disponible_para_egreso` y `EGRESO_SIN_SALDO`).
  Observación: ese cuerpo no valida autorización del actor sobre la tienda (la v1 sí);
  se conserva tal cual por la regla «cuerpo newa». Revisar antes de publicar.
- `fn_registrar_venta_offline_v4`, `pago`, `cambio_estado`, `comanda_item` no llaman a otra
  función offline, por eso no hay cableado `_m01` interno en el script 05.
- En newa `venta_v4`, `pago` y `cambio_estado_offline` solo tienen EXECUTE para `authenticated`;
  las `_m01` añaden `service_role` por indicación del pase.
- `fn_listar_ordenes` en newa tiene EXECUTE para PUBLIC/anon; `fn_listar_ordenes_m01` no
  (se llama con sesión autenticada, `check_user_has_access_to_any_tienda`).
- `fn_registrar_cambio_estado_operacion` y demás funciones de negocio llamadas **conservan su
  nombre**; si G3 requiere versiones `_m01` de ellas, no entran en este lote.
- G2 (`fn_obtener_licencia_firmada`, `fn_moneda_consolidacion`, `sync_bundle`) **no** forma
  parte de estos scripts.

## Espejo en newa (prueba)

Regla del plan: en newa los nombres antiguos pasan a tener el cuerpo de main y las `_m01`
el cuerpo nuevo.

**Espejo aplicado en newa el 2026-11-23** (migraciones `espejo_newa_nombres_antiguos_desde_main_1…4`,
solo newa; main solo se leyó). Las 14 funciones de nombre antiguo tienen `md5(prosrc)` igual a
main; las 14 `_m01` y los helpers no se tocaron (sus md5 difieren de los nombres antiguos).
Archivos: `espejo_newa/baseline_main_md5.txt` (name + md5 de main) y
`espejo_newa/restore_nombres_antiguos_desde_main.sql` (14 definiciones de main; los bloques
`DO` escriben el cuerpo en CRLF salvo `fn_cambiar_estado_comanda_item_offline`, que es LF, para
que el md5 coincida). `CREATE OR REPLACE` conservó los GRANT de newa (12 de las 14 sin
PUBLIC/anon; `fn_listar_ordenes` y `fn_actualizar_precio_promedio_recepcion_v2` ya tenían
PUBLIC/anon); no se concedió nada nuevo. Las ACL de main no se replican aquí.

Para probar solo la creación aditiva:

1. Con el MCP de **newa** (nunca main), aplicar 01 → 06 en ese orden. Los `CREATE OR REPLACE`
   de 01 coinciden con lo que ya hay en newa (idempotente); las `_m01` son nuevas.
2. Verificar existencia y que no hay llamadas cruzadas a nombres antiguos:
   ```sql
   select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and proname like '%\_m01' order by 1;   -- 14 filas
   select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and proname like '%\_m01'
     and pg_get_functiondef(p.oid) ~ 'public\.fn_(apertura|cerrar)_turno_offline(_usd|_monedas)?\(';  -- 0 filas
   ```
3. Smoke test: abrir/cerrar un turno de prueba con `fn_apertura_turno_offline_monedas_m01` y
   `fn_cerrar_turno_offline_monedas_m01`, repetir con el mismo `client_uuid` (debe devolver
   `idempotent: true` con `id_turno`).
4. Contrato local: desde `ventiq_admin_app`,
   `flutter test --no-pub test/promocion_m01_sql_contract_test.dart`
   (inspecciona los archivos; no sustituye la ejecución en PostgreSQL).

## Cliente

Llamar `_m01` primero y caer al nombre antiguo solo si la función no existe
(`RpcM01` en TPV/Admin; `promocion_fase0_nombres_m01.md`, paso 7 — hecho 2026-11-23).

## Puertas G1 / G2 / G4 / H9

| Archivo | Uso |
|---|---|
| `g1_arnes_compatibilidad.sql` / `g1_resultado_2026-11-23.md` | Resultados G1 en espejo |
| `../fn_config_tienda_helpers_aditivos.sql` | G2 helpers **sin** RLS tabla (Fase 1 main) |
| `../fn_config_tienda_puede_leer_g2.sql` | G2 REPLACE si S01 ya existía (newa) |
| `../fix_m01_venta_v1_pago_directo_tg_table.sql` | **H9** (newa; main con R15 → Fase 3) |
| `../fn_egreso_validar_saldo_caja.sql` | **No** Fase 1 main (C14 en `04_*_m01`) |
| `g4_respaldo_y_reversa.md` | Snapshot el día del pase |
| `../../docs/plan-multimoneda/runbook_pase_newa_main.md` | **Orden completo + exclusiones regla de oro** |
