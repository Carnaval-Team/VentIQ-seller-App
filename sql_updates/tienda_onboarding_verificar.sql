-- =============================================================================
-- Verificacion del onboarding de tienda (SOLO LECTURA).
--
-- Se ejecuta DESPUES de `sql_updates/tienda_onboarding.sql` para comprobar que
-- el despliegue quedo bien. No escribe nada: se puede correr en main sin miedo,
-- y tambien contra newa para comparar.
--
-- Que comprueba, en este orden:
--   1. Las columnas nuevas existen con el tipo y el default esperados.
--   2. Los CHECK estan puestos y admiten exactamente los valores del diseno.
--   3. El backfill se aplico: ninguna tienda viva quedo en 'borrador' por olvido.
--   4. La columna geografica `estado` sigue intacta (no se piso por error).
--   5. La tabla del checklist, su RLS y sus 4 politicas existen.
--   6. Los permisos de `authenticated` y de la secuencia estan dados.
--
-- OJO con el paso 3: que salga una tienda en 'borrador' NO es un fallo. Puede
-- ser una tienda nueva legitima, o una que alguien marco a proposito para
-- probar el flujo. Lo que denuncia un fallo es que TODAS sigan en borrador.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Columnas nuevas
-- -----------------------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tienda'
  AND column_name IN (
      'estado_onboarding',
      'tipo_negocio',
      'activada_en',
      'onboarding_descartado_en'
  )
ORDER BY column_name;

-- Esperado: 4 filas.
--   estado_onboarding         text        NO  'borrador'::text
--   tipo_negocio              text        YES NULL
--   activada_en               timestamptz YES NULL
--   onboarding_descartado_en  timestamptz YES NULL

-- -----------------------------------------------------------------------------
-- 2. CHECKs
-- -----------------------------------------------------------------------------
SELECT conname, pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conrelid = 'public.app_dat_tienda'::regclass
  AND conname IN ('chk_tienda_estado_onboarding', 'chk_tienda_tipo_negocio')
ORDER BY conname;

-- Esperado: 2 filas, con borrador/activa/suspendida y
-- retail/restaurante/servicentro/catalogo (mas el IS NULL de tipo_negocio).

-- -----------------------------------------------------------------------------
-- 3. Backfill
-- -----------------------------------------------------------------------------
-- 3a. Reparto por estado. Lo normal tras desplegar es que TODAS esten activas.
SELECT estado_onboarding, count(*) AS tiendas, count(activada_en) AS con_fecha
FROM public.app_dat_tienda
GROUP BY estado_onboarding
ORDER BY estado_onboarding;

-- 3b. Tiendas en borrador, con nombre, para poder decidir si alguna es un
--     descuido o una decision consciente. Si esta lista trae TODAS las tiendas,
--     el backfill no corrio: revisar antes de seguir.
SELECT id, denominacion, created_at, activada_en
FROM public.app_dat_tienda
WHERE estado_onboarding = 'borrador'
ORDER BY id;

-- 3c. Coherencia: una tienda 'activa' sin fecha de activacion es un fallo (la
--     columna se rellena en el mismo UPDATE del backfill). Debe dar 0 filas.
SELECT id, denominacion, estado_onboarding, activada_en
FROM public.app_dat_tienda
WHERE estado_onboarding = 'activa'
  AND activada_en IS NULL
ORDER BY id;

-- 3d. Coherencia: una tienda en 'borrador' CON fecha de activacion tambien es
--     sospechosa (se activo y luego se revirtio el estado a mano). Debe dar 0.
SELECT id, denominacion, estado_onboarding, activada_en
FROM public.app_dat_tienda
WHERE estado_onboarding = 'borrador'
  AND activada_en IS NOT NULL
ORDER BY id;

-- -----------------------------------------------------------------------------
-- 4. La columna geografica `estado` sigue siendo lo que era
-- -----------------------------------------------------------------------------
-- Si aqui aparecen 'borrador'/'activa'/'suspendida', alguien escribio el estado
-- de onboarding en la columna equivocada. Valores esperados: codigos de
-- provincia ('02', '04', '16', ...).
SELECT id, denominacion, estado AS codigo_provincia, estado_onboarding
FROM public.app_dat_tienda
ORDER BY id;

-- -----------------------------------------------------------------------------
-- 5. Tabla, RLS y politicas
-- -----------------------------------------------------------------------------
SELECT c.relname, c.relrowsecurity AS rls_activa
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_tarea_onboarding';

