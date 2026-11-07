-- ============================================================================
-- FASE 1 — Catálogo global de monedas + soporte para el superadmin
-- ============================================================================
-- Destino: rama de desarrollo `newa`. NO aplicar en producción hasta validar.
-- Idempotente: se puede ejecutar dos veces sin efectos secundarios.
--
-- ESTADO: ✅ APLICADA Y VERIFICADA en newa el 2026-11-04.
--
-- Qué hace:
--   1. Amplía `public.monedas` (metadatos: decimales, orden, base, sistema).
--   2. Añade el puente `tipos_moneda.codigo` -> `monedas.codigo`.
--   3. Crea `fn_tasa_cambio(...)`: resuelve la tasa de CUALQUIER par por código.
--   4. Crea las RPC de catálogo que usará la pantalla "Monedas" del superadmin.
--   5. Endurece la RLS de los catálogos que HOY NADIE escribe.
--
-- Qué NO hace (a propósito):
--   - No toca `app_dat_pago_venta` ni el CHECK de moneda        -> Fase 3
--   - No toca `app_dat_caja_turno`                              -> Fase 4
--   - No crea `app_dat_tienda_moneda`                           -> Fase 2
--   - No endurece `tasas_conversion` ni `tasa_cambio_extraoficial`: la app
--     admin las ESCRIBE hoy, así que se endurecen en la Fase 2 junto con el
--     cambio que quita esa escritura desde la app de tienda.
--
-- Comportamiento tras aplicar: NINGUNO visible. Ninguna moneda nueva queda
-- habilitada para ninguna tienda. El cobro actual es idéntico.
--
-- ----------------------------------------------------------------------------
-- RESULTADO DE LA VERIFICACIÓN EN newa (2026-11-04)
-- ----------------------------------------------------------------------------
--   ✅ Columnas creadas (monedas.decimales/orden/es_base/es_sistema,
--      tipos_moneda.codigo).
--   ✅ Puente correcto: id 1 -> CUP (es_base), id 2 -> USD (es_sistema).
--   ✅ Exactamente 1 moneda base.
--   ✅ `fn_tasa_cambio('CUP','CUP')` = 1.
--   ✅ `fn_tasa_cambio('USD','CUP', <tienda>)` = la tasa por tienda (850).
--   ✅ `fn_tasa_cambio('EUR','CUP')` = NULL cuando no hay tasa (bloquea el cobro
--      en EUR, que es el comportamiento querido: decisión B4).
--   ✅ RLS: 2 políticas por catálogo endurecido, sin permisivas.
--   ✅ Idempotencia: la migración completa re-ejecutada sin error
--      (1 moneda base, 6 políticas).
--   ✅ Alta real probada: `fn_crear_moneda('EUR',...)` + denominaciones (7),
--      escritura atómica en `monedas` Y `tipos_moneda` (id 3). Dato de prueba
--      eliminado después.
--   ✅ Guardia fail-closed: sin sesión de superadmin, la RPC lanza
--      'P0001: Solo un superadministrador puede crear monedas'.
--   ✅ Regresión: los 23 pagos de newa intactos, 0 en monedas distintas de CUP/USD.
--   ✅ Los 5 RPC ejercitados: crear, actualizar (nombre/decimales/orden),
--      guardar_denominaciones, guardar_tasa_global y fn_tasa_cambio.
--   ✅ Fallback GLOBAL de `fn_tasa_cambio` verificado (EUR->CUP = 1000 tras
--      registrar la tasa global). Antes no se podía probar porque en newa
--      `tasas_conversion` está vacía.
--   ✅ Pantalla `monedas_screen.dart` + servicio `monedas_service.dart` en la
--      app superadmin; `dart analyze lib` -> No errors.
--   ✅ Ruta concedida al rol 1 de newa (43 -> 44 rutas) para que RouteGuard no
--      la deniegue. Ver la sección 7: es un paso OBLIGATORIO también en producción.
--
-- ⚠️ BUG ENCONTRADO Y CORREGIDO EN ESTA VERSIÓN:
--      Los parámetros `p_decimales` y `p_orden` estaban declarados `smallint`.
--      Un literal entero NO resuelve contra `smallint` (la conversión int4->int2
--      es de ASIGNACIÓN, no implícita), así que la llamada fallaba con
--      `42883: function public.fn_crear_moneda(...) does not exist`.
--      Ahora son `integer` y se convierten dentro de la función.
--      Incluye `DROP FUNCTION IF EXISTS` de la firma vieja: cambiar el tipo de
--      un parámetro NO reemplaza la función, crea una sobrecarga.
--
-- ⚠️ DIVERGENCIA ENTRE RAMAS detectada: newa tiene 237 tablas (main 239) y
--      `tasas_conversion` está VACÍA (main tiene USD->CUP = 900). Por eso
--      `fn_tasa_cambio('USD','CUP')` sin tienda devuelve NULL en newa.
-- ============================================================================


