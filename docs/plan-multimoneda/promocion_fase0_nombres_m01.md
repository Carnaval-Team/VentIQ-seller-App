# Fase 0 — Nombres `_m01` para la expansión en main

Borrador de trabajo 2026-11-23. Complementa `tasks/plan_promocion_main.md` §3–4.
No aplica SQL en main. Objetivo: dejar scripts aditivos que crean `*_m01` con el
cuerpo de newa y conservan el nombre antiguo con el cuerpo de main.

## Ya cerrado en prep (2026-11-23)

| Ítem | Resultado |
|---|---|
| Baselines md5 (14)/(17)/(56) | (14) venta main `1833dad1…`; (17) hashes main; (56) exige post-(14)/(17) |
| H1 datos main | 0 huérfanos en `app_dat_caja_turno_moneda` |
| G3 llamadores | Ver abajo |
| G2 `puede_leer` | **Cerrado 2026-11-23:** RH + trabajador; newa aplicado (`fn_config_tienda_puede_leer_g2.sql`); S01 parcheado; simulación main = 0 fuera |

## Mapa de las 14 (nombre nuevo)

| Antigua (queda = cuerpo main) | Nueva (cuerpo newa vigente) |
|---|---|
| `fn_apertura_turno_offline` | `fn_apertura_turno_offline_m01` |
| `fn_apertura_turno_offline_usd` | `fn_apertura_turno_offline_usd_m01` |
| `fn_apertura_turno_offline_monedas` | `fn_apertura_turno_offline_monedas_m01` |
| `fn_cerrar_turno_offline` | `fn_cerrar_turno_offline_m01` |
| `fn_cerrar_turno_offline_usd` | `fn_cerrar_turno_offline_usd_m01` |
| `fn_cerrar_turno_offline_monedas` | `fn_cerrar_turno_offline_monedas_m01` |
| `fn_cambiar_estado_comanda_item_offline` | `fn_cambiar_estado_comanda_item_offline_m01` |
| `fn_registrar_cambio_estado_offline` | `fn_registrar_cambio_estado_offline_m01` |
| `fn_registrar_egreso_offline` | `fn_registrar_egreso_offline_m01` |
| `fn_registrar_egreso_offline_v2` | `fn_registrar_egreso_offline_v2_m01` |
| `fn_registrar_pago_venta_offline` | `fn_registrar_pago_venta_offline_m01` |
| `fn_registrar_venta_offline_v4` | `fn_registrar_venta_offline_v4_m01` |
| `fn_listar_ordenes` | `fn_listar_ordenes_m01` |
| `fn_actualizar_precio_promedio_recepcion_v2` | `fn_actualizar_precio_promedio_recepcion_v2_m01` |

## Cableado interno (G3) — las `_m01` deben llamarse entre sí

```
monedas_m01 → usd_m01 → apertura_m01
monedas_m01 → apertura_m01          (si aplica tras H1)
cerrar_monedas_m01 → cerrar_usd_m01 → cerrar_m01
egreso_v2_m01 → (efecto; en main hoy v2 envuelve la v1)
fondo_caja_v2 (newa) → egreso_v2_m01
precio_promedio_v2_m01 ← FDI newa (solo si esas RPC van en la misma fase)
```

Helpers aditivos (no renombrar; main aún no los tiene):

- `fn_turno_alinear_fecha_apertura`
- `fn_alinear_apertura_turno_offline`
- `fn_caja_disponible_para_egreso` (C14; newa 2026-11-23)
- Tras la cadena de apertura: `fix_apertura_turno_offline_id_turno.sql` (H1) aplicado sobre el cuerpo `_m01`

## Huellas newa de la cadena apertura (2026-11-23)

| Función | md5(prosrc) | def_len |
|---|---|---|
| `fn_apertura_turno_offline` | `783930116807ee39b78d747a0d97d6a4` | 7427 |
| `fn_apertura_turno_offline_usd` | `d5e15933c2cdc3c9138e717844467d6c` | 1486 |
| `fn_apertura_turno_offline_monedas` | `0c4704a4b11581a4f1e6cea3a3de8531` | 2623 |
| `fn_turno_alinear_fecha_apertura` | `1883e20c53394e386dddee96dd6cdc4a` | 2002 |
| `fn_alinear_apertura_turno_offline` | `523fc409dbee3827926c5d624aeaf6d5` | 1850 |

