-- ============================================================================
-- 10 · Fase 1 · Enrutamiento de venta: descontar de la COCINA, no de la barra
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE RESUELVE
-- ------------
-- El 09 ya hace que el vendedor VEA los platos de sus cocinas. Pero al venderlos
-- el descuento sigue saliendo del almacen del TPV:
--
--     fn_descontar_ingredientes_elaborado(..., p_id_almacen := v_id_almacen)
--                                                              ^^^^^^^^^^^^
--                                              almacen del TPV (la barra)
--
-- Eso es incorrecto para un plato de cocina:
--
--   * al_pedido  la materia prima esta en la COCINA, no en la barra. Descontando
--                del almacen del TPV se falla con "stock insuficiente" aunque la
--                cocina este llena, o peor: se descuenta de la barra MP que
--                fisicamente esta en la cocina.
--
--   * por_tanda  no se debe tocar la receta en absoluto. Lo que se vende es una
--                PORCION YA HECHA: hay que descontar el propio SKU del almacen
--                de la cocina. Descontando ingredientes se estaria cobrando dos
--                veces la MP (una al producir la tanda, otra al vender).
--
-- Y falta la validacion de enrutamiento: un TPV no debe poder vender un plato
-- de una cocina a la que no esta ligado.
--
-- ESTRATEGIA: HELPERS PRIMERO, VENTA DESPUES
-- ------------------------------------------
-- Este archivo NO toca fn_registrar_venta ni fn_registrar_venta_mesa. Crea los
-- helpers que resuelven el enrutamiento, con sus propias pruebas. El 11 los
-- enchufa en las funciones de venta, usando el 03 como base (esa copia SI esta
-- sincronizada: la aplicamos nosotros en la Fase 0).
--
-- Motivo del corte: las funciones de venta son las mas delicadas del sistema.
-- Conviene tener el enrutamiento probado de forma aislada antes de meterlo ahi.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr 10.1 para confirmar que el 03 sigue intacto en produccion.
--   2. Aplicar 10.2 y 10.3.
--   3. Correr la VERIFICACION y la prueba funcional del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 10.1 Confirmar que las funciones de venta siguen como las dejo el 03
--      (NO MODIFICA NADA)
--
-- Si alguien las reemplazo despues, el 11 no puede usar el 03 como base y hay
-- que exportarlas de nuevo. Esperado: ambas delegan en el helper y ninguna
-- conserva el patron roto.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo,
    (p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%') AS delega_en_helper,
    (p.prosrc ILIKE '%v_inventario_ingrediente%')            AS conserva_patron_roto,
    (p.prosrc ILIKE '%id_cocina%')                           AS ya_sabe_de_cocinas
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 10.2 fn_resolver_origen_venta
--
-- Decide DE DONDE sale un producto al venderse desde un TPV, y valida que el
-- TPV tenga derecho a venderlo. Es la pieza que el 11 llamara una vez por
-- linea de venta, antes de tocar inventario.
--
-- Devuelve jsonb con:
--   origen       'barra' | 'cocina_al_pedido' | 'cocina_por_tanda' | 'servicio'
--   id_almacen   almacen del que hay que descontar
--   descontar    'sku'         -> descontar el propio producto (barra o tanda)
--                'ingredientes'-> descontar la receta (al_pedido)
--                'nada'        -> servicio sin receta
--   id_cocina    cocina destino, si aplica (para la comanda de Fase 2)
--
-- Las cuatro rutas:
--
--   1. servicio sin receta        -> nada que descontar
--   2. sin id_cocina              -> barra. Igual que hoy: almacen del TPV.
--                                    Si es elaborado, descuenta receta de ahi.
--   3. id_cocina + por_tanda      -> descontar el SKU del almacen de la COCINA.
--                                    La MP ya se consumio al producir la tanda.
--   4. id_cocina + al_pedido      -> descontar la RECETA del almacen de la COCINA.
--
-- Excepcion importante: si el producto tiene id_cocina pero TAMBIEN tiene stock
-- propio en el almacen del TPV, se trata como barra. Es el mismo criterio que
-- usa el 09 para no duplicar en el catalogo: si esta al alcance del vendedor,
-- se sirve de ahi. Asi la venta descuenta de donde el vendedor lo vio.
--
-- Errores de enrutamiento (status 'error'):
--   COCINA_NO_LIGADA    el TPV no esta ligado a la cocina del plato
--   COCINA_INACTIVA     la cocina existe pero tiene el turno cerrado
--   COCINA_NOT_FOUND    el plato apunta a una cocina borrada
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_resolver_origen_venta(
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
    v_tienda_tpv     bigint;
    v_almacen_tpv    bigint;
    v_prod           RECORD;
    v_almacen_cocina bigint;
    v_cocina_nombre  text;
    v_cocina_activa  boolean;
    v_cocina_tienda  bigint;
    v_ligada         boolean;
    v_tiene_receta   boolean;
    v_stock_barra    numeric;
BEGIN
    SELECT t.id_tienda, t.id_almacen
      INTO v_tienda_tpv, v_almacen_tpv
      FROM app_dat_tpv t
     WHERE t.id = p_id_tpv;

    IF v_tienda_tpv IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    SELECT p.id, p.id_tienda, p.denominacion,
           p.es_elaborado, p.es_servicio,
           COALESCE(p.modo_elaboracion, 'al_pedido') AS modo_elaboracion,
           p.id_cocina
      INTO v_prod
      FROM app_dat_producto p
     WHERE p.id = p_id_producto AND p.deleted_at IS NULL;

    IF v_prod.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND'
        );
    END IF;

    IF v_prod.id_tienda <> v_tienda_tpv THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no pertenece a la tienda del TPV',
            'error_code', 'TIENDA_MISMATCH'
        );
    END IF;

    -- ── RUTA 1 · servicio sin receta ──────────────────────────────────────
    IF v_prod.es_servicio AND NOT v_prod.es_elaborado THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'origen',      'servicio',
            'id_almacen',  v_almacen_tpv,
            'descontar',   'nada',
            'id_cocina',   NULL,
            'id_producto', p_id_producto
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM app_dat_producto_ingredientes pi
         WHERE pi.id_producto = p_id_producto
    ) INTO v_tiene_receta;

    -- ── RUTA 2 · sin cocina: barra (comportamiento previo intacto) ────────
    IF v_prod.id_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'origen',      'barra',
            'id_almacen',  v_almacen_tpv,
            'descontar',   CASE WHEN v_prod.es_elaborado AND v_tiene_receta
                                THEN 'ingredientes' ELSE 'sku' END,
            'id_cocina',   NULL,
            'id_producto', p_id_producto
        );
    END IF;

    -- ── El producto apunta a una cocina: validar antes de enrutar ────────
    SELECT c.id_almacen, c.denominacion, c.activa, c.id_tienda
      INTO v_almacen_cocina, v_cocina_nombre, v_cocina_activa, v_cocina_tienda
      FROM app_dat_cocina c
     WHERE c.id = v_prod.id_cocina AND c.deleted_at IS NULL;

    IF v_almacen_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El plato apunta a una cocina que no existe o fue eliminada',
            'error_code', 'COCINA_NOT_FOUND',
            'id_cocina',  v_prod.id_cocina,
            'producto',   v_prod.denominacion
        );
    END IF;

    IF v_cocina_tienda <> v_tienda_tpv THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cocina del plato es de otra tienda',
            'error_code', 'TIENDA_MISMATCH',
            'id_cocina',  v_prod.id_cocina
        );
    END IF;

    -- Excepcion: si hay stock propio en la barra, se sirve de ahi. Mismo
    -- criterio que el catalogo del 09, para que venta y catalogo coincidan.
    v_stock_barra := fn_stock_producto_almacen(p_id_producto, v_almacen_tpv);

    IF COALESCE(v_stock_barra, 0) > 0 THEN
        RETURN jsonb_build_object(
            'status',       'success',
            'origen',       'barra',
            'id_almacen',   v_almacen_tpv,
            'descontar',    'sku',
            'id_cocina',    NULL,
            'id_producto',  p_id_producto,
            'nota',         'Tiene stock en la barra: se sirve de ahi',
            'stock_barra',  v_stock_barra
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM app_dat_tpv_cocina tc
         WHERE tc.id_tpv = p_id_tpv AND tc.id_cocina = v_prod.id_cocina
    ) INTO v_ligada;

    IF NOT v_ligada THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'Este punto de venta no puede enviar pedidos a la cocina "'
                          || v_cocina_nombre || '"',
            'error_code', 'COCINA_NO_LIGADA',
            'id_cocina',  v_prod.id_cocina,
            'cocina',     v_cocina_nombre,
            'producto',   v_prod.denominacion
        );
    END IF;

    IF NOT v_cocina_activa THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'La cocina "' || v_cocina_nombre || '" no esta recibiendo pedidos',
            'error_code', 'COCINA_INACTIVA',
            'id_cocina',  v_prod.id_cocina,
            'cocina',     v_cocina_nombre,
            'producto',   v_prod.denominacion
        );
    END IF;

    -- ── RUTA 3 · por_tanda: se vende la porcion hecha ─────────────────────
    IF v_prod.modo_elaboracion = 'por_tanda' THEN
        RETURN jsonb_build_object(
            'status',      'success',
            'origen',      'cocina_por_tanda',
            'id_almacen',  v_almacen_cocina,
            'descontar',   'sku',
            'id_cocina',   v_prod.id_cocina,
            'cocina',      v_cocina_nombre,
            'id_producto', p_id_producto
        );
    END IF;

    -- ── RUTA 4 · al_pedido: se consume la receta en la cocina ─────────────
    -- Un elaborado sin receta no se puede producir. Se corta aqui en vez de
    -- dejar que el helper descuente cero y la venta pase en falso.
    IF v_prod.es_elaborado AND NOT v_tiene_receta THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El plato "' || v_prod.denominacion
                          || '" no tiene receta definida y no se puede preparar',
            'error_code', 'SIN_RECETA',
            'id_cocina',  v_prod.id_cocina,
            'producto',   v_prod.denominacion
        );
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'origen',      'cocina_al_pedido',
        'id_almacen',  v_almacen_cocina,
        'descontar',   CASE WHEN v_tiene_receta THEN 'ingredientes' ELSE 'sku' END,
        'id_cocina',   v_prod.id_cocina,
        'cocina',      v_cocina_nombre,
        'id_producto', p_id_producto
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_resolver_origen_venta(bigint, bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 10.3 fn_descontar_venta_enrutada
--
-- Descuenta una linea de venta del almacen CORRECTO, resolviendo el
-- enrutamiento por dentro. Es la unica llamada que el 11 necesita hacer:
-- reemplaza el bloque actual
--
--     IF v_es_elaborado THEN
--       fn_descontar_ingredientes_elaborado(..., p_id_almacen := v_id_almacen)
--     END IF
--
-- por una sola llamada que ademas cubre el caso por_tanda y la validacion de
-- enrutamiento.
--
-- Segun lo que resuelva fn_resolver_origen_venta:
--   descontar = 'nada'          no toca inventario (servicio)
--   descontar = 'ingredientes'  delega en fn_descontar_ingredientes_elaborado
--                               con el almacen que corresponda (barra o cocina)
--   descontar = 'sku'           descuenta el propio producto de ese almacen,
--                               repartiendo entre ubicaciones como hace el
--                               helper del 01 (FIFO por cantidad descendente)
--
-- IMPORTANTE sobre el caso 'sku' en BARRA
-- ---------------------------------------
-- Para un producto de barra normal, las funciones de venta YA insertan su
-- movimiento de inventario (el bloque INSERT ... origen_cambio 3). Por eso este
-- helper acepta p_ya_descontado_sku: cuando el 11 lo llame para una linea de
-- barra le pasara true y aqui solo se validara/enrutara sin volver a descontar.
-- Asi no se descuenta dos veces lo mismo.
--
-- El descuento de 'sku' propio SI se aplica cuando el origen es la cocina
-- (por_tanda), porque ahi la venta no inserto nada: el SKU vive en el almacen
-- de la cocina, no en el del TPV.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_venta_enrutada(
    p_id_producto        bigint,
    p_cantidad           numeric,
    p_id_tpv             bigint,
    p_id_extraccion      bigint  DEFAULT NULL,
    p_origen_cambio      integer DEFAULT 4,
    p_ya_descontado_sku  boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_ruta        jsonb;
    v_origen      text;
    v_descontar   text;
    v_id_almacen  bigint;
    v_resultado   jsonb;
    v_ubic        RECORD;
    v_pendiente   numeric;
    v_a_descontar numeric;
    v_movimientos jsonb := '[]'::jsonb;
    v_disponible  numeric;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- 1. Resolver de donde sale y validar el enrutamiento.
    v_ruta := fn_resolver_origen_venta(p_id_producto, p_id_tpv);

    IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
    END IF;

    v_origen     := v_ruta->>'origen';
    v_descontar  := v_ruta->>'descontar';
    v_id_almacen := (v_ruta->>'id_almacen')::bigint;

    -- 2. Servicio: no hay inventario que mover.
    IF v_descontar = 'nada' THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Servicio: sin movimiento de inventario'
        );
    END IF;

    -- 3. Receta: delegar en el helper del 01 con el almacen resuelto.
    --    Para un al_pedido de cocina ese almacen es el de la COCINA, que es
    --    justo lo que arregla este archivo.
    IF v_descontar = 'ingredientes' THEN
        v_resultado := fn_descontar_ingredientes_elaborado(
            p_id_producto_elaborado := p_id_producto,
            p_cantidad              := p_cantidad,
            p_id_almacen            := v_id_almacen,
            p_id_extraccion         := p_id_extraccion,
            p_origen_cambio         := p_origen_cambio
        );

        IF (v_resultado->>'status') <> 'success' THEN
            -- Enriquecer el error con el contexto de cocina para que el
            -- vendedor sepa DONDE falta la materia prima.
            RETURN v_resultado || jsonb_build_object(
                'origen',     v_origen,
                'id_almacen', v_id_almacen,
                'id_cocina',  v_ruta->'id_cocina',
                'cocina',     v_ruta->'cocina'
            );
        END IF;

        RETURN v_resultado || jsonb_build_object(
            'origen',     v_origen,
            'id_almacen', v_id_almacen,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina',
            'descontado', true
        );
    END IF;

    -- 4. SKU propio.
    --    En barra la venta ya inserto su movimiento: aqui solo se valida.
    IF v_origen = 'barra' AND p_ya_descontado_sku THEN
        RETURN v_ruta || jsonb_build_object(
            'descontado', false,
            'message',    'Producto de barra: descontado por la funcion de venta'
        );
    END IF;

    -- Validar que alcance antes de mover nada.
    v_disponible := fn_stock_producto_almacen(p_id_producto, v_id_almacen);

    IF COALESCE(v_disponible, 0) < p_cantidad THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    CASE
                WHEN v_origen = 'cocina_por_tanda' THEN
                    'No hay suficientes porciones preparadas en "'
                    || COALESCE(v_ruta->>'cocina', 'la cocina')
                    || '" (disponibles: ' || COALESCE(v_disponible, 0)
                    || ', requeridas: ' || p_cantidad || ')'
                ELSE
                    'Stock insuficiente (disponible: ' || COALESCE(v_disponible, 0)
                    || ', requerido: ' || p_cantidad || ')'
            END,
            'error_code',          CASE WHEN v_origen = 'cocina_por_tanda'
                                        THEN 'INSUFFICIENT_PORTIONS'
                                        ELSE 'INSUFFICIENT_STOCK' END,
            'origen',              v_origen,
            'id_almacen',          v_id_almacen,
            'id_cocina',           v_ruta->'id_cocina',
            'cocina',              v_ruta->'cocina',
            'cantidad_disponible', COALESCE(v_disponible, 0),
            'cantidad_requerida',  p_cantidad
        );
    END IF;

    -- Descontar repartiendo entre ubicaciones, igual que el helper del 01.
    v_pendiente := p_cantidad;

    FOR v_ubic IN
        SELECT * FROM fn_stock_producto_almacen_detalle(p_id_producto, v_id_almacen)
    LOOP
        EXIT WHEN v_pendiente <= 0;

        v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);

        INSERT INTO app_dat_inventario_productos (
            id_producto,
            id_variante,
            id_opcion_variante,
            id_ubicacion,
            id_presentacion,
            cantidad_inicial,
            cantidad_final,
            sku_producto,
            sku_ubicacion,
            origen_cambio,
            id_extraccion,
            created_at
        ) VALUES (
            p_id_producto,
            v_ubic.id_variante,
            v_ubic.id_opcion_variante,
            v_ubic.id_ubicacion,
            v_ubic.id_presentacion,
            v_ubic.cantidad_final,
            v_ubic.cantidad_final - v_a_descontar,
            v_ubic.sku_producto,
            v_ubic.sku_ubicacion,
            p_origen_cambio,
            p_id_extraccion,
            NOW()
        );

        v_movimientos := v_movimientos || jsonb_build_object(
            'id_ubicacion', v_ubic.id_ubicacion,
            'antes',        v_ubic.cantidad_final,
            'descontado',   v_a_descontar,
            'despues',      v_ubic.cantidad_final - v_a_descontar
        );

        v_pendiente := v_pendiente - v_a_descontar;
    END LOOP;

    -- Defensa: si algo cambio entre la validacion y el descuento.
    IF v_pendiente > 0 THEN
        RAISE EXCEPTION
            'No se pudo descontar la cantidad completa del producto % en el almacen % (falto %)',
            p_id_producto, v_id_almacen, v_pendiente;
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'origen',      v_origen,
        'id_almacen',  v_id_almacen,
        'id_cocina',   v_ruta->'id_cocina',
        'cocina',      v_ruta->'cocina',
        'id_producto', p_id_producto,
        'cantidad',    p_cantidad,
        'descontado',  true,
        'movimientos', v_movimientos
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_descontar_venta_enrutada(bigint, numeric, bigint, bigint, integer, boolean)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las dos funciones deben existir, SECURITY DEFINER y con search_path fijo
SELECT p.oid::regprocedure AS firma,
       p.prosecdef         AS security_definer,
       p.proconfig         AS config
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_resolver_origen_venta', 'fn_descontar_venta_enrutada')
 ORDER BY p.proname;

