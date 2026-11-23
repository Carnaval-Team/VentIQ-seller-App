-- ============================================================================
-- 07_aportes_inversores.sql — Fase 7: inversores aportantes al 100 %
--
-- OBJETIVO
--   Que los inversores cubran una compra al 100 % **sin que ese dinero se
--   acumule en el fondo**. El aporte vive atado a su compra: no entra en
--   `fdi_dat_saldo`, no crea saldo del inversor y no roza
--   `fdi_dat_inversor.porcentaje` (el % es de la utilidad liquidada, no de la
--   caja de una compra).
--
-- REGLAS QUE ESTE ARCHIVO DEJA EN LA BASE (no solo en la RPC)
--   R1  `fdi_dat_compra_aporte` sólo existe en compras con
--       `modo_liquidacion = 'inversores'`         → trg_fdi_aporte_inversores
--   R2  en modo `fondo` no se puede insertar un aporte
--       (misma regla, otro sentido)               → trg_fdi_aporte_inversores
--   R3  en modo `inversores` no existe reserva del fondo
--                                                 → trg_fdi_reserva_solo_fondo
--   R4  en modo `inversores` ningún pago tiene `origen = 'fondo'`, y en modo
--       `fondo` ninguno tiene `origen = 'aporte'` → trg_fdi_pago_coherente
--   R5  Σ aportes vigentes nunca pasa de `total_financiado`
--                                                 → trg_fdi_aporte_inversores
--   R6  `modo_liquidacion` no cambia con dinero ya comprometido ni fuera de
--       `creada`                                  → trg_fdi_compra_modo_inmutable
--   R7  un pago con `origen = 'aporte'` no tiene cuenta ni medio de pago, y
--       siempre apunta a su aporte                → fdi_pago_fuente_check
--   R8  en una compra de inversores ningún ajuste ni cargo de recepción tiene
--       `origen_pago = 'fondo'`                   → trg_fdi_ajuste_solo_fondo /
--                                                   trg_fdi_recepcion_solo_fondo
--   R9  un aporte registrado es inmutable salvo su devolución, no se reactiva
--       y no se borra                             → trg_fdi_aporte_inversores
--       (INSERT/UPDATE/DELETE)
--   R10 `total_financiado` sólo cambia mientras la compra está en `creada`
--                                                 → trg_fdi_compra_modo_inmutable
--
-- MÁQUINA DE ESTADOS EN MODO INVERSORES
--   `creada`  →  se registran aportes hasta cubrir `total_financiado`.
--   `pagada`  →  sólo con Σ aportes vigentes = `total_financiado`; escribe una
--                fila de `fdi_dat_compra_pago` por aporte (`origen='aporte'`,
--                sin movimiento de dinero) y **no toca el fondo**.
--   No se usa `reservada`: en modo inversores no hay nada que reservar del
--   fondo. `fn_fdi_compra_liberar` rechaza el modo (devolver aportes es la
--   operación equivalente, y es explícita).
--
-- DEVOLUCIÓN = CANCELACIÓN DE PASIVO
--   `fn_fdi_compra_aporte_devolver` marca el aporte como `devuelto` (no lo
--   borra), deja rastro de quién y por qué, y **no mueve dinero del fondo**.
--   Si `naturaleza = 'pasivo'` y hay `tasa_interes`, el interés es gasto de la
--   tienda: aquí solo se **declara** y se expone estimado; no se contabiliza en
--   el libro del fondo (fase 8, reporte de inversores). Un aporte `anticipo` o
--   `capital` no devenga interés y el trigger lo impide.
--
-- GUARDAS EN EL RESTO DE LA FASE 4
--   · `pagar`        rama propia para aportes (nunca debita el fondo).
--   · `liberar`      rechaza modo inversores.
--   · `cancelar`     exige que no queden aportes vigentes.
--   · `anular`       exige lo mismo y no devuelve al fondo lo que no salió de
--                    él (salta las filas `origen='aporte'`).
--
-- IDEMPOTENTE: se puede reaplicar. No borra datos. No toca `fdi_dat_inversor`
-- ni `fdi_dat_inversor_reparto` ni `fdi_dat_saldo`.
--
-- REQUIERE: 03a, 03b, 04 (reserva/pago/pagar/anular/cancelar/liberar) y
--           preferiblemente 06d. Aplicar en `newa` (qhprswhhfasrikhawjoz).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) Preflight
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_pago;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_reserva') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_reserva;';
    END IF;
    IF to_regclass('public.fdi_dat_inversor') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_inversor;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '07: faltan tablas:%.', v_falta USING ERRCODE = '42P01';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra'
                      AND column_name = 'modo_liquidacion') THEN
        RAISE EXCEPTION '07: falta fdi_dat_compra.modo_liquidacion (03a).'
            USING ERRCODE = '42P01';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_pagar(bigint,numeric)') IS NULL THEN
        RAISE EXCEPTION '07: falta fn_fdi_compra_pagar(bigint,numeric) (04).'
            USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_cancelar(bigint,text)') IS NULL THEN
        RAISE EXCEPTION '07: falta fn_fdi_compra_cancelar(bigint,text) (04).'
            USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_anular(bigint,text)') IS NULL THEN
        RAISE EXCEPTION '07: falta fn_fdi_compra_anular(bigint,text) (04).'
            USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_liberar(bigint,text)') IS NULL THEN
        RAISE EXCEPTION '07: falta fn_fdi_compra_liberar(bigint,text) (04).'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Entidad aislada: el aporte de un inversor a una compra
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fdi_dat_compra_aporte (
    id                bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    id_compra         bigint NOT NULL
                      REFERENCES public.fdi_dat_compra(id) ON DELETE CASCADE,
    id_tienda         bigint NOT NULL REFERENCES public.app_dat_tienda(id),
    id_inversor       bigint NOT NULL,
    naturaleza        text NOT NULL DEFAULT 'anticipo'
                      CHECK (naturaleza IN ('anticipo','pasivo','capital')),
    moneda            text NOT NULL
                      CHECK (moneda IN ('USD','CUP','EUR')),
    monto             numeric(14,2) NOT NULL CHECK (monto > 0),
    tasa_a_total      numeric(18,10) NOT NULL DEFAULT 1 CHECK (tasa_a_total > 0),
    -- Derivado: no hay forma de que el equivalente mienta.
    monto_eq_total    numeric(14,2)
                      GENERATED ALWAYS AS (round(monto * tasa_a_total, 2)) STORED,
    tasa_interes      numeric(9,6) CHECK (tasa_interes IS NULL OR tasa_interes >= 0),
    comprobante       text,
    observacion       text,
    estado            text NOT NULL DEFAULT 'aportado'
                      CHECK (estado IN ('aportado','devuelto')),
    idempotency_key   uuid,
    devuelto_at       timestamptz,
    devuelto_por      uuid,
    motivo_devolucion text,
    created_by        uuid,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    -- El inversor tiene que ser de la misma tienda que la compra.
    FOREIGN KEY (id_inversor, id_tienda)
        REFERENCES public.fdi_dat_inversor(id, id_tienda),
    -- Un aporte devuelto siempre deja rastro de cuándo y por qué.
    CONSTRAINT fdi_aporte_devolucion_check CHECK (
        (estado = 'aportado'
            AND devuelto_at IS NULL AND motivo_devolucion IS NULL)
     OR (estado = 'devuelto'
            AND devuelto_at IS NOT NULL
            AND motivo_devolucion IS NOT NULL
            AND btrim(motivo_devolucion) <> ''))
);

