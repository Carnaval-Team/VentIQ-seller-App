-- ============================================================================
-- 054_tarifa_sc_base_config_y_matching.sql
-- RECONCILIACIÓN de la 053 (ya aplicada en producción) y CIERRE de la
-- regresión de emparejamiento que introdujo.
--
-- QUÉ PASÓ ANTES (estado real hoy en vsieeihstajlrdvpuooh)
--   · `zonas_tarifa.SC-BASE` ACTIVA (círculo 4,3 km / 49 puntos, Parque Vidal,
--     modo 'fijo', 1500, 120, prioridad 5).
--   · `zonas_tarifa.MUN` INACTIVA, todavía con modo 'fijo', 1500, precio_km 400.
--   · `configuracion_tarifas`: precio_km_fallback 120, monto_fijo_fallback 1500,
--     precio_corto_auto 0, prima_distancia_cup 0, hub_lat/hub_lon/hub_municipio.
--   · `fn_cotizar_viaje` reescrita: 1500 en el casco, 1500 + 120×(recogida +
--     viaje) fuera, Placetas→SC (40 km) = 10.400 CUP. Números ya publicados en
--     la landing: NO se tocan.
--
-- EL PROBLEMA (confirmado leyendo el código vivo)
--   `muevete.fn_viajes_disponibles` empareja chofer y solicitud por IGUALDAD de
--   `zona_id`:
--       (v_zona_chofer IS NOT NULL AND s.zona_id = v_zona_chofer)
--       OR (v_zona_chofer IS NULL AND s.zona_id IS NULL)
--   Con SC-BASE activa y MUN apagada, un chofer aparcado fuera del círculo
--   (aeropuerto, UCLV, circunvalación, carretera central) obtiene
--   `v_zona_chofer = NULL` y deja de ver las solicitudes nacidas en el casco.
--   Y un chofer dentro del casco no ve las solicitudes de la periferia. Es una
--   pérdida silenciosa de viajes: el síntoma es "no me salen carreras".
--
-- LA CORRECCIÓN (sin tocar fn_viajes_disponibles)
--   1. El área base deja de ser una ZONA y pasa a ser una GEOMETRÍA de tarifa:
--      `configuracion_tarifas.base_geometria` (+ base_sc_cup, precio_km_sc,
--      base_radio_km, base_nombre). Cobrar y emparejar quedan desacoplados.
--   2. Se REACTIVA `MUN` como ÚNICA zona activa del municipio (mismo polígono
--      de 22×28 km) y se deja en `modo='por_km'`, `monto_fijo=0`,
--      `precio_km=120`: sirve para emparejar y ya no puede cobrar 1.500 planos
--      por un viaje de 22 km por ningún camino legacy.
--   3. Se DESACTIVA `SC-BASE` (se conserva la fila y su polígono como
--      procedencia de `base_geometria`; no se borra para no romper
--      `solicitudes_transporte.zona_id` históricas).
--   4. `fn_cotizar_viaje` se reescribe para leer el precio de
--      `configuracion_tarifas` y del área base, con la MISMA firma de 9
--      argumentos y las MISMAS claves de salida que la 053 (más alias aditivos).
--   5. Las solicitudes PENDIENTES que quedaron con `zona_id = SC-BASE` se
--      reasignan a MUN para que no queden invisibles hasta que expiren.
--
-- REGLA DE PRECIO (idéntica a la 053 aplicada; números publicados intactos)
--   · Origen Y destino dentro del área base ............ 1.500 planos.
--   · Cualquier extremo fuera del área base ............ 1.500 + 120 × (recogida + viaje).
--   · `tramo_recogida` = km del hub (Parque Vidal) al origen, y SÓLO se cobra
--     cuando el origen está FUERA del perímetro municipal (MUN) y a más de
--     `recogida_min_km` (8 km) del hub. Así no se cobra recogida a un pasajero
--     del propio municipio que está a 10 km del parque (eso sería doble cobro),
--     pero sí a Placetas (34 km, fuera del municipio).
--   · `tramo_viaje` = origen→destino (km de ruta `p_km` si la app los manda,
--     acotados por la distancia lineal como en 032/053).
--
-- COMPATIBILIDAD
--   · `solicitudes_transporte.tarifa_modo` sólo admite 'fijo'|'fijo_mas_km'|
--     'por_km'; se siguen usando 'fijo' (dentro del área base) y
--     'fijo_mas_km' (fuera). Ningún CHECK nuevo.
--   · `fn_crear_solicitud` lee km_total, tipo_vehiculo, precio_plataforma,
--     comision_pct, precio_chofer, tarifa_modo y zona_id: todos siguen ahí.
--   · Se conservan las claves de la 053 (`km_recogida`, `km_cobrables`, `hub_*`,
--     `origen_fuera_municipio`) y se añaden alias (`tramo_recogida_km`,
--     `tramo_viaje_km`, `km_cobrados`, `base_nombre`, `en_base_origen`,
--     `en_base_destino`) para la app Flutter.
--
-- IDEMPOTENTE: ADD COLUMN IF NOT EXISTS, UPDATEs con valores fijos,
-- CREATE OR REPLACE FUNCTION (misma firma), REVOKE/GRANT.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Columnas del área base (aditivas; hub_lat/hub_lon/hub_municipio ya existen
--    desde la 053, se re-declaran por si esta migración se corre en otro
--    entorno donde la 053 no esté).
-- ============================================================================

