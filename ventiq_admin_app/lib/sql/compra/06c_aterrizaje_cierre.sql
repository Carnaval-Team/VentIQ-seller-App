-- ============================================================================
-- 06c_aterrizaje_cierre.sql — Fase 6c: resumen del costo aterrizado, catálogo
--                             de costos bajo superadmin y retirada del código
--                             muerto `_v3`
--
-- REQUIERE: 06a y 06b aplicados.
--
-- Qué añade:
--   0. **Reversa del costo al cancelar/devolver una recepción** (decisión del
--      dueño): columnas de reversa en `app_dat_recepcion_producto_costo`,
--      trigger sobre `app_dat_estado_operacion` (estados 3 y 4),
--      `fn_fdi_recepcion_revertir_costo` y `_v2` excluyendo las filas
--      revertidas. Marca, no borra: el importe y el tipo se conservan.
--   1. `fn_fdi_compra_costo_resumen(bigint)` — STABLE, JSON. Una sola fuente
--      para lo que la UI necesita del costo aterrizado de una compra:
--        · valor de factura vinculado y cargo de importadora aplicado;
--        · % declarado (ajuste porcentual del catálogo) vs % efectivo y desvío;
--        · ajustes globales: cuánto se aplica según lo recibido y cuánto queda
--          por asignar (la regla "el costo global se reparte solo sobre lo
--          recibido" del plan, sin persistir nada);
--        · por vínculo y por línea de recepción, el costo de factura, los
--          costos ya persistidos y el costo aterrizado unitario.
--      No escribe: el aterrizaje lo persiste 06b y el promedio lo capitaliza
--      `fn_actualizar_precio_promedio_recepcion_v2`.
--   2. `fn_cont_tipo_costo_guardar(...)` y `fn_cont_tipo_costo_eliminar(...)` —
--      el nomenclador `app_cont_tipo_costo` pasa a gestionarse **solo por
--      superadmin**. Antes la tabla tenía RLS con una política ALL/true para
--      `authenticated` y GRANT de INSERT/UPDATE/DELETE a `anon` y
--      `authenticated`: cualquier usuario podía crear o borrar conceptos por
--      PostgREST. Ahora la tabla queda en **solo lectura** y la escritura pasa
--      por estas RPC SECURITY DEFINER con comprobación de superadmin.
--      Guardas: no se puede renombrar ni borrar `Importadora` (el aterrizaje la
--      resuelve por denominación), ni borrar un concepto en uso.
--   3. `DROP` de `fn_actualizar_precio_promedio_recepcion_v3(bigint, jsonb)`:
--      código muerto (0 referencias en el cliente). La v2 es la que se usa.
--
-- ROLLBACK: 06c_aterrizaje_cierre_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Preflight
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_ajuste') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_ajuste;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion;';
    END IF;
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL THEN
        v_falta := v_falta || ' app_dat_recepcion_producto_costo;';
    END IF;
    IF to_regclass('public.app_cont_tipo_costo') IS NULL THEN
        v_falta := v_falta || ' app_cont_tipo_costo;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '06c: faltan tablas:%.', v_falta USING ERRCODE = '42P01';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'app_dat_recepcion_producto_costo'
           AND column_name = 'id_compra_recepcion') THEN
        RAISE EXCEPTION '06c: falta app_dat_recepcion_producto_costo.id_compra_recepcion. Aplique 06b.'
            USING ERRCODE = '42P01';
    END IF;

    IF to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)') IS NULL THEN
        RAISE EXCEPTION '06c: falta fn_fdi_compra_recepcion_bases(bigint). Aplique 06b.'
            USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_user_can_access_tienda(bigint)') IS NULL THEN
        RAISE EXCEPTION '06c: falta fn_user_can_access_tienda(bigint).' USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_is_superadmin_full_access()') IS NULL THEN
        RAISE EXCEPTION '06c: falta fn_is_superadmin_full_access().' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1a) Reversa del costo al cancelar (o devolver) una recepción
