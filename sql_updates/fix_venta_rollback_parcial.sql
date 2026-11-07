-- fix_venta_rollback_parcial.sql
--
-- Bug: las RPC de venta (fn_registrar_venta[_mesa][_v2/_v3]) procesan cada
-- producto en un loop. Cuando un producto falla (stock insuficiente de
-- ingrediente, NO_LOCATION_FOUND, ruta de cocina inválida, etc.) hacen
-- `RETURN jsonb_build_object('status','error',...)` en lugar de lanzar
-- excepción. Un RETURN NO revierte nada: las líneas ya procesadas
-- (extracción + descuento de inventario + la operación cabecera) quedan
-- COMMITTEADAS aunque la app recibe 'error'. Resultado:
--   * operaciones huérfanas con parte de los productos,
--   * filas de extracción sin descuento real (la línea fallida insertó su
--     extracción antes de que el BOM detectara el ingrediente faltante),
--   * al cancelar la venta, la devolución re-ingresa cantidades que nunca
--     se descontaron -> inflado de inventario.
--
-- Fix: renombrar cada implementación a *_impl y dejar el nombre original
-- como wrapper fino. Si la impl devuelve status<>'success', el wrapper
-- hace RAISE dentro de su propio bloque BEGIN/EXCEPTION: la subtransacción
-- implícita revierte TODAS las escrituras de la impl (operación,
-- extracciones y descuentos parciales de ingredientes), y devuelve a la
-- app el mismo payload de error de siempre.
--
-- Comportamiento idéntico en el camino feliz y en el mensaje de error;
-- solo cambia que el error es ahora atómico.
--
-- Aplicar UNA vez. Reversible: renombrar *_impl de vuelta al nombre
-- original tras DROP FUNCTION del wrapper.

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- 1) fn_registrar_venta (legacy, fallback de la app)
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  RENAME TO fn_registrar_venta_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  TO anon, authenticated, service_role;

-- ════════════════════════════════════════════════════════════════════
-- 2) fn_registrar_venta_v2
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta_v2(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  RENAME TO fn_registrar_venta_v2_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_v2(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_v2_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_v2(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  TO anon, authenticated, service_role;

-- ════════════════════════════════════════════════════════════════════
-- 3) fn_registrar_venta_v3 (la que usa la app primero)
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  RENAME TO fn_registrar_venta_v3_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_v3(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_v3_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint)
  TO anon, authenticated, service_role;

-- ════════════════════════════════════════════════════════════════════
-- 4) fn_registrar_venta_mesa (legacy, fallback de la app)
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  RENAME TO fn_registrar_venta_mesa_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL, p_id_mesa bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_mesa_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente, p_id_mesa);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  TO anon, authenticated, service_role;

-- ════════════════════════════════════════════════════════════════════
-- 5) fn_registrar_venta_mesa_v2
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta_mesa_v2(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  RENAME TO fn_registrar_venta_mesa_v2_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa_v2(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL, p_id_mesa bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_mesa_v2_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente, p_id_mesa);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa_v2(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  TO anon, authenticated, service_role;

-- ════════════════════════════════════════════════════════════════════
-- 6) fn_registrar_venta_mesa_v3
-- ════════════════════════════════════════════════════════════════════
ALTER FUNCTION public.fn_registrar_venta_mesa_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  RENAME TO fn_registrar_venta_mesa_v3_impl;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa_v3(
  p_id_tpv bigint, p_uuid uuid, p_productos jsonb,
  p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador',
  p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1,
  p_id_cliente bigint DEFAULT NULL, p_id_mesa bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $w$
DECLARE v_res jsonb;
BEGIN
  v_res := public.fn_registrar_venta_mesa_v3_impl(
    p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
    p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente, p_id_mesa);
  IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'ROLLBACK_VENTA_PARCIAL';
  END IF;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN
  IF v_res IS NOT NULL THEN RETURN v_res; END IF;
  RETURN jsonb_build_object('status','error','message','Error al registrar venta: '||SQLERRM,'sqlstate',SQLSTATE);
END;
$w$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)
  TO anon, authenticated, service_role;

COMMIT;

-- NOTA: los callers internos que invocan por nombre (p.ej.
-- fn_registrar_venta_offline_v4 -> fn_registrar_venta_v3) pasan por el
-- wrapper automáticamente, así que el rollback atómico también cubre el
-- flujo offline.
--
-- PENDIENTE (siguiente paso, no incluido aquí): limpiar las operaciones
-- huérfanas ya creadas por este bug — extracciones de ventas fallidas que
-- quedaron registradas — y cuadrar el inventario que la cancelación
-- re-ingresó de más.
