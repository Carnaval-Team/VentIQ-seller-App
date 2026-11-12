# 04 · Diseño técnico — Taxi Muevete con precio fijado por la plataforma

> **Rol:** programador / diseñador técnico del equipo.
> **Alcance:** esquema `muevete` (migraciones `030`–`038`), 9 RPCs, RLS, app `inventtia_muevete/` y consola `ventiq_superadmin/`.
> **Contrato de referencia:** [`PLAN-IMPLEMENTACION.md`](PLAN-IMPLEMENTACION.md) §4 (datos) y §5 (RPCs). **Este documento no renombra nada del contrato.** Lo que propongo distinto va en §12 "Desvíos propuestos".
> **Depende de:** `01-analisis-tecnico.md`, `02-modelo-negocio.md`, `03-modelo-economico.md`, `PLAN-IMPLEMENTACION.md`.
> **Modo:** diseño. No se implementó código; el único archivo escrito es este.
> **Fecha:** 2026-11-12 (America/Havana).
> **Verificación:** esquema real consultado por SQL contra el proyecto Supabase (no sólo contra los `.sql` del repo). Resultados en §0.2.

---

## Índice

1. [Resumen y verificación previa](#1-resumen-y-verificación-previa)
2. [Modelo de datos (DDL completo)](#2-modelo-de-datos-ddl-completo)
3. [Evaluación de zona (sin PostGIS)](#3-evaluación-de-zona-sin-postgis)
4. [Cálculo de la tarifa](#4-cálculo-de-la-tarifa)
5. [Las 9 RPCs: firma y cuerpo](#5-las-9-rpcs-firma-y-cuerpo)
6. [RLS, permisos y realtime](#6-rls-permisos-y-realtime)
7. [Cambios en `inventtia_muevete/`](#7-cambios-en-inventtia_muevete)
8. [Cambios en `ventiq_superadmin/`](#8-cambios-en-ventiq_superadmin)
9. [Compatibilidad y migración](#9-compatibilidad-y-migración)
10. [Plan de pruebas](#10-plan-de-pruebas)
11. [Hitos H0–H6](#11-hitos-h0h6)
12. [Desvíos propuestos (explícitos)](#12-desvíos-propuestos-explícitos)
13. [Supuestos](#13-supuestos)
14. [Riesgos](#14-riesgos)
15. [Recomendación](#15-recomendación)

---

## 1. Resumen y verificación previa

### 1.1 Qué se entrega por capa

| Capa | Entrega |
|---|---|
| **BD** | `muevete.zonas_tarifa` (polígono GeoJSON en `jsonb`), `muevete.tarifas_municipio` (fallback D4), `muevete.configuracion_tarifas` (singleton), `vehicle_type.multiplicador_tarifa` (D2), columnas snapshot en `solicitudes_transporte` y `viajes` (`solicitud_id`). |
| **RPCs** | `fn_punto_en_poligono`, `fn_zona_de_punto`, `fn_cotizar_viaje`, `fn_crear_solicitud`, `fn_viajes_disponibles`, `fn_tomar_viaje` (atómico), `fn_completar_viaje`, `fn_cancelar_solicitud`, `fn_recargar_wallet`. |
| **Cliente** | Precio de sólo lectura, desglose, "Buscando conductor", sin campo de oferta ni pantalla de ofertas. |
| **Chofer** | Lista "Viajes disponibles" con **"Cliente paga $X · Te toca $Y (Z %)"**, botón **Tomar viaje**, deuda visible, sin contraoferta. |
| **Superadmin** | "Zonas y Tarifas": lista/CRUD, editor de polígono sobre `flutter_map`, parámetros globales, simulador (precio / comisión / neto). |

### 1.2 Verificación hecha antes de diseñar

Consultas ejecutadas contra el proyecto (`muevete`, sólo lectura):

| Verificación | Resultado | Consecuencia |
|---|---|---|
| PostGIS instalado | **No.** `pg_extension`: `pg_cron, pg_net, pg_stat_statements, pg_trgm, pgcrypto, plpgsql, supabase_vault, unaccent, uuid-ossp, vector`. `pg_available_extensions`: `postgis 3.3.7`, `installed_version = null`. | **Point-in-polygon en PL/pgSQL**, sin PostGIS. `fn_punto_en_poligono` es el único acoplamiento para migrar a `ST_Contains` después. |
| `CREATE EXTENSION` en el repo | 0 coincidencias en `supabase/migrations/`, `inventtia_muevete/docs/migrations/`, `sql_updates/`, `sql_triggers/`, raíz. | No hay provisión de extensiones; asumir PostGIS sería frágil. |
| `políticas RLS` reales | El plan §2.5 reporta 118 políticas en `muevete`. Verifiqué por SQL las de `solicitudes_transporte`, `ofertas_chofer`, `viajes`, `place`, `drivers`, `vehicle_type` y `notificaciones`: `drivers_see_solicitudes` es `USING (true)` para el rol público, `solicitudes_select_own_client` es `((user_id = auth.uid()) OR true)`, `solicitudes_update_own_client`/`insert_client` permiten al cliente escribir cualquier columna, `viajes_insert_authenticated` es `WITH CHECK (true)` y `ofertas_update_client` existe. **No verifiqué por SQL** `wallet_drivers`/`transacciones_wallet` (las tomo del plan §2.5) → se confirman en H0. | El endurecimiento va en `038` **en el cutover**, no en H0 (si no, se rompen las apps actuales). |
| `viajes` | `driver_id smallint` (vs `drivers.id bigint`), **sin `solicitud_id`**; `estado` es `bool` (semántica: `false` = yendo a recoger, `true` = en viaje), `completado bool`. | `ALTER COLUMN driver_id TYPE bigint` (metadata-only) + `solicitud_id` + índice único. |
| `solicitudes_transporte` | 16 columnas; **sin `driver_id`**; `precio_oferta numeric`; `estado` sin CHECK; `expires_at` sin default. | Añadir las columnas del contrato §4.2 + trigger de guarda. |
| `vehicle_type` | Columnas `tipo, precio_km_default, precio_inside_sc, status, tiempo_min_por_km, precio_espera_min, categoria`; **sin** `multiplicador_tarifa`; el plan §2.5 reporta 7 tipos pasajeros activos. | Añadir `multiplicador_tarifa` y sembrarlo (H0). `precio_espera_min` **ya existe** → se usa para la espera de `fn_completar_viaje`. |
| Funciones reutilizables | `muevete.set_updated_at()`, `muevete.get_my_driver_id()`, `muevete.is_superadmin()`, `muevete.complete_ride_payment(...)` (6 args + sobrecarga legacy de 5, con `0.15` hardcodeado), `pg_cron`. **Ya versionadas en `030_baseline_sync_produccion.sql`.** | Se reutilizan tal cual; **no se redefinen** en 031–038. |
| Triggers de push | `solicitudes_push`, `ofertas_push`, `notificaciones_push` → Edge Function `send-push-notification`. La función **no está en el repo** (`supabase/functions/` sólo tiene `ai-*`). | El push por zona es dependencia externa (§9.6). Plan B: realtime + polling + notificación local. |
| `tarjetas`/estado de negociación | `ofertas_chofer` viva y escrita por 5 puntos de la app; `driver_offers_screen.dart` activa. | Se elimina escritura; tabla queda `LEGACY` de sólo lectura (plan §8.4). |

**Discrepancia a resolver en H0 (importante).** El plan §2.5 reporta que `notificaciones, ofertas_chofer, place, solicitudes_transporte, vehicle_type, viajes` están publicadas en realtime. Mi consulta `SELECT * FROM pg_publication_tables WHERE schemaname='muevete'` devolvió **0 filas**, y `supabase_realtime` contiene 2 tablas del esquema `flow`. No sé si el plan revisó otro endpoint/proyecto o el dashboard. **Acción H0:** re-ejecutar

```sql
SELECT pubname, schemaname, tablename FROM pg_publication_tables WHERE schemaname = 'muevete';
SELECT relname, relreplident FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname='muevete' AND relname IN ('solicitudes_transporte','viajes','vehicle_type');
```

y, si faltan, aplicar en `034_taxi_rls_tarifas.sql` (o en el cutover, según decisión):

```sql
ALTER TABLE muevete.solicitudes_transporte REPLICA IDENTITY FULL;
ALTER TABLE muevete.viajes                 REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE muevete.solicitudes_transporte;
ALTER PUBLICATION supabase_realtime ADD TABLE muevete.viajes;
```

**Mientras no se confirme, el diseño asume polling** como red de seguridad en todas las pantallas nuevas (15 s). No se apuesta la UX a realtime.

### 1.3 Principios de implementación (obligatorios)

1. **El dinero sólo lo escribe el servidor.** `precio_plataforma`, `comision_pct`, `precio_chofer`, `tarifa_detalle`, `zona_id`, `driver_id` son de escritura exclusiva de las RPC. Doble defensa: `GRANT` por columna (cutover) + trigger de guarda (`fn_solicitud_guarda`, activo desde H0 cuando `taxi_precio_fijo_activo=true`).
2. **Snapshot congelado.** La tarifa se calcula al crear la solicitud y no se recalcula al completar. Cambiar precios/comisión no altera viajes en curso.
3. **Una sola puerta por transición.** `pendiente → aceptada` sólo por `fn_tomar_viaje`; `→ completada` sólo por `fn_completar_viaje`; `→ cancelada` sólo por `fn_cancelar_solicitud`; `→ expirada` por job/cron.
4. **Atómico o nada.** `fn_tomar_viaje` = un único `UPDATE … WHERE estado='pendiente' AND driver_id IS NULL RETURNING`; el perdedor no actualiza filas.
5. **Nombres del contrato intactos.** Cualquier adición va en §12, no en silencio.

---

## 2. Modelo de datos (DDL completo)

### 2.1 Archivos de migración

| Archivo | Contenido |
|---|---|
| `inventtia_muevete/docs/migrations/031_taxi_zonas_tarifas.sql` | Las 3 tablas de §2.2–§2.4, `vehicle_type.multiplicador_tarifa`, columnas de §2.5–§2.6, índices, triggers `updated_at`, trigger de guarda (`fn_solicitud_guarda`), `down` documentado al final. |
| `032_taxi_geo_y_cotizacion.sql` | `fn_punto_en_anillo` (helper), `fn_haversine_km` (helper), `fn_punto_en_poligono`, `fn_zona_de_punto`, `fn_cotizar_viaje`. |
| `033_taxi_seed_santa_clara.sql` | `configuracion_tarifas` (valores §2.3 del plan), `tarifas_municipio` Villa Clara/Santa Clara (1500/400), `vehicle_type.multiplicador_tarifa` (7 tipos), zonas MUN y FB (+ borradores Z1–Z9 inactivos). |
| `034_taxi_rls_tarifas.sql` | RLS de las 3 tablas nuevas (`SELECT` authenticated + `superadmin_all_*`), grants de funciones de lectura/cotización, y (si se confirma) publicación realtime. |
| `035_taxi_rpc_solicitud.sql` | `fn_crear_solicitud`, `fn_cancelar_solicitud`. |
| `036_taxi_rpc_toma.sql` | `fn_viajes_disponibles`, `fn_tomar_viaje`. |
| `037_taxi_rpc_cierre.sql` | `fn_completar_viaje`, `fn_recargar_wallet`. **No redefine `complete_ride_payment`** (vive en `030_baseline`). |
| `038_taxi_rls_hardening.sql` | Revocación de las 8 políticas de §4.3 del plan. **Sólo en el cutover.** |
| `docs/plan-taxi-precio-fijo/sql/` | `test_cotizacion.sql`, `test_concurrencia.sql`, `test_rls.sql`, volcado de `pg_policies`/`pg_publication_tables`. |

Convención de orden: el repo usa prefijo numérico en `inventtia_muevete/docs/migrations/`. **`030_baseline_sync_produccion.sql` ya existe y está versionado**: contiene el estado real de producción (entre otras cosas `get_my_driver_id()`, `is_superadmin()`, `complete_ride_payment` de 6 argumentos **y su sobrecarga legacy de 5**, y los triggers de push `solicitudes_push`/`ofertas_push`/`notificaciones_push`). **Esos objetos se reutilizan tal cual y NO se redefinen en 031–038.** Las migraciones nuevas empiezan en `031` y siguen la numeración de este diseño.

### 2.2 `muevete.zonas_tarifa`

```sql
-- 031_taxi_zonas_tarifas.sql
BEGIN;

CREATE TABLE IF NOT EXISTS muevete.zonas_tarifa (
  id             bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre         text        NOT NULL,
  provincia      text,
  municipio      text,
  -- D1: GeoJSON Polygon. coordinates = [ anillo_exterior, huecos… ];
  -- cada punto es [lon, lat] (orden GeoJSON).
  geometria      jsonb       NOT NULL,
  -- D3
  modo           text        NOT NULL,
  monto_fijo     numeric,
  precio_km      numeric,
  -- Resolución de solapes: MAYOR prioridad gana (contrato §4.1)
  prioridad      integer     NOT NULL DEFAULT 0,
  activo         boolean     NOT NULL DEFAULT true,
  vigente_desde  timestamptz NOT NULL DEFAULT now(),
  vigente_hasta  timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT zonas_tarifa_pkey PRIMARY KEY (id),
  CONSTRAINT zonas_tarifa_geo_valida
    CHECK (jsonb_typeof(geometria -> 'coordinates') = 'array'),
  CONSTRAINT zonas_tarifa_modo_chk
    CHECK (modo IN ('fijo','fijo_mas_km','por_km')),
  CONSTRAINT zonas_tarifa_montos_chk CHECK (
       (modo = 'fijo'        AND monto_fijo IS NOT NULL AND monto_fijo >= 0)
    OR (modo = 'fijo_mas_km' AND monto_fijo IS NOT NULL AND monto_fijo >= 0
                            AND precio_km  IS NOT NULL AND precio_km  >= 0)
    OR (modo = 'por_km'      AND precio_km  IS NOT NULL AND precio_km  >= 0)
  ),
  CONSTRAINT zonas_tarifa_vigencia_chk
    CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

CREATE INDEX IF NOT EXISTS zonas_tarifa_activas_idx
  ON muevete.zonas_tarifa (activo, prioridad DESC)
  WHERE activo;

CREATE TRIGGER trg_zonas_tarifa_updated_at
  BEFORE UPDATE ON muevete.zonas_tarifa
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
```

Formato de `geometria` (el que produce el editor y el que consume `fn_punto_en_poligono`):

```json
{
  "type": "Polygon",
  "coordinates": [
    [[-79.9750, 22.4000], [-79.9600, 22.4000], [-79.9600, 22.4130], [-79.9750, 22.4130]]
  ]
}
```

Contrato geométrico:
- Anillo exterior en `coordinates[0]`; `coordinates[1..]` = huecos (restan).
- El anillo **no** requiere repetir el primer punto al final (el editor cierra al guardar; el ray casting lo tolera; el `CHECK` no lo exige).
- Mínimo 3 puntos distintos por anillo (se valida en el editor y en `fn_punto_en_poligono` devolviendo `false` si no).
- Sólo `Polygon`; no `MultiPolygon` (si el negocio necesita multipolígono, se modela como varias filas de `zonas_tarifa` con la misma tarifa — ver §12).

> **Desvío D-01:** añado `zonas_tarifa.codigo text UNIQUE` en `032` para que el seed y los logs tengan identificador estable (MUN, FB, Z1…Z9). No renombra nada; es una columna extra nullable. Ver §12.

### 2.3 `muevete.tarifas_municipio` (fallback D4)

```sql
CREATE TABLE IF NOT EXISTS muevete.tarifas_municipio (
  id          bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  provincia   text    NOT NULL,
  municipio   text    NOT NULL,
  modo        text    NOT NULL DEFAULT 'fijo',
  monto_fijo  numeric NOT NULL DEFAULT 1500,
  precio_km   numeric NOT NULL DEFAULT 400,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT tarifas_municipio_pkey PRIMARY KEY (id),
  CONSTRAINT tarifas_municipio_unq UNIQUE (provincia, municipio),
  CONSTRAINT tarifas_municipio_modo_chk
    CHECK (modo IN ('fijo','fijo_mas_km','por_km')),
  CONSTRAINT tarifas_municipio_montos_chk CHECK (monto_fijo >= 0 AND precio_km >= 0)
);

CREATE TRIGGER trg_tarifas_municipio_updated_at
  BEFORE UPDATE ON muevete.tarifas_municipio
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
```

`fn_cotizar_viaje` lo usa cuando el **origen** no cae en ninguna zona (ver la fórmula en §4.1 y el cuerpo en §4.2). Si no hay fila para el municipio informado ni ninguna activa, usa `configuracion_tarifas.monto_fijo_fallback_municipio` / `precio_km_fallback`.

### 2.4 `muevete.configuracion_tarifas` (singleton)

```sql
CREATE TABLE IF NOT EXISTS muevete.configuracion_tarifas (
  id                          smallint     NOT NULL DEFAULT 1,
  moneda                      text         NOT NULL DEFAULT 'CUP',
  comision_pct                numeric(5,2) NOT NULL DEFAULT 15.00,
  tope_comision_viaje         numeric      NOT NULL DEFAULT 2500,
  recarga_pct                 numeric(5,2) NOT NULL DEFAULT 11.00,
  limite_deuda_efectivo       numeric      NOT NULL DEFAULT 1000,
  -- D6: si false, el chofer no puede quedar debajo de 0 (se bloquea al llegar a 0)
  permite_deuda               boolean      NOT NULL DEFAULT true,
  dias_max_deuda              integer      NOT NULL DEFAULT 7,
  precio_minimo_auto          numeric      NOT NULL DEFAULT 1500,
  precio_minimo_moto          numeric      NOT NULL DEFAULT 900,
  precio_minimo_microbus      numeric      NOT NULL DEFAULT 2250,
  precio_corto_auto           numeric      NOT NULL DEFAULT 1000,
  umbral_km_corto             numeric(4,1) NOT NULL DEFAULT 1.5,
  recargo_nocturno_pct        numeric(5,2) NOT NULL DEFAULT 20,
  ventana_nocturna_inicio     time         NOT NULL DEFAULT '22:00',
  ventana_nocturna_fin        time         NOT NULL DEFAULT '06:00',
  gracia_espera_min           integer      NOT NULL DEFAULT 3,
  tope_cobro_espera           numeric      NOT NULL DEFAULT 1200,
  redondeo_cup                integer      NOT NULL DEFAULT 50,
  prima_distancia_cup         numeric      NOT NULL DEFAULT 500,
  umbral_prima_distancia_km   numeric(4,1) NOT NULL DEFAULT 8,
  descuento_pago_wallet_pct   numeric(5,2) NOT NULL DEFAULT 5,
  -- D4: valores de respaldo cuando no hay fila en tarifas_municipio
  -- (§2.3 del plan los lista; §4.1 los omite → ver desvío D-13)
  monto_fijo_fallback_municipio numeric    NOT NULL DEFAULT 1500,
  precio_km_fallback            numeric    NOT NULL DEFAULT 400,
  precio_vigente_desde        timestamptz  NOT NULL DEFAULT now(),
  -- §8.6 del plan: flag de corte / rollback
  taxi_precio_fijo_activo     boolean      NOT NULL DEFAULT false,
  updated_at                  timestamptz  NOT NULL DEFAULT now(),

  CONSTRAINT configuracion_tarifas_pkey PRIMARY KEY (id),
  CONSTRAINT configuracion_tarifas_singleton CHECK (id = 1),
  CONSTRAINT configuracion_tarifas_comision_chk CHECK (comision_pct BETWEEN 0 AND 30),
  CONSTRAINT configuracion_tarifas_recarga_chk  CHECK (recarga_pct BETWEEN 0 AND 50),
  CONSTRAINT configuracion_tarifas_deuda_chk    CHECK (limite_deuda_efectivo BETWEEN 0 AND 5000),
  CONSTRAINT configuracion_tarifas_redondeo_chk CHECK (redondeo_cup IN (0,5,25,50,100)),
  CONSTRAINT configuracion_tarifas_fallback_chk CHECK (
       monto_fijo_fallback_municipio BETWEEN 0 AND 20000
   AND precio_km_fallback           BETWEEN 0 AND 5000),
  CONSTRAINT configuracion_tarifas_nocturno_chk CHECK (recargo_nocturno_pct BETWEEN 0 AND 50),
  CONSTRAINT configuracion_tarifas_espera_chk   CHECK (gracia_espera_min BETWEEN 0 AND 30
                                                       AND tope_cobro_espera >= 0)
);

INSERT INTO muevete.configuracion_tarifas (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TRIGGER trg_configuracion_tarifas_updated_at
  BEFORE UPDATE ON muevete.configuracion_tarifas
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
```

Parámetros de arranque: los de `PLAN-IMPLEMENTACION.md` §2.3. `limite_deuda_efectivo` arranca en **500** según D6 (lanzamiento) y se sube a 1 000 cuando el negocio lo confirme — es un `UPDATE`, no un deploy.

### 2.5 `muevete.vehicle_type.multiplicador_tarifa` (D2)

```sql
ALTER TABLE muevete.vehicle_type
  ADD COLUMN IF NOT EXISTS multiplicador_tarifa numeric NOT NULL DEFAULT 1;

ALTER TABLE muevete.vehicle_type
  ADD CONSTRAINT vehicle_type_multiplicador_chk
    CHECK (multiplicador_tarifa BETWEEN 0.1 AND 5) NOT VALID;
```

Seed (en `032`, idempotente por `lower(tipo)`):

```sql
UPDATE muevete.vehicle_type SET multiplicador_tarifa = v.mult
FROM (VALUES
  ('moto', 0.60), ('auto', 1.00), ('microbus', 1.50), ('camioneta', 1.20),
  ('minivan', 1.30), ('tuktuk', 0.50), ('bicicleta', 0.30)
) AS v(tipo, mult)
WHERE lower(muevete.vehicle_type.tipo) = v.tipo;
```

A partir de aquí, `precio_inside_sc` y `precio_km_default` quedan **DEPRECADOS** para taxi de pasajeros (la tarifa vive en zonas + multiplicador). No se borran: `vehicle_type_service.dart` los sigue leyendo para mostrarlos y hay datos históricos.

### 2.6 Columnas nuevas en `muevete.solicitudes_transporte`

```sql
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS driver_id         bigint REFERENCES muevete.drivers(id),
  ADD COLUMN IF NOT EXISTS aceptada_at       timestamptz,
  ADD COLUMN IF NOT EXISTS zona_id           bigint REFERENCES muevete.zonas_tarifa(id),
  ADD COLUMN IF NOT EXISTS tarifa_modo       text,
  ADD COLUMN IF NOT EXISTS precio_plataforma numeric,   -- lo que paga el cliente (CONGELADO)
  ADD COLUMN IF NOT EXISTS comision_pct      numeric,   -- % vigente al crear
  ADD COLUMN IF NOT EXISTS precio_chofer     numeric,   -- neto del chofer (CONGELADO)
  ADD COLUMN IF NOT EXISTS moneda            text DEFAULT 'CUP',
  ADD COLUMN IF NOT EXISTS tarifa_detalle    jsonb;     -- snapshot del desglose

-- Adiciones de trazabilidad (D-02): necesarias para la máquina de estados
-- del anexo 02 y para el panel del superadmin
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS completada_at      timestamptz,
  ADD COLUMN IF NOT EXISTS cancelada_at       timestamptz,
  ADD COLUMN IF NOT EXISTS motivo_cancelacion text,
  ADD COLUMN IF NOT EXISTS updated_at         timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS solicitudes_estado_created_idx
  ON muevete.solicitudes_transporte (estado, created_at DESC);
CREATE INDEX IF NOT EXISTS solicitudes_driver_idx
  ON muevete.solicitudes_transporte (driver_id);
CREATE INDEX IF NOT EXISTS solicitudes_zona_estado_idx
  ON muevete.solicitudes_transporte (zona_id, estado);
CREATE INDEX IF NOT EXISTS solicitudes_pendientes_idx
  ON muevete.solicitudes_transporte (created_at DESC)
  WHERE estado = 'pendiente';

CREATE TRIGGER trg_solicitudes_updated_at
  BEFORE UPDATE ON muevete.solicitudes_transporte
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
```

Constraints (`NOT VALID` para no fallar con filas históricas):

```sql
ALTER TABLE muevete.solicitudes_transporte
  ADD CONSTRAINT solicitudes_precio_plataforma_chk
    CHECK (precio_plataforma IS NULL OR precio_plataforma >= 0) NOT VALID,
  ADD CONSTRAINT solicitudes_comision_pct_chk
    CHECK (comision_pct IS NULL OR comision_pct BETWEEN 0 AND 30) NOT VALID,
  ADD CONSTRAINT solicitudes_tarifa_modo_chk
    CHECK (tarifa_modo IS NULL
           OR tarifa_modo IN ('fijo','fijo_mas_km','por_km')) NOT VALID;
```

> **Desvío D-02:** `completada_at`, `cancelada_at`, `motivo_cancelacion`, `updated_at` no están en §4.2 del plan pero son necesarios (doc 02 modela 11 estados con timestamps y el superadmin los muestra). Son columnas extra nullable/default; no renombran nada. Ver §12.

> **Semántica de `tarifa_modo`:** es el **snapshot del modo de la zona** con el que se cotizó (`fijo`, `fijo_mas_km`, `por_km`). Las filas históricas (negociación) quedan con `tarifa_modo = NULL` y `precio_plataforma = NULL`; no se les inventa un modo. El "modo legacy" se detecta por `precio_plataforma IS NULL`, no por un valor textual dentro de la columna.

### 2.7 Columnas nuevas en `muevete.viajes`

```sql
ALTER TABLE muevete.viajes
  ALTER COLUMN driver_id TYPE bigint;   -- era smallint; drivers.id es bigint (metadata-only)

ALTER TABLE muevete.viajes
  ADD COLUMN IF NOT EXISTS solicitud_id     bigint REFERENCES muevete.solicitudes_transporte(id),
  ADD COLUMN IF NOT EXISTS precio_plataforma numeric,
  ADD COLUMN IF NOT EXISTS precio_chofer     numeric,
  ADD COLUMN IF NOT EXISTS comision_pct      numeric,
  ADD COLUMN IF NOT EXISTS metodo_pago       text,
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS viajes_solicitud_id_uidx
  ON muevete.viajes (solicitud_id) WHERE solicitud_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS viajes_activos_idx
  ON muevete.viajes (driver_id) WHERE completado = false;

CREATE TRIGGER trg_viajes_updated_at
  BEFORE UPDATE ON muevete.viajes
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();
```

Se mantiene la semántica booleana de `viajes.estado` (`false` = yendo a recoger, `true` = en viaje) porque `active_ride_screen.dart` y `muevete_map_screen.dart` la leen así. El estado de negocio vive en `solicitudes_transporte.estado`.

### 2.8 Trigger de guarda del dinero

Activo desde H0; sólo bloquea cuando `taxi_precio_fijo_activo = true` (así las apps viejas siguen funcionando con el flag apagado y la app nueva no puede ser manipulada con el flag encendido):

```sql
CREATE OR REPLACE FUNCTION muevete.fn_solicitud_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
BEGIN
  -- Sesiones de RPC (SECURITY DEFINER) marcan la transacción
  IF coalesce(current_setting('muevete.rpc', true), 'off') = 'on' THEN
    RETURN NEW;
  END IF;

  -- Flag apagado = modo legacy: no se estorba a las apps viejas
  IF NOT coalesce((SELECT taxi_precio_fijo_activo
                     FROM muevete.configuracion_tarifas WHERE id = 1), false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'usar_fn_crear_solicitud' USING ERRCODE = '42501';
  END IF;

  IF NEW.precio_plataforma IS DISTINCT FROM OLD.precio_plataforma
     OR NEW.comision_pct    IS DISTINCT FROM OLD.comision_pct
     OR NEW.precio_chofer   IS DISTINCT FROM OLD.precio_chofer
     OR NEW.tarifa_detalle  IS DISTINCT FROM OLD.tarifa_detalle
     OR NEW.zona_id         IS DISTINCT FROM OLD.zona_id
     OR NEW.driver_id       IS DISTINCT FROM OLD.driver_id
     OR NEW.precio_oferta   IS DISTINCT FROM OLD.precio_oferta
  THEN
    RAISE EXCEPTION 'campos_de_tarifa_inmutables' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_solicitud_guarda
  BEFORE INSERT OR UPDATE ON muevete.solicitudes_transporte
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_solicitud_guarda();
```

> **Resuelve una tensión del plan:** el criterio de H0 dice "un cliente no puede INSERT/UPDATE de precio", pero §4.3 dice que las revocaciones van en el cutover (H5). Con este trigger ambas cosas son ciertas: en H0 (flag apagado) nada cambia; al encender el flag el dinero es inmutable aun antes de aplicar `038`.

### 2.9 Seed Santa Clara (`032`)

```sql
BEGIN;

-- Configuración global (§2.3 del plan)
UPDATE muevete.configuracion_tarifas SET
  moneda = 'CUP',
  comision_pct = 15.00,
  tope_comision_viaje = 2500,
  recarga_pct = 11.00,
  limite_deuda_efectivo = 1000,    -- plan §2.3: 500 las primeras semanas, 1000 después
  permite_deuda = true,            -- D6; false = el chofer no puede quedar negativo
  dias_max_deuda = 7,
  precio_minimo_auto = 1500,
  precio_minimo_moto = 900,
  precio_minimo_microbus = 2250,
  precio_corto_auto = 1000,
  umbral_km_corto = 1.5,
  recargo_nocturno_pct = 20,
  ventana_nocturna_inicio = '22:00',
  ventana_nocturna_fin = '06:00',
  gracia_espera_min = 3,
  tope_cobro_espera = 1200,
  redondeo_cup = 50,
  prima_distancia_cup = 500,
  umbral_prima_distancia_km = 8,
  descuento_pago_wallet_pct = 5,
  monto_fijo_fallback_municipio = 1500,
  precio_km_fallback = 400,
  taxi_precio_fijo_activo = false   -- el corte es una decisión aparte (H6)
WHERE id = 1;

-- Fallback municipal (D4)
INSERT INTO muevete.tarifas_municipio (provincia, municipio, modo, monto_fijo, precio_km, activo)
VALUES ('Villa Clara', 'Santa Clara', 'fijo', 1500, 400, true)
ON CONFLICT (provincia, municipio) DO UPDATE
  SET modo = excluded.modo, monto_fijo = excluded.monto_fijo,
      precio_km = excluded.precio_km, activo = excluded.activo;

-- Multiplicadores D2 para los 7 tipos pasajeros
UPDATE muevete.vehicle_type SET multiplicador_tarifa = v.mult
FROM (VALUES ('moto',0.60),('auto',1.00),('microbus',1.50),('camioneta',1.20),
             ('minivan',1.30),('tuktuk',0.50),('bicicleta',0.30)) AS v(tipo, mult)
WHERE lower(muevete.vehicle_type.tipo) = v.tipo;

-- MUN: rectángulo aproximado del municipio (el real lo redibuja el superadmin)
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo, monto_fijo, precio_km,
   prioridad, activo)
VALUES (
  'MUN', 'Municipio Santa Clara', 'Villa Clara', 'Santa Clara',
  jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
    jsonb_build_array(
      jsonb_build_array(-80.050, 22.300), jsonb_build_array(-79.850, 22.300),
      jsonb_build_array(-79.850, 22.550), jsonb_build_array(-80.050, 22.550)
    ))),
  'fijo', 1500, 400, 0, true
)
ON CONFLICT (codigo) DO NOTHING;

-- FB: fallback geométrico opcional (inactivo; D4 se resuelve con tarifas_municipio)
INSERT INTO muevete.zonas_tarifa
  (codigo, nombre, provincia, municipio, geometria, modo, monto_fijo, precio_km,
   prioridad, activo)
VALUES (
  'FB', 'Fallback provincial', 'Villa Clara', NULL,
  jsonb_build_object('type','Polygon','coordinates', jsonb_build_array(
    jsonb_build_array(
      jsonb_build_array(-80.600, 21.900), jsonb_build_array(-79.100, 21.900),
      jsonb_build_array(-79.100, 22.900), jsonb_build_array(-80.600, 22.900)
    ))),
  'fijo', 1500, 400, -10, false
)
ON CONFLICT (codigo) DO NOTHING;

-- Z1–Z9: borradores inactivos (el negocio los dibuja/activa en el editor)
-- (se insertan con prioridad 100 y activo=false; ver §12 nota sobre codigo)
COMMIT;
```

> **Ninguna zona interna se activa sin que el superadmin la dibuje** (plan §2.4). MUN arranca activo porque reproduce el comportamiento actual (círculo de 2,53 km → ahora rectángulo municipal aproximado); si el negocio no quiere cobrar 1 500 fuera del casco, se deja MUN inactivo y todo cae al fallback municipal hasta que se dibujen Z1–Z9.

### 2.10 Índices únicos de invariantes (H5, con pre-chequeo)

No van en `030` porque hay datos históricos que pueden duplicar. Pre-chequeo y creación en `038`:

```sql
-- Un chofer no puede tener 2 viajes aceptados a la vez
SELECT driver_id, array_agg(id ORDER BY created_at) AS ids
FROM muevete.solicitudes_transporte
WHERE estado = 'aceptada' AND driver_id IS NOT NULL
GROUP BY driver_id HAVING count(*) > 1;

-- Un cliente no puede tener 2 solicitudes abiertas
SELECT user_id, array_agg(id ORDER BY created_at) AS ids
FROM muevete.solicitudes_transporte
WHERE estado IN ('pendiente','aceptada')
GROUP BY user_id HAVING count(*) > 1;

CREATE UNIQUE INDEX IF NOT EXISTS solicitudes_driver_activa_uidx
  ON muevete.solicitudes_transporte (driver_id)
  WHERE driver_id IS NOT NULL AND estado = 'aceptada';
CREATE UNIQUE INDEX IF NOT EXISTS solicitudes_user_abierta_uidx
  ON muevete.solicitudes_transporte (user_id)
  WHERE estado IN ('pendiente','aceptada');
```

Si los pre-chequeos devuelven filas: expirar/cancelar la más antigua antes del cutover (script de §9.4). No crear los índices a ciegas.

### 2.11 `down` (reversibilidad, criterio H0)

```sql
-- 031_down.sql (documentado, no ejecutado en despliegue normal)
-- NOTA: 030 es el baseline de sincronización (030_baseline_sync_produccion.sql);
-- el down de las migraciones del taxi empieza en 031.
DROP TRIGGER IF EXISTS trg_solicitud_guarda ON muevete.solicitudes_transporte;
DROP FUNCTION IF EXISTS muevete.fn_solicitud_guarda();
DROP TRIGGER IF EXISTS trg_viajes_updated_at ON muevete.viajes;
ALTER TABLE muevete.viajes
  DROP COLUMN IF EXISTS solicitud_id, DROP COLUMN IF EXISTS precio_plataforma,
  DROP COLUMN IF EXISTS precio_chofer, DROP COLUMN IF EXISTS comision_pct,
  DROP COLUMN IF EXISTS metodo_pago, DROP COLUMN IF EXISTS updated_at;
ALTER TABLE muevete.viajes ALTER COLUMN driver_id TYPE smallint;  -- sólo si sigue cabiendo
ALTER TABLE muevete.solicitudes_transporte
  DROP COLUMN IF EXISTS driver_id, DROP COLUMN IF EXISTS aceptada_at,
  DROP COLUMN IF EXISTS zona_id, DROP COLUMN IF EXISTS tarifa_modo,
  DROP COLUMN IF EXISTS precio_plataforma, DROP COLUMN IF EXISTS comision_pct,
  DROP COLUMN IF EXISTS precio_chofer, DROP COLUMN IF EXISTS moneda,
  DROP COLUMN IF EXISTS tarifa_detalle, DROP COLUMN IF EXISTS completada_at,
  DROP COLUMN IF EXISTS cancelada_at, DROP COLUMN IF EXISTS motivo_cancelacion,
  DROP COLUMN IF EXISTS updated_at;
ALTER TABLE muevete.vehicle_type DROP COLUMN IF EXISTS multiplicador_tarifa;
DROP TABLE IF EXISTS muevete.configuracion_tarifas;
DROP TABLE IF EXISTS muevete.tarifas_municipio;
DROP TABLE IF EXISTS muevete.zonas_tarifa;
```

> El `down` **no** es el rollback del negocio (ese es apagar `taxi_precio_fijo_activo`, §9.5). Es la salida de emergencia si el esquema queda inservible.

---

## 3. Evaluación de zona (sin PostGIS)

### 3.1 Decisión y justificación

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **PostGIS** (`geometry(Polygon,4326)` + `ST_Contains` + GiST) | Preciso, `ST_IsValid`, huecos y multipolígonos gratis | **No instalado** (verificado: `installed_version=null`, 0 `CREATE EXTENSION` en el repo). Requiere cambio de infraestructura no versionado, impacta `search_path`, backups y entornos. | **Descartada como base.** Prevista como fase 2 (§3.6). |
| **Point-in-polygon PL/pgSQL sobre `jsonb`** | Cero dependencias, versionable, determinista, testeable, mismo formato que dibuja/guarda el editor | Ray casting propio, O(n) por anillo; hay que validar anillos | **Elegida** |
| Círculo centro+radio | Trivial | No modela barrios ni municipios | No aplica: D1 exige polígono |
| Municipio textual | Ya existe en `drivers`/`users` | No hay lat/lon → municipio en servidor | Sólo metadato (fallback `tarifas_municipio`) |

**Justificación cuantitativa:** con decenas de zonas (el seed trae 11) y anillos de 20–200 vértices, el coste por cotización es despreciable (microsegundos). El riesgo real es la **autoría** de la geometría, y `jsonb` GeoJSON es exactamente lo que produce `flutter_map`. Añadir PostGIS no compra nada hoy y añade un requisito de infraestructura.

### 3.2 `fn_punto_en_poligono` (RPC #1 del contrato)

```sql
-- 032_taxi_geo_y_cotizacion.sql
-- Helper interno (no se GRANT a authenticated): ray casting sobre un anillo
CREATE OR REPLACE FUNCTION muevete.fn_punto_en_anillo(
  p_lat double precision,
  p_lon double precision,
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
       AND (p_lon < (v_xj - v_xi) * (p_lat - v_yi) / nullif(v_yj - v_yi, 0) + v_xi)
    THEN
      v_inside := NOT v_inside;
    END IF;

    v_j := v_i;
  END LOOP;

  RETURN v_inside;
END;
$$;

-- RPC #1: GeoJSON Polygon (con huecos)
CREATE OR REPLACE FUNCTION muevete.fn_punto_en_poligono(
  p_lat     double precision,
  p_lon     double precision,
  p_geojson jsonb
) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
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

  -- fuera del anillo exterior → fuera del polígono
  IF NOT muevete.fn_punto_en_anillo(p_lat, p_lon, v_anillos -> 0) THEN
    RETURN false;
  END IF;

  -- dentro de un hueco → fuera del polígono
  v_n := jsonb_array_length(v_anillos);
  FOR v_i IN 1 .. v_n - 1 LOOP
    IF muevete.fn_punto_en_anillo(p_lat, p_lon, v_anillos -> v_i) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$;
```

### 3.3 `fn_zona_de_punto` (RPC #2)

```sql
-- Distancia geodésica en km (helper interno)
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

-- RPC #2: zona activa de MAYOR prioridad que contiene el punto (0 o 1 fila)
CREATE OR REPLACE FUNCTION muevete.fn_zona_de_punto(
  p_lat double precision,
  p_lon double precision,
  p_at  timestamptz DEFAULT now()
) RETURNS SETOF muevete.zonas_tarifa
LANGUAGE sql STABLE PARALLEL SAFE
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
```

**Resolución de solapes.** Gana la de **mayor `prioridad`** (contrato §4.1). A igual prioridad gana la de menor `id` (determinista y estable). Prioridades recomendadas para el editor (se muestran como ayuda):

| Tipo de zona | Prioridad |
|---|---|
| Zona especial (aeropuerto, terminal, UCLV, hospital) | 200 |
| Barrio / reparto interno | 150 |
| Zona interna amplia (Centro, Condado, Virginia) | 100 |
| Periferia / circunvalación | 50 |
| Municipio (MUN) | 0 |
| Fallback provincial (FB) | −10 |

### 3.4 Validación de geometría en el editor (no en la BD)

La BD valida forma (`jsonb_typeof = 'array'`) y coherencia de tarifa. La **validez geométrica fina** se valida en el editor, donde el usuario puede corregir:

- ≥ 3 vértices distintos.
- Sin auto-intersecciones (segmentos no adyacentes).
- Coordenadas dentro de Cuba: `lat ∈ [19.0, 24.0]`, `lon ∈ [-86.0, -73.0]`.
- Área mínima (evitar un polígono degenerado): > 1 000 m².
- Aviso (no bloqueo) si se solapa con otra zona: "Se solapa con Z1 · Centro; se resolverá por prioridad (mayor gana)".

Implementación en Dart en `_ZonaEditorState._validarGeometria()` (§8.3). Se guarda igual aunque haya solape (el solape es legal, la prioridad lo resuelve) y se avisa en el snackbar.

### 3.5 Bonus: helper de zona del chofer

`fn_viajes_disponibles` y `fn_tomar_viaje` necesitan resolver la zona actual del chofer. No se crea RPC pública: se usa `fn_zona_de_punto(place.latitude, place.longitude)` dentro de cada función. Si en el futuro se necesita para RLS, se añade:

```sql
CREATE OR REPLACE FUNCTION muevete.fn_zona_de_mi_place()
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
  SELECT z.id
  FROM muevete.place p
  CROSS JOIN LATERAL muevete.fn_zona_de_punto(p.latitude, p.longitude) z
  WHERE p.driver = muevete.get_my_driver_id()
  LIMIT 1;
$$;
```

### 3.6 Camino a PostGIS (fase 2, fuera de este plan)

`fn_punto_en_poligono` es el único punto de acoplamiento. Cuando se habilite:

```sql
-- FASE 2 (no ejecutar ahora)
-- CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions;
-- ALTER TABLE muevete.zonas_tarifa ADD COLUMN geom extensions.geometry(Polygon,4326)
--   GENERATED ALWAYS AS (extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON(geometria::text),4326)) STORED;
-- CREATE INDEX zonas_tarifa_geom_gist ON muevete.zonas_tarifa USING gist (geom);
-- -- y reemplazar el cuerpo de fn_punto_en_poligono por:
-- --   SELECT extensions.ST_Covers(z_generada, punto) ...
```

Requisitos: ventana de mantenimiento, `CREATE EXTENSION` con el rol de migraciones, re-ejecutar la suite SQL y **mantener la firma** de `fn_punto_en_poligono` / `fn_zona_de_punto` para no tocar apps.

---

## 4. Cálculo de la tarifa

### 4.1 Fórmula (implementación literal de `PLAN-IMPLEMENTACION.md` §2.2)

```
zona_origen  = fn_zona_de_punto(lat_o, lon_o, at)    -- mayor prioridad
zona_destino = fn_zona_de_punto(lat_d, lon_d, at)
si zona_origen IS NULL → regla de tarifas_municipio(provincia, municipio del origen) (D4)
                          si no hay fila → config.monto_fijo_fallback_municipio / precio_km_fallback

modo = zona_origen.modo (o municipio.modo)
km   = distancia de ruta (p_km, que envía routing_service) — NO haversine si viene

base = CASE modo
   'fijo'        → si zona_destino = zona_origen: monto_fijo
                   si el viaje sale de la zona:   km_total × precio_km
   'fijo_mas_km' → monto_fijo + km_total × precio_km
   'por_km'      → km_total × precio_km
   (fallback municipal: sin lógica "dentro", aplica el modo con sus valores)

precio = base × multiplicador_tarifa(tipo)               -- D2
precio = max(precio, precio_minimo_<tipo>)               -- piso por tipo
si tipo='auto' y km < umbral_km_corto: precio = min(precio, precio_corto_auto)

recargos:
  nocturno   = precio × recargo_nocturno_pct/100          -- 22:00–06:00 America/Havana
  prima_dist = prima_distancia_cup si km > umbral_prima_distancia_km
  espera     = se cobra al cerrar (fn_completar_viaje), no aquí
precio = precio + nocturno + prima_dist

redondeo: precio = ceil(precio / redondeo_cup) × redondeo_cup      -- HACIA ARRIBA

comisión:
  comision_monto = round(precio × comision_pct/100, 2)
  si tope_comision_viaje > 0: comision_monto = min(comision_monto, tope_comision_viaje)
  precio_chofer  = precio - comision_monto

snapshot: precio_plataforma, comision_pct, precio_chofer, zona_id,
          tarifa_modo, moneda, tarifa_detalle (jsonb completo)
```

Decisiones explícitas del contrato:
- **Manda el origen** (plan §2.2, R5 implícito): la zona del origen decide la regla; la del destino sólo se usa para "¿está dentro de la misma zona?".
- **Multiplicador** sale de `vehicle_type.multiplicador_tarifa` (columna nueva), no de la zona.
- **Piso por tipo**: sólo `auto`, `moto`, `microbus` tienen mínimo configurado. Para `camioneta`, `minivan`, `tuktuk`, `bicicleta` **no hay piso** (su precio es `base × multiplicador`). Documentado en §12 (D-07).
- **`precio_corto_auto`** es un **tope** para viajes cortos de auto (1 000 si < 1,5 km). Se aplica después del piso.
- **Nocturno** se calcula sobre el precio ya multiplicado y con piso, y **no** se aplica a la espera (la espera se cobra aparte al cerrar).
- **Redondeo hacia arriba** a múltiplos de `redondeo_cup` (50 por defecto).
- **`descuento_pago_wallet_pct`** está en configuración pero **no se aplica** en `fn_cotizar_viaje` (no está en §2.2). Se reserva para H5; ver §12 (D-08).

### 4.2 `fn_cotizar_viaje` (RPC #3) — cuerpo completo

```sql
CREATE OR REPLACE FUNCTION muevete.fn_cotizar_viaje(
  p_lat_o      double precision,
  p_lon_o      double precision,
  p_lat_d      double precision,
  p_lon_d      double precision,
  p_id_tipo    bigint,
  p_at         timestamptz DEFAULT now(),
  p_km         double precision DEFAULT NULL,
  p_provincia  text DEFAULT NULL,
  p_municipio  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
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
    -- Anti-manipulación (ver §12 D-05): nunca menos que la recta,
    -- nunca más que 2× recta + 1 km
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

  -- ── Válvula de viaje corto (auto) ────────────────────────────────────
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

  -- ── Redondeo hacia arriba a múltiplos de redondeo_cup ────────────────
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

  -- ── Snapshot del desglose (lo que se guarda en tarifa_detalle) ───────
  v_detalle := jsonb_build_object(
    'zona_origen_id',      v_zona_o.id,
    'zona_origen_nombre',  v_zona_o.nombre,
    'zona_destino_id',     v_zona_d.id,
    'zona_destino_nombre', v_zona_d.nombre,
    'dentro_de_zona',      v_dentro,
    'fallback_municipio',  v_zona_o.id IS NULL,
    'municipio_aplicado',  CASE WHEN v_zona_o.id IS NULL THEN v_muni.municipio END,
    'modo',                v_modo,
    'monto_fijo',          v_monto_fijo,
    'precio_km',           v_precio_km,
    'km_lineal',           round(v_km_lineal::numeric, 3),
    'km_total',            v_km,
    'km_fuente',           v_km_fuente,
    'base',                round(v_base, 2),
    'multiplicador_tipo',  v_mult,
    'tipo_vehiculo',       v_tipo,
    'precio_minimo',       v_minimo,
    'precio_corto_aplicado', v_corto,
    'es_nocturno',         v_nocturno,
    'recargo_nocturno',    v_rec_noct,
    'recargo_prima_distancia', v_rec_prima,
    'precio_antes_redondeo', round(v_pre_redondeo, 2),
    'redondeo_cup',        cfg.redondeo_cup,
    'precio_plataforma',   v_precio
  );

  RETURN jsonb_build_object(
    'precio_plataforma', v_precio,
    'moneda',            cfg.moneda,
    'comision_pct',      cfg.comision_pct,
    'comision_monto',    v_comision,
    'precio_chofer',     v_chofer,
    'zona_id',           v_zona_o.id,
    'zona_nombre',       coalesce(v_zona_o.nombre, 'Fuera de zona'),
    'tarifa_modo',       v_modo,
    'km_total',          v_km,
    'km_fuente',         v_km_fuente,
    'tipo_vehiculo',     v_tipo,
    'multiplicador_tipo', v_mult,
    'es_nocturno',       v_nocturno,
    'precio_corto',      v_corto,
    'detalle',           v_detalle,
    'precio_vigente_desde', cfg.precio_vigente_desde,
    'calculado_at',      p_at
  );
END;
$$;
```

### 4.3 Ejemplos numéricos (contrato de pruebas de H0)

Con la configuración por defecto y MUN (`modo='fijo'`, 1 500 + 400/km) activo:

| Caso | Datos | precio_plataforma | comisión 15 % | precio_chofer |
|---|---|---|---|---|
| Auto dentro de MUN (3,2 km) | origen y destino dentro | 1 500 → redondeo 50 → **1 500** | 225,00 | 1 275,00 |
| Auto que sale de MUN (12 km) | destino fuera | 12 × 400 = 4 800 → **4 800** | 720,00 | 4 080,00 |
| Auto 1 km (corto) | dentro, 1 km | 1 500 → cap corto → **1 000** | 150,00 | 850,00 |
| Moto dentro (3,2 km) | ×0,60 | 900 → piso moto 900 → **900** | 135,00 | 765,00 |
| Microbús dentro | ×1,50 | 2 250 → piso 2 250 → **2 250** | 337,50 | 1 912,50 |
| Camioneta dentro (3,2 km) | ×1,20, sin piso | **1 800** | 270,00 | 1 530,00 |
| Bicicleta dentro | ×0,30, sin piso | **450** | 67,50 | 382,50 |
| Nocturno 22:30 (auto, 3,2 km) | +20 % | 1 800 → **1 800** | 270,00 | 1 530,00 |
| Fuera de zona (fallback municipal) | ambas fuera | fallback 1 500 → **1 500** | 225,00 | 1 275,00 |
| Largo > 8 km (auto, 10 km) | + prima 500 | 4 000 + 500 = 4 500 → **4 500** | 675,00 | 3 825,00 |
| Largo con tope de comisión | 44 km × 450 = 19 800 | tope comisión 2 500 → **2 500** | 2 500,00 | 17 300,00 |

> Con `redondeo_cup = 50` y `ceil`, 4 800 ya es múltiplo; 1 502 → 1 550. Los 14 casos exactos de referencia están en `03-modelo-economico.md` §8.3 y **son el criterio de aceptación de H0**.

---

## 5. Las 9 RPCs: firma y cuerpo

Reglas comunes a las 9:

```sql
-- patrón obligatorio en cada definición
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = muevete, pg_temp
-- y al inicio del cuerpo, en las que escriben dinero:
--   PERFORM set_config('muevete.rpc', 'on', true);
-- Permisos:
REVOKE ALL ON FUNCTION muevete.<fn>(<firma>) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.<fn>(<firma>) TO authenticated;
```

Tabla resumen (nombres y firmas del contrato):

| # | RPC | Firma real | Devuelve | Escribe |
|---|---|---|---|---|
| 1 | `fn_punto_en_poligono` | `(p_lat float8, p_lon float8, p_geojson jsonb)` | `boolean` | no |
| 2 | `fn_zona_de_punto` | `(p_lat float8, p_lon float8, p_at timestamptz DEFAULT now())` | `SETOF zonas_tarifa` (0/1) | no |
| 3 | `fn_cotizar_viaje` | `(p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo, p_at DEFAULT now(), p_km DEFAULT NULL, p_provincia DEFAULT NULL, p_municipio DEFAULT NULL)` | `jsonb` | no |
| 4 | `fn_crear_solicitud` | `(p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo, p_dir_o, p_dir_d, p_km, p_metodo_pago, p_provincia DEFAULT NULL, p_municipio DEFAULT NULL)` | `solicitudes_transporte` | sí |
| 5 | `fn_viajes_disponibles` | `(p_lat DEFAULT NULL, p_lon DEFAULT NULL, p_limite DEFAULT 30)` | `SETOF jsonb` | no |
| 6 | `fn_tomar_viaje` | `(p_solicitud_id bigint)` | `jsonb` | sí |
| 7 | `fn_completar_viaje` | `(p_viaje_id bigint, p_espera_min integer DEFAULT NULL)` | `jsonb` | sí |
| 8 | `fn_cancelar_solicitud` | `(p_solicitud_id bigint, p_motivo text DEFAULT NULL)` | `jsonb` | sí |
| 9 | `fn_recargar_wallet` | `(p_metodo text, p_monto numeric, p_evidencia text DEFAULT NULL)` | `jsonb` | sí |

> Los parámetros con `DEFAULT` al final son **aditivos** al contrato (el plan fija el nombre y la responsabilidad, no prohíbe parámetros opcionales). Listados en §12.

### 5.1 (1) `fn_punto_en_poligono` y (2) `fn_zona_de_punto`

Cuerpos completos en §3.2 y §3.3. Grants:

```sql
REVOKE ALL ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_punto_en_poligono(double precision, double precision, jsonb) TO authenticated;

REVOKE ALL ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_zona_de_punto(double precision, double precision, timestamptz) TO authenticated;
```

### 5.2 (3) `fn_cotizar_viaje`

Cuerpo completo en §4.2. Grants:

```sql
REVOKE ALL ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cotizar_viaje(
  double precision, double precision, double precision, double precision,
  bigint, timestamptz, double precision, text, text) TO authenticated;
```

**No escribe nada** (criterio del contrato). Es la misma función que usa el simulador del superadmin y la que alimenta el preview del cliente: **un solo camino de cálculo**, por eso el precio mostrado coincide con el cobrado.

### 5.3 (4) `fn_crear_solicitud`

```sql
CREATE OR REPLACE FUNCTION muevete.fn_crear_solicitud(
  p_lat_o        double precision,
  p_lon_o        double precision,
  p_lat_d        double precision,
  p_lon_d        double precision,
  p_id_tipo      bigint,
  p_dir_o        text,
  p_dir_d        text,
  p_km           double precision,
  p_metodo_pago  text,
  p_provincia    text DEFAULT NULL,
  p_municipio    text DEFAULT NULL
) RETURNS muevete.solicitudes_transporte
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  cfg       muevete.configuracion_tarifas%ROWTYPE;
  v_cot     jsonb;
  v_row     muevete.solicitudes_transporte%ROWTYPE;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT coalesce(cfg.taxi_precio_fijo_activo, false) THEN
    RAISE EXCEPTION 'servicio_en_mantenimiento' USING ERRCODE = 'P0003';
  END IF;

  IF p_metodo_pago NOT IN ('efectivo', 'wallet') THEN
    RAISE EXCEPTION 'metodo_pago_invalido: %', p_metodo_pago USING ERRCODE = 'P0004';
  END IF;

  -- Una sola solicitud abierta por cliente (backstop del índice de §2.10)
  IF EXISTS (
    SELECT 1
      FROM muevete.solicitudes_transporte s
     WHERE s.user_id = v_uid
       AND s.estado IN ('pendiente','aceptada')
       AND (s.expires_at IS NULL OR s.expires_at > now())
  ) THEN
    RAISE EXCEPTION 'solicitud_activa_existente' USING ERRCODE = 'P0005';
  END IF;

  -- SIEMPRE recotiza en servidor: el precio del cliente se ignora
  v_cot := muevete.fn_cotizar_viaje(
             p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo,
             now(), p_km, p_provincia, p_municipio);

  v_cot := jsonb_set(v_cot, '{origen_calculo}', '"fn_crear_solicitud"', true);

  INSERT INTO muevete.solicitudes_transporte (
    user_id, lat_origen, lon_origen, lat_destino, lon_destino,
    tipo_vehiculo, id_tipo_vehiculo,
    precio_oferta,                -- espejo legacy (apps viejas / reportes)
    precio_plataforma,            -- autoritativo (CONGELADO)
    comision_pct, precio_chofer, moneda,
    estado, tarifa_modo, tarifa_detalle,
    direccion_origen, direccion_destino, distancia_km,
    zona_id, metodo_pago, expires_at
  ) VALUES (
    v_uid, p_lat_o, p_lon_o, p_lat_d, p_lon_d,
    lower(v_cot ->> 'tipo_vehiculo'), p_id_tipo,
    (v_cot ->> 'precio_plataforma')::numeric,
    (v_cot ->> 'precio_plataforma')::numeric,
    (v_cot ->> 'comision_pct')::numeric,
    (v_cot ->> 'precio_chofer')::numeric,
    coalesce(cfg.moneda, 'CUP'),
    'pendiente', v_cot ->> 'tarifa_modo', v_cot,
    p_dir_o, p_dir_d, p_km,
    (v_cot ->> 'zona_id')::bigint,
    p_metodo_pago,
    now() + interval '15 minutes'      -- TTL (ver §12 D-09)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_crear_solicitud(
  double precision, double precision, double precision, double precision,
  bigint, text, text, double precision, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_crear_solicitud(
  double precision, double precision, double precision, double precision,
  bigint, text, text, double precision, text, text, text) TO authenticated;
```

> El `INSERT` dispara `solicitudes_push` (Edge Function externa). El payload ya incluye `zona_id`, `id_tipo_vehiculo`, `precio_plataforma` — son los tres filtros/valores que necesita el fan-out por zona (§9.6).

### 5.4 (5) `fn_viajes_disponibles`

```sql
CREATE OR REPLACE FUNCTION muevete.fn_viajes_disponibles(
  p_lat    double precision DEFAULT NULL,
  p_lon    double precision DEFAULT NULL,
  p_limite integer DEFAULT 30
) RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_driver       bigint := muevete.get_my_driver_id();
  v_online       boolean := false;
  v_kyc          boolean := false;
  v_lat          double precision;
  v_lon          double precision;
  v_zona_chofer  bigint;
  v_tipo_chofer  bigint;
  v_activo       boolean := false;
  v_saldo        numeric := 0;
  v_deuda_tope   numeric := 0;
  v_permite_deuda boolean := true;
BEGIN
  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'no_es_chofer' USING ERRCODE = '28000';
  END IF;

  SELECT coalesce(d.kyc, false), veh.id_tipo_vehiculo
    INTO v_kyc, v_tipo_chofer
    FROM muevete.drivers d
    LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
   WHERE d.id = v_driver;

  SELECT coalesce(p.estado, false), p.latitude, p.longitude
    INTO v_online, v_lat, v_lon
    FROM muevete.place p
   WHERE p.driver = v_driver;
  -- SELECT INTO con 0 filas asigna NULL: normalizar (bug clásico de plpgsql)
  v_online := coalesce(v_online, false);
  v_kyc    := coalesce(v_kyc, false);

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
    v_lat := p_lat;
    v_lon := p_lon;
  END IF;

  IF v_lat IS NOT NULL THEN
    SELECT z.id INTO v_zona_chofer
      FROM muevete.fn_zona_de_punto(v_lat, v_lon, now()) z;
  END IF;

  SELECT coalesce(w.balance, 0) INTO v_saldo
    FROM muevete.wallet_drivers w WHERE w.driver_id = v_driver;
  v_saldo := coalesce(v_saldo, 0);

  SELECT coalesce(c.permite_deuda, true), coalesce(c.limite_deuda_efectivo, 0)
    INTO v_permite_deuda, v_deuda_tope
    FROM muevete.configuracion_tarifas c WHERE c.id = 1;

  SELECT EXISTS (
    SELECT 1 FROM muevete.solicitudes_transporte s
     WHERE s.driver_id = v_driver AND s.estado = 'aceptada'
  ) INTO v_activo;

  RETURN QUERY
  SELECT jsonb_build_object(
    'solicitud_id',        s.id,
    'zona_id',             s.zona_id,
    'zona_nombre',         z.nombre,
    'tarifa_modo',         s.tarifa_modo,
    'tipo_vehiculo',       s.tipo_vehiculo,
    'id_tipo_vehiculo',    s.id_tipo_vehiculo,
    'lat_origen',          s.lat_origen,
    'lon_origen',          s.lon_origen,
    'lat_destino',         s.lat_destino,
    'lon_destino',         s.lon_destino,
    'direccion_origen',    s.direccion_origen,
    'direccion_destino',   s.direccion_destino,
    'km',                  coalesce(s.distancia_km,
                                    (s.tarifa_detalle ->> 'km_total')::numeric),
    'precio_plataforma',   s.precio_plataforma,
    'comision_pct',        s.comision_pct,
    'comision_monto',      round(s.precio_plataforma * coalesce(s.comision_pct,0) / 100.0, 2),
    'precio_chofer',       s.precio_chofer,
    'moneda',              coalesce(s.moneda, 'CUP'),
    'distancia_a_origen_km',
        round(muevete.fn_haversine_km(v_lat, v_lon, s.lat_origen, s.lon_origen)::numeric, 2),
    'desglose',            s.tarifa_detalle,
    'created_at',          s.created_at,
    'expires_at',          s.expires_at,
    'deuda_disponible',    round((coalesce(v_saldo,0) + (CASE WHEN coalesce(v_permite_deuda,true) THEN coalesce(v_deuda_tope,0) ELSE 0 END))
                                 - round(s.precio_plataforma * coalesce(s.comision_pct,0) / 100.0, 2), 2),
    'puede_tomar',         (coalesce(v_online, false) AND coalesce(v_kyc, false)
                            AND NOT v_activo
                            AND (s.id_tipo_vehiculo IS NULL
                                 OR s.id_tipo_vehiculo IS NOT DISTINCT FROM v_tipo_chofer)
                            AND (coalesce(v_saldo,0) + (CASE WHEN coalesce(v_permite_deuda,true) THEN coalesce(v_deuda_tope,0) ELSE 0 END))
                                >= round(s.precio_plataforma * coalesce(s.comision_pct,0) / 100.0, 2)),
    'motivo_bloqueo',      CASE
                              WHEN NOT coalesce(v_online, false) THEN 'chofer_offline'
                              WHEN NOT coalesce(v_kyc, false)    THEN 'chofer_no_aprobado'
                              WHEN v_activo     THEN 'ya_tienes_un_viaje'
                              WHEN s.id_tipo_vehiculo IS NOT NULL
                                   AND s.id_tipo_vehiculo IS DISTINCT FROM v_tipo_chofer
                                                THEN 'tipo_vehiculo_incompatible'
                              WHEN (coalesce(v_saldo,0) + (CASE WHEN coalesce(v_permite_deuda,true) THEN coalesce(v_deuda_tope,0) ELSE 0 END))
                                   < round(s.precio_plataforma * coalesce(s.comision_pct,0) / 100.0, 2)
                                                THEN 'limite_de_deuda_alcanzado'
                              ELSE NULL
                            END
  )
  FROM muevete.solicitudes_transporte s
  LEFT JOIN muevete.zonas_tarifa z ON z.id = s.zona_id
  WHERE s.estado = 'pendiente'
    AND s.driver_id IS NULL
    -- Excluye filas legacy (negociación): sólo viajes con precio congelado
    AND s.precio_plataforma IS NOT NULL
    AND (s.expires_at IS NULL OR s.expires_at > now())
    -- El origen debe caer en la zona donde está el chofer (D-lead / plan §5)
    AND ((v_zona_chofer IS NOT NULL AND s.zona_id = v_zona_chofer)
         OR (v_zona_chofer IS NULL AND s.zona_id IS NULL))
  ORDER BY (v_lat IS NULL),                                    -- sin posición, primero
           muevete.fn_haversine_km(v_lat, v_lon, s.lat_origen, s.lon_origen),
           s.created_at
  LIMIT greatest(1, least(coalesce(p_limite, 30), 100));
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_viajes_disponibles(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_viajes_disponibles(double precision, double precision, integer) TO authenticated;
```

### 5.5 (6) `fn_tomar_viaje` — atómico, primer gana

```sql
CREATE OR REPLACE FUNCTION muevete.fn_tomar_viaje(p_solicitud_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_driver      bigint := muevete.get_my_driver_id();
  cfg           muevete.configuracion_tarifas%ROWTYPE;
  v_sol         muevete.solicitudes_transporte%ROWTYPE;
  v_prev        muevete.solicitudes_transporte%ROWTYPE;
  v_online      boolean := false;
  v_kyc         boolean := false;
  v_activo      boolean := false;
  v_lat         double precision;
  v_lon         double precision;
  v_zona_chofer bigint;
  v_tipo_chofer bigint;
  v_saldo       numeric := 0;
  v_comision    numeric;
  v_metodo      text;
  v_viaje_id    bigint;
  v_hold        numeric := 0;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'no_es_chofer' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  IF NOT coalesce(cfg.taxi_precio_fijo_activo, false) THEN
    RAISE EXCEPTION 'servicio_en_mantenimiento' USING ERRCODE = 'P0003';
  END IF;

  -- ── 1. Pre-chequeos del chofer (antes de tocar la fila) ──────────────
  SELECT coalesce(d.kyc, false), veh.id_tipo_vehiculo
    INTO v_kyc, v_tipo_chofer
    FROM muevete.drivers d
    LEFT JOIN muevete.vehiculos veh ON veh.id = d.vehiculo
   WHERE d.id = v_driver;

  SELECT coalesce(p.estado, false), p.latitude, p.longitude
    INTO v_online, v_lat, v_lon
    FROM muevete.place p
   WHERE p.driver = v_driver;
  -- SELECT INTO con 0 filas asigna NULL: normalizar
  v_online := coalesce(v_online, false);
  v_kyc    := coalesce(v_kyc, false);

  IF NOT v_online THEN
    RAISE EXCEPTION 'chofer_offline' USING ERRCODE = 'P0010';
  END IF;
  IF NOT v_kyc THEN
    RAISE EXCEPTION 'chofer_no_aprobado' USING ERRCODE = 'P0011';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM muevete.solicitudes_transporte
     WHERE driver_id = v_driver AND estado = 'aceptada'
  ) INTO v_activo;
  IF v_activo THEN
    RAISE EXCEPTION 'chofer_con_viaje_activo' USING ERRCODE = 'P0012';
  END IF;

  -- ── 2. Validaciones sobre la solicitud (campos inmutables) ───────────
  SELECT * INTO v_prev FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND OR v_prev.estado <> 'pendiente' OR v_prev.driver_id IS NOT NULL THEN
    RAISE EXCEPTION 'ya_tomado' USING ERRCODE = 'P0020';
  END IF;
  -- No se puede tomar una solicitud legacy (sin snapshot de precio)
  IF v_prev.precio_plataforma IS NULL THEN
    RAISE EXCEPTION 'solicitud_legacy_sin_tarifa' USING ERRCODE = 'P0025';
  END IF;
  IF v_prev.id_tipo_vehiculo IS NOT NULL
     AND v_prev.id_tipo_vehiculo IS DISTINCT FROM v_tipo_chofer THEN
    RAISE EXCEPTION 'tipo_vehiculo_incompatible' USING ERRCODE = 'P0021';
  END IF;
  IF v_lat IS NOT NULL THEN
    SELECT z.id INTO v_zona_chofer FROM muevete.fn_zona_de_punto(v_lat, v_lon, now()) z;
    IF v_zona_chofer IS DISTINCT FROM v_prev.zona_id THEN
      RAISE EXCEPTION 'viaje_fuera_de_tu_zona' USING ERRCODE = 'P0022';
    END IF;
  END IF;

  -- ── 3. D6: deuda permitida (saldo + tope, o saldo >= 0 si permite_deuda=false) ─
  SELECT coalesce(w.balance, 0) INTO v_saldo
    FROM muevete.wallet_drivers w WHERE w.driver_id = v_driver;

  IF NOT FOUND THEN
    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_driver, 0) ON CONFLICT (driver_id) DO NOTHING;
    v_saldo := 0;
  END IF;

  v_comision := round(coalesce(v_prev.precio_plataforma, 0)
                      * coalesce(v_prev.comision_pct, cfg.comision_pct) / 100.0, 2);
  IF coalesce(cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, cfg.tope_comision_viaje);
  END IF;

  IF coalesce(cfg.permite_deuda, true) THEN
    -- Puede quedar negativo hasta el tope configurado
    IF (v_saldo + coalesce(cfg.limite_deuda_efectivo, 0)) < v_comision THEN
      RAISE EXCEPTION 'limite_de_deuda_alcanzado: comision % > disponible %',
        v_comision, (v_saldo + coalesce(cfg.limite_deuda_efectivo, 0))
        USING ERRCODE = 'P0023';
    END IF;
  ELSE
    -- Sin deuda: debe tener saldo suficiente para la comisión
    IF v_saldo < v_comision THEN
      RAISE EXCEPTION 'saldo_insuficiente_para_comision: comision % > saldo %',
        v_comision, v_saldo USING ERRCODE = 'P0023';
    END IF;
  END IF;

  v_metodo := coalesce(v_prev.metodo_pago, 'efectivo');

  -- ── 4. TOMA ATÓMICA: una sola sentencia; el perdedor no toca nada ────
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

  -- ── 5. Retención de wallet del cliente (si aplica) ───────────────────
  IF v_metodo = 'wallet' THEN
    UPDATE muevete.suscription_user u
       SET balance = coalesce(u.balance, 0) - coalesce(v_sol.precio_plataforma, 0)
     WHERE u.user_id = v_sol.user_id
       AND coalesce(u.balance, 0) >= coalesce(v_sol.precio_plataforma, 0);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'cliente_sin_saldo' USING ERRCODE = 'P0024';
    END IF;
    v_hold := coalesce(v_sol.precio_plataforma, 0);
  END IF;

  -- ── 6. Crear el viaje en la MISMA transacción ────────────────────────
  INSERT INTO muevete.viajes (
    driver_id, "user", estado, completado, visto,
    latitud_cliente, longitud_cliente,
    solicitud_id, precio_plataforma, precio_chofer, comision_pct, metodo_pago
  ) VALUES (
    v_driver, v_sol.user_id::text, false, false, false,
    v_sol.lat_destino::text, v_sol.lon_destino::text,
    v_sol.id, v_sol.precio_plataforma, v_sol.precio_chofer, v_sol.comision_pct, v_metodo
  ) RETURNING id INTO v_viaje_id;

  -- ── 7. Cerrar ofertas legacy de esa solicitud (sólo lectura después) ─
  UPDATE muevete.ofertas_chofer o
     SET estado = 'rechazada'
   WHERE o.solicitud_id = v_sol.id AND o.estado = 'pendiente';

  -- ── 8. Notificar al cliente (dispara notificaciones_push) ────────────
  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  VALUES (
    v_sol.user_id, 'viaje_asignado', 'Conductor asignado',
    'Tu conductor va en camino. Precio: ' || v_sol.precio_plataforma
      || ' ' || coalesce(v_sol.moneda, 'CUP'),
    jsonb_build_object('solicitud_id', v_sol.id, 'viaje_id', v_viaje_id,
                       'driver_id', v_driver, 'precio_plataforma', v_sol.precio_plataforma)
  );

  RETURN jsonb_build_object(
    'success',           true,
    'solicitud_id',      v_sol.id,
    'viaje_id',          v_viaje_id,
    'precio_plataforma', v_sol.precio_plataforma,
    'comision_pct',      coalesce(v_sol.comision_pct, cfg.comision_pct),
    'comision_monto',    v_comision,
    'precio_chofer',     coalesce(v_sol.precio_plataforma, 0) - v_comision,
    'metodo_pago',       v_metodo,
    'hold_cliente',      v_hold,
    'saldo_chofer',      v_saldo
  );
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_tomar_viaje(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_tomar_viaje(bigint) TO authenticated;
```

**Garantía de concurrencia.** Dos sesiones ejecutan el mismo `UPDATE`. La primera bloquea la fila y actualiza; la segunda **espera** en la fila y, al hacer `COMMIT` la primera, PostgreSQL re-evalúa el `WHERE` sobre la versión nueva (EvalPlanQual): `estado` ya no es `'pendiente'` → 0 filas → `NOT FOUND` → `ya_tomado`. **No hace falta `FOR UPDATE SKIP LOCKED`** para tomar un viaje concreto (no aporta atomicidad y confunde el diagnóstico). Las validaciones previas que dependen de la fila (tipo/zona) se hacen antes del `UPDATE`; si alguna de las validaciones posteriores lanza excepción, la transacción entera revierte y la solicitud queda libre.

### 5.6 (7) `fn_completar_viaje` — comisión del snapshot, espera, deuda

```sql
CREATE OR REPLACE FUNCTION muevete.fn_completar_viaje(
  p_viaje_id   bigint,
  p_espera_min integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  cfg            muevete.configuracion_tarifas%ROWTYPE;
  v_viaje        muevete.viajes%ROWTYPE;
  v_sol          muevete.solicitudes_transporte%ROWTYPE;
  v_metodo       text;
  v_tarifa_esp   numeric := 0;
  v_espera_min   integer := 0;
  v_espera_cob   integer := 0;
  v_espera_monto numeric := 0;
  v_total        numeric;
  v_comision     numeric;
  v_chofer       numeric;
  v_saldo        numeric;
  v_saldo_cli    numeric;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;

  -- Lock del viaje: serializa dos cierres simultáneos sobre el mismo viaje
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

  -- Idempotencia (reintentos de la cola offline)
  IF v_sol.estado = 'completada' THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotente', true,
      'solicitud_id', v_sol.id, 'viaje_id', v_viaje.id,
      'precio_plataforma', v_sol.precio_plataforma,
      'comision_monto', round(v_sol.precio_plataforma * coalesce(v_sol.comision_pct,0)/100.0, 2),
      'precio_chofer', v_sol.precio_chofer);
  END IF;

  IF v_sol.estado <> 'aceptada' THEN
    RAISE EXCEPTION 'estado_invalido: %', v_sol.estado USING ERRCODE = 'P0032';
  END IF;

  v_metodo := coalesce(v_sol.metodo_pago, v_viaje.metodo_pago, 'efectivo');
  IF v_metodo NOT IN ('efectivo','wallet') THEN
    RAISE EXCEPTION 'metodo_pago_invalido: %', v_metodo USING ERRCODE = 'P0004';
  END IF;

  -- ── Espera: manda el servidor si el viaje trae segundos medidos ──────
  SELECT coalesce(vt.precio_espera_min, 0) INTO v_tarifa_esp
    FROM muevete.vehicle_type vt WHERE vt.id = v_sol.id_tipo_vehiculo;
  v_tarifa_esp := coalesce(v_tarifa_esp, 0);

  IF v_viaje.tiempo_espera_segundos IS NOT NULL
     AND v_viaje.tiempo_espera_segundos > 0 THEN
    v_espera_min := ceil(v_viaje.tiempo_espera_segundos / 60.0)::integer;
  ELSE
    v_espera_min := greatest(coalesce(p_espera_min, 0), 0);
  END IF;

  v_espera_cob := greatest(v_espera_min - coalesce(cfg.gracia_espera_min, 0), 0);
  IF v_espera_cob > 0 AND v_tarifa_esp > 0 THEN
    v_espera_monto := round(v_espera_cob * v_tarifa_esp, 2);
    IF coalesce(cfg.tope_cobro_espera, 0) > 0 THEN
      v_espera_monto := least(v_espera_monto, cfg.tope_cobro_espera);
    END IF;
  END IF;

  -- ── Total y reparto: SIEMPRE desde el snapshot, nunca del cliente ────
  v_total    := coalesce(v_sol.precio_plataforma, 0) + v_espera_monto;
  v_comision := round(v_total * coalesce(v_sol.comision_pct, cfg.comision_pct) / 100.0, 2);
  IF coalesce(cfg.tope_comision_viaje, 0) > 0 THEN
    v_comision := least(v_comision, cfg.tope_comision_viaje);
  END IF;
  v_chofer := v_total - v_comision;

  IF v_metodo = 'wallet' THEN
    -- Al tomar se retuvo precio_plataforma; se cobra sólo la espera
    IF v_espera_monto > 0 THEN
      UPDATE muevete.suscription_user u
         SET balance = coalesce(u.balance, 0) - v_espera_monto
       WHERE u.user_id = v_sol.user_id
         AND coalesce(u.balance, 0) >= v_espera_monto;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'cliente_sin_saldo_para_espera' USING ERRCODE = 'P0024';
      END IF;
    END IF;

    SELECT coalesce(balance, 0) INTO v_saldo_cli
      FROM muevete.suscription_user WHERE user_id = v_sol.user_id;

    INSERT INTO muevete.transacciones_wallet
      (user_id, tipo, monto, balance_despues, viaje_id, descripcion, estado)
    VALUES (v_sol.user_id, 'pago_viaje', -v_total, v_saldo_cli, v_viaje.id,
            'Pago de viaje por wallet (solicitud #' || v_sol.id || ')', 'completada');

    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_sol.driver_id, 0) ON CONFLICT (driver_id) DO NOTHING;

    UPDATE muevete.wallet_drivers
       SET balance = coalesce(balance, 0) + v_chofer
     WHERE driver_id = v_sol.driver_id
    RETURNING balance INTO v_saldo;

    INSERT INTO muevete.transacciones_wallet
      (driver_id, tipo, monto, balance_despues, viaje_id, descripcion, estado)
    VALUES (v_sol.driver_id, 'pago_viaje', v_chofer, v_saldo, v_viaje.id,
            'Pago por viaje (total ' || v_total || ' - '
             || coalesce(v_sol.comision_pct, cfg.comision_pct) || '% comisión)', 'completada');

  ELSE
    -- D6: en efectivo se descuenta la comisión aunque deje saldo negativo
    INSERT INTO muevete.wallet_drivers (driver_id, balance)
    VALUES (v_sol.driver_id, 0) ON CONFLICT (driver_id) DO NOTHING;

    UPDATE muevete.wallet_drivers
       SET balance = coalesce(balance, 0) - v_comision
     WHERE driver_id = v_sol.driver_id
    RETURNING balance INTO v_saldo;

    INSERT INTO muevete.transacciones_wallet
      (driver_id, tipo, monto, balance_despues, viaje_id, descripcion, estado)
    VALUES (v_sol.driver_id, 'comision_viaje', -v_comision, v_saldo, v_viaje.id,
            'Comisión ' || coalesce(v_sol.comision_pct, cfg.comision_pct)
             || '% por viaje completado (efectivo)', 'completada');
  END IF;

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
         comision_pct      = coalesce(v_sol.comision_pct, cfg.comision_pct)
   WHERE id = v_viaje.id;

  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  VALUES (v_sol.user_id, 'viaje_completado', 'Viaje completado',
          'Total: ' || v_total || ' ' || coalesce(v_sol.moneda, 'CUP'),
          jsonb_build_object('solicitud_id', v_sol.id, 'viaje_id', v_viaje.id,
                             'precio_plataforma', v_total));

  RETURN jsonb_build_object(
    'success',           true,
    'solicitud_id',      v_sol.id,
    'viaje_id',          v_viaje.id,
    'precio_plataforma', v_total,
    'espera_min',        v_espera_min,
    'espera_cobrada_min', v_espera_cob,
    'espera_monto',      v_espera_monto,
    'comision_pct',      coalesce(v_sol.comision_pct, cfg.comision_pct),
    'comision_monto',    v_comision,
    'precio_chofer',     v_chofer,
    'metodo_pago',       v_metodo,
    'saldo_chofer',      v_saldo,
    'deuda_chofer',      greatest(0, -coalesce(v_saldo, 0)));
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_completar_viaje(bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_completar_viaje(bigint, integer) TO authenticated;
```

**Rechazo de precios del cliente:** la firma **no recibe precio**. `p_espera_min` sólo se usa como *fallback* si el viaje no trae `tiempo_espera_segundos` (lo escribe el servidor/app durante la espera); el monto siempre se acota por `tope_cobro_espera`. Ver §12 (D-06).

### 5.7 (8) `fn_cancelar_solicitud`

```sql
CREATE OR REPLACE FUNCTION muevete.fn_cancelar_solicitud(
  p_solicitud_id bigint,
  p_motivo       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_driver    bigint := muevete.get_my_driver_id();
  v_sol       muevete.solicitudes_transporte%ROWTYPE;
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

  IF v_sol.estado = 'cancelada' THEN
    RETURN jsonb_build_object('success', true, 'idempotente', true,
                              'solicitud_id', v_sol.id, 'reembolso', 0);
  END IF;
  IF v_sol.estado = 'completada' THEN
    RAISE EXCEPTION 'viaje_ya_completado' USING ERRCODE = 'P0032';
  END IF;

  -- Si el cliente pagaba con wallet y ya se retuvo al tomar → reembolsar
  IF coalesce(v_sol.metodo_pago, '') = 'wallet'
     AND v_sol.driver_id IS NOT NULL
     AND v_sol.estado = 'aceptada'
     AND coalesce(v_sol.precio_plataforma, 0) > 0 THEN

    v_reembolso := v_sol.precio_plataforma;

    UPDATE muevete.suscription_user u
       SET balance = coalesce(u.balance, 0) + v_reembolso
     WHERE u.user_id = v_sol.user_id
    RETURNING balance INTO v_saldo;

    INSERT INTO muevete.transacciones_wallet
      (user_id, tipo, monto, balance_despues, descripcion, estado)
    VALUES (v_sol.user_id, 'reembolso', v_reembolso, v_saldo,
            'Reembolso por cancelación de la solicitud #' || v_sol.id, 'completada');
  END IF;

  UPDATE muevete.solicitudes_transporte
     SET estado             = 'cancelada',
         cancelada_at       = now(),
         motivo_cancelacion = p_motivo,
         driver_id          = NULL
   WHERE id = v_sol.id;

  UPDATE muevete.viajes
     SET completado = true, estado = false
   WHERE solicitud_id = v_sol.id;

  IF v_sol.driver_id IS NOT NULL THEN
    INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
    SELECT d.uuid, 'viaje_cancelado', 'Viaje cancelado',
           coalesce(p_motivo, 'El viaje fue cancelado'),
           jsonb_build_object('solicitud_id', v_sol.id)
      FROM muevete.drivers d
     WHERE d.id = v_sol.driver_id AND d.uuid IS NOT NULL;
  END IF;

  RETURN jsonb_build_object('success', true, 'solicitud_id', v_sol.id,
                            'reembolso', v_reembolso, 'estado', 'cancelada');
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_cancelar_solicitud(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_cancelar_solicitud(bigint, text) TO authenticated;
```

### 5.8 (9) `fn_recargar_wallet` — centraliza el 11 %

```sql
CREATE OR REPLACE FUNCTION muevete.fn_recargar_wallet(
  p_metodo    text,
  p_monto     numeric,
  p_evidencia text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_driver    bigint := muevete.get_my_driver_id();
  cfg         muevete.configuracion_tarifas%ROWTYPE;
  v_total     numeric;
  v_tx_id     bigint;
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

  SELECT * INTO cfg FROM muevete.configuracion_tarifas WHERE id = 1;
  v_total := round(p_monto * (1 + coalesce(cfg.recarga_pct, 0) / 100.0), 2);

  -- Crea la transacción PENDIENTE (el saldo lo acredita el admin al aprobar)
  INSERT INTO muevete.transacciones_wallet
    (user_id, driver_id, tipo, monto, estado, descripcion, created_at)
  VALUES (
    CASE WHEN v_driver IS NULL THEN v_uid END,
    v_driver,
    'recarga',
    p_monto,
    'pendiente',
    'Recarga de ' || p_monto || ' ' || coalesce(cfg.moneda,'CUP')
      || ' — pago total: ' || v_total || ' (incluye '
      || coalesce(cfg.recarga_pct,0) || '% comisión) — canal: ' || p_metodo,
    now()
  ) RETURNING id INTO v_tx_id;

  IF p_evidencia IS NOT NULL AND length(trim(p_evidencia)) > 0 THEN
    INSERT INTO muevete.verificacion_operacion_recarga (transaccion_id, detalle_texto)
    VALUES (v_tx_id, p_evidencia);
  END IF;

  RETURN jsonb_build_object(
    'success',           true,
    'transaccion_id',    v_tx_id,
    'monto_acreditar',   p_monto,
    'total_a_pagar',     v_total,
    'recarga_pct',       cfg.recarga_pct,
    'moneda',            cfg.moneda,
    'estado',            'pendiente',
    'es_recarga_chofer', v_driver IS NOT NULL);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_recargar_wallet(text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_recargar_wallet(text, numeric, text) TO authenticated;
```

> Mantiene el comportamiento actual (crear transacción `pendiente`, la aprueba el superadmin en `muevete_wallets_screen`) pero **el 11 % sale de configuración**, no del literal `1.11` en Dart. Se elimina el literal de `wallet_service.addFunds/addDriverFunds`.

### 5.9 Deprecación de `complete_ride_payment` (H1)

`complete_ride_payment` **ya existe en producción y está versionado en `030_baseline_sync_produccion.sql`** (6 argumentos + sobrecarga legacy de 5). **No se redefine en 031–038**: se reutiliza tal cual. La app nueva no lo llama; queda intacto para builds viejas y viajes históricos. El `0.15` que contiene **no afecta al flujo nuevo** (que usa `fn_completar_viaje` con la comisión del snapshot/config) y se elimina de Dart en H5 (§7.5). Si en el futuro se quiere alinear la comisión del camino legacy, será un PR aparte con `CREATE OR REPLACE` explícito y pruebas. El bloque siguiente queda **sólo como referencia de lo que ya existe**:

> ⚠️ **NO ejecutar el bloque siguiente.** Se transcribe únicamente para documentar la firma que ya está en producción (`030_baseline`). Crearlo aquí duplicaría/redefiniría una función versionada, que es justo lo que se quiere evitar.

```sql
-- REFERENCIA (NO EJECUTAR): ya existe en 030_baseline_sync_produccion.sql
-- CREATE OR REPLACE FUNCTION muevete.complete_ride_payment(
  p_metodo_pago  text,
  p_client_uuid  uuid,
  p_driver_id    bigint,
  p_viaje_id     bigint,
  p_precio_final numeric,
  p_precio_base  numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_sol_id bigint;
  v_pct    numeric;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  SELECT solicitud_id INTO v_sol_id FROM muevete.viajes WHERE id = p_viaje_id;
  IF v_sol_id IS NOT NULL THEN
    -- Camino nuevo: manda el snapshot y la config; se ignora el precio del cliente
    RETURN muevete.fn_completar_viaje(p_viaje_id, NULL);
  END IF;

  -- Camino legacy (viajes huérfanos previos a H0): misma aritmética, % dinámico
  SELECT coalesce(comision_pct, 15.00) INTO v_pct
    FROM muevete.configuracion_tarifas WHERE id = 1;
  v_pct := coalesce(v_pct, 15.00);

  -- ... (misma lógica de la versión actual, reemplazando 0.15 por v_pct/100)
  RETURN jsonb_build_object('success', true, 'legacy', true, 'comision_pct', v_pct);
END;
$$;
```

**Criterio:** `grep -rn "complete_ride_payment" inventtia_muevete/lib/` sólo devuelve el método marcado `@Deprecated` (`wallet_service.completeRidePaymentRpc`, usado por `completion_sync_service` para entradas v1); el flujo nuevo no lo invoca. **El RPC no se modifica.**

---

## 6. RLS, permisos y realtime

### 6.1 Tablas nuevas (`033`)

```sql
BEGIN;

ALTER TABLE muevete.zonas_tarifa          ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.tarifas_municipio     ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.configuracion_tarifas ENABLE ROW LEVEL SECURITY;

-- Lectura: cualquier autenticado (el chofer muestra la zona, el cliente la comisión)
CREATE POLICY zonas_tarifa_select_auth
  ON muevete.zonas_tarifa FOR SELECT TO authenticated USING (true);
CREATE POLICY tarifas_municipio_select_auth
  ON muevete.tarifas_municipio FOR SELECT TO authenticated USING (true);
CREATE POLICY configuracion_tarifas_select_auth
  ON muevete.configuracion_tarifas FOR SELECT TO authenticated USING (true);

-- Escritura: patrón superadmin_all_* (como el resto del esquema)
CREATE POLICY superadmin_all_zonas_tarifa
  ON muevete.zonas_tarifa FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
CREATE POLICY superadmin_all_tarifas_municipio
  ON muevete.tarifas_municipio FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());
CREATE POLICY superadmin_all_configuracion_tarifas
  ON muevete.configuracion_tarifas FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

GRANT SELECT ON muevete.zonas_tarifa, muevete.tarifas_municipio,
               muevete.configuracion_tarifas TO authenticated;
GRANT INSERT, UPDATE, DELETE ON muevete.zonas_tarifa, muevete.tarifas_municipio
  TO authenticated;                       -- filtrado por las políticas de superadmin

COMMIT;
```

### 6.2 Endurecimiento (`038`, sólo en el cutover)

Orden seguro (plan §4.3 y §8.3): **crear RPC y publicar apps nuevas → subir versión mínima → revocar**. Si se revoca antes, las apps actuales dejan de funcionar.

```sql
BEGIN;

-- 1. El cliente edita cualquier columna: revocar UPDATE de tabla
DROP POLICY IF EXISTS solicitudes_update_own_client ON muevete.solicitudes_transporte;
-- 2. Precio libre en INSERT
DROP POLICY IF EXISTS solicitudes_insert_client ON muevete.solicitudes_transporte;
-- 3. SELECT con OR true
DROP POLICY IF EXISTS solicitudes_select_own_client ON muevete.solicitudes_transporte;
CREATE POLICY solicitudes_select_own_client ON muevete.solicitudes_transporte
  FOR SELECT TO authenticated USING (user_id = auth.uid());
-- 4. Cualquiera ve todas las solicitudes
DROP POLICY IF EXISTS drivers_see_solicitudes ON muevete.solicitudes_transporte;
-- 5. Cualquiera crea viajes
DROP POLICY IF EXISTS viajes_insert_authenticated ON muevete.viajes;
-- 6. El chofer edita su propio saldo (agujero de dinero)
DROP POLICY IF EXISTS wallet_drivers_update_own ON muevete.wallet_drivers;
DROP POLICY IF EXISTS wallet_drivers_insert_own ON muevete.wallet_drivers;
-- 7. Transacciones falsas
DROP POLICY IF EXISTS transacciones_insert_client ON muevete.transacciones_wallet;
DROP POLICY IF EXISTS transacciones_insert_driver ON muevete.transacciones_wallet;
-- 8. Cliente manipula ofertas
DROP POLICY IF EXISTS ofertas_update_client ON muevete.ofertas_chofer;
DROP POLICY IF EXISTS ofertas_insert_driver ON muevete.ofertas_chofer;

-- 9. Mantener: wallet_drivers_select_own (el chofer ve saldo y deuda)
-- 10. Mantener: superadmin_all_* y replicar para las 3 tablas nuevas (§6.1)

REVOKE INSERT, UPDATE, DELETE ON muevete.solicitudes_transporte FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON muevete.viajes FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON muevete.wallet_drivers FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON muevete.transacciones_wallet FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON muevete.ofertas_chofer FROM authenticated, anon;
-- (las RPC son SECURITY DEFINER: no les afecta)
-- Lectura de histórico del chofer/cliente se mantiene:
GRANT SELECT ON muevete.ofertas_chofer TO authenticated;

COMMIT;
```

> Verificación post-`038` (script `test_rls.sql`): con un JWT de cliente, `UPDATE muevete.solicitudes_transporte SET precio_plataforma=1` debe fallar; con un JWT de chofer, `SELECT count(*) FROM muevete.solicitudes_transporte` debe devolver sólo lo suyo/pendiente de su zona; `UPDATE wallet_drivers` debe fallar.

### 6.3 Realtime

- Verificación y `ALTER PUBLICATION` en §1.2 (discrepancia a resolver en H0).
- `REPLICA IDENTITY FULL` en `solicitudes_transporte` y `viajes` para que los payloads de UPDATE traigan `estado`, `driver_id`, precios.
- Si no se puede publicar (permisos): **polling** obligatorio en cliente (`searching_driver_sheet`) y chofer (`available_trips_screen`), 10–15 s.

---

## 7. Cambios en `inventtia_muevete/`

Convención: **NEW** crear · **REWRITE** reescribir · **EDIT** cambio puntual · **DELETE** borrar · **LEGACY** queda sin uso nuevo (`@Deprecated`).

### 7.1 Mapa de archivos (H2 cliente + H3 chofer + H5 dinero)

| Archivo | Acción | Qué cambia |
|---|---|---|
| `lib/models/tarifa_model.dart` | **NEW** | `Cotizacion` (mapea el jsonb de `fn_cotizar_viaje`), `TarifaDetalle`. |
| `lib/models/viaje_disponible_model.dart` | **NEW** | Fila de `fn_viajes_disponibles` (`precioPlataforma`, `precioChofer`, `comisionPct`, `comisionMonto`, `puedeTomar`, `motivoBloqueo`, `deudaDisponible`, `desglose`). |
| `lib/models/transport_request_model.dart` | **EDIT** | Añadir `precioPlataforma`, `precioChofer`, `comisionPct`, `zonaId`, `tarifaDetalle`, `driverId`, `tarifaModo`. `precioOferta` queda **LEGACY**. |
| `lib/models/driver_offer_model.dart` | **LEGACY** | `@Deprecated`; sólo lectura histórica (`request_history_screen`). |
| `lib/models/notification_model.dart` | **EDIT** | Tipos `viajeDisponible`, `viajeTomado`, `viajeAsignado`, `viajeCancelado`; retirar `nuevaOferta`/`ofertaAceptada` del flujo activo. |
| `lib/utils/tarifa_calculator.dart` | **NEW** | Espejo Dart puro de la fórmula para preview offline y para el test de paridad. **No es fuente de verdad.** |
| `lib/services/tarifa_service.dart` | **NEW** | `cotizar()` → RPC `fn_cotizar_viaje`; `configuracion()` (lee `configuracion_tarifas`). |
| `lib/services/viaje_service.dart` | **NEW** | `crearSolicitud()`, `viajesDisponibles()`, `tomarViaje()`, `completarViaje()`, `cancelarSolicitud()`, `miSolicitudActiva()`, suscripciones realtime. |
| `lib/services/transport_request_service.dart` | **REWRITE** | Fuera `createRequest` (INSERT directo), `acceptOffer`, `getExistingOffers`, `subscribeToOffers`, `subscribeToOfertaUpdates`. Dentro: `subscribeToSolicitud` (UPDATE de estado/driver_id). Se conserva `getNearbyDrivers`/`getDriverDetails` para el mapa. |
| `lib/providers/transport_provider.dart` | **REWRITE** | Estados nuevos; `_calculatePrice`/`_isInsideCityZone`/`setOfferPrice`/`offerPrice`/`driverOffers`/`acceptedOffer`/`acceptOffer`/`declineOffer`/`_onNewOffer`/`_onOfertaUpdate`/`pollOffers` **eliminados**. Nuevo: `cotizacion`, `cotizar()`, `sendRequest()`→`fn_crear_solicitud`, `cancelRequest()`→RPC, `completarViaje()`→RPC. |
| `lib/screens/client/route_preview_screen.dart` | **REWRITE** (bloque precio) | Elimina `_offerController`, `_userEditedPrice`, "Tu Oferta", validación de mínimo. Nuevo: tarjeta de precio sólo lectura + `PriceBreakdown` + `_onSolicitar`. |
| `lib/screens/client/driver_offers_screen.dart` | **DELETE** | Ruta `/client/driver-offers` se re-apunta a `SearchingDriverSheet`/pantalla nueva para no romper deep links. |
| `lib/widgets/searching_driver_sheet.dart` | **NEW** | Mapa + "Buscando conductor" + precio + cancelar; al detectar `driver_id` navega a `RideConfirmedScreen`. |
| `lib/widgets/price_breakdown.dart` | **NEW** | Desglose reusable (cliente, recibo, simulador no — ese es Dart/Flutter del superadmin). |
| `lib/screens/client/ride_confirmed_screen.dart` | **EDIT** | Chofer desde `solicitud.driver_id`+`drivers`; precio desde `precio_plataforma`; completar vía `fn_completar_viaje`; recibo con `tarifa_detalle`. |
| `lib/screens/client/request_history_screen.dart` | **EDIT** | Leer `precio_plataforma`/`tarifa_modo`; no usar `oferta`. |
| `lib/screens/client/home_map_screen.dart` | **EDIT** | Quitar referencias a ofertas/`acceptedOffer`; precio desde la solicitud activa. |
| `lib/screens/client/wallet_screen.dart` | **EDIT** | Mostrar `recarga_pct` de configuración (no `1.11` hardcodeado). |
| `lib/screens/driver/available_trips_screen.dart` | **NEW** | Lista de viajes tomables (reemplaza el diálogo de `incoming_requests_screen` y el duplicado de `driver_home_screen`). |
| `lib/widgets/available_trip_card.dart` | **NEW** | "Cliente paga $X · Te toca $Y (Z %)· km · zona · deuda disponible". |
| `lib/screens/driver/incoming_requests_screen.dart` | **REWRITE** | Tabs "Disponibles"/"Mis viajes"; fuera `_showMakeOfferDialog`, `_submitOffer`, `driverHasEnoughForCommission`, `price*0.15`. Dentro: `fn_tomar_viaje`, `fn_completar_viaje`. |
| `lib/screens/driver/driver_home_screen.dart` | **REWRITE** (parcial) | Fuera `_incomingRequests`, `_offeredRequestIds`, `_showMakeOfferDialog`, `_submitOffer`, `_subscribeToOfferAcceptances`, `_onOfferAccepted`. Dentro: hoja de viajes disponibles + `tomarViaje`; banner de viaje activo por `solicitudes.driver_id`. |
| `lib/screens/driver/active_ride_screen.dart` | **EDIT** | Completar por RPC; mostrar "Tu ganancia" (`precio_chofer`) y desglose; espera desde el server. |
| `lib/screens/driver/driver_wallet_screen.dart` | **EDIT** | Saldo negativo = deuda + "disponible hasta el tope". |
| `lib/services/driver_service.dart` | **REWRITE** (parcial) | Fuera `makeOffer`, `hasExistingOffer`, `subscribeToMyOfferAcceptances`, `createViaje` (lo crea la RPC). Dentro `viajesDisponibles()`, `tomarViaje()`, `completarViaje()`. |
| `lib/services/wallet_service.dart` | **EDIT** | Eliminar `chargeDriverCommission`, `creditDriverForWalletPayment`, `driverHasEnoughForCommission` (su aritmética vive en `fn_completar_viaje`); `addFunds`/`addDriverFunds` → `fn_recargar_wallet`; `completeRidePaymentRpc` → `LEGACY`. |
| `lib/services/completion_sync_service.dart` | **REWRITE** | Encola `{v:2, solicitud_id, viaje_id, espera_min}` y llama `fn_completar_viaje` (idempotente). Migra entradas v1 (§9.5). |
| `lib/services/trip_completion_qr_service.dart` | **EDIT** | Payload con `solicitud_id`/`viaje_id`; sin precios; secreto HMAC fuera del código (H5). |
| `lib/services/background_service.dart` | **EDIT** | Canal de ofertas → canal de solicitud; textos "Nuevo viaje disponible…" (sólo lo toca H3). |
| `lib/services/notification_service.dart` | **EDIT** | Nuevos tipos y `pushLocal` para `viajeTomado`. |
| `lib/utils/constants.dart` | **EDIT** | Quitar `cityCenterLat/Lon`, `cityRadiusKm` (o `@Deprecated` una release). |
| `lib/widgets/driver_offer_card.dart` | **DELETE** | Sustituido por `available_trip_card.dart`. |
| `lib/main.dart` | **EDIT** | Rutas: `/client/searching` (NEW), `/client/driver-offers` → alias, `/driver/available-trips` (NEW); quitar import de `driver_offers_screen`. |

### 7.2 `transport_provider.dart` — estados y API

```dart
enum TransportState {
  idle,
  calculatingRoute,  // pidiendo ruta a OSRM
  routeReady,        // ruta + cotización listas
  requesting,        // fn_crear_solicitud en vuelo
  searchingDriver,   // solicitud publicada, esperando toma
  driverAssigned,    // driver_id != null
  rideInProgress,
  rideCompleted,
  error,
}
```

```dart
// ── Cotizar (mismo RPC que el simulador del superadmin) ────────────────
Future<void> cotizar() async {
  if (_pickup == null || _dropoff == null || _selectedVehicleType?.id == null) return;
  _state = TransportState.calculatingRoute;
  notifyListeners();
  try {
    _cotizacion = await _tarifaService.cotizar(
      latOrigen: _pickup!.latitude,
      lonOrigen: _pickup!.longitude,
      latDestino: _dropoff!.latitude,
      lonDestino: _dropoff!.longitude,
      idTipo: _selectedVehicleType!.id!,
      km: _routeDistanceKm > 0 ? _routeDistanceKm : null,
      provincia: _provinciaOrigen,
      municipio: _municipioOrigen,
    );
    _state = TransportState.routeReady;
  } catch (e) {
    _error = AppError.message(e, action: 'calcular la tarifa');
    _state = TransportState.error;
  }
  notifyListeners();
}

// ── Publicar ────────────────────────────────────────────────────────────
Future<bool> sendRequest(String userId) async {
  if (_pickup == null || _dropoff == null || _selectedVehicleType?.id == null) {
    return false;
  }
  _state = TransportState.requesting;
  _error = null;
  notifyListeners();
  try {
    final row = await _viajeService.crearSolicitud(
      latOrigen: _pickup!.latitude,
      lonOrigen: _pickup!.longitude,
      latDestino: _dropoff!.latitude,
      lonDestino: _dropoff!.longitude,
      idTipo: _selectedVehicleType!.id!,
      dirOrigen: _pickupAddress,
      dirDestino: _dropoffAddress,
      km: _routeDistanceKm,
      metodoPago: _paymentMethod,
      provincia: _provinciaOrigen,
      municipio: _municipioOrigen,
    );
    _activeRequest = TransportRequestModel.fromJson(row);
    _viajeService.subscribeToSolicitud(_activeRequest!.id!, _onSolicitudUpdate);
    _state = TransportState.searchingDriver;
    notifyListeners();
    BackgroundService.updateStatus(
      title: 'Muevete',
      content: 'Buscando conductor · ${_cotizacion!.precioPlataforma.toStringAsFixed(2)} CUP',
    );
    return true;
  } catch (e) {
    _error = AppError.message(e, action: 'publicar la solicitud');
    _state = TransportState.error;
    notifyListeners();
    return false;
  }
}

void _onSolicitudUpdate(Map<String, dynamic> row) {
  final estado = row['estado'] as String?;
  final driverId = (row['driver_id'] as num?)?.toInt();
  switch (estado) {
    case 'aceptada':
      _activeRequest = _activeRequest?.copyWith(
        estado: EstadoSolicitud.aceptada,
        driverId: driverId,
        precioPlataforma: (row['precio_plataforma'] as num?)?.toDouble(),
      );
      _state = TransportState.driverAssigned;
      break;
    case 'cancelada':
    case 'expirada':
      _state = TransportState.idle;
      _activeRequest = null;
      break;
    case 'completada':
      _state = TransportState.rideCompleted;
      break;
  }
  notifyListeners();
}
```

### 7.3 `route_preview_screen.dart` — el precio deja de ser editable

Se elimina (líneas actuales 25, 27, 53–71, 119–126, 489–546): `_offerController`, `_userEditedPrice`, el `TextFormField` "Tu Oferta", la validación "La oferta mínima es…".

```dart
// ✅ NUEVO: tarjeta de precio de sólo lectura
Widget _buildPrecioTarjeta(bool isDark, Cotizacion? c) {
  if (c == null) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4)),
      ),
    );
  }
  return Container(
    key: const Key('precio_plataforma_readonly'),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? AppTheme.darkCard : Colors.grey[100],
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.lock_outline, size: 16,
              color: isDark ? Colors.white54 : Colors.grey[600]),
          const SizedBox(width: 6),
          Text('Precio de la plataforma',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700])),
          const Spacer(),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(c.zonaNombre ?? 'Fuera de zona',
                style: GoogleFonts.plusJakartaSans(fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '\$ ${c.precioPlataforma.toStringAsFixed(2)} ${c.moneda}',
          key: const Key('precio_plataforma_valor'),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 28, fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87),
        ),
        Text(
          c.dentroDeZona
              ? 'Dentro de ${c.zonaNombre} · ${c.kmTotal.toStringAsFixed(1)} km'
              : c.fueraDeZona
                  ? 'Fuera de zona (tarifa municipal) · ${c.kmTotal.toStringAsFixed(1)} km'
                  : '${c.kmTotal.toStringAsFixed(1)} km · ${c.tarifaModo}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => PriceBreakdownSheet(cotizacion: c),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text('Ver desglose',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: AppTheme.primaryColor,
                  decoration: TextDecoration.underline)),
          ),
        ),
      ],
    ),
  );
}
```

CTA:

```dart
Future<void> _onSolicitar() async {
  final tp = context.read<TransportProvider>();
  final auth = context.read<AuthProvider>();
  final wallet = context.read<WalletProvider>();
  final c = tp.cotizacion;
  if (c == null) return;

  if (_metodo == 'wallet') {
    await wallet.loadClientBalance(auth.user?.id ?? '');
    if (!wallet.hasSufficientBalance(c.precioPlataforma)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saldo insuficiente: necesitas '
            '\$${c.precioPlataforma.toStringAsFixed(2)}'),
        backgroundColor: AppTheme.error));
      return;
    }
    tp.setPaymentMethod('wallet');
  } else {
    tp.setPaymentMethod('efectivo');
  }

  final ok = await tp.sendRequest(auth.user?.id ?? '');
  if (!mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tp.error ?? 'No se pudo publicar el viaje'),
      backgroundColor: AppTheme.error));
    return;
  }
  Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const SearchingDriverSheet()));
}
```

**Traducción de errores** (en `AppError`/`viaje_service`):

| PostgreSQL | Texto |
|---|---|
| `servicio_en_mantenimiento` | "El servicio de taxi está en actualización. Intenta en unos minutos." |
| `solicitud_activa_existente` | "Ya tienes un viaje activo. Cancélalo o espera a que termine." |
| `tipo_vehiculo_invalido` | "Tipo de vehículo no disponible." |
| `configuracion_tarifas_no_inicializada` | "No hay tarifa configurada. Contacta a soporte." |
| `no_autenticado` | "Tu sesión expiró. Vuelve a iniciar sesión." |

### 7.4 `available_trips_screen.dart` + tarjeta (chofer)

```dart
// lib/widgets/available_trip_card.dart — el texto exacto del requerimiento #4
class AvailableTripCard extends StatelessWidget {
  final ViajeDisponible viaje;
  final bool tomando;
  final VoidCallback? onTomar;

  const AvailableTripCard({
    super.key, required this.viaje,
    this.tomando = false, this.onTomar,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = viaje.puedeTomar && !tomando && onTomar != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(label: Text(viaje.tipoVehiculo.toUpperCase())),
              const SizedBox(width: 8),
              if (viaje.zonaNombre != null)
                Text(viaje.zonaNombre!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const Spacer(),
              const Icon(Icons.near_me_outlined, size: 14),
              const SizedBox(width: 4),
              Text('${viaje.distanciaAOrigenKm.toStringAsFixed(1)} km'),
            ]),
            const SizedBox(height: 8),
            Text(viaje.direccionOrigen ?? 'Origen',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('→ ${viaje.direccionDestino ?? 'Destino'}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Divider(height: 20),
            Text(
              'Cliente paga \$${viaje.precioPlataforma.toStringAsFixed(2)} ${viaje.moneda}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Te toca \$${viaje.precioChofer.toStringAsFixed(2)} '
              '(${viaje.comisionPct.toStringAsFixed(0)}% comisión)',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppTheme.success),
            ),
            if (viaje.deudaDisponible < 0)
              Text('Deuda disponible: \$${viaje.deudaDisponible.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: habilitado ? onTomar : null,
                child: tomando
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(habilitado
                        ? 'Tomar viaje'
                        : (viaje.motivoBloqueo ?? 'No disponible')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

`_tomar()` en la pantalla (manejo de carrera y de deuda):

```dart
Future<void> _tomar(ViajeDisponible v) async {
  setState(() => _tomando = v.solicitudId);
  try {
    final res = await _viajeService.tomarViaje(v.solicitudId);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ActiveRideScreen(tripData: {
        'solicitud_id': v.solicitudId,
        'viaje_id': res['viaje_id'],
        'precio': res['precio_plataforma'],
        'pago_chofer': res['precio_chofer'],
        'direccion_origen': v.direccionOrigen,
        'direccion_destino': v.direccionDestino,
        'lat_origen': v.latOrigen, 'lon_origen': v.lonOrigen,
        'lat_destino': v.latDestino, 'lon_destino': v.lonDestino,
        'user_id': v.userId,
      }),
    ));
    if (mounted) await _cargar();
  } on PostgrestException catch (e) {
    if (!mounted) return;
    final msg = e.message.contains('ya_tomado')
        ? 'Ese viaje ya fue tomado. Actualizando la lista…'
        : e.message.contains('limite_de_deuda_alcanzado')
            ? 'Alcanzaste tu límite de deuda. Recarga tu billetera para seguir tomando viajes en efectivo.'
            : e.message.contains('viaje_fuera_de_tu_zona')
                ? 'Ese viaje pertenece a otra zona.'
                : 'No se pudo tomar el viaje. Intenta de nuevo.';
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.warning));
    await _cargar();          // refresca: la tarjeta desaparece
  } finally {
    if (mounted) setState(() => _tomando = null);
  }
}
```

### 7.5 `wallet_service.dart` (H5)

```dart
// ❌ SE ELIMINAN: chargeDriverCommission, creditDriverForWalletPayment,
//    driverHasEnoughForCommission  (la aritmética vive en fn_completar_viaje)
// ❌ SE ELIMINA el literal 1.11 / '15%' de addFunds/addDriverFunds

// ✅ NUEVO: recarga centralizada
Future<Map<String, dynamic>> recargar({
  required String metodo,          // 'efectivo' | 'transferencia' | 'usd' ...
  required double monto,
  String? evidencia,
}) async {
  final res = await _supabase.schema('muevete').rpc('fn_recargar_wallet', params: {
    'p_metodo': metodo,
    'p_monto': monto,
    'p_evidencia': evidencia,
  });
  return Map<String, dynamic>.from(res as Map);
}
```

### 7.6 `completion_sync_service.dart` (H5)

```dart
static Future<void> enqueueCompletion({
  required int solicitudId,
  required int viajeId,
  int esperaMin = 0,
  DateTime? timestamp,
}) async { /* guarda {'v': 2, ...} en la misma clave pending_completions */ }

static Future<void> _syncOne(Map<String, dynamic> entry) async {
  final v = entry['v'] as int? ?? 1;
  if (v >= 2) {
    // Idempotente en servidor: si ya está completada devuelve idempotente=true
    await _supabase.schema('muevete').rpc('fn_completar_viaje', params: {
      'p_viaje_id': entry['viaje_id'],
      'p_espera_min': entry['espera_min'] ?? null,
    });
    return;
  }
  // Entrada v1 de una build anterior en el mismo dispositivo:
  // se descarta (el servidor ya no acepta precios del cliente) y se avisa.
  debugPrint('[CompletionSync] entrada legacy descartada: $entry');
}
```

### 7.7 Realtime y push (H2/H3)

- Cliente: `subscribeToSolicitud(id)` en `solicitudes_transporte` (filtro `id=eq.N`) → `driverAssigned`.
- Chofer: INSERT/UPDATE en `solicitudes_transporte` + **polling 10–15 s** (obligatorio mientras se confirma realtime).
- Push: el trigger `solicitudes_push` llama a la Edge Function externa. El mensaje debe pasar de "nueva solicitud / haz tu oferta" a **"Viaje disponible en tu zona: se cobra $X, te tocan $Y (Z %)"**, filtrando por `zona_id` + `id_tipo_vehiculo` (§9.6). **Plan B:** desactivar `solicitudes_push` y notificar localmente al detectar el viaje (realtime/polling), para no mandar copy incorrecto.

---

## 8. Cambios en `ventiq_superadmin/`

`flutter_map: ^7.0.2` y `latlong2: ^0.9.1` **ya están** en `ventiq_superadmin/pubspec.yaml` (líneas 40–41). No hay que añadir dependencias. El patrón de mapa/tiles ya existe en `lib/screens/muevete/muevete_map_screen.dart` (ArcGIS World Imagery, `FlutterMap` + `MarkerLayer`).

### 8.1 Archivos

| Archivo | Acción | Contenido |
|---|---|---|
| `lib/models/zona_tarifa.dart` | **NEW** | `ZonaTarifa` (puntos `LatLng` ↔ GeoJSON `[lon,lat]`), `TarifaMunicipio`, `ConfiguracionTarifas`, `CotizacionSimulada`. |
| `lib/services/muevete_tarifas_service.dart` | **NEW** | CRUD de zonas/municipios/config + `simular()` (RPC `fn_cotizar_viaje`). |
| `lib/screens/muevete/muevete_zonas_screen.dart` | **NEW** | Lista + estado + activar/desactivar + "Nueva zona" + acceso a parámetros y simulador. |
| `lib/screens/muevete/muevete_zona_editor_screen.dart` | **NEW** | Editor `flutter_map`: añadir vértice, deshacer, cerrar, validar, previsualizar, formulario de tarifa y prioridad. |
| `lib/screens/muevete/muevete_tarifas_config_screen.dart` | **NEW** | Parámetros globales (§2.3 del plan) + multiplicadores por tipo + tab de fallback municipal. |
| `lib/screens/muevete/muevete_tarifas_simulador_screen.dart` | **NEW** | Origen/destino/km/tipo/hora → precio cliente, comisión, neto y zona aplicada. |
| `lib/config/app_routes.dart` | **EDIT** | `/muevete/zonas`, `/muevete/zonas/editor`, `/muevete/tarifas`, `/muevete/tarifas/simulador` (grupo `Muévete`). |
| `lib/main.dart` | **EDIT** | Rutas con `RouteGuard`. |
| `lib/widgets/app_drawer.dart` | **EDIT** | Ítems "Zonas y Tarifas" y "Parámetros tarifarios" en el grupo *Inventtia Muévete*. |
| `lib/screens/muevete/muevete_requests_screen.dart` | **EDIT** | Tab "Ofertas" → histórico de sólo lectura; columnas `precio_plataforma`, `zona`, `estado`, comisión. |
| `lib/screens/muevete/muevete_trips_screen.dart` | **EDIT** | `precio_plataforma`, `precio_chofer`, `comision_pct`. |
| `lib/screens/muevete/muevete_wallets_screen.dart` | **EDIT** | Saldo negativo = deuda; badge "tope de deuda"; recargas con `recarga_pct`. |
| `lib/services/muevete_service.dart` | **EDIT** | Incluir los campos nuevos en `getRequests`/`getTrips`/`getDriverWallets`. |

### 8.2 Servicio

```dart
// lib/services/muevete_tarifas_service.dart
class MueveteTarifasService {
  static final _s = Supabase.instance.client;

  static Future<List<ZonaTarifa>> zonas({bool soloActivas = false}) async {
    var q = _s.schema('muevete').from('zonas_tarifa').select();
    if (soloActivas) q = q.eq('activo', true);
    final rows = await q.order('prioridad', ascending: false).order('nombre');
    return (rows as List)
        .map((e) => ZonaTarifa.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> guardarZona(ZonaTarifa z) async {
    final data = z.toJson();            // incluye geometria GeoJSON
    if (z.id == null) {
      await _s.schema('muevete').from('zonas_tarifa').insert(data);
    } else {
      await _s.schema('muevete').from('zonas_tarifa').update(data).eq('id', z.id!);
    }
  }

  static Future<void> setActivo(int id, bool activo) async {
    await _s.schema('muevete').from('zonas_tarifa')
        .update({'activo': activo}).eq('id', id);
  }

  static Future<void> eliminarZona(int id) async {
    // Preferir desactivar; borrar sólo si no hay historial
    final usos = await _s.schema('muevete').from('solicitudes_transporte')
        .select('id').eq('zona_id', id).limit(1);
    if ((usos as List).isNotEmpty) {
      await setActivo(id, false);
      throw Exception('La zona tiene viajes históricos: se desactivó en lugar de borrarse.');
    }
    await _s.schema('muevete').from('zonas_tarifa').delete().eq('id', id);
  }

  static Future<ConfiguracionTarifas> configuracion() async {
    final row = await _s.schema('muevete').from('configuracion_tarifas')
        .select().eq('id', 1).single();
    return ConfiguracionTarifas.fromJson(row);
  }

  static Future<void> guardarConfiguracion(ConfiguracionTarifas c) async {
    await _s.schema('muevete').from('configuracion_tarifas')
        .update(c.toJson()).eq('id', 1);
  }

  static Future<List<TarifaMunicipio>> municipios() async {
    final rows = await _s.schema('muevete').from('tarifas_municipio').select();
    return (rows as List)
        .map((e) => TarifaMunicipio.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> guardarMunicipio(TarifaMunicipio m) async {
    await _s.schema('muevete').from('tarifas_municipio')
        .upsert(m.toJson(), onConflict: 'provincia,municipio');
  }

  /// Mismo RPC que usa el cliente → el número del simulador es el real.
  static Future<Map<String, dynamic>> simular({
    required double latO, required double lonO,
    required double latD, required double lonD,
    required int idTipo,
    double? km,
    DateTime? at,
  }) async {
    final res = await _s.schema('muevete').rpc('fn_cotizar_viaje', params: {
      'p_lat_o': latO, 'p_lon_o': lonO,
      'p_lat_d': latD, 'p_lon_d': lonD,
      'p_id_tipo': idTipo,
      'p_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'p_km': km,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<List<Map<String, dynamic>>> tiposVehiculo() async {
    final rows = await _s.schema('muevete').from('vehicle_type')
        .select('id, tipo, multiplicador_tarifa, categoria, status')
        .eq('categoria', 'pasajero');
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
```

### 8.3 Editor de polígono (`muevete_zona_editor_screen.dart`)

```dart
class MueveteZonaEditorScreen extends StatefulWidget {
  final ZonaTarifa? zona;
  const MueveteZonaEditorScreen({super.key, this.zona});
  @override
  State<MueveteZonaEditorScreen> createState() => _MueveteZonaEditorScreenState();
}

class _MueveteZonaEditorScreenState extends State<MueveteZonaEditorScreen> {
  final MapController _map = MapController();
  final _formKey = GlobalKey<FormState>();

  final List<LatLng> _puntos = [];
  bool _cerrado = false;
  List<ZonaTarifa> _otras = [];
  List<Map<String, dynamic>> _tipos = [];

  late TextEditingController _nombre;
  late TextEditingController _provincia;
  late TextEditingController _municipio;
  late TextEditingController _montoFijo;
  late TextEditingController _precioKm;
  String _modo = 'fijo';
  int _prioridad = 100;
  bool _activo = true;
  DateTime? _vigenteHasta;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final z = widget.zona;
    _nombre    = TextEditingController(text: z?.nombre ?? '');
    _provincia = TextEditingController(text: z?.provincia ?? 'Villa Clara');
    _municipio = TextEditingController(text: z?.municipio ?? 'Santa Clara');
    _montoFijo = TextEditingController(text: (z?.montoFijo ?? 1500).toStringAsFixed(0));
    _precioKm  = TextEditingController(text: (z?.precioKm ?? 400).toStringAsFixed(0));
    if (z != null) {
      _modo = z.modo;
      _prioridad = z.prioridad;
      _activo = z.activo;
      _vigenteHasta = z.vigenteHasta;
      _puntos.addAll(z.puntos);
      _cerrado = _puntos.length >= 3;
    }
    _cargarContexto();
  }

  Future<void> _cargarContexto() async {
    final zonas = await MueveteTarifasService.zonas();
    final tipos = await MueveteTarifasService.tiposVehiculo();
    if (!mounted) return;
    setState(() {
      _otras = zonas.where((z) => z.id != widget.zona?.id).toList();
      _tipos = tipos;
      if (_puntos.isNotEmpty) _map.move(_puntos.first, 14);
    });
  }

  void _onMapTap(TapPosition _, LatLng p) {
    if (_cerrado) return;
    setState(() => _puntos.add(p));
  }

  void _deshacer() {
    if (_puntos.isEmpty) return;
    setState(() {
      if (_cerrado) {
        _cerrado = false;                 // primer "deshacer" reabre el polígono
      } else {
        _puntos.removeLast();
      }
    });
  }

  void _cerrar() {
    if (_puntos.length < 3) {
      _snack('Necesitas al menos 3 vértices');
      return;
    }
    final err = _validarGeometria(_puntos);
    if (err != null) { _snack(err); return; }
    setState(() => _cerrado = true);
    _snack('Polígono cerrado. Puedes seguir ajustando o guardar.');
  }

  String? _validarGeometria(List<LatLng> pts) {
    for (final p in pts) {
      if (p.latitude < 19.0 || p.latitude > 24.0 ||
          p.longitude < -86.0 || p.longitude > -73.0) {
        return 'Hay un vértice fuera de Cuba';
      }
    }
    // auto-intersección (segmentos no adyacentes)
    bool seg(LatLng a, LatLng b, LatLng c, LatLng d) {
      double cross(LatLng o, LatLng p, LatLng q) =>
          (p.longitude - o.longitude) * (q.latitude - o.latitude) -
          (p.latitude - o.latitude) * (q.longitude - o.longitude);
      final d1 = cross(c, d, a), d2 = cross(c, d, b);
      final d3 = cross(a, b, c), d4 = cross(a, b, d);
      return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
             ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
    }
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      for (var j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue;
        if (seg(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n])) {
          return 'El polígono se cruza a sí mismo (vértices ${i + 1} y ${j + 1})';
        }
      }
    }
    // área aproximada > 1000 m²
    double area = 0;
    for (var i = 0; i < n; i++) {
      final p1 = pts[i], p2 = pts[(i + 1) % n];
      area += p1.longitude * p2.latitude - p2.longitude * p1.latitude;
    }
    final m2 = (area.abs() / 2) * 111320 * 111320 * 0.75; // aproximación a 22° lat
    if (m2 < 1000) return 'El polígono es demasiado pequeño';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_cerrado || _puntos.length < 3) {
      _snack('Cierra el polígono antes de guardar');
      return;
    }
    final zona = ZonaTarifa(
      id: widget.zona?.id,
      nombre: _nombre.text.trim(),
      provincia: _provincia.text.trim().isEmpty ? null : _provincia.text.trim(),
      municipio: _municipio.text.trim().isEmpty ? null : _municipio.text.trim(),
      puntos: List.of(_puntos),
      modo: _modo,
      montoFijo: _modo == 'por_km' ? null : double.tryParse(_montoFijo.text),
      precioKm: _modo == 'fijo' || _modo == 'fijo_mas_km'
          ? double.tryParse(_precioKm.text) : double.tryParse(_precioKm.text),
      prioridad: _prioridad,
      activo: _activo,
      vigenteHasta: _vigenteHasta,
    );
    setState(() => _guardando = true);
    try {
      await MueveteTarifasService.guardarZona(zona);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.zona == null ? 'Nueva zona' : 'Editar zona'),
      actions: [
        IconButton(tooltip: 'Deshacer', onPressed: _deshacer,
            icon: const Icon(Icons.undo_rounded)),
        IconButton(tooltip: 'Guardar', onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded)),
      ],
    ),
    body: Row(children: [
      Expanded(flex: 3, child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: const LatLng(22.4069, -79.9657),
          initialZoom: 13,
          onTap: _onMapTap,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.inventtia.superadmin',
            maxZoom: 18, maxNativeZoom: 18,
          ),
          // Otras zonas como contexto
          PolygonLayer(polygons: [
            for (final z in _otras)
              if (z.puntos.length >= 3)
                Polygon(
                  points: z.puntos,
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderColor: Colors.blue.withValues(alpha: 0.55),
                  borderStrokeWidth: 1,
                  label: z.nombre,
                ),
          ]),
          // Zona en edición
          if (_cerrado && _puntos.length >= 3)
            PolygonLayer(polygons: [
              Polygon(
                points: _puntos,
                color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                borderColor: const Color(0xFF2563EB),
                borderStrokeWidth: 2.5,
              ),
            ]),
          if (!_cerrado && _puntos.length >= 2)
            PolylineLayer(polylines: [
              Polyline(points: _puntos, strokeWidth: 2.5,
                  color: const Color(0xFF2563EB)),
            ]),
          // Vértices: long-press para borrar
          MarkerLayer(markers: [
            for (var i = 0; i < _puntos.length; i++)
              Marker(
                point: _puntos[i], width: 26, height: 26,
                child: GestureDetector(
                  onLongPress: () => setState(() {
                    _puntos.removeAt(i);
                    _cerrado = false;
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: i == 0 ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(child: Text('$i',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
          ]),
        ],
      )),
      SizedBox(width: 380, child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(key: _formKey, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Toca el mapa para añadir vértices. Long-press en un vértice para borrarlo.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _cerrar,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_cerrado ? 'Polígono cerrado' : 'Cerrar polígono'),
              )),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() { _puntos.clear(); _cerrado = false; }),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ]),
            Text('${_puntos.length} vértices', style: const TextStyle(fontSize: 11)),
            const Divider(height: 24),
            TextFormField(controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
            Row(children: [
              Expanded(child: TextFormField(controller: _provincia,
                  decoration: const InputDecoration(labelText: 'Provincia'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _municipio,
                  decoration: const InputDecoration(labelText: 'Municipio'))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _modo,
              decoration: const InputDecoration(labelText: 'Modo de cálculo'),
              items: const [
                DropdownMenuItem(value: 'fijo',
                    child: Text('Fijo (al salir: km × precio/km)')),
                DropdownMenuItem(value: 'fijo_mas_km',
                    child: Text('Fijo + km × precio/km')),
                DropdownMenuItem(value: 'por_km', child: Text('Sólo por km')),
              ],
              onChanged: (v) => setState(() => _modo = v ?? 'fijo'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(controller: _montoFijo,
                  decoration: const InputDecoration(labelText: 'Monto fijo'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_modo == 'por_km') return null;
                    final n = double.tryParse(v ?? '');
                    return (n == null || n < 0) ? 'Requerido' : null;
                  })),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _precioKm,
                  decoration: const InputDecoration(labelText: 'Precio/km'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_modo == 'fijo') return null;
                    final n = double.tryParse(v ?? '');
                    return (n == null || n < 0) ? 'Requerido' : null;
                  })),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(
                  initialValue: '$_prioridad',
                  decoration: const InputDecoration(
                      labelText: 'Prioridad (mayor gana)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _prioridad = int.tryParse(v) ?? 100)),
              const SizedBox(width: 8),
              Expanded(child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa', style: TextStyle(fontSize: 13)),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              )),
            ]),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vigente hasta', style: TextStyle(fontSize: 13)),
              subtitle: Text(_vigenteHasta?.toString().split(' ').first ?? 'Sin límite'),
              trailing: IconButton(
                icon: const Icon(Icons.event),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) setState(() => _vigenteHasta = d);
                },
              ),
            ),
            const Divider(height: 24),
            const Text('Multiplicador por tipo (informativo)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final t in _tipos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(t['tipo'] as String? ?? '—')),
                  Text('×${t['multiplicador_tarifa'] ?? 1}'),
                ]),
              ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Guardar zona'),
            )),
          ],
        )),
      )),
    ]),
  );

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
```

`ZonaTarifa` ↔ GeoJSON:

```dart
// lib/models/zona_tarifa.dart
class ZonaTarifa {
  final int? id;
  final String nombre;
  final String? provincia, municipio;
  final List<LatLng> puntos;
  final String modo;
  final double? montoFijo, precioKm;
  final int prioridad;
  final bool activo;
  final DateTime? vigenteHasta;

  // ...

  /// GeoJSON Polygon: [ [ [lon,lat], ... ] ]
  Map<String, dynamic> get geometria => {
    'type': 'Polygon',
    'coordinates': [
      [for (final p in puntos) [p.longitude, p.latitude]],
    ],
  };

  static List<LatLng> puntosDesdeGeoJson(Map<String, dynamic> geojson) {
    final coords = (geojson['coordinates'] as List).first as List;
    return coords
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'nombre': nombre,
    'provincia': provincia,
    'municipio': municipio,
    'geometria': geometria,
    'modo': modo,
    'monto_fijo': montoFijo,
    'precio_km': precioKm,
    'prioridad': prioridad,
    'activo': activo,
    'vigente_hasta': vigenteHasta?.toUtc().toIso8601String(),
  };
}
```

### 8.4 Parámetros globales (`muevete_tarifas_config_screen.dart`)

Formulario sobre `configuracion_tarifas` con los campos de §2.3 del plan. Validaciones en Dart (además de los `CHECK`):

| Campo | Regla UI |
|---|---|
| Comisión % | 0–30; aviso si > 20 |
| Tope comisión | 0 = sin tope; 2 500 sugerido |
| Multiplicadores | 0,4–2,0 por tipo; aviso si auto ≠ 1,0 |
| Fallback municipal | fijo 500–5 000; precio/km 0–2 000; `modo=por_km` exige precio/km > 0 |
| Nocturno | 0–50 %; si > 0, `inicio ≠ fin` |
| Redondeo | 0/5/25/50/100 (el `CHECK` lo exige) |
| Límite de deuda | 0–5 000; aviso: "500 en lanzamiento, 1 000 tras 4 semanas (doc 03 §3.6)" |
| `taxi_precio_fijo_activo` | switch con confirmación + texto: "Apagado, la app nueva muestra 'servicio en mantenimiento'. Encendido, comienza el cobro con precio fijo." |

Guardado: `UPDATE` directo (la política `superadmin_all_configuracion_tarifas` lo permite) + `updated_at` por trigger. Mostrar `updated_at` y avisar si `precio_vigente_desde` tiene más de 30 días (revisión de precio del doc 03).

### 8.5 Simulador (`muevete_tarifas_simulador_screen.dart`)

- Mapa con dos marcadores (origen verde / destino rojo) que se colocan tocando.
- Campo `km` opcional (si vacío, el server usa haversine y lo marca `km_fuente='haversine'`).
- Dropdown de tipo de vehículo (de `vehicle_type`).
- Selector de fecha/hora (para probar el nocturno) → `p_at`.
- Resultado: **precio cliente**, **comisión**, **neto chofer**, **zona aplicada**, **modo**, desglose completo; aviso si `fallback_municipio=true`.
- Botón "Usar este trayecto como caso de prueba" → copia el JSON a la suite SQL (`docs/.../sql/test_cotizacion.sql`).

### 8.6 Rutas, drawer y permisos

```dart
// app_routes.dart — grupo 'Muévete'
AppRoute(route: '/muevete/zonas',            label: 'Zonas y Tarifas',      group: 'Muévete'),
AppRoute(route: '/muevete/zonas/editor',     label: 'Editor de zona',       group: 'Muévete'),
AppRoute(route: '/muevete/tarifas',          label: 'Parámetros tarifarios', group: 'Muévete'),
AppRoute(route: '/muevete/tarifas/simulador',label: 'Simulador de tarifa',  group: 'Muévete'),
```

```dart
// main.dart
'/muevete/zonas': (context) => const RouteGuard(
      route: '/muevete/zonas', child: MueveteZonasScreen()),
'/muevete/zonas/editor': (context) {
  final zona = ModalRoute.of(context)?.settings.arguments as ZonaTarifa?;
  return RouteGuard(route: '/muevete/zonas/editor',
      child: MueveteZonaEditorScreen(zona: zona));
},
'/muevete/tarifas': (context) => const RouteGuard(
      route: '/muevete/tarifas', child: MueveteTarifasConfigScreen()),
'/muevete/tarifas/simulador': (context) => const RouteGuard(
      route: '/muevete/tarifas/simulador', child: MueveteTarifasSimuladorScreen()),
```

El drawer tiene los ítems de Muévete hardcodeados (`app_drawer.dart:161–216`) y una condición `item.route.startsWith('/muevete/')` (`:490`): los dos ítems nuevos entran sin cambios estructurales. Permisos: `RouteGuard` usa `AppRoutes.protected`; se añaden las 4 rutas para que aparezcan en la pantalla de roles (`roles_screen.dart`).

---

## 9. Compatibilidad y migración

### 9.1 Estrategia por hitos (plan §8)

1. **H0 aditivo**: tablas/columnas nuevas con default, RPCs nuevas, seed completo. Apps actuales siguen igual porque `taxi_precio_fijo_activo=false` (el trigger de guarda no interviene). **Criterio del plan:** las apps actuales siguen funcionando.
2. **H1 aditivo**: RPCs de asignación y cierre. Nadie las llama todavía.
3. **Cutover** (cuando H2–H5 verificados): publicar superadmin → app chofer nueva → app cliente nueva → **subir versión mínima obligatoria** (`versiones_screen.dart` + `fn_check_update`) → aplicar `038` (RC hardening) → encender `taxi_precio_fijo_activo`.
4. **`ofertas_chofer`**: no se borra. Sólo lectura; se limpia en una migración posterior tras el periodo de gracia (plan §8.4).

### 9.2 Apps viejas en dispositivos

| Capa | Mecanismo |
|---|---|
| **Versión mínima** | `update_service.dart` ya llama `fn_check_update` y el diálogo bloqueante existe (`update_dialog_helper.dart`). Se configura `min_build` obligatorio en `/versiones` **antes** de revocar `038`. Es la capa que realmente saca las builds viejas. |
| **Flag** | Con `taxi_precio_fijo_activo=true`, `fn_crear_solicitud` funciona pero el INSERT directo de la app vieja lo bloquea el trigger (`usar_fn_crear_solicitud`) y la política (tras `038`). La app vieja muestra su snackbar genérico. |
| **Copy** | Recomendado en el diálogo: "El servicio de taxi ahora tiene precio fijo. Actualiza la app para seguir pidiendo viajes." |
| **Datos** | Apps viejas que lean `precio_oferta` siguen viéndolo: `fn_crear_solicitud` lo espeja con `precio_plataforma`. Apps viejas que lean `ofertas_chofer` siguen viendo el histórico. |

### 9.3 Datos históricos (backfill en `038`, antes del cutover)

```sql
BEGIN;

-- 1) Las filas previas al corte quedan con tarifa_modo = NULL y
--    tarifa_detalle = NULL: NULL == negociación legacy. No se rellena
--    artificialmente un "modo" que no existía.

-- 2) Precio congelado = última oferta aceptada, o el precio ofertado
UPDATE muevete.solicitudes_transporte s
   SET precio_plataforma = coalesce(
         (SELECT o.precio FROM muevete.ofertas_chofer o
           WHERE o.solicitud_id = s.id AND o.estado = 'aceptada'
           ORDER BY o.created_at DESC LIMIT 1),
         s.precio_oferta)
 WHERE s.precio_plataforma IS NULL;

-- 3) Comisión histórica (la que estaba vigente: 15 %)
UPDATE muevete.solicitudes_transporte
   SET comision_pct = 15.00
 WHERE comision_pct IS NULL;

UPDATE muevete.solicitudes_transporte
   SET precio_chofer = precio_plataforma - round(precio_plataforma * comision_pct / 100.0, 2)
 WHERE precio_plataforma IS NOT NULL AND precio_chofer IS NULL;

-- 4) Enlazar viajes con su solicitud cuando es inequívoco
UPDATE muevete.viajes v
   SET solicitud_id = sub.solicitud_id,
       precio_plataforma = sub.precio,
       metodo_pago = sub.metodo_pago
  FROM (
    SELECT DISTINCT ON (v2.id)
           v2.id AS viaje_id, o.solicitud_id, o.precio, s.metodo_pago
      FROM muevete.viajes v2
      JOIN muevete.solicitudes_transporte s
        ON s.user_id::text = v2."user" AND s.estado = 'completada'
      JOIN muevete.ofertas_chofer o
        ON o.solicitud_id = s.id AND o.estado = 'aceptada'
     WHERE v2.completado = true AND v2.solicitud_id IS NULL
     ORDER BY v2.id, o.created_at DESC
  ) AS sub
 WHERE v.id = sub.viaje_id AND v.solicitud_id IS NULL;

