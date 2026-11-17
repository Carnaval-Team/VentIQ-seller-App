-- ============================================================================
-- 055_tarifa_recogida_configurable.sql
-- TRAMO DE RECOGIDA (hub -> origen) CONFIGURABLE DESDE EL SUPERADMIN.
--
-- QUÉ YA EXISTÍA (054, viva en producción)
--   `fn_cotizar_viaje` cobraba un tramo de recogida = km del hub (Parque Vidal)
--   al origen, a 120 CUP/km, PERO con dos limitaciones duras:
--     · sólo se cobraba si el origen estaba FUERA del municipio del hub
--       (`recogida_min_km` = 8 además filtraba a los vecinos del parque);
--     · el precio/km del tramo era el mismo `precio_km_sc` del viaje, y tanto
--       el umbral como el tope y el hub sólo se podían cambiar con SQL a mano.
--   Resultado: un pasajero del propio Santa Clara a 10 km del parque pagaba
--   1.500 + 120 × viaje, sin recogida; y el dueño no tenía interruptor.
--
-- QUÉ AÑADE ESTA MIGRACIÓN
--   3 columnas nuevas en `muevete.configuracion_tarifas` (aditivas):
--     · `recogida_activa`         bool   (default true)  interruptor maestro.
--     · `recogida_en_municipio`   bool   (default false) cobrar el tramo
--                                       también cuando el origen está dentro
--                                       del perímetro municipal (hoy NO).
--     · `recogida_precio_km`      numeric (default NULL) CUP/km SÓLO del tramo
--                                       de recogida. NULL = usa `precio_km_sc`
--                                       (120), es decir el comportamiento de
--                                       la 054.
--   Y reescribe `fn_cotizar_viaje` para leerlas, con la MISMA firma de 9
--   argumentos, las MISMAS claves de salida y claves nuevas ADITIVAS
--   (`dist_hub_km`, `recogida_motivo`, `recogida_activa`,
--   `recogida_en_municipio`, `recogida_precio_km`, `tramo_recogida_cup`).
--
-- INVARIANTE DE PRECIOS (lo importante)
--   Con la configuración que queda tras esta migración
--   (`recogida_activa=true`, `recogida_en_municipio=false`,
--    `recogida_precio_km=NULL`, `recogida_min_km=8`, `tope=0`)
--   la rama de recogida evalúa EXACTAMENTE las mismas condiciones que la 054:
--     NOT v_en_muni  ∧  dist_hub > 8  ∧  (tope)  ∧  precio 120.
--   Ningún número publicado se mueve: Placetas → SC sigue en 10.400 CUP,
--   casco 1.500, La Habana → casco 63.550 (con el tope de comisión).
--   No se UPDATEA ni `recogida_min_km` ni `tope_tramo_recogida_km`: si el dueño
--   los afinó a mano, se respetan.
--
-- LO QUE ESTA MIGRACIÓN NO HACE (y no puede hacer sola)
--   El tramo se mide del HUB al origen, no de la posición real del chofer.
--   En el momento de cotizar no hay chofer asignado, así que la distancia real
--   de acercamiento no existe todavía. Cobrarla exigiría un cargo aparte al
--   completar el viaje (`fn_completar_viaje`) o en la liquidación del chofer.
--
-- DESPUÉS DE APLICARLA
--   El panel (`ventiq_superadmin` → Muevete → Tarifas → Configuración) muestra
--   la sección "Tramo de recogida" con los 3 campos nuevos + `recogida_min_km`,
--   `tope_tramo_recogida_km` y el hub. Antes de aplicarla, el panel detecta que
--   las columnas no existen y muestra el aviso en vez de romper el guardado.
--
-- IDEMPOTENTE: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE (misma firma),
-- REVOKE/GRANT. Se puede correr dos veces sin daño.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Columnas nuevas
--    `recogida_min_km` y `tope_tramo_recogida_km` ya existen desde la 054.
-- ============================================================================

ALTER TABLE muevete.configuracion_tarifas
  ADD COLUMN IF NOT EXISTS recogida_activa boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS recogida_en_municipio boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS recogida_precio_km numeric
    CHECK (recogida_precio_km IS NULL OR recogida_precio_km >= 0);

COMMENT ON COLUMN muevete.configuracion_tarifas.recogida_activa IS
  'Interruptor maestro del tramo de recogida (hub → origen). false = no se cobra nunca, aunque el origen esté fuera del municipio.';
COMMENT ON COLUMN muevete.configuracion_tarifas.recogida_en_municipio IS
  'true = el tramo de recogida también se cobra cuando el origen cae DENTRO del perímetro municipal del hub (con recogida_min_km como umbral). false = comportamiento de la 054.';
COMMENT ON COLUMN muevete.configuracion_tarifas.recogida_precio_km IS
  'CUP por km del tramo de recogida. NULL (o 0) = usar precio_km_sc, que es lo que hacía la 054 con los dos tramos al mismo precio.';

