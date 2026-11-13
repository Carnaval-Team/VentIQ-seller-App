-- ============================================================================
-- test_permisos_rpc.sql — guardarraíl de PERMISOS de las RPC del taxi
--
-- POR QUÉ EXISTE ESTE ARCHIVO
--   El 2026-11-13 una llamada real de la app (`POST /rest/v1/rpc/fn_cotizar_viaje`
--   como usuario autenticado) devolvió:
--      42501 permission denied for function fn_punto_en_anillo
--   Causa: `fn_cotizar_viaje`, `fn_zona_de_punto` y `fn_punto_en_poligono` se
--   crearon como SECURITY INVOKER (032), pero delegan en helpers INTERNOS que
--   están revocados para `authenticated`. Todo el cálculo de precio fallaba en
--   producción/para el cliente.
--
--   Las pruebas 038/039/040 NO lo detectaron porque se ejecutan como `postgres`
--   (superusuario): PostgreSQL se salta los permisos y las pruebas pasaban.
--
--   Esta prueba se ejecuta como el rol REAL `authenticated`, con claims de un
--   usuario de `auth.users`, y exige que NINGUNA RPC pública devuelva 42501
--   ("permission denied"). Se aceptan los errores de negocio (P00xx, 28000…):
--   significan que el permiso pasó y la lógica actuó.
--
-- CÓMO SE EJECUTA
--   Un único bloque DO que termina en `RAISE EXCEPTION` con el reporte; la
--   excepción revierte el bloque (no deja basura). Ejecutar con `execute_sql`
--   del proyecto de PRUEBAS (qhprswhhfasrikhawjoz).
--
--   ⚠️ Si el proyecto de pruebas cambia de usuarios, ajusta `v_uid` a cualquier
--   uuid existente en `auth.users`.
-- ============================================================================

DO $test$
DECLARE
  -- Cualquier usuario real de auth (da igual si no tiene perfil: lo que se
  -- prueba es el permiso de ejecución, no la lógica).
  v_uid uuid := '148c8191-2797-44e2-b3c2-9eabd657735c';

  v_sql text[]   := ARRAY[]::text[];
  v_lbl text[]   := ARRAY[]::text[];
  v_L   text[]   := ARRAY[]::text[];
  v_ok  integer  := 0;
  v_n   integer  := 0;
  v_cnt bigint;

  v_st  text;
  v_msg text;
  i     integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_uid) THEN
    SELECT u.id INTO v_uid FROM auth.users u ORDER BY u.created_at LIMIT 1;
  END IF;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sin usuarios en auth.users';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  -- Cambiamos al rol real de la app. A partir de aquí los permisos se aplican.
  EXECUTE 'SET LOCAL ROLE authenticated';

  -- ── Catálogo de RPC a probar ────────────────────────────────────────────
  v_lbl := array_append(v_lbl, 'fn_cotizar_viaje');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_cotizar_viaje(22.406959,-79.965681,22.421228085174683,-79.97167505793266,5,now(),2.8,null,null)$q$);

  v_lbl := array_append(v_lbl, 'fn_punto_en_poligono');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_punto_en_poligono(22.406959,-79.965681,'{"type":"Polygon","coordinates":[[[-79.97,22.40],[-79.96,22.40],[-79.96,22.42],[-79.97,22.42],[-79.97,22.40]]]}'::jsonb)$q$);

  v_lbl := array_append(v_lbl, 'fn_zona_de_punto');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_zona_de_punto(22.406959,-79.965681,now())$q$);

  v_lbl := array_append(v_lbl, 'fn_viajes_disponibles');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_viajes_disponibles(22.406959,-79.965681,5)$q$);

  v_lbl := array_append(v_lbl, 'fn_tomar_viaje');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_tomar_viaje(999999)$q$);

  v_lbl := array_append(v_lbl, 'fn_completar_viaje');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_completar_viaje(999999, null)$q$);

  v_lbl := array_append(v_lbl, 'fn_cancelar_solicitud');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_cancelar_solicitud(999999, 'x')$q$);

  v_lbl := array_append(v_lbl, 'fn_crear_solicitud');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_crear_solicitud(22.406959,-79.965681,22.421228,-79.971675,5,'o','d',2.8,'efectivo',null,null,1)$q$);

  v_lbl := array_append(v_lbl, 'fn_recargar_wallet');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_recargar_wallet('transfermovil', 100, null)$q$);

  v_lbl := array_append(v_lbl, 'fn_gate_seguridad');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_gate_seguridad(auth.uid())$q$);

  v_lbl := array_append(v_lbl, 'fn_usuario_habilitado');
  v_sql := array_append(v_sql, $q$select count(*) from muevete.fn_usuario_habilitado(auth.uid(),'cliente')$q$);

  -- ── Ejecución ───────────────────────────────────────────────────────────
  FOR i IN 1 .. array_length(v_sql, 1) LOOP
    v_n := v_n + 1;
    BEGIN
      EXECUTE v_sql[i] INTO v_cnt;
      v_ok := v_ok + 1;
      v_L := array_append(v_L, format('%s . OK (filas=%s)', v_lbl[i], v_cnt));
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_st = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      IF v_st = '42501' OR v_msg ILIKE '%permission denied%' THEN
        v_L := array_append(v_L,
          format('%s . FALLA DE PERMISOS %s / %s', v_lbl[i], v_st, v_msg));
      ELSE
        -- Error de negocio: el permiso pasó y la RPC actuó. Cuenta como OK.
        v_ok := v_ok + 1;
        v_L := array_append(v_L,
          format('%s . OK (negocio: %s / %s)', v_lbl[i], v_st, v_msg));
      END IF;
    END;
  END LOOP;

  EXECUTE 'RESET ROLE';

  RAISE EXCEPTION E'REPORTE PERMISOS RPC %/%\n%',
    v_ok, v_n, array_to_string(v_L, E'\n');
END
$test$;

-- ============================================================================
-- RESULTADO ESPERADO
-- ----------------------------------------------------------------------------
-- Ninguna línea puede decir "FALLA DE PERMISOS". Ejemplo de salida buena:
--   REPORTE PERMISOS RPC 11/11
--   fn_cotizar_viaje . OK (filas=1)
--   fn_punto_en_poligono . OK (filas=1)
--   fn_zona_de_punto . OK (filas=1)
--   fn_viajes_disponibles . OK (negocio: 28000 / no_es_chofer)
--   fn_crear_solicitud . OK (negocio: P0003 / servicio_en_mantenimiento)
--   ...
--
-- QUÉ HACER SI FALLA
--   El mensaje dice exactamente qué función interna falta. Regla del módulo:
--   las funciones PÚBLICAS (concedidas a `authenticated`) deben ser
--   SECURITY DEFINER con `SET search_path = muevete, pg_temp`, para que los
--   helpers internos (revocados) sigan privados. Es el patrón de 038–040.
-- ============================================================================