CREATE INDEX IF NOT EXISTS idx_fdi_aporte_compra
    ON public.fdi_dat_compra_aporte (id_compra, estado);

CREATE INDEX IF NOT EXISTS idx_fdi_aporte_inversor
    ON public.fdi_dat_compra_aporte (id_inversor, estado);

-- Un doble clic no crea dos aportes.
CREATE UNIQUE INDEX IF NOT EXISTS idx_fdi_aporte_idem
    ON public.fdi_dat_compra_aporte (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.fdi_dat_compra_aporte ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fdi_aporte_select ON public.fdi_dat_compra_aporte;
CREATE POLICY fdi_aporte_select ON public.fdi_dat_compra_aporte
    FOR SELECT TO authenticated
    USING (public.fn_user_can_access_tienda(id_tienda));
GRANT SELECT ON public.fdi_dat_compra_aporte TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) El pago puede venir de un aporte: sin cuenta ni medio de pago
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_pago
    ALTER COLUMN id_cuenta   DROP NOT NULL,
    ALTER COLUMN id_medio_pago DROP NOT NULL;

ALTER TABLE public.fdi_dat_compra_pago
    DROP CONSTRAINT IF EXISTS fdi_pago_fuente_check;
ALTER TABLE public.fdi_dat_compra_pago
    ADD CONSTRAINT fdi_pago_fuente_check CHECK (
        -- El camino del fondo: cuenta, medio y movimiento obligatorios.
        (origen = 'fondo'
            AND id_cuenta IS NOT NULL
            AND id_medio_pago IS NOT NULL
            AND id_movimiento IS NOT NULL
            AND id_aporte IS NULL)
     OR -- El camino del aporte: sin cuenta, sin medio y sin movimiento.
        (origen = 'aporte'
            AND id_aporte IS NOT NULL
            AND id_cuenta IS NULL
            AND id_medio_pago IS NULL
            AND id_movimiento IS NULL));

-- La FK del pago amarra el aporte **y su compra**: un pago de la compra A no
-- puede apuntar a un aporte de la compra B.
CREATE UNIQUE INDEX IF NOT EXISTS uq_fdi_aporte_id_compra
    ON public.fdi_dat_compra_aporte (id, id_compra);

ALTER TABLE public.fdi_dat_compra_pago
    DROP CONSTRAINT IF EXISTS fdi_pago_aporte_fk;
ALTER TABLE public.fdi_dat_compra_pago
    ADD CONSTRAINT fdi_pago_aporte_fk
    FOREIGN KEY (id_aporte, id_compra)
    REFERENCES public.fdi_dat_compra_aporte(id, id_compra);

CREATE INDEX IF NOT EXISTS idx_fdi_pago_aporte
    ON public.fdi_dat_compra_pago (id_aporte)
    WHERE id_aporte IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3) Exclusividad y modo inmutable (R1-R6)
-- ---------------------------------------------------------------------------

-- R1/R2/R5 — el aporte sólo existe en modo inversores, nunca pasa del faltante y
-- no se puede reescribir por detrás de su RPC.
CREATE OR REPLACE FUNCTION public.fn_fdi_aporte_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_modo      text;
    v_total     numeric;
    v_tienda    bigint;
    v_estado    text;
    v_vigentes  numeric;
    v_faltante  numeric;
