-- ============================================================================
-- 032_taxi_geo_y_cotizacion.sql
-- H0 · Geometría (sin PostGIS) y motor de cotización.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/04-diseno-tecnico.md §3.2, §3.3, §4.2
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql (no se redefine nada suyo)
--   · 031_taxi_zonas_tarifas.sql (zonas_tarifa, tarifas_municipio,
--     configuracion_tarifas y vehicle_type.multiplicador_tarifa)
--
-- NO HAY POSTGIS (verificado en producción): point-in-polygon en PL/pgSQL
-- mediante ray casting. fn_punto_en_poligono es el ÚNICO punto de acoplamiento
-- con la geometría; si algún día se habilita PostGIS se reemplaza su cuerpo
-- manteniendo la firma.
--
-- IDEMPOTENCIA: CREATE OR REPLACE FUNCTION + REVOKE/GRANT (idempotentes).
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 0. HELPERS INTERNOS (NO son RPC públicas: sin GRANT a authenticated/anon)
--    Se revocan de PUBLIC porque PostgreSQL concede EXECUTE a PUBLIC por defecto.
--    Las RPC SECURITY DEFINER pueden llamarlos igualmente (corren como owner).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0.1 Ray casting sobre UN anillo [[lon,lat],...]
--     Devuelve false si el anillo está malformado (no adivina).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_punto_en_anillo(
  p_lat    double precision,
  p_lon    double precision,
  p_anillo jsonb
) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_n      integer;
  v_i      integer;
  v_j      integer;
  v_xi     double precision; v_yi double precision;
  v_xj     double precision; v_yj double precision;
  v_inside boolean := false;
BEGIN
  IF p_anillo IS NULL OR jsonb_typeof(p_anillo) <> 'array' THEN
    RETURN false;
  END IF;

  v_n := jsonb_array_length(p_anillo);
  IF v_n < 3 THEN
    RETURN false;
  END IF;

  v_j := v_n - 1;
  FOR v_i IN 0 .. v_n - 1 LOOP
    v_xi := (p_anillo -> v_i ->> 0)::double precision;  -- lon
    v_yi := (p_anillo -> v_i ->> 1)::double precision;  -- lat
    v_xj := (p_anillo -> v_j ->> 0)::double precision;
    v_yj := (p_anillo -> v_j ->> 1)::double precision;

    IF v_xi IS NULL OR v_yi IS NULL OR v_xj IS NULL OR v_yj IS NULL THEN
      RETURN false;   -- anillo malformado: no adivinar
    END IF;

    IF ((v_yi > p_lat) <> (v_yj > p_lat))
       AND (p_lon < (v_xj - v_xi) * (p_lat - v_yi)
                    / nullif(v_yj - v_yi, 0) + v_xi)
    THEN
      v_inside := NOT v_inside;
    END IF;

    v_j := v_i;
  END LOOP;

  RETURN v_inside;
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_punto_en_anillo(double precision, double precision, jsonb)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION muevete.fn_punto_en_anillo(double precision, double precision, jsonb) IS
  'INTERNA. Ray casting sobre un anillo GeoJSON [[lon,lat],...]. No expuesta como RPC.';

-- ----------------------------------------------------------------------------
-- 0.2 Distancia geodésica en km (haversine)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_haversine_km(
  p_lat1 double precision, p_lon1 double precision,
  p_lat2 double precision, p_lon2 double precision
) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT 2 * 6371.0088 * atan2(sqrt(v.a), sqrt(greatest(0::double precision, 1 - v.a)))
  FROM (
    SELECT power(sin(radians(p_lat2 - p_lat1) / 2), 2)
         + cos(radians(p_lat1)) * cos(radians(p_lat2))
         * power(sin(radians(p_lon2 - p_lon1) / 2), 2) AS a
  ) AS v;
$$;

REVOKE ALL ON FUNCTION muevete.fn_haversine_km(double precision, double precision, double precision, double precision)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION muevete.fn_haversine_km(double precision, double precision, double precision, double precision) IS
  'INTERNA. Distancia haversine en km. No expuesta como RPC.';

