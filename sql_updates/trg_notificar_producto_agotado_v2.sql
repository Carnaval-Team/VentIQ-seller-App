-- ============================================================
-- Aviso de producto agotado → dueño, gerente, supervisor, vendedor
-- ============================================================
-- Por qué se reescribe el trigger existente:
--
--  1. El trigger anterior era `AFTER UPDATE OF cantidad_final`. Ningún flujo
--     real (venta, extracción, ajuste, tanda) UPDATEA esa columna: todas las
--     funciones `fn_descontar_*` / `fn_registrar_venta_*` INSERTAN el
--     movimiento ya con `cantidad_inicial` y `cantidad_final` calculados.
--     Resultado: el trigger no se disparaba nunca en una venta real.
--  2. No avisaba al dueño de la tienda.
--  3. No era SECURITY DEFINER y no tenía manejo de excepciones: al ejecutarse
--     con el rol del vendedor podía quedarse sin leer las tablas de roles por
--     RLS, y cualquier error abortaba la transacción de la venta.
--  4. `= 0` dejaba fuera los stocks negativos (venta con sobre-giro).
--
-- Regla nueva: se avisa cuando un movimiento deja SU ubicación en <= 0
-- viniendo de una cantidad > 0, y sólo si esa fila es la última de esa
-- producto+ubicación+variante+opción (es decir, la que representa el stock
-- actual). Un mismo usuario con varios roles recibe UNA sola notificación.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_notificar_producto_agotado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_id_tienda   BIGINT;
    v_id_almacen  BIGINT;
    v_producto    TEXT;
    v_variante    TEXT := '';
    v_opcion      TEXT := '';
    v_ubicacion   TEXT := '';
    v_almacen     TEXT := '';
    v_nombre      TEXT;
    v_donde       TEXT;
    v_mensaje     TEXT;
    v_data        JSONB;
    v_prev        NUMERIC;
    v_es_ultimo   BOOLEAN;
    v_user_uuid   UUID;
