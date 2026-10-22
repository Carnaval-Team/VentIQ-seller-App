-- ============================================================================
-- 30 Â· Fase 1 Â· Consumo de ingredientes por EQUIVALENTE BASE (cadena _v2)
-- ============================================================================
-- Proyectos Supabase: debug qhprswhhfasrikhawjoz + produccion vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard (o MCP con permisos de escritura).
-- Idempotente: todo CREATE OR REPLACE. NO toca ninguna funcion viva.
--
-- Regla de la Fase 1 (docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md
-- Â§4.3, decision 1B): nada de funciones vivas se modifica; todo lo nuevo va a
-- _v2/_v3. Los builds instalados conservan el bug hasta que el release de Dart
-- migre a estas RPC.
--
-- ----------------------------------------------------------------------------
-- EL DEFECTO QUE CIERRA
-- ----------------------------------------------------------------------------
-- fn_descontar_ingredientes_elaborado (viva, md5 47be3a93f8d026eba2f5fbfc31b0cd4a)
-- y fn_descontar_venta_enrutada (viva, md5 d56b117f2c9307a8c6bfaac29ce5e1e8) hacen
--
--     v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);   -- L33 / L118
--
-- donde `v_ubic.cantidad_final` es la cantidad FISICA de una presentacion
-- (`fn_stock_producto_almacen_detalle` NO aplica factor, a proposito: es lo que
-- se persiste en el ledger) y `v_pendiente` viene de
-- `fn_obtener_ingredientes_recursivos` en UNIDADES BASE. Comparar kg con gramos
-- tiene dos efectos medidos (docs/_analisis/INGREDIENTES_SQL.md Â§4.3 y Â§2-bis):
--
--   Â· subdescuento: el estante queda a cero y la venta se reporta fallida;
--   Â· sobreconsumo silencioso: 2500 unidades base se descuentan como si fueran
--     2500 kg (2.500.000 base), con `status: success`.
--
-- Ademas, la validacion (`fn_validar_ingredientes_elaborado`, escalar base) y el
-- consumo (detalle fisico) median con funciones distintas: por eso "validar dice
-- que alcanza" y "consumir destruye el estante" podian ocurrir a la vez (C1).
--
-- ----------------------------------------------------------------------------
-- QUE TRAE ESTE ARCHIVO
-- ----------------------------------------------------------------------------
-- 1. fn_ejecutar_entrega_fisica_v3 : copia FIEL de la viva
--    fn_ejecutar_entrega_fisica_v2 (md5 9edf415b400a467a1d6627a628fd3376) con DOS
--    cambios, y solo dos:
--
--      (a) `SET search_path TO ''` -> `SET search_path TO 'public, pg_catalog'`.
--      (b) la llamada al plan pasa por `fn_preview_entrega_fisica_v3` (30.1b) en
--          vez de por la viva `fn_preview_entrega_fisica_v2`.
--
--    MOTIVO DE (a) â€” defecto C9, medido en los dos proyectos: la _v2 llama a
--    `check_user_has_access_to_tienda`, que no tiene SET propio y usa tablas sin
--    calificar; con el search_path vacio heredado revienta con
--    42P01 relation "app_dat_vendedor" does not exist.
--
--    MOTIVO DE (b) â€” IMPORTANTE, medido en la definicion viva el 2026-10-21:
--    un `SET` de funcion NO es global, se aplica al entrar en esa funcion y lo
--    heredan sus llamadas anidadas. La viva `fn_preview_entrega_fisica_v2` tiene
--    su PROPIO `SET search_path TO ''` (proconfig = {"search_path=\"\""}), asi que
--    llamarla desde la _v3 vuelve a dejar el search_path vacio DENTRO de ella y su
--    `check_user_has_access_to_tienda` vuelve a fallar con 42P01. Arreglar solo el
--    search_path de la _v3 NO basta: hay que evitar entrar en la preview viva.
--    Por eso 30.1b define `fn_preview_entrega_fisica_v3`, copia de la preview viva
--    con el search_path corregido, y la _v3 la usa. No se toca la preview viva.
--
--    El jsonb de salida y el registro de conversiones son IDENTICOS a la _v2.
--
--    NOTA (Fase 0.5, archivo presentaciones_inventario/45_guard_search_path.sql):
--    comprobado el 2026-10-21 en produccion que
--    `public.fn_check_user_has_access_to_tienda_safe(bigint)` AUN NO EXISTE
--    (to_regprocedure -> NULL), asi que aqui se conserva el guard actual: desde un
--    search_path con `public` la guarda resuelve sus tablas y funciona. Cuando
--    exista la _safe, basta cambiar la PERFORM del guard (queda anotada en las dos
--    funciones).
--
-- 2. fn_ingrediente_base_alcanzable : KERNEL de medida. STABLE, no escribe.
--    Mide UN producto (ingrediente) en UN alcance en unidades base: equivalente
--    total, saldo propio de la presentacion base, convertible de las demas
--    presentaciones, maximo consumible con empaques ENTEROS y el desglose por
--    ubicacion. Es la fuente unica que usan la validacion, el consumo y la UI
--    (asi validacion y consumo ya no pueden discrepar: decision 12 / C1).
--
-- 3. fn_ingredientes_elaborado_base : medida de TODA la receta de un elaborado,
--    ingrediente por ingrediente, con `alcanza`, `maximo_producible` (porciones)
--    y `saldo_por_presentacion[]`. STABLE, no escribe. Fuente unica de validacion
--    y de UI (Fase 1, punto 2 del plan).
--
-- 4. fn_consumir_ingrediente_base_v2 : consume EXACTAMENTE una cantidad en
--    unidades base, ubicacion por ubicacion, pasada 1 (saldo propio) + pasada 2
--    (convertible), con fn_ejecutar_entrega_fisica_v3 (planificador v2, enteros).
--    Pre-valida el equivalente del alcance y la descomposicion entera ANTES de la
--    primera escritura; si algo no cuadra devuelve error SIN escribir; si hubiera
--    que abortar despues de escribir, RAISE EXCEPTION (no deja commit parcial: C10).
--
-- ----------------------------------------------------------------------------
-- SEMANTICA (docs/_analisis/INGREDIENTES_SQL.md Â§5.2)
-- ----------------------------------------------------------------------------
--   Â· Unidad de cuenta = unidad base del ingrediente (factor_rel; la base da 1).
--   Â· El pendiente se mide SIEMPRE en base; cada escritura al ledger queda en la
--     presentacion fisica que realmente se movio (fisica - fisica), con su
--     conversion auditada en app_dat_conversion_presentacion.
--   Â· Sin fracciones de empaque: para poder abrir un empaque de nivel i hacen
--     falta relaciones ENTERAS entre TODOS los niveles i..base. Si la cadena no
--     es divisible, ese nivel NO se cuenta como consumible (`usable=false`) y el
--     maximo consumible baja: nunca se sirve 4,8 Bultos ni 1,25 Cajas.
--   Â· Saldos negativos preexistentes: el planificador v2 los rechaza
--     (INVALID_PRESENTATION_CHAIN) y `fn_stock_producto_almacen_detalle` los
--     descarta (<= 0). Aqui se decide UNA sola cosa para validacion y consumo:
--     se rechaza el consumo del ingrediente con NEGATIVE_STOCK_PRESENTACION.
--   Â· Variantes/opciones: esta cadena NO filtra por variante (igual que la
--     validacion viva y que fn_ejecutar_entrega_fisica_v2 con p_id_variante NULL).
--     Si un ingrediente se maneja por variantes, la UI debe leer el desglose.
--
-- ----------------------------------------------------------------------------
-- CONTRATO DE ERROR EN LA FRONTERA
-- ----------------------------------------------------------------------------
-- Los codigos estables que ya consume la app son INSUFFICIENT_STOCK,
-- INSUFFICIENT_STOCK_INGREDIENT e INSUFFICIENT_PORTIONS (decision 7). El kernel y
-- el consumidor exponen codigos mas finos (INVALID_PRESENTATION_CHAIN,
-- NEGATIVE_STOCK_PRESENTACION, y `motivo` CADENA_NO_DIVISIBLE_EN_ENTEROS) y la
-- frontera del BOM (archivo 31) los traduce.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 30.1 Â· fn_ejecutar_entrega_fisica_v3
-- Copia fiel de fn_ejecutar_entrega_fisica_v2 + search_path corregido (C9).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ejecutar_entrega_fisica_v3(
    p_id_producto bigint,
    p_id_ubicacion bigint,
    p_id_presentacion bigint,
    p_cantidad numeric,
    p_origen_cambio integer DEFAULT 3,
    p_id_extraccion bigint DEFAULT NULL::bigint,
    p_id_variante bigint DEFAULT NULL::bigint,
    p_id_opcion_variante bigint DEFAULT NULL::bigint,
    p_id_operacion bigint DEFAULT NULL::bigint,
    p_uuid uuid DEFAULT NULL::uuid,
    p_motivo text DEFAULT 'venta'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $function$
DECLARE
  v_plan jsonb; v_conv jsonb; v_entrega jsonb; v_id_tienda bigint;
  v_saldo_origen numeric; v_saldo_destino numeric; v_saldo numeric;
  v_sku_producto varchar; v_sku_ubicacion varchar; v_id_conv bigint;
  v_conversiones_ejecutadas jsonb := '[]'::jsonb;
BEGIN
  SELECT p.id_tienda INTO v_id_tienda FROM public.app_dat_producto p WHERE p.id=p_id_producto;
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(format('%s|%s|%s|%s',p_id_producto,p_id_ubicacion,COALESCE(p_id_variante,0),COALESCE(p_id_opcion_variante,0)),0));
  v_plan := public.fn_preview_entrega_fisica_v3(p_id_producto,p_id_ubicacion,p_id_presentacion,p_cantidad,p_id_variante,p_id_opcion_variante);
  IF v_plan->>'status' <> 'success' THEN RETURN v_plan; END IF;

  SELECT MIN(s.sku_producto),MIN(s.sku_ubicacion) INTO v_sku_producto,v_sku_ubicacion
  FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,p_id_ubicacion,true)s
  WHERE (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
    AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

  FOR v_conv IN SELECT value FROM jsonb_array_elements(v_plan->'conversiones') LOOP
    SELECT COALESCE(SUM(s.saldo),0) INTO v_saldo_origen
    FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,p_id_ubicacion,true)s
    WHERE s.id_presentacion=(v_conv->>'id_presentacion_origen')::bigint
      AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
      AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
    SELECT COALESCE(SUM(s.saldo),0) INTO v_saldo_destino
    FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,p_id_ubicacion,true)s
    WHERE s.id_presentacion=(v_conv->>'id_presentacion_destino')::bigint
      AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
      AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
    IF v_saldo_origen < (v_conv->>'cantidad_origen')::numeric THEN
      RAISE EXCEPTION 'PLAN_STALE: saldo insuficiente durante conversiÃ³n';
    END IF;
    v_id_conv := public.fn_registrar_conversion_presentacion(
      p_id_producto,p_id_ubicacion,(v_conv->>'id_presentacion_origen')::bigint,
      (v_conv->>'id_presentacion_destino')::bigint,(v_conv->>'cantidad_origen')::numeric,
      (v_conv->>'cantidad_destino')::numeric,'abrir',v_saldo_origen,v_saldo_destino,
      p_id_variante,p_id_opcion_variante,p_id_operacion,p_uuid,p_motivo,v_sku_producto,v_sku_ubicacion);
    v_conversiones_ejecutadas := v_conversiones_ejecutadas || (v_conv || jsonb_build_object('id_conversion',v_id_conv));
  END LOOP;

  FOR v_entrega IN SELECT value FROM jsonb_array_elements(v_plan->'entregas_fisicas') LOOP
    SELECT COALESCE(SUM(s.saldo),0),MIN(s.sku_producto),MIN(s.sku_ubicacion)
      INTO v_saldo,v_sku_producto,v_sku_ubicacion
    FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,p_id_ubicacion,true)s
    WHERE s.id_presentacion=(v_entrega->>'id_presentacion')::bigint
      AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
      AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
    IF v_saldo < (v_entrega->>'cantidad')::numeric THEN
      RAISE EXCEPTION 'PLAN_STALE: saldo insuficiente durante entrega';
    END IF;
    INSERT INTO public.app_dat_inventario_productos(
      id_producto,id_variante,id_opcion_variante,id_ubicacion,id_presentacion,
      cantidad_inicial,cantidad_final,sku_producto,sku_ubicacion,origen_cambio,
      id_extraccion,created_at)
    VALUES(p_id_producto,p_id_variante,p_id_opcion_variante,p_id_ubicacion,
      (v_entrega->>'id_presentacion')::bigint,v_saldo,
      v_saldo-(v_entrega->>'cantidad')::numeric,v_sku_producto,v_sku_ubicacion,
      p_origen_cambio,p_id_extraccion,pg_catalog.now());
  END LOOP;
  RETURN v_plan || jsonb_build_object('conversiones',v_conversiones_ejecutadas,'executed',true);
