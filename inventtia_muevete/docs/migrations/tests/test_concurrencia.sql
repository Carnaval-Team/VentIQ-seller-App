-- ============================================================================
-- test_concurrencia.sql — "el primero gana" sin necesidad de dos conexiones
--
--   Demuestra el guard del UPDATE atómico de fn_tomar_viaje:
--
--     UPDATE muevete.solicitudes_transporte s
--        SET estado='aceptada', driver_id = <yo>, aceptada_at = now()
--      WHERE s.id = <p> AND s.estado = 'pendiente' AND s.driver_id IS NULL
--        AND (s.expires_at IS NULL OR s.expires_at > now());
--
--   Ese WHERE es exactamente el camino que ejecuta el perdedor bajo
--   concurrencia real: el segundo UPDATE no encuentra la fila (ya la movió el
--   primero), no actualiza nada y fn_tomar_viaje lanza P0020 `ya_tomado`.
--   Por eso no hacen falta dos sesiones con pg_sleep: el resultado es
--   determinista y la prueba es reproducible en cualquier orden.
--
-- CÓMO SE EJECUTA
--   UN SOLO bloque DO. Crea su fixture, prueba y termina lanzando una EXCEPCIÓN
--   con el reporte (una línea por prueba). La excepción revierte TODO el bloque:
--   la base queda como estaba, no hay que hacer ROLLBACK ni limpiar a mano.
--
--   Ejecutar con execute_sql del proyecto de PRUEBAS (qhprswhhfasrikhawjoz).
--   Requiere 038, 039 y 040 aplicadas (y 035/036 para el gate de identidad).
--
-- QUÉ CUBRE
--   T01 cliente publica (auto, efectivo): nace 'pendiente' a 1500
--   T02 chofer A la toma: 'aceptada', driver_id = A, viaje creado
--   T03 chofer B la intenta tomar → P0020 ya_tomado (no P0012: B está libre)
--   T04 chofer B toma un id inexistente → P0020 solicitud_no_existe
--   T05 la solicitud quedó con driver_id de A, estado 'aceptada' y aceptada_at
--   T06 existe UN SOLO viaje para esa solicitud (y es de A)
--   T07 guard atómico: el UPDATE del perdedor afecta 0 filas y no cambia dueño
--   T08 el otro cliente publica una segunda solicitud
--   T09 chofer A no puede tomar otra → P0012 chofer_con_viaje_activo
--   T10 control: B (elegible) sí toma la otra → el P0020 de T03 era el guard
-- ============================================================================

DO $test$
DECLARE
  v_lineas    text[]  := ARRAY[]::text[];
  v_ok        integer := 0;
  v_total     integer := 0;

  v_cliente   uuid;
  v_cliente2  uuid;
  v_chofer_a  uuid;
  v_chofer_b  uuid;

  v_driver_a  bigint;
  v_driver_b  bigint;
  v_veh_a     bigint;
  v_veh_b     bigint;
  v_auto      bigint;

  v_sol       muevete.solicitudes_transporte%ROWTYPE;
  v_sol_id    bigint;
  v_sol2_id   bigint;
  v_viaje_id  bigint;
  v_res       jsonb;

  v_estado    text;
  v_dueno     bigint;
  v_aceptada  timestamptz;
  v_n         integer;
  v_rows      integer;
  v_msg       text;
  v_state     text;
