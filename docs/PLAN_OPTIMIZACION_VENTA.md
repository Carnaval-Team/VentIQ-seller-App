# Plan de optimización del proceso de venta (ventiq_app)

Estudio del 2026-10-29 sobre Main. Síntoma: el chequeo de disponibilidad en
el preorden tarda demasiado y el registro de la orden termina en timeout sin
completarse.

## Diagnóstico

- Rol `authenticated`: `statement_timeout = 8s`, `lock_timeout = 0`.
- `fn_registrar_venta_v3`: 220 llamadas, media **938 ms**, máximo **7 839 ms**.
- `fn_ejecutar_entrega_fisica_v3` toma `pg_advisory_xact_lock` por
  `producto|ubicación|variante|opción`: dos cajas vendiendo lo mismo se
  serializan; con `lock_timeout = 0` la segunda espera hasta el corte de 8 s.
- `fn_resolver_origen_venta` se ejecutaba 2 veces por línea.
- Preorden: consultas en serie por item y la misma receta pedida hasta 3 veces
  por elaborado (chequeo, verificación de ingredientes, descomposición), más un
  `SELECT app_dat_producto` por item para saber si es elaborado (2 veces).
- Selects de la app sobre `app_dat_inventario_productos` (414k filas): 140–160
  ms de media, picos de 2,5–4,8 s.
- `fn_stock_producto_almacen_detalle` con el producto más pesado (8 576 filas
  de ledger): 73 ms, ordena todo el historial para quedarse con 1 fila.

## Hecho (2026-10-29)

### Cliente (`ventiq_app`)
1. `preorder_screen.dart` — `_processElaboratedProducts` y
   `_decomposeElaboratedProducts` usan `producto.esElaborado/esServicio` en vez
   de `isProductElaborated` (un SELECT por item). Los ingredientes anidados usan
   caché.
2. `preorder_screen.dart` — caché por envío (`_ingredientesCached`,
   `_almacenVentaCached`, `_recetaCached`, `_esElaboradoCached`), limpiada al
   iniciar cada envío. La receta y la ruta se piden una sola vez por elaborado.
3. `preorder_screen.dart` — `_checkInventoryAvailability` lanza en paralelo
   todas las consultas de red (stock propio de cada línea, ruta + receta de los
   elaborados) y luego evalúa en orden (el pozo compartido depende del orden).
4. `order_service.dart` — mensaje claro cuando la venta falla con
   `sqlstate 55P03` (lock_timeout).

### Servidor
`sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql` (**pendiente de
aplicar** en Main y Newa):
1. `fn_descontar_venta_enrutada_v2(..., p_ruta jsonb DEFAULT NULL)` reutiliza
   la ruta ya resuelta (solo si es del mismo producto).
2. `fn_registrar_venta_v3` y `fn_registrar_venta_mesa_v3` pasan
   `p_ruta := v_ruta`.
3. Ambas ventas: `SET lock_timeout = '3s'` — fallan rápido y revierten todo si
   otra caja tiene bloqueado el mismo producto.

### Servidor · saldos vigentes (2026-10-29, tras un timeout real)
Venta de 2 pizzas + 1 café (TPV 124) → `57014 statement timeout`. Cada
ingrediente tiene 5–8k filas de ledger; `fn_ingrediente_base_alcanzable` llama
3 veces a `fn_stock_saldos_presentacion`, que ordenaba todo el historial
(~80 ms). Con 9 ingredientes × 3 llamadas × validar + consumir × 2 pizzas se
superan los 8 s.

`sql_updates/optimizar_saldos_vigentes_skip_scan.sql`:
- Índice parcial `idx_inv_prod_lote_producto` (CONCURRENTLY, ejecutar solo).
- `fn_stock_producto_almacen_detalle` y `fn_stock_saldos_presentacion` leen la
  última fila por combinación con skip scan sobre `idx_inv_prod_combo`
  (79 ms → 0,3 ms). Productos con lotes conservan la consulta original.
- Equivalencia verificada en Main contra las funciones actuales: 170
  productos / 382 filas (incluye saldos cero y negativos), 0 diferencias.

Esto cubre S2 para estas dos funciones; `fn_fefo_saldos_en_ubicacion` (solo
lotes) queda igual.