END;
$function$;

COMMENT ON FUNCTION public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)
    IS 'Copia fiel de fn_ejecutar_entrega_fisica_v2 con search_path public, pg_catalog (cierra C9 / 42P01 del guard). Mismo contrato jsonb y mismas conversiones auditadas. Fase 1, archivo 30.';

REVOKE ALL ON FUNCTION public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 30.1b Â· fn_preview_entrega_fisica_v3
-- Copia FIEL de la viva fn_preview_entrega_fisica_v2
-- (md5 c46c5d977095057a7f33b8f7b360e254) con el UNICO cambio
-- `SET search_path TO ''` -> `SET search_path TO 'public, pg_catalog'`.
--
-- Existe por el defecto C9 y por como funciona el SET de una funcion: el SET se
-- aplica al entrar en la funcion y lo heredan sus llamadas anidadas, asi que la
-- preview viva deja el search_path VACIO dentro de ella y su guarda
-- (check_user_has_access_to_tienda, tablas sin calificar) falla con 42P01 aunque
-- el llamador tenga el search_path bien. La _v3 usa esta copia (ver 30.1).
-- Devuelve exactamente el mismo jsonb que la viva.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_preview_entrega_fisica_v3(
    p_id_producto bigint,
    p_id_ubicacion bigint,
    p_id_presentacion bigint,
    p_cantidad numeric,
    p_id_variante bigint DEFAULT NULL::bigint,
    p_id_opcion_variante bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_catalog
AS $function$
DECLARE v_cadena jsonb; v_saldos jsonb; v_plan jsonb; v_id_tienda bigint;
BEGIN
  SELECT p.id_tienda INTO v_id_tienda FROM public.app_dat_producto p WHERE p.id=p_id_producto;
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda);
  PERFORM public.fn_validar_id_presentacion(p_id_producto,p_id_presentacion);
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'nivel',c.nivel,'id_presentacion',c.id_presentacion,'nombre',c.nombre,
    'factor_rel',c.factor_rel,'es_fraccionable',c.es_fraccionable) ORDER BY c.nivel),'[]'::jsonb)
    INTO v_cadena FROM public.fn_presentaciones_producto(p_id_producto) c;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id_presentacion',x.id_presentacion,'cantidad',x.saldo)),'[]'::jsonb)
    INTO v_saldos FROM (
      SELECT s.id_presentacion,SUM(s.saldo) saldo
      FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,p_id_ubicacion,true) s
      WHERE (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
        AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
      GROUP BY s.id_presentacion) x;
  v_plan := public.fn_planificar_entrega_fisica_v2(v_cadena,v_saldos,p_id_presentacion,p_cantidad);
  IF v_plan->>'status' = 'error' AND v_plan->>'error_code'='INSUFFICIENT_PHYSICAL_STOCK' THEN
    RETURN v_plan || jsonb_build_object('estrategia','imposible','necesita_conversion',false,'presentacion_nombre',(SELECT c.nombre FROM public.fn_presentaciones_producto(p_id_producto)c WHERE c.id_presentacion=p_id_presentacion));
  END IF;
  RETURN v_plan || jsonb_build_object('presentacion_nombre',(SELECT c.nombre FROM public.fn_presentaciones_producto(p_id_producto)c WHERE c.id_presentacion=p_id_presentacion));