-- ============================================================================
-- 2. Estado explícito de la fila única (sin pisar lo que el dueño afinó)
--    ADD COLUMN con DEFAULT ya deja los valores correctos; este UPDATE sólo
--    garantiza que no queden NULL por haber corrido en un entorno raro.
-- ============================================================================

UPDATE muevete.configuracion_tarifas
   SET recogida_activa       = coalesce(recogida_activa, true),
       recogida_en_municipio = coalesce(recogida_en_municipio, false),
       updated_at            = now()
 WHERE id = 1
   AND (recogida_activa IS NULL OR recogida_en_municipio IS NULL);

-- Asserts de la configuración de la que depende la invariancia de precios.
DO $asserts$
DECLARE
  v_min   numeric;
  v_tope  numeric;
  v_precio numeric;
BEGIN
  SELECT recogida_min_km, tope_tramo_recogida_km, coalesce(recogida_precio_km, precio_km_sc)
    INTO v_min, v_tope, v_precio
    FROM muevete.configuracion_tarifas WHERE id = 1;

  IF v_min IS NULL THEN
    RAISE EXCEPTION 'recogida_min_km_nulo';
  END IF;
  IF coalesce(v_tope, 0) < 0 THEN
    RAISE EXCEPTION 'tope_tramo_recogida_km_negativo: %', v_tope;
  END IF;
  IF coalesce(v_precio, 0) <= 0 THEN
    RAISE EXCEPTION 'precio_km_de_recogida_no_positivo: %', v_precio;
  END IF;
END
$asserts$;

-- ============================================================================
-- 3. MOTOR DE COTIZACIÓN (misma firma; sólo cambia la rama de recogida)
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
  v_rec_precio   numeric;          -- 055: CUP/km sólo del tramo de recogida
  v_rec_motivo   text;             -- 055: por qué no se cobró (null = se cobró)
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

  -- 055: el tramo de recogida puede tener su propio CUP/km. NULL o 0 = el del
  -- viaje, que es lo que hacía la 054.
  v_rec_precio := coalesce(nullif(cfg.recogida_precio_km, 0), v_precio_km);

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
    v_modo       := 'fijo';
    v_base       := v_base_cup;
    v_rec_km     := 0;
    v_via_km     := 0;
    v_rec_motivo := 'dentro_del_area_base';
  ELSE
    v_modo := 'fijo_mas_km';

    -- ──────────────────────────────────────────────────────────────────────
    -- 055 · TRAMO DE RECOGIDA (hub → origen)
    --
    -- La distancia al hub se calcula SIEMPRE: se publica en `dist_hub_km` para
    -- que el panel pueda explicar por qué no se cobró. Lo que decide el cobro
    -- es esta cascada, en este orden:
    --   1. `recogida_activa = false`      → no se cobra nunca.
    --   2. origen en el municipio del hub → no se cobra salvo que
    --      `recogida_en_municipio = true`.
    --   3. dist_hub <= `recogida_min_km`  → no se cobra (el pasajero está
    --      cerca del hub; cobrarle "acercamiento" sería doble cobro).
    --   4. si no, se cobran los km del hub al origen, recortados por
    --      `tope_tramo_recogida_km` (0 = sin tope).
    -- ──────────────────────────────────────────────────────────────────────
    v_dist_hub := round(
      muevete.fn_haversine_km(v_hub_lat, v_hub_lon, p_lat_o, p_lon_o)::numeric, 3);

    IF NOT coalesce(cfg.recogida_activa, true) THEN
      v_rec_motivo := 'desactivada';

    ELSIF v_en_muni AND NOT coalesce(cfg.recogida_en_municipio, false) THEN
      v_rec_motivo := 'origen_en_el_municipio';

    ELSIF v_dist_hub <= coalesce(cfg.recogida_min_km, 8) THEN
      v_rec_motivo := 'bajo_el_minimo';

    ELSE
      v_rec_km := v_dist_hub;
      IF coalesce(cfg.tope_tramo_recogida_km, 0) > 0 THEN
        v_rec_km := least(v_rec_km, cfg.tope_tramo_recogida_km);
      END IF;
      v_rec_motivo := NULL;   -- se cobró
    END IF;

    v_via_km := greatest(0::numeric, v_km - coalesce(cfg.km_incluidos_base, 0));

    v_rec_cup := round(v_rec_km * v_rec_precio, 2);
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
    'km_cobrados',             v_km_cobrados,
    -- claves aditivas (055) del tramo de recogida configurable
    'recogida_activa',         coalesce(cfg.recogida_activa, true),
    'recogida_en_municipio',   coalesce(cfg.recogida_en_municipio, false),
    'recogida_precio_km',      v_rec_precio,
    'tope_tramo_recogida_km',  coalesce(cfg.tope_tramo_recogida_km, 0),
    'dist_hub_km',             v_dist_hub,
    'recogida_motivo',         v_rec_motivo
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
    'km_cobrados',        v_km_cobrados,
    -- alias aditivos (055)
    'tramo_recogida_cup', v_rec_cup,
    'recogida_motivo',    v_rec_motivo
  );
END;
$function$;

