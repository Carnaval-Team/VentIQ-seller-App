-- ============================================================================
-- 040_taxi_rpc_cierre_y_recarga.sql
-- RPCs de cierre: completar viaje (comisión, espera, deuda) y recargar wallet.
--
-- ANEXO DE DISEÑO
--   · docs/plan-taxi-precio-fijo/04-diseno-tecnico.md       §5.6 y §5.8
--   · docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §6.3 (qué NO bloquea)
--   · docs/plan-taxi-precio-fijo/03-modelo-economico.md     (comisión topada)
--
-- PRERREQUISITOS
--   · 031_taxi_zonas_tarifas.sql        (columnas de tarifa, wallet, config)
--   · 038_taxi_rpc_solicitud.sql        (convenio de wallet)
--   · 039_taxi_rpc_lista_y_toma.sql     (crea el viaje y la retención)
--   · 036/037                           (fn_usuario_habilitado para la recarga)
--
-- QUÉ HACE
--   1. fn_completar_viaje() → cierra el viaje. El monto sale SIEMPRE del
--      snapshot de la solicitud + la espera medida por el servidor. La firma no
--      recibe precio: un cliente modificado no puede abaratarlo.
--   2. fn_recargar_wallet() → crea la recarga PENDIENTE (la aprueba el
--      superadmin). El % de recarga sale de configuración, no de un literal en
--      Dart (era 1.11 / 11 % hardcodeado).
--
-- REGLAS
--   · Cerrar el viaje NO se bloquea por KYC ni por consentimiento: bloquearlo
--     dejaría viajes huérfanos y al cliente sin poder pagar. Sí se avisa.
--   · La recarga NO exige perfil completo (se puede recargar sin un documento),
--     sólo consentimiento: sin aceptar privacidad/términos no se mueve dinero.
--   · La comisión se topa con configuracion_tarifas.tope_comision_viaje si > 0.
--
-- CONVENIO DE WALLET (ver 038 y 039). Tipos válidos por CHECK:
--   recarga | cobro_viaje | pago_viaje | reembolso | comision_viaje
--   · 039 al tomar:        cobro_viaje  monto = -precio_plataforma (retención)
--   · 040 al cerrar:       cobro_viaje  monto = -espera_monto   (sólo si > 0)
--   · 040 wallet chofer:   pago_viaje   monto = +precio_chofer
--   · 040 efectivo chofer: comision_viaje monto = -comision_monto
--   La suma de las filas de un viaje cuadra con el total cobrado.
--
-- IDEMPOTENCIA
--   fn_completar_viaje es idempotente por estado (reintentos de la cola
--   offline devuelven el mismo resultado sin volver a mover saldos).
--   CREATE OR REPLACE + REVOKE/GRANT.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_falta text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_tomar_viaje') THEN
    v_falta := array_append(v_falta, '039.fn_tomar_viaje');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_usuario_habilitado') THEN
    v_falta := array_append(v_falta, '036.fn_usuario_habilitado');
  END IF;
  IF cardinality(v_falta) > 0 THEN
    RAISE EXCEPTION 'prerrequisitos_faltantes: %', v_falta USING ERRCODE = 'P0001';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. RPC · fn_completar_viaje
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_completar_viaje(
  p_viaje_id   bigint,
  p_espera_min integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_cfg         muevete.configuracion_tarifas%ROWTYPE;
  v_viaje       muevete.viajes%ROWTYPE;
  v_sol         muevete.solicitudes_transporte%ROWTYPE;
  v_metodo      text;
  v_tarifa_esp  numeric := 0;
  v_espera_min  integer := 0;
  v_espera_cob  integer := 0;
  v_espera_monto numeric := 0;
  v_total       numeric;
  v_comision    numeric;
  v_chofer      numeric;
  v_saldo       numeric;
  v_saldo_cli   numeric;
  v_kyc_estado  text;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_cfg FROM muevete.configuracion_tarifas WHERE id = 1;

  -- Lock del viaje: serializa dos cierres simultáneos
  SELECT * INTO v_viaje FROM muevete.viajes WHERE id = p_viaje_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'viaje_no_existe' USING ERRCODE = 'P0030';
  END IF;

  SELECT * INTO v_sol
    FROM muevete.solicitudes_transporte
   WHERE id = v_viaje.solicitud_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe_para_viaje' USING ERRCODE = 'P0031';
  END IF;

  IF NOT (v_sol.user_id = v_uid
          OR v_sol.driver_id = muevete.get_my_driver_id()
          OR muevete.is_superadmin()) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- ── Idempotencia (reintentos de la cola offline) ───────────────────────
  IF v_sol.estado = 'completada' THEN
    RETURN jsonb_build_object(
      'success',           true,
      'idempotente',       true,
      'solicitud_id',      v_sol.id,
      'viaje_id',          v_viaje.id,
      'precio_plataforma', v_sol.precio_plataforma,
      'comision_monto',    round(coalesce(v_sol.precio_plataforma, 0)
                                 * coalesce(v_sol.comision_pct, v_cfg.comision_pct) / 100.0, 2),
      'precio_chofer',     v_sol.precio_chofer,
      'metodo_pago',       coalesce(v_sol.metodo_pago, v_viaje.metodo_pago, 'efectivo'));
  END IF;

  IF v_sol.estado <> 'aceptada' THEN
    RAISE EXCEPTION 'estado_invalido: %', v_sol.estado USING ERRCODE = 'P0032';
  END IF;

  v_metodo := coalesce(v_sol.metodo_pago, v_viaje.metodo_pago, 'efectivo');
  IF v_metodo NOT IN ('efectivo', 'wallet') THEN
    -- P0006, NO P0004: P0004 es `assert_failure` (reservado y no capturable por
    -- WHEN OTHERS). Ver la nota de códigos en 038.
    RAISE EXCEPTION 'metodo_pago_invalido: %', v_metodo USING ERRCODE = 'P0006';
  END IF;

  -- ── Espera: manda el servidor si el viaje trae segundos medidos ────────
  SELECT coalesce(vt.precio_espera_min, 0) INTO v_tarifa_esp
    FROM muevete.vehicle_type vt
   WHERE vt.id = v_sol.id_tipo_vehiculo;
  v_tarifa_esp := coalesce(v_tarifa_esp, 0);

  IF v_viaje.tiempo_espera_segundos IS NOT NULL AND v_viaje.tiempo_espera_segundos > 0 THEN
    v_espera_min := ceil(v_viaje.tiempo_espera_segundos / 60.0)::integer;
  ELSE
    v_espera_min := greatest(coalesce(p_espera_min, 0), 0);
  END IF;

  v_espera_cob := greatest(v_espera_min - coalesce(v_cfg.gracia_espera_min, 0), 0);
  IF v_espera_cob > 0 AND v_tarifa_esp > 0 THEN
    v_espera_monto := round(v_espera_cob * v_tarifa_esp, 2);
    IF coalesce(v_cfg.tope_cobro_espera, 0) > 0 THEN
      v_espera_monto := least(v_espera_monto, v_cfg.tope_cobro_espera);
    END IF;
  END IF;

  -- ── Total y reparto: SIEMPRE del snapshot, nunca del cliente ───────────
  v_total    := coalesce(v_sol.precio_plataforma, 0) + v_espera_monto;
  v_comision := round(v_total * coalesce(v_sol.comision_pct, v_cfg.comision_pct) / 100.0, 2);
  IF coalesce(v_cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, v_cfg.tope_comision_viaje);
  END IF;
  v_chofer := v_total - v_comision;

  IF v_metodo = 'wallet' THEN
    -- Al tomar se retuvo precio_plataforma; aquí sólo se cobra la espera
    IF v_espera_monto > 0 THEN
      -- suscription_user no tiene único por user_id: se apunta a la fila de
      -- menor id para que el UPDATE sea determinista.
      UPDATE muevete.suscription_user u
         SET balance = coalesce(u.balance, 0) - v_espera_monto
       WHERE u.id = (SELECT x.id FROM muevete.suscription_user x
                      WHERE x.user_id = v_sol.user_id
                      ORDER BY x.id
                      LIMIT 1)
         AND coalesce(u.balance, 0) >= v_espera_monto
      RETURNING u.balance INTO v_saldo_cli;

      IF v_saldo_cli IS NULL THEN
        RAISE EXCEPTION 'cliente_sin_saldo_para_espera' USING ERRCODE = 'P0024';
      END IF;

      INSERT INTO muevete.transacciones_wallet
        (user_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
      VALUES
        (v_sol.user_id, v_viaje.id, 'cobro_viaje', -v_espera_monto, v_saldo_cli,
         'Cobro de espera (' || v_espera_cob || ' min) del viaje #' || v_sol.id,
         'completada');
    ELSE
      SELECT coalesce(u.balance, 0) INTO v_saldo_cli
        FROM muevete.suscription_user u
       WHERE u.user_id = v_sol.user_id
       ORDER BY u.id
       LIMIT 1;
    END IF;

    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_sol.driver_id, 0)
    ON CONFLICT (driver_id) DO NOTHING;

    UPDATE muevete.wallet_drivers
       SET balance = coalesce(balance, 0) + v_chofer
     WHERE driver_id = v_sol.driver_id
    RETURNING balance INTO v_saldo;

    INSERT INTO muevete.transacciones_wallet
      (driver_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
    VALUES
      (v_sol.driver_id, v_viaje.id, 'pago_viaje', v_chofer, v_saldo,
       'Pago por viaje #' || v_sol.id || ' (total ' || v_total || ' - '
        || round(coalesce(v_sol.comision_pct, v_cfg.comision_pct), 2) || '% comisión)',
       'completada');

  ELSE
    -- D6: en efectivo se descuenta la comisión aunque deje saldo negativo
    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_sol.driver_id, 0)
    ON CONFLICT (driver_id) DO NOTHING;

    UPDATE muevete.wallet_drivers
       SET balance = coalesce(balance, 0) - v_comision
     WHERE driver_id = v_sol.driver_id
    RETURNING balance INTO v_saldo;

    INSERT INTO muevete.transacciones_wallet
      (driver_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
    VALUES
      (v_sol.driver_id, v_viaje.id, 'comision_viaje', -v_comision, v_saldo,
       'Comisión ' || round(coalesce(v_sol.comision_pct, v_cfg.comision_pct), 2)
        || '% por viaje #' || v_sol.id || ' cobrado en efectivo',
       'completada');
  END IF;

  -- ── Cierre ─────────────────────────────────────────────────────────────
  UPDATE muevete.solicitudes_transporte
     SET estado            = 'completada',
         completada_at     = now(),
         precio_plataforma = v_total,
         precio_chofer     = v_chofer
   WHERE id = v_sol.id;

  UPDATE muevete.viajes
     SET completado        = true,
         estado            = false,
         precio_plataforma = v_total,
         precio_chofer     = v_chofer,
         comision_pct      = coalesce(v_sol.comision_pct, v_cfg.comision_pct),
         cobro_espera      = v_espera_monto
   WHERE id = v_viaje.id;

  -- ── Aviso de KYC rechazado sobrevenido (NO bloquea el cierre) ──────────
  IF v_sol.driver_id IS NOT NULL THEN
    SELECT d.kyc_estado INTO v_kyc_estado
      FROM muevete.drivers d WHERE d.id = v_sol.driver_id;

    IF v_kyc_estado = 'rechazado' THEN
      RAISE WARNING 'kyc_rechazado_durante_viaje: viaje % driver %',
        v_viaje.id, v_sol.driver_id;

      INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
      SELECT d.uuid, 'kyc_rechazado', 'Verificación rechazada',
             'Tu verificación fue rechazada. Revisa tus documentos para seguir recibiendo viajes.',
             jsonb_build_object('viaje_id', v_viaje.id, 'solicitud_id', v_sol.id)
        FROM muevete.drivers d
       WHERE d.id = v_sol.driver_id AND d.uuid IS NOT NULL;
    END IF;
  END IF;

  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  VALUES (
    v_sol.user_id, 'viaje_completado', 'Viaje completado',
    'Total: ' || v_total || ' ' || coalesce(v_sol.moneda, 'CUP'),
    jsonb_build_object('solicitud_id', v_sol.id, 'viaje_id', v_viaje.id,
                       'precio_plataforma', v_total,
                       'espera_monto', v_espera_monto)
  );

  RETURN jsonb_build_object(
    'success',            true,
    'solicitud_id',       v_sol.id,
    'viaje_id',           v_viaje.id,
    'precio_plataforma',  v_total,
    'precio_viaje',       coalesce(v_sol.precio_plataforma, 0),
    'espera_min',         v_espera_min,
    'espera_cobrada_min', v_espera_cob,
    'espera_monto',       v_espera_monto,
    'comision_pct',       coalesce(v_sol.comision_pct, v_cfg.comision_pct),
    'comision_monto',     v_comision,
    'precio_chofer',      v_chofer,
    'metodo_pago',        v_metodo,
    'saldo_chofer',       v_saldo,
    'deuda_chofer',       greatest(0, -coalesce(v_saldo, 0))
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_completar_viaje(bigint, integer) IS
  'Cierra el viaje desde el snapshot de tarifa + espera medida en servidor. Sin parámetro de precio. Idempotente.';

REVOKE ALL ON FUNCTION muevete.fn_completar_viaje(bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_completar_viaje(bigint, integer) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. RPC · fn_recargar_wallet
--    Crea la recarga PENDIENTE; el % sale de configuración (no de Dart).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_recargar_wallet(
  p_metodo    text,
  p_monto     numeric,
  p_evidencia text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid     uuid   := auth.uid();
  v_driver  bigint := muevete.get_my_driver_id();
  v_cfg     muevete.configuracion_tarifas%ROWTYPE;
  v_gate    jsonb;
  v_total   numeric;
  v_tx_id   bigint;
  v_rol     text;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION 'monto_invalido' USING ERRCODE = 'P0040';
  END IF;
  IF p_metodo IS NULL OR length(trim(p_metodo)) = 0 THEN
    RAISE EXCEPTION 'metodo_invalido' USING ERRCODE = 'P0041';
  END IF;

  -- Sólo consentimiento: se puede recargar con el perfil a medias, pero no sin
  -- haber aceptado privacidad y términos (se mueve dinero).
  v_rol  := CASE WHEN v_driver IS NULL THEN 'cliente' ELSE 'chofer' END;
  v_gate := muevete.fn_usuario_habilitado(v_uid, v_rol);

  IF NOT coalesce((v_gate -> 'consentimiento' ->> 'ok')::boolean, false) THEN
    RAISE EXCEPTION 'consentimiento_pendiente: %',
                    v_gate -> 'consentimiento' -> 'faltantes'
      USING ERRCODE = 'P0053';
  END IF;

  SELECT * INTO v_cfg FROM muevete.configuracion_tarifas WHERE id = 1;

  v_total := round(p_monto * (1 + coalesce(v_cfg.recarga_pct, 0) / 100.0), 2);

  -- Transacción PENDIENTE: el saldo lo acredita el superadmin al aprobar
  INSERT INTO muevete.transacciones_wallet
    (user_id, driver_id, tipo, monto, estado, descripcion, created_at)
  VALUES (
    CASE WHEN v_driver IS NULL THEN v_uid END,
    v_driver,
    'recarga',
    p_monto,
    'pendiente',
    'Recarga de ' || p_monto || ' ' || coalesce(v_cfg.moneda, 'CUP')
      || ' — pago total: ' || v_total || ' (incluye '
      || coalesce(v_cfg.recarga_pct, 0) || '% comisión) — canal: ' || p_metodo,
    now()
  ) RETURNING id INTO v_tx_id;

  IF p_evidencia IS NOT NULL AND length(trim(p_evidencia)) > 0 THEN
    INSERT INTO muevete.verificacion_operacion_recarga (transaccion_id, detalle_texto)
    VALUES (v_tx_id, left(p_evidencia, 1000));
  END IF;

  RETURN jsonb_build_object(
    'success',           true,
    'transaccion_id',    v_tx_id,
    'monto_acreditar',   p_monto,
    'total_a_pagar',     v_total,
    'recarga_pct',       v_cfg.recarga_pct,
    'moneda',            v_cfg.moneda,
    'estado',            'pendiente',
    'es_recarga_chofer', v_driver IS NOT NULL
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_recargar_wallet(text, numeric, text) IS
  'Crea la recarga pendiente de aprobación. El % de recarga sale de configuracion_tarifas; exige consentimiento.';

REVOKE ALL ON FUNCTION muevete.fn_recargar_wallet(text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_recargar_wallet(text, numeric, text) TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Objetos:
--   SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'muevete'
--      AND proname IN ('fn_completar_viaje','fn_recargar_wallet');
--
-- 2) Viaje en efectivo (precio 1500, comisión 15 %, sin espera):
--   SELECT muevete.fn_completar_viaje(<viaje_id>);
--   -- esperado: precio_plataforma 1500, comision_monto 225,
--   --           precio_chofer 1275, saldo_chofer = saldo_prev - 225
--   -- y una fila transacciones_wallet tipo='comision_viaje', monto=-225
--
-- 3) Viaje con wallet:
--   -- al tomar: fila 'cobro_viaje' -1500 en el cliente
--   SELECT muevete.fn_completar_viaje(<viaje_id>);
--   -- esperado: se cobra sólo la espera (0 si no hubo);
--   --           fila 'pago_viaje' +1275 en el chofer
--
-- 4) Idempotencia: llamarla dos veces devuelve idempotente=true y no mueve
--    otra vez los saldos.
--
-- 5) La firma no acepta precio: no existe forma de enviar un total.
--
-- 6) Recarga (el % sale de config, recarga_pct):
--   SELECT muevete.fn_recargar_wallet('transfermovil', 1000, 'ref 123');
--   -- esperado: total_a_pagar = 1000 * (1 + recarga_pct/100), estado pendiente
--
-- 7) Recarga sin consentimiento → consentimiento_pendiente (P0053).
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DROP FUNCTION IF EXISTS muevete.fn_recargar_wallet(text, numeric, text);
-- DROP FUNCTION IF EXISTS muevete.fn_completar_viaje(bigint, integer);
-- ============================================================================