-- ============================================================================
-- 1. RPC #1 · fn_punto_en_poligono
--    GeoJSON Polygon: p_geojson = {"type":"Polygon","coordinates":[anillo, huecos...]}
--    - coordinates[0] = anillo exterior
--    - coordinates[1..] = huecos (restan)
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_punto_en_poligono(
  p_lat     double precision,
  p_lon     double precision,
  p_geojson jsonb
) RETURNS boolean
-- SECURITY DEFINER OBLIGATORIO: esta función se concede a `authenticated`, pero
-- por dentro llama a `fn_punto_en_anillo`, que es INTERNA y está revocada para
-- los clientes. Sin DEFINER, cualquier llamada desde la app fallaba con
-- `42501 permission denied for function fn_punto_en_anillo` (detectado con una
-- llamada real a `fn_cotizar_viaje` desde PostgREST). El `search_path` ya está
-- fijado, que es lo que hace seguro el DEFINER.
-- Tampoco puede ser PARALLEL SAFE: DEFINER + ejecución en paralelo es inseguro.
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_anillos jsonb;
  v_n       integer;
  v_i       integer;
BEGIN
  IF p_geojson IS NULL OR jsonb_typeof(p_geojson) <> 'object' THEN
    RETURN false;
  END IF;

  v_anillos := p_geojson -> 'coordinates';
  IF v_anillos IS NULL OR jsonb_typeof(v_anillos) <> 'array'
     OR jsonb_array_length(v_anillos) = 0 THEN
    RETURN false;
  END IF;

  -- Fuera del anillo exterior → fuera del polígono
  IF NOT muevete.fn_punto_en_anillo(p_lat, p_lon, v_anillos -> 0) THEN
    RETURN false;
  END IF;

  -- Dentro de un hueco → fuera del polígono
  v_n := jsonb_array_length(v_anillos);
  FOR v_i IN 1 .. v_n - 1 LOOP
    IF muevete.fn_punto_en_anillo(p_lat, p_lon, v_anillos -> v_i) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb) IS
  'RPC #1. Point-in-polygon (Ray casting + huecos) sobre GeoJSON Polygon. Sin PostGIS.';

-- ============================================================================
-- 2. RPC #2 · fn_zona_de_punto
--    Devuelve 0 o 1 fila: la zona activa y vigente de MAYOR prioridad que
--    contiene el punto. A igual prioridad gana el id menor (determinista).
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_zona_de_punto(
  p_lat double precision,
  p_lon double precision,
  p_at  timestamptz DEFAULT now()
) RETURNS SETOF muevete.zonas_tarifa
-- SECURITY DEFINER por el mismo motivo que fn_punto_en_poligono: es pública
-- (concedida a `authenticated`) y delega en helpers internos revocados.
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
  SELECT z.*
  FROM muevete.zonas_tarifa z
  WHERE z.activo
    AND z.vigente_desde <= p_at
    AND (z.vigente_hasta IS NULL OR z.vigente_hasta > p_at)
    AND muevete.fn_punto_en_poligono(p_lat, p_lon, z.geometria)
  ORDER BY z.prioridad DESC, z.id ASC
  LIMIT 1;
$$;

COMMENT ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz) IS
  'RPC #2. Zona tarifaria activa/vigente que contiene el punto (mayor prioridad). 0 o 1 fila.';

-- ============================================================================
-- 3. RPC #3 · fn_cotizar_viaje
--    Implementación literal de la fórmula del anexo §4.1:
--      0) zona_origen / zona_destino / fallback municipal (D4)
--      1) modo: fijo (dentro → monto_fijo; sale → km*precio_km)
--               fijo_mas_km (monto_fijo + km*precio_km)
--               por_km (km*precio_km)
--      2) × vehicle_type.multiplicador_tarifa (D2)
--      3) piso por tipo (auto/moto/microbus)
--         + tope precio_corto_auto para auto con km < umbral_km_corto
--      4) recargos: nocturno % y prima por distancia > umbral
--      5) redondeo HACIA ARRIBA a múltiplos de redondeo_cup
--      6) comisión desde configuración con tope; precio_chofer = total - comisión
--    NO escribe nada. La usan: cliente (preview), fn_crear_solicitud (verdad),
--    simulador del superadmin (mismo número que la app).
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_cotizar_viaje(
  p_lat_o     double precision,
  p_lon_o     double precision,
  p_lat_d     double precision,
  p_lon_d     double precision,
  p_id_tipo   bigint,
  p_at        timestamptz DEFAULT now(),
  p_km        double precision DEFAULT NULL,
  p_provincia text DEFAULT NULL,
  p_municipio text DEFAULT NULL
) RETURNS jsonb
-- SECURITY DEFINER: es la RPC pública que usa la app para el preview. Por dentro
-- usa `fn_zona_de_punto`, `fn_haversine_km` y `fn_punto_en_anillo`, todos
-- internos y revocados para `authenticated`. Resto de RPC del módulo (038–040)
-- ya son DEFINER por el mismo motivo.
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  cfg            muevete.configuracion_tarifas%ROWTYPE;
  v_tipo         text;
  v_mult         numeric;
  v_zona_o       muevete.zonas_tarifa%ROWTYPE;
  v_zona_d       muevete.zonas_tarifa%ROWTYPE;
  v_muni         muevete.tarifas_municipio%ROWTYPE;
  v_modo         text;
  v_monto_fijo   numeric := 0;
  v_precio_km    numeric := 0;
  v_dentro       boolean := false;
  v_km_lineal    numeric;
  v_km           numeric;
  v_km_fuente    text;
  v_base         numeric := 0;
  v_precio       numeric := 0;
  v_minimo       numeric;
  v_corto        boolean := false;
  v_nocturno     boolean := false;
  v_hora         time;
  v_rec_noct     numeric := 0;
  v_rec_prima    numeric := 0;
  v_pre_redondeo numeric;
  v_comision     numeric;
  v_chofer       numeric;
  v_detalle      jsonb;
