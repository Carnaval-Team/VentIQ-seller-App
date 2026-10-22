-- ============================================================================
-- 35 Â· Fase 4 Â· Devoluciones de elaborados a la presentacion BASE (C7)
--      public.fn_devolver_ingredientes_elaborado_v2(...)
--      public.fn_cancelar_item_pedido_v2(...)
--      public.fn_eliminar_producto_orden_v2(...)
-- ============================================================================
-- Fase 4 del plan `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`
-- (Â§3.1 C7, Â§4, Â§6 Fase 4) y Â§5 "rutas vivas y callers".
--
-- ----------------------------------------------------------------------------
-- EL DEFECTO (C7), medido sobre la definicion VIVA
-- ----------------------------------------------------------------------------
-- `fn_devolver_ingredientes_elaborado` devuelve la materia prima a una
-- presentacion elegida por CASCADA, no a la base:
--
--   prosrc: (SELECT pp.id FROM public.app_dat_producto_presentacion pp
--             WHERE pp.id_producto = v_ing.id_ingrediente ORDER BY pp.id ASC LIMIT 1)
--   -> `ORDER BY pp.id ASC` aparece 1 vez (medido con regexp_matches)
--
-- y ademas **suma una cantidad en unidades BASE a una fila que es FISICA**:
--
--   SELECT ip.cantidad_final ... WHERE id_producto AND id_ubicacion
--    ORDER BY ip.id DESC LIMIT 1            -- ultima fila de CUALQUIER presentacion
--   ...
--   VALUES (..., v_actual, v_actual + v_ing.cantidad_total_necesaria, ...)
--   -> `v_actual + v_ing.cantidad_total_necesaria` aparece 2 veces (escritura + traza)
--
-- Es el mismo empalme del C2 (fisica vs base) en la direccion contraria: si la
-- ultima fila de la ubicacion destino es un `Kilogramo` (factor_rel 1000), la
-- devolucion de 500 base escribe `saldo + 500` **en kilos** => infla el
-- equivalente x1000 (el caso "500 en una fila Kilogramo" de Â§2-bis).
-- Tampoco escribe `id_variante`/`id_opcion_variante`, asi que en productos con
-- variantes crea una fila nueva sin variante.
--
-- Censo medido en produccion (vsieeihstl...): de **103 ingredientes** usados en
-- recetas, **5 tienen mas de una presentacion** con factores distintos:
--   217 azucar refino  Bulto x10 (337)  + Bolsa base 1 (336)   ubic 12/15
--   219 croqueta       Caja  x24 (340)  + Unidad base 1 (339)   ubic 40
--   220 pan de la casa Caja  x24 (342)  + Unidad base 1 (341)   ubic 40
--   239 perro caliente Caja  x24 (379)  + Unidad base 1 (378)   ubic 1/40
--   960 refresco coral Caja  x24 (1117) + Blister x12 (1116) + Unidad base (1115)
-- Medido ademas: hoy la ULTIMA fila del ledger en cada ubicacion destino es la
-- presentacion base en los 5 casos => la inflacion esta **latente**, no
-- realizada; cualquier movimiento que deje un Bulto/Caja como ultima fila la
-- activa. `_v2` no puede inflar: siempre escribe en la base (factor 1) con
-- `cantidad_fisica = cantidad_base / factor_rel`.
--
-- ----------------------------------------------------------------------------
-- QUE CREA ESTE ARCHIVO (nada de esto existe hoy: verificado por to_regprocedure)
-- ----------------------------------------------------------------------------
-- 1. `fn_devolver_ingredientes_elaborado_v2(p_id_producto_elaborado bigint,
--      p_cantidad numeric, p_id_almacen bigint, p_id_extraccion bigint DEFAULT NULL,
--      p_origen_cambio integer DEFAULT 4)` -> jsonb.
--    **Misma firma que la viva** (fijada por el lead), mismo contrato de exito
--    (`status`, `id_almacen`, `lineas_afectadas`, `movimientos`) y de error
--    (`INVALID_QUANTITY`, `ALMACEN_NOT_RESOLVED`, `NO_RETURN_LOCATION`).
--    Cambios: (a) devuelve a la presentacion BASE resuelta por la cascada
--    canonica de `fn_presentaciones_producto` (`es_base DESC, factor_rel ASC,
--    id ASC`), (b) pasa de equivalente base a fisico de esa presentacion con
--    verificacion de exactitud, (c) pre-valida TODO antes de la primera
--    escritura (atomicidad), (d) escribe variante/opcion vigentes, (e) traza
--    `cantidad_base` y `devuelto` (fisico) por movimiento.
--    `_v2` devuelve `devuelto` = fisico y `devuelto_base` = equivalente, y
--    `movimientos[].presentacion` = nombre de la base.
-- 2. `fn_cancelar_item_pedido_v2(p_id_item bigint, p_motivo text DEFAULT NULL)`:
--    copia de la viva con `search_path` correcto, guard seguro, y la cantidad
--    convertida a BASE con `fn_cantidad_en_base(v_item.id_presentacion, cantidad)`
--    en las DOS ramas (receta -> `_v2`; SKU -> devuelve a la presentacion base
--    en lugar de "la primera fila del detalle").
-- 3. `fn_eliminar_producto_orden_v2(p_id_extraccion bigint, p_uuid_usuario uuid)`:
--    copia de la viva con `search_path` correcto y la devolucion de MP en BASE.
--
-- ----------------------------------------------------------------------------
-- QUE **NO** TOCA
-- ----------------------------------------------------------------------------
--   Â· `fn_devolver_ingredientes_elaborado`   (viva; md5 7a4a71902aae6719bcac5513a3db9027)
--   Â· `fn_cancelar_item_pedido`              (viva; md5 a151a00bdc98a668eafc87eb14ac2761)
--   Â· `fn_eliminar_producto_orden`           (viva; md5 0d658a6dbce1bb448c74d0012d053b4b)
--   Ninguna firma ni cuerpo vivo cambia. Este archivo solo crea objetos nuevos.
--
-- ----------------------------------------------------------------------------
-- DEPENDENCIAS Y ORDEN DE APLICACION
-- ----------------------------------------------------------------------------
--   Â· `presentaciones_inventario/45_guard_search_path.sql` -> `_safe` (el guard
--     que usan los `_v2`). Gate activo al inicio de este archivo.
--   Â· `presentaciones_inventario/24_bom_cantidad_en_base.sql` -> `fn_cantidad_en_base`
--     (ya aplicada en produccion, `proconfig = search_path=public`).
--   Â· Helpers vivos reutilizados: `fn_obtener_ingredientes_recursivos`,
--     `fn_ubicacion_destino_devolucion`, `fn_presentaciones_producto`,
--     `fn_stock_producto_almacen`, `fn_almacen_de_extraccion`,
--     `_fn_distribuir_pagos_orden`.
--   Â· El test transaccional (S-B) usa `fn_descontar_ingredientes_elaborado_v2`
--     (30/31, tarea de sql-core): aplicar 30/31 antes de correr S-B.
--   Â· Orden recomendado: 45 -> 30/31 -> **35** -> 33 -> 34. (La creacion no
--     depende del orden â€” PL/pgSQL resuelve los nombres al ejecutar â€” pero el
--     USO si.)
--
-- ----------------------------------------------------------------------------
-- CODIGOS DE ERROR
-- ----------------------------------------------------------------------------
-- Se conservan los de la viva. Se anaden dos codigos NUEVOS, ambos de
-- pre-validacion (siempre `status = 'error'`, sin escribir nada):
--   Â· `NO_BASE_PRESENTATION`      el ingrediente no tiene presentaciones.
--   Â· `NON_INTEGER_DECOMPOSITION` el equivalente no da un fisico exacto en una
--                                 presentacion no fraccionable.
-- Ningun caller vivo los interpreta hoy (el resultado se guarda en
-- `devolucion`/`v_bom`), y la app solo mira `status`/`message` en estas rutas.
-- ============================================================================

