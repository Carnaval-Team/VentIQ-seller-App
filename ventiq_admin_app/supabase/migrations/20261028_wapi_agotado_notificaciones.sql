-- ============================================================================
--  WAPI — Aviso a grupos guardados cuando un producto llega a stock 0
--  Fecha: 2026-10-28
--
--  QUÉ HACE
--    Cuando el stock TOTAL de un producto de una tienda con aviso activo
--    pasa de ">0" (o desconocido) a "<=0", se encolan una fila por
--    destinatario en app_wapi_agotado_log y se dispara la edge function
--    `wapi-notify-agotado`, que manda UN mensaje de texto por grupo/número
--    con la plantilla configurable.
--
--  DISEÑO (contrato FROZEN con la UI de Flutter — no cambiar nombres):
--    app_wapi_agotado_config        (1 fila por tienda; activo=false por defecto)
--    app_wapi_agotado_destinatario  (N:N config ↔ app_wapi_destinatario)
--    app_wapi_agotado_estado        (estado previo para detectar la transición)
--    app_wapi_agotado_log           (una fila por destinatario y aviso)
--
--  ACTIVACIÓN: la hace el usuario/gerente desde la app. Por defecto NADIE
--    recibe avisos (activo=false). Ver docs/WAPI_AGOTADO.md.
--
--  POR QUÉ UN TRIGGER NUEVO Y NO REUTILIZAR fn_notificar_producto_agotado()
--    Ya existía en producción `trg_notificar_producto_agotado`
--    (AFTER UPDATE OF cantidad_final WHEN new.cantidad_final = 0 AND
--    new.cantidad_inicial > 0) → `fn_notificar_producto_agotado()`, que manda
--    notificaciones IN-APP (fn_crear_notificacion) a vendedores/supervisores/
--    gerentes/almaceneros. Es OTRO canal (campana de la app, no WhatsApp) y
--    Otra semántica: dispara por UBICACIÓN y sólo en UPDATE.
--    Este canal necesita: (a) producto TOTAL = 0 (suma de la última fila por
--    (id_producto,id_ubicacion) sobre las ubicaciones de los almacenes de los
--    TPVs de la tienda — misma semántica que loadProductInfo de
--    wapi-send-products), (b) INSERT **y** UPDATE, (c) WhatsApp, no campana.
--    Ampliar la existente cambiaría el comportamiento de una feature viva y
--    arriesgaría las ventas en curso, así que se añade un trigger PROPIO e
--    independiente. La existente NO se toca.
--
--  SEGURIDAD DE LA TRANSACCIÓN (la BD está en producción con ventas reales):
--    · El trigger lleva cláusula WHEN baratísima: sólo despierta cuando el
--      movimiento deja SU ubicación en <=0 (condición necesaria para que el
--      total pueda ser 0). El resto de inserts de inventario no pagan nada.
--    · La función del trigger sale de inmediato si la tienda no tiene config
--      activa (índice UNIQUE por id_tienda).
--    · Todo el cuerpo va dentro de EXCEPTION WHEN OTHERS → RAISE WARNING: un
--      fallo del aviso NUNCA aborta el INSERT de la venta (mismo patrón que
--      fn_notificar_producto_disponible()).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- ---------------------------------------------------------------------------
-- 1. app_wapi_agotado_config — configuración por tienda
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_agotado_config (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda         bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  id_sesion         bigint REFERENCES public.app_wapi_sesion(id) ON DELETE SET NULL,
  -- La columna se deja NULL-able a propósito (el contrato con la UI dice
  -- "default false"): la UI puede mandar `null` sin romper nada y el trigger
  -- trata NULL como "no activo".
  activo            boolean NOT NULL DEFAULT false,
  plantilla         text NOT NULL DEFAULT
'⚠️ *PRODUCTO AGOTADO*

🔴 *{producto}*
🏷️ {categoria}
💰 {precio}
📦 Existencias: {stock}

Pronto volverá a estar disponible. — {tienda}',
  delay_min_seconds int NOT NULL DEFAULT 5  CHECK (delay_min_seconds >= 0),
  delay_max_seconds int NOT NULL DEFAULT 10 CHECK (delay_max_seconds >= delay_min_seconds),
  cooldown_minutos  int NOT NULL DEFAULT 30 CHECK (cooldown_minutos >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_wapi_agotado_config_tienda_key UNIQUE (id_tienda)
);

COMMENT ON TABLE public.app_wapi_agotado_config IS
  'Config del aviso de "producto agotado" a grupos de WhatsApp, por tienda. activo=false por defecto: el usuario lo enciende desde la app.';
COMMENT ON COLUMN public.app_wapi_agotado_config.plantilla IS
  'Plantilla del mensaje. Placeholders: {producto} {precio} {stock} {categoria} {tienda}.';
COMMENT ON COLUMN public.app_wapi_agotado_config.id_sesion IS
  'Sesión WAPI con la que se manda. NULL = la primera sesión CONNECTED de la tienda.';
COMMENT ON COLUMN public.app_wapi_agotado_config.cooldown_minutos IS
  'Ventana mínima entre dos avisos del mismo producto (evita ráfagas si el stock oscila).';

-- ---------------------------------------------------------------------------
-- 2. app_wapi_agotado_destinatario — qué grupos/números reciben el aviso
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_agotado_destinatario (
  id_config       bigint NOT NULL REFERENCES public.app_wapi_agotado_config(id)   ON DELETE CASCADE,
  id_destinatario bigint NOT NULL REFERENCES public.app_wapi_destinatario(id)     ON DELETE CASCADE,
  PRIMARY KEY (id_config, id_destinatario)
);

CREATE INDEX IF NOT EXISTS idx_wapi_agotado_dest_destinatario
  ON public.app_wapi_agotado_destinatario(id_destinatario);

-- Índice para la FK (el lint `unindexed_foreign_keys` de get_advisors lo pide,
-- y además es el acceso natural: "¿qué sesión usa cada config?").
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_config_sesion
  ON public.app_wapi_agotado_config(id_sesion)
  WHERE id_sesion IS NOT NULL;

COMMENT ON TABLE public.app_wapi_agotado_destinatario IS
  'Destinatarios (grupos/números de app_wapi_destinatario) suscritos al aviso de agotado.';

-- ---------------------------------------------------------------------------
-- 3. app_wapi_agotado_estado — estado previo para detectar la TRANSICIÓN
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_agotado_estado (
  id_tienda   bigint  NOT NULL REFERENCES public.app_dat_tienda(id)   ON DELETE CASCADE,
  id_producto bigint  NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
  stock_total numeric,
  agotado     boolean NOT NULL DEFAULT false,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id_tienda, id_producto)
);