COMMIT;
```

Verificación:

```sql
SELECT count(*) FILTER (WHERE precio_plataforma IS NULL)     AS legacy_sin_precio,
       count(*) FILTER (WHERE precio_plataforma IS NOT NULL) AS con_precio,
       count(*) FILTER (WHERE tarifa_detalle IS NOT NULL)    AS con_desglose,
       count(*) FILTER (WHERE tarifa_modo IS NOT NULL)        AS con_modo
FROM muevete.solicitudes_transporte;
```

Las filas históricas se muestran sin desglose y con etiqueta "legacy"; no necesitan `zona_id`.

### 9.4 Script de ventana de corte

```sql
BEGIN;
-- Liberar retenciones de wallet de solicitudes abiertas y cancelarlas
UPDATE muevete.solicitudes_transporte
   SET estado = 'expirada'
 WHERE estado = 'pendiente'
   AND created_at < now() - interval '1 hour';

-- Reembolsar (si había hold) las aceptadas que se cortan
-- → ejecutar fn_cancelar_solicitud sobre cada una desde el script del operador
COMMIT;

-- Encender el flag (una sola fila)
UPDATE muevete.configuracion_tarifas
   SET taxi_precio_fijo_activo = true
 WHERE id = 1;
```

### 9.5 Rollback

1. `UPDATE muevete.configuracion_tarifas SET taxi_precio_fijo_activo = false WHERE id = 1;`
2. La app nueva muestra "servicio en mantenimiento" al intentar publicar (error `servicio_en_mantenimiento` ya traducido).
3. Las apps viejas vuelven a escribir por RLS (hasta que se aplique `038`; por eso `038` va **después** de confirmar el cutover).
4. Tiempo objetivo: < 2 minutos, verificado en H6.

### 9.6 Dependencia externa: Edge Function de push

No está en el repo. Contrato mínimo que necesita el trigger `solicitudes_push`:

```json
{
  "type": "INSERT",
  "table": "solicitudes_transporte",
  "record": {
    "id": 123, "zona_id": 7, "id_tipo_vehiculo": 2,
    "precio_plataforma": 1500, "precio_chofer": 1275,
    "lat_origen": 22.406, "lon_origen": -79.964, "estado": "pendiente"
  }
}
```

Acciones: (a) si es modificable, filtrar choferes por zona (polígono) + tipo + online + KYC y enviar "Viaje disponible: se cobra $X, te tocan $Y (Z %)"; (b) si no, **plan B**: desactivar `solicitudes_push` y notificar localmente al detectar el viaje (realtime/polling). Sin (a) ni (b), el push actual diría "haz tu oferta", copy incorrecto.

### 9.7 `precio_espera_min` (bug de nombres)

El plan §2.3 avisa: "ya existe en BD; corregir el bug de nombres". Verificado: `muevete.vehicle_type.precio_espera_min` existe y es `numeric`. **No se renombra** (rompería `vehicle_type_service`/admin); se usa en `fn_completar_viaje`. Si en H1 se confirma que el valor está mal cargado, se corrige con datos en `032`, no con esquema.

---

## 10. Plan de pruebas

Recordatorio del entorno: **antes de usar `flutter`/`dart`** fijar:

```powershell
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'
```

### 10.1 Paridad Dart ↔ SQL (criterio clave de H2)

El cliente muestra el precio **antes** de publicar con `TarifaCalculator` (Dart puro) o directamente con `fn_cotizar_viaje` (recomendado: RPC; el Dart sólo para offline). Ambos deben coincidir con el servidor.

1. **Vectores Dorados** desde SQL (staging), uno por caso:

```sql
SELECT jsonb_pretty(jsonb_agg(caso)) FROM (
  SELECT jsonb_build_object(
    'caso', 'dentro_zona_auto',
    'input', jsonb_build_object(
      'lat_o', 22.4070, 'lon_o', -79.9645, 'lat_d', 22.4120, 'lon_d', -79.9600,
      'id_tipo', 2, 'km', 3.2, 'at', '2026-11-12T10:00:00-05:00'),
    'output', muevete.fn_cotizar_viaje(
      22.4070, -79.9645, 22.4120, -79.9600, 2,
      '2026-11-12T10:00:00-05:00'::timestamptz, 3.2, 'Villa Clara', 'Santa Clara'))
  AS caso
  UNION ALL SELECT jsonb_build_object(
    'caso', 'nocturno_auto',
    'input', jsonb_build_object(/* ... */),
    'output', muevete.fn_cotizar_viaje(/* ... p_at 23:00 ... */))
  -- + 12 casos más: moto, microbus, camioneta, corto, fuera de zona,
  --   salida de zona, prima >8 km, tope de comisión, fallback municipal,
  --   solape de prioridad, vigencia expirada
) t;
```

Guardar en `inventtia_muevete/test/fixtures/cotizaciones_golden.json`.

2. **Test Dart** `test/utils/tarifa_calculator_test.dart`: para cada vector, `expect(calc.precioPlataforma, closeTo(server, 0.01))`; además tests de regresión de la fórmula (fijo dentro no depende de km; multiplicador; salida de zona = km × precio_km; redondeo hacia arriba; nocturno; tope de comisión).

3. **Recomendación:** que la app llame **siempre** a `fn_cotizar_viaje` para mostrar el precio (con caché por par origen/destino/tipo durante la pantalla) y use `TarifaCalculator` sólo si no hay red, marcando el precio como "estimado". Así se elimina la posibilidad de divergencia en producción.

### 10.2 Tests SQL unitarios (`docs/plan-taxi-precio-fijo/sql/test_cotizacion.sql`)

Todo en `BEGIN; … ROLLBACK;` con `ASSERT` (PL/pgSQL ≥ 9.5):

```sql
BEGIN;

