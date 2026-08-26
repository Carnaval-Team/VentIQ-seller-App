-- ============================================================================
-- 07 · Fase 1 · Schema de cocinas (datos)
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente.
-- REQUISITOS: Fase 0 completa (01, 03, 05, 06 aplicados).
--
-- MODELO (del plan, seccion "Modelo objetivo")
-- --------------------------------------------
-- La tienda tiene N almacenes de venta (TPV) y N cocinas.
-- Cada cocina ES un almacen propio (materias primas + tandas).
-- Un TPV se relaciona con una o mas cocinas (N:M).
-- El producto elaborado indica a que cocina va y si es por_tanda o al_pedido.
--
-- Decisiones que este archivo respeta (seccion "No hacer" del plan):
--   - la cocina NO se cuelga del TPV; el TPV sigue siendo caja;
--   - NO hay un solo id_almacen_cocina en la tienda (rompe multi-cocina);
--   - NO se reviven las tablas app_rest_*.
--
-- POR QUE LA COCINA ES UN ALMACEN
-- -------------------------------
-- Reutiliza todo lo que ya existe y funciona: layouts
-- (app_dat_layout_almacen), inventario (app_dat_inventario_productos),
-- recepcion, conteo, transferencias, y el helper de Fase 0
-- fn_descontar_ingredientes_elaborado(p_id_almacen := <almacen de la cocina>).
-- Sin esto habria que duplicar el modulo de inventario entero.
--
-- ESTE ARCHIVO SOLO CREA/AGREGA. No modifica ninguna funcion existente.
-- Nada de lo que agrega cambia el comportamiento actual: los defaults estan
-- elegidos para que una tienda sin cocinas siga operando igual.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 7.1 app_dat_almacen.es_cocina
-- Marca un almacen como estacion de cocina.
--
-- Default false: todos los almacenes existentes siguen siendo almacenes de
-- venta, sin cambio de comportamiento.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_almacen
    ADD COLUMN IF NOT EXISTS es_cocina boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_almacen.es_cocina
    IS 'Si true, este almacen es una estacion de cocina (materias primas + tandas), no un almacen de venta.';

-- Indice parcial: las consultas de cocina siempre filtran es_cocina = true,
-- que sera una minoria de filas.
CREATE INDEX IF NOT EXISTS idx_almacen_tienda_es_cocina
    ON public.app_dat_almacen (id_tienda)
    WHERE es_cocina = true AND deleted_at IS NULL;


-- ----------------------------------------------------------------------------
-- 7.2 app_dat_cocina
-- Una fila por cocina. Cuelga de la tienda y apunta a su almacen.
--
-- Se separa de app_dat_almacen porque la cocina tiene atributos propios que no
-- aplican a un almacen normal (impresora, orden de visualizacion en el KDS) y
-- porque asi la relacion N:M con TPV apunta a una entidad "cocina", no a un
-- almacen generico.
--
-- UNIQUE (id_almacen): un almacen no puede ser dos cocinas.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_cocina
(
    id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda     bigint      NOT NULL,
    id_almacen    bigint      NOT NULL,
    denominacion  text        NOT NULL,
    descripcion   text,
    -- Nombre/identificador de la impresora de esta cocina. Se usa en Fase 3
    -- para el ticket tipo 'cocina'. Texto libre porque el vendedor guarda la
    -- impresora por nombre (ver configuracion_tienda.guardar_impresora_por_defecto).
    impresora     text,
    -- Orden de aparicion en pantallas (KDS, selectores). Menor primero.
    orden         smallint    NOT NULL DEFAULT 0,
    activa        boolean     NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    deleted_at    timestamptz,

    CONSTRAINT app_dat_cocina_tienda_fkey
        FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_cocina_almacen_fkey
        FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen (id) ON DELETE RESTRICT,
    CONSTRAINT app_dat_cocina_almacen_unique
        UNIQUE (id_almacen)
);

