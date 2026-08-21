-- ============================================================================
-- 08 · Fase 1 · RPCs de cocinas
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- REQUISITOS: 07_schema_cocinas.sql aplicado.
--
-- CONTENIDO
--   8.1  fn_crear_cocina            crea almacen + cocina + layout inicial
--   8.2  fn_actualizar_cocina
--   8.3  fn_eliminar_cocina         soft-delete con validaciones
--   8.4  fn_listar_cocinas
--   8.5  fn_asignar_tpv_cocina / fn_desasignar_tpv_cocina
--   8.6  fn_listar_cocinas_tpv      que cocinas ve un TPV
--   8.7  fn_disponibilidad_plato
--
-- NOTA DE SEGURIDAD
-- -----------------
-- Este proyecto NO tiene RLS: se comprobo que la anon key sin login lee
-- app_dat_almacen y app_dat_producto completos. La unica barrera son las
-- funciones SECURITY DEFINER que llaman a check_user_has_access_to_tienda(),
-- como ya hace get_productos_by_categoria_tpv_search_meta.
--
-- Por eso TODAS las funciones de escritura de aqui empiezan con
-- PERFORM check_user_has_access_to_tienda(<tienda>), y las de lectura tambien.
-- Sin esa llamada, cualquiera con la anon key podria crear cocinas en tiendas
-- ajenas. Si algun dia se activa RLS, este guard sigue siendo correcto.
--
-- CONVENCION DE RESPUESTA
-- -----------------------
-- Todas devuelven jsonb con 'status' = 'success' | 'error', igual que
-- fn_insertar_mesa / fn_actualizar_mesa, para que el cliente Flutter las trate
-- del mismo modo. Los errores traen 'error_code' estable.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 8.1 fn_crear_cocina
-- Crea una cocina completa: almacen (es_cocina = true) + fila en
-- app_dat_cocina + un layout inicial donde guardar materia prima.
--
-- Por que crea tambien el almacen y el layout:
--   sin layout el almacen no puede recibir inventario, y una cocina sin
--   inventario no sirve para nada. Dejarlo en dos pasos obligaria al admin a
--   recordar el segundo. El trigger del 07 marca es_cocina automaticamente.
--
-- p_id_almacen_existente permite convertir un almacen que ya existe en cocina,
-- en vez de crear uno nuevo (caso: la tienda ya tenia un almacen "Cocina").
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_crear_cocina(
    p_id_tienda            bigint,
    p_denominacion         text,
    p_descripcion          text    DEFAULT NULL,
    p_impresora            text    DEFAULT NULL,
    p_orden                smallint DEFAULT 0,
    p_id_almacen_existente bigint  DEFAULT NULL,
    p_denominacion_layout  text    DEFAULT 'Área de cocina',
    p_id_tipo_layout       bigint  DEFAULT 1,
    p_direccion            text    DEFAULT NULL,
    p_ubicacion            text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_almacen bigint;
    v_id_cocina  bigint;
    v_id_layout  bigint;
    v_creo_almacen boolean := false;
BEGIN
    PERFORM check_user_has_access_to_tienda(p_id_tienda);

    IF COALESCE(trim(p_denominacion), '') = '' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina necesita un nombre',
            'error_code', 'MISSING_DENOMINACION'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La tienda no existe',
            'error_code', 'TIENDA_NOT_FOUND'
        );
    END IF;

    -- Nombre unico de cocina dentro de la tienda (evita "Cocina" duplicada).
    IF EXISTS (
        SELECT 1 FROM app_dat_cocina
         WHERE id_tienda = p_id_tienda
           AND lower(denominacion) = lower(trim(p_denominacion))
           AND deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Ya existe una cocina con ese nombre en esta tienda',
            'error_code', 'DUPLICATE_COCINA'
        );
    END IF;

    -- ── Resolver el almacen ────────────────────────────────────────────────
    IF p_id_almacen_existente IS NOT NULL THEN
        -- Convertir un almacen existente en cocina.
        IF NOT EXISTS (
            SELECT 1 FROM app_dat_almacen
             WHERE id = p_id_almacen_existente
               AND id_tienda = p_id_tienda
               AND deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'El almacen indicado no existe o no pertenece a esta tienda',
                'error_code', 'ALMACEN_NOT_FOUND',
                'id_almacen', p_id_almacen_existente
            );
        END IF;

        -- UNIQUE(id_almacen) en app_dat_cocina lo impediria, pero damos un
        -- error legible en vez de una violacion de constraint.
        IF EXISTS (
            SELECT 1 FROM app_dat_cocina
             WHERE id_almacen = p_id_almacen_existente
               AND deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'Ese almacen ya esta asignado a otra cocina',
                'error_code', 'ALMACEN_YA_ES_COCINA',
                'id_almacen', p_id_almacen_existente
            );
        END IF;

        -- Un almacen que abastece a un TPV no deberia volverse cocina: el TPV
        -- venderia desde el mismo almacen que produce, y se pierde la
        -- separacion barra/cocina que sostiene todo el modelo.
        IF EXISTS (SELECT 1 FROM app_dat_tpv WHERE id_almacen = p_id_almacen_existente) THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'Ese almacen es el almacen de venta de un TPV; no puede ser cocina',
                'error_code', 'ALMACEN_ES_DE_TPV',
                'id_almacen', p_id_almacen_existente
            );
        END IF;

        v_id_almacen := p_id_almacen_existente;
    ELSE
        INSERT INTO app_dat_almacen (id_tienda, denominacion, direccion, ubicacion, es_cocina)
        VALUES (p_id_tienda, trim(p_denominacion), p_direccion, p_ubicacion, true)
        RETURNING id INTO v_id_almacen;

        v_creo_almacen := true;
    END IF;

    -- ── Crear la cocina (el trigger marca es_cocina en el almacen) ─────────
    INSERT INTO app_dat_cocina
        (id_tienda, id_almacen, denominacion, descripcion, impresora, orden)
    VALUES
        (p_id_tienda, v_id_almacen, trim(p_denominacion), p_descripcion,
         p_impresora, COALESCE(p_orden, 0))
    RETURNING id INTO v_id_cocina;

    -- ── Layout inicial ────────────────────────────────────────────────────
    -- Solo si el almacen no tiene ninguno (al convertir uno existente puede
    -- que ya tenga sus zonas).
    SELECT id INTO v_id_layout
      FROM app_dat_layout_almacen
     WHERE id_almacen = v_id_almacen
       AND deleted_at IS NULL
     ORDER BY id ASC
     LIMIT 1;

    IF v_id_layout IS NULL THEN
        INSERT INTO app_dat_layout_almacen
            (id_almacen, id_tipo_layout, denominacion, sku_codigo)
        VALUES
            (v_id_almacen,
             COALESCE(p_id_tipo_layout, 1),
             COALESCE(NULLIF(trim(p_denominacion_layout), ''), 'Área de cocina'),
             'COC-' || v_id_cocina::text)
        RETURNING id INTO v_id_layout;
    END IF;

    RETURN jsonb_build_object(
        'status',        'success',
        'id_cocina',     v_id_cocina,
        'id_almacen',    v_id_almacen,
        'id_layout',     v_id_layout,
        'almacen_creado', v_creo_almacen,
        'message',       'Cocina creada correctamente'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al crear cocina: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_crear_cocina(bigint, text, text, text, smallint, bigint, text, bigint, text, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.2 fn_actualizar_cocina
-- Edita los datos propios de la cocina. NO cambia id_almacen: mover una cocina
-- a otro almacen dejaria su inventario y sus tandas huerfanos. Para eso hay que
-- crear otra cocina y transferir.
--
-- Todos los parametros son NULL-opcionales (patron COALESCE de
-- fn_actualizar_mesa), salvo p_activa, que se distingue con IS NOT NULL para
-- poder desactivar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_actualizar_cocina(
    p_id_cocina    bigint,
    p_denominacion text     DEFAULT NULL,
    p_descripcion  text     DEFAULT NULL,
    p_impresora    text     DEFAULT NULL,
    p_orden        smallint DEFAULT NULL,
    p_activa       boolean  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda  bigint;
    v_id_almacen bigint;
BEGIN
    SELECT id_tienda, id_almacen
      INTO v_id_tienda, v_id_almacen
      FROM app_dat_cocina
     WHERE id = p_id_cocina AND deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    -- Nombre unico dentro de la tienda si se esta cambiando.
    IF p_denominacion IS NOT NULL AND trim(p_denominacion) <> '' THEN
        IF EXISTS (
            SELECT 1 FROM app_dat_cocina
             WHERE id_tienda = v_id_tienda
               AND lower(denominacion) = lower(trim(p_denominacion))
               AND id <> p_id_cocina
               AND deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'Ya existe otra cocina con ese nombre en esta tienda',
                'error_code', 'DUPLICATE_COCINA'
            );
        END IF;
    END IF;

    UPDATE app_dat_cocina
       SET denominacion = COALESCE(NULLIF(trim(p_denominacion), ''), denominacion),
           descripcion  = COALESCE(p_descripcion, descripcion),
           impresora    = COALESCE(p_impresora,   impresora),
           orden        = COALESCE(p_orden,       orden),
           activa       = COALESCE(p_activa,      activa)
     WHERE id = p_id_cocina;

    -- Mantener el nombre del almacen alineado con el de la cocina: el
    -- almacenero y el jefe de cocina ven la misma etiqueta en inventario.
    IF p_denominacion IS NOT NULL AND trim(p_denominacion) <> '' THEN
        UPDATE app_dat_almacen
           SET denominacion = trim(p_denominacion)
         WHERE id = v_id_almacen;
    END IF;

    RETURN jsonb_build_object(
        'status',    'success',
        'id_cocina', p_id_cocina,
        'message',   'Cocina actualizada'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al actualizar cocina: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_actualizar_cocina(bigint, text, text, text, smallint, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.3 fn_eliminar_cocina
-- Soft-delete. NUNCA borra fisicamente: la cocina esta referenciada por
-- productos, por su almacen y (desde Fase 2) por comandas historicas.
--
-- Bloquea si hay productos que todavia apuntan a esta cocina: dejarlos
-- huerfanos haria que el TPV no supiera a donde mandarlos. El admin debe
-- reasignarlos primero (p_forzar = true los desasigna en bloque).
--
-- El almacen queda con es_cocina = true y su inventario intacto; solo se
-- desliga. Asi el stock de materia prima sigue siendo auditable.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_eliminar_cocina(
    p_id_cocina bigint,
    p_forzar    boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda    bigint;
    v_id_almacen   bigint;
    v_n_productos  integer;
    v_n_tpvs       integer;
BEGIN
    SELECT id_tienda, id_almacen
      INTO v_id_tienda, v_id_almacen
      FROM app_dat_cocina
     WHERE id = p_id_cocina AND deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe o ya fue eliminada',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    SELECT COUNT(*) INTO v_n_productos
      FROM app_dat_producto
     WHERE id_cocina = p_id_cocina AND deleted_at IS NULL;

    SELECT COUNT(*) INTO v_n_tpvs
      FROM app_dat_tpv_cocina
     WHERE id_cocina = p_id_cocina;

    IF v_n_productos > 0 AND NOT p_forzar THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cocina tiene ' || v_n_productos ||
                          ' producto(s) asignado(s). Reasignalos o usa p_forzar = true.',
            'error_code', 'COCINA_CON_PRODUCTOS',
            'productos',  v_n_productos
        );
    END IF;

    -- Desasignar productos y desligar TPVs.
    IF v_n_productos > 0 THEN
        UPDATE app_dat_producto
           SET id_cocina = NULL
         WHERE id_cocina = p_id_cocina;
    END IF;

    DELETE FROM app_dat_tpv_cocina WHERE id_cocina = p_id_cocina;

    UPDATE app_dat_categoria_tienda
       SET id_cocina = NULL
     WHERE id_cocina = p_id_cocina;

    UPDATE app_dat_cocina
       SET deleted_at = now(),
           activa     = false
     WHERE id = p_id_cocina;

    RETURN jsonb_build_object(
        'status',              'success',
        'id_cocina',           p_id_cocina,
        'id_almacen',          v_id_almacen,
        'productos_liberados', v_n_productos,
        'tpvs_desligados',     v_n_tpvs,
        'message',             'Cocina eliminada. El almacen y su inventario se conservan.'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al eliminar cocina: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_eliminar_cocina(bigint, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.4 fn_listar_cocinas
-- Cocinas de una tienda con sus contadores y sus TPVs ligados, en una sola
-- llamada. Alimenta la pantalla de gestion de cocinas del admin.
--
-- Devuelve jsonb (no TABLE) porque incluye el arreglo anidado de TPVs; asi la
-- UI no necesita una segunda consulta por fila.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_cocinas(
    p_id_tienda       bigint,
    p_solo_activas    boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_result jsonb;
BEGIN
    PERFORM check_user_has_access_to_tienda(p_id_tienda);

    SELECT COALESCE(jsonb_agg(fila ORDER BY fila->>'orden', fila->>'cocina'), '[]'::jsonb)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'id_cocina',          c.id,
            'denominacion',       c.denominacion,
            'descripcion',        c.descripcion,
            'impresora',          c.impresora,
            'orden',              c.orden,
            'activa',             c.activa,
            'cocina',             c.denominacion,
            'id_almacen',         c.id_almacen,
            'almacen',            a.denominacion,
            'cantidad_layouts',   (SELECT COUNT(*) FROM app_dat_layout_almacen la
                                    WHERE la.id_almacen = c.id_almacen
                                      AND la.deleted_at IS NULL),
            'cantidad_productos', (SELECT COUNT(*) FROM app_dat_producto p
                                    WHERE p.id_cocina = c.id
                                      AND p.deleted_at IS NULL),
            'productos_por_tanda',(SELECT COUNT(*) FROM app_dat_producto p
                                    WHERE p.id_cocina = c.id
                                      AND p.deleted_at IS NULL
                                      AND p.modo_elaboracion = 'por_tanda'),
            'tpvs',               COALESCE((
                                    SELECT jsonb_agg(jsonb_build_object(
                                               'id_tpv',       t.id,
                                               'denominacion', t.denominacion
                                           ) ORDER BY t.denominacion)
                                      FROM app_dat_tpv_cocina tc
                                      JOIN app_dat_tpv t ON t.id = tc.id_tpv
                                     WHERE tc.id_cocina = c.id
                                  ), '[]'::jsonb),
            'created_at',         c.created_at,
            'updated_at',         c.updated_at
        ) AS fila
          FROM app_dat_cocina c
          JOIN app_dat_almacen a ON a.id = c.id_almacen
         WHERE c.id_tienda = p_id_tienda
           AND c.deleted_at IS NULL
           AND (NOT p_solo_activas OR c.activa = true)
      ) sub;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_cocinas(bigint, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.5 fn_asignar_tpv_cocina / fn_desasignar_tpv_cocina
-- Ligar y desligar un TPV con una cocina.
--
-- El trigger del 07 (trg_validar_tpv_cocina) ya impide cruzar tiendas; aqui se
-- valida antes para devolver un error legible en vez de una excepcion de
-- trigger, y se hace idempotente: asignar dos veces no falla.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_asignar_tpv_cocina(
    p_id_tpv    bigint,
    p_id_cocina bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_tienda_tpv    bigint;
    v_tienda_cocina bigint;
    v_cocina_activa boolean;
    v_id            bigint;
BEGIN
    SELECT id_tienda INTO v_tienda_tpv
      FROM app_dat_tpv WHERE id = p_id_tpv;

    IF v_tienda_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_tienda_tpv);

    SELECT id_tienda, activa
      INTO v_tienda_cocina, v_cocina_activa
      FROM app_dat_cocina
     WHERE id = p_id_cocina AND deleted_at IS NULL;

    IF v_tienda_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    IF v_tienda_cocina <> v_tienda_tpv THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El TPV y la cocina son de tiendas distintas',
            'error_code', 'TIENDA_MISMATCH',
            'tienda_tpv',    v_tienda_tpv,
            'tienda_cocina', v_tienda_cocina
        );
    END IF;

    -- Idempotente: si ya esta ligado, devolver el vinculo existente.
    SELECT id INTO v_id
      FROM app_dat_tpv_cocina
     WHERE id_tpv = p_id_tpv AND id_cocina = p_id_cocina;

    IF v_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status',    'success',
            'id',        v_id,
            'ya_existia', true,
            'message',   'El TPV ya estaba ligado a esa cocina'
        );
    END IF;

    INSERT INTO app_dat_tpv_cocina (id_tpv, id_cocina)
    VALUES (p_id_tpv, p_id_cocina)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'status',     'success',
        'id',         v_id,
        'ya_existia', false,
        'cocina_activa', v_cocina_activa,
        'message',    'TPV ligado a la cocina'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al ligar TPV con cocina: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_asignar_tpv_cocina(bigint, bigint)
    TO anon, authenticated, service_role;


CREATE OR REPLACE FUNCTION public.fn_desasignar_tpv_cocina(
    p_id_tpv    bigint,
    p_id_cocina bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_tienda_tpv bigint;
    v_borradas   integer;
    v_productos  integer;
BEGIN
    SELECT id_tienda INTO v_tienda_tpv
      FROM app_dat_tpv WHERE id = p_id_tpv;

    IF v_tienda_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_tienda_tpv);

    -- Informativo: cuantos platos deja de ver ese TPV al desligar.
    SELECT COUNT(*) INTO v_productos
      FROM app_dat_producto p
     WHERE p.id_cocina = p_id_cocina
       AND p.deleted_at IS NULL
       AND p.es_vendible = true;

    DELETE FROM app_dat_tpv_cocina
     WHERE id_tpv = p_id_tpv AND id_cocina = p_id_cocina;

    GET DIAGNOSTICS v_borradas = ROW_COUNT;

    RETURN jsonb_build_object(
        'status',              'success',
        'desligado',           v_borradas > 0,
        'productos_afectados', v_productos,
        'message',             CASE WHEN v_borradas > 0
                                    THEN 'TPV desligado de la cocina'
                                    ELSE 'El TPV no estaba ligado a esa cocina'
                               END
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',   'error',
            'message',  'Error al desligar TPV de cocina: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_desasignar_tpv_cocina(bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.6 fn_listar_cocinas_tpv
-- Que cocinas puede usar un TPV. Es la consulta que hara el vendedor al abrir
-- el catalogo, y la que usara la validacion de venta ("el plato va a una cocina
-- que este TPV no tiene ligada").
--
-- Solo devuelve cocinas ACTIVAS: una cocina desactivada (turno cerrado) no debe
-- recibir comandas aunque el vinculo exista.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_cocinas_tpv(
    p_id_tpv bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_tienda_tpv bigint;
    v_result     jsonb;
BEGIN
    SELECT id_tienda INTO v_tienda_tpv
      FROM app_dat_tpv WHERE id = p_id_tpv;

    IF v_tienda_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_tienda_tpv);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id_cocina',    c.id,
               'denominacion', c.denominacion,
               'id_almacen',   c.id_almacen,
               'impresora',    c.impresora,
               'orden',        c.orden
           ) ORDER BY c.orden, c.denominacion), '[]'::jsonb)
      INTO v_result
      FROM app_dat_tpv_cocina tc
      JOIN app_dat_cocina c ON c.id = tc.id_cocina
     WHERE tc.id_tpv = p_id_tpv
       AND c.deleted_at IS NULL
       AND c.activa = true;

    RETURN jsonb_build_object(
        'status',   'success',
        'id_tpv',   p_id_tpv,
        'id_tienda', v_tienda_tpv,
        'cocinas',  v_result,
        'total',    jsonb_array_length(v_result)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_cocinas_tpv(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8.7 fn_disponibilidad_plato
-- Cuantas unidades de un producto se pueden servir AHORA desde un TPV.
--
-- Tres casos, segun el plan ("En la misma cuenta conviven: listo para venta
-- (cerveza), tanda (moro) y al pedido (bistec)"):
--
--   1. Sin cocina (id_cocina IS NULL)
--      Producto normal de barra. Disponible = stock en el almacen del TPV.
--      Es lo que ya hace el catalogo hoy; se incluye para que la UI tenga una
--      sola funcion que preguntar.
--
--   2. por_tanda
--      Disponible = stock TERMINADO del propio SKU en el almacen de la cocina.
--      Regla del plan: "Disponibilidad de por_tanda = stock terminado (si se
--      acabo, agotado aunque quede MP)". No se mira la receta: que haya arroz
--      no significa que haya moro hecho.
--
--   3. al_pedido
--      Disponible = min por ingrediente de floor(stock / cantidad_necesaria),
--      con el stock acotado a los layouts de ESA cocina. Es el limite real de
--      cuantos bistecs se pueden sacar con la MP que hay en la estacion.
--
-- Ademas valida el enrutamiento: si el producto va a una cocina que este TPV no
-- tiene ligada, devuelve disponible = 0 con error_code COCINA_NO_LIGADA. Ese es
-- el criterio de aceptacion "bistec va a Cocina caliente; no aparece en
-- Pizzeria".
--
-- LIMITACION CONOCIDA (se resuelve en Fase 4)
-- ------------------------------------------
-- fn_obtener_ingredientes_recursivos explota los hijos elaborados hasta llegar a
-- ingredientes hoja (filtra es_elaborado = false). Por tanto un plato al_pedido
-- que lleva un componente por_tanda (bistec + moro) hoy explota tambien la
-- receta del moro en vez de parar y contar porciones de moro hechas. La parada
-- por modo_elaboracion = 'por_tanda' es trabajo de Fase 4; hasta entonces el
-- calculo de un combo asi es conservador (subestima), no optimista.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_disponibilidad_plato(
    p_id_producto bigint,
    p_id_tpv      bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_tienda_tpv       bigint;
    v_almacen_tpv      bigint;
    v_prod             RECORD;
    v_id_cocina        bigint;
    v_almacen_cocina   bigint;
    v_cocina_nombre    text;
    v_cocina_activa    boolean;
    v_ligada           boolean;
    v_disponible       numeric := 0;
    v_max_unidades     numeric;
    v_ing              RECORD;
    v_stock_ing        numeric;
    v_posibles         numeric;
    v_detalle          jsonb := '[]'::jsonb;
    v_tiene_receta     boolean := false;
BEGIN
    -- ── TPV ───────────────────────────────────────────────────────────────
    SELECT id_tienda, id_almacen
      INTO v_tienda_tpv, v_almacen_tpv
      FROM app_dat_tpv WHERE id = p_id_tpv;

    IF v_tienda_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND',
            'disponible', 0
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_tienda_tpv);

    -- ── Producto ──────────────────────────────────────────────────────────
    SELECT id, id_tienda, denominacion, sku, um,
           es_elaborado, es_servicio, es_vendible,
           modo_elaboracion, id_cocina
      INTO v_prod
      FROM app_dat_producto
     WHERE id = p_id_producto AND deleted_at IS NULL;

    IF v_prod.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND',
            'disponible', 0
        );
    END IF;

    IF v_prod.id_tienda <> v_tienda_tpv THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no pertenece a la tienda del TPV',
            'error_code', 'TIENDA_MISMATCH',
            'disponible', 0
        );
    END IF;

    -- Un servicio sin receta no tiene disponibilidad que calcular: siempre se
    -- puede vender (es el criterio que ya usa el resto del sistema).
    IF v_prod.es_servicio AND NOT v_prod.es_elaborado THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'id_producto', p_id_producto,
            'producto',    v_prod.denominacion,
            'tipo',        'servicio',
            'disponible',  NULL,          -- NULL = ilimitado
            'ilimitado',   true,
            'message',     'Servicio: sin control de disponibilidad'
        );
    END IF;

    v_id_cocina := v_prod.id_cocina;

    -- ══════════════════════════════════════════════════════════════════════
    -- CASO 1 · sin cocina: producto de barra / listo para venta
    -- ══════════════════════════════════════════════════════════════════════
    IF v_id_cocina IS NULL THEN
        -- Un elaborado sin cocina asignada sigue el comportamiento previo a la
        -- Fase 1: su MP se busca en el almacen del TPV.
        IF v_prod.es_elaborado THEN
            v_max_unidades := NULL;

            FOR v_ing IN
                SELECT id_ingrediente, cantidad_total_necesaria
                  FROM fn_obtener_ingredientes_recursivos(p_id_producto, 1)
            LOOP
                v_tiene_receta := true;
                v_stock_ing := fn_stock_producto_almacen(v_ing.id_ingrediente, v_almacen_tpv);
                v_posibles  := floor(v_stock_ing / NULLIF(v_ing.cantidad_total_necesaria, 0));

                v_detalle := v_detalle || jsonb_build_object(
                    'id_ingrediente',     v_ing.id_ingrediente,
                    'ingrediente',        (SELECT denominacion FROM app_dat_producto
                                            WHERE id = v_ing.id_ingrediente),
                    'cantidad_necesaria', v_ing.cantidad_total_necesaria,
                    'stock_disponible',   v_stock_ing,
                    'unidades_posibles',  v_posibles
                );

                v_max_unidades := LEAST(COALESCE(v_max_unidades, v_posibles), v_posibles);
            END LOOP;

            v_disponible := CASE
                WHEN NOT v_tiene_receta THEN 0
                ELSE GREATEST(COALESCE(v_max_unidades, 0), 0)
            END;

            RETURN jsonb_build_object(
                'status',       'success',
                'id_producto',  p_id_producto,
                'producto',     v_prod.denominacion,
                'tipo',         'elaborado_sin_cocina',
                'modo_elaboracion', v_prod.modo_elaboracion,
                'id_almacen',   v_almacen_tpv,
                'disponible',   v_disponible,
                'tiene_receta', v_tiene_receta,
                'ingredientes', v_detalle,
                'message',      CASE WHEN v_tiene_receta
                                     THEN 'Calculado sobre la materia prima del almacen del TPV'
                                     ELSE 'El elaborado no tiene receta definida'
                                END
            );
        END IF;

        -- Producto normal: stock propio en el almacen del TPV.
        v_disponible := fn_stock_producto_almacen(p_id_producto, v_almacen_tpv);

        RETURN jsonb_build_object(
            'status',      'success',
            'id_producto', p_id_producto,
            'producto',    v_prod.denominacion,
            'tipo',        'stock_propio',
            'id_almacen',  v_almacen_tpv,
            'disponible',  v_disponible,
            'message',     'Stock en el almacen del TPV'
        );
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- El producto va a una cocina: validar cocina y enrutamiento
    -- ══════════════════════════════════════════════════════════════════════
    SELECT c.id_almacen, c.denominacion, c.activa
      INTO v_almacen_cocina, v_cocina_nombre, v_cocina_activa
      FROM app_dat_cocina c
     WHERE c.id = v_id_cocina AND c.deleted_at IS NULL;

    IF v_almacen_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El producto apunta a una cocina que no existe o fue eliminada',
            'error_code', 'COCINA_NOT_FOUND',
            'id_cocina',  v_id_cocina,
            'disponible', 0
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM app_dat_tpv_cocina
         WHERE id_tpv = p_id_tpv AND id_cocina = v_id_cocina
    ) INTO v_ligada;

    IF NOT v_ligada THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'id_producto', p_id_producto,
            'producto',    v_prod.denominacion,
            'tipo',        'no_disponible',
            'error_code',  'COCINA_NO_LIGADA',
            'id_cocina',   v_id_cocina,
            'cocina',      v_cocina_nombre,
            'disponible',  0,
            'vendible_aqui', false,
            'message',     'Este TPV no esta ligado a la cocina "' || v_cocina_nombre || '"'
        );
    END IF;

    IF NOT v_cocina_activa THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'id_producto', p_id_producto,
            'producto',    v_prod.denominacion,
            'tipo',        'no_disponible',
            'error_code',  'COCINA_INACTIVA',
            'id_cocina',   v_id_cocina,
            'cocina',      v_cocina_nombre,
            'disponible',  0,
            'vendible_aqui', false,
            'message',     'La cocina "' || v_cocina_nombre || '" esta desactivada'
        );
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- CASO 2 · por_tanda: stock terminado del propio SKU en la cocina
    -- ══════════════════════════════════════════════════════════════════════
    IF v_prod.modo_elaboracion = 'por_tanda' THEN
        v_disponible := fn_stock_producto_almacen(p_id_producto, v_almacen_cocina);

        RETURN jsonb_build_object(
            'status',           'success',
            'id_producto',      p_id_producto,
            'producto',         v_prod.denominacion,
            'tipo',             'por_tanda',
            'modo_elaboracion', 'por_tanda',
            'id_cocina',        v_id_cocina,
            'cocina',           v_cocina_nombre,
            'id_almacen',       v_almacen_cocina,
            'disponible',       v_disponible,
            'vendible_aqui',    true,
            'porciones_hechas', v_disponible,
            'message',          CASE WHEN v_disponible > 0
                                     THEN 'Porciones listas en ' || v_cocina_nombre
                                     ELSE 'Agotado: no hay porciones hechas en ' || v_cocina_nombre
                                END
        );
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- CASO 3 · al_pedido: limitado por la MP de esa cocina
    -- ══════════════════════════════════════════════════════════════════════
    v_max_unidades := NULL;

    FOR v_ing IN
        SELECT id_ingrediente, cantidad_total_necesaria
          FROM fn_obtener_ingredientes_recursivos(p_id_producto, 1)
    LOOP
        v_tiene_receta := true;

        v_stock_ing := fn_stock_producto_almacen(v_ing.id_ingrediente, v_almacen_cocina);
        v_posibles  := floor(v_stock_ing / NULLIF(v_ing.cantidad_total_necesaria, 0));

        v_detalle := v_detalle || jsonb_build_object(
            'id_ingrediente',     v_ing.id_ingrediente,
            'ingrediente',        (SELECT denominacion FROM app_dat_producto
                                    WHERE id = v_ing.id_ingrediente),
            'cantidad_necesaria', v_ing.cantidad_total_necesaria,
            'stock_disponible',   v_stock_ing,
            'unidades_posibles',  v_posibles,
            'suficiente',         v_stock_ing >= v_ing.cantidad_total_necesaria
        );

        v_max_unidades := LEAST(COALESCE(v_max_unidades, v_posibles), v_posibles);
    END LOOP;

    -- Un elaborado asignado a cocina pero SIN receta no se puede producir: no
    -- hay nada que descontar ni de que calcular. Se reporta explicito para que
    -- el admin lo note en vez de mostrar un plato que fallara al venderse.
    IF NOT v_tiene_receta THEN
        RETURN jsonb_build_object(
            'status',           'success',
            'id_producto',      p_id_producto,
            'producto',         v_prod.denominacion,
            'tipo',             'al_pedido',
            'modo_elaboracion', 'al_pedido',
            'id_cocina',        v_id_cocina,
            'cocina',           v_cocina_nombre,
            'id_almacen',       v_almacen_cocina,
            'disponible',       0,
            'vendible_aqui',    true,
            'tiene_receta',     false,
            'error_code',       'SIN_RECETA',
            'ingredientes',     '[]'::jsonb,
            'message',          'El plato no tiene receta definida: no se puede calcular disponibilidad'
        );
    END IF;

    v_disponible := GREATEST(COALESCE(v_max_unidades, 0), 0);

    RETURN jsonb_build_object(
        'status',           'success',
        'id_producto',      p_id_producto,
        'producto',         v_prod.denominacion,
        'tipo',             'al_pedido',
        'modo_elaboracion', 'al_pedido',
        'id_cocina',        v_id_cocina,
        'cocina',           v_cocina_nombre,
        'id_almacen',       v_almacen_cocina,
        'disponible',       v_disponible,
        'vendible_aqui',    true,
        'tiene_receta',     true,
        'ingredientes',     v_detalle,
        'message',          CASE WHEN v_disponible > 0
                                 THEN 'Se pueden preparar ' || v_disponible || ' en ' || v_cocina_nombre
                                 ELSE 'Sin materia prima suficiente en ' || v_cocina_nombre
                            END
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'Error al calcular disponibilidad: ' || SQLERRM,
            'sqlstate',   SQLSTATE,
            'disponible', 0
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_disponibilidad_plato(bigint, bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las 8 RPCs deben existir -> 8 filas
SELECT p.oid::regprocedure AS rpc
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_crear_cocina', 'fn_actualizar_cocina', 'fn_eliminar_cocina',
        'fn_listar_cocinas', 'fn_asignar_tpv_cocina', 'fn_desasignar_tpv_cocina',
        'fn_listar_cocinas_tpv', 'fn_disponibilidad_plato'
   )
 ORDER BY p.proname;

-- (b) Todas deben tener el guard de acceso por tienda -> 8 filas con true
SELECT p.proname,
       (p.prosrc ILIKE '%check_user_has_access_to_tienda%') AS tiene_guard
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_crear_cocina', 'fn_actualizar_cocina', 'fn_eliminar_cocina',
        'fn_listar_cocinas', 'fn_asignar_tpv_cocina', 'fn_desasignar_tpv_cocina',
        'fn_listar_cocinas_tpv', 'fn_disponibilidad_plato'
   )
 ORDER BY p.proname;