ALTER TABLE muevete.configuracion_tarifas
  ADD COLUMN IF NOT EXISTS base_nombre text NOT NULL DEFAULT 'Base Santa Clara (Parque Vidal)',
  ADD COLUMN IF NOT EXISTS base_sc_cup numeric NOT NULL DEFAULT 1500
    CHECK (base_sc_cup >= 0),
  ADD COLUMN IF NOT EXISTS precio_km_sc numeric NOT NULL DEFAULT 120
    CHECK (precio_km_sc >= 0),
  ADD COLUMN IF NOT EXISTS base_radio_km numeric NOT NULL DEFAULT 4.3
    CHECK (base_radio_km > 0 AND base_radio_km <= 25),
  ADD COLUMN IF NOT EXISTS base_geometria jsonb,
  ADD COLUMN IF NOT EXISTS km_incluidos_base numeric NOT NULL DEFAULT 0
    CHECK (km_incluidos_base >= 0),
  ADD COLUMN IF NOT EXISTS tope_tramo_recogida_km numeric NOT NULL DEFAULT 0
    CHECK (tope_tramo_recogida_km >= 0),
  ADD COLUMN IF NOT EXISTS recogida_min_km numeric NOT NULL DEFAULT 8
    CHECK (recogida_min_km >= 0),
  ADD COLUMN IF NOT EXISTS hub_lat double precision,
  ADD COLUMN IF NOT EXISTS hub_lon double precision,
  ADD COLUMN IF NOT EXISTS hub_municipio text;

COMMENT ON COLUMN muevete.configuracion_tarifas.base_geometria IS
  'Polígono GeoJSON del área base de Santa Clara (círculo 4,3 km desde el Parque Vidal). Sustituye a la zona SC-BASE: el precio se decide aquí, el emparejamiento sigue en zonas_tarifa.';
COMMENT ON COLUMN muevete.configuracion_tarifas.base_sc_cup IS
  'Tarifa base (CUP) dentro del área base; también es el término fijo fuera de ella.';
COMMENT ON COLUMN muevete.configuracion_tarifas.precio_km_sc IS
  'CUP por km fuera del área base (120).';
COMMENT ON COLUMN muevete.configuracion_tarifas.km_incluidos_base IS
  'Km del tramo de viaje que la base ya cubre (0 = se cobran todos los km cuando el viaje sale del área base).';
COMMENT ON COLUMN muevete.configuracion_tarifas.tope_tramo_recogida_km IS
  'Tope del tramo de recogida en km (0 = sin tope). Evita cotizaciones absurdas desde otra provincia (p. ej. La Habana).';
COMMENT ON COLUMN muevete.configuracion_tarifas.recogida_min_km IS
  'Radio (km desde el hub) por debajo del cual NO se cobra tramo de recogida aunque el origen caiga fuera del perímetro municipal.';
COMMENT ON COLUMN muevete.configuracion_tarifas.hub_municipio IS
  'Municipio del hub de flota. Sólo se usa como respaldo si falta el polígono MUN.';

-- ============================================================================
-- 2. Valores de precio (los que ya publica la landing: no cambian)
-- ============================================================================

UPDATE muevete.configuracion_tarifas
   SET base_sc_cup                   = 1500,
       precio_km_sc                  = 120,
       precio_km_fallback            = 120,
       monto_fijo_fallback_municipio = 1500,
       -- La válvula de viaje corto dejaba un viaje de 1 km por debajo de la base.
       precio_corto_auto             = 0,
       -- Desactivada por el dueño en la 053: la prima de 500 CUP encarecía
       -- justo los viajes largos que ya paga por km. Reactivar = UPDATE.
       prima_distancia_cup           = 0,
       hub_lat                       = 22.406959,
       hub_lon                       = -79.965681,
       hub_municipio                 = 'Santa Clara',
       base_nombre                   = 'Base Santa Clara (Parque Vidal)',
       base_radio_km                 = 4.3,
       km_incluidos_base             = 0,
       tope_tramo_recogida_km        = 0,
       recogida_min_km               = 8,
       updated_at                    = now()
 WHERE id = 1;