-- ============================================================================
-- 1) public.monedas — metadatos del catálogo
-- ============================================================================
-- VERIFICADO en Fase 0: `codigo` ya es `character(3)` (bpchar(3)) y admite 'USD'.
-- El volcado VentiQ.sql del repo perdía el `(3)`. NO hace falta ALTER COLUMN.

ALTER TABLE public.monedas
  ADD COLUMN IF NOT EXISTS decimales  smallint NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS orden      smallint NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS es_base    boolean  NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS es_sistema boolean  NOT NULL DEFAULT false;

-- Solo puede haber una moneda base (índice parcial único).
CREATE UNIQUE INDEX IF NOT EXISTS ux_monedas_una_base
  ON public.monedas ((es_base)) WHERE es_base;

-- CUP es la moneda base contable y una moneda de sistema (no borrable).
UPDATE public.monedas SET es_base = true,  es_sistema = true, orden = 10 WHERE codigo = 'CUP';
UPDATE public.monedas SET es_base = false, es_sistema = true, orden = 20 WHERE codigo = 'USD';


-- ============================================================================
-- 2) public.tipos_moneda — puente de identidad con las tasas por tienda
-- ============================================================================
-- `tasa_cambio_extraoficial` referencia tipos_moneda(id) y NO se migra.
-- Se añade `codigo` (mismo tipo que monedas.codigo, para que la FK sea válida)
-- y así poder traducir id <-> código sin tocar el histórico de tasas.

ALTER TABLE public.tipos_moneda
  ADD COLUMN IF NOT EXISTS codigo character(3);

UPDATE public.tipos_moneda SET codigo = 'CUP' WHERE id = 1 AND codigo IS NULL;
UPDATE public.tipos_moneda SET codigo = 'USD' WHERE id = 2 AND codigo IS NULL;

-- FK solo si no existe ya (idempotencia)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tipos_moneda_codigo_fkey'
      AND conrelid = 'public.tipos_moneda'::regclass
  ) THEN
    ALTER TABLE public.tipos_moneda
      ADD CONSTRAINT tipos_moneda_codigo_fkey
      FOREIGN KEY (codigo) REFERENCES public.monedas(codigo);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_tipos_moneda_codigo
  ON public.tipos_moneda (codigo);


-- ============================================================================
-- 3) public.fn_tasa_cambio(...) — tasa de cualquier par, por CÓDIGO
-- ============================================================================
-- Resuelve: tasa por tienda (tasa_cambio_extraoficial, vía tipos_moneda.codigo)
--           con fallback a la tasa global (tasas_conversion).
-- Devuelve NULL si no hay tasa: el llamador decide (cobrar en CUP siempre se
-- puede; cobrar en otra moneda sin tasa se bloquea).

CREATE OR REPLACE FUNCTION public.fn_tasa_cambio(
  p_moneda_origen  text,
  p_moneda_destino text DEFAULT 'CUP',
  p_id_tienda      bigint DEFAULT NULL,
  p_fecha          timestamptz DEFAULT now()
) RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_origen  text := upper(trim(p_moneda_origen));
  v_destino text := upper(trim(coalesce(p_moneda_destino,'CUP')));
  v_id_origen  bigint;
  v_id_destino bigint;
  v_tasa    numeric;
