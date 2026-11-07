-- =============================================================================
-- Rol Dueño: acceso completo a la tienda, incluida la información de ganancias.
-- Gerente / supervisor / auditor y el resto siguen operando, sin ver ganancias.
-- El alta del primer Dueño la hace un superadmin (o un Dueño ya existente).
-- También se registra en app_dat_gerente para que las RPC históricas que
-- comprueban ese rol sigan autorizando las operaciones de la tienda.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_dat_dueno (
  id bigserial PRIMARY KEY,
  uuid uuid NOT NULL REFERENCES auth.users(id),
  id_tienda bigint NOT NULL REFERENCES public.app_dat_tienda(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  id_trabajador bigint REFERENCES public.app_dat_trabajadores(id)
);

CREATE INDEX IF NOT EXISTS idx_dueno_uuid_tienda
  ON public.app_dat_dueno (uuid, id_tienda);

CREATE UNIQUE INDEX IF NOT EXISTS uq_dueno_trabajador
  ON public.app_dat_dueno (id_trabajador)
  WHERE id_trabajador IS NOT NULL;

COMMENT ON TABLE public.app_dat_dueno IS
  'Dueño de la tienda. Ve ganancias y tiene el acceso operativo completo.';

CREATE OR REPLACE FUNCTION public.fn_user_is_dueno(p_id_tienda bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_dat_dueno
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.app_dat_superadmin s
    WHERE s.uuid = auth.uid() AND s.activo IS TRUE
  );
$function$;

ALTER TABLE public.app_dat_dueno ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_dueno_select ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_select
  ON public.app_dat_dueno
  FOR SELECT TO authenticated
  USING (
    uuid = auth.uid()
    OR public.fn_user_is_dueno(id_tienda)
    OR public.fn_user_can_access_tienda(id_tienda)
  );

DROP POLICY IF EXISTS app_dat_dueno_insert ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_insert
  ON public.app_dat_dueno
  FOR INSERT TO authenticated
  WITH CHECK (public.fn_user_is_dueno(id_tienda));

DROP POLICY IF EXISTS app_dat_dueno_update ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_update
  ON public.app_dat_dueno
  FOR UPDATE TO authenticated
  USING (public.fn_user_is_dueno(id_tienda))
  WITH CHECK (public.fn_user_is_dueno(id_tienda));

DROP POLICY IF EXISTS app_dat_dueno_delete ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_delete
  ON public.app_dat_dueno
  FOR DELETE TO authenticated
  USING (public.fn_user_is_dueno(id_tienda));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_dueno TO authenticated;
GRANT ALL ON public.app_dat_dueno TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_dueno_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.app_dat_dueno_id_seq TO service_role;

-- Acceso genérico a la tienda
CREATE OR REPLACE FUNCTION public.fn_user_can_access_tienda(p_id_tienda bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_dat_dueno
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.app_dat_gerente
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.app_dat_supervisor
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.auditor
    WHERE id_tienda = p_id_tienda AND uuid = auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION public.check_user_has_access_to_tienda(id_tienda_param bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    user_has_access boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.app_dat_vendedor WHERE uuid = auth.uid() AND id_tpv IN (
            SELECT id FROM public.app_dat_tpv WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM public.app_dat_almacenero WHERE uuid = auth.uid() AND id_almacen IN (
            SELECT id FROM public.app_dat_almacen WHERE id_tienda = id_tienda_param
        )
        UNION
        SELECT 1 FROM public.app_dat_supervisor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.auditor WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.app_dat_gerente WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.app_dat_dueno WHERE uuid = auth.uid() AND id_tienda = id_tienda_param
        UNION
        SELECT 1 FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = auth.uid()
           AND c.id_tienda = id_tienda_param
           AND c.deleted_at IS NULL
    ) INTO user_has_access;

    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para acceder a esta tienda';
    END IF;
END;
$function$;

-- Alta / baja del rol. Dueño también queda como gerente para las RPC históricas.
CREATE OR REPLACE FUNCTION public.fn_agregar_rol_trabajador(
  p_trabajador_id bigint,
  p_id_tienda bigint,
  p_tipo_rol text,
  p_usuario_uuid uuid,
  p_tpv_id bigint DEFAULT NULL::bigint,
  p_almacen_id bigint DEFAULT NULL::bigint,
  p_numero_confirmacion text DEFAULT NULL::text,
  p_id_cocina bigint DEFAULT NULL::bigint,
  p_es_jefe_cocina boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_exists boolean;
    v_trabajador_uuid uuid;
    v_puede_dueno boolean;
BEGIN
    SELECT uuid INTO v_trabajador_uuid FROM app_dat_trabajadores WHERE id = p_trabajador_id;

    IF v_trabajador_uuid IS NULL THEN
        RETURN jsonb_build_object('success', false,
            'message', 'El trabajador debe tener un UUID antes de asignarle roles');
    END IF;

    CASE p_tipo_rol
        WHEN 'dueno' THEN
            SELECT (
              public.fn_user_is_dueno(p_id_tienda)
            ) INTO v_puede_dueno;
            IF NOT v_puede_dueno THEN
                RETURN jsonb_build_object('success', false,
                    'message', 'Solo un Dueño o un superadmin puede asignar el rol Dueño');
            END IF;

            SELECT EXISTS(SELECT 1 FROM app_dat_dueno WHERE id_trabajador = p_trabajador_id) INTO v_exists;
            IF NOT v_exists THEN
                INSERT INTO app_dat_dueno (id_trabajador, uuid, id_tienda)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_id_tienda);
            END IF;

            -- Si ya es gerente de la tienda, no se vuelve a asignar.
            SELECT EXISTS(
              SELECT 1 FROM app_dat_gerente
              WHERE id_trabajador = p_trabajador_id
                 OR (uuid = v_trabajador_uuid AND id_tienda = p_id_tienda)
            ) INTO v_exists;
            IF NOT v_exists THEN
                INSERT INTO app_dat_gerente (id_trabajador, uuid, id_tienda)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_id_tienda);
            END IF;

        WHEN 'gerente' THEN
            SELECT EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id) INTO v_exists;
            IF NOT v_exists THEN
                INSERT INTO app_dat_gerente (id_trabajador, uuid, id_tienda)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_id_tienda);
            END IF;

        WHEN 'supervisor' THEN
            SELECT EXISTS(SELECT 1 FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id) INTO v_exists;
            IF NOT v_exists THEN
                INSERT INTO app_dat_supervisor (id_trabajador, uuid, id_tienda)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_id_tienda);
            END IF;

        WHEN 'vendedor' THEN
            SELECT EXISTS(SELECT 1 FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id) INTO v_exists;
            IF NOT v_exists THEN
                INSERT INTO app_dat_vendedor (id_trabajador, uuid, id_tpv, numero_confirmacion)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_tpv_id, p_numero_confirmacion);
            ELSE
                UPDATE app_dat_vendedor
                   SET id_tpv = COALESCE(p_tpv_id, id_tpv),
                       numero_confirmacion = COALESCE(p_numero_confirmacion, numero_confirmacion)
                 WHERE id_trabajador = p_trabajador_id;
            END IF;

        WHEN 'almacenero' THEN
            SELECT EXISTS(SELECT 1 FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id) INTO v_exists;
            IF NOT v_exists THEN
                IF p_almacen_id IS NULL THEN
                    RETURN jsonb_build_object('success', false,
                        'message', 'El rol de almacenero requiere un almacén asignado');
                END IF;
                INSERT INTO app_dat_almacenero (id_trabajador, uuid, id_almacen)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_almacen_id);
            ELSE
                UPDATE app_dat_almacenero
                   SET id_almacen = COALESCE(p_almacen_id, id_almacen)
                 WHERE id_trabajador = p_trabajador_id;
            END IF;

        WHEN 'jefe_cocina', 'cocinero' THEN
            IF p_id_cocina IS NULL THEN
                RETURN jsonb_build_object('success', false,
                    'message', 'El rol de cocina requiere una cocina asignada');
            END IF;

            PERFORM fn_asignar_jefe_cocina(
                v_trabajador_uuid, p_id_cocina, p_trabajador_id,
                CASE WHEN p_tipo_rol = 'cocinero' THEN false
                     ELSE COALESCE(p_es_jefe_cocina, true) END);

        ELSE
            RETURN jsonb_build_object('success', true,
                'message', 'El rol "' || p_tipo_rol || '" no requiere registro de ambito',
                'sin_ambito', true);
    END CASE;

    RETURN jsonb_build_object('success', true, 'message', 'Rol agregado correctamente');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'message', 'Error al agregar rol: ' || SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_eliminar_rol_trabajador(
  p_trabajador_id bigint,
  p_tipo_rol text,
  p_id_cocina bigint DEFAULT NULL::bigint
)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_uuid uuid;
    v_n integer;
    v_tienda bigint;
    v_puede_dueno boolean;