END;
$function$;

COMMENT ON FUNCTION public.fn_preview_entrega_fisica_v3(bigint,bigint,bigint,numeric,bigint,bigint)
    IS 'Copia fiel de fn_preview_entrega_fisica_v2 con search_path public, pg_catalog: el SET de la viva deja el search_path vacio dentro de ella y su guarda falla con 42P01 (C9). Mismo jsonb. Fase 1, archivo 30.';

REVOKE ALL ON FUNCTION public.fn_preview_entrega_fisica_v3(bigint,bigint,bigint,numeric,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_preview_entrega_fisica_v3(bigint,bigint,bigint,numeric,bigint,bigint)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 30.2 Â· fn_ingrediente_base_alcanzable
-- KERNEL de medida de UN ingrediente en UN alcance, en unidades base.
-- STABLE, no escribe. Lo usan fn_ingredientes_elaborado_base,
-- fn_consumir_ingrediente_base_v2 y, via el archivo 31, la validacion de receta.
--
-- p_alcance: 'almacen' (acota a p_id_almacen; NULL = todos los almacenes) o
--            'tienda'  (todos los almacenes de la tienda del p_id_almacen).
-- p_cantidad_base: si se pasa, devuelve `alcanza` y `motivo` para esa cantidad.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ingrediente_base_alcanzable(
    p_id_producto   bigint,
    p_id_almacen    bigint  DEFAULT NULL,
    p_alcance       text    DEFAULT 'almacen',
    p_cantidad_base numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_r             record;
    v_n             integer;
    v_i             integer;
    v_j             integer;
    v_base_pres     bigint;
    v_base_nombre   text;
    v_base_idx      integer;
    v_ids           bigint[]  := '{}';
    v_nombres       text[]    := '{}';
    v_factores      numeric[] := '{}';
    v_es_base       boolean[] := '{}';
    v_usable        boolean[] := '{}';
    v_almacenes     bigint[];
    v_tienda        bigint;
    v_cadena_valida boolean := true;
    v_desc_entera   boolean := true;
    v_cadena        jsonb   := '[]'::jsonb;
    v_saldos        jsonb   := '[]'::jsonb;
    v_ubicaciones   jsonb   := '[]'::jsonb;
    v_equiv_total   numeric := 0;
    v_saldo_propio  numeric := 0;
    v_convertible   numeric := 0;
    v_maximo        numeric := 0;
    v_alcanza       boolean;
    v_motivo        text;
    v_neg_pres      bigint;
    v_neg_nombre    text;
    v_neg_ubi       bigint;
BEGIN
    IF p_id_producto IS NULL THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_ARGUMENT',
            'message','p_id_producto es obligatorio');
    END IF;
    IF p_cantidad_base IS NOT NULL AND p_cantidad_base <= 0 THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_QUANTITY',
            'message','La cantidad en unidades base debe ser mayor que cero',
            'id_producto',p_id_producto,'cantidad_base',p_cantidad_base);
    END IF;
    IF p_alcance IS NULL OR p_alcance NOT IN ('almacen','tienda') THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_ARGUMENT',
            'message','p_alcance debe ser ''almacen'' o ''tienda''','alcance',p_alcance);
    END IF;

    -- â”€â”€ Alcance: array de almacenes (NULL = sin filtro) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF p_alcance = 'tienda' THEN
        IF p_id_almacen IS NULL THEN
            RETURN jsonb_build_object(
                'status','error','error_code','INVALID_ARGUMENT',
                'message','El alcance ''tienda'' necesita p_id_almacen para resolver la tienda');
        END IF;
        SELECT a.id_tienda INTO v_tienda FROM public.app_dat_almacen a WHERE a.id = p_id_almacen;
        IF v_tienda IS NULL THEN
            RETURN jsonb_build_object(
                'status','error','error_code','ALMACEN_NOT_FOUND',
                'message',format('El almacen %s no existe',p_id_almacen),'id_almacen',p_id_almacen);
        END IF;
        SELECT array_agg(a.id ORDER BY a.id) INTO v_almacenes
          FROM public.app_dat_almacen a
         WHERE a.id_tienda = v_tienda AND a.deleted_at IS NULL;
    ELSIF p_id_almacen IS NOT NULL THEN
        v_almacenes := ARRAY[p_id_almacen];
    END IF;

    -- â”€â”€ Cadena de presentaciones (nivel 1 = empaque mayor ... n = base) â”€â”€â”€â”€â”€
    FOR v_r IN
        SELECT c.id_presentacion, c.nombre, c.factor_rel, c.es_base, c.nivel
          FROM public.fn_presentaciones_producto(p_id_producto) c
         ORDER BY c.nivel, c.id_presentacion
    LOOP
        v_ids      := v_ids || v_r.id_presentacion;
        v_nombres  := v_nombres || COALESCE(v_r.nombre,'Presentacion')::text;
        v_factores := v_factores || COALESCE(v_r.factor_rel,0);
        v_es_base  := v_es_base || COALESCE(v_r.es_base,false);
        IF v_r.es_base THEN
            v_base_idx    := array_length(v_ids,1);
            v_base_pres   := v_r.id_presentacion;
            v_base_nombre := COALESCE(v_r.nombre,'Presentacion')::text;
        END IF;
    END LOOP;

    v_n := COALESCE(array_length(v_ids,1),0);
    IF v_n = 0 THEN
        RETURN jsonb_build_object(
            'status','error','error_code','PRODUCTO_SIN_PRESENTACIONES',
            'message',format('El producto %s no tiene presentaciones en app_dat_producto_presentacion',p_id_producto),
            'id_producto',p_id_producto);
    END IF;

    -- â”€â”€ Validez de la cadena (la que exige fn_planificar_entrega_fisica_v2) â”€â”€
    IF v_factores[v_n] <> 1 THEN v_cadena_valida := false; END IF;
    FOR v_i IN 1..v_n LOOP
        IF v_factores[v_i] <= 0 THEN v_cadena_valida := false; END IF;
    END LOOP;
    FOR v_i IN 1..(v_n-1) LOOP
        IF v_factores[v_i] <= v_factores[v_i+1] THEN v_cadena_valida := false; END IF;
    END LOOP;
    IF (SELECT count(DISTINCT x) FROM unnest(v_ids) AS u(x)) <> v_n THEN v_cadena_valida := false; END IF;
    -- La base declarada tiene que ser el ultimo nivel (factor_rel = 1). Si
    -- `es_base` esta en una fila con cantidad <> 1 (p.ej. "Docena 12" base sobre
    -- "Unidad 1"), el ultimo factor no es 1 y la cadena NO se puede consumir:
    -- es el caso 'base con cantidad != 1' del plan (no se asume factor = 1).
    IF v_base_idx IS NULL OR v_base_idx <> v_n THEN v_cadena_valida := false; END IF;

    -- â”€â”€ Usabilidad: un nivel solo se puede ABRIR si las relaciones i..base
    --    son TODAS enteras (nunca se sirven fracciones de empaque) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    FOR v_i IN 1..v_n LOOP
        v_usable := v_usable || true;
    END LOOP;
    FOR v_i IN 1..(v_n-1) LOOP
        IF v_factores[v_i] <= 0 OR v_factores[v_i+1] <= 0
           OR (v_factores[v_i] / v_factores[v_i+1]) <> trunc(v_factores[v_i] / v_factores[v_i+1]) THEN
            v_desc_entera := false;
            FOR v_j IN 1..v_i LOOP
                v_usable[v_j] := false;
            END LOOP;
        END IF;
    END LOOP;

    v_cadena := '[]'::jsonb;
    FOR v_i IN 1..v_n LOOP
        v_cadena := v_cadena || jsonb_build_object(
            'nivel',v_i,'id_presentacion',v_ids[v_i],'nombre',v_nombres[v_i],
            'factor_rel',v_factores[v_i],'es_base',v_es_base[v_i],'usable',v_usable[v_i]);
    END LOOP;

    IF NOT v_cadena_valida THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_PRESENTATION_CHAIN',
            'message',format('La cadena de presentaciones del producto %s no es consumible: factores positivos, estrictamente decrecientes, unicos, con la base (factor_rel = 1) en el ultimo nivel',p_id_producto),
            'id_producto',p_id_producto,'id_almacen',p_id_almacen,'alcance',p_alcance,
            'presentacion_base_id',v_base_pres,'presentacion_base',v_base_nombre,
            'cadena',v_cadena,'descomposicion_entera',v_desc_entera);
    END IF;

    -- â”€â”€ Saldos negativos preexistentes: validacion y consumo deciden igual â”€â”€
    SELECT s.id_presentacion, COALESCE(f.nombre,'Presentacion'), s.id_ubicacion
      INTO v_neg_pres, v_neg_nombre, v_neg_ubi
      FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,NULL,false) s
      LEFT JOIN public.fn_presentaciones_producto(p_id_producto) f
             ON f.id_presentacion = s.id_presentacion
     WHERE (v_almacenes IS NULL OR s.id_almacen = ANY(v_almacenes))
       AND s.saldo < 0
     ORDER BY s.id_ubicacion, s.id_presentacion
     LIMIT 1;

    IF v_neg_pres IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status','error','error_code','NEGATIVE_STOCK_PRESENTACION',
            'message',format('El ingrediente %s tiene saldo negativo en %s (ubicacion %s): la validacion y el consumo lo rechazan igual',p_id_producto,v_neg_nombre,v_neg_ubi),
            'id_producto',p_id_producto,'id_almacen',p_id_almacen,'alcance',p_alcance,
            'id_presentacion',v_neg_pres,'presentacion',v_neg_nombre,'id_ubicacion',v_neg_ubi,
            'presentacion_base_id',v_base_pres,'presentacion_base',v_base_nombre,'cadena',v_cadena);
    END IF;

    -- â”€â”€ Saldo agregado por presentacion (para UI y validacion) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    FOR v_r IN
        SELECT COALESCE(f.nivel,999)                          AS nivel,
               s.id_presentacion,
               COALESCE(MAX(f.nombre),'Presentacion')         AS nombre,
               COALESCE(MAX(f.factor_rel),1)                  AS factor_rel,
               COALESCE(bool_or(COALESCE(f.es_base,false)),false) AS es_base,
               SUM(s.saldo)                                   AS saldo
          FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,NULL,false) s
          LEFT JOIN public.fn_presentaciones_producto(p_id_producto) f
                 ON f.id_presentacion = s.id_presentacion
         WHERE (v_almacenes IS NULL OR s.id_almacen = ANY(v_almacenes))
         GROUP BY COALESCE(f.nivel,999), s.id_presentacion
         ORDER BY COALESCE(f.nivel,999), s.id_presentacion
    LOOP
        v_equiv_total := v_equiv_total + COALESCE(v_r.saldo,0) * v_r.factor_rel;
        IF v_r.id_presentacion = v_base_pres THEN
            v_saldo_propio := v_saldo_propio + COALESCE(v_r.saldo,0);
        ELSE
            v_convertible := v_convertible + COALESCE(v_r.saldo,0) * v_r.factor_rel;
        END IF;
        v_saldos := v_saldos || jsonb_build_object(
            'id_presentacion',v_r.id_presentacion,'nombre',v_r.nombre,'nivel',v_r.nivel,
            'factor_rel',v_r.factor_rel,'es_base',v_r.es_base,
            'saldo_fisico',COALESCE(v_r.saldo,0),
            'equivalente_base',COALESCE(v_r.saldo,0) * v_r.factor_rel,
            'usable',COALESCE(v_usable[v_r.nivel],true));
    END LOOP;

    -- â”€â”€ Desglose por ubicacion + maximo consumible con empaques ENTEROS â”€â”€â”€â”€
    FOR v_r IN
        SELECT s.id_ubicacion,
               MIN(s.id_almacen) AS id_almacen,
               COALESCE(SUM(CASE WHEN s.id_presentacion = v_base_pres
                                 THEN s.saldo ELSE 0 END),0) AS saldo_propio,
               COALESCE(SUM(s.saldo * COALESCE(f.factor_rel,1)),0) AS equivalente_base,
               COALESCE(SUM(CASE WHEN s.id_presentacion <> v_base_pres
                                 THEN s.saldo * COALESCE(f.factor_rel,1) ELSE 0 END),0) AS convertible_base,
               COALESCE(SUM(CASE WHEN s.id_presentacion <> v_base_pres
                                  AND COALESCE(v_usable[COALESCE(f.nivel,v_n)],true)
                                 THEN s.saldo * COALESCE(f.factor_rel,1) ELSE 0 END),0) AS convertible_usable
          FROM public.fn_stock_saldos_presentacion(p_id_producto,NULL,NULL,false) s
          LEFT JOIN public.fn_presentaciones_producto(p_id_producto) f
                 ON f.id_presentacion = s.id_presentacion
         WHERE (v_almacenes IS NULL OR s.id_almacen = ANY(v_almacenes))
         GROUP BY s.id_ubicacion
         ORDER BY s.id_ubicacion
    LOOP
        v_maximo := v_maximo
                  + GREATEST(COALESCE(v_r.saldo_propio,0),0)
                  + GREATEST(COALESCE(v_r.convertible_usable,0),0);
        v_ubicaciones := v_ubicaciones || jsonb_build_object(
            'id_ubicacion',v_r.id_ubicacion,'id_almacen',v_r.id_almacen,
            'saldo_propio',COALESCE(v_r.saldo_propio,0),
            'equivalente_base',COALESCE(v_r.equivalente_base,0),
            'convertible_base',COALESCE(v_r.convertible_base,0),
            'convertible_usable',COALESCE(v_r.convertible_usable,0),
            'maximo_producible',GREATEST(COALESCE(v_r.saldo_propio,0),0)
                              + GREATEST(COALESCE(v_r.convertible_usable,0),0));
    END LOOP;

    v_alcanza := (p_cantidad_base IS NULL) OR (v_maximo >= p_cantidad_base);
    v_motivo  := CASE
        WHEN v_alcanza THEN NULL
        WHEN NOT v_desc_entera AND v_equiv_total >= p_cantidad_base
            THEN 'CADENA_NO_DIVISIBLE_EN_ENTEROS'
        ELSE 'STOCK_BASE_INSUFICIENTE'
    END;

    RETURN jsonb_build_object(
        'status','success',
        'id_producto',p_id_producto,
        'id_almacen',p_id_almacen,
        'alcance',p_alcance,
        'cantidad_solicitada_base',p_cantidad_base,
        'presentacion_base_id',v_base_pres,
        'presentacion_base',v_base_nombre,
        'cadena_valida',v_cadena_valida,
        'descomposicion_entera',v_desc_entera,
        'cadena',v_cadena,
        'saldo_por_presentacion',v_saldos,
        'ubicaciones',v_ubicaciones,
        'equivalente_base',v_equiv_total,
        'saldo_propio',v_saldo_propio,
        'convertible_base',v_convertible,
        'maximo_producible',v_maximo,
        'alcanza',v_alcanza,
        'motivo',v_motivo,
        'fuente','fn_ingrediente_base_alcanzable');