BEGIN
  IF v_origen = v_destino THEN
    RETURN 1;
  END IF;

  SELECT id INTO v_id_origen  FROM public.tipos_moneda WHERE codigo = v_origen;
  SELECT id INTO v_id_destino FROM public.tipos_moneda WHERE codigo = v_destino;
  IF v_id_origen IS NULL OR v_id_destino IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1) Tasa por tienda, la más reciente vigente a la fecha
  IF p_id_tienda IS NOT NULL THEN
    SELECT valor_cambio INTO v_tasa
    FROM public.tasa_cambio_extraoficial
    WHERE id_tienda = p_id_tienda
      AND id_moneda_origen = v_id_origen
      AND id_moneda_destino = v_id_destino
      AND activo
      AND created_at <= p_fecha
    ORDER BY created_at DESC
    LIMIT 1;
    IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
      RETURN v_tasa;
    END IF;
  END IF;

  -- 2) Tasa global
  SELECT tasa INTO v_tasa
  FROM public.tasas_conversion
  WHERE moneda_origen = v_origen
    AND moneda_destino = v_destino
    AND fecha_actualizacion <= p_fecha
  ORDER BY fecha_actualizacion DESC
  LIMIT 1;

  RETURN NULLIF(v_tasa, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_tasa_cambio(text, text, bigint, timestamptz)
  TO authenticated;


-- ============================================================================
-- 4) RPC de catálogo (superadmin)
-- ============================================================================
-- Todas: SECURITY DEFINER + comprobación de superadmin.
-- `fn_crear_moneda` es atómica: escribe `monedas` Y `tipos_moneda`. Si una
-- existe y la otra no, la moneda no sirve para cobrar. Esa es la regla de oro.
--
-- NOTA IMPORTANTE sobre tipos: los parámetros numéricos son `integer`, NO
-- `smallint`. Un literal entero no resuelve contra smallint y la llamada falla
-- con 42883. Verificado en newa.

DROP FUNCTION IF EXISTS public.fn_crear_moneda(text, text, text, text, smallint, smallint);