-- (c) Todas SECURITY DEFINER con search_path fijado -> 8 filas
SELECT p.proname, p.prosecdef AS security_definer, p.proconfig
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_crear_cocina', 'fn_actualizar_cocina', 'fn_eliminar_cocina',
        'fn_listar_cocinas', 'fn_asignar_tpv_cocina', 'fn_desasignar_tpv_cocina',
        'fn_listar_cocinas_tpv', 'fn_disponibilidad_plato'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL COMPLETA (transaccion revertida: no deja rastro)
--
-- Datos reales verificados de la tienda 11 (La Estrella):
--   TPV 18 "TPV La estrella" -> almacen 12
--   almacenes: 12 "La Estrella warehouse", 15 "contenedor refrigerado"
--   elaborado 219 "croqueta": 40 g de harina (216) + 10 g de sal (218)
--   harina (216) en almacen 12: 4.0 + 1.0 = 5.0  -> alcanza para 0 croquetas
--   sal    (218) en almacen 12: 27.5            -> alcanza para 2 croquetas
--
-- Ejecutar TODO el bloque de una vez.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    -- 1. Crear la cocina
    SELECT public.fn_crear_cocina(
        p_id_tienda    := 11,
        p_denominacion := 'PRUEBA Cocina caliente',
        p_descripcion  := 'cocina de prueba, se revierte'
    ) AS crear_cocina;
    -- esperado: status success, con id_cocina, id_almacen e id_layout

    -- 2. El trigger del 07 debe haber marcado el almacen como cocina
    SELECT a.id, a.denominacion, a.es_cocina
      FROM app_dat_almacen a
      JOIN app_dat_cocina c ON c.id_almacen = a.id
     WHERE c.denominacion = 'PRUEBA Cocina caliente';
    -- esperado: es_cocina = true

    -- 3. Nombre duplicado debe fallar de forma limpia
    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina caliente') AS duplicada;
    -- esperado: error_code DUPLICATE_COCINA

    -- 4. Convertir el almacen de venta del TPV en cocina debe fallar
    SELECT public.fn_crear_cocina(
        p_id_tienda            := 11,
        p_denominacion         := 'PRUEBA Cocina invalida',
        p_id_almacen_existente := 12
    ) AS almacen_de_tpv;
    -- esperado: error_code ALMACEN_ES_DE_TPV

    -- 5. Asignar el plato 219 a la cocina de prueba
    UPDATE app_dat_producto
       SET id_cocina = (SELECT id FROM app_dat_cocina
                         WHERE denominacion = 'PRUEBA Cocina caliente'),
           modo_elaboracion = 'al_pedido'
     WHERE id = 219;

    -- 6. Disponibilidad ANTES de ligar el TPV: no debe poder venderse
    SELECT public.fn_disponibilidad_plato(219, 18) AS sin_ligar;
    -- esperado: disponible 0, vendible_aqui false, error_code COCINA_NO_LIGADA

    -- 7. Ligar el TPV 18 a la cocina
    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina caliente')
    ) AS ligar;
    -- esperado: status success, ya_existia false

    -- 8. Idempotencia: ligar otra vez no debe fallar
    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina caliente')
    ) AS ligar_otra_vez;
    -- esperado: status success, ya_existia true

    -- 9. Disponibilidad al_pedido YA LIGADO.
    --    La cocina nueva no tiene materia prima, asi que 0, pero con el detalle
    --    por ingrediente y apuntando al almacen de la cocina (no al del TPV).
    SELECT public.fn_disponibilidad_plato(219, 18) AS al_pedido_cocina_vacia;
    -- esperado: disponible 0, tipo al_pedido, tiene_receta true,
    --           id_almacen = almacen de la cocina

    -- 10. Cambiar el plato a por_tanda: ahora mira stock terminado, no receta
    UPDATE app_dat_producto SET modo_elaboracion = 'por_tanda' WHERE id = 219;
    SELECT public.fn_disponibilidad_plato(219, 18) AS por_tanda;
    -- esperado: tipo por_tanda, disponible 0, porciones_hechas 0,
    --           mensaje "Agotado: no hay porciones hechas en ..."

    -- 11. Un producto de barra (sin cocina) sigue midiendo el almacen del TPV
    SELECT public.fn_disponibilidad_plato(216, 18) AS harina_barra;
    -- esperado: tipo stock_propio, disponible 5.0, id_almacen 12

    -- 12. Listado con contadores y TPVs anidados
    SELECT public.fn_listar_cocinas(11) AS listado;
    SELECT public.fn_listar_cocinas_tpv(18) AS cocinas_del_tpv;

    -- 13. Eliminar con producto asignado debe bloquear
    SELECT public.fn_eliminar_cocina(
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina caliente')
    ) AS eliminar_bloqueada;
    -- esperado: error_code COCINA_CON_PRODUCTOS, productos 1

    -- 14. Forzando si elimina y libera el producto
    SELECT public.fn_eliminar_cocina(
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina caliente'),
        true
    ) AS eliminar_forzada;
    -- esperado: status success, productos_liberados 1, tpvs_desligados 1

ROLLBACK;
*/

-- Comprobar que el ROLLBACK dejo todo limpio -> 0 filas en ambas
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT id, denominacion FROM app_dat_producto WHERE id = 219 AND id_cocina IS NOT NULL;