-- Espejo en tarifas_municipio (panel/admin). El motor lee de config, pero esta
-- fila no puede quedar mintiendo.
INSERT INTO muevete.tarifas_municipio (provincia, municipio, modo, monto_fijo, precio_km, activo)
VALUES ('Villa Clara', 'Santa Clara', 'fijo_mas_km', 1500, 120, true)
ON CONFLICT (provincia, municipio) DO UPDATE
   SET modo = 'fijo_mas_km', monto_fijo = 1500, precio_km = 120,
       activo = true, updated_at = now();

-- ============================================================================
-- 3. ÁREA BASE: heredar el polígono de SC-BASE (4,3 km) o generarlo
-- ============================================================================

DO $base$
DECLARE
  v_geom   jsonb;
  v_lados  integer;
  c_hub_lat  constant double precision := 22.406959;
  c_hub_lon  constant double precision := -79.965681;
  c_radio_km constant double precision := 4.3;
  v_dlat double precision;
  v_dlon double precision;
BEGIN
  -- Procedencia preferente: el polígono que ya se validó en producción.
  SELECT z.geometria INTO v_geom
    FROM muevete.zonas_tarifa z
   WHERE z.codigo = 'SC-BASE';

  IF v_geom IS NULL
     OR coalesce(jsonb_typeof(v_geom -> 'coordinates'), 'null') <> 'array' THEN
    -- Respaldo: círculo de 4,3 km / 48 lados centrado en el Parque Vidal.
    v_dlat := c_radio_km / 110.574;
    v_dlon := c_radio_km / (111.320 * cos(radians(c_hub_lat)));

    SELECT jsonb_agg(
             jsonb_build_array(
               round((c_hub_lon + v_dlon * cos(2 * pi() * i / 48))::numeric, 6),
               round((c_hub_lat + v_dlat * sin(2 * pi() * i / 48))::numeric, 6)
             ) ORDER BY i)
      INTO v_geom
      FROM generate_series(0, 47) AS s(i);

    v_geom := jsonb_build_object('type', 'Polygon',
                                 'coordinates', jsonb_build_array(v_geom));
  END IF;

  v_lados := jsonb_array_length(v_geom -> 'coordinates' -> 0);
  IF v_lados < 3 THEN
    RAISE EXCEPTION 'base_geometria_invalida: % puntos', v_lados;
  END IF;

  UPDATE muevete.configuracion_tarifas
     SET base_geometria = v_geom,
         hub_lat        = coalesce(hub_lat, c_hub_lat),
         hub_lon        = coalesce(hub_lon, c_hub_lon),
         hub_municipio  = coalesce(hub_municipio, 'Santa Clara'),
         updated_at     = now()
   WHERE id = 1;

  -- Asserts: si el polígono no cubre lo que debe, la migración no pasa.
  IF NOT muevete.fn_punto_en_poligono(c_hub_lat, c_hub_lon, v_geom) THEN
    RAISE EXCEPTION 'base_invalida: el Parque Vidal quedó fuera';
  END IF;
  IF NOT muevete.fn_punto_en_poligono(22.3891801, -79.9522131, v_geom) THEN
    RAISE EXCEPTION 'base_invalida: la Universidad de Ciencias Médicas quedó fuera';
  END IF;
  IF NOT muevete.fn_punto_en_poligono(22.3961896, -79.9282471, v_geom) THEN
    RAISE EXCEPTION 'base_invalida: el reparto Arco Iris quedó fuera';
  END IF;
  IF muevete.fn_punto_en_poligono(22.4383115, -79.8944822, v_geom) THEN
    RAISE EXCEPTION 'base_invalida: la UCLV (8,1 km) NO debe estar dentro';
  END IF;
  IF muevete.fn_punto_en_poligono(22.3166, -79.6500, v_geom) THEN
    RAISE EXCEPTION 'base_invalida: Placetas NO debe estar dentro';
  END IF;
END
$base$;

-- ============================================================================
-- 4. MATCHING: MUN vuelve a ser la única zona activa del municipio
--    (mismo polígono; ya no cobra el plano de 1.500)
-- ============================================================================