BEGIN
    -- Abrir/cerrar una caja crea filas de inventario que nacen en 0 (fase
    -- presentaciones). No es un agotado: es el mismo stock reempaquetado.
    IF NEW.id_conversion IS NOT NULL OR NEW.id_conversion_evento IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF COALESCE(NEW.cantidad_final, 0) > 0 THEN
        RETURN NEW;
    END IF;

    -- Cantidad que había en esa ubicación antes de este movimiento.
    v_prev := CASE WHEN TG_OP = 'UPDATE'
                   THEN COALESCE(OLD.cantidad_final, 0)
                   ELSE COALESCE(NEW.cantidad_inicial, 0)
              END;

    IF v_prev <= 0 THEN
        RETURN NEW;   -- ya estaba en cero: no hay transición que avisar
    END IF;

    -- Sólo la fila más reciente de esa ubicación/variante representa el
    -- stock de verdad. Evita avisos al insertar movimientos históricos o
    -- varias filas de la misma operación.
    SELECT NOT EXISTS (
        SELECT 1
          FROM public.app_dat_inventario_productos x
         WHERE x.id_producto = NEW.id_producto
           AND x.id_ubicacion IS NOT DISTINCT FROM NEW.id_ubicacion
           AND x.id_variante IS NOT DISTINCT FROM NEW.id_variante
           AND x.id_opcion_variante IS NOT DISTINCT FROM NEW.id_opcion_variante
           AND x.id > NEW.id
    ) INTO v_es_ultimo;

    IF NOT COALESCE(v_es_ultimo, FALSE) THEN
        RETURN NEW;
    END IF;

    SELECT p.denominacion, p.id_tienda
      INTO v_producto, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    IF v_id_tienda IS NULL THEN
        RETURN NEW;   -- producto inexistente: nada que avisar
    END IF;

    IF NEW.id_variante IS NOT NULL THEN
        SELECT a.denominacion
          INTO v_variante
          FROM public.app_dat_variantes v
          JOIN public.app_dat_atributos a ON a.id = v.id_atributo
         WHERE v.id = NEW.id_variante;
        v_variante := COALESCE(' · ' || v_variante, '');
    END IF;

    IF NEW.id_opcion_variante IS NOT NULL THEN
        SELECT valor
          INTO v_opcion
          FROM public.app_dat_atributo_opcion
         WHERE id = NEW.id_opcion_variante;
        v_opcion := COALESCE(': ' || v_opcion, '');
    END IF;

    IF NEW.id_ubicacion IS NOT NULL THEN
        SELECT la.denominacion, la.id_almacen, al.denominacion
          INTO v_ubicacion, v_id_almacen, v_almacen
          FROM public.app_dat_layout_almacen la
          JOIN public.app_dat_almacen al ON al.id = la.id_almacen
         WHERE la.id = NEW.id_ubicacion;
    END IF;

    v_nombre := COALESCE(v_producto, 'Producto') || v_variante || v_opcion;

    v_donde := CASE
        WHEN v_almacen IS NOT NULL AND v_ubicacion IS NOT NULL
            THEN format('el almacén "%s" (ubicación "%s")', v_almacen, v_ubicacion)
        WHEN v_almacen IS NOT NULL
            THEN format('el almacén "%s"', v_almacen)
        ELSE 'la tienda'
    END;

    v_mensaje := format('El producto "%s" se agotó en %s.', v_nombre, v_donde);

    v_data := jsonb_build_object(
        'id_tienda',         v_id_tienda,
        'id_producto',       NEW.id_producto,
        'id_variante',       NEW.id_variante,
        'id_opcion_variante',NEW.id_opcion_variante,
        'id_almacen',        v_id_almacen,
        'id_ubicacion',      NEW.id_ubicacion,
        'producto_nombre',   v_producto,
        'almacen_nombre',    v_almacen,
        'ubicacion_nombre',  v_ubicacion,
        'stock_anterior',    v_prev,
        'stock_actual',      NEW.cantidad_final
    );

    -- Anti-ráfaga: una operación masiva puede dejar varias filas en 0 para la
    -- misma ubicación. Si ya se avisó hace menos de 10 minutos, no se repite.
    IF EXISTS (
        SELECT 1
          FROM public.app_dat_notificaciones n
         WHERE n.tipo = 'inventario'
           AND n.titulo = 'Producto agotado'
           AND n.data->>'id_producto' = NEW.id_producto::TEXT
           AND COALESCE(n.data->>'id_ubicacion', '') = COALESCE(NEW.id_ubicacion::TEXT, '')
           AND n.created_at > now() - INTERVAL '10 minutes'
    ) THEN
        RETURN NEW;
    END IF;

    -- Destinatarios: un solo aviso por usuario aunque tenga varios roles.
    FOR v_user_uuid IN
        SELECT DISTINCT u
          FROM (
                SELECT d.uuid AS u
                  FROM public.app_dat_dueno d
                 WHERE d.id_tienda = v_id_tienda
                UNION ALL
                SELECT g.uuid
                  FROM public.app_dat_gerente g
                 WHERE g.id_tienda = v_id_tienda
                UNION ALL
                SELECT s.uuid
                  FROM public.app_dat_supervisor s
                 WHERE s.id_tienda = v_id_tienda
                UNION ALL
                SELECT v.uuid
                  FROM public.app_dat_vendedor v
                  JOIN public.app_dat_tpv t ON t.id = v.id_tpv
                 WHERE t.id_tienda = v_id_tienda
                UNION ALL
                SELECT am.uuid
                  FROM public.app_dat_almacenero am
                 WHERE am.id_almacen = v_id_almacen
               ) x
         WHERE u IS NOT NULL
    LOOP
        PERFORM public.fn_crear_notificacion(
            p_user_id  := v_user_uuid,
            p_tipo     := 'inventario',
            p_titulo   := 'Producto agotado',
            p_mensaje  := v_mensaje,
            p_data     := v_data,
            p_prioridad:= 'alta'
        );
    END LOOP;

    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    -- Nunca abortar la venta/extracción que provocó el movimiento.
    RAISE WARNING 'fn_notificar_producto_agotado: % (producto=%, ubicación=%)',
        SQLERRM, NEW.id_producto, NEW.id_ubicacion;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_notificar_producto_agotado() IS
'Avisa a dueño, gerente, supervisor, vendedor (y almacenero del almacén) cuando un movimiento deja la ubicación en stock <= 0. Nunca aborta la transacción de origen.';

-- El trigger pasa de UPDATE a INSERT OR UPDATE: los movimientos reales se
-- insertan ya con su cantidad_final.
DROP TRIGGER IF EXISTS trg_notificar_producto_agotado ON public.app_dat_inventario_productos;

CREATE TRIGGER trg_notificar_producto_agotado
    AFTER INSERT OR UPDATE OF cantidad_final ON public.app_dat_inventario_productos
    FOR EACH ROW
    WHEN (COALESCE(NEW.cantidad_final, 0) <= 0)
    EXECUTE FUNCTION public.fn_notificar_producto_agotado();

COMMENT ON TRIGGER trg_notificar_producto_agotado ON public.app_dat_inventario_productos IS
'Dispara el aviso de agotado cuando un movimiento deja la ubicación en <= 0. La deduplicación por rol y por ráfaga la hace la función.';

-- La app (NotificationService) se suscribe por realtime a esta tabla, pero la
-- tabla no estaba en la publicación. Sin esto el aviso sólo se ve al recargar.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = 'app_dat_notificaciones'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_dat_notificaciones;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'No se pudo añadir app_dat_notificaciones a supabase_realtime: %', SQLERRM;
END $$;
