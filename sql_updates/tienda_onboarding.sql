-- =============================================================================
-- Onboarding de tienda: estado de ciclo de vida, tipo de negocio y checklist.
--
-- ESTADO: APLICADO EN NEWA (qhprswhhfasrikhawjoz). PENDIENTE DE APLICAR EN MAIN.
--
-- Problema: hoy una tienda no tiene ciclo de vida. Existe o no existe, y nada
-- distingue una tienda que ya vende de una que se acaba de crear y esta a
-- medias. El alta obliga a rellenar los 4 pasos del asistente de una sentada
-- porque, si el cliente abandona, la tienda queda creada pero no hay donde
-- verificar que le falta para poder vender. Tampoco hay donde guardar que tipo
-- de negocio declaro el cliente (retail, restaurante, servicentro, solo
-- catalogo), asi que el producto no puede guiarlo segun su caso.
--
-- Arreglo: una columna de estado de onboarding, una de tipo de negocio
-- declarado, dos timestamps (cuando se activo y cuando se descarto el checklist)
-- y una tabla de tareas del checklist. Con eso el cliente puede abandonar y
-- volver, y el Go Live tiene un sitio donde escribir el resultado.
--
-- DESVIACION DEL PLAN (importante, leer antes de portar a main):
--   El plan pide una columna llamada `estado`. En esta base ESE NOMBRE YA ESTA
--   OCUPADO: `public.app_dat_tienda.estado` existe desde el esquema original y
--   guarda el codigo de la provincia/estado geografico, no el ciclo de vida.
--   Lo escribe `store_registration_service.dart:240` con `adminCode1` del
--   dropdown de pais, y hoy tiene valores '02', '04', '16' en las 8 tiendas.
--   Un `ADD COLUMN IF NOT EXISTS estado` no habria creado nada (la columna ya
--   existe), y el `CHECK (estado IN ('borrador','activa','suspendida'))` habria
--   fallado al validarse contra los valores actuales: el script no habria
--   pasado de la primera linea. Por eso la columna nueva se llama
--   `estado_onboarding`. `estado` (geografico) no se toca.
--
-- Notas de diseno:
--   * Idempotente entero. Se puede reejecutar sin efectos: los ADD COLUMN son
--     IF NOT EXISTS, los CHECK se anaden con DO bloqueados por pg_constraint,
--     la tabla es IF NOT EXISTS y las politicas se recrean con DROP IF EXISTS.
--   * El backfill de tiendas existentes corre UNA SOLA VEZ, y solo si la
--     columna `estado_onboarding` no existia antes del ALTER. Si se reejecutara
--     a ciegas, una tienda que el cliente dejo legitimamente en 'borrador'
--     volveria a 'activa' en cada despliegue: justo lo contrario de lo que
--     mide esta columna. El "era nueva" se captura en una variable ANTES del
--     ALTER, que es el unico momento en que ese dato aun es fiable.
--   * El tipo de negocio es DECLARATIVO. Solo elige que tareas recomendar; no
--     enciende `modo_restaurante`, `cocina_activa` ni `modo_servicentro`. Tener
--     dos fuentes de verdad para "esta tienda es un restaurante" permitiria que
--     se contradigan, y la capacidad real la siguen decidiendo esos flags.
--     `tipo_negocio` admite NULL a proposito: una tienda en borrador puede no
--     haberlo declarado todavia.
--   * `activada_en` es timestamp y no booleano para poder medir cuanto tarda
--     una tienda desde que se crea hasta que activa. Es nullable porque una
--     tienda en borrador no tiene fecha de activacion.
--   * La RLS copia el patron `m01_*` de `app_dat_trabajadores` /
--     `app_dat_gerente`, que ya existen en newa. No se inventa ninguna funcion
--     de permiso: se reutilizan `fn_config_tienda_puede_leer` y
--     `fn_config_tienda_puede_escribir`, que ya resuelven dueno, gerente,
--     superadmin y auditor por tienda.
--   * La tabla lleva `updated_at` con trigger para no depender de que cada
--     cliente se acuerde de escribirlo al marcar una tarea.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1-4. Columnas de onboarding en app_dat_tienda
-- -----------------------------------------------------------------------------

-- Estas tres columnas son independientes y no condicionan ningun backfill, asi
-- que se crean primero: el backfill necesita `activada_en` ya existente. Un
-- ADD COLUMN IF NOT EXISTS es idempotente por si mismo.
ALTER TABLE public.app_dat_tienda
    ADD COLUMN IF NOT EXISTS tipo_negocio text;

-- Cuando la tienda paso a 'activa' (Go Live). Nullable: en borrador no hay
-- fecha. Sirve para medir tiempo hasta la activacion.
ALTER TABLE public.app_dat_tienda
    ADD COLUMN IF NOT EXISTS activada_en timestamptz;