CREATE INDEX IF NOT EXISTS idx_cocina_tienda_activa
    ON public.app_dat_cocina (id_tienda, activa)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE  public.app_dat_cocina
    IS 'Estaciones de cocina de una tienda. Cada cocina es un almacen propio (app_dat_almacen.es_cocina = true).';
COMMENT ON COLUMN public.app_dat_cocina.id_almacen
    IS 'Almacen que respalda esta cocina: ahi vive su materia prima y sus tandas terminadas.';
COMMENT ON COLUMN public.app_dat_cocina.impresora
    IS 'Impresora de esta cocina para el ticket tipo cocina (Fase 3). NULL = usar la del dispositivo.';
COMMENT ON COLUMN public.app_dat_cocina.orden
    IS 'Orden de aparicion en KDS y selectores. Menor primero.';


-- ----------------------------------------------------------------------------
-- 7.3 app_dat_tpv_cocina
-- Relacion N:M entre TPV y cocina: a que cocinas puede mandar comandas un TPV.
--
-- Criterio de acceptacion del plan: "TPV Terraza ligado a 2 cocinas ve platos
-- de ambas" y "TPV Bar ... bistec va a Cocina caliente; no aparece en Pizzeria".
--
-- ON DELETE CASCADE en ambos lados: si se borra el TPV o la cocina, el vinculo
-- deja de tener sentido.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_tpv_cocina
(
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tpv      bigint      NOT NULL,
    id_cocina   bigint      NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT app_dat_tpv_cocina_tpv_fkey
        FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_tpv_cocina_cocina_fkey
        FOREIGN KEY (id_cocina) REFERENCES public.app_dat_cocina (id) ON DELETE CASCADE,
    CONSTRAINT app_dat_tpv_cocina_unique
        UNIQUE (id_tpv, id_cocina)
);

-- El UNIQUE ya cubre las busquedas por id_tpv (prefijo del indice implicito).
-- Falta el sentido inverso: "que TPVs estan ligados a esta cocina".
CREATE INDEX IF NOT EXISTS idx_tpv_cocina_cocina
    ON public.app_dat_tpv_cocina (id_cocina);

COMMENT ON TABLE public.app_dat_tpv_cocina
    IS 'Que cocinas puede usar cada TPV. Un TPV sin filas aqui no puede vender platos de cocina.';


-- ----------------------------------------------------------------------------
-- 7.4 app_dat_producto: modo_elaboracion + id_cocina
--
-- modo_elaboracion:
--   'al_pedido' -> se cocina cuando se pide (bistec). Baja MP al pedir.
--   'por_tanda' -> se produce en lotes (arroz moro). Se vende del stock
--                  terminado; la explosion de receta PARA aqui.
--
-- Default 'al_pedido' por decision explicita del plan: "Default de
-- modo_elaboracion = al_pedido (no romper elaborados actuales)". Con ese default
-- los elaborados que ya existen se comportan exactamente como hoy.
--
-- id_cocina NULL = el producto no va a cocina (cerveza, refresco, un elaborado
-- que se arma en la barra). No se pone NOT NULL porque la mayoria de los
-- productos de la base no son platos.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_producto
    ADD COLUMN IF NOT EXISTS modo_elaboracion text NOT NULL DEFAULT 'al_pedido';

ALTER TABLE public.app_dat_producto
    ADD COLUMN IF NOT EXISTS id_cocina bigint;

-- CHECK con nombre fijo, creado solo si no existe (ADD CONSTRAINT no admite
-- IF NOT EXISTS en Postgres).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_producto_modo_elaboracion_check'
    ) THEN
        ALTER TABLE public.app_dat_producto
            ADD CONSTRAINT app_dat_producto_modo_elaboracion_check
            CHECK (modo_elaboracion IN ('al_pedido', 'por_tanda'));
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_producto_id_cocina_fkey'
    ) THEN
        ALTER TABLE public.app_dat_producto
            ADD CONSTRAINT app_dat_producto_id_cocina_fkey
            FOREIGN KEY (id_cocina) REFERENCES public.app_dat_cocina (id)
            ON DELETE SET NULL;
    END IF;
