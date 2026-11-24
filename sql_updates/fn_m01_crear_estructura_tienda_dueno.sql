-- =============================================================================
-- Al crear una tienda, el creador queda registrado como Dueño.
--
-- Problema: `crear_estructura_tienda` mete al usuario principal en
-- `app_dat_gerente` y `app_dat_supervisor` (por el `personal_data` que manda el
-- cliente), pero nunca escribe en `app_dat_dueno`. Sin fila ahí,
-- `fn_user_is_dueno`, `fn_m01_fuentes_puede_gestionar_duenos` y
-- `fn_config_tienda_puede_escribir` no lo reconocen como Dueño: no ve las
-- ganancias y no puede asignar el rol Dueño a nadie.
--
-- Arreglo: `fn_m01_crear_estructura_tienda` es SECURITY DEFINER y ya conoce el
-- `auth.uid()` del creador (es el único punto de entrada del alta inicial).
-- Tras crear la estructura inserta la fila de `app_dat_dueno` enlazando el
-- trabajador principal cuando existe.
--
-- Notas de diseño:
--   * No se toca `crear_estructura_tienda` (INVOKER, 9 KB): su `EXECUTE` está
--     revocado a `authenticated`, así que la RLS de `app_dat_dueno` impediría
--     el INSERT desde ahí. En el wrapper DEFINER la escritura sí procede.
--   * El alta del Dueño nunca aborta la creación de la tienda: si falla, se
--     devuelve `dueno_registrado = false` y el mensaje del error en el JSON, en
--     vez de tirar abajo un alta ya hecha.
--   * Idempotente: reejecutar no duplica filas (`NOT EXISTS`).
--
-- Segundo defecto, menor pero visible: `crear_estructura_tienda` inserta los
-- trabajadores sin la columna `uuid`, aunque el cliente la manda en
-- `personal_data`. El Dueño acaba con `id_trabajador` nulo y no aparece en el
-- listado de personal. Aqui se enlaza el trabajador del creador por su
-- posicion en `personal_data` (la RPC los inserta en ese mismo orden) y se le
-- pone el `uuid`; el trigger `fn_sync_trabajador_user_mail` rellena el correo.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_m01_crear_estructura_tienda(
    p_denominacion_tienda character varying,
    p_direccion_tienda character varying,
    p_ubicacion_tienda character varying,
    p_pais character varying DEFAULT NULL::character varying,
    p_estado character varying DEFAULT NULL::character varying,
    p_nombre_pais character varying DEFAULT NULL::character varying,
    p_nombre_estado character varying DEFAULT NULL::character varying,
    p_latitude numeric DEFAULT NULL::numeric,
    p_longitude numeric DEFAULT NULL::numeric,
    p_almacenes_data jsonb DEFAULT NULL::jsonb,
    p_tpv_data jsonb DEFAULT NULL::jsonb,
    p_personal_data jsonb DEFAULT NULL::jsonb,
    p_layouts_data jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_uuid uuid := auth.uid();
    v_resultado jsonb;
    v_tienda_id bigint;
    v_trabajador_id bigint;
    v_indice_creador int;
    v_dueno_registrado boolean := false;
    v_dueno_error text;
BEGIN
    -- Alta inicial: quien se registra todavia no pertenece a ninguna tienda.
    -- El creador es siempre auth.uid(). No se acepta un uuid ajeno y no se
    -- exige un rol previo. Las demas entradas siguen exigiendo admin de tienda.
    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'No autorizado para crear tiendas' USING ERRCODE = '42501';
    END IF;

    v_resultado := public.crear_estructura_tienda(
        v_uuid,
        p_denominacion_tienda, p_direccion_tienda, p_ubicacion_tienda,
        p_pais, p_estado, p_nombre_pais, p_nombre_estado,
        p_latitude, p_longitude,
        p_almacenes_data, p_tpv_data, p_personal_data, p_layouts_data
    );

    -- Si la estructura no se creo, no hay tienda de la que ser dueno.
    IF coalesce((v_resultado->>'success')::boolean, false) IS NOT TRUE THEN
        RETURN v_resultado;
    END IF;

    v_tienda_id := NULLIF(v_resultado->'data'->>'tienda_id', '')::bigint;
    IF v_tienda_id IS NULL THEN
        RETURN v_resultado;
    END IF;

    BEGIN
        -- Los trabajadores se insertan en el mismo orden que `personal_data`.
        -- La primera entrada del creador es la que le corresponde.
        SELECT (orden - 1) INTO v_indice_creador
        FROM jsonb_array_elements(coalesce(p_personal_data, '[]'::jsonb))
             WITH ORDINALITY AS e(valor, orden)
        WHERE (valor->>'uuid') = v_uuid::text
        ORDER BY orden
        LIMIT 1;

        -- Enlazar el trabajador del creador: por uuid (si alguna vez se
        -- insertó bien) o por su posicion en `personal_data`.
        SELECT t.id INTO v_trabajador_id
        FROM public.app_dat_trabajadores t
        WHERE t.id_tienda = v_tienda_id
          AND t.deleted_at IS NULL
          AND (
              t.uuid = v_uuid
              OR (
                  v_indice_creador IS NOT NULL
                  AND t.id = (
                      SELECT tt.id
                      FROM public.app_dat_trabajadores tt
                      WHERE tt.id_tienda = v_tienda_id
                        AND tt.deleted_at IS NULL
                      ORDER BY tt.id
                      OFFSET v_indice_creador LIMIT 1
                  )
              )
          )
        ORDER BY (t.uuid = v_uuid) DESC, t.id
        LIMIT 1;

        IF v_trabajador_id IS NOT NULL THEN
            UPDATE public.app_dat_trabajadores
            SET uuid = v_uuid
            WHERE id = v_trabajador_id
              AND uuid IS DISTINCT FROM v_uuid;
        END IF;

        INSERT INTO public.app_dat_dueno (uuid, id_tienda, id_trabajador)
        SELECT v_uuid, v_tienda_id, v_trabajador_id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_dueno d
            WHERE d.uuid = v_uuid AND d.id_tienda = v_tienda_id
        );

        -- El rol Dueño tambien se registra como Gerente: las RPC historicas que
        -- comprueban `app_dat_gerente` tienen que seguir autorizandolo.
        INSERT INTO public.app_dat_gerente (uuid, id_tienda, id_trabajador)
        SELECT v_uuid, v_tienda_id, v_trabajador_id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.app_dat_gerente g
            WHERE g.uuid = v_uuid AND g.id_tienda = v_tienda_id
        );

        v_dueno_registrado := true;
    EXCEPTION
        WHEN OTHERS THEN
            -- La tienda ya existe: se informa del fallo sin deshacer el alta.
            v_dueno_registrado := false;
            v_dueno_error := SQLERRM;
            RAISE WARNING 'Tienda % creada pero el Dueno no se registro: %',
                v_tienda_id, SQLERRM;
    END;

    v_resultado := jsonb_set(
        v_resultado,
        '{data,dueno_registrado}',
        to_jsonb(v_dueno_registrado),
        true
    );

    IF v_dueno_error IS NOT NULL THEN
        v_resultado := jsonb_set(
            v_resultado,
            '{data,dueno_error}',
            to_jsonb(v_dueno_error),
            true
        );
    END IF;

    RETURN v_resultado;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_crear_estructura_tienda(
    character varying, character varying, character varying,
    character varying, character varying, character varying, character varying,
    numeric, numeric, jsonb, jsonb, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_crear_estructura_tienda(
    character varying, character varying, character varying,
    character varying, character varying, character varying, character varying,
    numeric, numeric, jsonb, jsonb, jsonb, jsonb) TO authenticated;

COMMIT;

-- =============================================================================
-- Verificacion (solo lectura)
-- =============================================================================
-- Las tiendas creadas antes de este script no tienen fila de Dueno. Para
-- rellenarlas, primero identifica al creador (el gerente con el trabajador mas
-- antiguo de la tienda) y despues asignalo con la RPC existente:
--
--   SELECT t.id AS id_tienda, t.denominacion, g.uuid, tr.nombres, tr.apellidos
--   FROM public.app_dat_tienda t
--   JOIN public.app_dat_gerente g ON g.id_tienda = t.id
--   LEFT JOIN public.app_dat_trabajadores tr ON tr.id = g.id_trabajador
--   WHERE NOT EXISTS (
--       SELECT 1 FROM public.app_dat_dueno d
--       WHERE d.id_tienda = t.id AND d.uuid = g.uuid
--   )
--   ORDER BY t.id, g.created_at;
--
--   SELECT public.fn_m01_asignar_dueno_por_email('correo@ejemplo.com', 6, 'Nombre', 'Apellidos');