BEGIN
    -- El rastro de un aporte no se borra: se marca como devuelto.
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Un aporte no se borra: devuélvalo (queda el rastro del dinero)'
            USING ERRCODE = '22023';
    END IF;

    SELECT c.modo_liquidacion, c.total_financiado, c.id_tienda, c.estado
      INTO v_modo, v_total, v_tienda, v_estado
      FROM public.fdi_dat_compra c
     WHERE c.id = NEW.id_compra
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La compra % no existe', NEW.id_compra USING ERRCODE = 'P0002';
    END IF;

    IF v_modo <> 'inversores' THEN
        RAISE EXCEPTION 'La compra #% se liquida con el fondo: no admite aportes de inversores',
            NEW.id_compra USING ERRCODE = '22023';
    END IF;

    IF NEW.id_tienda <> v_tienda THEN
        RAISE EXCEPTION 'El aporte es de la tienda % y la compra de la %',
            NEW.id_tienda, v_tienda USING ERRCODE = '42501';
    END IF;

    -- ---- UPDATE: el aporte registrado es inmutable salvo su devolución ----
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id_compra    <> OLD.id_compra
           OR NEW.id_tienda <> OLD.id_tienda
           OR NEW.id_inversor <> OLD.id_inversor
           OR NEW.naturaleza  <> OLD.naturaleza
           OR NEW.moneda      <> OLD.moneda
           OR NEW.monto       <> OLD.monto
           OR NEW.tasa_a_total <> OLD.tasa_a_total
           OR NEW.tasa_interes IS DISTINCT FROM OLD.tasa_interes
           OR NEW.comprobante IS DISTINCT FROM OLD.comprobante
           OR NEW.created_at  <> OLD.created_at THEN
            RAISE EXCEPTION 'Un aporte registrado es inmutable: sólo cambia su estado a devuelto'
                USING ERRCODE = '22023';
        END IF;
        IF OLD.estado = 'devuelto' AND NEW.estado = 'aportado' THEN
            RAISE EXCEPTION 'Un aporte devuelto no se reactiva: registre uno nuevo'
                USING ERRCODE = '22023';
        END IF;
        RETURN NEW;
    END IF;

    -- ---- INSERT ----
    IF v_estado <> 'creada' THEN
        RAISE EXCEPTION 'Sólo se aporta a una compra en estado creada (actual: %)', v_estado
            USING ERRCODE = '22023';
    END IF;

    IF NEW.tasa_interes IS NOT NULL AND NEW.naturaleza <> 'pasivo' THEN
        RAISE EXCEPTION 'Sólo un aporte con naturaleza pasivo devenga interés (recibido: %)',
            NEW.naturaleza USING ERRCODE = '22023';
    END IF;

    -- El tope sólo se comprueba al dar de alta un aporte vigente: la devolución
    -- lo baja y no puede quedar bloqueada por sí misma.
    IF NEW.estado = 'aportado' THEN
        SELECT COALESCE(sum(a.monto_eq_total), 0) INTO v_vigentes
          FROM public.fdi_dat_compra_aporte a
         WHERE a.id_compra = NEW.id_compra
           AND a.estado = 'aportado';

        v_faltante := v_total - v_vigentes;
        IF NEW.monto_eq_total > v_faltante THEN
            RAISE EXCEPTION 'El aporte de % excede el faltante de la compra #% (faltan %)',
                NEW.monto_eq_total, NEW.id_compra, round(v_faltante, 2)
                USING ERRCODE = '22023';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_aporte_inversores ON public.fdi_dat_compra_aporte;
CREATE TRIGGER trg_fdi_aporte_inversores
    BEFORE INSERT OR UPDATE OR DELETE ON public.fdi_dat_compra_aporte
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_aporte_validar();

-- R3 — en modo inversores no hay reserva del fondo.
CREATE OR REPLACE FUNCTION public.fn_fdi_reserva_solo_fondo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_modo text;
BEGIN
    SELECT c.modo_liquidacion INTO v_modo
      FROM public.fdi_dat_compra c
     WHERE c.id = NEW.id_compra
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La compra % no existe', NEW.id_compra USING ERRCODE = 'P0002';
    END IF;

    IF v_modo <> 'fondo' THEN
        RAISE EXCEPTION 'La compra #% se liquida con inversores: no admite reservas del fondo',
            NEW.id_compra USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_reserva_solo_fondo ON public.fdi_dat_compra_reserva;
CREATE TRIGGER trg_fdi_reserva_solo_fondo
    BEFORE INSERT ON public.fdi_dat_compra_reserva
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_reserva_solo_fondo();

-- R4 — cada modo tiene su única fuente de dinero.
CREATE OR REPLACE FUNCTION public.fn_fdi_pago_coherente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_modo text;
BEGIN
    SELECT c.modo_liquidacion INTO v_modo
      FROM public.fdi_dat_compra c
     WHERE c.id = NEW.id_compra
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La compra % no existe', NEW.id_compra USING ERRCODE = 'P0002';
    END IF;

    IF NEW.origen = 'fondo' AND v_modo <> 'fondo' THEN
        RAISE EXCEPTION 'La compra #% se liquida con inversores: ningún pago sale del fondo',
            NEW.id_compra USING ERRCODE = '22023';
    END IF;

    IF NEW.origen = 'aporte' AND v_modo <> 'inversores' THEN
        RAISE EXCEPTION 'La compra #% se liquida con el fondo: no admite pagos con aportes',
            NEW.id_compra USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_pago_coherente ON public.fdi_dat_compra_pago;
CREATE TRIGGER trg_fdi_pago_coherente
    BEFORE INSERT OR UPDATE OF origen, id_aporte, id_cuenta, id_medio_pago
    ON public.fdi_dat_compra_pago
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_pago_coherente();

-- R8 — en una compra de inversores ningún cargo lo paga el fondo.
--      Un ajuste con `origen_pago='fondo'` infla `total_financiado` y hace que
--      los inversores cubran dinero del fondo; un cargo de importadora con
--      `origen_pago='fondo'` además se salta la capitalización en 06b
--      (`omitido / origen_pago_fondo`) y deja el costo subestimado en silencio.
--      El trigger cubre crear/editar/agregar y cualquier escritura directa, así
--      que no hace falta repetir la guarda en tres cuerpos.
CREATE OR REPLACE FUNCTION public.fn_fdi_cargo_solo_fondo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_modo text;
BEGIN
    SELECT c.modo_liquidacion INTO v_modo
      FROM public.fdi_dat_compra c
     WHERE c.id = NEW.id_compra
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La compra % no existe', NEW.id_compra USING ERRCODE = 'P0002';
    END IF;

    IF NEW.origen_pago = 'fondo' AND v_modo <> 'fondo' THEN
        RAISE EXCEPTION 'La compra #% se liquida con aportes: ningún cargo lo paga el fondo (use wallet_importadora, wallet_proveedor o externo)',
            NEW.id_compra USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_ajuste_solo_fondo ON public.fdi_dat_compra_ajuste;
CREATE TRIGGER trg_fdi_ajuste_solo_fondo
    BEFORE INSERT OR UPDATE OF origen_pago ON public.fdi_dat_compra_ajuste
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_cargo_solo_fondo();

DROP TRIGGER IF EXISTS trg_fdi_recepcion_solo_fondo ON public.fdi_dat_compra_recepcion;
CREATE TRIGGER trg_fdi_recepcion_solo_fondo
    BEFORE INSERT OR UPDATE OF origen_pago ON public.fdi_dat_compra_recepcion
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_cargo_solo_fondo();

