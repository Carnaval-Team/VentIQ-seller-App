-- ============================================================================
-- 038_taxi_rpc_solicitud.sql
-- RPCs de la solicitud: crear (precio congelado en el servidor) y cancelar.
--
-- ANEXO DE DISEÑO
--   · docs/plan-taxi-precio-fijo/04-diseno-tecnico.md  §5.3 y §5.7
--   · docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §6.1 (gate + capacidad)
--   · docs/plan-taxi-precio-fijo/07-seguridad-del-viaje.md    §9    (gate de seguridad)
--   · docs/plan-taxi-precio-fijo/08-privacidad-y-consentimiento.md §7 (consentimiento)
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql
--   · 031_taxi_zonas_tarifas.sql            (columnas de tarifa + trigger de guarda)
--   · 032_taxi_geo_y_cotizacion.sql         (fn_cotizar_viaje)
--   · 035_taxi_vehiculos_catalogo.sql       (pasajeros, pasajeros_max)
--   · 036_taxi_identidad_consentimiento.sql (fn_usuario_habilitado)
--   · 037_taxi_seguridad.sql                (fn_gate_seguridad)
--
-- QUÉ HACE
--   1. fn_crear_solicitud()      → RECOTIZA en servidor y CONGELA la tarifa.
--                                  El precio que mande el cliente se ignora.
--   2. fn_cancelar_solicitud()   → único camino a 'cancelada', con reembolso
--                                  de wallet si había retención.
--   3. Índice único parcial      → una solicitud abierta por cliente (backstop
--                                  de concurrencia, no sólo del chequeo EXISTS).
--
-- REGLAS QUE IMPONE EL SERVIDOR (no la UI, no evadibles desde un cliente modificado)
--   · Gate de identidad + consentimiento (E4) ....... perfil_incompleto      P0050
--   · Gate de seguridad (contacto de emergencia) .... sin_contacto_emergencia P0110
--   · Capacidad declarada vs pasajeros_max del TIPO . capacidad_excedida_tipo P0051
--   · Una sola solicitud abierta por cliente ........ solicitud_activa_existente P0005
--   · TTL 15 min (D-09). Las propias vencidas se cierran solas al crear.
--
-- DESVIACIÓN DOCUMENTADA · D-5 (capacidad en el preview)
--   El plan pedía añadir p_pasajeros también a fn_cotizar_viaje. NO se hace:
--   un 10º parámetro obliga a DROP+CREATE de una función ya validada contra los
--   14 casos de referencia de 03-modelo-economico §8.3 y produce ambigüedad de
--   sobrecarga para los llamadores de 9 argumentos (preview y simulador).
--   La capacidad se valida en el cliente filtrando v_catalogo_vehiculos por
--   pasajeros_max, y se IMPONE aquí en el servidor.
--
-- CONVENIO DE WALLET (lo deben respetar 039 y 040)
--   muevete.transacciones_wallet.tipo tiene CHECK y SÓLO admite:
--       recarga | cobro_viaje | pago_viaje | reembolso | comision_viaje
--   · Al tomar el viaje (039), si el cliente paga con wallet se retiene
--     precio_plataforma y se registra el débito con:
--         tipo = 'cobro_viaje', monto = -precio_plataforma, viaje_id = <viaje>,
--         balance_despues = saldo resultante, estado = 'completada'
--     (monto NEGATIVO = débito, igual que el resto de la app).
--   · Al cerrar (040) sólo se cobra el extra de espera (otro 'cobro_viaje').
--   · Aquí se busca esa retención por viaje_id, se toma su valor absoluto y se
--     reembolsa UNA sola vez, marcando el reembolso con tipo='reembolso' y monto
--     POSITIVO. Si ya hay un 'reembolso' para ese viaje, no se repite.
--   · Nada de esto toca suscription_user fuera de las RPC (041 revoca escrituras
--     directas).
--
-- EFECTO SECUNDARIO CONOCIDO
--   El trigger baseline `solicitudes_push` lanza una Edge Function en cada
--   INSERT (pg_net, asíncrono). En el proyecto de PRUEBAS apunta a producción:
--   cada solicitud de prueba genera un POST que no notifica a nadie real.
--
-- IDEMPOTENCIA
--   CREATE OR REPLACE FUNCTION + CREATE UNIQUE INDEX IF NOT EXISTS.
--   Re-ejecutar no falla y vuelve a dejar los mismos GRANT.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos: fallar temprano y con mensaje claro
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_falta text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_cotizar_viaje'
  ) THEN
    v_falta := array_append(v_falta, '032.fn_cotizar_viaje');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_usuario_habilitado'
  ) THEN
    v_falta := array_append(v_falta, '036.fn_usuario_habilitado');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_gate_seguridad'
  ) THEN
    v_falta := array_append(v_falta, '037.fn_gate_seguridad');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'muevete' AND table_name = 'solicitudes_transporte'
       AND column_name = 'pasajeros'
  ) THEN
    v_falta := array_append(v_falta, '035.solicitudes_transporte.pasajeros');
  END IF;

  IF cardinality(v_falta) > 0 THEN
    RAISE EXCEPTION 'prerrequisitos_faltantes: %', v_falta USING ERRCODE = 'P0001';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Backstop de concurrencia: una solicitud abierta por cliente
