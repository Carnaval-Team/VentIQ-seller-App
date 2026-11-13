-- ============================================================================
-- test_039_040_flujo.sql — prueba de extremo a extremo del flujo sin negociación
--
--   cliente publica → chofer ve → chofer toma → cliente cancela (con reembolso)
--   → cliente publica otra vez → chofer toma → chofer completa → recarga
--
-- CÓMO SE EJECUTA
--   UN SOLO bloque DO. Crea su fixture, prueba y termina lanzando una EXCEPCIÓN
--   con el reporte (una línea por prueba). La excepción revierte TODO el bloque:
--   la base queda como estaba, no hay que hacer ROLLBACK.
--
--   Ejecutar con execute_sql del proyecto de PRUEBAS (qhprswhhfasrikhawjoz).
--   Requiere 038, 039 y 040 aplicadas.
--
-- QUÉ CUBRE
--   T01 cliente crea solicitud con wallet (precio congelado 1500)
--   T02 el chofer la ve en su lista, con su parte (1275) y puede_tomar=true
--   T03 el chofer la toma: retención 1500 al cliente, viaje creado
--   T04 segunda toma del mismo chofer → chofer_con_viaje_activo (P0012)
--   T05 el cliente cancela → reembolso 1500 y saldo restaurado
--   T06 nuevo viaje en efectivo, tomado y completado: comisión 225, chofer 1275
--   T07 completar dos veces → idempotente y sin mover saldos otra vez
--   T08 recarga de wallet: 1000 + % de config (11 % => 1110)
-- ============================================================================

DO $test$
DECLARE
  v_lineas    text[]  := ARRAY[]::text[];
  v_ok        integer := 0;
  v_total     integer := 0;

  v_cliente   uuid;
  v_chofer    uuid;
  v_driver    bigint;
  v_vehiculo  bigint;
  v_auto      bigint;

  v_sol       muevete.solicitudes_transporte%ROWTYPE;
  v_sol_id    bigint;
  v_viaje_id  bigint;
  v_res       jsonb;
  v_n         integer;
  v_saldo     numeric;
  v_lista     jsonb[];
  v_item      jsonb;

  v_msg       text;
  v_state     text;
  v_drv_row   muevete.drivers%ROWTYPE;