-- ---------------------------------------------------------------------------
-- 3b) El ajuste tardío de una compra de inversores no lo paga el fondo
--
-- `fn_fdi_compra_ajuste_agregar` (06d) inserta el ajuste con `origen_pago =
-- 'fondo'` y `estado = 'por_financiar'` **fijo en el cuerpo**: en una compra de
-- inversores ese INSERT lo rechaza el trigger de arriba, y el costo tardío
-- (flete, aduana, recargo) quedaría sin poder registrarse nunca — el costo
-- aterrizado se queda corto para siempre y no hay otra vía.
--
-- Se corrige el cuerpo, sin duplicarlo: se lee la definición viva, se cambia el
-- literal del INSERT y se recompila. Si el ancla no aparece exactamente una vez,
-- el script aborta en vez de dejar el archivo a medias.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_def   text;
    v_src   text;
    v_ancla text := '''fondo'', ''por_financiar''';
    v_nuevo text := 'CASE WHEN v_c.modo_liquidacion = ''inversores'' THEN ''externo'' ELSE ''fondo'' END,
        CASE WHEN v_c.modo_liquidacion = ''inversores'' THEN ''declarado'' ELSE ''por_financiar'' END';
    v_pos   integer;
BEGIN
    IF to_regprocedure('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)') IS NULL THEN
        RAISE EXCEPTION '07: falta fn_fdi_compra_ajuste_agregar (06d).' USING ERRCODE = 'P0002';
    END IF;

    v_def := pg_get_functiondef(
        'public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'::regprocedure);

    IF position('''inversores'' THEN ''externo''' in v_def) > 0 THEN
        RETURN; -- ya parcheado
    END IF;

    v_pos := position(v_ancla in v_def);
    IF v_pos = 0 THEN
        RAISE EXCEPTION '07: no se encontró el ancla del ajuste en fn_fdi_compra_ajuste_agregar';
    END IF;
    IF position(v_ancla in substr(v_def, v_pos + 1)) > 0 THEN
        RAISE EXCEPTION '07: el ancla del ajuste aparece más de una vez en fn_fdi_compra_ajuste_agregar';
    END IF;

    v_src := replace(v_def, v_ancla, v_nuevo);
    EXECUTE v_src;
END;
$$;

-- R6 — el modo de liquidación no cambia con dinero ya comprometido, y
-- `total_financiado` sólo se mueve mientras la compra está en `creada`
-- (mismo invariante que aplica `fn_fdi_compra_recalcular` en 06d).
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_modo_inmutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.modo_liquidacion IS DISTINCT FROM OLD.modo_liquidacion THEN
        IF OLD.estado <> 'creada' THEN
            RAISE EXCEPTION 'El modo de liquidación de la compra #% no cambia fuera de creada (actual: %)',
                OLD.id, OLD.estado USING ERRCODE = '22023';
        END IF;
        -- Cualquier aporte, en cualquier estado, ancla el modo: si no, una compra
        -- con aportes devueltos podría pasar a `fondo` y quedarse con filas de
        -- aporte que contradicen su modo (y fuera del alcance de verify/07).
        IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_aporte a WHERE a.id_compra = OLD.id)
           OR EXISTS (SELECT 1 FROM public.fdi_dat_compra_reserva r WHERE r.id_compra = OLD.id) THEN
            RAISE EXCEPTION 'La compra #% ya tiene dinero comprometido: no se cambia el modo de liquidación',
                OLD.id USING ERRCODE = '22023';
        END IF;
    END IF;

    IF NEW.total_financiado IS DISTINCT FROM OLD.total_financiado
       AND OLD.estado <> 'creada' THEN
        RAISE EXCEPTION 'El total financiado de la compra #% está congelado fuera de creada (actual: %)',
            OLD.id, OLD.estado USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_compra_modo_inmutable ON public.fdi_dat_compra;
CREATE TRIGGER trg_fdi_compra_modo_inmutable
    BEFORE UPDATE OF modo_liquidacion, total_financiado ON public.fdi_dat_compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_fdi_compra_modo_inmutable();

