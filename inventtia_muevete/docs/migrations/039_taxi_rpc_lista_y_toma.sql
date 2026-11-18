-- ============================================================================
-- 039_taxi_rpc_lista_y_toma.sql
-- RPCs del chofer: ver los viajes disponibles de su zona y tomar uno (atómico).
--
-- ANEXO DE DISEÑO
--   · docs/plan-taxi-precio-fijo/04-diseno-tecnico.md       §5.4 y §5.5
--   · docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §6.2 (gate + capacidad)
--   · docs/plan-taxi-precio-fijo/07-seguridad-del-viaje.md   §9   (gate + emparejamiento)
--   · docs/plan-taxi-precio-fijo/PLAN-IMPLEMENTACION.md      regla 4 (fan-out por zona)
--
-- PRERREQUISITOS
--   · 031_taxi_zonas_tarifas.sql            (columnas de tarifa, viajes, wallet)
--   · 032_taxi_geo_y_cotizacion.sql         (fn_haversine_km, fn_zona_de_punto)
--   · 035_taxi_vehiculos_catalogo.sql       (pasajeros, fn_capacidad_vehiculo)
--   · 036_taxi_identidad_consentimiento.sql (fn_usuario_habilitado)
--   · 037_taxi_seguridad.sql                (fn_gate_seguridad, fn_emparejamiento_bloqueado)
--   · 038_taxi_rpc_solicitud.sql            (crea las solicitudes que aquí se listan)
--
-- QUÉ HACE
--   1. fn_viajes_disponibles() → lista para el chofer:
--        · sólo solicitudes pendientes, sin chofer, no vencidas y con precio
--          congelado (las legacy sin tarifa no se listan);
--        · sólo las que caen en la MISMA zona donde está el chofer;
--        · con el reparto ya calculado: "se cobra X, a ti te tocan Y";
--        · con `puede_tomar` y `motivo_bloqueo` por fila.
--   2. fn_tomar_viaje() → toma atómica "el primero gana", crea el viaje y
--      retiene el wallet del cliente si paga por wallet.
--
-- REGLAS QUE IMPONE EL SERVIDOR (no evadibles)
--   · Gate de identidad/consentimiento del CHOFER ..... perfil_incompleto_chofer  P0050
--   · Gate de seguridad (contacto + bloqueos) ......... P0110
--   · Emparejamiento bloqueado cliente↔chofer ......... emparejamiento_bloqueado P0112
--   · Capacidad del vehículo vs pasajeros ............. capacidad_insuficiente    P0052
--   · Tipo de vehículo, zona, deuda ................... P0010–P0025 (ver cuerpo)
--
-- CONCURRENCIA (por qué NO se usa SKIP LOCKED)
--   El `UPDATE ... WHERE estado='pendiente' AND driver_id IS NULL` es la toma.
--   El segundo chofer espera el lock de fila; al hacer COMMIT el primero,
--   PostgreSQL reevalúa el WHERE sobre la versión nueva (EvalPlanQual): ya no
--   es 'pendiente' → 0 filas → NOT FOUND → 'ya_tomado'. Ninguna validación
--   previa necesita lock porque todas se reevalúan o fallan seguro.
--
-- CONVENIO DE WALLET (definido en 038, respetado aquí y en 040)
--   OJO: muevete.transacciones_wallet.tipo tiene CHECK y SÓLO admite
--   recarga | cobro_viaje | pago_viaje | reembolso | comision_viaje.
--   Pago con wallet al tomar: se descuenta precio_plataforma de
--   suscription_user.balance y se registra con tipo='cobro_viaje', monto
--   NEGATIVO, viaje_id del viaje recién creado.
--   fn_cancelar_solicitud (038) reembolsa esa retención;
--   fn_completar_viaje (040) sólo cobra el extra de espera.
--
-- IDEMPOTENCIA
--   CREATE OR REPLACE FUNCTION + REVOKE/GRANT. Re-ejecutar no falla.
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
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_gate_seguridad') THEN
    v_falta := array_append(v_falta, '037.fn_gate_seguridad');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_emparejamiento_bloqueado') THEN
    v_falta := array_append(v_falta, '037.fn_emparejamiento_bloqueado');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_capacidad_vehiculo') THEN
    v_falta := array_append(v_falta, '035.fn_capacidad_vehiculo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_crear_solicitud') THEN
    v_falta := array_append(v_falta, '038.fn_crear_solicitud');
  END IF;
  IF cardinality(v_falta) > 0 THEN
    RAISE EXCEPTION 'prerrequisitos_faltantes: %', v_falta USING ERRCODE = 'P0001';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. RPC · fn_viajes_disponibles