-- â”€â”€ Gate de dependencias (aborta la aplicacion si falta el guard seguro) â”€â”€â”€â”€â”€
DO $gate$
BEGIN
    IF to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)') IS NULL THEN
        RAISE EXCEPTION
            'Falta fn_check_user_has_access_to_tienda_safe: aplica antes presentaciones_inventario/45_guard_search_path.sql';
    END IF;
END
$gate$;


-- ============================================================================
-- 35.1 Â· fn_devolver_ingredientes_elaborado_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_devolver_ingredientes_elaborado_v2(
    p_id_producto_elaborado bigint,
    p_cantidad numeric,
    p_id_almacen bigint,
    p_id_extraccion bigint DEFAULT NULL::bigint,
    p_origen_cambio integer DEFAULT 4
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_ing             RECORD;
    v_plan            jsonb   := '[]'::jsonb;
    v_paso            jsonb;
    v_id_ubicacion    bigint;
    v_id_presentacion bigint;
    v_nombre_pres     varchar;
    v_factor_base     numeric;
    v_es_fraccionable boolean;
    v_cantidad_base   numeric;
    v_cantidad_fisica numeric;
    v_variante        bigint;
    v_opcion          bigint;
    v_actual          numeric;
    v_sku_producto    varchar;
    v_sku_ubicacion   varchar;
    v_movimientos     jsonb   := '[]'::jsonb;
    v_lineas          integer := 0;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cantidad a devolver debe ser positiva',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    IF p_id_almacen IS NULL THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'No se pudo determinar el almacen para devolver la materia prima',
            'error_code', 'ALMACEN_NOT_RESOLVED'
        );
    END IF;

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- PASADA 1 Â· resolver y validar TODO, sin escribir
    --   (atomicidad: si algo no cuadra se sale con status='error' y 0 filas)
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    FOR v_ing IN
        SELECT i.id_ingrediente, i.cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad) i
         ORDER BY i.id_ingrediente
    LOOP
        v_cantidad_base := COALESCE(v_ing.cantidad_total_necesaria, 0);

        IF v_cantidad_base <= 0 THEN
            CONTINUE;   -- nada que devolver por este ingrediente
        END IF;

        -- (1) ubicacion destino dentro del almacen (helper vivo, sin cambios)
        v_id_ubicacion := public.fn_ubicacion_destino_devolucion(v_ing.id_ingrediente, p_id_almacen);

        IF v_id_ubicacion IS NULL THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'El almacen no tiene ubicacion donde devolver el ingrediente: '
                                  || COALESCE((SELECT p.denominacion FROM public.app_dat_producto p
                                                WHERE p.id = v_ing.id_ingrediente),
                                              '#' || v_ing.id_ingrediente),
                'error_code',     'NO_RETURN_LOCATION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- (2) presentacion BASE del ingrediente: misma cascada canonica que
        --     fn_presentaciones_producto (es_base DESC, menor factor, menor id).
        --     Su factor_rel es 1 por definicion, pero NO se asume: se lee.
        SELECT c.id_presentacion, c.nombre, COALESCE(c.factor_rel, 1), COALESCE(c.es_fraccionable, false)
          INTO v_id_presentacion, v_nombre_pres, v_factor_base, v_es_fraccionable
          FROM public.fn_presentaciones_producto(v_ing.id_ingrediente) c
         ORDER BY c.es_base DESC, c.factor_rel ASC NULLS LAST, c.id_presentacion ASC
         LIMIT 1;

        IF v_id_presentacion IS NULL THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'El ingrediente no tiene presentaciones configuradas: '
                                  || COALESCE((SELECT p.denominacion FROM public.app_dat_producto p
                                                WHERE p.id = v_ing.id_ingrediente),
                                              '#' || v_ing.id_ingrediente),
                'error_code',     'NO_BASE_PRESENTATION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        IF v_factor_base IS NULL OR v_factor_base <= 0 THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'CATALOGO_PRESENTACIONES_INVALIDO: el ingrediente '
                                  || v_ing.id_ingrediente || ' tiene factor_rel ' || v_factor_base
                                  || ' en su presentacion base',
                'error_code',     'CATALOGO_PRESENTACIONES_INVALIDO',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- (3) equivalente base -> unidades FISICAS de esa presentacion
        v_cantidad_fisica := v_cantidad_base / v_factor_base;

        IF round(v_cantidad_fisica * v_factor_base, 6) <> round(v_cantidad_base, 6) THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'Devolucion no exacta: ' || v_cantidad_base || ' base del ingrediente '
                                  || v_ing.id_ingrediente || ' no es multiplo exacto de '
                                  || COALESCE(v_nombre_pres, 'la presentacion base')
                                  || ' (factor ' || v_factor_base || ')',
                'error_code',     'NON_INTEGER_DECOMPOSITION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        -- Sin fracciones de empaque salvo que la presentacion sea fraccionable.
        IF NOT v_es_fraccionable AND v_cantidad_fisica <> trunc(v_cantidad_fisica) THEN
            RETURN jsonb_build_object(
                'status',         'error',
                'message',        'Devolucion con fraccion de empaque: ' || v_cantidad_fisica || ' '
                                  || COALESCE(v_nombre_pres, 'unidades') || ' del ingrediente '
                                  || v_ing.id_ingrediente || ' (no fraccionable)',
                'error_code',     'NON_INTEGER_DECOMPOSITION',
                'id_ingrediente', v_ing.id_ingrediente,
                'id_almacen',     p_id_almacen
            );
        END IF;

        v_plan := v_plan || jsonb_build_object(
            'id_ingrediente',  v_ing.id_ingrediente,
            'id_ubicacion',    v_id_ubicacion,
            'id_presentacion', v_id_presentacion,
            'presentacion',    v_nombre_pres,
            'factor_rel',      v_factor_base,
            'cantidad_base',   v_cantidad_base,
            'cantidad_fisica', v_cantidad_fisica
        );
    END LOOP;

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- PASADA 2 Â· escribir el plan (una fila de ledger por ingrediente)
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    FOR v_paso IN SELECT e.value FROM jsonb_array_elements(v_plan) AS e
    LOOP
        -- Fila VIGENTE de ESA presentacion base en la ubicacion destino.
        -- Mismo criterio que fn_stock_saldos_presentacion (ultima fila por clave
        -- ubicacion + variante + opcion + presentacion). Si no hay fila, se parte
        -- de 0: el saldo de la presentacion base en esa ubicacion es 0.
        SELECT DISTINCT ON (COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0))
               ip.id_variante,
               ip.id_opcion_variante,
               COALESCE(ip.cantidad_final, 0),
               ip.sku_producto,
               ip.sku_ubicacion
          INTO v_variante, v_opcion, v_actual, v_sku_producto, v_sku_ubicacion
          FROM public.app_dat_inventario_productos ip
         WHERE ip.id_producto     = (v_paso->>'id_ingrediente')::bigint
           AND ip.id_ubicacion    = (v_paso->>'id_ubicacion')::bigint
           AND ip.id_presentacion = (v_paso->>'id_presentacion')::bigint
         ORDER BY COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0), ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        IF v_sku_producto IS NULL THEN
            SELECT p.sku INTO v_sku_producto
              FROM public.app_dat_producto p
             WHERE p.id = (v_paso->>'id_ingrediente')::bigint;
        END IF;

        IF v_sku_ubicacion IS NULL THEN
            SELECT la.sku_codigo INTO v_sku_ubicacion
              FROM public.app_dat_layout_almacen la
             WHERE la.id = (v_paso->>'id_ubicacion')::bigint;
        END IF;

        INSERT INTO public.app_dat_inventario_productos (
            id_producto,
            id_variante,
            id_opcion_variante,
            id_ubicacion,
            id_presentacion,
            cantidad_inicial,
            cantidad_final,
            sku_producto,
            sku_ubicacion,
            origen_cambio,
            id_extraccion,
            created_at
        ) VALUES (
            (v_paso->>'id_ingrediente')::bigint,
            v_variante,
            v_opcion,
            (v_paso->>'id_ubicacion')::bigint,
            (v_paso->>'id_presentacion')::bigint,
            v_actual,
            v_actual + (v_paso->>'cantidad_fisica')::numeric,
            v_sku_producto,
            v_sku_ubicacion,
            p_origen_cambio,
            p_id_extraccion,
            now()
        );

        v_movimientos := v_movimientos || jsonb_build_object(
            'id_ingrediente',  (v_paso->>'id_ingrediente')::bigint,
            'id_ubicacion',    (v_paso->>'id_ubicacion')::bigint,
            'id_presentacion', (v_paso->>'id_presentacion')::bigint,
            'presentacion',    v_paso->>'presentacion',
            'factor_rel',      (v_paso->>'factor_rel')::numeric,
            'devuelto',        (v_paso->>'cantidad_fisica')::numeric,   -- unidades fisicas
            'devuelto_base',   (v_paso->>'cantidad_base')::numeric,     -- equivalente base
            'stock_previo',    v_actual,
            'stock_nuevo',     v_actual + (v_paso->>'cantidad_fisica')::numeric
        );

        v_lineas := v_lineas + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_almacen',       p_id_almacen,
        'lineas_afectadas', v_lineas,
        'presentacion',     'base',
        'movimientos',      v_movimientos
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_devolver_ingredientes_elaborado_v2(bigint, numeric, bigint, bigint, integer) IS
    'Fase 4 / C7: devuelve la materia prima de un elaborado a la presentacion BASE del ingrediente (cascada canonica de fn_presentaciones_producto), en equivalente exacto y con traza (devuelto fisico + devuelto_base). Pre-valida todo antes de escribir. Misma firma y mismo contrato que fn_devolver_ingredientes_elaborado (la viva no se toca).';