END;
$function$;

COMMENT ON FUNCTION public.fn_ingrediente_base_alcanzable(bigint,bigint,text,numeric)
    IS 'KERNEL de medida de un ingrediente en un alcance, EN UNIDADES BASE: equivalente, saldo propio, convertible, maximo consumible con empaques enteros y desglose por ubicacion. STABLE, no escribe. Fuente unica de validacion, consumo y UI. Fase 1, archivo 30.';

REVOKE ALL ON FUNCTION public.fn_ingrediente_base_alcanzable(bigint,bigint,text,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ingrediente_base_alcanzable(bigint,bigint,text,numeric)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 30.3 Â· fn_ingredientes_elaborado_base
-- Medida de la receta completa de un elaborado, en unidades base.
-- STABLE, no escribe. Fuente unica de validacion y de UI de la Fase 1.
--
--   alcanza = true  -> todos los ingredientes tienen equivalente >= requerido y
--                      descomposicion entera posible en el alcance.
--   alcanza = false -> `faltantes[]` con el detalle; `maximo_producible` son
--                      PORCIONES producibles = min(floor(max_ing * cantidad /
--                      requerido_ing)) sobre los ingredientes.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ingredientes_elaborado_base(
    p_id_producto_elaborado bigint,
    p_cantidad              numeric,
    p_id_almacen            bigint,
    p_alcance               text DEFAULT 'almacen'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_r              record;
    v_kernel         jsonb;
    v_nombre         text;
    v_detalle        jsonb := '[]'::jsonb;
    v_faltantes      jsonb := '[]'::jsonb;
    v_hubo_receta    boolean := false;
    v_alcanza        boolean := true;
    v_porciones      numeric;
    v_porciones_ing  numeric;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_QUANTITY',
            'message','La cantidad a producir debe ser positiva',
            'id_producto_elaborado',p_id_producto_elaborado,'cantidad',p_cantidad);
    END IF;

    FOR v_r IN
        SELECT i.id_ingrediente, i.cantidad_total_necesaria
          FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad) i
         ORDER BY i.id_ingrediente
    LOOP
        v_hubo_receta := true;

        v_kernel := public.fn_ingrediente_base_alcanzable(
                        v_r.id_ingrediente, p_id_almacen, p_alcance, v_r.cantidad_total_necesaria);

        IF (v_kernel->>'status') <> 'success' THEN
            -- Problema estructural del ingrediente (cadena invalida, saldo
            -- negativo, sin presentaciones): se corta sin escribir nada.
            RETURN jsonb_build_object(
                'status','error','error_code',v_kernel->>'error_code',
                'message',v_kernel->>'message',
                'id_producto_elaborado',p_id_producto_elaborado,
                'id_ingrediente',v_r.id_ingrediente,
                'id_almacen',p_id_almacen,'alcance',p_alcance,
                'ingrediente_kernel',v_kernel,
                'ingredientes',v_detalle);
        END IF;

        SELECT p.denominacion INTO v_nombre
          FROM public.app_dat_producto p WHERE p.id = v_r.id_ingrediente;

        IF v_r.cantidad_total_necesaria > 0 THEN
            v_porciones_ing := floor((v_kernel->>'maximo_producible')::numeric
                                     * p_cantidad / v_r.cantidad_total_necesaria);
            v_porciones := LEAST(COALESCE(v_porciones, v_porciones_ing), v_porciones_ing);
        END IF;

        IF NOT COALESCE((v_kernel->>'alcanza')::boolean,false) THEN
            v_alcanza := false;
            v_faltantes := v_faltantes || jsonb_build_object(
                'id_ingrediente',v_r.id_ingrediente,
                'ingrediente',COALESCE(v_nombre,'#'||v_r.id_ingrediente),
                'cantidad_requerida_base',v_r.cantidad_total_necesaria,
                'cantidad_disponible',(v_kernel->>'maximo_producible')::numeric,
                'maximo_producible',(v_kernel->>'maximo_producible')::numeric,
                'presentacion',v_kernel->>'presentacion_base',
                'unidad',v_kernel->>'presentacion_base',
                'motivo',v_kernel->>'motivo');
        END IF;

        v_detalle := v_detalle || jsonb_build_object(
            'id_ingrediente',v_r.id_ingrediente,
            'ingrediente',COALESCE(v_nombre,'#'||v_r.id_ingrediente),
            -- La receta suele traer unidad_medida = null (Â§2-bis): la unidad de
            -- cuenta es la presentacion BASE del ingrediente, no ese campo.
            'unidad',COALESCE(v_kernel->>'presentacion_base','unidad base'),
            'cantidad_requerida_base',v_r.cantidad_total_necesaria,
            'presentacion_base_id',(v_kernel->>'presentacion_base_id')::bigint,
            'presentacion_base',v_kernel->>'presentacion_base',
            'equivalente_base',(v_kernel->>'equivalente_base')::numeric,
            'saldo_propio',(v_kernel->>'saldo_propio')::numeric,
            'convertible_base',(v_kernel->>'convertible_base')::numeric,
            'maximo_producible',(v_kernel->>'maximo_producible')::numeric,
            'alcanza',(v_kernel->>'alcanza')::boolean,
            'motivo',v_kernel->>'motivo',
            'descomposicion_entera',(v_kernel->>'descomposicion_entera')::boolean,
            'saldo_por_presentacion',v_kernel->'saldo_por_presentacion',
            'ubicaciones',v_kernel->'ubicaciones');
    END LOOP;

    RETURN jsonb_build_object(
        'status','success',
        'id_producto_elaborado',p_id_producto_elaborado,
        'cantidad',p_cantidad,
        'id_almacen',p_id_almacen,
        'alcance',p_alcance,
        'tiene_receta',v_hubo_receta,
        'unidad_cuenta','unidad_base',
        'alcanza',v_alcanza,
        'maximo_producible',CASE WHEN v_hubo_receta THEN v_porciones ELSE NULL END,
        'faltantes',v_faltantes,
        'ingredientes',v_detalle,
        'fuente','fn_ingrediente_base_alcanzable');
