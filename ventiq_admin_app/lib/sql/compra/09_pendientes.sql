-- ============================================================================
-- 09_pendientes.sql — Fase 9: pendientes de recepción, historial de
-- recepciones y vista de facturas (solo lectura)
--
-- REQUIERE: 01 (motor de dinero), 02, 03a/03b (compras), 04 (reserva/pago),
--           05a (recepción), 06a-06d (costo aterrizado y ajustes) y 08
--           (reportes). Todo aplicado en `newa` (qhprswhhfasrikhawjoz) antes de
--           este script.
--
-- Qué crea (4 funciones STABLE SECURITY DEFINER que NO escriben nada):
--
--   1  fn_fdi_pendientes_panel(bigint, text)
--      El panel de compras ABIERTAS (`creada`, `reservada`, `pagada`,
--      `entrega_parcial`) con lo pedido, lo recibido, lo que falta y la
--      antigüedad. `completada`, `cancelada` y `anulada` no aparecen: esas
--      compras ya no tienen nada pendiente (o ya no existen como obligación).
--      Orden: 'antiguedad' (más vieja primero) o 'monto' (más pendiente
--      primero). Cualquier otro valor revienta con 22023.
--
--   2  fn_fdi_pendientes_detalle(bigint, bigint)
--      El desglose por línea de UNA compra, con las mismas cifras que el
--      panel para que la pantalla de detalle cuadre con la fila del panel.
--      Valida que la compra sea de la tienda pedida (42501 si no).
--
--   3  fn_fdi_recepciones_historial(bigint, date, date)
--      El histórico de recepciones (una fila por vínculo
--      `fdi_dat_compra_recepcion`), con el estado de su operación y un texto
--      corto de productos, para exportar. Filtro opcional por fecha.
--
--   4  fn_fdi_facturas(bigint, date, date)
--      La vista de facturas con su estado de recepción, INCLUYENDO las
--      compras cerradas: es el listado documental, no el de trabajo.
--
-- Reglas que respeta:
--   · Nunca suma monedas distintas: todo agregado va por moneda y cada
--     importe viaja con la suya. No hay un «total» multimoneda.
--   · Solo lectura: STABLE (no puede escribir) + SECURITY DEFINER.
--   · Control de acceso con `fn_user_can_access_tienda(p_id_tienda)`. Sin
--     sesión (`auth.uid()` NULL: service_role / editor SQL) se permite, igual
--     que el resto del módulo.
--   · REVOKE de PUBLIC y `anon`; GRANT solo a `authenticated`.
--   · Idempotente: CREATE OR REPLACE y ningún DDL que dependa del estado
--     previo (no hay tablas nuevas, ni columnas, ni datos).
--
-- CRITERIO DE SALIDA DEL PLAN (el invariante que vigila el verify):
--   pendiente(línea)      = cantidad − recibido, acotado a 0 por línea
--   monto_pendiente(línea) = pendiente × costo_unitario
--   monto_pendiente(compra) = Σ monto_pendiente de sus líneas
--   recibido_pct          = Σ recibido / Σ pedido, acotado a [0, 1] (razón,
--                           sin moneda)
--
-- DECISIONES QUE CONVIENE TENER A LA VISTA:
--   · El acotado a 0 es POR LÍNEA, no sobre el total. Una sobre-recepción en
--     una línea no puede «cancelar» lo que falta en otra; si se acotara el
--     total, un exceso taparía un pendiente real. Hoy ningún dato está
--     sobre-recibido, así que ambas lecturas coinciden; cuando dejen de
--     coincidir, vale la de por línea.
--   · `monto_total` del panel es Σ `costo_linea` (COALESCE a
--     cantidad × costo_unitario si viniera nulo), no `total_mercancia`: así el
--     panel y su detalle suman exactamente lo mismo, línea a línea.
--   · `dias_antiguedad` y `dias_sin_movimiento` van con GREATEST(0, …) para
--     que un `created_at` futuro (reloj) no produzca una antigüedad negativa.
--     No cambia ningún dato real (las compras de hoy dan 0..3 días).
--   · `dias_sin_movimiento` se cuenta desde la última recepción de la compra
--     (o de la línea, en el detalle) o, si nunca se recibió nada, desde el
--     `created_at` de la compra.
--   · `variante`: `app_dat_variantes` NO guarda un nombre propio (solo
--     `id_sub_categoria` e `id_atributo`), así que la etiqueta es la
--     denominación del atributo; NULL si no resuelve. `presentacion` sale de
--     `app_dat_producto_presentacion` → `app_nom_presentacion`. En los datos
--     reales de `newa` `id_variante` e `id_presentacion` son NULL en todas las
--     líneas, así que hoy ambas columnas vuelven NULL (y el LEFT JOIN no se
--     come ninguna línea).
--   · `estado_operacion` del histórico es el `estado` (smallint) de la fila de
--     `app_dat_estado_operacion` con `id` MAYOR para la operación — el estado
--     de la operación es la última fila, no la de mayor `created_at`. Se
--     devuelve además `estado_operacion_nombre` desde
--     `app_nom_estado_operacion` para que la UI no tenga que adivinarlo.
--   · `productos` del histórico: el primero por nombre y «+N» con los demás
--     distintos; NULL si la recepción no tiene líneas con producto resoluble.
--   · `moneda` del histórico puede ser NULL en la tabla; se agrupa tal cual
--     (NULL es «moneda desconocida», no una moneda más). Hoy todas son USD.
--
-- ROLLBACK: 09_pendientes_rollback.sql (solo `DROP FUNCTION`).
-- VERIFY:   verify/09_pendientes.sql (solo lectura, una sola sentencia).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Preflight: sin estas piezas las funciones no se pueden construir
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_linea;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion_linea;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_pago;';
    END IF;
    IF to_regclass('public.app_dat_operaciones') IS NULL THEN
        v_falta := v_falta || ' app_dat_operaciones;';
    END IF;
    IF to_regclass('public.app_dat_estado_operacion') IS NULL THEN
        v_falta := v_falta || ' app_dat_estado_operacion;';
    END IF;
    IF to_regclass('public.app_dat_producto') IS NULL THEN
        v_falta := v_falta || ' app_dat_producto;';
    END IF;
    IF to_regclass('public.app_dat_variantes') IS NULL THEN
        v_falta := v_falta || ' app_dat_variantes;';
    END IF;
    IF to_regclass('public.app_dat_atributos') IS NULL THEN
        v_falta := v_falta || ' app_dat_atributos;';
    END IF;
    IF to_regclass('public.app_dat_producto_presentacion') IS NULL THEN
        v_falta := v_falta || ' app_dat_producto_presentacion;';
    END IF;
    IF to_regclass('public.app_nom_presentacion') IS NULL THEN
        v_falta := v_falta || ' app_nom_presentacion;';
    END IF;
    IF to_regclass('public.app_nom_estado_operacion') IS NULL THEN
        v_falta := v_falta || ' app_nom_estado_operacion;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '09: faltan tablas:%.', v_falta USING ERRCODE = '42P01';
    END IF;

    IF to_regprocedure('public.fn_user_can_access_tienda(bigint)') IS NULL THEN
        RAISE EXCEPTION '09: falta fn_user_can_access_tienda(bigint).' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Panel de compras abiertas
