-- ============================================================================
-- 04_compra_liquidacion_rollback.sql — reversa de la fase 4 (reserva y pago)
--
-- REQUIERE: 04_compra_liquidacion.sql aplicado (es lo que se revierte) y
--           03b_compra_rpcs.sql aplicado (es el estado al que se vuelve:
--           aquí se restaura el `fn_fdi_compra_cancelar` de 03b).
--
-- SOLO DDL + el mínimo DML de reversa que exige restaurar el CHECK del ledger
-- (ver §4). Todo en UNA transacción: o revierte, o no toca nada.
--
-- QUÉ REVIERTE
--   1. DROP de las 5 RPC de liquidación.
--   2. `fn_fdi_compra_cancelar` vuelve al cuerpo de 03b (el 04 le añadió el
--      paso por `reservada`; si se dejara así, quedaría una función viva
--      apuntando a una tabla que ya no existe → falla en runtime).
--   3. `_fdi_aplicar_movimiento` vuelve a 11 args y RETURNS void
--      (el 04 lo subió a 13 args y bigint). No es opcional: la versión de 13
--      args escribe `id_compra` y `tasa`, columnas que este script borra.
--      Sin restaurarla el módulo FDI entero (`fn_fdi_ingreso_manual`,
--      `fn_fdi_gasto`, `fn_fdi_ajuste`, `fn_fdi_inversion_anular`…) revienta
--      en el primer movimiento.
--   4. `fdi_dat_movimiento` pierde `id_compra` (con su FK) y `tasa`.
--   5. El CHECK de `tipo` vuelve a los 10 valores de 01/02a.
--   6. Se borran `fdi_dat_compra_reserva` y `fdi_dat_compra_pago`.
--
-- LO QUE CAE SOLO CON LAS TABLAS (no hace falta nombrarlo): políticas RLS,
-- GRANTs, índices (`idx_fdi_reserva_compra`, `idx_fdi_reserva_clave`,
-- `idx_fdi_pago_compra`), CHECKs, FKs y las secuencias IDENTITY de cada id.
--
-- POR QUÉ ABORTA SI HAY DATOS
--   Una reserva es dinero apartado y un pago es dinero ya salido del fondo.
--   Borrarlos sin más deja el ledger descuadrado o, peor, hace desaparecer el
--   rastro de un débito real. Además, si existen movimientos `pago_compra` /
--   `devolucion_compra` el CHECK viejo NO se puede volver a poner: ésos son
--   justamente los valores que el 04 añadió. Por eso la guardia mira las dos
--   cosas (filas en las tablas y movimientos con los tipos nuevos).
--   El camino correcto NO es forzar: es deshacer cada compra con
--   `fn_fdi_compra_anular` (devuelve el dinero) o `fn_fdi_compra_cancelar`
--   (suelta la reserva) ANTES de ejecutar este script.
--
-- CÓMO FORZAR (solo con los datos ya exportados/archivados)
--   Opción A, misma sesión:
--       select set_config('ventiq.forzar_rollback_compra', 'on', false);
--       -- y a continuación este script
--   Opción B, si el editor no conserva la sesión: cambiar temporalmente el
--   DECLARE de la guardia a `v_forzar boolean := true;`.
--
--   Al forzar, §4 devuelve al saldo el importe de cada movimiento
--   `pago_compra`/`devolucion_compra` y borra esos movimientos. Es lo único
--   que mantiene la conciliación en 0 cuando el rastro desaparece del ledger:
--   el dinero vuelve a estar en la clave del fondo como si el pago nunca
--   hubiera ocurrido. El bloque final lo verifica y, si no cuadra, deshace
--   TODO el script (incluido el borrado de las tablas).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Guardias
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_forzar   boolean := ('on' = coalesce(current_setting('ventiq.forzar_rollback_compra', true), 'off'));
    v_reservas bigint := 0;
    v_pagos    bigint := 0;
    v_movs     bigint := 0;
    v_compras  text;
