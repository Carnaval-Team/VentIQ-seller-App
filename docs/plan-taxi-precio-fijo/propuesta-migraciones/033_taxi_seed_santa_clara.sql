-- ============================================================================
-- 033_taxi_seed_santa_clara.sql
-- H0 · Semilla de arranque de Santa Clara (parámetros, fallback municipal,
--      multiplicadores por tipo y zonas MUN/FB + borradores Z1..Z9).
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/04-diseno-tecnico.md §2.9
--                  y PLAN-IMPLEMENTACION.md §2.3 y §2.4
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql
--   · 031_taxi_zonas_tarifas.sql (tablas y columnas)
--   · 032_taxi_geo_y_cotizacion.sql (para validar después con fn_cotizar_viaje)
--
-- IDEMPOTENCIA
--   · UPDATE de configuración: es un upsert lógico sobre id = 1.
--   · UPDATE de vehicle_type: por lower(tipo); si un tipo no existe, no falla.
--   · INSERT de municipio: ON CONFLICT (provincia, municipio) DO UPDATE.
--   · INSERT de zonas: ON CONFLICT (codigo) DO NOTHING → si el superadmin
--     ya editó una zona, este archivo NO la pisa al re-ejecutarse.
--
-- IMPORTANTE
--   · MUN se siembra ACTIVA porque reproduce el comportamiento tarifario
--     actual (círculo de 2,53 km de Santa Clara) con un rectángulo aproximado.
--     El polígono real del municipio lo dibuja/ajusta el superadmin en el editor.
--   · Z1..Z9 se siembran INACTIVAS como borradores: ninguna zona interna
--     empieza a cobrar sin que el negocio la dibuje y la active.
--   · FB se siembra INACTIVA: el fallback D4 lo resuelve tarifas_municipio;
--     FB queda sólo como fallback geométrico opcional.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Configuración global de arranque (PLAN §2.3)
--    D5 comisión 15 % · D6 deuda · D2 multiplicadores viven en vehicle_type.
-- ----------------------------------------------------------------------------
UPDATE muevete.configuracion_tarifas SET
  moneda                        = 'CUP',
  comision_pct                  = 15.00,
  tope_comision_viaje           = 2500,
  recarga_pct                   = 11.00,
  -- D6: plan §2.3 arranca en 1000; el lanzamiento puede bajarse a 500 con un UPDATE
  limite_deuda_efectivo         = 1000,
  permite_deuda                 = true,
  dias_max_deuda                = 7,
  precio_minimo_auto            = 1500,
  precio_minimo_moto            = 900,
  precio_minimo_microbus        = 2250,
  precio_corto_auto             = 1000,
  umbral_km_corto               = 1.5,
  recargo_nocturno_pct          = 20,
  ventana_nocturna_inicio       = '22:00',
  ventana_nocturna_fin          = '06:00',
  prima_distancia_cup           = 500,
  umbral_prima_distancia_km     = 8,
  gracia_espera_min             = 3,
  tope_cobro_espera             = 1200,
  redondeo_cup                  = 50,
  descuento_pago_wallet_pct     = 5,
  monto_fijo_fallback_municipio = 1500,
  precio_km_fallback            = 400,
  precio_vigente_desde          = now(),
  -- El corte es una decisión aparte (H6). Se siembra APAGADO.
  taxi_precio_fijo_activo       = false,
  updated_at                    = now()
WHERE id = 1;

-- Si por alguna razón no existe la fila singleton (no debería: 031 la crea),
-- la creamos con los defaults y repetimos el UPDATE una sola vez.
INSERT INTO muevete.configuracion_tarifas (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. Fallback municipal D4: Villa Clara / Santa Clara (1500 fijo + 400/km)
-- ----------------------------------------------------------------------------
INSERT INTO muevete.tarifas_municipio
  (provincia, municipio, modo, monto_fijo, precio_km, activo)
VALUES
  ('Villa Clara', 'Santa Clara', 'fijo', 1500, 400, true)
ON CONFLICT (provincia, municipio) DO UPDATE
  SET modo       = excluded.modo,
      monto_fijo = excluded.monto_fijo,
      precio_km  = excluded.precio_km,
      activo     = excluded.activo,
      updated_at = now();

-- ----------------------------------------------------------------------------
-- 3. D2 · Multiplicador por tipo de vehículo (PLAN §2.5)
--    7 tipos pasajeros activos en producción:
--      moto 0.60 · auto 1.00 · microbus 1.50 · camioneta 1.20
--      minivan 1.30 · tuktuk 0.50 · bicicleta 0.30
--    Los UPDATE son por lower(tipo): si un tipo no existe, simplemente no
--    actualiza filas (no falla).
-- ----------------------------------------------------------------------------
UPDATE muevete.vehicle_type SET multiplicador_tarifa = v.mult
FROM (VALUES
  ('moto',      0.60),
  ('auto',      1.00),
  ('microbus',  1.50),
  ('camioneta', 1.20),
  ('minivan',   1.30),
  ('tuktuk',    0.50),
  ('bicicleta', 0.30)
) AS v(tipo, mult)
WHERE lower(muevete.vehicle_type.tipo) = v.tipo;

-- Tarifa de espera por tipo (PLAN §2.3: auto 40 · moto 100 · microbús 60 CUP/min).
-- NOTA: estas columnas NO están en configuracion_tarifas (el contrato sólo
-- define gracia_espera_min y tope_cobro_espera). El valor por minuto ya existe
-- en muevete.vehicle_type.precio_espera_min y es el que usa fn_completar_viaje.
UPDATE muevete.vehicle_type SET precio_espera_min = v.precio
FROM (VALUES
  ('auto',      40),
  ('moto',     100),
  ('microbus',  60)
) AS v(tipo, precio)
WHERE lower(muevete.vehicle_type.tipo) = v.tipo;

-- ----------------------------------------------------------------------------
-- 4. Zonas semilla
--    MUN: rectángulo aproximado del municipio de Santa Clara (ACTIVA).
--    FB : rectángulo provincial (INACTIVA, fallback geométrico opcional).
--    Z1..Z9: borradores INACTIVOS con rectángulos de referencia.
--    Prioridad: MAYOR gana. MUN = 0; FB = -10; internas 40..120.
--    Los rectángulos son PLACEHOLDERS: el negocio los redibuja en el editor.
-- ----------------------------------------------------------------------------

-- 4.1 MUN · Municipio Santa Clara (base, activa)
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo,
   monto_fijo, precio_km, prioridad, activo)
