-- ============================================================================
-- BITÁCORA DE CAPITÁN — carnavalapp.order_details_bitacora
-- ============================================================================
-- Registra TODO cambio en carnavalapp."OrderDetails": quién puso más producto,
-- quién lo quitó, cuándo, por qué, cuánto dinero se movió y qué pasó en el ERP.
--
-- Complementa (no reemplaza) carnavalapp.order_status_history, que solo audita
-- cambios de STATUS de la orden. Esta tabla audita las LÍNEAS de la orden.
--
-- APPEND-ONLY: RLS activo, política solo de SELECT. Ni anon ni authenticated
-- pueden INSERT/UPDATE/DELETE, así que un repartidor NO puede borrar su rastro.
-- Escribe únicamente el trigger fn_orderdetails_ajustar_erp (SECURITY DEFINER).
--
-- ORDEN DE APLICACIÓN: 1º este archivo, 2º carnaval_orderdetails_trigger_ajuste_inventario.sql
-- APLICAR MANUALMENTE en Supabase (SQL Editor).
-- ============================================================================

CREATE TABLE IF NOT EXISTS carnavalapp.order_details_bitacora (
  id                       bigserial PRIMARY KEY,
  created_at               timestamptz NOT NULL DEFAULT now(),

  -- QUÉ cambió ---------------------------------------------------------------
  accion                   text        NOT NULL,  -- aumento | disminucion | eliminacion | cambio_precio | ajuste_sistema
  origen_tg                text        NOT NULL,  -- UPDATE | DELETE
  order_id                 bigint,
  order_detail_id          bigint,
  product_id               bigint,                -- carnavalapp."Productos".id
  producto_nombre          text,
  proveedor                smallint,              -- = public.app_dat_tienda.id_tienda_carnaval
  order_status             text,

  -- CANTIDADES ---------------------------------------------------------------
  cantidad_anterior        numeric,
  cantidad_nueva           numeric,
  delta                    numeric,               -- nueva - anterior

  -- DINERO -------------------------------------------------------------------
  precio_anterior          numeric,
  precio_nuevo             numeric,
  importe_anterior         numeric,
  importe_nuevo            numeric,
  importe_delta            numeric,

  -- QUIÉN --------------------------------------------------------------------
  actor_uuid               uuid,                  -- auth.uid() del que hizo el cambio
  actor_tipo               text,                  -- repartidor | usuario | desconocido | sistema
  actor_id                 bigint,
  actor_nombre             text,
  actor_telefono           text,
  actor_rol                text,
  repartidor_id            bigint,                -- Orders.repartidor al momento del cambio
  repartidor_nombre        text,
  cajero                   smallint,
  db_user                  text        NOT NULL DEFAULT current_user,

  -- POR QUÉ ------------------------------------------------------------------
  motivo                   text,
  nota                     text,

  -- TRAZA AL ERP (schema public) --------------------------------------------
  aplicado_erp             boolean     NOT NULL DEFAULT false,
  erp_error                text,
  origen_cambio            smallint,              -- 5=Devolución Cliente | 24=Error en Cantidades
  id_tienda                bigint,
  id_producto_erp          bigint,
  id_operacion_venta       bigint,                -- venta original que se ajustó
  id_operacion_ajuste      bigint,                -- recepción/extracción creada
  id_linea_ajuste          bigint,
  inventario_antes         numeric,
  inventario_despues       numeric,
  stock_carnaval_ajustado  boolean     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_odbit_order       ON carnavalapp.order_details_bitacora (order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_odbit_producto    ON carnavalapp.order_details_bitacora (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_odbit_actor       ON carnavalapp.order_details_bitacora (actor_uuid, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_odbit_repartidor  ON carnavalapp.order_details_bitacora (repartidor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_odbit_fecha       ON carnavalapp.order_details_bitacora (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_odbit_sin_aplicar ON carnavalapp.order_details_bitacora (created_at DESC)
  WHERE NOT aplicado_erp;

COMMENT ON TABLE carnavalapp.order_details_bitacora IS
  'Bitácora de capitán: todo cambio de cantidad/precio o borrado de líneas en "OrderDetails". Append-only.';
COMMENT ON COLUMN carnavalapp.order_details_bitacora.delta IS
  'cantidad_nueva - cantidad_anterior. Negativo = el cliente devolvió (origen_cambio 5). Positivo = el cliente quiso más (origen_cambio 24).';
COMMENT ON COLUMN carnavalapp.order_details_bitacora.accion IS
  'ajuste_sistema = lo recortó el propio trigger de creación de la orden por falta de stock, NO fue una persona.';
COMMENT ON COLUMN carnavalapp.order_details_bitacora.motivo IS
  'Motivo declarado por la app. Antes del UPDATE: SELECT set_config(''carnavalapp.motivo_cambio'', ''el cliente devolvió 2 panes'', true);';
COMMENT ON COLUMN carnavalapp.order_details_bitacora.nota IS
  'Nota libre de la app: SELECT set_config(''carnavalapp.nota_cambio'', ''...'', true);';
COMMENT ON COLUMN carnavalapp.order_details_bitacora.aplicado_erp IS
  'true si se generó el movimiento de inventario y la operación en public. Si es false, erp_error explica por qué.';

-- ---------------------------------------------------------------------------
-- Append-only: lectura para autenticados, CERO escritura desde la app.
-- ---------------------------------------------------------------------------
ALTER TABLE carnavalapp.order_details_bitacora ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS odbit_select_authenticated ON carnavalapp.order_details_bitacora;
CREATE POLICY odbit_select_authenticated
  ON carnavalapp.order_details_bitacora
  FOR SELECT TO authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON carnavalapp.order_details_bitacora FROM anon, authenticated;
GRANT SELECT ON carnavalapp.order_details_bitacora TO authenticated;

-- ---------------------------------------------------------------------------
-- Vista de lectura para el front: bitácora legible por orden.
-- ---------------------------------------------------------------------------
-- Se borra y se recrea: CREATE OR REPLACE VIEW solo permite AÑADIR columnas al
-- final, así que si este archivo se vuelve a aplicar con columnas nuevas en
-- medio, un REPLACE fallaría con "cannot change name of view column".
DROP VIEW IF EXISTS carnavalapp.v_bitacora_capitan;

CREATE OR REPLACE VIEW carnavalapp.v_bitacora_capitan AS
SELECT
  b.id,
  b.created_at,
  b.order_id,
  b.order_detail_id,
  b.order_status,
  b.producto_nombre,
  b.product_id,
  -- Se expone el proveedor para que el front pueda acotar la bitácora a la
  -- tienda que la mira: en los detalles de la orden, una tienda que no es la
  -- principal solo ve SUS líneas, así que tampoco debe ver la bitácora de las
  -- líneas de otro proveedor.
  b.proveedor,
  b.accion,                                        -- valor crudo, para iconos
  b.origen_tg,
  CASE b.accion
    WHEN 'aumento'        THEN 'Añadió producto'
    WHEN 'disminucion'    THEN 'Quitó producto'
    WHEN 'eliminacion'    THEN 'Eliminó la línea completa'
    WHEN 'cambio_precio'  THEN 'Cambió el precio'
    WHEN 'ajuste_sistema' THEN 'Ajuste automático del sistema'
    ELSE b.accion
  END                                              AS que_hizo,
  COALESCE(b.actor_nombre, b.repartidor_nombre,
           'sin identificar (' || b.db_user || ')') AS quien,
  b.actor_tipo,
  b.actor_telefono,
  b.repartidor_nombre,
  b.cantidad_anterior,
  b.cantidad_nueva,
  b.delta,
  b.importe_anterior,
  b.importe_nuevo,
  b.importe_delta,
  b.motivo,
  b.nota,
  b.aplicado_erp,
  b.erp_error,
  b.inventario_antes,
  b.inventario_despues,
  b.id_operacion_ajuste
FROM carnavalapp.order_details_bitacora b
ORDER BY b.created_at DESC;

COMMENT ON VIEW carnavalapp.v_bitacora_capitan IS
  'Bitácora de capitán en formato legible para el front (quién / qué hizo / cuánto / por qué).';

GRANT SELECT ON carnavalapp.v_bitacora_capitan TO authenticated;
