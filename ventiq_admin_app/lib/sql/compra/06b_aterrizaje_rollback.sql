-- ============================================================================
-- 06b_aterrizaje_rollback.sql — reversa de la fase 6b
--
-- REQUIERE: 06b_aterrizaje.sql aplicado.
--
-- Qué deshace:
--   1. `fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid)`
--   2. `fn_fdi_compra_repartir_aterrizaje(bigint, numeric)`
--   3. `fn_fdi_compra_recepcion_bases(bigint)`
--   4. `fdi_dat_compra_recepcion.tasa_usd_aplicada numeric(18,10)` (columna 0b)
--   5. `app_dat_recepcion_producto_costo.id_compra_recepcion bigint`, su FK y
--      su índice `idx_recepcion_producto_costo_vinculo` (columna 0c)
--   Las funciones se retiran primero porque su cuerpo referencia las dos
--   columnas; después las columnas, que se llevan por delante su FK e índice.
--
-- Corrección de la versión anterior: este archivo decía «06b no añadió ni una
-- columna» y no retiraba `tasa_usd_aplicada`. Era falso: 06b añade **dos**
-- columnas. Un rollback que deja una columna que dice no haber creado deja la
-- base en un estado que ningún script declara.
--
-- Qué NO deshace, a propósito:
--   · **No dropea `app_dat_recepcion_producto_costo`**: la tabla es anterior a
--     06b y la comparte el cliente (`costos_adicionales_service.dart`) y
--     `fn_actualizar_precio_promedio_recepcion_v2`. Dropearla rompería el
--     módulo de costos entero, no sólo 06b.
--   · **No borra las filas de costo ya escritas** (tipo 'Importadora' ni las
--     demás). Son data con valor contable: si hay que retirarlas es una
--     decisión de negocio con su nota de ajuste, no un rollback de esquema.
--     Al retirar `id_compra_recepcion` **pierden la atribución al vínculo**
--     (el importe queda); se avisa con el número de filas afectadas.
--   · No toca `app_cont_tipo_costo` (lo sembró 06a) ni las columnas del vínculo
--     de importadora (las puso 05a).
--
-- Es transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Guardia: avisar de lo que queda sin atribución o sin carril de reparto
--    (no aborta: sólo deja constancia en el log del servidor)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_filas    bigint;
    v_tipo     bigint;
    v_vinculos bigint;
    v_atribuidas bigint;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'app_dat_recepcion_producto_costo'
           AND column_name = 'id_compra_recepcion') THEN
        EXECUTE 'SELECT count(*) FROM public.app_dat_recepcion_producto_costo
                  WHERE id_compra_recepcion IS NOT NULL'
           INTO v_atribuidas;
        IF v_atribuidas > 0 THEN
            RAISE NOTICE
                'Rollback 06b: % fila(s) de costo pierden la atribución a su vínculo. Los importes NO se borran.', v_atribuidas;
        END IF;
    END IF;

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
-- 3) Retirar las dos columnas que 06b añadió (la FK y el índice se van con
--    la columna)
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_dat_recepcion_producto_costo
    DROP COLUMN IF EXISTS id_compra_recepcion;

ALTER TABLE public.fdi_dat_compra_recepcion
    DROP COLUMN IF EXISTS tasa_usd_aplicada;

-- ---------------------------------------------------------------------------
-- 4) Verificación final
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

    -- Las dos columnas de 06b se retiraron.
    SELECT count(*) INTO v
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND ((table_name = 'fdi_dat_compra_recepcion' AND column_name = 'tasa_usd_aplicada')
         OR (table_name = 'app_dat_recepcion_producto_costo' AND column_name = 'id_compra_recepcion'));
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 06b: quedan % columna(s) que 06b añadió', v;
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

    -- La tabla compartida sigue en pie y con sus filas.
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL THEN
        RAISE EXCEPTION 'Rollback 06b: falta app_dat_recepcion_producto_costo; NO debía tocarse';
    END IF;

    RAISE NOTICE 'Rollback 06b aplicado: 3 funciones y 2 columnas retiradas; tabla y datos intactos.';
END;
$$;

COMMIT;