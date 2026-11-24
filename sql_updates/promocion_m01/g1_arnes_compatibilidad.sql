-- ============================================================================
-- G1 — Arnés de compatibilidad (solo lectura de efecto + ROLLBACK)
-- ============================================================================
-- Ejecutar en newa DESPUÉS de dejar el espejo de main:
--   nombres antiguos = cuerpo main; *_m01 = cuerpo newa.
-- No aplicar en main. Termina siempre en ROLLBACK.
--
-- Criterio por caso: misma forma de éxito/error justificada, o diferencia
-- documentada abajo. Sustituir los GUCs de fixture por IDs reales de prueba
-- (tienda/TPV/vendedor/usuario de newa, no producción).
--
-- Uso (SQL Editor, postgres):
--   SET app.g1_approved = 'yes';
--   SET app.g1_id_tpv = '<tpv>';
--   SET app.g1_id_vendedor = '<vendedor>';
--   SET app.g1_uuid = '<uuid auth de prueba>';
--   \i g1_arnes_compatibilidad.sql
-- ============================================================================

BEGIN;

DO $gate$
BEGIN
  IF current_setting('app.g1_approved', true) IS DISTINCT FROM 'yes' THEN
    RAISE EXCEPTION 'G1: fijar app.g1_approved=yes y fixtures antes de correr';
  END IF;
END;
$gate$;

DO $casos$
DECLARE
  v_tpv bigint := NULLIF(current_setting('app.g1_id_tpv', true), '')::bigint;
  v_vendedor bigint := NULLIF(current_setting('app.g1_id_vendedor', true), '')::bigint;
  v_uuid uuid := NULLIF(current_setting('app.g1_uuid', true), '')::uuid;
  v_clave_old uuid := gen_random_uuid();
  v_clave_m01 uuid := gen_random_uuid();
  v_old jsonb;
  v_new jsonb;
  v_err_old text;
  v_err_new text;
BEGIN
  IF v_tpv IS NULL OR v_vendedor IS NULL OR v_uuid IS NULL THEN
    RAISE EXCEPTION 'G1: faltan app.g1_id_tpv / g1_id_vendedor / g1_uuid';
  END IF;

  -- 1) Apertura: antigua vs _m01 con CLAVES DISTINTAS (misma clave choca).
  --    Esperado con espejo: antigua = main; _m01 = newa.
  --    Diferencia justificada tipica: idempotent true (main) vs false (m01)
  --    al reutilizar un turno ya abierto.
  BEGIN
    SELECT public.fn_apertura_turno_offline(
      v_clave_old, 0, v_tpv, v_vendedor, v_uuid, false, '[]'::jsonb, 'g1-old', now()
    ) INTO v_old;
  EXCEPTION WHEN OTHERS THEN
    v_err_old := SQLERRM;
  END;

  BEGIN
    SELECT public.fn_apertura_turno_offline_m01(
      v_clave_m01, 0, v_tpv, v_vendedor, v_uuid, false, '[]'::jsonb, 'g1-m01', now()
    ) INTO v_new;
  EXCEPTION WHEN OTHERS THEN
    v_err_new := SQLERRM;
  END;

  RAISE NOTICE 'G1 apertura old=% err_old=% m01=% err_m01=%',
    v_old, v_err_old, v_new, v_err_new;

  -- 2) Presencia de las 14 _m01 (el espejo debe haberlas creado).
  IF (
       SELECT count(DISTINCT p.proname)
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname IN (
           'fn_apertura_turno_offline_m01',
           'fn_cerrar_turno_offline_m01',
           'fn_registrar_venta_offline_v4_m01',
           'fn_registrar_egreso_offline_v2_m01',
           'fn_listar_ordenes_m01'
         )
     ) < 5
  THEN
    RAISE EXCEPTION 'G1: faltan una o más *_m01; generar/aplicar promocion_m01 primero';
  END IF;

  -- 3) Casos ejecutados a mano en newa el 2026-11-23 (ver g1_resultado_2026-11-23.md).
  --    Patron: un DO por variante; set_config('request.jwt.claims', ...); RAISE EXCEPTION
  --    al final con el resultado (revierte todo). claves distintas por version.
  --    - CIERRE: correr antigua y _m01 en TRANSACCIONES SEPARADAS (la primera deja el
  --      turno cerrado y la segunda respondería "No hay turno abierto").
  --      fn_cerrar_turno_offline[_monedas]: ('{"CUP":0,"USD":0}'). Replay = misma clave.
  --    - VENTA v4: producto 16 (Diesel) tienda 8; productos=[{id_producto,cantidad,
  --      precio_unitario}]. Con permitir_moneda_por_producto=true ambas dan 42501
  --      "no puede omitir el contrato de moneda" (trigger R17). Para comparar el resto:
  --      set_config('app.m01_politica_flag_autorizada','yes',true) y
  --      UPDATE app_dat_configuracion_tienda SET permitir_moneda_por_producto=false
  --      WHERE id_tienda=8; (solo dentro de la txn).
  --    - PAGO / ESTADO: usar el id_operacion de la venta creada en la misma txn.
  --      PAGO falla en ambas con 42703 mientras no se corrija H9
  --      (fn_m01_venta_v1_pago_directo); ver tasks/hallazgos_pruebas_newa.md.
  --    - COMANDA ITEM: sin cocinas/comandas en newa (skip).
  --    - LISTAR: fn_listar_ordenes vs _m01, mismos 11 parametros posicionales
  --      (id_tienda, id_tpv, id_usuario, id_estado, fecha_desde, fecha_hasta,
  --       id_tipo_operacion, con_inventario, solo_pendientes, limite, pagina);
  --      comparar filas/ids/claves, no payload completo (_m01 es superconjunto).

  RAISE NOTICE 'G1: presencia _m01 OK. Completar cargas de venta/egreso/cierre con fixtures reales y comparar filas antes de aprobar.';
END;
$casos$;

ROLLBACK;
