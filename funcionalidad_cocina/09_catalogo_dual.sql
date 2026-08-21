-- ============================================================================
-- 09 · Fase 1 · Catalogo dual: barra + cocinas ligadas
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE RESUELVE
-- ------------
-- Hoy get_productos_by_categoria_tpv_search_meta solo muestra productos que
-- tienen inventario en el almacen del TPV:
--
--     EXISTS (SELECT 1 FROM app_dat_inventario_productos ip
--             JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
--             WHERE ip.id_producto = p.id AND la.id_almacen = tpv.id_almacen)
--
-- Un plato que se cocina en la "Cocina caliente" NO tiene inventario en el
-- almacen de la barra, asi que el vendedor no lo ve. Ese es el bloqueo de la
-- Fase 1: hace falta que el catalogo una DOS origenes.
--
--   origen 1 (barra)   producto con stock propio en el almacen del TPV
--                      -> cerveza, refresco, lo listo para venta
--   origen 2 (cocina)  producto asignado a una cocina LIGADA a este TPV
--                      -> bistec (al_pedido), moro (por_tanda)
--
-- Regla del plan: "En la misma cuenta conviven listo para venta (cerveza),
-- tanda (moro) y al pedido (bistec)".
--
-- ESTRATEGIA: ADITIVA, NO DESTRUCTIVA
-- -----------------------------------
-- Este archivo NO reemplaza get_productos_by_categoria_tpv_search_meta.
-- Motivo: las copias .sql de la raiz del repo estan desincronizadas con
-- produccion (ya paso con pending_order_edit.sql en la Fase 0), y esa funcion
-- carga cosas que no se pueden perder: el producto de contacto por suscripcion
-- vencida, reservado_carnaval, unaccent en la busqueda.
--
-- En su lugar se crea fn_productos_cocina_tpv, que devuelve SOLO el origen 2
-- con la MISMA forma de columnas. Asi:
--
--   * nada de lo que hoy funciona se toca
--   * la app puede unir los dos origenes de inmediato
--   * el 10 podra hacer el UNION dentro de la funcion original cuando se
--     exporte su definicion real (consulta 9.1 de este archivo)
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr la consulta 9.1 y guardar el resultado (definicion real).
--   2. Aplicar la seccion 9.2 (la funcion nueva).
--   3. Correr la VERIFICACION del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 9.1 Exportar la definicion REAL del catalogo actual (NO MODIFICA NADA)
--
-- Antes de tocar esa funcion en el 10 hay que ver como esta en produccion.
-- La copia local tiene 243 lineas; si el largo del cuerpo no coincide, la copia
-- local esta vieja y no sirve como base.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    length(p.prosrc)          AS largo_cuerpo,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'get_productos_by_categoria_tpv_search_meta',
        'get_productos_by_categoria_tpv_meta'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 9.2 fn_productos_cocina_tpv
