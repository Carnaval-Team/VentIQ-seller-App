-- ============================================================================
-- PRODUCCIÓN — FASE 3.1: esquema de pago multimoneda (SIN tocar la app)
-- ============================================================================
-- Incluye las tres sub-fases aplicadas y verificadas en `newa`:
--   3.1  esquema + RPC genérica
--   3.1b trigger: toda tienda nueva nace con CUP y USD
--   3.1c guardas: `_v1` y `_v2` dejan de coaccionar monedas en silencio
--
-- ORDEN OBLIGATORIO: 1 → 2 → 3 → 4 → 5 → 6 (tal como está el fichero).
--
-- Depende de: fase1_catalogo_monedas.sql, fase1b_tasa_automatica.sql,
--             fase2_monedas_por_tienda.sql   (todos aplicados ya)
--
-- ⚠️ NO APLICADO EN PRODUCCIÓN. En `newa` está aplicado y verificado.
--
-- ─── POR QUÉ ES SEGURO APLICARLO SIN CAMBIAR LA APP ──────────────────────────
--   * La app desplegada sigue llamando a `fn_registrar_pago_venta_v2`, que NO se
--     elimina. Su comportamiento para CUP y USD es idéntico (verificado).
--   * Quitar el CHECK solo AMPLÍA lo permitido.
--   * La app solo envía CUP/USD, así que las nuevas guardas de 3.1c nunca
--     se disparan con el cliente actual.
--   * Ninguna función de lectura se modifica.
--
-- ─── MEDIDO EN PRODUCCIÓN ANTES DE ESCRIBIR ESTO (2026-11-04) ────────────────
--   * `app_dat_pago_venta`: 129.373 pagos · 0 en monedas ≠ CUP/USD · 666 con
--     `monto_cup_equivalente` NULL.
--   * `app_dat_tienda`: 148 tiendas · todas con config en
--     `app_dat_tienda_moneda` (296 filas) · 0 sin config.
--   * Sin triggers sobre `app_dat_pago_venta`.
--
-- ─── RIESGO CRÍTICO QUE ESTO CIERRA (R1 de la auditoría) ─────────────────────
--   `_v1` y `_v2` hacían `v_moneda := CASE WHEN = 'USD' THEN 'USD' ELSE 'CUP'`.
--   Si un cliente nuevo enviaba EUR y caía al fallback, el servidor guardaba
--   una fila moneda='CUP' con el importe nativo como equivalente: corrupción
--   SILENCIOSA, sin error. Ahora lanzan excepción explícita.
--   Afectaba también al camino offline: `fn_registrar_pago_venta_offline`
--   delega en `_v1`.
-- ============================================================================


-- ############################################################################
-- 1) Fuera la lista fija de monedas
-- ############################################################################
ALTER TABLE public.app_dat_pago_venta
  DROP CONSTRAINT IF EXISTS app_dat_pago_venta_moneda_check;


-- ############################################################################
-- 2) Tasa genérica (moneda nativa -> CUP)
-- ############################################################################
ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS tasa_cambio numeric;

UPDATE public.app_dat_pago_venta
SET tasa_cambio = COALESCE(tasa_usd, 1)
WHERE tasa_cambio IS NULL;


-- ############################################################################
-- 3) Integridad: la moneda debe existir en el catálogo
-- ############################################################################
-- `moneda` era TEXT. Se pasa a character(3) para que la FK encaje EXACTAMENTE
-- con `monedas.codigo`, que es character(3). Con varchar(3) la FK no valida.
ALTER TABLE public.app_dat_pago_venta
  ALTER COLUMN moneda TYPE character(3);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'app_dat_pago_venta_moneda_fkey'
      AND conrelid = 'public.app_dat_pago_venta'::regclass
  ) THEN
    ALTER TABLE public.app_dat_pago_venta
      ADD CONSTRAINT app_dat_pago_venta_moneda_fkey
      FOREIGN KEY (moneda) REFERENCES public.monedas(codigo);
  END IF;
END $$;


-- ############################################################################
-- 4) [3.1b] Toda tienda nueva nace con CUP y USD
-- ############################################################################
-- `fn_registrar_pago_venta_v3` exige que la tienda acepte la moneda. Las 148
-- tiendas actuales ya tienen config, pero una tienda NUEVA nacería sin filas y
-- no podría registrar ningún pago.
CREATE OR REPLACE FUNCTION public.fn_seed_tienda_monedas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_dat_tienda_moneda (id_tienda, moneda, activo, orden)
  SELECT NEW.id, m.codigo, true,
         CASE m.codigo WHEN 'CUP' THEN 10 WHEN 'USD' THEN 20 ELSE 100 END
  FROM public.monedas m
  WHERE m.codigo IN ('CUP', 'USD')
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seed_tienda_monedas ON public.app_dat_tienda;

