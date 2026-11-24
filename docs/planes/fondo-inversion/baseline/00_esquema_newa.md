# Baseline de `newa` — Fondo de Inversión

Capturado el **2026-11-20** contra `newa` = `qhprswhhfasrikhawjoz` (MCP `supabase-debug`), en solo
lectura. Fuente: `information_schema`, `pg_proc`, `pg_indexes`.

## Semáforo (`verify/00_linea_base.sql`)

| # | Comprobación | Estado |
|---|---|---|
| 1 | 15 tablas `fdi_*` | ok |
| 2 | `fdi_dat_movimiento` admite `'gasto'` | ok |
| 3 | `fn_registrar_recepcion_con_inventario` 12 args, 1 firma | ok |
| 4 | `fn_fdi_registrar_recepcion` + `fdi_idempotency_key`/`fdi_solicitud` | **ok (era falla)** |
| 5 | `app_dat_recepcion_productos.costo_real` = `NEVER` | ok |
| 6 | Tablas de costos adicionales | ok |
| 7 | `moneda`/`id_compra` en facturas imp/prv | info (fase 6) |
| 8 | `fn_fdi_crear_liquidacion` 11 args | ok |

**7 ok + 1 info, 0 falla** tras aplicar `ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql`.

## Aplicado el 2026-11-20 en `newa` (runbook)

1. `ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql`
   - Añade `app_dat_operacion_recepcion.fdi_idempotency_key uuid` y `.fdi_solicitud jsonb`.
   - Crea `idx_recepcion_fdi_idempotency` (único parcial `WHERE fdi_idempotency_key IS NOT NULL`).
   - Crea `fn_fdi_registrar_recepcion(jsonb, jsonb, uuid)`, `SECURITY DEFINER`, con `EXECUTE` solo a
     `authenticated`.
   - Verificación posterior: función ✅ · columnas ✅ · índice ✅ · `prosecdef` ✅ · cuerpo con
     `financiada_fondo` ✅.

No aplicado: nada más. `mapeo_categorias_consignacion.sql` queda **pendiente de decisión**.

## Tablas `fdi_*` y filas

| Tabla | Filas |
|---|---|
| `fdi_dat_concepto` | 4 |
| `fdi_dat_cuenta` | 6 |
| `fdi_dat_saldo` | 10 |
| `fdi_dat_movimiento` | 16 |
| `fdi_dat_liquidacion` | 3 |
| `fdi_dat_liquidacion_detalle` | 6 |
| `fdi_dat_liquidacion_orden` | 26 |
| `fdi_dat_inversor` | 3 |
| `fdi_dat_inversor_reparto` | 12 |
| `fdi_dat_config` | 0 |
| `fdi_dat_transferencia` | 0 |
| `fdi_dat_inversion` | 0 |
| `fdi_dat_inversion_fuente` | 0 |
| `fdi_dat_inversion_recepcion` | 0 |
| `fdi_hist_estado_inversion` | 0 |

⚠️ **Estos 16 movimientos y 10 saldos son datos reales de prueba. Cualquier migración de escala o de
idempotencia (fases 1 y 2) los toca y debe verificarlos, no recrearlos.**

## Funciones `fn_fdi_*` vivas (24)

| Función | args |
|---|---|
| `fn_fdi_ajuste` | 7 |
| `fn_fdi_ajuste_correccion_liquidacion` | 7 |
| `fn_fdi_cambiar_estado_inversion` | 3 |
| `fn_fdi_crear_inversion` | 7 |
| `fn_fdi_crear_liquidacion` | 11 |
| `fn_fdi_desvincular_recepcion` | 1 |
| `fn_fdi_detalle_inversion` | 1 |
| `fn_fdi_gasto` | 8 |
| `fn_fdi_guardar_inversor` | 5 |
| `fn_fdi_historial_inversores` | 3 |
| `fn_fdi_ingreso_manual` | 8 |
| `fn_fdi_inversiones` | 3 |
| `fn_fdi_liquidaciones` | 3 |
| `fn_fdi_movimientos` | 9 |
| `fn_fdi_pagar_inversor` | 2 |
| `fn_fdi_recalcular_inversion` | 1 |
| `fn_fdi_registrar_recepcion` | **3 (nueva)** |
| `fn_fdi_repartir_ganancia` | 0 (trigger) |
| `fn_fdi_resolver_revision` | 2 |
| `fn_fdi_saldos` | 1 |
| `fn_fdi_transferir` | 13 |
| `fn_fdi_ventas_por_medio_moneda` | 4 |
| `fn_fdi_vincular_recepcion` | 6 |

