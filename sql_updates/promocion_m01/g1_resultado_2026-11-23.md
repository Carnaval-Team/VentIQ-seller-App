# G1 — resultado parcial (newa espejo, 2026-11-23)

Estado del espejo: nombres antiguos = `md5` de main; `*_m01` = cuerpos newa/M01.

## Presencia

- 14 funciones `*_m01` presentes.
- `fn_apertura_turno_offline` md5 `8c7ddcbf…` ≠ `fn_apertura_turno_offline_m01` md5 `1c4891f2…`.

## Fixtures (tienda 8)

| | |
|---|---|
| TPV | 6 |
| Vendedor | 3 |
| uuid | `5e9ccb3f-8f9a-4e53-8b19-736ec40d4593` |

Auth: `set_config('request.jwt.claims', …)` + `ROLLBACK` al terminar.

## Caso apertura (claves distintas)

| | Antigua (cuerpo main) | `_m01` |
|---|---|---|
| Resultado | success, reutiliza turno 30 | success, reutiliza turno 30 |
| `idempotent` | `true` | `false` |
| Error | — | — |

**Diferencia justificada:** con turno ya abierto, main marca reutilización como idempotente; M01 registra evidencia nueva (`m01_solicitud` / tienda) y responde `idempotent: false` aunque reutiliza el mismo `id_turno`. Mismo efecto de negocio (no abre segundo turno).

**No justificado / a evitar en el arnés:** usar la **misma** `client_uuid` en antigua y `_m01` — la clave queda retenida o choca (42501 en `_m01`).

## Caso egreso_v2 (monto 999999999 CUP, claves distintas, ROLLBACK)

| | Antigua (cuerpo main, sin C14) | `_m01` (con C14) |
|---|---|---|
| Resultado | `success: true` (registraría el egreso) | `success: false` |
| `error_code` | — | `EGRESO_SIN_SALDO` |

**Diferencia justificada (C14):** main hoy no valida saldo en la RPC; `_m01` sí. El cliente nuevo depende de ese rechazo. No es regresión para clientes viejos (siguen en el nombre antiguo).

## Espejo md5

Las 14 parejas antigua/`_m01` tienen `md5(prosrc)` distintos (verificado 2026-11-23).

## Método de los casos siguientes (2026-11-23, segunda tanda)

- Solo newa (MCP `project-0-VentIQ-seller-App-supabase-newa`). Nada contra main.
- Cada caso corre en un bloque `DO` que fija `request.jwt.claims` (uuid de fixture), llama a la antigua y a la `_m01` **en transacciones separadas** (el cierre de una dejaría sin turno abierto a la otra) con `client_uuid` distintos, y termina con `RAISE EXCEPTION` con el resultado → todo se revierte. Para casos que necesitan encadenar (venta → pago → estado) se hace dentro de una misma transacción por versión.
- Tras la tanda se verificó que no quedó nada: turno 30 sigue `estado=1`, `max(app_dat_operaciones.id)=209` (las ops de prueba 221–226 no existen), `permitir_moneda_por_producto` de la tienda 8 sigue `true`, `fn_m01_venta_v1_pago_directo` sigue sin parchear, 0 filas nuevas en `app_dat_operacion_offline_idempotencia`.

## Caso cierre (turno 30 abierto, TPV 6, efectivo real 0)

| Variante | Antigua (cuerpo main) | `_m01` |
|---|---|---|
| `fn_cerrar_turno_offline` | `{"status":"success","idempotent":false}`, turno 30 → `estado=2` | `{"status":"success","idempotent":false}`, turno 30 → `estado=2` |
| `fn_cerrar_turno_offline_monedas` (`{"CUP":0,"USD":0}`) | `success`, `idempotent:false`; 2 filas en `app_dat_caja_turno_moneda`; turno 30 → `estado=2` | idéntico |
| Replay misma clave (monedas) | `success`, `idempotent:true`, «Cierre ya procesado» | idéntico |

**Resultado: PASA, sin diferencias.** Todo con `ROLLBACK`; el turno 30 siguió abierto después. No se probó `_usd` por separado (la ejercitan `_monedas` y su `_m01`, que llama a `_usd_m01` → base `_m01`).

