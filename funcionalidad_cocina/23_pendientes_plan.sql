-- ============================================================================
-- 23 · Pendientes del plan · cocina por defecto en categoria + rol en UI
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE RESUELVE (pendientes marcados en docs/PLAN_RESTAURANTE_COCINA.md)
-- --------------------------------------------------------------------
--   Fase 1 (opcional): app_dat_categoria_tienda.id_cocina por defecto.
--   Fase 3: rol jefe_cocina en las RPC de gestion de roles del trabajador,
--           para que la UI de admin pueda asignarlo como cualquier otro rol.
--   Fase 3: acotar recepcion / conteo / transferencia al almacen de la cocina.
--
-- ESTADO VERIFICADO ANTES DE ESCRIBIR (via MCP)
-- ---------------------------------------------
--   * La columna app_dat_categoria_tienda.id_cocina YA EXISTE (la creo el 07,
--     seccion 7.5) con su FK. Nunca se uso: 0 filas con id_cocina en las 15
--     tiendas con categorias. Faltaba la logica, no el schema.
--
--   * Cadena producto -> categoria verificada:
--       app_dat_producto
--         -> app_dat_productos_subcategorias (id_producto, id_sub_categoria)
--         -> app_dat_subcategorias (id, idcategoria)
--         -> app_dat_categoria_tienda (id_categoria, id_tienda, id_cocina)
--     No hay ninguna columna id_categoria directa en el producto.
--
--   * BUG PREEXISTENTE ENCONTRADO al inspeccionar las 3 RPC de roles:
--     fn_agregar_rol_trabajador, fn_eliminar_rol_trabajador y
--     fn_actualizar_datos_rol_trabajador usan CASE ... END CASE **sin ELSE**.
--     En plpgsql eso lanza CASE_NOT_FOUND si ningun WHEN casa. Medido:
--
--       fn_eliminar_rol_trabajador(x, 'recursos_humanos')
--         -> {"success": false, "message": "Error al eliminar rol: case not found"}
--       fn_eliminar_rol_trabajador(x, 'auditor')          -> igual
--       fn_actualizar_datos_rol_trabajador(x, 'gerente')  -> igual
--
--     O sea: el rol "recursos_humanos" que la UI ya ofrece **no se puede
--     desactivar**, y el error sale como un mensaje generico. No es un problema
--     de cocina: es un bug que ya estaba. Se corrige aqui de paso.
--
-- DECISIONES DE DISENO
-- --------------------
--
-- 1. LA CATEGORIA SUGIERE, NO IMPONE.
--    La cocina de la categoria es un DEFECTO que se aplica cuando el plato no
--    tiene cocina propia. Nunca sobreescribe una asignacion explicita: si el
--    gerente puso "pizza margarita" en la Pizzeria y la categoria "Comidas"
--    apunta a Cocina caliente, el plato se queda en Pizzeria.
--
-- 2. LA HERENCIA SE RESUELVE AL ASIGNAR, NO AL LEER.
--    Se podria calcular la cocina efectiva en cada consulta (COALESCE del plato
--    y su categoria). No se hace: el enrutamiento de la venta (10, 11) y el KDS
--    leen producto.id_cocina directamente, y meter un COALESCE en ese camino
--    obligaria a tocar funciones de venta que ya estan probadas. En su lugar la
--    herencia se materializa cuando se asigna el plato: el dato queda escrito y
--    todo lo demas sigue leyendo una sola columna.
--
-- 3. UN BULK EXPLICITO PARA APLICAR LA CATEGORIA.
--    fn_aplicar_cocina_categoria_a_platos recorre los elaborados de la
--    categoria y asigna los que NO tienen cocina. Es el caso de uso real:
--    "acabo de crear la Cocina caliente, mandale todas las Comidas de golpe".
--    Devuelve que toco y que respeto, para que el gerente lo vea.
--
-- 4. jefe_cocina EN LAS RPC DE ROLES, PERO CON SU AMBITO.
--    El resto de roles se asignan con p_tpv_id o p_almacen_id. Cocina necesita
--    p_id_cocina, que esas RPC no tienen. Antes que cambiar su firma (las llama
--    la UI existente para 6 roles), se anade un parametro con DEFAULT NULL: las
--    llamadas viejas siguen compilando y funcionando igual.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Este archivo (idempotente).
--   2. Correr la VERIFICACION del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 23.1 fn_asignar_cocina_categoria
--
-- Define (o quita) la cocina por defecto de una categoria en una tienda.
--
-- p_id_cocina = NULL quita el defecto. No toca los platos ya asignados: quitar
-- el defecto de la categoria no debe desconfigurar la carta.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_asignar_cocina_categoria(
    p_id_tienda   bigint,
    p_id_categoria bigint,
    p_id_cocina   bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_ct       bigint;
    v_cat_nombre  text;
    v_coc_nombre  text;
    v_anterior    bigint;
BEGIN
    PERFORM check_user_has_access_to_tienda(p_id_tienda);

    SELECT ct.id, ct.id_cocina INTO v_id_ct, v_anterior
      FROM app_dat_categoria_tienda ct
     WHERE ct.id_tienda = p_id_tienda
       AND ct.id_categoria = p_id_categoria;

    IF v_id_ct IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Esa categoria no esta asociada a la tienda',
            'error_code', 'CATEGORIA_NO_EN_TIENDA'
        );
    END IF;

    SELECT c.denominacion INTO v_cat_nombre
      FROM app_dat_categoria c WHERE c.id = p_id_categoria;

    IF p_id_cocina IS NOT NULL THEN
        -- La cocina tiene que ser de ESTA tienda: si no, el defecto enviaria
        -- platos a una cocina que el TPV nunca podra alcanzar.
        SELECT ck.denominacion INTO v_coc_nombre
          FROM app_dat_cocina ck
         WHERE ck.id = p_id_cocina
           AND ck.id_tienda = p_id_tienda
           AND ck.deleted_at IS NULL;

        IF v_coc_nombre IS NULL THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'La cocina no existe o pertenece a otra tienda',
                'error_code', 'COCINA_INVALIDA'
            );
        END IF;
    END IF;

    UPDATE app_dat_categoria_tienda
       SET id_cocina = p_id_cocina
     WHERE id = v_id_ct;

    RETURN jsonb_build_object(
        'status',        'success',
        'id_tienda',     p_id_tienda,
        'id_categoria',  p_id_categoria,
        'categoria',     v_cat_nombre,
        'id_cocina',     p_id_cocina,
        'cocina',        v_coc_nombre,
        'cocina_anterior', v_anterior,
        'message', CASE
            WHEN p_id_cocina IS NULL
                THEN 'La categoria "' || COALESCE(v_cat_nombre, '?') || '" ya no tiene cocina por defecto'
            ELSE 'Los platos nuevos de "' || COALESCE(v_cat_nombre, '?')
                 || '" iran a ' || v_coc_nombre || ' salvo que se indique otra'
        END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_asignar_cocina_categoria(bigint, bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 23.2 fn_cocina_por_defecto_producto
--
-- Resuelve que cocina le corresponderia a un producto por sus categorias.
--
-- Un producto puede estar en varias subcategorias y por tanto en varias
-- categorias con cocina distinta. Se devuelve la de menor id de forma
-- determinista y se avisa con `ambiguo` para que la UI lo diga en vez de elegir
-- en silencio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cocina_por_defecto_producto(
    p_id_producto bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_candidatas jsonb;
    v_n integer;
    v_elegida bigint;
    v_nombre text;
BEGIN
    SELECT p.id_tienda INTO v_id_tienda
      FROM app_dat_producto p WHERE p.id = p_id_producto;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    -- producto -> subcategoria -> categoria -> categoria_tienda.id_cocina
    SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
               'id_cocina', q.id_cocina,
               'cocina',    q.cocina,
               'categoria', q.categoria)), '[]'::jsonb),
           count(DISTINCT q.id_cocina),
           min(q.id_cocina)
      INTO v_candidatas, v_n, v_elegida
      FROM (
        SELECT ct.id_cocina, ck.denominacion AS cocina, cat.denominacion AS categoria
          FROM app_dat_productos_subcategorias ps
          JOIN app_dat_subcategorias sc ON sc.id = ps.id_sub_categoria
          JOIN app_dat_categoria cat ON cat.id = sc.idcategoria
          JOIN app_dat_categoria_tienda ct ON ct.id_categoria = cat.id
                                          AND ct.id_tienda = v_id_tienda
          JOIN app_dat_cocina ck ON ck.id = ct.id_cocina
         WHERE ps.id_producto = p_id_producto
           AND ct.id_cocina IS NOT NULL
           AND ck.deleted_at IS NULL
      ) q;

    IF v_elegida IS NOT NULL THEN
        SELECT ck.denominacion INTO v_nombre
          FROM app_dat_cocina ck WHERE ck.id = v_elegida;
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'id_producto', p_id_producto,
        'id_cocina',   v_elegida,
        'cocina',      v_nombre,
        'ambiguo',     COALESCE(v_n, 0) > 1,
        'candidatas',  v_candidatas,
        'message', CASE
            WHEN v_elegida IS NULL
                THEN 'Ninguna categoria de este producto tiene cocina por defecto'
            WHEN COALESCE(v_n, 0) > 1
                THEN 'El producto pertenece a ' || v_n || ' categorias con cocinas distintas; '
                     || 'se propone ' || v_nombre
            ELSE 'Cocina por defecto: ' || v_nombre
        END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cocina_por_defecto_producto(bigint)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 23.3 fn_aplicar_cocina_categoria_a_platos
