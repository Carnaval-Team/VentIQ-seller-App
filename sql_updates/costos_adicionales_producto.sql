-- ============================================================================
-- Costos adicionales por producto
--
-- 1. app_dat_producto_costo — conceptos asociados al producto (USD / u. base)
-- 2. app_dat_recepcion_producto_costo — auditoría por línea de recepción
-- 3. costo_real deja de ser GENERATED → columna normal + trigger de fórmula
-- 4. fn_actualizar_precio_promedio_recepcion_v2 acepta costos[] opcionales
--
-- Despliegue: Newa → validar → Main
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Relación producto ↔ concepto de costo
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_dat_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_producto bigint NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL DEFAULT 0,
  monto_promedio_usd numeric NOT NULL DEFAULT 0,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id_producto, id_tipo_costo)
);

ALTER TABLE public.app_dat_producto_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_producto_costo_select ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_select ON public.app_dat_producto_costo
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_can_access_tienda(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_insert ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_insert ON public.app_dat_producto_costo
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_update ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_update ON public.app_dat_producto_costo
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_producto_costo_delete ON public.app_dat_producto_costo;
CREATE POLICY app_dat_producto_costo_delete ON public.app_dat_producto_costo
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_dat_producto p
      WHERE p.id = app_dat_producto_costo.id_producto
        AND public.fn_user_is_gerente_or_superadmin(p.id_tienda)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_producto_costo TO authenticated;
GRANT ALL ON public.app_dat_producto_costo TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Auditoría de costo aplicado por línea de recepción
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_dat_recepcion_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_recepcion_producto bigint NOT NULL
    REFERENCES public.app_dat_recepcion_productos(id) ON DELETE CASCADE,
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL,
  monto_promedio_anterior numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recepcion_producto_costo_rp
  ON public.app_dat_recepcion_producto_costo (id_recepcion_producto);

ALTER TABLE public.app_dat_recepcion_producto_costo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_select
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_select
  ON public.app_dat_recepcion_producto_costo
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_can_access_tienda(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_insert
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_insert
  ON public.app_dat_recepcion_producto_costo
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_can_access_tienda(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_update
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_update
  ON public.app_dat_recepcion_producto_costo
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  );

DROP POLICY IF EXISTS app_dat_recepcion_producto_costo_delete
  ON public.app_dat_recepcion_producto_costo;
CREATE POLICY app_dat_recepcion_producto_costo_delete
  ON public.app_dat_recepcion_producto_costo
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.app_dat_recepcion_productos rp
      JOIN public.app_dat_operaciones o ON o.id = rp.id_operacion
      WHERE rp.id = app_dat_recepcion_producto_costo.id_recepcion_producto
        AND public.fn_user_is_gerente_or_superadmin(o.id_tienda)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_recepcion_producto_costo TO authenticated;
GRANT ALL ON public.app_dat_recepcion_producto_costo TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. costo_real: de GENERATED STORED → columna normal + trigger fórmula
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'app_dat_recepcion_productos'
      AND a.attname = 'costo_real'
      AND a.attgenerated = 's'
  ) THEN
    ALTER TABLE public.app_dat_recepcion_productos
      ALTER COLUMN costo_real DROP EXPRESSION;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_fn_recepcion_productos_costo_real()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.costo_real IS NULL THEN
    NEW.costo_real :=
      (COALESCE(NEW.precio_unitario, 0) - COALESCE(NEW.descuento_monto, 0))
      - ((COALESCE(NEW.precio_referencia, 0) * COALESCE(NEW.descuento_porcentaje, 0)) / 100);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recepcion_productos_costo_real
  ON public.app_dat_recepcion_productos;
CREATE TRIGGER trg_recepcion_productos_costo_real
  BEFORE INSERT OR UPDATE OF precio_unitario, descuento_monto, descuento_porcentaje,
                             precio_referencia, costo_real
  ON public.app_dat_recepcion_productos
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_recepcion_productos_costo_real();

COMMIT;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. v2: costos[] opcionales + propagación a presentaciones
--    (SECURITY DEFINER: actualiza promedios de conceptos bajo RLS de gerente)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(
    p_id_operacion bigint,
    p_productos    jsonb
)
RETURNS TABLE(success boolean, mensaje text, productos_actualizados integer, tiempo_ms integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inicio        timestamptz := clock_timestamp();
    v_actualizados  int := 0;
    v_tiempo        int;
    v_es_devolucion boolean;
    v_fila          record;
    v_linea         record;
    v_costo         record;
    v_id_producto   bigint;
    v_factor_rel    numeric;
    v_id_base       bigint;
    v_saldo_base    numeric;
    v_costo_ant     numeric;
    v_costo_nuevo   numeric;
    v_id_rp         bigint;
    v_prev_avg      numeric;
    v_nuevo_avg     numeric;
    v_adicionales   numeric;
    v_puro_dto      numeric;
    v_cant_base_ln  numeric;
    v_costos_json   jsonb;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM app_dat_consignacion_envio
         WHERE id_operacion_recepcion = p_id_operacion
           AND tipo_envio = 2
    ) INTO v_es_devolucion;

    IF v_es_devolucion THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'Operacion de devolucion - precio promedio no actualizado'::text, 0, v_tiempo;
        RETURN;
    END IF;

    IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'La operacion es una transferencia, devolucion u operacion interna; no modifica el costo promedio'::text,
            0, v_tiempo;
        RETURN;
    END IF;

    IF p_productos IS NULL
       OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE, 'No hay productos para procesar'::text, 0, v_tiempo;
        RETURN;
    END IF;

    FOR v_fila IN
        SELECT (e->>'id_presentacion')::bigint AS id_pp
          FROM jsonb_array_elements(p_productos) e
         WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
    LOOP
        IF NOT EXISTS (SELECT 1 FROM app_dat_producto_presentacion pp
                        WHERE pp.id = v_fila.id_pp) THEN
            v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
            RETURN QUERY SELECT FALSE,
                format('La presentacion %s no existe', v_fila.id_pp)::text, 0, v_tiempo;
            RETURN;
        END IF;
    END LOOP;

    -- Por línea: auditoría de costos + costo_real efectivo + promedio por concepto.
    -- costos[] en jsonb tiene prioridad; si viene vacío se leen filas ya
    -- persistidas en app_dat_recepcion_producto_costo (alta de recepción).
    FOR v_linea IN
        SELECT
            (e->>'id_presentacion')::bigint AS id_pp,
            (e->>'precio_unitario')::numeric AS precio_unitario,
            (e->>'cantidad')::numeric        AS cantidad,
            COALESCE(e->'costos', '[]'::jsonb) AS costos_json
          FROM jsonb_array_elements(p_productos) e
         WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
           AND NULLIF(e->>'precio_unitario','') IS NOT NULL
           AND NULLIF(e->>'cantidad','')        IS NOT NULL
           AND (e->>'precio_unitario')::numeric > 0
           AND (e->>'cantidad')::numeric        > 0
    LOOP
        SELECT pp.id_producto,
               COALESCE(f.factor_rel, 1)
          INTO v_id_producto, v_factor_rel
          FROM app_dat_producto_presentacion pp
          LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                 ON f.id_presentacion = pp.id
         WHERE pp.id = v_linea.id_pp;

        IF v_id_producto IS NULL THEN
            CONTINUE;
        END IF;

        v_factor_rel := COALESCE(v_factor_rel, 1);
        v_cant_base_ln := v_linea.cantidad * v_factor_rel;

        SELECT rp.id INTO v_id_rp
          FROM app_dat_recepcion_productos rp
         WHERE rp.id_operacion = p_id_operacion
           AND rp.id_presentacion = v_linea.id_pp
         ORDER BY rp.id
         LIMIT 1;

        IF v_id_rp IS NULL THEN
            SELECT rp.id INTO v_id_rp
              FROM app_dat_recepcion_productos rp
             WHERE rp.id_operacion = p_id_operacion
               AND rp.id_producto = v_id_producto
             ORDER BY rp.id
             LIMIT 1;
        END IF;

        v_costos_json := v_linea.costos_json;
        IF (v_costos_json IS NULL
            OR jsonb_typeof(v_costos_json) <> 'array'
            OR jsonb_array_length(v_costos_json) = 0)
           AND v_id_rp IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id_tipo_costo', rpc.id_tipo_costo,
                     'monto_usd', rpc.monto_usd
                   )), '[]'::jsonb)
              INTO v_costos_json
              FROM app_dat_recepcion_producto_costo rpc
             WHERE rpc.id_recepcion_producto = v_id_rp;
        END IF;

        IF v_costos_json IS NULL
           OR jsonb_typeof(v_costos_json) <> 'array'
           OR jsonb_array_length(v_costos_json) = 0 THEN
            CONTINUE;
        END IF;

        v_adicionales := 0;

        FOR v_costo IN
            SELECT (c->>'id_tipo_costo')::bigint AS id_tipo_costo,
                   (c->>'monto_usd')::numeric    AS monto_usd
              FROM jsonb_array_elements(v_costos_json) c
             WHERE NULLIF(c->>'id_tipo_costo','') IS NOT NULL
               AND NULLIF(c->>'monto_usd','') IS NOT NULL
        LOOP
            v_adicionales := v_adicionales + COALESCE(v_costo.monto_usd, 0);

            SELECT COALESCE(pc.monto_promedio_usd, 0) INTO v_prev_avg
              FROM app_dat_producto_costo pc
             WHERE pc.id_producto = v_id_producto
               AND pc.id_tipo_costo = v_costo.id_tipo_costo
             FOR UPDATE;

            IF NOT FOUND THEN
                v_prev_avg := 0;
            END IF;

            IF v_id_rp IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM app_dat_recepcion_producto_costo x
                 WHERE x.id_recepcion_producto = v_id_rp
                   AND x.id_tipo_costo = v_costo.id_tipo_costo
            ) THEN
                INSERT INTO app_dat_recepcion_producto_costo (
                    id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior
                ) VALUES (
                    v_id_rp, v_costo.id_tipo_costo, v_costo.monto_usd, v_prev_avg
                );
            END IF;

            SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
              FROM public.fn_stock_saldos_presentacion(v_id_producto, NULL, NULL, false) s;

            v_saldo_base := GREATEST(v_saldo_base - v_cant_base_ln, 0);

            IF (v_saldo_base + v_cant_base_ln) = 0 THEN
                v_nuevo_avg := v_costo.monto_usd;
            ELSIF v_prev_avg <= 0 OR v_saldo_base <= 0 THEN
                v_nuevo_avg := v_costo.monto_usd;
            ELSE
                v_nuevo_avg := (
                    (v_prev_avg * v_saldo_base)
                    + (v_costo.monto_usd * v_cant_base_ln)
                ) / (v_saldo_base + v_cant_base_ln);
            END IF;

            INSERT INTO app_dat_producto_costo (
                id_producto, id_tipo_costo, monto_usd, monto_promedio_usd, activo
            ) VALUES (
                v_id_producto, v_costo.id_tipo_costo,
                v_costo.monto_usd, v_nuevo_avg, true
            )
            ON CONFLICT (id_producto, id_tipo_costo) DO UPDATE
              SET monto_promedio_usd = EXCLUDED.monto_promedio_usd;
        END LOOP;

        IF v_id_rp IS NOT NULL AND v_adicionales <> 0 THEN
            SELECT
                (COALESCE(rp.precio_unitario, 0) - COALESCE(rp.descuento_monto, 0))
                - ((COALESCE(rp.precio_referencia, 0) * COALESCE(rp.descuento_porcentaje, 0)) / 100)
              INTO v_puro_dto
              FROM app_dat_recepcion_productos rp
             WHERE rp.id = v_id_rp;

            UPDATE app_dat_recepcion_productos
               SET costo_real = COALESCE(v_puro_dto, 0) + (v_adicionales * v_factor_rel)
             WHERE id = v_id_rp;
        END IF;
    END LOOP;

    -- Ponderación de precio_promedio con costo efectivo (puro + adicionales)
    FOR v_fila IN
        WITH entrada AS (
            SELECT (e->>'id_presentacion')::bigint AS id_pp,
                   (e->>'precio_unitario')::numeric AS precio_unitario,
                   (e->>'cantidad')::numeric        AS cantidad,
                   COALESCE(e->'costos', '[]'::jsonb) AS costos
              FROM jsonb_array_elements(p_productos) e
             WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
               AND NULLIF(e->>'precio_unitario','') IS NOT NULL
               AND NULLIF(e->>'cantidad','')        IS NOT NULL
               AND (e->>'precio_unitario')::numeric > 0
               AND (e->>'cantidad')::numeric        > 0
        ),
        con_factor AS (
            SELECT pp.id_producto,
                   en.cantidad * COALESCE(f.factor_rel, 1) AS cant_base,
                   (en.precio_unitario / NULLIF(COALESCE(f.factor_rel, 1), 0))
                     + COALESCE((
                         SELECT SUM(x.monto)
                           FROM (
                             SELECT (c->>'monto_usd')::numeric AS monto
                               FROM jsonb_array_elements(en.costos) c
                              WHERE jsonb_typeof(en.costos) = 'array'
                                AND jsonb_array_length(en.costos) > 0
                                AND NULLIF(c->>'id_tipo_costo','') IS NOT NULL
                                AND NULLIF(c->>'monto_usd','') IS NOT NULL
                             UNION ALL
                             SELECT rpc.monto_usd
                               FROM app_dat_recepcion_productos rp
                               JOIN app_dat_recepcion_producto_costo rpc
                                 ON rpc.id_recepcion_producto = rp.id
                              WHERE (jsonb_typeof(en.costos) <> 'array'
                                     OR jsonb_array_length(en.costos) = 0)
                                AND rp.id_operacion = p_id_operacion
                                AND rp.id_presentacion = en.id_pp
                           ) x
                       ), 0) AS costo_base
              FROM entrada en
              JOIN app_dat_producto_presentacion pp ON pp.id = en.id_pp
              LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                     ON f.id_presentacion = pp.id
        )
        SELECT id_producto,
               SUM(cant_base)              AS cant_base,
               SUM(cant_base * costo_base) AS importe_base
          FROM con_factor
         WHERE cant_base > 0 AND costo_base IS NOT NULL
         GROUP BY id_producto
    LOOP
        SELECT c.id_presentacion INTO v_id_base
          FROM public.fn_presentaciones_producto(v_fila.id_producto) c
         WHERE c.es_base
         LIMIT 1;

        IF v_id_base IS NULL THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(pp.precio_promedio, 0) INTO v_costo_ant
          FROM app_dat_producto_presentacion pp
         WHERE pp.id = v_id_base
           FOR UPDATE;

        SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
          FROM public.fn_stock_saldos_presentacion(v_fila.id_producto, NULL, NULL, false) s;

        v_saldo_base := GREATEST(v_saldo_base - v_fila.cant_base, 0);

        IF v_costo_ant <= 0 OR v_saldo_base <= 0 THEN
            v_costo_nuevo := v_fila.importe_base / v_fila.cant_base;
        ELSE
            v_costo_nuevo := ((v_costo_ant * v_saldo_base) + v_fila.importe_base)
                             / (v_saldo_base + v_fila.cant_base);
        END IF;

        UPDATE app_dat_producto_presentacion
           SET precio_promedio = v_costo_nuevo
         WHERE id = v_id_base
           AND COALESCE(precio_promedio, -1) <> v_costo_nuevo::real;

        IF FOUND THEN
            v_actualizados := v_actualizados + 1;
        END IF;

        -- Propagación: costo_presentacion = costo_base * factor_rel
        UPDATE app_dat_producto_presentacion pp
           SET precio_promedio = v_costo_nuevo * f.factor_rel
          FROM public.fn_presentaciones_producto(v_fila.id_producto) f
         WHERE f.id_presentacion = pp.id
           AND pp.id_producto = v_fila.id_producto
           AND COALESCE(pp.precio_promedio, -1)
               <> (v_costo_nuevo * f.factor_rel)::real;
    END LOOP;

    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;

    RETURN QUERY SELECT TRUE,
        format('Se actualizaron %s costos promedio (ponderados en unidades base)', v_actualizados)::text,
        v_actualizados, v_tiempo;

EXCEPTION WHEN OTHERS THEN
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
    RETURN QUERY SELECT FALSE,
        format('Error en fn_actualizar_precio_promedio_recepcion_v2 [%s]: %s', SQLSTATE, SQLERRM)::text,
        0, v_tiempo;
END;
$$;

COMMENT ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(bigint, jsonb) IS
  'Pondera precio_promedio en u. base. Acepta costos[] opcional por línea '
  '(id_tipo_costo, monto_usd): suma al costo efectivo, audita, actualiza '
  'monto_promedio_usd del concepto y escribe costo_real efectivo.';

GRANT EXECUTE ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(bigint, jsonb)
  TO authenticated, service_role;
