-- ============================================================
-- PARCHE: Agregar id_extraccion a los items de listar_ordenes
--
-- Aplica este parche sobre la función listar_ordenes existente.
-- Solo modifica el jsonb_agg de items dentro del SELECT final
-- para incluir 'id_extraccion': ep.id en cada item.
--
-- INSTRUCCIONES:
--   1. Abre tu función listar_ordenes en Supabase SQL Editor.
--   2. Localiza el bloque jsonb_agg de items (SELECT jsonb_agg(...)).
--   3. Agrega 'id_extraccion', ep.id  como primer campo del objeto.
--
-- El bloque de items DEBE quedar así (cambio marcado con ← NUEVO):
-- ============================================================

-- Fragmento del jsonb_agg que debes modificar dentro de listar_ordenes:
/*
    SELECT jsonb_agg(jsonb_build_object(
        'id_extraccion', ep.id,              ← NUEVO: agregar esta línea
        'id_producto', ep.id_producto,
        'producto_nombre', p.denominacion,
        'cantidad', ep.cantidad,
        'precio_unitario', ep.precio_unitario,
        'importe', ep.importe,
        'presentacion', np.denominacion,
        'cantidad_inicial', ip.cantidad_inicial,
        'cantidad_final', ip.cantidad_final,
        'es_elaborado', p.es_elaborado,
        'entradas_producto', (...),
        'variante', CASE ...
    ))
    FROM app_dat_extraccion_productos ep
    ...
*/

-- ============================================================
-- Si tienes acceso a reemplazar la función completa, usa este
-- fragmento de reemplazo del jsonb_agg de items.
-- Pega esto DENTRO de tu CREATE OR REPLACE FUNCTION listar_ordenes,
-- reemplazando el SELECT jsonb_agg de items existente:
-- ============================================================

-- REEMPLAZO DEL jsonb_agg DE ITEMS (pega dentro de listar_ordenes):
/*
    SELECT jsonb_agg(jsonb_build_object(
        'id_extraccion', ep.id,
        'id_producto', ep.id_producto,
        'producto_nombre', p.denominacion,
        'cantidad', ep.cantidad,
        'precio_unitario', ep.precio_unitario,
        'importe', ep.importe,
        'presentacion', np.denominacion,
        'cantidad_inicial', ip.cantidad_inicial,
        'cantidad_final', ip.cantidad_final,
        'es_elaborado', p.es_elaborado,
        'entradas_producto', (
            SELECT COALESCE(SUM(ip_entradas.cantidad_final - ip_entradas.cantidad_inicial), 0)
            FROM app_dat_inventario_productos ip_entradas
            WHERE ip_entradas.id_producto = ep.id_producto
              AND ip_entradas.id_recepcion IS NOT NULL
              AND ip_entradas.created_at >= v_fecha_inicio
              AND ip_entradas.created_at <= v_fecha_fin
        ),
        'variante', CASE
            WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                'id', ep.id_variante,
                'atributo', a.denominacion,
                'opcion', ao.valor
            )
            ELSE NULL
        END
    ))
    FROM app_dat_extraccion_productos ep
    JOIN app_dat_producto p ON ep.id_producto = p.id
    LEFT JOIN app_dat_inventario_productos ip ON ep.id = ip.id_extraccion
    LEFT JOIN app_dat_variantes v ON ep.id_variante = v.id
    LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
    LEFT JOIN app_dat_atributo_opcion ao ON ep.id_opcion_variante = ao.id
    LEFT JOIN app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    WHERE ep.id_operacion = of.id
*/
