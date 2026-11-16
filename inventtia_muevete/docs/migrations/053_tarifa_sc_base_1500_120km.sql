-- ============================================================================
-- 053_tarifa_sc_base_1500_120km.sql
-- H? · Corrige la tarifa de Santa Clara a la regla de negocio vigente:
--
--   · Base de 1.500 CUP dentro del "casco" de Santa Clara: un círculo de 4,3 km
--     alrededor del Parque Vidal que cubre el centro, la zona de la universidad
--     José Martí y el reparto Arco Iris.
--   · 120 CUP por cada km adicional (fuera de ese casco).
--   · Si el pasajero está fuera del municipio de Santa Clara (p. ej. Placetas),
--     se cobra: 1.500 + 120 × (km de ida a recogerlo + km del viaje).
--
-- PROBLEMA QUE CORRIGE
--   El estado anterior (semilla 033) tenía:
--     · precio por km = 400 CUP (debía ser 120)
--     · la zona MUN cubría un rectángulo de ~22 × 28 km con 1.500 CUP PLANOS,
--       así que un viaje de 15 km dentro del municipio costaba lo mismo que uno
--       de 1 km, y un Placetas → Santa Clara (~40 km) costaba 1.500 CUP.
--     · el fallback municipal (`modo = fijo`) ignoraba la distancia.
--
-- REGLA IMPLEMENTADA (una sola, fácil de explicar al chofer)
--   precio = 1.500 + 120 × km_cobrables
--     · dentro del casco .......................... km_cobrables = 0
--     · Santa Clara, origen fuera del casco ....... km_cobrables = km del viaje
--     · otro municipio (Placetas, Camajuaní…) .... km_cobrables = km del viaje
--                                                   + km desde el Parque Vidal
--                                                     hasta el punto de recogida
--
--   Ejemplo Placetas → Parque Vidal: 1.500 + 120 × (34 + 40) ≈ 10.400 CUP
--   Ejemplo Santa Clara (casco) → Placetas: 1.500 + 120 × 40      =  6.300 CUP
--   Ejemplo dentro del casco (2 km):                               =  1.500 CUP
--
--   Encima de eso siguen aplicándose, sin cambios:
--     · multiplicador por tipo de vehículo (moto 0,60 · auto 1,00 · …)
--     · piso por tipo (auto 1.500 · moto 900 · microbús 2.250)
--     · recargo nocturno +20 % (22:00–06:00)
--     · redondeo hacia arriba a múltiplos de 50 CUP
--     · comisión de plataforma 15 %
--
--   Se APAGAN dos reglas que contradecían la base de 1.500:
--     · `precio_corto_auto` (1.000 CUP si el viaje era < 1,5 km) → 0
--     · `prima_distancia_cup` (500 CUP extra si > 8 km) → 0
--   Con 120 CUP/km la distancia ya se cobra por kilómetro; sumarle una prima
--   aparte haría que el precio no cuadrara con la fórmula publicada.
--
-- IDEMPOTENTE: se puede re-ejecutar. Las zonas se actualizan, no se duplican.
-- NO toca datos de viajes ya cerrados: `tarifa_detalle` es un snapshot.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Parámetros nuevos de configuración: hub de flota y municipio del hub
--    El hub es el punto desde el que se mide el km de recogida intermunicipal.
--    Por defecto: Parque Vidal, Santa Clara.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.configuracion_tarifas
  ADD COLUMN IF NOT EXISTS hub_lat      double precision,
  ADD COLUMN IF NOT EXISTS hub_lon      double precision,
  ADD COLUMN IF NOT EXISTS hub_municipio text;

COMMENT ON COLUMN muevete.configuracion_tarifas.hub_lat IS
  'Latitud del hub de flota. Se usa para cobrar el km de recogida cuando el pasajero está fuera del municipio del hub.';
COMMENT ON COLUMN muevete.configuracion_tarifas.hub_lon IS
  'Longitud del hub de flota (ver hub_lat).';
COMMENT ON COLUMN muevete.configuracion_tarifas.hub_municipio IS
  'Municipio del hub. Si el origen está en otro municipio, se suma el km hub→origen.';

