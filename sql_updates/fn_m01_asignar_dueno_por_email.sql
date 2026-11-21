-- =============================================================================
-- Asigna el rol Dueño de una tienda a un usuario identificado por email.
--
-- Uso (SQL Editor o cliente con service_role):
--   SELECT public.fn_m01_asignar_dueno_por_email('correo@ejemplo.com', 8);
--   SELECT public.fn_m01_asignar_dueno_por_email('correo@ejemplo.com', 8, 'Nombre', 'Apellidos');
--
-- Reglas:
--   * El usuario debe existir en auth.users (ya tiene que haberse registrado).
--   * Desde la app (rol authenticated) solo puede llamarla un Dueño de esa
--     tienda o un superadmin activo (fn_user_is_dueno). Desde el SQL Editor
--     auth.uid() es NULL y la comprobación no aplica: por eso no se usa
--     "auth.uid() IS NULL" como rechazo, sino "auth.uid() IS NOT NULL AND ...".
--     Los permisos de EXECUTE ya excluyen a anon y a PUBLIC.
--   * Registra el dueño en app_dat_dueno y, como hace fn_agregar_rol_trabajador,
--     también en app_dat_gerente para que las RPC históricas lo autoricen.
--   * Si se pasan p_nombres/p_apellidos crea (o reutiliza) el trabajador de la
--     tienda y enlaza id_trabajador en ambas tablas. Sin nombres no crea
--     trabajador: el acceso funciona igual, pero no aparece en el listado de
--     personal.
--   * Idempotente: si ya es dueño o gerente de esa tienda no duplica filas.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_m01_asignar_dueno_por_email(
    p_email text,
    p_id_tienda bigint,
    p_nombres text DEFAULT NULL,
    p_apellidos text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_uuid uuid;
    v_trabajador_id bigint;
    v_ya_dueno boolean;
BEGIN
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Falta el id de la tienda';
    END IF;

    IF auth.uid() IS NOT NULL AND NOT public.fn_user_is_dueno(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo un Dueño o un superadmin de la tienda puede asignar el rol Dueño'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda) THEN
        RAISE EXCEPTION 'No existe la tienda %', p_id_tienda;
    END IF;

    SELECT u.id INTO v_uuid
    FROM auth.users u
    WHERE lower(u.email) = lower(trim(p_email))
    LIMIT 1;

    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'No existe ningún usuario registrado con el email %', p_email;
    END IF;

    -- Trabajador opcional: solo si se pasan nombres.
    IF p_nombres IS NOT NULL AND trim(p_nombres) <> '' THEN
        SELECT t.id INTO v_trabajador_id
        FROM public.app_dat_trabajadores t
        WHERE t.uuid = v_uuid AND t.id_tienda = p_id_tienda AND t.deleted_at IS NULL
        ORDER BY t.id
        LIMIT 1;

        IF v_trabajador_id IS NULL THEN
            INSERT INTO public.app_dat_trabajadores (uuid, nombres, apellidos, id_tienda)
            VALUES (v_uuid, trim(p_nombres), coalesce(trim(p_apellidos), ''), p_id_tienda)
            RETURNING id INTO v_trabajador_id;
        END IF;
    END IF;

    -- Dueño (una sola fila por usuario y tienda).
    SELECT EXISTS (
        SELECT 1 FROM public.app_dat_dueno d
        WHERE d.uuid = v_uuid AND d.id_tienda = p_id_tienda
    ) INTO v_ya_dueno;

    IF NOT v_ya_dueno THEN
        INSERT INTO public.app_dat_dueno (uuid, id_tienda, id_trabajador)
        VALUES (v_uuid, p_id_tienda, v_trabajador_id);
    END IF;

    -- Gerente, para que las RPC históricas lo autoricen igual que a un Dueño.
    IF NOT EXISTS (
        SELECT 1 FROM public.app_dat_gerente g
        WHERE g.uuid = v_uuid AND g.id_tienda = p_id_tienda
    ) THEN
        INSERT INTO public.app_dat_gerente (uuid, id_tienda, id_trabajador)
        VALUES (v_uuid, p_id_tienda, v_trabajador_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'uuid', v_uuid,
        'id_tienda', p_id_tienda,
        'id_trabajador', v_trabajador_id,
        'ya_era_dueno', v_ya_dueno,
        'message', CASE WHEN v_ya_dueno
            THEN 'El usuario ya era Dueño de la tienda'
            ELSE 'Rol Dueño asignado' END
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_asignar_dueno_por_email(text, bigint, text, text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_asignar_dueno_por_email(text, bigint, text, text)
    TO authenticated, service_role;
