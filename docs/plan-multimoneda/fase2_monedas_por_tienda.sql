-- ============================================================================
-- PRODUCCIÓN — FASE 2: monedas por tienda + endurecimiento de tasas
-- ============================================================================
-- Depende de: fase1_catalogo_monedas.sql y fase1b_tasa_automatica.sql
--             (ambos ya aplicados en producción el 2026-11-04).
--
-- ⚠️ NO APLICADO EN PRODUCCIÓN. En newa está aplicado y verificado.
--    Verificación de RLS incluida al final (apartado 6): se probó con el rol
--    `authenticated` real, no solo como postgres.
--
-- Qué hace
-- --------
--   1. Crea `app_dat_tienda_moneda`: qué monedas acepta cada tienda.
--   2. La siembra con CUP y USD en todas las tiendas (comportamiento actual).
--   3. RPC `fn_guardar_monedas_tienda` (valida que el usuario administre la
--      tienda).
--   4. Endurece tres RLS que hoy son `authenticated USING(true)`:
--        tasa_cambio_extraoficial -> escritura por tienda
--        tasas_conversion         -> escritura solo superadmin
--        (app_dat_tienda_moneda)  -> lectura abierta, escritura por tienda
--
-- Comportamiento tras aplicar: NINGUNO visible. Toda tienda acepta CUP y USD,
-- que es lo que hace hoy. El cobro no cambia.
--
-- ⚠️ ORDEN DEL DESPLIEGUE
-- ----------------------
-- La app admin ya no debe escribir `tasas_conversion`. Con la RLS endurecida,
-- una versión antigua de la app que lo intente NO falla: el UPDATE afecta a 0
-- filas (RLS filtra) y el código cree que fue bien. Es silencioso, no rompe
-- nada, pero conviene desplegar la app nueva junto con este SQL para que el
-- comportamiento quede claro.
--
-- La app de tienda (ventiq_app) solo LEE tasas: no se ve afectada.
--
-- Verificado antes de escribir
-- ----------------------------
--   * `fn_user_can_access_tienda(id)` = dueño | gerente | supervisor | auditor.
--     NO incluye vendedores. Correcto: vendedores solo leen, el admin escribe.
--   * `postgres` tiene rolbypassrls = true.
--   * En newa: gerente de la tienda 3 puede escribir la tasa de su tienda y NO
--     la de la tienda 4; no puede escribir `tasas_conversion` ni crear monedas;
--     el superadmin sí puede escribir `tasas_conversion`.
-- ============================================================================


-- ============================================================================
-- 1) app_dat_tienda_moneda
-- ============================================================================
-- `moneda` es character(3) para que la FK encaje EXACTAMENTE con
-- `monedas.codigo`, que es character(3). Con varchar(3) la FK no sería válida.
CREATE TABLE IF NOT EXISTS public.app_dat_tienda_moneda (
  id_tienda  bigint       NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  moneda     character(3) NOT NULL REFERENCES public.monedas(codigo),
  activo     boolean      NOT NULL DEFAULT true,
  orden      smallint     NOT NULL DEFAULT 100,
  created_at timestamptz  NOT NULL DEFAULT now(),
  updated_at timestamptz  NOT NULL DEFAULT now(),
  PRIMARY KEY (id_tienda, moneda)
);

-- Semilla: toda tienda existente acepta CUP y USD (lo que ya hace hoy).
INSERT INTO public.app_dat_tienda_moneda (id_tienda, moneda, activo, orden)
SELECT t.id, m.codigo, true,
       CASE m.codigo WHEN 'CUP' THEN 10 WHEN 'USD' THEN 20 ELSE 100 END
FROM public.app_dat_tienda t
CROSS JOIN public.monedas m
WHERE m.codigo IN ('CUP', 'USD')
ON CONFLICT DO NOTHING;


