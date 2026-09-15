-- ============================================================================
-- 43 · Catalogo TPV con stock mixto por presentacion (v3)
-- ============================================================================
-- PROPOSITO
-- ---------
-- El catalogo del vendedor sumaba `SUM(ip.cantidad_final)` SIN ponderar por
-- presentacion: con Cajon x30 (13) + Caja x24 (48) + Blister x6 (73) +
-- Unidad x1 (19) el vendedor leia "153", que no es ni la cantidad fisica de
-- nada ni un equivalente. Verificado en produccion, producto 11007 "cerveza
-- cristal" (tienda 223, almacen 331): 13+48+73+19 = 153 fisico, 1999 base.
--
-- La v3 NO cambia el contrato: mismas 18 columnas, mismo orden, mismo tipo.
-- Lo unico que hace es enriquecer las claves del `metadata` jsonb con el
-- desglose fisico y su equivalente en base, reutilizando los helpers vivos
-- (`fn_stock_saldos_presentacion`, `fn_formatear_stock_mixto`,
-- `fn_plural_presentacion`) que ya replican las apps en Dart.
--
-- POR QUE ADITIVA Y NO `CREATE OR REPLACE` DE LA VIVA
-- ---------------------------------------------------
-- `get_productos_by_categoria_tpv_search_meta` la consume la app en produccion
-- (ventiq_app/lib/services/product_service.dart:48 y :208, dos rutas: catalogo
-- y buscador) y `ventiq_admin_app` consume `get_productos_by_categoria_tpv`.
-- Por eso se crean v3 y v2 como funciones NUEVAS y las vivas quedan intactas.
-- Es el patron `_vX` ya adoptado en el 29 y el 30. Migrar el Dart es un cambio
-- aparte y reversible.
--
-- BUG COLATERAL CORREGIDO EN LAS NUEVAS
-- -------------------------------------
-- `get_productos_by_categoria_tpv` une `app_dat_precio_venta` con un LEFT JOIN
-- sin desempatar: con varias filas de precio activas (2.198 productos tienen
-- mas de una, 1.040 con precios distintos, hasta 24 filas) devuelve EL MISMO
-- PRODUCTO N veces. La subconsulta de stock no lo nota (mismo valor), pero la
-- lista sale duplicada. Las nuevas usan `LEFT JOIN LATERAL ... LIMIT 1`.
-- La search_meta ya lo tenia resuelto con LATERAL.
--
-- DECISION DE CONTRATO (importante)
-- ---------------------------------
-- `stock_disponible` y `tiene_stock` NO cambian de valor. Se evaluo poner el
-- equivalente base en `stock_disponible`, pero eso romperia la semantica del
-- nombre (no es un "disponible vendible"), moveria el precio a otra unidad y
-- haria que dos fallbacks encadenados en Dart (`invSum > 0 ? invSum :
-- cachedCantidad`) devolvieran cosas de dos unidades distintas. Los numeros
-- nuevos viajan SOLO en el metadata; el Dart migra aparte.
--
-- TODO el SQL es idempotente (`create or replace`). No toca datos, no toca
-- ninguna funcion viva, no agrega indices ni triggers.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 43.1 fn_catalogo_stock_meta
-- Payload de stock de UN producto en UN almacen, ya en formato de UI.
--
-- Una llamada por producto. La `LEFT JOIN LATERAL` del catalogo la invoca solo
-- cuando la fila tiene stock (`cantidad_final > 0`), asi que en la practica no
-- agrega costo: son decenas de productos por categoria en el peor caso.
--
-- Devuelve SIEMPRE un jsonb (nunca NULL) con:
--   stock_desglose          array ordenado de mayor a menor empaque
--   stock_texto             "13 Cajones + 48 Cajas + 73 Blisteres + 19 Unidades"
--   stock_texto_corto       con sku_codigo del nomenclador ("13 CAJ + ...")
--   stock_equivalente_base  suma de saldo x factor_rel (para dinero y rotacion)
--   stock_total_fisico      suma de saldos crudos: el numero enganoso de hoy
--   stock_filas             filas con saldo (una por variante/opcion/presentacion)
--   stock_n_presentaciones  presentaciones distintas con saldo
--   stock_mixto             true cuando hay mas de una presentacion con saldo
--   stock_con_variantes     true cuando hay saldo en filas con id_variante
--
-- OJO con el nombre: `stock_mixto` es "hay empaques distintos con saldo". Un
-- producto con una sola presentacion no-base (Caja x24, saldo 48) NO es mixto:
-- su numero fisico (48) es legible tal cual y `stock_total_fisico` =
-- `stock_disponible` de hoy, o sea cero regresion visual.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_catalogo_stock_meta(
    p_id_producto bigint,
    p_id_almacen  bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_vacio   jsonb;
    v_filas   integer := 0;
    v_n_pres  integer := 0;
    v_con_var boolean := false;
    v_fisico  numeric := 0;
    v_equiv   numeric := 0;
    v_desglose jsonb;
BEGIN
    -- check_user_has_access_to_tienda y los helpers resuelven tablas SIN
    -- calificar. Con el `SET search_path = ''` del proconfig fallarian con
    -- 42P01, asi que se restaura public, pg_catalog antes de llamarlos.
    -- El cambio dura hasta el fin de la transaccion de la llamada.
    PERFORM set_config('search_path', 'public, pg_catalog', false);

    v_vacio := jsonb_build_object(
        'stock_desglose',         '[]'::jsonb,
        'stock_texto',            NULL,
        'stock_texto_corto',      NULL,
        'stock_equivalente_base', NULL,
        'stock_total_fisico',     NULL,
        'stock_filas',            0,
        'stock_n_presentaciones', 0,
        'stock_mixto',            false,
        'stock_con_variantes',    false
    );

    -- Sin producto o sin almacen no hay nada que agregar. Devolver el payload
    -- vacio en vez de NULL para que el `->>` del catalogo no explote.
    IF p_id_producto IS NULL OR p_id_almacen IS NULL THEN
        RETURN v_vacio;
    END IF;

    SELECT count(*)::integer,
           count(DISTINCT s.id_presentacion)::integer,
           bool_or(s.id_variante IS NOT NULL),
           COALESCE(sum(s.saldo), 0),
           COALESCE(sum(s.equivalente_base), 0)
      INTO v_filas, v_n_pres, v_con_var, v_fisico, v_equiv
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, p_id_almacen, NULL, false
           ) AS s;

    IF v_filas = 0 THEN
        RETURN v_vacio;
    END IF;

    SELECT jsonb_agg(
               jsonb_build_object(
                   'id_presentacion',  s.id_presentacion,
                   'nombre',           s.presentacion_nombre,
                   'sku_codigo',       s.sku_codigo,
                   'cantidad',         s.saldo,
                   'factor_rel',       s.factor_rel,
                   'es_base',          s.es_base,
                   'nivel',            s.nivel,
                   'equivalente_base', s.equivalente_base
               )
               ORDER BY s.nivel NULLS LAST, s.id_presentacion
           )
      INTO v_desglose
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, p_id_almacen, NULL, false
           ) AS s;

    RETURN jsonb_build_object(
        'stock_desglose',         COALESCE(v_desglose, '[]'::jsonb),
        -- p_vacio NULL a proposito: cuando no hay filas el texto es null y la
        -- UI cae a su render de siempre, no a un "Sin stock" inventado aqui.
        'stock_texto',            public.fn_formatear_stock_mixto(v_desglose, false, NULL),
        'stock_texto_corto',      public.fn_formatear_stock_mixto(v_desglose, true,  NULL),
        'stock_equivalente_base', v_equiv,
        'stock_total_fisico',     v_fisico,
        'stock_filas',            v_filas,
        'stock_n_presentaciones', v_n_pres,
        'stock_mixto',            v_n_pres > 1,
        'stock_con_variantes',    v_con_var
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_catalogo_stock_meta(bigint, bigint) IS
    'Payload jsonb de stock de un producto en un almacen: desglose fisico por '
    'presentacion, textos mixtos y equivalente en unidades base. Una sola '
    'llamada por producto. Devuelve las claves en cero (nunca NULL) cuando no '
    'hay saldo, para que el catalogo no tenga que defenderse.';

REVOKE ALL ON FUNCTION public.fn_catalogo_stock_meta(bigint, bigint)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_catalogo_stock_meta(bigint, bigint)
    FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_catalogo_stock_meta(bigint, bigint)
    TO authenticated;


-- ----------------------------------------------------------------------------
-- 43.2 get_productos_by_categoria_tpv_search_meta_v3
--
-- MISMO contrato que la viva: 18 columnas, mismo orden, mismos tipos, y las
-- MISMAS 17 claves de metadata (`es_elaborado`, `es_servicio`, `es_paquete`,
-- `reservado_carnaval`) mas las `stock_*` del helper. Los dos modos de la viva
-- (producto de contacto por suscripcion vencida y catalogo normal) se replican
-- tal cual.
--
-- Orden de parametros igual al de la viva (id_categoria, id_tienda, id_tpv,
-- text_search, solo_disponibles) para que el cambio de nombre en Dart sea de
-- una linea.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_productos_by_categoria_tpv_search_meta_v3(
    id_categoria_param     bigint,
    id_tienda_param        bigint,
    id_tpv_param           bigint,
    text_search            text,
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
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    tiene_suscripcion_activa BOOLEAN := FALSE;
    primer_producto          RECORD;
    primera_subcategoria     RECORD;
    primera_categoria        RECORD;
    v_text_search            TEXT := NULLIF(trim(text_search), '');
    v_id_almacen             bigint;
BEGIN
    -- check_user_has_access_to_tienda resuelve tablas SIN calificar
    -- (app_dat_vendedor, app_dat_almacen, etc.). Con el `SET search_path = ''`
    -- del proconfig fallaba con 42P01 «relation "app_dat_vendedor" does not
    -- exist» — visto de verdad al ensayar este archivo, no es teorico. Hay que
    -- restaurar public, pg_catalog ANTES de la guarda. El cambio persiste hasta
    -- el fin de la transaccion de la llamada RPC. Mismo patron del archivo 32.
    PERFORM set_config('search_path', 'public, pg_catalog', false);

    -- Valida acceso a la tienda ANTES de cualquier lectura de datos.
    PERFORM public.check_user_has_access_to_tienda(id_tienda_param);

    SELECT EXISTS(
        SELECT 1
          FROM public.app_suscripciones
         WHERE id_tienda = id_tienda_param
           AND estado = 1
           AND (fecha_fin IS NULL OR fecha_fin > now())
         ORDER BY created_at DESC
         LIMIT 1
    ) INTO tiene_suscripcion_activa;

    -- ── Rama 1: sin suscripcion activa, producto de contacto ───────────────
    IF NOT tiene_suscripcion_activa THEN
        SELECT p.id, p.sku, p.um, p.es_refrigerado, p.es_fragil, p.es_vendible,
               p.codigo_barras, p.imagen, p.es_elaborado, p.es_servicio
          INTO primer_producto
          FROM public.app_dat_producto p
         WHERE p.id_tienda = id_tienda_param
         LIMIT 1;

        SELECT sc.id, sc.denominacion
          INTO primera_subcategoria
          FROM public.app_dat_subcategorias sc
         WHERE sc.idcategoria = id_categoria_param
         LIMIT 1;

        SELECT c.id, c.denominacion
          INTO primera_categoria
          FROM public.app_dat_categoria c
         WHERE c.id = id_categoria_param;

        IF primer_producto IS NULL THEN
            primer_producto.id            := 999999;
            primer_producto.sku           := 'CONTACT-ADMIN';
            primer_producto.um            := 'Unidad';
            primer_producto.es_refrigerado:= FALSE;
            primer_producto.es_fragil     := FALSE;
            primer_producto.es_vendible   := FALSE;
            primer_producto.codigo_barras := '';
            primer_producto.imagen        := '';
            primer_producto.es_elaborado  := FALSE;
            primer_producto.es_servicio   := TRUE;
        END IF;

        IF primera_subcategoria IS NULL THEN
            primera_subcategoria.id          := 999999;
            primera_subcategoria.denominacion:= 'Administracion';
        END IF;

        IF primera_categoria IS NULL THEN
            primera_categoria.id           := COALESCE(id_categoria_param, 999999);
            primera_categoria.denominacion := 'Administracion';
        END IF;

        RETURN QUERY
        SELECT primer_producto.id::bigint,
               COALESCE(primer_producto.sku, 'CONTACT-ADMIN')::text,
               'CONTACTAR VIA WHATSAPP AL 53765120 O supportinvenntia@gmail.com'::text,
               'escribir a soporteinventtia@gmail.com o via whatsapp al 53765120'::text,
               COALESCE(primer_producto.um, 'Unidad')::text,
               COALESCE(primer_producto.es_refrigerado, FALSE)::boolean,
               COALESCE(primer_producto.es_fragil, FALSE)::boolean,
               FALSE::boolean,
               COALESCE(primer_producto.codigo_barras, '')::text,
               primera_subcategoria.id::bigint,
               primera_subcategoria.denominacion::text,
               primera_categoria.id::bigint,
               primera_categoria.denominacion::text,
               0::numeric,
               COALESCE(primer_producto.imagen, '')::text,
               0::numeric,
               FALSE::boolean,
               jsonb_build_object(
                   'es_elaborado',       COALESCE(primer_producto.es_elaborado, FALSE),
                   'es_servicio',        COALESCE(primer_producto.es_servicio, TRUE),
                   'es_paquete',         FALSE,
                   'reservado_carnaval', 0
               );

        RETURN;
    END IF;

    -- ── Rama 2: catalogo normal ─────────────────────────────────────────────
    -- El almacen del TPV se resuelve UNA vez. Si el TPV no existe o es de otra
    -- tienda, la viva devolvia cero filas (el JOIN con app_dat_tpv no casa);
    -- aqui se devuelve vacio explicitamente, que es lo mismo.
    SELECT t.id_almacen
      INTO v_id_almacen
      FROM public.app_dat_tpv t
     WHERE t.id = id_tpv_param
       AND t.id_tienda = id_tienda_param;

    IF v_id_almacen IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT p.id::bigint,
           p.sku::text,
           p.denominacion::text,
           p.descripcion::text,
           p.um::text,
           p.es_refrigerado::boolean,
           p.es_fragil::boolean,
           p.es_vendible::boolean,
           p.codigo_barras::text,
           sc.id::bigint,
           sc.denominacion::text,
           c.id::bigint,
           c.denominacion::text,
           COALESCE(pv.precio_venta_cup, 0)::numeric,
           p.imagen::text,
           -- Los dos numeros de stock se calculan IGUAL que en la viva, con la
           -- misma clave completa y el mismo MAX(id). No se tocan a proposito:
           -- ver la nota "DECISION DE CONTRATO" del encabezado.
           COALESCE((
               SELECT sum(ip.cantidad_final)
                 FROM public.app_dat_inventario_productos ip
                 JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                WHERE ip.id_producto = p.id
                  AND la.id_almacen = v_id_almacen
                  AND ip.cantidad_final > 0
                  AND ip.id = (
                      SELECT max(ip2.id)
                        FROM public.app_dat_inventario_productos ip2
                       WHERE ip2.id_producto = ip.id_producto
                         AND COALESCE(ip2.id_variante, 0)         = COALESCE(ip.id_variante, 0)
                         AND COALESCE(ip2.id_opcion_variante, 0)  = COALESCE(ip.id_opcion_variante, 0)
                         AND COALESCE(ip2.id_presentacion, 0)     = COALESCE(ip.id_presentacion, 0)
                         AND COALESCE(ip2.id_ubicacion, 0)        = COALESCE(ip.id_ubicacion, 0)
                  )
           ), 0)::numeric,
           COALESCE((
               SELECT CASE WHEN sum(ip.cantidad_final) > 0 THEN true ELSE false END
                 FROM public.app_dat_inventario_productos ip
                 JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                WHERE ip.id_producto = p.id
                  AND la.id_almacen = v_id_almacen
                  AND ip.cantidad_final > 0
                  AND ip.id = (
                      SELECT max(ip2.id)
                        FROM public.app_dat_inventario_productos ip2
                       WHERE ip2.id_producto = ip.id_producto
                         AND COALESCE(ip2.id_variante, 0)         = COALESCE(ip.id_variante, 0)
                         AND COALESCE(ip2.id_opcion_variante, 0)  = COALESCE(ip.id_opcion_variante, 0)
                         AND COALESCE(ip2.id_presentacion, 0)     = COALESCE(ip.id_presentacion, 0)
                         AND COALESCE(ip2.id_ubicacion, 0)        = COALESCE(ip.id_ubicacion, 0)
                  )
           ), false)::boolean,
           -- Las 4 claves de la viva mas las del helper. `||` en jsonb AGREGA
           -- claves: si el helper devolviera una que ya existe, ganaria la
           -- derecha. Ninguna colisiona (las nuevas van con prefijo stock_).
           jsonb_build_object(
               'es_elaborado',       p.es_elaborado,
               'es_servicio',        p.es_servicio,
               'es_paquete',         p.es_paquete,
               'reservado_carnaval', COALESCE((
                   SELECT sum(cart.quantity)
                     FROM public.relation_products_carnaval rpc
                     JOIN carnavalapp."Carrito" cart ON cart.product_id = rpc.id_producto_carnaval
                    WHERE rpc.id_producto = p.id
               ), 0)
           ) || public.fn_catalogo_stock_meta(p.id, v_id_almacen)
      FROM public.app_dat_producto p
      JOIN public.app_dat_productos_subcategorias ps ON p.id = ps.id_producto
      JOIN public.app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
      JOIN public.app_dat_categoria c ON sc.idcategoria = c.id
      -- LEFT JOIN LATERAL + LIMIT 1: desempata el precio. La viva ya lo tenia
      -- asi; se conserva el ORDER BY fecha_desde DESC.
      LEFT JOIN LATERAL (
          SELECT pv_inner.precio_venta_cup
            FROM public.app_dat_precio_venta pv_inner
           WHERE pv_inner.id_producto = p.id
             AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
             AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
           ORDER BY pv_inner.fecha_desde DESC
           LIMIT 1
      ) pv ON TRUE
     WHERE p.id_tienda = id_tienda_param
       AND p.es_vendible = true
       AND c.visible_vendedor = true
       AND (id_categoria_param IS NULL OR c.id = id_categoria_param)
       AND (
             v_text_search IS NULL
             OR unaccent(p.denominacion) ILIKE unaccent('%' || v_text_search || '%')
             OR unaccent(p.descripcion)  ILIKE unaccent('%' || v_text_search || '%')
             OR unaccent(p.sku)          ILIKE unaccent('%' || v_text_search || '%')
           )
       AND EXISTS (
             SELECT 1
               FROM public.app_dat_inventario_productos ip
               JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
              WHERE ip.id_producto = p.id
                AND la.id_almacen = v_id_almacen
                AND (
                      NOT solo_disponibles_param
                      OR (
                          ip.cantidad_final > 0
                          AND ip.id = (
                              SELECT max(ip2.id)
                                FROM public.app_dat_inventario_productos ip2
                               WHERE ip2.id_producto = ip.id_producto
                                 AND COALESCE(ip2.id_variante, 0)        = COALESCE(ip.id_variante, 0)
                                 AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                                 AND COALESCE(ip2.id_presentacion, 0)    = COALESCE(ip.id_presentacion, 0)
                                 AND COALESCE(ip2.id_ubicacion, 0)       = COALESCE(ip.id_ubicacion, 0)
                          )
                      )
                )
           )
     ORDER BY p.denominacion;
END;
$function$;

COMMENT ON FUNCTION public.get_productos_by_categoria_tpv_search_meta_v3(bigint,bigint,bigint,text,boolean) IS
    'Catalogo del vendedor por categoria/TPV con las 18 columnas de la '
    'search_meta y el metadata ampliado con stock_desglose, stock_texto, '
    'stock_texto_corto, stock_equivalente_base, stock_total_fisico, '
    'stock_filas, stock_n_presentaciones, stock_mixto y stock_con_variantes. '
    'No cambia stock_disponible ni tiene_stock: eso se migra aparte en el Dart.';

REVOKE ALL ON FUNCTION public.get_productos_by_categoria_tpv_search_meta_v3(bigint,bigint,bigint,text,boolean)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_productos_by_categoria_tpv_search_meta_v3(bigint,bigint,bigint,text,boolean)
    FROM anon;
GRANT EXECUTE ON FUNCTION public.get_productos_by_categoria_tpv_search_meta_v3(bigint,bigint,bigint,text,boolean)
    TO authenticated;


-- ----------------------------------------------------------------------------
-- 43.3 get_productos_by_categoria_tpv_v2
--
-- La hermana SIN metadata de la v3 (casa matriz / gerencia:
-- `get_productos_by_categoria_tpv`, 17 columnas). Misma correccion de stock
-- mixto disponible no aplica -- no tiene metadata -- pero SI se arregla un bug
-- real: el `LEFT JOIN app_dat_precio_venta` sin desempatar devolvia el mismo
-- producto varias veces cuando tiene mas de un precio activo (hasta 24 filas).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_productos_by_categoria_tpv_v2(
    id_categoria_param     bigint DEFAULT NULL,
    id_tienda_param        bigint DEFAULT NULL,
    id_tpv_param           bigint DEFAULT NULL,
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
    tiene_stock        boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_id_almacen bigint;
BEGIN
    -- Misma razon que en la v3: la guarda resuelve tablas sin calificar y el
    -- `SET search_path = ''` del proconfig la haria fallar con 42P01.
    PERFORM set_config('search_path', 'public, pg_catalog', false);

    PERFORM public.check_user_has_access_to_tienda(id_tienda_param);

    SELECT t.id_almacen
      INTO v_id_almacen
      FROM public.app_dat_tpv t
     WHERE t.id = id_tpv_param
       AND t.id_tienda = id_tienda_param;

    IF v_id_almacen IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT p.id::bigint,
           p.sku::text,
           p.denominacion::text,
           p.descripcion::text,
           p.um::text,
           p.es_refrigerado::boolean,
           p.es_fragil::boolean,
           p.es_vendible::boolean,
           p.codigo_barras::text,
           sc.id::bigint,
           sc.denominacion::text,
           c.id::bigint,
           c.denominacion::text,
           COALESCE(pv.precio_venta_cup, 0)::numeric,
           p.imagen::text,
           COALESCE((
               SELECT sum(ip.cantidad_final)
                 FROM public.app_dat_inventario_productos ip
                 JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                WHERE ip.id_producto = p.id
                  AND la.id_almacen = v_id_almacen
                  AND ip.cantidad_final > 0
                  AND ip.id = (
                      SELECT max(ip2.id)
                        FROM public.app_dat_inventario_productos ip2
                       WHERE ip2.id_producto = ip.id_producto
                         AND COALESCE(ip2.id_variante, 0)        = COALESCE(ip.id_variante, 0)
                         AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                         AND COALESCE(ip2.id_presentacion, 0)    = COALESCE(ip.id_presentacion, 0)
                         AND COALESCE(ip2.id_ubicacion, 0)       = COALESCE(ip.id_ubicacion, 0)
                  )
           ), 0)::numeric,
           COALESCE((
               SELECT CASE WHEN sum(ip.cantidad_final) > 0 THEN true ELSE false END
                 FROM public.app_dat_inventario_productos ip
                 JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
                WHERE ip.id_producto = p.id
                  AND la.id_almacen = v_id_almacen
                  AND ip.cantidad_final > 0
                  AND ip.id = (
                      SELECT max(ip2.id)
                        FROM public.app_dat_inventario_productos ip2
                       WHERE ip2.id_producto = ip.id_producto
                         AND COALESCE(ip2.id_variante, 0)        = COALESCE(ip.id_variante, 0)
                         AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                         AND COALESCE(ip2.id_presentacion, 0)    = COALESCE(ip.id_presentacion, 0)
                         AND COALESCE(ip2.id_ubicacion, 0)       = COALESCE(ip.id_ubicacion, 0)
                  )
           ), false)::boolean
      FROM public.app_dat_producto p
      JOIN public.app_dat_productos_subcategorias ps ON p.id = ps.id_producto
      JOIN public.app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
      JOIN public.app_dat_categoria c ON sc.idcategoria = c.id
      -- El fix: LATERAL + LIMIT 1 en vez del LEFT JOIN que multiplicaba filas.
      LEFT JOIN LATERAL (
          SELECT pv_inner.precio_venta_cup
            FROM public.app_dat_precio_venta pv_inner
           WHERE pv_inner.id_producto = p.id
             AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
             AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
           ORDER BY pv_inner.fecha_desde DESC, pv_inner.id DESC
           LIMIT 1
      ) pv ON TRUE
     WHERE p.id_tienda = id_tienda_param
       AND p.es_vendible = true
       AND NOT EXISTS (
           SELECT 1
             FROM public.app_dat_producto_ingredientes pri
            WHERE pri.id_ingrediente = p.id
       )
       AND (id_categoria_param IS NULL OR c.id = id_categoria_param)
       AND EXISTS (
             SELECT 1
               FROM public.app_dat_inventario_productos ip
               JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
              WHERE ip.id_producto = p.id
                AND la.id_almacen = v_id_almacen
                AND (NOT solo_disponibles_param OR ip.cantidad_final > 0)
           )
     ORDER BY p.denominacion;
END;
$function$;

COMMENT ON FUNCTION public.get_productos_by_categoria_tpv_v2(bigint,bigint,bigint,boolean) IS
    'Catalogo por categoria/TPV sin metadata (casa matriz). Igual a '
    'get_productos_by_categoria_tpv pero desempata el precio con LATERAL: la '
    'viva devolvia el producto N veces si tenia varias filas de precio activo.';

REVOKE ALL ON FUNCTION public.get_productos_by_categoria_tpv_v2(bigint,bigint,bigint,boolean)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_productos_by_categoria_tpv_v2(bigint,bigint,bigint,boolean)
    FROM anon;
GRANT EXECUTE ON FUNCTION public.get_productos_by_categoria_tpv_v2(bigint,bigint,bigint,boolean)
    TO authenticated;


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica nada)
-- ============================================================================

-- V1 · Las funciones nuevas existen y las vivas siguen intactas.
--      Esperado: 3 nuevas + 2 vivas, y las vivas con su largo de siempre
--      (search_meta 10.058 / tpv 5.110).
SELECT p.proname,
       p.oid::regprocedure AS firma,
       length(p.prosrc)    AS largo,
       p.prosecdef        AS security_definer
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_catalogo_stock_meta',
        'get_productos_by_categoria_tpv_search_meta',
        'get_productos_by_categoria_tpv_search_meta_v3',
        'get_productos_by_categoria_tpv',
        'get_productos_by_categoria_tpv_v2'
   )
 ORDER BY p.proname;

-- V2 · La viva NO se toco: su metadata sigue con 4 claves.
--      Esperado: metadata_claves = 4.
SELECT jsonb_object_keys_count.*
  FROM (
    SELECT count(*) AS metadata_claves
      FROM (
        SELECT jsonb_object_keys(metadata) AS k
          FROM public.get_productos_by_categoria_tpv_search_meta(104, 223, 224, NULL, false)
      ) t
  ) AS jsonb_object_keys_count;

-- V3 · El caso real: producto 11007 "cerveza cristal" en el almacen 331.
--      Esperado: fisico 153, equivalente 1999, mixto true,
--                texto "13 Cajones + 48 Cajas + 73 Blisteres + 19 Unidades".
SELECT m->>'stock_texto'            AS texto,
       (m->>'stock_total_fisico')::numeric     AS fisico_153,
       (m->>'stock_equivalente_base')::numeric AS equiv_1999,
       (m->>'stock_mixto')::boolean            AS mixto,
       (m->>'stock_n_presentaciones')::int     AS n_pres
  FROM public.fn_catalogo_stock_meta(11007, 331) AS m;

-- V4 · Producto de UNA sola presentacion: el fisico tiene que ser identico al
--      `stock_disponible` de la viva y `stock_mixto` false. Cero regresion.
--      Esperado: fisico = stock_disponible en cada fila, mixto = false.
SELECT v.denominacion,
       v.stock_disponible,
       (v.metadata->>'stock_total_fisico')::numeric AS fisico_nuevo,
       (v.metadata->>'stock_mixto')::boolean        AS mixto,
       v.metadata->>'stock_texto'                   AS texto
  FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL, 223, 224, NULL, false) v
  JOIN app_dat_producto p ON p.id = v.id_producto
 WHERE (v.metadata->>'stock_mixto')::boolean = false
 LIMIT 10;

