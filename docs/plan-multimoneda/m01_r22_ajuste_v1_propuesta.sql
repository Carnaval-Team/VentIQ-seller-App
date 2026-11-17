BEGIN;

-- BORRADOR MC-044. NO EJECUTAR en main.
-- Una devolucion nueva apunta a la linea original y agrega una fila.
-- No borra la extraccion ni reescribe el cobro. No consulta Carnaval
-- ni recalcula el precio con el catalogo de hoy.

SET LOCAL app.m01_r22_ajuste_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r22_ajuste_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-044: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regclass('public.app_dat_ajuste_linea_v1') IS NOT NULL THEN
        RAISE EXCEPTION 'El ajuste v1 ya existe';
    END IF;
END;
$preflight$;

CREATE TABLE public.app_dat_ajuste_linea_v1 (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda bigint NOT NULL,
    id_extraccion bigint NOT NULL,
    id_linea_cliente uuid NOT NULL,
    moneda text NOT NULL,
    monto_nativo numeric NOT NULL,
    motivo text NOT NULL,
    version_monetaria text NOT NULL DEFAULT 'producto-v1',
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT m01_ajuste_moneda CHECK (moneda IN ('CUP', 'USD')),
    CONSTRAINT m01_ajuste_version CHECK (version_monetaria = 'producto-v1')
);

ALTER TABLE public.app_dat_ajuste_linea_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_ajuste_linea_v1 FORCE ROW LEVEL SECURITY;

CREATE POLICY app_dat_ajuste_linea_v1_select
    ON public.app_dat_ajuste_linea_v1
    FOR SELECT TO authenticated
    USING (public.fn_config_tienda_puede_leer(id_tienda));

CREATE POLICY app_dat_ajuste_linea_v1_sin_escritura
    ON public.app_dat_ajuste_linea_v1
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

CREATE FUNCTION public.fn_m01_devolver_linea_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_linea record;
    v_tienda bigint;
    v_id bigint;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    SELECT e.id, e.id_linea_cliente, e.moneda_venta, e.importe_neto_nativo, o.id_tienda
      INTO v_linea
    FROM public.app_dat_extraccion_productos e
    JOIN public.app_dat_operaciones o ON o.id = e.id_operacion
    WHERE e.id = (p_solicitud->>'id_extraccion')::bigint
      AND e.version_monetaria = 'producto-v1';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_tienda := v_linea.id_tienda;
    IF public.fn_config_tienda_puede_leer(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_solicitud->>'moneda' IS DISTINCT FROM v_linea.moneda_venta THEN
        RAISE EXCEPTION 'MONEDA_DISTINTA' USING ERRCODE = '23514';
    END IF;
    IF COALESCE(p_solicitud->>'motivo', '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.app_dat_ajuste_linea_v1 (
        id_tienda, id_extraccion, id_linea_cliente, moneda, monto_nativo, motivo
    ) VALUES (
        v_tienda, v_linea.id, v_linea.id_linea_cliente, v_linea.moneda_venta,
        (p_solicitud->>'monto_nativo')::numeric, p_solicitud->>'motivo'
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('status', 'success', 'id_ajuste', v_id, 'moneda', v_linea.moneda_venta);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_devolver_linea_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_devolver_linea_v1(jsonb) TO authenticated;

COMMIT;