-- Esperado: 1 fila con rls_activa = true.

SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'app_dat_tarea_onboarding'
ORDER BY policyname;

-- Esperado: 4 filas.
--   m01_tarea_onboarding_leer        SELECT  fn_config_tienda_puede_leer(id_tienda)
--   m01_tarea_onboarding_insertar    INSERT  fn_config_tienda_puede_escribir(id_tienda)
--   m01_tarea_onboarding_actualizar  UPDATE  fn_config_tienda_puede_escribir(id_tienda)
--   m01_tarea_onboarding_eliminar    DELETE  fn_config_tienda_puede_escribir(id_tienda)

-- Trigger de updated_at.
SELECT tgname
FROM pg_trigger
WHERE tgrelid = 'public.app_dat_tarea_onboarding'::regclass
  AND NOT tgisinternal;

-- Esperado: trg_tarea_onboarding_touch.

-- -----------------------------------------------------------------------------
-- 6. Permisos
-- -----------------------------------------------------------------------------
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tarea_onboarding'
  AND grantee IN ('authenticated', 'service_role')
ORDER BY grantee, privilege_type;

-- Esperado: SELECT/INSERT/UPDATE/DELETE para authenticated y service_role.
--
-- En newa salen ademas REFERENCES, TRIGGER y TRUNCATE. NO son un fallo de este
-- script: el esquema `public` tiene ALTER DEFAULT PRIVILEGES que concede
-- `arwdDxtm` a authenticated sobre toda tabla nueva (comprobado con
-- `SELECT defaclnamespace::regnamespace, defaclobjtype, defaclacl FROM
-- pg_default_acl`), asi que cualquier tabla creada aqui los hereda. Los GRANT
-- explicitos del script son redundantes en esa base, pero se mantienen para que
-- el script funcione igual en un proyecto sin ese ALTER DEFAULT PRIVILEGES.
--
-- HALLAZGO PREEXISTENTE (no lo arregla este script, hay que decidirlo aparte):
-- ese TRUNCATE heredado SI permite vaciar la tabla sin pasar por RLS. Se probo
-- con `SET LOCAL ROLE authenticated; TRUNCATE public.app_dat_tarea_onboarding;`
-- y funciono (0 filas y sin error 42501). Afecta igual a `app_dat_trabajadores`,
-- `app_dat_gerente` y `app_dat_tienda`, que tienen los mismos privilegios, asi
-- que no es algo que introduzca esta tabla: es como esta configurado el
-- esquema `public` entero. Arreglarlo de verdad es un REVOKE TRUNCATE sobre
-- `public` (o quitar TRUNCATE del default), y eso es una decision de proyecto,
-- no de esta migracion. Revocar solo en esta tabla daria una falsa sensacion
-- de seguridad y dejaria el resto igual.


SELECT grantee, privilege_type
FROM information_schema.role_usage_grants
WHERE object_schema = 'public'
  AND object_name = 'app_dat_tarea_onboarding_id_seq'
ORDER BY grantee, privilege_type;

-- -----------------------------------------------------------------------------
-- 7. Prueba funcional de RLS (opcional, requiere un uuid real de dueno)
-- -----------------------------------------------------------------------------
-- Este bloque esta comentado a proposito: los scripts de verificacion no deben
-- escribir. Para probar el aislamiento, descomentar y sustituir los dos uuid
-- por el dueno de una tienda y el dueno de OTRA tienda. El segundo debe ver 0.
--
-- BEGIN;
-- SET LOCAL ROLE authenticated;
-- SET LOCAL request.jwt.claims = '{"sub":"<uuid_dueno_tienda_A>","role":"authenticated"}';
-- INSERT INTO public.app_dat_tarea_onboarding (id_tienda, clave, estado)
-- VALUES (<id_tienda_A>, 'tpv', 'pendiente')
-- ON CONFLICT (id_tienda, clave) DO UPDATE SET estado = excluded.estado;
-- RESET ROLE;
-- SET LOCAL ROLE authenticated;
-- SET LOCAL request.jwt.claims = '{"sub":"<uuid_dueno_tienda_B>","role":"authenticated"}';
-- SELECT count(*) AS filas_visibles_por_ajeno
-- FROM public.app_dat_tarea_onboarding WHERE id_tienda = <id_tienda_A>;
-- ROLLBACK;
