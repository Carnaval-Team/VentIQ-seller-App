-- ============================================================================
-- 20261102140000 · La venta de un elaborado consume su receta, no su "stock de 1"
-- ============================================================================
--
-- PROBLEMA (reproducido en la tienda 223, TPV 224):
--   Producto 10800 «tacos» (es_elaborado, id_cocina 39 «Cocina caliente»,
--   modo_elaboracion al_pedido). En la barra (almacén 331) quedó 1 unidad
--   suelta de su propio SKU; la cocina (almacén 333) tiene materia prima para
--   41000 tacos (1230 kg de harina / 0.03 kg por taco).
--
--   Al vender 12 tacos, `fn_resolver_origen_venta` veía `stock_barra = 1 > 0`
--   y aplicaba la "excepción de barra" ANTES de la ruta de cocina: origen
--   `barra`, `descontar = 'sku'`. Después
--   `fn_descontar_venta_enrutada_v2` validaba 12 contra el SKU propio:
--   "Stock insuficiente (disponible: 1.000000, requerido: 12.000000)".
--   Es falso: la venta debía consumir la receta en la cocina.
--
-- ARREGLO:
--   La excepción de barra (servir de una unidad suelta del propio SKU) deja de
--   aplicar a productos **elaborados**. Un elaborado sigue siempre el
--   enrutamiento de receta:
--     · al_pedido  -> consume ingredientes en el almacén de su cocina;
--     · por_tanda  -> vende la porción ya hecha del almacén de la cocina;
--     · sin cocina -> consume la MP del almacén del TPV (RUTA 2 no cambia).
--   Los productos normales conservan la excepción de barra tal cual.
--
--   Con esto venta y catálogo coinciden: `fn_disponibilidad_plato` (que usa el
--   listado) ya ignoraba el stock proprio de barra de un elaborado con cocina.
--
-- Nota: `fn_registrar_venta_v3` y `fn_descontar_venta_enrutada_v2` NO cambian;
-- ambos ya saben consumir la receta cuando la ruta lo dice.
-- Idempotente: misma firma, mismo retorno, `create or replace`.
-- ============================================================================

create or replace function public.fn_resolver_origen_venta(
  p_id_producto bigint,
  p_id_tpv bigint
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
         WHERE pi.id_producto_elaborado = p_id_producto
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

    -- Excepción: si hay stock propio en la barra, se sirve de ahí.
    -- ⚠️ NO aplica a elaborados: una unidad suelta de su SKU no puede sustituir
    -- la receta. Sin este `NOT v_prod.es_elaborado`, vender 12 tacos con 1
    -- unidad en barra fallaba con "Stock insuficiente (1 < 12)" aunque la
    -- cocina tuviera materia prima para miles.
    v_stock_barra := fn_stock_producto_almacen(p_id_producto, v_almacen_tpv);

    IF COALESCE(v_stock_barra, 0) > 0 AND NOT v_prod.es_elaborado THEN
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

grant execute on function public.fn_resolver_origen_venta(bigint, bigint) to authenticated;

comment on function public.fn_resolver_origen_venta(bigint, bigint) is
  'Resuelve de dónde sale una línea de venta (barra/cocina/servicio). Un elaborado NUNCA usa la excepción de stock propio de barra: sigue su receta o su porción de cocina.';