## Scripts generados (2026-11-23)

Carpeta: `sql_updates/promocion_m01/` (léase primero `00_README.md`). No aplicados en main.

| Script | Contenido |
|---|---|
| `01_helpers_alineacion.sql` | helpers de alineación + `fn_caja_disponible_para_egreso` |
| `02_apertura_turno_m01.sql` | cadena apertura `_m01` (con H1) |
| `03_cerrar_turno_m01.sql` | cadena cierre `_m01` |
| `04_egreso_m01.sql` | egreso v1/v2 `_m01` (C14) |
| `05_venta_pago_estado_comanda_m01.sql` | venta v4, pago, cambio de estado, comanda |
| `06_listar_ordenes_precio_m01.sql` | `fn_listar_ordenes_m01`, precio promedio v2 |

Contrato local: `ventiq_admin_app/test/promocion_m01_sql_contract_test.dart`.
Hallazgo: main aún no tiene `fn_config_tienda_puede_escribir`, `fn_operacion_completada`,
`fn_operacion_en_turno`, columnas `m01_solicitud`/`m01_id_tienda`, columnas v1 de
extracción/venta ni las tablas de costos adicionales; los preflight de 02–06 abortan hasta
que esos scripts previos estén aplicados (ver README).

## Orden de generación de scripts (siguiente trabajo)

1. Helpers de alineación (aditivos, mismos nombres).
2. Cadena apertura `_m01` (base → usd → monedas), cuerpos newa con calls internas `_m01`.
3. Cadena cierre `_m01`.
4. Egreso `_m01` + C14 (`fn_caja_disponible_para_egreso` + saldo en v2_m01).
5. Venta / pago / estado / comanda / listar_ordenes / precio_promedio `_m01`.
6. Espejo en newa: nombres antiguos = cuerpo main; `_m01` = cuerpo nuevo (regla del plan).
   **Hecho 2026-11-23**: las 14 funciones antiguas restauradas desde main en newa
   (`md5(prosrc)` idéntico a main; ver `sql_updates/promocion_m01/espejo_newa/`); las `_m01`
   quedan con el cuerpo de newa/M01 y distinto md5. Main no se modificó.
7. ~~Cliente: llamar `_m01` primero, caer solo si la función no existe.~~ **Hecho en el cliente (2026-11-23)**:
   helper `RpcM01` (`ventiq_app/lib/services/rpc_m01.dart` y copia idéntica en
   `ventiq_admin_app/lib/services/rpc_m01.dart`). Prueba `<base>_m01` y cae al nombre
   antiguo solo con PGRST202 / schema cache / «does not exist»; 42501 y demás errores
   se relanzan sin caer.
   - TPV: `auto_sync_service` (alinear apertura, cierre online/offline cola, `_rpcTurnoOfflineMonedas`
     apertura/cierre monedas → respaldo, egreso v2/v1, venta v4, pago offline, cambio de estado),
     `turno_service` (apertura/cierre monedas), `order_service` (`fn_listar_ordenes` ×2,
     `fn_registrar_cambio_estado_offline`), `egreso_screen` (egreso v2/v1),
     `comanda_service` y `cocina_offline_queue` (`fn_cambiar_estado_comanda_item_offline`).
   - Admin: `inventory_service` (`fn_actualizar_precio_promedio_recepcion_v2`).
   - Las cadenas de respaldo (monedas → usd → v3, v4 → v3) no cambian: `_m01` es solo el primer intento.
   - Admin no llama `fn_listar_ordenes` (usa `listar_ordenes`, otra función): sin cambio.
   - Pruebas: `ventiq_app/test/rpc_m01_test.dart`. Los tests de contrato con MockClient usan
     `rpc_m01_mock_helper.dart` (responde PGRST202 a `*_m01`) para seguir fijando la cadena antigua.

## G2 (cerrado)

`puede_leer` incluye RH y trabajador. Con eso, licencia / consolidación / `sync_bundle` pueden ir con el mismo nombre tras S01+G2 en el pase.