-- Cuando el cliente descarto el checklist. Se conserva en vez de borrar las
-- tareas: el checklist se puede descartar Y recuperar.
ALTER TABLE public.app_dat_tienda
    ADD COLUMN IF NOT EXISTS onboarding_descartado_en timestamptz;

-- `estado_onboarding` y el backfill van juntos en el mismo bloque porque el
-- backfill necesita saber si la columna se acaba de crear. Se captura si es
-- nueva ANTES del ALTER: despues ya existiria siempre y no habria forma de
-- distinguir la primera ejecucion de una reejecucion.
DO $$
DECLARE
    v_era_nueva boolean;
BEGIN
    SELECT NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_tienda'
          AND column_name = 'estado_onboarding'
    ) INTO v_era_nueva;

    IF v_era_nueva THEN
        ALTER TABLE public.app_dat_tienda
            ADD COLUMN estado_onboarding text NOT NULL DEFAULT 'borrador';

        -- El CHECK va en su propio ALTER para que el NOT NULL DEFAULT quede
        -- aplicado antes de validar los datos existentes.
        ALTER TABLE public.app_dat_tienda
            ADD CONSTRAINT chk_tienda_estado_onboarding
            CHECK (estado_onboarding IN ('borrador','activa','suspendida'));
    END IF;

    -- El DEFAULT 'borrador' es lo correcto para una tienda nueva, pero deja en
    -- borrador a todas las que YA existen y estan operando. El backfill las
    -- marca activas y les pone la fecha de activacion igual a su created_at,
    -- que es la mejor aproximacion disponible de cuando empezaron a operar.
    -- Solo corre la primera vez: en una reejecucion v_era_nueva es falso y una
    -- tienda puesta a proposito en borrador se queda en borrador.
    IF v_era_nueva THEN
        UPDATE public.app_dat_tienda
        SET estado_onboarding = 'activa',
            activada_en = COALESCE(activada_en, created_at)
        WHERE estado_onboarding = 'borrador';

        RAISE NOTICE 'tienda_onboarding: columna creada, % tiendas marcadas activas',
            (SELECT count(*) FROM public.app_dat_tienda WHERE estado_onboarding = 'activa');
    ELSE
        RAISE NOTICE 'tienda_onboarding: columna ya existia, backfill omitido';
    END IF;
END
$$;

-- Red de seguridad: si la columna ya existia pero le falta el CHECK (por
-- ejemplo, se creo a mano), se anade sin tocar los datos.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.app_dat_tienda'::regclass
          AND conname = 'chk_tienda_estado_onboarding'
    ) THEN
        ALTER TABLE public.app_dat_tienda
            ADD CONSTRAINT chk_tienda_estado_onboarding
            CHECK (estado_onboarding IN ('borrador','activa','suspendida'));
    END IF;
END
$$;

-- Tipo de negocio declarado. Nullable y sin efecto sobre los flags reales.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.app_dat_tienda'::regclass
          AND conname = 'chk_tienda_tipo_negocio'
    ) THEN
        ALTER TABLE public.app_dat_tienda
            ADD CONSTRAINT chk_tienda_tipo_negocio
            CHECK (
                tipo_negocio IS NULL
                OR tipo_negocio IN ('retail','restaurante','servicentro','catalogo')
            );
    END IF;
END
$$;

COMMENT ON COLUMN public.app_dat_tienda.estado_onboarding IS
  'Ciclo de vida de la tienda: borrador (no puede vender), activa, suspendida. '
  'OJO: no confundir con app_dat_tienda.estado, que es el codigo de provincia.';
COMMENT ON COLUMN public.app_dat_tienda.tipo_negocio IS
  'Tipo declarado por el cliente para recomendar tareas del checklist. '
  'Declarativo: NO enciende modo_restaurante, cocina_activa ni modo_servicentro.';
COMMENT ON COLUMN public.app_dat_tienda.activada_en IS
  'Momento del Go Live. NULL mientras la tienda esta en borrador.';
COMMENT ON COLUMN public.app_dat_tienda.onboarding_descartado_en IS
  'Momento en que el cliente descarto el checklist. NULL si no lo ha descartado.';

-- -----------------------------------------------------------------------------
-- 5. Tabla del checklist
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.app_dat_tarea_onboarding (
    id bigserial PRIMARY KEY,
    id_tienda bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
    clave text NOT NULL,
    estado text NOT NULL DEFAULT 'pendiente',
    completada_en timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_tarea_onboarding_estado
        CHECK (estado IN ('pendiente','completada','omitida')),
    CONSTRAINT uq_tarea_onboarding_tienda_clave UNIQUE (id_tienda, clave)
);

COMMENT ON TABLE public.app_dat_tarea_onboarding IS
  'Estado por tarea del checklist de activacion de una tienda. '
  'Una fila por (tienda, clave); la clave la define el cliente.';

