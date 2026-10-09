-- ============================================================================
-- depositos_extraccion_observacion.sql
-- ----------------------------------------------------------------------------
-- Agrega la columna `observacion` a las extracciones de Fondo de Caja
-- (dep_dat_deposito), para capturar notas al registrar/editar una extracción
-- y mostrarlas en el listado y el detalle.
--
-- Idempotente: se puede ejecutar más de una vez sin efectos secundarios.
--
-- RLS: dep_dat_deposito ya tiene RLS habilitado y políticas definidas en
-- depositos_bancarios_schema.sql; la columna nueva hereda esas políticas,
-- por lo que no se requieren políticas adicionales.
-- ============================================================================

ALTER TABLE public.dep_dat_deposito
    ADD COLUMN IF NOT EXISTS observacion TEXT;

COMMENT ON COLUMN public.dep_dat_deposito.observacion IS
    'Observaciones libres registradas al crear/editar la extracción';

-- Recarga el schema cache de PostgREST para exponer la columna en la API.
NOTIFY pgrst, 'reload schema';
