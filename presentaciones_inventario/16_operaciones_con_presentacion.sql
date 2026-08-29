-- ============================================================================
-- 16 · Listas de operaciones con la presentacion de cada linea
-- ============================================================================
--
-- PROPOSITO
-- ---------
-- Inyectar las 5 claves de fn_presentacion_item_json (archivo 15) en los SIETE
-- bloques que arman el JSON de `items` dentro de
-- fn_listar_operaciones_inventario_new, para que la UI pueda escribir
-- "4 Bultos" en vez de "4" (o, peor, "4 unidades" inventando la etiqueta).
--
-- Verificado contra la funcion viva (2026-08-27):
--   position('id_presentacion' in prosrc) = 0
--   → la columna existe en las 3 tablas de detalle y la RPC NO la lee.
--
-- POR QUE UN DO BLOCK Y NO EL CREATE OR REPLACE COMPLETO
-- ------------------------------------------------------
-- La funcion tiene 600 lineas / 33.495 caracteres y SIETE ramas que construyen
-- items (venta, transferencia×3, extraccion, recepcion, control). Pegarla
-- entera aca significa:
--   a) que este archivo quede desincronizado en cuanto alguien toque la RPC por
--      otro motivo (ya paso con los .sql de la raiz del repo);
--   b) 33 KB de SQL en el que un parentesis mal puesto es invisible.
--
-- En cambio este script LEE la definicion viva, le aplica solo las inserciones
-- y la reescribe. Es idempotente (si ya esta aplicado, sale sin tocar nada) y
-- ABORTA si el conteo de parches no da exacto: 4 extraccion + 2 recepcion +
-- 1 control. Si manana produccion cambia y un patron deja de calzar, este
-- archivo falla en voz alta en vez de aplicar un parche parcial.
--
-- EL COALESCE NO ES OPCIONAL
-- --------------------------
-- fn_presentacion_item_json devuelve NULL cuando la presentacion no existe, y
-- en Postgres `jsonb || NULL` es NULL: sin el COALESCE una sola fila huerfana
-- borraria el item COMPLETO del JSON (el producto desapareceria de la lista de
-- la operacion). Censo en produccion: 0 huerfanas de 201.772 filas de
-- extraccion, 24.465 de recepcion, 187.585 de control. La defensa cuesta cero.
--
-- COMPATIBILIDAD
-- --------------
-- Solo AGREGA claves al objeto de cada item, con el merge `||` al mismo nivel.
-- Ningun campo existente cambia de nombre ni de tipo, asi que el Dart actual
-- (item['cantidad'], item['sku_producto'], item['importe']...) sigue leyendo
-- igual. Las pantallas que no usen las claves nuevas no se enteran.
--
-- Claves nuevas por item:
--   id_presentacion, presentacion_nombre, presentacion_sku,
--   presentacion_factor, cantidad_formateada
--
-- DEPENDE DE: 15_presentacion_item_json.sql (aplicado primero).
-- ============================================================================

DO $do$
DECLARE
    v_def  text;
    v_new  text;
    v_ext  int;
    v_rec  int;
    v_ctrl int;