DO $$
DECLARE
  v_zona_a bigint;
  v_zona_b bigint;
  v_r jsonb;
  v_ok boolean;
BEGIN
  -- Fixtures (no tocan las zonas reales)
  INSERT INTO muevete.zonas_tarifa
    (nombre, provincia, municipio, geometria, modo, monto_fijo, precio_km, prioridad, activo)
  VALUES
    ('TEST_A', 'Villa Clara', 'Santa Clara',
     '{"type":"Polygon","coordinates":[[[-79.980,22.400],[-79.960,22.400],[-79.960,22.420],[-79.980,22.420]]]}'::jsonb,
     'fijo', 1000, 100, 10, true),
    ('TEST_B', 'Villa Clara', 'Santa Clara',
     '{"type":"Polygon","coordinates":[[[-80.050,22.300],[-79.850,22.300],[-79.850,22.550],[-80.050,22.550]]]}'::jsonb,
     'fijo', 1500, 400, 0, true)
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_zona_a FROM muevete.zonas_tarifa WHERE nombre='TEST_A' ORDER BY id DESC LIMIT 1;
  SELECT id INTO v_zona_b FROM muevete.zonas_tarifa WHERE nombre='TEST_B' ORDER BY id DESC LIMIT 1;

  -- 1. Dentro del polígono y prioridad
  SELECT id INTO v_zona_a FROM muevete.fn_zona_de_punto(22.410, -79.970, now()) LIMIT 1;
  ASSERT v_zona_a IS NOT NULL, 'point-in-polygon falló';

  -- 2. Punto fuera de A pero dentro de B (B tiene prioridad menor → gana A si contiene)
  SELECT count(*) INTO v_ok FROM muevete.fn_zona_de_punto(22.520, -79.990, now());
  ASSERT v_ok = 1, 'solape/prioridad falló';

  -- 3. Fuera de todo → 0 filas
  SELECT count(*) INTO v_ok FROM muevete.fn_zona_de_punto(23.200, -82.300, now());
  ASSERT v_ok = 0, 'no debía resolver zona';

  -- 4. Zona inactiva se ignora
  UPDATE muevete.zonas_tarifa SET activo = false WHERE id = v_zona_a;
  SELECT count(*) INTO v_ok FROM muevete.fn_zona_de_punto(22.410, -79.970, now())
   WHERE id = v_zona_a;
  ASSERT v_ok = 0, 'zona inactiva no se ignoró';
  UPDATE muevete.zonas_tarifa SET activo = true WHERE id = v_zona_a;

  -- 5. Vigencia futura se ignora
  UPDATE muevete.zonas_tarifa SET vigente_desde = now() + interval '1 day' WHERE id = v_zona_a;
  SELECT count(*) INTO v_ok FROM muevete.fn_zona_de_punto(22.410, -79.970, now())
   WHERE id = v_zona_a;
  ASSERT v_ok = 0, 'vigencia futura no se respetó';
  UPDATE muevete.zonas_tarifa SET vigente_desde = now() WHERE id = v_zona_a;

  RAISE NOTICE 'PRUEBAS DE ZONA OK';