END$$;

-- Indice para el catalogo dual: "elaborados de las cocinas ligadas a este TPV".
CREATE INDEX IF NOT EXISTS idx_producto_cocina
    ON public.app_dat_producto (id_cocina)
    WHERE id_cocina IS NOT NULL AND deleted_at IS NULL;

COMMENT ON COLUMN public.app_dat_producto.modo_elaboracion
    IS 'al_pedido = se cocina al pedirlo (baja MP al pedir). por_tanda = se produce en lotes y se vende del stock terminado.';
COMMENT ON COLUMN public.app_dat_producto.id_cocina
    IS 'Cocina que prepara este producto. NULL = no va a cocina (barra / listo para venta).';


-- ----------------------------------------------------------------------------
-- 7.5 app_dat_categoria_tienda.id_cocina (opcional del plan)
-- Cocina por defecto de una categoria en una tienda: al crear un producto en
-- "Platos calientes" se propone esa cocina. Es solo un default para la UI; la
-- verdad operativa es app_dat_producto.id_cocina.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_categoria_tienda
    ADD COLUMN IF NOT EXISTS id_cocina bigint;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_categoria_tienda_id_cocina_fkey'
    ) THEN
        ALTER TABLE public.app_dat_categoria_tienda
            ADD CONSTRAINT app_dat_categoria_tienda_id_cocina_fkey
            FOREIGN KEY (id_cocina) REFERENCES public.app_dat_cocina (id)
            ON DELETE SET NULL;
    END IF;
END$$;

COMMENT ON COLUMN public.app_dat_categoria_tienda.id_cocina
    IS 'Cocina sugerida por defecto para productos nuevos de esta categoria. Solo default de UI.';


-- ----------------------------------------------------------------------------
-- 7.6 Configuracion de tienda: flag de cocina
--
-- modo_restaurante ya existe y activa mesas. La cocina es un paso mas: hay
-- tiendas en modo restaurante que NO tienen cocina (bar que solo sirve bebidas
-- y platos ya listos). Con este flag el vendedor no ve nada de comandas hasta
-- que se active.
--
-- tickets_a_imprimir ya es jsonb y admite 'cocina' sin cambio de schema; hoy
-- contiene ["cliente","almacen"]. No se toca el dato existente.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_configuracion_tienda
    ADD COLUMN IF NOT EXISTS cocina_activa boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.cocina_activa
    IS 'Si true, la tienda usa cocinas: el TPV enruta platos y aparece el KDS. Requiere modo_restaurante.';


-- ----------------------------------------------------------------------------
-- 7.7 Trigger de updated_at en app_dat_cocina
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cocina_updated_at ON public.app_dat_cocina;
CREATE TRIGGER trg_cocina_updated_at
    BEFORE UPDATE ON public.app_dat_cocina
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_touch_updated_at();


-- ----------------------------------------------------------------------------
-- 7.8 Coherencia: el almacen de una cocina debe estar marcado es_cocina
--
-- En vez de confiar en que la RPC lo haga siempre, se fuerza por trigger. Asi
-- ninguna via (RPC, dashboard, script) puede dejar los datos inconsistentes.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cocina_marcar_almacen()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tienda_almacen bigint;
BEGIN
    SELECT id_tienda INTO v_tienda_almacen
      FROM public.app_dat_almacen
     WHERE id = NEW.id_almacen;

    IF v_tienda_almacen IS NULL THEN
        RAISE EXCEPTION 'El almacen % no existe', NEW.id_almacen
            USING ERRCODE = 'P0001';
    END IF;

    -- La cocina y su almacen tienen que ser de la misma tienda.
    IF v_tienda_almacen <> NEW.id_tienda THEN
        RAISE EXCEPTION 'El almacen % pertenece a la tienda %, no a la tienda % de la cocina',
                        NEW.id_almacen, v_tienda_almacen, NEW.id_tienda
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.app_dat_almacen
       SET es_cocina = true
     WHERE id = NEW.id_almacen
       AND es_cocina = false;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cocina_marcar_almacen ON public.app_dat_cocina;
