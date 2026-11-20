-- ============================================================================
-- fn_listar_ordenes (newa): la clave JSON de cada pago salía como 'tipo_paago'
-- ============================================================================
-- Proyecto: SOLO newa. Main ya emite 'tipo_pago' (no hay nada que corregir allí).
--
-- Origen: el script docs/plan-multimoneda/m01_r29_listar_ordenes_v1_propuesta.sql
-- (MC-055, aplicado en newa) tenía el typo `'tipo_paago'`. El TPV lee
-- `payment['tipo_pago']` en orders_screen.dart, así que en newa la lista de pagos
-- perdía el tipo (efectivo/digital) al recargar órdenes desde el servidor.
--
-- Qué hace: reemplaza solo esa clave sobre el cuerpo vivo (pg_get_functiondef), así
-- conserva SECURITY DEFINER, search_path y permisos, y no pisa ningún otro cambio.
-- Idempotente: si ya está corregida no hace nada. Misma firma.
-- La fuente m01_r29 ya está corregida: al promover a main, el cuerpo sale bien.
-- ============================================================================

BEGIN;

DO $patch$
DECLARE
    v_oid oid;
    v_def text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Ejecutar como postgres (actual: %)', current_user;
    END IF;

    v_oid := to_regprocedure(
        'public.fn_listar_ordenes(bigint,bigint,uuid,smallint,date,date,bigint,boolean,boolean,integer,integer)'
    );
    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'No existe fn_listar_ordenes con la firma de 11 parámetros';
    END IF;

    v_def := pg_get_functiondef(v_oid);

    IF position('''tipo_paago''' IN v_def) = 0 THEN
        RAISE NOTICE 'fn_listar_ordenes ya emite tipo_pago: sin cambios';
        RETURN;
    END IF;

    v_def := replace(v_def, '''tipo_paago''', '''tipo_pago''');

    IF position('tipo_paago' IN v_def) > 0 THEN
        RAISE EXCEPTION 'Quedan apariciones de tipo_paago tras el reemplazo';
    END IF;

    EXECUTE v_def;
END
$patch$;

-- Verificación: debe devolver typo_restante = false y tipo_pago_presente = true
SELECT
    p.prosrc LIKE '%tipo_paago%'      AS typo_restante,
    p.prosrc LIKE '%''tipo_pago''%'   AS tipo_pago_presente,
    p.prosecdef                       AS security_definer,
    p.proconfig                       AS config
FROM pg_proc p
WHERE p.oid = to_regprocedure(
    'public.fn_listar_ordenes(bigint,bigint,uuid,smallint,date,date,bigint,boolean,boolean,integer,integer)'
);

COMMIT;
