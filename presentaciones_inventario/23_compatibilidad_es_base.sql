-- ============================================================================
-- 23 · Compatibilidad con la app en producción: liberar `es_base`
-- ============================================================================
-- Corrige el `12_congelar_factor_presentacion.sql`, que bloqueaba una operación
-- normal de la app que ya está en producción.
--
-- ----------------------------------------------------------------------------
-- El síntoma
-- ----------------------------------------------------------------------------
-- Desde `admin.inventtia.com` (app viva, supabase-flutter 2.16.0):
--
--   PATCH /rest/v1/app_dat_producto_presentacion?id_producto=eq.10798
--   {"es_base": false}
--
--   → 23001 'No se puede cambiar la marca de base (es_base: t -> f) de la
--            presentacion "Kilogramo" (id 10941) del producto 10798: ya tiene
--            movimientos de inventario.'
--
-- El producto 10798 «Harina 1» (tienda 223) tiene **una sola presentación**:
-- Kilogramo, factor 1, `es_base = true`, con movimientos. Apagarle la marca no
-- cambia absolutamente nada — verificado con `fn_presentaciones_producto(10798)`
-- antes y después: `factor_rel 1.000000`, `es_base true`, `nivel 1` en los dos
-- casos, porque la cascada resuelve la base por `(es_base DESC, cantidad ASC,
-- id ASC)` y con una sola fila esa fila gana siempre.
--
-- El guard rechazaba una operación **sin efecto**.
--
-- ----------------------------------------------------------------------------
-- Por qué pasó: `es_base` no es del mismo tipo que las otras tres
-- ----------------------------------------------------------------------------
-- El `12` metió cuatro columnas en el mismo guard. Tres son datos duros:
--
--   · `cantidad`         → el factor. Cambiarlo reinterpreta el histórico y el
--                          valor viejo se pierde: **irreversible**.
--   · `id_presentacion`  → apunta al nomenclador. Idem.
--   · `id_producto`      → mover la fila a otro producto. Idem.
--
-- `es_base` es distinto: es un **puntero, no un dato**. La cascada de
-- `fn_presentaciones_producto` lo usa solo como primer criterio de desempate, y
-- el valor anterior es recuperable (es un booleano: se vuelve a poner). Además,
-- el patrón normal de la app para cambiar de base es de **dos pasos**:
--
--   UPDATE ... SET es_base = false WHERE id_producto = X;   -- apagar todas
--   UPDATE ... SET es_base = true  WHERE id = Y;            -- prender una
--
-- (`presentation_service.dart`: `setBasePresentation`, `addPresentationToProduct`
-- y `updateProductPresentation` — tres métodos, todos con este patrón.) El guard
-- rompía el **primer** paso, así que ni siquiera se podía llegar al segundo. Con
-- el guard puesto, esos tres métodos estaban muertos para cualquier producto con
-- movimientos.
--
-- Medido: apagar todas las marcas es un **no-op para la cascada en 8.781 de
-- 8.792 productos** (la base resuelta por `cantidad ASC, id ASC` es la misma).
-- Solo en 11 productos mueve la base — y son casos donde la marca contradecía al
-- factor, que es justamente lo que el gerente necesita poder arreglar.
--
-- ----------------------------------------------------------------------------
-- Qué se cambia
-- ----------------------------------------------------------------------------
-- `es_base` sale del guard. Quedan protegidos `cantidad`, `id_presentacion`,
-- `id_producto` y el `DELETE`, que son los cambios irreversibles.
--
-- Se quita de dos sitios, y los dos hacen falta:
--   1. La lista `UPDATE OF` del `CREATE TRIGGER` — así Postgres no dispara el
--      trigger cuando solo cambia `es_base` (más barato).
--   2. El `IF NEW.es_base IS DISTINCT FROM OLD.es_base` del cuerpo — porque el
--      trigger igual se dispara cuando el mismo `UPDATE` toca `es_base` **y**
--      `cantidad` a la vez, y ahí el mensaje debe hablar solo del factor.
--
-- El riesgo que queda: mover la base entre presentaciones **sí** reinterpreta la
-- cadena. Verificado con el producto 217 (Bolsa 336 factor 1 base, Bulto 337
-- factor 10):
--
--   antes            337 factor_rel 10.0   /  336 factor_rel 1.0   (base 336)
--   con 337 de base  337 factor_rel  1.0   /  336 factor_rel 0.1   (base 337)
--
-- Eso es un cambio real de interpretación y sigue siendo peligroso, pero es una
-- decisión legítima del gerente (nada lo hace irreversible) y bloquearlo dejaba
-- la app en producción sin forma de corregir una base mal marcada. Los 9
-- productos sin `es_base` y el 9635 con tres marcas son exactamente los que
-- necesitan esta operación.
--
-- ⚠️ Advertencia operativa, no técnica: cambiar la base de un producto con
-- movimientos reinterpreta sus saldos. La app debería avisarlo en la UI. Eso es
-- Fase 2/4 de la app, no de este archivo.
--
-- ----------------------------------------------------------------------------
-- Compatibilidad
-- ----------------------------------------------------------------------------
-- · No cambia ninguna firma. Nada que la app llame se toca.
-- · `precio_promedio` sigue libre (nunca estuvo en el guard) → las recepciones y
--   `fn_actualizar_precio_promedio_recepcion_v2` (el `20`) siguen funcionando.
-- · El escape `SET LOCAL ventiq.permitir_cambio_factor = 'on'` se conserva.
-- · El código de error sigue siendo **23001** (`restrict_violation`) con los
--   mismos textos, así que `presentacion_editable_service.dart`, que ya lo
--   traduce, no cambia.
--
-- Idempotente: `CREATE OR REPLACE FUNCTION` + `DROP TRIGGER IF EXISTS` y recrear.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_trg_congelar_factor_presentacion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id            BIGINT;
  v_permitir      TEXT;
  v_movimientos   BOOLEAN;
  v_que_cambia    TEXT[] := '{}';
  v_nombre        TEXT;