CREATE TRIGGER trg_cocina_marcar_almacen
    AFTER INSERT OR UPDATE OF id_almacen, id_tienda ON public.app_dat_cocina
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_cocina_marcar_almacen();


-- ----------------------------------------------------------------------------
-- 7.9 Coherencia: un TPV solo se liga a cocinas de su misma tienda
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validar_tpv_cocina()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tienda_tpv    bigint;
    v_tienda_cocina bigint;
BEGIN
    SELECT id_tienda INTO v_tienda_tpv
      FROM public.app_dat_tpv WHERE id = NEW.id_tpv;

    SELECT id_tienda INTO v_tienda_cocina
      FROM public.app_dat_cocina WHERE id = NEW.id_cocina;

    IF v_tienda_tpv IS NULL THEN
        RAISE EXCEPTION 'El TPV % no existe', NEW.id_tpv USING ERRCODE = 'P0001';
    END IF;

    IF v_tienda_cocina IS NULL THEN
        RAISE EXCEPTION 'La cocina % no existe', NEW.id_cocina USING ERRCODE = 'P0001';
    END IF;

    IF v_tienda_tpv <> v_tienda_cocina THEN
        RAISE EXCEPTION 'El TPV % (tienda %) no puede ligarse a la cocina % (tienda %)',
                        NEW.id_tpv, v_tienda_tpv, NEW.id_cocina, v_tienda_cocina
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_tpv_cocina ON public.app_dat_tpv_cocina;
CREATE TRIGGER trg_validar_tpv_cocina
    BEFORE INSERT OR UPDATE ON public.app_dat_tpv_cocina
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validar_tpv_cocina();


-- ----------------------------------------------------------------------------
-- 7.10 Coherencia: un producto solo apunta a una cocina de su misma tienda
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validar_producto_cocina()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tienda_cocina bigint;
BEGIN
    IF NEW.id_cocina IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_tienda INTO v_tienda_cocina
      FROM public.app_dat_cocina WHERE id = NEW.id_cocina;

    IF v_tienda_cocina IS NULL THEN
        RAISE EXCEPTION 'La cocina % no existe', NEW.id_cocina USING ERRCODE = 'P0001';
    END IF;

    IF v_tienda_cocina <> NEW.id_tienda THEN
        RAISE EXCEPTION 'El producto % (tienda %) no puede asignarse a la cocina % (tienda %)',
                        NEW.id, NEW.id_tienda, NEW.id_cocina, v_tienda_cocina
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_producto_cocina ON public.app_dat_producto;
CREATE TRIGGER trg_validar_producto_cocina
    BEFORE INSERT OR UPDATE OF id_cocina, id_tienda ON public.app_dat_producto
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validar_producto_cocina();


-- ----------------------------------------------------------------------------
-- 7.11 Vista de apoyo: cocinas con su almacen y sus TPVs
-- Evita repetir el join en cada pantalla del admin.
--
-- security_invoker = true: la vista respeta los permisos de quien la consulta,
-- no los del creador. Sin esto una vista en un schema expuesto puede filtrar
-- filas de otras tiendas.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.vista_cocinas_tienda;
CREATE VIEW public.vista_cocinas_tienda
WITH (security_invoker = true) AS
SELECT
    c.id                AS id_cocina,
    c.id_tienda,
    c.denominacion      AS cocina,
    c.descripcion,
    c.impresora,
    c.orden,
    c.activa,
    c.id_almacen,
    a.denominacion      AS almacen,
    a.es_cocina,
    (SELECT COUNT(*) FROM public.app_dat_layout_almacen la
      WHERE la.id_almacen = c.id_almacen AND la.deleted_at IS NULL)
                        AS cantidad_layouts,
    (SELECT COUNT(*) FROM public.app_dat_tpv_cocina tc
      WHERE tc.id_cocina = c.id)
                        AS cantidad_tpvs,
    (SELECT COUNT(*) FROM public.app_dat_producto p
      WHERE p.id_cocina = c.id AND p.deleted_at IS NULL)
                        AS cantidad_productos,
    c.created_at,
    c.updated_at
  FROM public.app_dat_cocina c
  JOIN public.app_dat_almacen a ON a.id = c.id_almacen
 WHERE c.deleted_at IS NULL;

