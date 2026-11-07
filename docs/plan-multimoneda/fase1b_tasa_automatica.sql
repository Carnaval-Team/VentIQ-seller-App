-- ============================================================================
-- PRODUCCIÓN — Capa de tasa automática («el toque»)
-- ============================================================================
-- ESTE ES EL FICHERO QUE FALTABA. El de cron (`fase1d_cron_tasas.sql`) usa
-- estas funciones en su verificación, así que debe aplicarse DESPUÉS.
--
-- Orden correcto en producción:
--   1. ✅ fase1_catalogo_monedas.sql          (ya aplicado)
--   2. ⬜ ESTE fichero                        (fase1b_tasa_automatica.sql)
--   3. ⬜ fase1d_cron_tasas.sql               (cron del refresco)
--
-- Requisitos previos (verificados en producción el 2026-11-04):
--   * `public.monedas` con decimales/orden/es_base/es_sistema -> OK
--   * `public.tipos_moneda.codigo`                            -> OK
--   * fn_crear_moneda / fn_actualizar_moneda / fn_guardar_denominaciones /
--     fn_guardar_tasa_global / fn_tasa_cambio                 -> OK (5)
--   * Esquema `flow` con `tasa_cambio`, `tasa_factor`, `tasas_actuales`,
--     `tasas_refrescar`, `tasas_ingest`                        -> OK
--   * Extensión pg_net y pg_cron                               -> OK
--
-- Qué crea
-- --------
--   fn_tasa_automatica(origen, destino)  -> numeric | null
--   fn_tasa_automatica_estado()          -> jsonb (estado de la caché)
--   fn_tasas_refrescar(forzar)           -> dispara y vuelve (NO bloquea)
--   fn_tasas_ingerir()                   -> recoge respuestas pendientes
--   fn_tasa_cambio(...)                  -> se reemplaza para añadir el
--                                           escalón automático al final
--
-- Precedencia resultante de fn_tasa_cambio
-- ----------------------------------------
--   1. Tasa de la tienda (tasa_cambio_extraoficial, manual)
--   2. Tasa global       (tasas_conversion, manual)
--   3. Tasa automática   («el toque»)          <-- NUEVO
--   4. NULL -> el cobro en esa moneda se bloquea
--
-- La MANUAL siempre gana. Instalar esto NO cambia el comportamiento de ninguna
-- tienda. Para usar la automática en una moneda, basta con NO darle tasa manual.
--
-- ⚠️ En producción, `tasas_conversion` ya tiene USD->CUP = 900 (manual), así que
--    ese par seguirá usando 900. La automática entrará en EUR->CUP y MLC->CUP.
--
-- Cobertura del proveedor: SOLO USD, EUR y MLC (CAD y GBP devuelven NULL).
-- Cualquier moneda nueva necesitará tasa manual.
-- ============================================================================