CREATE INDEX IF NOT EXISTS idx_wapi_agotado_estado_agotado
  ON public.app_wapi_agotado_estado(id_tienda, updated_at DESC)
  WHERE agotado = true;

-- Cobertura de la FK id_producto (lint unindexed_foreign_keys) y consulta
-- natural "¿está agotado este producto?" desde la app.
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_estado_producto
  ON public.app_wapi_agotado_estado(id_producto);

COMMENT ON TABLE public.app_wapi_agotado_estado IS
  'Último stock_total conocido por producto/tienda. Sólo el trigger (service role) escribe aquí.';

-- ---------------------------------------------------------------------------
-- 4. app_wapi_agotado_log — bitácora: una fila por destinatario y aviso
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_wapi_agotado_log (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda       bigint NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  -- SET NULL (no CASCADE): si se borra el producto, el historial de envíos
  -- debe sobrevivir para auditoría.
  id_producto     bigint REFERENCES public.app_dat_producto(id)          ON DELETE SET NULL,
  id_destinatario bigint REFERENCES public.app_wapi_destinatario(id)     ON DELETE SET NULL,
  chat_id         text   NOT NULL,
  estado          text   NOT NULL DEFAULT 'pendiente'
                  CHECK (estado IN ('pendiente','enviado','fallido','omitido')),
  error_code      text,
  error_message   text,
  mensaje_id      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  sent_at         timestamptz
);

-- Historial por tienda (lo que pinta la UI).
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_log_tienda_fecha
  ON public.app_wapi_agotado_log(id_tienda, created_at DESC);
-- Cola de trabajo de la edge function.
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_log_pendientes
  ON public.app_wapi_agotado_log(estado, created_at)
  WHERE estado IN ('pendiente','fallido');
