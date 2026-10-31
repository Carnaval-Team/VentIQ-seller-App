-- =============================================================================
-- Ventas fuera de turno: marcador de cierre + validación de turno abierto
-- =============================================================================
-- Caso real (tienda 196, 2026-10-24): el vendedor cerró el turno 3338 a las
-- 15:15 en su dispositivo, pero el cierre quedó en cola offline ~67 min.
-- Mientras, el servidor seguía viendo el turno abierto y 3 ventas
-- (179095, 179099, 179105) se registraron "con turno" desde otro dispositivo
-- o sesión — dinero que no entra en el cuadre del cierre.
--
-- Cambios:
--
--   1. app_dat_caja_turno.cierre_solicitado_at (nuevo):
--      marcador liviano que el dispositivo escribe en cuanto se pide el
--      cierre, aunque el cuadre completo siga en cola offline. estado sigue
--      en 1 hasta que fn_cerrar_turno_offline/tpv haga el cierre real, así
--      el sync del cierre NO se vuelve no-op (seguiría escribiendo
--      efectivo_real, productos, diferencia).
--
--   2. fn_registrar_venta_v3 / fn_registrar_venta_mesa_v3 exigen un turno
--      VENDIBLE para el TPV:
--          estado = 1 AND cierre_solicitado_at IS NULL
--      → cierra el hueco "turno cerrándose" para ventas online desde
--      cualquier dispositivo, y prohíbe vender sin turno.
--      Las ventas OFFLINE (fn_registrar_venta_offline*) NO se tocan: una
--      orden creada offline durante un turno abierto debe poder subir
--      aunque el turno ya haya cerrado.
--
--   3. La app suma `.isFilter('cierre_solicitado_at', null)` a su query de
--      turno abierto y, al encolar un cierre, hace un UPDATE inmediato del
--      marcador (ver turno_service.dart / cierre_screen.dart).
--
-- La app cliente requiere que la columna exista ANTES de publicarse la
-- versión nueva (si no, la query de turno abierto falla y no deja vender).
--
-- Reescritura por definición viva con anclas verificadas; idempotente;
-- CREATE OR REPLACE conserva firmas y permisos. Aplicable a Main y Newa.
-- =============================================================================

BEGIN;

-- ── 1. Columna marcador + índice del check de venta ──────────────────────────
ALTER TABLE public.app_dat_caja_turno
    ADD COLUMN IF NOT EXISTS cierre_solicitado_at timestamptz;

COMMENT ON COLUMN public.app_dat_caja_turno.cierre_solicitado_at IS
'Marca de "cierre pedido" escrita por el dispositivo al encolar el cierre '
'offline. estado permanece 1 hasta que el cierre completo sincronice; '
'las ventas online (fn_registrar_venta_v3/mesa_v3) y los clientes la '
'tratan como turno ya cerrándose (no vendible).';

CREATE INDEX IF NOT EXISTS idx_caja_turno_tpv_vendible
    ON public.app_dat_caja_turno (id_tpv)
    WHERE estado = 1 AND cierre_solicitado_at IS NULL;

-- ── 2. Ventas v3 exigen turno vendible ───────────────────────────────────────
DO $$
DECLARE
    v_fn      regprocedure;
    v_def     text;
    v_anchor  constant text :=
        '    -- Obtener ID del tipo de operación "Venta"';
    v_check   constant text := $check$
    -- Turno vendible requerido: abierto y SIN cierre ya solicitado por
    -- otro dispositivo (cierre_solicitado_at cubre el hueco entre el
    -- cierre local y su sincronización completa).
    IF NOT EXISTS (
        SELECT 1 FROM app_dat_caja_turno
         WHERE id_tpv = p_id_tpv
           AND estado = 1
           AND cierre_solicitado_at IS NULL
    ) THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'No hay un turno abierto para este TPV'
      );
    END IF;
$check$;
BEGIN
    FOREACH v_fn IN ARRAY ARRAY[
        'public.fn_registrar_venta_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint)'::regprocedure,
        'public.fn_registrar_venta_mesa_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)'::regprocedure
    ]
    LOOP
        v_def := pg_get_functiondef(v_fn);

        IF position('cierre_solicitado_at' IN v_def) > 0 THEN
            RAISE NOTICE '% ya exige turno vendible: se omite', v_fn;
            CONTINUE;
        END IF;

        IF position(v_anchor IN v_def) = 0 THEN
            RAISE EXCEPTION 'Ancla de tipo_operacion no encontrada en %', v_fn;
        END IF;

        EXECUTE replace(v_def, v_anchor, v_check || E'\n' || v_anchor);
        RAISE NOTICE '%: exige turno vendible', v_fn;
    END LOOP;
END
$$;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT proname,
       position('cierre_solicitado_at' IN prosrc) > 0 AS exige_turno_vendible
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN ('fn_registrar_venta_v3', 'fn_registrar_venta_mesa_v3')
 ORDER BY proname;

SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'app_dat_caja_turno'
   AND column_name = 'cierre_solicitado_at';
