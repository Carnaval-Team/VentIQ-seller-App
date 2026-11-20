-- ============================================================================
-- 01_motor_dinero.sql — Fase 1: integridad, escala y conciliación
--
-- REQUIERE: verify/00_linea_base.sql en verde en `newa`.
-- Aplica en UNA transacción: si algo falla, no queda nada a medias.
--
-- Cubre:
--   R1  _fdi_aplicar_movimiento valida tienda/cuenta/medio/moneda y redondea
--   R2  fn_fdi_inversion_anular con devolución al fondo (tipo devolucion_inversion)
--   R3  fn_fdi_vincular_recepcion toma FOR UPDATE antes de decidir el exceso
--   R6  escala 2 en el ledger (saldo y montos)
--   R7  fn_fdi_repartir_ganancia no bloquea cuando no hay inversores activos
--   --  fn_fdi_conciliacion por (cuenta, medio, moneda)
--
-- ROLLBACK: 01_motor_dinero_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) R6 · ESCALA DEL LEDGER
--    `round(...)` explícito: la intención es redondear a centavos, no truncar.
--    Verificado antes de migrar: en las 12 claves existentes,
--    round(saldo,2) = Σ round(monto,2) → la identidad se conserva.
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_saldo
  ALTER COLUMN saldo TYPE numeric(14,2) USING round(saldo, 2);

ALTER TABLE public.fdi_dat_movimiento
  ALTER COLUMN monto          TYPE numeric(14,2) USING round(monto, 2),
  ALTER COLUMN saldo_anterior TYPE numeric(14,2) USING round(saldo_anterior, 2),
  ALTER COLUMN saldo_nuevo    TYPE numeric(14,2) USING round(saldo_nuevo, 2);

