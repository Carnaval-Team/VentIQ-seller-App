-- ============================================================================
-- 28 · Lista de Operaciones con presentacion por linea (Fase 3)
-- ============================================================================
-- Cierra el pendiente «Listas de operacion: mostrar presentacion por linea, no
-- "unidades" generico» de docs/PLAN_PRESENTACIONES_INVENTARIO.md (Fase 2 Admin
-- y Fase 3).
--
-- ----------------------------------------------------------------------------
-- El hallazgo: la lista NUNCA se toco
-- ----------------------------------------------------------------------------
-- Durante la Fase 3 se dio por hecho que la pantalla de Operaciones ya mostraba
-- la presentacion. Es FALSO, y se verifico contra la funcion viva:
-- `fn_listar_operaciones_inventario_new` **no menciona `id_presentacion` ni una
-- sola vez** en sus 32.828 caracteres. Los items del JSON llevan solo
-- `id_producto`, `producto_nombre`, `sku_producto`, `cantidad`,
-- `precio_unitario` e `importe`. Con stock por presentacion, «4» no dice si son
-- 4 Bultos o 4 Bolsas.
--
-- La app la llama desde `inventory_service.dart:265` y la consume
-- `inventory_operations_screen.dart` via `detalles->'items'`.
--
-- ----------------------------------------------------------------------------
-- Que se agrega (y que NO se toca)
-- ----------------------------------------------------------------------------
-- A cada item se le CONCATENA el jsonb de `fn_presentacion_item_json`, que ya
-- existe desde el `17` (kardex) y esta probada:
--
--     fn_presentacion_item_json(337, 4) ->
--       { "id_presentacion": 337, "presentacion_nombre": "Bulto",
--         "presentacion_factor": 10.0, "presentacion_factor_rel": 10.000000,
--         "presentacion_sku": "BLT", "cantidad_formateada": "4 Bultos",
--         "equivalente_base": 40.000000 }
--
--     fn_presentacion_item_json(NULL, 4) ->
--       { ...todo null..., "cantidad_formateada": "4" }
--
-- RETROCOMPATIBILIDAD: el operador `||` de jsonb solo **agrega** claves. Las 6
-- que la app vieja lee (`id_producto`, `producto_nombre`, `sku_producto`,
-- `cantidad`, `precio_unitario`, `importe`) **no se renombran ni se quitan**, y
-- el `RETURNS TABLE` de la funcion no cambia. Una app sin actualizar ignora las
-- claves nuevas y sigue funcionando igual.
--
-- Con `id_presentacion` nulo (operaciones viejas) `cantidad_formateada` es solo
-- el numero, sin inventar la palabra "unidades": el ledger no sabe en que
-- estaba expresada esa fila. Esa decision ya se tomo en el `StockMixtoFormatter`
-- del admin y aqui se respeta.
--
-- ----------------------------------------------------------------------------
-- Los 7 bloques de items
-- ----------------------------------------------------------------------------
-- La funcion arma items en 8 sitios, uno por tipo de operacion. Se parchean 7:
--
--     alias `ep` (app_dat_extraccion_productos) .... 4 bloques
--     alias `rp` (app_dat_recepcion_productos) ..... 2 bloques
--     alias `cp` (app_dat_control_productos) ....... 1 bloque
--     alias `ai` (app_dat_ajuste_inventario) ....... 1 bloque  -> SE SALTA
--
-- El de ajustes se salta porque **`app_dat_ajuste_inventario` no tiene columna
-- `id_presentacion`** (verificado en information_schema): el ajuste se identifica
-- por producto+ubicacion y su cantidad ya es la de la presentacion que el
-- servidor resolvio. Inventarle una presentacion seria adivinar.
--
-- ----------------------------------------------------------------------------
-- Metodo
-- ----------------------------------------------------------------------------
-- Igual que el `17`, el `25` y el `26`: este archivo NO contiene el cuerpo de la
-- funcion (32.828 caracteres, 8 ramas que alimentan un UNION ALL posicional).
-- Es un DO block que baja el `pg_get_functiondef` vivo, aplica una sustitucion
-- por alias con `regexp_replace` y **aborta si el conteo no da exacto**.
--
-- Idempotente: si ya esta parcheada, la guarda del principio lo detecta y sale.
-- ============================================================================