-- ---------------------------------------------------------------------------
-- 4) Lectura: desglose de aportes con restante bloqueante
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_aportes(p_id_compra bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c         record;
    v_vigente   numeric := 0;
    v_devuelto  numeric := 0;
    v_faltante  numeric := 0;
    v_pct       numeric := 0;
    v_motivo    text;
    v_aportes   jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la compra %', p_id_compra USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(sum(a.monto_eq_total) FILTER (WHERE a.estado = 'aportado'), 0),
           COALESCE(sum(a.monto_eq_total) FILTER (WHERE a.estado = 'devuelto'), 0)
      INTO v_vigente, v_devuelto
      FROM public.fdi_dat_compra_aporte a
     WHERE a.id_compra = p_id_compra;

    v_faltante := GREATEST(v_c.total_financiado - v_vigente, 0);

    IF v_c.total_financiado > 0 THEN
        v_pct := round(v_vigente / v_c.total_financiado * 100, 2);
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', a.id,
               'id_inversor', a.id_inversor,
               'inversor', i.nombre,
               'porcentaje_inversor', i.porcentaje,
               'naturaleza', a.naturaleza,
               'moneda', a.moneda,
               'monto', a.monto,
               'tasa_a_total', a.tasa_a_total,
               'monto_eq_total', a.monto_eq_total,
               'tasa_interes', a.tasa_interes,
               'interes_estimado',
                   round(a.monto_eq_total * COALESCE(a.tasa_interes, 0), 2),
               'comprobante', a.comprobante,
               'observacion', a.observacion,
               'estado', a.estado,
               'devuelto_at', a.devuelto_at,
               'motivo_devolucion', a.motivo_devolucion,
               'created_at', a.created_at
           ) ORDER BY a.id), '[]'::jsonb)
      INTO v_aportes
      FROM public.fdi_dat_compra_aporte a
      JOIN public.fdi_dat_inversor i ON i.id = a.id_inversor
     WHERE a.id_compra = p_id_compra;

    -- Motivo por el que el pago está bloqueado (null = se puede pagar).
    v_motivo := CASE
        WHEN v_c.modo_liquidacion <> 'inversores'
             THEN 'La compra se liquida con el fondo'
        WHEN v_c.estado = 'pagada' THEN 'La compra ya está pagada'
        WHEN v_c.estado IN ('entrega_parcial','completada')
             THEN 'La compra ya está pagada'
        WHEN v_c.estado = 'cancelada' THEN 'La compra está cancelada'
        WHEN v_c.estado = 'anulada' THEN 'La compra está anulada'
        WHEN v_c.estado <> 'creada'
             THEN 'La compra está en estado ' || v_c.estado
        WHEN v_c.total_financiado <= 0
             THEN 'La compra no tiene total a financiar'
        WHEN v_faltante > 0
             THEN 'Faltan ' || btrim(to_char(v_faltante, 'FM999999999990.00'))
                  || ' ' || v_c.moneda_total
        ELSE NULL
    END;

    RETURN jsonb_build_object(
        'id_compra',            p_id_compra,
        'modo_liquidacion',     v_c.modo_liquidacion,
        'estado',               v_c.estado,
        'moneda',               v_c.moneda_total,
        'total',                v_c.total_financiado,
        'aportado',             v_vigente,
        'devuelto',             v_devuelto,
        'faltante',             v_faltante,
        'pct',                  v_pct,
        -- Registrar y pagar son puertas distintas: `motivo_bloqueo` habla del
        -- pago (que exige el 100 %), no de seguir aportando.
        'puede_registrar',      (v_c.estado = 'creada'
                                  AND v_c.total_financiado > 0
                                  AND v_faltante > 0),
        'puede_devolver',       (v_c.estado IN ('creada','pagada')
                                  AND v_vigente > 0),
        'puede_pagar',          (v_motivo IS NULL),
        'motivo_bloqueo',       v_motivo,
        'aportes',              v_aportes
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) Registrar un aporte (no excede el faltante)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_aporte_registrar(
    p_id_compra       bigint,
    p_id_inversor     bigint,
    p_moneda          text,
    p_monto           numeric,
    p_tasa_a_total    numeric DEFAULT NULL,
    p_naturaleza      text    DEFAULT 'anticipo',
    p_tasa_interes    numeric DEFAULT NULL,
    p_comprobante     text    DEFAULT NULL,
    p_observacion     text    DEFAULT NULL,
    p_idempotency_key uuid    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c         record;
    v_inv       record;
    v_moneda    text;
    v_tasa      numeric;
    v_nat       text;
    v_vigente   numeric := 0;
    v_faltante  numeric := 0;
    v_id        bigint;
    v_existente bigint;
    v_existente_compra bigint;
    v_aporte    record;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 OR p_monto <> round(p_monto, 2) THEN
        RAISE EXCEPTION 'El monto del aporte debe ser > 0 y de dos decimales (recibido %)', p_monto
            USING ERRCODE = '22023';
    END IF;

    v_moneda := upper(btrim(COALESCE(p_moneda, '')));
    IF v_moneda = '' THEN
        RAISE EXCEPTION 'La moneda del aporte es obligatoria' USING ERRCODE = '22023';
    END IF;

    v_nat := lower(btrim(COALESCE(p_naturaleza, 'anticipo')));
    IF v_nat NOT IN ('anticipo','pasivo','capital') THEN
        RAISE EXCEPTION 'Naturaleza inválida: % (anticipo, pasivo o capital)', p_naturaleza
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;

    -- Reintento del mismo formulario. Se comprueba después del permiso: una
    -- clave ajena no debe revelar el importe de otra compra.
    IF p_idempotency_key IS NOT NULL THEN
        SELECT a.id, a.id_compra INTO v_existente, v_existente_compra
          FROM public.fdi_dat_compra_aporte a
         WHERE a.idempotency_key = p_idempotency_key;
        IF v_existente IS NOT NULL THEN
            IF v_existente_compra <> p_id_compra THEN
                RAISE EXCEPTION 'La clave de idempotencia ya se usó en la compra %', v_existente_compra
                    USING ERRCODE = '22023';
            END IF;
            SELECT * INTO v_aporte FROM public.fdi_dat_compra_aporte WHERE id = v_existente;
            RETURN jsonb_build_object(
                'status','ok','duplicada',true,
                'id', v_aporte.id, 'id_compra', v_aporte.id_compra,
                'monto_eq_total', v_aporte.monto_eq_total,
                'estado', v_aporte.estado);
        END IF;
    END IF;

    IF v_c.modo_liquidacion <> 'inversores' THEN
        RAISE EXCEPTION 'La compra #% se liquida con el fondo: no admite aportes de inversores',
            v_c.numero_compra USING ERRCODE = '22023';
    END IF;
    IF v_c.estado <> 'creada' THEN
        RAISE EXCEPTION 'Sólo se aporta a una compra en estado creada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF v_c.total_financiado <= 0 THEN
        RAISE EXCEPTION 'La compra no tiene total a financiar' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_inv
      FROM public.fdi_dat_inversor i
     WHERE i.id = p_id_inversor AND i.id_tienda = v_c.id_tienda;
    IF v_inv.id IS NULL THEN
        RAISE EXCEPTION 'El inversor % no existe en la tienda de la compra', p_id_inversor
            USING ERRCODE = 'P0002';
    END IF;
    IF NOT v_inv.activo THEN
        RAISE EXCEPTION 'El inversor % está inactivo', v_inv.nombre USING ERRCODE = '22023';
    END IF;

    -- Misma moneda que la compra ⇒ la tasa es 1 por definición. Moneda distinta
    -- ⇒ la tasa se pide explícitamente: asumir 1 convertiría 1.000 CUP en 1.000
    -- USD sin que nadie lo declare.
    IF v_moneda = v_c.moneda_total THEN
        v_tasa := 1;
    ELSE
        IF p_tasa_a_total IS NULL THEN
            RAISE EXCEPTION 'Indique la tasa de % a % (unidades de % por 1 %)',
                v_moneda, v_c.moneda_total, v_c.moneda_total, v_moneda
                USING ERRCODE = '22023';
        END IF;
        v_tasa := p_tasa_a_total;
    END IF;
    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        RAISE EXCEPTION 'La tasa debe ser mayor que cero' USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(a.monto_eq_total), 0) INTO v_vigente
      FROM public.fdi_dat_compra_aporte a
     WHERE a.id_compra = p_id_compra AND a.estado = 'aportado';

    v_faltante := round(v_c.total_financiado - v_vigente, 2);
    IF round(p_monto * v_tasa, 2) > v_faltante THEN
        RAISE EXCEPTION 'El aporte equivale a % y sólo faltan % % de la compra #%',
            round(p_monto * v_tasa, 2), v_faltante, v_c.moneda_total, v_c.numero_compra
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.fdi_dat_compra_aporte (
        id_compra, id_tienda, id_inversor, naturaleza, moneda, monto,
        tasa_a_total, tasa_interes, comprobante, observacion,
        estado, idempotency_key, created_by
    ) VALUES (
        p_id_compra, v_c.id_tienda, p_id_inversor, v_nat, v_moneda, p_monto,
        v_tasa, p_tasa_interes, NULLIF(btrim(COALESCE(p_comprobante, '')), ''),
        NULLIF(btrim(COALESCE(p_observacion, '')), ''),
        'aportado', p_idempotency_key, auth.uid()
    ) RETURNING id INTO v_id;

    SELECT * INTO v_aporte FROM public.fdi_dat_compra_aporte WHERE id = v_id;

    RETURN jsonb_build_object(
        'status','ok',
        'id', v_id,
        'id_compra', p_id_compra,
        'id_inversor', p_id_inversor,
        'inversor', v_inv.nombre,
        'moneda', v_moneda,
        'monto', p_monto,
        'tasa_a_total', v_tasa,
        'monto_eq_total', v_aporte.monto_eq_total,
        'aportado', round(v_vigente + v_aporte.monto_eq_total, 2),
        'faltante', round(v_faltante - v_aporte.monto_eq_total, 2),
        'total', v_c.total_financiado);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) Devolver un aporte = cancelar el pasivo (el dinero no vuelve al fondo)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_aporte_devolver(
    p_id_aporte bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_a        record;
    v_c        record;
    v_vigente  numeric := 0;
    v_devuelto numeric := 0;
    v_cambio   boolean := false;
    v_id_compra bigint;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo de la devolución es obligatorio' USING ERRCODE = '22023';
    END IF;

    -- Orden de bloqueo: SIEMPRE compra → aporte. Al revés se cruza con `pagar`,
    -- que bloquea la compra y luego toma el aporte por la FK del pago (FOR KEY
    -- SHARE), y PostgreSQL aborta una de las dos con 40P01.
    SELECT a.id_compra INTO v_id_compra
      FROM public.fdi_dat_compra_aporte a
     WHERE a.id = p_id_aporte;
    IF v_id_compra IS NULL THEN
        RAISE EXCEPTION 'Aporte % no encontrado', p_id_aporte USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = v_id_compra FOR UPDATE;
    SELECT * INTO v_a FROM public.fdi_dat_compra_aporte WHERE id = p_id_aporte FOR UPDATE;
    IF v_a.id IS NULL THEN
        RAISE EXCEPTION 'Aporte % no encontrado', p_id_aporte USING ERRCODE = 'P0002';
    END IF;

    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;

    IF v_a.estado = 'devuelto' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true,'id',p_id_aporte);
    END IF;

    -- Devolver con la mercancía ya recibida dejaría una compra cerrada, con
    -- inventario valorado y sin financiación: sólo `creada` y `pagada`.
    IF v_c.estado NOT IN ('creada','pagada') THEN
        RAISE EXCEPTION 'No se devuelven aportes de una compra en estado % (sólo creada o pagada)',
            v_c.estado USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra_aporte
       SET estado            = 'devuelto',
           devuelto_at       = now(),
           devuelto_por      = auth.uid(),
           motivo_devolucion = btrim(p_motivo),
           updated_at        = now()
     WHERE id = p_id_aporte;

    SELECT COALESCE(sum(a.monto_eq_total) FILTER (WHERE a.estado = 'aportado'), 0),
           COALESCE(sum(a.monto_eq_total) FILTER (WHERE a.estado = 'devuelto'), 0)
      INTO v_vigente, v_devuelto
      FROM public.fdi_dat_compra_aporte a
     WHERE a.id_compra = v_a.id_compra;

    -- La devolución después del pago deja la compra `pagada` con cobertura
    -- incompleta: se anota en el historial para que el hueco tenga documento.
    IF v_c.estado = 'pagada' THEN
        INSERT INTO public.fdi_hist_estado_compra
            (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
        VALUES (v_a.id_compra, v_c.id_tienda, 'pagada', 'pagada', 'manual',
                'Devolución de aporte #' || p_id_aporte || ' por '
                || btrim(to_char(v_a.monto_eq_total, 'FM999999999990.00')) || ' '
                || v_a.moneda || ': la compra queda con un faltante de '
                || btrim(to_char(GREATEST(v_c.total_financiado - v_vigente, 0),
                                 'FM999999999990.00')) || ' ' || v_c.moneda_total
                || ' ya pagado por el proveedor. Motivo: ' || btrim(p_motivo),
                auth.uid());
        v_cambio := false;
    END IF;

    RETURN jsonb_build_object(
        'status','ok',
        'id', p_id_aporte,
        'id_compra', v_a.id_compra,
        'id_inversor', v_a.id_inversor,
        'devuelto_monto', v_a.monto_eq_total,
        'aportado', v_vigente,
        'devuelto', v_devuelto,
        'faltante', GREATEST(v_c.total_financiado - v_vigente, 0),
        'estado_compra', v_c.estado,
        'estado_cambiado', v_cambio);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) Pagar: rama propia del modo inversores (no debita el fondo)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_pagar(
    p_id_compra bigint,
    p_tasa_pago numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c     record;
    v_r     record;
    v_a     record;
    v_mov   bigint;
    v_total numeric := 0;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'pagada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true,'id_compra',p_id_compra);
    END IF;

    -- ------------------------------------------------------------------
    -- 7a) Modo inversores: los aportes son la única fuente. No hay reserva
    --     del fondo que consumir y no se escribe ningún movimiento.
    -- ------------------------------------------------------------------
    IF v_c.modo_liquidacion = 'inversores' THEN
        IF v_c.estado <> 'creada' THEN
            RAISE EXCEPTION 'Sólo se paga una compra creada con inversores (actual: %)', v_c.estado
                USING ERRCODE = '22023';
        END IF;
        -- Sin esta guarda una compra con líneas a costo 0 pasaría a `pagada` sin
        -- escribir un solo pago (y rompería «pagada ⇒ hay pago» de verify/04).
        IF v_c.total_financiado <= 0 THEN
            RAISE EXCEPTION 'La compra no tiene total a financiar' USING ERRCODE = '22023';
        END IF;

        SELECT COALESCE(sum(a.monto_eq_total), 0) INTO v_total
          FROM public.fdi_dat_compra_aporte a
         WHERE a.id_compra = p_id_compra AND a.estado = 'aportado';

        IF v_total <> v_c.total_financiado THEN
            RAISE EXCEPTION 'Los aportes cubren % y la compra necesita %: faltan % %',
                v_total, v_c.total_financiado,
                round(v_c.total_financiado - v_total, 2), v_c.moneda_total
                USING ERRCODE = '22023';
        END IF;

        FOR v_a IN
            SELECT a.* FROM public.fdi_dat_compra_aporte a
             WHERE a.id_compra = p_id_compra AND a.estado = 'aportado'
             ORDER BY a.id
        LOOP
            -- Sin cuenta, sin medio de pago y sin movimiento: el aporte es dinero
            -- del inversor, no del fondo.
            INSERT INTO public.fdi_dat_compra_pago (
                id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
                monto, tasa_a_total, monto_eq_total, origen, id_aporte,
                id_movimiento, created_by
            ) VALUES (
                p_id_compra, v_c.id_tienda, NULL, NULL, v_a.moneda,
                v_a.monto, v_a.tasa_a_total, v_a.monto_eq_total, 'aporte', v_a.id,
                NULL, auth.uid()
            );
        END LOOP;

        UPDATE public.fdi_dat_compra
           SET estado = 'pagada', updated_at = now()
         WHERE id = p_id_compra;

        INSERT INTO public.fdi_hist_estado_compra
            (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
        VALUES (p_id_compra, v_c.id_tienda, v_c.estado, 'pagada', 'automatico',
                'Pago con aportes de inversores (sin movimiento del fondo)', auth.uid());

        RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','pagada',
            'pagado',v_total,'origen','aporte');
    END IF;

    -- ------------------------------------------------------------------
    -- 7b) Modo fondo (fase 4, sin cambios de comportamiento)
    -- ------------------------------------------------------------------
    IF v_c.estado <> 'reservada' THEN
        RAISE EXCEPTION 'Solo se paga una compra reservada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(r.monto_eq_total), 0) INTO v_total
      FROM public.fdi_dat_compra_reserva r
     WHERE r.id_compra = p_id_compra AND r.estado = 'activa';

    IF v_total <> v_c.total_financiado THEN
        RAISE EXCEPTION 'Las reservas cubren % y la compra necesita %', v_total, v_c.total_financiado
            USING ERRCODE = '22023';
    END IF;

    FOR v_r IN
        SELECT r.* FROM public.fdi_dat_compra_reserva r
         WHERE r.id_compra = p_id_compra AND r.estado = 'activa'
         ORDER BY r.id
    LOOP
        v_mov := public._fdi_aplicar_movimiento(
            v_c.id_tienda, v_r.id_cuenta, v_r.id_medio_pago, v_r.moneda,
            -v_r.monto, 'pago_compra',
            p_observacion := 'Pago compra #' || v_c.numero_compra,
            p_id_compra := p_id_compra,
            p_tasa := v_r.tasa_a_total);

        UPDATE public.fdi_dat_compra_reserva
           SET estado = 'consumida', id_movimiento = v_mov, updated_at = now()
         WHERE id = v_r.id;

        INSERT INTO public.fdi_dat_compra_pago (
            id_compra, id_tienda, id_cuenta, id_medio_pago, moneda,
            monto, tasa_a_total, monto_eq_total, origen, id_movimiento, created_by
        ) VALUES (
            p_id_compra, v_c.id_tienda, v_r.id_cuenta, v_r.id_medio_pago, v_r.moneda,
            v_r.monto, v_r.tasa_a_total, v_r.monto_eq_total, 'fondo', v_mov, auth.uid()
        );
    END LOOP;

    UPDATE public.fdi_dat_compra SET estado = 'pagada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'reservada', 'pagada', 'automatico',
            'Pago de la compra', auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','pagada',
        'pagado',v_total,'origen','fondo');
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) Liberar: sólo tiene sentido con reservas del fondo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_liberar(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
    v_n integer;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo es obligatorio' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.modo_liquidacion <> 'fondo' THEN
        RAISE EXCEPTION 'La compra #% se liquida con aportes: devuelva los aportes en vez de liberar reservas',
            v_c.numero_compra USING ERRCODE = '22023';
    END IF;
    IF v_c.estado <> 'reservada' THEN
        RAISE EXCEPTION 'Solo se liberan reservas de una compra reservada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra_reserva
       SET estado = 'liberada', updated_at = now()
     WHERE id_compra = p_id_compra AND estado = 'activa';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE public.fdi_dat_compra SET estado = 'creada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'reservada', 'creada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'liberadas',v_n,'estado','creada');