CREATE OR REPLACE FUNCTION public.fn_crear_moneda(
  p_codigo    text,
  p_nombre    text,
  p_simbolo   text    DEFAULT NULL,
  p_pais      text    DEFAULT NULL,
  p_decimales integer DEFAULT 2,
  p_orden     integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_nombre text := coalesce(nullif(trim(p_nombre), ''), upper(trim(p_codigo)));
  v_nuevo_id bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede crear monedas';
  END IF;

  IF v_codigo !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'El código debe ser ISO-4217 de 3 letras (recibido: %)', p_codigo;
  END IF;

  IF EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_codigo) THEN
    RAISE EXCEPTION 'La moneda % ya existe en el catálogo', v_codigo;
  END IF;

  INSERT INTO public.monedas (codigo, nombre, simbolo, pais, activo,
                              decimales, orden, es_base, es_sistema)
  VALUES (v_codigo, v_nombre, nullif(trim(p_simbolo),''), nullif(trim(p_pais),''),
          true, coalesce(p_decimales, 2)::smallint, coalesce(p_orden, 100)::smallint,
          false, false);

  -- Puente para las tasas por tienda. `tipos_moneda.id` no tiene DEFAULT.
  SELECT coalesce(max(id), 0) + 1 INTO v_nuevo_id FROM public.tipos_moneda;

  INSERT INTO public.tipos_moneda (id, denominacion, simbolo, nombre_corto,
                                   pais, activo, codigo)
  VALUES (v_nuevo_id, v_nombre, coalesce(nullif(trim(p_simbolo),''), ''),
          v_codigo, nullif(trim(p_pais),''), true, v_codigo);

  RETURN jsonb_build_object(
    'status', 'success',
    'codigo', v_codigo,
    'id_tipos_moneda', v_nuevo_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_crear_moneda(text, text, text, text, integer, integer)
  TO authenticated;


DROP FUNCTION IF EXISTS public.fn_actualizar_moneda(text, text, text, text, smallint, smallint, boolean);

CREATE OR REPLACE FUNCTION public.fn_actualizar_moneda(
  p_codigo    text,
  p_nombre    text     DEFAULT NULL,
  p_simbolo   text     DEFAULT NULL,
  p_pais      text     DEFAULT NULL,
  p_decimales integer  DEFAULT NULL,
  p_orden     integer  DEFAULT NULL,
  p_activo    boolean  DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_es_base boolean;
  v_pagos   bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar monedas';
  END IF;

  SELECT es_base INTO v_es_base FROM public.monedas WHERE codigo = v_codigo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La moneda % no existe', v_codigo;
  END IF;

  -- No se puede desactivar la moneda base ni una con pagos registrados
  IF p_activo IS FALSE THEN
    IF v_es_base THEN
      RAISE EXCEPTION 'No se puede desactivar la moneda base (%)', v_codigo;
    END IF;
    SELECT count(*) INTO v_pagos
    FROM public.app_dat_pago_venta WHERE moneda = v_codigo;
    IF v_pagos > 0 THEN
      RAISE EXCEPTION 'No se puede desactivar %: tiene % pagos registrados',
        v_codigo, v_pagos;
    END IF;
  END IF;

  UPDATE public.monedas SET
    nombre         = coalesce(nullif(trim(p_nombre),''), nombre),
    simbolo        = coalesce(nullif(trim(p_simbolo),''), simbolo),
    pais           = coalesce(nullif(trim(p_pais),''), pais),
    decimales      = coalesce(p_decimales, decimales)::smallint,
    orden          = coalesce(p_orden, orden)::smallint,
    activo         = coalesce(p_activo, activo),
    actualizado_en = now()
  WHERE codigo = v_codigo;

  -- Mantener el puente alineado
  UPDATE public.tipos_moneda SET
    denominacion = coalesce(nullif(trim(p_nombre),''), denominacion),
    activo       = coalesce(p_activo, activo),
    updated_at   = now()
  WHERE codigo = v_codigo;

  RETURN jsonb_build_object('status','success','codigo',v_codigo);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_actualizar_moneda(text, text, text, text, integer, integer, boolean)
  TO authenticated;


-- Denominaciones (billetes/monedas) de una divisa. Reemplaza el juego completo.
-- `app_dat_denominaciones_moneda` es GLOBAL; en newa solo tiene CUP y USD.
CREATE OR REPLACE FUNCTION public.fn_guardar_denominaciones(
  p_codigo         text,
  p_denominaciones jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_item   jsonb;
  v_valor  numeric;
  v_activo boolean;
  v_n       int := 0;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar denominaciones';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_codigo) THEN
    RAISE EXCEPTION 'La moneda % no existe', v_codigo;
  END IF;

  IF p_denominaciones IS NULL OR jsonb_typeof(p_denominaciones) <> 'array' THEN
    RAISE EXCEPTION 'p_denominaciones debe ser un array JSON';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_denominaciones)
  LOOP
    v_valor  := (v_item->>'denominacion')::numeric;
    v_activo := coalesce((v_item->>'active')::boolean, true);

    IF v_valor IS NULL OR v_valor <= 0 THEN
      RAISE EXCEPTION 'Denominación inválida: %', v_item->>'denominacion';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.app_dat_denominaciones_moneda
      WHERE codigo_moneda = v_codigo AND denominacion = v_valor
    ) THEN
      UPDATE public.app_dat_denominaciones_moneda
      SET active = v_activo, updated_at = now()
      WHERE codigo_moneda = v_codigo AND denominacion = v_valor;
    ELSE
      INSERT INTO public.app_dat_denominaciones_moneda
        (codigo_moneda, denominacion, active)
      VALUES (v_codigo, v_valor, v_activo);
    END IF;
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('status','success','codigo',v_codigo,'denominaciones',v_n);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_guardar_denominaciones(text, jsonb)
  TO authenticated;


-- Tasa global (tasas_conversion). Versiona: inserta una fila nueva.
CREATE OR REPLACE FUNCTION public.fn_guardar_tasa_global(
  p_moneda_origen  text,
  p_moneda_destino text,
  p_tasa           numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_origen  text := upper(trim(p_moneda_origen));
  v_destino text := upper(trim(p_moneda_destino));
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar la tasa global';
  END IF;

  IF p_tasa IS NULL OR p_tasa <= 0 THEN
    RAISE EXCEPTION 'La tasa debe ser mayor que cero';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_origen) THEN
    RAISE EXCEPTION 'La moneda origen % no existe', v_origen;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_destino) THEN
    RAISE EXCEPTION 'La moneda destino % no existe', v_destino;
  END IF;

  INSERT INTO public.tasas_conversion (moneda_origen, moneda_destino, tasa, fecha_actualizacion)
  VALUES (v_origen, v_destino, p_tasa, now());

  RETURN jsonb_build_object('status','success','par', v_origen || '->' || v_destino);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_guardar_tasa_global(text, text, numeric)
  TO authenticated;