--
-- Bulk: manda a la cocina de la categoria todos los elaborados de esa categoria
-- que NO tengan cocina propia.
--
-- Es el caso de uso real: "acabo de crear la Cocina caliente, mandale todas las
-- Comidas de golpe". Los que ya tienen cocina se RESPETAN y se informan aparte:
-- una asignacion explicita del gerente no se pisa nunca en un bulk.
--
-- p_modo_elaboracion permite fijar tambien el modo de golpe (por_tanda para una
-- categoria de guarniciones, por ejemplo). NULL = no tocar el modo.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_aplicar_cocina_categoria_a_platos(
    p_id_tienda        bigint,
    p_id_categoria     bigint,
    p_modo_elaboracion text    DEFAULT NULL,
    p_solo_elaborados  boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_cocina bigint;
    v_cocina    text;
    v_categoria text;
    v_asignados jsonb := '[]'::jsonb;
    v_respetados jsonb := '[]'::jsonb;
    v_p RECORD;
BEGIN
    PERFORM check_user_has_access_to_tienda(p_id_tienda);

    IF p_modo_elaboracion IS NOT NULL
       AND p_modo_elaboracion NOT IN ('por_tanda', 'al_pedido') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El modo de elaboracion debe ser por_tanda o al_pedido',
            'error_code', 'MODO_INVALIDO'
        );
    END IF;

    SELECT ct.id_cocina, ck.denominacion, cat.denominacion
      INTO v_id_cocina, v_cocina, v_categoria
      FROM app_dat_categoria_tienda ct
      JOIN app_dat_categoria cat ON cat.id = ct.id_categoria
      LEFT JOIN app_dat_cocina ck ON ck.id = ct.id_cocina AND ck.deleted_at IS NULL
     WHERE ct.id_tienda = p_id_tienda
       AND ct.id_categoria = p_id_categoria;

    IF v_categoria IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Esa categoria no esta asociada a la tienda',
            'error_code', 'CATEGORIA_NO_EN_TIENDA'
        );
    END IF;

    IF v_id_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La categoria "' || v_categoria || '" no tiene cocina por defecto. '
                       || 'Asignasela primero.',
            'error_code', 'CATEGORIA_SIN_COCINA'
        );
    END IF;

    FOR v_p IN
        SELECT DISTINCT p.id, p.denominacion, p.id_cocina, p.es_elaborado
          FROM app_dat_producto p
          JOIN app_dat_productos_subcategorias ps ON ps.id_producto = p.id
          JOIN app_dat_subcategorias sc ON sc.id = ps.id_sub_categoria
         WHERE sc.idcategoria = p_id_categoria
           AND p.id_tienda = p_id_tienda
           AND p.deleted_at IS NULL
           AND (NOT p_solo_elaborados OR p.es_elaborado = true)
         ORDER BY p.denominacion
    LOOP
        IF v_p.id_cocina IS NOT NULL THEN
            -- Ya tiene cocina: se respeta. Solo se informa.
            v_respetados := v_respetados || jsonb_build_object(
                'id_producto', v_p.id,
                'producto',    v_p.denominacion,
                'id_cocina',   v_p.id_cocina,
                'cocina',      (SELECT denominacion FROM app_dat_cocina WHERE id = v_p.id_cocina)
            );
            CONTINUE;
        END IF;

        UPDATE app_dat_producto
           SET id_cocina = v_id_cocina,
               modo_elaboracion = COALESCE(p_modo_elaboracion, modo_elaboracion, 'al_pedido')
         WHERE id = v_p.id;

        v_asignados := v_asignados || jsonb_build_object(
            'id_producto', v_p.id,
            'producto',    v_p.denominacion,
            'es_elaborado', v_p.es_elaborado
        );
    END LOOP;

    RETURN jsonb_build_object(
        'status',      'success',
        'id_categoria', p_id_categoria,
        'categoria',   v_categoria,
        'id_cocina',   v_id_cocina,
        'cocina',      v_cocina,
        'asignados',   v_asignados,
        'total_asignados', jsonb_array_length(v_asignados),
        'respetados',  v_respetados,
        'total_respetados', jsonb_array_length(v_respetados),
        'message',
            jsonb_array_length(v_asignados) || ' plato(s) enviados a ' || v_cocina
            || CASE WHEN jsonb_array_length(v_respetados) > 0
                    THEN '. ' || jsonb_array_length(v_respetados)
                         || ' ya tenian cocina propia y no se tocaron'
                    ELSE '' END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_aplicar_cocina_categoria_a_platos(bigint, bigint, text, boolean)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 23.4 fn_asignar_plato_cocina
--
-- Asigna cocina y modo a un plato, con HERENCIA de la categoria.
--
-- Hasta ahora el admin hacia un UPDATE directo desde Dart
-- (CocinaService.asignarCocinaAProducto). Eso funciona, pero no puede heredar
-- de la categoria ni validar nada. Esta RPC:
--
--   * p_id_cocina indicado  -> se usa tal cual (el gerente manda).
--   * p_id_cocina NULL y p_heredar_categoria = true -> se busca el defecto de
--     la categoria.
--   * p_id_cocina NULL y p_heredar_categoria = false -> se DESASIGNA (el plato
--     vuelve a ser producto de barra).
--
-- La diferencia entre "no me lo dijeron" y "quitamelo" no se puede expresar con
-- un solo NULL, de ahi el flag.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_asignar_plato_cocina(
    p_id_producto       bigint,
    p_id_cocina         bigint  DEFAULT NULL,
    p_modo_elaboracion  text    DEFAULT NULL,
    p_heredar_categoria boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_producto  text;
    v_es_elab   boolean;
    v_final     bigint;
    v_cocina    text;
    v_heredada  boolean := false;
    v_defecto   jsonb;
    v_modo      text;
BEGIN
    SELECT p.id_tienda, p.denominacion, p.es_elaborado, p.modo_elaboracion
      INTO v_id_tienda, v_producto, v_es_elab, v_modo
      FROM app_dat_producto p WHERE p.id = p_id_producto;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    IF p_modo_elaboracion IS NOT NULL
       AND p_modo_elaboracion NOT IN ('por_tanda', 'al_pedido') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El modo de elaboracion debe ser por_tanda o al_pedido',
            'error_code', 'MODO_INVALIDO'
        );
    END IF;

    v_final := p_id_cocina;

    -- Herencia de la categoria: solo si no vino cocina explicita.
    IF v_final IS NULL AND p_heredar_categoria THEN
        v_defecto := fn_cocina_por_defecto_producto(p_id_producto);
        IF (v_defecto->>'status') = 'success' AND (v_defecto->'id_cocina') <> 'null'::jsonb THEN
            v_final := (v_defecto->>'id_cocina')::bigint;
            v_heredada := true;
        END IF;
    END IF;

    IF v_final IS NOT NULL THEN
        SELECT ck.denominacion INTO v_cocina
          FROM app_dat_cocina ck
         WHERE ck.id = v_final
           AND ck.id_tienda = v_id_tienda
           AND ck.deleted_at IS NULL;

        IF v_cocina IS NULL THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'La cocina no existe o pertenece a otra tienda',
                'error_code', 'COCINA_INVALIDA'
            );
        END IF;
    END IF;

    UPDATE app_dat_producto
       SET id_cocina = v_final,
           modo_elaboracion = CASE
               WHEN p_modo_elaboracion IS NOT NULL THEN p_modo_elaboracion
               WHEN v_final IS NOT NULL THEN COALESCE(v_modo, 'al_pedido')
               ELSE v_modo
           END
     WHERE id = p_id_producto;

    SELECT p.modo_elaboracion INTO v_modo
      FROM app_dat_producto p WHERE p.id = p_id_producto;

    RETURN jsonb_build_object(
        'status',           'success',
        'id_producto',      p_id_producto,
        'producto',         v_producto,
        'es_elaborado',     v_es_elab,
        'id_cocina',        v_final,
        'cocina',           v_cocina,
        'modo_elaboracion', v_modo,
        'heredada_de_categoria', v_heredada,
        'message', CASE
            WHEN v_final IS NULL
                THEN v_producto || ' ya no pertenece a ninguna cocina'
            WHEN v_heredada
                THEN v_producto || ' asignado a ' || v_cocina || ' (heredado de su categoria)'
            ELSE v_producto || ' asignado a ' || v_cocina
        END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_asignar_plato_cocina(bigint, bigint, text, boolean)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 23.5 Rol jefe_cocina en las RPC de gestion de roles
--
-- Para que la UI de admin (edit_worker_multi_role_screen) pueda asignar jefe de
-- cocina como cualquier otro rol, las 3 RPC de roles tienen que conocerlo.
--
-- Se anaden con parametros NUEVOS Y CON DEFAULT: las llamadas existentes de la
-- app (6 roles, sin p_id_cocina) siguen funcionando sin cambios.
--
-- ADEMAS SE CORRIGE UN BUG PREEXISTENTE:
-- los 3 CASE no tenian ELSE, asi que un rol no contemplado lanzaba
-- CASE_NOT_FOUND y salia como "Error al eliminar rol: case not found".
-- Medido antes del fix:
--   fn_eliminar_rol_trabajador(x,'recursos_humanos') -> case not found
--   fn_eliminar_rol_trabajador(x,'auditor')          -> case not found
-- Es decir: el rol recursos_humanos que la UI ya ofrece NO SE PODIA DESACTIVAR.
-- ----------------------------------------------------------------------------

-- Antes de recrear: eliminar las firmas ANTIGUAS. Anadir parametros con DEFAULT
-- NO reemplaza la funcion, crea una SOBRECARGA. Con las dos vivas la llamada de
-- la app (7/2/5 argumentos) queda ambigua y Postgres la rechaza con
-- "function ... is not unique" -> pantalla de trabajadores rota. Medido y
-- corregido durante la implementacion.
DROP FUNCTION IF EXISTS public.fn_agregar_rol_trabajador(bigint, bigint, text, uuid, bigint, bigint, text);
DROP FUNCTION IF EXISTS public.fn_eliminar_rol_trabajador(bigint, text);
DROP FUNCTION IF EXISTS public.fn_actualizar_datos_rol_trabajador(bigint, text, bigint, bigint, text);

-- 23.5.a agregar rol (+ jefe_cocina, + ELSE)
CREATE OR REPLACE FUNCTION public.fn_agregar_rol_trabajador(
    p_trabajador_id       bigint,
    p_id_tienda           bigint,
    p_tipo_rol            text,
    p_usuario_uuid        uuid,
    p_tpv_id              bigint DEFAULT NULL,
    p_almacen_id          bigint DEFAULT NULL,
    p_numero_confirmacion text   DEFAULT NULL,
    p_id_cocina           bigint DEFAULT NULL,
    p_es_jefe_cocina      boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_exists boolean;
    v_trabajador_uuid uuid;
BEGIN
    SELECT uuid INTO v_trabajador_uuid
      FROM app_dat_trabajadores
     WHERE id = p_trabajador_id;

    IF v_trabajador_uuid IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El trabajador debe tener un UUID antes de asignarle roles'
        );
    END IF;

    CASE p_tipo_rol
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
                    RETURN jsonb_build_object(
                        'success', false,
                        'message', 'El rol de almacenero requiere un almacén asignado'
                    );
                END IF;

                INSERT INTO app_dat_almacenero (id_trabajador, uuid, id_almacen)
                VALUES (p_trabajador_id, v_trabajador_uuid, p_almacen_id);
            ELSE
                UPDATE app_dat_almacenero
                   SET id_almacen = COALESCE(p_almacen_id, id_almacen)
                 WHERE id_trabajador = p_trabajador_id;
            END IF;

        -- FASE 3: jefe de cocina / cocinero. Se delega en fn_asignar_jefe_cocina
        -- para no duplicar el guard ni la logica de UNIQUE(uuid, id_cocina).
        WHEN 'jefe_cocina', 'cocinero' THEN
            IF p_id_cocina IS NULL THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'El rol de cocina requiere una cocina asignada'
                );
            END IF;

            PERFORM fn_asignar_jefe_cocina(
                v_trabajador_uuid,
                p_id_cocina,
                p_trabajador_id,
                CASE WHEN p_tipo_rol = 'cocinero' THEN false
                     ELSE COALESCE(p_es_jefe_cocina, true) END
            );

        ELSE
            -- Antes esto lanzaba CASE_NOT_FOUND y el error salia como
            -- "case not found". Roles sin tabla propia (recursos_humanos,
            -- usuario) simplemente no tienen nada que insertar.
            RETURN jsonb_build_object(
                'success', true,
                'message', 'El rol "' || p_tipo_rol || '" no requiere registro de ambito',
                'sin_ambito', true
            );
    END CASE;

    RETURN jsonb_build_object('success', true, 'message', 'Rol agregado correctamente');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al agregar rol: ' || SQLERRM
        );
