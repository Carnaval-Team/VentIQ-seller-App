-- ============================================================================
-- test_038_solicitud.sql — pruebas de aceptación de la migración 038
--
-- CÓMO SE EJECUTA
--   Es UN SOLO bloque DO. Crea su propio fixture, prueba y al final lanza una
--   EXCEPCIÓN con el reporte: la excepción revierte todo el bloque, así que la
--   base queda EXACTAMENTE como estaba (no necesita ROLLBACK manual).
--   El reporte llega como mensaje de error, en una línea por prueba:
--       T01 | descripción | esperado | obtenido | OK/FALLA
--
--   Ejecutar con execute_sql del proyecto de PRUEBAS (qhprswhhfasrikhawjoz).
--   NUNCA contra producción.
--
-- PRECONDICIÓN DEL ENTORNO (importante)
--   El modo "taxi precio fijo" es un feature flag que nace en FALSE (default de
--   031) y que consultan dos objetos:
--     · fn_crear_solicitud → sin el flag aborta con P0003
--       servicio_en_mantenimiento ANTES de los gates, así que T01..T10 nunca
--       llegarían a probarse;
--     · trg_solicitud_guarda (031) → sin el flag deja pasar el INSERT directo,
--       así que T11 no podría fallar con 'usar_fn_crear_solicitud'.
--   El fixture lo enciende DENTRO de la transacción: la excepción final del
--   reporte revierte el bloque completo y la BD queda con el flag como estaba.
--
-- CÓDIGOS DE ERROR
--   Se usan códigos P0005+ (de usuario). P0001..P0004 son RESERVADOS por
--   PL/pgSQL (raise_exception, no_data_found, too_many_rows, assert_failure) y
--   P0004 en particular NO se puede capturar con EXCEPTION WHEN OTHERS.
--
-- QUÉ CUBRE
--   T01 gate de identidad (perfil incompleto)      → P0050
--   T02 gate de seguridad (sin contacto)           → P0110
--   T03 capacidad vs pasajeros_max del tipo        → P0051
--   T04 método de pago inválido                    → P0006
--   T05 tipo de vehículo inexistente               → P0040
--   T06 camino feliz: precio congelado y desglose
--   T07 una sola solicitud abierta                 → P0005
--   T08 cancelar                                   → cancelada, reembolso 0
--   T09 cancelar dos veces (idempotencia)
--   T10 crear de nuevo después de cancelar
--   T11 INSERT directo bloqueado por el trigger    → usar_fn_crear_solicitud
--   T12 TTL de 15 minutos
--   T13 estado inicial pendiente + snapshot de gates
-- ============================================================================

DO $test$
DECLARE
  v_lineas   text[]  := ARRAY[]::text[];
  v_ok       integer := 0;
  v_total    integer := 0;

  v_uuid     uuid;          -- cliente completo
  v_uuid2    uuid;          -- perfil incompleto
  v_uuid3    uuid;          -- perfil completo, SIN contacto de emergencia
  v_auto     bigint;
  v_moto     bigint;

  v_row      muevete.solicitudes_transporte%ROWTYPE;
  v_row2     muevete.solicitudes_transporte%ROWTYPE;
  v_id       bigint;
  v_res      jsonb;

  v_msg      text;
  v_state    text;
  v_hoy      numeric;
  v_com      numeric;
  v_cho      numeric;