-- ============================================================================
-- 5) RLS — endurecer SOLO los catálogos que hoy nadie escribe
-- ============================================================================
-- Verificado en Fase 0: las 5 tablas tienen RLS activo con políticas
-- permisivas `*_authenticated_all` (ALL a authenticated, USING true).
-- Aquí se sustituyen las de los 3 catálogos que hoy son de SOLO LECTURA.
--
-- `tasas_conversion` y `tasa_cambio_extraoficial` NO se tocan en esta fase:
-- la app admin las escribe (currency_service / personal_rates_service).
-- Endurecerlas ahora rompería esa funcionalidad. Van en la Fase 2, junto con
-- el cambio que retira esa escritura desde la app de tienda.

-- 5.1 public.monedas
DROP POLICY IF EXISTS monedas_authenticated_all ON public.monedas;
DROP POLICY IF EXISTS monedas_lectura            ON public.monedas;
DROP POLICY IF EXISTS monedas_escritura_superadmin ON public.monedas;

CREATE POLICY monedas_lectura ON public.monedas
  FOR SELECT TO authenticated USING (true);
CREATE POLICY monedas_escritura_superadmin ON public.monedas
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

-- 5.2 public.tipos_moneda
DROP POLICY IF EXISTS tipos_moneda_authenticated_all ON public.tipos_moneda;
DROP POLICY IF EXISTS tipos_moneda_lectura           ON public.tipos_moneda;
DROP POLICY IF EXISTS tipos_moneda_escritura_superadmin ON public.tipos_moneda;

CREATE POLICY tipos_moneda_lectura ON public.tipos_moneda
  FOR SELECT TO authenticated USING (true);
CREATE POLICY tipos_moneda_escritura_superadmin ON public.tipos_moneda
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

-- 5.3 public.app_dat_denominaciones_moneda
DROP POLICY IF EXISTS app_dat_denominaciones_moneda_authenticated_all
  ON public.app_dat_denominaciones_moneda;
DROP POLICY IF EXISTS denominaciones_lectura
  ON public.app_dat_denominaciones_moneda;
DROP POLICY IF EXISTS denominaciones_escritura_superadmin
  ON public.app_dat_denominaciones_moneda;

CREATE POLICY denominaciones_lectura ON public.app_dat_denominaciones_moneda
  FOR SELECT TO authenticated USING (true);
CREATE POLICY denominaciones_escritura_superadmin ON public.app_dat_denominaciones_moneda
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());


-- ============================================================================
-- 6) VERIFICACIÓN — ejecutar después de aplicar
-- ============================================================================

-- 6.1 Columnas nuevas presentes
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (   (table_name = 'monedas'      AND column_name IN ('decimales','orden','es_base','es_sistema'))
       OR (table_name = 'tipos_moneda' AND column_name = 'codigo') )
ORDER BY table_name, column_name;

-- 6.2 Puente correcto: cada moneda de tipos_moneda apunta a su código
SELECT tm.id, tm.nombre_corto, tm.codigo, m.nombre AS moneda_nombre,
       m.es_base, m.es_sistema
FROM public.tipos_moneda tm
LEFT JOIN public.monedas m ON m.codigo = tm.codigo
ORDER BY tm.id;

-- 6.3 Exactamente una moneda base
SELECT count(*) AS monedas_base FROM public.monedas WHERE es_base;
-- Esperado: 1