CREATE TRIGGER trg_seed_tienda_monedas
AFTER INSERT ON public.app_dat_tienda
FOR EACH ROW
EXECUTE FUNCTION public.fn_seed_tienda_monedas();


-- ############################################################################
-- 5) [3.1] RPC genérica e idempotente — fn_registrar_pago_venta_v3
-- ############################################################################
-- Misma semántica que `_v2` (borra y reescribe los pagos no liquidados) pero:
--   * acepta CUALQUIER código del catálogo;
--   * acepta `tasa_cambio` (y `tasa_usd` como alias de compatibilidad);
--   * valida catálogo y que la tienda acepte esa moneda;
--   * rellena `tasa_cambio` y sigue rellenando `tasa_usd` sólo para USD.
--
-- ⚠️ NO redondea el equivalente a propósito. La app envía USD con toda su
--    precisión (9.090909090909092 × 550 = 5000.0000…). Redondear dejaría la
--    suma por debajo de `importe_total` y la venta quedaría `es_pagada=false`.
CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_v3(
  p_id_operacion_venta bigint,
  p_pagos jsonb
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pago            JSONB;
  v_importe_total   NUMERIC;
  v_total_pagos_cup NUMERIC := 0;
  v_uuid_usuario    UUID;
  v_id_tienda       BIGINT;
  v_id_medio_pago   SMALLINT;
  v_moneda          TEXT;
  v_tasa            NUMERIC;
  v_monto           NUMERIC;
  v_monto_cup       NUMERIC;
BEGIN
  SELECT ov.importe_total, o.uuid, o.id_tienda
  INTO v_importe_total, v_uuid_usuario, v_id_tienda
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  WHERE ov.id_operacion = p_id_operacion_venta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Venta con id_operacion % no encontrada', p_id_operacion_venta;
  END IF;
  IF v_importe_total IS NULL THEN
    RAISE EXCEPTION 'La venta no tiene un importe_total definido';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_dat_vendedor WHERE uuid = v_uuid_usuario) THEN
    RAISE EXCEPTION 'El usuario que creó la venta no está registrado como vendedor';
  END IF;
  IF p_pagos IS NULL OR jsonb_typeof(p_pagos) <> 'array' THEN
    RETURN FALSE;
  END IF;

  DELETE FROM public.app_dat_pago_venta
  WHERE id_operacion_venta = p_id_operacion_venta
    AND id_liquidacion IS NULL;

  FOR v_pago IN SELECT value FROM jsonb_array_elements(p_pagos)
  LOOP
    v_id_medio_pago := (v_pago->>'id_medio_pago')::SMALLINT;
    v_moneda := upper(trim(coalesce(v_pago->>'moneda', 'CUP')));
    v_monto  := COALESCE(NULLIF(v_pago->>'monto', '')::NUMERIC, 0);

    IF NOT EXISTS (SELECT 1 FROM public.app_nom_medio_pago
                   WHERE id = v_id_medio_pago AND es_activo = TRUE) THEN
      RAISE EXCEPTION 'Medio de pago con id % no existe o está inactivo', v_id_medio_pago;
    END IF;
    IF v_monto <= 0 THEN
      RAISE EXCEPTION 'El monto del pago debe ser mayor que cero';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.monedas
                   WHERE codigo = v_moneda AND activo) THEN
      RAISE EXCEPTION 'La moneda % no existe o no está activa en el catálogo', v_moneda;
    END IF;

    IF v_id_tienda IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda_moneda
                     WHERE id_tienda = v_id_tienda
                       AND moneda = v_moneda
                       AND activo) THEN
        RAISE EXCEPTION 'La tienda % no acepta pagos en %', v_id_tienda, v_moneda;
      END IF;
    END IF;

    IF v_moneda = 'CUP' THEN
      v_tasa := 1;
    ELSE
      v_tasa := COALESCE(
        NULLIF(v_pago->>'tasa_cambio', '')::NUMERIC,
        NULLIF(v_pago->>'tasa_usd', '')::NUMERIC
      );
      IF COALESCE(v_tasa, 0) <= 0 THEN
        RAISE EXCEPTION 'La tasa de cambio de % debe ser mayor que cero', v_moneda;
      END IF;
    END IF;

    v_monto_cup := v_monto * v_tasa;
    v_total_pagos_cup := v_total_pagos_cup + v_monto_cup;

    INSERT INTO public.app_dat_pago_venta (
      id_operacion_venta, id_medio_pago, monto, referencia_pago,
      id_institucion_financiera, creado_por, tipo_pago,
      importe_sin_descuento, moneda, tasa_cambio, tasa_usd,
      monto_cup_equivalente
    ) VALUES (
      p_id_operacion_venta, v_id_medio_pago, v_monto,
      NULLIF(v_pago->>'referencia_pago', ''),
      NULLIF(v_pago->>'id_institucion_financiera', '')::BIGINT,
      v_uuid_usuario,
      COALESCE(NULLIF(v_pago->>'tipo_pago', '')::BIGINT, 1),
      NULLIF(v_pago->>'importe_sin_descuento', '')::NUMERIC,
      v_moneda::character(3),
      v_tasa,
      CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END,  -- legacy
      v_monto_cup
    );
  END LOOP;

  IF v_total_pagos_cup >= v_importe_total THEN
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = TRUE
    WHERE id_operacion = p_id_operacion_venta;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_v3(bigint, jsonb)
  TO authenticated;


