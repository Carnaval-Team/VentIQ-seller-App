
-- ============================================================================
-- 25 · Atajo del boton de carrito en modo restaurante
--
-- Pedido del usuario durante el QA:
--   "cuando estoy en el modo restaurant seria recomendable que el boton que
--    tiene un carrito que dice preorden cambiarlo para que te lleve a la ultima
--    cuenta abierta que se abrio para annadirle productos"
--
-- POR QUE HACE FALTA
-- ------------------
-- En modo restaurante la preorden LOCAL no se usa: el carrito vive en BD por
-- mesa (app_dat_mesa_cuenta_item). El boton del carrito llevaba a /preorder,
-- que en ese modo esta SIEMPRE vacia. Para seguir anadiendo platos el mesero
-- tenia que ir a Mesas -> buscar la mesa -> entrar a la cuenta: tres toques por
-- cada ronda de pedidos.
--
-- Esta RPC responde "a que cuenta volveria el mesero", y la app usa eso para el
-- atajo (ver NavigationHelper.goCarrito en ventiq_app).
--
-- POR QUE updated_at Y NO created_at
-- ----------------------------------
-- Si el mesero atiende dos mesas a la vez, la que le interesa NO es la que abrio
-- primero, es la que acaba de tocar. Ordenar por created_at le mandaria a la
-- mesa equivocada justo cuando hay prisa.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_ultima_cuenta_abierta_tpv(
    p_id_tpv      bigint,
    p_id_vendedor bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_tienda bigint;
    v_out       jsonb;
BEGIN
    SELECT t.id_tienda INTO v_id_tienda
      FROM app_dat_tpv t WHERE t.id = p_id_tpv;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object('status','error','error_code','TPV_INVALIDO',
                                  'message','El punto de venta no existe');
    END IF;

    PERFORM check_user_has_access_to_tienda(v_id_tienda);

    -- OJO con el schema real: la tabla es app_dat_mesas (PLURAL) y la zona es
    -- una COLUMNA text, no una tabla app_dat_zona. Asumirlo al reves costo un
    -- 'relation app_dat_mesa does not exist' en la primera version.
    SELECT jsonb_build_object(
               'status',            'success',
               'id_cuenta',         c.id,
               'id_mesa',           c.id_mesa,
               'mesa_numero',       m.numero,
               'mesa_zona',         m.zona,
               'numero_comensales', c.numero_comensales,
               'cantidad_items',    COALESCE(x.n, 0),
               'total',             COALESCE(x.total, 0),
               'created_at',        c.created_at,
               'updated_at',        c.updated_at,
               'minutos_abierta',   floor(EXTRACT(EPOCH FROM (now() - c.created_at)) / 60)
           )
      INTO v_out
      FROM app_dat_mesa_cuenta_abierta c
      JOIN app_dat_mesas m ON m.id = c.id_mesa
      LEFT JOIN LATERAL (
           SELECT count(*)::int AS n,
                  COALESCE(SUM(i.cantidad * i.precio_unitario), 0)::numeric AS total
             FROM app_dat_mesa_cuenta_item i WHERE i.id_cuenta = c.id
      ) x ON TRUE
     WHERE c.estado = 1                    -- 1 = abierta
       AND c.id_tienda = v_id_tienda
       -- Se filtra por TPV solo si la cuenta lo tiene puesto: hay cuentas
       -- historicas con id_tpv NULL y esconderlas dejaria al mesero sin atajo.
       AND (c.id_tpv IS NULL OR c.id_tpv = p_id_tpv)
       AND (p_id_vendedor IS NULL OR c.id_vendedor IS NULL
            OR c.id_vendedor = p_id_vendedor)
     ORDER BY c.updated_at DESC, c.id DESC
     LIMIT 1;

    -- Sin cuentas abiertas NO es un error: la app manda a /mesas para elegir.
    IF v_out IS NULL THEN
        RETURN jsonb_build_object('status','success','id_cuenta', NULL,
                                  'message','No hay cuentas abiertas');
    END IF;

    RETURN v_out;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_ultima_cuenta_abierta_tpv(bigint, bigint)
    TO anon, authenticated, service_role;


-- ============================================================================
-- COMPORTAMIENTO EN LA APP (ventiq_app, ya aplicado)
--
-- NavigationHelper.goCarrito() decide en cascada:
--   1. Modo normal            -> /preorder, como siempre.
--   2. Cuenta activa en RAM   -> directo a esa cuenta (caso mas comun).
--   3. Esta RPC               -> la ultima cuenta abierta, con aviso de la mesa.
--   4. Sin cuentas abiertas   -> /mesas, para elegir mesa.
--
-- La barra inferior tambien cambia en modo restaurante:
--   * icono   -> receipt_long en vez de shopping_cart
--   * etiqueta-> numero de la mesa, o "Mesas" si no hay cuenta
--   * badge   -> punto verde si hay cuenta abierta (no el contador rojo: los
--                items estan en BD y contarlos en cada rebuild seria una
--                consulta por frame)
-- ============================================================================


-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- (a) Sin cuentas abiertas: id_cuenta null y status success, NO error
--     Sustituir <TPV> por el id real del punto de venta.
-- SELECT public.fn_ultima_cuenta_abierta_tpv(<TPV>) AS sin_cuentas;

-- (b) Devuelve la mas reciente por updated_at.
--     Abrir dos cuentas, tocar la primera, y comprobar que gana la primera.
-- BEGIN;
-- DO $$
-- DECLARE c1 bigint; c2 bigint;
-- BEGIN
--   c1 := public.fn_abrir_cuenta_mesa(p_id_mesa:=1, p_id_tpv:=<TPV>, p_forzar_nueva:=true);
--   c2 := public.fn_abrir_cuenta_mesa(p_id_mesa:=2, p_id_tpv:=<TPV>, p_forzar_nueva:=true);
--   UPDATE app_dat_mesa_cuenta_abierta SET updated_at = now() + interval '1 min' WHERE id = c1;
--   RAISE NOTICE 'devuelve % (esperado %)',
--     public.fn_ultima_cuenta_abierta_tpv(<TPV>)->>'id_cuenta', c1;
-- END $$;
-- ROLLBACK;

-- (c) TPV inexistente -> TPV_INVALIDO
SELECT public.fn_ultima_cuenta_abierta_tpv(999999)->>'error_code' AS esperado_tpv_invalido;

-- (d) Coherencia con la RPC que ya existia para una mesa concreta:
--     el total y el conteo de items deben coincidir.
-- SELECT 'nueva' AS fuente, (public.fn_ultima_cuenta_abierta_tpv(<TPV>)->>'cantidad_items') AS items,
--                           (public.fn_ultima_cuenta_abierta_tpv(<TPV>)->>'total') AS total
-- UNION ALL
-- SELECT 'fn_listar_cuentas_mesa', cantidad_items::text, total::text
--   FROM public.fn_listar_cuentas_mesa(<ID_MESA>);