BEGIN
  v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;

  -- Salida de emergencia explicita (SET LOCAL, muere con la transaccion).
  -- El segundo argumento 'true' de current_setting evita el error cuando la
  -- variable no esta definida, que es el caso normal.
  v_permitir := COALESCE(current_setting('ventiq.permitir_cambio_factor', true), 'off');
  IF lower(v_permitir) IN ('on', 'true', '1', 'yes') THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- ── Que se intenta cambiar ───────────────────────────────────────────────
  --
  -- `es_base` NO esta aca a proposito (ver 23_compatibilidad_es_base.sql).
  -- Es un puntero reversible, no un dato: la cascada lo usa como primer
  -- desempate y el valor viejo se recupera poniendolo de vuelta. Bloquearlo
  -- rompia los tres metodos de presentation_service.dart que cambian la base,
  -- porque todos empiezan apagando la marca de todas las filas del producto.
  --
  -- El chequeo se mantiene para el caso en que el MISMO UPDATE toque es_base y
  -- alguna columna dura: ahi el mensaje debe hablar de la columna dura.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cantidad IS DISTINCT FROM OLD.cantidad THEN
      v_que_cambia := v_que_cambia || format('el factor (cantidad: %s -> %s)',
                        public.fn_fmt_cantidad(OLD.cantidad),
                        public.fn_fmt_cantidad(NEW.cantidad));
    END IF;

    IF NEW.id_presentacion IS DISTINCT FROM OLD.id_presentacion THEN
      v_que_cambia := v_que_cambia || format('la presentacion (id_presentacion: %s -> %s)',
                        OLD.id_presentacion, NEW.id_presentacion);
    END IF;

    IF NEW.id_producto IS DISTINCT FROM OLD.id_producto THEN
      v_que_cambia := v_que_cambia || format('el producto (id_producto: %s -> %s)',
                        OLD.id_producto, NEW.id_producto);
    END IF;

    -- Solo cambio es_base, precio_promedio u otra columna libre: se deja pasar.
    IF array_length(v_que_cambia, 1) IS NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  -- ── Recien aca se consulta el historico ──────────────────────────────────
  -- Puesto despues del chequeo de columnas a proposito: el UPDATE de
  -- precio_promedio pasa por este trigger en cada recepcion y no debe pagar
  -- cinco EXISTS por nada.
  v_movimientos := public.fn_presentacion_tiene_movimientos(v_id);

  IF NOT v_movimientos THEN
    -- Sin historia, cualquier correccion es libre.
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  SELECT np.denominacion
  INTO v_nombre
  FROM app_nom_presentacion np
  WHERE np.id = OLD.id_presentacion;

  -- OJO: en RAISE el placeholder es `%`, NO `%s` (eso es de format()). Con
  -- `%s` el % consume el argumento y queda una `s` suelta en el mensaje.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'No se puede borrar la presentacion "%" (id %) del producto %: ya tiene movimientos de inventario registrados. Los movimientos historicos quedarian sin referencia. Cree una presentacion nueva y deje de usar esta.',
      COALESCE(v_nombre, '?'), OLD.id, OLD.id_producto
      USING ERRCODE = 'restrict_violation',
            HINT = 'Si es un error de carga y hay que forzarlo: BEGIN; SET LOCAL ventiq.permitir_cambio_factor = ''on''; ... COMMIT;';
  END IF;

  RAISE EXCEPTION
    'No se puede cambiar % de la presentacion "%" (id %) del producto %: ya tiene movimientos de inventario. El factor se interpreta al leer, asi que cambiarlo reinterpreta TODO el historico de esa presentacion (saldos, IPV, valoracion y costos de meses cerrados cambiarian solos, sin dejar traza).',
    array_to_string(v_que_cambia, ' y '),
    COALESCE(v_nombre, '?'), NEW.id, NEW.id_producto
    USING ERRCODE = 'restrict_violation',
          HINT = 'Cree una presentacion nueva con el factor correcto y deje de usar la vieja. Si es un error de carga y el historico tambien esta mal: BEGIN; SET LOCAL ventiq.permitir_cambio_factor = ''on''; ... COMMIT;';