## Caso venta_offline_v4 (tienda 8, TPV 6, producto 16 Diesel, 1 u × 2375, turno 30 abierto)

**Hallazgo previo (afecta a ambas por igual):** con la tienda 8 tal cual está (`permitir_moneda_por_producto = true`), **las dos** responden igual:

| | Antigua | `_m01` |
|---|---|---|
| Venta legacy sin contrato de moneda | `status:error`, «Una venta nueva no puede omitir el contrato de moneda», `sqlstate 42501` | idéntico |

Es el trigger `m01_venta_legacy_con_flag` (M01 R17): con el flag ON una venta legacy se rechaza. Es el comportamiento esperado de la expansión, no una regresión de `_m01`. Los clientes viejos (nombre antiguo) contra una tienda con flag ON quedan bloqueados en newa; por eso el pase a main debe dejar el flag en `false` hasta publicar los clientes.

Para comparar el resto se apagó el flag **solo dentro de la transacción** (`set_config('app.m01_politica_flag_autorizada','yes',true)` + `UPDATE …=false`), con `ROLLBACK`:

| | Antigua | `_m01` |
|---|---|---|
| Venta sin pagos | `success`, `id_operacion`, `total_venta 2375`, `idempotent:false`, `client_uuid` | idéntico (ids distintos, otra transacción) |
| Replay misma clave y misma solicitud | `success`, `idempotent:true`, `id_operacion` igual; mensaje con **mojibake** («OperaciÃ³n») y **sin** `client_uuid` | `success`, `idempotent:true`, `id_operacion` igual; mensaje correcto («Operación») y **con** `client_uuid` |
| Venta con `p_pagos` CUP 2375 (con trigger corregido, ver abajo) | `success`, `pagos_registrados:true`; `es_pagada=true` | idéntico |

**Diferencias justificadas:** en el replay `_m01` devuelve `client_uuid` y el texto bien codificado (cuerpo newa; contrato más completo; los clientes solo leen `status`/`idempotent`/`id_operacion`).

## Caso pago_venta_offline

Operación de prueba: la venta creada dentro de la misma transacción (no se toca ninguna operación real).

**Con el estado actual de newa, FALLA en las dos por igual (defecto previo, no de `_m01`):**

| | Antigua | `_m01` |
|---|---|---|
| `fn_registrar_pago_venta_offline*` CUP 2375 sobre una venta legacy | excepción `42703` «record "new" has no field "version_monetaria"» | idéntico |
| Venta v4 con `p_pagos` | **No probado** con el trigger sin parchear (se infiere el mismo fallo: llama a `fn_registrar_pago_venta_v2`, mismo INSERT) | (ídem) |

Causa: `fn_m01_venta_v1_pago_directo()` es el trigger de `app_dat_pago_venta` **y** de `app_dat_operacion_venta`; en la tabla de pagos evalúa `TG_TABLE_NAME = 'operacion_venta' AND NEW.version_monetaria = …` y plpgsql no cortocircuita el acceso al campo `NEW.version_monetaria` (que no existe en `app_dat_pago_venta`). **Cualquier INSERT directo en `app_dat_pago_venta` fuera de `app.m01_venta_v1_interna='yes'` falla**: `fn_registrar_pago_venta`, `fn_registrar_pago_venta_v2` (los usan los RPC legacy y los antiguos del TPV) y por tanto el pago de las ventas legacy. Anotado como **H9** en `tasks/hallazgos_pruebas_newa.md`. **Aplicado 2026-11-23** (`fix_m01_venta_v1_pago_directo_tg_table.sql`).

Con el trigger **corregido solo dentro de la transacción** (rama por `TG_TABLE_NAME` con IF anidados), `ROLLBACK`:

| | Antigua | `_m01` |
|---|---|---|
| Pago CUP 2375 | `{"success":true,"idempotent":false,"id_operacion":<op>}` | idéntico |
| Replay misma clave | `success`, `idempotent:true`, «Pagos ya registrados previamente (idempotente)» | idéntico |
| Efecto en la venta | `es_pagada=true` | `es_pagada=true` |

**Resultado: PASA (paridad) con el defecto H9 corregido; ambas fallan igual sin corregirlo.**

