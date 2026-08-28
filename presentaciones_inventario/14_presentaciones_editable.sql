-- ============================================================================
-- 14 · fn_presentaciones_producto_editable · que puede tocar la UI
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md (Fase 2.0, la parte de UI)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
--
-- DEPENDE DE: 11 (indices) y 12 (el trigger y fn_presentacion_tiene_movimientos).
--
-- NO reemplaza ninguna funcion viva. Solo lectura.
--
--
-- POR QUE EXISTE
-- --------------
-- El trigger del 12 rechaza el cambio de factor, pero lo hace cuando el usuario
-- ya escribio y ya apreto Guardar. Eso es una red de seguridad, no una
-- interfaz: el usuario ve un error de base de datos por algo que se podia
-- haber sabido al abrir la pantalla.
--
-- `fn_presentacion_tiene_movimientos` responde por UNA presentacion. La pantalla
-- de edicion muestra TODA la cadena del producto (base + adicionales), asi que
-- con esa funcion sola la app tendria que hacer N llamadas y esperar N viajes de
-- red. Esta funcion devuelve la cadena completa con las banderas ya calculadas:
-- una sola llamada.
--
-- Ademas resuelve algo que la app no puede adivinar: la diferencia entre "no se
-- puede editar el factor" y "no se puede borrar". Son dos candados distintos,
-- de dos origenes distintos:
--
--   factor_editable = false   -> por el trigger del 12 (tiene movimientos)
--   puede_borrarse   = false  -> por el trigger del 12 O por la FK de
--                               app_dat_precio_costo, que es anterior a todo
--                               esto y afecta a 87 presentaciones que NO tienen
--                               ningun movimiento
--
-- Sin esa distincion la pantalla mostraria "se puede borrar" y despues fallaria
-- con un 23503 crudo.
--
--
-- SEGURIDAD
-- ---------
-- Este proyecto NO usa RLS: la anon key lee app_dat_* de todas las tiendas. La
-- unica barrera real es que cada RPC nueva sea SECURITY DEFINER, valide el
-- acceso con `check_user_has_access_to_tienda` y fije `search_path`.
--
-- Por eso la funcion resuelve la tienda del producto y llama a la guarda ANTES
-- de devolver nada. Sin eso, cualquiera con la anon key podria enumerar la
-- estructura de presentaciones y el historial de costos de cualquier tienda.
--
-- Eso obliga a que sea plpgsql y no sql: `PERFORM` no existe en LANGUAGE sql.
--
-- Nota: `check_user_has_access_to_tienda` devuelve void y **lanza excepcion** si
-- no hay acceso; no devuelve false. Por eso va con PERFORM y no dentro de un IF.
--
--
-- CONTRATO
-- --------
-- Una fila por presentacion del producto, en orden de mayor a menor factor
-- (el mismo orden que fn_presentaciones_producto):
--
--   id_producto_presentacion  el id que va en los payloads (app_dat_producto_presentacion.id)
--   id_nom_presentacion       el id del catalogo (app_nom_presentacion.id)
--   nombre                    'Caja', 'Unidad', ...
--   nivel                     1 = el empaque mas grande
--   factor                    app_dat_producto_presentacion.cantidad, tal cual
--   factor_rel                factor relativo a la base (lo que usa el calculo)
--   es_base                   si es la presentacion de referencia
--   tiene_movimientos         aparece en ledger / detalles / conversiones
--   tiene_precio_costo        tiene historial en app_dat_precio_costo
--   factor_editable           se puede cambiar cantidad / es_base / id_presentacion
--   puede_borrarse            se puede borrar la fila
--   motivo_bloqueo            texto listo para mostrar, NULL si no hay bloqueo
--
-- `motivo_bloqueo` viene del SQL por la misma razon que el `mensaje_usuario` de
-- fn_preview_rebalanceo: el texto tiene que decir lo mismo que dice el trigger
-- cuando rechaza, y mantener dos redacciones sincronizadas a mano no funciona.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_presentaciones_producto_editable(
  p_id_producto BIGINT
)
RETURNS TABLE (
  id_producto_presentacion BIGINT,
  id_nom_presentacion      BIGINT,
  nombre                   TEXT,
  nivel                    INTEGER,
  factor                   NUMERIC,
  factor_rel               NUMERIC,
  es_base                  BOOLEAN,
  tiene_movimientos        BOOLEAN,
  tiene_precio_costo       BOOLEAN,
  factor_editable          BOOLEAN,
  puede_borrarse           BOOLEAN,
  motivo_bloqueo           TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id_tienda BIGINT;
BEGIN
  SELECT p.id_tienda INTO v_id_tienda
    FROM app_dat_producto p
   WHERE p.id = p_id_producto;

  IF v_id_tienda IS NULL THEN
    -- Producto inexistente: no se filtra si existe o no, simplemente no hay
    -- nada que devolver.
    RETURN;
  END IF;

  -- Lanza excepcion si el usuario no pertenece a esa tienda.
  PERFORM check_user_has_access_to_tienda(v_id_tienda);

  RETURN QUERY
  WITH cadena AS (
    SELECT c.nivel               AS c_nivel,
           c.id_presentacion     AS c_id_pp,
           c.id_nom_presentacion AS c_id_nom,
           -- OJO: fn_presentaciones_producto devuelve `nombre` como VARCHAR
           -- (viene de app_nom_presentacion.denominacion). Sin este cast
           -- explicito, RETURN QUERY falla con
           -- '42804 structure of query does not match function result type:
           --  Returned type character varying does not match expected type text'.
           c.nombre::text        AS c_nombre,
           c.factor              AS c_factor,
           c.factor_rel          AS c_factor_rel,
           c.es_base             AS c_es_base
      FROM public.fn_presentaciones_producto(p_id_producto) c
  ),
  flags AS (
    SELECT ca.*,
           public.fn_presentacion_tiene_movimientos(ca.c_id_pp) AS mov,
           EXISTS (SELECT 1 FROM app_dat_precio_costo pc
                    WHERE pc.id_presentacion = ca.c_id_pp)      AS precio
      FROM cadena ca
  )
  SELECT
    f.c_id_pp,
    f.c_id_nom,
    f.c_nombre,
    f.c_nivel,
    f.c_factor,
    f.c_factor_rel,
    f.c_es_base,
    f.mov,
    f.precio,
    NOT f.mov                        AS factor_editable,
    NOT (f.mov OR f.precio)          AS puede_borrarse,
    (CASE
      WHEN f.mov THEN format(
        'Ya hay movimientos de inventario registrados en %s. El factor no se '
        'puede cambiar: se interpreta al leer, asi que cambiarlo reinterpretaria '
        'todo el historico. Si el factor esta mal, cree una presentacion nueva '
        'con el valor correcto y deje de usar esta.',
        public.fn_plural_presentacion(f.c_nombre, 2))
      WHEN f.precio THEN
        'Esta presentacion tiene historial de precio de costo: se puede editar '
        'el factor, pero no borrarla.'
      ELSE NULL
    END)::text                       AS motivo_bloqueo
  FROM flags f
  ORDER BY f.c_nivel;
END;
$$;

COMMENT ON FUNCTION public.fn_presentaciones_producto_editable(BIGINT) IS
  'Cadena de presentaciones de un producto con banderas de edicion para la UI: '
  'factor_editable (lo decide el trigger del 12), puede_borrarse (trigger + la '
  'FK de app_dat_precio_costo) y motivo_bloqueo listo para mostrar. Una llamada '
  'por producto, no una por presentacion. Valida acceso a la tienda del producto.';

GRANT EXECUTE ON FUNCTION public.fn_presentaciones_producto_editable(BIGINT)
  TO anon, authenticated, service_role;


-- ============================================================================
-- ENSAYO YA REALIZADO (BEGIN/ROLLBACK contra datos reales, 2026-08-26)
-- ============================================================================
-- Seis pruebas, todas OK. Producto 217 "azucar refino" (tienda 11), cadena
-- Bulto 10 / Bolsa 1 (base).
--
--   T1  sin usuario (postgres, auth.uid() NULL)
--       -> RECHAZADO: 'Acceso denegado: No tienes permisos para acceder a esta
--          tienda'. Esto es lo que se quiere: la guarda corta antes de devolver
--          nada.
--   T2  suplantando un gerente de la tienda 11 -> 2 filas:
--         nivel 1  Bulto  id_pp 337  factor 10  factor_rel 10
--                  mov true, precio true -> factor_editable FALSE, puede_borrarse FALSE
--         nivel 2  Bolsa  id_pp 336  factor 1   factor_rel 1  es_base
--                  mov true, precio true -> factor_editable FALSE, puede_borrarse FALSE
--       motivo_bloqueo: 'Ya hay movimientos de inventario registrados en Bultos.
--       El factor no se puede cambiar: se interpreta al leer, ...'
--   T3  coherencia: `tiene_movimientos` coincide con lo que devuelve
--       fn_presentacion_tiene_movimientos llamada de a una. true en todas.
--   T4  producto inexistente (-1) -> 0 filas, sin error y sin revelar nada.
--   T5  **aislamiento entre tiendas**: el mismo gerente de la tienda 11 pidiendo
--       el producto 9856 (de otra tienda) -> RECHAZADO 'Acceso denegado'.
--   T6  y la propia sigue funcionando en la misma sesion -> 2 filas.
--
-- Producto 7075 (ensayo previo; la base tiene factor 24):
--   nivel 1  Unidad  factor 24  factor_rel 1  es_base -> todo bloqueado.
--   Confirma que `factor` y `factor_rel` son cosas distintas: la UI tiene que
--   MOSTRAR factor (lo que el usuario escribio) y CALCULAR con factor_rel.
--
--
-- Dos defectos que este ensayo destapo, ya corregidos arriba:
--
--   (a) **42804 structure of query does not match function result type**:
--       `fn_presentaciones_producto` devuelve `nombre` como VARCHAR y la firma
--       aca lo declara TEXT. plpgsql no coacciona: hay que castear
--       `c.nombre::text` en el CTE. Un `LANGUAGE sql` no habria fallado, asi que
--       el error aparecio recien al pasar a plpgsql para poder usar PERFORM.
--
--   (b) El `CASE` del motivo tambien necesita `::text`, por lo mismo: sus ramas
--       son literales `unknown`/varchar.
--
-- Ninguno de los dos se ve en un pglast: son errores de tipos en tiempo de
-- ejecucion. Por eso el ensayo contra datos reales no es opcional.


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
--   -- 1. como postgres tiene que RECHAZAR (auth.uid() es NULL):
--   SELECT * FROM public.fn_presentaciones_producto_editable(217);
--   -- esperado: ERROR 'Acceso denegado: No tienes permisos...'
--
--   -- 2. suplantando un usuario real de esa tienda:
--   BEGIN;
--     SELECT set_config('request.jwt.claims',
--       json_build_object('sub', (SELECT g.uuid::text FROM app_dat_gerente g
--                                  JOIN app_dat_producto p ON p.id_tienda = g.id_tienda
--                                 WHERE p.id = 217 LIMIT 1))::text, true);
--     SELECT * FROM public.fn_presentaciones_producto_editable(217);
--   ROLLBACK;
--   -- esperado: 2 filas, ambas con factor_editable = false
--
--   -- 3. rendimiento: con los indices del 11 tiene que ser milisegundos
--   EXPLAIN (ANALYZE) SELECT * FROM public.fn_presentaciones_producto_editable(217);