BEGIN
    -- 0.1) Datos vivos en las 2 tablas: no se destruyen a ciegas.
    IF to_regclass('public.fdi_dat_compra_reserva') IS NOT NULL THEN
        SELECT count(*) INTO v_reservas FROM public.fdi_dat_compra_reserva;
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NOT NULL THEN
        SELECT count(*) INTO v_pagos FROM public.fdi_dat_compra_pago;
    END IF;

    -- 0.2) Movimientos con los tipos que el CHECK viejo no admite. Bloquean
    --      la restauración del CHECK aunque las tablas estén vacías.
    IF to_regclass('public.fdi_dat_movimiento') IS NOT NULL
       AND EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'fdi_dat_movimiento_tipo_check'
                      AND conrelid = 'public.fdi_dat_movimiento'::regclass
                      AND pg_get_constraintdef(oid) LIKE '%pago_compra%') THEN
        SELECT count(*) INTO v_movs
          FROM public.fdi_dat_movimiento
         WHERE tipo IN ('pago_compra','devolucion_compra');
    END IF;

    IF (v_reservas > 0 OR v_pagos > 0 OR v_movs > 0) AND NOT v_forzar THEN
        SELECT string_agg(DISTINCT c.numero_compra::text, ', ' ORDER BY c.numero_compra::text)
          INTO v_compras
          FROM public.fdi_dat_compra c
         WHERE c.id IN (
                 SELECT r.id_compra FROM public.fdi_dat_compra_reserva r
                 UNION
                 SELECT p.id_compra FROM public.fdi_dat_compra_pago p
                 UNION
                 SELECT m.id_compra FROM public.fdi_dat_movimiento m
                  WHERE m.tipo IN ('pago_compra','devolucion_compra')
                    AND m.id_compra IS NOT NULL);

        RAISE EXCEPTION
            'La fase 4 tiene datos vivos: % reserva(s), % pago(s) y % movimiento(s) de compra. No se borra nada.',
            v_reservas, v_pagos, v_movs
            USING HINT = 'Deshaz primero esas compras con fn_fdi_compra_anular / fn_fdi_compra_cancelar'
                      || coalesce(' (compras nº ' || v_compras || ')', '')
                      || '. Para forzar con los datos ya archivados: '
                      || 'select set_config(''ventiq.forzar_rollback_compra'',''on'',false); '
                      || 'en la misma sesión (o pon v_forzar := true en este script).';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Las 5 RPC de liquidación, con su firma exacta.