-- ############################################################################
-- 6) [3.1c] `_v1` y `_v2` rechazan monedas nuevas en vez de coaccionarlas
-- ############################################################################
-- Ver cabecera (R1). Se reproduce el cuerpo desplegado completo cambiando SOLO
-- la normalización de moneda.

CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta(
  p_id_operacion_venta bigint,
  p_pagos jsonb
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pago JSONB;
  v_importe_total NUMERIC;
  v_total_pagos_cup NUMERIC := 0;
  v_uuid_usuario UUID;
  v_id_medio_pago SMALLINT;
  v_moneda TEXT;
  v_tasa NUMERIC;
  v_monto NUMERIC;
  v_monto_cup NUMERIC;
BEGIN
  SELECT ov.importe_total, o.uuid
  INTO v_importe_total, v_uuid_usuario
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  WHERE ov.id_operacion = p_id_operacion_venta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Venta con id_operacion % no encontrada', p_id_operacion_venta;
  END IF;
  IF v_importe_total IS NULL THEN
    RAISE EXCEPTION 'La venta no tiene un importe_total definido';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_dat_vendedor WHERE uuid = v_uuid_usuario) THEN
    RAISE EXCEPTION 'El usuario que creó la venta no está registrado como vendedor';
  END IF;
  IF p_pagos IS NULL OR jsonb_typeof(p_pagos) <> 'array' THEN
    RETURN FALSE;
  END IF;

  FOR v_pago IN SELECT value FROM jsonb_array_elements(p_pagos)
  LOOP
    v_id_medio_pago := (v_pago->>'id_medio_pago')::SMALLINT;

    v_moneda := UPPER(COALESCE(v_pago->>'moneda', 'CUP'));
    IF v_moneda NOT IN ('CUP', 'USD') THEN
      RAISE EXCEPTION
        'fn_registrar_pago_venta solo admite CUP y USD (recibido: %). Usa fn_registrar_pago_venta_v3 para multimoneda.',
        v_moneda;
    END IF;

    v_tasa := NULLIF(v_pago->>'tasa_usd', '')::NUMERIC;
    v_monto := COALESCE(NULLIF(v_pago->>'monto', '')::NUMERIC, 0);

    IF NOT EXISTS (
      SELECT 1 FROM public.app_nom_medio_pago
      WHERE id = v_id_medio_pago AND es_activo = TRUE
    ) THEN
      RAISE EXCEPTION 'Medio de pago con id % no existe o está inactivo', v_id_medio_pago;
    END IF;
    IF v_monto <= 0 THEN
      RAISE EXCEPTION 'El monto del pago debe ser mayor que cero';
    END IF;
    IF v_moneda = 'USD' AND COALESCE(v_tasa, 0) <= 0 THEN
      RAISE EXCEPTION 'La tasa USD debe ser mayor que cero';
    END IF;

    v_monto_cup := CASE WHEN v_moneda = 'USD' THEN v_monto * v_tasa ELSE v_monto END;
    v_total_pagos_cup := v_total_pagos_cup + v_monto_cup;

    INSERT INTO public.app_dat_pago_venta (
      id_operacion_venta, id_medio_pago, monto, referencia_pago,
      id_institucion_financiera, creado_por, tipo_pago,
      importe_sin_descuento, moneda, tasa_usd, monto_cup_equivalente
    ) VALUES (
      p_id_operacion_venta, v_id_medio_pago, v_monto,
      NULLIF(v_pago->>'referencia_pago', ''),
      NULLIF(v_pago->>'id_institucion_financiera', '')::BIGINT,
      v_uuid_usuario,
      COALESCE(NULLIF(v_pago->>'tipo_pago', '')::BIGINT, 1),
      NULLIF(v_pago->>'importe_sin_descuento', '')::NUMERIC,
      v_moneda::character(3),
      CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END,
      v_monto_cup
    );
  END LOOP;

  IF v_total_pagos_cup >= v_importe_total THEN
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = TRUE
    WHERE id_operacion = p_id_operacion_venta;
  END IF;

  RETURN TRUE;