VALUES (
  'MUN',
  'Municipio Santa Clara',
  'Villa Clara',
  'Santa Clara',
  jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
    jsonb_build_array(
      jsonb_build_array(-80.050, 22.300),
      jsonb_build_array(-79.850, 22.300),
      jsonb_build_array(-79.850, 22.550),
      jsonb_build_array(-80.050, 22.550)
    )
  )),
  'fijo', 1500, 400, 0, true
)
ON CONFLICT (codigo) DO NOTHING;

-- 4.2 FB · Fallback provincial (inactiva; D4 real = tarifas_municipio)
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo,
   monto_fijo, precio_km, prioridad, activo)
VALUES (
  'FB',
  'Fallback provincial (Villa Clara)',
  'Villa Clara',
  NULL,
  jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
    jsonb_build_array(
      jsonb_build_array(-80.600, 21.900),
      jsonb_build_array(-79.100, 21.900),
      jsonb_build_array(-79.100, 22.900),
      jsonb_build_array(-80.600, 22.900)
    )
  )),
  'fijo', 1500, 400, -10, false
)
ON CONFLICT (codigo) DO NOTHING;

-- 4.3 Z1..Z9 · borradores INACTIVOS (PLAN §2.4)
--     Rectángulos de referencia alrededor del punto aproximado de cada zona.
--     Todas con activo = false: se activan sólo después de dibujarlas.
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo,
   monto_fijo, precio_km, prioridad, activo)
VALUES
  -- Z1 · Centro (fijo)
  ('Z1', 'Z1 · Centro', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.975, 22.400),
       jsonb_build_array(-79.955, 22.400),
       jsonb_build_array(-79.955, 22.415),
       jsonb_build_array(-79.975, 22.415)
     ))),
   'fijo', 1500, 400, 100, false),

  -- Z2 · Condado–Santa Catalina (fijo)
  ('Z2', 'Z2 · Condado - Santa Catalina', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.965, 22.390),
       jsonb_build_array(-79.945, 22.390),
       jsonb_build_array(-79.945, 22.405),
       jsonb_build_array(-79.965, 22.405)
     ))),
   'fijo', 1500, 400, 90, false),

  -- Z3 · Reparto Virginia (fijo + km)
  ('Z3', 'Z3 · Reparto Virginia', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.940, 22.420),
       jsonb_build_array(-79.915, 22.420),
       jsonb_build_array(-79.915, 22.445),
       jsonb_build_array(-79.940, 22.445)
     ))),
   'fijo_mas_km', 300, 400, 80, false),

  -- Z4 · Báez (fijo + km)
  ('Z4', 'Z4 · Báez', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.930, 22.350),
       jsonb_build_array(-79.900, 22.350),
       jsonb_build_array(-79.900, 22.380),
       jsonb_build_array(-79.930, 22.380)
     ))),
   'fijo_mas_km', 500, 420, 70, false),

  -- Z5 · UCLV (fijo + km)
  ('Z5', 'Z5 · UCLV', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.945, 22.440),
       jsonb_build_array(-79.910, 22.440),
       jsonb_build_array(-79.910, 22.470),
       jsonb_build_array(-79.945, 22.470)
     ))),
   'fijo_mas_km', 500, 420, 70, false),

  -- Z6 · Aeropuerto (fijo + km)
  ('Z6', 'Z6 · Aeropuerto', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-79.960, 22.480),
       jsonb_build_array(-79.940, 22.480),
       jsonb_build_array(-79.940, 22.500),
       jsonb_build_array(-79.960, 22.500)
     ))),
   'fijo_mas_km', 1000, 420, 120, false),

  -- Z7 · Periferia / Circunvalación (fijo + km)
  ('Z7', 'Z7 · Periferia / Circunvalación', 'Villa Clara', 'Santa Clara',
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-80.020, 22.340),
       jsonb_build_array(-79.870, 22.340),
       jsonb_build_array(-79.870, 22.530),
       jsonb_build_array(-80.020, 22.530)
     ))),
   'fijo_mas_km', 300, 420, 50, false),

  -- Z8 · Corredor intermunicipal (fijo + km)
  ('Z8', 'Z8 · Corredor intermunicipal', 'Villa Clara', NULL,
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-80.300, 22.200),
       jsonb_build_array(-79.500, 22.200),
       jsonb_build_array(-79.500, 22.700),
       jsonb_build_array(-80.300, 22.700)
     ))),
   'fijo_mas_km', 800, 450, 40, false),

  -- Z9 · Cayos (fijo + km)
  ('Z9', 'Z9 · Cayos', 'Villa Clara', NULL,
   jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
     jsonb_build_array(
       jsonb_build_array(-81.100, 22.900),
       jsonb_build_array(-80.300, 22.900),
       jsonb_build_array(-80.300, 23.300),
       jsonb_build_array(-81.100, 23.300)
     ))),
   'fijo_mas_km', 800, 450, 40, false)