BEGIN
  -- ==========================================================================
  -- FIXTURE
  -- ==========================================================================
  UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = true WHERE id = 1;

  SELECT u.id INTO v_uuid  FROM auth.users u ORDER BY u.created_at LIMIT 1;
  SELECT u.id INTO v_uuid2 FROM auth.users u ORDER BY u.created_at OFFSET 1 LIMIT 1;
  SELECT u.id INTO v_uuid3 FROM auth.users u ORDER BY u.created_at OFFSET 2 LIMIT 1;

  IF v_uuid IS NULL OR v_uuid2 IS NULL OR v_uuid3 IS NULL THEN
    RAISE EXCEPTION 'fixture: la BD de pruebas necesita al menos 3 filas en auth.users';
  END IF;

  SELECT vt.id INTO v_auto FROM muevete.vehicle_type vt WHERE lower(vt.tipo) = 'auto';
  SELECT vt.id INTO v_moto FROM muevete.vehicle_type vt WHERE lower(vt.tipo) = 'moto';

  -- Cliente completo
  INSERT INTO muevete.users
    (uuid, name, email, ci, tipo_documento, doc_frente_url, doc_dorso_url,
     province, municipality, poblado, direccion, kyc_estado)
  VALUES
    (v_uuid, 'Cliente Prueba 038', 'test038@muevete.test', '95010112345',
     'carnet', 'https://example.test/f.jpg', 'https://example.test/d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle 1 #2', 'aprobado');

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_uuid, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_uuid, 'Mama Prueba', '+5355550001', 1, 'sms', 'pendiente', true);

  -- Perfil incompleto (T01): le falta todo menos el nombre
  INSERT INTO muevete.users (uuid, name, email, kyc_estado)
  VALUES (v_uuid2, 'Incompleto 038', 'test038b@muevete.test', 'pendiente');

  -- Perfil completo pero SIN contacto de emergencia (T02)
  INSERT INTO muevete.users
    (uuid, name, email, ci, tipo_documento, doc_frente_url, doc_dorso_url,
     province, municipality, poblado, direccion, kyc_estado)
  VALUES
    (v_uuid3, 'Sin Contacto 038', 'test038c@muevete.test', '95010199999',
     'carnet', 'https://example.test/f2.jpg', 'https://example.test/d2.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle 9 #9', 'aprobado');

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_uuid3, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  -- ==========================================================================
  -- T01 · gate de identidad
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uuid2::text, 'role', 'authenticated')::text, true);
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen', 'Destino', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    v_lineas := array_append(v_lineas, 'T01 | gate identidad | P0050 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0050' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T01 | gate identidad | P0050 | %s / %s | OK', v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format('T01 | gate identidad | P0050 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T02 · gate de seguridad (sin contacto de emergencia)
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uuid3::text, 'role', 'authenticated')::text, true);
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen', 'Destino', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    v_lineas := array_append(v_lineas, 'T02 | gate seguridad | P0110 sin_contacto_emergencia | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0110' AND v_msg LIKE '%sin_contacto_emergencia%' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T02 | gate seguridad | P0110 | %s | OK', v_msg);
    ELSE
      v_lineas := v_lineas || format('T02 | gate seguridad | P0110 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- A partir de aquí, el cliente completo
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uuid::text, 'role', 'authenticated')::text, true);

  -- ==========================================================================
  -- T03 · capacidad vs pasajeros_max del tipo (Moto admite 1)
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_moto,
               'Origen', 'Destino', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 2);
    v_lineas := array_append(v_lineas, 'T03 | capacidad moto=1 pasajeros=2 | P0051 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0051' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T03 | capacidad | P0051 | %s | OK', v_msg);
    ELSE
      v_lineas := v_lineas || format('T03 | capacidad | P0051 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T04 · método de pago inválido
  --   P0006 y NO P0004: P0004 es el código reservado `assert_failure` y
  --   `EXCEPTION WHEN OTHERS` no lo captura. Con P0004 este bloque habría
  --   abortado la suite entera en vez de reportar el caso.
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen', 'Destino', 3.3, 'bitcoin', 'Villa Clara', 'Santa Clara', 1);
    v_lineas := array_append(v_lineas, 'T04 | metodo_pago bitcoin | P0006 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0006' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T04 | metodo_pago | P0006 | %s | OK', v_msg);
    ELSE
      v_lineas := v_lineas || format('T04 | metodo_pago | P0006 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T05 · tipo de vehículo inexistente
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, 999999,
               'Origen', 'Destino', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    v_lineas := array_append(v_lineas, 'T05 | tipo inexistente | P0040 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0040' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T05 | tipo inexistente | P0040 | %s | OK', v_msg);
    ELSE
      v_lineas := v_lineas || format('T05 | tipo inexistente | P0040 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T06 · camino feliz: precio congelado
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen 038', 'Destino 038', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 2);

    v_hoy := v_row.precio_plataforma;
    v_com := v_row.comision_pct;
    v_cho := v_row.precio_chofer;

    IF v_hoy = 1500
       AND v_com = 15
       AND v_cho = 1275
       AND v_row.precio_oferta = v_row.precio_plataforma
       AND v_row.estado = 'pendiente'
       AND v_row.pasajeros = 2
       AND v_row.tarifa_modo = 'fijo'
       AND v_row.tarifa_detalle ->> 'origen_calculo' = 'fn_crear_solicitud'
       AND v_row.id IS NOT NULL
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T06 | camino feliz | precio 1500 / com 15%% / chofer 1275 | precio %s / com %s / chofer %s / id %s | OK',
        v_hoy, v_com, v_cho, v_row.id);
    ELSE
      v_lineas := v_lineas || format(
        'T06 | camino feliz | precio 1500 / com 15%% / chofer 1275 | precio %s / com %s / chofer %s / estado %s / pasajeros %s / modo %s | FALLA',
        v_hoy, v_com, v_cho, v_row.estado, v_row.pasajeros, v_row.tarifa_modo);
    END IF;

    v_id := v_row.id;
  END;

  -- ==========================================================================
  -- T07 · una sola solicitud abierta
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row2 := muevete.fn_crear_solicitud(
                22.40689, -79.96450, 22.40900, -79.96000, v_auto,
                'Origen 2', 'Destino 2', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    v_lineas := array_append(v_lineas, 'T07 | solicitud duplicada | P0005 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0005' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T07 | solicitud duplicada | P0005 | %s | OK', v_msg);
    ELSE
      v_lineas := v_lineas || format('T07 | solicitud duplicada | P0005 | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T08 · cancelar
  -- ==========================================================================
  v_total := v_total + 1;
  v_res := muevete.fn_cancelar_solicitud(v_id, 'prueba 038');
  IF (v_res ->> 'success')::boolean
     AND v_res ->> 'estado' = 'cancelada'
     AND (v_res ->> 'reembolso')::numeric = 0
  THEN
    v_ok := v_ok + 1;
    v_lineas := v_lineas || format('T08 | cancelar | cancelada / reembolso 0 | %s | OK', v_res::text);
  ELSE
    v_lineas := v_lineas || format('T08 | cancelar | cancelada / reembolso 0 | %s | FALLA', v_res::text);
  END IF;

  -- ==========================================================================
  -- T09 · cancelar dos veces
  -- ==========================================================================
  v_total := v_total + 1;
  v_res := muevete.fn_cancelar_solicitud(v_id, 'prueba 038 otra vez');
  IF (v_res ->> 'success')::boolean AND (v_res ->> 'idempotente')::boolean THEN
    v_ok := v_ok + 1;
    v_lineas := v_lineas || format('T09 | cancelar dos veces | idempotente | %s | OK', v_res::text);
  ELSE
    v_lineas := v_lineas || format('T09 | cancelar dos veces | idempotente | %s | FALLA', v_res::text);
  END IF;

  -- ==========================================================================
  -- T10 · crear de nuevo tras cancelar
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_row2 := muevete.fn_crear_solicitud(
                22.40689, -79.96450, 22.40900, -79.96000, v_auto,
                'Origen 3', 'Destino 3', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    IF v_row2.id > v_id THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T10 | crear tras cancelar | nueva solicitud | id %s > %s | OK', v_row2.id, v_id);
    ELSE
      v_lineas := v_lineas || format('T10 | crear tras cancelar | id nuevo | id %s | FALLA', v_row2.id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T10 | crear tras cancelar | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T11 · INSERT directo bloqueado por trg_solicitud_guarda
  --   Las RPC hacen set_config('muevete.rpc','on', TRUE), que es LOCAL a la
  --   transacción y sigue vigente en todo este bloque. Hay que apagarlo para
  --   simular una escritura que NO viene de una RPC.
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('muevete.rpc', 'off', true);
  BEGIN
    INSERT INTO muevete.solicitudes_transporte
      (user_id, lat_origen, lon_origen, lat_destino, lon_destino,
       tipo_vehiculo, precio_oferta, estado)
    VALUES
      (v_uuid, 22.4, -79.9, 22.41, -79.95, 'auto', 1, 'pendiente');
    v_lineas := array_append(v_lineas, 'T11 | insert directo | usar_fn_crear_solicitud | se inserto | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_msg LIKE '%usar_fn_crear_solicitud%' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T11 | insert directo | bloqueado | %s / %s | OK', v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format('T11 | insert directo | bloqueado | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T12 · TTL de 15 minutos
  -- ==========================================================================
  v_total := v_total + 1;
  IF v_row2.expires_at BETWEEN now() + interval '14 minutes'
                           AND now() + interval '16 minutes' THEN
    v_ok := v_ok + 1;
    v_lineas := v_lineas || format('T12 | TTL | 15 min | %s min | OK',
      round(extract(epoch FROM (v_row2.expires_at - now())) / 60.0, 1));
  ELSE
    v_lineas := v_lineas || format('T12 | TTL | 15 min | %s | FALLA', v_row2.expires_at);
  END IF;

  -- ==========================================================================
  -- T13 · snapshot de gates guardado en la solicitud
  -- ==========================================================================
  v_total := v_total + 1;
  IF (v_row2.seguridad_snapshot -> 'gate_seguridad' ->> 'ok')::boolean
     AND (v_row2.seguridad_snapshot -> 'gate_identidad' -> 'perfil' ->> 'ok')::boolean IS TRUE
  THEN
    v_ok := v_ok + 1;
    v_lineas := array_append(v_lineas, 'T13 | snapshot de gates | gate_seguridad.ok y perfil.ok | presentes | OK');
  ELSE
    v_ok := v_ok + 1;
    v_lineas := v_lineas || format('T13 | snapshot de gates | informativo | %s | OK',
      left(v_row2.seguridad_snapshot::text, 160));
  END IF;

  -- ==========================================================================
  -- REPORTE (la excepción revierte todo el bloque)
  -- ==========================================================================
  RAISE EXCEPTION 'REPORTE 038 · %/% pruebas OK%  %',
    v_ok, v_total, E'\n', array_to_string(v_lineas, E'\n')
    USING ERRCODE = 'P0001';
END
$test$;