BEGIN
  -- ==========================================================================
  -- FIXTURE
  -- ==========================================================================
  -- El flag de corte viene APAGADO por defecto en la BD. Sin encenderlo,
  -- fn_crear_solicitud y fn_tomar_viaje lanzan 'servicio_en_mantenimiento'
  -- (P0003). Se enciende DENTRO de la transacción: el ROLLBACK implícito del
  -- final lo devuelve a false.
  UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = true WHERE id = 1;

  -- 4 usuarios de auth distintos: cliente 1, cliente 2, chofer A, chofer B.
  SELECT id INTO v_cliente  FROM auth.users ORDER BY created_at, id OFFSET 0 LIMIT 1;
  SELECT id INTO v_cliente2 FROM auth.users ORDER BY created_at, id OFFSET 1 LIMIT 1;
  SELECT id INTO v_chofer_a FROM auth.users ORDER BY created_at, id OFFSET 2 LIMIT 1;
  SELECT id INTO v_chofer_b FROM auth.users ORDER BY created_at, id OFFSET 3 LIMIT 1;

  IF v_cliente IS NULL OR v_cliente2 IS NULL OR v_chofer_a IS NULL OR v_chofer_b IS NULL THEN
    RAISE EXCEPTION 'fixture: hacen falta al menos 4 filas en auth.users (hay menos)';
  END IF;

  SELECT id INTO v_auto FROM muevete.vehicle_type WHERE lower(tipo) = 'auto';
  IF v_auto IS NULL THEN
    RAISE EXCEPTION 'fixture: falta el tipo de vehículo auto (migración 033/035)';
  END IF;

  -- ── Cliente 1 (el que publica el viaje en disputa) ─────────────────────
  INSERT INTO muevete.users
    (uuid, name, email, ci, tipo_documento, doc_frente_url, doc_dorso_url,
     province, municipality, poblado, direccion, kyc_estado)
  VALUES
    (v_cliente, 'Cliente Concurrencia 1', 'conc.cliente1@muevete.test', '91010100001',
     'carnet', 'https://example.test/cc1-f.jpg', 'https://example.test/cc1-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle C1 #1', 'aprobado');

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_cliente, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_cliente, 'Contacto C1', '+5355551001', 1, 'sms', 'pendiente', true);

  -- ── Cliente 2 (sólo para el "otra solicitud" de T08/T09) ───────────────
  INSERT INTO muevete.users
    (uuid, name, email, ci, tipo_documento, doc_frente_url, doc_dorso_url,
     province, municipality, poblado, direccion, kyc_estado)
  VALUES
    (v_cliente2, 'Cliente Concurrencia 2', 'conc.cliente2@muevete.test', '91010100002',
     'carnet', 'https://example.test/cc2-f.jpg', 'https://example.test/cc2-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle C2 #2', 'aprobado');

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_cliente2, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_cliente2, 'Contacto C2', '+5355551002', 1, 'sms', 'pendiente', true);

  -- ── Chofer A ───────────────────────────────────────────────────────────
  INSERT INTO muevete.vehiculos (marca, modelo, chapa, id_tipo_vehiculo, capacidad_int, color)
  VALUES ('Lada', '2107', 'CONC0A', v_auto, 4, 'Azul')
  RETURNING id INTO v_veh_a;

  INSERT INTO muevete.drivers
    (uuid, name, telefono, estado, kyc, kyc_estado, ci, tipo_documento,
     doc_frente_url, doc_dorso_url, province, municipality, poblado, direccion,
     vehiculo)
  VALUES
    (v_chofer_a, 'Chofer A Concurrencia', '+5355552001', true, true, 'aprobado', '91010100011',
     'carnet', 'https://example.test/ca-f.jpg', 'https://example.test/ca-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle A #10', v_veh_a)
  RETURNING id INTO v_driver_a;

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_chofer_a, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_chofer_a, 'Contacto A', '+5355552002', 1, 'sms', 'pendiente', true);

  INSERT INTO muevete.place (driver, latitude, longitude, estado)
  VALUES (v_driver_a, 22.40689, -79.96450, true);

  INSERT INTO muevete.wallet_drivers (driver_id, balance)
  VALUES (v_driver_a, 0);

  -- ── Chofer B (misma zona, sin viaje: el perdedor de la carrera) ────────
  INSERT INTO muevete.vehiculos (marca, modelo, chapa, id_tipo_vehiculo, capacidad_int, color)
  VALUES ('Lada', '2107', 'CONC0B', v_auto, 4, 'Rojo')
  RETURNING id INTO v_veh_b;

  INSERT INTO muevete.drivers
    (uuid, name, telefono, estado, kyc, kyc_estado, ci, tipo_documento,
     doc_frente_url, doc_dorso_url, province, municipality, poblado, direccion,
     vehiculo)
  VALUES
    (v_chofer_b, 'Chofer B Concurrencia', '+5355552003', true, true, 'aprobado', '91010100012',
     'carnet', 'https://example.test/cb-f.jpg', 'https://example.test/cb-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle B #11', v_veh_b)
  RETURNING id INTO v_driver_b;

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_chofer_b, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_chofer_b, 'Contacto B', '+5355552004', 1, 'sms', 'pendiente', true);

  INSERT INTO muevete.place (driver, latitude, longitude, estado)
  VALUES (v_driver_b, 22.40689, -79.96450, true);

  INSERT INTO muevete.wallet_drivers (driver_id, balance)
  VALUES (v_driver_b, 0);

  -- ==========================================================================
  -- T01 · el cliente publica (auto, efectivo)
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cliente::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_sol := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen concurrencia', 'Destino concurrencia', 3.3, 'efectivo',
               'Villa Clara', 'Santa Clara', 1);
    v_sol_id := v_sol.id;

    IF v_sol.estado = 'pendiente'
       AND v_sol.driver_id IS NULL
       AND v_sol.precio_plataforma = 1500
       AND v_sol.metodo_pago = 'efectivo'
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T01 | cliente publica auto/efectivo | pendiente, sin chofer, 1500 | %s / driver=%s / %s | OK',
        v_sol.estado, coalesce(v_sol.driver_id::text, 'null'), v_sol.precio_plataforma);
    ELSE
      v_lineas := v_lineas || format(
        'T01 | cliente publica auto/efectivo | pendiente, sin chofer, 1500 | %s / driver=%s / %s | FALLA',
        v_sol.estado, coalesce(v_sol.driver_id::text, 'null'), v_sol.precio_plataforma);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T01 | cliente publica | OK | %s / %s | FALLA', v_state, v_msg);
    v_sol_id := NULL;
  END;

  -- ==========================================================================
  -- T02 · el chofer A la toma
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_chofer_a::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol_id);
    v_viaje_id := (v_res ->> 'viaje_id')::bigint;

    IF coalesce((v_res ->> 'success')::boolean, false)
       AND v_viaje_id IS NOT NULL
       AND (v_res ->> 'precio_plataforma')::numeric = 1500
       AND (v_res ->> 'comision_monto')::numeric = 225
       AND (v_res ->> 'precio_chofer')::numeric = 1275
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T02 | chofer A toma | success, viaje creado, 1500/225/1275 | viaje=%s, %s/%s/%s | OK',
        v_viaje_id, v_res ->> 'precio_plataforma', v_res ->> 'comision_monto', v_res ->> 'precio_chofer');
    ELSE
      v_lineas := v_lineas || format('T02 | chofer A toma | success y viaje | %s | FALLA',
        left(v_res::text, 300));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T02 | chofer A toma | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T03 · el chofer B la intenta tomar → P0020 ya_tomado (NO P0012)
  --       B está online, aprobado y SIN viaje activo: lo único que lo frena
  --       es el guard de la solicitud.
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_chofer_b::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol_id);
    v_lineas := v_lineas || format(
      'T03 | chofer B toma la misma | P0020 ya_tomado | devolvió %s (sin error) | FALLA',
      left(v_res::text, 200));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0020' AND v_msg = 'ya_tomado' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T03 | chofer B toma la misma | P0020 ya_tomado | %s / %s | OK',
        v_state, v_msg);
    ELSIF v_state = 'P0012' THEN
      v_lineas := v_lineas || format(
        'T03 | chofer B toma la misma | P0020 ya_tomado | %s / %s (B quedó con viaje activo: fixture mal armado) | FALLA',
        v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format('T03 | chofer B toma la misma | P0020 ya_tomado | %s / %s | FALLA',
        v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T04 · el chofer B toma un id que no existe → P0020 solicitud_no_existe
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_res := muevete.fn_tomar_viaje(-987654321);
    v_lineas := v_lineas || format(
      'T04 | id inexistente | P0020 solicitud_no_existe | devolvió %s (sin error) | FALLA',
      left(v_res::text, 200));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0020' AND v_msg = 'solicitud_no_existe' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T04 | id inexistente | P0020 solicitud_no_existe | %s / %s | OK',
        v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format(
        'T04 | id inexistente | P0020 solicitud_no_existe | %s / %s | FALLA', v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T05 · la solicitud quedó con el driver de A, 'aceptada' y con aceptada_at
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    SELECT estado, driver_id, aceptada_at
      INTO v_estado, v_dueno, v_aceptada
      FROM muevete.solicitudes_transporte
     WHERE id = v_sol_id;

    IF v_estado = 'aceptada' AND v_dueno = v_driver_a AND v_aceptada IS NOT NULL THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T05 | estado final solicitud | aceptada / driver A / aceptada_at | %s / driver=%s / %s | OK',
        v_estado, v_dueno, v_aceptada);
    ELSE
      v_lineas := v_lineas || format(
        'T05 | estado final solicitud | aceptada / driver A / aceptada_at | %s / driver=%s / %s | FALLA',
        v_estado, v_dueno, v_aceptada);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T05 | estado final solicitud | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T06 · exactamente UN viaje para esa solicitud, y es de A
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    SELECT count(*) INTO v_n
      FROM muevete.viajes v
     WHERE v.solicitud_id = v_sol_id;

    IF v_n = 1
       AND EXISTS (SELECT 1 FROM muevete.viajes v
                    WHERE v.solicitud_id = v_sol_id AND v.driver_id = v_driver_a)
       AND NOT EXISTS (SELECT 1 FROM muevete.viajes v
                        WHERE v.solicitud_id = v_sol_id AND v.driver_id = v_driver_b)
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T06 | un solo viaje | 1 viaje, de A, ninguno de B | %s viaje(s) | OK',
        v_n);
    ELSE
      v_lineas := v_lineas || format('T06 | un solo viaje | 1 viaje, de A, ninguno de B | %s viaje(s) | FALLA',
        v_n);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T06 | un solo viaje | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T07 · el guard atómico, en crudo: el UPDATE del perdedor no toca nada
  --       (es la sentencia exacta de fn_tomar_viaje §8, ejecutada por B).
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    UPDATE muevete.solicitudes_transporte s
       SET estado      = 'aceptada',
           driver_id   = v_driver_b,
           aceptada_at = now()
     WHERE s.id = v_sol_id
       AND s.estado = 'pendiente'
       AND s.driver_id IS NULL
       AND (s.expires_at IS NULL OR s.expires_at > now());

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    SELECT driver_id, estado INTO v_dueno, v_estado
      FROM muevete.solicitudes_transporte WHERE id = v_sol_id;

    IF v_rows = 0 AND v_dueno = v_driver_a AND v_estado = 'aceptada' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T07 | guard UPDATE perdedor | 0 filas, dueño sigue A | %s fila(s), driver=%s | OK',
        v_rows, v_dueno);
    ELSE
      v_lineas := v_lineas || format(
        'T07 | guard UPDATE perdedor | 0 filas, dueño sigue A | %s fila(s), driver=%s, %s | FALLA',
        v_rows, v_dueno, v_estado);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T07 | guard UPDATE perdedor | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T08 · el OTRO cliente publica la segunda solicitud
  --       Va en su propio bloque a propósito: cuando un bloque PL/pgSQL captura
  --       una excepción, restaura TODAS sus variables al valor de entrada, así
  --       que si la toma fallida de T09 estuviera en el mismo bloque que esta
  --       creación, v_sol2_id volvería a NULL. La solicitud va primero, aparte.
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cliente2::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_sol := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40850, -79.96200, v_auto,
               'Origen C2', 'Destino C2', 2.1, 'efectivo',
               'Villa Clara', 'Santa Clara', 1);
    v_sol2_id := v_sol.id;

    IF v_sol2_id IS NOT NULL AND v_sol.estado = 'pendiente' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T08 | cliente 2 publica la otra | pendiente, 1500 | id=%s / %s | OK',
        v_sol2_id, v_sol.estado);
    ELSE
      v_lineas := v_lineas || format(
        'T08 | cliente 2 publica la otra | pendiente, 1500 | id=%s / %s | FALLA',
        v_sol2_id, v_sol.estado);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T08 | cliente 2 publica la otra | OK | %s / %s | FALLA',
      v_state, v_msg);
  END;

  -- ==========================================================================
  -- T09 · A, que ya tiene viaje, no puede tomar otra → P0012
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_chofer_a::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol2_id);

    v_lineas := v_lineas || format(
      'T09 | A toma otra (ya tiene viaje) | P0012 chofer_con_viaje_activo | devolvió %s (sin error) | FALLA',
      left(v_res::text, 200));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0012' AND v_msg = 'chofer_con_viaje_activo' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T09 | A toma otra (ya tiene viaje) | P0012 chofer_con_viaje_activo | %s / %s | OK',
        v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format(
        'T09 | A toma otra (ya tiene viaje) | P0012 chofer_con_viaje_activo | %s / %s | FALLA',
        v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T10 · control: B, que no tiene viaje, sí puede tomar la otra.
  --       Esto demuestra que el P0020 de T03 no venía de un bloqueo de B
  --       (deuda, zona, KYC ni capacidad): venía del guard de la solicitud.
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_chofer_b::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol2_id);

    IF coalesce((v_res ->> 'success')::boolean, false)
       AND (v_res ->> 'viaje_id') IS NOT NULL
       AND EXISTS (SELECT 1 FROM muevete.solicitudes_transporte s
                    WHERE s.id = v_sol2_id
                      AND s.driver_id = v_driver_b
                      AND s.estado = 'aceptada')
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format(
        'T10 | control: B sí toma la otra | success, driver B, aceptada | viaje=%s, driver=%s | OK',
        v_res ->> 'viaje_id', v_driver_b);
    ELSE
      v_lineas := v_lineas || format(
        'T10 | control: B sí toma la otra | success, driver B | %s | FALLA', left(v_res::text, 300));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T10 | control: B sí toma la otra | OK | %s / %s | FALLA',
      v_state, v_msg);
  END;

  -- ==========================================================================
  -- REPORTE (la excepción revierte todo el bloque)
  -- ==========================================================================
  RAISE EXCEPTION 'REPORTE concurrencia · %/% pruebas OK%  %',
    v_ok, v_total, E'\n', array_to_string(v_lineas, E'\n')
    USING ERRCODE = 'P0001';
END
$test$;