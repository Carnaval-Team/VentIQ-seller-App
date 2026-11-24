-- ============================================================================
-- 06a_costo_aterrizado_base.sql — Fase 6: base del costo aterrizado
--
-- REQUIERE: 05c aplicado.
--
-- Qué resuelve:
--   1. `confirmada_con_exceso` en el vínculo compra↔recepción. Sin ella, un
--      exceso autorizado era indistinguible de uno real.
--   2. `fecha_operacion` de la recepción: existía y nadie la escribía, así que
--      el inventario se fechaba con now().
--   3. `id_compra` (y `moneda` donde faltaba) en las facturas de importadora y
--      proveedor: sin ese vínculo su libro sigue sin relación con la compra.
--   4. Catálogo `app_cont_tipo_costo` sembrado: tenía 0 filas, así que el
--      módulo de costos no se había ejecutado nunca.
--
-- ROLLBACK: 06a_costo_aterrizado_base_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Exceso confirmado
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_recepcion
    ADD COLUMN IF NOT EXISTS confirmada_con_exceso boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.trg_fdi_rec_linea_marca_exceso()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cant numeric;
    v_rec  numeric;
BEGIN
    SELECT l.cantidad INTO v_cant
    FROM public.fdi_dat_compra_linea l WHERE l.id = NEW.id_compra_linea;

    SELECT COALESCE(sum(rl.cantidad_recibida), 0) INTO v_rec
    FROM public.fdi_dat_compra_recepcion_linea rl
    WHERE rl.id_compra_linea = NEW.id_compra_linea;

    IF v_cant IS NOT NULL AND v_rec > v_cant THEN
        UPDATE public.fdi_dat_compra_recepcion
           SET confirmada_con_exceso = true
         WHERE id = NEW.id_compra_recepcion;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_rec_linea_exceso ON public.fdi_dat_compra_recepcion_linea;
CREATE TRIGGER trg_fdi_rec_linea_exceso
    AFTER INSERT ON public.fdi_dat_compra_recepcion_linea
    FOR EACH ROW EXECUTE FUNCTION public.trg_fdi_rec_linea_marca_exceso();

REVOKE ALL ON FUNCTION public.trg_fdi_rec_linea_marca_exceso() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Fecha de operación de la recepción
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fdi_recepcion_fecha_operacion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.fecha_operacion IS NULL THEN
        NEW.fecha_operacion := COALESCE(NEW.created_at::date, CURRENT_DATE);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fdi_recepcion_fecha ON public.app_dat_operacion_recepcion;
CREATE TRIGGER trg_fdi_recepcion_fecha
    BEFORE INSERT ON public.app_dat_operacion_recepcion
    FOR EACH ROW EXECUTE FUNCTION public.trg_fdi_recepcion_fecha_operacion();

REVOKE ALL ON FUNCTION public.trg_fdi_recepcion_fecha_operacion() FROM PUBLIC, anon, authenticated;

UPDATE public.app_dat_operacion_recepcion
   SET fecha_operacion = COALESCE(created_at::date, CURRENT_DATE)
 WHERE fecha_operacion IS NULL;

-- ---------------------------------------------------------------------------
-- 3) Vínculo documental de las facturas con la compra
-- ---------------------------------------------------------------------------
ALTER TABLE public.imp_dat_factura
    ADD COLUMN IF NOT EXISTS id_compra bigint REFERENCES public.fdi_dat_compra(id),
    ADD COLUMN IF NOT EXISTS moneda text;

ALTER TABLE public.prv_dat_factura
    ADD COLUMN IF NOT EXISTS id_compra bigint REFERENCES public.fdi_dat_compra(id),
    ADD COLUMN IF NOT EXISTS moneda text;

CREATE INDEX IF NOT EXISTS idx_imp_factura_compra ON public.imp_dat_factura (id_compra)
    WHERE id_compra IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_prv_factura_compra ON public.prv_dat_factura (id_compra)
    WHERE id_compra IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4) Catálogo de tipos de costo (estaba vacío)
--    `naturaleza`: 1 = gasto (app_nom_naturaleza_costo). `afecta_margen`: sí,
--    porque todos capitalizan al costo del producto.
-- ---------------------------------------------------------------------------
INSERT INTO public.app_cont_tipo_costo (denominacion, descripcion, naturaleza, afecta_margen)
SELECT v.denominacion, v.descripcion, 1, true
FROM (VALUES
        ('Importadora',  'Servicio o porcentaje cobrado por la importadora'),
        ('Flete',        'Transporte de la mercancía hasta el almacén'),
        ('Aduana',       'Aranceles e impuestos no recuperables de importación'),
        ('Seguro',       'Seguro de la carga')
     ) AS v(denominacion, descripcion)
WHERE NOT EXISTS (
    SELECT 1 FROM public.app_cont_tipo_costo t WHERE t.denominacion = v.denominacion
);

-- ---------------------------------------------------------------------------
-- 5) Verificación
-- ---------------------------------------------------------------------------
DO $$
DECLARE v integer;
BEGIN
    SELECT count(*) INTO v FROM information_schema.columns
    WHERE table_schema='public' AND table_name='fdi_dat_compra_recepcion'
      AND column_name='confirmada_con_exceso';
    IF v <> 1 THEN RAISE EXCEPTION 'Falta confirmada_con_exceso'; END IF;

    SELECT count(*) INTO v FROM pg_trigger
    WHERE NOT tgisinternal AND tgname IN ('trg_fdi_rec_linea_exceso','trg_fdi_recepcion_fecha');
    IF v <> 2 THEN RAISE EXCEPTION 'Faltan triggers: % de 2', v; END IF;

    SELECT count(*) INTO v FROM public.app_dat_operacion_recepcion WHERE fecha_operacion IS NULL;
    IF v <> 0 THEN RAISE EXCEPTION 'Quedaron % recepciones sin fecha_operacion', v; END IF;

    SELECT count(*) INTO v FROM information_schema.columns
    WHERE table_schema='public' AND table_name IN ('imp_dat_factura','prv_dat_factura')
      AND column_name='id_compra';
    IF v <> 2 THEN RAISE EXCEPTION 'Falta id_compra en las facturas'; END IF;

    SELECT count(*) INTO v FROM public.app_cont_tipo_costo;
    IF v < 4 THEN RAISE EXCEPTION 'El catálogo de costos quedó con % filas', v; END IF;
END;
$$;

COMMIT;