COMMENT ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) IS
  'RPC #3. Motor único de cotización. 054: 1.500 CUP dentro del área base de SC y 1.500 + 120 × (recogida + viaje) fuera. 055: el tramo de recogida (hub → origen) es configurable — recogida_activa, recogida_en_municipio, recogida_precio_km, recogida_min_km, tope_tramo_recogida_km. No escribe nada.';

REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) TO authenticated;

COMMIT;

-- ============================================================================
-- 4. VERIFICACIÓN (a mano; sólo lectura)
--
--    OJO: `fn_cotizar_viaje` sólo es ejecutable por `authenticated`, así que
--    desde psql como postgres/supabase_read_only_user da 42501. Correr el 4.2
--    desde el SQL Editor de Supabase (que usa un rol con permiso) o desde la
--    app. El 4.1 y el 4.3 sí corren con cualquier rol de lectura.
-- ============================================================================
--
-- 4.1 Configuración que debe quedar después de aplicar:
--   SELECT recogida_activa, recogida_en_municipio, recogida_precio_km,
--          recogida_min_km, tope_tramo_recogida_km, hub_lat, hub_lon,
--          precio_km_sc
--     FROM muevete.configuracion_tarifas WHERE id = 1;
--   -- esperado tras aplicar: true | false | (null) | 8 | 0 | 22.406959 |
--   --                         -79.965681 | 120
--
-- 4.2 Los 8 casos de la 054 deben dar EXACTAMENTE lo mismo que antes
--     (p_id_tipo 5 = auto, 3 = moto, 6 = microbús):
--
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
--          (x.j->>'precio_plataforma')::numeric AS precio,
--          x.j->>'tarifa_modo'                  AS modo,
--          (x.j->>'tramo_recogida_km')::numeric AS rec_km,
--          (x.j->>'tramo_recogida_cup')::numeric AS rec_cup,
--          (x.j->>'tramo_viaje_km')::numeric    AS via_km,
--          (x.j->>'comision_monto')::numeric    AS comision,
--          (x.j->>'precio_chofer')::numeric     AS chofer,
--          x.j->>'recogida_motivo'              AS motivo
--     FROM casos c
--     CROSS JOIN LATERAL (
--       SELECT muevete.fn_cotizar_viaje(
--                c.lat_o, c.lon_o, c.lat_d, c.lon_d, c.tipo,
--                timestamptz '2026-11-16 12:00:00-05', c.km,
--                'Villa Clara', c.muni) AS j
--     ) x
--    ORDER BY c.caso;
--
--   -- ESPERADO (idéntico a la 054; sólo se añaden rec_cup, motivo):
--   -- A   1500    fijo         rec 0       rec 0      via 0       com 225    chofer 1275    dentro_del_area_base
--   -- B   2700    fijo_mas_km  rec 0       rec 0      via 9.990   com 405    chofer 2295    origen_en_el_municipio
--   -- C   9700    fijo_mas_km  rec 33.982  rec 4077.84 via 33.982  com 1455   chofer 8245    (null = se cobró)
--   -- D  10400    fijo_mas_km  rec 33.982  rec 4077.84 via 40.000  com 1560   chofer 8840    (null)   <-- publicado
--   -- E   6300    fijo_mas_km  rec 0       rec 0      via 40.000  com 945    chofer 5355    origen_en_el_municipio
--   -- F  63550    fijo_mas_km  rec 258.412 rec 31009.44 via 258.412 com 2500* chofer 61050   (null)
--   -- G    900    fijo         (moto ×0.6, piso 900)                            com 135    chofer 765
--   -- H   2250    fijo         (microbús ×1.5, piso 2250)                        com 337.5  chofer 1912.5
--
-- 4.3 Prueba de que el interruptor muerde (se hace y se deshace):
--   -- BEGIN;
--   --   UPDATE muevete.configuracion_tarifas SET recogida_activa = false WHERE id = 1;
--   --   -- D debe bajar de 10400 a 10400 - 4.077,84 = 6300 exacto
--   -- ROLLBACK;
--
--   -- BEGIN;
--   --   UPDATE muevete.configuracion_tarifas SET recogida_en_municipio = true WHERE id = 1;
--   --   -- B (9,99 km al norte del hub, dentro del municipio) debe pasar de 2700 a
--   --   -- 1500 + 120×9,99 (viaje) + 120×9,99 (recogida) = 3.897,60 → 3900
--   -- ROLLBACK;

-- ============================================================================
-- 5. DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- -- 1) Volver al motor de la 054 (CREATE OR REPLACE; no borra datos).
-- --    Copiar el cuerpo de 054_tarifa_sc_base_config_y_matching.sql §5.
-- -- 2) Quitar las columnas nuevas.
-- ALTER TABLE muevete.configuracion_tarifas
--   DROP COLUMN IF EXISTS recogida_activa,
--   DROP COLUMN IF EXISTS recogida_en_municipio,
--   DROP COLUMN IF EXISTS recogida_precio_km;
-- COMMIT;
--
-- Nota: el panel del superadmin detecta la ausencia de `recogida_activa` y
-- esconde la sección, así que un DOWN no deja la app rota.
-- ============================================================================