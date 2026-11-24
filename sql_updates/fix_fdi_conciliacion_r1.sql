-- Instala SOLO `fn_fdi_conciliacion` (R1) en una base donde la fase 1 no se aplicó
-- completa pero la fase 4 en adelante sí.
--
-- POR QUÉ NO SE APLICA `01_motor_dinero.sql` ENTERO:
--   ese script reescribe `_fdi_aplicar_movimiento`, `fn_fdi_vincular_recepcion`,
--   `fn_fdi_repartir_ganancia` y `fn_fdi_inversion_anular` con los cuerpos de la
--   fase 1. Si ya están aplicados 04/05/06b, esos cuerpos son MÁS NUEVOS (el
--   aplicador con `id_compra` y `tasa`, el vínculo con atribución al vínculo,
--   etc.), así que reejecutar 01 los devolvería a versiones viejas y rompería
--   pagos, recepciones y aportes.
--
--   La única pieza de la fase 1 que la fase 8 necesita es la conciliación, y es
--   autónoma: lee `fdi_dat_saldo` y `fdi_dat_movimiento` y llama a
--   `fn_user_can_access_tienda`. No depende de nada más del script 01.
--
-- Idempotente: CREATE OR REPLACE.
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_fdi_conciliacion(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_json jsonb;
BEGIN
    -- Sin sesión (service_role / editor SQL) se permite; con sesión, se exige acceso.
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    WITH s AS (
        SELECT id_cuenta, id_medio_pago, moneda, saldo
        FROM public.fdi_dat_saldo
        WHERE id_tienda = p_id_tienda
    ), m AS (
        SELECT id_cuenta, id_medio_pago, moneda,
               sum(monto) AS suma_mov, count(*) AS n_mov
        FROM public.fdi_dat_movimiento
        WHERE id_tienda = p_id_tienda
        GROUP BY 1, 2, 3
    ), u AS (
        SELECT DISTINCT ON (id_cuenta, id_medio_pago, moneda)
               id_cuenta, id_medio_pago, moneda, saldo_nuevo
        FROM public.fdi_dat_movimiento
        WHERE id_tienda = p_id_tienda
        ORDER BY id_cuenta, id_medio_pago, moneda, id DESC
    ), j AS (
        SELECT
            s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
            COALESCE(m.suma_mov, 0)  AS suma_mov,
            COALESCE(m.n_mov, 0)     AS n_mov,
            u.saldo_nuevo            AS ultimo_saldo_nuevo,
            round(s.saldo - COALESCE(m.suma_mov, 0), 2)   AS dif_saldo_vs_mov,
            round(s.saldo - COALESCE(u.saldo_nuevo, 0), 2) AS dif_saldo_vs_ultimo
        FROM s
        LEFT JOIN m USING (id_cuenta, id_medio_pago, moneda)
        LEFT JOIN u USING (id_cuenta, id_medio_pago, moneda)
    )
    SELECT jsonb_build_object(
        'id_tienda', p_id_tienda,
        'claves',    count(*),
        'descuadres', count(*) FILTER (
            WHERE abs(dif_saldo_vs_mov) >= 0.005
               OR abs(dif_saldo_vs_ultimo) >= 0.005),
        'filas', COALESCE(jsonb_agg(jsonb_build_object(
            'id_cuenta', id_cuenta,
            'id_medio_pago', id_medio_pago,
            'moneda', moneda,
            'saldo', saldo,
            'suma_movimientos', suma_mov,
            'n_movimientos', n_mov,
            'ultimo_saldo_nuevo', ultimo_saldo_nuevo,
            'dif_saldo_vs_mov', dif_saldo_vs_mov,
            'dif_saldo_vs_ultimo', dif_saldo_vs_ultimo,
            'ok', abs(dif_saldo_vs_mov) < 0.005 AND abs(dif_saldo_vs_ultimo) < 0.005
        ) ORDER BY id_cuenta, id_medio_pago, moneda), '[]'::jsonb)
    ) INTO v_json
    FROM j;

    RETURN v_json;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_conciliacion(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_conciliacion(bigint) TO authenticated;

COMMIT;

-- Comprobación: existe, es STABLE, es SECURITY DEFINER y da el mismo veredicto.
SELECT jsonb_pretty(jsonb_build_object(
  'existe', to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NOT NULL,
  'estable', (SELECT p.provolatile = 's' FROM pg_proc p
               WHERE p.oid = 'public.fn_fdi_conciliacion(bigint)'::regprocedure),
  'definer', (SELECT p.prosecdef FROM pg_proc p
               WHERE p.oid = 'public.fn_fdi_conciliacion(bigint)'::regprocedure),
  'conciliacion', public.fn_fdi_conciliacion((SELECT min(id_tienda) FROM public.fdi_dat_saldo))
)) AS estado;