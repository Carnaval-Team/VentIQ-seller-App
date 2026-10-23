-- ============================================================================
-- 34 Â· Fase 3 Â· Venta v3/v4: presentaciones + rebalanceo + ingredientes v2
-- ============================================================================
-- Proyecto: LOS DOS (debug qhprswhhfasrikhawjoz y release vsieeihstjaldrdvpuooh)
-- Aplicar DESPUÃ‰S de: 30/31 (cadena _v2 de ingredientes) y, opcionalmente, 45
-- (guard _safe). Este archivo NO TOCA NINGUNA FUNCIÃ“N VIVA: crea `_v3`/`_v4`.
--
-- QUÃ‰ RESUELVE
-- ------------
-- 1. `fn_registrar_venta_v2` / `fn_registrar_venta_mesa_v2` (vivas) delegan el
--    descuento de receta en `fn_descontar_venta_enrutada` (el LEAST mixto) y el
--    descuento del SKU en `fn_ejecutar_entrega_fisica_v2`, que estÃ¡ ROTO con
--    42P01 por heredar `search_path=''` hacia un guard con tablas sin calificar
--    (`docs/_analisis/VERIFICACION_PLAN_2.md`, hallazgo C9).
-- 2. Por eso la app, con 1B, necesita una ruta de venta que use:
--      Â· `fn_ejecutar_entrega_fisica_v3`  (search_path correcto, empaques enteros)
--      Â· `fn_descontar_venta_enrutada_v2` (receta por equivalente base, atÃ³mica)
--    y que NO toque las funciones vivas.
--
-- CÃ“MO LO HACE (patrÃ³n del repo, ver `presentaciones_inventario/17_kardex_...`)
-- ---------------------------------------------------------------------------
-- El `DO` block baja la definiciÃ³n VIVA con `pg_get_functiondef`, aplica dos
-- sustituciones y ABORTA si el conteo no es exacto. AsÃ­ no se transporta a mano
-- un cuerpo de ~16 KB (que es donde se desalinean los UNION/casts).
--
-- REVERTIR
-- --------
--   DROP FUNCTION IF EXISTS public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint);
--   DROP FUNCTION IF EXISTS public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint);
--   DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb);
-- Las funciones vivas no se tocan, asÃ­ que revertir = volver a apuntar el Dart.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 34.1 fn_registrar_venta_v3  (patch de la viva fn_registrar_venta_v2)
-- ----------------------------------------------------------------------------
DO $do$
DECLARE
    v_src   text := 'public.fn_registrar_venta_v2(bigint,uuid,jsonb,text,text,text,smallint,bigint)';
    v_def   text;
    v_new   text;
    v_n     integer;
    v_token text;
