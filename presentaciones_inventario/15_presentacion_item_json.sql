-- ============================================================================
-- 15 · fn_presentacion_item_json — la presentacion de una linea, para el JSON
--      de las listas de operaciones
-- ============================================================================
--
-- PROPOSITO
-- ---------
-- Las listas de operaciones (fn_listar_operaciones_inventario_new y compania)
-- arman el detalle de cada operacion con jsonb_build_object y hoy NO incluyen
-- la presentacion. El cliente recibe:
--
--     {"id_producto": 217, "cantidad": 4, "producto_nombre": "azucar refino"}
--
-- y entonces la UI no tiene con que escribir "4 Bultos": pinta "4" o, peor,
-- "4 unidades" inventando una etiqueta que el ledger nunca dijo.
--
-- Verificado contra produccion (2026-08-27):
--   position('id_presentacion' in prosrc) = 0 en
--   fn_listar_operaciones_inventario_new  → la columna NO se lee en ninguna de
--   las 6 ramas que construyen items, aunque las 3 tablas de detalle
--   (extraccion, recepcion, control) SI la tienen.
--
-- QUE DEVUELVE
-- ------------
-- Un jsonb con las 5 claves que necesita la UI, listo para mezclar con `||`:
--
--     {
--       "id_presentacion":     337,
--       "presentacion_nombre": "Bulto",
--       "presentacion_sku":    "BLT",
--       "presentacion_factor": 10.0,
--       "cantidad_formateada": "4 Bultos"
--     }
--
-- `cantidad_formateada` se calcula aca y no en Dart porque
-- fn_plural_presentacion ya maneja las irregularidades del nomenclador
-- (Carton→Cartones, Bolsas que ya es plural). El cliente igual puede armar el
-- suyo con los campos estructurados: el helper Dart
-- (lib/utils/stock_mixto_formatter.dart) replica la misma regla para el modo
-- offline.
--
-- POR QUE UN HELPER Y NO SQL REPETIDO
-- -----------------------------------
-- Hay SEIS bloques de items en fn_listar_operaciones_inventario_new (venta,
-- transferencia×3, extraccion, recepcion) mas el de control. Repetir el LEFT
-- JOIN doble en cada uno es 6 oportunidades de escribir mal el join. Con el
-- helper cada bloque agrega UNA linea.
--
-- CONTRATO DE id_presentacion
-- ---------------------------
-- El parametro es app_dat_producto_presentacion.id (la fila del producto), NO
-- app_nom_presentacion.id. Es el mismo contrato que el resto de la Fase 0/1.
--
-- NULL-SAFE: las operaciones viejas tienen id_presentacion NULL. En ese caso
-- devuelve las claves con null y `cantidad_formateada` con la cantidad sola,
-- sin etiqueta: el ledger no sabe en que estaba expresada esa fila y no se
-- inventa una.
--
-- IMMUTABLE no, STABLE: consulta tablas.
-- ============================================================================


