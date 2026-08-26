-- ============================================================================
-- 19 · Fase 3 · Rol jefe de cocina
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- ESTADO VERIFICADO ANTES DE ESCRIBIR (via MCP)
-- ---------------------------------------------
-- El patron de asignacion de roles es una tabla por rol, todas con la misma
-- forma: uuid + ambito + id_trabajador.
--
--   app_dat_vendedor     uuid, id_tpv,     id_trabajador  (+ extras de venta)
--   app_dat_almacenero   uuid, id_almacen, id_trabajador
--   app_dat_supervisor   uuid, id_tienda,  id_trabajador
--   app_dat_gerente      uuid, id_tienda,  id_trabajador
--
-- app_dat_trabajadores tiene uuid, id_tienda, id_roll (-> seg_roll), nombres,
-- apellidos, user_mail, deleted_at.
--
-- seg_roll es POR TIENDA (id_tienda NOT NULL) y ya contiene roles de cocina
-- creados a mano en la tienda 1: "Chef Ejecutivo" (8), "Ayudante Cocina" (9),
-- "Pastelero" (13). Es decir: seg_roll es un catalogo descriptivo de puestos,
-- NO el mecanismo de permisos. Los permisos salen de en que tabla de rol esta
-- el uuid, que es lo que consulta check_user_has_access_to_tienda.
--
-- DECISION DE DISENO
-- ------------------
-- Se crea app_dat_jefe_cocina siguiendo el patron exacto de app_dat_almacenero,
-- porque es el rol mas parecido: ambito = un recurso concreto (su cocina), no
-- la tienda entera.
--
-- El plan ya decidio "no reusar solo el rol almacenero para jefe de cocina
-- (misma forma de asignacion, permisos distintos)". Esto lo respeta: misma
-- forma, tabla propia.
--
-- Un jefe de cocina puede tener MAS DE UNA cocina (un chef que cubre dos
-- estaciones en un turno flojo), asi que la UNIQUE es (uuid, id_cocina) y no
-- solo uuid. Igual que un almacenero puede estar en varios almacenes.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Aplicar este archivo (idempotente).
--   2. Correr la VERIFICACION.
--   3. Despues el 20 (RPC del KDS) y el 21 (UI).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 19.1 app_dat_jefe_cocina
--
-- ON DELETE CASCADE en id_cocina: si se elimina la cocina, la asignacion no
-- tiene sentido. Ojo que fn_eliminar_cocina es SOFT delete (pone deleted_at),
-- asi que en la practica el CASCADE casi nunca dispara; esta por integridad si
-- alguien borra de verdad.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_jefe_cocina (
    id             bigserial PRIMARY KEY,
    uuid           uuid        NOT NULL,
    id_cocina      bigint      NOT NULL
                   REFERENCES public.app_dat_cocina(id) ON DELETE CASCADE,
    id_trabajador  bigint      REFERENCES public.app_dat_trabajadores(id),

    -- Distingue al jefe (puede producir tandas, recepcionar, contar) del
    -- cocinero (solo KDS). El plan lo deja como opcional en 3.1; se resuelve
    -- con una columna en vez de una segunda tabla para no duplicar toda la
    -- logica de permisos por una diferencia de grado.
    es_jefe        boolean     NOT NULL DEFAULT true,

    created_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_jefe_cocina_uuid_cocina UNIQUE (uuid, id_cocina)
);

COMMENT ON TABLE public.app_dat_jefe_cocina IS
    'Asignacion de un trabajador a una cocina. Mismo patron que app_dat_almacenero.';
COMMENT ON COLUMN public.app_dat_jefe_cocina.es_jefe IS
    'true = jefe de cocina (KDS + inventario de su cocina); false = cocinero (solo KDS).';

CREATE INDEX IF NOT EXISTS idx_jefe_cocina_uuid
    ON public.app_dat_jefe_cocina (uuid);

CREATE INDEX IF NOT EXISTS idx_jefe_cocina_cocina
    ON public.app_dat_jefe_cocina (id_cocina);