BEGIN
    CASE p_tipo_rol
        WHEN 'dueno' THEN
            SELECT id_tienda INTO v_tienda
            FROM app_dat_dueno WHERE id_trabajador = p_trabajador_id LIMIT 1;
            IF v_tienda IS NULL THEN
                RETURN jsonb_build_object('success', true, 'message', 'El trabajador no tenía rol Dueño');
            END IF;
            SELECT public.fn_user_is_dueno(v_tienda) INTO v_puede_dueno;
            IF NOT v_puede_dueno THEN
                RETURN jsonb_build_object('success', false,
                    'message', 'Solo un Dueño o un superadmin puede quitar el rol Dueño');
            END IF;
            DELETE FROM app_dat_dueno WHERE id_trabajador = p_trabajador_id;

        WHEN 'gerente' THEN
            DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;
        WHEN 'supervisor' THEN
            DELETE FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id;
        WHEN 'vendedor' THEN
            DELETE FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id;
        WHEN 'almacenero' THEN
            DELETE FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id;

        WHEN 'jefe_cocina', 'cocinero' THEN
            SELECT uuid INTO v_uuid FROM app_dat_trabajadores WHERE id = p_trabajador_id;

            IF p_id_cocina IS NULL THEN
                DELETE FROM app_dat_jefe_cocina
                 WHERE id_trabajador = p_trabajador_id
                    OR (v_uuid IS NOT NULL AND uuid = v_uuid);
            ELSE
                DELETE FROM app_dat_jefe_cocina
                 WHERE id_cocina = p_id_cocina
                   AND (id_trabajador = p_trabajador_id
                        OR (v_uuid IS NOT NULL AND uuid = v_uuid));
            END IF;

            GET DIAGNOSTICS v_n = ROW_COUNT;
            RETURN jsonb_build_object('success', true,
                'message', 'Rol de cocina eliminado (' || v_n || ' asignacion(es))',
                'eliminadas', v_n);

        ELSE
            RETURN jsonb_build_object('success', true,
                'message', 'El rol "' || p_tipo_rol || '" no tiene registro de ambito que eliminar',
                'sin_ambito', true);
    END CASE;

    RETURN jsonb_build_object('success', true, 'message', 'Rol eliminado correctamente');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'message', 'Error al eliminar rol: ' || SQLERRM);
