-- Solo newa (qhprswhhfasrikhawjoz). No ejecutar en main.
--
-- Trae de main (vsieeihstajlrdvpuooh) las 12 funciones donde main está más
-- nueva (docs/plan-multimoneda/comparacion_funciones_newa_main.md, sección C).
-- El objetivo es que md5(prosrc) quede igual que en main; el bloque final lo
-- comprueba y aborta todo si no coincide.
--
-- * 8 funciones solo difieren en el precio vigente: main ordena por id, newa
--   por fecha_desde. Se parchea la definición viva de newa.
-- * 4 funciones se copian enteras de main.
-- * Main guarda casi todos los cuerpos con CRLF. Para que un editor no rompa
--   la huella al normalizar finales de línea, los cuerpos se reconstruyen en el
--   servidor (todo CRLF salvo fn_listar_motivos_extraccion, que en main es LF).
-- * Main no concede EXECUTE a PUBLIC en fn_check_update.
--
-- Idempotente: se puede volver a ejecutar.

BEGIN;

DO $pre$
BEGIN
  IF to_regproc('public.fn_version_menor') IS NULL
     OR to_regproc('public.fn_carnaval_precio_base_vigente') IS NULL
     OR to_regproc('public.fn_carnaval_porcientos_tienda') IS NULL THEN
    RAISE EXCEPTION 'Faltan funciones auxiliares (fn_version_menor / fn_carnaval_*)';
  END IF;
  IF to_regclass('public.precio_global_productos_carnaval') IS NULL
     OR to_regclass('carnavalapp."Productos"') IS NULL THEN
    RAISE EXCEPTION 'Faltan tablas de Carnaval';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'app_versiones'
         AND column_name IN ('id', 'titulo', 'novedades', 'url_descarga')) <> 4 THEN
    RAISE EXCEPTION 'app_versiones no tiene id/titulo/novedades/url_descarga';
  END IF;
END
$pre$;

-- 1) Precio vigente por id mayor en las 8 funciones de catálogo.
DO $orden$
DECLARE
  v_sig text;
  v_def text;
  v_viejo constant text := 'ORDER BY id_producto, fecha_desde DESC';
  v_nuevo constant text := 'ORDER BY id_producto, id DESC';
  v_veces int;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.buscar_producto_por_codigo_barras_v3(text)',
    'public.get_productos_completos_by_tienda_optimized_provider(bigint,bigint,boolean,integer)',
    'public.get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer,boolean)',
    'public.get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer)',
    'public.get_productos_completos_by_tienda_optimized_v2(bigint,bigint,boolean,boolean)',
    'public.get_productos_completos_by_tienda_optimized(integer,integer,boolean)',
    'public.get_productos_completos_by_tienda_optimized2(bigint,bigint,boolean,boolean)',
    'public.get_productos_completos_by_tienda_with_supplier(integer,integer,boolean,integer)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION 'Falta la función %', v_sig;
    END IF;
    v_def := pg_get_functiondef(to_regprocedure(v_sig));
    v_veces := (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo);
    IF v_veces = 0 AND position(v_nuevo IN v_def) > 0 THEN
      CONTINUE;
    END IF;
    IF v_veces <> 1 THEN
      RAISE EXCEPTION '% tiene % apariciones del orden por fecha (se esperaba 1)', v_sig, v_veces;
    END IF;
    EXECUTE replace(v_def, v_viejo, v_nuevo);
  END LOOP;
END
$orden$;

