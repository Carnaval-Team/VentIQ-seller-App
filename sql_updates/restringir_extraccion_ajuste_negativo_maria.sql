-- ============================================================================
-- Restricción: maria@inventtia.com no puede crear Extracciones (18)
--              ni Ajustes Negativos (4)
-- ============================================================================
-- Proyecto: Main (donde existe la usuaria en auth.users).
-- Mecanismo: CONSTRAINT TRIGGER AFTER INSERT diferido sobre
-- app_dat_operaciones.
--   - Se evalúa NEW.uuid (el uuid que la RPC/app escribe en la operación)
--     al final de la transacción, por lo que bloquea TODAS las vías:
--     RPCs de la app, inserts directos, sincronización offline.
--   - Diferido (INITIALLY DEFERRED) para no bloquear transferencias:
--     fn_transferir_inventario_entre_layouts inserta la operación como
--     Extracción (18) y luego la reclasifica a Transferencia Salida (7)
--     con UPDATE en la misma transacción.
--   - No depende de rol: aunque sea gerente, el tipo de operación queda
--     vetado solo para este usuario.
--   - El resto de tipos (recepciones, ajustes positivos, ventas,
--     transferencias, etc.) sigue permitido.
-- Idempotente.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_trg_bloquear_operaciones_usuario()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_uuid_bloqueado constant uuid := 'f9c73481-89b9-4b98-8dd2-3aaa5330dac3'; -- maria@inventtia.com
    v_tipos_bloqueados constant int[] := ARRAY[4, 18]; -- Ajuste Negativo, Extracción
    v_tipo_final int;
BEGIN
    IF NEW.uuid IS DISTINCT FROM v_uuid_bloqueado THEN
        RETURN NEW;
    END IF;

    -- Releer la fila real: si la transacción la reclasificó (p. ej.
    -- transferencia: INSERT tipo 18 → UPDATE a tipo 7), aquí ya se ve
    -- el tipo definitivo, no el del INSERT.
    SELECT o.id_tipo_operacion INTO v_tipo_final
      FROM public.app_dat_operaciones o
     WHERE o.id = NEW.id;

    IF v_tipo_final = ANY (v_tipos_bloqueados) THEN
        RAISE EXCEPTION
            'El usuario no tiene permitido crear operaciones de tipo %',
            (SELECT denominacion FROM app_nom_tipo_operacion
              WHERE id = v_tipo_final)
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_bloquear_operaciones_maria
    ON public.app_dat_operaciones;

-- CONSTRAINT TRIGGER diferido: se evalúa al final de la transacción.
-- Necesario porque las transferencias crean la operación como Extracción
-- (tipo 18) y la convierten a Transferencia Salida (7) con un UPDATE dentro
-- de la misma transacción (fn_transferir_inventario_entre_layouts).
-- Con BEFORE INSERT la transferencia quedaría bloqueada; diferido, la fila
-- ya es tipo 7 al evaluarse → permitida. Una extracción real sigue siendo
-- 18 al commit → bloqueada.
CREATE CONSTRAINT TRIGGER trg_bloquear_operaciones_maria
    AFTER INSERT ON public.app_dat_operaciones
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_bloquear_operaciones_usuario();

COMMIT;

-- Verificación: debe listar el trigger activo
SELECT tgname, tgrelid::regclass AS tabla
FROM pg_trigger
WHERE tgname = 'trg_bloquear_operaciones_maria' AND NOT tgisinternal;