END $$;

ROLLBACK;
```

El archivo completo cubre los **14 casos de `03-modelo-economico.md` §8.3** (cotización 0/1/2 zonas, solape, salida de zona, fallback, multiplicadores, redondeo, nocturno, prima, corto, tope de comisión) — es el criterio de aceptación de H0.

### 10.3 Concurrencia de `fn_tomar_viaje` (criterio de H1)

Script `docs/plan-taxi-precio-fijo/sql/test_concurrencia.sql` con dos sesiones (el plan sugiere `pg_sleep`; se implementa así para que sea reproducible sin herramientas extra):

```sql
-- Sesión A (psql 1)
BEGIN;
SELECT pg_sleep(2);
SELECT muevete.fn_tomar_viaje(:sol_id);   -- debe tener éxito
COMMIT;
```

```sql
-- Sesión B (psql 2), lanzada simultáneamente
BEGIN;
SELECT pg_sleep(2);
SELECT muevete.fn_tomar_viaje(:sol_id);   -- debe lanzar ya_tomado
COMMIT;
```

Automatización en PowerShell con PostgREST (dos JWTs de chofer distintos, más representativo de la app):

```powershell
$uri = "$env:SUPABASE_URL/rest/v1/rpc/fn_tomar_viaje"
$base = @{ apikey = $env:SUPABASE_ANON_KEY
           'Content-Type' = 'application/json'
           'Accept-Profile' = 'muevete' }