END;
$function$;


-- 23.5.b eliminar rol (+ jefe_cocina, + ELSE)
CREATE OR REPLACE FUNCTION public.fn_eliminar_rol_trabajador(
    p_trabajador_id bigint,
    p_tipo_rol      text,
    p_id_cocina     bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_uuid uuid;
    v_n    integer;
BEGIN
    CASE p_tipo_rol
        WHEN 'gerente' THEN
            DELETE FROM app_dat_gerente WHERE id_trabajador = p_trabajador_id;
        WHEN 'supervisor' THEN
            DELETE FROM app_dat_supervisor WHERE id_trabajador = p_trabajador_id;
        WHEN 'vendedor' THEN
            DELETE FROM app_dat_vendedor WHERE id_trabajador = p_trabajador_id;
        WHEN 'almacenero' THEN
            DELETE FROM app_dat_almacenero WHERE id_trabajador = p_trabajador_id;

        WHEN 'jefe_cocina', 'cocinero' THEN
            -- p_id_cocina NULL quita TODAS las cocinas del trabajador (quitar el
            -- rol entero). Con id concreto solo esa estacion, porque
            -- UNIQUE(uuid, id_cocina) permite cubrir varias.
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
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Rol de cocina eliminado (' || v_n || ' asignacion(es))',
                'eliminadas', v_n
            );

        ELSE
            RETURN jsonb_build_object(
                'success', true,
                'message', 'El rol "' || p_tipo_rol || '" no tiene registro de ambito que eliminar',
                'sin_ambito', true
            );
    END CASE;

    RETURN jsonb_build_object('success', true, 'message', 'Rol eliminado correctamente');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al eliminar rol: ' || SQLERRM
        );
