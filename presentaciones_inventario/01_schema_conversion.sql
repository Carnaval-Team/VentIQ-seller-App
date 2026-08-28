-- ============================================================================
-- 01 · Fase 0 · Esquema de conversion de presentaciones (abrir / empaquetar)
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 0)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente.
--
-- QUE HACE
-- --------
-- Agrega la infraestructura minima para que "abrir una caja" y "empaquetar
-- sueltas" sean movimientos de inventario TRAZABLES y DISTINGUIBLES de una
-- venta, una merma o un ajuste. No cambia ninguna funcion existente. No mueve
-- ni un solo saldo. Es 100% aditivo.
--
-- 1. Tabla app_dat_conversion_presentacion  -> cabecera/detalle de la conversion
-- 2. Columna app_dat_inventario_productos.id_conversion -> une las DOS patas
--    (salida de la presentacion grande + entrada de la chica) en un solo evento
-- 3. Indices de apoyo
--
-- POR QUE HACE FALTA LA COLUMNA (no basta origen_cambio)
-- ------------------------------------------------------
-- Verificado en produccion: obtener_ipv y obtener_reporte_inventario_completo*
-- clasifican como AJUSTE toda fila del ledger con
--   id_recepcion IS NULL AND id_extraccion IS NULL AND id_control IS NULL
-- Una conversion sin marca propia entraria como "ajuste positivo de 12 unidades"
-- y "ajuste negativo de 1 caja", inflando el IPV. Con id_conversion los
-- reportes pueden excluirla con un solo predicado (se hace en la Fase 3).
--
-- CODIGOS QUE SE REUTILIZAN (no se inventan nuevos)
-- ------------------------------------------------
--   app_nom_tipo_operacion.id = 20 'Cambio de presentacion'
--       Ya existe en produccion y tiene 0 usos. Su descripcion literal es
--       "Usar para cambiar la presentación de inventarios". Es exactamente esto.
--   origen_cambio = 20
--       Valores en uso hoy: 1,2,3,4,5,6,7 y un 24 suelto (que coincide con el
--       tipo de operacion 24). Se sigue esa misma convencion: origen_cambio 20
--       para las dos patas de la conversion. Ninguna consulta de produccion
--       filtra por origen_cambio con una lista cerrada, asi que 20 es seguro.
--
-- NOTA DE SEGURIDAD (para el usuario, no es un cambio de este archivo)
-- --------------------------------------------------------------------
-- app_dat_inventario_productos ya tiene INSERT/UPDATE/DELETE concedido a anon
-- y authenticated, sin RLS. Los helpers de la Fase 0 son SECURITY INVOKER: no
-- amplian el acceso existente ni lo reducen. Cerrar ese hueco es un tema
-- aparte de este plan.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1.1 Tabla de conversiones
--
-- Una fila = un evento fisico de conversion en UNA ubicacion:
--   abrir       1 Caja  -> 12 Unidades
--   empaquetar 12 Unidades ->  1 Caja
--
-- id_operacion es OPCIONAL a proposito:
--   - Conversion implicita dentro de un egreso (venta, extraccion, transfer):
--     se pasa el id_operacion de ESA operacion. No se crea una operacion
--     paralela, para no ensuciar fn_listar_operaciones_inventario.
--   - Conversion explicita (futura UI "Abrir caja"): el caller crea una
--     operacion de tipo 20 y la pasa aqui.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_conversion_presentacion (
    id                       BIGSERIAL PRIMARY KEY,
    id_operacion             BIGINT      NULL,
    id_producto              BIGINT      NOT NULL,
    id_variante              BIGINT      NULL,
    id_opcion_variante       BIGINT      NULL,
    id_ubicacion             BIGINT      NOT NULL,
    -- Presentaciones: SIEMPRE app_dat_producto_presentacion.id (el vinculo
    -- producto-presentacion), NUNCA app_nom_presentacion.id. Es el mismo
    -- contrato que app_dat_inventario_productos.id_presentacion.
    id_presentacion_origen   BIGINT      NOT NULL,
    id_presentacion_destino  BIGINT      NOT NULL,
    cantidad_origen          NUMERIC     NOT NULL,
    cantidad_destino         NUMERIC     NOT NULL,
    tipo                     TEXT        NOT NULL,
    motivo                   TEXT        NULL,
    uuid                     UUID        NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Constraints por separado para que el archivo sea re-ejecutable sin errores.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_tipo_chk') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_tipo_chk
            CHECK (tipo IN ('abrir', 'empaquetar'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_cant_chk') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_cant_chk
            CHECK (cantidad_origen > 0 AND cantidad_destino > 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_distintas_chk') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_distintas_chk
            CHECK (id_presentacion_origen <> id_presentacion_destino);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_operacion_fkey') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_operacion_fkey
            FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
            ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_producto_fkey') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_producto_fkey
            FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_ubicacion_fkey') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_ubicacion_fkey
            FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_pres_origen_fkey') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_pres_origen_fkey
            FOREIGN KEY (id_presentacion_origen)
            REFERENCES public.app_dat_producto_presentacion(id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_conversion_presentacion_pres_destino_fkey') THEN
        ALTER TABLE public.app_dat_conversion_presentacion
            ADD CONSTRAINT app_dat_conversion_presentacion_pres_destino_fkey
            FOREIGN KEY (id_presentacion_destino)
            REFERENCES public.app_dat_producto_presentacion(id);
    END IF;
END;
$$;

COMMENT ON TABLE public.app_dat_conversion_presentacion IS
    'Conversiones fisicas de empaque (abrir caja / empaquetar sueltas). Cada fila '
    'se corresponde con DOS filas de app_dat_inventario_productos (salida del '
    'origen + entrada del destino) unidas por id_conversion.';

COMMENT ON COLUMN public.app_dat_conversion_presentacion.id_presentacion_origen IS
    'app_dat_producto_presentacion.id de la presentacion que se consume.';
COMMENT ON COLUMN public.app_dat_conversion_presentacion.id_presentacion_destino IS
    'app_dat_producto_presentacion.id de la presentacion que se produce.';
COMMENT ON COLUMN public.app_dat_conversion_presentacion.tipo IS
    'abrir = origen mayor a destino (1 Caja -> 12 U). empaquetar = origen menor '
    'a destino (12 U -> 1 Caja).';

CREATE INDEX IF NOT EXISTS idx_conv_pres_producto_ubicacion
    ON public.app_dat_conversion_presentacion (id_producto, id_ubicacion, id DESC);

CREATE INDEX IF NOT EXISTS idx_conv_pres_operacion
    ON public.app_dat_conversion_presentacion (id_operacion)
    WHERE id_operacion IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 1.2 Enlace desde el ledger de inventario
--
-- Nullable, sin default: en Postgres 11+ el ADD COLUMN es instantaneo y no
-- reescribe la tabla (308k filas). Las 308k filas existentes quedan en NULL,
-- que es exactamente lo correcto: ninguna es una conversion.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_inventario_productos
    ADD COLUMN IF NOT EXISTS id_conversion BIGINT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'app_dat_inventario_productos_id_conversion_fkey') THEN
        ALTER TABLE public.app_dat_inventario_productos
            ADD CONSTRAINT app_dat_inventario_productos_id_conversion_fkey
            FOREIGN KEY (id_conversion)
            REFERENCES public.app_dat_conversion_presentacion(id)
            ON DELETE CASCADE;
    END IF;
END;
$$;

COMMENT ON COLUMN public.app_dat_inventario_productos.id_conversion IS
    'Cuando no es NULL, esta fila es una pata de una conversion de presentacion '
    '(abrir/empaquetar), NO una venta, merma ni ajuste. Los reportes de IPV y '
    'valoracion deben excluirla del calculo de ajustes.';

CREATE INDEX IF NOT EXISTS idx_inventario_conversion
    ON public.app_dat_inventario_productos (id_conversion)
    WHERE id_conversion IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 1.3 Grants (mismo patron que las tablas hermanas app_dat_*)
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.app_dat_conversion_presentacion
    TO anon, authenticated, service_role;

GRANT USAGE, SELECT
    ON SEQUENCE public.app_dat_conversion_presentacion_id_seq
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- Todo debe dar TRUE / 0.
--
-- SELECT
--   to_regclass('public.app_dat_conversion_presentacion') IS NOT NULL AS tabla_existe,
--   EXISTS (SELECT 1 FROM information_schema.columns
--            WHERE table_schema='public'
--              AND table_name='app_dat_inventario_productos'
--              AND column_name='id_conversion')                       AS columna_existe,
--   (SELECT count(*) FROM public.app_dat_conversion_presentacion)      AS conversiones_esperado_0,
--   (SELECT count(*) FROM public.app_dat_inventario_productos
--     WHERE id_conversion IS NOT NULL)                                 AS ledger_marcado_esperado_0,
--   EXISTS (SELECT 1 FROM public.app_nom_tipo_operacion WHERE id=20)   AS tipo_op_20_existe;