REVOKE ALL ON FUNCTION public.fn_devolver_ingredientes_elaborado_v2(bigint, numeric, bigint, bigint, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_devolver_ingredientes_elaborado_v2(bigint, numeric, bigint, bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_devolver_ingredientes_elaborado_v2(bigint, numeric, bigint, bigint, integer)
    TO authenticated, service_role;


-- ============================================================================
-- 35.2 Â· fn_cancelar_item_pedido_v2
-- ============================================================================
-- Copia de la viva (md5 a151a00bdc98a668eafc87eb14ac2761) con:
--   Â· `SET search_path = 'public, pg_catalog'` y guard seguro;
--   Â· cantidad del item convertida a BASE (`fn_cantidad_en_base`) en las DOS
--     ramas: la linea guarda la presentacion vendida (1 Caja), pero la receta se
--     consumio multiplicada por su factor (24 base);
--   Â· rama SKU: se devuelve a la presentacion BASE (no a "la primera fila del
--     detalle", que podia ser un Bulto/Kilogramo => el caso C7).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_cancelar_item_pedido_v2(
    p_id_item bigint,
    p_motivo text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_item               RECORD;
    v_id_tienda          bigint;
    v_estado_cta         smallint;
    v_com_item           RECORD;
    v_ya_servido         boolean := false;
    v_devuelto           jsonb   := NULL;
    v_movs               jsonb   := '[]'::jsonb;
    v_id_almacen         bigint;
    v_cantidad_base      numeric;
    v_id_ubicacion       bigint;
    v_id_presentacion    bigint;
    v_nombre_presentacion varchar;
    v_factor_base        numeric;
    v_delta_fisico       numeric;
    v_variante           bigint;
    v_opcion             bigint;
    v_actual             numeric;
    v_sku_producto       varchar;
    v_sku_ubicacion      varchar;
BEGIN
    SELECT i.id, i.id_cuenta, i.id_producto, i.id_presentacion, i.cantidad,
           i.origen_stock, i.id_cocina, i.id_comanda_item, i.stock_movido,
           i.inventory_data
      INTO v_item
      FROM public.app_dat_mesa_cuenta_item i
     WHERE i.id = p_id_item;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El item no existe',
            'error_code', 'ITEM_NOT_FOUND'
        );
    END IF;

    SELECT c.id_tienda, c.estado INTO v_id_tienda, v_estado_cta
      FROM public.app_dat_mesa_cuenta_abierta c
     WHERE c.id = v_item.id_cuenta;

    -- Guard seguro (search_path fijo): la viva no se toca.
    PERFORM public.fn_check_user_has_access_to_tienda_safe(v_id_tienda);

    IF v_estado_cta <> 1 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cuenta ya no esta abierta',
            'error_code', 'CUENTA_NO_ABIERTA'
        );
    END IF;

    -- â”€â”€ Estado en cocina â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_item.id_comanda_item IS NOT NULL THEN
        SELECT ci.id, ci.estado, ci.id_comanda
          INTO v_com_item
          FROM public.app_dat_comanda_item ci
         WHERE ci.id = v_item.id_comanda_item;

        -- 4 entregado. 3 listo tambien cuenta como servido: el plato existe.
        v_ya_servido := COALESCE(v_com_item.estado, 0) IN (3, 4);
    ELSIF v_item.origen_stock = 'tanda' THEN
        -- Una tanda se sirve al pedirla: ya salio de la cocina.
        v_ya_servido := true;
    END IF;

    IF v_ya_servido AND (p_motivo IS NULL OR trim(p_motivo) = '') THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El plato ya fue servido: hace falta un motivo para registrar la merma',
            'error_code', 'MOTIVO_REQUERIDO',
            'ya_servido', true
        );
    END IF;

    -- â”€â”€ Cancelar la comanda si estaba viva â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_com_item.id IS NOT NULL AND v_com_item.estado IN (1, 2) THEN
        UPDATE public.app_dat_comanda_item
           SET estado = 5, updated_at = now()
         WHERE id = v_com_item.id;

        -- Si no queda ninguna linea viva, cancelar la cabecera tambien.
        UPDATE public.app_dat_comanda co
           SET estado = 5, cancelled_at = now(), updated_at = now()
         WHERE co.id = v_com_item.id_comanda
           AND NOT EXISTS (
                SELECT 1 FROM public.app_dat_comanda_item ci2
                 WHERE ci2.id_comanda = co.id AND ci2.estado IN (1, 2, 3)
           );
    END IF;

    -- â”€â”€ Devolver stock solo si NO se sirvio â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_item.stock_movido AND NOT v_ya_servido THEN
        v_id_almacen := NULLIF(v_item.inventory_data->>'id_almacen', '')::bigint;

        -- C5/C7: la linea guarda la presentacion VENDIDA; la receta se consumio
        -- en equivalente BASE. Se convierte en la entrada (misma conversion que
        -- fn_pedir_item_cuenta_v2 / fn_actualizar_cantidad_producto_orden_v2).
        v_cantidad_base := public.fn_cantidad_en_base(v_item.id_presentacion, v_item.cantidad);

        IF v_id_almacen IS NULL THEN
            -- Sin traza del almacen no se adivina: se avisa en vez de devolver
            -- a un almacen equivocado.
            v_devuelto := jsonb_build_object(
                'status', 'warning',
                'message', 'No se pudo determinar el almacen de origen: revisar manualmente'
            );
        ELSIF v_item.origen_stock = 'al_pedido' THEN
            -- Se devuelven los INGREDIENTES a la cocina, a la presentacion base.
            v_devuelto := public.fn_devolver_ingredientes_elaborado_v2(
                p_id_producto_elaborado := v_item.id_producto,
                p_cantidad              := v_cantidad_base,
                p_id_almacen            := v_id_almacen,
                p_origen_cambio         := 4
            );
        ELSE
            -- Se devuelve el SKU propio (barra o porcion de tanda no servida).
            -- `_v2`: EN EQUIVALENTE BASE y a la presentacion BASE del producto.
            v_id_ubicacion := public.fn_ubicacion_destino_devolucion(v_item.id_producto, v_id_almacen);

            IF v_id_ubicacion IS NULL THEN
                v_devuelto := jsonb_build_object(
                    'status',  'warning',
                    'message', 'El almacen no tiene ubicacion donde devolver el producto: revisar manualmente'
                );
            ELSE
                SELECT c.id_presentacion, c.nombre, COALESCE(c.factor_rel, 1)
                  INTO v_id_presentacion, v_nombre_presentacion, v_factor_base
                  FROM public.fn_presentaciones_producto(v_item.id_producto) c
                 ORDER BY c.es_base DESC, c.factor_rel ASC NULLS LAST, c.id_presentacion ASC
                 LIMIT 1;

                IF v_id_presentacion IS NULL OR v_factor_base IS NULL OR v_factor_base <= 0 THEN
                    v_devuelto := jsonb_build_object(
                        'status',  'warning',
                        'message', 'El producto no tiene una presentacion base valida: revisar manualmente'
                    );
                ELSE
                    v_delta_fisico := v_cantidad_base / v_factor_base;

                    SELECT DISTINCT ON (COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0))
                           ip.id_variante,
                           ip.id_opcion_variante,
                           COALESCE(ip.cantidad_final, 0),
                           ip.sku_producto,
                           ip.sku_ubicacion
                      INTO v_variante, v_opcion, v_actual, v_sku_producto, v_sku_ubicacion
                      FROM public.app_dat_inventario_productos ip
                     WHERE ip.id_producto     = v_item.id_producto
                       AND ip.id_ubicacion    = v_id_ubicacion
                       AND ip.id_presentacion = v_id_presentacion
                     ORDER BY COALESCE(ip.id_variante, 0), COALESCE(ip.id_opcion_variante, 0), ip.id DESC
                     LIMIT 1;

                    v_actual := COALESCE(v_actual, 0);

                    IF v_sku_producto IS NULL THEN
                        SELECT p.sku INTO v_sku_producto FROM public.app_dat_producto p
                         WHERE p.id = v_item.id_producto;
                    END IF;
                    IF v_sku_ubicacion IS NULL THEN
                        SELECT la.sku_codigo INTO v_sku_ubicacion FROM public.app_dat_layout_almacen la
                         WHERE la.id = v_id_ubicacion;
                    END IF;

                    INSERT INTO public.app_dat_inventario_productos (
                        id_producto, id_variante, id_opcion_variante,
                        id_ubicacion, id_presentacion,
                        cantidad_inicial, cantidad_final,
                        sku_producto, sku_ubicacion,
                        origen_cambio, created_at
                    ) VALUES (
                        v_item.id_producto, v_variante, v_opcion,
                        v_id_ubicacion, v_id_presentacion,
                        v_actual, v_actual + v_delta_fisico,
                        v_sku_producto, v_sku_ubicacion,
                        4, now()
                    );

                    v_movs := v_movs || jsonb_build_object(
                        'id_ubicacion',    v_id_ubicacion,
                        'id_presentacion', v_id_presentacion,
                        'presentacion',    v_nombre_presentacion,
                        'factor_rel',      v_factor_base,
                        'devuelto',        v_delta_fisico,
                        'devuelto_base',   v_cantidad_base
                    );

                    v_devuelto := jsonb_build_object(
                        'status',      'success',
                        'presentacion','base',
                        'movimientos', v_movs
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- â”€â”€ Quitar la linea de la cuenta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    DELETE FROM public.app_dat_mesa_cuenta_item WHERE id = p_id_item;

    UPDATE public.app_dat_mesa_cuenta_abierta SET updated_at = now()
     WHERE id = v_item.id_cuenta;

    RETURN jsonb_build_object(
        'status',            'success',
        'id_item',           p_id_item,
        'ya_servido',        v_ya_servido,
        'stock_devuelto',    (v_item.stock_movido AND NOT v_ya_servido),
        'es_merma',          v_ya_servido,
        'motivo',            p_motivo,
        'comanda_cancelada', (v_com_item.id IS NOT NULL AND v_com_item.estado IN (1, 2)),
        'devolucion',        v_devuelto,
        'message',           CASE
            WHEN v_ya_servido
              THEN 'Item retirado de la cuenta y registrado como merma'
            WHEN v_item.stock_movido
              THEN 'Item cancelado y stock devuelto'
            ELSE 'Item cancelado'
        END
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_cancelar_item_pedido_v2(bigint, text) IS
    'Fase 4 / C5+C7: copia de fn_cancelar_item_pedido con search_path correcto, guard seguro y devolucion en equivalente BASE a la presentacion base del ingrediente/producto (fn_devolver_ingredientes_elaborado_v2). La viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_cancelar_item_pedido_v2(bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_cancelar_item_pedido_v2(bigint, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_cancelar_item_pedido_v2(bigint, text)
    TO authenticated, service_role;


-- ============================================================================
-- 35.3 Â· fn_eliminar_producto_orden_v2
-- ============================================================================
-- Copia de la viva (md5 0d658a6dbce1bb448c74d0012d053b4b) con `search_path`
-- correcto y la devolucion de materia prima en equivalente BASE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_eliminar_producto_orden_v2(
    p_id_extraccion bigint,
    p_uuid_usuario uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_extraccion       RECORD;
    v_nuevo_total      NUMERIC;
    v_es_elaborado     BOOLEAN;
    v_estado           INT;
    v_id_almacen       BIGINT;
    v_bom              JSONB;
    v_cantidad_base    NUMERIC;
BEGIN
    -- 1. Obtener extracciÃ³n
    SELECT e.*, o.id AS op_id
      INTO v_extraccion
      FROM public.app_dat_extraccion_productos e
      JOIN public.app_dat_operaciones        o ON o.id = e.id_operacion
     WHERE e.id = p_id_extraccion;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','ExtracciÃ³n no encontrada');
    END IF;

    -- 2. Verificar estado Pendiente
    SELECT eo.estado INTO v_estado
      FROM public.app_dat_estado_operacion eo
     WHERE eo.id_operacion = v_extraccion.op_id
     ORDER BY eo.created_at DESC, eo.id DESC
     LIMIT 1;

    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object('status','error','message','Solo se pueden editar Ã³rdenes en estado Pendiente');
    END IF;

    -- 3. Verificar si es elaborado (mismo criterio que las otras rutas)
    SELECT (es_elaborado or es_servicio) INTO v_es_elaborado
      FROM public.app_dat_producto WHERE id = v_extraccion.id_producto;

    -- 4. Restaurar inventario (devolver stock)
    IF v_es_elaborado IS NOT TRUE THEN
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion,
            origen_cambio, id_extraccion, created_at
        )
        SELECT
            v_extraccion.id_producto,
            v_extraccion.id_variante,
            v_extraccion.id_opcion_variante,
            v_extraccion.id_ubicacion,
            v_extraccion.id_presentacion,
            COALESCE(ip.cantidad_final, 0),
            COALESCE(ip.cantidad_final, 0) + v_extraccion.cantidad,  -- devolver stock
            v_extraccion.sku_producto,
            v_extraccion.sku_ubicacion,
            3,
            p_id_extraccion,
            NOW()
        FROM (
            SELECT cantidad_final
              FROM public.app_dat_inventario_productos
             WHERE id_producto = v_extraccion.id_producto
               AND COALESCE(id_variante,  0) = COALESCE(v_extraccion.id_variante,  0)
               AND COALESCE(id_ubicacion, 0) = COALESCE(v_extraccion.id_ubicacion, 0)
             ORDER BY created_at DESC, id DESC
             LIMIT 1
        ) ip;
    ELSE
        -- Devolucion de materia prima acotada al almacen de la linea.
        -- FASE 4: la linea guarda la presentacion VENDIDA; la receta se consumio
        -- en equivalente BASE => se convierte antes de devolver.
        v_id_almacen := public.fn_almacen_de_extraccion(p_id_extraccion);

        IF v_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error',
                'message','No se pudo determinar el almacen de la linea para devolver la materia prima',
                'error_code','ALMACEN_NOT_RESOLVED',
                'id_extraccion', p_id_extraccion
            );
        END IF;

        v_cantidad_base := public.fn_cantidad_en_base(v_extraccion.id_presentacion, v_extraccion.cantidad);

        v_bom := public.fn_devolver_ingredientes_elaborado_v2(
            p_id_producto_elaborado := v_extraccion.id_producto,
            p_cantidad              := v_cantidad_base,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := 4
        );

        IF (v_bom->>'status') <> 'success' THEN
            RETURN jsonb_build_object(
                'status',     'error',
                'message',    COALESCE(v_bom->>'message', 'Error devolviendo materia prima'),
                'error_code', COALESCE(v_bom->>'error_code', 'BOM_ERROR'),
                'id_almacen', v_id_almacen
            );
        END IF;
    END IF;

    -- 5. Eliminar extracciÃ³n
    DELETE FROM public.app_dat_extraccion_productos WHERE id = p_id_extraccion;

    -- 6. Recalcular total
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
      INTO v_nuevo_total
      FROM public.app_dat_extraccion_productos
     WHERE id_operacion = v_extraccion.op_id;

    UPDATE public.app_dat_operacion_venta
       SET importe_total = v_nuevo_total
     WHERE id_operacion = v_extraccion.op_id;

    -- 7. Redistribuir pagos proporcionalmente (solo si quedan productos)
    IF v_nuevo_total > 0 THEN
        PERFORM public._fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total);
    END IF;

    -- 8. Log
    INSERT INTO public.app_dat_log_modificacion_orden
        (id_operacion, uuid_usuario, accion, detalle, created_at)
    VALUES (
        v_extraccion.op_id,
        p_uuid_usuario,
        'remove_product',
        jsonb_build_object(
            'id_extraccion',   p_id_extraccion,
            'id_producto',     v_extraccion.id_producto,
            'cantidad',        v_extraccion.cantidad,
            'cantidad_base',   v_cantidad_base,
            'precio_unitario', v_extraccion.precio_unitario,
            'importe',         v_extraccion.importe,
            'nuevo_total_orden',v_nuevo_total,
            'id_almacen_bom',  v_id_almacen
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'status',       'success',
        'id_extraccion',p_id_extraccion,
        'total_orden',  v_nuevo_total,
        'message',      'Producto eliminado correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','error','message','Error: ' || SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$;

COMMENT ON FUNCTION public.fn_eliminar_producto_orden_v2(bigint, uuid) IS
    'Fase 4 / C7: copia de fn_eliminar_producto_orden con search_path correcto y devolucion de materia prima en equivalente BASE (fn_devolver_ingredientes_elaborado_v2). La viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_eliminar_producto_orden_v2(bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_eliminar_producto_orden_v2(bigint, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_producto_orden_v2(bigint, uuid)
    TO authenticated, service_role;


-- ============================================================================
-- VERIFICACION (comentada)
-- ============================================================================
--
-- V1 Â· Firma, retorno y search_path de las tres:
--
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--          p.prorettype::regtype AS ret, p.proconfig
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_devolver_ingredientes_elaborado_v2',
--                        'fn_cancelar_item_pedido_v2','fn_eliminar_producto_orden_v2')
--    ORDER BY 1;
--   -- esperado: (p_id_producto_elaborado bigint, p_cantidad numeric, p_id_almacen bigint,
--   --            p_id_extraccion bigint, p_origen_cambio integer) | jsonb | {search_path="public, pg_catalog"}
--   --           (p_id_item bigint, p_motivo text) | jsonb | ...
--   --           (p_id_extraccion bigint, p_uuid_usuario uuid) | jsonb | ...
--
-- V2 Â· Las VIVAS siguen intactas:
--
--   SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_devolver_ingredientes_elaborado','fn_cancelar_item_pedido',
--                        'fn_eliminar_producto_orden') ORDER BY 1;
--   -- esperado: 7a4a71902aae6719bcac5513a3db9027 / a151a00bdc98a668eafc87eb14ac2761 / 0d658a6dbce1bb448c74d0012d053b4b
--
-- V3 Â· `_v2` NO elige presentacion por cascada ni suma base a una fila fisica:
--
--   SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, 'ORDER BY pp\.id ASC', 'g')) AS cascada_prohibida,
--          (SELECT count(*) FROM regexp_matches(p.prosrc, 'ORDER BY c\.es_base DESC', 'g')) AS base_canonica
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.proname='fn_devolver_ingredientes_elaborado_v2';
--   -- esperado: 0 | 1
--
-- ============================================================================
-- TESTS
-- ============================================================================
-- S-A corre en produccion con el MCP en modo lectura. S-B necesita escritura
-- (debug `qhprswhhfasrikhawjoz` o SQL Editor) y usa `BEGIN ... ROLLBACK`.
-- ============================================================================