--    Van primero: son las que leen las tablas y las columnas que se borran.
--    IF EXISTS + firma exacta: si alguna no está, el script sigue; si está,
--    no se lleva por delante un overload distinto.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_disponible(bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_reservar(bigint, jsonb, uuid);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_pagar(bigint, numeric);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_liberar(bigint, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_anular(bigint, text);

-- ---------------------------------------------------------------------------
-- 2) `fn_fdi_compra_cancelar` vuelve al cuerpo de 03b.
--    El 04 le metió `UPDATE fdi_dat_compra_reserva ... WHERE estado='activa'`
--    y amplió los estados de entrada a ('creada','reservada'). Con la tabla
--    borrada esa sentencia no compila en runtime, así que se restaura la
--    versión publicada por 03b tal cual (solo estado 'creada').
--    Los GRANT/REVOKE se conservan: CREATE OR REPLACE no toca los ACL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_cancelar(
    p_id_compra bigint,
    p_motivo    text
) RETURNS jsonb
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
    IF v_c.estado <> 'creada' THEN
        RAISE EXCEPTION 'Solo se cancela una compra en estado creada (actual: %)', v_c.estado
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion WHERE id_compra = p_id_compra) THEN
        RAISE EXCEPTION 'La compra ya tiene recepciones' USING ERRCODE = '22023';
    END IF;

    UPDATE public.fdi_dat_compra
       SET estado = 'cancelada', observacion = COALESCE(observacion,'')
           || CASE WHEN observacion IS NULL OR observacion = '' THEN '' ELSE ' · ' END
           || 'Cancelada: ' || btrim(p_motivo),
           updated_at = now()
     WHERE id = p_id_compra;

    INSERT INTO public.fdi_hist_estado_compra
        (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
    VALUES (p_id_compra, v_c.id_tienda, v_c.estado, 'cancelada', 'manual', btrim(p_motivo), auth.uid());

    RETURN jsonb_build_object('status','ok','id_compra',p_id_compra,'estado','cancelada');
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) `_fdi_aplicar_movimiento` vuelve a los 11 args y a RETURNS void.
--    Se borra la firma de 13 args a propósito: si se dejara viva junto a la de
--    11, cualquier llamada con 10-11 args seguiría cayendo en la nueva y
--    seguiría intentando escribir `id_compra`/`tasa` (que ya no existirán).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public._fdi_aplicar_movimiento(
    bigint, bigint, smallint, text, numeric, character varying, bigint, bigint, bigint, text, uuid, bigint, numeric);

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
    p_observacion      text   DEFAULT NULL,
    p_idempotency_key  uuid   DEFAULT NULL
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

    IF NOT EXISTS (
        SELECT 1 FROM public.fdi_dat_cuenta c
        WHERE c.id = p_id_cuenta AND c.id_tienda = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'La cuenta % no pertenece a la tienda %', p_id_cuenta, p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.app_nom_medio_pago m WHERE m.id = p_id_medio_pago) THEN
        RAISE EXCEPTION 'El medio de pago % no existe', p_id_medio_pago USING ERRCODE = 'P0002';
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
        observacion, created_by, idempotency_key
    ) VALUES (
        p_id_tienda, p_id_cuenta, p_id_medio_pago, v_moneda, round(p_delta, 2),
        v_saldo_previo, v_saldo_nuevo, p_tipo,
        p_id_liquidacion, p_id_transferencia, p_id_inversion,
        p_observacion, auth.uid(), p_idempotency_key
    );
END;
$$;

-- Se mantiene el endurecimiento del 04: el aplicador no es API. Antes del 04
-- estaba abierto a PUBLIC (podías escribir en el ledger con la anon key);
-- restaurarlo abierto sería reintroducir el agujero. El dueño (postgres)
-- conserva EXECUTE, así que las RPC SECURITY DEFINER que lo llaman siguen
-- funcionando igual.
REVOKE ALL ON FUNCTION public._fdi_aplicar_movimiento(
    bigint, bigint, smallint, text, numeric, character varying, bigint, bigint, bigint, text, uuid)
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Las 2 tablas.
--    Sin CASCADE a propósito: si algún objeto externo dependiera de ellas, el
--    DROP falla y la transacción entera se deshace, en vez de arrastrar en
--    silencio lo que no era de este módulo.
--    Van ANTES de tocar el ledger porque `*_reserva.id_movimiento` y
--    `*_pago.id_movimiento` referencian `fdi_dat_movimiento`: con las tablas
--    vivas, borrar un movimiento choca contra la FK.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS public.fdi_dat_compra_reserva;
DROP TABLE IF EXISTS public.fdi_dat_compra_pago;

-- ---------------------------------------------------------------------------
-- 5) Reversa del dinero en el ledger (solo tiene efecto si se forzó con
--    movimientos vivos; si no hay, los UPDATE/DELETE no tocan ninguna fila).
--    Se devuelve al saldo el importe del movimiento (saldo - monto deshace su
--    efecto: monto negativo → suma, positivo → resta) y después se borra la
--    fila. Así la identidad saldo = Σ movimientos sigue en pie y el CHECK
--    viejo se puede volver a crear.
-- ---------------------------------------------------------------------------
UPDATE public.fdi_dat_saldo s
   SET saldo = round(s.saldo - m.monto, 2), updated_at = now()
  FROM (
        SELECT id_cuenta, id_medio_pago, moneda, sum(monto) AS monto
          FROM public.fdi_dat_movimiento
         WHERE tipo IN ('pago_compra','devolucion_compra')
         GROUP BY 1, 2, 3
       ) m
 WHERE s.id_cuenta = m.id_cuenta
   AND s.id_medio_pago = m.id_medio_pago
   AND s.moneda = m.moneda;

