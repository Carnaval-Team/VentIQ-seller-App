# Funcionalidad Cocina - SQL

SQL de la implementacion del plan `docs/PLAN_RESTAURANTE_COCINA.md`.
Se aplica MANUALMENTE en el SQL Editor del dashboard de Supabase
(proyecto `vsieeihstajlrdvpuooh`), en el orden numerico de los archivos.

Los archivos que modifican algo son idempotentes: se pueden correr mas de una
vez sin romper nada.

## Orden de aplicacion

| # | Archivo | Fase | Modifica | Que hace |
|---|---------|------|----------|----------|
| 01 | `01_helpers_bom_almacen.sql` | 0 | si (solo agrega) | Helpers de descuento de receta acotado a un almacen. No toca funciones existentes. |
| 02 | `02_exportar_definiciones_actuales.sql` | 0 | no | Exporta el codigo real de las funciones de venta y diagnostica el impacto del bug. |
| 03 | `03_fix_descuento_bom_por_almacen.sql` | 0 | si | Reemplaza `fn_registrar_venta` y `fn_registrar_venta_mesa` para que deleguen en el helper. |
| 04 | `04_exportar_rutas_restantes.sql` | 0 | no | Verifica que el 03 quedo bien + exporta las 3 rutas de edicion de orden. |
| 05 | `05_helpers_devolucion_bom.sql` | 0 | si (solo agrega) | Helpers de DEVOLUCION de receta + resolucion de almacen desde extraccion/operacion. |
| 06 | `06_fix_edicion_orden_pendiente.sql` | 0 | si | Arregla las 3 rutas de edicion de orden + unifica el criterio `es_servicio` (stock fantasma). |

## Estado

- [x] 01 escrito y validado
- [x] 01 aplicado en Supabase
- [x] 02 escrito y validado
- [x] 02 ejecutado y resultado analizado
- [x] 03 escrito y validado
- [x] 03 aplicado en Supabase
- [x] 04 escrito y validado
- [x] 04 ejecutado: las 5 verificaciones pasan, `fn_stock_producto_almacen(216,12)` = 5.0
- [x] 05 escrito y validado
- [ ] 05 aplicado en Supabase
- [x] 06 escrito y validado
- [ ] 06 aplicado en Supabase
- [ ] Ajuste del stock fantasma historico (+35.3 unidades, ver 6.5)

## Validar antes de aplicar

```bash
# venv de un solo uso
uv venv "$LOCALAPPDATA/Temp/vqsql" --python 3.11
uv pip install --python "$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" pglast

PY="$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe"

# sintaxis SQL + cuerpo plpgsql de cada archivo
"$PY" funcionalidad_cocina/_validar_sql.py

# que el 03 conserve los bloques de produccion y elimine el patron roto
"$PY" funcionalidad_cocina/_verificar_03.py

# lo mismo para el 06 (las 3 rutas de edicion de orden)
"$PY" funcionalidad_cocina/_verificar_06.py

# comparar copias del repo contra el largo real de produccion
"$PY" funcionalidad_cocina/_comparar_pending_order.py
```

`_validar_sql.py` usa pglast (el parser real de Postgres). No comprueba que
tablas o columnas existan; eso sale al aplicar en el dashboard.

## Fase 0 - el bug

El descuento de materia prima de un elaborado buscaba el inventario del
ingrediente asi:

```sql
SELECT ... FROM app_dat_inventario_productos
WHERE id_producto = v_ingrediente.id_ingrediente
ORDER BY id desc, created_at DESC
LIMIT 1;
```

Ultima fila GLOBAL del ingrediente: no filtra por el almacen del TPV que vende y
solo mira UNA ubicacion. Dos fallos distintos:

1. Descuenta materia prima de otro almacen.
2. Si el ingrediente esta repartido en varias ubicaciones del almacen correcto,
   reporta "stock insuficiente" aunque en total si alcance.

### Impacto medido en la base

Consulta 2.4 - ingredientes con stock en mas de un almacen (podian descontarse
del almacen equivocado):

| id | ingrediente | almacenes | stock total |
|----|-------------|-----------|-------------|
| 417 | AZUCAR | 29, 81 | 20641.05 |
| 413 | LEVADURA | 29, 81 | 15253.00 |
| 1180 | tete | 77, 78 | 4145.0 |
| 848 | hh | 59, 60 | 700.0 |
| 217 | azucar refino | 12, 15 | 121.0 |
| 1197 | SALCHICHA 100G | 29, 81 | 28 |

Consulta 2.5 - ingredientes repartidos en 2 ubicaciones del mismo almacen
(daban "stock insuficiente" en falso):