--
-- Devuelve los productos que este TPV puede vender POR VIA DE COCINA, con la
-- misma forma de columnas que get_productos_by_categoria_tpv_search_meta para
-- que la app pueda concatenar las dos listas sin transformar nada.
--
-- QUE INCLUYE
--   Productos con id_cocina apuntando a una cocina que:
--     - pertenece a esta tienda
--     - esta ligada a este TPV (app_dat_tpv_cocina)
--     - esta activa (una cocina con turno cerrado no recibe comandas)
--   y que son vendibles, en categoria visible al vendedor.
--
-- QUE NO INCLUYE
--   Los productos de barra: esos ya los devuelve la funcion original. Aqui se
--   excluyen explicitamente los que tienen stock en el almacen del TPV para que
--   al concatenar no salgan duplicados. Un producto con id_cocina Y stock en la
--   barra se considera de barra (se sirve de lo que hay al alcance del vendedor).
--
-- DISPONIBILIDAD (dos calculos distintos, esto es el corazon del asunto)
--   por_tanda  -> stock TERMINADO del propio SKU en el almacen de la cocina.
--                 Si se acabo el moro, agotado, aunque quede arroz.
--   al_pedido  -> min por ingrediente de floor(stock_en_cocina / necesaria).
--                 Es cuantos bistecs se pueden sacar con la MP de esa estacion.
--
-- El campo metadata lleva los datos de cocina para que la UI pueda pintar el
-- chip ("3 porciones", "Hasta 5", el nombre de la estacion) sin otra consulta.
--
-- Se delega en fn_stock_producto_almacen y fn_obtener_ingredientes_recursivos
-- (helpers del 01) para no repetir la logica de "stock vigente por ubicacion",
-- que es justo lo que estaba roto antes de la Fase 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_productos_cocina_tpv(
    id_categoria_param     bigint,
    id_tienda_param        bigint,
    id_tpv_param           bigint,
    text_search            text    DEFAULT NULL,
    solo_disponibles_param boolean DEFAULT false
)
RETURNS TABLE(
    id_producto        bigint,
    sku                text,
    denominacion       text,
    descripcion        text,
    um                 text,
    es_refrigerado     boolean,
    es_fragil          boolean,
    es_vendible        boolean,
    codigo_barras      text,
    id_subcategoria    bigint,
    subcategoria_nombre text,
    id_categoria       bigint,
    categoria_nombre   text,
    precio_venta       numeric,
    imagen             text,
    stock_disponible   numeric,
    tiene_stock        boolean,
    metadata           jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_almacen_tpv  bigint;
    v_text_search  text := NULLIF(trim(text_search), '');
BEGIN
    PERFORM check_user_has_access_to_tienda(id_tienda_param);

    SELECT t.id_almacen INTO v_almacen_tpv
      FROM app_dat_tpv t
     WHERE t.id = id_tpv_param
       AND t.id_tienda = id_tienda_param;

    -- TPV inexistente o de otra tienda: lista vacia, no error. La app
    -- concatena resultados y un error aqui tumbaria todo el catalogo.
    IF v_almacen_tpv IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH cocinas_ligadas AS (
        -- Las cocinas ACTIVAS que este TPV tiene ligadas.
        SELECT co.id AS id_cocina, co.denominacion, co.id_almacen, co.impresora
          FROM app_dat_tpv_cocina tc
          JOIN app_dat_cocina co ON co.id = tc.id_cocina
         WHERE tc.id_tpv = id_tpv_param
           AND co.id_tienda = id_tienda_param
           AND co.activa = true
           AND co.deleted_at IS NULL
    ),
    base AS (
        SELECT
            p.id,
            p.sku,
            p.denominacion,
            p.descripcion,
            p.um,
            p.es_refrigerado,
            p.es_fragil,
            p.es_vendible,
            p.codigo_barras,
            p.imagen,
            p.es_elaborado,
            p.es_servicio,
            p.es_paquete,
            COALESCE(p.modo_elaboracion, 'al_pedido') AS modo_elaboracion,
            sc.id            AS id_subcategoria,
            sc.denominacion  AS subcategoria_nombre,
            c.id             AS id_categoria,
            c.denominacion   AS categoria_nombre,
            COALESCE(pv.precio_venta_cup, 0) AS precio_venta,
            cl.id_cocina,
            cl.denominacion  AS cocina_nombre,
            cl.id_almacen    AS almacen_cocina,
            cl.impresora
          FROM app_dat_producto p
          JOIN cocinas_ligadas cl ON cl.id_cocina = p.id_cocina
          JOIN app_dat_productos_subcategorias ps ON ps.id_producto = p.id
          JOIN app_dat_subcategorias sc ON sc.id = ps.id_sub_categoria
          JOIN app_dat_categoria c ON c.id = sc.idcategoria
          LEFT JOIN LATERAL (
              SELECT pv_inner.precio_venta_cup
                FROM app_dat_precio_venta pv_inner
               WHERE pv_inner.id_producto = p.id
                 AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
                 AND (pv_inner.fecha_hasta IS NULL
                      OR pv_inner.fecha_hasta >= CURRENT_DATE)
               ORDER BY pv_inner.created_at DESC
               LIMIT 1
          ) pv ON TRUE
         WHERE p.id_tienda = id_tienda_param
           AND p.es_vendible = true
           AND p.deleted_at IS NULL
           AND c.visible_vendedor = true
           AND (id_categoria_param IS NULL OR c.id = id_categoria_param)
           AND (
                v_text_search IS NULL
                OR unaccent(p.denominacion) ILIKE unaccent('%' || v_text_search || '%')
                OR unaccent(p.descripcion)  ILIKE unaccent('%' || v_text_search || '%')
                OR unaccent(p.sku)          ILIKE unaccent('%' || v_text_search || '%')
           )
           -- Anti-duplicado: si el producto ya tiene stock en la barra, lo
           -- devuelve la funcion original. Aqui solo va lo que NO esta a mano.
           AND NOT EXISTS (
                SELECT 1
                  FROM app_dat_inventario_productos ip
                  JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                 WHERE ip.id_producto = p.id
                   AND la.id_almacen = v_almacen_tpv
                   AND la.deleted_at IS NULL
                   AND ip.cantidad_final > 0
           )
    ),
    con_disponibilidad AS (
        SELECT
            b.*,
            CASE
                -- Un servicio elaborado no consume MP: siempre disponible.
                WHEN b.es_servicio AND NOT b.es_elaborado THEN NULL

                -- por_tanda: porciones ya hechas en la cocina.
                WHEN b.modo_elaboracion = 'por_tanda' THEN
                    fn_stock_producto_almacen(b.id, b.almacen_cocina)

                -- al_pedido con receta: limite segun la MP de esa cocina.
                WHEN EXISTS (
                    SELECT 1 FROM app_dat_producto_ingredientes pi
                     WHERE pi.id_producto = b.id
                ) THEN (
                    SELECT COALESCE(MIN(
                               floor(
                                   fn_stock_producto_almacen(ing.id_ingrediente,
                                                             b.almacen_cocina)
                                   / NULLIF(ing.cantidad_total_necesaria, 0)
                               )
                           ), 0)
                      FROM fn_obtener_ingredientes_recursivos(b.id, 1) ing
                )

                -- Elaborado sin receta: no se puede producir.
                ELSE 0
            END AS disponible
          FROM base b
    )
    SELECT
        cd.id::bigint,
        cd.sku::text,
        cd.denominacion::text,
        cd.descripcion::text,
        cd.um::text,
        cd.es_refrigerado::boolean,
        cd.es_fragil::boolean,
        cd.es_vendible::boolean,
        cd.codigo_barras::text,
        cd.id_subcategoria::bigint,
        cd.subcategoria_nombre::text,
        cd.id_categoria::bigint,
        cd.categoria_nombre::text,
        cd.precio_venta::numeric,
        cd.imagen::text,
        COALESCE(cd.disponible, 0)::numeric AS stock_disponible,
        -- Un servicio (disponible NULL) siempre se puede vender.
        (cd.disponible IS NULL OR cd.disponible > 0)::boolean AS tiene_stock,
        jsonb_build_object(
            'es_elaborado',       cd.es_elaborado,
            'es_servicio',        cd.es_servicio,
            'es_paquete',         cd.es_paquete,
            'reservado_carnaval', 0,
            -- Datos de cocina: la UI pinta el chip sin otra consulta.
            'origen',             'cocina',
            'id_cocina',          cd.id_cocina,
            'cocina',             cd.cocina_nombre,
            'id_almacen_cocina',  cd.almacen_cocina,
            'impresora',          cd.impresora,
            'modo_elaboracion',   cd.modo_elaboracion,
            'ilimitado',          (cd.disponible IS NULL)
        ) AS metadata
      FROM con_disponibilidad cd
     WHERE NOT solo_disponibles_param
        OR cd.disponible IS NULL
        OR cd.disponible > 0
     ORDER BY cd.denominacion;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_productos_cocina_tpv(bigint, bigint, bigint, text, boolean)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) La funcion debe existir con la firma esperada -> 1 fila
