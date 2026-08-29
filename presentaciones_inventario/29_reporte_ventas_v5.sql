-- ============================================================================
-- 29 · fn_reporte_ventas_con_proveedor5: una fila por producto + desglose
--      por presentacion (Fase 3)
-- ============================================================================
-- Cierra el punto 1 de «Lo que queda» de docs/PLAN_PRESENTACIONES_INVENTARIO.md
-- («Reportes de ventas admin»).
--
-- ----------------------------------------------------------------------------
-- FUNCION NUEVA, la v4 NO SE TOCA (decision del usuario)
-- ----------------------------------------------------------------------------
-- «para no cambiar las rpc de supabase recomiendo crear nuevas funciones
--  basadas en las anteriores ponerles un _vx siendo x un numero sucesor a la
--  que ya esta para no romper las app en produccion ni las rpc de supabase»
--
-- Asi que:
--   · `fn_reporte_ventas_con_proveedor4` queda **intacta**, con su firma y su
--     RETURNS TABLE de 16 columnas. Las apps en produccion siguen llamandola.
--   · `fn_reporte_ventas_con_proveedor_precios_actuales` tampoco se toca.
--   · Esta v5 es nueva y **nadie la llama todavia**: el Dart se migra despues,
--     en un paso aparte y reversible.
--
-- ----------------------------------------------------------------------------
-- Los dos problemas que resuelve
-- ----------------------------------------------------------------------------
-- **(1) La v4 devuelve VARIAS FILAS INDISTINGUIBLES del mismo producto.**
-- Agrupa por `id_presentacion` y por `precio_venta_cup_op` (L346-352) pero
-- **no expone ninguna de las dos**. Medido en la tienda 45, sin filtro de fecha:
--
--     filas devueltas .......... 1.377
--     productos distintos ......   671
--     filas "de mas" ...........   706   (51 %)
--     productos con >1 fila ....   420
--        · por precio distinto ..   420
--        · por presentacion ....      0
--
-- El cliente pinta dos «Refresco» seguidos con cantidades distintas y el usuario
-- no tiene como saber por que. **Este es el bug que se ve hoy**, y no tiene nada
-- que ver con presentaciones: es el historico de precios.
--
-- **(2) `total_vendido` sumaria cantidades de presentaciones distintas.**
-- Hoy NO esta ocurriendo: ventas del mismo producto en mas de una presentacion
-- en 30 dias = **0 combinaciones tienda+producto** (censo sobre 1.261). Es
-- preventivo, para cuando se configure un empaque real en un producto que se
-- vende suelto y por caja.
--
-- ----------------------------------------------------------------------------
-- Como esta construida: envuelve la v4, no la reimplementa
-- ----------------------------------------------------------------------------
-- La v4 tiene 17.314 caracteres de logica de costos historicos: costo de receta
-- al momento de la venta para elaborados, tasa USD/CUP vigente ese dia, precio
-- de venta vigente con fallback a importe/cantidad, y tres niveles de fallback
-- de costo (historial > precio_promedio > recepcion). **Reimplementar eso es
-- pedir un bug.** La v5 la llama y agrega su salida:
--
--     ingresos_totales, costo_total_vendido y total_vendido son TOTALES por
--     fila (no unitarios), asi que son sumables sin perder informacion.
--
-- Verificado: la compactacion cuadra al centimo (ver VERIFICACION V2).
--
-- El desglose por presentacion **no se puede sacar de la v4** porque no lo
-- expone, asi que se lee del ledger replicando sus mismos filtros: tipo de
-- operacion 'venta', `ov.es_pagada`, ultimo estado = 2, el criterio de fecha
-- (`creacion` vs `completado`), el rango y el filtro de almacen.
--
-- ----------------------------------------------------------------------------
-- Precio y costo unitarios: PONDERADOS, no el de una fila cualquiera
-- ----------------------------------------------------------------------------
-- Al compactar 420 productos que tienen varios precios en el periodo, quedarse
-- con el precio de una fila arbitraria seria falsear el dato. La v5 devuelve
--
--     precio_venta_cup = ingresos_totales / total_vendido
--     precio_costo_cup = costo_total_vendido / total_vendido
--
-- que es el precio medio realmente cobrado. Se conservan los nombres de columna
-- de la v4 para que el modelo Dart existente siga parseando.
--
-- ----------------------------------------------------------------------------
-- Columnas NUEVAS (las 16 de la v4 se mantienen con el mismo nombre y tipo)
-- ----------------------------------------------------------------------------
--   cantidades_por_presentacion  jsonb    desglose fisico: [{id_presentacion,
--                                         presentacion_nombre, factor_rel,
--                                         cantidad, cantidad_formateada}, ...]
--   equiv_unidades_base          numeric  SUM(cantidad * factor_rel)
--   cantidad_formateada          text     "2 Cajas + 5 Unidades"
--   n_presentaciones             integer  cuantas presentaciones distintas
--   n_precios_distintos          integer  cuantos precios distintos se agregaron
--                                         (>1 explica por que la v4 daba varias
--                                         filas; util para auditar)
--
-- `equiv_unidades_base` es la columna con la que el cliente debe multiplicar
-- para el dinero, **no** `total_vendido`, que es la suma de cantidades fisicas.
-- Cuando todo el producto se vendio en su presentacion base los dos coinciden,
-- que es el caso de todas las tiendas hoy.
--
-- ----------------------------------------------------------------------------
-- TRAMPA · el id_presentacion NULL es la presentacion BASE, no "ninguna"
-- ----------------------------------------------------------------------------
-- El primer intento agrupaba el desglose por `ep.id_presentacion` a secas. Las
-- lineas historicas sin presentacion salian como una **presentacion fantasma
-- sin nombre**, que ademas inflaba `n_presentaciones`:
--
--     Cerveza cristal  -> "149 Unidades + 131"   n_presentaciones = 2   MAL
--     galletas marias  -> "6 Unidades + 3"       n_presentaciones = 2   MAL
--
-- El `+ 131` sin etiqueta son ventas viejas de la MISMA presentacion base. El
-- CTE `lineas_norm` resuelve el nulo a la base (via `base_pres`) antes de
-- agrupar, y entonces:
--
--     Cerveza cristal  -> "280 Unidades"         n_presentaciones = 1   OK
--     galletas marias  -> "9 Unidades"           n_presentaciones = 1   OK
--
-- Es el mismo error que hubo en el `26` con `COALESCE(id_presentacion, 0)`.
-- Cualquier agregado nuevo por presentacion tiene que resolver el nulo a la
-- base, nunca tratarlo como una dimension aparte.
--
-- Seguridad: SECURITY DEFINER + `check_user_has_access_to_tienda` + search_path
-- fijado, igual que el resto de RPC nuevas (el proyecto no usa RLS).
--
-- Coste: la v4 anidada tarda ~78 ms para 30 dias de la tienda 45; la v5 completa
-- ~129 ms. El sobrecoste del desglose es aceptable para un reporte.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor5(
    p_id_tienda    bigint,
    p_fecha_desde  date    DEFAULT NULL::date,
    p_fecha_hasta  date    DEFAULT NULL::date,
    p_id_almacen   bigint  DEFAULT NULL::bigint,
    p_filtro_fecha text    DEFAULT 'creacion'::text
)
RETURNS TABLE (
    -- === las 16 columnas de la v4, mismo nombre y mismo tipo ===
    id_tienda                   bigint,
    id_producto                 bigint,
    nombre_producto             character varying,
    id_proveedor                bigint,
    nombre_proveedor            character varying,
    precio_venta_cup            numeric,
    precio_costo                numeric,
    valor_usd                   numeric,
    precio_costo_cup            numeric,
    total_vendido               numeric,
    ingresos_totales            numeric,
    costo_total_vendido         numeric,
    ganancia_unitaria           numeric,
    ganancia_total              numeric,
    es_elaborado                boolean,
    es_servicio                 boolean,
    -- === nuevas ===
    cantidades_por_presentacion jsonb,
    equiv_unidades_base         numeric,
    cantidad_formateada         text,
    n_presentaciones            integer,
    n_precios_distintos         integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_filtro_fecha  text := lower(coalesce(nullif(trim(p_filtro_fecha), ''), 'creacion'));
    v_es_completado boolean;
    v_id_tipo_venta bigint;
BEGIN
    -- El proyecto no usa RLS: la barrera es esta.
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;
    v_es_completado := (v_filtro_fecha = 'completado');

    SELECT id INTO v_id_tipo_venta
      FROM app_nom_tipo_operacion
     WHERE lower(denominacion) = 'venta'
     LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH
    -- ---------------------------------------------------------------------
    -- Base: la v4 tal cual. Toda la logica de costos historicos, tasas y
    -- precios vigentes se hereda; aqui solo se agrega.
    -- ---------------------------------------------------------------------
    base AS MATERIALIZED (
        SELECT * FROM public.fn_reporte_ventas_con_proveedor4(
            p_id_tienda, p_fecha_desde, p_fecha_hasta, p_id_almacen, p_filtro_fecha
        )
    ),

    -- ---------------------------------------------------------------------
    -- Una fila por producto. ingresos/costo/cantidad son totales por fila en
    -- la v4, asi que SUM() no pierde nada.
    -- ---------------------------------------------------------------------
    compacto AS (
        SELECT
            b.id_tienda,
            b.id_producto,
            b.nombre_producto,
            b.id_proveedor,
            b.nombre_proveedor,
            b.es_elaborado,
            b.es_servicio,
            SUM(b.total_vendido)                          AS total_vendido,
            SUM(b.ingresos_totales)                       AS ingresos_totales,
            SUM(b.costo_total_vendido)                    AS costo_total_vendido,
            -- Ponderados: el precio medio realmente cobrado, no el de una fila.
            CASE WHEN SUM(b.total_vendido) > 0
                 THEN ROUND((SUM(b.ingresos_totales) / SUM(b.total_vendido))::numeric, 2)
                 ELSE 0 END                               AS precio_venta_cup,
            CASE WHEN SUM(b.total_vendido) > 0
                 THEN ROUND((SUM(b.costo_total_vendido) / SUM(b.total_vendido))::numeric, 2)
                 ELSE 0 END                               AS precio_costo_cup,
            -- precio_costo (USD) y valor_usd (tasa) tambien ponderados por
            -- cantidad; con una sola tasa en el periodo dan la de siempre.
            CASE WHEN SUM(b.total_vendido) > 0
                 THEN ROUND((SUM(b.precio_costo * b.total_vendido) / SUM(b.total_vendido))::numeric, 4)
                 ELSE 0 END                               AS precio_costo,
            CASE WHEN SUM(b.total_vendido) > 0
                 THEN ROUND((SUM(b.valor_usd * b.total_vendido) / SUM(b.total_vendido))::numeric, 2)
                 ELSE 0 END                               AS valor_usd,
            COUNT(DISTINCT b.precio_venta_cup)::integer   AS n_precios_distintos
        FROM base b
        GROUP BY b.id_tienda, b.id_producto, b.nombre_producto,
                 b.id_proveedor, b.nombre_proveedor, b.es_elaborado, b.es_servicio
    ),

    -- ---------------------------------------------------------------------
    -- Operaciones de venta validas: MISMOS filtros que la v4.
    -- ---------------------------------------------------------------------
    ops AS MATERIALIZED (
        SELECT
            o.id,
            CASE WHEN v_es_completado THEN e.ts_estado ELSE o.created_at END AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov
          ON ov.id_operacion = o.id
         AND ov.es_pagada = true
        CROSS JOIN LATERAL (
            SELECT eo.estado, eo.created_at AS ts_estado
              FROM app_dat_estado_operacion eo
             WHERE eo.id_operacion = o.id
             ORDER BY eo.id DESC
             LIMIT 1
        ) e
        WHERE o.id_tienda         = p_id_tienda
          AND o.id_tipo_operacion = v_id_tipo_venta
          AND e.estado = 2
    ),

    -- ---------------------------------------------------------------------
    -- Desglose fisico por presentacion. No sale de la v4 (no la expone), se
    -- lee del ledger con los mismos filtros de fecha y almacen.
    -- ---------------------------------------------------------------------
    lineas AS (
        SELECT
            ep.id_producto,
            ep.id_presentacion,
            SUM(ep.cantidad) AS cantidad
        FROM ops op
        JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
        WHERE ep.cantidad > 0
          AND (p_fecha_desde IS NULL OR op.ts_op::date >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR op.ts_op::date <= p_fecha_hasta)
          AND (p_id_almacen IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_layout_almacen la
                 WHERE la.id_almacen = p_id_almacen
                   AND la.id = ep.id_ubicacion
              ))
        GROUP BY ep.id_producto, ep.id_presentacion
    ),

    -- La presentacion BASE de los productos que tienen alguna linea historica
    -- sin id_presentacion. Se resuelve una sola vez por producto.
    base_pres AS (
        SELECT DISTINCT
               l.id_producto,
               (SELECT c.id_presentacion
                  FROM public.fn_presentaciones_producto(l.id_producto) c
                 WHERE c.es_base
                 LIMIT 1) AS id_base
          FROM lineas l
         WHERE l.id_presentacion IS NULL
    ),

    -- El id_presentacion NULL es la presentacion BASE (contrato Fase 1), no
    -- "ninguna": se funde con la linea de la base en vez de aparecer como una
    -- presentacion fantasma sin nombre. Ver la TRAMPA en la cabecera.
    lineas_norm AS (
        SELECT
            l.id_producto,
            COALESCE(l.id_presentacion, bp.id_base) AS id_presentacion,
            SUM(l.cantidad)                        AS cantidad
        FROM lineas l
        LEFT JOIN base_pres bp ON bp.id_producto = l.id_producto
        GROUP BY l.id_producto, COALESCE(l.id_presentacion, bp.id_base)
    ),

    -- Se resuelve la cadena UNA vez por producto, no por linea.
    lineas_pres AS (
        SELECT
            l.id_producto,
            l.id_presentacion,
            l.cantidad,
            COALESCE(f.factor_rel, 1) AS factor_rel,
            f.nombre                  AS presentacion_nombre
        FROM lineas_norm l
        LEFT JOIN LATERAL public.fn_presentaciones_producto(l.id_producto) f
               ON f.id_presentacion = l.id_presentacion
    ),

    desglose AS (
        SELECT
            lp.id_producto,
            jsonb_agg(
                jsonb_build_object(
                    'id_presentacion',      lp.id_presentacion,
                    'presentacion_nombre',  lp.presentacion_nombre,
                    'factor_rel',           lp.factor_rel,
                    'cantidad',             lp.cantidad,
                    'cantidad_formateada',  public.fn_fmt_cantidad(lp.cantidad)
                        || CASE WHEN lp.presentacion_nombre IS NOT NULL
                                THEN ' ' || public.fn_plural_presentacion(
                                                lp.presentacion_nombre, lp.cantidad)
                                ELSE '' END
                )
                ORDER BY lp.factor_rel DESC, lp.presentacion_nombre
            )                                                   AS cantidades_por_presentacion,
            SUM(lp.cantidad * lp.factor_rel)                    AS equiv_unidades_base,
            -- "2 Cajas + 5 Unidades", de mayor a menor factor.
            string_agg(
                public.fn_fmt_cantidad(lp.cantidad)
                    || CASE WHEN lp.presentacion_nombre IS NOT NULL
                            THEN ' ' || public.fn_plural_presentacion(
                                            lp.presentacion_nombre, lp.cantidad)
                            ELSE '' END,
                ' + ' ORDER BY lp.factor_rel DESC, lp.presentacion_nombre
            )                                                   AS cantidad_formateada,
            COUNT(*)::integer                                   AS n_presentaciones
        FROM lineas_pres lp
        GROUP BY lp.id_producto
    )

    SELECT
        c.id_tienda,
        c.id_producto,
        c.nombre_producto,
        c.id_proveedor,
        c.nombre_proveedor,
        c.precio_venta_cup,
        c.precio_costo,
        c.valor_usd,
        c.precio_costo_cup,
        c.total_vendido,
        ROUND(c.ingresos_totales::numeric, 2)     AS ingresos_totales,
        ROUND(c.costo_total_vendido::numeric, 2)  AS costo_total_vendido,
        ROUND((c.precio_venta_cup - c.precio_costo_cup)::numeric, 2)      AS ganancia_unitaria,
        ROUND((c.ingresos_totales - c.costo_total_vendido)::numeric, 2)   AS ganancia_total,
        c.es_elaborado,
        c.es_servicio,
        -- Nuevas. El COALESCE cubre el producto que esta en la v4 pero cuyas
        -- lineas no casan con el ledger (no deberia pasar, pero si pasa es
        -- mejor una fila con desglose vacio que perder el producto del reporte).
        COALESCE(d.cantidades_por_presentacion, '[]'::jsonb)              AS cantidades_por_presentacion,
        COALESCE(d.equiv_unidades_base, c.total_vendido)                  AS equiv_unidades_base,
        COALESCE(d.cantidad_formateada,
                 public.fn_fmt_cantidad(c.total_vendido))                 AS cantidad_formateada,
        COALESCE(d.n_presentaciones, 0)                                   AS n_presentaciones,
        c.n_precios_distintos
    FROM compacto c
    LEFT JOIN desglose d ON d.id_producto = c.id_producto
    ORDER BY c.nombre_producto;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_ventas_con_proveedor5(bigint, date, date, bigint, text) IS