END;
$$;


CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_v2(
  p_id_operacion_venta bigint,
  p_pagos jsonb
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pago JSONB;
  v_importe_total NUMERIC;
  v_total_pagos_cup NUMERIC := 0;
  v_uuid_usuario UUID;
  v_id_medio_pago SMALLINT;
  v_moneda TEXT;
  v_tasa NUMERIC;
  v_monto NUMERIC;
  v_monto_cup NUMERIC;
BEGIN
  SELECT ov.importe_total, o.uuid
  INTO v_importe_total, v_uuid_usuario
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  WHERE ov.id_operacion = p_id_operacion_venta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Venta con id_operacion % no encontrada', p_id_operacion_venta;
  END IF;
  IF v_importe_total IS NULL THEN
    RAISE EXCEPTION 'La venta no tiene un importe_total definido';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_dat_vendedor WHERE uuid = v_uuid_usuario) THEN
    RAISE EXCEPTION 'El usuario que creó la venta no está registrado como vendedor';
  END IF;
  IF p_pagos IS NULL OR jsonb_typeof(p_pagos) <> 'array' THEN
    RETURN FALSE;
  END IF;

  DELETE FROM public.app_dat_pago_venta
  WHERE id_operacion_venta = p_id_operacion_venta
    AND id_liquidacion IS NULL;

  FOR v_pago IN SELECT value FROM jsonb_array_elements(p_pagos)
  LOOP
    v_id_medio_pago := (v_pago->>'id_medio_pago')::SMALLINT;

    v_moneda := UPPER(COALESCE(v_pago->>'moneda', 'CUP'));
    IF v_moneda NOT IN ('CUP', 'USD') THEN
      RAISE EXCEPTION
        'fn_registrar_pago_venta_v2 solo admite CUP y USD (recibido: %). Usa fn_registrar_pago_venta_v3 para multimoneda.',
        v_moneda;
    END IF;

    v_tasa := NULLIF(v_pago->>'tasa_usd', '')::NUMERIC;
    v_monto := COALESCE(NULLIF(v_pago->>'monto', '')::NUMERIC, 0);

    IF NOT EXISTS (
      SELECT 1 FROM public.app_nom_medio_pago
      WHERE id = v_id_medio_pago AND es_activo = TRUE
    ) THEN
      RAISE EXCEPTION 'Medio de pago con id % no existe o está inactivo', v_id_medio_pago;
    END IF;
    IF v_monto <= 0 THEN
      RAISE EXCEPTION 'El monto del pago debe ser mayor que cero';
    END IF;
    IF v_moneda = 'USD' AND COALESCE(v_tasa, 0) <= 0 THEN
      RAISE EXCEPTION 'La tasa USD debe ser mayor que cero';
    END IF;

    v_monto_cup := CASE WHEN v_moneda = 'USD' THEN v_monto * v_tasa ELSE v_monto END;
    v_total_pagos_cup := v_total_pagos_cup + v_monto_cup;

    INSERT INTO public.app_dat_pago_venta (
      id_operacion_venta, id_medio_pago, monto, referencia_pago,
      id_institucion_financiera, creado_por, tipo_pago,
      importe_sin_descuento, moneda, tasa_usd, monto_cup_equivalente
    ) VALUES (
      p_id_operacion_venta, v_id_medio_pago, v_monto,
      NULLIF(v_pago->>'referencia_pago', ''),
      NULLIF(v_pago->>'id_institucion_financiera', '')::BIGINT,
      v_uuid_usuario,
      COALESCE(NULLIF(v_pago->>'tipo_pago', '')::BIGINT, 1),
      NULLIF(v_pago->>'importe_sin_descuento', '')::NUMERIC,
      v_moneda::character(3),
      CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END,
      v_monto_cup
    );
  END LOOP;

  IF v_total_pagos_cup >= v_importe_total THEN
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = TRUE
    WHERE id_operacion = p_id_operacion_venta;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta(bigint, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_v2(bigint, jsonb) TO authenticated;


-- ############################################################################
-- 7) VERIFICACIÓN
-- ############################################################################

