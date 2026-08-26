-- ============================================================================
-- 21 · Fase 4 · Tandas de produccion
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE RESUELVE
-- ------------
-- Hay platos que no se cocinan al pedido: se producen en lote y se sirven por
-- porciones (arroz moro, congri, potaje). El plan lo dice asi:
--
--   "Producir N porciones; disponibilidad por stock terminado; parada de BOM."
--
-- Hoy el sistema ya SIRVE porciones (modo_elaboracion = 'por_tanda' descuenta
-- el SKU terminado del almacen de la cocina, Fase 1/2), pero NO hay forma de
-- METERLAS: nadie convierte 2 kg de arroz + especias en 12 porciones de moro.
-- Ese es el agujero que cierra este archivo.
--
-- ESTADO VERIFICADO ANTES DE ESCRIBIR (via MCP)
-- ---------------------------------------------
-- Existen y se reutilizan:
--   fn_descontar_ingredientes_elaborado(p_id_producto_elaborado, p_cantidad,
--       p_id_almacen, p_id_extraccion DEFAULT NULL, p_origen_cambio DEFAULT 4)
--   fn_validar_ingredientes_elaborado(p_id_producto_elaborado, p_cantidad, p_id_almacen)
--   fn_devolver_ingredientes_elaborado(... mismos 5 args ...)
--   fn_ubicacion_destino_devolucion(p_id_producto, p_id_almacen)
--       -> COALESCE(donde ya hay stock, ultimo movimiento, primer layout)
--   fn_stock_producto_almacen(p_id_producto, p_id_almacen)
--   fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
--
-- app_dat_inventario_productos: id_presentacion es NOT NULL. Se resuelve con la
-- misma cascada COALESCE de tres pasos que usa fn_devolver_ingredientes_elaborado
-- (ubicacion -> almacen -> presentacion base del producto). Se comprobo que
-- omitirla revienta con SQLSTATE 23502 (fue el bug del archivo 16).
--
-- origen_cambio en uso hoy: 1..7 y un 24 suelto. Se usan valores existentes en
-- vez de inventar codigos nuevos:
--   4 = consumo de receta (lo que ya usa fn_descontar_ingredientes_elaborado)
--   1 = entrada de inventario (para la entrada de porciones terminadas)
--
-- DECISIONES DE DISENO
-- --------------------
--
-- 1. LA TANDA ES UN MOVIMIENTO DE INVENTARIO, NO UN ESTADO PARALELO.
--    Producir escribe en app_dat_inventario_productos: sale MP, entra producto
--    terminado. app_dat_produccion_tanda es la CABECERA de auditoria (quien,
--    cuando, cuanto, con que merma), no la fuente de verdad del stock.
--    Asi los reportes de inventario que ya existen ven la produccion sin
--    tocarlos, y fn_disponibilidad_plato sigue funcionando sin cambios.
--
-- 2. LA MERMA SE DECLARA AL CERRAR, NO AL PRODUCIR.
--    Se producen 12 porciones de moro; al final del servicio sobran 2 que se
--    botan. Eso NO es lo mismo que producir 10. El costo real de la tanda
--    incluye las 12, y el descarte hay que poder mirarlo para ajustar la
--    produccion del dia siguiente. De ahi que la tabla lleve
--    porciones_producidas y porciones_descartadas por separado.
--
-- 3. NO SE VALIDA CONTRA LA CANTIDAD "TEORICA" DE LA RECETA.
--    La receta de una porcion de moro dice 150 g de arroz. Producir 12 porciones
--    consume 1.8 kg. Pero en la vida real el cocinero echa el arroz que le
--    parece. Se descuenta lo que dice la receta por N porciones (trazable y
--    consistente con el resto del sistema) y se deja p_ajuste_mp para corregir
--    a mano cuando haga falta, en vez de bloquear la produccion.
--
-- 4. PARADA DE BOM (el punto mas importante del plan).
--    fn_obtener_ingredientes_recursivos explota hasta hojas (es_elaborado =
--    false). Un combo al_pedido con un componente por_tanda (bistec + moro)
--    explota la receta del moro en vez de contar porciones hechas. Se crea
--    fn_ingredientes_con_parada_tanda, que se detiene en cualquier componente
--    por_tanda y lo devuelve como si fuera un ingrediente hoja.
--    Es un helper NUEVO: no se toca fn_obtener_ingredientes_recursivos, que la
--    usan la Fase 0 y varias funciones de venta en produccion.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Este archivo (idempotente).
--   2. Correr la VERIFICACION del final.
--   3. Luego el 22 (parada de BOM en disponibilidad y descuento) y el 23 (UI).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 21.1 app_dat_produccion_tanda
--
-- Cabecera de auditoria de un lote producido.
--
-- estado:
--   1 abierta    se esta consumiendo del lote (hay porciones disponibles)
--   2 agotada    se vendieron todas las porciones
--   3 cerrada    el jefe cerro el lote y declaro la merma
--   4 anulada    se revirtio la produccion (devuelve MP, retira porciones)
--
-- No se guarda "porciones_restantes": eso lo dice el inventario del SKU
-- terminado (fn_stock_producto_almacen). Duplicarlo aqui garantiza que un dia
-- las dos cifras no coincidan.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_produccion_tanda (
    id                     bigserial PRIMARY KEY,

    id_cocina              bigint      NOT NULL
                           REFERENCES public.app_dat_cocina(id),
    id_producto            bigint      NOT NULL
                           REFERENCES public.app_dat_producto(id),

    -- Almacen y ubicacion donde entraron las porciones. Se guardan explicitos
    -- para poder anular la tanda sin volver a resolverlos (y que la anulacion
    -- retire de donde de verdad entro).
    id_almacen             bigint      NOT NULL
                           REFERENCES public.app_dat_almacen(id),
    id_ubicacion           bigint      NOT NULL
                           REFERENCES public.app_dat_layout_almacen(id),

    porciones_producidas   numeric(14,3) NOT NULL
                           CHECK (porciones_producidas > 0),
    porciones_descartadas  numeric(14,3) NOT NULL DEFAULT 0
                           CHECK (porciones_descartadas >= 0),

    estado                 smallint    NOT NULL DEFAULT 1
                           CHECK (estado BETWEEN 1 AND 4),

    -- Quien produjo. uuid del cocinero/jefe; el trabajador se resuelve por
    -- app_dat_jefe_cocina cuando haga falta mostrar el nombre.
    uuid_usuario           uuid,

    notas                  text,
    motivo_descarte        text,

    -- Costo de la MP consumida en el momento de producir, congelado. El costo
    -- de los ingredientes cambia; el de esta tanda no debe cambiar con el.
    costo_mp               numeric(14,2),

    -- Fila de app_dat_inventario_productos que metio las porciones. Es el ANCLA
    -- para detectar salidas posteriores al anular. Comparar por created_at NO
    -- sirve: now() devuelve el mismo timestamp para toda la transaccion, asi que
    -- una venta hecha en la misma transaccion tiene created_at identico y el
    -- filtro '>' la pierde. La secuencia de ids si es monotona.
    id_inventario_entrada  bigint,

    created_at             timestamptz NOT NULL DEFAULT now(),
    closed_at              timestamptz,
    cancelled_at           timestamptz
);

