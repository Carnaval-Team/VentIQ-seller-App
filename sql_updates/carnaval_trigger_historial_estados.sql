-- ============================================================================
-- Carnaval: trigger de historial para "Entregando" y "Completado"
-- Aplicar en: Supabase > SQL Editor
-- ============================================================================
--
-- PROBLEMA QUE RESUELVE
-- ---------------------
-- carnavalapp.order_status_history solo se llena desde la app de admin
-- (CarnavalService._logOrderStatusChange). Cuando el REPARTIDOR mueve la orden
-- desde su app, el cambio no queda registrado. Por eso hoy no existe ni un solo
-- registro con status 'Entregando' en el historial.
--
-- Este trigger cubre el hueco a nivel de base de datos: pase quien pase la
-- orden a 'Entregando' o 'Completado' (admin, repartidor, panel o RPC), queda
-- auditado.
--
-- NO DUPLICA
-- ----------
-- La app de admin ya inserta el historial por su cuenta. Si el trigger
-- insertara siempre, cada acción del admin generaría DOS filas. Por eso antes
-- de insertar se comprueba que no exista ya una fila igual (mismo order_id y
-- mismo status) en los últimos segundos.
--
-- QUIÉN LO HIZO (changed_by)
-- --------------------------
-- Se resuelve en este orden, quedándose con el primero que dé un nombre:
--   1. Orders.completado_por  -> el admin que acaba de completar la orden
--   2. auth.uid() = repartidores.uuid -> el repartidor autenticado
--   3. Orders.repartidor      -> el repartidor asignado a la orden
--   4. 'Sistema'              -> cambio automático, sin usuario identificable
-- ============================================================================


CREATE OR REPLACE FUNCTION carnavalapp.fn_log_order_status_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = carnavalapp, public
AS $$
DECLARE
    v_changed_by TEXT;
    v_uid        UUID;
    v_ya_existe  BOOLEAN;
BEGIN
    -- Solo auditar los dos estados pedidos
    IF NEW.status NOT IN ('Entregando', 'Completado') THEN
        RETURN NEW;
    END IF;

    -- ¿La app ya registró este mismo cambio hace un instante?
    -- Ventana corta: dos cambios legítimos al MISMO estado separados por
    -- menos de 10s no ocurren en el flujo real, pero el doble registro
    -- app + trigger sí sucede en milisegundos.
    SELECT EXISTS (
        SELECT 1
        FROM carnavalapp.order_status_history h
        WHERE h.order_id   = NEW.id
          AND h.status     = NEW.status
          AND h.created_at > NOW() - INTERVAL '10 seconds'
    ) INTO v_ya_existe;

    IF v_ya_existe THEN
        RETURN NEW;
    END IF;

    -- 1. Admin que completó (lo escribe la app junto con el status)
    IF NEW.status = 'Completado'
       AND NULLIF(TRIM(COALESCE(NEW.completado_por, '')), '') IS NOT NULL THEN
        v_changed_by := TRIM(NEW.completado_por);
    END IF;

    -- 2. Repartidor autenticado que hace el cambio desde su app.
    --    auth.uid() puede no existir en contextos sin sesión (RPC, cron),
    --    por eso va protegido.
    IF v_changed_by IS NULL THEN
        BEGIN
            v_uid := auth.uid();
        EXCEPTION WHEN OTHERS THEN
            v_uid := NULL;
        END;

        IF v_uid IS NOT NULL THEN
            SELECT NULLIF(TRIM(r.nombre), '')
            INTO v_changed_by
            FROM carnavalapp.repartidores r
            WHERE r.uuid = v_uid
            LIMIT 1;
        END IF;
    END IF;

    -- 3. Repartidor asignado a la orden
    IF v_changed_by IS NULL AND NEW.repartidor IS NOT NULL THEN
        SELECT NULLIF(TRIM(r.nombre), '')
        INTO v_changed_by
        FROM carnavalapp.repartidores r
        WHERE r.id = NEW.repartidor
        LIMIT 1;
    END IF;

    -- 4. Sin usuario identificable
    v_changed_by := COALESCE(v_changed_by, 'Sistema');

    INSERT INTO carnavalapp.order_status_history (order_id, status, changed_by)
    VALUES (NEW.id, NEW.status, v_changed_by);

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION carnavalapp.fn_log_order_status_history() IS
    'Registra en order_status_history los pasos a Entregando/Completado, venga el cambio de donde venga. Evita duplicar el registro que ya hace la app de admin.';


DROP TRIGGER IF EXISTS trg_log_order_status_history ON carnavalapp."Orders";

CREATE TRIGGER trg_log_order_status_history
    AFTER UPDATE OF status ON carnavalapp."Orders"
    FOR EACH ROW
    WHEN (
        OLD.status IS DISTINCT FROM NEW.status
        AND NEW.status IN ('Entregando', 'Completado')
    )
    EXECUTE FUNCTION carnavalapp.fn_log_order_status_history();


-- ----------------------------------------------------------------------------
-- VERIFICACIÓN
--
-- Tras aplicar, mover una orden a Entregando desde la app del repartidor y
-- comprobar que aparece la fila. Antes de este trigger, el conteo de
-- 'Entregando' era 0.
-- ----------------------------------------------------------------------------
SELECT status, changed_by, COUNT(*) AS n
FROM carnavalapp.order_status_history
GROUP BY status, changed_by
ORDER BY n DESC;