UPDATE muevete.zonas_tarifa
   SET activo     = true,
       modo       = 'por_km',
       monto_fijo = 0,
       precio_km  = 120,
       prioridad  = 0,
       nombre     = 'Municipio Santa Clara',
       updated_at = now()
 WHERE codigo = 'MUN';

UPDATE muevete.zonas_tarifa
   SET activo     = false,
       prioridad  = 0,
       nombre     = 'Casco Santa Clara (histórico 053 · el área base vive en configuracion_tarifas)',
       updated_at = now()
 WHERE codigo = 'SC-BASE';

-- Solicitudes pendientes que quedaron apuntando a la zona apagada: sin esto
-- ningún chofer las vería (el filtro es por igualdad de zona_id).
UPDATE muevete.solicitudes_transporte s
   SET zona_id = (SELECT z.id FROM muevete.zonas_tarifa z WHERE z.codigo = 'MUN')
 WHERE s.estado = 'pendiente'
   AND s.zona_id = (SELECT z.id FROM muevete.zonas_tarifa z WHERE z.codigo = 'SC-BASE');

-- ============================================================================
-- 5. MOTOR DE COTIZACIÓN
-- ============================================================================

CREATE OR REPLACE FUNCTION muevete.fn_cotizar_viaje(
  p_lat_o     double precision,
  p_lon_o     double precision,
  p_lat_d     double precision,
  p_lon_d     double precision,
  p_id_tipo   bigint,
  p_at        timestamp with time zone DEFAULT now(),
  p_km        double precision DEFAULT NULL::double precision,
  p_provincia text DEFAULT NULL::text,
  p_municipio text DEFAULT NULL::text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'muevete', 'pg_temp'
AS $function$
DECLARE
  cfg            muevete.configuracion_tarifas%ROWTYPE;
  v_tipo         text;
  v_mult         numeric;
  v_zona_o       muevete.zonas_tarifa%ROWTYPE;
  v_zona_d       muevete.zonas_tarifa%ROWTYPE;
  v_muni_pol     jsonb;
  v_modo         text;
  v_base_cup     numeric;
  v_precio_km    numeric;
  v_base_nombre  text;
  v_en_base_o    boolean := false;
  v_en_base_d    boolean := false;
  v_dentro       boolean := false;
  v_en_muni      boolean := true;
  v_hub_lat      double precision;
  v_hub_lon      double precision;
  v_hub_muni     text;
  v_dist_hub     numeric := 0;
  v_rec_km       numeric := 0;
  v_via_km       numeric := 0;
  v_rec_cup      numeric := 0;
  v_via_cup      numeric := 0;
  v_km_cobrados  numeric := 0;
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

  -- Zonas: ya sólo sirven para emparejar y para el nombre mostrado.
  SELECT * INTO v_zona_o FROM muevete.fn_zona_de_punto(p_lat_o, p_lon_o, p_at) LIMIT 1;
  SELECT * INTO v_zona_d FROM muevete.fn_zona_de_punto(p_lat_d, p_lon_d, p_at) LIMIT 1;

  v_km_lineal := muevete.fn_haversine_km(p_lat_o, p_lon_o, p_lat_d, p_lon_d);

  IF p_km IS NULL OR p_km <= 0 THEN
    v_km := round(v_km_lineal::numeric, 3);
    v_km_fuente := 'haversine';
  ELSE
    v_km := least(greatest(p_km, v_km_lineal), v_km_lineal * 2.0 + 1.0);
    v_km := round(v_km::numeric, 3);
    v_km_fuente := 'ruta';
  END IF;

  -- ------------------------------------------------------------------------
  -- Área base (precio) — independiente de las zonas de emparejamiento
  -- ------------------------------------------------------------------------
  v_base_nombre := coalesce(nullif(btrim(cfg.base_nombre), ''), 'Base Santa Clara (Parque Vidal)');
  v_base_cup    := coalesce(cfg.base_sc_cup, cfg.monto_fijo_fallback_municipio, 1500);
  v_precio_km   := coalesce(cfg.precio_km_sc, cfg.precio_km_fallback, 120);

  IF cfg.base_geometria IS NOT NULL
     AND jsonb_typeof(cfg.base_geometria -> 'coordinates') = 'array' THEN
    v_en_base_o := muevete.fn_punto_en_poligono(p_lat_o, p_lon_o, cfg.base_geometria);
    v_en_base_d := muevete.fn_punto_en_poligono(p_lat_d, p_lon_d, cfg.base_geometria);
  ELSIF coalesce(cfg.base_radio_km, 0) > 0 THEN
    v_en_base_o := muevete.fn_haversine_km(v_hub_lat, v_hub_lon, p_lat_o, p_lon_o)
                     <= cfg.base_radio_km;
    v_en_base_d := muevete.fn_haversine_km(v_hub_lat, v_hub_lon, p_lat_d, p_lon_d)
                     <= cfg.base_radio_km;
  END IF;

  v_dentro := v_en_base_o AND v_en_base_d;

  -- ¿El origen está dentro del perímetro municipal? (polígono MUN)
  SELECT z.geometria INTO v_muni_pol
    FROM muevete.zonas_tarifa z
   WHERE z.codigo = 'MUN';

  IF v_muni_pol IS NOT NULL AND jsonb_typeof(v_muni_pol -> 'coordinates') = 'array' THEN
    v_en_muni := muevete.fn_punto_en_poligono(p_lat_o, p_lon_o, v_muni_pol);
  ELSE
    -- Respaldo si no hay polígono MUN: se confía en el municipio que manda la app.
    v_en_muni := (p_municipio IS NULL OR lower(btrim(p_municipio)) = lower(v_hub_muni));
  END IF;

  -- ------------------------------------------------------------------------
  -- Tramos y precio
  -- ------------------------------------------------------------------------
  IF v_dentro THEN
    v_modo   := 'fijo';
    v_base   := v_base_cup;
    v_rec_km := 0;
    v_via_km := 0;
  ELSE
    v_modo := 'fijo_mas_km';

    -- Recogida: sólo si el origen está fuera del municipio del hub.
    IF NOT v_en_muni THEN
      v_dist_hub := round(
        muevete.fn_haversine_km(v_hub_lat, v_hub_lon, p_lat_o, p_lon_o)::numeric, 3);

      IF v_dist_hub > coalesce(cfg.recogida_min_km, 8) THEN
        v_rec_km := v_dist_hub;
        IF coalesce(cfg.tope_tramo_recogida_km, 0) > 0 THEN
          v_rec_km := least(v_rec_km, cfg.tope_tramo_recogida_km);
        END IF;
      ELSE
        v_dist_hub := 0;  -- no se cobra: queda sólo como dato
      END IF;
    END IF;

    v_via_km := greatest(0::numeric, v_km - coalesce(cfg.km_incluidos_base, 0));

    v_rec_cup := round(v_rec_km * v_precio_km, 2);
    v_via_cup := round(v_via_km * v_precio_km, 2);

    v_base := v_base_cup + v_rec_cup + v_via_cup;
  END IF;

  v_km_cobrados := v_rec_km + v_via_km;

  v_precio := round(v_base * coalesce(v_mult, 1), 2);

  v_minimo := CASE lower(v_tipo)
                WHEN 'auto'     THEN cfg.precio_minimo_auto
                WHEN 'moto'     THEN cfg.precio_minimo_moto
                WHEN 'microbus' THEN cfg.precio_minimo_microbus
                ELSE NULL
              END;
  IF v_minimo IS NOT NULL AND v_minimo > 0 THEN
    v_precio := greatest(v_precio, v_minimo);
  END IF;

  -- Válvula de viaje corto: el código sigue, la config la apaga (precio 0).
  IF lower(v_tipo) = 'auto'
     AND coalesce(cfg.precio_corto_auto, 0) > 0
     AND v_km < coalesce(cfg.umbral_km_corto, 1.5) THEN
    IF v_precio > cfg.precio_corto_auto THEN
      v_precio := cfg.precio_corto_auto;
      v_corto  := true;
    END IF;
  END IF;

  v_hora := (p_at AT TIME ZONE 'America/Havana')::time;

  IF cfg.ventana_nocturna_inicio <= cfg.ventana_nocturna_fin THEN
    v_nocturno := v_hora >= cfg.ventana_nocturna_inicio
                  AND v_hora < cfg.ventana_nocturna_fin;
  ELSE
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

  IF coalesce(cfg.redondeo_cup, 0) > 0 THEN
    v_precio := ceil(v_precio / cfg.redondeo_cup) * cfg.redondeo_cup;
  ELSE
    v_precio := round(v_precio, 2);
  END IF;

  v_comision := round(v_precio * cfg.comision_pct / 100.0, 2);
  IF coalesce(cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, cfg.tope_comision_viaje);
  END IF;
  v_chofer := v_precio - v_comision;

  v_detalle := jsonb_build_object(
    -- claves heredadas (032 y 053)
    'zona_origen_id',          v_zona_o.id,
    'zona_origen_nombre',      v_zona_o.nombre,
    'zona_destino_id',         v_zona_d.id,
    'zona_destino_nombre',     v_zona_d.nombre,
    'dentro_de_zona',          v_dentro,
    'fallback_municipio',      v_zona_o.id IS NULL,
    'municipio_aplicado',      p_municipio,
    'modo',                    v_modo,
    'monto_fijo',              v_base_cup,
    'precio_km',               v_precio_km,
    'km_lineal',               round(v_km_lineal::numeric, 3),
    'km_total',                v_km,
    'km_fuente',               v_km_fuente,
    'base',                    round(v_base, 2),
    'multiplicador_tipo',      v_mult,
    'tipo_vehiculo',           v_tipo,
    'precio_minimo',           v_minimo,
    'precio_corto_aplicado',   v_corto,
    'es_nocturno',             v_nocturno,
    'recargo_nocturno',        v_rec_noct,
    'recargo_prima_distancia', v_rec_prima,
    'precio_antes_redondeo',   round(v_pre_redondeo, 2),
    'redondeo_cup',            cfg.redondeo_cup,
    'precio_plataforma',       v_precio,
    -- claves de la 053 (compatibilidad con la landing)
    'km_recogida',             v_rec_km,
    'km_cobrables',            v_km_cobrados,
    'hub_lat',                 v_hub_lat,
    'hub_lon',                 v_hub_lon,
    'hub_municipio',           v_hub_muni,
    'origen_fuera_municipio',  NOT v_en_muni,
    -- alias aditivos (054) para la app
    'base_nombre',             v_base_nombre,
    'base_radio_km',           cfg.base_radio_km,
    'base_sc_cup',             v_base_cup,
    'precio_km_sc',            v_precio_km,
    'km_incluidos_base',       coalesce(cfg.km_incluidos_base, 0),
    'recogida_min_km',         coalesce(cfg.recogida_min_km, 8),
    'en_base_origen',          v_en_base_o,
    'en_base_destino',         v_en_base_d,
    'en_municipio_hub',        v_en_muni,
    'tramo_recogida_km',       v_rec_km,
    'tramo_viaje_km',          v_via_km,
    'tramo_recogida_cup',      v_rec_cup,
    'tramo_viaje_cup',         v_via_cup,
    'km_cobrados',             v_km_cobrados
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
    'km_recogida',        v_rec_km,
    'km_cobrables',       v_km_cobrados,
    'km_fuente',          v_km_fuente,
    'tipo_vehiculo',      v_tipo,
    'multiplicador_tipo', v_mult,
    'es_nocturno',        v_nocturno,
    'precio_corto',       v_corto,
    'detalle',            v_detalle,
    'precio_vigente_desde', cfg.precio_vigente_desde,
    'calculado_at',       p_at,
    -- alias aditivos (054)
    'base_nombre',        v_base_nombre,
    'en_base_origen',     v_en_base_o,
    'en_base_destino',    v_en_base_d,
    'tramo_recogida_km',  v_rec_km,
    'tramo_viaje_km',     v_via_km,
    'km_cobrados',        v_km_cobrados
  );
END;
$function$;

COMMENT ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) IS
  'RPC #3. Motor único de cotización. 054: 1.500 CUP dentro del área base de SC (base_geometria, 4,3 km desde el Parque Vidal) y 1.500 + 120 × (recogida + viaje) fuera; la recogida sólo se cobra si el origen está fuera del municipio del hub. No escribe nada.';

REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) TO authenticated;

COMMIT;

-- ============================================================================
-- 6. VERIFICACIÓN (a mano; sólo lectura, no aborta nada)
--    `p_id_tipo = 5` = 'auto' en producción.
--    Hora 12:00 para que no aplique el recargo nocturno.
-- ============================================================================
--
-- 6.1 Estado que debe quedar:
--   SELECT codigo, activo, modo, monto_fijo, precio_km, prioridad, nombre
--     FROM muevete.zonas_tarifa ORDER BY id;
--   -- esperado: MUN activa | por_km | 0 | 120 | 0 | 'Municipio Santa Clara'
--   --           SC-BASE inactiva; FB y Z1..Z9 inactivas
--
--   SELECT base_sc_cup, precio_km_sc, base_radio_km, hub_lat, hub_lon,
--          hub_municipio, precio_corto_auto, prima_distancia_cup,
--          recogida_min_km, km_incluidos_base, tope_tramo_recogida_km,
--          jsonb_array_length(base_geometria->'coordinates'->0) AS lados
--     FROM muevete.configuracion_tarifas WHERE id = 1;
--   -- esperado: 1500 | 120 | 4.3 | 22.406959 | -79.965681 | Santa Clara |
--   --           0 | 0 | 8 | 0 | 0 | 49 (o 48 si se generó)
--
-- 6.2 Cotizaciones esperadas (base 1500, 120/km, sin prima, sin corto):
--   WITH casos(caso, lat_o, lon_o, lat_d, lon_d, km, tipo, muni) AS (VALUES
--     ('A casco 2 km',            22.406959::float8, -79.965681::float8, 22.424930::float8, -79.965681::float8, NULL::float8, 5::bigint, 'Santa Clara'),
--     ('B casco -> 10 km',        22.406959, -79.965681, 22.496800, -79.965700, NULL, 5, 'Santa Clara'),
--     ('C Placetas -> casco',     22.3166,   -79.6500,   22.406959, -79.965681, NULL, 5, 'Placetas'),
--     ('D Placetas -> casco 40',  22.3166,   -79.6500,   22.406959, -79.965681, 40::float8, 5, 'Placetas'),
--     ('E casco -> Placetas 40',  22.406959, -79.965681, 22.3166,   -79.6500,   40::float8, 5, 'Santa Clara'),
--     ('F La Habana -> casco',    23.1136,   -82.3666,   22.406959, -79.965681, NULL, 5, 'La Habana'),
--     ('G moto en casco',         22.406959, -79.965681, 22.424930, -79.965681, NULL, 3, 'Santa Clara'),
--     ('H microbús en casco',     22.406959, -79.965681, 22.424930, -79.965681, NULL, 6, 'Santa Clara')
--   )
--   SELECT c.caso,
--          (x.j->>'precio_plataforma')::numeric  AS precio,
--          x.j->>'tarifa_modo'                    AS modo,
--          (x.j->>'tramo_recogida_km')::numeric   AS rec_km,
--          (x.j->>'tramo_viaje_km')::numeric      AS via_km,
--          (x.j->>'comision_monto')::numeric      AS comision,
--          (x.j->>'precio_chofer')::numeric       AS chofer
--     FROM casos c
--     CROSS JOIN LATERAL (
--       SELECT muevete.fn_cotizar_viaje(
--                c.lat_o, c.lon_o, c.lat_d, c.lon_d, c.tipo,
--                timestamptz '2026-11-16 12:00:00-05', c.km,
--                'Villa Clara', c.muni) AS j
--     ) x
--    ORDER BY c.caso;
--
--   -- ESPERADO (auto ×1.0 si no se indica; redondeo 50; comisión 15 %):
--   -- A   1500    fijo         rec 0       via 0       com 225    chofer 1275
--   -- B   2700    fijo_mas_km  rec 0       via 9.990   com 405    chofer 2295
--   -- C   9700    fijo_mas_km  rec 33.982  via 33.982  com 1455   chofer 8245
--   -- D  10400    fijo_mas_km  rec 33.982  via 40.000  com 1560   chofer 8840   <-- publicado
--   -- E   6300    fijo_mas_km  rec 0       via 40.000  com 945    chofer 5355   <-- publicado
--   -- F  63550    fijo_mas_km  rec 258.412 via 258.412 com 2500*  chofer 61050  (*) tope
--   -- G    900    fijo         (moto ×0.6, piso 900)      com 135    chofer 765
--   -- H   2250    fijo         (microbús ×1.5, piso 2250) com 337.5  chofer 1912.5
--
-- 6.3 PRUEBA DE EMPAREJAMIENTO (la regresión que cierra esta migración)
--   -- Reproduce el predicado de fn_viajes_disponibles sin escribir nada:
--   WITH posiciones(nombre, lat, lon) AS (VALUES
--     ('chofer Parque Vidal',      22.406959, -79.965681),
--     ('chofer Arco Iris',         22.3961896,-79.9282471),
--     ('chofer 10 km al norte',    22.496800, -79.965700),
--     ('chofer UCLV',             22.4383115,-79.8944822),
--     ('chofer Placetas',         22.3166,   -79.6500)
--   ), origenes(nombre, lat, lon) AS (VALUES
--     ('solicitud casco (PV)',     22.406959, -79.965681),
--     ('solicitud periferia 10km', 22.496800, -79.965700),
--     ('solicitud Placetas',       22.3166,   -79.6500)
--   )
--   SELECT p.nombre AS chofer,
--          (SELECT z.id FROM muevete.fn_zona_de_punto(p.lat, p.lon, now()) z) AS zona_chofer,
--          o.nombre AS solicitud,
--          (SELECT z.id FROM muevete.fn_zona_de_punto(o.lat, o.lon, now()) z) AS zona_solicitud,
--          (SELECT z.id FROM muevete.fn_zona_de_punto(p.lat, p.lon, now()) z)
--            IS NOT DISTINCT FROM
--          (SELECT z.id FROM muevete.fn_zona_de_punto(o.lat, o.lon, now()) z) AS se_ven
--     FROM posiciones p CROSS JOIN origenes o
--    ORDER BY p.nombre, o.nombre;
--
--   -- ESPERADO: los 4 choferes del municipio (Parque Vidal, Arco Iris, 10 km,
--   -- UCLV) obtienen la MISMA zona (MUN) que las 2 solicitudes del municipio
--   -- → se_ven = true en las 8 combinaciones. El chofer de Placetas obtiene
--   -- NULL y sólo ve la solicitud de Placetas (NULL), igual que antes de la 053.
--
-- 6.4 No escribe nada (salvo la reasignación de pendientes del paso 4):
--   SELECT count(*) FROM muevete.solicitudes_transporte WHERE estado = 'pendiente'
--     AND zona_id = (SELECT id FROM muevete.zonas_tarifa WHERE codigo = 'SC-BASE');
--   -- esperado: 0