COMMENT ON TABLE public.app_dat_produccion_tanda IS
    'Lotes de produccion de platos por_tanda. Cabecera de auditoria: el stock real vive en app_dat_inventario_productos.';
COMMENT ON COLUMN public.app_dat_produccion_tanda.porciones_descartadas IS
    'Merma declarada al cerrar el lote. Separada de las producidas para no falsear el costo real de la tanda.';

CREATE INDEX IF NOT EXISTS idx_produccion_tanda_cocina
    ON public.app_dat_produccion_tanda (id_cocina, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_produccion_tanda_producto
    ON public.app_dat_produccion_tanda (id_producto, estado);

CREATE INDEX IF NOT EXISTS idx_produccion_tanda_abiertas
    ON public.app_dat_produccion_tanda (id_cocina)
    WHERE estado = 1;

-- ----------------------------------------------------------------------------
-- 21.2 fn_ingredientes_con_parada_tanda   <<< EL NUCLEO DE LA FASE 4
--
-- Explota la receta de un producto PARANDO en los componentes por_tanda.
--
-- EL PROBLEMA QUE RESUELVE
-- ------------------------
-- fn_obtener_ingredientes_recursivos baja hasta las hojas (filtra al final por
-- es_elaborado = false). Con un combo asi:
--
--   Bistec con moro (al_pedido)
--     +- bistec de cerdo   200 g   (ingrediente hoja)
--     +- moro              1 porc  (elaborado, POR TANDA)
--          +- arroz  150 g
--          +- frijol  50 g
--
-- la funcion vieja devuelve: bistec 200 g + arroz 150 g + frijol 50 g. Es
-- INCORRECTO en dos sentidos:
--
--   a) Al vender descontaria arroz y frijol crudos que YA se consumieron al
--      producir la tanda de moro -> el arroz se descuenta DOS VECES.
--   b) Al calcular disponibilidad diria "hay 40 bistecs con moro" porque hay
--      arroz en el almacen, cuando solo hay 3 porciones de moro hechas.
--
-- Lo correcto es parar en el moro y tratarlo como un ingrediente mas, cuyo
-- stock es el del SKU terminado.
--
-- COMO
-- ----
-- CTE recursiva igual que la original, pero la condicion de recursion exige que
-- el hijo NO sea por_tanda. Y el SELECT final no filtra solo hojas: devuelve
-- hojas crudas Y componentes por_tanda.
--
-- Se devuelve es_por_tanda para que quien llame sepa que ese "ingrediente" se
-- descuenta como SKU terminado y no como materia prima.
--
-- NO se toca fn_obtener_ingredientes_recursivos: la usan la Fase 0, las dos
-- funciones de venta y fn_devolver_ingredientes_elaborado, todas en produccion.
-- Esta es nueva y quien quiera la parada la pide explicitamente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ingredientes_con_parada_tanda(
    p_id_producto_elaborado bigint,
    p_cantidad_producto     numeric DEFAULT 1
)
RETURNS TABLE (
    id_ingrediente            bigint,
    cantidad_total_necesaria  numeric,
    nivel_recursion           integer,
    es_por_tanda              boolean
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  WITH RECURSIVE ingredientes AS (
    -- Caso base: ingredientes directos.
    SELECT
      pi.id_ingrediente,
      pi.cantidad_necesaria * p_cantidad_producto AS cantidad_total,
      1 AS nivel,
      ARRAY[p_id_producto_elaborado] AS ruta
    FROM app_dat_producto_ingredientes pi
    WHERE pi.id_producto_elaborado = p_id_producto_elaborado

    UNION ALL

    -- Caso recursivo: solo se BAJA por hijos elaborados que NO sean por_tanda.
    -- Un hijo por_tanda se queda como hoja: su stock es el del SKU terminado.
    SELECT
      pi.id_ingrediente,
      pi.cantidad_necesaria * ing.cantidad_total AS cantidad_total,
      ing.nivel + 1 AS nivel,
      ing.ruta || pi.id_producto_elaborado AS ruta
    FROM app_dat_producto_ingredientes pi
    INNER JOIN ingredientes ing ON pi.id_producto_elaborado = ing.id_ingrediente
    INNER JOIN app_dat_producto p ON p.id = pi.id_producto_elaborado
    WHERE p.es_elaborado = true
      AND COALESCE(p.modo_elaboracion, 'al_pedido') <> 'por_tanda'   -- LA PARADA
      AND NOT (pi.id_producto_elaborado = ANY(ing.ruta))             -- evitar ciclos
      AND ing.nivel < 10                                             -- limite de seguridad
  )
  SELECT
    ing.id_ingrediente,
    SUM(ing.cantidad_total)::numeric AS cantidad_total_necesaria,
    MAX(ing.nivel)::integer          AS nivel_recursion,
    -- Un componente elaborado por_tanda se consume como SKU terminado.
    bool_or(p.es_elaborado = true
            AND COALESCE(p.modo_elaboracion, 'al_pedido') = 'por_tanda') AS es_por_tanda
  FROM ingredientes ing
  INNER JOIN app_dat_producto p ON p.id = ing.id_ingrediente
  -- A diferencia de la original NO se filtra solo es_elaborado = false: hacen
  -- falta las hojas crudas Y los componentes por_tanda donde se paro.
  WHERE p.es_elaborado = false
     OR COALESCE(p.modo_elaboracion, 'al_pedido') = 'por_tanda'
  GROUP BY ing.id_ingrediente;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_ingredientes_con_parada_tanda(bigint, numeric)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 21.3 fn_producir_tanda
--
-- "Producir N porciones de moro."
--
-- Consume la materia prima de la receta (por N porciones) del almacen de la
-- cocina y mete N porciones del SKU terminado en ese mismo almacen.
--
-- POR QUE NO SE REUSA fn_descontar_ingredientes_elaborado A SECAS
-- ---------------------------------------------------------------
-- Si se reusara tal cual, un plato por_tanda cuya receta lleve OTRO componente
-- por_tanda explotaria la receta del nieto. Se usa el helper 21.2 para la
-- validacion y el descuento, parando donde debe.
--
-- Ojo con el orden: primero se VALIDA todo, luego se descuenta, y solo al final
-- entra el producto terminado. Si falta materia prima a mitad de camino, la
-- cocina no se queda con porciones fantasma.
--
-- GUARD: requiere ser JEFE de la cocina (p_requiere_jefe = true). Producir una
-- tanda mueve inventario de verdad; un cocinero marca comandas, no produce.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_producir_tanda(
    p_id_cocina   bigint,
    p_id_producto bigint,
    p_porciones   numeric,
    p_notas       text    DEFAULT NULL,
    p_ajuste_mp   numeric DEFAULT 1.0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_almacen        bigint;
    v_cocina_nombre  text;
    v_cocina_activa  boolean;
    v_prod           RECORD;
    v_ing            RECORD;
    v_ubic_destino   bigint;
    v_ubic_mp        bigint;
    v_stock          numeric;
    v_actual         numeric;
    v_presentacion   bigint;
    v_sku_producto   varchar;
    v_sku_ubicacion  varchar;
    v_id_tanda       bigint;
    v_consumo        jsonb := '[]'::jsonb;
    v_costo          numeric := 0;
    v_faltantes      jsonb := '[]'::jsonb;
    v_id_inv_entrada bigint;
    v_cant_mp        numeric;
BEGIN
    IF p_porciones IS NULL OR p_porciones <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Las porciones a producir deben ser mayores que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    SELECT c.id_almacen, c.denominacion, c.activa
      INTO v_almacen, v_cocina_nombre, v_cocina_activa
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_almacen IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    -- Producir mueve inventario: hace falta ser jefe, no solo cocinero.
    PERFORM fn_usuario_puede_operar_cocina(p_id_cocina, true);

    IF NOT v_cocina_activa THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina "' || v_cocina_nombre || '" esta desactivada',
            'error_code', 'COCINA_INACTIVA'
        );
    END IF;

    SELECT p.id, p.denominacion, p.es_elaborado, p.modo_elaboracion, p.id_cocina, p.sku
      INTO v_prod
      FROM app_dat_producto p
     WHERE p.id = p_id_producto;

    IF v_prod.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no existe',
            'error_code', 'PRODUCTO_NOT_FOUND'
        );
    END IF;

    -- Solo tiene sentido producir en lote lo que se sirve por porciones.
    IF COALESCE(v_prod.modo_elaboracion, 'al_pedido') <> 'por_tanda' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', v_prod.denominacion || ' no esta configurado como plato por tanda. '
                       || 'Cambialo a "por tanda" en la gestion de platos si se produce en lote.',
            'error_code', 'NO_ES_POR_TANDA',
            'modo_actual', COALESCE(v_prod.modo_elaboracion, 'al_pedido')
        );
    END IF;

    -- El plato debe pertenecer a ESTA cocina: si no, la produccion entraria en
    -- un almacen donde el catalogo no lo va a buscar.
    IF v_prod.id_cocina IS DISTINCT FROM p_id_cocina THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', v_prod.denominacion || ' no pertenece a ' || v_cocina_nombre,
            'error_code', 'PLATO_OTRA_COCINA',
            'id_cocina_plato', v_prod.id_cocina
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app_dat_producto_ingredientes pi
         WHERE pi.id_producto_elaborado = p_id_producto
    ) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', v_prod.denominacion || ' no tiene receta: no se puede calcular el consumo',
            'error_code', 'SIN_RECETA'
        );
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- PRIMERA PASADA: validar TODA la materia prima antes de tocar nada.
    -- Se acumulan los faltantes en vez de cortar en el primero, para que el
    -- jefe de cocina vea de una vez todo lo que le falta.
    -- ══════════════════════════════════════════════════════════════════════
    FOR v_ing IN
        SELECT t.id_ingrediente, t.cantidad_total_necesaria, t.es_por_tanda,
               pr.denominacion
          FROM fn_ingredientes_con_parada_tanda(p_id_producto, p_porciones) t
          JOIN app_dat_producto pr ON pr.id = t.id_ingrediente
    LOOP
        v_cant_mp := v_ing.cantidad_total_necesaria * COALESCE(p_ajuste_mp, 1.0);
        v_stock := fn_stock_producto_almacen(v_ing.id_ingrediente, v_almacen);

        IF v_stock < v_cant_mp THEN
            v_faltantes := v_faltantes || jsonb_build_object(
                'id_producto',  v_ing.id_ingrediente,
                'ingrediente',  v_ing.denominacion,
                'necesario',    v_cant_mp,
                'disponible',   v_stock,
                'falta',        v_cant_mp - v_stock,
                'es_por_tanda', v_ing.es_por_tanda
            );
        END IF;
    END LOOP;

    IF jsonb_array_length(v_faltantes) > 0 THEN
        RETURN jsonb_build_object(
            'status',      'error',
            'message',     'No hay materia prima suficiente en ' || v_cocina_nombre
                           || ' para producir ' || p_porciones || ' porciones',
            'error_code',  'INSUFFICIENT_STOCK',
            'id_cocina',   p_id_cocina,
            'cocina',      v_cocina_nombre,
            'producto',    v_prod.denominacion,
            'porciones',   p_porciones,
            'faltantes',   v_faltantes
        );
    END IF;

    -- Ubicacion donde entraran las porciones terminadas.
    v_ubic_destino := fn_ubicacion_destino_devolucion(p_id_producto, v_almacen);

    IF v_ubic_destino IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El almacen de ' || v_cocina_nombre
                       || ' no tiene ninguna ubicacion donde meter las porciones',
            'error_code', 'NO_LOCATION_FOUND',
            'id_almacen', v_almacen
        );
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- Cabecera de la tanda. Se crea ANTES de mover inventario para poder
    -- referenciarla; si algo falla despues, el RAISE revierte todo.
    -- ══════════════════════════════════════════════════════════════════════
    INSERT INTO app_dat_produccion_tanda (
        id_cocina, id_producto, id_almacen, id_ubicacion,
        porciones_producidas, estado, uuid_usuario, notas
    ) VALUES (
        p_id_cocina, p_id_producto, v_almacen, v_ubic_destino,
        p_porciones, 1, auth.uid(), p_notas
    ) RETURNING id INTO v_id_tanda;

    -- ══════════════════════════════════════════════════════════════════════
    -- SEGUNDA PASADA: consumir la materia prima.
    --
    -- No se delega en fn_descontar_ingredientes_elaborado porque esa explota
    -- hasta hojas y aqui hace falta la parada en componentes por_tanda. Se
    -- escribe el movimiento directo, con el mismo patron: fila nueva con
    -- cantidad_inicial / cantidad_final, nunca UPDATE del stock.
    -- ══════════════════════════════════════════════════════════════════════
    FOR v_ing IN
        SELECT t.id_ingrediente, t.cantidad_total_necesaria, t.es_por_tanda,
               pr.denominacion, pr.sku
          FROM fn_ingredientes_con_parada_tanda(p_id_producto, p_porciones) t
          JOIN app_dat_producto pr ON pr.id = t.id_ingrediente
    LOOP
        v_cant_mp := v_ing.cantidad_total_necesaria * COALESCE(p_ajuste_mp, 1.0);

        -- De donde sacar: la ubicacion de ese almacen con mas stock.
        SELECT d.id_ubicacion INTO v_ubic_mp
          FROM fn_stock_producto_almacen_detalle(v_ing.id_ingrediente, v_almacen) d
         ORDER BY d.cantidad_final DESC
         LIMIT 1;

        IF v_ubic_mp IS NULL THEN
            RAISE EXCEPTION 'No se encontro ubicacion con stock de % en el almacen %',
                v_ing.denominacion, v_almacen USING ERRCODE = 'P0001';
        END IF;

        SELECT ip.cantidad_final, ip.id_presentacion, ip.sku_producto, ip.sku_ubicacion
          INTO v_actual, v_presentacion, v_sku_producto, v_sku_ubicacion
          FROM app_dat_inventario_productos ip
         WHERE ip.id_producto = v_ing.id_ingrediente
           AND ip.id_ubicacion = v_ubic_mp
         ORDER BY ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        -- id_presentacion es NOT NULL: misma cascada de tres pasos que usa
        -- fn_devolver_ingredientes_elaborado. Omitirla revienta con 23502.
        IF v_presentacion IS NULL THEN
            SELECT COALESCE(
                (SELECT ip2.id_presentacion FROM app_dat_inventario_productos ip2
                   JOIN app_dat_layout_almacen la2 ON la2.id = ip2.id_ubicacion
                  WHERE ip2.id_producto = v_ing.id_ingrediente
                    AND la2.id_almacen = v_almacen
                    AND ip2.id_presentacion IS NOT NULL
                  ORDER BY ip2.id DESC LIMIT 1),
                (SELECT pp.id FROM app_dat_producto_presentacion pp
                  WHERE pp.id_producto = v_ing.id_ingrediente
                  ORDER BY pp.es_base DESC, pp.id ASC LIMIT 1)
            ) INTO v_presentacion;
        END IF;

        IF v_presentacion IS NULL THEN
            RAISE EXCEPTION 'El ingrediente % no tiene presentacion definida',
                v_ing.denominacion USING ERRCODE = 'P0001';
        END IF;

        INSERT INTO app_dat_inventario_productos (
            id_producto, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio, created_at
        ) VALUES (
            v_ing.id_ingrediente, v_ubic_mp, v_presentacion,
            v_actual, v_actual - v_cant_mp,
            COALESCE(v_sku_producto, v_ing.sku),
            COALESCE(v_sku_ubicacion,
                     (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_ubic_mp)),
            4,   -- 4 = consumo de receta, el mismo que usa la Fase 0
            now()
        );

        v_consumo := v_consumo || jsonb_build_object(
            'id_producto',  v_ing.id_ingrediente,
            'ingrediente',  v_ing.denominacion,
            'consumido',    v_cant_mp,
            'es_por_tanda', v_ing.es_por_tanda,
            'stock_previo', v_actual,
            'stock_nuevo',  v_actual - v_cant_mp
        );
    END LOOP;

    -- ══════════════════════════════════════════════════════════════════════
    -- ENTRADA del producto terminado: N porciones al almacen de la cocina.
    -- ══════════════════════════════════════════════════════════════════════
    SELECT ip.cantidad_final, ip.id_presentacion, ip.sku_ubicacion
      INTO v_actual, v_presentacion, v_sku_ubicacion
      FROM app_dat_inventario_productos ip
     WHERE ip.id_producto = p_id_producto
       AND ip.id_ubicacion = v_ubic_destino
     ORDER BY ip.id DESC
     LIMIT 1;

    v_actual := COALESCE(v_actual, 0);

    IF v_presentacion IS NULL THEN
        SELECT COALESCE(
            (SELECT ip2.id_presentacion FROM app_dat_inventario_productos ip2
               JOIN app_dat_layout_almacen la2 ON la2.id = ip2.id_ubicacion
              WHERE ip2.id_producto = p_id_producto
                AND la2.id_almacen = v_almacen
                AND ip2.id_presentacion IS NOT NULL
              ORDER BY ip2.id DESC LIMIT 1),
            (SELECT pp.id FROM app_dat_producto_presentacion pp
              WHERE pp.id_producto = p_id_producto
              ORDER BY pp.es_base DESC, pp.id ASC LIMIT 1)
        ) INTO v_presentacion;
    END IF;

    IF v_presentacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', v_prod.denominacion || ' no tiene presentacion definida: '
                       || 'no se puede registrar el inventario de las porciones',
            'error_code', 'SIN_PRESENTACION'
        );
    END IF;

    INSERT INTO app_dat_inventario_productos (
        id_producto, id_ubicacion, id_presentacion,
        cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, created_at
    ) VALUES (
        p_id_producto, v_ubic_destino, v_presentacion,
        v_actual, v_actual + p_porciones,
        v_prod.sku,
        COALESCE(v_sku_ubicacion,
                 (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_ubic_destino)),
        1,   -- 1 = entrada de inventario
        now()
    ) RETURNING id INTO v_id_inv_entrada;

    -- Costo de la MP consumida, congelado en la cabecera.
    SELECT COALESCE(SUM(
             (m->>'consumido')::numeric *
             COALESCE((SELECT pc.precio_costo_usd FROM app_dat_precio_costo pc
                        WHERE pc.id_producto = (m->>'id_producto')::bigint
                        ORDER BY pc.id DESC LIMIT 1), 0)
           ), 0)
      INTO v_costo
      FROM jsonb_array_elements(v_consumo) m;

    UPDATE app_dat_produccion_tanda
       SET costo_mp = ROUND(v_costo, 2),
           id_inventario_entrada = v_id_inv_entrada
     WHERE id = v_id_tanda;

    RETURN jsonb_build_object(
        'status',            'success',
        'id_tanda',          v_id_tanda,
        'id_cocina',         p_id_cocina,
        'cocina',            v_cocina_nombre,
        'id_producto',       p_id_producto,
        'producto',          v_prod.denominacion,
        'porciones',         p_porciones,
        'id_almacen',        v_almacen,
        'id_ubicacion',      v_ubic_destino,
        'stock_previo',      v_actual,
        'stock_nuevo',       v_actual + p_porciones,
        'costo_mp',          ROUND(v_costo, 2),
        'costo_por_porcion', ROUND(v_costo / p_porciones, 2),
        'consumo',           v_consumo,
        'message',           p_porciones || ' porciones de ' || v_prod.denominacion
                             || ' listas en ' || v_cocina_nombre
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_producir_tanda(bigint, bigint, numeric, text, numeric)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 21.4 fn_cerrar_tanda
--
-- Fin de servicio: el jefe declara cuantas porciones sobraron y se botaron.
--
-- POR QUE LA MERMA VA AQUI Y NO AL PRODUCIR
-- -----------------------------------------
-- Se producen 12 porciones de moro y al cierre sobran 2 que se botan. Eso NO es
-- lo mismo que haber producido 10: la materia prima de las 12 se gasto igual.
-- Si se registraran 10, el costo por porcion saldria mal y nadie sabria que se
-- esta produciendo de mas todos los dias.
--
-- El descarte RETIRA inventario (las porciones ya no existen) pero se contabiliza
-- aparte, en porciones_descartadas, para poder mirarlo y ajustar la produccion.
--
-- No se exige que el descarte cuadre con el stock restante: puede haber dos
-- tandas del mismo plato abiertas, o alguien puede haber ajustado el inventario
-- por otra via. Se descarta lo que el jefe dice, acotado al stock que hay.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cerrar_tanda(
    p_id_tanda    bigint,
    p_descartadas numeric DEFAULT 0,
    p_motivo      text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_t              RECORD;
    v_stock          numeric;
    v_actual         numeric;
    v_presentacion   bigint;
    v_sku_ubicacion  varchar;
    v_prod_nombre    text;
    v_prod_sku       varchar;
    v_descartar      numeric;
BEGIN
    SELECT t.*, c.denominacion AS cocina
      INTO v_t
      FROM app_dat_produccion_tanda t
      JOIN app_dat_cocina c ON c.id = t.id_cocina
     WHERE t.id = p_id_tanda;

    IF v_t.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La tanda no existe',
            'error_code', 'TANDA_NOT_FOUND'
        );
    END IF;

    PERFORM fn_usuario_puede_operar_cocina(v_t.id_cocina, true);

    IF v_t.estado IN (3, 4) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', CASE v_t.estado
                WHEN 3 THEN 'La tanda ya estaba cerrada'
                ELSE 'La tanda fue anulada' END,
            'error_code', 'TANDA_YA_CERRADA',
            'estado', v_t.estado
        );
    END IF;

    IF p_descartadas < 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Las porciones descartadas no pueden ser negativas',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- Botar comida es una decision que hay que justificar.
    IF p_descartadas > 0 AND (p_motivo IS NULL OR TRIM(p_motivo) = '') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Indica el motivo del descarte (se paso, sobro del servicio, se quemo...)',
            'error_code', 'MOTIVO_REQUERIDO'
        );
    END IF;

    SELECT p.denominacion, p.sku INTO v_prod_nombre, v_prod_sku
      FROM app_dat_producto p WHERE p.id = v_t.id_producto;

    v_stock := fn_stock_producto_almacen(v_t.id_producto, v_t.id_almacen);

    -- No se puede botar mas de lo que hay: el resto ya se vendio.
    v_descartar := LEAST(p_descartadas, GREATEST(v_stock, 0));

    IF v_descartar > 0 THEN
        SELECT ip.cantidad_final, ip.id_presentacion, ip.sku_ubicacion
          INTO v_actual, v_presentacion, v_sku_ubicacion
          FROM app_dat_inventario_productos ip
         WHERE ip.id_producto = v_t.id_producto
           AND ip.id_ubicacion = v_t.id_ubicacion
         ORDER BY ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        IF v_presentacion IS NULL THEN
            SELECT pp.id INTO v_presentacion
              FROM app_dat_producto_presentacion pp
             WHERE pp.id_producto = v_t.id_producto
             ORDER BY pp.es_base DESC, pp.id ASC LIMIT 1;
        END IF;

        IF v_presentacion IS NULL THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', v_prod_nombre || ' no tiene presentacion: no se puede registrar el descarte',
                'error_code', 'SIN_PRESENTACION'
            );
        END IF;

        INSERT INTO app_dat_inventario_productos (
            id_producto, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio, created_at
        ) VALUES (
            v_t.id_producto, v_t.id_ubicacion, v_presentacion,
            v_actual, GREATEST(v_actual - v_descartar, 0),
            v_prod_sku,
            COALESCE(v_sku_ubicacion,
                     (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_t.id_ubicacion)),
            5,   -- 5 = merma / ajuste negativo
            now()
        );
    END IF;

    UPDATE app_dat_produccion_tanda
       SET estado = 3,
           porciones_descartadas = v_descartar,
           motivo_descarte = NULLIF(TRIM(COALESCE(p_motivo, '')), ''),
           closed_at = now()
     WHERE id = p_id_tanda;

    RETURN jsonb_build_object(
        'status',            'success',
        'id_tanda',          p_id_tanda,
        'producto',          v_prod_nombre,
        'cocina',            v_t.cocina,
        'producidas',        v_t.porciones_producidas,
        'descartadas',       v_descartar,
        'pedido_descartar',  p_descartadas,
        'acotado_por_stock', v_descartar < p_descartadas,
        'vendidas_estimado', GREATEST(v_t.porciones_producidas - v_descartar, 0),
        'stock_antes',       v_stock,
        'stock_despues',     GREATEST(v_stock - v_descartar, 0),
        'costo_mp',          v_t.costo_mp,
        -- Costo real por porcion SERVIDA: lo que de verdad costo cada plato que
        -- se vendio, incluyendo lo que se boto. Es el numero que dice si vale la
        -- pena producir tandas de este tamano.
        'costo_por_servida',
            CASE WHEN (v_t.porciones_producidas - v_descartar) > 0
                 THEN ROUND(COALESCE(v_t.costo_mp, 0) / (v_t.porciones_producidas - v_descartar), 2)
                 ELSE NULL END,
        'message', CASE WHEN v_descartar > 0
            THEN 'Tanda cerrada. Se descartaron ' || v_descartar || ' porciones de ' || v_prod_nombre
            ELSE 'Tanda de ' || v_prod_nombre || ' cerrada sin merma' END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cerrar_tanda(bigint, numeric, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 21.5 fn_anular_tanda
--
-- Deshacer una produccion: devuelve la materia prima y retira las porciones.
-- Para el caso "me equivoque de plato" o "puse 20 en vez de 2".
--
-- SOLO si no se ha vendido nada del lote. Si ya salieron porciones, revertir
-- descuadraria el inventario: la MP volveria entera pero el producto terminado
-- ya no esta completo. En ese caso el camino es cerrar la tanda declarando la
-- merma, que si es trazable.
--
-- La comprobacion es conservadora: se exige que el stock actual sea >= a las
-- porciones producidas. No es perfecta (podria haber otra tanda del mismo plato)
-- pero falla del lado seguro: ante la duda, no anula.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_anular_tanda(
    p_id_tanda bigint,
    p_motivo   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_t              RECORD;
    v_stock          numeric;
    v_actual         numeric;
    v_presentacion   bigint;
    v_sku_ubicacion  varchar;
    v_prod_nombre    text;
    v_prod_sku       varchar;
    v_ing            RECORD;
    v_ubic_mp        bigint;
    v_devuelto       jsonb := '[]'::jsonb;
    v_salidas        numeric;
BEGIN
    SELECT t.*, c.denominacion AS cocina
      INTO v_t
      FROM app_dat_produccion_tanda t
      JOIN app_dat_cocina c ON c.id = t.id_cocina
     WHERE t.id = p_id_tanda;

    IF v_t.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La tanda no existe',
            'error_code', 'TANDA_NOT_FOUND'
        );
    END IF;

    PERFORM fn_usuario_puede_operar_cocina(v_t.id_cocina, true);

    IF v_t.estado = 4 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La tanda ya estaba anulada',
            'error_code', 'TANDA_YA_ANULADA'
        );
    END IF;

    SELECT p.denominacion, p.sku INTO v_prod_nombre, v_prod_sku
      FROM app_dat_producto p WHERE p.id = v_t.id_producto;

    -- ══════════════════════════════════════════════════════════════════════
    -- CORREGIDO tras probar: la primera version comparaba el stock TOTAL del
    -- plato contra las porciones de la tanda. Con stock previo de otro lote
    -- (10 sobrantes + 4 nuevas - 1 vendida = 13 >= 4) el chequeo pasaba y
    -- anulaba una tanda YA SERVIDA: retiraba 4 porciones cuando solo quedaban 3
    -- de ese lote y devolvia la MP entera. Descuadre en los dos sentidos.
    --
    -- Ahora se mira si hubo SALIDAS del plato en ese almacen DESPUES de la
    -- entrada de la tanda, usando el id de inventario como ancla. Por id y no
    -- por created_at porque now() es constante dentro de una transaccion: una
    -- venta en la misma transaccion tendria el mismo timestamp y se perderia.
    -- ══════════════════════════════════════════════════════════════════════
    SELECT COALESCE(SUM(ip.cantidad_inicial - ip.cantidad_final), 0)
      INTO v_salidas
      FROM app_dat_inventario_productos ip
      JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
     WHERE ip.id_producto = v_t.id_producto
       AND la.id_almacen = v_t.id_almacen
       AND ip.cantidad_final < ip.cantidad_inicial
       AND (CASE WHEN v_t.id_inventario_entrada IS NOT NULL
                 THEN ip.id > v_t.id_inventario_entrada
                 ELSE ip.created_at > v_t.created_at END);

    IF v_salidas > 0 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'Ya salieron ' || v_salidas || ' porciones desde que se creo esta tanda: '
                          || 'no se puede anular. Cierrala declarando la merma en su lugar.',
            'error_code', 'TANDA_YA_CONSUMIDA',
            'producidas', v_t.porciones_producidas,
            'salidas_desde_la_tanda', v_salidas
        );
    END IF;

    v_stock := fn_stock_producto_almacen(v_t.id_producto, v_t.id_almacen);

    -- Salvaguarda adicional: nunca dejar el inventario en negativo.
    IF v_stock < v_t.porciones_producidas THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    'El stock actual (' || v_stock || ') es menor que lo producido ('
                          || v_t.porciones_producidas || '): no se puede anular sin dejar '
                          || 'el inventario en negativo.',
            'error_code', 'TANDA_YA_CONSUMIDA',
            'producidas', v_t.porciones_producidas,
            'stock',      v_stock
        );
    END IF;

    -- Retirar las porciones producidas.
    SELECT ip.cantidad_final, ip.id_presentacion, ip.sku_ubicacion
      INTO v_actual, v_presentacion, v_sku_ubicacion
      FROM app_dat_inventario_productos ip
     WHERE ip.id_producto = v_t.id_producto
       AND ip.id_ubicacion = v_t.id_ubicacion
     ORDER BY ip.id DESC
     LIMIT 1;

    v_actual := COALESCE(v_actual, 0);

    IF v_presentacion IS NULL THEN
        SELECT pp.id INTO v_presentacion
          FROM app_dat_producto_presentacion pp
         WHERE pp.id_producto = v_t.id_producto
         ORDER BY pp.es_base DESC, pp.id ASC LIMIT 1;
    END IF;

    INSERT INTO app_dat_inventario_productos (
        id_producto, id_ubicacion, id_presentacion,
        cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, created_at
    ) VALUES (
        v_t.id_producto, v_t.id_ubicacion, v_presentacion,
        v_actual, GREATEST(v_actual - v_t.porciones_producidas, 0),
        v_prod_sku,
        COALESCE(v_sku_ubicacion,
                 (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_t.id_ubicacion)),
        3,   -- 3 = devolucion / reverso
        now()
    );

    -- Devolver la materia prima, con la MISMA parada de BOM que se uso al
    -- producir: si no, se devolveria arroz crudo que nunca se consumio aqui.
    FOR v_ing IN
        SELECT t.id_ingrediente, t.cantidad_total_necesaria,
               pr.denominacion, pr.sku
          FROM fn_ingredientes_con_parada_tanda(v_t.id_producto, v_t.porciones_producidas) t
          JOIN app_dat_producto pr ON pr.id = t.id_ingrediente
    LOOP
        v_ubic_mp := fn_ubicacion_destino_devolucion(v_ing.id_ingrediente, v_t.id_almacen);

        IF v_ubic_mp IS NULL THEN
            RAISE EXCEPTION 'No hay ubicacion donde devolver % en el almacen %',
                v_ing.denominacion, v_t.id_almacen USING ERRCODE = 'P0001';
        END IF;

        SELECT ip.cantidad_final, ip.id_presentacion, ip.sku_ubicacion
          INTO v_actual, v_presentacion, v_sku_ubicacion
          FROM app_dat_inventario_productos ip
         WHERE ip.id_producto = v_ing.id_ingrediente
           AND ip.id_ubicacion = v_ubic_mp
         ORDER BY ip.id DESC
         LIMIT 1;

        v_actual := COALESCE(v_actual, 0);

        IF v_presentacion IS NULL THEN
            SELECT COALESCE(
                (SELECT ip2.id_presentacion FROM app_dat_inventario_productos ip2
                   JOIN app_dat_layout_almacen la2 ON la2.id = ip2.id_ubicacion
                  WHERE ip2.id_producto = v_ing.id_ingrediente
                    AND la2.id_almacen = v_t.id_almacen
                    AND ip2.id_presentacion IS NOT NULL
                  ORDER BY ip2.id DESC LIMIT 1),
                (SELECT pp.id FROM app_dat_producto_presentacion pp
                  WHERE pp.id_producto = v_ing.id_ingrediente
                  ORDER BY pp.es_base DESC, pp.id ASC LIMIT 1)
            ) INTO v_presentacion;
        END IF;

        IF v_presentacion IS NULL THEN
            RAISE EXCEPTION 'El ingrediente % no tiene presentacion definida',
                v_ing.denominacion USING ERRCODE = 'P0001';
        END IF;

        INSERT INTO app_dat_inventario_productos (
            id_producto, id_ubicacion, id_presentacion,
            cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio, created_at
        ) VALUES (
            v_ing.id_ingrediente, v_ubic_mp, v_presentacion,
            v_actual, v_actual + v_ing.cantidad_total_necesaria,
            v_ing.sku,
            COALESCE(v_sku_ubicacion,
                     (SELECT sku_codigo FROM app_dat_layout_almacen WHERE id = v_ubic_mp)),
            3,   -- 3 = devolucion / reverso
            now()
        );

        v_devuelto := v_devuelto || jsonb_build_object(
            'id_producto', v_ing.id_ingrediente,
            'ingrediente', v_ing.denominacion,
            'devuelto',    v_ing.cantidad_total_necesaria
        );
    END LOOP;

    UPDATE app_dat_produccion_tanda
       SET estado = 4,
           motivo_descarte = NULLIF(TRIM(COALESCE(p_motivo, '')), ''),
           cancelled_at = now()
     WHERE id = p_id_tanda;

    RETURN jsonb_build_object(
        'status',       'success',
        'id_tanda',     p_id_tanda,
        'producto',     v_prod_nombre,
        'cocina',       v_t.cocina,
        'retiradas',    v_t.porciones_producidas,
        'mp_devuelta',  v_devuelto,
        'message',      'Tanda anulada: se retiraron ' || v_t.porciones_producidas
                        || ' porciones y se devolvio la materia prima'
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_anular_tanda(bigint, text)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 21.6 fn_listar_tandas_cocina
--
-- Lo que el jefe de cocina ve en su pantalla de produccion: que lotes hay
-- abiertos, cuantas porciones quedan de cada plato, y el historial del dia.
--
-- Ojo: porciones_restantes NO sale de la tanda, sale del inventario del SKU
-- terminado. Es el stock real, y si hay dos tandas del mismo plato abiertas el
-- valor se repite en ambas (es el stock del plato, no el de cada lote). Se
-- documenta aqui para que la UI no lo sume.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_tandas_cocina(
    p_id_cocina bigint     DEFAULT NULL,
    p_estados   smallint[] DEFAULT ARRAY[1, 2]::smallint[],
    p_dias      integer    DEFAULT 2,
    p_limite    integer    DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_cocinas bigint[];
    v_result  jsonb;
BEGIN
    -- Mismo criterio que el KDS: el alcance lo decide el servidor.
    IF p_id_cocina IS NOT NULL THEN
        PERFORM fn_usuario_puede_operar_cocina(p_id_cocina);
        v_cocinas := ARRAY[p_id_cocina];
    ELSE
        SELECT array_agg(cu.id_cocina) INTO v_cocinas
          FROM fn_cocinas_del_usuario() cu;
    END IF;

    IF v_cocinas IS NULL OR array_length(v_cocinas, 1) IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'tandas', '[]'::jsonb, 'total', 0,
            'message', 'No tienes cocinas asignadas'
        );
    END IF;

    SELECT COALESCE(jsonb_agg(q.t ORDER BY q.creado DESC), '[]'::jsonb)
      INTO v_result
      FROM (
        SELECT t.created_at AS creado,
               jsonb_build_object(
                 'id',            t.id,
                 'id_cocina',     t.id_cocina,
                 'cocina',        c.denominacion,
                 'id_producto',   t.id_producto,
                 'producto',      p.denominacion,
                 'sku',           p.sku,
                 'producidas',    t.porciones_producidas,
                 'descartadas',   t.porciones_descartadas,
                 'estado',        t.estado,
                 'estado_texto',  CASE t.estado
                                    WHEN 1 THEN 'Abierta'
                                    WHEN 2 THEN 'Agotada'
                                    WHEN 3 THEN 'Cerrada'
                                    WHEN 4 THEN 'Anulada'
                                  END,
                 -- Stock real del SKU terminado en el almacen de la cocina.
                 -- Con dos tandas abiertas del mismo plato este valor se repite:
                 -- es el stock del producto, no el del lote. La UI no debe sumarlo.
                 'porciones_restantes',
                     CASE WHEN t.estado IN (3, 4) THEN 0
                          ELSE fn_stock_producto_almacen(t.id_producto, t.id_almacen)
                     END,
                 'costo_mp',      t.costo_mp,
                 'costo_por_porcion',
                     CASE WHEN t.porciones_producidas > 0
                          THEN ROUND(COALESCE(t.costo_mp, 0) / t.porciones_producidas, 2)
                          ELSE NULL END,
                 'notas',           t.notas,
                 'motivo_descarte', t.motivo_descarte,
                 'uuid_usuario',    t.uuid_usuario,
                 'producido_por',
                     COALESCE(NULLIF(TRIM(COALESCE(tr.nombres, '') || ' ' || COALESCE(tr.apellidos, '')), ''),
                              'Sin identificar'),
                 'created_at',    t.created_at,
                 'closed_at',     t.closed_at,
                 'minutos_abierta',
                     GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (
                         COALESCE(t.closed_at, t.cancelled_at, now()) - t.created_at)) / 60))::integer
               ) AS t
          FROM app_dat_produccion_tanda t
          JOIN app_dat_cocina c   ON c.id = t.id_cocina
          JOIN app_dat_producto p ON p.id = t.id_producto
          LEFT JOIN app_dat_jefe_cocina jc
                 ON jc.uuid = t.uuid_usuario AND jc.id_cocina = t.id_cocina
          LEFT JOIN app_dat_trabajadores tr ON tr.id = jc.id_trabajador
         WHERE t.id_cocina = ANY(v_cocinas)
           AND t.estado = ANY(p_estados)
           AND t.created_at >= now() - (COALESCE(p_dias, 2) || ' days')::interval
         ORDER BY t.created_at DESC
         LIMIT p_limite
      ) q;

    RETURN jsonb_build_object(
        'status',  'success',
        'tandas',  v_result,
        'total',   jsonb_array_length(v_result),
        'cocinas', to_jsonb(v_cocinas)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_tandas_cocina(bigint, smallint[], integer, integer)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 21.7 fn_platos_por_tanda_cocina
--
-- Catalogo de la pantalla de produccion: que platos por_tanda tiene esta cocina,
-- cuantas porciones quedan y cuantas se PODRIAN producir con la MP que hay.
--
-- El maximo producible es el minimo sobre los ingredientes de
-- floor(stock / cantidad_necesaria), con la parada de BOM aplicada. Es el mismo
-- calculo que hace fn_disponibilidad_plato para al_pedido, pero aqui responde
-- otra pregunta: no "cuantos puedo vender" sino "cuantos puedo cocinar".
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_platos_por_tanda_cocina(
    p_id_cocina bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_almacen bigint;
    v_cocina  text;
    v_p       RECORD;
    v_ing     RECORD;
    v_max     numeric;
    v_posible numeric;
    v_stock   numeric;
    v_items   jsonb := '[]'::jsonb;
    v_falta   jsonb;
BEGIN
    SELECT c.id_almacen, c.denominacion INTO v_almacen, v_cocina
      FROM app_dat_cocina c
     WHERE c.id = p_id_cocina AND c.deleted_at IS NULL;

    IF v_almacen IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cocina no existe',
            'error_code', 'COCINA_NOT_FOUND'
        );
    END IF;

    PERFORM fn_usuario_puede_operar_cocina(p_id_cocina);

    FOR v_p IN
        SELECT p.id, p.denominacion, p.sku
          FROM app_dat_producto p
         WHERE p.id_cocina = p_id_cocina
           AND COALESCE(p.modo_elaboracion, 'al_pedido') = 'por_tanda'
         ORDER BY p.denominacion
    LOOP
        v_max := NULL;
        v_falta := NULL;

        FOR v_ing IN
            SELECT t.id_ingrediente, t.cantidad_total_necesaria, t.es_por_tanda,
                   pr.denominacion
              FROM fn_ingredientes_con_parada_tanda(v_p.id, 1) t
              JOIN app_dat_producto pr ON pr.id = t.id_ingrediente
        LOOP
            IF v_ing.cantidad_total_necesaria > 0 THEN
                v_stock := fn_stock_producto_almacen(v_ing.id_ingrediente, v_almacen);
                v_posible := FLOOR(v_stock / v_ing.cantidad_total_necesaria);

                IF v_max IS NULL OR v_posible < v_max THEN
                    v_max := v_posible;
                    -- Guardar el ingrediente que limita: es lo que el jefe
                    -- necesita saber para pedir al almacen.
                    v_falta := jsonb_build_object(
                        'ingrediente', v_ing.denominacion,
                        'stock',       v_stock,
                        'por_porcion', v_ing.cantidad_total_necesaria
                    );
                END IF;
            END IF;
        END LOOP;

        v_items := v_items || jsonb_build_object(
            'id_producto',         v_p.id,
            'producto',            v_p.denominacion,
            'sku',                 v_p.sku,
            'porciones_hechas',    fn_stock_producto_almacen(v_p.id, v_almacen),
            'max_producible',      COALESCE(v_max, 0),
            'ingrediente_limite',  v_falta,
            'tiene_receta',        v_max IS NOT NULL,
            'tanda_abierta', (
                SELECT t.id FROM app_dat_produccion_tanda t
                 WHERE t.id_producto = v_p.id AND t.id_cocina = p_id_cocina
                   AND t.estado = 1
                 ORDER BY t.created_at DESC LIMIT 1
            )
        );
    END LOOP;

    RETURN jsonb_build_object(
        'status',    'success',
        'id_cocina', p_id_cocina,
        'cocina',    v_cocina,
        'platos',    v_items,
        'total',     jsonb_array_length(v_items)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_platos_por_tanda_cocina(bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) La tabla y sus checks
SELECT c.relname AS tabla,
       (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columnas
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'app_dat_produccion_tanda';

SELECT conname, pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
 WHERE conrelid = 'public.app_dat_produccion_tanda'::regclass
 ORDER BY conname;

-- (b) Las 5 funciones nuevas, todas SECURITY DEFINER salvo el helper de BOM
SELECT p.oid::regprocedure AS firma, p.prosecdef AS sec_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_ingredientes_con_parada_tanda', 'fn_producir_tanda',
                     'fn_cerrar_tanda', 'fn_anular_tanda',
                     'fn_listar_tandas_cocina', 'fn_platos_por_tanda_cocina')
 ORDER BY p.proname;

-- (c) La parada de BOM debe estar en el helper -> true
SELECT (p.prosrc LIKE '%<> ''por_tanda''%') AS tiene_parada
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_ingredientes_con_parada_tanda';

-- (d) fn_obtener_ingredientes_recursivos NO debe haberse tocado: no conoce
--     modo_elaboracion. Si esto sale true, algo la modifico por error.
SELECT (p.prosrc LIKE '%modo_elaboracion%') AS ojo_fue_modificada
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_obtener_ingredientes_recursivos';