DELETE FROM public.fdi_dat_movimiento
 WHERE tipo IN ('pago_compra','devolucion_compra');

-- ---------------------------------------------------------------------------
-- 6) CHECK de `tipo` sin los dos valores nuevos (los 10 de 01/02a).
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_movimiento
    DROP CONSTRAINT IF EXISTS fdi_dat_movimiento_tipo_check;
ALTER TABLE public.fdi_dat_movimiento
    ADD CONSTRAINT fdi_dat_movimiento_tipo_check
    CHECK (tipo IN ('liquidacion', 'transferencia_salida', 'transferencia_entrada',
                    'comision_transferencia', 'extraccion_inversion', 'ingreso_manual',
                    'ajuste', 'ajuste_correccion', 'gasto', 'devolucion_inversion'));

-- ---------------------------------------------------------------------------
-- 7) Columnas del ledger. `id_compra` se lleva su FK por delante; se nombra
--    explícitamente para que quede claro qué cae.
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_movimiento
    DROP CONSTRAINT IF EXISTS fdi_dat_movimiento_id_compra_fkey;
ALTER TABLE public.fdi_dat_movimiento
    DROP COLUMN IF EXISTS id_compra,
    DROP COLUMN IF EXISTS tasa;

-- ---------------------------------------------------------------------------
-- 8) Verificación: o quedó como antes del 04, o se deshace TODO.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_tablas     integer;
    v_rpcs       integer;
    v_cols       integer;
    v_check      text;
    v_firmas     integer;
    v_args       integer;
    v_ret        oid;
    v_cancelar   text;
    v_descuadre  integer;