--
--     Decisión del dueño (2026-11-21): **marcar**, no borrar. Las filas de
--     costo conservan su importe y su tipo; se marcan como revertidas con la
--     fecha, el usuario, el motivo y la fila de estado que lo provocó. Con eso:
--       · `_v2` no vuelve a capitalizarlas (se parchea abajo),
--       · el resumen de la compra las ignora y el costo aterrizado de la línea
--         vuelve al de factura (`costo_real`),
--       · queda el documento: la fila de `app_dat_estado_operacion` que dispara
--         el trigger y una entrada en `fdi_hist_estado_compra` por compra con
--         filas e importe revertidos.
--
--     LÍMITE CONOCIDO (documentado, no oculto): `precio_promedio` ya ponderado
--     NO se reconstruye. Deshacer una ponderación exigiría recalcular el costo
--     del producto desde sus recepciones vivas, que es un recosteo completo y
--     no forma parte de esta fase.
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_dat_recepcion_producto_costo
    ADD COLUMN IF NOT EXISTS revertido_at      timestamptz,
    ADD COLUMN IF NOT EXISTS revertido_por     uuid,
    ADD COLUMN IF NOT EXISTS motivo_reversa    text,
    ADD COLUMN IF NOT EXISTS id_estado_reversa bigint
        REFERENCES public.app_dat_estado_operacion(id);

ALTER TABLE public.app_dat_recepcion_producto_costo
    DROP CONSTRAINT IF EXISTS chk_recepcion_costo_reversa_motivo;