## Caso cambio_estado_offline (sobre la venta de la misma transacción, estado 2)

| | Antigua | `_m01` |
|---|---|---|
| Cambio a estado 2 | `{"success":true,"idempotent":false}` | idéntico |
| Replay misma clave | `success`, `idempotent:true`, «Cambio de estado ya aplicado (idempotente)» | idéntico |

**Resultado: PASA, sin diferencias.** (No depende del trigger de pagos.)

## Caso comanda_item_offline

**SKIP.** `app_dat_comanda_item`, `app_dat_comanda` y `app_dat_cocina` de la tienda 8 tienen 0 filas en newa (0 items en total), así que `fn_cambiar_estado_comanda_item_offline[_m01]` solo podría ejercitar la ruta «sin ítem» (`42501` en `_m01`). Se prueba cuando haya una cocina con comanda en newa. Sin cambios de contrato sospechosos en el cuerpo (mismo guard de tienda + idempotencia M01).

## Caso listar_ordenes

Firma `_m01` (de `06_listar_ordenes_precio_m01.sql`): 11 parámetros idénticos a la antigua — `id_tienda_param, id_tpv_param, id_usuario_param, id_estado_param, fecha_desde_param, fecha_hasta_param, id_tipo_operacion_param, con_inventario_param, solo_pendientes_param, limite_param, pagina_param`.

| Llamada | Antigua | `_m01` |
|---|---|---|
| tienda 8, TPV 6, resto por defecto (`limite=0`, `pagina=1`) | 3 filas (ids 201, 208, 209), sin error | 3 filas (ids 201, 208, 209), sin error |
| tienda 8, sin TPV, `con_inventario=true`, `limite=5` | 5 filas, sin error | 5 filas, sin error |
| Claves de nivel raíz | — | mismas que la antigua |
| Claves de `detalles` | base | base + `client_uuid`, `version_monetaria` |
| Claves de ítem (`detalles.items[]`) | base | base + `moneda_venta`, `precio_unitario_nativo`, `precio_unitario_neto_nativo`, `importe_neto_nativo`, `tasa_cambio_cup`, `snapshot_precio`, `snapshot_tasa`, `snapshot_descuentos`, `id_linea_cliente`, `id_medio_pago_seleccionado`, `seleccion_pendiente`, `descuento_manual_unitario_nativo`, `version_monetaria` |

**Diferencia justificada:** `_m01` es un superconjunto aditivo (campos nativos/snapshot de `producto-v1`; R29/M01). Los clientes viejos ignoran claves nuevas. Ninguna clave existente se quita. (Longitud del JSON de las 3 filas: 5200 vs 8823 caracteres, todo por esos campos añadidos.) **Resultado: PASA con diferencia justificada.**

## Resumen G1 (2026-11-23)

| Caso | Estado |
|---|---|
| Apertura | Diferencia justificada (`idempotent` true/false al reutilizar turno) |
| Egreso v2 | Diferencia justificada (C14 `EGRESO_SIN_SALDO`) |
| Cierre (base + monedas + replay) | **Pasa** |
| Venta v4 | **Pasa** con flag apagado en la txn; con flag ON ambas dan el mismo `42501` (esperado). Diferencia justificada en el replay (`client_uuid`, encoding) |
| Pago offline | **Pasa** con H9 corregido; **ambas fallan igual** con el estado actual de newa (H9) |
| Cambio estado offline | **Pasa** |
| Comanda ítem | **Skip** (sin comandas/cocinas en newa) |
| listar_ordenes | **Pasa**, `_m01` superconjunto aditivo |

## Pendiente de G1

- ~~**H9**~~ aplicado en newa (`sql_updates/fix_m01_venta_v1_pago_directo_tg_table.sql`, 2026-11-23). Verificado: ya no hay 42703; venta v1 sigue bloqueada con 42501.
- Comanda ítem: sin cocina/ítems en tienda 8 (skip).
- Comanda ítem: repetir cuando exista cocina + comanda en newa (o crear fixture dentro de una transacción con `ROLLBACK`).
- Opcional: `_usd` suelto, `cierre` con `p_fecha_cierre` anterior a la apertura (R33), venta con producto de cocina por tanda, listar con filtros `solo_pendientes`/estado.