-- ############################################################################
-- SECCION S-A Â· Evidencia del defecto C7 en la funcion VIVA (solo lectura)
-- ############################################################################

SELECT
    md5(pg_get_functiondef('public.fn_devolver_ingredientes_elaborado(bigint,numeric,bigint,bigint,integer)'::regprocedure))
        = '7a4a71902aae6719bcac5513a3db9027'                            AS viva_intacta,
    (SELECT count(*) FROM regexp_matches(p.prosrc, 'ORDER BY pp\.id ASC', 'g'))
                                                                        AS cascada_pp_id_asc,
    (SELECT count(*) FROM regexp_matches(p.prosrc, 'v_actual \+ v_ing\.cantidad_total_necesaria', 'g'))
                                                                        AS suma_base_a_fila_fisica,
    (SELECT count(*) FROM regexp_matches(p.prosrc, 'ORDER BY ip\.id DESC', 'g'))
                                                                        AS ultima_fila_sin_presentacion,
    (SELECT count(*) FROM (
        SELECT DISTINCT pi.id_ingrediente
          FROM public.app_dat_producto_ingredientes pi) x
      JOIN LATERAL (
        SELECT count(*) AS n
          FROM public.app_dat_producto_presentacion pp
         WHERE pp.id_producto = x.id_ingrediente) c ON true
     WHERE c.n > 1)                                                     AS ingredientes_receta_con_mas_de_una_pres,
    (SELECT count(*)
       FROM (SELECT DISTINCT pi.id_ingrediente FROM public.app_dat_producto_ingredientes pi) i) AS ingredientes_en_recetas
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_devolver_ingredientes_elaborado';
-- Esperado (medido en produccion): true | 1 | 2 | 1 | 5 | 103

