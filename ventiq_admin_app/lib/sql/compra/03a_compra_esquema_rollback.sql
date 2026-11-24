-- ============================================================================
-- 03a_compra_esquema_rollback.sql — reversa de la fase 3 (esquema)
--
-- REQUIERE: 03b_compra_rpcs_rollback.sql ejecutado ANTES.
--   Las 5 RPC de 03b leen y escriben estas tablas. Si se borran las tablas y
--   las RPC siguen publicadas, PostgREST las sigue exponiendo y fallan en
--   tiempo de ejecución (relation does not exist). Por eso este script aborta
--   si encuentra alguna de las 5 RPC viva: primero las funciones, luego el
--   esquema.
--
-- Qué borra (orden inverso a las dependencias):
--   fdi_dat_compra_recepcion_linea → fdi_dat_compra_recepcion →
--   fdi_hist_estado_compra → fdi_dat_compra_ajuste → fdi_dat_compra_linea →
--   fdi_dat_compra, y después trg_fdi_compra_recalcular /
--   fn_fdi_compra_recalcular.
--
-- Lo que cae con las tablas (no hace falta nombrarlo): políticas RLS, GRANTs,
-- índices (incluido idx_fdi_compra_factura), CHECKs, FKs, triggers y las
-- secuencias IDENTITY de cada id.
--
-- POR QUÉ ABORTA SI HAY COMPRAS
--   Una compra no es una fila suelta: es un documento con líneas, ajustes
--   capitalizados, historial de estados y —si ya se recibió mercancía—
--   vínculos a operaciones de recepción reales, con montos valorizados que
--   alimentan el costo. Un DROP arrastra todo eso sin papelera: no hay
--   `deshacer`, y reconstruir los totales después es imposible porque el
--   histórico de estados y los vínculos con recepciones se pierden. Borrar
--   datos contables a ciegas no es una operación de "revertir un script".
--   Si de verdad hay que destruirlos, se pide explícitamente (ver abajo) y
--   conviene haber exportado antes.
--
-- CÓMO FORZAR (solo con los datos ya archivados):
--   Opción A, misma sesión:
--       select set_config('ventiq.forzar_rollback_compra', 'on', false);
--       -- y a continuación este script
--   Opción B, si el editor no conserva la sesión: cambiar temporalmente el
--   DECLARE de la guardia a `v_forzar boolean := true;`.
--
-- Es transaccional: o revierte todo, o no toca nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Guardias: orden de dependencias y datos vivos
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_forzar  boolean := ('on' = coalesce(current_setting('ventiq.forzar_rollback_compra', true), 'off'));
    v_rpcs    text;
    v_compras bigint;
    v_lineas  bigint;
    v_ajustes bigint;
    v_hist    bigint;
    v_recep   bigint;
BEGIN
    -- 0.1) Las RPC de 03b siguen publicadas: se borrarían sus tablas por debajo.
    SELECT string_agg(x.nombre, ', ' ORDER BY x.nombre) INTO v_rpcs
    FROM (VALUES
        ('fn_fdi_compra_crear',    'public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'),
        ('fn_fdi_compra_editar',   'public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'),
        ('fn_fdi_compra_listar',   'public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text)'),
        ('fn_fdi_compra_detalle',  'public.fn_fdi_compra_detalle(bigint)'),
        ('fn_fdi_compra_cancelar', 'public.fn_fdi_compra_cancelar(bigint,text)')
    ) x(nombre, firma)
    WHERE to_regprocedure(x.firma) IS NOT NULL;

    IF v_rpcs IS NOT NULL THEN
        RAISE EXCEPTION 'Quedan RPC de compra publicadas: %', v_rpcs
            USING HINT = 'Ejecuta primero 03b_compra_rpcs_rollback.sql: sin sus tablas, esas funciones fallan en runtime.';
    END IF;

    -- 0.2) Datos vivos: no se destruyen a ciegas.
    IF to_regclass('public.fdi_dat_compra') IS NOT NULL THEN
        SELECT count(*) INTO v_compras FROM public.fdi_dat_compra;
        v_lineas  := (SELECT count(*) FROM public.fdi_dat_compra_linea);
        v_ajustes := (SELECT count(*) FROM public.fdi_dat_compra_ajuste);
        v_hist    := (SELECT count(*) FROM public.fdi_hist_estado_compra);
        v_recep   := (SELECT count(*) FROM public.fdi_dat_compra_recepcion);

        IF v_compras > 0 AND NOT v_forzar THEN
            RAISE EXCEPTION
                'Hay % compra(s) con datos: % línea(s), % ajuste(s), % evento(s) de historial, % recepción(es). No se borra nada.',
                v_compras, v_lineas, v_ajustes, v_hist, v_recep
                USING HINT = 'Exporta/archiva primero. Para forzar: select set_config(''ventiq.forzar_rollback_compra'',''on'',false); en la misma sesión (o pon v_forzar := true en este script).';
        END IF;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Tablas, de la hoja a la raíz de las dependencias