END;
$function$;

COMMENT ON FUNCTION public.fn_ingredientes_elaborado_base(bigint,numeric,bigint,text)
    IS 'Medida de la receta completa de un elaborado EN UNIDADES BASE: cantidad_requerida_base, equivalente_base, presentacion_base_id, saldo_por_presentacion[], ubicaciones[], alcanza y maximo_producible (porciones). STABLE, no escribe. Fuente unica de validacion y UI. Fase 1, archivo 30.';

REVOKE ALL ON FUNCTION public.fn_ingredientes_elaborado_base(bigint,numeric,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ingredientes_elaborado_base(bigint,numeric,bigint,text)
    TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 30.4 Â· fn_consumir_ingrediente_base_v2
-- Consume EXACTAMENTE p_cantidad_base unidades base de un producto en un almacen.
--
-- Algoritmo:
--   1. PRE-VALIDACION sin escribir (kernel): equivalente del alcance y
--      descomposicion entera. Si no alcanza -> error jsonb, CERO filas escritas.
--   2. Pasada 1: ubicaciones con saldo propio de la presentacion base, de mayor a
--      menor saldo y con desempate explicito por id_ubicacion (determinismo).
--   3. Pasada 2: ubicaciones con convertible usable (`convertible_usable` del
--      kernel, ya filtrado por relaciones enteras), de mayor a menor convertible.
--   4. Cada ubicacion se ejecuta con fn_ejecutar_entrega_fisica_v3, que re-planifica
--      contra el ledger vigente y registra la conversion auditada.
--   5. Si algo falla DESPUES de haber escrito, RAISE EXCEPTION: la transaccion
--      completa se revierte (no hay commit parcial, defecto C10).
--
-- p_cantidad_base SIEMPRE en unidades base (equivalente del ingrediente).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_consumir_ingrediente_base_v2(
    p_id_producto   bigint,
    p_id_almacen    bigint,
    p_cantidad_base numeric,
    p_origen_cambio integer DEFAULT 4,
    p_id_extraccion bigint  DEFAULT NULL,
    p_id_operacion  bigint  DEFAULT NULL,
    p_uuid          uuid    DEFAULT NULL,
    p_motivo        text    DEFAULT 'consumo_ingrediente'
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_catalog
AS $function$
DECLARE
    v_kernel         jsonb;
    v_base_pres      bigint;
    v_base_nombre    text;
    v_pendiente      numeric;
    v_ubic           record;
    v_res            jsonb;
    v_a              numeric;
    v_escrito        boolean := false;
    v_usado          numeric := 0;
    v_lineas         integer := 0;
    v_lineas_fisicas jsonb := '[]'::jsonb;
    v_conversiones   jsonb := '[]'::jsonb;
    v_movimientos    jsonb := '[]'::jsonb;
    v_cantidad_disponible numeric;
    v_detalle_error  jsonb;
BEGIN
    IF p_id_producto IS NULL OR p_id_almacen IS NULL THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_ARGUMENT',
            'message','Producto y almacen son obligatorios',
            'id_producto',p_id_producto,'id_almacen',p_id_almacen);
    END IF;
    IF p_cantidad_base IS NULL OR p_cantidad_base <= 0 THEN
        RETURN jsonb_build_object(
            'status','error','error_code','INVALID_QUANTITY',
            'message','La cantidad en unidades base debe ser mayor que cero',
            'id_producto',p_id_producto,'id_almacen',p_id_almacen,'cantidad_base',p_cantidad_base);
    END IF;

    -- â”€â”€ 1 Â· PRE-VALIDACION (sin escribir) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    v_kernel := public.fn_ingrediente_base_alcanzable(p_id_producto, p_id_almacen, 'almacen', p_cantidad_base);

    IF (v_kernel->>'status') <> 'success' THEN
        RETURN v_kernel || jsonb_build_object('id_almacen',p_id_almacen);
    END IF;

    v_base_pres   := (v_kernel->>'presentacion_base_id')::bigint;
    v_base_nombre := v_kernel->>'presentacion_base';

    IF NOT COALESCE((v_kernel->>'alcanza')::boolean,false) THEN
        v_cantidad_disponible := (v_kernel->>'maximo_producible')::numeric;
        v_detalle_error := jsonb_build_object(
            'status','error','error_code','INSUFFICIENT_STOCK_INGREDIENT',
            'message',format('Stock insuficiente para el ingrediente %s: requerido %s %s y el maximo consumible es %s %s',
                             p_id_producto, p_cantidad_base, v_base_nombre,
                             v_cantidad_disponible, v_base_nombre),
            'id_producto',p_id_producto,'id_almacen',p_id_almacen,
            'cantidad_requerida',p_cantidad_base,
            'cantidad_disponible',v_cantidad_disponible,
            'maximo_producible',v_cantidad_disponible,
            'equivalente_base',(v_kernel->>'equivalente_base')::numeric,
            'presentacion',v_base_nombre,'presentacion_base_id',v_base_pres,
            'motivo',v_kernel->>'motivo',
            'saldo_por_presentacion',v_kernel->'saldo_por_presentacion',
            'ubicaciones',v_kernel->'ubicaciones',
            'prevalidacion',v_kernel);
        RETURN v_detalle_error;
    END IF;

    v_pendiente := p_cantidad_base;

    -- â”€â”€ 2 Â· Pasada 1: saldo propio de la presentacion base â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    FOR v_ubic IN
        SELECT s.id_ubicacion, SUM(s.saldo) AS saldo
          FROM public.fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, NULL, false) s
         WHERE s.id_presentacion = v_base_pres
           AND s.saldo > 0
         GROUP BY s.id_ubicacion
        HAVING SUM(s.saldo) > 0
         ORDER BY SUM(s.saldo) DESC, s.id_ubicacion
    LOOP
        EXIT WHEN v_pendiente <= 0;

        v_a := LEAST(v_ubic.saldo, v_pendiente);

        v_res := public.fn_ejecutar_entrega_fisica_v3(
                     p_id_producto       := p_id_producto,
                     p_id_ubicacion      := v_ubic.id_ubicacion,
                     p_id_presentacion   := v_base_pres,
                     p_cantidad          := v_a,
                     p_origen_cambio     := p_origen_cambio,
                     p_id_extraccion     := p_id_extraccion,
                     p_id_operacion      := p_id_operacion,
                     p_uuid              := p_uuid,
                     p_motivo            := p_motivo);

        IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
            IF NOT v_escrito THEN
                RETURN jsonb_build_object(
                    'status','error','error_code','INSUFFICIENT_STOCK_INGREDIENT',
                    'message',format('No se pudo entregar %s %s del producto %s en la ubicacion %s: %s',
                                     v_a, v_base_nombre, p_id_producto, v_ubic.id_ubicacion,
                                     COALESCE(v_res->>'message','error de plan')),
                    'id_producto',p_id_producto,'id_almacen',p_id_almacen,
                    'id_ubicacion',v_ubic.id_ubicacion,
                    'cantidad_requerida',p_cantidad_base,'cantidad_disponible',0,
                    'presentacion',v_base_nombre,'motivo',v_res->>'error_code',
                    'respuesta',v_res);
            END IF;
            RAISE EXCEPTION 'CONSUMO_INGREDIENTE_ABORTADO: no se pudo entregar % % del producto % en la ubicacion % (%)',
                v_a, v_base_nombre, p_id_producto, v_ubic.id_ubicacion,
                COALESCE(v_res->>'message', v_res->>'error_code')
                USING ERRCODE = 'P0001',
                      HINT = 'Habia escrituras previas del mismo consumo: se aborta la transaccion para no dejar descuento parcial (C10).';
        END IF;

        v_escrito := true;
        v_usado   := v_usado + v_a;
        v_pendiente := v_pendiente - v_a;
        v_lineas  := v_lineas + jsonb_array_length(COALESCE(v_res->'entregas_fisicas','[]'::jsonb));
        v_lineas_fisicas := v_lineas_fisicas || COALESCE(v_res->'entregas_fisicas','[]'::jsonb);
        v_conversiones   := v_conversiones   || COALESCE(v_res->'conversiones','[]'::jsonb);
        v_movimientos := v_movimientos || jsonb_build_object(
            'pasada',1,'id_ubicacion',v_ubic.id_ubicacion,'cantidad_base',v_a,
            'estrategia',v_res->>'estrategia',
            'entregas_fisicas',v_res->'entregas_fisicas',
            'conversiones',v_res->'conversiones');
    END LOOP;

    -- â”€â”€ 3 Â· Pasada 2: ubicaciones con convertible usable (abrir empaques) â”€â”€
    IF v_pendiente > 0 THEN
        FOR v_ubic IN
            SELECT (u.value->>'id_ubicacion')::bigint            AS id_ubicacion,
                   (u.value->>'convertible_usable')::numeric     AS convertible_usable
              FROM jsonb_array_elements(COALESCE(v_kernel->'ubicaciones','[]'::jsonb)) AS u(value)
             WHERE (u.value->>'convertible_usable')::numeric > 0
             ORDER BY (u.value->>'convertible_usable')::numeric DESC,
                      (u.value->>'id_ubicacion')::bigint
        LOOP
            EXIT WHEN v_pendiente <= 0;

            v_a := LEAST(v_ubic.convertible_usable, v_pendiente);
            CONTINUE WHEN v_a <= 0;

            v_res := public.fn_ejecutar_entrega_fisica_v3(
                         p_id_producto       := p_id_producto,
                         p_id_ubicacion      := v_ubic.id_ubicacion,
                         p_id_presentacion   := v_base_pres,
                         p_cantidad          := v_a,
                         p_origen_cambio     := p_origen_cambio,
                         p_id_extraccion     := p_id_extraccion,
                         p_id_operacion      := p_id_operacion,
                         p_uuid              := p_uuid,
                         p_motivo            := p_motivo);

            -- En esta pasada un fallo puntual de una ubicacion no es fatal si
            -- queda otra: puede que ahi los empaques no formen la cantidad
            -- entera pedida (la cadena no es divisible).
            IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
                CONTINUE;
            END IF;

            v_escrito := true;
            v_usado   := v_usado + v_a;
            v_pendiente := v_pendiente - v_a;
            v_lineas  := v_lineas + jsonb_array_length(COALESCE(v_res->'entregas_fisicas','[]'::jsonb));
            v_lineas_fisicas := v_lineas_fisicas || COALESCE(v_res->'entregas_fisicas','[]'::jsonb);
            v_conversiones   := v_conversiones   || COALESCE(v_res->'conversiones','[]'::jsonb);
            v_movimientos := v_movimientos || jsonb_build_object(
                'pasada',2,'id_ubicacion',v_ubic.id_ubicacion,'cantidad_base',v_a,
                'estrategia',v_res->>'estrategia',
                'entregas_fisicas',v_res->'entregas_fisicas',
                'conversiones',v_res->'conversiones');
        END LOOP;
    END IF;

    -- â”€â”€ 4 Â· Cierre: pendiente > 0 solo puede pasar si la cadena no es
    --        divisible en enteros; nunca se deja commit parcial â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_pendiente > 0 THEN
        IF NOT v_escrito THEN
            RETURN jsonb_build_object(
                'status','error','error_code','INSUFFICIENT_STOCK_INGREDIENT',
                'message',format('No se pudo cubrir %s de %s %s del producto %s en el almacen %s con empaques enteros',
                                 v_pendiente, p_cantidad_base, v_base_nombre, p_id_producto, p_id_almacen),
                'id_producto',p_id_producto,'id_almacen',p_id_almacen,
                'cantidad_requerida',p_cantidad_base,
                'cantidad_disponible',v_usado,
                'maximo_producible',(v_kernel->>'maximo_producible')::numeric,
                'presentacion',v_base_nombre,
                'motivo','CADENA_NO_DIVISIBLE_EN_ENTEROS',
                'saldo_por_presentacion',v_kernel->'saldo_por_presentacion',
                'ubicaciones',v_kernel->'ubicaciones',
                'prevalidacion',v_kernel);
        END IF;
        RAISE EXCEPTION 'CONSUMO_INGREDIENTE_INCOMPLETO: quedaron % % sin consumir del producto % en el almacen % (descomposicion en empaques enteros imposible)',
            v_pendiente, v_base_nombre, p_id_producto, p_id_almacen
            USING ERRCODE = 'P0001',
                  HINT = 'Habia escrituras previas del mismo consumo: se aborta la transaccion para no dejar descuento parcial (C10).';
    END IF;

    RETURN jsonb_build_object(
        'status','success',
        'id_producto',p_id_producto,
        'id_almacen',p_id_almacen,
        'presentacion_base_id',v_base_pres,
        'presentacion_base',v_base_nombre,
        'cantidad_base',p_cantidad_base,
        'equivalente_consumido',v_usado,
        'lineas_afectadas',v_lineas,
        'lineas_fisicas',v_lineas_fisicas,
        'conversiones',v_conversiones,
        'movimientos',v_movimientos,
        'maximo_producible_previo',(v_kernel->>'maximo_producible')::numeric,
        'executed',true);