-- ############################################################################
-- SECCION S-B Â· Simetria consumo -> devolucion (_v2) Â· requiere escritura
-- ############################################################################

-- COMMIT OBLIGATORIO antes de los tests: el `ROLLBACK` del final revierte la
-- transaccion en curso y, si el DDL de arriba comparte esa transaccion (el SQL
-- Editor y el MCP mandan el archivo como UN solo batch), el DDL se perderia.
-- Medido el 2026-10-22 en debug: sin este COMMIT, aplicar este archivo NO
-- creaba ninguna de sus tres `_v2`.
COMMIT;

BEGIN;

DO $test$
DECLARE
    v_id_almacen   bigint;
    v_disp216      numeric;
    v_disp218      numeric;
    v_cajas        numeric;
    v_base         numeric;     -- equivalente base de las cajas del caso
    v_antes216     numeric;
    v_antes218     numeric;
    v_desc         jsonb;
    v_dev          jsonb;
    v_esperado216  numeric;
    v_esperado218  numeric;
    v_pres_base    varchar;
BEGIN
    -- Dependencia del test: el consumo por equivalente base (30/31, sql-core).
    IF to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL THEN
        RAISE NOTICE 'S-B OMITIDO: falta fn_descontar_ingredientes_elaborado_v2 (aplica antes 30/31). El DDL de este archivo ya quedo aplicado.';
        RETURN;
    END IF;

    -- Caso real medido: producto 219 "croqueta" (base Unidad 339, Caja 340 x24),
    -- receta por unidad = 216 -> 40, 218 -> 10
    --   fn_obtener_ingredientes_recursivos(219,1)  = [(216,40), (218,10)]
    --   fn_obtener_ingredientes_recursivos(219,24) = [(216,960),(218,240)]
    --   fn_cantidad_en_base(340, 1) = 24   (Caja x24)
    IF public.fn_cantidad_en_base(340, 1) <> 24 THEN
        RAISE NOTICE 'S-B OMITIDO: el fixture de produccion (presentacion 340 = Caja x24) no esta en este proyecto (fn_cantidad_en_base(340,1) = %).',
            public.fn_cantidad_en_base(340, 1);
        RETURN;
    END IF;

    -- Almacen con stock de los dos ingredientes
    SELECT la.id_almacen
      INTO v_id_almacen
      FROM public.app_dat_inventario_productos ip
      JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
     WHERE ip.id_producto IN (216, 218)
       AND la.deleted_at IS NULL
     GROUP BY la.id_almacen
     ORDER BY count(DISTINCT ip.id_producto) DESC, sum(ip.cantidad_final) DESC NULLS LAST
     LIMIT 1;

    IF v_id_almacen IS NULL THEN
        RAISE NOTICE 'S-B OMITIDO: no hay almacen con movimiento de los ingredientes 216/218 en este proyecto.';
        RETURN;
    END IF;

    v_disp216 := public.fn_stock_producto_almacen(216, v_id_almacen);
    v_disp218 := public.fn_stock_producto_almacen(218, v_id_almacen);

    -- Cuantas CAJAS completas caben (1 Caja = 24 base = 960 de 216 + 240 de 218)
    v_cajas := floor(LEAST(v_disp216 / (40 * 24), v_disp218 / (10 * 24)));

    IF v_cajas < 1 THEN
        RAISE NOTICE 'S-B OMITIDO: stock insuficiente para 1 Caja completa (disp 216=%, disp 218=%).',
            v_disp216, v_disp218;
        RETURN;
    END IF;

    v_base        := 24 * v_cajas;       -- equivalente base vendido
    v_esperado216 := 40 * v_base;
    v_esperado218 := 10 * v_base;

    v_antes216 := v_disp216;
    v_antes218 := v_disp218;

    -- (a) CONSUMO por equivalente base, como hace fn_pedir_item_cuenta_v2
    --     (p_cantidad := fn_cantidad_en_base(p_id_presentacion, p_cantidad))
    v_desc := public.fn_descontar_ingredientes_elaborado_v2(
        p_id_producto_elaborado := 219,
        p_cantidad              := v_base,
        p_id_almacen            := v_id_almacen,
        p_id_extraccion         := NULL,
        p_origen_cambio         := 4
    );

    IF (v_desc->>'status') <> 'success' THEN
        RAISE EXCEPTION 'S-B: el descuento fallo: %', v_desc;
    END IF;

    IF public.fn_stock_producto_almacen(216, v_id_almacen) <> v_antes216 - v_esperado216 THEN
        RAISE EXCEPTION 'S-B: 216 deberia bajar % (de % a %), quedo en %',
            v_esperado216, v_antes216, v_antes216 - v_esperado216,
            public.fn_stock_producto_almacen(216, v_id_almacen);
    END IF;
    IF public.fn_stock_producto_almacen(218, v_id_almacen) <> v_antes218 - v_esperado218 THEN
        RAISE EXCEPTION 'S-B: 218 deberia bajar % (de % a %), quedo en %',
            v_esperado218, v_antes218, v_antes218 - v_esperado218,
            public.fn_stock_producto_almacen(218, v_id_almacen);
    END IF;

    -- (b) DEVOLUCION simetrica con la _v2 (presentacion base, equivalente exacto)
    v_dev := public.fn_devolver_ingredientes_elaborado_v2(
        p_id_producto_elaborado := 219,
        p_cantidad              := v_base,
        p_id_almacen            := v_id_almacen,
        p_id_extraccion         := NULL,
        p_origen_cambio         := 4
    );

    IF (v_dev->>'status') <> 'success' THEN
        RAISE EXCEPTION 'S-B: la devolucion fallo: %', v_dev;
    END IF;

    IF public.fn_stock_producto_almacen(216, v_id_almacen) <> v_antes216 THEN
        RAISE EXCEPTION 'S-B: neto 216 <> 0 (% vs %)',
            public.fn_stock_producto_almacen(216, v_id_almacen), v_antes216;
    END IF;
    IF public.fn_stock_producto_almacen(218, v_id_almacen) <> v_antes218 THEN
        RAISE EXCEPTION 'S-B: neto 218 <> 0 (% vs %)',
            public.fn_stock_producto_almacen(218, v_id_almacen), v_antes218;
    END IF;

    -- (c) la devolucion fue a la presentacion BASE, no a una cascada por id
    SELECT c.nombre INTO v_pres_base
      FROM public.fn_presentaciones_producto(216) c
     WHERE c.es_base
     LIMIT 1;

    IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_dev->'movimientos') m
         WHERE (m->>'id_ingrediente')::bigint = 216
           AND m->>'presentacion' = v_pres_base) THEN
        RAISE EXCEPTION 'S-B: la devolucion de 216 no fue a la presentacion base (%): %',
            v_pres_base, v_dev->'movimientos';
    END IF;