## Pendiente

### Cliente
- **C4. Stock de todas las líneas en una sola consulta.** Hoy el prefetch hace
  una consulta por línea (en paralelo). Mejor: una RPC batch o un
  `in('id_producto', ids)` con `DISTINCT ON` resuelto en servidor. Requiere RPC
  nueva porque PostgREST no expresa "última fila por grupo".
- **C5. Timeout e idempotencia del RPC de venta.** Añadir `.timeout()` al
  `rpc('fn_registrar_venta_v3')` y, antes de reintentar, verificar si la venta
  ya existe (p. ej. buscando la operación por `p_denominacion` =
  `Venta Inventtia Caja - ORD-…` del TPV en los últimos minutos) para no
  duplicarla cuando se pierde la respuesta. Ideal: pasar un `p_client_uuid`
  único y que el servidor sea idempotente sobre él (columna + índice único).
- **C6. `_checkIngredientsAvailability` duplica el chequeo.** Con la caché ya
  no cuesta red, pero conceptualmente repite lo que hizo
  `_checkInventoryAvailability`. Unificar: que el primer chequeo también
  produzca los avisos de "próximo a agotar".
- **C7. Descomposición online sin uso.** `order_service` tiene comentado el
  envío de ingredientes descompuestos: el servidor hace el BOM. Evaluar si la
  descomposición del cliente solo es necesaria offline y omitirla online.

### Servidor
- **S2. Lecturas "última fila por grupo" sin ordenar todo el historial.**
  `fn_stock_producto_almacen_detalle`, `fn_fefo_saldos_en_ubicacion` y
  `fn_stock_saldos_presentacion` usan `DISTINCT ON` sobre todo el ledger del
  producto. Reescribir con *loose index scan* (CTE recursiva o
  `LATERAL (... ORDER BY id DESC LIMIT 1)` por combinación) apoyado en
  `idx_inv_prod_combo`. Alternativa más profunda: tabla de saldos vigentes
  (`app_dat_inventario_saldo`) mantenida por trigger, con RLS y policies.
- **S4. Índice en `app_dat_producto_ingredientes(id_producto_elaborado)`**
  (3 M de seq scans; tabla pequeña, impacto bajo pero gratis). También
  `(id_ingrediente)` si se consulta por ingrediente.
- **S5. RPC batch de chequeo de orden.** `fn_verificar_orden(p_id_tpv,
  p_productos jsonb)` que reutilice `fn_resolver_origen_venta`,
  `fn_preview_entrega_fisica_v3` y `fn_validar_ingredientes_elaborado_v2` y
  devuelva todos los problemas en un solo viaje, con la misma lógica que la
  venta (incluido el pozo compartido por producto). Sustituye el chequeo del
  cliente online.
- **S6. Resolución de ubicación sin `id_ubicacion`.** En
  `fn_registrar_venta_v3` el `SELECT … ORDER BY cantidad_final DESC` recorre
  todo el historial del producto en el almacén; debería mirar solo las filas
  vigentes (ver S2).
- **S7. `search_path` de `fn_descontar_venta_enrutada_v2`.** Está como
  `'public, pg_catalog'` (una sola cadena entrecomillada = un esquema
  inexistente). Funciona porque las llamadas están calificadas, pero conviene
  corregirlo a `public, pg_catalog`.
- **S8. Observabilidad.** `track_functions = none`: activar `pl` en el proyecto
  permitiría ver el tiempo por función (`pg_stat_user_functions`) y localizar
  el siguiente cuello de botella con datos.

## Verificación sugerida tras aplicar el SQL
1. Ejecutar la consulta de verificación al final del script (firma con
   `p_ruta`, `proconfig` con `lock_timeout=3s`, permisos sin `anon` en el
   helper).
2. Venta normal, venta con elaborado, venta de mesa y `fn_pedir_item_cuenta_v2`
   (usa el helper sin `p_ruta`).
3. Dos cajas vendiendo el mismo producto a la vez: la segunda debe esperar como
   máximo 3 s y, si no obtiene el lock, mostrar el mensaje de reintento.
4. Comparar `mean_exec_time` / `max_exec_time` de la venta en
   `extensions.pg_stat_statements` antes y después.
