# Contratos remotos de inventario

Baseline de solo lectura capturado el 2026-09-09. Este archivo documenta identidad, contrato y seguridad de funciones remotas necesarias para preparar SQL local. No contiene una definición reconstruida ni implica que los archivos `31`, `32` o `34` se hayan aplicado remotamente.

## `fn_inventario_resumen_por_usuario_almacen2`

- Firma: `public.fn_inventario_resumen_por_usuario_almacen2(bigint,bigint,text,boolean,text,integer,integer)`.
- Retorna 14 columnas, en este orden: `prod_id bigint`, `prod_nombre varchar`, `prod_sku varchar`, `variante_id bigint`, `variante_valor varchar`, `opcion_variante_id bigint`, `opcion_variante_valor varchar`, `cant_unidades_base numeric`, `cant_almacen_total numeric`, `stock_disponible numeric`, `stock_reservado numeric`, `zonas_count integer`, `presentaciones_count integer`, `total_count bigint`.
- No retorna descripción del producto.
- Granularidad: producto + variante + opción.
- Filtra y ordena por `created_at`.
- Corrige `factor_rel` por `id_presentacion` y llama `public.fn_presentaciones_producto`.
- `SECURITY DEFINER = true`; propietaria `postgres`.
- `proconfig = null`; el cuerpo cambia `search_path` dinámicamente.
- ACL incluye `PUBLIC`, `anon`, `authenticated` y `service_role`.
- MD5 de `pg_get_functiondef`: `c049187042b287897a1ada62ce899d5e`.

El archivo `31_inventario_resumen_stock_mixto_v3.sql` debe envolver esta función y conservar esas 14 columnas antes de agregar las columnas `stock_*`. No debe copiar su modelo de seguridad.

## `fn_inventario_resumen_por_usuario_almacen`

- Retorna 31 columnas, incluidos metadatos del producto.
- `SECURITY INVOKER`.
- ACL pública.
- MD5 de `pg_get_functiondef`: `705db4837ef8f22caa4a72623c5234cc`.

No es la base contractual de la v3.

## Baseline de Advisors

Se revisaron completos los resultados remotos de Advisors: seguridad, 693461 caracteres y 12 lints; rendimiento, 292073 caracteres y 7 lints.

Hallazgos relevantes:

- `0011_function_search_path_mutable`: afecta al resumen sin sufijo, la v2, `fn_presentaciones_producto`, `fn_stock_saldos_presentacion` y `fn_stock_mixto_json`.
- `0028_anon_security_definer_function_executable`: la v2 es `SECURITY DEFINER` ejecutable por `anon`.
- `0029_authenticated_security_definer_function_executable`: la v2 es `SECURITY DEFINER` ejecutable por `authenticated`.
- Advisors de rendimiento no reportó hallazgos específicos por nombre para esas funciones.

Referencias:

- `/database/database-linter?lint=0011_function_search_path_mutable`
- `/database/database-linter?lint=0028_anon_security_definer_function_executable`
- `/database/database-linter?lint=0029_authenticated_security_definer_function_executable`

Las funciones nuevas usan `SECURITY INVOKER`, `SET search_path = ''`, nombres calificados, validación de acceso existente, revocación de `PUBLIC`/`anon` y concesión exclusiva a `authenticated`, para no repetir este baseline.