END $test$;

ROLLBACK;

-- ############################################################################
-- SECCION S-C Â· Reverificacion: nada aplicado y md5 vivos intactos
--              (corre tambien en produccion con MCP lectura)
-- ############################################################################

SELECT
    to_regprocedure('public.fn_devolver_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)') IS NULL
        AS devolver_v2_no_creada,
    to_regprocedure('public.fn_cancelar_item_pedido_v2(bigint,text)') IS NULL
        AS cancelar_v2_no_creada,
    to_regprocedure('public.fn_eliminar_producto_orden_v2(bigint,uuid)') IS NULL
        AS eliminar_v2_no_creada,
    md5(pg_get_functiondef('public.fn_devolver_ingredientes_elaborado(bigint,numeric,bigint,bigint,integer)'::regprocedure))
        = '7a4a71902aae6719bcac5513a3db9027'  AS devolver_viva_intacta,
    md5(pg_get_functiondef('public.fn_cancelar_item_pedido(bigint,text)'::regprocedure))
        = 'a151a00bdc98a668eafc87eb14ac2761'  AS cancelar_viva_intacta,
    md5(pg_get_functiondef('public.fn_eliminar_producto_orden(bigint,uuid)'::regprocedure))
        = '0d658a6dbce1bb448c74d0012d053b4b'  AS eliminar_viva_intacta;