END;
$function$;


-- 23.5.c actualizar datos del rol (+ jefe_cocina, + ELSE)
CREATE OR REPLACE FUNCTION public.fn_actualizar_datos_rol_trabajador(
    p_trabajador_id       bigint,
    p_tipo_rol            text,
    p_tpv_id              bigint  DEFAULT NULL,
    p_almacen_id          bigint  DEFAULT NULL,
    p_numero_confirmacion text    DEFAULT NULL,
    p_id_cocina           bigint  DEFAULT NULL,
    p_es_jefe_cocina      boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_uuid uuid;
BEGIN
    CASE p_tipo_rol
        WHEN 'vendedor' THEN
            UPDATE app_dat_vendedor
               SET id_tpv = COALESCE(p_tpv_id, id_tpv),
                   numero_confirmacion = COALESCE(p_numero_confirmacion, numero_confirmacion)
             WHERE id_trabajador = p_trabajador_id;

        WHEN 'almacenero' THEN
            UPDATE app_dat_almacenero
               SET id_almacen = COALESCE(p_almacen_id, id_almacen)
             WHERE id_trabajador = p_trabajador_id;

        WHEN 'jefe_cocina', 'cocinero' THEN
            SELECT uuid INTO v_uuid FROM app_dat_trabajadores WHERE id = p_trabajador_id;

            IF v_uuid IS NULL THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'El trabajador no tiene UUID'
                );
            END IF;

            IF p_id_cocina IS NOT NULL THEN
                -- Cambiar de cocina = quitar las anteriores y asignar la nueva.
                -- Si se quisiera cubrir dos estaciones se llama a agregar dos veces.
                DELETE FROM app_dat_jefe_cocina
                 WHERE (id_trabajador = p_trabajador_id OR uuid = v_uuid)
                   AND id_cocina <> p_id_cocina;

                PERFORM fn_asignar_jefe_cocina(
                    v_uuid, p_id_cocina, p_trabajador_id,
                    CASE WHEN p_tipo_rol = 'cocinero' THEN false
                         ELSE COALESCE(p_es_jefe_cocina, true) END
                );
            ELSIF p_es_jefe_cocina IS NOT NULL THEN
                -- Solo cambiar el grado (jefe <-> cocinero) sin mover de cocina.
                UPDATE app_dat_jefe_cocina
                   SET es_jefe = p_es_jefe_cocina
                 WHERE id_trabajador = p_trabajador_id OR uuid = v_uuid;
            END IF;

        ELSE
            RETURN jsonb_build_object(
                'success', true,
                'message', 'El rol "' || p_tipo_rol || '" no tiene datos de ambito que actualizar',
                'sin_ambito', true
            );
    END CASE;

    RETURN jsonb_build_object('success', true, 'message', 'Datos actualizados correctamente');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al actualizar datos: ' || SQLERRM
        );