'Reporte de ventas por producto: UNA fila por producto (la v4 devuelve varias '
'indistinguibles porque agrupa por presentacion y precio sin exponerlos) mas el '
'desglose fisico por presentacion, el equivalente en unidades base y el texto '
'"2 Cajas + 5 Unidades". Envuelve a fn_reporte_ventas_con_proveedor4 para heredar '
'su logica de costos historicos. precio_venta_cup y precio_costo_cup son '
'PONDERADOS por cantidad. Para el dinero usar equiv_unidades_base, no '
'total_vendido. La v4 NO se modifica: sigue sirviendo a las apps en produccion. '
'Fase 3 presentaciones, archivo 29.';

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor5(bigint, date, date, bigint, text)
    TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- V1 · La v4 sigue EXACTAMENTE igual (16 columnas, 1 sobrecarga) y la v5 existe.
--      VERIFICADO 2026-08-29: v4_cols 16 | v5_cols 21 | v4_sobrecargas 1 |
--      v5_sobrecargas 1 | v4_len 17.314 (sin cambios) | v5 SECURITY DEFINER t |
--      v5 proconfig {search_path=public}
-- SELECT
--   (SELECT count(*) FROM information_schema.columns c
--     WHERE c.table_schema='public') AS ignorar,
--   (SELECT array_length(string_to_array(pg_get_function_result(
--       'public.fn_reporte_ventas_con_proveedor4(bigint,date,date,bigint,text)'::regprocedure), ','), 1)) AS v4_cols,
--   (SELECT array_length(string_to_array(pg_get_function_result(
--       'public.fn_reporte_ventas_con_proveedor5(bigint,date,date,bigint,text)'::regprocedure), ','), 1)) AS v5_cols,
--   (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--     WHERE n.nspname='public' AND p.proname='fn_reporte_ventas_con_proveedor4') AS v4_sobrecargas,
--   (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--     WHERE n.nspname='public' AND p.proname='fn_reporte_ventas_con_proveedor5') AS v5_sobrecargas;