-- ---------------------------------------------------------------------------
-- 2) R1 · APLICADOR DE MOVIMIENTOS
--    Antes localizaba el saldo por (cuenta, medio, moneda) sin comprobar la
--    tienda: movía el saldo correcto y registraba el movimiento en otra tienda.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fdi_aplicar_movimiento(
    p_id_tienda        bigint,
    p_id_cuenta        bigint,
    p_id_medio_pago    smallint,
    p_moneda           text,
    p_delta            numeric,
    p_tipo             character varying,
    p_id_liquidacion   bigint DEFAULT NULL,
    p_id_transferencia bigint DEFAULT NULL,
    p_id_inversion     bigint DEFAULT NULL,
    p_observacion      text   DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_saldo_id     bigint;
    v_saldo_tienda bigint;
    v_saldo_previo numeric;
    v_saldo_nuevo  numeric;
    v_moneda       text := upper(btrim(coalesce(p_moneda, '')));
BEGIN
    IF v_moneda = '' THEN
        RAISE EXCEPTION 'La moneda es obligatoria' USING ERRCODE = '22023';
    END IF;
    IF p_delta IS NULL OR p_delta <> round(p_delta, 2) THEN
        RAISE EXCEPTION 'El monto debe tener como máximo dos decimales (recibido %)', p_delta
            USING ERRCODE = '22023';
    END IF;

    -- La cuenta debe pertenecer a la tienda del movimiento.
    IF NOT EXISTS (
        SELECT 1 FROM public.fdi_dat_cuenta c
        WHERE c.id = p_id_cuenta AND c.id_tienda = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'La cuenta % no pertenece a la tienda %', p_id_cuenta, p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.app_nom_medio_pago m WHERE m.id = p_id_medio_pago
    ) THEN
        RAISE EXCEPTION 'El medio de pago % no existe', p_id_medio_pago
            USING ERRCODE = 'P0002';
    END IF;

    SELECT id, id_tienda, saldo
      INTO v_saldo_id, v_saldo_tienda, v_saldo_previo
    FROM public.fdi_dat_saldo
    WHERE id_cuenta = p_id_cuenta
      AND id_medio_pago = p_id_medio_pago
      AND moneda = v_moneda
    FOR UPDATE;

    IF v_saldo_id IS NULL THEN
        INSERT INTO public.fdi_dat_saldo
            (id_tienda, id_cuenta, id_medio_pago, moneda, saldo)
        VALUES (p_id_tienda, p_id_cuenta, p_id_medio_pago, v_moneda, 0)
        RETURNING id, saldo INTO v_saldo_id, v_saldo_previo;
    ELSIF v_saldo_tienda <> p_id_tienda THEN
        RAISE EXCEPTION 'El saldo de la cuenta % pertenece a otra tienda', p_id_cuenta
            USING ERRCODE = '42501';
    END IF;

    v_saldo_nuevo := round(v_saldo_previo + p_delta, 2);
    IF v_saldo_nuevo < 0 THEN
        RAISE EXCEPTION 'Saldo insuficiente en cuenta %, medio %, moneda %: disponible %, requerido %',
            p_id_cuenta, p_id_medio_pago, v_moneda, v_saldo_previo, -p_delta
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.fdi_dat_saldo
    SET saldo = v_saldo_nuevo, updated_at = now()
    WHERE id = v_saldo_id;

    INSERT INTO public.fdi_dat_movimiento (
        id_tienda, id_cuenta, id_medio_pago, moneda, monto,
        saldo_anterior, saldo_nuevo, tipo,
        id_liquidacion, id_transferencia, id_inversion,
        observacion, created_by
    ) VALUES (
        p_id_tienda, p_id_cuenta, p_id_medio_pago, v_moneda, round(p_delta, 2),
        v_saldo_previo, v_saldo_nuevo, p_tipo,
        p_id_liquidacion, p_id_transferencia, p_id_inversion,
        p_observacion, auth.uid()
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) R3 · VINCULAR RECEPCIÓN CON FOR UPDATE
--    Antes leía la inversión sin bloquear: dos recepciones concurrentes podían
--    pasar ambas sin confirmar el exceso.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_vincular_recepcion(
    p_id_operacion     bigint,
    p_id_inversion     bigint,
    p_monto            numeric,
    p_moneda           text,
    p_tasa_a_ref       numeric DEFAULT 1,
    p_confirmar_exceso boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv       record;
    v_op_tienda bigint;
    v_monto_ref numeric;
BEGIN
    SELECT * INTO v_inv
    FROM public.fdi_dat_inversion
    WHERE id = p_id_inversion
    FOR UPDATE;

    IF v_inv.id IS NULL THEN
        RAISE EXCEPTION 'Inversión % no encontrada', p_id_inversion USING ERRCODE = 'P0002';
    END IF;
    IF v_inv.estado = 'anulado' THEN
        RAISE EXCEPTION 'La inversión % está anulada y no admite recepciones', p_id_inversion
            USING ERRCODE = '22023';
    END IF;

    SELECT id_tienda INTO v_op_tienda FROM public.app_dat_operaciones WHERE id = p_id_operacion;
    IF v_op_tienda IS NULL OR v_op_tienda <> v_inv.id_tienda THEN
        RAISE EXCEPTION 'La recepción % no pertenece a la tienda de la inversión', p_id_operacion
            USING ERRCODE = 'P0002';
    END IF;

    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto de la recepción debe ser > 0' USING ERRCODE = 'P0002';
    END IF;

    IF p_moneda = v_inv.moneda_referencia THEN
        p_tasa_a_ref := 1;
    END IF;
    IF p_tasa_a_ref IS NULL OR p_tasa_a_ref <= 0 THEN
        RAISE EXCEPTION 'La tasa a la moneda de referencia debe ser > 0' USING ERRCODE = 'P0002';
    END IF;

    v_monto_ref := round(p_monto * p_tasa_a_ref, 2);

    IF v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref
       AND NOT p_confirmar_exceso THEN
        RETURN jsonb_build_object(
            'status', 'requires_confirmation',
            'code', 'exceso_recepcion',
            'monto_total_ref', v_inv.monto_total_ref,
            'monto_recibido_ref', v_inv.monto_recibido_ref,
            'monto_nuevo_ref', v_monto_ref);
    END IF;

    INSERT INTO public.fdi_dat_inversion_recepcion (
        id_inversion, id_operacion, monto_recepcion, moneda_recepcion,
        tasa_a_ref, monto_ref, confirmada_con_exceso, created_by
    ) VALUES (
        p_id_inversion, p_id_operacion, p_monto, p_moneda,
        p_tasa_a_ref, v_monto_ref,
        v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref,
        auth.uid()
    );

    PERFORM public.fn_fdi_recalcular_inversion(p_id_inversion);

    RETURN jsonb_build_object('status', 'ok', 'monto_ref', v_monto_ref);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) R7 · REPARTO DE GANANCIA SIN BLOQUEAR
--    Antes lanzaba excepción si no había inversores activos, y eso tumbaba
--    cualquier liquidación aunque el usuario ya hubiera definido su retiro.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_repartir_ganancia() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tienda    bigint;
    v_igual     boolean;
    v_total     numeric;
    v_n         integer;
    v_asignado  numeric := 0;
    v_monto     numeric;
    v_pct       numeric;
    v_i         record;
    v_ultimo    bigint;
BEGIN
    SELECT id_tienda, repartir_igual INTO STRICT v_tienda, v_igual
    FROM public.fdi_dat_liquidacion WHERE id = NEW.id_liquidacion;

    SELECT sum(porcentaje), max(id), count(*)
      INTO v_total, v_ultimo, v_n
    FROM public.fdi_dat_inversor
    WHERE id_tienda = v_tienda AND activo;

    -- Sin inversores activos no hay reparto: la liquidación sigue siendo válida.
    IF v_n IS NULL OR v_n = 0 THEN
        RETURN NEW;
    END IF;

    IF NOT COALESCE(public.fn_user_is_dueno(v_tienda), false) THEN
        RAISE EXCEPTION 'Solo el dueño puede liquidar ganancias' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('fdi_inversores:' || v_tienda, 0));

    IF NOT v_igual AND v_total IS DISTINCT FROM 100::numeric THEN
        RAISE EXCEPTION 'La participación de los inversores activos debe sumar 100%%';
    END IF;
    IF NEW.monto_ganancia_retirada = 0 THEN RETURN NEW; END IF;
    IF NEW.monto_ganancia_retirada <> round(NEW.monto_ganancia_retirada, 2) THEN
        RAISE EXCEPTION 'La ganancia retirada debe tener como máximo dos decimales';
    END IF;

    FOR v_i IN SELECT * FROM public.fdi_dat_inversor
                WHERE id_tienda = v_tienda AND activo ORDER BY id LOOP
        v_pct := CASE WHEN v_igual THEN 100.0 / v_n ELSE v_i.porcentaje END;
        -- En reparto por % el último cierra la suma; en reparto igual el
        -- remanente queda en el fondo.
        v_monto := CASE WHEN NOT v_igual AND v_i.id = v_ultimo
                        THEN NEW.monto_ganancia_retirada - v_asignado
                        ELSE trunc(NEW.monto_ganancia_retirada * v_pct / 100, 2) END;
        INSERT INTO public.fdi_dat_inversor_reparto
            (id_tienda, id_inversor, id_detalle, nombre_snapshot, porcentaje_snapshot, moneda, monto)
        VALUES
            (v_tienda, v_i.id, NEW.id, v_i.nombre, v_pct, NEW.moneda, v_monto);
        v_asignado := v_asignado + v_monto;
    END LOOP;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) R2 · ANULACIÓN DE INVERSIÓN CON DEVOLUCIÓN
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_inversion
  DROP CONSTRAINT IF EXISTS fdi_dat_inversion_estado_check;