END;
$$;

-- ---------------------------------------------------------------------------
-- 9) Cancelar: no se cancela con aportes vigentes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_cancelar(p_id_compra bigint, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c record;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo de cancelación es obligatorio' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'cancelada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true);
    END IF;
    IF v_c.estado NOT IN ('creada','reservada') THEN
        RAISE EXCEPTION 'Solo se cancela una compra creada o reservada (actual: %). Si está pagada, usar anular.',
            v_c.estado USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_aporte a
                WHERE a.id_compra = p_id_compra AND a.estado = 'aportado') THEN
        RAISE EXCEPTION 'La compra #% tiene aportes de inversores vigentes: devuélvalos antes de cancelar',
            v_c.numero_compra USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra_reserva
       SET estado = 'liberada', updated_at = now()
     WHERE id_compra = p_id_compra AND estado = 'activa';

    UPDATE public.fdi_dat_compra SET estado = 'cancelada', updated_at = now() WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, 'cancelada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','cancelada');
END;
$$;

-- ---------------------------------------------------------------------------
-- 10) Anular: devuelve al fondo sólo lo que salió del fondo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_anular(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c        record;
    v_p        record;
    v_devuelto numeric := 0;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo es obligatorio' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra FOR UPDATE;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF v_c.estado = 'anulada' THEN
        RETURN jsonb_build_object('status','ok','duplicada',true,'devuelto',0);
    END IF;
    IF v_c.estado <> 'pagada' THEN
        RAISE EXCEPTION 'Solo se anula una compra pagada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones; no se anula sin resolver el inventario'
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_aporte a
                WHERE a.id_compra = p_id_compra AND a.estado = 'aportado') THEN
        RAISE EXCEPTION 'La compra #% se pagó con aportes: devuélvalos antes de anular',
            v_c.numero_compra USING ERRCODE = '22023';
    END IF;

    FOR v_p IN SELECT * FROM public.fdi_dat_compra_pago WHERE id_compra = p_id_compra ORDER BY id LOOP
        -- El aporte no salió del fondo: no hay nada que devolverle al fondo.
        IF v_p.origen = 'aporte' THEN
            CONTINUE;
        END IF;
        PERFORM public._fdi_aplicar_movimiento(
            v_c.id_tienda, v_p.id_cuenta, v_p.id_medio_pago, v_p.moneda,
            v_p.monto, 'devolucion_compra',
            p_observacion := 'Anulación compra #' || v_c.numero_compra || '. Motivo: ' || btrim(p_motivo),
            p_id_compra := p_id_compra,
            p_tasa := v_p.tasa_a_total);
        v_devuelto := v_devuelto + v_p.monto;
    END LOOP;

    UPDATE public.fdi_dat_compra SET estado = 'anulada', updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, 'pagada', 'anulada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','anulada',
        'devuelto',v_devuelto);