END;
$function$;

COMMENT ON FUNCTION public.fn_trg_congelar_factor_presentacion() IS
    'Congela los datos irreversibles de una presentacion con movimientos: cantidad (el factor), id_presentacion, id_producto y el borrado. es_base NO se congela: es un puntero reversible y bloquearlo rompia el cambio de base de la app en produccion. Escape: SET LOCAL ventiq.permitir_cambio_factor = ''on''. Ver presentaciones_inventario/23.';

-- El trigger se recrea con `es_base` FUERA de la lista `UPDATE OF`: asi Postgres
-- no lo dispara siquiera cuando el UPDATE solo toca esa columna.
DROP TRIGGER IF EXISTS trg_congelar_factor_presentacion
  ON public.app_dat_producto_presentacion;

CREATE TRIGGER trg_congelar_factor_presentacion
  BEFORE DELETE OR UPDATE OF cantidad, id_presentacion, id_producto
  ON public.app_dat_producto_presentacion
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_congelar_factor_presentacion();


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ El PATCH que fallaba ahora pasa, y lo que debe seguir bloqueado sigue
--      bloqueado. Ensayado en producción con ROLLBACK:
--
--   | caso                                        | resultado           |
--   |---------------------------------------------|---------------------|
--   | es_base = false en producto 10798           | pasa ✅             |
--   | setBasePresentation completo (217: apagar   | pasa ✅             |
--   |   todas + prender el Bulto 337)             |                     |
--   | cambiar cantidad de la 337 a 99             | 23001 rechazado ✅  |
--   | borrar la presentación 336                  | 23001 rechazado ✅  |
--   | cambiar precio_promedio de la 336           | pasa ✅             |
--
--   El script del ensayo está en el historial; se puede repetir envolviendo cada
--   UPDATE en un `DO $$ ... EXCEPTION WHEN OTHERS THEN ... END $$` y volcando el
--   SQLSTATE a una tabla temporal.

-- V2 · La lista UPDATE OF del trigger ya no incluye es_base:
--
--   SELECT pg_get_triggerdef(t.oid)
--     FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
--    WHERE c.relname = 'app_dat_producto_presentacion'
--      AND t.tgname = 'trg_congelar_factor_presentacion';
--
--   Esperado: `BEFORE DELETE OR UPDATE OF cantidad, id_presentacion, id_producto`
--   (sin `es_base`).

