-- ============================================================================
-- 22 · Fase 5 · Offline y cierre de turno con comandas
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE RESUELVE
-- ------------
-- Del plan (Fase 5):
--   - Cola offline de comandas (idempotencia).
--   - Impresora / ticket por cocina.
--   - Cierre de turno: listar o bloquear comandas abiertas de las cocinas
--     ligadas al almacen/TPV.
--
-- ESTADO VERIFICADO ANTES DE ESCRIBIR (via MCP)
-- ---------------------------------------------
-- El proyecto YA TIENE infraestructura de idempotencia offline y se reutiliza
-- tal cual, sin inventar nada nuevo:
--
--   app_dat_operacion_offline_idempotencia
--       client_uuid uuid NOT NULL   <- clave (hay ON CONFLICT (client_uuid))
--       id_operacion bigint NOT NULL
--       tipo text NOT NULL
--       uuid_usuario uuid
--       created_at timestamptz NOT NULL
--
--   tipos en uso hoy: cierre_turno (52), apertura_turno (50), pago (46),
--   estado:2 (40), venta (10), admin_recepcion (5).
--
-- El patron canonico esta en fn_cerrar_turno_offline: (1) buscar client_uuid,
-- (2) si existe devolver {status: success, idempotent: true}, (3) si no,
-- ejecutar la funcion online y registrar el client_uuid. Se copia ese patron.
--
-- app_dat_cocina ya tiene la columna `impresora text` (del 07), sin usar.
--
-- DECISIONES DE DISENO
-- --------------------
--
-- 1. LOS WRAPPERS OFFLINE NO DUPLICAN LOGICA.
--    fn_pedir_item_cuenta_offline valida el client_uuid y delega en
--    fn_pedir_item_cuenta. Si manana cambia la logica de pedir, el camino
--    offline la hereda. Duplicarla garantizaria que un dia divergen.
--
-- 2. IDEMPOTENCIA REAL, NO "REINTENTAR Y REZAR".
--    La tablet de un restaurante pierde el wifi a media comanda. Al volver, la
--    cola reenvia. Sin client_uuid el plato se pediria dos veces: doble
--    descuento de materia prima y dos comandas para la cocina. Con client_uuid
--    el segundo intento devuelve el MISMO id_item y no toca nada.
--
--    El client_uuid lo genera el DISPOSITIVO al crear la operacion, no el
--    servidor: es lo unico que sobrevive a un reintento.
--
-- 3. EL CIERRE DE TURNO AVISA, NO BLOQUEA (por defecto).
--    Un turno con comandas sin servir es un problema real: comida cocinada que
--    nadie cobro, o platos que el comensal espera. Pero bloquear el cierre deja
--    al vendedor atrapado si la cocina se fue sin marcar los tickets.
--    fn_comandas_abiertas_turno devuelve el detalle y un flag `bloquear` que la
--    tienda puede endurecer despues; la RPC no decide la politica.
--
-- 4. EL TICKET SE ARMA EN SQL, NO EN LA APP.
--    Dos apps (vendedor y admin) y posibles impresoras distintas tendrian que
--    formatear igual. Se devuelve el contenido estructurado + un texto plano ya
--    montado para impresoras de 40 columnas, que es el formato de las termicas
--    de tickets.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Este archivo (idempotente).
--   2. Correr la VERIFICACION del final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 22.1 fn_pedir_item_cuenta_offline
--
-- Envoltorio idempotente de fn_pedir_item_cuenta para la cola offline.
--
-- Devuelve exactamente lo mismo que la RPC online, mas `idempotent`:
--   false -> se ejecuto ahora
--   true  -> ya se habia ejecutado; se devuelve el id_item original
--
-- El tipo de idempotencia es 'pedir_item'. id_operacion guarda el id de la
-- linea de cuenta creada, que es lo que la app necesita recuperar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta_offline(
    p_client_uuid        uuid,
    p_id_cuenta          bigint,
    p_id_producto        bigint,
    p_cantidad           numeric,
    p_precio_unitario    numeric,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_id_presentacion    bigint  DEFAULT NULL,
    p_id_ubicacion       bigint  DEFAULT NULL,
    p_precio_base        numeric DEFAULT NULL,
    p_id_metodo_pago     bigint  DEFAULT NULL,
    p_promotion_data     jsonb   DEFAULT NULL,
    p_inventory_data     jsonb   DEFAULT NULL,
    p_notas              text    DEFAULT NULL,
    p_sku_producto       text    DEFAULT NULL,
    p_sku_ubicacion      text    DEFAULT NULL,
    p_uuid_vendedor      uuid    DEFAULT NULL,
    p_forzar_sin_stock   boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_existing bigint;
    v_res      jsonb;
    v_id_item  bigint;
BEGIN
    IF p_client_uuid IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Falta el client_uuid: sin el no se puede garantizar que '
                       || 'el pedido no se duplique al reintentar',
            'error_code', 'CLIENT_UUID_REQUERIDO'
        );
    END IF;

    -- ¿Ya se proceso este pedido? La cola pudo reenviarlo tras recuperar la red.
    SELECT id_operacion INTO v_existing
      FROM app_dat_operacion_offline_idempotencia
     WHERE client_uuid = p_client_uuid
       AND tipo = 'pedir_item';

    IF v_existing IS NOT NULL THEN
        -- Se reconstruye la respuesta desde la linea ya creada, para que la app
        -- reciba la misma forma que la primera vez.
        RETURN (
            SELECT jsonb_build_object(
                     'status',          'success',
                     'idempotent',      true,
                     'id_item',         i.id,
                     'id_cuenta',       i.id_cuenta,
                     'origen_stock',    i.origen_stock,
                     'id_cocina',       i.id_cocina,
                     'cocina',          ck.denominacion,
                     'stock_movido',    i.stock_movido,
                     'id_comanda_item', i.id_comanda_item,
                     'id_comanda',      ci.id_comanda,
                     'numero_comanda',  co.numero,
                     'estado_servicio', i.estado_servicio,
                     'message',         'Este pedido ya se habia registrado'
                   )
              FROM app_dat_mesa_cuenta_item i
              LEFT JOIN app_dat_cocina ck ON ck.id = i.id_cocina
              LEFT JOIN app_dat_comanda_item ci ON ci.id = i.id_comanda_item
              LEFT JOIN app_dat_comanda co ON co.id = ci.id_comanda
             WHERE i.id = v_existing
        );
    END IF;

    -- Delegar en la RPC online: la logica de clasificar, descontar y disparar
    -- comanda vive en un solo sitio.
    v_res := fn_pedir_item_cuenta(
        p_id_cuenta          := p_id_cuenta,
        p_id_producto        := p_id_producto,
        p_cantidad           := p_cantidad,
        p_precio_unitario    := p_precio_unitario,
        p_id_variante        := p_id_variante,
        p_id_opcion_variante := p_id_opcion_variante,
        p_id_presentacion    := p_id_presentacion,
        p_id_ubicacion       := p_id_ubicacion,
        p_precio_base        := p_precio_base,
        p_id_metodo_pago     := p_id_metodo_pago,
        p_promotion_data     := p_promotion_data,
        p_inventory_data     := p_inventory_data,
        p_notas              := p_notas,
        p_sku_producto       := p_sku_producto,
        p_sku_ubicacion      := p_sku_ubicacion,
        p_uuid_vendedor      := p_uuid_vendedor,
        p_forzar_sin_stock   := p_forzar_sin_stock
    );

    -- Solo se marca como procesado si de verdad se creo la linea. Si fallo por
    -- falta de stock, el reintento debe volver a intentarlo.
    IF (v_res->>'status') = 'success' THEN
        v_id_item := (v_res->>'id_item')::bigint;

        INSERT INTO app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_id_item, 'pedir_item',
                COALESCE(p_uuid_vendedor, auth.uid()))
        ON CONFLICT (client_uuid) DO NOTHING;

        v_res := v_res || jsonb_build_object('idempotent', false);
    END IF;

    RETURN v_res;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_pedir_item_cuenta_offline(
    uuid, bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint,
    numeric, bigint, jsonb, jsonb, text, text, text, uuid, boolean)
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 22.2 fn_cambiar_estado_comanda_item_offline
--
-- La tablet de la COCINA tambien se queda sin red. El cocinero marca "listo" y
-- el toque se encola. Al volver la red se reenvia.
--
-- Aqui la idempotencia importa menos por duplicacion (marcar dos veces el mismo
-- estado ya era idempotente en el 20) y mas por ORDEN: si se encolan "empezar"
-- y luego "listo" y llegan al reves, la matriz de transiciones rechazaria el
-- segundo. Registrar el client_uuid permite a la app saber que ya se aplico y no
-- reintentar en bucle.
--
-- El tipo de idempotencia es 'estado_comanda_item'. Se guarda el id del item de
-- comanda como id_operacion.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item_offline(
    p_client_uuid  uuid,
    p_id_item      bigint,
    p_nuevo_estado smallint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_existing bigint;
    v_res      jsonb;
BEGIN
    IF p_client_uuid IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Falta el client_uuid',
            'error_code', 'CLIENT_UUID_REQUERIDO'
        );
    END IF;

    SELECT id_operacion INTO v_existing
      FROM app_dat_operacion_offline_idempotencia
     WHERE client_uuid = p_client_uuid
       AND tipo = 'estado_comanda_item';

    IF v_existing IS NOT NULL THEN
        RETURN (
            SELECT jsonb_build_object(
                     'status',     'success',
                     'idempotent', true,
                     'id_item',    ci.id,
                     'plato',      ci.denominacion,
                     'estado',     ci.estado,
                     'id_comanda', ci.id_comanda,
                     'message',    'Este cambio ya se habia aplicado'
                   )
              FROM app_dat_comanda_item ci
             WHERE ci.id = v_existing
        );
    END IF;

    v_res := fn_cambiar_estado_comanda_item(p_id_item, p_nuevo_estado);

    IF (v_res->>'status') = 'success' THEN
        INSERT INTO app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_item, 'estado_comanda_item', auth.uid())
        ON CONFLICT (client_uuid) DO NOTHING;

        v_res := v_res || jsonb_build_object('idempotent', false);
    END IF;

    RETURN v_res;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cambiar_estado_comanda_item_offline(uuid, bigint, smallint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 22.3 fn_comandas_abiertas_turno
--
-- "¿Puedo cerrar el turno?"
--
-- Devuelve las comandas SIN SERVIR de las cocinas ligadas al TPV que se esta
-- cerrando. Es el punto del plan: "listar o bloquear comandas abiertas de las
-- cocinas ligadas al almacen/TPV".
--
-- POR QUE AVISA Y NO BLOQUEA
-- --------------------------
-- Un turno con comandas sin servir es un problema real: comida cocinada que
-- nadie cobro, o platos que el comensal sigue esperando. Pero bloquear el cierre
-- deja al vendedor atrapado si la cocina se fue a su casa sin marcar los
-- tickets, y entonces nadie puede cuadrar la caja.
--
-- Se devuelve el detalle y un flag `bloquear` calculado con un criterio
-- conservador: solo se sugiere bloquear si hay comandas con cuenta ABIERTA
-- (estado 1), o sea, mesas sin cobrar. Una comanda sin servir cuya cuenta ya se
-- cerro es un descuadre que hay que revisar, pero no impide cuadrar la caja.
--
-- La RPC NO decide la politica: devuelve el dato y la app elige.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_comandas_abiertas_turno(
    p_id_tpv bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_result    jsonb;
    v_total     integer;
    v_sin_pagar integer;
BEGIN
    SELECT t.id_tienda INTO v_id_tienda
      FROM app_dat_tpv t WHERE t.id = p_id_tpv;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El TPV no existe',
            'error_code', 'TPV_NOT_FOUND'
        );
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    SELECT COALESCE(jsonb_agg(q.c ORDER BY q.creado), '[]'::jsonb),
           count(*),
           count(*) FILTER (WHERE q.cuenta_abierta)
      INTO v_result, v_total, v_sin_pagar
      FROM (
        SELECT co.created_at AS creado,
               (cta.estado = 1) AS cuenta_abierta,
               jsonb_build_object(
                 'id_comanda',     co.id,
                 'numero',         co.numero,
                 'estado',         co.estado,
                 'estado_texto',   CASE co.estado
                                     WHEN 1 THEN 'Pendiente'
                                     WHEN 2 THEN 'En preparacion'
                                     WHEN 3 THEN 'Lista sin entregar'
                                   END,
                 'id_cocina',      co.id_cocina,
                 'cocina',         ck.denominacion,
                 'id_cuenta',      co.id_cuenta,
                 'cuenta_abierta', (cta.estado = 1),
                 'id_mesa',        co.id_mesa,
                 'mesa',           m.numero,
                 'zona',           m.zona,
                 'created_at',     co.created_at,
                 'espera_minutos',
                     GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - co.created_at)) / 60))::integer,
                 'items', COALESCE((
                     SELECT jsonb_agg(jsonb_build_object(
                              'denominacion', ci.denominacion,
                              'cantidad',     ci.cantidad,
                              'estado',       ci.estado
                            ) ORDER BY ci.id)
                       FROM app_dat_comanda_item ci
                      WHERE ci.id_comanda = co.id
                        AND ci.estado IN (1, 2, 3)
                 ), '[]'::jsonb)
               ) AS c
          FROM app_dat_comanda co
          JOIN app_dat_cocina ck ON ck.id = co.id_cocina
          -- Solo las cocinas que atienden a ESTE TPV: cerrar la caja de la barra
          -- no deberia alarmar por comandas de otra sala.
          JOIN app_dat_tpv_cocina tc ON tc.id_cocina = co.id_cocina
                                    AND tc.id_tpv = p_id_tpv
          LEFT JOIN app_dat_mesa_cuenta_abierta cta ON cta.id = co.id_cuenta
          LEFT JOIN app_dat_mesas m ON m.id = co.id_mesa
         WHERE co.estado IN (1, 2, 3)   -- pendiente / preparando / lista sin entregar
      ) q;

    RETURN jsonb_build_object(
        'status',          'success',
        'id_tpv',          p_id_tpv,
        'comandas',        v_result,
        'total',           COALESCE(v_total, 0),
        'con_cuenta_abierta', COALESCE(v_sin_pagar, 0),
        -- Sugerencia, no imposicion: solo si hay mesas sin cobrar.
        'bloquear',        COALESCE(v_sin_pagar, 0) > 0,
        'message', CASE
            WHEN COALESCE(v_total, 0) = 0
                THEN 'No hay comandas pendientes en las cocinas de este TPV'
            WHEN COALESCE(v_sin_pagar, 0) > 0
                THEN COALESCE(v_sin_pagar, 0) || ' comanda(s) sin servir en mesas sin cobrar'
            ELSE COALESCE(v_total, 0) || ' comanda(s) sin servir, pero las cuentas ya se cerraron'
        END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_comandas_abiertas_turno(bigint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 22.4 fn_ticket_comanda
--
-- Ticket de cocina, para impresora termica o para mostrar en pantalla.
--
-- POR QUE SE ARMA EN SQL Y NO EN LA APP
-- -------------------------------------
-- Dos apps (vendedor y admin) y varias impresoras tendrian que formatear igual.
-- Se devuelve el contenido estructurado Y un texto plano ya montado a 40
-- columnas, que es el ancho de las termicas de tickets mas comunes.
--
-- app_dat_cocina.impresora existe desde el 07 y hasta ahora no se usaba: aqui se
-- devuelve para que la app sepa a que impresora mandar el ticket.
--
-- El ticket de cocina NO lleva precios: al cocinero no le importan y ocupan
-- espacio que necesitan las notas del comensal.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ticket_comanda(
    p_id_comanda bigint,
    p_ancho      integer DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_co       RECORD;
    v_it       RECORD;
    v_texto    text := '';
    v_sep      text;
    v_ancho    integer := GREATEST(COALESCE(p_ancho, 40), 24);
    v_linea    text;
    v_items    jsonb := '[]'::jsonb;
    v_n        integer := 0;
BEGIN
    SELECT co.id, co.numero, co.estado, co.created_at, co.notas,
           co.id_cocina, ck.denominacion AS cocina, ck.impresora,
           co.id_mesa, m.numero AS mesa, m.zona,
           co.id_cuenta, co.id_tpv,
           TRIM(COALESCE(tr.nombres, '') || ' ' || COALESCE(tr.apellidos, '')) AS vendedor
      INTO v_co
      FROM app_dat_comanda co
      JOIN app_dat_cocina ck ON ck.id = co.id_cocina
      LEFT JOIN app_dat_mesas m ON m.id = co.id_mesa
      LEFT JOIN app_dat_mesa_cuenta_abierta cta ON cta.id = co.id_cuenta
      LEFT JOIN app_dat_vendedor v ON v.id = cta.id_vendedor
      LEFT JOIN app_dat_trabajadores tr ON tr.id = v.id_trabajador
     WHERE co.id = p_id_comanda;

    IF v_co.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La comanda no existe',
            'error_code', 'COMANDA_NOT_FOUND'
        );
    END IF;

    PERFORM fn_usuario_puede_operar_cocina(v_co.id_cocina);

    v_sep := repeat('-', v_ancho);

    -- Cabecera: numero grande y destino. Es lo que el cocinero canta.
    v_texto := v_texto || lpad('COMANDA #' || COALESCE(v_co.numero::text, v_co.id::text),
                               (v_ancho + length('COMANDA #' || COALESCE(v_co.numero::text, v_co.id::text))) / 2) || E'\n';
    v_texto := v_texto || upper(COALESCE(v_co.cocina, '')) || E'\n';
    v_texto := v_texto || v_sep || E'\n';

    IF v_co.mesa IS NOT NULL THEN
        v_texto := v_texto || 'Mesa: ' || v_co.mesa
                   || COALESCE('  (' || v_co.zona || ')', '') || E'\n';
    ELSIF v_co.id_cuenta IS NOT NULL THEN
        v_texto := v_texto || 'Cuenta: ' || v_co.id_cuenta || E'\n';
    ELSE
        v_texto := v_texto || 'Mostrador' || E'\n';
    END IF;

    IF COALESCE(v_co.vendedor, '') <> '' THEN
        v_texto := v_texto || 'Atiende: ' || v_co.vendedor || E'\n';
    END IF;

    v_texto := v_texto || 'Hora: ' || to_char(v_co.created_at, 'HH24:MI') || E'\n';
    v_texto := v_texto || v_sep || E'\n';

    FOR v_it IN
        SELECT ci.id, ci.denominacion, ci.cantidad, ci.notas,
               ci.modo_elaboracion, ci.estado
          FROM app_dat_comanda_item ci
         WHERE ci.id_comanda = p_id_comanda
           AND ci.estado <> 5          -- lo cancelado no se cocina
         ORDER BY ci.id
    LOOP
        v_n := v_n + 1;

        -- "2 x Croqueta" con la cantidad delante: se lee mejor al vuelo.
        v_linea := (CASE WHEN v_it.cantidad % 1 = 0
                         THEN v_it.cantidad::integer::text
                         ELSE trim(to_char(v_it.cantidad, 'FM999990.999')) END)
                   || ' x ' || v_it.denominacion;

        v_texto := v_texto || substr(v_linea, 1, v_ancho) || E'\n';

        -- La nota del comensal, indentada y en mayusculas: es lo que provoca
        -- devoluciones si se pasa por alto.
        IF v_it.notas IS NOT NULL AND TRIM(v_it.notas) <> '' THEN
            v_texto := v_texto || '   >> ' || upper(substr(TRIM(v_it.notas), 1, v_ancho - 6)) || E'\n';
        END IF;

        IF v_it.modo_elaboracion = 'por_tanda' THEN
            v_texto := v_texto || '   (de tanda)' || E'\n';
        END IF;

        v_items := v_items || jsonb_build_object(
            'id',               v_it.id,
            'denominacion',     v_it.denominacion,
            'cantidad',         v_it.cantidad,
            'notas',            v_it.notas,
            'modo_elaboracion', v_it.modo_elaboracion,
            'estado',           v_it.estado
        );
    END LOOP;

    IF v_n = 0 THEN
        v_texto := v_texto || '(sin platos)' || E'\n';
    END IF;

    IF v_co.notas IS NOT NULL AND TRIM(v_co.notas) <> '' THEN
        v_texto := v_texto || v_sep || E'\n';
        v_texto := v_texto || 'NOTA: ' || upper(TRIM(v_co.notas)) || E'\n';
    END IF;

    v_texto := v_texto || v_sep || E'\n';

    RETURN jsonb_build_object(
        'status',      'success',
        'id_comanda',  v_co.id,
        'numero',      v_co.numero,
        'id_cocina',   v_co.id_cocina,
        'cocina',      v_co.cocina,
        -- A que impresora mandarlo. NULL = la cocina no tiene una configurada y
        -- la app deberia mostrar el ticket en pantalla.
        'impresora',   v_co.impresora,
        'mesa',        v_co.mesa,
        'zona',        v_co.zona,
        'vendedor',    NULLIF(v_co.vendedor, ''),
        'created_at',  v_co.created_at,
        'items',       v_items,
        'total_items', v_n,
        'ancho',       v_ancho,
        'texto',       v_texto
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_ticket_comanda(bigint, integer)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las 4 funciones nuevas
SELECT p.oid::regprocedure AS firma, p.prosecdef AS sec_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_pedir_item_cuenta_offline',
                     'fn_cambiar_estado_comanda_item_offline',
                     'fn_comandas_abiertas_turno',
                     'fn_ticket_comanda')
 ORDER BY p.proname;

-- (b) Los wrappers offline deben DELEGAR, no reimplementar -> ambos true
SELECT p.proname,
       (p.prosrc LIKE '%app_dat_operacion_offline_idempotencia%') AS usa_idempotencia,
       (p.prosrc LIKE '%fn_pedir_item_cuenta(%'
        OR p.prosrc LIKE '%fn_cambiar_estado_comanda_item(%')      AS delega
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_pedir_item_cuenta_offline',
                     'fn_cambiar_estado_comanda_item_offline')
 ORDER BY p.proname;

-- (c) Tipos de idempotencia registrados (los nuevos apareceran al usarse)
SELECT tipo, count(*) AS operaciones
  FROM app_dat_operacion_offline_idempotencia
 GROUP BY tipo
 ORDER BY 2 DESC;