BEGIN
    IF to_regprocedure('public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_descontar_venta_enrutada_v2: aplica antes 30/31_ingredientes_v2_rutas.sql';
    END IF;
    IF to_regprocedure('public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_ejecutar_entrega_fisica_v3: aplica antes 30_ingredientes_por_equivalente_base.sql';
    END IF;

    v_def := pg_get_functiondef(v_src::regprocedure);

    -- 1) renombrar SOLO la cabecera
    v_token := 'FUNCTION public.fn_registrar_venta_v2(';
    v_n := (length(v_def) - length(replace(v_def, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 cabecera "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_def, v_token, 'FUNCTION public.fn_registrar_venta_v3(');

    -- 2) ejecutor de SKU con search_path correcto
    v_token := 'fn_ejecutar_entrega_fisica_v2(';
    v_n := (length(v_new) - length(replace(v_new, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 llamada a "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_new, v_token, 'fn_ejecutar_entrega_fisica_v3(');

    -- 3) receta por equivalente base
    v_token := 'fn_descontar_venta_enrutada(';
    v_n := (length(v_new) - length(replace(v_new, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 llamada a "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_new, v_token, 'fn_descontar_venta_enrutada_v2(');

    EXECUTE v_new;
    RAISE NOTICE 'fn_registrar_venta_v3 creada desde la definiciÃ³n viva de la v2';
END
$do$;

COMMENT ON FUNCTION public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint) IS
    'Venta v3: igual que la v2 viva pero con fn_ejecutar_entrega_fisica_v3 (search_path corregido) y fn_descontar_venta_enrutada_v2 (receta por equivalente base). La v2 viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 34.2 fn_registrar_venta_mesa_v3  (patch de la viva fn_registrar_venta_mesa_v2)
-- ----------------------------------------------------------------------------
DO $do$
DECLARE
    v_src   text := 'public.fn_registrar_venta_mesa_v2(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)';
    v_def   text;
    v_new   text;
    v_n     integer;
    v_token text;
BEGIN
    v_def := pg_get_functiondef(v_src::regprocedure);

    v_token := 'FUNCTION public.fn_registrar_venta_mesa_v2(';
    v_n := (length(v_def) - length(replace(v_def, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 cabecera "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_def, v_token, 'FUNCTION public.fn_registrar_venta_mesa_v3(');

    v_token := 'fn_ejecutar_entrega_fisica_v2(';
    v_n := (length(v_new) - length(replace(v_new, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 llamada a "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_new, v_token, 'fn_ejecutar_entrega_fisica_v3(');

    v_token := 'fn_descontar_venta_enrutada(';
    v_n := (length(v_new) - length(replace(v_new, v_token, ''))) / length(v_token);
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 llamada a "%", encontradas %', v_token, v_n;
    END IF;
    v_new := replace(v_new, v_token, 'fn_descontar_venta_enrutada_v2(');

    EXECUTE v_new;
    RAISE NOTICE 'fn_registrar_venta_mesa_v3 creada desde la definiciÃ³n viva de la _mesa_v2';
END
$do$;

COMMENT ON FUNCTION public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint) IS
    'Venta de mesa v3: igual que la _mesa_v2 viva pero con el ejecutor _v3 y la receta _v2. La _mesa_v2 viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 34.3 fn_registrar_venta_offline_v4
-- ----------------------------------------------------------------------------
-- Copia fiel de la viva `fn_registrar_venta_offline_v3` con DOS cambios:
--   Â· llama a `fn_registrar_venta_v3` (no a la v2 rota por C9)
--   Â· `SET search_path = 'public, pg_catalog'` en vez de '' â†’ el guard
--     `check_user_has_access_to_tienda` (tablas sin calificar) resuelve bien.
--     NO depende del patch opcional 46: con search_path correcto el guard vivo
--     funciona; si ademÃ¡s se aplica el 46, sigue funcionando igual.
-- La idempotencia por `client_uuid` se conserva tal cual.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL,
    p_denominacion text DEFAULT NULL,
    p_observaciones text DEFAULT NULL,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL,
    p_fecha_creacion timestamp with time zone DEFAULT NULL,
    p_pagos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
  v_existing_op bigint; v_result jsonb; v_op bigint; v_ok boolean;
  v_id_tienda bigint;
BEGIN
  SELECT t.id_tienda INTO v_id_tienda FROM public.app_dat_tpv t WHERE t.id = p_id_tpv;
  IF v_id_tienda IS NULL THEN
    RETURN jsonb_build_object('status','error','error_code','TPV_NOT_FOUND','message','El TPV no existe');
  END IF;
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

  SELECT i.id_operacion INTO v_existing_op
  FROM public.app_dat_operacion_offline_idempotencia i
  WHERE i.client_uuid = p_client_uuid;
  IF v_existing_op IS NOT NULL THEN
    v_op := v_existing_op;
    v_result := jsonb_build_object('status','success','id_operacion',v_op,'idempotent',true,
                                   'message','OperaciÃ³n ya registrada previamente (idempotente)');
  ELSE
    v_result := public.fn_registrar_venta_v3(p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
                                             p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
    IF v_result IS NULL OR v_result->>'status' IS DISTINCT FROM 'success' THEN RETURN v_result; END IF;
    v_op := NULLIF(v_result->>'id_operacion','')::bigint;
    IF v_op IS NULL THEN RAISE EXCEPTION 'fn_registrar_venta_v3 no devolviÃ³ id_operacion'; END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia(client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_op, 'venta_v4', p_uuid) ON CONFLICT(client_uuid) DO NOTHING;
    IF p_fecha_creacion IS NOT NULL THEN
      UPDATE public.app_dat_operaciones SET created_at = p_fecha_creacion WHERE id = v_op;
      UPDATE public.app_dat_operacion_venta SET created_at = p_fecha_creacion WHERE id_operacion = v_op;
    END IF;
    v_result := v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
  END IF;

  -- Pagos: fn_registrar_pago_venta_v2 es idempotente (reescribe los no liquidados),
  -- asÃ­ que se reparan tambiÃ©n los desgloses parciales de intentos anteriores.
  IF p_pagos IS NOT NULL AND jsonb_typeof(p_pagos) = 'array' AND jsonb_array_length(p_pagos) > 0 THEN
    v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
    IF NOT COALESCE(v_ok, false) THEN
      RAISE EXCEPTION 'No se pudieron registrar los pagos de la operaciÃ³n %', v_op;
    END IF;
    v_result := v_result || jsonb_build_object('pagos_registrados', true);
  END IF;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb) IS
    'Venta offline v4: idempotencia por client_uuid sobre fn_registrar_venta_v3, con search_path corregido para el guard de tienda. La v3 viva no se toca.';

REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb) TO authenticated, service_role;

-- ============================================================================
-- VERIFICACIÃ“N (correr despuÃ©s de aplicar; NO escribe)
-- ============================================================================
-- 1. Existen y con la firma esperada:
--   SELECT to_regprocedure('public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)'),
--          to_regprocedure('public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'),
--          to_regprocedure('public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)');
--
-- 2. Las nuevas llaman a los objetos nuevos y las vivas siguen intactas:
--   SELECT p.proname,
--          p.prosrc LIKE '%fn_ejecutar_entrega_fisica_v3(%'   AS usa_exec_v3,
--          p.prosrc LIKE '%fn_descontar_venta_enrutada_v2(%'  AS usa_receta_v2,
--          p.prosrc LIKE '%fn_registrar_venta_v3(%'           AS usa_venta_v3,
--          md5(pg_get_functiondef(p.oid))                     AS md5
--     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='public'
--      AND p.proname IN ('fn_registrar_venta','fn_registrar_venta_mesa','fn_registrar_venta_v2',
--                        'fn_registrar_venta_mesa_v2','fn_registrar_venta_v3','fn_registrar_venta_mesa_v3',
--                        'fn_registrar_venta_offline_v3','fn_registrar_venta_offline_v4')
--    ORDER BY 1;
--   -- Esperado: md5 de las vivas SIN CAMBIOS (los de docs/_analisis/INGREDIENTES_SQL.md Â§10:
--   --   venta 371402e5..., mesa 74b4751f..., v2 253d9d16..., mesa_v2 6d34466b...).
--
-- 3. Prueba funcional (SIEMPRE en transacciÃ³n, porque escribe ledger):
--   BEGIN;
--     SELECT public.fn_registrar_venta_v3(<id_tpv>, <uuid_usuario>, '<productos jsonb>'::jsonb);
--   ROLLBACK;
--   -- Antes: comparar el saldo de los ingredientes y del SKU; despuÃ©s del ROLLBACK, idÃ©nticos.
-- ============================================================================