BEGIN
    -- 8.1) Las 2 tablas, fuera.
    SELECT count(*) INTO v_tablas
    FROM (VALUES ('public.fdi_dat_compra_reserva'), ('public.fdi_dat_compra_pago')) x(t)
    WHERE to_regclass(x.t) IS NOT NULL;
    IF v_tablas <> 0 THEN
        RAISE EXCEPTION 'Quedaron % tabla(s) de liquidación sin borrar', v_tablas;
    END IF;

    -- 8.2) Las 5 RPC, fuera.
    SELECT count(*) INTO v_rpcs
    FROM (VALUES
        ('public.fn_fdi_disponible(bigint)'),
        ('public.fn_fdi_compra_reservar(bigint,jsonb,uuid)'),
        ('public.fn_fdi_compra_pagar(bigint,numeric)'),
        ('public.fn_fdi_compra_liberar(bigint,text)'),
        ('public.fn_fdi_compra_anular(bigint,text)')) x(f)
    WHERE to_regprocedure(x.f) IS NOT NULL;
    IF v_rpcs <> 0 THEN
        RAISE EXCEPTION 'Quedaron % RPC de liquidación publicadas', v_rpcs;
    END IF;

    -- 8.3) Las columnas del ledger, fuera.
    SELECT count(*) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'fdi_dat_movimiento'
      AND column_name IN ('id_compra','tasa');
    IF v_cols <> 0 THEN
        RAISE EXCEPTION 'Quedaron % columna(s) de liquidación en el ledger', v_cols;
    END IF;

    -- 8.4) El CHECK viejo: los 10 valores y ninguno de los 2 nuevos.
    SELECT pg_get_constraintdef(oid) INTO v_check
    FROM pg_constraint
    WHERE conname = 'fdi_dat_movimiento_tipo_check'
      AND conrelid = 'public.fdi_dat_movimiento'::regclass
      AND contype = 'c';
    IF v_check IS NULL THEN
        RAISE EXCEPTION 'No quedó el CHECK de tipo del ledger';
    END IF;
    IF v_check LIKE '%pago_compra%' OR v_check LIKE '%devolucion_compra%' THEN
        RAISE EXCEPTION 'El CHECK de tipo sigue admitiendo los valores de la fase 4: %', v_check;
    END IF;
    IF v_check NOT LIKE '%devolucion_inversion%' OR v_check NOT LIKE '%ajuste_correccion%' THEN
        RAISE EXCEPTION 'El CHECK de tipo quedó incompleto: %', v_check;
    END IF;

    -- 8.5) El aplicador: una sola firma, 11 args, void.
    SELECT count(*) INTO v_firmas
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = '_fdi_aplicar_movimiento';
    IF v_firmas <> 1 THEN
        RAISE EXCEPTION 'Quedaron % firmas de _fdi_aplicar_movimiento (debe ser 1)', v_firmas;
    END IF;

    SELECT p.pronargs, p.prorettype INTO v_args, v_ret
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = '_fdi_aplicar_movimiento';
    IF v_args <> 11 THEN
        RAISE EXCEPTION 'El aplicador quedó con % args (deben ser 11)', v_args;
    END IF;
    IF v_ret <> 'void'::regtype THEN
        RAISE EXCEPTION 'El aplicador quedó devolviendo % (debe ser void)', format_type(v_ret, null);
    END IF;

    -- 8.6) `fn_fdi_compra_cancelar` ya no menciona la tabla borrada.
    SELECT prosrc INTO v_cancelar
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_fdi_compra_cancelar'
      AND p.pronargs = 2;
    IF v_cancelar IS NULL THEN
        RAISE EXCEPTION 'Desapareció fn_fdi_compra_cancelar';
    END IF;
    IF v_cancelar LIKE '%fdi_dat_compra_reserva%' THEN
        RAISE EXCEPTION 'fn_fdi_compra_cancelar sigue apuntando a fdi_dat_compra_reserva';
    END IF;

    -- 8.7) La conciliación del fondo sigue en 0 descuadres (misma lógica que
    --      fn_fdi_conciliacion). Si el borrado de movimientos de §5 dejó el
    --      ledger torcido, esto lo caza y se deshace el script completo.
    SELECT count(*) INTO v_descuadre
    FROM (
        SELECT s.id_tienda, s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
               round(s.saldo - coalesce(m.suma_mov, 0), 2)    AS dif_mov,
               round(s.saldo - coalesce(u.saldo_nuevo, 0), 2) AS dif_ultimo
          FROM public.fdi_dat_saldo s
          LEFT JOIN (SELECT id_tienda, id_cuenta, id_medio_pago, moneda, sum(monto) AS suma_mov
                       FROM public.fdi_dat_movimiento GROUP BY 1,2,3,4) m
                 ON m.id_tienda = s.id_tienda AND m.id_cuenta = s.id_cuenta
                AND m.id_medio_pago = s.id_medio_pago AND m.moneda = s.moneda
          LEFT JOIN (SELECT DISTINCT ON (id_tienda, id_cuenta, id_medio_pago, moneda)
                            id_tienda, id_cuenta, id_medio_pago, moneda, saldo_nuevo
                       FROM public.fdi_dat_movimiento
                      ORDER BY id_tienda, id_cuenta, id_medio_pago, moneda, id DESC) u
                 ON u.id_tienda = s.id_tienda AND u.id_cuenta = s.id_cuenta
                AND u.id_medio_pago = s.id_medio_pago AND u.moneda = s.moneda
    ) j
    WHERE abs(j.dif_mov) >= 0.005 OR abs(j.dif_ultimo) >= 0.005;

    IF v_descuadre > 0 THEN
        RAISE EXCEPTION 'La conciliación quedó rota en % clave(s): se deshace el rollback entero', v_descuadre;
    END IF;
END;
$$;

COMMIT;