-- 7.1 Esquema
SELECT
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid='public.app_dat_pago_venta'::regclass
      AND conname='app_dat_pago_venta_moneda_check')  AS check_eliminado,   -- 0
  (SELECT data_type || '(' || coalesce(character_maximum_length::text,'') || ')'
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='app_dat_pago_venta'
      AND column_name='moneda')                       AS tipo_moneda,      -- character(3)
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid='public.app_dat_pago_venta'::regclass
      AND conname='app_dat_pago_venta_moneda_fkey')   AS fk_moneda,        -- 1
  (SELECT count(*) FROM public.app_dat_pago_venta
    WHERE tasa_cambio IS NULL)                        AS tasa_nula,        -- 0
  (SELECT count(*) FROM pg_trigger
    WHERE tgrelid='public.app_dat_tienda'::regclass
      AND tgname='trg_seed_tienda_monedas'
      AND NOT tgisinternal)                           AS trigger_tienda;   -- 1

-- 7.2 Las tres RPC existen y las guardas están puestas
SELECT p.proname,
       (position('solo admite CUP y USD' in pg_get_functiondef(p.oid)) > 0) AS guarda,
       (position('= ''USD'' THEN ''USD''' in pg_get_functiondef(p.oid)) > 0) AS coaccion
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('fn_registrar_pago_venta','fn_registrar_pago_venta_v2',
                    'fn_registrar_pago_venta_v3')
ORDER BY p.proname;
-- Esperado: _v1 y _v2 con guarda=true y coaccion=false; _v3 sin guarda (es genérica).

-- 7.3 Regresión de pagos (no debe cambiar nada)
SELECT count(*) AS pagos,
       count(*) FILTER (WHERE moneda='CUP') AS cup,
       count(*) FILTER (WHERE moneda='USD') AS usd,
       count(*) FILTER (WHERE moneda NOT IN ('CUP','USD')) AS otras,
       count(*) FILTER (WHERE monto_cup_equivalente IS NULL) AS equiv_nulos
FROM public.app_dat_pago_venta;

-- 7.4 PRUEBA TRANSACCIONAL (ejecutar aparte; termina revirtiendo).
--     Sustituye el filtro por una operación real cuyo creador sea vendedor.
--     Resultado esperado:
--       * EUR por `_v2` -> excepción 'solo admite CUP y USD'
--       * USD por `_v2` -> true, con moneda='USD', tasa_usd=900 y
--                          monto_cup_equivalente == importe_total
--
-- DO $$
-- DECLARE v_op bigint; v_total numeric; v_err text; v_ok boolean;
-- BEGIN
--   SELECT ov.id_operacion, ov.importe_total INTO v_op, v_total
--   FROM public.app_dat_operacion_venta ov
--   JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
--   WHERE EXISTS (SELECT 1 FROM public.app_dat_vendedor v WHERE v.uuid = o.uuid)
--   ORDER BY ov.id_operacion DESC LIMIT 1;
--
--   BEGIN
--     PERFORM public.fn_registrar_pago_venta_v2(v_op, jsonb_build_array(
--       jsonb_build_object('id_medio_pago',1,'monto',5,'moneda','EUR','tasa_cambio',10)));
--     v_err := 'NO BLOQUEO (mal)';
--   EXCEPTION WHEN OTHERS THEN v_err := sqlerrm; END;
--
--   v_ok := public.fn_registrar_pago_venta_v2(v_op, jsonb_build_array(
--     jsonb_build_object('id_medio_pago',1,'monto',v_total/900.0,'moneda','USD','tasa_usd',900)));
--
--   RAISE EXCEPTION 'EUR: % | USD ok: %', v_err, v_ok;
-- END $$;


-- ############################################################################
-- 8) Reversión
-- ############################################################################
-- Restaurar el CHECK y la coacción es DELIBERADAMENTE incómodo: ambas cosas son
-- peligrosas con multimoneda activo. Si hiciera falta volver atrás:
--
--   ALTER TABLE public.app_dat_pago_venta
--     ADD CONSTRAINT app_dat_pago_venta_moneda_check
--     CHECK (moneda IN ('CUP','USD'));          -- fallará si ya hay otras monedas
--
-- Quitar la columna `tasa_cambio` NO es recomendable (la RPC v3 la escribe).
-- Deshacer el trigger:
--   DROP TRIGGER IF EXISTS trg_seed_tienda_monedas ON public.app_dat_tienda;
-- ============================================================================