BEGIN
    v_def := pg_get_functiondef(
        'public.fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer)'::regprocedure
    );

    -- Idempotencia: si ya tiene el merge, no se toca.
    IF v_def LIKE '%fn_presentacion_item_json%' THEN
        RAISE NOTICE 'fn_listar_operaciones_inventario_new ya trae la presentacion; sin cambios.';
        RETURN;
    END IF;

    v_new := v_def;

    -- Ramas de EXTRACCION (venta, transferencia×2, extraccion suelta): el
    -- jsonb_build_object termina en el importe calculado.
    v_new := regexp_replace(
        v_new,
        '(''importe'',\s+COALESCE\(ep\.importe, ep\.precio_unitario \* ep\.cantidad\)\s*\r?\n)(\s*)\)\)',
        '\1\2) || COALESCE(public.fn_presentacion_item_json(ep.id_presentacion, ep.cantidad), ''{}''::jsonb))',
        'g'
    );

    -- Ramas de RECEPCION (transferencia y recepcion suelta): terminan en
    -- precio_unitario, sin importe.
    v_new := regexp_replace(
        v_new,
        '(''precio_unitario'', rp\.precio_unitario\s*\r?\n)(\s*)\)\)',
        '\1\2) || COALESCE(public.fn_presentacion_item_json(rp.id_presentacion, rp.cantidad), ''{}''::jsonb))',
        'g'
    );

    -- Rama de CONTROL (conteo de inventario): el jsonb_agg y el
    -- jsonb_build_object cierran en lineas distintas, por eso el patron captura
    -- el salto en el grupo 3 en vez de escribirlo en el reemplazo (un '\n' en el
    -- string de reemplazo entra como backslash-n LITERAL y rompe la funcion).
    v_new := regexp_replace(
        v_new,
        '(''almacen'',\s+COALESCE\(alm\.denominacion, ''''\)\s*\r?\n)(\s*)\)(\r?\n\s*\))',
        '\1\2) || COALESCE(public.fn_presentacion_item_json(cp.id_presentacion, cp.cantidad), ''{}''::jsonb)\3',
        'g'
    );

    SELECT count(*) INTO v_ext
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(ep\.', 'g');
    SELECT count(*) INTO v_rec
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(rp\.', 'g');
    SELECT count(*) INTO v_ctrl
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(cp\.', 'g');

    IF v_ext <> 4 OR v_rec <> 2 OR v_ctrl <> 1 THEN
        RAISE EXCEPTION
            'ABORTA: conteo de parches inesperado (extraccion=% esperado 4, '
            'recepcion=% esperado 2, control=% esperado 1). La funcion en '
            'produccion cambio: revisar los patrones antes de aplicar.',
            v_ext, v_rec, v_ctrl;
    END IF;

    EXECUTE v_new;

    RAISE NOTICE 'Aplicado: % bloques de extraccion, % de recepcion, % de control.',
        v_ext, v_rec, v_ctrl;
END
$do$;


-- ============================================================================
-- VERIFICACION
-- ============================================================================
--
-- V1 · el merge quedo en los 7 bloques:
--
--   SELECT count(*) FROM regexp_matches(
--     pg_get_functiondef('public.fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer)'::regprocedure),
--     'fn_presentacion_item_json', 'g');
--   -- espera 7
--
-- V2 · una recepcion real (op 154048, tienda 224). La RPC es SECURITY DEFINER
--      y filtra por las tiendas del usuario, asi que hay que suplantar a un
--      gerente de esa tienda:
--
--   BEGIN;
--     SET LOCAL ROLE authenticated;
--     SELECT set_config('request.jwt.claims',
--            json_build_object('sub','bd095687-8477-44b0-ac24-2a1d4cf39347',
--                              'role','authenticated')::text, true);
--     SELECT i->>'producto_nombre', i->>'cantidad_formateada'
--       FROM public.fn_listar_operaciones_inventario_new(p_id_tienda := 224,
--                                                        p_limite := 40) r,
--            jsonb_array_elements(r.detalles->'items') i
--      WHERE r.id = 154048;
--   ROLLBACK;
--   -- resultado real del ensayo:
--   --   Harina de trigo  | 2000 Unidades
--   --   Sal              | 500 Unidades
--   --   Azucar refini    | 300 Unidades
--
-- V3 · una venta real (op 154050, tienda 196): 3 items, todos "1 Unidad"
--      (singular correcto, no "1 Unidades").
--
-- V4 · el caso que importa — factor <> 1 en una fila es_base (la anomalia
--      documentada: 131 filas base con cantidad 12/24/30). Venta 153946,
--      tienda 45, producto 4380 con presentacion 4445 "Unidad" factor 30:
--
--   -- devuelve cantidad_formateada "2 Unidades" y presentacion_factor "30.0"
--   -- La UI ahora PUEDE detectar la anomalia (factor 30 en algo llamado
--   -- "Unidad") porque recibe el factor; antes no tenia con que.
--
-- V5 · compatibilidad: ninguna clave previa cambio.
--
--   -- En el ensayo, los items siguen trayendo id_producto, producto_nombre,
--   -- sku_producto, cantidad, precio_unitario e importe con los mismos tipos.
-- ============================================================================