-- ---------------------------------------------------------------------------
-- Estados abiertos: la compra existe, se puede recibir y todavía le falta
-- mercancía (o al menos no se declaró cerrada). `completada`, `cancelada` y
-- `anulada` quedan fuera por definición.
--
-- `recibido` sale de `fdi_dat_compra_recepcion_linea.cantidad_recibida`
-- (el vínculo real de la recepción con la línea), no de una columna agregada
-- de la compra: así el panel, el detalle y `fn_fdi_compra_recepcion_pendiente`
-- hablan del mismo número.
--
-- `ultima_recepcion` es la fecha del vínculo (`fdi_dat_compra_recepcion`) más
-- reciente de la compra; NULL si nunca se recibió nada.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_pendientes_panel(
    p_id_tienda bigint,
    p_orden     text DEFAULT 'antiguedad'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_orden text := lower(COALESCE(p_orden, 'antiguedad'));
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    IF v_orden NOT IN ('antiguedad', 'monto') THEN
        RAISE EXCEPTION 'Orden % no válido para el panel: use ''antiguedad'' o ''monto''', p_orden
            USING ERRCODE = '22023';
    END IF;

    RETURN (
        WITH abiertas AS (
            SELECT c.id,
                   c.numero_compra,
                   c.numero_factura,
                   c.fecha_factura,
                   c.estado,
                   c.moneda_total,
                   c.created_at,
                   pr.denominacion AS proveedor
              FROM public.fdi_dat_compra c
              LEFT JOIN public.app_dat_proveedor pr ON pr.id = c.id_proveedor
             WHERE c.id_tienda = p_id_tienda
               AND c.estado IN ('creada', 'reservada', 'pagada', 'entrega_parcial')
        ),
        lineas AS (
            SELECT l.id_compra,
                   l.cantidad,
                   l.costo_unitario,
                   COALESCE(l.costo_linea, l.cantidad * l.costo_unitario) AS costo_linea,
                   COALESCE(rl.recibido, 0) AS recibido
              FROM public.fdi_dat_compra_linea l
              JOIN abiertas a ON a.id = l.id_compra
              LEFT JOIN LATERAL (
                    SELECT sum(x.cantidad_recibida) AS recibido
                      FROM public.fdi_dat_compra_recepcion_linea x
                     WHERE x.id_compra_linea = l.id) rl ON TRUE
        ),
        recepciones AS (
            SELECT r.id_compra, max(r.created_at) AS ultima
              FROM public.fdi_dat_compra_recepcion r
              JOIN abiertas a ON a.id = r.id_compra
             GROUP BY 1
        ),
        filas AS (
            SELECT a.id AS id_compra,
                   a.numero_compra,
                   a.numero_factura,
                   a.proveedor,
                   a.fecha_factura,
                   a.estado,
                   a.moneda_total AS moneda,
                   GREATEST(0, CURRENT_DATE - a.created_at::date) AS dias_antiguedad,
                   count(l.id_compra) AS lineas,
                   round(COALESCE(sum(l.cantidad), 0), 4) AS pedido,
                   round(COALESCE(sum(l.recibido), 0), 4) AS recibido,
                   round(COALESCE(sum(l.costo_linea), 0), 2) AS monto_total,
                   round(COALESCE(sum(GREATEST(0, l.cantidad - l.recibido) * l.costo_unitario), 0), 2)
                       AS monto_pendiente,
                   r.ultima AS ultima_recepcion,
                   GREATEST(0, CURRENT_DATE - COALESCE(r.ultima::date, a.created_at::date))
                       AS dias_sin_movimiento
              FROM abiertas a
              LEFT JOIN lineas l       ON l.id_compra = a.id
              LEFT JOIN recepciones r  ON r.id_compra = a.id
             GROUP BY a.id, a.numero_compra, a.numero_factura, a.proveedor,
                      a.fecha_factura, a.estado, a.moneda_total, a.created_at, r.ultima
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'orden', v_orden,
            'generado_at', now(),
            'compras', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra', f.id_compra,
                           'numero_compra', f.numero_compra,
                           'numero_factura', f.numero_factura,
                           'proveedor', f.proveedor,
                           'fecha_factura', f.fecha_factura,
                           'estado', f.estado,
                           'moneda', f.moneda,
                           'dias_antiguedad', f.dias_antiguedad,
                           'lineas', f.lineas,
                           'pedido', f.pedido,
                           'recibido', f.recibido,
                           'recibido_pct', CASE WHEN f.pedido > 0
                                                THEN LEAST(1, round(f.recibido / f.pedido, 6))
                                                ELSE 0 END,
                           'monto_total', f.monto_total,
                           'monto_pendiente', f.monto_pendiente,
                           'ultima_recepcion', f.ultima_recepcion,
                           'dias_sin_movimiento', f.dias_sin_movimiento)
                       ORDER BY CASE WHEN v_orden = 'monto'
                                     THEN f.monto_pendiente
                                     ELSE f.dias_antiguedad::numeric END DESC,
                                f.monto_pendiente DESC,
                                f.id_compra)
                   FROM filas f
            ), '[]'::jsonb),
            -- Un objeto por moneda. No hay total multimoneda a propósito.
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'compras', t.compras,
                           'monto_total', t.monto_total,
                           'monto_pendiente', t.monto_pendiente)
                       ORDER BY t.moneda NULLS LAST)
                  FROM (
                        SELECT moneda,
                               count(*) AS compras,
                               round(sum(monto_total), 2) AS monto_total,
                               round(sum(monto_pendiente), 2) AS monto_pendiente
                          FROM filas
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_pendientes_panel(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_pendientes_panel(bigint, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) Detalle por línea de una compra
-- ---------------------------------------------------------------------------
-- Mismas fórmulas que el panel, línea a línea, para que
-- Σ `monto_pendiente` del detalle = `monto_pendiente` de la fila del panel.
-- La cabecera repite los agregados de la compra (pedido, recibido, pct,
-- montos) para que la pantalla de detalle no dependa de dos llamadas.
--
-- `ultima_recepcion` de la línea es la fecha del vínculo más reciente de esa
-- línea; `dias_sin_movimiento` cuenta desde ahí o, si nunca se recibió, desde
-- el `created_at` de la compra (el mismo criterio que el panel).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_pendientes_detalle(
    p_id_tienda bigint,
    p_id_compra bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_compra record;
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_compra
      FROM public.fdi_dat_compra c
     WHERE c.id = p_id_compra;

    IF v_compra.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;

    IF v_compra.id_tienda IS DISTINCT FROM p_id_tienda THEN
        RAISE EXCEPTION 'Sin acceso a la compra % de la tienda %',
            p_id_compra, p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH base AS (
            SELECT c.id,
                   c.numero_compra,
                   c.numero_factura,
                   c.fecha_factura,
                   c.estado,
                   c.moneda_total,
                   c.tasa_factura,
                   c.total_mercancia,
                   c.total_ajustes,
                   c.total_financiado,
                   c.costo_aterrizado,
                   c.observacion,
                   c.created_at,
                   pr.denominacion AS proveedor
              FROM public.fdi_dat_compra c
              LEFT JOIN public.app_dat_proveedor pr ON pr.id = c.id_proveedor
             WHERE c.id = p_id_compra
        ),
        lineas AS (
            SELECT l.id AS id_compra_linea,
                   COALESCE(pr.denominacion, 'Producto ' || l.id_producto::text) AS producto,
                   (SELECT a.denominacion
                      FROM public.app_dat_variantes v
                      JOIN public.app_dat_atributos a ON a.id = v.id_atributo
                     WHERE v.id = l.id_variante) AS variante,
                   (SELECT np.denominacion
                      FROM public.app_dat_producto_presentacion pp
                      JOIN public.app_nom_presentacion np ON np.id = pp.id_presentacion
                     WHERE pp.id = l.id_presentacion) AS presentacion,
                   l.id_almacen,
                   l.id_ubicacion,
                   l.cantidad,
                   l.costo_unitario,
                   COALESCE(l.costo_linea, l.cantidad * l.costo_unitario) AS costo_linea,
                   COALESCE(rl.recibido, 0) AS recibido,
                   rl.ultima AS ultima_recepcion
              FROM public.fdi_dat_compra_linea l
              LEFT JOIN public.app_dat_producto pr ON pr.id = l.id_producto
              LEFT JOIN LATERAL (
                    SELECT sum(x.cantidad_recibida) AS recibido,
                           max(rc.created_at) AS ultima
                      FROM public.fdi_dat_compra_recepcion_linea x
                      JOIN public.fdi_dat_compra_recepcion rc ON rc.id = x.id_compra_recepcion
                     WHERE x.id_compra_linea = l.id) rl ON TRUE
             WHERE l.id_compra = p_id_compra
        ),
        calc AS (
            SELECT y.*,
                   round(GREATEST(0, y.cantidad - y.recibido), 4) AS pendiente,
                   round(GREATEST(0, y.cantidad - y.recibido) * y.costo_unitario, 2) AS monto_pendiente
              FROM lineas y
        ),
        resumen AS (
            SELECT count(*) AS lineas,
                   round(COALESCE(sum(cantidad), 0), 4) AS pedido,
                   round(COALESCE(sum(recibido), 0), 4) AS recibido,
                   round(COALESCE(sum(costo_linea), 0), 2) AS monto_total,
                   round(COALESCE(sum(monto_pendiente), 0), 2) AS monto_pendiente,
                   max(ultima_recepcion) AS ultima_recepcion
              FROM calc
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'compra', jsonb_build_object(
                'id_compra', b.id,
                'numero_compra', b.numero_compra,
                'numero_factura', b.numero_factura,
                'proveedor', b.proveedor,
                'fecha_factura', b.fecha_factura,
                'estado', b.estado,
                'moneda', b.moneda_total,
                'tasa_factura', b.tasa_factura,
                'total_mercancia', b.total_mercancia,
                'total_ajustes', b.total_ajustes,
                'total_financiado', b.total_financiado,
                'costo_aterrizado', b.costo_aterrizado,
                'observacion', b.observacion,
                'created_at', b.created_at,
                'dias_antiguedad', GREATEST(0, CURRENT_DATE - b.created_at::date),
                'lineas', r.lineas,
                'pedido', r.pedido,
                'recibido', r.recibido,
                'recibido_pct', CASE WHEN r.pedido > 0
                                     THEN LEAST(1, round(r.recibido / r.pedido, 6))
                                     ELSE 0 END,
                'monto_total', r.monto_total,
                'monto_pendiente', r.monto_pendiente,
                'ultima_recepcion', r.ultima_recepcion,
                'dias_sin_movimiento',
                    GREATEST(0, CURRENT_DATE - COALESCE(r.ultima_recepcion::date, b.created_at::date))),
            'lineas', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra_linea', c.id_compra_linea,
                           'producto', c.producto,
                           'variante', c.variante,
                           'presentacion', c.presentacion,
                           'id_almacen', c.id_almacen,
                           'id_ubicacion', c.id_ubicacion,
                           'cantidad', c.cantidad,
                           'recibido', c.recibido,
                           'pendiente', c.pendiente,
                           'costo_unitario', c.costo_unitario,
                           'monto_pendiente', c.monto_pendiente,
                           'ultima_recepcion', c.ultima_recepcion,
                           'dias_sin_movimiento',
                               GREATEST(0, CURRENT_DATE
                                            - COALESCE(c.ultima_recepcion::date, b.created_at::date)))
                       ORDER BY c.id_compra_linea)
                   FROM calc c
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', b.moneda_total,
                           'lineas', r.lineas,
                           'monto_total', r.monto_total,
                           'monto_pendiente', r.monto_pendiente))
                   FROM base b CROSS JOIN resumen r
            ), '[]'::jsonb)
        )
        FROM base b CROSS JOIN resumen r
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_pendientes_detalle(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_pendientes_detalle(bigint, bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Histórico de recepciones (para exportar)
-- ---------------------------------------------------------------------------
-- Una fila por vínculo `fdi_dat_compra_recepcion` (una recepción puede cubrir
-- varias líneas de la compra; aquí se agregan).
--
-- `estado_operacion` es el `estado` de la fila con `id` MÁS ALTO de
-- `app_dat_estado_operacion` para la operación — el estado vigente es la última
-- fila escrita, no la de mayor fecha. Si la operación no tiene ninguna fila,
-- ambas columnas vuelven NULL (no se inventa «pendiente»).
--
-- `fecha` es la fecha del vínculo (`created_at::date`) y es también el campo
-- por el que filtra `p_desde`/`p_hasta`. `fecha_operacion` es el `created_at`
-- de la operación, que puede ser anterior.
--
-- `productos` es un texto corto para la exportación: el primer producto por
-- nombre y «+N» con el resto de productos distintos de la recepción.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_recepciones_historial(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH recepciones AS (
            SELECT r.id,
                   r.id_compra,
                   r.id_operacion,
                   r.created_at,
                   r.monto_valorizado,
                   r.moneda,
                   r.origen_pago,
                   r.pct_importadora,
                   r.monto_importadora,
                   c.numero_compra,
                   c.numero_factura,
                   pr.denominacion AS proveedor,
                   o.created_at AS fecha_operacion,
                   (SELECT e.estado
                      FROM public.app_dat_estado_operacion e
                     WHERE e.id_operacion = r.id_operacion
                     ORDER BY e.id DESC
                     LIMIT 1) AS estado_operacion,
                   (SELECT ne.denominacion
                      FROM public.app_dat_estado_operacion e
                      JOIN public.app_nom_estado_operacion ne ON ne.id = e.estado
                     WHERE e.id_operacion = r.id_operacion
                     ORDER BY e.id DESC
                     LIMIT 1) AS estado_operacion_nombre
              FROM public.fdi_dat_compra_recepcion r
              LEFT JOIN public.fdi_dat_compra c ON c.id = r.id_compra
              LEFT JOIN public.app_dat_proveedor pr ON pr.id = c.id_proveedor
              LEFT JOIN public.app_dat_operaciones o ON o.id = r.id_operacion
             WHERE r.id_tienda = p_id_tienda
               AND (p_desde IS NULL OR r.created_at::date >= p_desde)
               AND (p_hasta IS NULL OR r.created_at::date <= p_hasta)
        ),
        filas AS (
            SELECT x.*,
                   (SELECT count(*)
                      FROM public.fdi_dat_compra_recepcion_linea rl
                     WHERE rl.id_compra_recepcion = x.id) AS lineas,
                   (SELECT round(COALESCE(sum(rl.cantidad_recibida), 0), 4)
                      FROM public.fdi_dat_compra_recepcion_linea rl
                     WHERE rl.id_compra_recepcion = x.id) AS cantidad_recibida,
                   (SELECT CASE
                               WHEN count(DISTINCT p.denominacion) = 0 THEN NULL
                               WHEN count(DISTINCT p.denominacion) = 1 THEN min(p.denominacion)
                               ELSE min(p.denominacion)
                                    || ' +' || (count(DISTINCT p.denominacion) - 1)::text
                           END
                      FROM public.fdi_dat_compra_recepcion_linea rl
                      JOIN public.fdi_dat_compra_linea l ON l.id = rl.id_compra_linea
                      LEFT JOIN public.app_dat_producto p ON p.id = l.id_producto
                     WHERE rl.id_compra_recepcion = x.id) AS productos
              FROM recepciones x
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', p_desde,
            'hasta', p_hasta,
            'generado_at', now(),
            'recepciones', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_recepcion', f.id,
                           'id_operacion', f.id_operacion,
                           'fecha', f.created_at::date,
                           'numero_compra', f.numero_compra,
                           'numero_factura', f.numero_factura,
                           'proveedor', f.proveedor,
                           'monto_valorizado', f.monto_valorizado,
                           'moneda', f.moneda,
                           'origen_pago', f.origen_pago,
                           'pct_importadora', f.pct_importadora,
                           'monto_importadora', f.monto_importadora,
                           'estado_operacion', f.estado_operacion,
                           'estado_operacion_nombre', f.estado_operacion_nombre,
                           'lineas', f.lineas,
                           'cantidad_recibida', f.cantidad_recibida,
                           'productos', f.productos,
                           'fecha_operacion', f.fecha_operacion)
                       ORDER BY f.created_at DESC, f.id DESC)
                   FROM filas f
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'recepciones', t.recepciones,
                           'monto_valorizado', t.monto_valorizado,
                           'monto_importadora', t.monto_importadora,
                           'cantidad_recibida', t.cantidad_recibida)
                       ORDER BY t.moneda NULLS LAST)
                  FROM (
                        SELECT moneda,
                               count(*) AS recepciones,
                               round(sum(monto_valorizado), 2) AS monto_valorizado,
                               round(sum(monto_importadora), 2) AS monto_importadora,
                               round(sum(cantidad_recibida), 4) AS cantidad_recibida
                          FROM filas
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_recepciones_historial(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_recepciones_historial(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Vista de facturas con su estado de recepción
-- ---------------------------------------------------------------------------
-- Lista TODAS las compras de la tienda (incluidas `completada`, `cancelada` y
-- `anulada`): es la vista documental de facturas, no el panel de trabajo.
--
-- `total_factura` es `total_mercancia` y `aterrizado` es `costo_aterrizado`:
-- las dos columnas que ya usa R3 (`fn_fdi_reporte_compras`), ambas en la
-- moneda de la compra.
--
-- `pagado` = Σ `monto_eq_total` de los pagos, que ya está en la moneda de la
-- compra y por eso es lo único comparable con las dos anteriores. NO se suma
-- el importe nativo de pagos en otras monedas: eso queda en R5 por moneda de
-- pago.
--
-- `estado_recepcion`: 'sin recibir' si no hay nada recibido, 'completa' si lo
-- recibido cubre lo pedido (una sobre-recepción también es completa) y
-- 'parcial' en el resto.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_facturas(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH compras AS (
            SELECT c.id,
                   c.numero_compra,
                   c.numero_factura,
                   c.fecha_factura,
                   c.estado,
                   c.moneda_total,
                   c.total_mercancia,
                   c.costo_aterrizado,
                   pr.denominacion AS proveedor
              FROM public.fdi_dat_compra c
              LEFT JOIN public.app_dat_proveedor pr ON pr.id = c.id_proveedor
             WHERE c.id_tienda = p_id_tienda
               AND (p_desde IS NULL OR c.fecha_factura >= p_desde)
               AND (p_hasta IS NULL OR c.fecha_factura <= p_hasta)
        ),
        pedido AS (
            SELECT l.id_compra, sum(l.cantidad) AS cantidad
              FROM public.fdi_dat_compra_linea l
              JOIN compras c ON c.id = l.id_compra
             GROUP BY 1
        ),
        recibido AS (
            SELECT l.id_compra, sum(rl.cantidad_recibida) AS cantidad
              FROM public.fdi_dat_compra_recepcion_linea rl
              JOIN public.fdi_dat_compra_linea l ON l.id = rl.id_compra_linea
              JOIN compras c ON c.id = l.id_compra
             GROUP BY 1
        ),
        pagos AS (
            SELECT p.id_compra, sum(p.monto_eq_total) AS pagado
              FROM public.fdi_dat_compra_pago p
              JOIN compras c ON c.id = p.id_compra
             GROUP BY 1
        ),
        recepciones AS (
            SELECT r.id_compra, count(*) AS n, max(r.created_at) AS ultima
              FROM public.fdi_dat_compra_recepcion r
              JOIN compras c ON c.id = r.id_compra
             GROUP BY 1
        ),
        filas AS (
            SELECT c.id AS id_compra,
                   c.numero_factura,
                   c.numero_compra,
                   c.proveedor,
                   c.fecha_factura,
                   c.estado,
                   c.moneda_total AS moneda,
                   round(c.total_mercancia, 2) AS total_factura,
                   round(c.costo_aterrizado, 2) AS aterrizado,
                   round(COALESCE(p.pagado, 0), 2) AS pagado,
                   COALESCE(r.n, 0) AS recepciones,
                   r.ultima AS ultima_recepcion,
                   round(COALESCE(pd.cantidad, 0), 4) AS pedido,
                   round(COALESCE(rc.cantidad, 0), 4) AS recibido
              FROM compras c
              LEFT JOIN pedido pd      ON pd.id_compra = c.id
              LEFT JOIN recibido rc    ON rc.id_compra = c.id
              LEFT JOIN pagos p        ON p.id_compra = c.id
              LEFT JOIN recepciones r  ON r.id_compra = c.id
        ),
        calc AS (
            SELECT f.*,
                   CASE WHEN f.pedido > 0
                        THEN LEAST(1, round(f.recibido / f.pedido, 6))
                        ELSE 0 END AS recibido_pct,
                   CASE WHEN f.recibido <= 0 THEN 'sin recibir'
                        WHEN f.pedido > 0 AND f.recibido >= f.pedido THEN 'completa'
                        ELSE 'parcial' END AS estado_recepcion
              FROM filas f
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', p_desde,
            'hasta', p_hasta,
            'generado_at', now(),
            'facturas', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra', x.id_compra,
                           'numero_factura', x.numero_factura,
                           'numero_compra', x.numero_compra,
                           'proveedor', x.proveedor,
                           'fecha_factura', x.fecha_factura,
                           'estado', x.estado,
                           'moneda', x.moneda,
                           'total_factura', x.total_factura,
                           'aterrizado', x.aterrizado,
                           'pagado', x.pagado,
                           'recepciones', x.recepciones,
                           'recibido_pct', x.recibido_pct,
                           'estado_recepcion', x.estado_recepcion,
                           'ultima_recepcion', x.ultima_recepcion)
                       ORDER BY x.fecha_factura DESC NULLS LAST, x.numero_compra DESC, x.id_compra DESC)
                   FROM calc x
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'compras', t.compras,
                           'total_factura', t.total_factura,
                           'aterrizado', t.aterrizado,
                           'pagado', t.pagado)
                       ORDER BY t.moneda NULLS LAST)
                  FROM (
                        SELECT moneda,
                               count(*) AS compras,
                               round(sum(total_factura), 2) AS total_factura,
                               round(sum(aterrizado), 2) AS aterrizado,
                               round(sum(pagado), 2) AS pagado
                          FROM calc
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_facturas(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_facturas(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) Verificación del script
-- ---------------------------------------------------------------------------
-- Comprueba lo que el script promete: las 4 funciones con su firma exacta,
-- STABLE, SECURITY DEFINER, jsonb, ejecutables por `authenticated` y no por
-- `anon`, con sus DEFAULT; que responden sobre datos reales sin romperse; y
-- las dos pruebas negativas del contrato (orden inválido y compra de otra
-- tienda). No valida cifras: eso es del verify de solo lectura.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v        integer;
    v_tienda bigint;
    v_otra   bigint;
    v_compra bigint;
    v_res    jsonb;
    v_nombre text;
    v_firmas text[] := ARRAY[
        'public.fn_fdi_pendientes_panel(bigint,text)',
        'public.fn_fdi_pendientes_detalle(bigint,bigint)',
        'public.fn_fdi_recepciones_historial(bigint,date,date)',
        'public.fn_fdi_facturas(bigint,date,date)'
    ];
BEGIN
    FOREACH v_nombre IN ARRAY v_firmas LOOP
        IF to_regprocedure(v_nombre) IS NULL THEN
            RAISE EXCEPTION '09: no se creó %', v_nombre USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    -- Forma: STABLE + SECURITY DEFINER + jsonb, en las 4.
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid IN (SELECT to_regprocedure(f) FROM unnest(v_firmas) f)
       AND p.prosecdef
       AND p.provolatile = 's'
       AND pg_get_function_result(p.oid) = 'jsonb';
    IF v <> 4 THEN
        RAISE EXCEPTION '09: solo % de 4 quedaron STABLE/SECURITY DEFINER/jsonb', v;
    END IF;

    -- Sin sobrecargas inesperadas (un residuo de una versión anterior con
    -- otra firma dejaría dos candidatos y PostgREST elegiría por su cuenta).
    SELECT count(*) INTO v
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_pendientes_panel', 'fn_fdi_pendientes_detalle',
                         'fn_fdi_recepciones_historial', 'fn_fdi_facturas');
    IF v <> 4 THEN
        RAISE EXCEPTION '09: hay % funciones con esos nombres (se esperaban 4); sobran % sobrecargas',
            v, v - 4;
    END IF;

    -- Permisos: `authenticated` sí, `anon` no.
    SELECT count(*) INTO v
      FROM unnest(v_firmas) f
     WHERE has_function_privilege('authenticated', to_regprocedure(f), 'EXECUTE');
    IF v <> 4 THEN
        RAISE EXCEPTION '09: `authenticated` no puede ejecutar % de 4 funciones', 4 - v;
    END IF;
    SELECT count(*) INTO v
      FROM unnest(v_firmas) f
     WHERE has_function_privilege('anon', to_regprocedure(f), 'EXECUTE');
    IF v <> 0 THEN
        RAISE EXCEPTION '09: `anon` puede ejecutar % función(es); falta REVOKE', v;
    END IF;

    -- DEFAULT: el panel puede llamarse solo con la tienda (p_orden) y las dos
    -- con fechas pueden llamarse sin ellas (p_desde, p_hasta).
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid = to_regprocedure('public.fn_fdi_pendientes_panel(bigint,text)')
       AND p.pronargdefaults = 1;
    IF v <> 1 THEN
        RAISE EXCEPTION '09: fn_fdi_pendientes_panel no tiene el DEFAULT de p_orden';
    END IF;
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.fn_fdi_recepciones_historial(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_facturas(bigint,date,date)'))
       AND p.pronargdefaults = 2;
    IF v <> 2 THEN
        RAISE EXCEPTION '09: % de 2 funciones con fechas tienen los 2 DEFAULT', v;
    END IF;

    -- Humo (solo lectura) sobre la tienda con más compras del módulo.
    SELECT id_tienda INTO v_tienda
      FROM public.fdi_dat_compra
     GROUP BY id_tienda
     ORDER BY count(*) DESC, id_tienda
     LIMIT 1;

    IF v_tienda IS NOT NULL THEN
        v_res := public.fn_fdi_pendientes_panel(v_tienda);
        IF (v_res ->> 'id_tienda')::bigint IS DISTINCT FROM v_tienda
           OR (v_res ->> 'orden') IS DISTINCT FROM 'antiguedad'
           OR (v_res ->> 'generado_at') IS NULL
           OR jsonb_typeof(v_res -> 'compras') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '09: fn_fdi_pendientes_panel no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_pendientes_panel(v_tienda, 'monto');
        IF (v_res ->> 'orden') IS DISTINCT FROM 'monto'
           OR jsonb_typeof(v_res -> 'compras') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '09: fn_fdi_pendientes_panel(…, ''monto'') no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_recepciones_historial(v_tienda);
        IF jsonb_typeof(v_res -> 'recepciones') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '09: fn_fdi_recepciones_historial no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_facturas(v_tienda);
        IF jsonb_typeof(v_res -> 'facturas') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '09: fn_fdi_facturas no devolvió la forma esperada';
        END IF;

        -- Detalle de una compra real de esa tienda.
        SELECT id INTO v_compra
          FROM public.fdi_dat_compra
         WHERE id_tienda = v_tienda
         ORDER BY id
         LIMIT 1;
        IF v_compra IS NOT NULL THEN
            v_res := public.fn_fdi_pendientes_detalle(v_tienda, v_compra);
            IF jsonb_typeof(v_res -> 'compra') IS DISTINCT FROM 'object'
               OR jsonb_typeof(v_res -> 'lineas') IS DISTINCT FROM 'array'
               OR (v_res -> 'compra' ->> 'id_compra')::bigint IS DISTINCT FROM v_compra THEN
                RAISE EXCEPTION '09: fn_fdi_pendientes_detalle no devolvió la forma esperada';
            END IF;

            -- Prueba negativa: la misma compra pedida desde otra tienda.
            SELECT id INTO v_otra
              FROM public.fdi_dat_compra
             WHERE id_tienda <> v_tienda
             LIMIT 1;
            v_otra := COALESCE(v_otra, v_tienda + 1);
            BEGIN
                PERFORM public.fn_fdi_pendientes_detalle(v_otra, v_compra);
                RAISE EXCEPTION '09: el detalle no rechazó una compra de otra tienda';
            EXCEPTION WHEN insufficient_privilege THEN
                NULL; -- correcto: 42501
            END;
        END IF;

        -- Prueba negativa: un p_orden que no sea 'antiguedad' ni 'monto'.
        BEGIN
            PERFORM public.fn_fdi_pendientes_panel(v_tienda, 'por_lo_que_sea');
            RAISE EXCEPTION '09: el panel no rechazó un p_orden inválido';
        EXCEPTION WHEN invalid_parameter_value THEN
            NULL; -- correcto: 22023
        END;
    END IF;

    -- No se toca nada de las fases anteriores.
    IF to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)') IS NULL THEN
        RAISE EXCEPTION '09: desapareció fn_fdi_compra_costo_resumen(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION '09: desapareció fn_fdi_conciliacion(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_recepcion_pendiente(bigint)') IS NULL THEN
        RAISE EXCEPTION '09: desapareció fn_fdi_compra_recepcion_pendiente(bigint)';
    END IF;

    RAISE NOTICE '09 aplicado: panel de pendientes, detalle, histórico de recepciones y facturas (solo lectura).';
END;
$$;

COMMIT;