--    Partial unique index: sólo cuentan 'pendiente' y 'aceptada'.
--    'expirada' queda fuera a propósito (si no, una solicitud vencida bloquearía
--    al cliente para siempre; fn_crear_solicitud las cierra solas antes).
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS solicitudes_una_abierta_cliente_uidx
  ON muevete.solicitudes_transporte (user_id)
  WHERE estado IN ('pendiente', 'aceptada')
    AND user_id IS NOT NULL;

COMMENT ON INDEX muevete.solicitudes_una_abierta_cliente_uidx IS
  'Un cliente no puede tener dos solicitudes abiertas. Backstop del chequeo de fn_crear_solicitud.';

-- ----------------------------------------------------------------------------
-- 2. RPC · fn_crear_solicitud
--    El cliente NUNCA fija el precio: se recotiza aquí y se congela.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_crear_solicitud(
  p_lat_o       double precision,
  p_lon_o       double precision,
  p_lat_d       double precision,
  p_lon_d       double precision,
  p_id_tipo     bigint,
  p_dir_o       text,
  p_dir_d       text,
  p_km          double precision,
  p_metodo_pago text,
  p_provincia   text    DEFAULT NULL,
  p_municipio   text    DEFAULT NULL,
  p_pasajeros   integer DEFAULT 1
) RETURNS muevete.solicitudes_transporte
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  cfg         muevete.configuracion_tarifas%ROWTYPE;
  v_cot       jsonb;
  v_row       muevete.solicitudes_transporte%ROWTYPE;
  v_gate_id   jsonb;
  v_gate_seg  jsonb;
  v_cap_tipo  smallint;
  v_km        double precision;
  v_km_cot    double precision;