SELECT p.oid::regprocedure AS firma,
       p.prosecdef         AS security_definer,
       p.proconfig         AS config
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_productos_cocina_tpv';

-- (b) Debe devolver EXACTAMENTE las mismas 18 columnas, en el mismo orden y
--     con los mismos tipos que el catalogo actual. Si esto no da 0 filas, la
--     app no puede concatenar las dos listas.
WITH cols AS (
    SELECT p.proname,
           u.ordinality AS pos,
           u.nombre,
           format_type(t.tipo, NULL) AS tipo
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL unnest(p.proargnames) WITH ORDINALITY AS u(nombre, ordinality)
      CROSS JOIN LATERAL unnest(p.proallargtypes) WITH ORDINALITY AS t(tipo, ord)
     WHERE n.nspname = 'public'
       AND u.ordinality = t.ord
       AND p.proargmodes[u.ordinality] IN ('o', 't')
       AND p.proname IN ('fn_productos_cocina_tpv',
                         'get_productos_by_categoria_tpv_search_meta')
)
SELECT COALESCE(a.pos, b.pos)      AS posicion,
       a.nombre AS col_cocina,   a.tipo AS tipo_cocina,
       b.nombre AS col_original, b.tipo AS tipo_original
  FROM (SELECT * FROM cols WHERE proname = 'fn_productos_cocina_tpv') a
  FULL OUTER JOIN
       (SELECT * FROM cols WHERE proname = 'get_productos_by_categoria_tpv_search_meta') b
    ON a.pos = b.pos
 WHERE a.nombre IS DISTINCT FROM b.nombre
    OR a.tipo   IS DISTINCT FROM b.tipo
 ORDER BY posicion;


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL (transaccion revertida: no deja rastro)
--
-- Datos reales verificados contra produccion:
--   tienda 11, TPV 18 -> almacen 12
--   elaborado 219 "croqueta" = 40 g harina (216) + 10 g sal (218)
--   harina (216) en almacen 12: 5.0   -> alcanza para 0 croquetas
--   sal    (218) en almacen 12: 27.5  -> alcanza para 2 croquetas
--   por tanto al_pedido en un almacen con esa MP da 0 (manda la harina)
--
-- Ejecutar TODO el bloque de una vez.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    -- 1. Cocina de prueba + ligarla al TPV 18
    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina 09') AS cocina;

    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 09')
    ) AS ligar;

    -- 2. Mandar la croqueta a esa cocina, modo al_pedido
    UPDATE app_dat_producto
       SET id_cocina = (SELECT id FROM app_dat_cocina
                         WHERE denominacion = 'PRUEBA Cocina 09'),
           modo_elaboracion = 'al_pedido'
     WHERE id = 219;

    -- 3. La croqueta debe APARECER ahora en el catalogo de cocina.
    --    Antes de la Fase 1 era invisible: no tiene stock en el almacen 12.
    SELECT id_producto, denominacion, stock_disponible, tiene_stock,
           metadata->>'origen'           AS origen,
           metadata->>'cocina'           AS cocina,
           metadata->>'modo_elaboracion' AS modo
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: 1 fila, origen 'cocina', modo 'al_pedido',
    --           stock_disponible 0 (la cocina nueva no tiene MP), tiene_stock false

    -- 4. Cargar MP en la cocina: 500 g de harina y 200 g de sal.
    --    Con eso deberian salir 12 croquetas (500/40 = 12, 200/10 = 20 -> min 12).
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 216,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 09' LIMIT 1),
           500, 500, now();

    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 218,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 09' LIMIT 1),
           200, 200, now();

    SELECT id_producto, denominacion, stock_disponible, tiene_stock
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: stock_disponible 12, tiene_stock true
    -- (limita la harina: floor(500/40) = 12, frente a floor(200/10) = 20)

    -- 5. Cambiar a por_tanda: ahora NO mira la receta, mira stock terminado.
    --    No hay croquetas hechas -> 0, aunque haya MP de sobra.
    UPDATE app_dat_producto SET modo_elaboracion = 'por_tanda' WHERE id = 219;

    SELECT denominacion, stock_disponible, tiene_stock,
           metadata->>'modo_elaboracion' AS modo
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: modo 'por_tanda', stock_disponible 0, tiene_stock false
    -- ESTE es el criterio del plan: "si se acabo, agotado aunque quede MP"

    -- 6. Meter 7 croquetas hechas en la cocina -> deben aparecer 7.
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 219,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 09' LIMIT 1),
           7, 7, now();

    SELECT denominacion, stock_disponible, tiene_stock
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: stock_disponible 7, tiene_stock true

    -- 7. solo_disponibles: con 7 porciones sigue apareciendo
    SELECT count(*) AS con_filtro_disponibles
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18, NULL, true);
    -- esperado: 1

    -- 8. ENRUTAMIENTO: desligar el TPV -> el plato desaparece del catalogo.
    --    Criterio del plan: "bistec va a Cocina caliente; no aparece en Pizzeria"
    SELECT public.fn_desasignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 09')
    ) AS desligar;

    SELECT count(*) AS tras_desligar
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: 0

    -- 9. Volver a ligar y DESACTIVAR la cocina -> tampoco aparece.
    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 09')
    );
    UPDATE app_dat_cocina SET activa = false
     WHERE denominacion = 'PRUEBA Cocina 09';

    SELECT count(*) AS cocina_inactiva
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: 0 (turno cerrado no recibe comandas)

    -- 10. Busqueda por texto (con y sin acentos) y filtro por categoria
    UPDATE app_dat_cocina SET activa = true
     WHERE denominacion = 'PRUEBA Cocina 09';

    SELECT count(*) AS busqueda_ok
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18, 'croq');
    -- esperado: 1

    SELECT count(*) AS busqueda_sin_match
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18, 'zzzz');
    -- esperado: 0

    -- 11. ANTI-DUPLICADO: si el plato tambien tiene stock en la barra
    --     (almacen 12 del TPV), debe salir del catalogo de cocina para no
    --     aparecer dos veces al concatenar con la funcion original.
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    VALUES (219, 37, 3, 3, now());   -- ubicacion 37 pertenece al almacen 12

    SELECT count(*) AS con_stock_en_barra
      FROM public.fn_productos_cocina_tpv(NULL, 11, 18);
    -- esperado: 0 (lo devuelve la funcion original, no esta)

    -- 12. TPV de otra tienda / inexistente -> lista vacia, sin error
    SELECT count(*) AS tpv_inexistente
      FROM public.fn_productos_cocina_tpv(NULL, 11, 999999);
    -- esperado: 0

ROLLBACK;
*/

-- Comprobar que el ROLLBACK dejo todo limpio -> 0 filas las dos
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT id, id_cocina FROM app_dat_producto WHERE id = 219 AND id_cocina IS NOT NULL;