$body = @{ p_solicitud_id = [int]$env:SOLICITUD_ID } | ConvertTo-Json

$res = @('JWT_CHOFER_1','JWT_CHOFER_2') | ForEach-Object -Parallel {
  $h = $using:base.Clone()
  $h['Authorization'] = "Bearer $((Get-Item "env:$_").Value)"
  try {
    $r = Invoke-RestMethod -Uri $using:uri -Method Post -Headers $h -Body $using:body
    [pscustomobject]@{ chofer = $_; ok = $true; viaje_id = $r.viaje_id }
  } catch {
    [pscustomobject]@{ chofer = $_; ok = $false; error = "$_" }
  }
} -ThrottleLimit 2

$res | Format-Table -AutoSize
if (($res | Where-Object ok).Count -ne 1) { throw 'FALLO: se esperaba exactamente 1 ganador' }
```

Verificación:

```sql
SELECT count(*) FROM muevete.viajes WHERE solicitud_id = :sol_id;      -- 1
SELECT estado, driver_id FROM muevete.solicitudes_transporte WHERE id = :sol_id;  -- aceptada, 1 driver
```

Repetir 20 veces. Criterio: **20/20 con 1 ganador, 1 viaje, 0 solicitudes duplicadas**.

### 10.4 Tests de RLS (`test_rls.sql`)

| Caso | Rol | Acción | Esperado |
|---|---|---|---|
| Cliente cambia precio | `authenticated` (cliente) | `UPDATE solicitudes_transporte SET precio_plataforma = 1` | error de privilegio/trigger |
| Cliente cambia estado | cliente | `UPDATE … SET estado='aceptada'` | error (después de `038`) |
| Chofer lee todo | chofer | `SELECT count(*) FROM solicitudes_transporte` | sólo las suyas/pendientes de su zona |
| Chofer edita saldo | chofer | `UPDATE wallet_drivers SET balance=999999` | error |
| Chofer inserta transacción | chofer | `INSERT INTO transacciones_wallet …` | error |
| Anon lee solicitudes | `anon` | `SELECT * FROM solicitudes_transporte` | 0 filas / error |
| Admin lee/escribe zonas | superadmin | CRUD `zonas_tarifa` | permitido |

### 10.5 E2E manual (matriz del anexo 02 §9, resumida)

| # | Caso | Resultado esperado |
|---|---|---|
| E2E-01 | Cliente pide en el centro, auto | Precio 1 500 (o el configurado), **sin campo editable**, desglose visible |
| E2E-02 | Alternar moto/auto/microbús | 900 / 1 500 / 2 250 (con mínimos de arranque) |
| E2E-03 | Chofer online dentro de la zona del origen | Ve "Cliente paga $1 500 · Te toca $1 275 (15 %)" |
| E2E-04 | Chofer online en otra zona | **No** ve el viaje |
| E2E-05 | Dos choferes tocan a la vez | Uno entra al viaje; el otro ve "ya fue tomado" y la tarjeta desaparece |
| E2E-06 | Chofer con saldo 0, tope de deuda 500, comisión 225 | Puede tomar; al cerrar queda en −225 y la billetera muestra deuda |
| E2E-07 | Chofer con deuda sobre el tope | Lista vacía / motivo "límite de deuda" |
| E2E-08 | Cliente con wallet suficiente | Se retiene al tomar; el chofer recibe el neto al cerrar; dos transacciones correctas |
| E2E-09 | Cliente cancela antes de que tomen | `cancelada`, desaparece de todas las listas |
| E2E-10 | Cliente cancela con viaje tomado y wallet | Reembolso, viaje cerrado, chofer notificado |
| E2E-11 | Sin choferes / TTL vencido | Pasa a `expirada`, desaparece |
| E2E-12 | Cierre offline | Se encola y sincroniza; sin doble cobro (idempotente) |
| E2E-13 | Superadmin dibuja zona nueva y la activa | Un viaje con origen dentro usa la tarifa nueva (validar antes en el simulador) |
| E2E-14 | Superadmin cambia comisión a 12 % | El siguiente viaje cobra 12 %; los ya publicados mantienen su snapshot |
| E2E-15 | Superadmin apaga el flag | La app nueva muestra "servicio en mantenimiento"; las apps viejas siguen operando (si no se aplicó `038`) |

### 10.6 Verificación estática y compilación

```powershell
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'

