-- ============================================================================
-- 20 · Fase 3 · RPC del KDS: listar y cambiar estado de comandas
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- QUE HACE
-- --------
-- Las tres RPC que alimentan la pantalla de cocina:
--
--   fn_listar_comandas_cocina        lo que la cocina tiene que hacer ahora
--   fn_cambiar_estado_comanda_item   avanzar un plato suelto
--   fn_cambiar_estado_comanda        avanzar el ticket completo
--
-- DECISIONES DE DISENO
-- --------------------
--
-- 1. ALCANCE POR USUARIO, NO POR PARAMETRO.
--    p_id_cocina es OPCIONAL. Sin el, devuelve las comandas de TODAS las
--    cocinas del usuario (fn_cocinas_del_usuario). Con el, valida que sea suya.
--    Un jefe de cocina no puede leer otra estacion ni pasando el id a mano.
--
-- 2. ESTADO A DOS NIVELES (item y ticket), como los KDS reales.
--    Lightspeed lo documenta: "mark individual items or the whole order".
--    Una guarnicion puede estar lista antes que el plato fuerte.
--
--    El estado de la CABECERA se DERIVA de sus items: es el MINIMO de los
--    items vivos. Asi un ticket con 2 platos listos y 1 preparando sigue
--    diciendo "en preparacion", que es la verdad operativa: no se puede
--    entregar la mesa entera todavia.
--
--    No se deja que la cabecera y los items se contradigan por descuido: cada
--    cambio de item recalcula la cabecera.
--
-- 3. TRANSICIONES VALIDADAS, CON MARCHA ATRAS LIMITADA.
--    Un cocinero se equivoca y marca "listo" el plato de otra mesa. Tiene que
--    poder deshacerlo. Pero un plato ya ENTREGADO al comensal no puede volver
--    a la cola, y un CANCELADO no revive: eso descuadraria el inventario que
--    ya se movio al pedir.
--
--      1 pendiente  -> 2, 3, 4, 5   (salto directo: plato rapido)
--      2 en prep    -> 1, 3, 4, 5   (1 = deshacer "empezar")
--      3 listo      -> 2, 4, 5      (2 = deshacer "listo")
--      4 entregado  -> (terminal)
--      5 cancelado  -> (terminal)
--
--    Se permite cualquier AVANCE porque "marchando todo" tiene que poder
--    llevar a listo un ticket con platos aun en pendiente. El retroceso queda
--    limitado a un paso.
--
--    Cancelar desde el KDS NO devuelve inventario: la RPC de cancelacion con
--    devolucion es fn_cancelar_item_pedido (14.4), que la usa el vendedor
--    desde la cuenta. Aqui cancelar significa "esto no se va a cocinar", y el
--    ajuste de stock lo decide quien maneja la nota.
--
-- 4. ESPEJO EN LA LINEA DE LA CUENTA.
--    Cada cambio actualiza app_dat_mesa_cuenta_item.estado_servicio. El 18 ya
--    lee comanda_estado como dato vivo, pero mantener el espejo sincronizado
--    hace que la linea sea consultable sin joins y sirve de respaldo.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Aplicar este archivo (idempotente).
--   2. Correr la VERIFICACION y la prueba funcional.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 20.1 fn_listar_comandas_cocina
--
-- La consulta que el KDS ejecuta cada pocos segundos. Devuelve jsonb con las
-- comandas y sus items anidados, para evitar N+1.
--
-- p_estados: por defecto solo lo VIVO (1 pendiente, 2 en prep, 3 listo). El
-- historico se pide explicitamente pasando ARRAY[4,5].
--
-- Orden: por antiguedad de la comanda. La cocina trabaja FIFO, y el ticket que
-- lleva mas tiempo esperando va primero. Se incluye espera_minutos para que la
-- UI pueda pintar en rojo lo que se esta demorando.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_comandas_cocina(
    p_id_cocina bigint     DEFAULT NULL,
    p_estados   smallint[] DEFAULT ARRAY[1, 2, 3]::smallint[],
    p_limite    integer    DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_cocinas bigint[];
    v_result  jsonb;
BEGIN
    -- Alcance: las cocinas del usuario. Si pide una concreta, validar que sea
    -- suya en lugar de confiar en el parametro.
    IF p_id_cocina IS NOT NULL THEN
        PERFORM fn_usuario_puede_operar_cocina(p_id_cocina);
        v_cocinas := ARRAY[p_id_cocina];
    ELSE
        SELECT array_agg(cu.id_cocina) INTO v_cocinas
          FROM fn_cocinas_del_usuario() cu;
    END IF;

    IF v_cocinas IS NULL OR array_length(v_cocinas, 1) IS NULL THEN
        RETURN jsonb_build_object(
            'status',   'success',
            'comandas', '[]'::jsonb,
            'total',    0,
            'message',  'No tienes cocinas asignadas'
        );
    END IF;

    SELECT COALESCE(jsonb_agg(c ORDER BY c->>'created_at'), '[]'::jsonb)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
                 'id',             co.id,
                 'numero',         co.numero,
                 'estado',         co.estado,
                 'id_cocina',      co.id_cocina,
                 'cocina',         ck.denominacion,
                 'id_cuenta',      co.id_cuenta,
                 'id_mesa',        co.id_mesa,
                 'mesa',           m.numero,
                 'zona',           m.zona,
                 'id_tpv',         co.id_tpv,
                 'notas',          co.notas,
                 'created_at',     co.created_at,
                 'started_at',     co.started_at,
                 'ready_at',       co.ready_at,
                 -- Minutos desde que entro la comanda. Es el dato con el que la
                 -- cocina prioriza y la UI decide cuando pintar en rojo.
                 'espera_minutos',
                     GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - co.created_at)) / 60))::integer,
                 'total_items',    (SELECT count(*) FROM app_dat_comanda_item ci
                                     WHERE ci.id_comanda = co.id),
                 'items_listos',   (SELECT count(*) FROM app_dat_comanda_item ci
                                     WHERE ci.id_comanda = co.id AND ci.estado >= 3
                                       AND ci.estado <> 5),
                 'items', COALESCE((
                     SELECT jsonb_agg(jsonb_build_object(
                              'id',               ci.id,
                              'id_producto',      ci.id_producto,
                              'denominacion',     ci.denominacion,
                              'cantidad',         ci.cantidad,
                              'modo_elaboracion', ci.modo_elaboracion,
                              'estado',           ci.estado,
                              'notas',            ci.notas,
                              'created_at',       ci.created_at,
                              'started_at',       ci.started_at,
                              'ready_at',         ci.ready_at
                          ) ORDER BY ci.id)
                       FROM app_dat_comanda_item ci
                      WHERE ci.id_comanda = co.id
                 ), '[]'::jsonb)
               ) AS c
          FROM app_dat_comanda co
          JOIN app_dat_cocina ck ON ck.id = co.id_cocina
          LEFT JOIN app_dat_mesas m ON m.id = co.id_mesa
         WHERE co.id_cocina = ANY(v_cocinas)
           AND co.estado = ANY(p_estados)
         ORDER BY co.created_at
         LIMIT p_limite
      ) q;

    RETURN jsonb_build_object(
        'status',   'success',
        'comandas', v_result,
        'total',    jsonb_array_length(v_result),
        'cocinas',  to_jsonb(v_cocinas)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_comandas_cocina(bigint, smallint[], integer)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 20.2 _fn_recalcular_estado_comanda  (interno)
--
-- La cabecera es el MINIMO de sus items vivos. Si todos estan cancelados, la
-- comanda queda cancelada; si todos entregados, entregada.
--
-- Los timestamps se sellan la PRIMERA vez que se alcanza cada estado y no se
-- borran al retroceder: interesa saber a que hora se empezo realmente, aunque
-- luego alguien deshiciera el marcado.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_recalcular_estado_comanda(
    p_id_comanda bigint
)
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_vivos   integer;
    v_min     smallint;
    v_total   integer;
    v_cancel  integer;
    v_nuevo   smallint;
BEGIN
    SELECT count(*),
           count(*) FILTER (WHERE estado <> 5),
           min(estado) FILTER (WHERE estado <> 5),
           count(*) FILTER (WHERE estado = 5)
      INTO v_total, v_vivos, v_min, v_cancel
      FROM app_dat_comanda_item
     WHERE id_comanda = p_id_comanda;

    IF v_total = 0 THEN
        RETURN NULL;   -- comanda sin items: no se toca
    END IF;

    -- Todos cancelados -> comanda cancelada.
    v_nuevo := CASE WHEN v_vivos = 0 THEN 5::smallint ELSE v_min END;

    UPDATE app_dat_comanda
       SET estado       = v_nuevo,
           started_at   = COALESCE(started_at,   CASE WHEN v_nuevo >= 2 AND v_nuevo <> 5 THEN now() END),
           ready_at     = COALESCE(ready_at,     CASE WHEN v_nuevo >= 3 AND v_nuevo <> 5 THEN now() END),
           delivered_at = COALESCE(delivered_at, CASE WHEN v_nuevo = 4 THEN now() END),
           cancelled_at = COALESCE(cancelled_at, CASE WHEN v_nuevo = 5 THEN now() END),
           updated_at   = now()
     WHERE id = p_id_comanda;

    RETURN v_nuevo;
END;
$function$;


-- ----------------------------------------------------------------------------
-- 20.3 fn_cambiar_estado_comanda_item
--
-- Avanza (o retrocede) un plato suelto.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item(
    p_id_item      bigint,
    p_nuevo_estado smallint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_item        RECORD;
    v_id_cocina   bigint;
    v_permitidos  smallint[];
    v_estado_cab  smallint;
BEGIN
    IF p_nuevo_estado IS NULL OR p_nuevo_estado < 1 OR p_nuevo_estado > 5 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Estado invalido: debe estar entre 1 y 5',
            'error_code', 'ESTADO_INVALIDO'
        );
    END IF;

    SELECT ci.id, ci.estado, ci.id_comanda, ci.denominacion, ci.id_item_cuenta,
           co.id_cocina
      INTO v_item
      FROM app_dat_comanda_item ci
      JOIN app_dat_comanda co ON co.id = ci.id_comanda
     WHERE ci.id = p_id_item;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El item de comanda no existe',
            'error_code', 'ITEM_NOT_FOUND'
        );
    END IF;

    -- Guard: solo quien opera esa cocina.
    PERFORM fn_usuario_puede_operar_cocina(v_item.id_cocina);

    -- Idempotente: marcar dos veces lo mismo no es un error (el KDS es tactil
    -- y el doble toque es habitual).
    IF v_item.estado = p_nuevo_estado THEN
        RETURN jsonb_build_object(
            'status',     'success',
            'sin_cambio', true,
            'id_item',    p_id_item,
            'estado',     p_nuevo_estado,
            'message',    'Ya estaba en ese estado'
        );
    END IF;

    -- Matriz de transiciones.
    -- CORREGIDO tras probar: la version inicial solo permitia avanzar de UNO
    -- en UNO (1->2->3->4). Eso rompia "marchando todo": al marcar la comanda
    -- entera como lista, los platos que seguian en 1 se saltaban, y la cabecera
    -- (que es el minimo de sus items) nunca llegaba a 3. En cocina real un
    -- plato rapido pasa de pendiente a listo sin escala.
    --
    -- Ahora: cualquier AVANCE vale; el RETROCESO es de un solo paso (3->2,
    -- 2->1) para deshacer un marcado equivocado; 4 y 5 siguen terminales.
    v_permitidos := CASE v_item.estado
        WHEN 1 THEN ARRAY[2, 3, 4, 5]::smallint[]
        WHEN 2 THEN ARRAY[1, 3, 4, 5]::smallint[]
        WHEN 3 THEN ARRAY[2, 4, 5]::smallint[]
        ELSE ARRAY[]::smallint[]   -- 4 y 5 son terminales
    END;

    IF NOT (p_nuevo_estado = ANY(v_permitidos)) THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    CASE v_item.estado
                WHEN 4 THEN 'El plato ya fue entregado: no se puede cambiar'
                WHEN 5 THEN 'El plato esta cancelado: no se puede reactivar'
                ELSE 'Transicion no permitida'
            END,
            'error_code',     'TRANSICION_INVALIDA',
            'estado_actual',  v_item.estado,
            'estado_pedido',  p_nuevo_estado,
            'permitidos',     to_jsonb(v_permitidos)
        );
    END IF;

    UPDATE app_dat_comanda_item
       SET estado       = p_nuevo_estado,
           -- >= y no = : un salto 1->3 tambien debe sellar started_at.
           started_at   = COALESCE(started_at,   CASE WHEN p_nuevo_estado >= 2 AND p_nuevo_estado <> 5 THEN now() END),
           ready_at     = COALESCE(ready_at,     CASE WHEN p_nuevo_estado >= 3 AND p_nuevo_estado <> 5 THEN now() END),
           delivered_at = COALESCE(delivered_at, CASE WHEN p_nuevo_estado = 4 THEN now() END),
           updated_at   = now()
     WHERE id = p_id_item;

    -- Espejo en la linea de la cuenta, para que el mesero lo vea.
    IF v_item.id_item_cuenta IS NOT NULL THEN
        UPDATE app_dat_mesa_cuenta_item
           SET estado_servicio = p_nuevo_estado,
               updated_at = now()
         WHERE id = v_item.id_item_cuenta;
    END IF;

    v_estado_cab := _fn_recalcular_estado_comanda(v_item.id_comanda);

    RETURN jsonb_build_object(
        'status',          'success',
        'id_item',         p_id_item,
        'plato',           v_item.denominacion,
        'estado_anterior', v_item.estado,
        'estado',          p_nuevo_estado,
        'id_comanda',      v_item.id_comanda,
        'estado_comanda',  v_estado_cab,
        'message',         v_item.denominacion || ': ' ||
            CASE p_nuevo_estado
                WHEN 1 THEN 'devuelto a pendiente'
                WHEN 2 THEN 'en preparacion'
                WHEN 3 THEN 'listo'
                WHEN 4 THEN 'entregado'
                WHEN 5 THEN 'cancelado'
            END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cambiar_estado_comanda_item(bigint, smallint)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 20.4 fn_cambiar_estado_comanda
--
-- Avanza el ticket completo: aplica el estado a todos los items que lo
-- admitan. Los que ya estan entregados o cancelados se dejan como estan en vez
-- de fallar: "marchando todo" no debe romperse porque un plato se cancelo.
--
-- Devuelve cuantos se cambiaron y cuantos se saltaron, para que el KDS pueda
-- avisar si algo no se movio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda(
    p_id_comanda   bigint,
    p_nuevo_estado smallint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_cocina  bigint;
    v_numero     integer;
    v_cambiados  integer := 0;
    v_saltados   integer := 0;
    v_it         RECORD;
    v_res        jsonb;
    v_estado_cab smallint;
BEGIN
    IF p_nuevo_estado IS NULL OR p_nuevo_estado < 1 OR p_nuevo_estado > 5 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'Estado invalido: debe estar entre 1 y 5',
            'error_code', 'ESTADO_INVALIDO'
        );
    END IF;

    SELECT co.id_cocina, co.numero INTO v_id_cocina, v_numero
      FROM app_dat_comanda co WHERE co.id = p_id_comanda;

    IF v_id_cocina IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La comanda no existe',
            'error_code', 'COMANDA_NOT_FOUND'
        );
    END IF;

    PERFORM fn_usuario_puede_operar_cocina(v_id_cocina);

    FOR v_it IN
        SELECT id FROM app_dat_comanda_item
         WHERE id_comanda = p_id_comanda
         ORDER BY id
    LOOP
        v_res := fn_cambiar_estado_comanda_item(v_it.id, p_nuevo_estado);

        IF (v_res->>'status') = 'success' AND NOT COALESCE((v_res->>'sin_cambio')::boolean, false) THEN
            v_cambiados := v_cambiados + 1;
        ELSE
            v_saltados := v_saltados + 1;
        END IF;
    END LOOP;

    v_estado_cab := _fn_recalcular_estado_comanda(p_id_comanda);

    RETURN jsonb_build_object(
        'status',      'success',
        'id_comanda',  p_id_comanda,
        'numero',      v_numero,
        'estado',      v_estado_cab,
        'cambiados',   v_cambiados,
        'saltados',    v_saltados,
        'message',     'Comanda #' || COALESCE(v_numero::text, '?') || ': ' ||
            CASE p_nuevo_estado
                WHEN 1 THEN 'devuelta a pendiente'
                WHEN 2 THEN 'en preparacion'
                WHEN 3 THEN 'lista'
                WHEN 4 THEN 'entregada'
                WHEN 5 THEN 'cancelada'
            END ||
            CASE WHEN v_saltados > 0
                THEN ' (' || v_saltados || ' sin cambiar)'
                ELSE '' END
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cambiar_estado_comanda(bigint, smallint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Las 4 funciones, todas SECURITY DEFINER
SELECT p.oid::regprocedure AS firma, p.prosecdef AS sec_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_listar_comandas_cocina', 'fn_cambiar_estado_comanda_item',
                     'fn_cambiar_estado_comanda', '_fn_recalcular_estado_comanda')
 ORDER BY p.proname;

-- (b) Las tres RPC publicas deben pasar por el guard de cocina -> 3 filas true
SELECT p.proname,
       (p.prosrc LIKE '%fn_usuario_puede_operar_cocina%'
        OR p.prosrc LIKE '%fn_cocinas_del_usuario%') AS aplica_guard
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_listar_comandas_cocina', 'fn_cambiar_estado_comanda_item',
                     'fn_cambiar_estado_comanda')
 ORDER BY p.proname;