-- Chequeo de cooldown del trigger: último aviso de (tienda, producto).
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_log_tienda_producto
  ON public.app_wapi_agotado_log(id_tienda, id_producto, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_log_destinatario
  ON public.app_wapi_agotado_log(id_destinatario);
-- Cobertura de la FK id_producto (lint unindexed_foreign_keys) y consulta
-- "historial de avisos de este producto" (la UI la usa tal cual).
CREATE INDEX IF NOT EXISTS idx_wapi_agotado_log_producto
  ON public.app_wapi_agotado_log(id_producto, created_at DESC);

COMMENT ON TABLE public.app_wapi_agotado_log IS
  'Bitácora del aviso de agotado: una fila por destinatario. La escribe el trigger (pendiente) y la cierra la edge function wapi-notify-agotado.';

-- ---------------------------------------------------------------------------
-- 5. RLS
--    · El gerente/supervisor de la tienda gestiona su configuración.
--    · El resto (estado y log) es del service_role (el trigger y la edge
--      function). A los usuarios de la tienda se les deja LECTURA del log y
--      del estado para que la UI pueda mostrar historial.
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_wapi_agotado_config       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_agotado_destinatario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_agotado_estado       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_wapi_agotado_log          ENABLE ROW LEVEL SECURITY;

-- Helper existente (20260525_wapi_notifications.sql). NO se modifica.
-- public.fn_user_can_access_tienda(bigint) → gerente o supervisor de la tienda.

DROP POLICY IF EXISTS wapi_agotado_config_access ON public.app_wapi_agotado_config;
CREATE POLICY wapi_agotado_config_access ON public.app_wapi_agotado_config
  FOR ALL TO authenticated
  USING      (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

DROP POLICY IF EXISTS wapi_agotado_dest_access ON public.app_wapi_agotado_destinatario;
CREATE POLICY wapi_agotado_dest_access ON public.app_wapi_agotado_destinatario
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.app_wapi_agotado_config c
    WHERE c.id = app_wapi_agotado_destinatario.id_config
      AND public.fn_user_can_access_tienda(c.id_tienda)
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.app_wapi_agotado_config c
    WHERE c.id = app_wapi_agotado_destinatario.id_config
      AND public.fn_user_can_access_tienda(c.id_tienda)
  ));

-- Estado y log: sólo lectura para los usuarios de la tienda. Las escrituras
-- llegan por service_role (trigger + edge function), que no pasa por RLS.
DROP POLICY IF EXISTS wapi_agotado_estado_select ON public.app_wapi_agotado_estado;
CREATE POLICY wapi_agotado_estado_select ON public.app_wapi_agotado_estado
  FOR SELECT TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda));

DROP POLICY IF EXISTS wapi_agotado_log_select ON public.app_wapi_agotado_log;
CREATE POLICY wapi_agotado_log_select ON public.app_wapi_agotado_log
  FOR SELECT TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda));

-- Grants explícitos (no depender de ALTER DEFAULT PRIVILEGES).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_config       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_destinatario TO authenticated;
GRANT SELECT                         ON public.app_wapi_agotado_estado       TO authenticated;
GRANT SELECT                         ON public.app_wapi_agotado_log          TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_config       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_destinatario TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_estado       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_wapi_agotado_log          TO service_role;

GRANT USAGE ON SEQUENCE public.app_wapi_agotado_config_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE public.app_wapi_agotado_log_id_seq    TO service_role;

-- ---------------------------------------------------------------------------
-- 6. updated_at de la config (reutiliza el helper ya existente)
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_wapi_agotado_config_updated_at ON public.app_wapi_agotado_config;
CREATE TRIGGER trg_wapi_agotado_config_updated_at
  BEFORE UPDATE ON public.app_wapi_agotado_config
  FOR EACH ROW EXECUTE FUNCTION public.fn_wapi_set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. Stock TOTAL del producto con la semántica de loadProductInfo
