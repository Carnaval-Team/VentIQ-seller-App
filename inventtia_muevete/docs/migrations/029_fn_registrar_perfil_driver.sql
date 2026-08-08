-- ============================================================
-- 029_fn_registrar_perfil_driver.sql
-- ============================================================
-- Registra perfil de driver (conductor / carrier / dispatcher)
-- + vehículo opcional + carrocerías opcionales en UNA transacción,
-- bypassing RLS de forma segura (SECURITY DEFINER).
--
-- También agrega policies quirúrgicas en vehiculos para INSERT/UPDATE
-- propios (por si se usa el cliente directo en otros flujos).
--
-- APLICAR MANUALMENTE en el SQL Editor del proyecto Muevete.
-- ============================================================

-- ------------------------------------------------------------
-- 1) RLS quirúrgico en vehiculos (propio driver_uuid)
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'vehiculos'
      AND policyname = 'drivers_insert_own_vehiculos'
  ) THEN
    CREATE POLICY drivers_insert_own_vehiculos
      ON muevete.vehiculos
      FOR INSERT
      TO authenticated
      WITH CHECK (driver_uuid = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'muevete'
      AND tablename  = 'vehiculos'
      AND policyname = 'drivers_update_own_vehiculos'
  ) THEN
    CREATE POLICY drivers_update_own_vehiculos
      ON muevete.vehiculos
      FOR UPDATE
      TO authenticated
      USING (driver_uuid = auth.uid())
      WITH CHECK (driver_uuid = auth.uid());
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2) RPC de registro atómico
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_registrar_perfil_driver(
  p_perfil      jsonb,
  p_vehiculo    jsonb DEFAULT NULL,
  p_carrocerias jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = muevete, public, auth
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_tipo           text;
  v_driver_id      bigint;
  v_vehicle_id     bigint;
  v_existing_id    bigint;
  v_item           jsonb;
  v_carrocerias_n  int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Sesión requerida. Completa el signup/login antes de registrar el perfil.'
    );
  END IF;

  IF p_perfil IS NULL OR jsonb_typeof(p_perfil) <> 'object' THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'p_perfil es obligatorio'
    );
  END IF;

  v_tipo := COALESCE(p_perfil->>'tipo_usuario', 'conductor_pasajeros');

  IF v_tipo NOT IN ('conductor_pasajeros', 'carrier_carga', 'dispatcher') THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'tipo_usuario inválido: ' || v_tipo
    );
  END IF;

  -- Idempotencia: si ya existe perfil para este auth user, no duplicar
  SELECT id INTO v_existing_id
  FROM muevete.drivers
  WHERE uuid = v_uid
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Perfil driver ya existía',
      'driver_id', v_existing_id,
      'already_exists', true
    );
  END IF;

  -- Insert driver: uuid SIEMPRE desde auth.uid() (no confiar en el cliente)
  INSERT INTO muevete.drivers (
    uuid,
    name,
    email,
    telefono,
    estado,
    tipo_usuario,
    pais,
    province,
    municipality,
    tipo_documento,
    doc_frente_url,
    doc_dorso_url,
    lic_conduccion_frente_url,
    lic_conduccion_dorso_url,
    lic_circulacion_frente_url,
    lic_circulacion_dorso_url,
    lic_operativa_frente_url,
    lic_operativa_dorso_url,
    empresa_nombre,
    empresa_rut,
    empresa_direccion
  ) VALUES (
    v_uid,
    NULLIF(TRIM(COALESCE(p_perfil->>'name', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'email', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'telefono', '')), ''),
    COALESCE((p_perfil->>'estado')::boolean, false),
    v_tipo,
    NULLIF(TRIM(COALESCE(p_perfil->>'pais', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'province', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'municipality', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'tipo_documento', '')), ''),
    NULLIF(p_perfil->>'doc_frente_url', ''),
    NULLIF(p_perfil->>'doc_dorso_url', ''),
    NULLIF(p_perfil->>'lic_conduccion_frente_url', ''),
    NULLIF(p_perfil->>'lic_conduccion_dorso_url', ''),
    NULLIF(p_perfil->>'lic_circulacion_frente_url', ''),
    NULLIF(p_perfil->>'lic_circulacion_dorso_url', ''),
    NULLIF(p_perfil->>'lic_operativa_frente_url', ''),
    NULLIF(p_perfil->>'lic_operativa_dorso_url', ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'empresa_nombre', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'empresa_rut', '')), ''),
    NULLIF(TRIM(COALESCE(p_perfil->>'empresa_direccion', '')), '')
  )
  RETURNING id INTO v_driver_id;

  -- Vehículo de pasajeros (opcional)
  IF v_tipo = 'conductor_pasajeros'
     AND p_vehiculo IS NOT NULL
     AND jsonb_typeof(p_vehiculo) = 'object'
     AND NULLIF(TRIM(COALESCE(p_vehiculo->>'chapa', '')), '') IS NOT NULL
  THEN
    INSERT INTO muevete.vehiculos (
      driver_uuid,
      marca,
      modelo,
      chapa,
      color,
      "año",
      capacidad_int,
      capacidad,
      condicion,
      aire_acondicionado,
      id_tipo_vehiculo
    ) VALUES (
      v_uid,
      NULLIF(TRIM(COALESCE(p_vehiculo->>'marca', '')), ''),
      NULLIF(TRIM(COALESCE(p_vehiculo->>'modelo', '')), ''),
      TRIM(p_vehiculo->>'chapa'),
      NULLIF(TRIM(COALESCE(p_vehiculo->>'color', '')), ''),
      COALESCE(
        NULLIF(p_vehiculo->>'año', '')::integer,
        NULLIF(p_vehiculo->>'anio', '')::integer
      ),
      NULLIF(p_vehiculo->>'capacidad_int', '')::integer,
      CASE
        WHEN NULLIF(p_vehiculo->>'capacidad_int', '') IS NOT NULL
          THEN (p_vehiculo->>'capacidad_int')
        ELSE NULLIF(p_vehiculo->>'capacidad', '')
      END,
      COALESCE(NULLIF(p_vehiculo->>'condicion', ''), 'bueno'),
      COALESCE((p_vehiculo->>'aire_acondicionado')::boolean, false),
      NULLIF(p_vehiculo->>'id_tipo_vehiculo', '')::bigint
    )
    RETURNING id INTO v_vehicle_id;

    UPDATE muevete.drivers
    SET vehiculo = v_vehicle_id
    WHERE id = v_driver_id;
  END IF;

  -- Carrocerías de carrier (opcional)
  IF v_tipo = 'carrier_carga'
     AND p_carrocerias IS NOT NULL
     AND jsonb_typeof(p_carrocerias) = 'array'
  THEN
    FOR v_item IN
      SELECT value FROM jsonb_array_elements(p_carrocerias)
    LOOP
      IF NULLIF(TRIM(COALESCE(v_item->>'tipo_carroceria', '')), '') IS NULL THEN
        CONTINUE;
      END IF;

      INSERT INTO muevete.carrocerias (
        driver_id,
        marca,
        modelo,
        matricula,
        tipo_carroceria,
        capacidad_ton,
        longitud_m,
        seguro_vigente,
        lic_circulacion_frente_url,
        lic_circulacion_dorso_url,
        lic_operativa_frente_url,
        lic_operativa_dorso_url
      ) VALUES (
        v_driver_id,
        NULLIF(TRIM(COALESCE(v_item->>'marca', '')), ''),
        NULLIF(TRIM(COALESCE(v_item->>'modelo', '')), ''),
        NULLIF(TRIM(COALESCE(v_item->>'matricula', '')), ''),
        TRIM(v_item->>'tipo_carroceria'),
        NULLIF(v_item->>'capacidad_ton', '')::numeric,
        NULLIF(v_item->>'longitud_m', '')::numeric,
        COALESCE((v_item->>'seguro_vigente')::boolean, false),
        NULLIF(v_item->>'lic_circulacion_frente_url', ''),
        NULLIF(v_item->>'lic_circulacion_dorso_url', ''),
        NULLIF(v_item->>'lic_operativa_frente_url', ''),
        NULLIF(v_item->>'lic_operativa_dorso_url', '')
      );

      v_carrocerias_n := v_carrocerias_n + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Perfil driver registrado',
    'driver_id', v_driver_id,
    'vehicle_id', v_vehicle_id,
    'carrocerias', v_carrocerias_n,
    'already_exists', false
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Ya existe un registro con ese email o uuid'
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', SQLERRM
    );
END;
$$;

COMMENT ON FUNCTION muevete.fn_registrar_perfil_driver(jsonb, jsonb, jsonb) IS
'Registra drivers + vehículo/carrocerías atómicamente usando auth.uid(). SECURITY DEFINER.';

GRANT EXECUTE ON FUNCTION muevete.fn_registrar_perfil_driver(jsonb, jsonb, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION muevete.fn_registrar_perfil_driver(jsonb, jsonb, jsonb)
  TO service_role;
