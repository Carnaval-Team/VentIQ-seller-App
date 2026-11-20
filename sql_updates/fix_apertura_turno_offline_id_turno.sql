BEGIN;

-- fix_apertura_turno_offline_id_turno
--
-- Problema (newa 2026-11-20, apertura de turno online desde el TPV nuevo):
--   insert or update on table "app_dat_caja_turno_moneda" violates foreign key
--   constraint "app_dat_caja_turno_moneda_id_turno_fkey"
--
-- Causa: fn_apertura_turno_offline devuelve en 'id_turno' el valor de
--   registrar_apertura_turno_v3, que es el id de la OPERACIÓN de apertura
--   (app_dat_operaciones.id), no el id del turno (app_dat_caja_turno.id).
--   Las ramas «reutilizar turno abierto» sí devuelven el id del turno, así que
--   el contrato era inconsistente. Quienes consumen 'id_turno' lo tratan como
--   id de turno:
--     - fn_apertura_turno_offline_monedas inserta en app_dat_caja_turno_moneda
--       (FK al turno) -> violación de FK (o, si coincidiera un id ajeno, fila
--       en el turno equivocado).
--     - fn_apertura_turno_offline_usd hace UPDATE app_dat_caja_turno WHERE id =
--       <id de operación> -> no actualiza el turno (o toca otro).
--     - fn_turno_alinear_fecha_apertura(<id de operación>) -> alinea otro turno
--       o ninguno.
--     - el cliente consulta app_dat_caja_turno.eq('id', id_turno).
--   El mismo defecto existe hoy en main (cuerpo idéntico); allí no se manifiesta
--   porque ningún cliente publicado llama la variante _monedas.
--
-- Cambio: en la rama de creación se resuelve el id del turno recién creado
--   (id_operacion_apertura = id de la operación) y ese id es el que se usa para
--   alinear la fecha, guardar la evidencia de idempotencia y responder.
--   En el replay se resuelve el turno también para las claves antiguas que
--   guardaron el id de la operación (acotado a TPV + vendedor de la solicitud).
--   Se añade 'id_operacion' a la respuesta (informativo).
-- No cambia firma, permisos ni la huella de idempotencia.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
    v_src text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres';
    END IF;
    SELECT prosrc INTO v_src
    FROM pg_proc
    WHERE oid = to_regprocedure('public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)');
    IF v_src IS NULL THEN
        RAISE EXCEPTION 'fn_apertura_turno_offline no existe';
    END IF;
    IF position('v_turno_resuelto' IN v_src) > 0 THEN
        RAISE NOTICE 'Ya aplicado: fn_apertura_turno_offline resuelve el id del turno';
    ELSIF position('fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura)' IN v_src) = 0 THEN
        RAISE EXCEPTION 'fn_apertura_turno_offline no tiene el cuerpo esperado de R33';
    END IF;
    IF to_regprocedure('public.fn_turno_alinear_fecha_apertura(bigint,timestamptz)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.registrar_apertura_turno_v3(numeric,bigint,bigint,uuid,boolean,jsonb,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta una dependencia de R33';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(
    p_client_uuid uuid,
    p_efectivo_inicial numeric,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean DEFAULT false,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL::text,
    p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_open bigint;
    v_new_op bigint;
    v_new_id bigint;
    v_turno_resuelto bigint;
    v_allowed boolean;
    v_extra text;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL
       OR p_id_tpv IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'efectivo_inicial', p_efectivo_inicial,
        'id_tpv', p_id_tpv,
        'id_vendedor', p_id_vendedor,
        'usuario', p_usuario,
        'maneja_inventario', p_maneja_inventario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_apertura', p_fecha_apertura,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    -- R33: dos claves distintas del mismo TPV + vendedor se serializan.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', p_id_tpv, p_id_vendedor), 0)
    );
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'apertura_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación (ver cabecera, punto 6).
           OR (v_existing.m01_solicitud - 'fecha_apertura') IS DISTINCT FROM (v_request - 'fecha_apertura')
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        -- id_operacion guarda el id del turno; las claves anteriores a este fix
        -- pudieron guardar el id de la operación de apertura. Se resuelve el
        -- turno del mismo TPV + vendedor que ya pasó la comparación de huella.
        SELECT ct.id INTO v_turno_resuelto
        FROM public.app_dat_caja_turno ct
        WHERE (ct.id = v_existing.id_operacion
               OR ct.id_operacion_apertura = v_existing.id_operacion)
          AND ct.id_tpv = p_id_tpv
          AND ct.id_vendedor = p_id_vendedor
        ORDER BY (ct.id = v_existing.id_operacion) DESC, ct.id DESC
        LIMIT 1;
        v_turno_resuelto := COALESCE(v_turno_resuelto, v_existing.id_operacion);
        -- R33: si el turno sigue abierto, recuperar la apertura real.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_turno_resuelto, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_turno', v_turno_resuelto,
            'message', 'Apertura ya procesada'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv
    FOR SHARE;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_allowed := public.fn_config_tienda_puede_escribir(v_store) IS TRUE
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
        );
    IF v_allowed IS DISTINCT FROM true
       OR (p_usuario IS NOT NULL AND p_usuario IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_open
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_open IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
        VALUES (p_client_uuid, v_open, 'apertura_turno', v_actor, v_request, v_store);
        -- R33: antes se reutilizaba sin fecha → apertura = hora del sync.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_open, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', false,
            'id_turno', v_open,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    -- registrar_apertura_turno_v3 devuelve el id de la OPERACIÓN de apertura.
    v_new_op := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := COALESCE(p_usuario, v_actor),
        p_maneja_inventario := COALESCE(p_maneja_inventario, false),
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_new_op IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó la apertura' USING ERRCODE = '42501';
    END IF;
    SELECT ct.id INTO v_new_id
    FROM public.app_dat_caja_turno ct
    WHERE ct.id_operacion_apertura = v_new_op;
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró el turno de la apertura %', v_new_op;
    END IF;
    -- R33: mismos límites que al reutilizar (antes: UPDATE sin acotar).
    PERFORM public.fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura);
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'apertura_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id,
        'id_operacion', v_new_op, 'idempotent', false
    );
END;
$function$;

-- Verificación
DO $verify$
DECLARE
    v_src text;
BEGIN
    SELECT prosrc INTO v_src
    FROM pg_proc
    WHERE oid = to_regprocedure('public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)');
    IF position('v_new_op' IN v_src) = 0 OR position('v_turno_resuelto' IN v_src) = 0 THEN
        RAISE EXCEPTION 'La función no quedó con el cuerpo corregido';
    END IF;
END;
$verify$;

COMMIT;
