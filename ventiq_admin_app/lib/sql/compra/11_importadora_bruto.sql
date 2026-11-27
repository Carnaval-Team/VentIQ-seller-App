-- ============================================================================
-- 11_importadora_bruto.sql — bruto y reembolso separados, SIN reescribir historia
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Contexto: `fdi_dat_compra_recepcion.monto_importadora` guarda el NETO
-- (base × % − reembolso). Se conserva así para no tocar ningún documento
-- histórico (decisión del dueño: corregir solo de aquí en adelante). Para que
-- nadie tenga que adivinar, se añade:
--
--   monto_bruto_importadora = monto_importadora + reembolso_importadora
--
-- como columna GENERADA (no editable), y se documenta el significado de las
-- tres. `repartir_aterrizaje` sigue usando el neto: es el cargo que capitaliza.
-- ============================================================================

ALTER TABLE public.fdi_dat_compra_recepcion
    ADD COLUMN IF NOT EXISTS monto_bruto_importadora numeric
    GENERATED ALWAYS AS (monto_importadora + reembolso_importadora) STORED;

COMMENT ON COLUMN public.fdi_dat_compra_recepcion.monto_importadora IS
    'Cargo NETO que capitaliza al costo: base × % / 100 − reembolso.';
COMMENT ON COLUMN public.fdi_dat_compra_recepcion.reembolso_importadora IS
    'Parte del cargo que la importadora devuelve. Se resta del bruto, no del costo ya capitalizado.';
COMMENT ON COLUMN public.fdi_dat_compra_recepcion.monto_bruto_importadora IS
    'Cargo BRUTO antes del reembolso = monto_importadora + reembolso_importadora. Generada, solo lectura.';

-- Verificación de invariante al aplicar: la generada cuadra con las dos.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM public.fdi_dat_compra_recepcion
         WHERE monto_bruto_importadora IS DISTINCT FROM (monto_importadora + reembolso_importadora)
    ) THEN
        RAISE EXCEPTION '11: monto_bruto_importadora no cuadra con neto + reembolso';
    END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
