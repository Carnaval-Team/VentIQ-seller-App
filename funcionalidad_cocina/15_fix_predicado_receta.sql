-- ============================================================================
-- 15 · FIX · Predicado de receta roto en dos RPC de cocina
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- EL BUG
-- ------
-- app_dat_producto_ingredientes NO tiene columna id_producto. Su FK al plato es
-- id_producto_elaborado:
--
--   id, id_producto_elaborado, id_ingrediente, cantidad_necesaria,
--   unidad_medida, costo_unitario, created_at
--
-- Dos funciones en produccion filtran por pi.id (el PK de la tabla de recetas)
-- en lugar de por esa FK:
--
--   fn_resolver_origen_venta   WHERE pi.id = p_id_producto
--   fn_productos_cocina_tpv    WHERE pi.id = b.id
--
-- Comparar el id de una fila de receta con el id de un producto es comparar dos
-- dominios distintos: casi siempre da 0 filas. No es un error de sintaxis, asi
-- que Postgres lo acepta y la funcion devuelve un resultado silenciosamente
-- equivocado.
--
-- IMPACTO MEDIDO (croqueta 219, receta real: 216 x40 g + 218 x10 g)
-- ----------------------------------------------------------------
--   SELECT count(*) ... WHERE id = 219                  -> 0   (lo que veia el bug)
--   SELECT count(*) ... WHERE id_producto_elaborado=219 -> 2   (la receta real)
--
--   fn_resolver_origen_venta(219, 18) devolvia:
--       {"origen": "barra", "descontar": "sku", "id_cocina": null, "id_almacen": 12}
--   cuando lo correcto es:
--       {"origen": "cocina_al_pedido", "descontar": "ingredientes", ...}
--
-- Con v_tiene_receta = false, un plato CON receta se clasificaba como producto
-- de barra: se descontaba su SKU (que no existe en la barra) en vez de explotar
-- la receta en la cocina. El 14 nunca habria enrutado nada a cocina.
--
-- POR QUE PASO
-- ------------
-- Los archivos locales 09 y 10 tienen el predicado CORRECTO
-- (id_producto_elaborado). Lo que hay en produccion es una version anterior a
-- esa correccion: se aplico el archivo antes de arreglarlo. Este 15 realinea
-- produccion con el repo.
--
-- Leccion: validar que un .sql parsea (pglast) no detecta este tipo de fallo.
-- Solo se ve ejecutando contra datos reales. De ahi que las pruebas funcionales
-- de los archivos anteriores tengan que correrse de verdad, no solo escribirse.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr 15.1 para confirmar el diagnostico ANTES de tocar nada.
--   2. Aplicar 15.2 y 15.3.
--   3. Correr 15.4 (comprobacion posterior).
--   4. Ya se puede correr la prueba funcional del 14.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 15.1 Confirmar el diagnostico (NO MODIFICA NADA)
--
-- Esperado antes del fix:
--   columna_id_producto_existe = false
--   funciones_afectadas        = 2
--   receta_por_pk              = 0     <- lo que cuenta el bug
--   receta_por_fk              = 2     <- la receta verdadera
-- ----------------------------------------------------------------------------
SELECT
    EXISTS (
        SELECT 1 FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'app_dat_producto_ingredientes'
           AND a.attname = 'id_producto'
           AND a.attnum > 0 AND NOT a.attisdropped
    ) AS columna_id_producto_existe,
    (SELECT count(*) FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosrc LIKE '%app_dat_producto_ingredientes pi%WHERE pi.id = %'
    ) AS funciones_afectadas,
    (SELECT count(*) FROM app_dat_producto_ingredientes WHERE id = 219)
        AS receta_por_pk,
    (SELECT count(*) FROM app_dat_producto_ingredientes WHERE id_producto_elaborado = 219)
        AS receta_por_fk;