END;
$function$;


-- ----------------------------------------------------------------------------
-- 23.6 fn_almacenes_del_usuario
--
-- Que almacenes puede operar el usuario y con que alcance. Es la RPC que
-- necesita la UI para acotar recepcion / conteo / transferencia.
--
-- Cada rol aporta lo suyo:
--   gerente / supervisor -> todos los almacenes de la tienda
--   almacenero           -> su almacen
--   jefe de cocina       -> el almacen de SU cocina (y solo si es_jefe)
--
-- `es_cocina` viaja en la respuesta para que la UI pueda mostrar "Cocina
-- caliente" en vez de "Almacen 37" y ordenar en consecuencia.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_almacenes_del_usuario(
    p_id_tienda bigint DEFAULT NULL
)
RETURNS TABLE (
    id_almacen    bigint,
    denominacion  text,
    id_tienda     bigint,
    es_cocina     boolean,
    id_cocina     bigint,
    cocina        text,
    origen        text,
    puede_operar  boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
    -- gerente
    SELECT a.id, a.denominacion::text, a.id_tienda,
           COALESCE(a.es_cocina, false),
           ck.id, ck.denominacion::text,
           'gerente'::text, true
      FROM app_dat_gerente g
      JOIN app_dat_almacen a ON a.id_tienda = g.id_tienda
      LEFT JOIN app_dat_cocina ck ON ck.id_almacen = a.id AND ck.deleted_at IS NULL
     WHERE g.uuid = auth.uid()
       AND (p_id_tienda IS NULL OR a.id_tienda = p_id_tienda)

    UNION

    -- supervisor
    SELECT a.id, a.denominacion::text, a.id_tienda,
           COALESCE(a.es_cocina, false),
           ck.id, ck.denominacion::text,
           'supervisor'::text, true
      FROM app_dat_supervisor s
      JOIN app_dat_almacen a ON a.id_tienda = s.id_tienda
      LEFT JOIN app_dat_cocina ck ON ck.id_almacen = a.id AND ck.deleted_at IS NULL
     WHERE s.uuid = auth.uid()
       AND (p_id_tienda IS NULL OR a.id_tienda = p_id_tienda)

    UNION

    -- almacenero: su almacen
    SELECT a.id, a.denominacion::text, a.id_tienda,
           COALESCE(a.es_cocina, false),
           ck.id, ck.denominacion::text,
           'almacenero'::text, true
      FROM app_dat_almacenero al
      JOIN app_dat_almacen a ON a.id = al.id_almacen
      LEFT JOIN app_dat_cocina ck ON ck.id_almacen = a.id AND ck.deleted_at IS NULL
     WHERE al.uuid = auth.uid()
       AND (p_id_tienda IS NULL OR a.id_tienda = p_id_tienda)

    UNION

    -- jefe de cocina: el almacen de su cocina. Un cocinero (es_jefe = false) lo
    -- VE pero con puede_operar = false: consulta si, mover inventario no.
    SELECT a.id, a.denominacion::text, a.id_tienda,
           true, ck.id, ck.denominacion::text,
           CASE WHEN jc.es_jefe THEN 'jefe_cocina' ELSE 'cocinero' END::text,
           jc.es_jefe
      FROM app_dat_jefe_cocina jc
      JOIN app_dat_cocina ck ON ck.id = jc.id_cocina AND ck.deleted_at IS NULL
      JOIN app_dat_almacen a ON a.id = ck.id_almacen
     WHERE jc.uuid = auth.uid()
       AND (p_id_tienda IS NULL OR a.id_tienda = p_id_tienda)

    ORDER BY 3, 4 DESC, 2;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_almacenes_del_usuario(bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las funciones nuevas / modificadas
SELECT p.oid::regprocedure AS firma, p.prosecdef AS sec_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_asignar_cocina_categoria',
                     'fn_cocina_por_defecto_producto',
                     'fn_aplicar_cocina_categoria_a_platos',
                     'fn_asignar_plato_cocina',
                     'fn_almacenes_del_usuario',
                     'fn_agregar_rol_trabajador',
                     'fn_eliminar_rol_trabajador',
                     'fn_actualizar_datos_rol_trabajador')
 ORDER BY p.proname;

-- (b) Los 3 CASE ya tienen ELSE -> ningun rol produce "case not found"
SELECT p.proname,
       (p.prosrc LIKE '%ELSE%') AS tiene_else,
       (p.prosrc LIKE '%jefe_cocina%') AS conoce_cocina
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_agregar_rol_trabajador',
                     'fn_eliminar_rol_trabajador',
                     'fn_actualizar_datos_rol_trabajador')
 ORDER BY p.proname;

