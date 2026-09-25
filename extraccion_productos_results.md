# Resultados de la tabla `extraccion_productos`

Este archivo presenta una estructura plausible y datos de ejemplo para la tabla `extraccion_productos`, asumiendo que el trigger `trg_crear_operacion_orden` y la función `fn_crear_operacion_desde_orden2` se ejecutaron correctamente tras una inserción en `carnavalapp."OrderDetails"`. Los valores exactos dependerán de la lógica interna de la función y de los datos insertados.

## Contenido de `extraccion_productos`

| id_operacion | id_orden | id_producto | cantidad | precio_unitario | total_operacion | fecha_creacion |
|---|---|---|---|---|---|---|
| 1 | 1 | 101 | 2 | 25.50 | 51.00 | 2026-09-24 10:00:00 |
| 2 | 2 | 102 | 1 | 10.00 | 10.00 | 2026-09-24 10:05:00 |
| 3 | 1 | 103 | 3 | 15.25 | 45.75 | 2026-09-24 10:10:00 |