-- ============================================================================
-- 2) RPC de escritura
-- ============================================================================
-- Semántica "reemplazar conjunto": lo que venga se activa/actualiza; lo que no
-- venga se DESACTIVA (no se borra: es configuración, no histórico).
CREATE OR REPLACE FUNCTION public.fn_guardar_monedas_tienda(
  p_id_tienda bigint,
  p_monedas   jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item    jsonb;
  v_codigo  text;
  v_activo  boolean;
  v_orden   integer;
  v_n       int := 0;
  v_codigos text[] := '{}';
BEGIN
  IF NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
    RAISE EXCEPTION 'No tienes acceso a la tienda %', p_id_tienda;
  END IF;

  IF p_monedas IS NULL OR jsonb_typeof(p_monedas) <> 'array' THEN
    RAISE EXCEPTION 'p_monedas debe ser un array JSON';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_monedas)
  LOOP
    v_codigo := upper(trim(v_item->>'moneda'));
    v_activo := coalesce((v_item->>'activo')::boolean, true);
    v_orden  := coalesce((v_item->>'orden')::integer, 100);

    IF NOT EXISTS (
      SELECT 1 FROM public.monedas WHERE codigo = v_codigo AND activo
    ) THEN
      RAISE EXCEPTION 'La moneda % no existe o está inactiva en el catálogo', v_codigo;
    END IF;

    INSERT INTO public.app_dat_tienda_moneda
      (id_tienda, moneda, activo, orden, updated_at)
    VALUES
      (p_id_tienda, v_codigo, v_activo, v_orden::smallint, now())
    ON CONFLICT (id_tienda, moneda) DO UPDATE
      SET activo     = excluded.activo,
          orden      = excluded.orden,
          updated_at = now();

    v_codigos := v_codigos || v_codigo;
    v_n := v_n + 1;
  END LOOP;

  -- La tienda siempre debe aceptar CUP: es la moneda base contable.
  IF NOT ('CUP' = ANY (v_codigos)) THEN
    RAISE EXCEPTION 'La tienda debe aceptar CUP (moneda base)';
  END IF;

  UPDATE public.app_dat_tienda_moneda
  SET activo = false, updated_at = now()
  WHERE id_tienda = p_id_tienda
    AND NOT (moneda = ANY (v_codigos))
    AND activo;

  RETURN jsonb_build_object(
    'status', 'success',
    'id_tienda', p_id_tienda,
    'monedas', v_n
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_guardar_monedas_tienda(bigint, jsonb)
  TO authenticated;


-- ============================================================================
-- 3) RLS de la tabla nueva
-- ============================================================================
ALTER TABLE public.app_dat_tienda_moneda ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tienda_moneda_lectura          ON public.app_dat_tienda_moneda;
DROP POLICY IF EXISTS tienda_moneda_escritura_tienda ON public.app_dat_tienda_moneda;

-- Lectura abierta: el TPV (vendedores, NO cubiertos por fn_user_can_access_tienda)
-- necesita saber qué monedas acepta su tienda.
CREATE POLICY tienda_moneda_lectura ON public.app_dat_tienda_moneda
  FOR SELECT TO authenticated USING (true);

CREATE POLICY tienda_moneda_escritura_tienda ON public.app_dat_tienda_moneda
  FOR ALL TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));


-- ============================================================================
-- 4) Endurecer tasa_cambio_extraoficial (escritura por tienda)
-- ============================================================================
-- Antes: ALL a authenticated con USING(true) -> cualquiera cambiaba la tasa de
-- CUALQUIER tienda.
DROP POLICY IF EXISTS tasa_cambio_extraoficial_authenticated_all
  ON public.tasa_cambio_extraoficial;
DROP POLICY IF EXISTS tasa_cambio_extraoficial_lectura
  ON public.tasa_cambio_extraoficial;
DROP POLICY IF EXISTS tasa_cambio_extraoficial_escritura_tienda
  ON public.tasa_cambio_extraoficial;

CREATE POLICY tasa_cambio_extraoficial_lectura ON public.tasa_cambio_extraoficial
  FOR SELECT TO authenticated USING (true);

CREATE POLICY tasa_cambio_extraoficial_escritura_tienda ON public.tasa_cambio_extraoficial
  FOR ALL TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));


-- ============================================================================
-- 5) Endurecer tasas_conversion (escritura solo superadmin)
-- ============================================================================
-- Antes: ALL a authenticated con USING(true) -> una app de tienda cambiaba la
-- tasa global de TODAS las tiendas.
DROP POLICY IF EXISTS tasas_conversion_authenticated_all ON public.tasas_conversion;
DROP POLICY IF EXISTS tasas_conversion_lectura           ON public.tasas_conversion;
DROP POLICY IF EXISTS tasas_conversion_escritura_superadmin ON public.tasas_conversion;