-- Esperado: true / true / true / true / true / true

-- ============================================================================
-- RESULTADO MEDIDO EN PRODUCCION (`vsieeihstajlrdvpuooh`, MCP read-only)
-- ============================================================================
--   Â· S-A: viva_intacta=true; cascada_pp_id_asc=1; suma_base_a_fila_fisica=2;
--          ultima_fila_sin_presentacion=1; ingredientes_receta_con_mas_de_una_pres=5;
--          ingredientes_en_recetas=103.
--   Â· Censo de las 5 cadenas: 217 azucar (Bulto x10 + Bolsa base),
--          219 croqueta (Caja x24 + Unidad), 220 pan (Caja x24 + Unidad),
--          239 perro caliente (Caja x24 + Unidad), 960 refresco (Caja x24 +
--          Blister x12 + Unidad base).
--   Â· Hoy la ultima fila del ledger en las ubicaciones destino es la base en
--     los 5 casos => la inflacion x factor de C7 esta latente.
--   Â· S-C: las tres `_v2` = NULL y los tres md5 vivos intactos.
--   Â· S-B NO se pudo correr contra produccion: el rol del MCP es
--     `supabase_read_only_user` (sin CREATE en public, sin EXECUTE en el guard);
--     queda listo para debug `qhprswhhfasrikhawjoz` o el SQL Editor, despues de
--     aplicar 45 y 30/31.
-- ============================================================================