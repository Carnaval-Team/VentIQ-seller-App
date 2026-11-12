# 09 · Identidad obligatoria y catálogo de vehículos (KYC + consentimiento + capacidad)

> **Rol:** programador / diseñador técnico.
> **Alcance:** migraciones `035` y `036` (esquema `muevete`), RPCs de identidad, gate de elegibilidad, catálogo ordenado de vehículos con capacidad, app `inventtia_muevete/` y consola `ventiq_superadmin/`.
> **Modo:** diseño. **No se ejecutó nada contra Supabase.** El único archivo escrito es este.
> **Dependede:** `PLAN-IMPLEMENTACION.md`, `02-modelo-negocio.md`, `04-diseno-tecnico.md`.
> **Fecha:** 2026-11-12 (America/Havana).
>
> ⚠️ **Este documento REEMPLAZA la numeración de migraciones de `04-diseno-tecnico.md` §2.1.** A partir de aquí:
> `031–034` = tarifas (ya escritas, **no se tocan**) · `035` = catálogo de vehículos · `036` = identidad + consentimiento · **`037` = seguridad del viaje** (anexo aparte, no forma parte de este documento) · `038–040` = RPCs de precio (con gate y capacidad) · `041` = RLS hardening.

---

## Índice

1. [Resumen ejecutivo y estado medido](#1-resumen-ejecutivo-y-estado-medido)
2. [Decisiones vinculantes](#2-decisiones-vinculantes)
3. [Migración `035_taxi_vehiculos_catalogo.sql`](#3-migración-035_taxi_vehiculos_catalogosql)
4. [Migración `036_taxi_identidad_consentimiento.sql`](#4-migración-036_taxi_identidad_consentimientosql)
5. [Gate de elegibilidad y dónde se valida](#5-gate-de-elegibilidad-y-dónde-se-valida)
6. [Parches obligatorios en `038–040` (precio)](#6-parches-obligatorios-en-038040-precio)
7. [Cambios en `inventtia_muevete/`](#7-cambios-en-inventtia_muevete)
8. [Cambios en `ventiq_superadmin/`](#8-cambios-en-ventiq_superadmin)
9. [Migración de los 41 usuarios existentes](#9-migración-de-los-41-usuarios-existentes)
10. [Compatibilidad, cutover y rollback](#10-compatibilidad-cutover-y-rollback)
11. [Criterios de aceptación y plan de pruebas](#11-criterios-de-aceptación-y-plan-de-pruebas)
12. [Riesgos](#12-riesgos)
13. [Desvíos / decisiones que necesito confirmar](#13-desvíos--decisiones-que-necesito-confirmar)

---

## 1. Resumen ejecutivo y estado medido

### 1.1 Qué se construye

| Capa | Entrega |
|---|---|
| **BD `035`** | `vehicle_type.orden`, `vehicle_type.pasajeros_max`, `vehicle_type.nombre_ui`; `solicitudes_transporte.pasajeros`; vista `v_catalogo_vehiculos`; helper `fn_capacidad_vehiculo()`; backfill de `vehiculos.capacidad_int`. |
| **BD `036`** | `users.poblado` (+ `kyc_estado`, `kyc_revisado_*`), `drivers.poblado/ci/direccion` (+ `kyc_estado`), tablas `documentos_legales` y `consentimientos`, singleton `configuracion_identidad`; RPCs `fn_usuario_habilitado`, `fn_aceptar_consentimiento`, `fn_guardar_identidad`, `fn_kyc_revisar`; RLS y triggers de guarda. |
| **`037`** | **Fuera de este anexo**: seguridad del viaje (contactos de emergencia, pánico, enlaces compartidos, incidentes, bloqueos). Aquí sólo se referencia para no confundir numeración. |
| **`038–040`** | `fn_crear_solicitud` / `fn_viajes_disponibles` / `fn_tomar_viaje` **llaman al gate** y validan `pasajeros`/capacidad. Se documenta el parche exacto. |
| **Cliente** | Selector de pasajeros + catálogo filtrado por capacidad y ordenado; pantalla de perfil/KYC (onboarding amable + bloqueo de la **operación**); documentos legales + aceptación. |
| **Superadmin** | Catálogo de vehículos (orden, nombre visible, capacidad, ocultar); revisión KYC con CI/docs/poblado; CRUD de documentos legales con versionado; auditoría de consentimientos. |

### 1.2 Estado medido (producción)

| Dato | Valor | Consecuencia |
|---|---|---|
| `muevete.users` | 18 filas · 3 con `ci` · 5 con `direccion` | 15/18 sin CI y 13/18 sin dirección → gate que les impide **operar** (publicar/tomar) hasta completar. |
| `muevete.drivers` | 23 filas · 1 con CI · 1 con dirección | Ídem; además el chofer ya tiene `kyc boolean` de aprobación. |
| `poblado` | **no existe** en ninguna de las dos tablas | Se crea en `036`. |
| Tablas de consentimiento / documentos legales | **no existen** | Se crean en `036`. |
| Tipos de vehículo activos | 7 pasajeros: moto, auto, microbus, camioneta, minivan, tuktuk, bicicleta | Hay que ocultar 2 y ordenar 5; **no se borra ninguno** (hay FKs históricas). |

### 1.3 Estado verificado del esquema (entorno de desarrollo; confirmar en prod en H0)

Consultado por SQL en el entorno accesible por MCP (**dev**; el entorno de producción es otro, `vsieeihstajlrdvpuooh`):

- `muevete.users` ya tiene: `ci varchar`, `tipo_documento text`, `doc_frente_url text`, `doc_dorso_url text`, `province`, `municipality`, `direccion`, `photo_url`, `uuid`. **No tiene** `poblado` ni estado KYC.
- `muevete.drivers` ya tiene: `carnet varchar` (hoy guarda el CI), `tipo_documento`, `doc_frente_url`, `doc_dorso_url`, `province`, `municipality`, `kyc bool`, `revisado bool`, `motivo text`. **No tiene** `ci`, `poblado` ni `direccion` como columnas propias.
- `muevete.vehiculos`: `capacidad varchar` **y** `capacidad_int integer` (esta última puede estar vacía; hay que backfillear).
- `muevete.vehicle_type`: `tipo text`, `status boolean`, `categoria text`, `precio_km_default`, `precio_inside_sc`, `precio_espera_min`. **No tiene** `orden`, `pasajeros_max` ni `nombre_ui`.
- RLS de `users`: existe una política **`users_` FOR ALL `USING (true) WITH CHECK (true)`** → cualquier autenticado puede leer y escribir todas las filas de usuarios. Con KYC (CI, fotos de carnet) eso es una fuga de datos personales: hay que cerrarla en `041` (y dejar preparado el terreno en `036`).
- RLS de `drivers`: propias (`uuid = auth.uid()`), flota (`dispatcher_id`) y superadmin. Correcta.
- `pgcrypto` está instalado (se usa para el hash de documentos legales).
- **No PostGIS** (irrelevante aquí, sin cambios de geometría).

> **Nota de honestidad:** el MCP de esta sesión apunta al entorno de desarrollo, donde las tablas están vacías. Las diferencias de columnas con producción se neutralizan con `ADD COLUMN IF NOT EXISTS` en `035/036`; el punto que **sí** requiere verificación en H0 es si en prod `drivers` ya tiene `ci`/`direccion` (la migración no falla en ningún caso, pero cambia si hay backfill que hacer desde `carnet`).

---

## 2. Decisiones vinculantes

| # | Decisión | Cómo se implementa | Consecuencia / trampa evitada |
|---|---|---|---|
| **E1** | Catálogo visible, **en este orden**: Auto, Minivan, Microbús, Moto, Triciclo Eléctrico | `vehicle_type.orden` + `nombre_ui` + vista `v_catalogo_vehiculos` (ORDER BY orden) | **No se renombra `vehicle_type.tipo`**: es clave funcional usada en `solicitudes_transporte.tipo_vehiculo`, `vehicle_type_service`, reglas de tarifa y textos. Se renombra **solo la etiqueta visible** (`nombre_ui`). `tuktuk` sigue siendo `tipo='tuktuk'` y se muestra "Triciclo Eléctrico". |
| **E2** | `bicicleta` y `camioneta` se ocultan, **no se borran** | `UPDATE vehicle_type SET status=false` | Hay históricos y FKs (`vehiculos.id_tipo_vehiculo`, `cargas.id_tipo_vehiculo`). Borrar rompería datos. |
| **E3** | Capacidad de pasajeros elegida por el cliente y filtrada por tipo | `solicitudes_transporte.pasajeros` + `vehicle_type.pasajeros_max` + `fn_capacidad_vehiculo()` | El filtro de UI es `pasajeros_max >= N`; la validación real es en servidor (crear y tomar) contra la capacidad **efectiva del vehículo** del chofer. |
| **E4** | KYC obligatorio y **no evadible** | Gate `muevete.fn_usuario_habilitado()` + validación dentro de las RPC de precio + bloqueo de la acción en la UI | No basta con esconder botones: `fn_crear_solicitud` y `fn_tomar_viaje` rechazan si el gate falla. Los datos sensibles se escriben sólo por RPC. |
| **E5** | Consentimiento obligatorio con **versión y auditoría** | `documentos_legales` + `consentimientos` (una fila por documento+versión+usuario) + validación en RPC | Sin fila de consentimiento de la **versión vigente** no se publica ni se toma viaje. La aceptación queda auditada con timestamp, método y app_version. |
| **E6** | Se exige también a los **41 usuarios existentes** | `kyc_estado='pendiente'` por defecto + gate que impide operar (sin bloquear el registro) | No se fabrican datos: cada usuario los completa. Sin backfill de consentimiento (no sería consentimiento real). |

---

## 3. Migración `035_taxi_vehiculos_catalogo.sql`

> Archivo: `inventtia_muevete/docs/migrations/035_taxi_vehiculos_catalogo.sql`
> Prerrequisitos: `030_baseline_sync_produccion.sql` (para `set_updated_at()`), `031–034` (tarifas).
> Idempotente. No redefine nada del baseline.

```sql
-- ============================================================================
-- 035_taxi_vehiculos_catalogo.sql
-- Catálogo de vehículos ordenado + capacidad de pasajeros.
-- Anexo: docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §3
-- ============================================================================
BEGIN;

-- ----------------------------------------------------------------------------
-- 1. vehicle_type: orden, capacidad máxima y nombre visible
--    OJO: `tipo` es la CLAVE funcional. NO se renombra.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.vehicle_type
  ADD COLUMN IF NOT EXISTS orden         smallint NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS pasajeros_max smallint NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS nombre_ui     text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'vehicle_type_orden_chk'
                    AND conrelid = 'muevete.vehicle_type'::regclass) THEN
    ALTER TABLE muevete.vehicle_type
      ADD CONSTRAINT vehicle_type_orden_chk
      CHECK (orden BETWEEN 0 AND 9999) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'vehicle_type_pasajeros_chk'
                    AND conrelid = 'muevete.vehicle_type'::regclass) THEN
    ALTER TABLE muevete.vehicle_type
      ADD CONSTRAINT vehicle_type_pasajeros_chk
      CHECK (pasajeros_max BETWEEN 1 AND 20) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS vehicle_type_catalogo_idx
  ON muevete.vehicle_type (orden, id)
  WHERE coalesce(status, true);

COMMENT ON COLUMN muevete.vehicle_type.orden IS
  'E1: orden del catálogo en la app del cliente. MENOR = primero. Configurable en superadmin.';
COMMENT ON COLUMN muevete.vehicle_type.pasajeros_max IS
  'E3: máximo de pasajeros que este TIPO admite. El cliente filtra por pasajeros_max >= pasajeros elegidos.';
COMMENT ON COLUMN muevete.vehicle_type.nombre_ui IS
  'E1: etiqueta visible. Permite renombrar (tuktuk -> "Triciclo Eléctrico") sin tocar la clave tipo.';

-- ----------------------------------------------------------------------------
-- 2. Catálogo: rename visible + orden + capacidad + ocultar 2 tipos
--    Se hace por lower(tipo) para no depender de ids (dev/prod pueden diferir).
-- ----------------------------------------------------------------------------
UPDATE muevete.vehicle_type SET
  nombre_ui     = v.nombre_ui,
  orden         = v.orden,
  pasajeros_max = v.pasajeros_max,
  status        = v.status
FROM (VALUES
  -- tipo        nombre_ui               orden  pasajeros_max  status
  ('auto',      'Auto',                    10,   4,             true),
  ('minivan',   'Minivan',                 20,   7,             true),
  ('microbus',  'Microbús',                30,  15,             true),
  ('moto',      'Moto',                    40,   1,             true),
  ('tuktuk',    'Triciclo Eléctrico',      50,   2,             true),
  -- E2: ocultos, NO borrados (hay históricos y FKs)
  ('camioneta', 'Camioneta',              900,   5,             false),
  ('bicicleta', 'Bicicleta',              910,   1,             false)
) AS v(tipo, nombre_ui, orden, pasajeros_max, status)
WHERE lower(muevete.vehicle_type.tipo) = v.tipo;

-- Si existieran tipos no listados, se les asigna una etiqueta legible.
UPDATE muevete.vehicle_type
   SET nombre_ui = initcap(tipo)
 WHERE nombre_ui IS NULL AND tipo IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. Capacidad efectiva por vehículo registrado
--    Feeente de verdad: vehiculos.capacidad_int; si es NULL, se intenta parsear
--    vehiculos.capacidad; si tampoco, se cae a vehicle_type.pasajeros_max.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_capacidad_vehiculo(p_vehiculo_id bigint)
RETURNS smallint
LANGUAGE sql STABLE
SET search_path = muevete, pg_temp
AS $$
  SELECT least(20, greatest(1, coalesce(
      veh.capacidad_int,
      CASE WHEN veh.capacidad ~ '^[0-9]{1,2}$' THEN veh.capacidad::integer END,
      vt.pasajeros_max,
      1
  )))::smallint
  FROM muevete.vehiculos veh
  LEFT JOIN muevete.vehicle_type vt ON vt.id = veh.id_tipo_vehiculo
  WHERE veh.id = p_vehiculo_id;
$$;

REVOKE ALL ON FUNCTION muevete.fn_capacidad_vehiculo(bigint) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION muevete.fn_capacidad_vehiculo(bigint) IS
  'INTERNA. Capacidad efectiva de un vehículo registrado (capacidad_int > capacidad parseada > pasajeros_max del tipo).';

-- Backfill de capacidad_int desde el texto libre donde sea inequívoco
UPDATE muevete.vehiculos
   SET capacidad_int = capacidad::integer
 WHERE capacidad_int IS NULL
   AND capacidad ~ '^[0-9]{1,2}$'
   AND capacidad::integer BETWEEN 1 AND 20;

-- ----------------------------------------------------------------------------
-- 4. solicitudes_transporte.pasajeros (E3)
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS pasajeros smallint NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'solicitudes_pasajeros_chk'
                    AND conrelid = 'muevete.solicitudes_transporte'::regclass) THEN
    ALTER TABLE muevete.solicitudes_transporte
      ADD CONSTRAINT solicitudes_pasajeros_chk
      CHECK (pasajeros BETWEEN 1 AND 20) NOT VALID;
  END IF;
END $$;

COMMENT ON COLUMN muevete.solicitudes_transporte.pasajeros IS
  'E3: cantidad de pasajeros declarada por el cliente. Snapshot; validada contra pasajeros_max y contra la capacidad del vehículo del chofer.';

-- ----------------------------------------------------------------------------
-- 5. Vista de catálogo para la app (una sola fuente de orden/etiqueta/filtro)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW muevete.v_catalogo_vehiculos AS
SELECT
  vt.id,
  lower(vt.tipo)                          AS tipo,
  coalesce(vt.nombre_ui, initcap(vt.tipo)) AS nombre,
  vt.orden,
  vt.pasajeros_max,
  vt.categoria,
  true                                    AS activo
FROM muevete.vehicle_type vt
WHERE coalesce(vt.status, true);

COMMENT ON VIEW muevete.v_catalogo_vehiculos IS
  'Catálogo de vehículos visible en la app del cliente, ya ordenado y con etiqueta UI.';

GRANT SELECT ON muevete.v_catalogo_vehiculos TO authenticated;

COMMIT;
```

**Verificación de `035`**

```sql
-- 1) Catálogo (esperado: 5 filas en el orden E1)
SELECT orden, tipo, nombre, pasajeros_max
  FROM muevete.v_catalogo_vehiculos
 ORDER BY orden;
--  10 auto Auto 4 | 20 minivan Minivan 7 | 30 microbus Microbús 15
--  40 moto Moto 1 | 50 tuktuk Triciclo Eléctrico 2

-- 2) Ocultos pero presentes (esperado: 2 filas, status=false)
SELECT tipo, status FROM muevete.vehicle_type
 WHERE lower(tipo) IN ('bicicleta','camioneta');

-- 3) Capacidad efectiva (con un vehículo real)
SELECT muevete.fn_capacidad_vehiculo(<vehiculo_id>);

-- 4) Idempotencia: re-ejecutar 035 no falla ni altera el orden ya editado
--    (los UPDATE reaplican los valores base; si el admin cambió `orden`,
--     volver a correr 035 lo devuelve al default — ver §13 D-2).
```

> ⚠️ **Sobre idempotencia y edición del admin:** los `UPDATE` de §2 son deterministas y **sobrescriben** `orden`/`nombre_ui`/`pasajeros_max`/`status` al re-ejecutarse. Eso es correcto para la primera aplicación, pero si el superadmin ya reordenó y alguien re-ejecuta la migración, se pierde el ajuste. Mitigación recomendada: ejecutar `035` **una sola vez** y, si se necesita re-aplicar en otro entorno, usar `WHERE ... AND updated_at = created_at` o simplemente no re-ejecutar. Se documenta como D-2 en §13.

---

## 4. Migración `036_taxi_identidad_consentimiento.sql`

> Archivo: `inventtia_muevete/docs/migrations/036_taxi_identidad_consentimiento.sql`
> Prerrequisitos: `030` (baseline: `is_superadmin`, `get_my_driver_id`, `set_updated_at`), `031` (configuración de tarifas), `035`.
> Idempotente. **No redefine** nada del baseline ni de `031–035`.

### 4.1 DDL

```sql
-- ============================================================================
-- 036_taxi_identidad_consentimiento.sql
-- KYC obligatorio + poblado + documentos legales versionados + consentimientos.
-- Anexo: docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §4
-- ============================================================================
BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Columnas de identidad en muevete.users
--    (ci, direccion, provincia, municipio, tipo_documento, doc_frente_url y
--     doc_dorso_url YA EXISTEN en dev; ADD COLUMN IF NOT EXISTS las cubre en prod)
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.users
  ADD COLUMN IF NOT EXISTS ci                  character varying,
  ADD COLUMN IF NOT EXISTS poblado              text,
  ADD COLUMN IF NOT EXISTS direccion            text,
  ADD COLUMN IF NOT EXISTS province             text,
  ADD COLUMN IF NOT EXISTS municipality         text,
  ADD COLUMN IF NOT EXISTS tipo_documento       text,
  ADD COLUMN IF NOT EXISTS doc_frente_url       text,
  ADD COLUMN IF NOT EXISTS doc_dorso_url        text,
  ADD COLUMN IF NOT EXISTS kyc_estado           text NOT NULL DEFAULT 'pendiente',
  ADD COLUMN IF NOT EXISTS kyc_motivo           text,
  ADD COLUMN IF NOT EXISTS kyc_revisado_por     uuid,
  ADD COLUMN IF NOT EXISTS kyc_revisado_at      timestamptz,
  ADD COLUMN IF NOT EXISTS perfil_completado_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'users_kyc_estado_chk'
                    AND conrelid = 'muevete.users'::regclass) THEN
    ALTER TABLE muevete.users
      ADD CONSTRAINT users_kyc_estado_chk
      CHECK (kyc_estado IN ('pendiente','en_revision','aprobado','rechazado')) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'users_ci_formato_chk'
                    AND conrelid = 'muevete.users'::regclass) THEN
    -- NOT VALID: no rompe filas históricas con CI sucio; el gate valida.
    ALTER TABLE muevete.users
      ADD CONSTRAINT users_ci_formato_chk
      CHECK (ci IS NULL OR ci ~ '^[0-9]{11}$') NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS users_ci_idx ON muevete.users (ci) WHERE ci IS NOT NULL;
CREATE INDEX IF NOT EXISTS users_kyc_estado_idx ON muevete.users (kyc_estado);

COMMENT ON COLUMN muevete.users.poblado IS
  'Poblado / reparto / consejo popular. Obligatorio para el gate de identidad.';
COMMENT ON COLUMN muevete.users.kyc_estado IS
  'pendiente | en_revision | aprobado | rechazado. El gate exige que no sea rechazado; si requiere_aprobacion_kyc_cliente=true exige aprobado.';

-- ----------------------------------------------------------------------------
-- 2. Columnas de identidad en muevete.drivers
--    drivers NO tiene ci/direccion/poblado en dev (usaba `carnet` para el CI).
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.drivers
  ADD COLUMN IF NOT EXISTS ci               character varying,
  ADD COLUMN IF NOT EXISTS poblado          text,
  ADD COLUMN IF NOT EXISTS direccion        text,
  ADD COLUMN IF NOT EXISTS kyc_estado       text NOT NULL DEFAULT 'pendiente',
  ADD COLUMN IF NOT EXISTS kyc_revisado_por uuid,
  ADD COLUMN IF NOT EXISTS kyc_revisado_at  timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'drivers_kyc_estado_chk'
                    AND conrelid = 'muevete.drivers'::regclass) THEN
    ALTER TABLE muevete.drivers
      ADD CONSTRAINT drivers_kyc_estado_chk
      CHECK (kyc_estado IN ('pendiente','en_revision','aprobado','rechazado')) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'drivers_ci_formato_chk'
                    AND conrelid = 'muevete.drivers'::regclass) THEN
    ALTER TABLE muevete.drivers
      ADD CONSTRAINT drivers_ci_formato_chk
      CHECK (ci IS NULL OR ci ~ '^[0-9]{11}$') NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS drivers_ci_idx ON muevete.drivers (ci) WHERE ci IS NOT NULL;
CREATE INDEX IF NOT EXISTS drivers_kyc_estado_idx ON muevete.drivers (kyc_estado);

-- Backfill: `carnet` guardaba el CI en el flujo viejo
UPDATE muevete.drivers
   SET ci = carnet
 WHERE ci IS NULL AND carnet ~ '^[0-9]{11}$';

-- Sincroniza el estado nuevo con los flags legacy (kyc/revisado)
UPDATE muevete.drivers
   SET kyc_estado = CASE
         WHEN coalesce(kyc, false) AND coalesce(revisado, false) THEN 'aprobado'
         WHEN coalesce(revisado, false) AND NOT coalesce(kyc, false) THEN 'rechazado'
         ELSE 'pendiente'
       END
 WHERE kyc_estado = 'pendiente';

-- ----------------------------------------------------------------------------
-- 3. muevete.documentos_legales (versionado + auditoría de publicación)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.documentos_legales (
  id              bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo          text        NOT NULL,             -- 'privacidad' | 'terminos' | 'kyc' ...
  version         text        NOT NULL,             -- '1.0.0'
  titulo          text        NOT NULL,
  resumen         text,
  contenido_md    text        NOT NULL,
  es_obligatorio  boolean     NOT NULL DEFAULT true,
  publicado       boolean     NOT NULL DEFAULT false,
  vigente_desde   timestamptz NOT NULL DEFAULT now(),
  vigente_hasta   timestamptz,
  hash_contenido  text,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT documentos_legales_pkey PRIMARY KEY (id),
  CONSTRAINT documentos_legales_codigo_version_unq UNIQUE (codigo, version),
  CONSTRAINT documentos_legales_vigencia_chk
    CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

-- Sólo puede haber UNA versión publicada y vigente por código
CREATE UNIQUE INDEX IF NOT EXISTS documentos_legales_vigente_uidx
  ON muevete.documentos_legales (codigo)
  WHERE publicado AND vigente_hasta IS NULL;

CREATE INDEX IF NOT EXISTS documentos_legales_codigo_idx
  ON muevete.documentos_legales (codigo, vigente_desde DESC);

-- Hash para auditar que el texto aceptado no cambió
CREATE OR REPLACE FUNCTION muevete.fn_doc_legal_hash()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, extensions, pg_temp
AS $$
BEGIN
  NEW.hash_contenido := encode(digest(coalesce(NEW.contenido_md, ''), 'sha256'), 'hex');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documentos_legales_hash ON muevete.documentos_legales;
CREATE TRIGGER trg_documentos_legales_hash
  BEFORE INSERT OR UPDATE OF contenido_md ON muevete.documentos_legales
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_doc_legal_hash();

DROP TRIGGER IF EXISTS trg_documentos_legales_updated_at ON muevete.documentos_legales;
CREATE TRIGGER trg_documentos_legales_updated_at
  BEFORE UPDATE ON muevete.documentos_legales
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

COMMENT ON TABLE muevete.documentos_legales IS
  'Documentos legales versionados. Al publicar una versión nueva se cierra la anterior (vigente_hasta). El hash permite probar qué texto aceptó cada usuario.';

-- ----------------------------------------------------------------------------
-- 4. muevete.consentimientos (auditoría; una fila por usuario+documento+versión)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.consentimientos (
  id                bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_uuid         uuid        NOT NULL,
  documento_id      bigint      NOT NULL,
  documento_codigo  text        NOT NULL,
  documento_version text        NOT NULL,
  aceptado          boolean     NOT NULL DEFAULT true,
  aceptado_at       timestamptz NOT NULL DEFAULT now(),
  metodo            text        NOT NULL DEFAULT 'app',
  app_version       text,
  user_agent        text,
  metadata          jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT consentimientos_pkey PRIMARY KEY (id),
  CONSTRAINT consentimientos_user_fkey FOREIGN KEY (user_uuid) REFERENCES auth.users(id),
  CONSTRAINT consentimientos_documento_fkey
    FOREIGN KEY (documento_id) REFERENCES muevete.documentos_legales(id),
  CONSTRAINT consentimientos_metodo_chk
    CHECK (metodo IN ('app','web','admin','migracion')),
  CONSTRAINT consentimientos_unq UNIQUE (user_uuid, documento_codigo, documento_version)
);

CREATE INDEX IF NOT EXISTS consentimientos_user_idx
  ON muevete.consentimientos (user_uuid, aceptado_at DESC);
CREATE INDEX IF NOT EXISTS consentimientos_doc_idx
  ON muevete.consentimientos (documento_codigo, documento_version);

COMMENT ON TABLE muevete.consentimientos IS
  'Evidencia de aceptación de documentos legales. Inmutable: se inserta, no se actualiza. Sólo por RPC.';

-- ----------------------------------------------------------------------------
-- 5. muevete.configuracion_identidad (singleton): staging y rollback del gate
--    Se añade porque el gate puede impedir operar a todos; hace falta poder relajarlo
--    (p. ej. durante una incidencia) sin desplegar código.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_identidad (
  id                            smallint    NOT NULL DEFAULT 1,
  kyc_obligatorio               boolean     NOT NULL DEFAULT true,
  consentimiento_obligatorio    boolean     NOT NULL DEFAULT true,
  requiere_aprobacion_kyc_cliente boolean   NOT NULL DEFAULT false,
  requiere_aprobacion_kyc_chofer  boolean   NOT NULL DEFAULT true,
  dias_gracia                   integer     NOT NULL DEFAULT 0,
  mensaje_bloqueo               text        NOT NULL DEFAULT
    'Para usar Muevete necesitas completar tu perfil y aceptar las políticas de privacidad.',
  -- Suspensión TEMPORAL del bloqueo (por si el gate deja la app sin choferes).
  -- Precedencia: si bloqueo_suspendido_hasta > now(), el gate relaja KYC y
  -- consentimiento sin borrar evidencia. Se reanuda solo al vencer, o antes
  -- con fn_suspender_bloqueo_identidad(0).
  bloqueo_suspendido_hasta      timestamptz,
  suspension_motivo             text,
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  updated_by                    uuid,

  CONSTRAINT configuracion_identidad_pkey PRIMARY KEY (id),
  CONSTRAINT configuracion_identidad_singleton CHECK (id = 1),
  CONSTRAINT configuracion_identidad_gracia_chk CHECK (dias_gracia BETWEEN 0 AND 90)
);

INSERT INTO muevete.configuracion_identidad (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_configuracion_identidad_updated_at ON muevete.configuracion_identidad;
CREATE TRIGGER trg_configuracion_identidad_updated_at
  BEFORE UPDATE ON muevete.configuracion_identidad
  FOR EACH ROW EXECUTE FUNCTION muevete.set_updated_at();

-- ----------------------------------------------------------------------------
-- 6. Trigger de guarda de identidad: los campos sensibles sólo por RPC
--    (mismo patrón que fn_solicitud_guarda de 031)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_identidad_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, pg_temp
AS $$
BEGIN
  IF coalesce(current_setting('muevete.rpc', true), 'off') = 'on' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.kyc_estado       IS DISTINCT FROM OLD.kyc_estado
       OR NEW.kyc_revisado_por IS DISTINCT FROM OLD.kyc_revisado_por
       OR NEW.kyc_revisado_at  IS DISTINCT FROM OLD.kyc_revisado_at
    THEN
      RAISE EXCEPTION 'kyc_solo_por_rpc_o_superadmin' USING ERRCODE = '42501';
    END IF;

    -- En users, CI/poblado/dirección/documentos sólo por fn_guardar_identidad
    IF TG_TABLE_NAME = 'users' THEN
      IF NEW.ci            IS DISTINCT FROM OLD.ci
         OR NEW.poblado     IS DISTINCT FROM OLD.poblado
         OR NEW.direccion   IS DISTINCT FROM OLD.direccion
         OR NEW.doc_frente_url IS DISTINCT FROM OLD.doc_frente_url
         OR NEW.doc_dorso_url  IS DISTINCT FROM OLD.doc_dorso_url
      THEN
        RAISE EXCEPTION 'usar_fn_guardar_identidad' USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_identidad_guarda ON muevete.users;
CREATE TRIGGER trg_users_identidad_guarda
  BEFORE UPDATE ON muevete.users
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_identidad_guarda();

DROP TRIGGER IF EXISTS trg_drivers_identidad_guarda ON muevete.drivers;
CREATE TRIGGER trg_drivers_identidad_guarda
  BEFORE UPDATE ON muevete.drivers
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_identidad_guarda();

COMMIT;
```

### 4.2 Funciones y RPCs de `036`

```sql
-- ============================================================================
-- 036 (continuación) · Validación de CI
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_ci_valido(p_ci text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v text := regexp_replace(coalesce(p_ci, ''), '\s', '', 'g');
BEGIN
  -- Carnet de identidad cubano: 11 dígitos (YYMMDD + consecutivo)
  IF v !~ '^[0-9]{11}$' THEN
    RETURN false;
  END IF;
  -- Validación de fecha (mes 01-12, día 01-31 y fecha real)
  IF substr(v, 3, 2)::integer NOT BETWEEN 1 AND 12 THEN
    RETURN false;
  END IF;
  IF substr(v, 5, 2)::integer NOT BETWEEN 1 AND 31 THEN
    RETURN false;
  END IF;
  BEGIN
    PERFORM to_date(substr(v, 1, 6), 'YYMMDD');
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION muevete.fn_ci_valido(text) IS
  'Valida formato de CI cubano (11 dígitos con fecha plausible). El registro civil NO se consulta: la verificación real es la revisión KYC del superadmin.';

REVOKE ALL ON FUNCTION muevete.fn_ci_valido(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION muevete.fn_ci_valido(text) TO authenticated;
```

```sql
-- ============================================================================
-- 036 (continuación) · RPC: gate de elegibilidad
--   Es la ÚNICA fuente de verdad para "puede operar".
--   Lo usan: la app (modo operar) y las RPC de precio 038–040.
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_usuario_habilitado(
  p_uuid uuid    DEFAULT auth.uid(),
  p_rol  text    DEFAULT NULL      -- 'cliente' | 'chofer' | NULL (autodetecta)
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  cfg            muevete.configuracion_identidad%ROWTYPE;
  v_uid          uuid := coalesce(p_uuid, auth.uid());
  v_rol          text;
  u              muevete.users%ROWTYPE;
  d              muevete.drivers%ROWTYPE;
  v_hay_user     boolean := false;
  v_hay_driver   boolean := false;
  v_faltantes    text[] := '{}';
  v_motivos      text[] := '{}';
  v_consent_ok   boolean := true;
  v_consent_falt text[] := '{}';
  v_kyc_ok       boolean := true;
  v_perfil_ok    boolean;
  v_habilitado   boolean;
  v_doc          record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO cfg FROM muevete.configuracion_identidad WHERE id = 1;
  IF NOT FOUND THEN
    -- Sin configuración no se bloquea a nadie (fail-open sólo si falta la fila)
    cfg.kyc_obligatorio := false;
    cfg.consentimiento_obligatorio := false;
    cfg.requiere_aprobacion_kyc_cliente := false;
    cfg.requiere_aprobacion_kyc_chofer := true;
    cfg.mensaje_bloqueo := NULL;
  END IF;

  -- Suspensión TEMPORAL del bloqueo (decisión operativa, no de datos):
  -- relaja KYC y consentimiento mientras esté vigente. La evidencia NO se borra.
  IF cfg.bloqueo_suspendido_hasta IS NOT NULL
     AND cfg.bloqueo_suspendido_hasta > now() THEN
    cfg.kyc_obligatorio := false;
    cfg.consentimiento_obligatorio := false;
  END IF;

  SELECT * INTO u FROM muevete.users WHERE uuid = v_uid LIMIT 1;
  v_hay_user := FOUND;

  SELECT * INTO d FROM muevete.drivers WHERE uuid = v_uid LIMIT 1;
  v_hay_driver := FOUND;

  v_rol := coalesce(
    p_rol,
    CASE WHEN v_hay_driver THEN 'chofer' WHEN v_hay_user THEN 'cliente' ELSE NULL END);

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'usuario_sin_perfil' USING ERRCODE = 'P0001';
  END IF;

  -- ── 1. Perfil / documentos ────────────────────────────────────────────
  IF v_rol = 'cliente' THEN
    IF NOT v_hay_user THEN
      v_faltantes := array_append(v_faltantes, 'perfil_cliente');
    ELSE
      IF NOT muevete.fn_ci_valido(u.ci) THEN v_faltantes := array_append(v_faltantes, 'ci'); END IF;
      IF coalesce(trim(u.tipo_documento), '') = '' THEN v_faltantes := array_append(v_faltantes, 'tipo_documento'); END IF;
      IF coalesce(trim(u.doc_frente_url), '') = '' THEN v_faltantes := array_append(v_faltantes, 'doc_frente'); END IF;
      IF coalesce(trim(u.doc_dorso_url), '') = '' THEN v_faltantes := array_append(v_faltantes, 'doc_dorso'); END IF;
      IF coalesce(trim(u.province), '') = '' THEN v_faltantes := array_append(v_faltantes, 'provincia'); END IF;
      IF coalesce(trim(u.municipality), '') = '' THEN v_faltantes := array_append(v_faltantes, 'municipio'); END IF;
      IF coalesce(trim(u.poblado), '') = '' THEN v_faltantes := array_append(v_faltantes, 'poblado'); END IF;
      IF coalesce(trim(u.direccion), '') = '' THEN v_faltantes := array_append(v_faltantes, 'direccion'); END IF;
    END IF;
  ELSE  -- chofer
    IF NOT v_hay_driver THEN
      v_faltantes := array_append(v_faltantes, 'perfil_chofer');
    ELSE
      IF NOT muevete.fn_ci_valido(d.ci) THEN v_faltantes := array_append(v_faltantes, 'ci'); END IF;
      IF coalesce(trim(d.tipo_documento), '') = '' THEN v_faltantes := array_append(v_faltantes, 'tipo_documento'); END IF;
      IF coalesce(trim(d.doc_frente_url), '') = '' THEN v_faltantes := array_append(v_faltantes, 'doc_frente'); END IF;
      IF coalesce(trim(d.doc_dorso_url), '') = '' THEN v_faltantes := array_append(v_faltantes, 'doc_dorso'); END IF;
      IF coalesce(trim(d.province), '') = '' THEN v_faltantes := array_append(v_faltantes, 'provincia'); END IF;
      IF coalesce(trim(d.municipality), '') = '' THEN v_faltantes := array_append(v_faltantes, 'municipio'); END IF;
      IF coalesce(trim(d.poblado), '') = '' THEN v_faltantes := array_append(v_faltantes, 'poblado'); END IF;
      IF coalesce(trim(d.direccion), '') = '' THEN v_faltantes := array_append(v_faltantes, 'direccion'); END IF;
    END IF;
  END IF;

  v_perfil_ok := array_length(v_faltantes, 1) IS NULL;

  -- ── 2. Estado KYC ─────────────────────────────────────────────────────
  IF v_rol = 'cliente' THEN
    IF cfg.kyc_obligatorio THEN
      IF v_hay_user AND u.kyc_estado = 'rechazado' THEN
        v_kyc_ok := false;
        v_motivos := array_append(v_motivos, 'kyc_rechazado');
      ELSIF cfg.requiere_aprobacion_kyc_cliente AND coalesce(u.kyc_estado, 'pendiente') <> 'aprobado' THEN
        v_kyc_ok := false;
        v_motivos := array_append(v_motivos, 'kyc_pendiente_aprobacion');
      END IF;
    END IF;
  ELSE
    IF v_hay_driver AND d.kyc_estado = 'rechazado' THEN
      v_kyc_ok := false;
      v_motivos := array_append(v_motivos, 'kyc_rechazado');
    ELSIF cfg.requiere_aprobacion_kyc_chofer AND coalesce(d.kyc_estado, 'pendiente') <> 'aprobado' THEN
      v_kyc_ok := false;
      v_motivos := array_append(v_motivos, 'kyc_pendiente_aprobacion');
    END IF;
  END IF;

  -- ── 3. Consentimientos de los documentos obligatorios vigentes ────────
  IF cfg.consentimiento_obligatorio THEN
    FOR v_doc IN
      SELECT dl.codigo, dl.version
        FROM muevete.documentos_legales dl
       WHERE dl.publicado
         AND dl.es_obligatorio
         AND (dl.vigente_hasta IS NULL OR dl.vigente_hasta > now())
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM muevete.consentimientos c
         WHERE c.user_uuid = v_uid
           AND c.documento_codigo = v_doc.codigo
           AND c.documento_version = v_doc.version
           AND c.aceptado
      ) THEN
        v_consent_ok := false;
        v_consent_falt := array_append(v_consent_falt,
                                       v_doc.codigo || '@' || v_doc.version);
      END IF;
    END LOOP;

    -- Sin documentos publicados no se puede exigir consentimiento (evita lockout)
    IF NOT EXISTS (SELECT 1 FROM muevete.documentos_legales
                    WHERE publicado AND es_obligatorio
                      AND (vigente_hasta IS NULL OR vigente_hasta > now())) THEN
      v_consent_ok := true;
      v_consent_falt := '{}';
    END IF;
  END IF;

  IF NOT v_consent_ok THEN
    v_motivos := array_append(v_motivos, 'consentimiento_pendiente');
  END IF;

  v_habilitado :=
        (NOT cfg.kyc_obligatorio OR v_perfil_ok)
    AND v_kyc_ok
    AND v_consent_ok
    AND (v_rol <> 'chofer' OR (v_hay_driver AND coalesce(d.kyc, false)))
    AND (v_rol <> 'cliente' OR v_hay_user);

  RETURN jsonb_build_object(
    'habilitado',        v_habilitado,
    'uuid',              v_uid,
    'rol',               v_rol,
    'kyc_obligatorio',   cfg.kyc_obligatorio,
    'consentimiento_obligatorio', cfg.consentimiento_obligatorio,
    'perfil', jsonb_build_object(
      'ok',          v_perfil_ok,
      'faltantes',   to_jsonb(v_faltantes),
      'kyc_estado',  CASE WHEN v_rol = 'cliente' THEN u.kyc_estado ELSE d.kyc_estado END
    ),
    'consentimiento', jsonb_build_object(
      'ok',        v_consent_ok,
      'faltantes', to_jsonb(v_consent_falt)
    ),
    'motivos',           to_jsonb(v_motivos),
    'mensaje',           cfg.mensaje_bloqueo,
    'bloqueo_suspendido', cfg.bloqueo_suspendido_hasta IS NOT NULL
                            AND cfg.bloqueo_suspendido_hasta > now(),
    'suspension_hasta',   cfg.bloqueo_suspendido_hasta,
    'operar_permitido',   v_habilitado
  );
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) TO authenticated;

COMMENT ON FUNCTION muevete.fn_usuario_habilitado(uuid, text) IS
  'RPC. Gate único de elegibilidad (perfil+CI+docs+poblado+dirección, KYC y consentimientos vigentes). Lo usan la app y las RPC de precio.';
```

> ✅ El SQL del bloque anterior es válido literal: no queda pseudocódigo. Las funciones se probaron por revisión estática (no se ejecutó nada contra Supabase).

```sql
-- ============================================================================
-- 036 (continuación) · RPC: aceptar consentimiento (auditado)
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_aceptar_consentimiento(
  p_codigo     text,
  p_version    text,
  p_metodo     text DEFAULT 'app',
  p_app_version text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_metadata   jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_doc muevete.documentos_legales%ROWTYPE;
  v_id  bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_doc
    FROM muevete.documentos_legales
   WHERE codigo = p_codigo AND version = p_version
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'documento_no_existe: %@%', p_codigo, p_version USING ERRCODE = 'P0042';
  END IF;
  IF NOT v_doc.publicado OR (v_doc.vigente_hasta IS NOT NULL AND v_doc.vigente_hasta <= now()) THEN
    RAISE EXCEPTION 'documento_no_vigente: %@%', p_codigo, p_version USING ERRCODE = 'P0043';
  END IF;

  INSERT INTO muevete.consentimientos
    (user_uuid, documento_id, documento_codigo, documento_version,
     aceptado, metodo, app_version, user_agent, metadata)
  VALUES
    (v_uid, v_doc.id, v_doc.codigo, v_doc.version,
     true, p_metodo, p_app_version, p_user_agent, coalesce(p_metadata, '{}'::jsonb))
  ON CONFLICT (user_uuid, documento_codigo, documento_version) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM muevete.consentimientos
     WHERE user_uuid = v_uid AND documento_codigo = v_doc.codigo
       AND documento_version = v_doc.version;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'consentimiento_id', v_id,
    'codigo', v_doc.codigo,
    'version', v_doc.version,
    'hash_contenido', v_doc.hash_contenido,
    'aceptado_at', now());
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_aceptar_consentimiento(text, text, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_aceptar_consentimiento(text, text, text, text, text, jsonb)
  TO authenticated;
```

```sql
-- ============================================================================
-- 036 (continuación) · RPC: guardar identidad (perfil + documentos)
--   Whitelist de campos. No permite tocar kyc_estado (eso es del superadmin).
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_guardar_identidad(
  p_rol   text,                    -- 'cliente' | 'chofer'
  p_datos jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_ci      text := nullif(trim(p_datos ->> 'ci'), '');
  v_poblado text := nullif(trim(p_datos ->> 'poblado'), '');
  v_dir     text := nullif(trim(p_datos ->> 'direccion'), '');
  v_prov    text := nullif(trim(p_datos ->> 'province'), '');
  v_muni    text := nullif(trim(p_datos ->> 'municipality'), '');
  v_tipo_doc text := nullif(trim(p_datos ->> 'tipo_documento'), '');
  v_frente  text := nullif(trim(p_datos ->> 'doc_frente_url'), '');
  v_dorso   text := nullif(trim(p_datos ->> 'doc_dorso_url'), '');
  v_nombre  text := nullif(trim(p_datos ->> 'name'), '');
  v_telefono text := nullif(trim(p_datos ->> 'telefono'), '');
  v_estado  text;
  v_gate    jsonb;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autenticado' USING ERRCODE = '28000';
  END IF;
  IF p_rol NOT IN ('cliente','chofer') THEN
    RAISE EXCEPTION 'rol_invalido: %', p_rol USING ERRCODE = 'P0001';
  END IF;
  IF v_ci IS NOT NULL AND NOT muevete.fn_ci_valido(v_ci) THEN
    RAISE EXCEPTION 'ci_invalido' USING ERRCODE = 'P0044';
  END IF;

  IF p_rol = 'cliente' THEN
    UPDATE muevete.users SET
      ci             = coalesce(v_ci, ci),
      poblado        = coalesce(v_poblado, poblado),
      direccion      = coalesce(v_dir, direccion),
      province       = coalesce(v_prov, province),
      municipality   = coalesce(v_muni, municipality),
      tipo_documento = coalesce(v_tipo_doc, tipo_documento),
      doc_frente_url = coalesce(v_frente, doc_frente_url),
      doc_dorso_url  = coalesce(v_dorso, doc_dorso_url),
      name           = coalesce(v_nombre, name),
      phone          = coalesce(v_telefono, phone),
      kyc_estado     = CASE
                         WHEN kyc_estado = 'rechazado' THEN 'en_revision'
                         WHEN kyc_estado = 'aprobado'  THEN 'aprobado'
                         ELSE 'en_revision'
                       END,
      perfil_completado_at = now()
    WHERE uuid = v_uid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'perfil_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSE
    UPDATE muevete.drivers SET
      ci             = coalesce(v_ci, ci),
      poblado        = coalesce(v_poblado, poblado),
      direccion      = coalesce(v_dir, direccion),
      province       = coalesce(v_prov, province),
      municipality   = coalesce(v_muni, municipality),
      tipo_documento = coalesce(v_tipo_doc, tipo_documento),
      doc_frente_url = coalesce(v_frente, doc_frente_url),
      doc_dorso_url  = coalesce(v_dorso, doc_dorso_url),
      name           = coalesce(v_nombre, name),
      telefono       = coalesce(v_telefono, telefono),
      kyc_estado     = CASE
                         WHEN kyc_estado = 'rechazado' THEN 'en_revision'
                         WHEN kyc_estado = 'aprobado'  THEN 'aprobado'
                         ELSE 'en_revision'
                       END
    WHERE uuid = v_uid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'perfil_chofer_no_existe' USING ERRCODE = 'P0045';
    END IF;
  END IF;

  v_gate := muevete.fn_usuario_habilitado(v_uid, p_rol);

  RETURN jsonb_build_object(
    'success', true,
    'rol', p_rol,
    'gate', v_gate);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_guardar_identidad(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_guardar_identidad(text, jsonb) TO authenticated;
```

```sql
-- ============================================================================
-- 036 (continuación) · RPC: revisión KYC (solo superadmin)
--   Mantiene sincronizados los flags legacy de drivers (kyc/revisado/motivo).
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_kyc_revisar(
  p_rol      text,     -- 'cliente' | 'chofer'
  p_uuid     uuid,
  p_decision text,     -- 'aprobado' | 'rechazado' | 'en_revision'
  p_motivo   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_decision NOT IN ('aprobado','rechazado','en_revision') THEN
    RAISE EXCEPTION 'decision_invalida: %', p_decision USING ERRCODE = 'P0001';
  END IF;

  IF p_rol = 'cliente' THEN
    UPDATE muevete.users
       SET kyc_estado       = p_decision,
           kyc_motivo       = p_motivo,
           kyc_revisado_por = auth.uid(),
           kyc_revisado_at  = now()
     WHERE uuid = p_uuid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'usuario_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSIF p_rol = 'chofer' THEN
    UPDATE muevete.drivers
       SET kyc_estado       = p_decision,
           kyc_revisado_por = auth.uid(),
           kyc_revisado_at  = now(),
           -- sincroniza flags legacy que usan las apps actuales
           kyc              = (p_decision = 'aprobado'),
           revisado         = (p_decision IN ('aprobado','rechazado')),
           motivo           = p_motivo
     WHERE uuid = p_uuid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'chofer_no_existe' USING ERRCODE = 'P0045';
    END IF;
  ELSE
    RAISE EXCEPTION 'rol_invalido: %', p_rol USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('success', true, 'rol', p_rol, 'uuid', p_uuid,
                            'decision', p_decision, 'revisado_at', now());
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_kyc_revisar(text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_kyc_revisar(text, uuid, text, text) TO authenticated;
```

```sql
-- ============================================================================
-- 036 (continuación) · RPC: suspender / reanudar el bloqueo de identidad
--   Válvula operativa: sólo superadmin. p_minutos = 0 reanuda de inmediato.
-- ============================================================================
CREATE OR REPLACE FUNCTION muevete.fn_suspender_bloqueo_identidad(
  p_minutos integer,
  p_motivo  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
DECLARE
  v_hasta timestamptz;
BEGIN
  IF NOT muevete.is_superadmin() THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_minutos IS NULL OR p_minutos < 0 OR p_minutos > 43200 THEN  -- max 30 días
    RAISE EXCEPTION 'minutos_invalidos: %', p_minutos USING ERRCODE = 'P0001';
  END IF;

  IF p_minutos = 0 THEN
    v_hasta := NULL;                       -- reanudar
  ELSE
    v_hasta := now() + make_interval(mins => p_minutos);
  END IF;

  UPDATE muevete.configuracion_identidad
     SET bloqueo_suspendido_hasta = v_hasta,
         suspension_motivo        = p_motivo,
         updated_by               = auth.uid()
   WHERE id = 1;

  RETURN jsonb_build_object(
    'success',       true,
    'suspendido',    v_hasta IS NOT NULL,
    'suspension_hasta', v_hasta,
    'motivo',        p_motivo);
END;
$$;

REVOKE ALL ON FUNCTION muevete.fn_suspender_bloqueo_identidad(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_suspender_bloqueo_identidad(integer, text) TO authenticated;
```

### 4.3 RLS de `036`

```sql
-- ============================================================================
-- 036 (continuación) · RLS
-- ============================================================================
ALTER TABLE muevete.documentos_legales   ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.consentimientos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.configuracion_identidad ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON muevete.documentos_legales, muevete.consentimientos,
              muevete.configuracion_identidad FROM anon;

-- Documentos: lectura de publicados/vigentes; superadmin todo
DROP POLICY IF EXISTS documentos_legales_select_auth ON muevete.documentos_legales;
CREATE POLICY documentos_legales_select_auth
  ON muevete.documentos_legales FOR SELECT TO authenticated
  USING (publicado OR muevete.is_superadmin());

DROP POLICY IF EXISTS superadmin_all_documentos_legales ON muevete.documentos_legales;
CREATE POLICY superadmin_all_documentos_legales
  ON muevete.documentos_legales FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

-- Consentimientos: cada usuario ve los suyos; superadmin ve todos.
-- NO hay política de INSERT/UPDATE/DELETE: sólo se escribe por RPC SECURITY DEFINER.
DROP POLICY IF EXISTS consentimientos_select_own ON muevete.consentimientos;
CREATE POLICY consentimientos_select_own
  ON muevete.consentimientos FOR SELECT TO authenticated
  USING (user_uuid = auth.uid());

DROP POLICY IF EXISTS superadmin_all_consentimientos ON muevete.consentimientos;
CREATE POLICY superadmin_all_consentimientos
  ON muevete.consentimientos FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

-- Configuración identidad: lectura autenticada; escritura superadmin
DROP POLICY IF EXISTS configuracion_identidad_select_auth ON muevete.configuracion_identidad;
CREATE POLICY configuracion_identidad_select_auth
  ON muevete.configuracion_identidad FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS superadmin_all_configuracion_identidad ON muevete.configuracion_identidad;
CREATE POLICY superadmin_all_configuracion_identidad
  ON muevete.configuracion_identidad FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

GRANT SELECT ON muevete.documentos_legales, muevete.configuracion_identidad TO authenticated;
GRANT SELECT ON muevete.consentimientos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON muevete.documentos_legales TO authenticated;
GRANT UPDATE ON muevete.configuracion_identidad TO authenticated;
-- consentimientos: sin INSERT/UPDATE/DELETE para authenticated (sólo RPC)

-- ----------------------------------------------------------------------------
-- 4.4 Acceso de lectura controlado entre usuarios (necesario para el viaje)
--   Actualmente `users` tiene una política users_ FOR ALL USING(true): cualquiera
--   lee/escribe todos los usuarios. Con CI y fotos de carnet eso es una fuga.
--   En 036 sólo se prepara la lectura mínima del chofer asignado; el cierre
--   definitivo de users_ va en 041 (hardening) para no romper otras pantallas
--   antes del cutover.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS users_select_conductor_asignado ON muevete.users;
CREATE POLICY users_select_conductor_asignado
  ON muevete.users FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM muevete.solicitudes_transporte s
       WHERE s.user_id = muevete.users.uuid
         AND s.driver_id = muevete.get_my_driver_id()
         AND s.estado IN ('aceptada','completada')
    )
  );
```

### 4.4 Seed de documentos y configuración (en `036`, idempotente)

```sql
-- ============================================================================
-- 036 (continuación) · Seed mínimo de documentos legales + configuración
--   ⚠️ El contenido es PLACEHOLDER. El texto legal real lo carga el superadmin
--   antes del cutover (bloqueante) o se reemplaza aquí en el repo.
-- ============================================================================
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md, es_obligatorio, publicado, vigente_desde)
VALUES
  ('privacidad', '1.0.0', 'Política de Privacidad',
   'Qué datos recogemos, para qué y durante cuánto tiempo.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\n## 1. Datos que recopilamos\n'
   || E'- Identificación: nombre, carnet de identidad, fotos del carnet.\n'
   || E'- Contacto: teléfono, correo.\n'
   || E'- Ubicación: necesaria para emparejar viajes.\n\n'
   || E'## 2. Uso de los datos\n'
   || E'Los datos se usan para prestar el servicio de transporte y cumplir obligaciones legales.\n\n'
   || E'## 3. Conservación y derechos\n'
   || E'Puedes solicitar acceso, rectificación o eliminación de tus datos.\n',
   true, true, now()),

  ('terminos', '1.0.0', 'Términos y Condiciones',
   'Reglas de uso del servicio de transporte.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\n## 1. Servicio\n'
   || E'Muevete conecta pasajeros con conductores. El precio lo fija la plataforma.\n\n'
   || E'## 2. Obligaciones del pasajero y del conductor\n'
   || E'Respeto, veracidad de los datos y cumplimiento de las normas de tránsito.\n\n'
   || E'## 3. Comisiones y pagos\n'
   || E'La comisión vigente se muestra en la app antes de aceptar un viaje.\n',
   true, true, now()),

  ('kyc', '1.0.0', 'Consentimiento de verificación de identidad',
   'Tratamiento de tu CI y de las fotos de tu carnet.',
   '<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del cutover -->'
   || E'\n\nAutorizas la verificación de tu identidad mediante el carnet de identidad '
   || E'y su revisión por el equipo de operaciones. Las imágenes se almacenan de forma '
   || E'restringida y sólo se usan para verificación.\n',
   true, true, now())
ON CONFLICT (codigo, version) DO NOTHING;

-- Configuración del gate: arranca exigiendo todo (E4/E5). Rollback = UPDATE.
UPDATE muevete.configuracion_identidad SET
  kyc_obligatorio                = true,
  consentimiento_obligatorio     = true,
  requiere_aprobacion_kyc_cliente = false,   -- el cliente no espera aprobación manual
  requiere_aprobacion_kyc_chofer  = true,    -- el chofer sí (ya era así)
  dias_gracia                    = 0,
  updated_at                     = now()
WHERE id = 1;
```

### 4.5 Verificación de `036`

```sql
-- 1) Columnas y tablas
SELECT column_name FROM information_schema.columns
 WHERE table_schema='muevete' AND table_name='users'
   AND column_name IN ('poblado','kyc_estado','kyc_revisado_por','perfil_completado_at');
SELECT column_name FROM information_schema.columns
 WHERE table_schema='muevete' AND table_name='drivers'
   AND column_name IN ('ci','poblado','direccion','kyc_estado');

-- 2) Documentos publicados (esperado 3, v1.0.0)
SELECT codigo, version, es_obligatorio, publicado, left(hash_contenido, 12) AS hash
  FROM muevete.documentos_legales ORDER BY codigo;

-- 3) Gate de un usuario cualquiera (debe salir habilitado=false con faltantes)
SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid>', 'cliente'));

-- 4) Consentimiento idempotente: llamar dos veces → mismo consentimiento_id
SELECT muevete.fn_aceptar_consentimiento('privacidad','1.0.0','app','1.6.0+42','test');
SELECT muevete.fn_aceptar_consentimiento('privacidad','1.0.0','app','1.6.0+42','test');

-- 5) Suspensión (5 min) y reanudación
SELECT muevete.fn_suspender_bloqueo_identidad(5, 'prueba');
SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid incompleto>', 'cliente'));  -- habilitado=true
SELECT muevete.fn_suspender_bloqueo_identidad(0, NULL);
SELECT jsonb_pretty(muevete.fn_usuario_habilitado('<uuid incompleto>', 'cliente'));  -- habilitado=false

-- 6) CI
SELECT muevete.fn_ci_valido('90010112345') AS ok,     -- true
       muevete.fn_ci_valido('90013212345') AS mes_malo, -- false
       muevete.fn_ci_valido('123')          AS corto;    -- false
```

---

## 5. Gate de elegibilidad y dónde se valida

### 5.1 Regla única

```
habilitado(cliente) =
      perfil_cliente_completo            -- CI válido + doc frente/dorso + provincia + municipio + poblado + dirección
  AND estado_kyc <> 'rechazado'
  AND (si requiere_aprobacion_kyc_cliente → estado_kyc = 'aprobado')
  AND consentimientos_vigentes_ok        -- todos los documentos obligatorios publicados

habilitado(chofer) =
      perfil_chofer_completo             -- idem + datos del vehículo (ya existentes)
  AND drivers.kyc = true                 -- aprobación legacy de conducción
  AND estado_kyc <> 'rechazado'
  AND (si requiere_aprobacion_kyc_chofer → estado_kyc = 'aprobado')
  AND consentimientos_vigentes_ok

-- Suspensión operativa (sólo si bloqueo_suspendido_hasta > now()):
--   se ignoran perfil, KYC y consentimiento, PERO:
--   · drivers.kyc = true (aprobación de conducción) NO se suspende
--   · la evidencia de consentimientos no se borra
```

Se implementa **sólo** en `muevete.fn_usuario_habilitado()` (§4.2). Ninguna app replica la lógica: la app muestra lo que el RPC dice.

### 5.2 Dónde se valida (defensa en profundidad)

| Punto | Validación | Efecto |
|---|---|---|
| **Arranque / registro / resume** | `rpc('fn_usuario_habilitado')` | **NO bloquea el registro ni la navegación**: onboarding + banner "Completa tu perfil". Se puede crear cuenta y explorar. |
| **Intento de publicar (cliente) o tomar (chofer)** | `ensureOperativo()` + validación en la RPC | Si `habilitado=false` → pantalla de perfil en modo **operar** (sin "Ahora no") y la RPC rechaza. |
| **Antes de cotizar/publicar** (UI) | mismo RPC cacheado | Botón "Solicitar" deshabilitado con motivo. |
| **`fn_crear_solicitud` (038)** | `IF NOT (fn_usuario_habilitado(...)->>'habilitado')::boolean THEN RAISE 'perfil_incompleto'` | **No evadible** desde un cliente modificado. |
| **`fn_viajes_disponibles` (039)** | gate del chofer para devolver lista (o `puede_tomar=false` con `motivo_bloqueo='identidad_incompleta'`) | El chofer sin KYC no ve viajes. |
| **`fn_tomar_viaje` (039)** | gate del chofer **y** capacidad del vehículo ≥ `solicitud.pasajeros` | **No evadible**: aunque la UI esté manipulada. |
| **`fn_completar_viaje` (040)** | gate del chofer (aviso: no bloquea el cierre si el KYC se rechazó *durante* el viaje; se permite cerrar y se marca para revisión) | Evita dejar viajes abiertos. |

### 5.3 Contrato del gate (JSON que consume la app)

```json
{
  "habilitado": false,
  "uuid": "…",
  "rol": "cliente",
  "kyc_obligatorio": true,
  "consentimiento_obligatorio": true,
  "perfil": { "ok": false, "faltantes": ["ci","doc_frente","doc_dorso","poblado"], "kyc_estado": "pendiente" },
  "consentimiento": { "ok": false, "faltantes": ["privacidad@1.0.0","terminos@1.0.0","kyc@1.0.0"] },
  "motivos": ["consentimiento_pendiente"],
  "mensaje": "Para usar Muevete necesitas completar tu perfil y aceptar las políticas de privacidad."
}
```

La UI traduce `faltantes` a campos concretos del formulario y `consentimiento.faltantes` a los checkboxes/links.

---

### 5.4 Modo operar vs modo registro (decisión de producto)

| Capacidad | Sin perfil completo | Con perfil completo |
|---|---|---|
| Crear cuenta / iniciar sesión | ✅ Permitido | ✅ Permitido |
| Ver mapa, tarifas, historial, billetera | ✅ Permitido (sólo lectura) | ✅ Permitido |
| Editar perfil / subir documentos / aceptar legales | ✅ Es justo lo que se le pide | ✅ Re-aceptar nuevas versiones |
| **Publicar un viaje (cliente)** | ❌ Bloqueado (UI + RPC `perfil_incompleto`) | ✅ |
| **Tomar un viaje (chofer)** | ❌ Bloqueado (UI + RPC `perfil_incompleto_chofer`) | ✅ |
| Recargar billetera | ⚠️ Permitido con **consentimiento** aceptado; no exige perfil completo | ✅ |

Consecuencias de diseño:
- **No se mata la conversión**: el registro no depende de tener CI ni fotos a mano; el usuario entra, explora y completa después.
- Tras login/registro con perfil incompleto: `PerfilRequeridoScreen` en modo `onboarding` con **"Ahora no"** (vuelve al home en modo lectura) + banner persistente.
- Al pulsar **"Solicitar viaje"** o **"Tomar viaje"**, `ensureOperativo()` abre el formulario en modo `operar` (**sin** "Ahora no"); si se cierra, la acción no se ejecuta.
- La pantalla siempre permite **cerrar sesión** (no se deja al usuario sin salida).
- **La RPC manda**: un APK modificado que salte la UI recibe `perfil_incompleto` / `perfil_incompleto_chofer`.

### 5.5 Suspensión del bloqueo (válvula de seguridad operativa)

Problema que resuelve: si el gate deja la app sin choferes operativos (una tanda de KYC mal rechazada, un fallo de subida de documentos), el negocio no puede esperar a un deploy.

**Cómo se activa** (sólo superadmin, RPC o SQL):

```sql
-- Suspender 120 minutos (relaja perfil + KYC + consentimiento)
SELECT muevete.fn_suspender_bloqueo_identidad(120, 'Incidente de subida de documentos');
-- Reanudar antes de que venza
SELECT muevete.fn_suspender_bloqueo_identidad(0, NULL);
-- Equivalente manual (no recomendado: no deja rastro del motivo)
UPDATE muevete.configuracion_identidad
   SET bloqueo_suspendido_hasta = now() + interval '120 minutes',
       suspension_motivo = 'Incidente de subida de documentos'
 WHERE id = 1;
```

**Qué pasa con los viajes en curso al suspender / reanudar:**

| Estado del viaje | Suspensión | Reanudación |
|---|---|---|
| `pendiente` (publicado, sin chofer) | Permanece; choferes sin perfil vuelven a poder tomarlo. | Sigue visible hasta `expires_at`; si nadie lo toma, expira por TTL (no se cancela en masa). |
| `aceptada` (en curso) | **No se toca**: se completa y liquida normal. El gate nunca interrumpe un viaje asignado. | Ídem; `fn_completar_viaje` no bloquea el cierre por KYC (sólo avisa a operaciones si se rechazó a mitad). |
| Wallet retenido | Se mantiene la retención; el cierre cobra y liquida como siempre. | Ídem. |
| Cancelación | `fn_cancelar_solicitud` no consulta el gate. | Ídem. |

Precedencia:
1. `bloqueo_suspendido_hasta > now()` → `kyc_obligatorio` y `consentimiento_obligatorio` se tratan como `false`.
2. `drivers.kyc = true` (aprobación de conducción) **no** se suspende: si faltan choferes aprobados, la palanca es aprobarlos, no desactivar la verificación.
3. Al vencer la suspensión el gate vuelve solo; **no** se borran consentimientos ni estados KYC.
4. Queda registrada (`suspension_motivo`, `updated_by`) y se muestra como aviso rojo en superadmin mientras esté activa.

## 6. Parches obligatorios en `038–040` (precio)

> Estos archivos aún no existen (se escriben en la tarea de RPCs). Para que el gate y la capacidad sean **no evadibles**, deben incluir exactamente esto:

### 6.1 `038` · `fn_crear_solicitud`

```sql
-- Firma: añadir p_pasajeros (aditivo al final, con default)
CREATE OR REPLACE FUNCTION muevete.fn_crear_solicitud(
  p_lat_o double precision, p_lon_o double precision,
  p_lat_d double precision, p_lon_d double precision,
  p_id_tipo bigint, p_dir_o text, p_dir_d text,
  p_km double precision, p_metodo_pago text,
  p_provincia text DEFAULT NULL, p_municipio text DEFAULT NULL,
  p_pasajeros integer DEFAULT 1          -- NUEVO (E3)
) RETURNS muevete.solicitudes_transporte
...
DECLARE
  v_gate jsonb;
  v_cap_tipo smallint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  -- (E4/E5) Gate de identidad + consentimiento: NO EVADIBLE
  v_gate := muevete.fn_usuario_habilitado(auth.uid(), 'cliente');
  IF NOT coalesce((v_gate ->> 'habilitado')::boolean, false) THEN
    RAISE EXCEPTION 'perfil_incompleto: %', v_gate -> 'motivos' USING ERRCODE = 'P0050';
  END IF;

  -- (E3) Capacidad declarada vs capacidad máxima del TIPO
  SELECT pasajeros_max INTO v_cap_tipo
    FROM muevete.vehicle_type WHERE id = p_id_tipo;
  IF p_pasajeros IS NULL OR p_pasajeros < 1 OR p_pasajeros > coalesce(v_cap_tipo, 1) THEN
    RAISE EXCEPTION 'capacidad_excedida_tipo: % > %', p_pasajeros, v_cap_tipo
      USING ERRCODE = 'P0051';
  END IF;

  -- ... cotizar, insertar, etc. (incluir pasajeros en el INSERT)
END;
```

Y en el `INSERT` de la solicitud: columna `pasajeros` con `p_pasajeros`.

### 6.2 `039` · `fn_viajes_disponibles` y `fn_tomar_viaje`

```sql
-- fn_viajes_disponibles: filtrar por capacidad del vehículo del chofer
--   v_capacidad := muevete.fn_capacidad_vehiculo(<vehiculo del chofer>)
--   AND s.pasajeros <= v_capacidad
-- y añadir al jsonb:
--   'pasajeros', s.pasajeros,
--   'capacidad_vehiculo', v_capacidad,
--   'puede_tomar', (... AND s.pasajeros <= v_capacidad AND gate_ok ...)

-- fn_tomar_viaje: gate + capacidad (además de lo ya diseñado)
DECLARE
  v_gate jsonb;
  v_capacidad smallint;
  v_vehiculo bigint;
BEGIN
  PERFORM set_config('muevete.rpc', 'on', true);

  v_gate := muevete.fn_usuario_habilitado(auth.uid(), 'chofer');
  IF NOT coalesce((v_gate ->> 'habilitado')::boolean, false) THEN
    RAISE EXCEPTION 'perfil_incompleto_chofer: %', v_gate -> 'motivos'
      USING ERRCODE = 'P0050';
  END IF;

  SELECT d.vehiculo INTO v_vehiculo FROM muevete.drivers d WHERE d.id = v_driver;
  v_capacidad := muevete.fn_capacidad_vehiculo(v_vehiculo);

  -- dentro de las validaciones previas a la toma atómica:
  IF coalesce(v_pre.pasajeros, 1) > v_capacidad THEN
    RAISE EXCEPTION 'capacidad_insuficiente: pasajeros % > vehiculo %',
      v_pre.pasajeros, v_capacidad USING ERRCODE = 'P0052';
  END IF;

  -- ... UPDATE atómico igual que en 04 §5.5 ...
END;
```

`fn_cancelar_solicitud` no necesita gate (cancelar siempre debe poder hacerse).

### 6.3 `040` · `fn_completar_viaje`

- No bloquea el cierre por KYC (evita viajes huérfanos), pero:
  - si el chofer quedó `kyc_estado='rechazado'` durante el viaje, insertar una `notificacion` a operaciones y `RAISE NOTICE`.
- `fn_recargar_wallet`: exigir gate sólo de consentimiento (no de perfil completo) para permitir recargar aunque falte un documento:
  `IF NOT (fn_usuario_habilitado(...)->'consentimiento'->>'ok')::boolean THEN RAISE 'consentimiento_pendiente'`.

### 6.4 `041` · hardening (además de lo de 04 §6.2)

```sql
-- Cerrar la fuga de datos personales de users (política FOR ALL USING(true))
DROP POLICY IF EXISTS users_ ON muevete.users;
-- Cerrar el INSERT/DELETE libre de vehículos
DROP POLICY IF EXISTS enable_insert_and_delete ON muevete.vehiculos;
-- Verificar que las pantallas que leían 'users' ajenos usan la vista/políticas
-- (dispatcher, carrier directory, admin). Lista de comprobación en §11.4.
```

> ⚠️ **No aplicar `041` antes del cutover sin auditar** qué pantallas leen `users` ajenos: `dispatcher_home_screen.dart`, `carrier_directory_screen.dart`, `muevete_map_screen.dart` (admin), `inventtia_payment_service`… Si se cierra `users_` de golpe, esas pantallas se quedan sin datos. Plan: `041` va con la misma release que el gate y la versión mínima forzada.

---

## 7. Cambios en `inventtia_muevete/`

### 7.1 Mapa de archivos

| Archivo | Acción | Cambio |
|---|---|---|
| `lib/models/vehicle_type_model.dart` | **EDIT** | Añadir `orden`, `pasajerosMax`, `nombreUi`; `displayName` pasa a usar `nombreUi` (fallback a `tipo`); dejar de depender de `precio_inside_sc` para pasajeros. |
| `lib/services/vehicle_type_service.dart` | **EDIT** | Leer de `muevete.v_catalogo_vehiculos` (ya ordenado y filtrado por `status`); exponer `getCatalogo()`; mantener `subscribeToChanges` si la vista no emite realtime → suscribirse a `vehicle_type` como hoy. |
| `lib/models/identity_model.dart` | **NEW** | `GateIdentidad` (parsea el JSON del RPC), `DocumentoLegal`, `Consentimiento`. |
| `lib/services/identity_service.dart` | **NEW** | `gate()`, `guardarIdentidad()`, `documentos()`, `aceptarConsentimiento()`. |
| `lib/providers/identity_provider.dart` | **NEW** (ChangeNotifier) | Estado `cargando/ok/bloqueado`, `gate`, `refresh()`, `motivo`. Se registra en `MultiProvider` de `main.dart`. |
| `lib/screens/identity/perfil_requerido_screen.dart` | **NEW** | Formulario de perfil con dos modos: `onboarding` (botón "Ahora no", se puede posponer) y `operar` (sin salida salvo completar o cerrar sesión). CI (11 dígitos, formatter), tipo de documento, fotos frente/dorso (`image_picker` + `document_upload_service`), provincia/municipio (`nomencladores_service`/`geonames_service`), **poblado**, dirección; documentos legales con checkboxes; CTA "Guardar y continuar". |
| `lib/screens/identity/documentos_legales_screen.dart` | **NEW** | Lista de documentos publicados, detalle con `SelectableText` (sin dependencias nuevas), botón "Acepto" → `fn_aceptar_consentimiento` con `app_version` de `changelog.json`. |
| `lib/widgets/identity_gate.dart` | **NEW** | **No bloquea la navegación**: refresca el gate, lanza el onboarding suave y muestra banner si falta perfil. Expone `ensureOperativo(context, rol:)`, que sí bloquea la acción (publicar/tomar). Escucha `AppLifecycleState.resumed`. |
| `lib/screens/client/route_preview_screen.dart` | **EDIT** | Selector de pasajeros (1..N) encima del catálogo; filtrar tipos por `pasajerosMax >= pasajeros`; ordenar por `orden`; mostrar capacidad ("hasta N"); pasar `p_pasajeros` a `cotizar`/`crearSolicitud`; si ningún tipo soporta N → mensaje y reset a 1. |
| `lib/providers/transport_provider.dart` | **EDIT** | `int pasajeros = 1`; `setPasajeros(int)` re-cotiza y re-selecciona tipo si el actual ya no aplica; `sendRequest` envía `p_pasajeros`; `cotizar` recibe `pasajeros`. |
| `lib/services/tarifa_service.dart` | **EDIT** | Añadir `pasajeros` a `fn_cotizar_viaje` (ver §6/§13: el RPC de cotización deberá aceptar `p_pasajeros` para validar capacidad en preview). |
| `lib/services/viaje_service.dart` | **EDIT** | `crearSolicitud(..., pasajeros)`; mapear errores `perfil_incompleto` y `capacidad_excedida_tipo`. |
| `lib/main.dart` | **EDIT** | Providers nuevos; `builder` con `IdentityGate`; rutas `/perfil/requerido`, `/legal/:codigo`; gate al `resume`. |
| `lib/screens/login_screen.dart` / `register_screen.dart` | **EDIT** | Tras autenticar, navegar a `/perfil/requerido` si el gate falla (en vez de al home). El registro ya pide provincia/municipio: añadir **poblado** y CI/docs allí mismo. |
| `lib/screens/driver/driver_home_screen.dart` | **EDIT** | Si gate chofer falla: banner bloqueante con motivo y sin lista de viajes (el RPC también devolverá vacío). |
| `lib/screens/driver/available_trips_screen.dart` *(aún no existe, H3)* | **EDIT** | Mostrar `pasajeros` y `capacidad_vehiculo`; deshabilitar "Tomar" si `capacidad_insuficiente`. |
| `lib/utils/constants.dart` | **EDIT** | Quitar `cityCenter*`/`cityRadiusKm` (pendiente de H2) y añadir `ciLength = 11`, `maxPasajeros = 20`. |
| `pubspec.yaml` | **EDIT** | Sin dependencias nuevas obligatorias (documentos se muestran en texto plano). Opcional: `flutter_markdown: ^0.7.6` para render bonito. |

### 7.2 Flujo de arranque (código)

```dart
// lib/main.dart — después de MultiProvider
MaterialApp(
  builder: (context, child) => IdentityGate(child: child ?? const SizedBox.shrink()),
  routes: {
    '/perfil/requerido': (context) => const PerfilRequeridoScreen(),
    '/legal/privacidad': (context) => const DocumentosLegalesScreen(codigo: 'privacidad'),
    // ...
  },
  // ...
)
```

```dart
// lib/widgets/identity_gate.dart
// REGLA (E4 corregida): el gate IMPIDE OPERAR, NO REGISTRARSE.
// Un usuario sin perfil puede crear cuenta y navegar; sólo se bloquean
// publicar viaje (cliente) y tomar viaje (chofer).
class IdentityGate extends StatefulWidget {
  final Widget child;
  const IdentityGate({super.key, required this.child});
  @override
  State<IdentityGate> createState() => _IdentityGateState();
}

class _IdentityGateState extends State<IdentityGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<IdentityProvider>().refresh();
      if (!mounted) return;
      _onboardingSiAplica(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<IdentityProvider>().refresh();
    }
  }

  /// Onboarding suave: ofrece completar el perfil, pero se puede posponer.
  void _onboardingSiAplica(BuildContext context) {
    final id = context.read<IdentityProvider>();
    if (!id.listo || !id.incompleto) return;
    Navigator.of(context, rootNavigator: true).pushNamed(
      '/perfil/requerido',
      arguments: {'modo': 'onboarding'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = context.watch<IdentityProvider>();
    return Stack(
      children: [
        widget.child,
        if (id.listo && id.incompleto)
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: MaterialBanner(
              content: Text(id.gate?.mensaje ??
                  'Completa tu perfil para pedir o tomar viajes.'),
              leading: const Icon(Icons.verified_user_outlined),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(
                    '/perfil/requerido',
                    arguments: {'modo': 'onboarding'},
                  ),
                  child: const Text('Completar'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Guard de ACCIÓN (llamar antes de publicar o tomar un viaje).
/// No bloquea la navegación; bloquea la operación.
Future<bool> ensureOperativo(BuildContext context, {String? rol}) async {
  final id = context.read<IdentityProvider>();
  if (!id.listo) await id.refresh();
  if (id.gate?.habilitado == true) return true;

  await Navigator.of(context).pushNamed(
    '/perfil/requerido',
    arguments: {'modo': 'operar', 'rol': rol ?? id.gate?.rol},
  );
  return context.read<IdentityProvider>().gate?.habilitado == true;
}
```

```dart
// lib/providers/identity_provider.dart (resumen)
class IdentityProvider extends ChangeNotifier {
  final IdentityService _service = IdentityService();
  GateIdentidad? _gate;
  bool _cargando = true;
  bool _listo = false;

  bool? get _auth => Supabase.instance.client.auth.currentUser != null ? true : null;

  GateIdentidad? get gate => _gate;
  bool get listo => _listo;
  bool get bloqueado => _gate != null && !_gate!.habilitado;

  Future<void> refresh() async {
    if (_auth == null) { _gate = null; _listo = true; notifyListeners(); return; }
    _cargando = true; notifyListeners();
    try {
      _gate = await _service.gate();
    } catch (_) {
      _gate = null; // fail-open sólo ante error de red; el RPC decide al revalidar
    } finally {
      _cargando = false; _listo = true; notifyListeners();
    }
  }

  Future<void> guardar(Map<String, dynamic> datos, String rol) async {
    await _service.guardarIdentidad(rol, datos);
    await refresh();
  }

  Future<void> aceptarDocumentos() async {
    for (final doc in await _service.documentosObligatoriosPendientes()) {
      await _service.aceptar(doc.codigo, doc.version);
    }
    await refresh();
  }
}
```

### 7.3 Selector de pasajeros en `route_preview_screen.dart`

```dart
// Estado del widget
int _pasajeros = 1;

// UI — encima del carrusel de vehículos
Widget _buildPasajerosSelector(bool isDark, TransportProvider tp) {
  return Row(
    children: [
      Icon(Icons.groups_outlined, size: 20,
           color: isDark ? Colors.white70 : Colors.grey[700]),
      const SizedBox(width: 8),
      Text('Pasajeros', style: GoogleFonts.plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : Colors.grey[700])),
      const Spacer(),
      IconButton(
        onPressed: _pasajeros > 1
            ? () => setState(() { _pasajeros--; _aplicarPasajeros(tp); })
            : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      Text('$_pasajeros', style: GoogleFonts.plusJakartaSans(
        fontSize: 18, fontWeight: FontWeight.w700)),
      IconButton(
        onPressed: _pasajeros < 20
            ? () => setState(() { _pasajeros++; _aplicarPasajeros(tp); })
            : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );
}

void _aplicarPasajeros(TransportProvider tp) {
  tp.setPasajeros(_pasajeros);              // re-cotiza y re-filtra
  if (tp.selectedVehicleType == null) {
    // Ningún tipo soporta N pasajeros → volver a 1
    setState(() => _pasajeros = 1);
    tp.setPasajeros(1);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Ningún vehículo disponible soporta esa cantidad de pasajeros'),
    ));
  }
}
```

En el carrusel de tipos: filtrar
`tp.vehicleTypes.where((v) => v.pasajerosMax >= tp.pasajeros).toList()` y ordenar por `orden` (el servicio ya viene ordenado de la vista). Mostrar `v.nombreUi` y un badge `hasta ${v.pasajerosMax}`.

El CTA `_onSolicitar` debe empezar con:

```dart
if (!await ensureOperativo(context, rol: 'cliente')) return;
```

y el `_tomar()` del chofer con `rol: 'chofer'`. El provider valida además el gate antes de llamar a la RPC (defensa en profundidad).

### 7.4 `TransportProvider`

```dart
int _pasajeros = 1;
int get pasajeros => _pasajeros;

void setPasajeros(int n) {
  if (n < 1 || n > 20) return;
  _pasajeros = n;
  // Si el tipo seleccionado ya no soporta N, elegir el primero que sí
  final validos = _vehicleTypes.where((v) => v.pasajerosMax >= n).toList();
  if (validos.isEmpty) {
    _selectedVehicleType = null;
  } else if (_selectedVehicleType == null ||
             !validos.any((v) => v.id == _selectedVehicleType!.id)) {
    _selectedVehicleType = validos.first;
  }
  cotizar();
  notifyListeners();
}
```

Y en `sendRequest`/`sendRequest`→`publicarSolicitud`: `p_pasajeros: _pasajeros`.

---

## 8. Cambios en `ventiq_superadmin/`

### 8.1 Archivos

| Archivo | Acción | Contenido |
|---|---|---|
| `lib/models/vehiculo_catalogo.dart` | **NEW** | `VehiculoCatalogo` (id, tipo, nombre, orden, pasajerosMax, status, categoria). |
| `lib/services/vehiculos_catalogo_service.dart` | **NEW** | Listar (`ORDER BY orden`), actualizar `orden`/`nombre_ui`/`pasajeros_max`/`status`; `reordenar(List<int> ids)` (transacción no disponible en REST: N updates secuenciales + reordenar en cliente; o RPC `fn_reordenar_vehiculos(int[])` — recomendado, en `036` o `035`). |
| `lib/screens/muevete/muevete_vehiculos_screen.dart` | **NEW** | Lista ordenada con `ReorderableListView` (drag & drop) → guarda `orden` 10,20,30…; switch visible/oculto; editar `nombre_ui` y `pasajeros_max`; validaciones (1–20, nombre no vacío); aviso "ocultar no borra". |
| `lib/screens/muevete/muevete_kyc_screen.dart` | **EDIT** | Tabs Clientes/Conductores; columnas: CI, poblado, dirección, docs (thumbnails), estado; acciones Aprobar/Rechazar con motivo → `fn_kyc_revisar`. |
| `lib/screens/muevete/muevete_legales_screen.dart` | **NEW** | CRUD `documentos_legales`: crear versión (semver), editar `contenido_md`, publicar (cierra la versión anterior con `vigente_hasta=now()`), archivar. Validación: no publicar dos obligatorias del mismo código. |
| `lib/screens/muevete/muevete_consentimientos_screen.dart` | **NEW** | Auditoría: usuario, documento, versión, fecha, método, app_version; filtros por código/versión/rango y export CSV. |
| `lib/config/app_routes.dart` | **EDIT** | `/muevete/vehiculos`, `/muevete/legales`, `/muevete/consentimientos` (grupo Muévete). |
| `lib/main.dart` | **EDIT** | Rutas con `RouteGuard`. |
| `lib/widgets/app_drawer.dart` | **EDIT** | Ítems "Catálogo de vehículos", "Documentos legales", "Consentimientos". |
| `lib/services/muevete_service.dart` | **EDIT** | En `getDrivers`/KYC incluir `ci`, `poblado`, `direccion`, `kyc_estado`. |

### 8.2 Pantalla de catálogo (código clave)

```dart
// lib/screens/muevete/muevete_vehiculos_screen.dart
class MueveteVehiculosScreen extends StatefulWidget {
  const MueveteVehiculosScreen({super.key});
  @override
  State<MueveteVehiculosScreen> createState() => _MueveteVehiculosScreenState();
}

class _MueveteVehiculosScreenState extends State<MueveteVehiculosScreen> {
  List<VehiculoCatalogo> _items = [];
  bool _loading = true;

  Future<void> _cargar() async {
    final items = await VehiculosCatalogoService.listar(); // ORDER BY orden
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
  }

  Future<void> _reordenar(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    // reescribe orden 10,20,30…
    await VehiculosCatalogoService.reordenar(
        _items.map((e) => e.id).toList());
    await _cargar();
  }

  Future<void> _editar(VehiculoCatalogo v) async {
    final nombre = TextEditingController(text: v.nombre);
    final capacidad = TextEditingController(text: '${v.pasajerosMax}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar ${v.nombre}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nombre,
              decoration: const InputDecoration(labelText: 'Nombre visible')),
          TextField(controller: capacidad, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pasajeros máx. (1-20)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final cap = int.tryParse(capacidad.text) ?? v.pasajerosMax;
    if (cap < 1 || cap > 20) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La capacidad debe estar entre 1 y 20')));
      return;
    }
    await VehiculosCatalogoService.actualizar(v.id, {
      'nombre_ui': nombre.text.trim(),
      'pasajeros_max': cap,
    });
    await _cargar();
  }

  Future<void> _toggleVisible(VehiculoCatalogo v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(v.status ? 'Ocultar ${v.nombre}' : 'Mostrar ${v.nombre}'),
        content: Text(v.status
            ? 'Dejará de aparecer en la app del cliente. No se borra; los viajes históricos se conservan.'
            : 'Volverá a aparecer en el catálogo del cliente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    await VehiculosCatalogoService.actualizar(v.id, {'status': !v.status});
    await _cargar();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catálogo de vehículos')),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          onReorder: _reordenar,
          itemBuilder: (context, i) {
            final v = _items[i];
            return Card(
              key: ValueKey(v.id),
              child: ListTile(
                leading: const Icon(Icons.drag_handle),
                title: Text('${i + 1}. ${v.nombre}'),
                subtitle: Text('tipo: ${v.tipo} · hasta ${v.pasajerosMax} pasajeros'
                    '${v.status ? '' : ' · OCULTO'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editar(v)),
                  Switch(value: v.status, onChanged: (_) => _toggleVisible(v)),
                ]),
              ),
            );
          },
        ),
  );
}
```

### 8.3 KYC en superadmin

Extender `muevete_kyc_screen.dart`:

- Tabs **Clientes** / **Conductores** (clientes desde `users` con `kyc_estado in ('en_revision','pendiente')`).
- Fila: nombre, CI, `poblado`, municipio, fecha de envío, estado.
- Detalle: fotos `doc_frente_url` / `doc_dorso_url` (Image.network con placeholder), botón **Aprobar** / **Rechazar** (motivo obligatorio) → `fn_kyc_revisar(rol, uuid, decision, motivo)`.
- Mostrar `perfil_completado_at` y si ya aceptó consentimientos (join con `consentimientos`).

### 8.4 Documentos legales y consentimientos

- `muevete_legales_screen.dart`: formulario con `codigo`, `version` (semver), `titulo`, `resumen`, `contenido_md`, `es_obligatorio`, `publicar`. Al publicar: `UPDATE ... SET publicado=false, vigente_hasta=now() WHERE codigo=:c AND publicado`; luego insertar/publicar la nueva. Mostrar hash y quién publicó.
- `muevete_consentimientos_screen.dart`: tabla paginada (100/página) con filtro por código, versión y fecha; botón "Exportar CSV" (genera en cliente, sin backend extra). KPIs: % de usuarios con consentimiento vigente (query a `fn_usuario_habilitado` o join directo).

---

## 9. Migración de los 41 usuarios existentes

### 9.1 Estrategia (sin fabricar datos)

1. `036` crea las columnas con `kyc_estado='pendiente'` y **no toca** CI/docs (no se pueden inventar).
2. Backfill **best-effort y verificable**:
   - `drivers.ci ← carnet` (sólo si son 11 dígitos).
   - `drivers.kyc_estado ← kyc+revisado` (mapa de §4.1).
   - `users.poblado ← municipality` **sólo si** el municipio es un valor razonable (no vacío, no '—').
3. **Sin backfill de consentimiento.** Firmar por el usuario es un acto personal; rellenarlo por SQL (`metodo='migracion'`) sólo sería válido si legal lo autoriza por escrito. Se documenta como decisión: **cada uno acepta al abrir la app**.
4. En el primer arranque tras el despliegue el gate devuelve `habilitado=false`: el usuario ve onboarding y puede navegar, pero **publicar/tomar** está bloqueado. Completa CI/docs/poblado/dirección y acepta documentos → gate `true`.

### 9.2 SQL de diagnóstico (antes y después)

```sql
-- Antes del cutover: radiografía de los 41 (18 users + 23 drivers)
SELECT 'users' AS tabla,
       count(*) AS total,
       count(*) FILTER (WHERE muevete.fn_ci_valido(ci))               AS ci_ok,
       count(*) FILTER (WHERE coalesce(trim(poblado),'') <> '')       AS poblado_ok,
       count(*) FILTER (WHERE coalesce(trim(direccion),'') <> '')     AS direccion_ok,
       count(*) FILTER (WHERE coalesce(trim(doc_frente_url),'') <> '') AS doc_frente_ok,
       count(*) FILTER (WHERE coalesce(trim(doc_dorso_url),'') <> '')  AS doc_dorso_ok
  FROM muevete.users
UNION ALL
SELECT 'drivers',
       count(*),
       count(*) FILTER (WHERE muevete.fn_ci_valido(ci)),
       count(*) FILTER (WHERE coalesce(trim(poblado),'') <> ''),
       count(*) FILTER (WHERE coalesce(trim(direccion),'') <> ''),
       count(*) FILTER (WHERE coalesce(trim(doc_frente_url),'') <> ''),
       count(*) FILTER (WHERE coalesce(trim(doc_dorso_url),'') <> '')
  FROM muevete.drivers;

-- Después: embudo de completado
SELECT rol, estado, count(*)
FROM (
  SELECT 'cliente' rol, coalesce(u.kyc_estado,'pendiente') estado
    FROM muevete.users u
  UNION ALL
  SELECT 'chofer', coalesce(d.kyc_estado,'pendiente')
    FROM muevete.drivers d
) t
GROUP BY rol, estado ORDER BY rol, estado;

-- Consentimientos por versión
SELECT documento_codigo, documento_version, count(*) AS aceptaciones
  FROM muevete.consentimientos
 WHERE aceptado
 GROUP BY 1, 2 ORDER BY 1, 2;
```

### 9.3 Plan de comunicación (bloqueante de producto)

- Aviso previo en la app (banner 7 días antes) y por el canal de soporte: "Actualiza y completa tu perfil; sin CI y aceptación de privacidad no podrás pedir ni tomar viajes".
- El mensaje del gate es configurable (`configuracion_identidad.mensaje_bloqueo`).
- La pantalla debe permitir **ver el estado** y **cerrar sesión** (no dejar al usuario sin salida), pero no navegar al mapa.

---

## 10. Compatibilidad, cutover y rollback

### 10.1 Orden de despliegue

1. **`035` + `036`** en producción (aditivas; `kyc_obligatorio=true` pero **no hay app nueva todavía** → nadie queda bloqueado porque el gate sólo lo consulta la app nueva y las RPC 038–040 aún no existen).
2. Superadmin: cargar **documentos legales reales** (reemplaza placeholders) y verificar el catálogo (orden/capacidad/ocultos).
3. Publicar **app chofer** nueva (gate + KYC + capacidad).
4. Publicar **app cliente** nueva (selector de pasajeros + gate + legales).
5. Subir `min_build` obligatorio en `/versiones` (bloquea builds viejas: si no, siguen operando sin KYC).
6. Aplicar `038–040` (RPC con gate/capacidad) y luego `041` (hardening).
7. Monitorear embudo de completado 72 h.

### 10.2 Apps viejas

- Las builds viejas **no llaman** al gate ni a las RPC nuevas: hasta que se aplique `038–040`, siguen publicando por INSERT directo sin KYC. Por eso el punto 5 (versión mínima) va **antes** de `038–040`.
- Tras `038–040` + `041`, un cliente modificado no puede saltarse el gate (validación en servidor).
- `ofertas_chofer` sigue como archivo de sólo lectura (no cambia aquí).

### 10.3 Rollback

| Escenario | Acción | Tiempo |
|---|---|---|
| El gate bloquea demasiado (falso positivo masivo) | `UPDATE muevete.configuracion_identidad SET kyc_obligatorio=false WHERE id=1;` → la app deja de bloquear por perfil, pero **el consentimiento sigue exigiéndose**. | < 1 min |
| El bloqueo deja la app sin choferes operativos | `SELECT muevete.fn_suspender_bloqueo_identidad(120, 'motivo');` (o UPDATE directo) → relaja perfil/KYC/consentimiento durante N minutos sin borrar evidencia. **Los viajes en curso NO se interrumpen** (§5.5). | < 1 min |
| Los documentos legales tienen un error | Publicar versión `1.0.1` y cerrar la anterior (`vigente_hasta`). Los usuarios vuelven a aceptar; no se borra la evidencia anterior. | < 5 min |
| El catálogo quedó mal ordenado | El superadmin lo reordena (no requiere deploy). | < 2 min |
| La capacidad de un tipo bloquea viajes | `UPDATE vehicle_type SET pasajeros_max = N` (configurable). | < 1 min |
| Emergencia total | `UPDATE configuracion_identidad SET kyc_obligatorio=false, consentimiento_obligatorio=false` + rollback de apps por `min_build` anterior. | < 5 min |

### 10.4 Datos personales

- Las imágenes del carnet van al bucket existente (`document_upload_service`); `036` **no** cambia buckets ni policies de Storage. **Pendiente de verificar en H0**: que las URLs de docs no sean públicas; si el bucket es público, se debe pasar a privado + signed URLs en una tarea aparte (riesgo R6).
- La política `users_ USING(true)` expone CI/docs a cualquier autenticado: se cierra en `041` (§6.4). Es **bloqueante** para considerar el KYC "seguro" (aunque la app nueva no los muestre, un cliente modificado sí puede leerlos).

---

## 11. Criterios de aceptación y plan de pruebas

### 11.1 SQL (H0 de esta fase)

| # | Caso | Esperado |
|---|---|---|
| S1 | `fn_ci_valido('90010112345')` | `true` |
| S2 | `fn_ci_valido('90013212345')` (mes 32) | `false` |
| S3 | `fn_ci_valido('123')` / `NULL` / `''` | `false` |
| S4 | `fn_capacidad_vehiculo` con `capacidad_int=4` | `4` |
| S5 | `fn_capacidad_vehiculo` con `capacidad_int=NULL`, `capacidad='6'` | `6` |
| S6 | `fn_capacidad_vehiculo` sin datos | cae a `pasajeros_max` del tipo |
| S7 | `v_catalogo_vehiculos` | exactamente 5 filas en orden Auto, Minivan, Microbús, Moto, Triciclo |
| S8 | `vehicle_type` con `bicicleta`/`camioneta` | `status=false`, filas conservadas |
| S9 | Gate usuario sin CI/docs/poblado | `habilitado=false`, `faltantes` contiene los 4+ |
| S10 | Gate usuario completo **sin** consentimiento | `habilitado=false`, motivo `consentimiento_pendiente` |
| S11 | Gate tras aceptar los 3 documentos | `habilitado=true` (cliente) |
| S12 | Gate chofer con `drivers.kyc=false` | `habilitado=false`, motivo `kyc_pendiente_aprobacion` |
| S13 | `fn_aceptar_consentimiento` dos veces | mismo `consentimiento_id`, 1 fila |
| S14 | `fn_aceptar_consentimiento` de versión no publicada | excepción `documento_no_vigente` |
| S15 | `fn_kyc_revisar` con rol no superadmin | excepción `no_autorizado` |
| S16 | Trigger `fn_identidad_guarda`: `UPDATE users SET ci=...` directo | excepción `usar_fn_guardar_identidad` |
| S17 | RLS: usuario A lee consentimientos de B | 0 filas |
| S18 | Idempotencia: ejecutar `035` y `036` dos veces | sin errores |
| S24 | `fn_suspender_bloqueo_identidad(5, …)` con usuario incompleto | gate devuelve `habilitado=true` mientras dure; `bloqueo_suspendido=true` |
| S25 | Tras vencer / `fn_suspender_bloqueo_identidad(0, NULL)` | gate vuelve a `habilitado=false` sin haber borrado consentimientos |
| S26 | `fn_suspender_bloqueo_identidad` como no-superadmin | excepción `no_autorizado` |

**Bloqueante de `038–040`** (cuando existan):

| # | Caso | Esperado |
|---|---|---|
| S19 | `fn_crear_solicitud` con gate fallido | excepción `perfil_incompleto` |
| S20 | `fn_crear_solicitud` con `p_pasajeros > pasajeros_max` | excepción `capacidad_excedida_tipo` |
| S21 | `fn_tomar_viaje` con vehículo de 4 y solicitud de 6 | excepción `capacidad_insuficiente` |
| S22 | `fn_tomar_viaje` con chofer sin consentimiento | excepción `perfil_incompleto_chofer` |
| S23 | `fn_viajes_disponibles` con chofer de 4 plazas | no devuelve solicitudes de 5+ |

### 11.2 Dart / Flutter

```powershell
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'
cd C:\Users\cesar\Documents\VentIQ-seller-App\inventtia_muevete
flutter analyze
flutter test test/services/vehicle_type_service_test.dart
flutter test test/widgets/pasajeros_selector_test.dart
flutter test test/widgets/identity_gate_test.dart
```

Casos:
- `vehicle_type_service_test`: parseo de la vista, orden respetado, 5 tipos, `nombreUi` de tuktuk = "Triciclo Eléctrico".
- `pasajeros_selector_test`: con 6 pasajeros no aparece Moto ni Triciclo; con 1 aparece Auto primero; con capacidad no soportada → snackbar y reset.
- `identity_gate_test`: con gate `habilitado=false` el child **sí** se renderiza (no se bloquea la navegación) y aparece el banner; `ensureOperativo()` devuelve `false` y navega a `/perfil/requerido?modo=operar`. Con gate `true`, `ensureOperativo()` devuelve `true` y no navega.
- `perfil_requerido_test`: CI inválida bloquea el guardado; formulario incompleto no habilita CTA.

### 11.3 E2E manual (dos dispositivos / emuladores)

| # | Escenario | Esperado |
|---|---|---|
| E1 | Usuario existente (sin CI) abre la app nueva | Ve onboarding/banner y **puede navegar**; "Solicitar" abre el perfil en modo operar; no puede publicar |
| E2 | Completa CI (11 dígitos), fotos frente/dorso, provincia/municipio/poblado/dirección | Guarda; estado `en_revision` (cliente) y gate mejora |
| E3 | Acepta los 3 documentos | Gate `true`; puede pedir viaje |
| E4 | Intenta publicar sin aceptar términos (cliente modificado) | RPC rechaza `perfil_incompleto` |
| E5 | Cliente elige 6 pasajeros | Solo Auto(4)/Minivan(7)/Microbús(15) visibles; Moto y Triciclo ocultos |
| E6 | Chofer con vehículo de 4 plazas intenta tomar viaje de 6 | Botón bloqueado + RPC `capacidad_insuficiente` |
| E7 | Chofer sin KYC aprobado entra a la app | Ve la app, pero la lista de viajes está vacía y "Tomar" abre el perfil en modo operar (motivo KYC) |
| E8 | Superadmin aprueba KYC del chofer | Al reabrir, el chofer ya puede tomar |
| E9 | Superadmin cambia orden: Moto primero | En la app, Moto aparece primero tras refrescar |
| E10 | Superadmin oculta Auto | Desaparece del catálogo; viajes históricos intactos; no se borra la fila |
| E11 | Superadmin publica `privacidad 1.0.1` | A todos les vuelve el gate por ese documento; aceptan y se audita versión |
| E12 | Auditoría | La pantalla muestra usuario+documento+versión+fecha+método |
| E13 | Usuario **nuevo** se registra sin CI y entra | Puede crear cuenta y navegar; banner/onboarding; al pulsar "Solicitar" se abre el perfil en modo operar |
| E14 | Superadmin suspende 5 min | Un chofer sin KYC puede tomar viajes; al vencer, vuelve a bloquearse; el viaje en curso se completó normal |

### 11.4 Auditoría de pantallas que leen `users` ajenos (antes de `041`)

Antes de cerrar `users_` en `041`, revisar y migrar a `v_usuarios_publicos`/políticas:

- `inventtia_muevete/lib/screens/dispatcher/dispatcher_home_screen.dart`
- `inventtia_muevete/lib/screens/shipper/carrier_directory_screen.dart`
- `inventtia_muevete/lib/services/oferta_carga_service.dart`, `carga_service.dart`
- `ventiq_superadmin/lib/services/muevete_service.dart` (`getClientWallets`, `getRequests` joins)
- `ventiq_superadmin/lib/services/inventtia_payment_service.dart`

Criterio: cada consulta que hoy hace `from('users').select('*')` de otro usuario debe pasar a `select('uuid,name,image')` (columnas no sensibles) o a una vista `v_usuarios_publicos`. Se crea la vista en `041`.

---

## 12. Riesgos

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | **Los 41 usuarios se bloquean** hasta completar perfil (churn / soporte) | Alto (negocio) | Aviso 7 días antes; mensaje configurable; pantalla clara con progreso; `dias_gracia` disponible para relajar; métricas diarias del embudo. |
| R2 | **Texto legal placeholder** se publica por error | Alto (legal) | `036` inserta `publicado=true` con contenido marcado `<!-- PLACEHOLDER -->`; **bloqueante de cutover**: superadmin debe cargar el texto real y el checklist lo verifica (`hash_contenido` + revisión legal). |
| R3 | **La política `users_ USING(true)` expone CI/fotos** | Crítico (privacidad) | `041` la cierra; hasta entonces el gate no se considera terminado. Auditar pantallas (§11.4) antes. |
| R4 | **Bucket de Storage público** con fotos de carnet | Crítico (privacidad) | Verificar en H0; si es público, pasar a privado + signed URLs (tarea aparte, no opcional para producción). |
| R5 | **Renombrar `tipo` rompería claves** | Alto (datos) | Ya evitado: sólo `nombre_ui`. Test S7 + grep de `tipo ==` en las apps. |
| R6 | **Capacidad ambigua** (`capacidad_int` vacío, `capacidad` texto libre en vehículos de carga) | Medio | `fn_capacidad_vehiculo` con fallback en cascada; backfill sólo donde es inequívoco; el superadmin puede corregir por vehículo; el chofer no puede tomar si no hay capacidad fiable (cae a `pasajeros_max`). |
| R7 | **Drift dev/prod** de columnas (`ci`/`direccion` en `drivers`) | Medio | `ADD COLUMN IF NOT EXISTS` en todo; verificación H0 con `information_schema`; backfill desde `carnet`. |
| R8 | **`038–040` sin gate** por escribir las RPCs antes de `036` | Crítico (bypass) | Orden obligatorio: `036` → `038–040` en el mismo release; el criterio S19–S22 es bloqueante. |
| R9 | **Consentimiento de menores de edad** (si aplica) | Medio (legal) | Fuera de alcance de este anexo; se documenta como decisión de producto pendiente (¿se exige tutor?). |
| R10 | **Imágenes KYC sin retención definida** | Medio (legal) | Definir política de retención/borrado (p. ej. 90 días tras aprobación) en una tarea posterior; `consentimientos.metadata` ya permite registrar el aviso. |
| R11 | **Usuarios sin email/teléfono** no pueden verificar | Bajo | El gate no exige email; exige CI+docs+poblado+dirección. |
| R12 | **Suspensión olvidada**: se activa el bypass por una incidencia y nadie lo reanuda | Alto (cumplimiento) | Caducidad obligatoria (`bloqueo_suspendido_hasta`, máx. 30 días), aviso rojo permanente en superadmin, log de quién/cuándo/motivo, y recordatorio en el panel a las 24 h. |

---

## 13. Desvíos / decisiones que necesito confirmar

| # | Punto | Propuesta | Por qué |
|---|---|---|---|
| **D-1** | Tabla `configuracion_identidad` (singleton) | Incluirla en `036` | El gate puede dejar a **todos** sin poder operar; sin un flag editable, una incidencia sólo se resuelve desplegando código. Es el mismo patrón que `configuracion_tarifas.taxi_precio_fijo_activo`. |
| **D-2** | Idempotencia vs edición del admin en `035` | Ejecutar `035` **una vez**; documentar que re-ejecutarla reaplica el orden/capacidad base | Si el admin ya reordenó, re-ejecutar lo pisa. Alternativa: `WHERE updated_at = created_at` (más frágil). Confirmar cuál prefieres. |
| **D-3** | Aprobación manual del cliente | `requiere_aprobacion_kyc_cliente=false` por defecto (el cliente no espera revisión; el chofer sí) | Si se exige aprobación manual de los 18 clientes, el lanzamiento se retrasa hasta que operaciones los revise uno a uno. |
| **D-4** | Los 3 documentos legales | `privacidad`, `terminos`, `kyc` como obligatorios v1.0.0 (placeholder) | El texto real lo aporta legal. ¿Falta algún documento (p. ej. "política de cancelaciones")? |
| **D-5** | Pasajeros en la cotización | Añadir `p_pasajeros` a `fn_cotizar_viaje` (038) además de a `fn_crear_solicitud` | Para que el preview no muestre un precio y luego falle al crear. Es un parámetro aditivo al final de la firma. |
| **D-6** | Cierre de viaje con KYC rechazado a mitad | `fn_completar_viaje` **no** bloquea el cierre; notifica a operaciones | Evitar viajes huérfanos (mismo criterio que los viajes ya iniciados cuando se corta el servicio). |
| **D-7** | Retención de fotos KYC | Pendiente de definir (¿90 días tras aprobación? ¿mientras la cuenta esté activa?) | Es una decisión legal, no técnica; el esquema la soporta (`metadata`). |
| **D-8** | Alcance de la suspensión | Relaja **perfil + KYC + consentimiento**, pero **no** `drivers.kyc` (aprobación de conducción) | Si se relajara la aprobación de conducción, cualquier conductor sin verificar podría operar. Si el problema es falta de choferes aprobados, la palanca correcta es aprobarlos. |

---

### Anexo A · Resumen de objetos nuevos

| Migración | Tablas | Columnas | Funciones | Triggers | Vistas |
|---|---|---|---|---|---|
| `035` | — | `vehicle_type.orden/pasajeros_max/nombre_ui`; `solicitudes_transporte.pasajeros` | `fn_capacidad_vehiculo` (interna) | 0 (usa los de 031) | `v_catalogo_vehiculos` |
| `036` | `documentos_legales`, `consentimientos`, `configuracion_identidad` | `users`: `poblado`, `kyc_estado`, `kyc_motivo`, `kyc_revisado_por/at`, `perfil_completado_at` (+ IF NOT EXISTS de `ci/direccion/docs`); `drivers`: `ci`, `poblado`, `direccion`, `kyc_estado`, `kyc_revisado_por/at` | `fn_ci_valido`, `fn_usuario_habilitado`, `fn_aceptar_consentimiento`, `fn_guardar_identidad`, `fn_kyc_revisar`, `fn_suspender_bloqueo_identidad`, `fn_identidad_guarda` (trigger), `fn_doc_legal_hash` (trigger) | `trg_users_identidad_guarda`, `trg_drivers_identidad_guarda`, `trg_documentos_legales_hash`, `trg_documentos_legales_updated_at`, `trg_configuracion_identidad_updated_at` | — |

> `configuracion_identidad` incluye además `bloqueo_suspendido_hasta` y `suspension_motivo` (válvula de suspensión operativa, §5.5).

### Anexo B · Checklist de cutover

- [ ] `035` y `036` aplicadas en staging y en producción (idempotencia verificada).
- [ ] `037` (seguridad del viaje) planificada por separado; **no** bloquea este gate, pero su número no se reutiliza.
- [ ] Textos legales reales cargados y **publicados** (reemplazan placeholders).
- [ ] Catálogo revisado: 5 visibles en orden Auto→Triciclo, 2 ocultos, capacidades correctas.
- [ ] Buckets de Storage con las fotos KYC **privados** (o signed URLs).
- [ ] App chofer + app cliente publicadas con gate y selector de pasajeros.
- [ ] `min_build` obligatorio subido en `/versiones` (bloquea builds viejas).
- [ ] `038–040` desplegadas (gate + pasajeros + capacidad en servidor).
- [ ] `041` desplegado (cierre de `users_` y de `vehiculos` libre).
- [ ] Métricas: % completado de los 41, tiempo medio de completado, soporte informado.
- [ ] Rollback probado (flags de `configuracion_identidad`).
- [ ] Suspensión probada: `fn_suspender_bloqueo_identidad(5, 'prueba')` permite operar y al vencer vuelve a bloquear; los viajes en curso se completan.

## Anexo C · Changelog de este documento

| Fecha | Cambio |
|---|---|
| 2026-11-12 | v1: DDL 035/036, gate, catálogo, KYC, consentimientos, migración de los 41 usuarios. |
| 2026-11-12 | v2: renumeración del plan (037 = seguridad del viaje; 038–040 RPCs; 041 hardening). Gate corregido: **impide operar, no registrarse**. Añadida válvula de suspensión (`bloqueo_suspendido_hasta` + `fn_suspender_bloqueo_identidad`) y comportamiento de los viajes en curso. |