-- ----------------------------------------------------------------------------
-- 2. Configuración global: 120 CUP/km y sin reglas que rompan la base
-- ----------------------------------------------------------------------------
UPDATE muevete.configuracion_tarifas SET
  hub_lat                   = 22.406959,   -- Parque Vidal, Santa Clara
  hub_lon                   = -79.965681,
  hub_municipio             = 'Santa Clara',
  precio_km_fallback        = 120,
  monto_fijo_fallback_municipio = 1500,
  precio_corto_auto         = 0,            -- apagado: la base son 1.500
  prima_distancia_cup       = 0,            -- apagado: la distancia se cobra por km
  taxi_precio_fijo_activo   = true,
  precio_vigente_desde      = coalesce(precio_vigente_desde, now()),
  updated_at                = now()
WHERE id = 1;

-- ----------------------------------------------------------------------------
-- 3. Fallback municipal de Santa Clara: fijo + km (1.500 / 120)
--    Aplica cuando el origen cae fuera de todas las zonas (p. ej. Placetas).
-- ----------------------------------------------------------------------------
INSERT INTO muevete.tarifas_municipio
  (provincia, municipio, modo, monto_fijo, precio_km, activo)
VALUES
  ('Villa Clara', 'Santa Clara', 'fijo_mas_km', 1500, 120, true)
ON CONFLICT (provincia, municipio) DO UPDATE
  SET modo       = 'fijo_mas_km',
      monto_fijo = 1500,
      precio_km  = 120,
      activo     = true,
      updated_at = now();

-- ----------------------------------------------------------------------------
-- 4. Zona base de Santa Clara (casco): círculo de 4,3 km alrededor del Parque
--    Vidal. Se genera un polígono de 48 lados; el cierre (i = 48) repite el
--    primer vértice para que el anillo sea válido.
--    El radio se eligió para que queden DENTRO los tres puntos que pidió el
--    negocio: Parque Vidal (0 km), reparto Arco Iris (≈3,9 km) y la zona de la
--    universidad José Martí (≈4,0 km). Placetas (≈34 km) queda fuera.
--    Prioridad 5: por debajo de las zonas internas (40..120) para que, si el
--    negocio activa Z1..Z9 en el futuro, esas ganen sobre el casco.
-- ----------------------------------------------------------------------------
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo,
   monto_fijo, precio_km, prioridad, activo, vigente_desde)
SELECT
  'SC-BASE',
  'Casco Santa Clara · 1.500 CUP',
  'Villa Clara',
  'Santa Clara',
  jsonb_build_object('type', 'Polygon', 'coordinates', jsonb_build_array(
    (SELECT jsonb_agg(jsonb_build_array(
              round((p.lon + (p.km / (111.320 * cos(radians(p.lat)))) * cos(2 * pi() * i / 48))::numeric, 6),
              round((p.lat + (p.km / 110.574) * sin(2 * pi() * i / 48))::numeric, 6)
            ) ORDER BY i)
     FROM generate_series(0, 48) AS i)
  )),
  'fijo',
  1500,
  120,
  5,
  true,
  '2026-01-01T00:00:00-05:00'::timestamptz
FROM (SELECT 22.406959::float8 AS lat, -79.965681::float8 AS lon, 4.3::float8 AS km) AS p
ON CONFLICT (codigo) DO UPDATE
  SET nombre        = excluded.nombre,
      geometria     = excluded.geometria,
      modo          = 'fijo',
      monto_fijo    = 1500,
      precio_km     = 120,
      prioridad     = 5,
      activo        = true,
      vigente_desde = excluded.vigente_desde,
      vigente_hasta = NULL,
      updated_at    = now();

-- ----------------------------------------------------------------------------
-- 5. La zona MUN (rectángulo de todo el municipio con 1.500 planos) se apaga.
--    Si se dejara activa, cualquier origen dentro del municipio —incluido un
--    punto a 15 km del centro— se cotizaría a 1.500 CUP.
-- ----------------------------------------------------------------------------
UPDATE muevete.zonas_tarifa
   SET activo = false,
       nombre = 'Municipio Santa Clara (desactivada · sustituida por SC-BASE)',
       updated_at = now()
 WHERE codigo = 'MUN';

