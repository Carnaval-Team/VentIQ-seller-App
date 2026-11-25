-- ============================================================================
-- Hotfix: search_path de *_m01 / helpers de alineación
-- ============================================================================
-- Síntoma (app nueva): al completar orden desde el detalle,
-- "relation app_dat_estado_operacion does not exist".
--
-- Causa: las *_m01 tienen SET search_path TO pg_catalog. Al llamar a
-- funciones legacy SIN search_path propio (p. ej.
-- fn_registrar_cambio_estado_operacion en main), heredan pg_catalog y
-- no resuelven tablas de public. En newa esa función ya trae
-- search_path=pg_catalog, public; en main no.
--
-- Igual riesgo: apertura → registrar_apertura_turno_v3, egreso →
-- registrar_egreso_parcial_v2, cierre → fn_cerrar_turno_tpv.
--
-- Arreglo aditivo: solo ALTER de funciones *_m01 / helpers nuevos.
-- No toca cuerpos ni nombres antiguos.
-- ============================================================================

ALTER FUNCTION public.fn_turno_alinear_fecha_apertura(bigint, timestamptz)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_alinear_apertura_turno_offline(bigint, timestamptz)
  SET search_path TO pg_catalog, public;

ALTER FUNCTION public.fn_apertura_turno_offline_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_apertura_turno_offline_usd_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz, numeric)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_apertura_turno_offline_monedas_m01(uuid, bigint, bigint, uuid, boolean, jsonb, jsonb, text, timestamptz)
  SET search_path TO pg_catalog, public;

ALTER FUNCTION public.fn_cerrar_turno_offline_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamptz)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_cerrar_turno_offline_usd_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamptz, numeric)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_cerrar_turno_offline_monedas_m01(uuid, bigint, uuid, jsonb, jsonb, text, timestamptz)
  SET search_path TO pg_catalog, public;

ALTER FUNCTION public.fn_registrar_egreso_offline_m01(uuid, bigint, numeric, varchar, varchar, text, smallint, uuid)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_registrar_egreso_offline_v2_m01(uuid, bigint, numeric, varchar, varchar, text, smallint, uuid, text)
  SET search_path TO pg_catalog, public;

ALTER FUNCTION public.fn_registrar_venta_offline_v4_m01(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamptz, jsonb)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_registrar_pago_venta_offline_m01(uuid, bigint, jsonb, uuid)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_registrar_cambio_estado_offline_m01(uuid, bigint, smallint, uuid)
  SET search_path TO pg_catalog, public;
ALTER FUNCTION public.fn_cambiar_estado_comanda_item_offline_m01(uuid, bigint, smallint)
  SET search_path TO pg_catalog, public;

-- Verificación
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
    INTO v_bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (
      p.proname LIKE '%\_m01' ESCAPE '\'
      OR p.proname IN (
        'fn_turno_alinear_fecha_apertura',
        'fn_alinear_apertura_turno_offline'
      )
    )
    AND EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c WHERE c = 'search_path=pg_catalog'
    );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Quedan search_path solo pg_catalog en: %', v_bad;
  END IF;
END $$;