--    "Cliente pide esto, se cobrará tanto, a ti te tocan tanto".
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_viajes_disponibles(
  p_lat    double precision DEFAULT NULL,
  p_lon    double precision DEFAULT NULL,
  p_limite integer          DEFAULT 30
) RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_driver       bigint  := muevete.get_my_driver_id();
  v_cfg          muevete.configuracion_tarifas%ROWTYPE;
  v_online       boolean := false;
  v_kyc_bool     boolean := false;
  v_activo       boolean := false;
  v_lat          double precision;
  v_lon          double precision;
  v_zona_chofer  bigint;
  v_tipo_chofer  bigint;
  v_vehiculo     bigint;
  v_capacidad    smallint := 1;
  v_saldo        numeric  := 0;
  v_deuda_tope   numeric  := 0;
  v_disponible   numeric  := 0;
  v_gate_id      jsonb;
  v_gate_ok      boolean := false;
  v_gate_motivos jsonb   := '[]'::jsonb;
  v_limit        integer;
BEGIN
  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'no_es_chofer' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_cfg FROM muevete.configuracion_tarifas WHERE id = 1;

  -- ── Estado del chofer ───────────────────────────────────────────────────
  SELECT coalesce(d.kyc, false), veh.id_tipo_vehiculo, d.vehiculo
    INTO v_kyc_bool, v_tipo_chofer, v_vehiculo
    FROM muevete.drivers d
    LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
   WHERE d.id = v_driver;
  v_kyc_bool := coalesce(v_kyc_bool, false);

  v_capacidad := coalesce(muevete.fn_capacidad_vehiculo(v_vehiculo), 1::smallint);

  SELECT coalesce(p.estado, false), p.latitude, p.longitude
    INTO v_online, v_lat, v_lon
    FROM muevete.place p
   WHERE p.driver = v_driver;
  v_online := coalesce(v_online, false);   -- SELECT INTO sin filas deja NULL

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
    v_lat := p_lat;
    v_lon := p_lon;
  END IF;

  IF v_lat IS NOT NULL AND v_lon IS NOT NULL THEN
    SELECT z.id INTO v_zona_chofer
      FROM muevete.fn_zona_de_punto(v_lat, v_lon, now()) z;
  END IF;

  -- ── Dinero del chofer: saldo + deuda permitida ──────────────────────────
  SELECT coalesce(w.balance, 0) INTO v_saldo
    FROM muevete.wallet_drivers w WHERE w.driver_id = v_driver;
  v_saldo := coalesce(v_saldo, 0);

  v_deuda_tope := CASE WHEN coalesce(v_cfg.permite_deuda, true)
                       THEN coalesce(v_cfg.limite_deuda_efectivo, 0)
                       ELSE 0 END;
  v_disponible := v_saldo + v_deuda_tope;

  -- ── Gates (identidad/consentimiento y seguridad) ───────────────────────
  v_gate_id := muevete.fn_usuario_habilitado(auth.uid(), 'chofer');

  SELECT coalesce((g ->> 'ok')::boolean, false), coalesce(g -> 'motivos', '[]'::jsonb)
    INTO v_gate_ok, v_gate_motivos
    FROM (SELECT muevete.fn_gate_seguridad(auth.uid(), v_driver) AS g) t;

  v_gate_ok := coalesce((v_gate_id ->> 'habilitado')::boolean, false) AND coalesce(v_gate_ok, false);

  -- ── ¿Ya tiene un viaje activo? ─────────────────────────────────────────
  SELECT EXISTS (
    SELECT 1 FROM muevete.solicitudes_transporte s
     WHERE s.driver_id = v_driver AND s.estado = 'aceptada'
  ) INTO v_activo;

  v_limit := greatest(1, least(coalesce(p_limite, 30), 100));

  RETURN QUERY
  WITH base AS (
    SELECT s.*
      FROM muevete.solicitudes_transporte s
     WHERE s.estado = 'pendiente'
       AND s.driver_id IS NULL
       AND s.precio_plataforma IS NOT NULL        -- excluye legacy sin tarifa
       AND (s.expires_at IS NULL OR s.expires_at > now())
       -- El viaje debe nacer en la zona donde está el chofer (regla 3/4)
       AND (
             (v_zona_chofer IS NOT NULL AND s.zona_id = v_zona_chofer)
          OR (v_zona_chofer IS NULL     AND s.zona_id IS NULL)
       )
  ), calc AS (
    SELECT b.*,
           round(b.precio_plataforma * coalesce(b.comision_pct, v_cfg.comision_pct) / 100.0, 2)
             AS comision_bruta
      FROM base b
  ), final AS (
    SELECT c.*,
           CASE WHEN coalesce(v_cfg.tope_comision_viaje, 0) > 0
                THEN least(c.comision_bruta, v_cfg.tope_comision_viaje)
                ELSE c.comision_bruta END AS comision_monto
      FROM calc c
  )
  SELECT jsonb_build_object(
    'solicitud_id',      f.id,
    'zona_id',           f.zona_id,
    'zona_nombre',       z.nombre,
    'tarifa_modo',       f.tarifa_modo,
    'tipo_vehiculo',     f.tipo_vehiculo,
    'id_tipo_vehiculo',  f.id_tipo_vehiculo,
    'pasajeros',         f.pasajeros,
    'capacidad_vehiculo', v_capacidad,
    'lat_origen',        f.lat_origen,
    'lon_origen',        f.lon_origen,
    'lat_destino',       f.lat_destino,
    'lon_destino',       f.lon_destino,
    'direccion_origen',  f.direccion_origen,
    'direccion_destino', f.direccion_destino,
    'km',                coalesce(f.distancia_km, (f.tarifa_detalle ->> 'km_total')::double precision),
    'precio_plataforma', f.precio_plataforma,          -- lo que paga el cliente
    'comision_pct',      coalesce(f.comision_pct, v_cfg.comision_pct),
    'comision_monto',    f.comision_monto,             -- lo que se lleva la plataforma
    -- Neto contable del chofer. OJO: NO es "lo que cobra". Con pago en efectivo el
    -- chofer recibe el total en mano y la comisión se le DESCUENTA del wallet; con
    -- pago por wallet se le ABONA este neto. La UI debe explicarlo según el método.
    'precio_chofer',     round(f.precio_plataforma - f.comision_monto, 2),
    'metodo_pago',       coalesce(f.metodo_pago, 'efectivo'),   -- 'efectivo' | 'wallet'
    'moneda',            coalesce(f.moneda, 'CUP'),
    'distancia_a_origen_km',
        round(muevete.fn_haversine_km(v_lat, v_lon, f.lat_origen, f.lon_origen)::numeric, 2),
    'desglose',          f.tarifa_detalle,
    'created_at',        f.created_at,
    'expires_at',        f.expires_at,
    'segundos_restantes', greatest(0, ceil(extract(epoch FROM (f.expires_at - now())))::integer),
    'deuda_disponible',  round(v_disponible - f.comision_monto, 2),
    'puede_tomar',       (v_online AND v_kyc_bool AND NOT v_activo AND v_gate_ok
                          AND f.pasajeros <= v_capacidad
                          AND (f.id_tipo_vehiculo IS NULL
                               OR f.id_tipo_vehiculo IS NOT DISTINCT FROM v_tipo_chofer)
                          AND v_disponible >= f.comision_monto
                          AND NOT muevete.fn_emparejamiento_bloqueado(f.user_id, v_driver)),
    'motivo_bloqueo',    CASE
                           WHEN NOT v_online     THEN 'chofer_offline'
                           WHEN NOT v_kyc_bool   THEN 'chofer_no_aprobado'
                           WHEN v_activo         THEN 'ya_tienes_un_viaje'
                           WHEN NOT coalesce((v_gate_id ->> 'habilitado')::boolean, false)
                                                 THEN 'perfil_incompleto_chofer'
                           WHEN NOT v_gate_ok    THEN coalesce(v_gate_motivos ->> 0, 'gate_seguridad')
                           WHEN f.pasajeros > v_capacidad THEN 'capacidad_insuficiente'
                           WHEN f.id_tipo_vehiculo IS NOT NULL
                                AND f.id_tipo_vehiculo IS DISTINCT FROM v_tipo_chofer
                                                 THEN 'tipo_vehiculo_incompatible'
                           WHEN v_disponible < f.comision_monto
                                                 THEN 'limite_de_deuda_alcanzado'
                           WHEN muevete.fn_emparejamiento_bloqueado(f.user_id, v_driver)
                                                 THEN 'emparejamiento_bloqueado'
                           ELSE NULL
                         END
  )
  FROM final f
  LEFT JOIN muevete.zonas_tarifa z ON z.id = f.zona_id
  ORDER BY muevete.fn_haversine_km(v_lat, v_lon, f.lat_origen, f.lon_origen) NULLS LAST,
           f.created_at
  LIMIT v_limit;