ALTER TABLE public.fdi_dat_inversion
  ADD CONSTRAINT fdi_dat_inversion_estado_check
  CHECK (estado IN ('pendiente', 'parcial', 'completado', 'anulado'));

ALTER TABLE public.fdi_dat_movimiento
  DROP CONSTRAINT IF EXISTS fdi_dat_movimiento_tipo_check;
ALTER TABLE public.fdi_dat_movimiento
  ADD CONSTRAINT fdi_dat_movimiento_tipo_check
  CHECK (tipo IN ('liquidacion', 'transferencia_salida', 'transferencia_entrada',
                  'comision_transferencia', 'extraccion_inversion', 'ingreso_manual',
                  'ajuste', 'ajuste_correccion', 'gasto', 'devolucion_inversion'));

CREATE OR REPLACE FUNCTION public.fn_fdi_inversion_anular(
    p_id_inversion bigint,
    p_motivo       text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv      record;
    v_fuente   record;
    v_devuelto numeric := 0;
    v_n        integer := 0;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo de anulación es obligatorio' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_inv
    FROM public.fdi_dat_inversion
    WHERE id = p_id_inversion
    FOR UPDATE;

    IF v_inv.id IS NULL THEN
        RAISE EXCEPTION 'Inversión % no encontrada', p_id_inversion USING ERRCODE = 'P0002';
    END IF;
    -- Sin sesión (service_role / editor SQL) se permite; con sesión, se exige rol.
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_inv.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;

    -- Idempotente: anular dos veces no devuelve el dinero dos veces.
    IF v_inv.estado = 'anulado' THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true, 'devuelto', 0);
    END IF;

    IF EXISTS (SELECT 1 FROM public.fdi_dat_inversion_recepcion WHERE id_inversion = p_id_inversion) THEN
        RAISE EXCEPTION 'La inversión % tiene recepciones vinculadas; desvincúlelas antes de anular',
            p_id_inversion USING ERRCODE = '22023';
    END IF;

    FOR v_fuente IN
        SELECT * FROM public.fdi_dat_inversion_fuente
        WHERE id_inversion = p_id_inversion
        ORDER BY id
    LOOP
        PERFORM public._fdi_aplicar_movimiento(
            v_inv.id_tienda, v_fuente.id_cuenta, v_fuente.id_medio_pago, v_fuente.moneda,
            v_fuente.monto, 'devolucion_inversion',
            NULL, NULL, p_id_inversion,
            'Anulación de inversión ' || v_inv.identificador || '. Motivo: ' || btrim(p_motivo));
        v_devuelto := v_devuelto + v_fuente.monto;
        v_n := v_n + 1;
    END LOOP;

    INSERT INTO public.fdi_hist_estado_inversion
        (id_inversion, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES
        (p_id_inversion, v_inv.estado, 'anulado', 'manual', btrim(p_motivo), auth.uid());

    UPDATE public.fdi_dat_inversion
       SET estado             = 'anulado',
           estado_manual      = true,
           requiere_revision  = false,
           motivo_revision    = NULL,
           monto_faltante_ref = NULL,
           updated_at         = now()
     WHERE id = p_id_inversion;

    RETURN jsonb_build_object('status', 'ok', 'devuelto', v_devuelto, 'fuentes', v_n);
END;
$$;

-- El recálculo automático no debe resucitar una inversión anulada.
CREATE OR REPLACE FUNCTION public.fn_fdi_recalcular_inversion(p_id_inversion bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv      record;
    v_recibido numeric;
    v_nuevo    varchar;
BEGIN
    SELECT * INTO v_inv FROM public.fdi_dat_inversion WHERE id = p_id_inversion FOR UPDATE;
    IF v_inv.id IS NULL THEN
        RETURN;
    END IF;
    -- Una inversión anulada ya devolvió su dinero: no se recalcula.
    IF v_inv.estado = 'anulado' THEN
        RETURN;
    END IF;

    SELECT COALESCE(sum(monto_ref), 0) INTO v_recibido
    FROM public.fdi_dat_inversion_recepcion WHERE id_inversion = p_id_inversion;

    v_nuevo := CASE
        WHEN v_recibido <= 0 THEN 'pendiente'
        WHEN v_recibido < v_inv.monto_total_ref THEN 'parcial'
        ELSE 'completado' END;

    IF v_nuevo <> v_inv.estado THEN
        INSERT INTO public.fdi_hist_estado_inversion (
            id_inversion, estado_anterior, estado_nuevo, origen, motivo, created_by
        ) VALUES (
            p_id_inversion, v_inv.estado, v_nuevo, 'automatico',
            'Recalculo por recepciones', auth.uid());
    END IF;

    UPDATE public.fdi_dat_inversion
    SET monto_recibido_ref = v_recibido,
        estado             = v_nuevo,
        estado_manual      = false,
        requiere_revision  = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN false ELSE requiere_revision END,
        motivo_revision    = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN NULL ELSE motivo_revision END,
        monto_faltante_ref = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN NULL ELSE monto_faltante_ref END,
        updated_at         = now()
    WHERE id = p_id_inversion;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) CONCILIACIÓN R1 — por (cuenta, medio, moneda)
-- ---------------------------------------------------------------------------
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

REVOKE ALL ON FUNCTION public.fn_fdi_inversion_anular(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_inversion_anular(bigint, text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_fdi_conciliacion(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_conciliacion(bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7) VERIFICACIÓN — si algo no cuadra, se revierte todo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_escala   integer;
    v_descuadre integer;
    v_anulable integer;
BEGIN
    SELECT count(*) INTO v_escala
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='fdi_dat_saldo'
      AND column_name='saldo' AND numeric_scale = 2;
    IF v_escala <> 1 THEN
        RAISE EXCEPTION 'fdi_dat_saldo.saldo no quedó en escala 2';
    END IF;

    SELECT count(*) INTO v_escala
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='fdi_dat_movimiento'
      AND column_name IN ('monto','saldo_anterior','saldo_nuevo') AND numeric_scale = 2;
    IF v_escala <> 3 THEN
        RAISE EXCEPTION 'fdi_dat_movimiento no quedó con las 3 columnas en escala 2';
    END IF;

    SELECT count(*) INTO v_descuadre
    FROM (
        SELECT s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
               COALESCE(sum(m.monto), 0) AS sm
        FROM public.fdi_dat_saldo s
        LEFT JOIN public.fdi_dat_movimiento m
          ON m.id_cuenta = s.id_cuenta
         AND m.id_medio_pago = s.id_medio_pago
         AND m.moneda = s.moneda
        GROUP BY 1,2,3,4
    ) x
    WHERE abs(x.saldo - x.sm) >= 0.005;
    IF v_descuadre > 0 THEN
        RAISE EXCEPTION 'La conciliación quedó rota en % clave(s)', v_descuadre;
    END IF;

    SELECT count(*) INTO v_anulable
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_fdi_inversion_anular','fn_fdi_conciliacion');
    IF v_anulable <> 2 THEN
        RAISE EXCEPTION 'Faltan las funciones nuevas de la fase 1';
    END IF;
END;
$$;

COMMIT;