-- V3 · Apagar la marca de un producto de una sola presentación no cambia nada.
--
--   BEGIN;
--     SET LOCAL ventiq.permitir_cambio_factor = 'on';   -- ya no hace falta, pero
--     SELECT 'antes' etapa, * FROM public.fn_presentaciones_producto(10798);
--     UPDATE app_dat_producto_presentacion SET es_base = false WHERE id_producto = 10798;
--     SELECT 'despues' etapa, * FROM public.fn_presentaciones_producto(10798);
--   ROLLBACK;
--
--   Medido: idéntico en los dos casos — id 10941, factor_rel 1.000000,
--   es_base true, nivel 1. La cascada resuelve la base por
--   (es_base DESC, cantidad ASC, id ASC) y con una sola fila esa fila gana.

-- V4 · Censo: apagar TODAS las marcas es no-op en la gran mayoría.
--
--   WITH c AS (
--     SELECT pp.id_producto,
--            (SELECT b.id FROM app_dat_producto_presentacion b
--              WHERE b.id_producto = pp.id_producto
--              ORDER BY b.es_base DESC, b.cantidad ASC, b.id ASC LIMIT 1) AS base_hoy,
--            (SELECT b.id FROM app_dat_producto_presentacion b
--              WHERE b.id_producto = pp.id_producto
--              ORDER BY b.cantidad ASC, b.id ASC LIMIT 1) AS base_sin_marcas
--       FROM app_dat_producto_presentacion pp GROUP BY pp.id_producto)
--   SELECT count(*) AS productos,
--          count(*) FILTER (WHERE base_hoy = base_sin_marcas)  AS apagar_es_noop,
--          count(*) FILTER (WHERE base_hoy <> base_sin_marcas) AS apagar_mueve_base
--     FROM c;
--   -- medido: 8.792 productos, 8.781 no-op, 11 mueven la base

-- V5 · ⚠️ El riesgo que queda documentado: mover la base SÍ reinterpreta.
--
--   BEGIN;
--     SELECT 'antes' e, id_presentacion, factor, factor_rel, es_base
--       FROM public.fn_presentaciones_producto(217);
--     UPDATE app_dat_producto_presentacion SET es_base = false WHERE id_producto = 217;
--     UPDATE app_dat_producto_presentacion SET es_base = true  WHERE id = 337;
--     SELECT 'despues' e, id_presentacion, factor, factor_rel, es_base
--       FROM public.fn_presentaciones_producto(217);
--   ROLLBACK;
--
--   Medido:
--     antes:   337 factor 10 factor_rel 10.0  |  336 factor 1 factor_rel 1.0
--     después: 337 factor 10 factor_rel  1.0  |  336 factor 1 factor_rel 0.1
--
--   Los saldos guardados no cambian, pero su INTERPRETACIÓN sí. Es una decisión
--   legítima del gerente y es reversible; la UI debería advertirlo.

-- V6 · Los 11 productos donde la marca contradice al factor (los que necesitan
--      esta operación para arreglarse):
--
--   WITH c AS (
--     SELECT pp.id_producto,
--            (SELECT b.id FROM app_dat_producto_presentacion b
--              WHERE b.id_producto = pp.id_producto
--              ORDER BY b.es_base DESC, b.cantidad ASC, b.id ASC LIMIT 1) AS base_hoy,
--            (SELECT b.id FROM app_dat_producto_presentacion b
--              WHERE b.id_producto = pp.id_producto
--              ORDER BY b.cantidad ASC, b.id ASC LIMIT 1) AS base_por_factor
--       FROM app_dat_producto_presentacion pp GROUP BY pp.id_producto)
--   SELECT c.id_producto, p.denominacion, c.base_hoy, c.base_por_factor
--     FROM c JOIN app_dat_producto p ON p.id = c.id_producto
--    WHERE c.base_hoy <> c.base_por_factor
--    ORDER BY c.id_producto;