| id | ingrediente | almacen | total real | veia antes |
|----|-------------|---------|-----------|------------|
| 217 | azucar refino | 12 | 103.0 | 100.0 |
| 216 | harina de trigo | 12 | 5.0 | 4.0 |

### El fix

`fn_descontar_ingredientes_elaborado` (archivo 01):

- acota el lookup a los layouts del almacen indicado,
- suma el stock de todas las ubicaciones de ese almacen,
- valida TODOS los ingredientes antes de descontar ninguno,
- consume ubicacion por ubicacion hasta cubrir la cantidad necesaria.

El contrato con Flutter no cambia: mismos `status` / `error_code`
`INSUFFICIENT_STOCK_INGREDIENT` / `id_ingrediente` / `cantidad_requerida` /
`cantidad_disponible`.

Queda reutilizable para la Fase 2: al pedir un plato `al_pedido` hay que
descontar MP en los layouts de ESA cocina, que es la misma llamada con otro
`p_id_almacen`.

## Rutas cubiertas y pendientes

Del inventario de rutas que descuentan receta (consulta 2.2):

| Funcion | Estado |
|---------|--------|
| `fn_registrar_venta` | arreglada en el 03 |
| `fn_registrar_venta_mesa` | arreglada en el 03 |
| `fn_registrar_venta_offline` | hereda el fix: solo delega en `fn_registrar_venta` con idempotencia por `client_uuid` |
| `fn_actualizar_cantidad_producto_orden` | arreglada en el 06 |
| `fn_agregar_producto_orden_pendiente` | arreglada en el 06 |
| `fn_eliminar_producto_orden` | arreglada en el 06 |

## Segundo bug encontrado: stock fantasma en servicios

No estaba en el plan. El criterio de "este producto no descuenta stock propio"
estaba INCONSISTENTE entre funciones:

| Funcion | Criterio (antes del 06) |
|---------|------------------------|
| `fn_registrar_venta` | `es_elaborado OR es_servicio` |
| `fn_registrar_venta_mesa` | `es_elaborado OR es_servicio` |
| `fn_actualizar_cantidad_producto_orden` | `es_elaborado OR es_servicio` |
| `fn_agregar_producto_orden_pendiente` | `es_elaborado OR es_servicio` |
| `fn_eliminar_producto_orden` | **`es_elaborado` a secas** |

Para un producto con `es_servicio = true` y `es_elaborado = false` (hay 46 en la
base) eso significaba: al venderlo NO se descuenta stock, pero al quitarlo de la
orden SI se devolvia. Inventario inflado de la nada.

Dano ya hecho, medido antes del fix (8 filas, +35.3 unidades):

| id | producto | inflado |
|----|----------|---------|
| 10086 | MANGUERA POR METROS | +22.3 |
| 2624 | CARGA DE ACEITE | +9.0 |
| 9448 | SOLDADURA | +3.0 |
| 2643 | ELECTRICIDAD | +1.0 |

El 06 unifica el criterio para que no siga creciendo. NO corrige el historico:
la seccion 6.5 lo lista para ajustarlo por la via normal de inventario, con su
trazabilidad.

## Por que no se parchea desde los .sql del repo

Las copias locales estan desincronizadas con produccion. Comparacion de largo
del cuerpo (`prosrc`) contra lo que devolvio la base:

| Funcion | repo | produccion | |
|---------|------|-----------|-|
| `fn_registrar_venta` (`registrarventa_ok.sql`) | 12314 | 13997 | produccion tiene +1683 chars |
| `fn_eliminar_producto_orden` | 5586 | 5586 | igual |
| `fn_actualizar_cantidad_producto_orden` | 9298 | 9311 | +13 |
| `fn_agregar_producto_orden_pendiente` | 9155 | 9176 | +21 |

Lo que produccion tiene y el repo no, en `fn_registrar_venta`:

- resolucion de `id_ubicacion` por el almacen del TPV (`v_id_almacen`), con
  error `NO_LOCATION_FOUND`;
- el bloque "5. Registrar pago de venta con monto 0", que inserta en
  `app_dat_pago_venta` cuando el total es 0.

Por eso el 03 se escribio sobre el dump real y `_verificar_03.py` comprueba
mecanicamente que esos bloques sobrevivieron al reemplazo.

## Nota sobre `fn_obtener_ingredientes_recursivos`

Su SELECT final filtra `p.es_elaborado = false`, asi que ya devuelve solo
ingredientes hoja y corta la recursion en elaborados intermedios (limite de 10
niveles y proteccion de ciclos por `ruta_productos`). Ese es el punto exacto
donde la Fase 4 tendra que meter la parada por `modo_elaboracion = 'por_tanda'`.