END;
$$;

COMMENT ON FUNCTION muevete.fn_viajes_disponibles(double precision, double precision, integer) IS
  'Lista de viajes para el chofer: sólo su zona, con precio del cliente, comisión, lo que le toca, y si puede tomarlo.';

REVOKE ALL ON FUNCTION muevete.fn_viajes_disponibles(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_viajes_disponibles(double precision, double precision, integer) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. RPC · fn_tomar_viaje — el primero gana
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_tomar_viaje(p_solicitud_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_driver      bigint := muevete.get_my_driver_id();
  v_cfg         muevete.configuracion_tarifas%ROWTYPE;
  v_sol         muevete.solicitudes_transporte%ROWTYPE;
  v_prev        muevete.solicitudes_transporte%ROWTYPE;
  v_online      boolean := false;
  v_kyc_bool    boolean := false;
  v_activo      boolean := false;
  v_lat         double precision;
  v_lon         double precision;
  v_zona_chofer bigint;
  v_tipo_chofer bigint;
  v_vehiculo    bigint;
  v_capacidad   smallint := 1;
  v_saldo       numeric := 0;
  v_disponible  numeric := 0;
  v_comision    numeric;
  v_metodo      text;
  v_viaje_id    bigint;
  v_hold        numeric := 0;
  v_saldo_cli   numeric;
  v_gate_id     jsonb;
  v_gate_seg    jsonb;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'no_es_chofer' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT coalesce(v_cfg.taxi_precio_fijo_activo, false) THEN
    RAISE EXCEPTION 'servicio_en_mantenimiento' USING ERRCODE = 'P0003';
  END IF;

  -- ── 1. Gate de identidad/consentimiento del CHOFER (no evadible) ───────
  v_gate_id := muevete.fn_usuario_habilitado(auth.uid(), 'chofer');
  IF NOT coalesce((v_gate_id ->> 'habilitado')::boolean, false) THEN
    RAISE EXCEPTION 'perfil_incompleto_chofer: %', v_gate_id -> 'motivos'
      USING ERRCODE = 'P0050';
  END IF;

  -- ── 2. Gate de seguridad (contacto de emergencia + bloqueos) ───────────
  v_gate_seg := muevete.fn_gate_seguridad(auth.uid(), v_driver);
  IF NOT coalesce((v_gate_seg ->> 'ok')::boolean, false) THEN
    RAISE EXCEPTION '%',
                    coalesce(v_gate_seg -> 'motivos' ->> 0, 'sin_contacto_emergencia')
      USING ERRCODE = 'P0110';
  END IF;

  -- ── 3. Pre-chequeos del chofer ─────────────────────────────────────────
  SELECT coalesce(d.kyc, false), veh.id_tipo_vehiculo, d.vehiculo
    INTO v_kyc_bool, v_tipo_chofer, v_vehiculo
    FROM muevete.drivers d
    LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
   WHERE d.id = v_driver;
  v_kyc_bool := coalesce(v_kyc_bool, false);
  v_capacidad := coalesce(muevete.fn_capacidad_vehiculo(v_vehiculo), 1::smallint);

  SELECT coalesce(p.estado, false), p.latitude, p.longitude
    INTO v_online, v_lat, v_lon
    FROM muevete.place p
   WHERE p.driver = v_driver;
  v_online := coalesce(v_online, false);

  IF NOT v_online THEN
    RAISE EXCEPTION 'chofer_offline' USING ERRCODE = 'P0010';
  END IF;
  IF NOT v_kyc_bool THEN
    RAISE EXCEPTION 'chofer_no_aprobado' USING ERRCODE = 'P0011';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM muevete.solicitudes_transporte s
     WHERE s.driver_id = v_driver AND s.estado = 'aceptada'
  ) INTO v_activo;
  IF v_activo THEN
    RAISE EXCEPTION 'chofer_con_viaje_activo' USING ERRCODE = 'P0012';
  END IF;

  -- ── 4. Validaciones sobre la solicitud ─────────────────────────────────
  SELECT * INTO v_prev FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0020';
  END IF;
  IF v_prev.estado <> 'pendiente' OR v_prev.driver_id IS NOT NULL THEN
    RAISE EXCEPTION 'ya_tomado' USING ERRCODE = 'P0020';
  END IF;
  IF v_prev.precio_plataforma IS NULL THEN
    RAISE EXCEPTION 'solicitud_legacy_sin_tarifa' USING ERRCODE = 'P0025';
  END IF;
  IF v_prev.expires_at IS NOT NULL AND v_prev.expires_at <= now() THEN
    RAISE EXCEPTION 'solicitud_vencida' USING ERRCODE = 'P0026';
  END IF;
  IF v_prev.id_tipo_vehiculo IS NOT NULL
     AND v_prev.id_tipo_vehiculo IS DISTINCT FROM v_tipo_chofer THEN
    RAISE EXCEPTION 'tipo_vehiculo_incompatible' USING ERRCODE = 'P0021';
  END IF;

  -- (E3) Capacidad real del vehículo del chofer
  IF coalesce(v_prev.pasajeros, 1) > v_capacidad THEN
    RAISE EXCEPTION 'capacidad_insuficiente: pasajeros % > vehiculo %',
      v_prev.pasajeros, v_capacidad USING ERRCODE = 'P0052';
  END IF;

  -- ── 5. Zona ────────────────────────────────────────────────────────────
  IF v_lat IS NOT NULL AND v_lon IS NOT NULL THEN
    SELECT z.id INTO v_zona_chofer
      FROM muevete.fn_zona_de_punto(v_lat, v_lon, now()) z;
    IF v_zona_chofer IS DISTINCT FROM v_prev.zona_id THEN
      RAISE EXCEPTION 'viaje_fuera_de_tu_zona' USING ERRCODE = 'P0022';
    END IF;
  END IF;

  -- ── 6. Emparejamiento bloqueado (seguridad personal) ───────────────────
  IF muevete.fn_emparejamiento_bloqueado(v_prev.user_id, v_driver) THEN
    RAISE EXCEPTION 'emparejamiento_bloqueado' USING ERRCODE = 'P0112';
  END IF;

  -- ── 7. Deuda permitida (D6) ────────────────────────────────────────────
  SELECT coalesce(w.balance, 0) INTO v_saldo
    FROM muevete.wallet_drivers w WHERE w.driver_id = v_driver;
  IF NOT FOUND THEN
    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_driver, 0)
    ON CONFLICT (driver_id) DO NOTHING;
    v_saldo := 0;
  END IF;
  v_saldo := coalesce(v_saldo, 0);

  v_comision := round(coalesce(v_prev.precio_plataforma, 0)
                      * coalesce(v_prev.comision_pct, v_cfg.comision_pct) / 100.0, 2);
  IF coalesce(v_cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, v_cfg.tope_comision_viaje);
  END IF;

  v_disponible := v_saldo
                  + CASE WHEN coalesce(v_cfg.permite_deuda, true)
                         THEN coalesce(v_cfg.limite_deuda_efectivo, 0)
                         ELSE 0 END;

  IF v_disponible < v_comision THEN
    IF coalesce(v_cfg.permite_deuda, true) THEN
      RAISE EXCEPTION 'limite_de_deuda_alcanzado: comision % > disponible %',
        v_comision, v_disponible USING ERRCODE = 'P0023';
    ELSE
      RAISE EXCEPTION 'saldo_insuficiente_para_comision: comision % > saldo %',
        v_comision, v_saldo USING ERRCODE = 'P0023';
    END IF;
  END IF;

  v_metodo := coalesce(v_prev.metodo_pago, 'efectivo');

  -- ── 8. TOMA ATÓMICA: una sola sentencia ────────────────────────────────
  UPDATE muevete.solicitudes_transporte s
     SET estado      = 'aceptada',
         driver_id   = v_driver,
         aceptada_at = now()
   WHERE s.id = p_solicitud_id
     AND s.estado = 'pendiente'
     AND s.driver_id IS NULL
     AND (s.expires_at IS NULL OR s.expires_at > now())
  RETURNING * INTO v_sol;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ya_tomado' USING ERRCODE = 'P0020';
  END IF;

  -- ── 9. Crear el viaje en la MISMA transacción ──────────────────────────
  --    Va ANTES de la retención para tener el viaje_id y poder registrar el
  --    débito ya asociado (el convenio de 038 busca la retención por viaje_id).
  --    Si la retención falla, revierte todo y la solicitud vuelve a 'pendiente'.
  INSERT INTO muevete.viajes (
    driver_id, "user", estado, completado, visto,
    latitud_cliente, longitud_cliente,
    solicitud_id, precio_plataforma, precio_chofer, comision_pct, metodo_pago
  ) VALUES (
    v_driver, v_sol.user_id::text, false, false, false,
    v_sol.lat_destino::text, v_sol.lon_destino::text,
    v_sol.id, v_sol.precio_plataforma, v_sol.precio_chofer,
    coalesce(v_sol.comision_pct, v_cfg.comision_pct), v_metodo
  ) RETURNING id INTO v_viaje_id;

  -- ── 10. Retención de wallet del cliente (sólo si paga por wallet) ──────
  --    OJO: suscription_user NO tiene índice único por user_id. Se apunta a la
  --    fila de menor id para que el UPDATE sea determinista (nunca dos filas).
  IF v_metodo = 'wallet' THEN
    UPDATE muevete.suscription_user u
       SET balance = coalesce(u.balance, 0) - coalesce(v_sol.precio_plataforma, 0)
     WHERE u.id = (SELECT x.id FROM muevete.suscription_user x
                    WHERE x.user_id = v_sol.user_id
                    ORDER BY x.id
                    LIMIT 1)
       AND coalesce(u.balance, 0) >= coalesce(v_sol.precio_plataforma, 0)
    RETURNING u.balance INTO v_saldo_cli;

    IF v_saldo_cli IS NULL THEN
      RAISE EXCEPTION 'cliente_sin_saldo' USING ERRCODE = 'P0024';
    END IF;

    v_hold := coalesce(v_sol.precio_plataforma, 0);

    INSERT INTO muevete.transacciones_wallet
      (user_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
    VALUES
      (v_sol.user_id, v_viaje_id, 'cobro_viaje', -v_hold, v_saldo_cli,
       'Cobro retenido por viaje #' || v_sol.id, 'completada');
  END IF;

  -- ── 11. Cerrar ofertas legacy de esa solicitud ─────────────────────────
  UPDATE muevete.ofertas_chofer o
     SET estado = 'rechazada'
   WHERE o.solicitud_id = v_sol.id
     AND o.estado = 'pendiente';

  -- ── 12. Notificar al cliente ───────────────────────────────────────────
  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  VALUES (
    v_sol.user_id, 'viaje_asignado', 'Conductor asignado',
    'Tu conductor va en camino. Precio: ' || v_sol.precio_plataforma
      || ' ' || coalesce(v_sol.moneda, 'CUP'),
    jsonb_build_object('solicitud_id', v_sol.id, 'viaje_id', v_viaje_id,
                       'driver_id', v_driver,
                       'precio_plataforma', v_sol.precio_plataforma)
  );

  RETURN jsonb_build_object(
    'success',           true,
    'solicitud_id',      v_sol.id,
    'viaje_id',          v_viaje_id,
    'precio_plataforma', v_sol.precio_plataforma,
    'comision_pct',      coalesce(v_sol.comision_pct, v_cfg.comision_pct),
    'comision_monto',    v_comision,
    'precio_chofer',     round(coalesce(v_sol.precio_plataforma, 0) - v_comision, 2),
    'metodo_pago',       v_metodo,
    'hold_cliente',      v_hold,
    'saldo_chofer',      v_saldo,
    'capacidad_vehiculo', v_capacidad
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_tomar_viaje(bigint) IS
  'Toma atómica de un viaje (el primero gana). Valida gates, tipo, zona, capacidad y deuda; crea el viaje y retiene el wallet del cliente.';

REVOKE ALL ON FUNCTION muevete.fn_tomar_viaje(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_tomar_viaje(bigint) TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Objetos:
--   SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'muevete'
--      AND proname IN ('fn_viajes_disponibles','fn_tomar_viaje');
--
-- 2) La lista NO filtra por tipo ni por capacidad: sólo la zona. Esas dos
--    condiciones salen en `puede_tomar` / `motivo_bloqueo` para que el chofer
--    VEA el viaje y sepa por qué no puede tomarlo (regla 4 del plan):
--   SET request.jwt.claims = '{"sub":"<uuid-chofer>","role":"authenticated"}';
--   SELECT muevete.fn_viajes_disponibles(22.40689, -79.96450, 10);
--     -- cada fila: precio_plataforma (lo que paga el cliente),
--     --            comision_monto, precio_chofer (lo que te toca),
--     --            puede_tomar, motivo_bloqueo
--
-- 3) Concurrencia (dos sesiones):
--   S1: BEGIN; SELECT muevete.fn_tomar_viaje(<id>);            -- éxito
--   S2: BEGIN; SELECT muevete.fn_tomar_viaje(<id>);            -- espera a S1,
--       -- y tras el COMMIT de S1 lanza 'ya_tomado' (P0020)
--
-- 4) Doble toma del mismo chofer:
--   -- una segunda toma inmediata → chofer_con_viaje_activo (P0012)
--
-- 5) Wallet:
--   -- cliente con saldo >= precio: se descuenta y aparece una fila
--   -- transacciones_wallet tipo='retencion', monto NEGATIVO, viaje_id no nulo
--   -- cliente sin saldo → cliente_sin_saldo (P0024) y NO se toma el viaje
--
-- 6) Permisos: authenticated=true, anon=false en ambas.
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DROP FUNCTION IF EXISTS muevete.fn_tomar_viaje(bigint);
-- DROP FUNCTION IF EXISTS muevete.fn_viajes_disponibles(double precision, double precision, integer);
-- ============================================================================