## Huella de los datos (detectar cambios tras las migraciones)

Medida el 2026-11-20, **antes** de cualquier migración de escala o idempotencia (fases 1 y 2):

| Magnitud | Valor |
|---|---|
| Filas `fdi_dat_saldo` | 10 |
| Σ `saldo` | `389420.154705882353` |
| md5 `id:saldo` de saldos | `0a632079b9f5590bc9e5fb9248dc363f` |
| Filas `fdi_dat_movimiento` | 16 |
| Σ `monto` | `389420.154705882353` |
| md5 `id:monto:saldo_nuevo` | `b91993d892016044dc8e9a0d755b2c0e` |
| Filas `fdi_dat_inversor_reparto` | 12 |
| Σ `monto` de repartos | `848583.54` |

**Dos hallazgos de esta huella:**

1. **Σ saldos = Σ movimientos exactamente.** El libro concilia hoy, así que R1 debería dar 0,00 incluso
   antes de construir la conciliación. Sirve de línea base para la fase 1.
2. **La suma tiene 12 decimales** (`…154705882353`). Es exactamente el problema de escala que ataca la
   fase 1: los montos viven en `numeric` sin precisión declarada.

Después de cada migración, `verify/01_motor_dinero.sql` debe devolver **los mismos md5**. Si cambian, la
migración alteró datos y hay que revertir.

### Segundo snapshot — tras el E2E de la fase 0 (2026-11-20)

El E2E creó datos nuevos (ingreso de 500.000 USD y la recepción financiada de 10.000), así que la huella
anterior ya no aplica. **La referencia para la fase 1 es esta:**

| Magnitud | Valor |
|---|---|
| Filas `fdi_dat_movimiento` | 19 |
| Σ `monto` | `679755075.154705882353` |
| Σ `saldo` | `679755075.154705882353` (igual: **el libro concilia**) |
| Σ redondeada a 2 | `679755075.15` |
| Filas de saldo con decimales | **1** |
| Desvío si se redondea | `-0.004705882353` (menos de medio centavo) |

✅ **Resuelto el 2026-11-20.** Al medir **por clave** antes de migrar:
`round(saldo,2) − Σ round(monto,2) = 0,00` en **las 12 claves**. Redondear ambos lados conserva la
identidad, así que **no hizo falta ningún movimiento de ajuste** y no se tocó la cadena de saldos. El
desvío de −0,0047 era la suma de una sola fila y desaparece al redondear las dos partes.

## Estado respecto a Main

Main tiene **7 de 8 rojos**: falta `'gasto'`, `fn_fdi_gasto`, las dos tablas de costos, `costo_real` no
generada (sigue `ALWAYS` con 30.038 NULL de 30.333), `fn_fdi_registrar_recepcion` y
`fn_fdi_crear_liquidacion` de 11 args. Ese paquete es la **fase 0b** y va por el pase del equipo
(`tasks/plan_promocion_main.md`), no suelto.

## Deuda detectada que no es de esta rama

`docs/planes/fondo-inversion/12-inventario-migraciones.md` §1: el cliente llama a **43 RPC que no
existen** en ninguna base. Solo una (`fn_fdi_registrar_recepcion`) era de esta rama y ya está. Las otras
**42 son código muerto previo** — pantallas que fallarán si alguien las abre. No se arreglan con SQL: hay
que retirarlas o implementarlas. Decisión pendiente del dueño.