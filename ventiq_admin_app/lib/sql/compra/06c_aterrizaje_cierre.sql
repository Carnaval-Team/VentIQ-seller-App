-- ============================================================================
-- 06c_aterrizaje_cierre.sql — Fase 6c: resumen del costo aterrizado, catálogo
--                             de costos bajo superadmin y retirada del código
--                             muerto `_v3`
--
-- REQUIERE: 06a y 06b aplicados.
--
-- Qué añade:
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
-- 1) Resumen del costo aterrizado de una compra (solo lectura)
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
                                WHERE c.id_compra_recepcion = r.id)
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

    -- Prueba de humo (solo lectura) sobre una compra real, si hay.
    SELECT min(id) INTO v_id_compra FROM public.fdi_dat_compra;
    IF v_id_compra IS NOT NULL THEN
        v_res := public.fn_fdi_compra_costo_resumen(v_id_compra);
        IF v_res ->> 'id_compra' IS NULL THEN
            RAISE EXCEPTION '06c: el resumen no devolvió id_compra';
        END IF;
    END IF;

    RAISE NOTICE '06c aplicado: resumen del costo aterrizado, catálogo bajo superadmin y _v3 retirada.';
END;
$$;

COMMIT;