cd C:\Users\cesar\Documents\VentIQ-seller-App\inventtia_muevete
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

cd ..\ventiq_superadmin
flutter pub get
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

Alternativa: MCP de Dart del workspace (`dart analyze`, `dart fix`, `run_tests`). El criterio es el mismo: **0 issues y 0 tests rojos**.

---

## 11. Hitos H0–H6

Los hitos y sus criterios son los del `PLAN-IMPLEMENTACION.md` §6; aquí se añade el detalle técnico y las dependencias.

### H0 · Fundaciones de datos — *depende de: nada*

**Entregables:** `030`, `031`, `032`, `033`; `docs/.../sql/` con volcado de `pg_policies`/`pg_publication_tables` y `test_cotizacion.sql`; resolver la discrepancia de realtime (§1.2).
**Aceptación:**
- [ ] Migración idempotente (re-ejecutable) y `down` documentado.
- [ ] `fn_cotizar_viaje` devuelve los 14 casos de `03` §8.3 exactos.
- [ ] 7 tipos pasajeros con `multiplicador_tarifa`.
- [ ] `viajes.driver_id` migrado a `bigint` sin pérdida.
- [ ] Un cliente autenticado **no** puede INSERT/UPDATE de precio (trigger de guarda con el flag encendido en staging).
- [ ] Apps actuales siguen funcionando (flag apagado; smoke de publicar/ofertar/aceptar).
**Riesgo:** alto (esquema y dinero).