BEGIN
  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'configuracion_tarifas_no_inicializada' USING ERRCODE = 'P0001';
  END IF;

  SELECT vt.tipo, coalesce(vt.multiplicador_tarifa, 1)
    INTO v_tipo, v_mult
    FROM muevete.vehicle_type vt
   WHERE vt.id = p_id_tipo;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'tipo_vehiculo_invalido: %', p_id_tipo USING ERRCODE = 'P0002';
  END IF;

  -- ── Zonas ────────────────────────────────────────────────────────────
  SELECT * INTO v_zona_o FROM muevete.fn_zona_de_punto(p_lat_o, p_lon_o, p_at) LIMIT 1;
  SELECT * INTO v_zona_d FROM muevete.fn_zona_de_punto(p_lat_d, p_lon_d, p_at) LIMIT 1;

  -- ── Distancia ────────────────────────────────────────────────────────
  v_km_lineal := muevete.fn_haversine_km(p_lat_o, p_lon_o, p_lat_d, p_lon_d);

  IF p_km IS NULL OR p_km <= 0 THEN
    v_km := round(v_km_lineal::numeric, 3);
    v_km_fuente := 'haversine';
  ELSE
    -- Anti-manipulación (desvío D-05 del anexo): nunca menos que la recta,
    -- nunca más que 2× recta + 1 km (holgura por el snap a vías).
    v_km := least(greatest(p_km, v_km_lineal), v_km_lineal * 2.0 + 1.0);
    v_km := round(v_km::numeric, 3);
    v_km_fuente := 'ruta';
  END IF;

  -- ── Regla: zona del origen o fallback municipal (D4) ─────────────────
  IF v_zona_o.id IS NOT NULL THEN
    v_modo       := v_zona_o.modo;
    v_monto_fijo := coalesce(v_zona_o.monto_fijo, 0);
    v_precio_km  := coalesce(v_zona_o.precio_km, cfg.precio_km_fallback, 0);
    v_dentro     := v_zona_d.id IS NOT NULL AND v_zona_d.id = v_zona_o.id;
  ELSE
    SELECT * INTO v_muni
      FROM muevete.tarifas_municipio m
     WHERE m.activo
       AND (p_provincia IS NULL OR lower(m.provincia) = lower(p_provincia))
       AND (p_municipio IS NULL OR lower(m.municipio) = lower(p_municipio))
     ORDER BY m.id
     LIMIT 1;

    IF v_muni.id IS NOT NULL THEN
      v_modo       := v_muni.modo;
      v_monto_fijo := v_muni.monto_fijo;
      v_precio_km  := v_muni.precio_km;
    ELSE
      v_modo       := 'fijo';
      v_monto_fijo := coalesce(cfg.monto_fijo_fallback_municipio, 1500);
      v_precio_km  := coalesce(cfg.precio_km_fallback, 400);
    END IF;
  END IF;

  -- ── Base según modo (D3) ─────────────────────────────────────────────
  IF v_zona_o.id IS NULL THEN
    -- Fallback: sin lógica "dentro/sale", se aplica el modo del municipio
    v_base := CASE v_modo
                WHEN 'por_km'      THEN v_km * v_precio_km
                WHEN 'fijo_mas_km' THEN v_monto_fijo + v_km * v_precio_km
                ELSE v_monto_fijo
              END;
  ELSE
    v_base := CASE v_modo
                WHEN 'fijo' THEN
                  CASE WHEN v_dentro THEN v_monto_fijo ELSE v_km * v_precio_km END
                WHEN 'fijo_mas_km' THEN v_monto_fijo + v_km * v_precio_km
                WHEN 'por_km'      THEN v_km * v_precio_km
                ELSE v_monto_fijo
              END;
  END IF;

  -- ── Multiplicador por tipo (D2) ──────────────────────────────────────
  v_precio := round(v_base * v_mult, 2);

  -- ── Piso por tipo ────────────────────────────────────────────────────
  v_minimo := CASE lower(v_tipo)
                WHEN 'auto'     THEN cfg.precio_minimo_auto
                WHEN 'moto'     THEN cfg.precio_minimo_moto
                WHEN 'microbus' THEN cfg.precio_minimo_microbus
                ELSE NULL
              END;
  IF v_minimo IS NOT NULL AND v_minimo > 0 THEN
    v_precio := greatest(v_precio, v_minimo);
  END IF;

  -- ── Válvula de viaje corto (sólo auto) ───────────────────────────────
  IF lower(v_tipo) = 'auto'
     AND coalesce(cfg.precio_corto_auto, 0) > 0
     AND v_km < coalesce(cfg.umbral_km_corto, 1.5) THEN
    IF v_precio > cfg.precio_corto_auto THEN
      v_precio := cfg.precio_corto_auto;
      v_corto  := true;
    END IF;
  END IF;

  -- ── Recargos ─────────────────────────────────────────────────────────
  v_hora := (p_at AT TIME ZONE 'America/Havana')::time;  -- zona horaria del producto

  IF cfg.ventana_nocturna_inicio <= cfg.ventana_nocturna_fin THEN
    v_nocturno := v_hora >= cfg.ventana_nocturna_inicio
                  AND v_hora < cfg.ventana_nocturna_fin;
  ELSE  -- ventana que cruza medianoche (22:00 → 06:00)
    v_nocturno := v_hora >= cfg.ventana_nocturna_inicio
                  OR v_hora < cfg.ventana_nocturna_fin;
  END IF;

  IF v_nocturno AND cfg.recargo_nocturno_pct > 0 THEN
    v_rec_noct := round(v_precio * cfg.recargo_nocturno_pct / 100.0, 2);
  END IF;

  IF coalesce(cfg.prima_distancia_cup, 0) > 0
     AND v_km > coalesce(cfg.umbral_prima_distancia_km, 8) THEN
    v_rec_prima := cfg.prima_distancia_cup;
  END IF;

  v_precio := v_precio + v_rec_noct + v_rec_prima;
  v_pre_redondeo := v_precio;

  -- ── Redondeo HACIA ARRIBA a múltiplos de redondeo_cup ────────────────
  IF coalesce(cfg.redondeo_cup, 0) > 0 THEN
    v_precio := ceil(v_precio / cfg.redondeo_cup) * cfg.redondeo_cup;
  ELSE
    v_precio := round(v_precio, 2);
  END IF;

  -- ── Comisión (D5) con tope ───────────────────────────────────────────
  v_comision := round(v_precio * cfg.comision_pct / 100.0, 2);
  IF coalesce(cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, cfg.tope_comision_viaje);
  END IF;
  v_chofer := v_precio - v_comision;

  -- ── Snapshot del desglose (se persiste en tarifa_detalle) ────────────
  v_detalle := jsonb_build_object(
    'zona_origen_id',       v_zona_o.id,
    'zona_origen_nombre',   v_zona_o.nombre,
    'zona_destino_id',      v_zona_d.id,
    'zona_destino_nombre',  v_zona_d.nombre,
    'dentro_de_zona',       v_dentro,
    'fallback_municipio',   v_zona_o.id IS NULL,
    'municipio_aplicado',   CASE WHEN v_zona_o.id IS NULL THEN v_muni.municipio END,
    'modo',                 v_modo,
    'monto_fijo',           v_monto_fijo,
    'precio_km',            v_precio_km,
    'km_lineal',            round(v_km_lineal::numeric, 3),
    'km_total',             v_km,
    'km_fuente',            v_km_fuente,
    'base',                 round(v_base, 2),
    'multiplicador_tipo',   v_mult,
    'tipo_vehiculo',        v_tipo,
    'precio_minimo',        v_minimo,
    'precio_corto_aplicado', v_corto,
    'es_nocturno',          v_nocturno,
    'recargo_nocturno',     v_rec_noct,
    'recargo_prima_distancia', v_rec_prima,
    'precio_antes_redondeo', round(v_pre_redondeo, 2),
    'redondeo_cup',         cfg.redondeo_cup,
    'precio_plataforma',    v_precio
  );

  RETURN jsonb_build_object(
    'precio_plataforma',  v_precio,
    'moneda',             cfg.moneda,
    'comision_pct',       cfg.comision_pct,
    'comision_monto',     v_comision,
    'precio_chofer',      v_chofer,
    'zona_id',            v_zona_o.id,
    'zona_nombre',        coalesce(v_zona_o.nombre, 'Fuera de zona'),
    'tarifa_modo',        v_modo,
    'km_total',           v_km,
    'km_fuente',          v_km_fuente,
    'tipo_vehiculo',      v_tipo,
    'multiplicador_tipo', v_mult,
    'es_nocturno',        v_nocturno,
    'precio_corto',       v_corto,
    'detalle',            v_detalle,
    'precio_vigente_desde', cfg.precio_vigente_desde,
    'calculado_at',       p_at
  );