DO $mig$
DECLARE
    v_src text;
    v_new text;
    v_n   int;
BEGIN
    v_src := pg_get_functiondef(
        'public.fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer)'::regprocedure
    );

    IF v_src LIKE '%fn_presentacion_item_json%' THEN
        RAISE NOTICE '28: ya aplicado, no se toca nada';
        RETURN;
    END IF;

    v_new := v_src;

    -- ------------------------------------------------------------------
    -- Bloques con alias `ep` (extraccion) · 4 esperados
    -- ------------------------------------------------------------------
    -- Se ancla en la linea de 'importe', que es la ULTIMA clave del objeto en
    -- los 4 bloques de extraccion. Asi el || queda pegado al cierre del
    -- jsonb_build_object sin tocar el resto.
    v_new := regexp_replace(
        v_new,
        '(''importe'',\s+COALESCE\(ep\.importe, ep\.precio_unitario \* ep\.cantidad\))(\s*\r?\n\s*)\)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(ep.id_presentacion, ep.cantidad))',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(ep\.id_presentacion, ep\.cantidad\)', 'g');
    IF v_n <> 4 THEN
        RAISE EXCEPTION '28: se esperaban 4 bloques de extraccion (ep), hay %', v_n;
    END IF;

    -- ------------------------------------------------------------------
    -- Bloques con alias `rp` (recepcion) · 2 esperados
    -- ------------------------------------------------------------------
    -- En recepcion la ultima clave es 'precio_unitario' (no hay 'importe').
    v_new := regexp_replace(
        v_new,
        '(''precio_unitario'',\s+rp\.precio_unitario)(\s*\r?\n\s*)\)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(rp.id_presentacion, rp.cantidad))',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(rp\.id_presentacion, rp\.cantidad\)', 'g');
    IF v_n <> 2 THEN
        RAISE EXCEPTION '28: se esperaban 2 bloques de recepcion (rp), hay %', v_n;
    END IF;

    -- ------------------------------------------------------------------
    -- Bloque con alias `cp` (control / conteo) · 1 esperado
    -- ------------------------------------------------------------------
    -- Aqui el jsonb_build_object cierra en su propia linea, con 'almacen' como
    -- ultima clave.
    v_new := regexp_replace(
        v_new,
        '(''almacen'',\s+COALESCE\(alm\.denominacion, ''''\))(\s*\r?\n\s*)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(cp.id_presentacion, cp.cantidad)',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(cp\.id_presentacion, cp\.cantidad\)', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION '28: se esperaba 1 bloque de control (cp), hay %', v_n;
    END IF;

    -- ------------------------------------------------------------------
    -- Guardas de compatibilidad
    -- ------------------------------------------------------------------
    -- Las 6 claves que la app vieja lee tienen que seguir ahi, con el mismo
    -- nombre y en el mismo numero de sitios que antes del parche.
    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''sku_producto''', 'g');
    IF v_n <> 8 THEN
        RAISE EXCEPTION '28: sku_producto aparecia 8 veces, ahora %', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''producto_nombre''', 'g');
    IF v_n <> 8 THEN
        RAISE EXCEPTION '28: producto_nombre aparecia 8 veces, ahora %', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''importe''', 'g');
    IF v_n <> 4 THEN
        RAISE EXCEPTION '28: importe aparecia 4 veces, ahora %', v_n;
    END IF;

    -- El total de inserciones tiene que ser 7 (4 ep + 2 rp + 1 cp).
    SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'fn_presentacion_item_json', 'g');
    IF v_n <> 7 THEN
        RAISE EXCEPTION '28: se esperaban 7 inserciones en total, hay %', v_n;
    END IF;

    -- El RETURNS TABLE no se toca: la app vieja rompe si cambia.
    IF v_new NOT LIKE '%RETURNS TABLE%' THEN
        RAISE EXCEPTION '28: no se encontro el RETURNS TABLE';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '28: fn_listar_operaciones_inventario_new parcheada (7 bloques)';