### H1 · RPCs de asignación y cierre — *depende de: H0*

**Entregables:** `035` (`fn_crear_solicitud`, `fn_cancelar_solicitud`), `036` (`fn_viajes_disponibles`, `fn_tomar_viaje`), `037` (`fn_completar_viaje`, `fn_recargar_wallet`), deprecación de `complete_ride_payment` **en el cliente** (el RPC no se redefine); `test_concurrencia.sql`; revocación de escrituras directas de `wallet_*`/`transacciones_wallet` (si el cutover se adelanta; si no, en `038`).
**Aceptación:**
- [ ] Concurrencia 20/20 (una gana, la otra recibe `ya_tomado`).
- [ ] `fn_completar_viaje` ignora cualquier precio del cliente (no hay parámetro de precio).
- [ ] Cambiar `comision_pct` 15 → 12 cambia el neto sin recompilar.
- [ ] Chofer en el tope de deuda no ve ni puede tomar; por debajo, sí.
- [ ] Viaje efectivo de 1 500 deja `wallet_drivers.balance = −225` + fila `comision_viaje`.
**Riesgo:** crítico (dinero + concurrencia).

### H2 · App cliente sin negociación — *depende de: H1*

**Entregables:** §7.1 (cliente) y §7.2–§7.5; `price_breakdown.dart`, `searching_driver_sheet.dart`; eliminar `driver_offers_screen.dart` y su ruta; ajustes en `ride_confirmed`, `request_history`, `home_map`, `background_service` (contrato con H3), `constants.dart`.
**Aceptación:**
- [ ] No queda ningún `TextFormField` de precio en el flujo del cliente.
- [ ] `flutter analyze` sin errores nuevos; test de que el precio mostrado == respuesta del servidor.
- [ ] `grep -r "precioOferta\|ofertas_chofer\|DriverOffer" lib/` sin resultados en flujo activo.
**Riesgo:** alto (8+ archivos). **Paralelizable con H3** (scopes disjuntos).