-- (c) Categorias con cocina por defecto
SELECT ct.id_tienda, cat.denominacion AS categoria, ck.denominacion AS cocina
  FROM app_dat_categoria_tienda ct
  JOIN app_dat_categoria cat ON cat.id = ct.id_categoria
  JOIN app_dat_cocina ck ON ck.id = ct.id_cocina
 WHERE ct.id_cocina IS NOT NULL
 ORDER BY ct.id_tienda, cat.denominacion;

-- ----------------------------------------------------------------------------
-- 23.7 fn_envolver_texto  + fix del truncado en fn_ticket_comanda
--
-- BUG PROPIO ENCONTRADO AL PROBAR LA IMPRESION (no lo detecta ningun validador).
--
-- fn_ticket_comanda (del 22) metia el texto en el ancho del papel con substr(),
-- o sea TRUNCANDO. Medido con ancho 32 (termica de 58 mm):
--
--   nota del comensal: 'sin sal y bien tostada por favor que es para un nino
--                       alergico al gluten'
--   ticket impreso:    '   >> SIN SAL Y BIEN TOSTADA POR'
--
-- Se perdia 'alergico al gluten' y el cocinero no tenia forma de saber que
-- faltaba texto. Es exactamente el dato que provoca devoluciones -- o algo peor.
--
-- Se anade un helper de ajuste por palabras y se sustituyen los 3 substr() del
-- ticket (nombre del plato, nota del item, nota de la comanda).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_envolver_texto(
    p_texto   text,
    p_ancho   integer,
    p_sangria text DEFAULT ''
)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $function$
DECLARE
    v_palabras text[];
    v_p        text;
    v_linea    text := '';
    v_out      text[] := ARRAY[]::text[];
    v_util     integer;
