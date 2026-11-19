CREATE OR REPLACE FUNCTION public.sync_bundle(id_tienda_param bigint, id_tpv_param bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_categorias jsonb;
    v_promos jsonb;
    v_store_config jsonb;
    v_turno jsonb;
    v_id_seller bigint;
BEGIN
    -- Categorías visibles para el vendedor (reusa la función existente).
    SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
    INTO v_categorias
    FROM get_categorias_by_tienda_tpv(id_tienda_param, id_tpv_param) c;

    -- Promociones globales activas de la tienda (reusa función existente).
    SELECT COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
    INTO v_promos
    FROM fn_listar_promociones2(id_tienda_param, true) p;

    -- Configuración de la tienda (si existe).
    SELECT to_jsonb(cfg)
    INTO v_store_config
    FROM app_dat_configuracion_tienda cfg
    WHERE cfg.id_tienda = id_tienda_param
    LIMIT 1;

    -- Vendedor asociado al TPV para localizar su turno abierto.
    SELECT v.id
    INTO v_id_seller
    FROM app_dat_vendedor v
    WHERE v.id_tpv = id_tpv_param
      AND v.uuid = auth.uid()
    LIMIT 1;

    -- Turno abierto (estado = 1) del TPV/vendedor, si lo hay.
    IF v_id_seller IS NOT NULL THEN
        SELECT to_jsonb(t)
        INTO v_turno
        FROM app_dat_caja_turno t
        WHERE t.id_tpv = id_tpv_param
          AND t.id_vendedor = v_id_seller
          AND t.estado = 1
        ORDER BY t.fecha_apertura DESC NULLS LAST
        LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'categorias', v_categorias,
        'promociones_globales', v_promos,
        'store_config', v_store_config,
        'turno_abierto', v_turno,
        'synced_at', now()
    );
END;
$function$