### H3 · App chofer: lista y toma — *depende de: H1*

**Entregables:** `available_trips_screen.dart`, `available_trip_card.dart`, reescritura de `incoming_requests_screen` y `driver_home_screen`, `driver_service`, `notification_model/service`, `background_service` (rama chofer), deprecación de `driver_offer_model/card`.
**Aceptación:**
- [ ] Chofer con wallet 0 puede tomar (D6) y queda en −comisión.
- [ ] Sobre el tope: lista vacía con motivo.
- [ ] Dos choferes a la vez: uno entra, el otro ve "ya fue tomado".
- [ ] La tarjeta muestra neto y % reales (incluido tope de comisión).
**Riesgo:** alto. **Paralelizable con H2.**

### H4 · Superadmin: Zonas y Tarifas — *depende de: H0*

**Entregables:** §8 (servicio, lista, editor, parámetros, simulador, rutas, drawer, permiso por rol, `muevete_requests_screen` en sólo lectura).
**Aceptación:**
- [ ] Dibujar polígono, guardar y que `fn_cotizar_viaje` lo aplique en < 1 s.
- [ ] El simulador muestra precio/comisión/neto y la zona aplicada.
- [ ] No se puede guardar polígono inválido ni tarifa incoherente (`fijo` sin monto, etc.).
- [ ] `flutter analyze` limpio; cambiar comisión se refleja sin recompilar la app del chofer.
**Riesgo:** alto (desarrollo nuevo; `carnaval_geo_admin_screen.dart` es un stub, no hay precedente).

### H5 · Dinero, cierre y offline — *depende de: H1, H2, H3*

**Entregables:** §7.5–§7.6; `wallet_screen`/`driver_wallet_screen`; recibo con snapshot en `ride_confirmed_screen`; `trip_completion_qr_service` sin precios y con secreto fuera del código; `038` (RC hardening). **`038` se aplica en el cutover**, nunca antes.
**Aceptación:**
- [ ] Cierre online, offline y por QR producen el mismo resultado; precios manipulados rechazados.
- [ ] Deuda visible en la billetera y liquidada al recargar.
- [ ] `038` aplicado en staging: los 7 tests de RLS pasan.
**Riesgo:** crítico.

### H6 · QA integral, compatibilidad y despliegue — *depende de: H0–H5*

**Entregables:** matriz E2E completa; `dart test` de paridad; SQL de concurrencia y RLS; `flutter analyze` en ambas apps; versión mínima obligatoria en `/versiones`; checklist de cutover y rollback; tablero de KPIs (anexo 02 §8).
**Aceptación:**
- [ ] Ningún viaje abierto queda huérfano al desplegar (script §9.4).
- [ ] Apps viejas bloqueadas por versión mínima antes de retirar escritura de `ofertas_chofer`.
- [ ] Rollback probado (< 2 min, flujo viejo operativo).
- [ ] Flag encendido en producción y E2E-01…E2E-15 verdes 48 h.
**Riesgo:** alto (coordinación).

### Diagrama de dependencias

```
H0 ──► H1 ──► H2 ─┐
 │      │     H3 ─┼──► H5 ──► H6
 └──────┴──► H4 ─┘
H2 ∥ H3 ∥ H4 (scopes disjuntos, ver plan §7)
```

### Orden de propiedad de archivos (plan §7)

| Hito | Write scope |
|---|---|
| H0 | `inventtia_muevete/docs/migrations/030-033*`, `docs/plan-taxi-precio-fijo/sql/` |
| H1 | `inventtia_muevete/docs/migrations/034-036*` |
| H2 | `inventtia_muevete/lib/screens/client/`, `providers/`, `services/transport_request_service.dart`, `widgets/price_breakdown.dart`, `widgets/searching_driver_sheet.dart` |
| H3 | `inventtia_muevete/lib/screens/driver/`, `services/driver_service.dart`, `background_service.dart`, `widgets/available_trip_card.dart` |
| H4 | `ventiq_superadmin/lib/screens/muevete/`, `services/`, `config/`, `widgets/` |
| H5 | `services/wallet_service.dart`, `completion_sync_service.dart`, `trip_completion_qr_service.dart`, `docs/.../037*` |
| H6 | `docs/`, sin código de producción |

**Frontera compartida:** `background_service.dart` es el único archivo que H2 y H3 comparten → lo toca **sólo H3**, y H2 le pide el cambio por contrato (canal de solicitud).

---

## 12. Desvíos propuestos (explícitos)

Nada de lo siguiente **renombra** el contrato; son adiciones u omisiones deliberadas. Cada una con su motivo y su coste de reversión.

| # | Desvío | Motivo | ¿Afecta el contrato? |
|---|---|---|---|
| **D-01** | `zonas_tarifa.codigo text UNIQUE` (adición) | El seed necesita identificador estable (MUN, FB, Z1…Z9) para ser idempotente (`ON CONFLICT`), y los logs/auditoría necesitan un nombre corto. Sin `codigo`, el seed por `nombre` es frágil. | No renombra; columna extra nullable. Reversible con `DROP COLUMN`. |
| **D-02** | `solicitudes_transporte.completada_at`, `cancelada_at`, `motivo_cancelacion`, `updated_at` (adición) | El anexo 02 modela 11 estados con timestamps y el superadmin los muestra. Sin ellos, el panel no puede responder "cuándo se completó/canceló". | No renombra; columnas extra. |
| **D-03** | Parámetros opcionales al final de las firmas: `fn_zona_de_punto(p_at)`, `fn_cotizar_viaje(p_at, p_km, p_provincia, p_municipio)`, `fn_crear_solicitud(p_provincia, p_municipio)`, `fn_viajes_disponibles(p_lat, p_lon, p_limite)`, `fn_completar_viaje(p_espera_min DEFAULT NULL)`, `fn_cancelar_solicitud(p_motivo DEFAULT NULL)`, `fn_recargar_wallet(p_evidencia DEFAULT NULL)` | Permiten tests deterministas (nocturno con `p_at`), preview sin datos de ruta (`p_km`), fallback municipal (`p_provincia`/`p_municipio`) y llamadas sin argumentos (`fn_viajes_disponibles()` como dice el contrato). **Un llamador que use la firma mínima del contrato sigue funcionando.** | No cambia nombres ni semántica; sólo agrega parámetros con default al final. |
| **D-04** | Helpers internos `fn_punto_en_anillo` y `fn_haversine_km` (no RPC, sin `GRANT` a `authenticated`) | Evitar duplicar el ray casting y la fórmula de distancia dentro de dos funciones. Son `plpgsql`/`sql` internos. | No expone superficie nueva. |
| **D-05** | **Clamp de `p_km`** en `fn_cotizar_viaje`: `least(greatest(p_km, haversine), haversine*2 + 1)` | El cliente envía la distancia de OSRM; sin cota, un cliente manipulado puede inflar/deflactar el precio. La cota es generosa (2× la recta + 1 km) para no castigar rutas reales con rodeos. Se marca `km_fuente='ruta'` para auditoría. | No cambia la fórmula; acota una entrada. |
| **D-06** | **Espera derivada del servidor**: `fn_completar_viaje` usa `viajes.tiempo_espera_segundos` cuando existe y sólo cae a `p_espera_min` si no hay medición; además acota por `tope_cobro_espera`. | `p_espera_min` es entrada del cliente y sería manipulable (cobrar 1 200 de espera en un viaje de 1 500). El servidor ya guarda segundos de espera. | Mantiene la firma `(p_viaje_id, p_espera_min)`; cambia la precedencia interna. |
| **D-07** | **Sin piso para tipos no configurados** (camioneta, minivan, tuktuk, bicicleta): su precio es `base × multiplicador`, sin `precio_minimo_*`. | `configuracion_tarifas` sólo define mínimos para auto/moto/microbús (contrato §4.1). Inventar mínimos para los otros 4 distorsiona (una bicicleta con piso de 1 500 sería absurdo). Si el negocio quiere piso, se añaden columnas en H1. | No cambia el contrato; lo interpreta. |
| **D-08** | `descuento_pago_wallet_pct` **se persiste pero no se aplica** en `fn_cotizar_viaje`. Devuelve el dato en `tarifa_detalle`/config para que H5 lo use si el negocio lo decide. | No está en la fórmula de §2.2. Aplicarlo silenciosamente cambiaría el precio respecto del contrato. | No aplica una regla no contratada. |
| **D-09** | **TTL de 15 minutos** de la solicitud fijo en `fn_crear_solicitud` (`now() + interval '15 minutes'`). | El contrato no define TTL y `solicitudes_transporte.expires_at` no tiene default. Se elige 15 min (más ágil que la hora actual para un flujo sin negociación). Si el negocio quiere parametrizarlo, se añade `ttl_solicitud_segundos` a `configuracion_tarifas` en H1 (una columna, un `UPDATE` en la función). | Hardcode temporal documentado. |
| **D-10** | Índices únicos parciales de invariantes (`ux_solicitudes_driver_activa`, `ux_solicitudes_user_abierta`) **no** en `030` sino en `038` con pre-chequeo. | Hay datos históricos que pueden duplicar; crear el índice a ciegas bloquea la migración (criterio H0 exige idempotencia). | No cambia el contrato; difiere una garantía. |
| **D-11** | Variante del filtro de visibilidad del chofer: además de la zona, se añade un filtro opcional de distancia (`p_radio_km`)… **no implementado**: la decisión del lead (zona del origen manda) se respeta tal cual. | — | Sin desvío; se documenta para que no se "mejore" sin querer. |
| **D-12** | **Discrepancia de realtime**: mi verificación (§1.2) no ve las tablas de `muevete` en `supabase_realtime`, el plan §2.5 sí. No se resuelve en este documento. | Puede ser otro proyecto/endpoint o el dashboard. | **Acción H0**: re-ejecutar la consulta y decidir; el diseño es tolerante (polling). |
| **D-13** | `configuracion_tarifas.monto_fijo_fallback_municipio` y `precio_km_fallback` (adición). | El plan §2.3 los exige como parámetros ("monto_fijo_fallback_municipio 1 500", "precio_km_fallback 400") pero §4.1 no los incluye en el DDL. Sin ellos, el fallback municipal sólo puede depender de `tarifas_municipio`, que puede estar vacío para el municipio del origen. | No renombra; dos columnas extra con default. Si el Lead prefiere, se eliminan y el fallback usa sólo `tarifas_municipio` + valores literales. |

Si el Lead prefiere no aceptar alguno, la reversión es local: D-01/D-02 son `DROP COLUMN`; D-03 son parámetros con default (se pueden quitar sin tocar llamadores); D-05/D-06/D-08/D-09 son líneas dentro de dos funciones; D-10 es mover el índice de archivo.

---

## 13. Supuestos

1. **PostGIS no se habilita** en este plan. Verificado: disponible pero no instalado; sin `CREATE EXTENSION` en el repo.
2. **El plan §2.5 es correcto en cuanto a datos de negocio** (7 tipos pasajeros, tarifas vigentes 800/200/250, 23 drivers, 55 solicitudes). La única discrepancia detectada es la publicación de realtime (§1.2 / D-12).
3. **`vehicle_type` tiene los 7 tipos pasajeros** al aplicar `032`. Si no, el `UPDATE` de multiplicadores no afecta filas y hay que sembrarlos antes (el seed de `032` lo verifica con un `RAISE NOTICE`).
4. **La Edge Function de push es externa** y no inspeccionable; se documenta contrato y plan B (§9.6).
5. **La actualización de la app se fuerza por `versiones`/`fn_check_update`**, no por stores. El cutover depende de esa capacidad.
6. **El cliente envía `p_km`** de `routing_service` (OSRM). Sin red, el servidor usa haversine y lo marca; el precio sigue siendo determinista y auditable.
7. **Un cliente = una solicitud abierta; un chofer = un viaje aceptado.** Se refuerza con índices únicos parciales (D-10).
8. **Manda el origen**: la zona del origen define la tarifa (contrato §2.2). Un viaje que sale de una zona barata a una cara paga la barata + `prima_distancia` si aplica.
9. **Los montos son CUP**; el `$` de la UI es decorativo; `moneda` viene de configuración.
10. **No se toca el flujo de carga (freight)**, `paradas_viaje` ni el 11 % de recarga más allá de centralizarlo en `fn_recargar_wallet`.
11. **Los nombres de este documento son el contrato de implementación.** Si un PR necesita cambiarlos, actualiza este documento y el cliente en el mismo PR.
12. **El backfill de `viajes.solicitud_id` es best-effort**: sin una oferta aceptada única no hay forma de reconstruir el vínculo; esas filas quedan `NULL` y el admin las muestra como "sin solicitud".

---

## 14. Riesgos

| # | Riesgo | Impacto | Prob. | Mitigación |
|---|---|---|---|---|
| R1 | **Point-in-polygon casero** cobra mal en bordes/huecos | Alto (dinero) | Media | Suite SQL (§10.2) con dentro/fuera/borde/hueco; prioridad y solapes; tests Dorados; revisión por pares del ray casting. |
| R2 | **Realtime no confirmado** (§1.2) → lista de viajes con latencia | Medio (UX) | Alta | Polling 10–15 s en `available_trips_screen` y `searching_driver_sheet`; verificar publicación en H0; no apostar la UX a realtime. |
| R3 | **Apps viejas** intentan publicar/ofertar y reciben error genérico | Alto (bloqueo) | Alta | Versión mínima obligatoria **antes** de `038`; flag; copy de actualización; monitoreo 48 h. |
| R4 | **Doble asignación** (si alguien "optimiza" el UPDATE) | Alto (visible) | Baja | El `UPDATE … WHERE estado='pendiente' RETURNING` es el único camino; test 20/20 en CI; revisión de PR. |
| R5 | **Deuda impaga** (D6) y chofer que abandona | Medio (negocio) | Media | Tope 500 al arranque, 1 000 tras 4 semanas (A2); panel de deudas en superadmin; alerta al 80 % del tope. |
| R6 | **Snapshot vs config**: cambiar la comisión no altera viajes en curso (deseado) pero sorprende a soporte | Bajo | Media | `comision_pct` visible en el desglose/recibo; el simulador usa config actual. |
| R7 | **`fn_completar_viaje` con dos cierres** (cliente y chofer a la vez) duplica transacciones | Alto (dinero) | Baja | `SELECT … FOR UPDATE` sobre viaje y solicitud + idempotencia por `estado='completada'`; test dedicado en H1. |
| R8 | **`038` aplicado antes de que las apps nuevas estén distribuidas** rompe el flujo actual | Crítico | Media | Orden del plan §8.3; `038` en el mismo checkpoint que la versión mínima; checklist firmado en H6. |
| R9 | **Push con copy viejo** ("haz tu oferta") | Medio (confusión) | Alta | Actualizar la Edge Function o desactivar `solicitudes_push` (plan B §9.6). |
| R10 | **Duplicados históricos** impiden crear los índices de invariantes | Medio | Media | Pre-chequeo en H0 (§2.10); saneo en `038`; no crear a ciegas. |
| R11 | **Editor de polígonos**: el admin dibuja mal (auto-intersección, zona gigante) y tarifica mal una ciudad | Alto (negocio) | Media | Validación en el editor (§8.3); zonas nuevas inactivas por defecto; simulador obligatorio antes de activar; logs `updated_at`. |
| R12 | **`precio_inside_sc`/`precio_km_default` deprecados** siguen usándose en algún rincón (p. ej. `vehicle_type_service`) | Bajo (inconsistencia visual) | Media | `grep` de esos campos en H2/H3/H4; dejar de usarlos en el flujo de pasajeros; mantenerlos sólo como dato histórico. |
| R13 | **`fn_recargar_wallet` centraliza el 11 %** y algún cliente viejo sigue insertando recargas directas | Bajo | Media | `038` revoca INSERT en `transacciones_wallet`; el flujo viejo moriría → por eso va en el cutover, junto con la versión mínima. |
| R14 | **Migración no idempotente** por triggers/índices existentes | Medio | Baja | `IF NOT EXISTS` en todo; `DROP TRIGGER IF EXISTS` antes de crear; probar dos veces en staging. |
| R15 | **Zona del origen vs destino** genera incentivo a pedir desde la zona barata | Medio | Media | Documentado (supuesto 8); `prima_distancia`; revisión mensual con datos; a futuro, tarificar por destino es un cambio sólo en `fn_cotizar_viaje`. |

---

## 15. Recomendación

1. **Ejecutar H0 + H1 primero, con `taxi_precio_fijo_activo=false`.** Son aditivos y desbloquean todo (incluido el simulador de H4). Con el simulador en staging, el negocio puede **calibrar precio y comisión antes de tocar una sola pantalla**: es el camino más corto a la información que hoy falta.
2. **Aceptar los desvíos D-01…D-10 como un paquete técnico**, no como cambio de contrato: añaden identificador estable, trazabilidad, parámetros opcionales y dos defensas anti-manipulación (distancia y espera) sin renombrar nada. Si hay que recortar, recortar D-02 y D-09 (son las menos críticas) y mantener D-05/D-06 (dinero).
3. **No negociar el orden del cutover:** RPC + apps nuevas + versión mínima → `038` → flag. Invertirlo es la única forma de romper producción con este plan.
4. **Presupuestar el editor de polígonos como el mayor esfuerzo de UI** (H4): no hay precedente en el repo (`carnaval_geo_admin_screen.dart` es un stub). Reutilizar el patrón de `muevete_map_screen.dart` (flutter_map 7, ArcGIS) y mantenerlo simple: tocar para añadir, long-press para borrar, cerrar, validar, guardar.
5. **Un solo camino de cálculo.** Que la app cliente, el chofer (para mostrar "te toca") y el simulador del superadmin llamen a la **misma** `fn_cotizar_viaje`. El espejo Dart es sólo para offline y para tests. Esto elimina la clase de bug más cara: precios distintos en pantallas distintas.
6. **Criterio de "terminado" del plan §13 como gate de release**, y no dar H6 por cerrado sin: concurrencia 20/20, 14 casos de cotización exactos, RLS verificado y rollback medido. El resto (mejoras de UX, zonas Z1–Z9 dibujadas, ajuste fino de precios) puede ir en releases posteriores sin bloquear.