-- ----------------------------------------------------------------------------
-- 19.2 Ampliar check_user_has_access_to_tienda
--
-- ══════════════════════════════════════════════════════════════════════════
-- ESTE ES EL CAMBIO MAS DELICADO DE TODA LA FASE 3.
--
-- check_user_has_access_to_tienda es el UNICO control de acceso del proyecto
-- (no hay RLS). La usan decenas de RPC. Si se rompe, se cae todo.
--
-- Se le anade un UNION mas para que un jefe de cocina tenga acceso a la tienda
-- de su cocina. Sin esto no podria ni leer sus propias comandas.
--
-- Se reescribe con el cuerpo EXPORTADO de produccion, anadiendo solo el bloque
-- nuevo. Los cinco UNION existentes quedan intactos.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.check_user_has_access_to_tienda(id_tienda_param bigint)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    user_has_access boolean;
BEGIN
    -- Verificar si el usuario tiene acceso a la tienda en cualquiera de los roles
    SELECT EXISTS (
        SELECT 1 FROM app_dat_vendedor WHERE uuid = auth.uid() AND id_tpv IN (
            SELECT id FROM app_dat_tpv WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM app_dat_almacenero WHERE uuid = auth.uid() AND id_almacen IN (
            SELECT id FROM app_dat_almacen WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM auditor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        -- FASE 3: jefe de cocina / cocinero. Su ambito es la cocina, y la
        -- cocina pertenece a una tienda.
        SELECT 1 FROM app_dat_jefe_cocina jc
          JOIN app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    -- Si no tiene acceso, lanzar error
    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;


-- ----------------------------------------------------------------------------
-- 19.3 fn_cocinas_del_usuario
--
-- Devuelve las cocinas que el usuario actual puede operar. Es la base del KDS:
-- la pantalla no pregunta "dame las comandas de la cocina X", pregunta "dame
-- lo mio", y el backend decide el alcance.
--
-- Asi un jefe de cocina A no puede ver la cocina B ni pasandole el id a mano,
-- que es el criterio de aceptacion del plan ("Jefe de cocina A no ve comandas
-- ni stock de cocina B").
--
-- Gerente y supervisor ven TODAS las cocinas de su tienda: necesitan poder
-- diagnosticar sin tener que asignarse a si mismos.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cocinas_del_usuario()
RETURNS TABLE (
    id_cocina     bigint,
    denominacion  text,
    id_tienda     bigint,
    id_almacen    bigint,
    activa        boolean,
    es_jefe       boolean,
    via           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
    -- Asignacion directa a la cocina
    SELECT c.id, c.denominacion, c.id_tienda, c.id_almacen, c.activa,
           jc.es_jefe,
           CASE WHEN jc.es_jefe THEN 'jefe_cocina' ELSE 'cocinero' END AS via
      FROM app_dat_jefe_cocina jc
      JOIN app_dat_cocina c ON c.id = jc.id_cocina
     WHERE jc.uuid = auth.uid()
       AND c.deleted_at IS NULL

    UNION

    -- Gerente: todas las cocinas de su tienda
    SELECT c.id, c.denominacion, c.id_tienda, c.id_almacen, c.activa,
           true, 'gerente'
      FROM app_dat_gerente g
      JOIN app_dat_cocina c ON c.id_tienda = g.id_tienda
     WHERE g.uuid = auth.uid()
       AND c.deleted_at IS NULL

    UNION

    -- Supervisor: idem
    SELECT c.id, c.denominacion, c.id_tienda, c.id_almacen, c.activa,
           true, 'supervisor'
      FROM app_dat_supervisor s
      JOIN app_dat_cocina c ON c.id_tienda = s.id_tienda
     WHERE s.uuid = auth.uid()
       AND c.deleted_at IS NULL

    ORDER BY 3, 2;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cocinas_del_usuario()
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 19.4 fn_usuario_puede_operar_cocina
--
-- Guard reutilizable para las RPC del KDS. Devuelve void y lanza excepcion,
-- igual que check_user_has_access_to_tienda, para que el patron sea el mismo
-- que ya usa todo el proyecto.
--
-- p_requiere_jefe: para operaciones que un cocinero no debe hacer (producir
-- tandas, recepcionar mercancia). Cambiar el estado de una comanda si.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_usuario_puede_operar_cocina(
    p_id_cocina      bigint,
    p_requiere_jefe  boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_es_jefe boolean;
    v_existe  boolean;
BEGIN
    -- OJO: aqui iba 'SELECT true, bool_or(...)'. Al ser una agregacion sin
    -- GROUP BY siempre devuelve UNA fila, asi que v_existe salia true incluso
    -- sin coincidencias y CUALQUIERA podia operar CUALQUIER cocina. El guard
    -- no guardaba nada. Con count(*) > 0 el chequeo es real.
    SELECT count(*) > 0, bool_or(cu.es_jefe)
      INTO v_existe, v_es_jefe
      FROM fn_cocinas_del_usuario() cu
     WHERE cu.id_cocina = p_id_cocina;

    IF NOT COALESCE(v_existe, false) THEN
        RAISE EXCEPTION 'Acceso denegado: no tienes asignada esta cocina'
            USING ERRCODE = 'P0001';
    END IF;

    IF p_requiere_jefe AND NOT COALESCE(v_es_jefe, false) THEN
        RAISE EXCEPTION 'Acceso denegado: esta operacion requiere ser jefe de cocina'
            USING ERRCODE = 'P0001';
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_usuario_puede_operar_cocina(bigint, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 19.5 RPC de asignacion (para el admin)
--
-- Espejo de como el admin asigna almaceneros. Solo gerente/supervisor de la
-- tienda de la cocina pueden asignar, de ahi el guard por tienda.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_asignar_jefe_cocina(
    p_uuid          uuid,
    p_id_cocina     bigint,
    p_id_trabajador bigint  DEFAULT NULL,
    p_es_jefe       boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_cocina    text;
    v_id        bigint;
    v_ya        boolean := false;
BEGIN
    SELECT c.id_tienda, c.denominacion
      INTO v_id_tienda, v_cocina
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    -- El trabajador, si se indica, debe ser de la misma tienda.
    IF p_id_trabajador IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM app_dat_trabajadores t
             WHERE t.id = p_id_trabajador
               AND t.id_tienda = v_id_tienda
               AND t.deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'El trabajador no pertenece a la tienda de la cocina',
                'error_code', 'TRABAJADOR_TIENDA_MISMATCH'
            );
        END IF;
    END IF;

    SELECT id INTO v_id
      FROM app_dat_jefe_cocina
     WHERE uuid = p_uuid AND id_cocina = p_id_cocina;

    IF v_id IS NOT NULL THEN
        -- Idempotente, igual que fn_asignar_tpv_cocina: reasignar actualiza el
        -- nivel en vez de fallar.
        UPDATE app_dat_jefe_cocina
           SET es_jefe = p_es_jefe,
               id_trabajador = COALESCE(p_id_trabajador, id_trabajador)
         WHERE id = v_id;
        v_ya := true;
    ELSE
        INSERT INTO app_dat_jefe_cocina (uuid, id_cocina, id_trabajador, es_jefe)
        VALUES (p_uuid, p_id_cocina, p_id_trabajador, p_es_jefe)
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object(
        'status',     'success',
        'id',         v_id,
        'ya_existia', v_ya,
        'id_cocina',  p_id_cocina,
        'cocina',     v_cocina,
        'es_jefe',    p_es_jefe,
        'message',    CASE WHEN p_es_jefe
                        THEN 'Asignado como jefe de ' || v_cocina
                        ELSE 'Asignado como cocinero de ' || v_cocina END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_asignar_jefe_cocina(uuid, bigint, bigint, boolean)
    TO anon, authenticated, service_role;


CREATE OR REPLACE FUNCTION public.fn_desasignar_jefe_cocina(
    p_uuid      uuid,
    p_id_cocina bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_borradas  integer;
BEGIN
    SELECT c.id_tienda INTO v_id_tienda
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    DELETE FROM app_dat_jefe_cocina
     WHERE uuid = p_uuid AND id_cocina = p_id_cocina;

    GET DIAGNOSTICS v_borradas = ROW_COUNT;

    RETURN jsonb_build_object(
        'status',    'success',
        'eliminado', v_borradas > 0,
        'message',   CASE WHEN v_borradas > 0
                       THEN 'Asignacion eliminada'
                       ELSE 'No estaba asignado a esa cocina' END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_desasignar_jefe_cocina(uuid, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 19.6 fn_listar_personal_cocina
--
-- Para la pantalla del admin: quien opera cada cocina.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_personal_cocina(
    p_id_cocina bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_result    jsonb;
BEGIN
    SELECT c.id_tienda INTO v_id_tienda
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id',            jc.id,
                'uuid',          jc.uuid,
                'id_trabajador', jc.id_trabajador,
                'nombre',        TRIM(COALESCE(t.nombres, '') || ' ' || COALESCE(t.apellidos, '')),
                'email',         t.user_mail,
                'es_jefe',       jc.es_jefe,
                'rol',           CASE WHEN jc.es_jefe THEN 'Jefe de cocina' ELSE 'Cocinero' END,
                'created_at',    jc.created_at
            ) ORDER BY jc.es_jefe DESC, t.nombres), '[]'::jsonb)
      INTO v_result
      FROM app_dat_jefe_cocina jc
      LEFT JOIN app_dat_trabajadores t ON t.id = jc.id_trabajador
     WHERE jc.id_cocina = p_id_cocina;

    RETURN jsonb_build_object(
        'status',    'success',
        'id_cocina', p_id_cocina,
        'personal',  v_result,
        'total',     jsonb_array_length(v_result)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_personal_cocina(bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) La tabla y su constraint de unicidad
SELECT c.relname AS tabla,
       (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columnas
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'app_dat_jefe_cocina';

SELECT conname, pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
 WHERE conrelid = 'public.app_dat_jefe_cocina'::regclass
 ORDER BY conname;

-- (b) check_user_has_access_to_tienda debe tener el bloque nuevo Y conservar
--     los cinco roles anteriores -> todo true
SELECT (prosrc LIKE '%app_dat_jefe_cocina%')  AS tiene_jefe_cocina,
       (prosrc LIKE '%app_dat_vendedor%')     AS conserva_vendedor,
       (prosrc LIKE '%app_dat_almacenero%')   AS conserva_almacenero,
       (prosrc LIKE '%app_dat_supervisor%')   AS conserva_supervisor,
       (prosrc LIKE '%auditor%')              AS conserva_auditor,
       (prosrc LIKE '%app_dat_gerente%')      AS conserva_gerente
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'check_user_has_access_to_tienda';

-- (c) Las 4 funciones nuevas
SELECT p.oid::regprocedure AS firma, p.prosecdef AS security_definer
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_cocinas_del_usuario', 'fn_usuario_puede_operar_cocina',
                     'fn_asignar_jefe_cocina', 'fn_desasignar_jefe_cocina',
                     'fn_listar_personal_cocina')
 ORDER BY p.proname;