ALTER TABLE public.app_dat_recepcion_producto_costo
    ADD CONSTRAINT chk_recepcion_costo_reversa_motivo
    CHECK (revertido_at IS NULL OR motivo_reversa IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_recepcion_producto_costo_vigente
    ON public.app_dat_recepcion_producto_costo (id_recepcion_producto)
    WHERE revertido_at IS NULL;

CREATE OR REPLACE FUNCTION public.fn_fdi_recepcion_revertir_costo(
    p_id_operacion bigint,
    p_id_estado    bigint,
    p_uuid         uuid,
    p_motivo       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_links  integer;
    v_filas  integer;
    v_lineas integer;
    v_monto  numeric;
    v_motivo text := COALESCE(NULLIF(btrim(p_motivo), ''), 'Cancelación de la recepción');
    v_r      record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_operacion_recepcion
                    WHERE id_operacion = p_id_operacion) THEN
        RETURN jsonb_build_object('status', 'no_aplica', 'motivo', 'no_es_recepcion');
    END IF;

    SELECT count(*) INTO v_links
      FROM public.fdi_dat_compra_recepcion
     WHERE id_operacion = p_id_operacion;

    IF v_links = 0 THEN
        RETURN jsonb_build_object('status', 'no_aplica', 'motivo', 'sin_vinculo');
    END IF;

    SELECT count(*), count(DISTINCT c.id_recepcion_producto), COALESCE(sum(c.monto_usd), 0)
      INTO v_filas, v_lineas, v_monto
      FROM public.app_dat_recepcion_producto_costo c
     WHERE c.revertido_at IS NULL
       AND c.id_recepcion_producto IN (
           SELECT rp.id FROM public.app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion)
       AND (c.id_compra_recepcion IN (
                SELECT r.id FROM public.fdi_dat_compra_recepcion r
                 WHERE r.id_operacion = p_id_operacion)
            OR (c.id_compra_recepcion IS NULL AND v_links = 1));

    IF v_filas = 0 THEN
        RETURN jsonb_build_object('status', 'no_aplica', 'motivo', 'sin_costos');
    END IF;

    UPDATE public.app_dat_recepcion_producto_costo c
       SET revertido_at      = now(),
           revertido_por     = p_uuid,
           motivo_reversa    = v_motivo,
           id_estado_reversa = p_id_estado
     WHERE c.revertido_at IS NULL
       AND c.id_recepcion_producto IN (
           SELECT rp.id FROM public.app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion)
       AND (c.id_compra_recepcion IN (
                SELECT r.id FROM public.fdi_dat_compra_recepcion r
                 WHERE r.id_operacion = p_id_operacion)
            OR (c.id_compra_recepcion IS NULL AND v_links = 1));

    -- El costo aplicado de la línea vuelve al de factura: el aterrizaje ya no
    -- cuenta para esa recepción. Misma fórmula que el trigger NULL-safe.
    UPDATE public.app_dat_recepcion_productos rp
       SET costo_real = (COALESCE(rp.precio_unitario, 0) - COALESCE(rp.descuento_monto, 0))
                        - (COALESCE(rp.precio_referencia, 0) * COALESCE(rp.descuento_porcentaje, 0) / 100)
     WHERE rp.id IN (
         SELECT c.id_recepcion_producto
           FROM public.app_dat_recepcion_producto_costo c
          WHERE c.id_estado_reversa = p_id_estado);

    FOR v_r IN
        SELECT DISTINCT r.id_compra, r.id_tienda
          FROM public.fdi_dat_compra_recepcion r
         WHERE r.id_operacion = p_id_operacion
    LOOP
        INSERT INTO public.fdi_hist_estado_compra
            (id_compra, id_tienda, estado_anterior, estado_nuevo, origen, motivo, created_by)
        SELECT v_r.id_compra, v_r.id_tienda, c.estado, c.estado, 'automatico',
               format('Reversión de costo por cancelación de la recepción %s: %s fila(s), %s USD',
                      p_id_operacion, v_filas, v_monto),
               p_uuid
          FROM public.fdi_dat_compra c
         WHERE c.id = v_r.id_compra;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_operacion', p_id_operacion,
        'filas', v_filas,
        'lineas', v_lineas,
        'monto_usd', v_monto);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_recepcion_revertir_costo(bigint, bigint, uuid, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fdi_recepcion_revertir_costo(bigint, bigint, uuid, text)
    TO service_role;

CREATE OR REPLACE FUNCTION public.trg_fdi_estado_revertir_costo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.fn_fdi_recepcion_revertir_costo(
        NEW.id_operacion,
        NEW.id,
        NEW.uuid,
        COALESCE(NULLIF(btrim(NEW.comentario), ''),
                 format('Cancelación de la recepción %s (estado %s)', NEW.id_operacion, NEW.estado)));
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_fdi_estado_revertir_costo() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_fdi_estado_revertir_costo ON public.app_dat_estado_operacion;
CREATE TRIGGER trg_fdi_estado_revertir_costo
    AFTER INSERT ON public.app_dat_estado_operacion
    FOR EACH ROW
    WHEN (NEW.estado IN (3, 4))
    EXECUTE FUNCTION public.trg_fdi_estado_revertir_costo();

-- `_v2` deja de leer las filas revertidas. Se reescribe la función a partir de
-- su definición viva con dos anclas exactas y se aborta si el cuerpo no es el
-- esperado; así no se reescribe a mano una función de 200 líneas.
DO $$
DECLARE
    v_def text;
    v_new text;
    v_n   integer;
BEGIN
    SELECT pg_get_functiondef('public.fn_actualizar_precio_promedio_recepcion_v2(bigint,jsonb)'::regprocedure)
      INTO v_def;

    v_new := replace(v_def,
        'rpc.id_recepcion_producto = v_id_rp;',
        'rpc.id_recepcion_producto = v_id_rp AND rpc.revertido_at IS NULL;');
    v_new := regexp_replace(v_new,
        '(x\.id_recepcion_producto = v_id_rp\s+AND x\.id_tipo_costo = v_costo\.id_tipo_costo)',
        '\1 AND x.revertido_at IS NULL', 'g');

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'revertido_at IS NULL', 'g');
    IF v_n <> 2 THEN
        RAISE EXCEPTION '06c: no se pudo parchear _v2 para excluir las filas revertidas (anclas encontradas: %). Revise el cuerpo de fn_actualizar_precio_promedio_recepcion_v2.', v_n;
    END IF;

    EXECUTE v_new;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1b) Resumen del costo aterrizado de una compra (solo lectura)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_costo_resumen(p_id_compra bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_c           record;
    v_valor       numeric := 0;
    v_cargo       numeric := 0;
    v_pct_decl    numeric;
    v_esperado    numeric;
    v_ajustes     numeric := 0;
    v_pedido      numeric := 0;
    v_recibido    numeric := 0;
    v_pct_rec     numeric := 0;
    v_aj_aplicado numeric := 0;
    v_vinculos    jsonb := '[]'::jsonb;
    v_lineas      jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO v_c FROM public.fdi_dat_compra WHERE id = p_id_compra;
    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Compra % no encontrada', p_id_compra USING ERRCODE = 'P0002';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(v_c.id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la compra %', p_id_compra USING ERRCODE = '42501';
    END IF;

    -- Valor de factura de lo vinculado y cargo de importadora ya registrado.
    SELECT COALESCE(sum(r.base_importadora), 0),
           COALESCE(sum(r.monto_importadora), 0)
      INTO v_valor, v_cargo
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_compra = p_id_compra;

    -- % declarado en la compra (ajuste porcentual del tipo Importadora).
    SELECT max(a.valor) INTO v_pct_decl
      FROM public.fdi_dat_compra_ajuste a
      JOIN public.app_cont_tipo_costo t ON t.id = a.id_tipo_costo
     WHERE a.id_compra = p_id_compra
       AND lower(btrim(t.denominacion)) = 'importadora'
       AND a.base = 'porcentaje';

    IF v_pct_decl IS NOT NULL THEN
        v_esperado := round(v_valor * v_pct_decl / 100, 2);
    END IF;

    -- Ajustes globales que capitalizan (flete, aduana... declarados por compra).
    SELECT COALESCE(sum(a.monto_capitalizado), 0) INTO v_ajustes
      FROM public.fdi_dat_compra_ajuste a
     WHERE a.id_compra = p_id_compra
       AND a.base = 'global'
       AND a.afecta_inventario;

    -- Avance por unidades: lo recibido no supera lo pedido en cada línea.
    SELECT COALESCE(sum(l.cantidad), 0),
           COALESCE(sum(LEAST(
               COALESCE((SELECT sum(rl.cantidad_recibida)
                          FROM public.fdi_dat_compra_recepcion_linea rl
                         WHERE rl.id_compra_linea = l.id), 0),
               l.cantidad)), 0)
      INTO v_pedido, v_recibido
      FROM public.fdi_dat_compra_linea l
     WHERE l.id_compra = p_id_compra;

    IF v_pedido > 0 THEN
        v_pct_rec := round(v_recibido / v_pedido, 6);
    END IF;
    v_aj_aplicado := round(v_ajustes * v_pct_rec, 2);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id_compra_recepcion', r.id,
               'id_operacion', r.id_operacion,
               'base_importadora', r.base_importadora,
               'monto_importadora', r.monto_importadora,
               'pct_importadora', r.pct_importadora,
               'reembolso_importadora', r.reembolso_importadora,
               'origen_pago', r.origen_pago,
               'moneda', r.moneda,
               'tasa_usd_aplicada', r.tasa_usd_aplicada,
               'confirmada_con_exceso', r.confirmada_con_exceso,
               'filas_costo', (SELECT count(*)
                                 FROM public.app_dat_recepcion_producto_costo c
                                WHERE c.id_compra_recepcion = r.id
                                  AND c.revertido_at IS NULL),
               'filas_revertidas', (SELECT count(*)
                                      FROM public.app_dat_recepcion_producto_costo c
                                     WHERE c.id_compra_recepcion = r.id
                                       AND c.revertido_at IS NOT NULL),
               'estado_operacion', (SELECT e.estado
                                      FROM public.app_dat_estado_operacion e
                                     WHERE e.id_operacion = r.id_operacion
                                     ORDER BY e.id DESC
                                     LIMIT 1)
           ) ORDER BY r.id), '[]'::jsonb)
      INTO v_vinculos
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_compra = p_id_compra;

    -- Líneas de recepción de los vínculos de esta compra. El costo persistido
    -- se limita a lo atribuido a estos vínculos (o a las filas sin atribuir de
    -- una operación con un solo vínculo): nunca suma costos de otra compra.
    -- `monto_usd` está en USD; el costo aterrizado unitario se expresa en la
    -- moneda de la compra (`moneda_total`), convirtiendo con la tasa USD de la
    -- operación (unidades de la moneda de la factura por 1 USD).
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id_recepcion_producto', x.id,
               'id_operacion', x.id_operacion,
               'id_producto', x.id_producto,
               'producto', x.producto,
               'cantidad', x.cantidad,
               'costo_factura_unit', x.costo_factura,
               'costos_total_usd', x.costos_usd,
               'costos_total_moneda', x.costos_moneda,
               'tasa_usd', x.tasa,
               'costo_aterrizado_unit', x.aterrizado
           ) ORDER BY x.id), '[]'::jsonb)
      INTO v_lineas
      FROM (
            SELECT rp.id,
                   rp.id_operacion,
                   rp.id_producto,
                   pr.denominacion AS producto,
                   rp.cantidad,
                   COALESCE(rp.costo_real, rp.precio_unitario, 0) AS costo_factura,
                   COALESCE(cs.total, 0) AS costos_usd,
                   round(COALESCE(cs.total, 0) * tr.tasa, 2) AS costos_moneda,
                   tr.tasa,
                   round(COALESCE(rp.costo_real, rp.precio_unitario, 0)
                         + (COALESCE(cs.total, 0) * tr.tasa) / NULLIF(rp.cantidad, 0), 4) AS aterrizado
              FROM public.app_dat_recepcion_productos rp
              JOIN public.app_dat_producto pr ON pr.id = rp.id_producto
              LEFT JOIN LATERAL (
                    SELECT sum(c.monto_usd) AS total
                      FROM public.app_dat_recepcion_producto_costo c
                     WHERE c.id_recepcion_producto = rp.id
                       AND c.revertido_at IS NULL
                       AND (c.id_compra_recepcion IN (
                                SELECT r3.id FROM public.fdi_dat_compra_recepcion r3
                                 WHERE r3.id_compra = p_id_compra)
                            OR (c.id_compra_recepcion IS NULL
                                AND (SELECT count(*)
                                       FROM public.fdi_dat_compra_recepcion r2
                                      WHERE r2.id_operacion = rp.id_operacion) = 1))
                   ) cs ON true
              LEFT JOIN LATERAL (
                    SELECT COALESCE(
                        (SELECT r.tasa_usd_aplicada
                           FROM public.fdi_dat_compra_recepcion r
                          WHERE r.id_operacion = rp.id_operacion
                            AND r.id_compra = p_id_compra
                          ORDER BY r.id
                          LIMIT 1),
                        (SELECT o.tasa_cambio_aplicada
                           FROM public.app_dat_operacion_recepcion o
                          WHERE o.id_operacion = rp.id_operacion),
                        1) AS tasa
                   ) tr ON true
             WHERE rp.id_operacion IN (
                       SELECT r.id_operacion FROM public.fdi_dat_compra_recepcion r
                        WHERE r.id_compra = p_id_compra)
               AND ((SELECT count(*)
                       FROM public.fdi_dat_compra_recepcion r2
                      WHERE r2.id_operacion = rp.id_operacion) = 1
                    OR EXISTS (SELECT 1
                                 FROM public.app_dat_recepcion_producto_costo c2
                                WHERE c2.id_recepcion_producto = rp.id
                                  AND c2.id_compra_recepcion IN (
                                      SELECT r4.id FROM public.fdi_dat_compra_recepcion r4
                                       WHERE r4.id_compra = p_id_compra)))
           ) x;

    RETURN jsonb_build_object(
        'id_compra', p_id_compra,
        'estado', v_c.estado,
        'moneda', v_c.moneda_total,
        'total_mercancia', v_c.total_mercancia,
        'total_ajustes', v_c.total_ajustes,
        'valor_vinculado', v_valor,
        'cargo_importadora', v_cargo,
        'pct_importadora_declarado', v_pct_decl,
        'pct_importadora_efectivo',
            CASE WHEN v_valor > 0 THEN round(v_cargo / v_valor * 100, 4) END,
        'cargo_esperado', v_esperado,
        'desvio_importadora',
            CASE WHEN v_esperado IS NOT NULL THEN round(v_cargo - v_esperado, 2) END,
        'ajustes_globales', v_ajustes,
        'pedido_cantidad', v_pedido,
        'recibido_cantidad', v_recibido,
        'pct_recibido', v_pct_rec,
        'ajustes_aplicados', v_aj_aplicado,
        'ajustes_por_asignar', round(v_ajustes - v_aj_aplicado, 2),
        'total_aterrizado', round(v_valor + v_cargo + v_aj_aplicado, 2),
        'vinculos', v_vinculos,
        'lineas', v_lineas);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_costo_resumen(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_costo_resumen(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Nomenclador de costos: escritura solo por superadmin
-- ---------------------------------------------------------------------------

-- Guarda común: sin sesión (service_role/editor SQL) se permite para poder
-- probar, igual que el resto del módulo; con sesión, solo superadmin.
CREATE OR REPLACE FUNCTION public.fn_fdi_exigir_superadmin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT COALESCE(public.fn_is_superadmin_full_access(), false) THEN
        RAISE EXCEPTION 'Solo superadministrador puede gestionar el nomenclador de costos'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_exigir_superadmin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_exigir_superadmin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_cont_tipo_costo_guardar(
    p_id              bigint  DEFAULT NULL,
    p_denominacion    text    DEFAULT NULL,
    p_descripcion     text    DEFAULT NULL,
    p_afecta_margen   boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nombre  text := btrim(COALESCE(p_denominacion, ''));
    v_desc    text := NULLIF(btrim(COALESCE(p_descripcion, '')), '');
    v_prev    record;
    v_id      bigint;
BEGIN
    PERFORM public.fn_fdi_exigir_superadmin();

    IF v_nombre = '' THEN
        RAISE EXCEPTION 'La denominación del concepto es obligatoria' USING ERRCODE = '22023';
    END IF;
    IF length(v_nombre) > 80 THEN
        RAISE EXCEPTION 'La denominación no puede pasar de 80 caracteres' USING ERRCODE = '22023';
    END IF;

    IF p_id IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.app_cont_tipo_costo WHERE id = p_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Concepto de costo % no encontrado', p_id USING ERRCODE = 'P0002';
        END IF;
        -- El aterrizaje resuelve este tipo por denominación: renombrarlo
        -- rompería el reparto con P0002 sin que nadie lo relacione.
        IF lower(btrim(v_prev.denominacion)) = 'importadora'
           AND lower(v_nombre) <> 'importadora' THEN
            RAISE EXCEPTION 'El concepto Importadora se resuelve por nombre en el aterrizaje: no se puede renombrar'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM public.app_cont_tipo_costo t
                WHERE lower(btrim(t.denominacion)) = lower(v_nombre)
                  AND (p_id IS NULL OR t.id <> p_id)) THEN
        RAISE EXCEPTION 'Ya existe un concepto con la denominación %', v_nombre
            USING ERRCODE = '22023';
    END IF;

    IF p_id IS NULL THEN
        -- naturaleza 1 = Gasto (app_nom_naturaleza_costo). Un costo adicional
        -- nunca es ingreso; no se acepta por parámetro para no inventarlo.
        INSERT INTO public.app_cont_tipo_costo (denominacion, descripcion, naturaleza, afecta_margen)
        VALUES (v_nombre, v_desc, 1, COALESCE(p_afecta_margen, true))
        RETURNING id INTO v_id;
    ELSE
        UPDATE public.app_cont_tipo_costo
           SET denominacion  = v_nombre,
               descripcion   = v_desc,
               afecta_margen = COALESCE(p_afecta_margen, afecta_margen)
         WHERE id = p_id;
        v_id := p_id;
    END IF;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id', v_id,
        'denominacion', v_nombre,
        'creado', p_id IS NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cont_tipo_costo_guardar(bigint, text, text, boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_cont_tipo_costo_eliminar(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tipo  record;
    v_refs  bigint;
    v_detalle text := '';
BEGIN
    PERFORM public.fn_fdi_exigir_superadmin();

    SELECT * INTO v_tipo FROM public.app_cont_tipo_costo WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Concepto de costo % no encontrado', p_id USING ERRCODE = 'P0002';
    END IF;

    IF lower(btrim(v_tipo.denominacion)) = 'importadora' THEN
        RAISE EXCEPTION 'El concepto Importadora no se puede eliminar: el aterrizaje lo resuelve por nombre'
            USING ERRCODE = '22023';
    END IF;

    SELECT (SELECT count(*) FROM public.app_dat_recepcion_producto_costo WHERE id_tipo_costo = p_id)
         + (SELECT count(*) FROM public.app_dat_producto_costo         WHERE id_tipo_costo = p_id)
         + (SELECT count(*) FROM public.fdi_dat_compra_ajuste          WHERE id_tipo_costo = p_id)
      INTO v_refs;

    IF v_refs > 0 THEN
        RAISE EXCEPTION 'El concepto % está en uso (% referencia(s)); no se elimina', v_tipo.denominacion, v_refs
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.app_cont_tipo_costo WHERE id = p_id;

    RETURN jsonb_build_object('status', 'ok', 'id', p_id, 'eliminado', true);
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'El concepto % está en uso y no se puede eliminar', v_tipo.denominacion
            USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cont_tipo_costo_eliminar(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cont_tipo_costo_eliminar(bigint) TO authenticated, service_role;

-- La tabla queda en solo lectura para el cliente: la escritura va por las RPC
-- de arriba (SECURITY DEFINER + superadmin). Se retira la política permisiva
-- (`FOR ALL USING true`) y los GRANT de escritura, incluido `anon`, que los
-- tenía y podía escribir por PostgREST.
DROP POLICY IF EXISTS app_cont_tipo_costo_authenticated_all ON public.app_cont_tipo_costo;
DROP POLICY IF EXISTS app_cont_tipo_costo_lectura ON public.app_cont_tipo_costo;

CREATE POLICY app_cont_tipo_costo_lectura
    ON public.app_cont_tipo_costo
    FOR SELECT TO authenticated
    USING (true);

REVOKE ALL ON public.app_cont_tipo_costo FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON public.app_cont_tipo_costo FROM authenticated;
GRANT SELECT ON public.app_cont_tipo_costo TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Retirar el código muerto `_v3`
-- ---------------------------------------------------------------------------
-- `fn_actualizar_precio_promedio_recepcion_v3` pondera cantidades crudas y
-- escribe el promedio en cada presentación recibida: es justo el
-- comportamiento que el script `presentaciones_inventario/20` corrigió con la
-- v2. No la llama nadie (0 referencias en `ventiq_admin_app` y `ventiq_app`).
-- Se documenta aquí y se borra; el rollback **no la restaura** a propósito.
DROP FUNCTION IF EXISTS public.fn_actualizar_precio_promedio_recepcion_v3(bigint, jsonb);

-- ---------------------------------------------------------------------------
-- 4) Verificación del script
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
    v_id_compra bigint;
    v_res jsonb;
BEGIN
    IF to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)') IS NULL THEN
        RAISE EXCEPTION '06c: no se creó fn_fdi_compra_costo_resumen(bigint)';
    END IF;
    IF to_regprocedure('public.fn_cont_tipo_costo_guardar(bigint,text,text,boolean)') IS NULL THEN
        RAISE EXCEPTION '06c: no se creó fn_cont_tipo_costo_guardar(...)';
    END IF;
    IF to_regprocedure('public.fn_cont_tipo_costo_eliminar(bigint)') IS NULL THEN
        RAISE EXCEPTION '06c: no se creó fn_cont_tipo_costo_eliminar(bigint)';
    END IF;

    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid = to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)')
       AND p.prosecdef AND p.provolatile = 's'
       AND pg_get_function_result(p.oid) = 'jsonb';
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: el resumen no quedó STABLE/SECURITY DEFINER/jsonb';
    END IF;

    IF to_regprocedure('public.fn_actualizar_precio_promedio_recepcion_v3(bigint,jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION '06c: _v3 sigue existiendo';
    END IF;

    -- El cliente no puede escribir el catálogo.
    SELECT count(*) INTO v
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public'
       AND table_name = 'app_cont_tipo_costo'
       AND grantee IN ('anon', 'authenticated')
       AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
    IF v <> 0 THEN
        RAISE EXCEPTION '06c: el catálogo conserva % permiso(s) de escritura para anon/authenticated', v;
    END IF;

    -- Y queda una sola política, de lectura.
    SELECT count(*) INTO v
      FROM pg_policy
     WHERE polrelid = 'public.app_cont_tipo_costo'::regclass
       AND polcmd = 'r';
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: se esperaba exactamente 1 política de lectura en el catálogo, hay %', v;
    END IF;

    -- Reversa: columnas, CHECK, índice, función y trigger.
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_recepcion_producto_costo'
       AND column_name IN ('revertido_at','revertido_por','motivo_reversa','id_estado_reversa');
    IF v <> 4 THEN
        RAISE EXCEPTION '06c: faltan columnas de reversa en el costo (% de 4)', v;
    END IF;

    SELECT count(*) INTO v FROM pg_constraint
     WHERE conrelid = 'public.app_dat_recepcion_producto_costo'::regclass
       AND conname = 'chk_recepcion_costo_reversa_motivo';
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: falta el CHECK de motivo de reversa';
    END IF;

    SELECT count(*) INTO v FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'app_dat_recepcion_producto_costo'
       AND indexname = 'idx_recepcion_producto_costo_vigente';
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: falta el índice de filas vigentes';
    END IF;

    IF to_regprocedure('public.fn_fdi_recepcion_revertir_costo(bigint,bigint,uuid,text)') IS NULL THEN
        RAISE EXCEPTION '06c: falta fn_fdi_recepcion_revertir_costo(...)';
    END IF;

    SELECT count(*) INTO v FROM pg_trigger
     WHERE tgrelid = 'public.app_dat_estado_operacion'::regclass
       AND tgname = 'trg_fdi_estado_revertir_costo'
       AND NOT tgisinternal;
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: falta el trigger de reversa en app_dat_estado_operacion';
    END IF;

    -- `_v2` excluye las filas revertidas (dos anclas).
    SELECT count(*) INTO v FROM pg_proc p
     WHERE p.oid = 'public.fn_actualizar_precio_promedio_recepcion_v2(bigint,jsonb)'::regprocedure
       AND (SELECT count(*) FROM regexp_matches(p.prosrc, 'revertido_at IS NULL', 'g')) = 2;
    IF v <> 1 THEN
        RAISE EXCEPTION '06c: _v2 no quedó excluyendo las filas revertidas';
    END IF;

    -- Prueba de humo (solo lectura) sobre una compra real, si hay.
    SELECT min(id) INTO v_id_compra FROM public.fdi_dat_compra;
    IF v_id_compra IS NOT NULL THEN
        v_res := public.fn_fdi_compra_costo_resumen(v_id_compra);
        IF v_res ->> 'id_compra' IS NULL THEN
            RAISE EXCEPTION '06c: el resumen no devolvió id_compra';
        END IF;
    END IF;

    RAISE NOTICE '06c aplicado: reversa de costo al cancelar, resumen del costo aterrizado, catálogo bajo superadmin y _v3 retirada.';
END;
$$;

COMMIT;