END;
$$;

COMMENT ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) IS
  'RPC #3. Motor único de cotización del taxi. No escribe nada. Mismo resultado para cliente, chofer y simulador admin.';

-- ============================================================================
-- 4. PERMISOS DE LAS RPC (sólo authenticated; anon/PUBLIC revocados)
-- ============================================================================

REVOKE ALL ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
  TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
  TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración).
-- Usa la configuración y zonas del seed 033 para que los números cuadren.
-- ============================================================================
-- 0) Funciones creadas:
--   SELECT p.proname, pg_get_function_arguments(p.oid)
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='muevete'
--      AND p.proname IN ('fn_punto_en_anillo','fn_haversine_km',
--                        'fn_punto_en_poligono','fn_zona_de_punto','fn_cotizar_viaje')
--    ORDER BY p.proname;
--
-- 1) Helpers NO expuestos:
--   SELECT has_function_privilege('authenticated',
--            'muevete.fn_punto_en_anillo(double precision,double precision,jsonb)', 'EXECUTE');
--      -- esperado: false
--   SELECT has_function_privilege('authenticated',
--            'muevete.fn_haversine_km(double precision,double precision,double precision,double precision)', 'EXECUTE');
--      -- esperado: false
--
-- 2) Point-in-polygon básico (cuadrado de prueba en Santa Clara):
--   SELECT muevete.fn_punto_en_poligono(
--     22.410, -79.970,
--     '{"type":"Polygon","coordinates":[[[-79.980,22.400],[-79.960,22.400],[-79.960,22.420],[-79.980,22.420]]]}'::jsonb);
--      -- esperado: true
--   SELECT muevete.fn_punto_en_poligono(
--     22.500, -79.970,
--     '{"type":"Polygon","coordinates":[[[-79.980,22.400],[-79.960,22.400],[-79.960,22.420],[-79.980,22.420]]]}'::jsonb);
--      -- esperado: false
--
-- 3) Hueco: el punto dentro del hueco debe dar false.
--
-- 4) Zona del punto:
--   SELECT id, codigo, nombre, prioridad FROM muevete.fn_zona_de_punto(22.4069, -79.9657);
--      -- esperado: una fila (MUN o la zona interna que corresponda)
--
-- 5) Cotización con los datos del seed (auto, 3.2 km dentro de MUN):
--   SELECT jsonb_pretty(muevete.fn_cotizar_viaje(
--     22.4069, -79.9657, 22.4120, -79.9600, 2,
--     '2026-11-12T10:00:00-05:00'::timestamptz, 3.2, 'Villa Clara', 'Santa Clara'));
--      -- esperado: precio_plataforma 1500, comision_monto 225, precio_chofer 1275
--      --           (si el id del tipo auto no es 2, ajustar p_id_tipo)
--
-- 6) No escribe nada:
--   SELECT count(*) FROM muevete.solicitudes_transporte;  -- igual antes y después
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
--   double precision, double precision, double precision, double precision,
--   bigint, timestamptz, double precision, text, text) FROM authenticated;
-- REVOKE ALL ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz)
--   FROM authenticated;
-- REVOKE ALL ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb)
--   FROM authenticated;
-- DROP FUNCTION IF EXISTS muevete.fn_cotizar_viaje(
--   double precision, double precision, double precision, double precision,
--   bigint, timestamptz, double precision, text, text);
-- DROP FUNCTION IF EXISTS muevete.fn_zona_de_punto(double precision, double precision, timestamptz);
-- DROP FUNCTION IF EXISTS muevete.fn_punto_en_poligono(double precision, double precision, jsonb);
-- DROP FUNCTION IF EXISTS muevete.fn_haversine_km(double precision, double precision, double precision, double precision);
-- DROP FUNCTION IF EXISTS muevete.fn_punto_en_anillo(double precision, double precision, jsonb);
-- COMMIT;
-- ============================================================================