-- ----------------------------------------------------------------------------
-- 15.2 fn_resolver_origen_venta · corregir el predicado
--
-- Se aplica con ALTER-por-reemplazo del cuerpo completo mediante regexp sobre
-- pg_get_functiondef, para NO reescribir a mano una funcion de 200+ lineas y
-- arriesgar perder algo. Solo cambia la subconsulta de receta.
--
-- Es deliberadamente conservador: si el patron no aparece exactamente una vez,
-- no toca nada y avisa.
-- ----------------------------------------------------------------------------
DO $do$
DECLARE
    v_def      text;
    v_nueva    text;
    v_ocurr    integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_resolver_origen_venta';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'fn_resolver_origen_venta no existe: aplicar primero el 10';
    END IF;

    IF v_def LIKE '%pi.id_producto_elaborado = p_id_producto%' THEN
        RAISE NOTICE 'fn_resolver_origen_venta ya esta corregida: no se toca';
        RETURN;
    END IF;

    v_ocurr := (length(v_def) - length(replace(v_def, 'WHERE pi.id = p_id_producto', '')))
               / length('WHERE pi.id = p_id_producto');

    IF v_ocurr <> 1 THEN
        RAISE EXCEPTION
            'Se esperaba 1 ocurrencia del predicado roto en fn_resolver_origen_venta, hay %',
            v_ocurr;
    END IF;

    v_nueva := replace(
        v_def,
        'WHERE pi.id = p_id_producto',
        'WHERE pi.id_producto_elaborado = p_id_producto'
    );

    EXECUTE v_nueva;
    RAISE NOTICE 'fn_resolver_origen_venta corregida';
END
$do$;


-- ----------------------------------------------------------------------------
-- 15.3 fn_productos_cocina_tpv · corregir el predicado
--
-- Mismo criterio. Aqui el plato se referencia como b.id (alias de la CTE de
-- productos base del catalogo).
--
-- Impacto de este bug en el catalogo: el CASE que decide si un elaborado se
-- mide por receta o por stock propio caia siempre por la rama de "sin receta",
-- asi que la disponibilidad de los al_pedido se calculaba mal.
-- ----------------------------------------------------------------------------
DO $do$
DECLARE
    v_def   text;
    v_nueva text;
    v_ocurr integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_productos_cocina_tpv';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'fn_productos_cocina_tpv no existe: aplicar primero el 09';
    END IF;

    IF v_def LIKE '%pi.id_producto_elaborado = b.id%' THEN
        RAISE NOTICE 'fn_productos_cocina_tpv ya esta corregida: no se toca';
        RETURN;
    END IF;

    v_ocurr := (length(v_def) - length(replace(v_def, 'WHERE pi.id = b.id', '')))
               / length('WHERE pi.id = b.id');

    IF v_ocurr < 1 THEN
        RAISE EXCEPTION
            'No se encontro el predicado roto en fn_productos_cocina_tpv';
    END IF;

    v_nueva := replace(
        v_def,
        'WHERE pi.id = b.id',
        'WHERE pi.id_producto_elaborado = b.id'
    );

    EXECUTE v_nueva;
    RAISE NOTICE 'fn_productos_cocina_tpv corregida (% ocurrencia(s))', v_ocurr;
END
$do$;


-- ----------------------------------------------------------------------------
-- 15.4 Comprobacion posterior
--
-- Esperado despues del fix:
--   funciones_con_bug = 0
--   funciones_ok      = 2
-- ----------------------------------------------------------------------------
SELECT
    (SELECT count(*) FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosrc LIKE '%app_dat_producto_ingredientes pi%WHERE pi.id = %'
    ) AS funciones_con_bug,
    (SELECT count(*) FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosrc LIKE '%pi.id_producto_elaborado%'
        AND p.proname IN ('fn_resolver_origen_venta', 'fn_productos_cocina_tpv')
    ) AS funciones_ok;

-- Y el enrutamiento real de un plato con receta y cocina asignada.
-- (Devuelve 'barra' si el producto no tiene id_cocina: eso es correcto.
--  Lo que ya NO puede pasar es que un al_pedido de cocina diga descontar 'sku'.)
SELECT public.fn_resolver_origen_venta(219, 18) AS ruta_219;