-- ----------------------------------------------------------------------------
-- 6. fn_cotizar_viaje · misma firma (9 parámetros) y misma forma de salida,
--    con la nueva regla de negocio. La app no necesita cambios.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_cotizar_viaje(
  p_lat_o      double precision,
  p_lon_o      double precision,
  p_lat_d      double precision,
  p_lon_d      double precision,
  p_id_tipo    bigint,
  p_at         timestamp with time zone DEFAULT now(),
  p_km         double precision DEFAULT NULL,
  p_provincia  text DEFAULT NULL,
  p_municipio  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'muevete', 'pg_temp'
AS $function$
DECLARE
  cfg              muevete.configuracion_tarifas%ROWTYPE;
  v_tipo           text;
  v_mult           numeric;
  v_zona_o         muevete.zonas_tarifa%ROWTYPE;
  v_zona_d         muevete.zonas_tarifa%ROWTYPE;
  v_muni           muevete.tarifas_municipio%ROWTYPE;
  v_modo           text;
  v_monto_fijo     numeric := 0;
  v_precio_km      numeric := 0;
  v_dentro         boolean := false;
  v_km_lineal      numeric;
  v_km             numeric;
  v_km_fuente      text;
  v_km_recogida    numeric := 0;
  v_km_cobrables   numeric := 0;
  v_base           numeric := 0;
  v_precio         numeric := 0;
  v_minimo         numeric;
  v_corto          boolean := false;
  v_nocturno       boolean := false;
  v_hora           time;
  v_rec_noct       numeric := 0;
  v_rec_prima      numeric := 0;
  v_pre_redondeo   numeric;
  v_comision       numeric;
  v_chofer         numeric;
  v_detalle        jsonb;
  v_hub_lat        numeric;
  v_hub_lon        numeric;
  v_hub_muni       text;
  v_dist_hub       numeric := 0;
  v_fuera_muni     boolean := false;
BEGIN
  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'configuracion_tarifas_no_inicializada' USING ERRCODE = 'P0001';
  END IF;

  v_hub_lat  := coalesce(cfg.hub_lat, 22.406959);
  v_hub_lon  := coalesce(cfg.hub_lon, -79.965681);
  v_hub_muni := coalesce(cfg.hub_municipio, 'Santa Clara');

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

  -- ── Distancia del viaje (con el mismo cinturón anti-manipulación) ────
  v_km_lineal := muevete.fn_haversine_km(p_lat_o, p_lon_o, p_lat_d, p_lon_d);

  IF p_km IS NULL OR p_km <= 0 THEN
    v_km := round(v_km_lineal::numeric, 3);
    v_km_fuente := 'haversine';
  ELSE
    -- Nunca menos que la recta; nunca más que 2× recta + 1 km (snap a vías).
    v_km := least(greatest(p_km, v_km_lineal), v_km_lineal * 2.0 + 1.0);
    v_km := round(v_km::numeric, 3);
    v_km_fuente := 'ruta';
  END IF;

  -- ── Regla: zona del origen o fallback municipal ──────────────────────
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
      v_modo       := 'fijo_mas_km';
      v_monto_fijo := coalesce(cfg.monto_fijo_fallback_municipio, 1500);
      v_precio_km  := coalesce(cfg.precio_km_fallback, 120);
    END IF;
  END IF;

  -- ── Km de recogida (solo intermunicipal) ─────────────────────────────
  -- Si el pasajero está en otro municipio que el hub, el carro sale desde el
  -- hub a buscarlo: esos kilómetros también se cobran.
  -- El corte de 8 km evita que un error de geocodificación (municipio vacío o
  -- mal escrito) cobre kilómetros de recogida dentro de la propia ciudad.
  v_dist_hub := round(
    muevete.fn_haversine_km(v_hub_lat::float8, v_hub_lon::float8, p_lat_o, p_lon_o)::numeric,
    3
  );

  v_fuera_muni := v_zona_o.id IS NULL
                  AND v_dist_hub > 8
                  AND (
                    p_municipio IS NULL
                    OR lower(btrim(p_municipio)) <> lower(v_hub_muni)
                  );

  IF v_fuera_muni THEN
    v_km_recogida := v_dist_hub;
  END IF;

  -- ── Base según la regla ──────────────────────────────────────────────
  IF v_zona_o.id IS NOT NULL THEN
    -- Origen dentro de una zona activa (casco o zona interna).
    v_km_cobrables := CASE WHEN v_dentro THEN 0 ELSE v_km END;
    v_base := v_monto_fijo + v_km_cobrables * v_precio_km;
  ELSE
    -- Origen fuera de toda zona.
    IF v_modo = 'fijo' AND v_muni.id IS NOT NULL
       AND p_municipio IS NOT NULL
       AND lower(btrim(p_municipio)) = lower(v_muni.municipio) THEN
      -- Viaje dentro del municipio con tarifa plana declarada: se respeta.
      v_km_cobrables := 0;
      v_base := v_monto_fijo;
    ELSE
      -- Base + km del viaje + km de recogida intermunicipal.
      v_km_cobrables := v_km + v_km_recogida;
      IF v_modo = 'por_km' THEN
        v_base := v_km_cobrables * v_precio_km;
      ELSE
        -- 'fijo_mas_km' (y cualquier 'fijo' que salga del municipio)
        v_base := v_monto_fijo + v_km_cobrables * v_precio_km;
      END IF;
    END IF;
  END IF;

  -- ── Multiplicador por tipo ───────────────────────────────────────────
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

  -- ── Válvula de viaje corto (sólo si está configurada > 0) ────────────
  IF lower(v_tipo) = 'auto'
     AND coalesce(cfg.precio_corto_auto, 0) > 0
     AND v_km < coalesce(cfg.umbral_km_corto, 1.5) THEN
    IF v_precio > cfg.precio_corto_auto THEN
      v_precio := cfg.precio_corto_auto;
      v_corto  := true;
    END IF;
  END IF;

  -- ── Recargos ─────────────────────────────────────────────────────────
  v_hora := (p_at AT TIME ZONE 'America/Havana')::time;

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

  -- ── Snapshot del desglose ────────────────────────────────────────────
  v_detalle := jsonb_build_object(
    'zona_origen_id',         v_zona_o.id,
    'zona_origen_nombre',     v_zona_o.nombre,
    'zona_destino_id',        v_zona_d.id,
    'zona_destino_nombre',    v_zona_d.nombre,
    'dentro_de_zona',         v_dentro,
    'fallback_municipio',     v_zona_o.id IS NULL,
    'municipio_aplicado',     CASE WHEN v_zona_o.id IS NULL THEN v_muni.municipio END,
    'modo',                   v_modo,
    'monto_fijo',             v_monto_fijo,
    'precio_km',              v_precio_km,
    'km_lineal',              round(v_km_lineal::numeric, 3),
    'km_total',               v_km,
    'km_recogida',            v_km_recogida,
    'km_cobrables',           v_km_cobrables,
    'hub_lat',                v_hub_lat,
    'hub_lon',                v_hub_lon,
    'hub_municipio',          v_hub_muni,
    'origen_fuera_municipio', v_fuera_muni,
    'km_fuente',              v_km_fuente,
    'base',                   round(v_base, 2),
    'multiplicador_tipo',     v_mult,
    'tipo_vehiculo',          v_tipo,
    'precio_minimo',          v_minimo,
    'precio_corto_aplicado',  v_corto,
    'es_nocturno',            v_nocturno,
    'recargo_nocturno',       v_rec_noct,
    'recargo_prima_distancia', v_rec_prima,
    'precio_antes_redondeo',  round(v_pre_redondeo, 2),
    'redondeo_cup',           cfg.redondeo_cup,
    'precio_plataforma',      v_precio
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
    'km_recogida',        v_km_recogida,
    'km_cobrables',       v_km_cobrables,
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
$function$;

COMMENT ON FUNCTION muevete.fn_cotizar_viaje(double precision, double precision, double precision, double precision, bigint, timestamp with time zone, double precision, text, text) IS
  'Cotiza un viaje. Regla vigente: 1.500 CUP de base en el casco de Santa Clara (zona SC-BASE, 4,3 km alrededor del Parque Vidal) + 120 CUP por km fuera del casco. Si el origen está fuera del municipio del hub, suma el km de recogida hub→origen. Multiplicador por tipo, piso por tipo, recargo nocturno, redondeo a 50 CUP y comisión 15 %.';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano después de aplicar)
-- ============================================================================
-- 1) Configuración
--   SELECT hub_lat, hub_lon, hub_municipio, precio_km_fallback,
--          monto_fijo_fallback_municipio, precio_corto_auto, prima_distancia_cup,
--          taxi_precio_fijo_activo
--     FROM muevete.configuracion_tarifas WHERE id = 1;
--   -- esperado: 22.406959 | -79.965681 | Santa Clara | 120 | 1500 | 0 | 0 | true
--
-- 2) Zonas activas (debe quedar SOLO SC-BASE)
--   SELECT codigo, nombre, modo, monto_fijo, precio_km, prioridad, activo
--     FROM muevete.zonas_tarifa ORDER BY prioridad DESC, codigo;
--
-- 3) El casco cubre los tres puntos pedidos (todos deben dar true)
--   SELECT muevete.fn_punto_en_poligono(22.406959, -79.965681,
--            (SELECT geometria FROM muevete.zonas_tarifa WHERE codigo='SC-BASE')) AS parque_vidal,
--          muevete.fn_punto_en_poligono(22.421000, -79.960000,
--            (SELECT geometria FROM muevete.zonas_tarifa WHERE codigo='SC-BASE')) AS jose_marti,
--          muevete.fn_punto_en_poligono(22.417000, -79.973000,
--            (SELECT geometria FROM muevete.zonas_tarifa WHERE codigo='SC-BASE')) AS arco_iris;
--
-- 4) Cotizaciones esperadas (auto = id 2, hora de día)
--   -- 4.1 Dentro del casco, 2 km → 1.500
--   SELECT muevete.fn_cotizar_viaje(22.406959,-79.965681, 22.412000,-79.960000,
--            2, '2026-11-12T10:00:00-05:00'::timestamptz, 2.0, 'Villa Clara','Santa Clara')
--          ->>'precio_plataforma';
--
--   -- 4.2 Santa Clara → Placetas (40 km) → 6.300
--   SELECT muevete.fn_cotizar_viaje(22.406959,-79.965681, 22.316600,-79.650000,
--            2, '2026-11-12T10:00:00-05:00'::timestamptz, 40.0, 'Villa Clara','Santa Clara')
--          ->>'precio_plataforma';
--
--   -- 4.3 Placetas → Santa Clara (≈34 + 40 km) → ≈10.400
--   SELECT muevete.fn_cotizar_viaje(22.316600,-79.650000, 22.406959,-79.965681,
--            2, '2026-11-12T10:00:00-05:00'::timestamptz, 40.0, 'Villa Clara','Placetas')
--          ->>'precio_plataforma';
--
--   -- 4.4 Moto dentro del casco → piso 900
--   SELECT muevete.fn_cotizar_viaje(22.406959,-79.965681, 22.412000,-79.960000,
--            (SELECT id FROM muevete.vehicle_type WHERE lower(tipo)='moto'),
--            '2026-11-12T10:00:00-05:00'::timestamptz, 2.0, 'Villa Clara','Santa Clara')
--          ->>'precio_plataforma';
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO se ejecuta en el despliegue normal)
-- ----------------------------------------------------------------------------
-- Para volver a la semilla 033 habría que:
--   BEGIN;
--   UPDATE muevete.configuracion_tarifas
--      SET precio_km_fallback = 400, precio_corto_auto = 1000,
--          prima_distancia_cup = 500, taxi_precio_fijo_activo = false
--    WHERE id = 1;
--   UPDATE muevete.tarifas_municipio SET modo='fijo', monto_fijo=1500, precio_km=400
--    WHERE provincia='Villa Clara' AND municipio='Santa Clara';
--   DELETE FROM muevete.zonas_tarifa WHERE codigo='SC-BASE';
--   UPDATE muevete.zonas_tarifa SET activo=true,
--          nombre='Municipio Santa Clara' WHERE codigo='MUN';
--   -- y reinstalar la función desde 032_taxi_geo_y_cotizacion.sql
--   COMMIT;
--
-- Alternativa quirúrgica y sin downtime: dejar el cobro nuevo apagado con
--   UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo=false WHERE id=1;
-- (la app hoy no lee ese flag: es una marca operativa, no un interruptor de código).
-- ============================================================================