BEGIN
  -- Marca la transacción como "viene de una RPC": habilita trg_solicitud_guarda
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tarifas_no_configuradas' USING ERRCODE = 'P0002';
  END IF;
  IF NOT coalesce(cfg.taxi_precio_fijo_activo, false) THEN
    RAISE EXCEPTION 'servicio_en_mantenimiento' USING ERRCODE = 'P0003';
  END IF;

  -- (E4) Gate de identidad + consentimiento. No evadible.
  v_gate_id := muevete.fn_usuario_habilitado(v_uid, 'cliente');
  IF NOT coalesce((v_gate_id ->> 'habilitado')::boolean, false) THEN
    RAISE EXCEPTION 'perfil_incompleto: %', v_gate_id -> 'motivos'
      USING ERRCODE = 'P0050';
  END IF;

  -- (G-01) Sin contacto de emergencia vigente no se publica nada.
  --        El mensaje es el primer motivo, para que las pruebas de aceptación
  --        vean literalmente 'sin_contacto_emergencia' o 'bloqueado'.
  v_gate_seg := muevete.fn_gate_seguridad(v_uid);
  IF NOT coalesce((v_gate_seg ->> 'ok')::boolean, false) THEN
    RAISE EXCEPTION '%',
                    coalesce(v_gate_seg -> 'motivos' ->> 0, 'sin_contacto_emergencia')
      USING ERRCODE = 'P0110';
  END IF;

  IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN ('efectivo', 'wallet') THEN
    -- P0006, NO P0004: P0004 es el código RESERVADO `assert_failure` y
    -- `EXCEPTION WHEN OTHERS` NO lo captura (igual que query_canceled). Usarlo
    -- hacía que un llamador con handler genérico abortara la transacción entera
    -- en vez de degradar. P0005+ son de usuario.
    RAISE EXCEPTION 'metodo_pago_invalido: %', p_metodo_pago
      USING ERRCODE = 'P0006';
  END IF;

  -- (E3) Capacidad declarada vs capacidad máxima del TIPO de vehículo
  SELECT vt.pasajeros_max INTO v_cap_tipo
    FROM muevete.vehicle_type vt
   WHERE vt.id = p_id_tipo;

  IF v_cap_tipo IS NULL THEN
    RAISE EXCEPTION 'tipo_vehiculo_no_existe: %', p_id_tipo USING ERRCODE = 'P0040';
  END IF;
  IF p_pasajeros IS NULL OR p_pasajeros < 1 OR p_pasajeros > v_cap_tipo THEN
    RAISE EXCEPTION 'capacidad_excedida_tipo: % > %', p_pasajeros, v_cap_tipo
      USING ERRCODE = 'P0051';
  END IF;

  -- Cierra mis propias solicitudes vencidas: si no, el índice único bloquearía
  -- una solicitud nueva por culpa de una vieja que ya nadie verá.
  -- El trigger trg_solicitud_cerrada_seguridad revoca los enlaces compartidos.
  UPDATE muevete.solicitudes_transporte s
     SET estado             = 'expirada',
         cancelada_at       = now(),
         motivo_cancelacion = coalesce(s.motivo_cancelacion, 'expirada_ttl')
   WHERE s.user_id = v_uid
     AND s.estado = 'pendiente'
     AND s.expires_at IS NOT NULL
     AND s.expires_at <= now();

  -- Una sola solicitud abierta por cliente
  IF EXISTS (
    SELECT 1
      FROM muevete.solicitudes_transporte s
     WHERE s.user_id = v_uid
       AND s.estado IN ('pendiente', 'aceptada')
  ) THEN
    RAISE EXCEPTION 'solicitud_activa_existente' USING ERRCODE = 'P0005';
  END IF;

  -- Km: si el cliente no los tiene (o manda basura) se calcula por haversine.
  -- fn_cotizar_viaje acota internamente el valor (D-05 del anexo 04 §12).
  v_km := CASE
            WHEN p_km IS NULL OR p_km <= 0 THEN NULL
            ELSE least(p_km, 500::double precision)
          END;

  -- SIEMPRE recotiza en el servidor. El precio del cliente se ignora.
  v_cot := muevete.fn_cotizar_viaje(
             p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo,
             now(), v_km, p_provincia, p_municipio);

  v_cot := jsonb_set(v_cot, '{origen_calculo}', '"fn_crear_solicitud"', true);

  v_km_cot := (v_cot ->> 'km_total')::double precision;

  INSERT INTO muevete.solicitudes_transporte (
    user_id, lat_origen, lon_origen, lat_destino, lon_destino,
    tipo_vehiculo, id_tipo_vehiculo,
    precio_oferta,          -- espejo legacy para apps viejas y reportes
    precio_plataforma,      -- autoritativo y CONGELADO
    comision_pct, precio_chofer, moneda,
    estado, tarifa_modo, tarifa_detalle,
    direccion_origen, direccion_destino, distancia_km,
    zona_id, metodo_pago, pasajeros,
    seguridad_snapshot, expires_at
  ) VALUES (
    v_uid, p_lat_o, p_lon_o, p_lat_d, p_lon_d,
    lower(v_cot ->> 'tipo_vehiculo'), p_id_tipo,
    (v_cot ->> 'precio_plataforma')::numeric,
    (v_cot ->> 'precio_plataforma')::numeric,
    (v_cot ->> 'comision_pct')::numeric,
    (v_cot ->> 'precio_chofer')::numeric,
    coalesce(cfg.moneda, 'CUP'),
    'pendiente', v_cot ->> 'tarifa_modo', v_cot,
    left(coalesce(p_dir_o, ''), 300),
    left(coalesce(p_dir_d, ''), 300),
    coalesce(v_km_cot, v_km),
    (v_cot ->> 'zona_id')::bigint,
    p_metodo_pago,
    p_pasajeros,
    jsonb_build_object(
      'gate_seguridad',  v_gate_seg,
      'gate_identidad',  jsonb_build_object(
                           'perfil',         v_gate_id -> 'perfil',
                           'consentimiento', v_gate_id -> 'consentimiento'),
      'snapshot_at',     now()
    ),
    now() + interval '15 minutes'   -- TTL (anexo 04 §12 D-09)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

COMMENT ON FUNCTION muevete.fn_crear_solicitud(
  double precision, double precision, double precision, double precision,
  bigint, text, text, double precision, text, text, text, integer
) IS
  'Único camino para publicar un viaje. Recotiza y congela la tarifa; aplica gates de identidad, consentimiento y seguridad, y valida capacidad. Ignora cualquier precio enviado por el cliente.';

REVOKE ALL ON FUNCTION muevete.fn_crear_solicitud(
  double precision, double precision, double precision, double precision,
  bigint, text, text, double precision, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_crear_solicitud(
  double precision, double precision, double precision, double precision,
  bigint, text, text, double precision, text, text, text, integer
) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. RPC · fn_cancelar_solicitud
--    Único camino a 'cancelada'. No exige gate (cancelar siempre debe poder
--    hacerse, incluso con el perfil a medias o el usuario bloqueado).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_cancelar_solicitud(
  p_solicitud_id bigint,
  p_motivo       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid       uuid   := auth.uid();
  v_driver    bigint := muevete.get_my_driver_id();
  v_sol       muevete.solicitudes_transporte%ROWTYPE;
  v_viaje_id  bigint;
  v_retenido  numeric := 0;
  v_reembolso numeric := 0;
  v_saldo     numeric;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_sol
    FROM muevete.solicitudes_transporte
   WHERE id = p_solicitud_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0031';
  END IF;

  IF NOT (v_sol.user_id = v_uid
          OR v_sol.driver_id = v_driver
          OR muevete.is_superadmin()) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Idempotencia: cancelar dos veces no rompe ni reembolsa dos veces
  IF v_sol.estado = 'cancelada' THEN
    RETURN jsonb_build_object(
      'success',      true,
      'idempotente',  true,
      'solicitud_id', v_sol.id,
      'estado',       'cancelada',
      'reembolso',    0
    );
  END IF;

  IF v_sol.estado = 'completada' THEN
    RAISE EXCEPTION 'viaje_ya_completado' USING ERRCODE = 'P0032';
  END IF;

  -- ── Reembolso de wallet ────────────────────────────────────────────────
  -- Sólo si el viaje se había tomado y existe el débito de la toma
  -- (convenio de wallet documentado en la cabecera).
  IF coalesce(v_sol.metodo_pago, '') = 'wallet' THEN
    SELECT v.id INTO v_viaje_id
      FROM muevete.viajes v
     WHERE v.solicitud_id = v_sol.id
     ORDER BY v.id DESC
     LIMIT 1;

    IF v_viaje_id IS NOT NULL THEN
      SELECT abs(t.monto) INTO v_retenido
        FROM muevete.transacciones_wallet t
       WHERE t.viaje_id = v_viaje_id
         AND t.tipo = 'cobro_viaje'
         AND t.estado = 'completada'
         AND coalesce(t.monto, 0) <> 0
       ORDER BY t.id DESC
       LIMIT 1;

      IF coalesce(v_retenido, 0) > 0
         AND NOT EXISTS (
           SELECT 1 FROM muevete.transacciones_wallet r
            WHERE r.viaje_id = v_viaje_id
              AND r.tipo = 'reembolso'
              AND r.estado = 'completada'
         ) THEN

        v_reembolso := v_retenido;

        -- suscription_user no tiene índice único por user_id: se apunta a la
        -- fila de menor id para que el UPDATE sea determinista.
        UPDATE muevete.suscription_user u
           SET balance = coalesce(u.balance, 0) + v_reembolso
         WHERE u.id = (SELECT x.id FROM muevete.suscription_user x
                        WHERE x.user_id = v_sol.user_id
                        ORDER BY x.id
                        LIMIT 1)
        RETURNING u.balance INTO v_saldo;

        IF v_saldo IS NULL THEN
          -- Caso defensivo: retención sin fila de wallet (dato inconsistente).
          -- Se crea la fila para no perder el dinero del cliente.
          INSERT INTO muevete.suscription_user (user_id, balance)
          VALUES (v_sol.user_id, v_reembolso)
          RETURNING balance INTO v_saldo;
        END IF;

        INSERT INTO muevete.transacciones_wallet
          (user_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
        VALUES
          (v_sol.user_id, v_viaje_id, 'reembolso', v_reembolso, v_saldo,
           'Reembolso por cancelación de la solicitud #' || v_sol.id, 'completada');
      END IF;
    END IF;
  END IF;

  -- ── Cierre del viaje (si existía) ──────────────────────────────────────
  -- Se hace ANTES de cambiar el estado de la solicitud para que el
  -- seguridad_snapshot final registre 'solicitud_cancelada' y no
  -- 'viaje_completado'.
  UPDATE muevete.viajes
     SET completado = true,
         estado     = false
   WHERE solicitud_id = v_sol.id
     AND coalesce(completado, false) = false;

  -- ── Cancelación de la solicitud ────────────────────────────────────────
  UPDATE muevete.solicitudes_transporte
     SET estado             = 'cancelada',
         cancelada_at       = now(),
         motivo_cancelacion = left(coalesce(p_motivo, ''), 300),
         driver_id          = NULL
   WHERE id = v_sol.id;

  -- ── Aviso al chofer asignado ───────────────────────────────────────────
  IF v_sol.driver_id IS NOT NULL THEN
    INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
    SELECT d.uuid,
           'viaje_cancelado',
           'Viaje cancelado',
           coalesce(nullif(left(coalesce(p_motivo, ''), 200), ''),
                    'El viaje fue cancelado'),
           jsonb_build_object('solicitud_id', v_sol.id)
      FROM muevete.drivers d
     WHERE d.id = v_sol.driver_id
       AND d.uuid IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'success',      true,
    'solicitud_id', v_sol.id,
    'estado',       'cancelada',
    'viaje_id',     v_viaje_id,
    'reembolso',    v_reembolso,
    'saldo',        v_saldo
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_cancelar_solicitud(bigint, text) IS
  'Único camino a estado cancelada. Idempotente. Reembolsa la retención de wallet una sola vez si existía.';

REVOKE ALL ON FUNCTION muevete.fn_cancelar_solicitud(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cancelar_solicitud(bigint, text) TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Objetos:
--   SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'muevete'
--      AND proname IN ('fn_crear_solicitud','fn_cancelar_solicitud');
--   SELECT indexname FROM pg_indexes
--    WHERE schemaname = 'muevete'
--      AND indexname = 'solicitudes_una_abierta_cliente_uidx';
--
-- 2) Permisos (esperado: authenticated=true, anon=false):
--   SELECT has_function_privilege('authenticated',
--            'muevete.fn_crear_solicitud(double precision,double precision,double precision,double precision,bigint,text,text,double precision,text,text,text,integer)',
--            'EXECUTE') AS auth_ok,
--          has_function_privilege('anon',
--            'muevete.fn_crear_solicitud(double precision,double precision,double precision,double precision,bigint,text,text,double precision,text,text,text,integer)',
--            'EXECUTE') AS anon_no_deberia;
--
-- 3) Gate de identidad (como usuario sin documentos → perfil_incompleto):
--   BEGIN;
--     SELECT set_config('request.jwt.claims',
--       json_build_object('sub','<uuid-de-prueba>','role','authenticated')::text, true);
--     SELECT muevete.fn_crear_solicitud(22.40689,-79.96450,22.40900,-79.96000,
--              <id-auto>, 'Origen', 'Destino', 3.3, 'efectivo');
--   ROLLBACK;   -- esperado: ERROR P0050 perfil_incompleto
--
-- 4) Camino feliz (usuario con KYC, consentimientos y contacto de emergencia):
--   BEGIN;
--     SELECT set_config('request.jwt.claims',
--       json_build_object('sub','<uuid-completo>','role','authenticated')::text, true);
--     SELECT id, estado, precio_plataforma, precio_oferta, comision_pct,
--            precio_chofer, tarifa_modo, zona_id, pasajeros, expires_at
--       FROM muevete.fn_crear_solicitud(22.40689,-79.96450,22.40900,-79.96000,
--              <id-auto>, 'Origen', 'Destino', 3.3, 'efectivo', NULL, NULL, 2);
--   ROLLBACK;
--   -- esperado: precio_plataforma = precio_oferta = 1500, comision_pct = 15,
--   --           precio_chofer = 1275, tarifa_modo = 'fijo', pasajeros = 2
--
-- 5) Capacidad (p_pasajeros = 2 con tipo Moto, pasajeros_max = 1):
--   -- esperado: ERROR P0051 capacidad_excedida_tipo: 2 > 1
--
-- 6) No se puede cobrar dos veces al mismo cliente:
--   -- crear una; crear otra → ERROR P0005 solicitud_activa_existente
--
-- 7) Cancelar:
--   SELECT muevete.fn_cancelar_solicitud(<id>, 'prueba');
--   -- esperado: success=true, estado=cancelada, reembolso=0 (pago efectivo)
--   SELECT muevete.fn_cancelar_solicitud(<id>, 'prueba');
--   -- esperado: success=true, idempotente=true
--
-- 8) Los enlaces de seguimiento quedan revocados por el trigger de 037:
--   SELECT count(*) FROM muevete.viaje_compartidos
--    WHERE solicitud_id = <id> AND revocado_at IS NULL;   -- esperado: 0
--
-- ============================================================================
-- ROLLBACK (ejecutar a mano si hay que deshacer)
-- ============================================================================
-- DROP FUNCTION IF EXISTS muevete.fn_cancelar_solicitud(bigint, text);
-- DROP FUNCTION IF EXISTS muevete.fn_crear_solicitud(
--   double precision, double precision, double precision, double precision,
--   bigint, text, text, double precision, text, text, text, integer);
-- DROP INDEX IF EXISTS muevete.solicitudes_una_abierta_cliente_uidx;
-- ============================================================================