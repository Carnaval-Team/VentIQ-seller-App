-- ============================================================================
-- 06b_aterrizaje_rollback.sql — reversa de la fase 6b
--
-- REQUIERE: 06b_aterrizaje.sql aplicado.
--
-- Qué deshace: las 3 funciones que creó 06b.
--   1. `fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid)`
--   2. `fn_fdi_compra_repartir_aterrizaje(bigint, numeric)`
--   3. `fn_fdi_compra_recepcion_bases(bigint)`
--   En orden inverso al que las puso, y el último el que los otros dos usan.
--
-- Qué NO deshace, a propósito:
--   · **No dropea `app_dat_recepcion_producto_costo`**: la tabla es anterior a
--     06b y la comparte el cliente (`costos_adicionales_service.dart`) y
--     `fn_actualizar_precio_promedio_recepcion_v2`. Dropearla rompería el
--     módulo de costos entero, no sólo 06b.
--   · **No borra las filas de costo ya escritas** (tipo 'Importadora'). Son
--     data con valor contable: si hay que retirarlas es una decisión de negocio
--     con su nota de ajuste, no un rollback de esquema. Quedan huérfanas de
--     quién las escribe, pero siguen siendo válidas y visibles.
--   · No toca `app_cont_tipo_costo` (lo sembró 06a) ni las columnas del vínculo
--     (las puso 05a). 06b no añadió ni una columna.
--
-- Es transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Guardia: avisar si hay costos de importadora ya aterrizados
--    (no aborta: sólo deja constancia en el log del servidor)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_filas   bigint;
    v_tipo    bigint;
    v_vinculos bigint;
BEGIN
    SELECT t.id INTO v_tipo
      FROM public.app_cont_tipo_costo t
     WHERE lower(btrim(t.denominacion)) = 'importadora'
     ORDER BY t.id
     LIMIT 1;

    IF v_tipo IS NOT NULL THEN
        SELECT count(*) INTO v_filas
          FROM public.app_dat_recepcion_producto_costo c
         WHERE c.id_tipo_costo = v_tipo;

        IF v_filas > 0 THEN
            RAISE NOTICE
                'Rollback 06b: quedan % fila(s) de costo con tipo Importadora. NO se borran (son data); '
                'a partir de aquí nadie las recalcula hasta que se reaplique 06b.', v_filas;
        END IF;
    END IF;

    SELECT count(*) INTO v_vinculos
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.origen_pago IN ('wallet_importadora', 'externo')
       AND r.monto_importadora > 0;

    IF v_vinculos > 0 THEN
        RAISE NOTICE
            'Rollback 06b: % vínculo(s) con cargo de importadora quedarán sin carril de reparto hasta reaplicar.', v_vinculos;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) Retirar las funciones (dependientes primero)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_repartir_aterrizaje(bigint, numeric);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_recepcion_bases(bigint);

-- ---------------------------------------------------------------------------
-- 3) Verificación final
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
BEGIN
    IF to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06b: fn_fdi_recepcion_con_costos sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06b: fn_fdi_compra_repartir_aterrizaje sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06b: fn_fdi_compra_recepcion_bases sigue existiendo';
    END IF;

    -- Ninguna otra función de la fase 6 debe haber desaparecido por arrastre.
    SELECT count(*) INTO v
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_compra_vincular_recepcion',
                         'fn_fdi_registrar_recepcion',
                         'fn_registrar_recepcion_con_inventario',
                         'fn_actualizar_precio_promedio_recepcion_v2');
    IF v <> 4 THEN
        RAISE EXCEPTION 'Rollback 06b: se perdieron funciones que no eran suyas (% de 4 presentes)', v;
    END IF;

    -- La tabla compartida sigue en pie.
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL THEN
        RAISE EXCEPTION 'Rollback 06b: falta app_dat_recepcion_producto_costo; NO debía tocarse';
    END IF;

    RAISE NOTICE 'Rollback 06b aplicado: funciones retiradas, tabla y datos intactos.';
END;
$$;

COMMIT;