BEGIN
  -- ==========================================================================
  -- FIXTURE
  -- ==========================================================================
  -- El flag de corte de precio fijo viene APAGADO por defecto en la BD (para no
  -- estorbar a las apps viejas). Sin encenderlo, fn_crear_solicitud lanza
  -- 'servicio_en_mantenimiento' (P0003). Se enciende DENTRO de la transacción:
  -- el ROLLBACK implícito del final lo devuelve a false.
  UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = true WHERE id = 1;

  SELECT id INTO v_cliente FROM auth.users ORDER BY created_at LIMIT 1;
  SELECT id INTO v_chofer  FROM auth.users ORDER BY created_at OFFSET 1 LIMIT 1;

  IF v_cliente IS NULL OR v_chofer IS NULL THEN
    RAISE EXCEPTION 'fixture: hacen falta al menos 2 filas en auth.users';
  END IF;

  SELECT id INTO v_auto FROM muevete.vehicle_type WHERE lower(tipo) = 'auto';
  IF v_auto IS NULL THEN
    RAISE EXCEPTION 'fixture: falta el tipo de vehículo auto (migración 033/035)';
  END IF;

  -- ── Cliente ────────────────────────────────────────────────────────────
  INSERT INTO muevete.users
    (uuid, name, email, ci, tipo_documento, doc_frente_url, doc_dorso_url,
     province, municipality, poblado, direccion, kyc_estado)
  VALUES
    (v_cliente, 'Cliente E2E', 'e2e.cliente@muevete.test', '95010112345',
     'carnet', 'https://example.test/c-f.jpg', 'https://example.test/c-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle 1 #2', 'aprobado');

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_cliente, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_cliente, 'Contacto Cliente', '+5355550011', 1, 'sms', 'pendiente', true);

  -- Saldo del cliente para poder pagar por wallet
  INSERT INTO muevete.suscription_user (user_id, balance)
  VALUES (v_cliente, 2000);

  -- ── Chofer ─────────────────────────────────────────────────────────────
  INSERT INTO muevete.vehiculos (marca, modelo, chapa, id_tipo_vehiculo, capacidad_int, color)
  VALUES ('Lada', '2107', 'E2E001', v_auto, 4, 'Blanco')
  RETURNING id INTO v_vehiculo;

  INSERT INTO muevete.drivers
    (uuid, name, telefono, estado, kyc, kyc_estado, ci, tipo_documento,
     doc_frente_url, doc_dorso_url, province, municipality, poblado, direccion,
     vehiculo)
  VALUES
    (v_chofer, 'Chofer E2E', '+5355550022', true, true, 'aprobado', '88020212345',
     'carnet', 'https://example.test/ch-f.jpg', 'https://example.test/ch-d.jpg',
     'Villa Clara', 'Santa Clara', 'Centro', 'Calle 3 #4', v_vehiculo)
  RETURNING id INTO v_driver;

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version, aceptado, metodo)
  SELECT v_chofer, dl.id, dl.codigo, dl.version, true, 'app'
    FROM muevete.documentos_legales dl
   WHERE dl.publicado AND dl.es_obligatorio
     AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now());

  INSERT INTO muevete.contactos_emergencia
    (user_uuid, nombre, telefono, prioridad, canal, estado, verificado)
  VALUES (v_chofer, 'Contacto Chofer', '+5355550033', 1, 'sms', 'pendiente', true);

  -- Chofer ONLINE en el centro de Santa Clara
  INSERT INTO muevete.place (driver, latitude, longitude, estado)
  VALUES (v_driver, 22.40689, -79.96450, true);

  INSERT INTO muevete.wallet_drivers (driver_id, balance)
  VALUES (v_driver, 0);

  -- ==========================================================================
  -- T01 · el cliente publica (wallet)
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cliente::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_sol := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen E2E', 'Destino E2E', 3.3, 'wallet', 'Villa Clara', 'Santa Clara', 2);
    v_sol_id := v_sol.id;

    IF v_sol.precio_plataforma = 1500 AND v_sol.metodo_pago = 'wallet' AND v_sol.estado = 'pendiente' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T01 | crear wallet | 1500/pendiente | %s/%s | OK',
        v_sol.precio_plataforma, v_sol.estado);
    ELSE
      v_lineas := v_lineas || format('T01 | crear wallet | 1500/pendiente | %s/%s | FALLA',
        v_sol.precio_plataforma, v_sol.estado);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T01 | crear wallet | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T02 · el chofer la ve con su parte
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_chofer::text, 'role', 'authenticated')::text, true);

  BEGIN
    SELECT array_agg(x) INTO v_lista
      FROM muevete.fn_viajes_disponibles(22.40689, -79.96450, 10) x;

    v_n := coalesce(array_length(v_lista, 1), 0);

    IF v_n >= 1 THEN
      v_item := v_lista[1];
      IF (v_item ->> 'precio_plataforma')::numeric = 1500
         AND (v_item ->> 'comision_monto')::numeric = 225
         AND (v_item ->> 'precio_chofer')::numeric = 1275
         AND (v_item ->> 'pasajeros')::integer = 2
         AND (v_item ->> 'capacidad_vehiculo')::integer = 4
         AND (v_item ->> 'puede_tomar')::boolean
      THEN
        v_ok := v_ok + 1;
        v_lineas := v_lineas || format('T02 | lista chofer | 1500/225/1275 pax2 cap4 | %s filas, %s | OK',
          v_n, v_item ->> 'precio_chofer');
      ELSE
        v_lineas := v_lineas || format('T02 | lista chofer | 1500/225/1275 | %s | FALLA',
          left(v_item::text, 300));
      END IF;
    ELSE
      v_lineas := v_lineas || format('T02 | lista chofer | 1 fila | %s filas | FALLA', v_n);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T02 | lista chofer | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T03 · el chofer la toma (retención de wallet)
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol_id);
    v_viaje_id := (v_res ->> 'viaje_id')::bigint;

    SELECT balance INTO v_saldo FROM muevete.suscription_user WHERE user_id = v_cliente;

    IF (v_res ->> 'success')::boolean
       AND (v_res ->> 'hold_cliente')::numeric = 1500
       AND v_saldo = 500
       AND v_viaje_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM muevete.transacciones_wallet t
                    WHERE t.viaje_id = v_viaje_id
                      AND t.tipo = 'cobro_viaje'
                      AND t.monto = -1500)
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T03 | tomar wallet | hold 1500, saldo 500 | hold %s, saldo %s, viaje %s | OK',
        v_res ->> 'hold_cliente', v_saldo, v_viaje_id);
    ELSE
      v_lineas := v_lineas || format('T03 | tomar wallet | hold 1500, saldo 500 | %s, saldo %s | FALLA',
        left(v_res::text, 300), v_saldo);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T03 | tomar wallet | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T04 · no puede tener dos viajes activos
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_res := muevete.fn_tomar_viaje(v_sol_id);
    v_lineas := array_append(v_lineas, 'T04 | segundo viaje activo | P0012 | SIN ERROR | FALLA');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0012' OR v_state = 'P0020' THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T04 | segundo viaje activo | P0012/P0020 | %s / %s | OK',
        v_state, v_msg);
    ELSE
      v_lineas := v_lineas || format('T04 | segundo viaje activo | P0012 | %s / %s | FALLA',
        v_state, v_msg);
    END IF;
  END;

  -- ==========================================================================
  -- T05 · el cliente cancela → reembolso
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cliente::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_cancelar_solicitud(v_sol_id, 'E2E cancelación');

    SELECT balance INTO v_saldo FROM muevete.suscription_user WHERE user_id = v_cliente;

    IF (v_res ->> 'success')::boolean
       AND (v_res ->> 'reembolso')::numeric = 1500
       AND v_saldo = 2000
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T05 | cancelar wallet | reembolso 1500, saldo 2000 | %s, saldo %s | OK',
        v_res ->> 'reembolso', v_saldo);
    ELSE
      v_lineas := v_lineas || format('T05 | cancelar wallet | reembolso 1500, saldo 2000 | %s, saldo %s | FALLA',
        left(v_res::text, 300), v_saldo);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T05 | cancelar wallet | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T06 · viaje en EFECTIVO, tomado y completado
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_sol := muevete.fn_crear_solicitud(
               22.40689, -79.96450, 22.40900, -79.96000, v_auto,
               'Origen E2E 2', 'Destino E2E 2', 3.3, 'efectivo', 'Villa Clara', 'Santa Clara', 1);
    v_sol_id := v_sol.id;

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_chofer::text, 'role', 'authenticated')::text, true);
    v_res := muevete.fn_tomar_viaje(v_sol_id);
    v_viaje_id := (v_res ->> 'viaje_id')::bigint;

    v_res := muevete.fn_completar_viaje(v_viaje_id, NULL);

    SELECT balance INTO v_saldo FROM muevete.wallet_drivers WHERE driver_id = v_driver;

    IF (v_res ->> 'success')::boolean
       AND (v_res ->> 'precio_plataforma')::numeric = 1500
       AND (v_res ->> 'comision_monto')::numeric = 225
       AND (v_res ->> 'precio_chofer')::numeric = 1275
       AND v_saldo = -225
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T06 | efectivo completo | 1500/225/1275, saldo -225 | %s/%s/%s, saldo %s | OK',
        v_res ->> 'precio_plataforma', v_res ->> 'comision_monto', v_res ->> 'precio_chofer', v_saldo);
    ELSE
      v_lineas := v_lineas || format('T06 | efectivo completo | 1500/225/1275, saldo -225 | %s, saldo %s | FALLA',
        left(v_res::text, 300), v_saldo);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T06 | efectivo completo | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T07 · completar dos veces (idempotencia, la cola offline reintenta)
  -- ==========================================================================
  v_total := v_total + 1;
  BEGIN
    v_res := muevete.fn_completar_viaje(v_viaje_id, NULL);

    SELECT balance INTO v_saldo FROM muevete.wallet_drivers WHERE driver_id = v_driver;

    IF (v_res ->> 'success')::boolean
       AND (v_res ->> 'idempotente')::boolean
       AND v_saldo = -225
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T07 | completar 2 veces | idempotente, saldo -225 | %s, saldo %s | OK',
        v_res ->> 'idempotente', v_saldo);
    ELSE
      v_lineas := v_lineas || format('T07 | completar 2 veces | idempotente, saldo -225 | %s, saldo %s | FALLA',
        left(v_res::text, 300), v_saldo);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T07 | completar 2 veces | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- T08 · recarga de wallet (el % sale de configuración)
  -- ==========================================================================
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cliente::text, 'role', 'authenticated')::text, true);

  BEGIN
    v_res := muevete.fn_recargar_wallet('transfermovil', 1000, 'ref E2E');

    IF (v_res ->> 'success')::boolean
       AND (v_res ->> 'total_a_pagar')::numeric = round(1000 * (1 + coalesce(
             (SELECT recarga_pct FROM muevete.configuracion_tarifas WHERE id = 1), 0) / 100.0), 2)
       AND v_res ->> 'estado' = 'pendiente'
    THEN
      v_ok := v_ok + 1;
      v_lineas := v_lineas || format('T08 | recarga 1000 | total %s, pendiente | %s | OK',
        v_res ->> 'total_a_pagar', v_res ->> 'estado');
    ELSE
      v_lineas := v_lineas || format('T08 | recarga 1000 | total config, pendiente | %s | FALLA',
        left(v_res::text, 300));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_lineas := v_lineas || format('T08 | recarga | OK | %s / %s | FALLA', v_state, v_msg);
  END;

  -- ==========================================================================
  -- REPORTE (la excepción revierte todo el bloque)
  -- ==========================================================================
  RAISE EXCEPTION 'REPORTE 039+040 · %/% pruebas OK%  %',
    v_ok, v_total, E'\n', array_to_string(v_lineas, E'\n')
    USING ERRCODE = 'P0001';
END
$test$;