-- (b) Los helpers del 01 en que se apoyan deben seguir presentes -> 4 filas
SELECT p.oid::regprocedure AS helper_requerido
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_stock_producto_almacen',
        'fn_stock_producto_almacen_detalle',
        'fn_descontar_ingredientes_elaborado',
        'fn_obtener_ingredientes_recursivos'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL (transaccion revertida: no deja rastro)
--
-- Datos reales verificados contra produccion:
--   tienda 11, TPV 18 -> almacen 12; ubicacion 37 pertenece al almacen 12
--   elaborado 219 "croqueta" = 40 g harina (216) + 10 g sal (218)
--   harina (216) en almacen 12: 5.0    sal (218) en almacen 12: 27.5
--
-- Lo que se demuestra: el descuento sale del almacen de la COCINA y no del de
-- la barra. Se comprueba mirando el stock de los DOS almacenes antes y despues.
--
-- Ejecutar TODO el bloque de una vez.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    -- ── Preparacion ───────────────────────────────────────────────────────
    SELECT public.fn_crear_cocina(11, 'PRUEBA Cocina 10') AS cocina;

    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 10')
    ) AS ligar;

    -- Cargar MP SOLO en la cocina: 500 g harina, 200 g sal.
    -- Con eso salen 12 croquetas (500/40 = 12, frente a 200/10 = 20).
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 216,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 10' LIMIT 1),
           500, 500, now();

    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 218,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 10' LIMIT 1),
           200, 200, now();

    UPDATE app_dat_producto
       SET id_cocina = (SELECT id FROM app_dat_cocina
                         WHERE denominacion = 'PRUEBA Cocina 10'),
           modo_elaboracion = 'al_pedido'
     WHERE id = 219;

    -- ── 1. Enrutamiento: al_pedido debe apuntar al almacen de la COCINA ───
    SELECT public.fn_resolver_origen_venta(219, 18) AS ruta_al_pedido;
    -- esperado: origen 'cocina_al_pedido', descontar 'ingredientes',
    --           id_almacen = almacen de la cocina (NO 12)

    -- ── 2. Foto del stock ANTES ───────────────────────────────────────────
    SELECT 'ANTES' AS momento,
           public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(218, 12) AS sal_barra,
           public.fn_stock_producto_almacen(216,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS harina_cocina,
           public.fn_stock_producto_almacen(218,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS sal_cocina;
    -- esperado: harina_barra 5.0, sal_barra 27.5,
    --           harina_cocina 500, sal_cocina 200

    -- ── 3. Vender 2 croquetas al pedido ───────────────────────────────────
    SELECT public.fn_descontar_venta_enrutada(
        p_id_producto := 219,
        p_cantidad    := 2,
        p_id_tpv      := 18
    ) AS venta_al_pedido;
    -- esperado: status success, origen 'cocina_al_pedido', descontado true

    -- ── 4. Foto del stock DESPUES · ESTA ES LA COMPROBACION CLAVE ─────────
    SELECT 'DESPUES' AS momento,
           public.fn_stock_producto_almacen(216, 12) AS harina_barra,
           public.fn_stock_producto_almacen(218, 12) AS sal_barra,
           public.fn_stock_producto_almacen(216,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS harina_cocina,
           public.fn_stock_producto_almacen(218,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS sal_cocina;
    -- esperado: harina_barra 5.0    <- INTACTA, no se toco la barra
    --           sal_barra    27.5   <- INTACTA
    --           harina_cocina 420   <- 500 - (40 * 2)
    --           sal_cocina    180   <- 200 - (10 * 2)
    --
    -- Antes de este archivo, la barra habria bajado a 5-80 (imposible) o la
    -- venta habria fallado con "stock insuficiente" teniendo la cocina llena.

    -- ── 5. por_tanda: se descuenta el SKU, NO la receta ───────────────────
    UPDATE app_dat_producto SET modo_elaboracion = 'por_tanda' WHERE id = 219;

    SELECT public.fn_resolver_origen_venta(219, 18) AS ruta_por_tanda;
    -- esperado: origen 'cocina_por_tanda', descontar 'sku'

    -- Sin porciones hechas debe fallar, aunque haya MP de sobra.
    SELECT public.fn_descontar_venta_enrutada(219, 1, 18) AS sin_porciones;
    -- esperado: error_code INSUFFICIENT_PORTIONS, mensaje nombrando la cocina

    -- Meter 7 porciones hechas en la cocina.
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    SELECT 219,
           (SELECT la.id FROM app_dat_layout_almacen la
              JOIN app_dat_cocina c ON c.id_almacen = la.id_almacen
             WHERE c.denominacion = 'PRUEBA Cocina 10' LIMIT 1),
           7, 7, now();

    SELECT public.fn_descontar_venta_enrutada(219, 3, 18) AS venta_por_tanda;
    -- esperado: status success, origen 'cocina_por_tanda', descontado true

    SELECT public.fn_stock_producto_almacen(219,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS porciones_restantes,
           public.fn_stock_producto_almacen(216,
               (SELECT id_almacen FROM app_dat_cocina
                 WHERE denominacion = 'PRUEBA Cocina 10')) AS harina_cocina;
    -- esperado: porciones_restantes 4  (7 - 3)
    --           harina_cocina       420 <- SIN CAMBIO: por_tanda no toca receta
    --
    -- Si la harina hubiera bajado, se estaria cobrando la MP dos veces: una al
    -- producir la tanda y otra al venderla.

    -- ── 6. Enrutamiento invalido: TPV no ligado ───────────────────────────
    SELECT public.fn_desasignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 10')
    );

    SELECT public.fn_resolver_origen_venta(219, 18)      AS ruta_no_ligada;
    SELECT public.fn_descontar_venta_enrutada(219, 1, 18) AS venta_no_ligada;
    -- esperado en ambas: error_code COCINA_NO_LIGADA
    -- Criterio del plan: "bistec va a Cocina caliente; no aparece en Pizzeria"

    -- ── 7. Cocina desactivada (turno cerrado) ─────────────────────────────
    SELECT public.fn_asignar_tpv_cocina(
        18,
        (SELECT id FROM app_dat_cocina WHERE denominacion = 'PRUEBA Cocina 10')
    );
    UPDATE app_dat_cocina SET activa = false
     WHERE denominacion = 'PRUEBA Cocina 10';

    SELECT public.fn_descontar_venta_enrutada(219, 1, 18) AS cocina_cerrada;
    -- esperado: error_code COCINA_INACTIVA

    UPDATE app_dat_cocina SET activa = true
     WHERE denominacion = 'PRUEBA Cocina 10';

    -- ── 8. Excepcion barra: con stock propio en el almacen del TPV ────────
    -- Mismo criterio que el catalogo del 09: si esta al alcance del vendedor,
    -- se sirve de ahi y NO se toca la cocina.
    INSERT INTO app_dat_inventario_productos
        (id_producto, id_ubicacion, cantidad_inicial, cantidad_final, created_at)
    VALUES (219, 37, 5, 5, now());   -- ubicacion 37 -> almacen 12 (barra)

    SELECT public.fn_resolver_origen_venta(219, 18) AS ruta_con_stock_barra;
    -- esperado: origen 'barra', id_almacen 12, nota sobre el stock en barra

    -- Con p_ya_descontado_sku = true (como lo llamara el 11 para barra) NO
    -- debe volver a descontar: la funcion de venta ya inserto su movimiento.
    SELECT public.fn_descontar_venta_enrutada(
        p_id_producto       := 219,
        p_cantidad          := 1,
        p_id_tpv            := 18,
        p_ya_descontado_sku := true
    ) AS barra_sin_doble_descuento;
    -- esperado: descontado false, mensaje "descontado por la funcion de venta"

    SELECT public.fn_stock_producto_almacen(219, 12) AS barra_intacta;
    -- esperado: 5  <- NO bajo: no hubo doble descuento

    -- ── 9. Producto de barra normal (sin cocina) sigue igual ──────────────
    UPDATE app_dat_producto SET id_cocina = NULL WHERE id = 219;
    SELECT public.fn_resolver_origen_venta(216, 18) AS ruta_harina_barra;
    -- esperado: origen 'barra', id_almacen 12, descontar 'sku'

    -- ── 10. Casos borde ───────────────────────────────────────────────────
    SELECT public.fn_descontar_venta_enrutada(219, 0, 18)      AS cantidad_cero;
    -- esperado: error_code INVALID_QUANTITY
    SELECT public.fn_resolver_origen_venta(219, 999999)        AS tpv_inexistente;
    -- esperado: error_code TPV_NOT_FOUND
    SELECT public.fn_resolver_origen_venta(999999, 18)         AS producto_inexistente;
    -- esperado: error_code PRODUCTO_NOT_FOUND

ROLLBACK;
*/

-- Comprobar que el ROLLBACK dejo todo limpio -> 0 filas las tres
-- SELECT id, denominacion FROM app_dat_cocina WHERE denominacion LIKE 'PRUEBA%';
-- SELECT id, id_cocina FROM app_dat_producto WHERE id = 219 AND id_cocina IS NOT NULL;
-- SELECT public.fn_stock_producto_almacen(219, 12) AS croqueta_en_barra;  -- debe ser 0