ON CONFLICT (codigo) DO NOTHING;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Configuración:
--   SELECT comision_pct, tope_comision_viaje, recarga_pct,
--          permite_deuda, limite_deuda_efectivo, dias_max_deuda,
--          precio_minimo_auto, precio_minimo_moto, precio_minimo_microbus,
--          precio_corto_auto, umbral_km_corto, recargo_nocturno_pct,
--          redondeo_cup, prima_distancia_cup, umbral_prima_distancia_km,
--          monto_fijo_fallback_municipio, precio_km_fallback,
--          taxi_precio_fijo_activo
--     FROM muevete.configuracion_tarifas WHERE id = 1;
--      -- esperado: 15 | 2500 | 11 | true | 1000 | 7 | 1500 | 900 | 2250 |
--      --           1000 | 1.5 | 20 | 50 | 500 | 8 | 1500 | 400 | false
--
-- 2) Fallback municipal:
--   SELECT provincia, municipio, modo, monto_fijo, precio_km, activo
--     FROM muevete.tarifas_municipio ORDER BY municipio;
--      -- esperado: Villa Clara / Santa Clara | fijo | 1500 | 400 | true
--
-- 3) Multiplicadores D2:
--   SELECT tipo, multiplicador_tarifa, precio_espera_min
--     FROM muevete.vehicle_type
--    WHERE categoria = 'pasajero' OR categoria IS NULL
--    ORDER BY tipo;
--      -- moto 0.60/100 · auto 1.00/40 · microbus 1.50/60 · camioneta 1.20
--      -- minivan 1.30 · tuktuk 0.50 · bicicleta 0.30
--
-- 4) Zonas:
--   SELECT codigo, nombre, modo, monto_fijo, precio_km, prioridad, activo
--     FROM muevete.zonas_tarifa ORDER BY prioridad DESC, codigo;
--      -- esperado: 11 filas; MUN activa; FB y Z1..Z9 inactivas
--   SELECT count(*) FROM muevete.zonas_tarifa WHERE activo;  -- esperado: 1 (MUN)
--
-- 5) Verifica que MUN cubre el centro (debe devolver true):
--   SELECT muevete.fn_punto_en_poligono(22.4069, -79.9657,
--     (SELECT geometria FROM muevete.zonas_tarifa WHERE codigo='MUN'));
--
-- 6) Cotización de humo (auto id=2, 3.2 km dentro de MUN):
--   SELECT jsonb_pretty(muevete.fn_cotizar_viaje(
--     22.4069, -79.9657, 22.4120, -79.9600, 2,
--     '2026-11-12T10:00:00-05:00'::timestamptz, 3.2, 'Villa Clara', 'Santa Clara'));
--      -- esperado precio_plataforma 1500 / comision 225 / chofer 1275
--
-- 7) Idempotencia: re-ejecutar 033 completo no debe fallar ni duplicar zonas.
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ----------------------------------------------------------------------------
-- La semilla no se "deshace" con DELETE si el negocio ya la editó. Para
-- desactivar el cobro nuevo basta con:
--   UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = false WHERE id = 1;
--
-- Si se quiere volver al estado previo a la semilla en un entorno de pruebas:
-- BEGIN;
-- DELETE FROM muevete.zonas_tarifa WHERE codigo IN
--   ('MUN','FB','Z1','Z2','Z3','Z4','Z5','Z6','Z7','Z8','Z9');
-- DELETE FROM muevete.tarifas_municipio
--  WHERE provincia = 'Villa Clara' AND municipio = 'Santa Clara';
-- UPDATE muevete.vehicle_type SET multiplicador_tarifa = 1;
-- -- (precio_espera_min no se revierte: ya existía con sus valores previos)
-- COMMIT;
-- ============================================================================