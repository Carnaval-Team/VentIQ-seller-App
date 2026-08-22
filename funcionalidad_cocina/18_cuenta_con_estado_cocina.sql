-- ============================================================================
-- 18 · Fase 2 · Exponer el estado de cocina en la cuenta abierta
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- POR QUE
-- -------
-- El 13 anadio a app_dat_mesa_cuenta_item los campos de servicio (origen_stock,
-- id_cocina, id_comanda_item, estado_servicio, stock_movido) y el 14 los rellena
-- al pedir. Pero fn_obtener_cuenta_mesa -- la RPC que alimenta la pantalla de
-- cuenta del vendedor -- no devuelve ninguno.
--
-- Sin esto la UI no puede cumplir el punto 2.4 del plan:
--   "Estado servido / en cocina en la linea de la cuenta"
--
-- QUE SE AGREGA A CADA ITEM
-- -------------------------
--   origen_stock      tpv | tanda | al_pedido | servicio (NULL = linea legado)
--   id_cocina         cocina destino
--   cocina_nombre     para mostrar "Cocina caliente" en vez de un id
--   estado_servicio   1 pendiente, 2 en preparacion, 3 listo, 4 entregado, 5 cancelado
--   stock_movido      si el inventario ya salio al pedir
--   id_comanda_item   linea de comanda asociada (la ultima, si la linea consolida)
--   comanda_numero    numero visible de la comanda ("marchando la 12")
--   comanda_estado    estado de la comanda completa, para agrupar en la UI
--
-- Y a nivel de cuenta, dos contadores para decidir si se puede cerrar la nota:
--   items_en_cocina   lineas con comanda pendiente o en preparacion
--   items_listos      lineas listas para servir pero aun no entregadas
--
-- El plan (2.3) pide "avisar o bloquear si hay comandas no servidas": con
-- items_en_cocina la UI puede avisar sin tener que consultar las comandas aparte.
--
-- ESTRATEGIA
-- ----------
-- CREATE OR REPLACE completo con el cuerpo exportado de produccion, anadiendo
-- solo campos al jsonb. No se cambia ninguna consulta existente ni el orden de
-- los items. Los nombres que ya devolvia se conservan tal cual para no romper
-- MesaCuentaItem.fromJson.
--
-- Se usa LEFT JOIN a cocina y comanda: una linea de barra no tiene ni una ni
-- otra y debe seguir apareciendo igual.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 18.1 fn_obtener_cuenta_mesa con estado de cocina
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_obtener_cuenta_mesa(p_id_cuenta bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'id', c.id,
        'id_mesa', c.id_mesa,
        'mesa_numero', m.numero,
        'mesa_zona', m.zona,
        'id_tpv', c.id_tpv,
        'id_vendedor', c.id_vendedor,
        'numero_comensales', c.numero_comensales,
        'notas', c.notas,
        'estado', c.estado,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'items', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', i.id,
                'id_producto', i.id_producto,
                'producto_nombre', p.denominacion,
                'producto_sku', i.sku_producto,
                'producto_es_elaborado', p.es_elaborado,
                'producto_es_servicio', p.es_servicio,
                'id_variante', i.id_variante,
                'id_opcion_variante', i.id_opcion_variante,
                'variante_nombre',
                    CASE WHEN i.id_opcion_variante IS NOT NULL THEN
                        (SELECT ao.valor FROM public.app_dat_atributo_opcion ao
                         WHERE ao.id = i.id_opcion_variante LIMIT 1)
                    ELSE NULL END,
                'id_presentacion', i.id_presentacion,
                'presentacion_nombre',
                    CASE WHEN i.id_presentacion IS NOT NULL THEN
                        (SELECT pr.denominacion FROM public.app_nom_presentacion pr
                         WHERE pr.id = i.id_presentacion LIMIT 1)
                    ELSE NULL END,
                'id_ubicacion', i.id_ubicacion,
                'ubicacion_nombre',
                    CASE WHEN i.id_ubicacion IS NOT NULL THEN
                        (SELECT la.denominacion FROM public.app_dat_layout_almacen la
                         WHERE la.id = i.id_ubicacion LIMIT 1)
                    ELSE NULL END,
                'cantidad', i.cantidad,
                'precio_unitario', i.precio_unitario,
                'precio_base', i.precio_base,
                'subtotal', (i.cantidad * i.precio_unitario)::numeric,
                'id_metodo_pago', i.id_metodo_pago,
                'promotion_data', i.promotion_data,
                'inventory_data', i.inventory_data,
                'notas', i.notas,
                'sku_producto', i.sku_producto,
                'sku_ubicacion', i.sku_ubicacion,
                'created_at', i.created_at,
                -- ══════════════════════════════════════════════════════════
                -- FASE 2 · estado de cocina y de servicio de la linea
                -- ══════════════════════════════════════════════════════════
                'origen_stock', i.origen_stock,
                'id_cocina', i.id_cocina,
                'cocina_nombre', ck.denominacion,
                'estado_servicio', i.estado_servicio,
                'stock_movido', i.stock_movido,
                'id_comanda_item', i.id_comanda_item,
                'comanda_numero', co.numero,
                'comanda_estado', co.estado
            ) ORDER BY i.created_at ASC)
            FROM public.app_dat_mesa_cuenta_item i
            LEFT JOIN public.app_dat_producto p  ON p.id = i.id_producto
            LEFT JOIN public.app_dat_cocina ck   ON ck.id = i.id_cocina
            LEFT JOIN public.app_dat_comanda_item ci ON ci.id = i.id_comanda_item
            LEFT JOIN public.app_dat_comanda co  ON co.id = ci.id_comanda
            WHERE i.id_cuenta = c.id
        ), '[]'::jsonb),
        'total', COALESCE((
            SELECT SUM(i.cantidad * i.precio_unitario)
            FROM public.app_dat_mesa_cuenta_item i
            WHERE i.id_cuenta = c.id
        ), 0)::numeric,
        -- ══════════════════════════════════════════════════════════════════
        -- FASE 2 · contadores para decidir si se puede cerrar la nota.
        -- El plan (2.3): "avisar o bloquear si hay comandas no servidas".
        -- ══════════════════════════════════════════════════════════════════
        'items_en_cocina', COALESCE((
            SELECT count(*)
            FROM public.app_dat_mesa_cuenta_item i
            JOIN public.app_dat_comanda_item ci ON ci.id = i.id_comanda_item
            WHERE i.id_cuenta = c.id
              AND ci.estado IN (1, 2)
        ), 0),
        'items_listos', COALESCE((
            SELECT count(*)
            FROM public.app_dat_mesa_cuenta_item i
            JOIN public.app_dat_comanda_item ci ON ci.id = i.id_comanda_item
            WHERE i.id_cuenta = c.id
              AND ci.estado = 3
        ), 0)
    ) INTO v_result
    FROM public.app_dat_mesa_cuenta_abierta c
    LEFT JOIN public.app_dat_mesas m ON m.id = c.id_mesa
    WHERE c.id = p_id_cuenta;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Cuenta % no encontrada', p_id_cuenta USING ERRCODE = 'P0001';
    END IF;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtener_cuenta_mesa(bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Debe exponer los campos nuevos y conservar los viejos
SELECT
    (p.prosrc LIKE '%origen_stock%')      AS expone_origen,
    (p.prosrc LIKE '%estado_servicio%')   AS expone_estado_servicio,
    (p.prosrc LIKE '%cocina_nombre%')     AS expone_cocina_nombre,
    (p.prosrc LIKE '%comanda_numero%')    AS expone_comanda,
    (p.prosrc LIKE '%items_en_cocina%')   AS expone_contadores,
    (p.prosrc LIKE '%promotion_data%')    AS conserva_promotion,
    (p.prosrc LIKE '%variante_nombre%')   AS conserva_variante
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_obtener_cuenta_mesa';