-- ============================================================================
-- 7. DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- -- 1) Devolver el área base a zona y restaurar la 053.
-- UPDATE muevete.zonas_tarifa
--    SET activo = true, prioridad = 5, modo = 'fijo', monto_fijo = 1500,
--        precio_km = 120, nombre = 'Casco Santa Clara - 1500 CUP'
--  WHERE codigo = 'SC-BASE';
-- UPDATE muevete.zonas_tarifa
--    SET activo = false, modo = 'fijo', monto_fijo = 1500, precio_km = 400,
--        nombre = 'Municipio Santa Clara (desactivada - sustituida por SC-BASE)'
--  WHERE codigo = 'MUN';
-- -- 2) Quitar columnas nuevas.
-- ALTER TABLE muevete.configuracion_tarifas
--   DROP COLUMN IF EXISTS base_nombre,
--   DROP COLUMN IF EXISTS base_sc_cup,
--   DROP COLUMN IF EXISTS precio_km_sc,
--   DROP COLUMN IF EXISTS base_radio_km,
--   DROP COLUMN IF EXISTS base_geometria,
--   DROP COLUMN IF EXISTS km_incluidos_base,
--   DROP COLUMN IF EXISTS tope_tramo_recogida_km,
--   DROP COLUMN IF EXISTS recogida_min_km;
-- -- 3) Restaurar el motor de la 053: re-ejecutar
-- --    `053_tarifa_sc_base_1500_120km.sql` (es CREATE OR REPLACE).
-- COMMIT;
--
-- ============================================================================
-- 8. RIESGOS QUE EL DUEÑO DEBE CONOCER
-- ============================================================================
--   · Un origen FUERA del rectángulo MUN (p. ej. La Habana) genera recogida y
--     una cotización de ~63.550 CUP. Si no se quieren fletes interprovinciales:
--     `UPDATE muevete.configuracion_tarifas SET tope_tramo_recogida_km = 60;`
--     o bloquear el origen en la app.
--   · El área base de 4,3 km deja FUERA a la UCLV (8,1 km): un viaje
--     Parque Vidal ↔ UCLV cuesta 1.500 + 120×8,1 ≈ 2.500 CUP. Si el dueño
--     quería que "la universidad" fuese la UCLV dentro de la base, hay que
--     subir el radio a ~8,5 km y eso encarecería/ablandaría toda la tarifa
--     urbana (8,5 km planos por 1.500).
--   · El tramo de recogida usa la distancia LINEAL desde el hub; la carretera
--     real a Placetas es ~17 % más larga. Si se quiere cobrar por carretera:
--     enviar el km de recogida desde la app (hoy no existe ese campo) o subir
--     `recogida_min_km`/aplicar un factor (no se hace para no mover los
--     números publicados en la landing).
--   · LÍMITE CONOCIDO (pre-existente, NO lo introduce la 054): una solicitud
--     que nace FUERA del municipio (Placetas → Santa Clara) queda con
--     `zona_id = NULL`, y `fn_viajes_disponibles` sólo se la enseña a choferes
--     con zona NULL (choferes de Placetas). Un chofer del municipio NO la ve,
--     aunque la tarifa le pague la recogida. Si el dueño quiere que los
--     choferes de Santa Clara vean los viajes que nacen en Placetas, hay que
--     parchear el predicado de `fn_viajes_disponibles` para incluir:
--         OR (v_zona_chofer IS NOT NULL AND s.zona_id IS NULL)
--     (decisión de producto: amplía el feed de todos los choferes del municipio
--     a toda solicitud sin zona; conviene filtrar además por distancia).
-- ============================================================================