BEGIN
    IF p_texto IS NULL OR TRIM(p_texto) = '' THEN
        RETURN ARRAY[]::text[];
    END IF;

    v_util := GREATEST(p_ancho - length(COALESCE(p_sangria, '')), 8);
    v_palabras := regexp_split_to_array(TRIM(p_texto), '\s+');

    FOREACH v_p IN ARRAY v_palabras LOOP
        -- Una palabra sola mas larga que el ancho (un SKU, una URL): se parte,
        -- no hay alternativa, pero se parte solo esa.
        WHILE length(v_p) > v_util LOOP
            IF v_linea <> '' THEN
                v_out := v_out || (p_sangria || v_linea);
                v_linea := '';
            END IF;
            v_out := v_out || (p_sangria || substr(v_p, 1, v_util));
            v_p := substr(v_p, v_util + 1);
        END LOOP;

        IF v_linea = '' THEN
            v_linea := v_p;
        ELSIF length(v_linea) + 1 + length(v_p) <= v_util THEN
            v_linea := v_linea || ' ' || v_p;
        ELSE
            v_out := v_out || (p_sangria || v_linea);
            v_linea := v_p;
        END IF;
    END LOOP;

    IF v_linea <> '' THEN
        v_out := v_out || (p_sangria || v_linea);
    END IF;

    RETURN v_out;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_envolver_texto(text, integer, text)
    TO anon, authenticated, service_role;