-- V2 · CUADRE: la v5 compacta sin perder dinero ni cantidad (tienda 45).
--      VERIFICADO 2026-08-29:
--         filas ....... v4 1.377  ->  v5   671   (-51 %)
--         ingresos .... 160.672.118,68  =  160.672.118,68
--         costo ....... 143.436.891,59  =  143.436.891,59
--         cantidad .... 64.744,59       =  64.744,59
--      OJO: hay que pasar un JWT valido o la guarda aborta con
--      "Acceso denegado: No tienes permisos para acceder a esta tienda"
--      (que es justamente lo que debe hacer). Gerente de la 45:
--      7e3507ec-1b29-4901-bf88-e5d77be72100.
-- SELECT
--   (SELECT count(*) FROM public.fn_reporte_ventas_con_proveedor4(45,NULL,NULL,NULL,'creacion')) AS filas_v4,
--   (SELECT count(*) FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')) AS filas_v5,
--   (SELECT round(sum(ingresos_totales),2)    FROM public.fn_reporte_ventas_con_proveedor4(45,NULL,NULL,NULL,'creacion')) AS ing_v4,
--   (SELECT round(sum(ingresos_totales),2)    FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')) AS ing_v5,
--   (SELECT round(sum(costo_total_vendido),2) FROM public.fn_reporte_ventas_con_proveedor4(45,NULL,NULL,NULL,'creacion')) AS cos_v4,
--   (SELECT round(sum(costo_total_vendido),2) FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')) AS cos_v5,
--   (SELECT round(sum(total_vendido),2)       FROM public.fn_reporte_ventas_con_proveedor4(45,NULL,NULL,NULL,'creacion')) AS cant_v4,
--   (SELECT round(sum(total_vendido),2)       FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')) AS cant_v5;

-- V3 · Un producto por fila: ningun id_producto repetido.
--      VERIFICADO 2026-08-29: 0 productos repetidos.
-- SELECT id_producto, count(*)
--   FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')
--  GROUP BY 1 HAVING count(*) > 1;

-- V4 · Los productos que la v4 partia en varias filas: ver n_precios_distintos.
--      VERIFICADO 2026-08-29 (tienda 45):
--         CARGA DE GAS ......... 14 precios -> 1 fila, precio ponderado 3.218,20
--                                (13.198.944,00 / 4.101,34)
--         GASOLINA LIMPIEZA .... 14 precios -> 1.702,27
--         PIZARRA .............. 10 precios ->   689,27
--      Antes eran 14, 14 y 10 filas indistinguibles en la UI.
-- SELECT nombre_producto, total_vendido, precio_venta_cup, ingresos_totales,
--        n_precios_distintos, cantidad_formateada, equiv_unidades_base
--   FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')
--  WHERE n_precios_distintos > 1
--  ORDER BY n_precios_distintos DESC, ingresos_totales DESC
--  LIMIT 10;

-- V5 · El desglose por presentacion y el equivalente.
--      VERIFICADO 2026-08-29 (tienda 11, tras la correccion del nulo):
--         Cerveza cristal ......... "280 Unidades"  n_presentaciones 1
--         galletas de soda marias . "9 Unidades"    n_presentaciones 1
--      Antes de normalizar el nulo daban "149 Unidades + 131" y
--      "6 Unidades + 3" con n_presentaciones 2 (presentacion fantasma).
-- SELECT nombre_producto, total_vendido, cantidad_formateada,
--        equiv_unidades_base, n_presentaciones,
--        jsonb_pretty(cantidades_por_presentacion) AS desglose
--   FROM public.fn_reporte_ventas_con_proveedor5(45,NULL,NULL,NULL,'creacion')
--  WHERE n_presentaciones > 0
--  ORDER BY total_vendido DESC
--  LIMIT 5;

-- V6 · Con filtro de fechas y de almacen sigue cuadrando.
--      VERIFICADO 2026-08-29 (tienda 45, 30 dias):
--         'creacion'   -> v4 331 filas / v5 318 | ingresos 62.928.061,80 = igual
--         'completado' -> v4 331 filas / v5 318 | ingresos 62.928.061,80 = igual
-- SELECT
--   (SELECT count(*) FROM public.fn_reporte_ventas_con_proveedor4(45, current_date-30, current_date, NULL, 'creacion')) AS filas_v4_30d,
--   (SELECT count(*) FROM public.fn_reporte_ventas_con_proveedor5(45, current_date-30, current_date, NULL, 'creacion')) AS filas_v5_30d,
--   (SELECT round(sum(ingresos_totales),2) FROM public.fn_reporte_ventas_con_proveedor4(45, current_date-30, current_date, NULL, 'creacion')) AS ing_v4_30d,
--   (SELECT round(sum(ingresos_totales),2) FROM public.fn_reporte_ventas_con_proveedor5(45, current_date-30, current_date, NULL, 'creacion')) AS ing_v5_30d;