END;
$function$;

COMMENT ON FUNCTION public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)
    IS 'Consume una cantidad EXACTA en unidades base de un producto en un almacen: pre-valida equivalente y descomposicion entera (cero escrituras si falla), pasada 1 saldo propio + pasada 2 convertible, con fn_ejecutar_entrega_fisica_v3 (empaques enteros y conversion auditada). RAISE si hay que abortar tras escribir. Fase 1, archivo 30.';

REVOKE ALL ON FUNCTION public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)
    TO authenticated, service_role;


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- V1 Â· Las 4 funciones quedaron creadas y NINGUNA viva cambio.
--
--   SELECT p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname IN (
--      'fn_ejecutar_entrega_fisica_v3','fn_ingrediente_base_alcanzable',
--      'fn_ingredientes_elaborado_base','fn_consumir_ingrediente_base_v2');
--
--   -- md5 de las vivas: deben seguir siendo los de INGREDIENTES_SQL.md Â§10,
--   -- en particular fn_ejecutar_entrega_fisica_v2 = 9edf415b400a467a1d6627a628fd3376
--   SELECT p.proname, md5(pg_get_functiondef(p.oid))
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.proname IN (
--      'fn_ejecutar_entrega_fisica_v2','fn_preview_entrega_fisica_v2',
--      'fn_descontar_ingredientes_elaborado','fn_descontar_venta_enrutada',
--      'fn_validar_ingredientes_elaborado');
--
-- V2 Â· v3 = v2 salvo el search_path (diferencia exacta de una linea):
--
--   SELECT (SELECT prosrc FROM pg_proc WHERE proname='fn_ejecutar_entrega_fisica_v3')
--       = (SELECT prosrc FROM pg_proc WHERE proname='fn_ejecutar_entrega_fisica_v2') AS cuerpo_identico,
--          (SELECT proconfig FROM pg_proc WHERE proname='fn_ejecutar_entrega_fisica_v3') AS sp_v3,
--          (SELECT proconfig FROM pg_proc WHERE proname='fn_ejecutar_entrega_fisica_v2') AS sp_v2;
--   -- esperado: cuerpo_identico = true | sp_v3 = {search_path=public, pg_catalog} | sp_v2 = {search_path=""}
--
-- V3 Â· La guarda ya no revienta con 42P01 (C9). Como vendedor de la tienda 223:
--
--   BEGIN;
--   SET LOCAL role authenticated;
--   SET LOCAL "request.jwt.claims" = '{"sub":"5016cee9-3665-452d-ba75-6d38900e3a1a","role":"authenticated"}';
--   SELECT public.fn_preview_entrega_fisica_v2(11007, 349, 11197, 1);  -- viva: 42P01
--   SELECT public.fn_ejecutar_entrega_fisica_v3(11007, 349, 11197, 1, 4); -- _v3: success
--   ROLLBACK;
--
-- V4 Â· Caso real de produccion (producto 11007 "cerveza cristal", almacen 331,
--      ubicacion 349, medido 2026-10-21): Cajon x30=13 | Caja x24=30 |
--      Blister x6=23 | Unidad x1=2  => equivalente 1250, pero Cajon/Caja no es
--      entero (30/24 = 1.25), asi que el maximo consumible con empaques enteros
--      es 860 (720 + 138 + 2).
--
--   SELECT (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'alcanza'           AS alcanza_1000,
--          (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'maximo_producible' AS maximo,
--          (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 1000))->>'motivo'            AS motivo,
--          (public.fn_ingrediente_base_alcanzable(11007, 331, 'almacen', 860))->>'alcanza'            AS alcanza_860;
--   -- esperado: alcanza_1000 = false | maximo = 860 | motivo = CADENA_NO_DIVISIBLE_EN_ENTEROS | alcanza_860 = true
--
-- V5 Â· Caso real de receta (elaborado 10800 "tacos", tienda 223, almacen 331):
--
--   SELECT public.fn_ingredientes_elaborado_base(10800, 10, 331, 'almacen') AS medida;
--   -- esperado: alcanza = true, ingredientes 10798 (0.3 kg) y 10799 (0.03 kg),
--   --           cada uno con equivalente_base y maximo_producible.
-- ============================================================================