-- 6.4 La tasa se resuelve por código
--     (en newa, `tasas_conversion` está VACÍA: el par global dará NULL y el de
--      tienda sí resolverá. En main el global es 900.)
SELECT public.fn_tasa_cambio('USD','CUP')      AS usd_a_cup_global,
       public.fn_tasa_cambio('CUP','USD')      AS cup_a_usd_global,
       public.fn_tasa_cambio('CUP','CUP')      AS identidad,
       public.fn_tasa_cambio('EUR','CUP')      AS eur_sin_tasa,
       public.fn_tasa_cambio('USD','CUP',
         (SELECT min(id_tienda) FROM public.tasa_cambio_extraoficial)) AS usd_a_cup_tienda;

-- 6.5 RLS: 2 políticas por catálogo endurecido, ninguna permisiva
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('monedas','tipos_moneda','app_dat_denominaciones_moneda')
ORDER BY tablename, policyname;

-- 6.6 Alta real de una moneda (requiere sesión de superadmin; desde SQL Editor
--     hay que simular el claim). Verificado en newa el 2026-11-04:
--       select set_config('request.jwt.claims',
--         '{"sub":"<uuid-superadmin>","role":"authenticated"}', true);
--       select public.fn_crear_moneda('EUR','Euro','€','Unión Europea',2,30);
--       select public.fn_guardar_denominaciones('EUR','[...]'::jsonb);
--     Sin sesión, DEBE fallar: 'Solo un superadministrador puede crear monedas'.
--     Limpieza:
--       DELETE FROM public.app_dat_denominaciones_moneda WHERE codigo_moneda = 'EUR';
--       DELETE FROM public.tipos_moneda WHERE codigo = 'EUR';
--       DELETE FROM public.monedas WHERE codigo = 'EUR';

-- 6.7 REGRESIÓN: el pago y la caja no deben haber cambiado
SELECT count(*) AS pagos_total,
       count(*) FILTER (WHERE moneda = 'USD') AS pagos_usd,
       count(*) FILTER (WHERE moneda = 'CUP') AS pagos_cup,
       count(*) FILTER (WHERE moneda NOT IN ('CUP','USD')) AS pagos_otras
FROM public.app_dat_pago_venta;

-- ============================================================================
-- 7) PASO OBLIGATORIO TRAS DESPLEGAR LA APP: conceder la ruta '/monedas'
-- ============================================================================
-- `AppRoutes.protected` incluye ya `/monedas` y la pantalla existe, pero el
-- guard de la app DENIEGA la ruta si el rol del superadmin no la tiene en su
-- lista `permisos`:
--
--   AuthService.canAccessRoute(route):
--     if (admin.rol == null && admin.nivelAcceso == 1) return true;  // legacy
--     return admin.permisosRutas.contains(route);                    // con rol
--
-- Verificado en newa: el rol `full` tenía 43 rutas y NO incluía '/monedas', y
-- el superadmin de newa tiene `id_rol = 1`. Sin concederla, la pantalla nueva
-- responde "Acceso denegado" aunque todo el SQL esté bien.
--
-- Dos formas de concederlo:
--
--   (a) RECOMENDADA — desde la propia app: Roles y Permisos → marcar "Monedas".
--       Es el flujo previsto y deja traza de quién lo cambió.
--
--   (b) Por SQL, para entornos de prueba (es lo aplicado en newa):
--
-- UPDATE public.app_dat_superadmin_roles
-- SET permisos = permisos || '["/monedas"]'::jsonb, updated_at = now()
-- WHERE jsonb_typeof(permisos) = 'array'
--   AND NOT (permisos @> '["/monedas"]'::jsonb);
--
-- AVISO: la sentencia de (b) concede la ruta a TODOS los roles. En producción
-- conviene acotarla al rol que corresponda (p. ej. `AND id = <id_rol>` o
-- `AND permisos @> '["/configuracion"]'::jsonb`).
--
-- Estado en newa: aplicado. El rol 1 pasó de 43 a 44 rutas.

-- ============================================================================
-- Fin Fase 1. Si la verificación es correcta, aplicar en producción.
-- La pantalla "Monedas" del superadmin consume estas RPC.
-- ============================================================================