END;
$function$;

-- Parchea funciones grandes sin reescribirlas: listado, alta y bajas de trabajador.
DO $patch$
DECLARE
  def text;
  fn text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'fn_listar_trabajadores_tienda';

  def := replace(
    def,
    'WHEN EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) THEN ''gerente''',
    'WHEN EXISTS(SELECT 1 FROM app_dat_dueno WHERE id_trabajador = t.id) THEN ''dueno'' WHEN EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) THEN ''gerente'''
  );
  def := replace(
    def,
    'EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) AS es_gerente,',
    'EXISTS(SELECT 1 FROM app_dat_dueno WHERE id_trabajador = t.id) AS es_dueno, EXISTS(SELECT 1 FROM app_dat_gerente WHERE id_trabajador = t.id) AS es_gerente,'
  );
  IF position('es_dueno' IN def) = 0 THEN
    RAISE EXCEPTION 'No se pudo parchear fn_listar_trabajadores_tienda';
  END IF;
  EXECUTE def;

  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_insertar_trabajador_completo'
    AND pg_get_function_identity_arguments(p.oid) LIKE 'p_id_tienda bigint%';

  def := replace(
    def,
    '''recursos_humanos'') THEN',
    '''recursos_humanos'',''dueno'') THEN'
  );
  def := replace(
    def,
    'WHEN ''gerente'' THEN',
    $ins$WHEN 'dueno' THEN
            IF NOT public.fn_user_is_dueno(p_id_tienda) THEN
                RETURN jsonb_build_object('success', false, 'message', 'Solo un Dueño o un superadmin puede asignar el rol Dueño');
            END IF;
            INSERT INTO app_dat_dueno (uuid, id_tienda, id_trabajador, created_at)
            VALUES (p_usuario_uuid, p_id_tienda, nuevo_trabajador_id, NOW());
            INSERT INTO app_dat_gerente (uuid, id_tienda, id_trabajador, created_at)
            SELECT p_usuario_uuid, p_id_tienda, nuevo_trabajador_id, NOW()
            WHERE NOT EXISTS (
              SELECT 1 FROM app_dat_gerente g
              WHERE g.id_trabajador = nuevo_trabajador_id
                 OR (g.uuid = p_usuario_uuid AND g.id_tienda = p_id_tienda)
            );
            resultado := jsonb_set(resultado, '{rol_especifico}', '"dueno"');
        WHEN 'gerente' THEN$ins$
  );
  IF position('app_dat_dueno' IN def) = 0 THEN
    RAISE EXCEPTION 'No se pudo parchear fn_insertar_trabajador_completo';
  END IF;
  EXECUTE def;

  FOREACH fn IN ARRAY ARRAY['fn_eliminar_trabajador_completo', 'fn_desvincular_usuario_trabajador']
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = fn;

    IF position('app_dat_dueno' IN def) = 0 THEN
      def := replace(
        def,
        'DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;',
        'DELETE FROM app_dat_dueno WHERE id_trabajador = p_trabajador_id; DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;'
      );
      IF position('app_dat_dueno' IN def) = 0 THEN
        RAISE EXCEPTION 'No se pudo parchear %', fn;
      END IF;
      EXECUTE def;
    END IF;
  END LOOP;
END
$patch$;

GRANT EXECUTE ON FUNCTION public.fn_user_is_dueno(bigint) TO authenticated, service_role;

COMMIT;