CREATE OR REPLACE FUNCTION public.fn_presentacion_item_json(
    p_id_presentacion bigint,
    p_cantidad        numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT CASE
        WHEN p_id_presentacion IS NULL THEN
            -- Operacion vieja sin presentacion registrada. Se devuelven las
            -- claves igual (para que el cliente no tenga que chequear su
            -- existencia) pero sin etiqueta inventada.
            jsonb_build_object(
                'id_presentacion',     NULL,
                'presentacion_nombre', NULL,
                'presentacion_sku',    NULL,
                'presentacion_factor', NULL,
                'presentacion_factor_rel', NULL,
                'equivalente_base',    NULL,
                'cantidad_formateada', public.fn_fmt_cantidad(p_cantidad)
            )
        ELSE (
            SELECT jsonb_build_object(
                'id_presentacion',     pp.id,
                'presentacion_nombre', np.denominacion,
                'presentacion_sku',    np.sku_codigo,
                -- factor = pp.cantidad, lo que el usuario escribio en la ficha.
                'presentacion_factor', pp.cantidad,
                -- factor_rel = pp.cantidad / cantidad_de_la_base. ESTE es el que
                -- sirve para equivalencias. En el producto 4380 la base tiene
                -- factor 30 y factor_rel 1: usar el primero daria "1 Unidad =
                -- 30 unidades base", que es falso.
                'presentacion_factor_rel', c.factor_rel,
                'equivalente_base',
                    ROUND(COALESCE(p_cantidad, 0) * COALESCE(c.factor_rel, 1), 6),
                'cantidad_formateada',
                    public.fn_fmt_cantidad(p_cantidad) || ' ' ||
                    public.fn_plural_presentacion(
                        np.denominacion::text,
                        COALESCE(p_cantidad, 0)
                    )
            )
              FROM app_dat_producto_presentacion pp
              JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
              -- LEFT JOIN, no INNER: si la cadena no resuelve (dato raro), se
              -- pierde el equivalente pero el nombre y el texto siguen saliendo.
              LEFT JOIN public.fn_presentaciones_producto(pp.id_producto) c
                     ON c.id_presentacion = pp.id
             WHERE pp.id = p_id_presentacion
        )
    END;
$$;

COMMENT ON FUNCTION public.fn_presentacion_item_json(bigint, numeric) IS
    'Presentacion de una linea de operacion como jsonb, para mezclar con || en '
    'el jsonb_build_object de las listas de operaciones. p_id_presentacion es '
    'app_dat_producto_presentacion.id. NULL-safe: sin presentacion devuelve las '
    'claves en null y la cantidad sin etiqueta (el ledger no sabe la unidad).';

GRANT EXECUTE ON FUNCTION public.fn_presentacion_item_json(bigint, numeric)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================
--
-- V1 · producto 217 "azucar refino": Bulto id 337 factor 10, Bolsa id 336 base.
--
--   SELECT jsonb_pretty(public.fn_presentacion_item_json(337, 4));
--   -- espera presentacion_nombre "Bulto", factor 10.0,
--   --        cantidad_formateada "4 Bultos"
--
--   SELECT public.fn_presentacion_item_json(336, 1) ->> 'cantidad_formateada';
--   -- espera "1 Bolsa"  (singular)
--
-- V2 · NULL-safe:
--
--   SELECT jsonb_pretty(public.fn_presentacion_item_json(NULL, 7));
--   -- espera las 4 claves en null y cantidad_formateada "7"
--
-- V3 · presentacion inexistente (dato huerfano):
--
--   SELECT public.fn_presentacion_item_json(99999999, 3);
--   -- espera NULL (el subselect no encuentra fila). El `||` con NULL en
--   -- jsonb da NULL, asi que el llamador DEBE envolverlo en COALESCE:
--   -- sin eso, una sola fila huerfana borraria el item entero del JSON.
--   --
--   -- Censo en produccion (2026-08-27): 0 huerfanas de 201.772 filas de
--   -- extraccion, 24.465 de recepcion y 187.585 de control. El COALESCE es
--   -- defensivo, no un parche de datos sucios.
--
-- V4 · el merge tal como se usara:
--
--   SELECT jsonb_pretty(
--            jsonb_build_object('id_producto', 217, 'cantidad', 4)
--            || COALESCE(public.fn_presentacion_item_json(337, 4), '{}'::jsonb)
--          );
--   -- espera un objeto plano con id_producto, cantidad y las 5 claves nuevas
--
-- V5 · paridad con el helper Dart (lib/utils/stock_mixto_formatter.dart):
--
--   SELECT public.fn_plural_presentacion('Caja', 4)   = 'Cajas'    AS t1,
--          public.fn_plural_presentacion('Unidad', 4) = 'Unidades' AS t2,
--          public.fn_plural_presentacion('Carton', 3) = 'Cartones' AS t3,
--          public.fn_fmt_cantidad(1.5)                = '1.5'      AS t4;
--   -- los 4 en true; el test Dart
--   -- test/stock_mixto_formatter_test.dart cubre los mismos casos.
-- ============================================================================
