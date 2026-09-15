-- ============================================================================
-- 13_obtener_productos_envio3.sql
-- RPC: public.obtener_productos_envio3(p_id_envio integer)
--
-- PROPÓSITO:
--   Sustituir a obtener_productos_envio2 en la pantalla de detalles del envío
--   de consignación, devolviendo la información COMPLETA del producto:
--     * Presentación (nombre + unidades por presentación + si es base)
--     * Variante (atributo + valor de opción) cuando exista
--     * Ubicación original (zona de almacén)
--     * Costo REAL de la presentación (precio_promedio de
--       app_dat_producto_presentacion), independiente del precio de
--       consignación configurado por el consignador
--     * Todos los campos que ya devolvía v2 (contrato compatible en nombres)
--
-- CAMPOS NUEVOS vs obtener_productos_envio2:
--   denominacion_presentacion, presentacion_unidades, es_presentacion_base,
--   precio_costo_real_usd, variante_atributo, variante_valor,
--   ubicacion_nombre, id_presentacion, id_variante, id_ubicacion
--
-- RESOLUCIÓN DE PRESENTACIÓN (por prioridad):
--   1. ep.id_presentacion_original  (guardado al crear el envío/devolución)
--   2. inv.id_presentacion          (fila de inventario referenciada)
--   3. presentación BASE del producto (es_base = true)
--   Cubre las 186 filas históricas con id_presentacion_original NULL.
--
-- SEGURIDAD: SECURITY DEFINER + SET search_path = public + verificación de
--   que auth.uid() tiene acceso a la tienda CONSIGNADORA o CONSIGNATARIA
--   (check_user_has_access_to_tienda sobre ambas, permite cualquiera).
--
-- NOTAS:
--   * NO modifica obtener_productos_envio2 (contrato vivo; los demás
--     consumidores siguen igual).
--   * Idempotente: CREATE OR REPLACE.
--   * tasa_cambio puede venir NULL (834 filas históricas): se devuelve tal
--     cual; la app recalcula USD con la tasa vigente si lo necesita.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.obtener_productos_envio3(
  p_id_envio INTEGER
)
RETURNS TABLE (
  -- ── Campos compatibles con v2 ───────────────────────────────────────────
  id BIGINT,
  id_producto BIGINT,
  id_inventario BIGINT,
  denominacion VARCHAR,
  sku VARCHAR,
  cantidad_propuesta NUMERIC,
  cantidad_aceptada NUMERIC,
  cantidad_rechazada NUMERIC,
  precio_costo_usd NUMERIC,          -- costo de CONSIGNACIÓN configurado (puede estar truncado a 2 dec.)
  precio_costo_cup NUMERIC,          -- costo de CONSIGNACIÓN en CUP (fuente fiable)
  precio_venta_cup NUMERIC,          -- precio de venta del consignatario (NULL hasta configurar)
  tasa_cambio NUMERIC,               -- tasa al momento de crear el envío (puede ser NULL)
  estado_producto INTEGER,           -- 1=PROPUESTO 2=CONFIGURADO 3=ACEPTADO 4=RECHAZADO
  estado INTEGER,
  tipo_envio INTEGER,                -- 1=directo 2=devolución
  -- ── Campos NUEVOS ───────────────────────────────────────────────────────
  denominacion_presentacion VARCHAR, -- ej. 'Caja', 'Unidad' (NULL si no se resuelve)
  presentacion_unidades NUMERIC,     -- unidades que contiene la presentación (ej. 24)
  es_presentacion_base BOOLEAN,
  precio_costo_real_usd NUMERIC,     -- precio_promedio de la presentación (costo real)
  variante_atributo VARCHAR,         -- ej. 'Color' (NULL si el producto no tiene variante)
  variante_valor VARCHAR,            -- ej. 'Rojo'
  ubicacion_nombre VARCHAR,          -- zona de almacén original
  id_presentacion BIGINT,            -- id de app_dat_producto_presentacion resuelto
  id_variante BIGINT,
  id_ubicacion BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_tiene_acceso BOOLEAN := FALSE;
BEGIN
  -- ── 1. Resolver tiendas del contrato del envío ──────────────────────────
  SELECT cc.id_tienda_consignadora, cc.id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_consignacion_envio e
  JOIN app_dat_contrato_consignacion cc ON cc.id = e.id_contrato_consignacion
  WHERE e.id = p_id_envio;

  IF v_id_tienda_consignadora IS NULL AND v_id_tienda_consignataria IS NULL THEN
    RAISE EXCEPTION 'Envío % no encontrado', p_id_envio;
  END IF;

  -- ── 2. Acceso: basta con pertenecer a CUALQUIERA de las dos tiendas ─────
  BEGIN
    PERFORM check_user_has_access_to_tienda(v_id_tienda_consignadora);
    v_tiene_acceso := TRUE;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      PERFORM check_user_has_access_to_tienda(v_id_tienda_consignataria);
      v_tiene_acceso := TRUE;
    EXCEPTION WHEN OTHERS THEN
      v_tiene_acceso := FALSE;
    END;
  END;

  IF NOT v_tiene_acceso THEN
    RAISE EXCEPTION 'Acceso denegado: no perteneces a la tienda consignadora ni consignataria de este envío';
  END IF;

  -- ── 3. Productos con presentación / variante / ubicación resueltas ──────
  RETURN QUERY
  SELECT
    ep.id,
    ep.id_producto,
    ep.id_inventario,
    p.denominacion::VARCHAR,
    p.sku::VARCHAR,
    ep.cantidad_propuesta,
    COALESCE(ep.cantidad_aceptada, 0),
    COALESCE(ep.cantidad_rechazada, 0),
    ep.precio_costo_usd,
    ep.precio_costo_cup,
    ep.precio_venta_cup,
    ep.tasa_cambio,
    ep.estado_producto,
    ep.estado,
    e.tipo_envio,
    np.denominacion::VARCHAR,
    pp.cantidad::NUMERIC,
    pp.es_base,
    pp.precio_promedio::NUMERIC,
    att.denominacion::VARCHAR,
    aop.valor::VARCHAR,
    lay.denominacion::VARCHAR,
    pp.id,
    COALESCE(ep.id_variante_original, inv.id_variante),
    COALESCE(ep.id_ubicacion_original, inv.id_ubicacion)
  FROM app_dat_consignacion_envio_producto ep
  JOIN app_dat_consignacion_envio e ON e.id = ep.id_envio
  JOIN app_dat_producto p ON p.id = ep.id_producto
  -- Fila de inventario fuente (para filas históricas sin *_original)
  LEFT JOIN app_dat_inventario_productos inv
         ON inv.id = COALESCE(ep.id_inventario_original, ep.id_inventario)
  -- Fallback: presentación BASE del producto si no hay ninguna referencia
  LEFT JOIN LATERAL (
    SELECT bpp.id
    FROM app_dat_producto_presentacion bpp
    WHERE bpp.id_producto = ep.id_producto
      AND bpp.es_base
    ORDER BY bpp.id
    LIMIT 1
  ) pb ON TRUE
  LEFT JOIN app_dat_producto_presentacion pp
         ON pp.id = COALESCE(ep.id_presentacion_original, inv.id_presentacion, pb.id)
  LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
  LEFT JOIN app_dat_variantes v
         ON v.id = COALESCE(ep.id_variante_original, inv.id_variante)
  LEFT JOIN app_dat_atributos att ON att.id = v.id_atributo
  LEFT JOIN app_dat_atributo_opcion aop ON aop.id = inv.id_opcion_variante
  LEFT JOIN app_dat_layout_almacen lay
         ON lay.id = COALESCE(ep.id_ubicacion_original, inv.id_ubicacion)
  WHERE ep.id_envio = p_id_envio
  ORDER BY ep.id;
END;
$$;

-- ============================================================================
-- VERIFICACIONES (ejecutar DESPUÉS de aplicar, en el SQL Editor)
-- ============================================================================

-- V1. La función existe y es SECURITY DEFINER con search_path=public:
--   SELECT p.proname, p.prosecdef, p.proconfig
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname='public' AND p.proname='obtener_productos_envio3';
--   → prosecdef = true, proconfig = {search_path=public}

-- V2. Envío 517 (cerveza cristal, presentación Caja x24):
--   SELECT denominacion, denominacion_presentacion, presentacion_unidades,
--          precio_costo_cup, precio_costo_usd, precio_costo_real_usd,
--          ubicacion_nombre, estado_producto
--   FROM obtener_productos_envio3(517);
--   → denominacion_presentacion='Caja', presentacion_unidades=24,
--     precio_costo_cup=3.00 (NO 0.00 como mostraba la app)

-- V3. Devolución 514 (presentaciones base Unidad):
--   SELECT denominacion, denominacion_presentacion, es_presentacion_base,
--          precio_costo_real_usd, tasa_cambio
--   FROM obtener_productos_envio3(514) LIMIT 5;
--   → denominacion_presentacion='Unidad', es_presentacion_base=true,
--     precio_costo_real_usd>0, tasa_cambio=680.00

-- V4. Filas históricas sin id_presentacion_original (debe resolver vía
--     inventario o base, no devolver NULL en las recientes):
--   SELECT count(*) AS total,
--          count(*) FILTER (WHERE denominacion_presentacion IS NULL) AS sin_pres
--   FROM obtener_productos_envio3(515);

-- V5. Seguridad — sin sesión válida debe fallar con 'Acceso denegado'
--     (probar con la anon key desde fuera; desde el SQL Editor del dashboard
--      no aplica porque auth.uid() es NULL y deniega igual):
--   SELECT * FROM obtener_productos_envio3(514);
--   → ERROR: Acceso denegado... (esperado si auth.uid() no pertenece a las tiendas)