-- ============================================================================
-- 1) fn_tasa_automatica — lectura blindada
-- ============================================================================
-- `public` no llama a `flow` directamente desde la app: este wrapper degrada a
-- NULL si el esquema `flow` no existe, para que el TPV nunca se rompa.
CREATE OR REPLACE FUNCTION public.fn_tasa_automatica(
  p_origen  text,
  p_destino text DEFAULT 'CUP'
) RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v numeric;
BEGIN
  BEGIN
    v := flow.tasa_factor(upper(trim(p_origen)), upper(trim(p_destino)));
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;

  RETURN NULLIF(v, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasa_automatica(text, text) TO authenticated;


-- ============================================================================
-- 2) fn_tasa_automatica_estado — estado de la caché para la UI
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_tasa_automatica_estado()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  BEGIN
    v := flow.tasas_actuales();
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  IF v IS NULL OR coalesce((v->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'disponible', true,
      'ok', false,
      'error', coalesce(v->>'error', 'Sin tasas en caché')
    );
  END IF;

  RETURN jsonb_build_object(
    'disponible', true,
    'ok', true,
    'fecha', v->'fecha',
    'hora', v->'hora',
    'fuente', v->'fuente',
    'actualizado', v->'actualizado',
    'vigente', v->'vigente',
    'tasas_cup', jsonb_build_object(
      'USD', nullif(v->'conversiones'->'USD'->>'CUP','')::numeric,
      'EUR', nullif(v->'conversiones'->'EUR'->>'CUP','')::numeric,
      'MLC', nullif(v->'conversiones'->'MLC'->>'CUP','')::numeric
    ),
    'monedas_cubiertas', (
      SELECT jsonb_agg(k ORDER BY k)
      FROM jsonb_object_keys(v->'conversiones') AS k
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasa_automatica_estado() TO authenticated;


-- ============================================================================
-- 3) fn_tasas_refrescar — dispara y vuelve (NO bloquea)
-- ============================================================================
-- El rol `authenticated` de Supabase tiene `statement_timeout = 8s`. El
-- proveedor tarda ~6 s, así que un sondeo con pg_sleep en Postgres quedaría al
-- borde del límite y abortaría con "canceling statement due to statement
-- timeout". Por eso aquí solo se dispara; el sondeo lo hace el cliente.
CREATE OR REPLACE FUNCTION public.fn_tasas_refrescar(
  p_forzar boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_r  jsonb;
  v_id bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede refrescar las tasas';
  END IF;

  BEGIN
    v_r := flow.tasas_refrescar(p_forzar);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  IF coalesce(v_r->>'estado','') = 'vigente' THEN
    RETURN public.fn_tasa_automatica_estado();
  END IF;

  v_id := nullif(v_r->>'request_id','')::bigint;

  RETURN jsonb_build_object(
    'disponible', true,
    'ok', true,
    'estado', 'solicitado',
    'request_id', v_id,
    'mensaje', 'Tasa solicitada al proveedor. Se recoge en unos segundos.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasas_refrescar(boolean) TO authenticated;


-- ============================================================================
-- 4) fn_tasas_ingerir — recoge las respuestas que ya llegaron
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_tasas_ingerir()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec record;
  v_res jsonb;
  v_n   int := 0;
  v_ok  int := 0;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede ingerir las tasas';
  END IF;

  BEGIN
    FOR v_rec IN
      SELECT request_id
      FROM flow.tasa_cambio_sondeo
      WHERE NOT ingerido
        AND creado_at <= now() - interval '2 seconds'
      ORDER BY request_id
      LIMIT 5
    LOOP
      v_n := v_n + 1;
      BEGIN
        v_res := flow.tasas_ingest(v_rec.request_id);
        IF coalesce(v_res->>'estado','') = 'ingerido' THEN
          v_ok := v_ok + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- una respuesta rota no debe tumbar el resto
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  RETURN public.fn_tasa_automatica_estado()
         || jsonb_build_object(
              'pendientes_procesados', v_n,
              'ingeridos', v_ok
            );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasas_ingerir() TO authenticated;


-- ============================================================================
-- 5) fn_tasa_cambio — añade el escalón AUTOMÁTICO
-- ============================================================================
-- Reemplaza la versión de la Fase 1. Misma firma, así que no hay sobrecargas.
CREATE OR REPLACE FUNCTION public.fn_tasa_cambio(
  p_moneda_origen  text,
  p_moneda_destino text DEFAULT 'CUP',
  p_id_tienda      bigint DEFAULT NULL,
  p_fecha          timestamptz DEFAULT now()
) RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_origen  text := upper(trim(p_moneda_origen));
  v_destino text := upper(trim(coalesce(p_moneda_destino,'CUP')));
  v_id_origen  bigint;
  v_id_destino bigint;
  v_tasa    numeric;
BEGIN
  IF v_origen = v_destino THEN
    RETURN 1;
  END IF;

  SELECT id INTO v_id_origen  FROM public.tipos_moneda WHERE codigo = v_origen;
  SELECT id INTO v_id_destino FROM public.tipos_moneda WHERE codigo = v_destino;

  -- 1) Tasa por tienda (manual)
  IF v_id_origen IS NOT NULL AND v_id_destino IS NOT NULL AND p_id_tienda IS NOT NULL THEN
    SELECT valor_cambio INTO v_tasa
    FROM public.tasa_cambio_extraoficial
    WHERE id_tienda = p_id_tienda
      AND id_moneda_origen = v_id_origen
      AND id_moneda_destino = v_id_destino
      AND activo
      AND created_at <= p_fecha
    ORDER BY created_at DESC
    LIMIT 1;
    IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
      RETURN v_tasa;
    END IF;
  END IF;

  -- 2) Tasa global manual
  SELECT tasa INTO v_tasa
  FROM public.tasas_conversion
  WHERE moneda_origen = v_origen
    AND moneda_destino = v_destino
    AND fecha_actualizacion <= p_fecha
  ORDER BY fecha_actualizacion DESC
  LIMIT 1;
  IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
    RETURN v_tasa;
  END IF;

  -- 3) Tasa automática («el toque»)
  v_tasa := public.fn_tasa_automatica(v_origen, v_destino);
  IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
    RETURN v_tasa;
  END IF;

  -- 4) Sin tasa
  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasa_cambio(text, text, bigint, timestamptz)
  TO authenticated;


-- ============================================================================
-- 6) VERIFICACIÓN
-- ============================================================================

-- 6.1 Las cinco funciones existen
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS argumentos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_tasa_automatica', 'fn_tasa_automatica_estado',
                    'fn_tasas_refrescar', 'fn_tasas_ingerir', 'fn_tasa_cambio')
ORDER BY p.proname;

-- 6.2 Estado de la caché automática
SELECT public.fn_tasa_automatica_estado() AS estado;

-- 6.3 Resolución de tasas. Esperado:
--     USD -> 900  (manual de tasas_conversion, gana)
--     EUR -> el valor del toque
--     MLC -> el valor del toque
--     CAD -> NULL (sin cobertura del proveedor)
SELECT public.fn_tasa_automatica('EUR','CUP') AS auto_eur_cup,
       public.fn_tasa_cambio('USD','CUP')     AS resolver_usd_cup,
       public.fn_tasa_cambio('EUR','CUP')     AS resolver_eur_cup,
       public.fn_tasa_cambio('MLC','CUP')     AS resolver_mlc_cup,
       public.fn_tasa_cambio('CAD','CUP')     AS resolver_cad_sin_cobertura,
       public.fn_tasa_cambio('CUP','CUP')     AS identidad;

-- 6.4 Regresión: los pagos no se tocan
SELECT count(*) AS pagos_total,
       count(*) FILTER (WHERE moneda = 'CUP') AS pagos_cup,
       count(*) FILTER (WHERE moneda = 'USD') AS pagos_usd
FROM public.app_dat_pago_venta;


-- ============================================================================
-- 7) Reversión
-- ============================================================================
-- Volver a la versión de la Fase 1 de fn_tasa_cambio (sin escalón automático):
--   reejecutar la definición de `fn_tasa_cambio` de fase1_catalogo_monedas.sql.
-- Las cuatro funciones nuevas pueden quedarse sin uso o eliminarse:
--   drop function if exists public.fn_tasas_ingerir();
--   drop function if exists public.fn_tasas_refrescar(boolean);
--   drop function if exists public.fn_tasa_automatica_estado();
--   drop function if exists public.fn_tasa_automatica(text, text);
--
-- Quitar estas funciones NO afecta a las tasas manuales ni al cobro actual.
-- ============================================================================