# Recon Fase 4 — Caja y arqueo multimoneda (`ventiq_app`)

Mapa de lo que hoy es binario CUP/USD en apertura, cierre, conteo de billetes y totales.
**Fecha:** 2026-11-04 · Solo lectura, con `archivo:línea`.

## Estado: el binario está en 6 sitios

| # | Sitio | Qué hace |
|---|---|---|
| 1 | `cash_count_dialog.dart:148-170` | `if (currency == 'USD') { usdCup += value*count*_cambioCupUsd } else { cup += value*count }` |
| 2 | `cash_count_dialog.dart:172-174` | **devuelve UN solo double ya convertido a CUP** al llamador |
| 3 | `bill_count_dialog.dart:193-216` | mismo `if USD … else CUP`; y `:459-461`, `:565-574` para las filas |
| 4 | `cierre_screen.dart:385-405` | `if (moneda == 'USD') efectivoUsd += montoNativo; else efectivo += montoCup` |
| 5 | `venta_total_screen.dart:141,153,159` | ídem en el desglose por medio de pago |
| 6 | `venta_total_screen.dart:701,2047` | parsea la moneda con `key.contains('(USD)')` |

## Riesgos reales encontrados (no cosméticos)

1. **`cash_count_dialog` devuelve el total ya convertido y `cierre_screen:2337` lo escribe en
   el campo CUP.** Con un conteo de 20 USD a 900, `efectivo_real` (CUP) sube 18.000 y
   `efectivo_real_usd` queda en `'0'`. El arqueo por divisa es imposible hoy por construcción.
2. **`venta_total_screen:56-57`**: `_egresosEfectivoUsd` y `_egresosTransferenciasUsd`
   nunca se asignan → el ticket imprime **siempre 0.0** en «Egresado USD» y
   «Efectivo Real USD» (`:2058`, `:2066`).
3. **Apertura y cierre online siempre usan la variante `_usd`** porque las pantallas pasan
   `... ?? 0` (nunca `null`): `apertura_screen.dart:2018-2028`, `cierre_screen.dart:3040-3046`.
   El sync offline sí puede llamar a las variantes sin `_usd`
   (`auto_sync_service.dart:1359-1360`, `2249-2271`). Asimetría a resolver.
4. **`cierre_screen.dart:705-712`**: si no hay datos, inventa `total_efectivo = ventas*0.7`
   y `total_transferencias = ventas*0.3`. Heurística binaria que con multimoneda no
   significa nada.
5. **Una sola tasa en todo el arqueo**: `getCambioCupUsd()` (clave CUP-USD cacheada) y
   `CurrencyService.getUsdRate()`. Hay que pasar a `getRatesForStore()`.

## Contratos RPC que la app consume hoy

| RPC | Consumidores | Devuelve / espera |
|---|---|---|
| `registrar_apertura_turno_v3` / `_usd` | `turno_service.dart:760-775` | escalar `bigint` |
| `fn_cerrar_turno_tpv` / `_usd` | `turno_service.dart:593-605` | **`boolean` estricto** (`== true`) |
| `fn_apertura_turno_offline` / `_usd` | `auto_sync_service.dart:1379-1400` | jsonb `{status, message, id_turno, idempotent}` |
| `fn_cerrar_turno_offline` / `_usd` | `auto_sync_service.dart:2255-2273` | jsonb `{status, message}` |
| `fn_resumen_turno_por_id` | `turno_service.dart:234-237` | columnas de resumen + las 3 USD |
| `fn_resumen_turno_kpi` | `turno_service.dart:86-89` | idem |
| `fn_resumen_diario_cierre_v2` | `turno_service:211`, `cierre:522`, `venta_total:313`, `settings:4434`, `sales_monitor_fab:110` | mismas columnas |
| `fn_resumen_diario_cierre_v3` | solo `auto_sync_service.dart:2862` | se cachea crudo |
| `registrar_egreso_parcial_v2` | `turno_service.dart:502-512` | `{success, message, egreso_id}` |
| `egresos_por_turno` | `turno_service.dart:639-642` | filas → `Expense` |

## Contrato nuevo de la Fase 4 (lo que la app debe empezar a usar)

```text
registrar_apertura_turno_monedas(p_id_tpv, p_id_vendedor, p_usuario,
                                 p_maneja_inventario, p_productos,
                                 p_efectivo_inicial_por_moneda jsonb,   -- {"CUP":1000,"USD":20}
                                 p_observaciones) -> bigint

fn_cerrar_turno_tpv_monedas(p_id_tpv, p_usuario, p_productos,
                            p_efectivo_real_por_moneda jsonb,           -- {"CUP":1500,"USD":18}
                            p_observaciones) -> boolean

fn_resumen_diario_cierre_v4(id_tpv_param, id_usuario_param) -> (…columnas de _v3…,
                               desglose_monedas jsonb, total_base numeric)
```

`desglose_monedas`:
```json
[{"moneda":"CUP","operaciones":120,"importe_nativo":45000,"importe_base":45000,
  "efectivo_nativo":30000,"digital_nativo":15000},
 {"moneda":"USD","operaciones":7,"importe_nativo":14,"importe_base":7700,
  "efectivo_nativo":10,"digital_nativo":4}]
```

## Orden de trabajo en las pantallas (de menor a mayor riesgo)

1. `cash_count_dialog` → devolver `Map<String,double>` (rompe a su único llamador: `cierre`).
2. `cierre_screen` → campos y diferencias por divisa; consumir `_v4`; quitar la heurística 70/30.
3. `apertura_screen` → un campo por divisa; enviar `p_efectivo_inicial_por_moneda`.
4. `turno_service` → colapsar las variantes `_usd` en las RPC nuevas.
5. `venta_total_screen` → totales por divisa reales y arreglar los `_egresos*Usd` que nunca se asignan.
6. `bill_count_dialog` → conteo por divisa (tiene 2 consumidores: `orders_screen` y `preorder_screen`).