-- ============================================================================
-- 03b_compra_rpcs_rollback.sql — reversa de la fase 3 (RPC de la compra)
--
-- REQUIERE: nada. Es independiente de 03a.
-- ORDEN: si además se va a revertir el esquema, este script va PRIMERO
--        (03a_compra_esquema_rollback.sql comprueba que estas 5 RPC ya no
--        existan y aborta si las encuentra).
--
-- Borra las 5 RPC con su firma exacta, en orden inverso al de creación. Entre
-- ellas no hay dependencias (no se llaman entre sí), así que el orden es de
-- legibilidad: primero lo que se creó último.
--
-- No toca fn_fdi_compra_recalcular ni trg_fdi_compra_recalcular: son parte del
-- esquema (03a), no de la API. Tampoco toca datos: las tablas y sus filas
-- quedan intactas.
--
-- Los GRANT/REVOKE de cada función desaparecen con ella; no hay que limpiarlos.
-- Es transaccional.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) RPC, de la última creada a la primera
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_compra_cancelar(bigint, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_detalle(bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_listar(bigint, text, bigint, date, date, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_editar(bigint, text, date, text, numeric, jsonb, jsonb, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_crear(bigint, bigint, text, date, text, numeric, jsonb, jsonb, text, text, text, uuid);

-- ---------------------------------------------------------------------------
-- 2) Verificación: o quedaron fuera todas, o se deshace todo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_rpcs  integer;
    v_recalc integer;
BEGIN
    SELECT count(*) INTO v_rpcs
    FROM (VALUES
        ('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'),
        ('public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'),
        ('public.fn_fdi_compra_listar(bigint,text,bigint,date,date,text)'),
        ('public.fn_fdi_compra_detalle(bigint)'),
        ('public.fn_fdi_compra_cancelar(bigint,text)')
    ) x(firma)
    WHERE to_regprocedure(x.firma) IS NOT NULL;
    IF v_rpcs <> 0 THEN
        RAISE EXCEPTION 'Quedaron % de 5 RPC de compra; revisa las firmas', v_rpcs;
    END IF;

    -- El recálculo es del esquema: este rollback NO debe llevárselo.
    SELECT count(*) INTO v_recalc
    FROM (VALUES ('public.fn_fdi_compra_recalcular(bigint)'),
                 ('public.trg_fdi_compra_recalcular()')) x(f)
    WHERE to_regprocedure(x.f) IS NOT NULL;
    IF v_recalc <> 2 THEN
        RAISE EXCEPTION 'Se esperaban las 2 funciones de recálculo intactas y hay %', v_recalc;
    END IF;
END;
$$;

COMMIT;