END;
$$;

-- ---------------------------------------------------------------------------
-- 11) Permisos
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fn_fdi_compra_aportes(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_aporte_registrar(
    bigint, bigint, text, numeric, numeric, text, numeric, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_aporte_devolver(bigint, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_aportes(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_aporte_registrar(
    bigint, bigint, text, numeric, numeric, text, numeric, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_aporte_devolver(bigint, text) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_pagar(bigint, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_liberar(bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_anular(bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_fdi_compra_cancelar(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_pagar(bigint, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_liberar(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_anular(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_cancelar(bigint, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12) Verificación final del archivo (falla si algo no quedó como se dijo)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_n integer;
BEGIN
    IF to_regclass('public.fdi_dat_compra_aporte') IS NULL THEN
        RAISE EXCEPTION '07: no se creó fdi_dat_compra_aporte';
    END IF;

    SELECT count(*) INTO v_n
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_aporte'
       AND column_name IN ('id_compra','id_inversor','naturaleza','moneda','monto',
                           'tasa_a_total','monto_eq_total','tasa_interes','comprobante',
                           'estado','idempotency_key','devuelto_at','motivo_devolucion');
    IF v_n <> 13 THEN
        RAISE EXCEPTION '07: fdi_dat_compra_aporte tiene % de 13 columnas esperadas', v_n;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_aporte'
                  AND column_name = 'monto_eq_total' AND is_generated <> 'ALWAYS') THEN
        RAISE EXCEPTION '07: monto_eq_total debe ser columna generada';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'fdi_pago_fuente_check' AND conrelid = 'public.fdi_dat_compra_pago'::regclass) THEN
        RAISE EXCEPTION '07: falta la restricción fdi_pago_fuente_check';
    END IF;

    SELECT count(*) INTO v_n
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_pago'
       AND column_name IN ('id_cuenta','id_medio_pago') AND is_nullable = 'YES';
    IF v_n <> 2 THEN
        RAISE EXCEPTION '07: id_cuenta/id_medio_pago deben admitir NULL para aportes (% de 2)', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
     WHERE NOT t.tgisinternal
       AND t.tgname IN ('trg_fdi_aporte_inversores','trg_fdi_reserva_solo_fondo',
                        'trg_fdi_pago_coherente','trg_fdi_compra_modo_inmutable',
                        'trg_fdi_ajuste_solo_fondo','trg_fdi_recepcion_solo_fondo');
    IF v_n <> 6 THEN
        RAISE EXCEPTION '07: faltan triggers de exclusividad (% de 6)', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_compra_aportes','fn_fdi_compra_aporte_registrar',
                         'fn_fdi_compra_aporte_devolver');
    IF v_n <> 3 THEN
        RAISE EXCEPTION '07: faltan RPC de aportes (% de 3)', v_n;
    END IF;

    -- Los cuerpos de la fase 4 quedaron con su rama de aportes.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_pagar'
                      AND p.prosrc LIKE '%7a) Modo inversores%'
                      AND p.prosrc LIKE '%id_aporte%') THEN
        RAISE EXCEPTION '07: fn_fdi_compra_pagar no tiene la rama de aportes';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_anular'
                      AND p.prosrc LIKE '%CONTINUE%') THEN
        RAISE EXCEPTION '07: fn_fdi_compra_anular no salta los pagos con aporte';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_cancelar'
                      AND p.prosrc LIKE '%devuélvalos antes de cancelar%') THEN
        RAISE EXCEPTION '07: fn_fdi_compra_cancelar no exige devolver los aportes';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_liberar'
                      AND p.prosrc LIKE '%devuelva los aportes en vez de liberar%') THEN
        RAISE EXCEPTION '07: fn_fdi_compra_liberar no rechaza el modo inversores';
    END IF;

    -- El ajuste tardío de una compra de inversores ya no choca con el trigger.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_ajuste_agregar'
                      AND p.prosrc LIKE '%''inversores'' THEN ''externo''%') THEN
        RAISE EXCEPTION '07: fn_fdi_compra_ajuste_agregar no elige el origen por modo';
    END IF;

    IF to_regclass('public.uq_fdi_aporte_id_compra') IS NULL THEN
        RAISE EXCEPTION '07: falta el índice único (id, id_compra) del aporte';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.fdi_dat_compra_pago'::regclass
                      AND conname = 'fdi_pago_aporte_fk'
                      AND pg_get_constraintdef(oid) LIKE '%(id_aporte, id_compra)%') THEN
        RAISE EXCEPTION '07: la FK del pago no amarra (id_aporte, id_compra)';
    END IF;

    RAISE NOTICE '07: aportes de inversores instalados (tabla, 6 triggers, 3 RPC, 4 cuerpos de la fase 4).';
END;
$$;