-- Sustitucion textual sobre la definicion VIVA de fn_ticket_comanda: se cambian
-- los 3 substr() por el helper. Idempotente (se salta si ya esta aplicado).
DO $do$
DECLARE
    v_def text; v_n integer; viejo text; nuevo text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_ticket_comanda';

    IF v_def IS NULL THEN RAISE EXCEPTION 'fn_ticket_comanda no existe'; END IF;
    IF v_def LIKE '%fn_envolver_texto%' THEN
        RAISE NOTICE 'ya envuelve el texto'; RETURN;
    END IF;

    viejo := '    v_items jsonb := ''[]''::jsonb; v_n integer := 0;';
    v_n := (length(v_def) - length(replace(v_def, viejo, ''))) / length(viejo);
    IF v_n <> 1 THEN RAISE EXCEPTION 'anclaje 1: % ocurrencias', v_n; END IF;
    v_def := replace(v_def, viejo, viejo || E'\n    v_wrap text[]; v_w text;');

    viejo := '        v_texto := v_texto || substr(v_linea, 1, v_ancho) || E''\n'';';
    v_n := (length(v_def) - length(replace(v_def, viejo, ''))) / length(viejo);
    IF v_n <> 1 THEN RAISE EXCEPTION 'anclaje 2: % ocurrencias', v_n; END IF;
    nuevo := '        -- Envolver, NO truncar: un plato de nombre largo se leia a medias.
        v_wrap := fn_envolver_texto(v_linea, v_ancho, '''');
        FOREACH v_w IN ARRAY v_wrap LOOP
            v_texto := v_texto || v_w || E''\n'';
        END LOOP;';
    v_def := replace(v_def, viejo, nuevo);

    viejo := '            v_texto := v_texto || ''   >> '' || upper(substr(TRIM(v_it.notas), 1, v_ancho - 6)) || E''\n'';';
    v_n := (length(v_def) - length(replace(v_def, viejo, ''))) / length(viejo);
    IF v_n <> 1 THEN RAISE EXCEPTION 'anclaje 3: % ocurrencias', v_n; END IF;
    nuevo := '            -- La nota del comensal NO se trunca: es lo que provoca devoluciones.
            v_wrap := fn_envolver_texto(upper(TRIM(v_it.notas)), v_ancho, ''   >> '');
            FOREACH v_w IN ARRAY v_wrap LOOP
                v_texto := v_texto || v_w || E''\n'';
            END LOOP;';
    v_def := replace(v_def, viejo, nuevo);

    viejo := '        v_texto := v_texto || ''NOTA: '' || upper(TRIM(v_co.notas)) || E''\n'';';
    v_n := (length(v_def) - length(replace(v_def, viejo, ''))) / length(viejo);
    IF v_n <> 1 THEN RAISE EXCEPTION 'anclaje 4: % ocurrencias', v_n; END IF;
    nuevo := '        v_wrap := fn_envolver_texto(''NOTA: '' || upper(TRIM(v_co.notas)), v_ancho, '''');
        FOREACH v_w IN ARRAY v_wrap LOOP
            v_texto := v_texto || v_w || E''\n'';
        END LOOP;';
    v_def := replace(v_def, viejo, nuevo);

    EXECUTE v_def;
    RAISE NOTICE 'fn_ticket_comanda ahora envuelve el texto sin truncar';
END
$do$;


-- ============================================================================
-- VERIFICACION EXTRA (23.6 - 23.7)
-- ============================================================================

-- (d) Alcance de almacenes: cada rol ve lo suyo
--     Ejecutar con el JWT simulado de cada usuario para comprobarlo.
SELECT * FROM public.fn_almacenes_del_usuario();

-- (e) El ticket no excede el ancho del papel y no pierde texto
--     Sustituir <ID_COMANDA> por una comanda real con notas largas.
-- SELECT CASE WHEN bool_and(length(l) <= 32) THEN 'OK todas caben'
--             ELSE 'FALLO max=' || max(length(l)) END AS ancho_32
--   FROM regexp_split_to_table(
--          (public.fn_ticket_comanda(<ID_COMANDA>, 32))->>'texto', E'\n') l
--  WHERE l <> '';

-- (f) El helper de ajuste con una palabra mas larga que el ancho
SELECT public.fn_envolver_texto(
         'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 20, '   >> ') AS parte_solo_esa;