-- 2) Cuerpos completos de main.
DO $copiar$
BEGIN
  EXECUTE replace(replace($def$CREATE OR REPLACE FUNCTION public.fn_check_update(p_app_name character varying, p_version_actual character varying, p_build_actual integer)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_latest       public.app_versiones%rowtype;
  v_hay          boolean := false;
  v_build_actual integer := coalesce(p_build_actual, 0);
begin
  -- Última versión activa de la app. `id` como desempate: si dos filas
  -- comparten build, gana la insertada después.
  select v.* into v_latest
  from public.app_versiones v
  where v.app_name = p_app_name
    and v.activa = true
  order by v.build_number desc, v.id desc
  limit 1;

  if found and coalesce(v_latest.build_number, 0) > v_build_actual then
    v_hay := true;
  end if;

  return json_build_object(
    -- ── claves originales (mismo significado) ──
    'hay_actualizacion',  v_hay,
    'version_disponible', coalesce(v_latest.version_actual, ''),
    'obligatoria',        coalesce(v_latest.actualizacion_obligatoria, false)
                          or public.fn_version_menor(p_version_actual, v_latest.version_minima),
    'version_minima',     coalesce(v_latest.version_minima, ''),
    'fecha_lanzamiento',  coalesce(v_latest.fecha_lanzamiento, now()),
    -- ── claves nuevas (72/75: null o [] cuando no hay actualización) ──
    'id_version',         case when v_hay then v_latest.id else null end,
    'build_disponible',   case when v_hay then v_latest.build_number else null end,
    'titulo',             case when v_hay then v_latest.titulo else null end,
    'novedades',          case
                            when v_hay and jsonb_typeof(v_latest.novedades) = 'array'
                              then v_latest.novedades
                            else '[]'::jsonb
                          end,
    'url_descarga',       case when v_hay then v_latest.url_descarga else null end
  );
end;
$function$
$def$, E'\r\n', E'\n'), E'\n', E'\r\n');

  EXECUTE replace($def$CREATE OR REPLACE FUNCTION public.fn_listar_motivos_extraccion()
 RETURNS TABLE(id bigint, denominacion character varying, descripcion character varying, es_activo boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    -- Solo se exige que el usuario este autenticado.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Devolver los motivos (catalogo global de solo lectura).
    RETURN QUERY
    SELECT
        me.id,
        me.denominacion,
        me.descripcion,
        (me.created_at IS NOT NULL) AS es_activo,
        me.created_at
    FROM public.app_nom_motivo_extraccion me
    ORDER BY me.denominacion;
END;
$function$
$def$, E'\r\n', E'\n');

  EXECUTE replace(replace($def$CREATE OR REPLACE FUNCTION public.fn_update_carnaval_product_prices()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actualizados INTEGER := 0;
BEGIN
    WITH productos AS (
        SELECT p.id_vendedor_app,
               public.fn_carnaval_precio_base_vigente(p.id) AS precio_base,
               GREATEST(COALESCE(pg.precio_venta_carnaval,
                                 NEW.porciento_efectivo),
                        NEW.porciento_efectivo)  AS pct_efectivo,
               GREATEST(COALESCE(pg.precio_venta_carnaval_transferencia,
                                 NEW.porciento_transferencia),
                        NEW.porciento_transferencia) AS pct_transferencia
        FROM public.app_dat_producto p
        LEFT JOIN public.app_dat_precio_general_tienda pg
               ON pg.id_tienda = p.id_tienda
        WHERE p.id_vendedor_app IS NOT NULL
          AND p.deleted_at IS NULL
    )
    UPDATE carnavalapp."Productos" cp
       SET price            = ROUND(pr.precio_base * (1 + pr.pct_transferencia / 100)),
           precio_descuento = ROUND(pr.precio_base * (1 + pr.pct_efectivo      / 100)),
           updated_at       = NOW()
      FROM productos pr
     WHERE cp.id = pr.id_vendedor_app
       AND pr.precio_base IS NOT NULL
       AND pr.precio_base > 0
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE '[piso_global] Productos recalculados: %.', v_actualizados;

    -- updated_at del global no se auto-actualiza en UPDATE;
    -- solo tocamos esa columna para no re-disparar este trigger
    -- (esta definido como UPDATE OF porciento_*).
    UPDATE public.precio_global_productos_carnaval
       SET updated_at = NOW()
     WHERE id = NEW.id;

    RETURN NEW;
END;
$function$
$def$, E'\r\n', E'\n'), E'\n', E'\r\n');

  EXECUTE replace(replace($def$CREATE OR REPLACE FUNCTION public.sync_price_to_carnaval()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id_vendedor_app   BIGINT;
    v_id_tienda         BIGINT;
    v_base_price        NUMERIC;
    v_pct_efectivo      NUMERIC;
    v_pct_transferencia NUMERIC;
    v_precio_descuento  NUMERIC;
    v_precio_oficial    NUMERIC;
BEGIN
    IF TG_OP NOT IN ('INSERT', 'UPDATE') THEN
        RETURN NEW;
    END IF;

    -- Cerrar/reabrir fechas (u otros metadatos) NO debe
    -- reescribir Carnaval con el precio de esa fila.
    IF TG_OP = 'UPDATE'
       AND NEW.precio_venta_cup IS NOT DISTINCT FROM OLD.precio_venta_cup
       AND NEW.precio_venta_usd IS NOT DISTINCT FROM OLD.precio_venta_usd
       AND NEW.precio_descuento IS NOT DISTINCT FROM OLD.precio_descuento
    THEN
        RETURN NEW;
    END IF;

    SELECT p.id_vendedor_app, p.id_tienda
      INTO v_id_vendedor_app, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    IF v_id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Siempre el vigente mas reciente por id (no NEW a ciegas).
    v_base_price := public.fn_carnaval_precio_base_vigente(NEW.id_producto);

    IF v_base_price IS NULL OR v_base_price <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(v_id_tienda);

    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RETURN NEW;
    END IF;

    v_precio_descuento := ROUND(v_base_price * (1 + v_pct_efectivo      / 100));
    v_precio_oficial   := ROUND(v_base_price * (1 + v_pct_transferencia / 100));

    UPDATE carnavalapp."Productos"
       SET price            = v_precio_oficial,
           precio_descuento = v_precio_descuento,
           updated_at       = NOW()
     WHERE id = v_id_vendedor_app
       AND COALESCE(proveedor, 0) <> 3;

    RETURN NEW;
END;
$function$
$def$, E'\r\n', E'\n'), E'\n', E'\r\n');
END
$copiar$;

REVOKE ALL ON FUNCTION public.fn_check_update(character varying, character varying, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_check_update(character varying, character varying, integer)
  TO anon, authenticated, service_role;

-- 3) Huellas de main (md5(prosrc), tomadas el 2026-11-20).
DO $verif$
DECLARE
  v record;
  v_md5 text;
BEGIN
  FOR v IN SELECT * FROM (VALUES
    ('public.buscar_producto_por_codigo_barras_v3(text)', '73306441fd99a92b3765105f88385b45'),
    ('public.fn_check_update(character varying,character varying,integer)', '112e9101d04c14ff417ef7c04feffa1a'),
    ('public.fn_listar_motivos_extraccion()', 'b5ffeaf89dc49a1421b4d490a346e0cf'),
    ('public.fn_update_carnaval_product_prices()', '039a999ba1c1b2f0ffa5c614ab7ea1bb'),
    ('public.get_productos_completos_by_tienda_optimized_provider(bigint,bigint,boolean,integer)', 'b03f3caabaa10363a9b6e2cf09865a9f'),
    ('public.get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer,boolean)', 'fbcc3d5daf34bf19350d58f5f1f461cd'),
    ('public.get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer)', 'd300f4f919acd0e9cfdeb41e9f11d289'),
    ('public.get_productos_completos_by_tienda_optimized_v2(bigint,bigint,boolean,boolean)', '9ac2d5649de0290ef21d84b133f8fdfd'),
    ('public.get_productos_completos_by_tienda_optimized(integer,integer,boolean)', 'ade12329400851570521ca6a47cc1214'),
    ('public.get_productos_completos_by_tienda_optimized2(bigint,bigint,boolean,boolean)', 'b83f9858420d0a1424df31bcb2fcc752'),
    ('public.get_productos_completos_by_tienda_with_supplier(integer,integer,boolean,integer)', '322e5dd3ce0bc1fe0a4759e2de30e4dd'),
    ('public.sync_price_to_carnaval()', '6401eca8bc810a3951033661f76c4b3b')
  ) AS t(sig, huella) LOOP
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(v.sig);
    IF v_md5 IS DISTINCT FROM v.huella THEN
      RAISE EXCEPTION 'Huella distinta en %: % (main %)', v.sig, v_md5, v.huella;
    END IF;
  END LOOP;
  IF has_function_privilege('public',
       'public.fn_check_update(character varying,character varying,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'fn_check_update sigue ejecutable por PUBLIC';
  END IF;
END
$verif$;

COMMIT;