--      (= la que usa wapi-send-products para pintar 🟢/🟡/🔴)
--
--      1. TPVs de la tienda del producto      (app_dat_tpv.id_almacen)
--      2. ubicaciones de esos almacenes       (app_dat_layout_almacen, no borradas)
--      3. ÚLTIMA fila por (id_producto,id_ubicacion) del histórico de
--         movimientos (gana el id más alto)
--      4. SUMA de cantidad_final
--
--    `p_hasta_id` acota el cálculo al histórico ANTERIOR a un movimiento
--    (`id < p_hasta_id`). Es lo que permite saber el stock que había JUSTO
--    ANTES del movimiento que estamos evaluando, que es la única forma exacta
--    de detectar la transición >0 → 0 (ver punto 8).
--
--    Devuelve NULL si la tienda no tiene almacenes/ubicaciones: "no se pudo
--    calcular" ≠ "agotado" (mismo criterio que stockOk=false en la edge
--    function). Nunca anuncia un agotado que no puede demostrar.
--
--    CASO "UBICACIONES SÍ, FILAS NO": devuelve 0, NO NULL. Es exactamente lo
--    que hace loadProductInfo: `stockOk = true` en cuanto hay ubicaciones
--    (wapi-send-products/index.ts:717-753) y el producto sin filas cae luego en
--    `stockMap.get(id) ?? 0` (línea 827) ⇒ el catálogo ya lo pinta "🔴 Agotado".
--    Devolver NULL ahí haría que la app y el aviso discreparan.
--
--    CONSECUENCIA (consciente y documentada): la rama "desconocido → <=0" del
--    diseño queda INALCANZABLE en la práctica. Sin ubicaciones el stock es NULL
--    y se sale sin avisar; con ubicaciones el stock siempre es numérico (0 como
--    mínimo), nunca NULL. Y un producto que ya estaba a 0 en el histórico no
--    produce transición (avisar sería decir que "se agotó" algo que ya estaba
--    agotado antes de que existiera la feature). Se prefiere eso a mandar
--    avisos masivos al inicializar inventarios en 0.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_agotado_stock_total(
  p_id_producto bigint,
  p_hasta_id    bigint DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  WITH ubicaciones AS (
    SELECT DISTINCT la.id
      FROM public.app_dat_producto p
      JOIN public.app_dat_tpv t
        ON t.id_tienda = p.id_tienda
      JOIN public.app_dat_layout_almacen la
        ON la.id_almacen = t.id_almacen
     WHERE p.id = p_id_producto
       AND la.deleted_at IS NULL
  ),
  ultima_por_ubicacion AS (
    SELECT DISTINCT ON (i.id_ubicacion) i.cantidad_final
      FROM public.app_dat_inventario_productos i
      JOIN ubicaciones u ON u.id = i.id_ubicacion
     WHERE i.id_producto = p_id_producto
       AND i.id_ubicacion IS NOT NULL
       AND (p_hasta_id IS NULL OR i.id < p_hasta_id)
     ORDER BY i.id_ubicacion, i.id DESC
  )
  SELECT CASE
           WHEN (SELECT count(*) FROM ubicaciones) = 0 THEN NULL
           ELSE COALESCE((SELECT sum(cantidad_final) FROM ultima_por_ubicacion), 0)
         END;
$$;

COMMENT ON FUNCTION public.fn_wapi_agotado_stock_total(bigint, bigint) IS
  'Stock total de un producto sumando la última cantidad_final por ubicación de los almacenes de los TPVs de su tienda. Con p_hasta_id, el stock ANTES de ese movimiento. NULL = no calculable (sin ubicaciones). Misma semántica que loadProductInfo() de wapi-send-products.';

-- Sólo el service_role (edge function) la invoca por RPC.
--
-- OJO: `REVOKE ... FROM PUBLIC` NO ES SUFICIENTE en Supabase. El proyecto tiene
-- ALTER DEFAULT PRIVILEGES que concede EXECUTE a anon/authenticated al CREAR
-- cada función, y ese grant es explícito a esos roles (no viene heredado de
-- PUBLIC). Sin el revoke explícito, get_advisors lo reporta y `/rest/v1/rpc/
-- fn_wapi_agotado_stock_total` quedaría invocable por cualquiera. Verificado
-- con get_advisors antes/después.
REVOKE ALL ON FUNCTION public.fn_wapi_agotado_stock_total(bigint, bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_wapi_agotado_stock_total(bigint, bigint) TO service_role;

-- ---------------------------------------------------------------------------
-- 8. Detección: función del trigger
--
--    SECURITY DEFINER es IMPRESCINDIBLE aquí, y por eso se justifica:
--      app_dat_inventario_productos tiene RLS habilitado y la app inserta
--      movimientos DIRECTAMENTE con el rol `authenticated`/`anon` (política
--      "inventario productos" ALL para public). Este trigger necesita leer
--      app_wapi_agotado_config (RLS restrictiva: sólo gerente/supervisor) y
--      escribir app_wapi_agotado_log/estado (sin política de escritura). Sin
--      SECURITY DEFINER, un INSERT hecho por un vendedor no vería la config y
--      el aviso nunca saldría.
--    Con search_path fijado y EXECUTE revocado de PUBLIC.
--
--    Es una función de TRIGGER (returns trigger): no es invocable por RPC.
--
--    DECISIÓN DE DISEÑO (desviación consciente del borrador del contrato):
--      La transición se calcula comparando el stock actual con el stock del
--      histórico ANTERIOR al movimiento, NO con el flag `agotado` de
--      app_wapi_agotado_estado. Motivo, reproducido en la prueba del
--      2026-10-28: el WHEN del trigger sólo despierta cuando el movimiento
--      deja su ubicación en <=0; una reposición no lo despierta, así que el
--      flag se queda en `agotado=true` y una caída posterior a 0 se
--      suprimiría en silencio (el producto quedaría agotado sin avisar).
--      El estado se sigue escribiendo (la UI y el contrato lo esperan) pero
--      es auditoría, no la fuente de la decisión.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_agotado_check()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, net, vault
AS $$
DECLARE
  v_id_tienda  bigint;
  v_id_config  bigint;
  v_activo     boolean;
  v_cooldown   int;
  v_stock      numeric;
  v_stock_prev numeric;
  v_ref_id     bigint;
  v_es_ultima  boolean;
  v_dest       record;
  v_log_id     bigint;
  v_log_ids    bigint[] := ARRAY[]::bigint[];
  v_ultimo     timestamptz;
  v_url        text;
  v_token      text;
BEGIN
  -- Sin ubicación no podemos hablar de stock total: los movimientos con
  -- id_ubicacion NULL no entran en el cálculo de loadProductInfo.
  IF NEW.id_ubicacion IS NULL THEN
    RETURN NULL;
  END IF;

  -- (a) La tienda del producto. Fuera de tienda no hay aviso.
  SELECT p.id_tienda INTO v_id_tienda
    FROM public.app_dat_producto p
   WHERE p.id = NEW.id_producto;

  IF v_id_tienda IS NULL THEN
    RETURN NULL;
  END IF;

  -- (a-bis) Salida rápida: sin config ACTIVA no se toca nada más.
  -- (id_tienda es UNIQUE → un solo índice lookup.)
  SELECT c.id, COALESCE(c.activo, false), COALESCE(c.cooldown_minutos, 30)
    INTO v_id_config, v_activo, v_cooldown
    FROM public.app_wapi_agotado_config c
   WHERE c.id_tienda = v_id_tienda;

  IF v_id_config IS NULL OR v_activo IS NOT TRUE THEN
    RETURN NULL;
  END IF;

  -- (b) Stock TOTAL real del producto AHORA.
  v_stock := public.fn_wapi_agotado_stock_total(NEW.id_producto);
  IF v_stock IS NULL THEN
    -- No se pudo calcular (tienda sin almacenes/ubicaciones). No se inventa un
    -- "agotado" ni se ensucia el estado: mejor no avisar que avisar mal.
    RAISE NOTICE 'fn_wapi_agotado_check: stock no calculable para producto %', NEW.id_producto;
    RETURN NULL;
  END IF;

  -- (c) ¿De dónde venía el stock? Se deriva del PROPIO HISTÓRICO
  --     (`id < movimiento`), no del estado cacheado.
  --
  --     POR QUÉ NO SE USA app_wapi_agotado_estado PARA DECIDIR:
  --     el trigger lleva un WHEN que sólo lo despierta cuando el movimiento
  --     deja SU ubicación en <=0 (si no, cada INSERT del histórico de 412k
  --     filas pagaría el coste). Consecuencia: una REPOSICIÓN (cantidad_final
  --     > 0) no despierta el trigger y el estado se queda en agotado=true.
  --     Si la transición se decidiera con ese flag, "producto repuesto y
  --     vuelto a agotar" no avisaría NUNCA (falso negativo silencioso).
  --     Calculando el stock previo desde el histórico, la decisión es exacta
  --     y no depende de que el caché esté fresco. El estado se sigue
  --     escribiendo (contrato con la UI / auditoría), pero NO decide.
  v_ref_id := CASE WHEN TG_OP = 'UPDATE' THEN OLD.id ELSE NEW.id END;

  IF TG_OP = 'UPDATE' THEN
    -- Si esta fila NO es la última de su ubicación, cambiar su cantidad_final
    -- no altera el total: no hay transición posible.
    SELECT NOT EXISTS (
      SELECT 1 FROM public.app_dat_inventario_productos x
       WHERE x.id_producto = NEW.id_producto
         AND x.id_ubicacion = NEW.id_ubicacion
         AND x.id > OLD.id
    ) INTO v_es_ultima;

    IF v_es_ultima THEN
      -- Total actual con el valor viejo restaurado (la fila ES la última).
      v_stock_prev := v_stock
                      - COALESCE(NEW.cantidad_final, 0)
                      + COALESCE(OLD.cantidad_final, 0);
    ELSE
      v_stock_prev := v_stock;
    END IF;
  ELSE
    -- Stock que había ANTES de esta fila (histórico con id < NEW.id).
    v_stock_prev := public.fn_wapi_agotado_stock_total(NEW.id_producto, v_ref_id);
  END IF;

  -- (e) Guardar el estado nuevo (auditoría/UI; no decide el aviso).
  INSERT INTO public.app_wapi_agotado_estado
    (id_tienda, id_producto, stock_total, agotado, updated_at)
  VALUES
    (v_id_tienda, NEW.id_producto, v_stock, (v_stock <= 0), now())
  ON CONFLICT (id_tienda, id_producto) DO UPDATE
    SET stock_total = EXCLUDED.stock_total,
        agotado     = EXCLUDED.agotado,
        updated_at  = EXCLUDED.updated_at;

  -- ¿Transición a agotado? (>0 → <=0; la rama "desconocido → <=0" del diseño es
  -- inalcanzable por construcción — ver la nota del punto 7).
  --
  -- Esta comprobación es TAMBIÉN la deduplicación real, no el cooldown: si dos
  -- movimientos de la MISMA transacción dejan el total en 0 (venta
  -- multiproducto, bulk, etc.), la 2ª fila calcula su `v_stock_prev` sobre el
  -- histórico que YA incluye la 1ª (id menor) y ve 0 ⇒ no vuelve a encolar. El
  -- cooldown es una capa extra anti-ráfaga para oscilaciones repuesto→agotado;
  -- con `cooldown_minutos = 0` simplemente no hay esa ventana, pero un mismo
  -- agotado sigue generando UN solo aviso.
  IF v_stock > 0 THEN
    RETURN NULL;
  END IF;
  IF v_stock_prev IS NOT NULL AND v_stock_prev <= 0 THEN
    RETURN NULL;  -- ya estaba agotado: no repetir el aviso
  END IF;

  -- Cooldown por (tienda, producto): si hubo un aviso reciente, no repetir.
  SELECT max(l.created_at) INTO v_ultimo
    FROM public.app_wapi_agotado_log l
   WHERE l.id_tienda = v_id_tienda
     AND l.id_producto = NEW.id_producto;

  IF v_ultimo IS NOT NULL
     AND v_ultimo > now() - make_interval(mins => GREATEST(v_cooldown, 0)) THEN
    RAISE NOTICE 'fn_wapi_agotado_check: cooldown activo para producto % (último aviso %)',
      NEW.id_producto, v_ultimo;
    RETURN NULL;
  END IF;

  -- (d) Encolar UNA fila por destinatario configurado.
  FOR v_dest IN
    SELECT d.id AS id_destinatario, btrim(d.chat_id) AS chat_id
      FROM public.app_wapi_agotado_destinatario ad
      JOIN public.app_wapi_destinatario d ON d.id = ad.id_destinatario
     WHERE ad.id_config = v_id_config
       AND d.chat_id IS NOT NULL
       AND btrim(d.chat_id) ~ '@(c|g)\.us$'
  LOOP
    INSERT INTO public.app_wapi_agotado_log
      (id_tienda, id_producto, id_destinatario, chat_id, estado)
    VALUES
      (v_id_tienda, NEW.id_producto, v_dest.id_destinatario, v_dest.chat_id, 'pendiente')
    RETURNING id INTO v_log_id;

    v_log_ids := v_log_ids || v_log_id;
  END LOOP;

  IF array_length(v_log_ids, 1) IS NULL THEN
    RAISE NOTICE 'fn_wapi_agotado_check: producto % agotado sin destinatarios configurados',
      NEW.id_producto;
    RETURN NULL;
  END IF;

  -- Disparo de la edge function. Mismo patrón que fn_wapi_dispatch_diario:
  -- secretos en Vault + headers Authorization y apikey.
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'wapi_supabase_url';
  SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets WHERE name = 'wapi_service_role_key';

  IF v_url IS NULL OR v_token IS NULL THEN
    UPDATE public.app_wapi_agotado_log
       SET estado = 'omitido',
           error_code = 'NO_VAULT',
           error_message = 'Faltan secretos wapi_supabase_url / wapi_service_role_key en Vault'
     WHERE id = ANY(v_log_ids);
    RAISE WARNING 'fn_wapi_agotado_check: faltan secretos en Vault; aviso no enviado (producto %)',
      NEW.id_producto;
    RETURN NULL;
  END IF;

  v_url := rtrim(v_url, '/') || '/functions/v1/wapi-notify-agotado';

  -- pg_net encola en net.http_request_queue (INSERT en la misma transacción):
  -- el worker sólo ve la petición cuando la transacción del INSERT de venta
  -- haga COMMIT, así que la edge function siempre encontrará sus log_ids.
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_token,
                 'apikey',        v_token,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object('log_ids', to_jsonb(v_log_ids)),
    timeout_milliseconds := 5000
  );

  RAISE NOTICE 'fn_wapi_agotado_check: producto % agotado → % aviso(s) encolado(s)',
    NEW.id_producto, array_length(v_log_ids, 1);

  RETURN NULL;

EXCEPTION WHEN OTHERS THEN
  -- NUNCA abortar la transacción del INSERT de la venta. Mismo patrón que
  -- public.fn_notificar_producto_disponible().
  RAISE WARNING 'fn_wapi_agotado_check: % (producto=%, ubicación=%)',
    SQLERRM, NEW.id_producto, NEW.id_ubicacion;
  RETURN NULL;
END $$;

COMMENT ON FUNCTION public.fn_wapi_agotado_check() IS
  'Trigger AFTER INSERT/UPDATE de app_dat_inventario_productos: detecta producto TOTAL<=0 y encola el aviso WhatsApp. Cualquier error se traga con RAISE WARNING para no abortar la venta.';

-- Es una función de TRIGGER: nadie la invoca por RPC (Postgres rechaza llamar
-- directamente a una función que devuelve trigger), pero se revoca EXECUTE
-- igualmente — también de anon/authenticated, por el ALTER DEFAULT PRIVILEGES
-- de Supabase (ver nota en fn_wapi_agotado_stock_total).
REVOKE ALL ON FUNCTION public.fn_wapi_agotado_check()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. El trigger
--    WHEN = filtro barato: sólo despierta si el movimiento deja SU ubicación
--    en <=0 (condición necesaria para que el total del producto sea 0) y no es
--    una conversión de presentación (esas nacen en 0 sin que el producto se
--    agote — mismo criterio que fn_notificar_producto_disponible y
--    fn_sincronizar_stock_producto).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_wapi_agotado_notificar ON public.app_dat_inventario_productos;
CREATE TRIGGER trg_wapi_agotado_notificar
  AFTER INSERT OR UPDATE OF cantidad_final ON public.app_dat_inventario_productos
  FOR EACH ROW
  WHEN (
    NEW.id_ubicacion IS NOT NULL
    AND NEW.id_conversion IS NULL
    AND NEW.id_conversion_evento IS NULL
    AND COALESCE(NEW.cantidad_final, 0) <= 0
  )
  EXECUTE FUNCTION public.fn_wapi_agotado_check();

-- Recarga la caché de PostgREST: sin esto, el RPC
-- fn_wapi_agotado_stock_total y las tablas nuevas pueden tardar en verse desde
-- la API (y la edge function lo llama por RPC).
NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- FIN — WAPI aviso de agotado
--
-- Verificación manual (copiar/pegar; NO se ejecuta automáticamente):
--
--   -- 1) ¿Existe mi config y está activa?
--   SELECT id, id_tienda, activo, cooldown_minutos, delay_min_seconds, delay_max_seconds
--     FROM public.app_wapi_agotado_config ORDER BY id DESC;
--
--   -- 2) Últimos avisos
--   SELECT id, id_tienda, id_producto, chat_id, estado, error_code, created_at, sent_at
--     FROM public.app_wapi_agotado_log ORDER BY id DESC LIMIT 20;
--
--   -- 3) Stock total que calcula el trigger
--   SELECT public.fn_wapi_agotado_stock_total(<id_producto>);
--
--   -- 4) ¿Salió la llamada HTTP del trigger?
--   SELECT id, status_code, LEFT(content::text, 300), created
--     FROM net._http_response ORDER BY created DESC LIMIT 10;
-- ============================================================================