--    Sin CASCADE a propósito: si algún objeto externo dependiera de estas
--    tablas, el DROP falla y la transacción entera se deshace, en vez de
--    arrastrar en silencio lo que no era de este módulo.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS public.fdi_dat_compra_recepcion_linea;
DROP TABLE IF EXISTS public.fdi_dat_compra_recepcion;
DROP TABLE IF EXISTS public.fdi_hist_estado_compra;
DROP TABLE IF EXISTS public.fdi_dat_compra_ajuste;
DROP TABLE IF EXISTS public.fdi_dat_compra_linea;
DROP TABLE IF EXISTS public.fdi_dat_compra;

-- ---------------------------------------------------------------------------
-- 2) Funciones de recálculo (ya sin triggers que las invoquen: los triggers
--    murieron con las tablas)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.trg_fdi_compra_recalcular();
DROP FUNCTION IF EXISTS public.fn_fdi_compra_recalcular(bigint);

-- ---------------------------------------------------------------------------
-- 3) Verificación: o quedó limpio, o se deshace todo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_tablas integer;
    v_funcs  integer;
    v_rpcs   integer;
BEGIN
    SELECT count(*) INTO v_tablas
    FROM (VALUES ('public.fdi_dat_compra'),
                 ('public.fdi_dat_compra_linea'),
                 ('public.fdi_dat_compra_ajuste'),
                 ('public.fdi_hist_estado_compra'),
                 ('public.fdi_dat_compra_recepcion'),
                 ('public.fdi_dat_compra_recepcion_linea')) x(t)
    WHERE to_regclass(x.t) IS NOT NULL;
    IF v_tablas <> 0 THEN
        RAISE EXCEPTION 'Quedaron % tabla(s) de compra sin borrar', v_tablas;
    END IF;

    SELECT count(*) INTO v_funcs
    FROM (VALUES ('public.fn_fdi_compra_recalcular(bigint)'),
                 ('public.trg_fdi_compra_recalcular()')) x(f)
    WHERE to_regprocedure(x.f) IS NOT NULL;
    IF v_funcs <> 0 THEN
        RAISE EXCEPTION 'Quedaron % función(es) de recálculo sin borrar', v_funcs;
    END IF;

    SELECT count(*) INTO v_rpcs
    FROM (VALUES ('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'),
                 ('public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'),
                 ('public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text)'),
                 ('public.fn_fdi_compra_detalle(bigint)'),
                 ('public.fn_fdi_compra_cancelar(bigint,text)')) x(f)
    WHERE to_regprocedure(x.f) IS NOT NULL;
    IF v_rpcs <> 0 THEN
        RAISE EXCEPTION 'Quedaron % RPC de compra: faltó ejecutar 03b_compra_rpcs_rollback.sql', v_rpcs;
    END IF;
END;
$$;

COMMIT;