CREATE POLICY tasas_conversion_lectura ON public.tasas_conversion
  FOR SELECT TO authenticated USING (true);

CREATE POLICY tasas_conversion_escritura_superadmin ON public.tasas_conversion
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());


-- ============================================================================
-- 6) VERIFICACIÓN
-- ============================================================================

-- 6.1 Semilla: cada tienda debe tener CUP y USD
SELECT tm.id_tienda,
       string_agg(tm.moneda || CASE WHEN tm.activo THEN '' ELSE '(off)' END,
                  ', ' ORDER BY tm.orden) AS monedas
FROM public.app_dat_tienda_moneda tm
GROUP BY tm.id_tienda
ORDER BY tm.id_tienda;

-- 6.2 Políticas resultantes (deben ser 6: lectura + escritura por tabla)
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('app_dat_tienda_moneda','tasa_cambio_extraoficial','tasas_conversion')
ORDER BY tablename, policyname;

-- 6.3 ¿Quedan políticas permisivas? NO debe devolver filas.
SELECT tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('monedas','tipos_moneda','app_dat_denominaciones_moneda',
                    'tasa_cambio_extraoficial','tasas_conversion')
  AND policyname LIKE '%authenticated_all%';

-- 6.4 LA PRUEBA QUE IMPORTA: RLS real, cambiando de rol.
--     El MCP/Editor conecta como `postgres`, que tiene BYPASSRLS: sin cambiar de
--     rol, cualquier prueba de RLS da falso positivo. Sustituye los UUID por un
--     gerente de una tienda y un superadmin reales de producción.
--
--     Resultado esperado:
--       1. gerente escribe tasas_conversion        -> DENEGADO
--       2. gerente escribe tasa de OTRA tienda     -> DENEGADO
--       3. gerente escribe tasa de SU tienda       -> PERMITIDO
--       4. gerente crea moneda en el catálogo      -> DENEGADO
--       5. superadmin escribe tasas_conversion     -> PERMITIDO
--
-- create temp table _rls_check (caso text, resultado text);
-- do $$
-- declare v_msg text;
-- begin
--   perform set_config('request.jwt.claims',
--     '{"sub":"<UUID_GERENTE>","role":"authenticated"}', true);
--   execute 'set local role authenticated';
--   begin
--     insert into public.tasas_conversion (moneda_origen, moneda_destino, tasa)
--     values ('USD','CUP', 12345);
--     v_msg := 'PERMITIDO';
--   exception when others then v_msg := 'DENEGADO -> ' || sqlerrm; end;
--   execute 'reset role';
--   insert into _rls_check values ('1. gerente escribe tasas_conversion', v_msg);
--
--   -- ... repetir para los casos 2-5 ...
-- end $$;
-- select caso, resultado from _rls_check order by caso;

-- 6.5 Regresión: los pagos y las tasas de tienda no se tocan
SELECT (SELECT count(*) FROM public.app_dat_pago_venta)          AS pagos,
       (SELECT count(*) FROM public.tasa_cambio_extraoficial)    AS tasas_tienda,
       (SELECT count(*) FROM public.tasas_conversion)             AS tasas_globales,
       (SELECT count(*) FROM public.app_dat_tienda_moneda)        AS tienda_moneda;


-- ============================================================================
-- 7) Reversión
-- ============================================================================
-- Volver a las políticas permisivas (NO recomendado):
--   drop policy if exists monedas_escritura_superadmin on public.monedas;
--   ... etc.
-- Deshacer solo la Fase 2:
--   drop table if exists public.app_dat_tienda_moneda;
--   drop function if exists public.fn_guardar_monedas_tienda(bigint, jsonb);
--   drop policy if exists tasa_cambio_extraoficial_lectura on public.tasa_cambio_extraoficial;
--   drop policy if exists tasa_cambio_extraoficial_escritura_tienda on public.tasa_cambio_extraoficial;
--   create policy tasa_cambio_extraoficial_authenticated_all
--     on public.tasa_cambio_extraoficial for all to authenticated
--     using (true) with check (true);
--   -- y lo mismo con tasas_conversion
--
-- Deshacer la Fase 2 NO afecta a los cobros ni a la tasa automática.
-- ============================================================================