-- V5 · No-regresion de columnas: la v3 tiene las MISMAS 18 claves de metadata
--      base que la viva mas las 9 nuevas.
--      Esperado: claves_v3 = 13, claves_viva = 4, y las 4 comunes iguales.
SELECT
  (SELECT count(*) FROM (
     SELECT jsonb_object_keys(metadata) FROM public.get_productos_by_categoria_tpv_search_meta_v3(NULL,223,224,NULL,false)
  ) t) AS claves_v3,
  (SELECT count(*) FROM (
     SELECT jsonb_object_keys(metadata) FROM public.get_productos_by_categoria_tpv_search_meta(NULL,223,224,NULL,false)
  ) t) AS claves_viva;

-- V6 · ACL: SOLO authenticated (ni PUBLIC ni anon). Se lee con
--      `aclexplode` sobre `proacl` y NO con `information_schema.routine_privileges`,
--      que con rol postgres devuelve una fila por cada concesion implicita y da
--      un falso "esta todo concedido".
--      Esperado: exactamente una fila por funcion, grantee = authenticated.
SELECT p.proname, g.grantee::regrole::text AS grantee, g.privilege_type
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) AS g
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_catalogo_stock_meta',
                     'get_productos_by_categoria_tpv_search_meta_v3',
                     'get_productos_by_categoria_tpv_v2')
 ORDER BY p.proname, grantee;

-- V6b · La viva conserva SU acl (no se toco).
SELECT p.proname, g.grantee::regrole::text AS grantee, g.privilege_type
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) AS g
 WHERE n.nspname = 'public'
   AND p.proname IN ('get_productos_by_categoria_tpv_search_meta',
                     'get_productos_by_categoria_tpv')
 ORDER BY p.proname, grantee;

-- V7 · search_path fijo en las 3 (anti search_path hijacking).
--      Esperado: proconfig = {search_path=}.
SELECT p.proname, p.proconfig
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_catalogo_stock_meta',
                     'get_productos_by_categoria_tpv_search_meta_v3',
                     'get_productos_by_categoria_tpv_v2')
 ORDER BY p.proname;