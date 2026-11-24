# Pase a producción — módulo Compras / Fondo

Orden de aplicación en **main** (`vsieeihstajlrdvpuooh`). Los scripts están en
`ventiq_admin_app/lib/sql/compra/`. Todos son idempotentes y traen `BEGIN; … COMMIT;`.
El detalle largo está en `tasks/plan_promocion_main.md`.

## Estado de main hoy (medido el 2026-11-24)

| | |
|---|---|
| Tablas `fdi_*` | 15 (el fondo antiguo: saldo, movimiento, inversor, liquidación) |
| Tablas `fdi_dat_compra*` | **0** |
| `app_dat_recepcion_producto_costo` | existe, pero **sin** `id_compra_recepcion` ni `revertido_at` |
| Funciones del módulo | **0** (ni `fn_fdi_conciliacion`, ni `fn_fdi_gasto`, ni `fn_fdi_transferir_v2`) |
| `pg_cron` | instalado |

**Main no tiene nada del módulo: hay que aplicar del 01 al 09, en este orden.**

## Antes de empezar

1. Copia de seguridad de `public` (o al menos de `fdi_*` y `app_dat_recepcion_producto_costo`).
2. Ventana de poca carga: el paso 01 toca las tablas de saldo y movimiento.
3. Aplicar **archivo completo**, uno a uno, con su `COMMIT`. No cortar y pegar bloques sueltos.
4. Después de cada paso, ejecutar su `verify/` (solo lectura) y comprobar que el resumen da `0 fallos`.

## Orden

| # | Script | Qué hace | Verify |
|---|---|---|---|
| 1 | `01_motor_dinero.sql` | Escala 2 del libro, restricciones de tienda y conciliación R1 | `verify/01_motor_dinero.sql` |
| 2 | `02a_idempotencia.sql` | Claves de idempotencia en las operaciones de dinero | — |
| 3 | `02b_transferir_v2.sql` | `fn_fdi_transferir_v2` (par de tasa explícito) | — |
| 4 | `03a_compra_esquema.sql` | Tablas de compra, líneas, ajustes, historial | `verify/03_compra.sql` |
| 5 | `03b_compra_rpcs.sql` | RPC de compra: crear, editar, listar, detalle, cancelar | `verify/03_compra.sql` |
| 6 | `04_compra_liquidacion.sql` | Reserva, pago, anulación, liberación del fondo | `verify/04_liquidacion.sql` |
| 7 | `05a_compra_recepcion.sql` | Recepción vinculada a compra | `verify/05_recepcion.sql` |
| 8 | `05c_carril_b.sql` | Carril B: recepción directa sin compra | `verify/05_recepcion.sql` |
| 9 | `06a_costo_aterrizado_base.sql` | Base del costo aterrizado y catálogo de costos | `verify/06_costos.sql` (27) |
| 10 | `06b_aterrizaje.sql` | Aterrizaje del cargo de importadora y atribución al vínculo | `verify/06_costos.sql` |
| 11 | `06c_aterrizaje_cierre.sql` | Reversa del costo al cancelar, resumen de la compra, catálogo bajo superadmin | `verify/06_costos.sql` |
| 12 | `06d_ajustes_por_financiar.sql` | Ajustes tardíos con reserva y pago propios | `verify/06_costos.sql` |
| 13 | `07_aportes_inversores.sql` | Aportes de inversores al 100 %, exclusividad en BD | `verify/07_aportes.sql` (32) |
| 14 | `08_reportes.sql` | Reportes R2-R7 | `verify/08_reportes.sql` (14) |
| 15 | `08b_conciliacion_job.sql` | R1 programada en `pg_cron` (03:00) | `verify/08b_job.sql` (9) |
| 16 | `09_pendientes.sql` | Panel de pendientes, detalle por línea, facturas | `verify/09_pendientes.sql` (14) |

## Cinco cosas que no se pueden saltar

1. **`06c` parchea `fn_actualizar_precio_promedio_recepcion_v2`** desde su definición viva para que
   excluya las filas revertidas. Si el paso falla, la función quedó con el cuerpo viejo y una
   recepción cancelada volverá a capitalizar su costo: `verify/06` n=27 lo detecta.
2. **`06d` cambia `fn_fdi_compra_recalcular`** para congelar `total_financiado` fuera de `creada`.
   Sin eso, un ajuste posterior al pago mueve lo financiado y rompe las reservas.
3. **`07` afloja dos columnas de `fdi_dat_compra_pago`** (`id_cuenta`, `id_medio_pago` pasan a
   `NULL`) y añade el CHECK `fdi_pago_fuente_check`. Es el único paso que quita una restricción.
4. **`07` reescribe cuatro cuerpos de la fase 4** (`pagar`, `liberar`, `cancelar`, `anular`). Con los
   cuerpos viejos, pagar una compra de inversores falla y anular acreditaría al fondo dinero ajeno.
5. **`08b` crea el job `fdi-conciliacion-diaria`**. Si `pg_cron` no estuviera disponible, el script
   avisa y deja tabla y RPC igualmente.

## Después de aplicar

Ejecutar los tres scripts de prueba con dinero (crean datos y terminan en `ROLLBACK`, no dejan nada):

```
verify/06c_pruebas_aterrizaje.sql    -> 23 comprobaciones, 0 fallos
verify/06d_pruebas_ajuste.sql        -> 14 comprobaciones, 0 fallos
verify/07_pruebas_aportes.sql        -> 42 comprobaciones, 0 fallos
```

Y comprobar a mano:

- `select * from public.fn_fdi_conciliacion(<id_tienda>);` → `descuadres = 0` en todas las claves.
- `select * from cron.job where jobname = 'fdi-conciliacion-diaria';` → una fila, `0 3 * * *`.

## Si algo falla

Cada script tiene su `_rollback.sql`; se aplican en orden inverso al de la tabla. Los pasos 2, 4 y 9
no tienen rollback propio: van cubiertos por el de su fase (`03a`, `06a`/`06b`, `07`).

Parar y no seguir si:

- un `verify` da filas en rojo que no sean de datos vacíos;
- `fn_fdi_conciliacion` devuelve `descuadres > 0` (el libro no cuadra: es lo único que no se toca a mano);
- el paso 01 falla a mitad: restaurar la copia antes de reintentar.

## Cliente

Publicar el admin nuevo **después** de los pasos 1-16: usa `/reportes`, `/compras/pendientes`,
`/compras/facturas` y las RPC de aportes. Un admin viejo sigue funcionando contra las funciones
antiguas; uno nuevo contra una base sin el módulo falla en esas pantallas.