COMMENT ON VIEW public.vista_cocinas_tienda
    IS 'Cocinas activas con su almacen, cantidad de layouts, TPVs ligados y productos asignados.';

GRANT SELECT ON public.vista_cocinas_tienda TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================
-- (a) Columnas nuevas -> 5 filas
--
--   SELECT table_name, column_name, data_type, column_default
--     FROM information_schema.columns
--    WHERE table_schema = 'public'
--      AND (
--        (table_name = 'app_dat_almacen'              AND column_name = 'es_cocina')
--     OR (table_name = 'app_dat_producto'             AND column_name IN ('modo_elaboracion','id_cocina'))
--     OR (table_name = 'app_dat_categoria_tienda'     AND column_name = 'id_cocina')
--     OR (table_name = 'app_dat_configuracion_tienda' AND column_name = 'cocina_activa')
--      )
--    ORDER BY table_name, column_name;
--
-- (b) Tablas nuevas -> 2 filas
--
--   SELECT table_name FROM information_schema.tables
--    WHERE table_schema = 'public'
--      AND table_name IN ('app_dat_cocina','app_dat_tpv_cocina');
--
-- (c) Ningun elaborado cambio de comportamiento: todos quedan al_pedido
--     y sin cocina asignada -> por_tanda = 0, con_cocina = 0
--
--   SELECT modo_elaboracion,
--          COUNT(*)                                  AS productos,
--          COUNT(*) FILTER (WHERE es_elaborado)      AS elaborados,
--          COUNT(*) FILTER (WHERE id_cocina IS NOT NULL) AS con_cocina
--     FROM public.app_dat_producto
--    WHERE deleted_at IS NULL
--    GROUP BY modo_elaboracion;
--
-- (d) Ninguna tienda tiene cocina activada todavia -> 0 filas
--
--   SELECT id_tienda FROM public.app_dat_configuracion_tienda WHERE cocina_activa = true;
--
-- (e) Triggers instalados -> 4 filas
--
--   SELECT c.relname AS tabla, t.tgname AS trigger
--     FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
--    WHERE NOT t.tgisinternal
--      AND t.tgname IN ('trg_cocina_updated_at','trg_cocina_marcar_almacen',
--                       'trg_validar_tpv_cocina','trg_validar_producto_cocina')
--    ORDER BY c.relname, t.tgname;
--
-- (f) La vista responde (vacia hasta crear la primera cocina)
--
--   SELECT * FROM public.vista_cocinas_tienda;
--
--
-- PRUEBA DE LOS TRIGGERS (dentro de una transaccion que se revierte)
-- -----------------------------------------------------------------
-- Sustituir 11 por una tienda real en modo restaurante.
--
--   BEGIN;
--     -- crear almacen de cocina
--     INSERT INTO app_dat_almacen (id_tienda, denominacion)
--     VALUES (11, 'PRUEBA Cocina caliente') RETURNING id;
--     -- usar ese id abajo como <ALM>
--
--     INSERT INTO app_dat_cocina (id_tienda, id_almacen, denominacion)
--     VALUES (11, <ALM>, 'PRUEBA Cocina caliente') RETURNING id;
--
--     -- el trigger 7.8 debe haber marcado es_cocina = true
--     SELECT id, denominacion, es_cocina FROM app_dat_almacen WHERE id = <ALM>;
--
--     -- ligar un TPV de OTRA tienda debe FALLAR
--     INSERT INTO app_dat_tpv_cocina (id_tpv, id_cocina)
--     VALUES (<TPV de otra tienda>, <COCINA>);
--     -- esperado: 'El TPV X (tienda Y) no puede ligarse a la cocina ...'
--   ROLLBACK;
-- ============================================================================