END
$mig$;

-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- V1 · Las 7 inserciones estan y las claves viejas siguen intactas.
--      Esperado: total 7 | ep 4 | rp 2 | cp 1 | sku 8 | nombre 8 | importe 4
-- SELECT
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'fn_presentacion_item_json','g')) AS total,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'fn_presentacion_item_json\(ep\.','g')) AS ep,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'fn_presentacion_item_json\(rp\.','g')) AS rp,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'fn_presentacion_item_json\(cp\.','g')) AS cp,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'''sku_producto''','g'))    AS sku,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'''producto_nombre''','g')) AS nombre,
--   (SELECT count(*) FROM regexp_matches(p.prosrc,'''importe''','g'))         AS importe
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname='fn_listar_operaciones_inventario_new';

-- V2 · Un item real trae las claves nuevas Y las viejas.
--      Tienda 45 (tiene operaciones con presentacion).
-- SELECT r.id, r.tipo_operacion_nombre,
--        item->>'cantidad'            AS cantidad_vieja,
--        item->>'importe'             AS importe_viejo,
--        item->>'sku_producto'        AS sku_viejo,
--        item->>'presentacion_nombre' AS pres_nueva,
--        item->>'cantidad_formateada' AS formateada_nueva,
--        item->>'equivalente_base'    AS equiv_nuevo
--   FROM (SELECT set_config('request.jwt.claims',
--            json_build_object('sub','7e3507ec-1b29-4901-bf88-e5d77be72100',
--                              'role','authenticated')::text, true) c) s,
--        LATERAL public.fn_listar_operaciones_inventario_new(45,NULL,NULL,NULL,NULL,NULL,NULL,NULL,10,1) r,
--        LATERAL jsonb_array_elements(r.detalles->'items') item
--  LIMIT 10;

-- V3 · Compatibilidad: NINGUN item perdio las 6 claves viejas.
--      Esperado: 0 filas.
-- SELECT r.id, item
--   FROM (SELECT set_config('request.jwt.claims',
--            json_build_object('sub','7e3507ec-1b29-4901-bf88-e5d77be72100',
--                              'role','authenticated')::text, true) c) s,
--        LATERAL public.fn_listar_operaciones_inventario_new(45,NULL,NULL,NULL,NULL,NULL,NULL,NULL,50,1) r,
--        LATERAL jsonb_array_elements(r.detalles->'items') item
--  WHERE NOT (item ? 'id_producto')
--     OR NOT (item ? 'producto_nombre')
--     OR NOT (item ? 'sku_producto')
--     OR NOT (item ? 'cantidad');

-- V4 · Las operaciones sin presentacion (historicas) no inventan nombre:
--      cantidad_formateada debe ser solo el numero y presentacion_nombre null.
-- SELECT item->>'cantidad' AS cant,
--        item->>'cantidad_formateada' AS formateada,
--        item->>'presentacion_nombre' AS pres
--   FROM (SELECT set_config('request.jwt.claims',
--            json_build_object('sub','7e3507ec-1b29-4901-bf88-e5d77be72100',
--                              'role','authenticated')::text, true) c) s,
--        LATERAL public.fn_listar_operaciones_inventario_new(45,NULL,NULL,NULL,NULL,NULL,NULL,NULL,50,1) r,
--        LATERAL jsonb_array_elements(r.detalles->'items') item
--  WHERE item->>'id_presentacion' IS NULL
--  LIMIT 5;
