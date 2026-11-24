-- =============================================================================
-- Go Live: activa una tienda cuando cumple los 4 esenciales para poder vender.
--
-- ESTADO: APLICADO EN NEWA (qhprswhhfasrikhawjoz). PENDIENTE DE APLICAR EN MAIN.
--
-- Uso:
--   SELECT public.fn_m01_activar_tienda(8);
--
-- Problema: hasta hoy, "la tienda esta lista" solo lo decidia el cliente
-- (store_registration_service y el asistente de alta validan en Dart). Eso deja
-- dos huecos: cualquiera puede saltarse la validacion llamando a un UPDATE, y
-- una tienda puede pasar a 'activa' sin lo minimo para vender, con lo que el
-- vendedor descubre el problema al abrir el TPV, ya en produccion. Ademas el
-- preflight le ensena al cliente un resumen que el servidor no confirma, asi
-- que cliente y servidor pueden discrepar sobre lo que hay.
--
-- Arreglo: una unica RPC que (1) comprueba permiso, (2) cuenta en servidor los
-- 4 esenciales y falla diciendo QUE falta si alguno es cero, (3) marca la tienda
-- 'activa' y (4) devuelve el mismo resumen que enseno el preflight, para que las
-- dos partes lean los mismos numeros.
--
-- DESVIACION DEL PLAN (leer antes de portar a main):
--   1. La columna es `estado_onboarding`, NO `estado`. `app_dat_tienda.estado`
--      existe desde el esquema original y guarda el codigo de la provincia
--      geografica ('16', '04', '02'); la escribe store_registration_service.
--      Escribir 'activa' en `estado` destruiria el dato geografico de todas las
--      tiendas y ademas violaria el uso que ya hace el resto del producto. Esta
--      funcion solo escribe `estado_onboarding` y `activada_en`.
--   2. El 4o esencial es "vendedor asignado a una caja", NO "metodo de pago".
--      `app_nom_medio_pago` es un catalogo GLOBAL de 4 filas compartidas por
--      todas las tiendas: como gate seria un pseudo-requisito siempre verdadero.
--      Lo que bloquea vender de verdad es que `fn_abrir_turno_tpv` exige
--      p_id_vendedor NOT NULL: sin fila en `app_dat_vendedor` no se puede ni
--      abrir turno ni cobrar. La clave del esencial sigue siendo `cobro`, para
--      no romper el contrato del checklist de la fase 3.
--
-- Notas de diseno:
--   * SECURITY DEFINER a proposito: la validacion no puede depender de la RLS
--     del cliente. El cliente podria tener politicas que le oculten parte de
--     sus propios datos, y entonces el conteo daria cero y el gate fallaria por
--     un motivo falso. Ademas el UPDATE de `app_dat_tienda` se hace sin pasar
--     por las politicas de escritura, que es lo que evita que cualquiera marque
--     su tienda 'activa' con un UPDATE directo.
--   * El permiso es exactamente el de `fn_m01_asignar_dueno_por_email`:
--     `auth.uid() IS NOT NULL AND NOT fn_user_is_dueno(...)`. No se usa
--     "auth.uid() IS NULL" como rechazo porque desde el SQL Editor (o con
--     service_role) auth.uid() es NULL y la comprobacion no debe aplicar; los
--     permisos de EXECUTE ya excluyen a `anon` y a `PUBLIC`.
--     `fn_user_is_dueno` ya devuelve true tambien para un superadmin activo, asi
--     que no hace falta una segunda comprobacion.
--   * El mensaje de error nombra cada esencial que falta y POR QUE bloquea, y
--     el ERRCODE es 22023 (invalid_parameter_value) para que el cliente pueda
--     distinguir "faltan datos" de "no tienes permiso" (42501) sin parsear
--     texto. Las claves que faltan viajan ademas en DETAIL, con un formato
--     estable (`esenciales_faltantes: cobro,producto`), para que el cliente
--     pueda marcarlas en el checklist sin depender del texto en espanol.
--   * Idempotente: reactivar una tienda ya activa es un no-op efectivo, porque
--     `activada_en = COALESCE(activada_en, now())` conserva la fecha original.
--     Eso importa: la fecha de activacion es una metrica (cuanto tarda una
--     tienda en arrancar) y reescribirla en cada clic la destruiria.
--   * Se bloquea la activacion de una tienda 'suspendida'. Una suspension es
--     una decision de soporte/compliance, no un estado del que el cliente pueda
--     salir por su cuenta: sin este guard, el Dueno de una tienda suspendida
--     podria "auto-levantar" la suspension con una llamada a esta RPC, que es
--     justo el privilegio que se le quiere quitar. Es una desviacion menor del
--     enunciado (que solo pedia el UPDATE) y esta declarada en el informe.
--   * `FOR UPDATE` sobre la fila de la tienda serializa dos Go Live
--     simultaneos: sin el, dos llamadas concurrentes podrian pasar las dos el
--     gate y competir por el UPDATE.
--   * El resumen devuelto es el que el cliente ensena en el preflight. Se
--     calcula con los mismos numeros que decidieron el gate (no se vuelve a
--     consultar despues del UPDATE) para que no haya dos verdades distintas en
--     la misma respuesta.
--   * Los conteos excluyen borrados logicos (`deleted_at`) en las tablas que lo
--     tienen: almacen, layout_almacen, producto, trabajador, cocina. Sin ese
--     filtro, una tienda podria "aprobar" con un almacen borrado.
--   * SQL sin acentos por convencion del repo (ver tienda_onboarding.sql).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_m01_activar_tienda(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_estado_previo text;
    v_activada_en timestamptz;

    v_almacenes integer;
    v_tpvs integer;
    v_productos integer;
    v_vendedores integer;
    v_zonas integer;
    v_trabajadores integer;
    v_cocinas integer;
    v_mesas integer;
    v_tipo_negocio text;
    v_modo_restaurante boolean;
    v_cocina_activa boolean;

    v_faltan text[] := ARRAY[]::text[];
    v_motivos text[] := ARRAY[]::text[];
    v_mensaje text;
BEGIN
    -- -------------------------------------------------------------------------
    -- 1. Permiso: Dueno de la tienda o superadmin activo.
    -- -------------------------------------------------------------------------
    IF p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Falta el id de la tienda'
            USING ERRCODE = '22023';
    END IF;

    IF auth.uid() IS NOT NULL AND NOT public.fn_user_is_dueno(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo un Dueno o un superadmin de la tienda puede activar la tienda'
            USING ERRCODE = '42501';
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. La tienda debe existir. El FOR UPDATE la bloquea hasta el final de la
    --    transaccion y serializa dos Go Live concurrentes.
    -- -------------------------------------------------------------------------
    SELECT t.estado_onboarding
    INTO v_estado_previo
    FROM public.app_dat_tienda t
    WHERE t.id = p_id_tienda
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la tienda %', p_id_tienda
            USING ERRCODE = '22023';
    END IF;

    -- Una suspension la levanta soporte, no el cliente. Ver nota de diseno.
    IF v_estado_previo = 'suspendida' THEN
        RAISE EXCEPTION 'La tienda esta suspendida: el Go Live no levanta una suspension, hay que hablar con soporte'
            USING ERRCODE = '42501';
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. Conteo real de los 4 esenciales y de lo que va en el resumen.
    --    Se hace todo en una sola lectura para que el gate y el resumen que se
    --    devuelve no puedan discrepar.
    -- -------------------------------------------------------------------------
    SELECT
        (SELECT count(*) FROM public.app_dat_almacen a
          WHERE a.id_tienda = p_id_tienda
            AND a.deleted_at IS NULL),
        (SELECT count(*) FROM public.app_dat_tpv tp
          WHERE tp.id_tienda = p_id_tienda),
        (SELECT count(*) FROM public.app_dat_producto pr
          WHERE pr.id_tienda = p_id_tienda
            AND pr.deleted_at IS NULL),
        (SELECT count(*) FROM public.app_dat_vendedor v
           JOIN public.app_dat_tpv tp ON tp.id = v.id_tpv
          WHERE tp.id_tienda = p_id_tienda),
        (SELECT count(*) FROM public.app_dat_layout_almacen l
           JOIN public.app_dat_almacen a ON a.id = l.id_almacen
          WHERE a.id_tienda = p_id_tienda
            AND a.deleted_at IS NULL
            AND l.deleted_at IS NULL),
        (SELECT count(*) FROM public.app_dat_trabajadores tr
          WHERE tr.id_tienda = p_id_tienda
            AND tr.deleted_at IS NULL),
        (SELECT count(*) FROM public.app_dat_cocina c
          WHERE c.id_tienda = p_id_tienda
            AND c.deleted_at IS NULL),
        (SELECT count(*) FROM public.app_dat_mesas m
          WHERE m.id_tienda = p_id_tienda),
        (SELECT t.tipo_negocio FROM public.app_dat_tienda t
          WHERE t.id = p_id_tienda),
        EXISTS (SELECT 1 FROM public.app_dat_configuracion_tienda ct
                 WHERE ct.id_tienda = p_id_tienda
                   AND ct.modo_restaurante IS TRUE),
        EXISTS (SELECT 1 FROM public.app_dat_configuracion_tienda ct
                 WHERE ct.id_tienda = p_id_tienda
                   AND ct.cocina_activa IS TRUE)
    INTO
        v_almacenes, v_tpvs, v_productos, v_vendedores,
        v_zonas, v_trabajadores, v_cocinas, v_mesas,
        v_tipo_negocio, v_modo_restaurante, v_cocina_activa;

    -- -------------------------------------------------------------------------
    -- 4. Gate: los 4 esenciales. Cada motivo dice que falta y por que importa,
    --    para que el mensaje sea accionable y no un "datos incompletos".
    -- -------------------------------------------------------------------------
    -- array_append en vez de `v_faltan || 'literal'`: con un literal sin tipo a
    -- la derecha, Postgres puede resolver el operador `||` como
    -- `text[] || text[]` e intentar parsear 'almacen' como literal de array,
    -- que falla con 22P02 ("malformed array literal"). Se probo en newa.
    IF v_almacenes = 0 THEN
        v_faltan := array_append(v_faltan, 'almacen'::text);
        v_motivos := array_append(v_motivos, 'falta un almacen: sin almacen no hay stock que vender'::text);
    END IF;

    IF v_tpvs = 0 THEN
        v_faltan := array_append(v_faltan, 'tpv'::text);
        v_motivos := array_append(v_motivos, 'falta un punto de venta: sin caja no hay donde cobrar'::text);
    END IF;

    IF v_productos = 0 THEN
        v_faltan := array_append(v_faltan, 'producto'::text);
        v_motivos := array_append(v_motivos, 'falta un producto: sin catalogo no hay nada que vender'::text);
    END IF;

    IF v_vendedores = 0 THEN
        v_faltan := array_append(v_faltan, 'cobro'::text);
        v_motivos := array_append(v_motivos, 'falta un vendedor asignado a la caja: sin vendedor no se puede abrir turno ni vender'::text);
    END IF;

    IF array_length(v_faltan, 1) IS NOT NULL THEN
        v_mensaje := 'No se puede activar la tienda: '
                     || array_to_string(v_motivos, '; ')
                     || '.';

        RAISE EXCEPTION '%', v_mensaje
            USING ERRCODE = '22023',
                  DETAIL = 'esenciales_faltantes: ' || array_to_string(v_faltan, ','),
                  HINT = 'Completa esas tareas desde la pantalla de activacion y vuelve a intentar el Go Live.';
    END IF;

    -- -------------------------------------------------------------------------
    -- 5. Activacion. `estado_onboarding`, nunca `estado`: ver la desviacion 1
    --    de la cabecera. El COALESCE mantiene la fecha original si la tienda ya
    --    estaba activa (idempotencia sin perder la metrica).
    -- -------------------------------------------------------------------------
    UPDATE public.app_dat_tienda
    SET estado_onboarding = 'activa',
        activada_en = COALESCE(activada_en, now())
    WHERE id = p_id_tienda
    RETURNING activada_en INTO v_activada_en;

    -- -------------------------------------------------------------------------
    -- 6. Respuesta: el mismo resumen que el cliente enseno en el preflight.
    -- -------------------------------------------------------------------------
    RETURN jsonb_build_object(
        'success', true,
        'id_tienda', p_id_tienda,
        'estado_onboarding', 'activa',
        'estado_anterior', v_estado_previo,
        'ya_estaba_activa', (v_estado_previo = 'activa'),
        'activada_en', v_activada_en,
        'mensaje', CASE
            WHEN v_estado_previo = 'activa'
                THEN 'La tienda ya estaba activa; se conserva la fecha de activacion original'
            ELSE 'Tienda activada: ya puede vender'
        END,
        'resumen', jsonb_build_object(
            'tipo_negocio', v_tipo_negocio,
            'modo_restaurante', v_modo_restaurante,
            'cocina_activa', v_cocina_activa,
            'almacenes', v_almacenes,
            'tpvs', v_tpvs,
            'productos', v_productos,
            'vendedores', v_vendedores,
            'zonas', v_zonas,
            'trabajadores', v_trabajadores,
            'cocinas', v_cocinas,
            'mesas', v_mesas
        ),
        'esenciales', jsonb_build_object(
            'almacen', (v_almacenes > 0),
            'tpv', (v_tpvs > 0),
            'producto', (v_productos > 0),
            'cobro', (v_vendedores > 0)
        )
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_m01_activar_tienda(bigint) IS
  'Go Live de una tienda: valida en servidor los 4 esenciales (almacen, tpv, '
  'producto y vendedor asignado a caja), la marca estado_onboarding=''activa'' '
  'y devuelve el resumen del preflight. 22023 si falta algo, 42501 si el '
  'llamante no es Dueno ni superadmin. OJO: escribe estado_onboarding, no '
  'estado (que es el codigo de provincia).';

REVOKE ALL ON FUNCTION public.fn_m01_activar_tienda(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_activar_tienda(bigint)
    TO authenticated, service_role;

-- =============================================================================
-- Verificacion (solo lectura)
-- =============================================================================

-- La funcion existe, es DEFINER y tiene search_path fijo.
-- Esperado: 1 fila con prosecdef = true y proconfig con search_path.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS devuelve,
       p.prosecdef AS security_definer,
       p.provolatile,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_m01_activar_tienda';

-- Permisos: `authenticated` y `service_role` con EXECUTE, `anon` y PUBLIC sin el.
-- Esperado: authenticated/service_role = true; anon = false.
SELECT r.rolname AS rol,
       has_function_privilege(r.oid, 'public.fn_m01_activar_tienda(bigint)', 'EXECUTE') AS puede_ejecutar
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY r.rolname;

-- Reparto actual de estado_onboarding y comprobacion de que la columna
-- geografica `estado` sigue con codigos de provincia.
SELECT estado_onboarding, count(*) AS tiendas
FROM public.app_dat_tienda
GROUP BY estado_onboarding
ORDER BY estado_onboarding;

SELECT id, denominacion, estado AS codigo_provincia, estado_onboarding, activada_en
FROM public.app_dat_tienda
ORDER BY id;