COMMENT ON COLUMN public.app_dat_tarea_onboarding.clave IS
  'Identificador estable de la tarea (almacen, tpv, producto, cobro, ...).';
COMMENT ON COLUMN public.app_dat_tarea_onboarding.estado IS
  'pendiente | completada | omitida. "omitida" es una tarea que el cliente '
  'decidio saltarse, no una que no aplique a su tipo de negocio.';

CREATE INDEX IF NOT EXISTS idx_tarea_onboarding_tienda
    ON public.app_dat_tarea_onboarding (id_tienda);

-- updated_at automatico: los clientes solo escriben estado y completada_en.
-- search_path fijo como en el resto de funciones del repo: el trigger no
-- resuelve nombres fuera de public/pg_catalog.
CREATE OR REPLACE FUNCTION public.fn_tarea_onboarding_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_tarea_onboarding_touch ON public.app_dat_tarea_onboarding;
CREATE TRIGGER trg_tarea_onboarding_touch
    BEFORE UPDATE ON public.app_dat_tarea_onboarding
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_tarea_onboarding_touch();

-- -----------------------------------------------------------------------------
-- 6. RLS: mismo patron que las politicas m01_* de app_dat_trabajadores /
--    app_dat_gerente. Las dos funciones de permiso ya existen; no se crean.
-- -----------------------------------------------------------------------------

ALTER TABLE public.app_dat_tarea_onboarding ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS m01_tarea_onboarding_leer ON public.app_dat_tarea_onboarding;
CREATE POLICY m01_tarea_onboarding_leer
  ON public.app_dat_tarea_onboarding
  FOR SELECT TO authenticated
  USING (public.fn_config_tienda_puede_leer(id_tienda));

DROP POLICY IF EXISTS m01_tarea_onboarding_insertar ON public.app_dat_tarea_onboarding;
CREATE POLICY m01_tarea_onboarding_insertar
  ON public.app_dat_tarea_onboarding
  FOR INSERT TO authenticated
  WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

DROP POLICY IF EXISTS m01_tarea_onboarding_actualizar ON public.app_dat_tarea_onboarding;
CREATE POLICY m01_tarea_onboarding_actualizar
  ON public.app_dat_tarea_onboarding
  FOR UPDATE TO authenticated
  USING (public.fn_config_tienda_puede_escribir(id_tienda))
  WITH CHECK (public.fn_config_tienda_puede_escribir(id_tienda));

DROP POLICY IF EXISTS m01_tarea_onboarding_eliminar ON public.app_dat_tarea_onboarding;
CREATE POLICY m01_tarea_onboarding_eliminar
  ON public.app_dat_tarea_onboarding
  FOR DELETE TO authenticated
  USING (public.fn_config_tienda_puede_escribir(id_tienda));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_tarea_onboarding TO authenticated;
GRANT ALL ON public.app_dat_tarea_onboarding TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_tarea_onboarding_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.app_dat_tarea_onboarding_id_seq TO service_role;

COMMIT;

-- =============================================================================
-- 7. Verificacion (solo lectura). Se puede ejecutar suelto despues del script.
-- =============================================================================

-- Columnas nuevas en app_dat_tienda (deben aparecer las 4).
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tienda'
  AND column_name IN ('estado_onboarding','tipo_negocio','activada_en','onboarding_descartado_en')
ORDER BY column_name;

-- CHECKs presentes.
SELECT conname, pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conrelid = 'public.app_dat_tienda'::regclass
  AND conname IN ('chk_tienda_estado_onboarding','chk_tienda_tipo_negocio')
ORDER BY conname;

-- Backfill: debe dar 0. Si no da 0, hay tiendas que quedaron en borrador
-- (esperado solo si alguien las puso a proposito despues del despliegue).
SELECT count(*) AS tiendas_en_borrador
FROM public.app_dat_tienda
WHERE estado_onboarding = 'borrador';

-- Reparto por estado, util para confirmar que las tiendas vivas quedaron activas.
SELECT estado_onboarding, count(*) AS tiendas
FROM public.app_dat_tienda
GROUP BY estado_onboarding
ORDER BY estado_onboarding;

-- La columna geografica `estado` sigue intacta (no debe haberse tocado).
SELECT id, denominacion, estado AS codigo_provincia, estado_onboarding
FROM public.app_dat_tienda
ORDER BY id;

-- Tabla y RLS.
SELECT c.relname, c.relrowsecurity AS rls_activa
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_tarea_onboarding';

-- Politicas de la tabla (deben ser 4: leer, insertar, actualizar, eliminar).
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'app_dat_tarea_onboarding'
ORDER BY policyname;

-- Permisos del rol authenticated.
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tarea_onboarding'
  AND grantee IN ('authenticated','service_role')
ORDER BY grantee, privilege_type;
