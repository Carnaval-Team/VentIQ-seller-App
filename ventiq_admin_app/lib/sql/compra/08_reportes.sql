-- ============================================================================
-- 08_reportes.sql — Fase 8: reportes de control R2-R7 (solo lectura)
--
-- REQUIERE: 01 (motor de dinero), 02, 03a/03b (compras), 04 (reserva/pago),
--           05a (recepción), 06a-06d (costo aterrizado y ajustes),
--           07 (aportes de inversores). Todos aplicados en `newa`
--           (qhprswhhfasrikhawjoz) antes de este script.
--
-- Qué crea (7 funciones STABLE SECURITY DEFINER que NO escriben nada):
--
--   R2  fn_fdi_reporte_caja(bigint)
--       Por (cuenta, medio, moneda): saldo bruto, reservado (Σ reservas
--       `activa` de esa clave), disponible = saldo − reservado, movimientos y
--       lo ejecutado en la ventana de 30 días (Σ monto con signo). Más
--       `totales_por_moneda`. NO sustituye a `fn_fdi_saldos(bigint)` (legacy,
--       sin reservado/disponible, con consumidores) ni a
--       `fn_fdi_disponible(bigint)` (la del diálogo de reserva): este reporte
--       añade el ejecutado del periodo y los totales por moneda.
--
--   R3  fn_fdi_reporte_compras(bigint, date, date)
--       Por estado y moneda: compras, facturado (Σ total_mercancia),
--       aterrizado (Σ costo_aterrizado), pagado (Σ monto_eq_total de los
--       pagos), reservado_activo y diferencia = aterrizado − facturado.
--       Filtro opcional por `fecha_factura`.
--
--   R4  fn_fdi_reporte_costo(bigint, date, date)
--       Por compra, el costo real contra la factura: mercancía, adicionales,
--       aterrizado, % de desvío y avance recibido. Más un `resumen` con el
--       desvío ponderado. Reutiliza la idea de
--       `fn_fdi_compra_costo_resumen(bigint)` (fase 6), que sigue siendo la
--       fuente del detalle de una compra.
--
--   R5  fn_fdi_reporte_cambiario(bigint, date, date)
--       Por compra y por pago: tasa de factura contra tasa de pago, el
--       equivalente real (monto_eq_total), el equivalente a la tasa de la
--       factura, la diferencia y su signo. Agregado por compra y total por
--       moneda. Los importes nativos de los pagos se agregan por su propia
--       moneda (`pagos_por_moneda`): no hay un `monto_pagado` que sume USD con
--       CUP.
--
--   R6  fn_fdi_reporte_movimientos(bigint, date, date)
--       Por (día, usuario, moneda): cuántos movimientos, entradas, salidas y
--       neto. Usuario = `created_by` resuelto a email. Ventana por defecto:
--       últimos 30 días. Es el agregado de `fn_fdi_movimientos(...)`, que
--       sigue siendo la lista con saldo antes/después.
--
--   R7  fn_fdi_reporte_inversores(bigint)
--       Por inversor y moneda: aportes vigentes y devueltos, utilidad
--       repartida, pagada y pendiente; más el detalle de las compras en las
--       que participa. Complementa a `fn_fdi_historial_inversores(...)`, que
--       sigue dando repartos y pagos por liquidación.
--
--   --  fn_fdi_reporte_aging(bigint)  (aging + descuadres declarados)
--       `reservas_activas`: antigüedad de cada reserva viva, con el estado y
--       el financiado de su compra. `descuadres`: compras cuyo financiado no
--       cuadra con líneas + ajustes de fondo, o cuyo pagado no cuadra con el
--       financiado, con la última fila de `fdi_hist_estado_compra` para ver
--       el descuadre declarado.
--
-- Reglas que respeta:
--   · Nunca suma monedas distintas: todo agregado va por moneda y cada
--     importe viaja con la suya. No hay un «total» multimoneda.
--   · Solo lectura: STABLE (no puede escribir) + SECURITY DEFINER (lee
--     `auth.users` para el email sin depender de los permisos del cliente).
--   · Control de acceso con `fn_user_can_access_tienda(p_id_tienda)`. Sin
--     sesión (`auth.uid()` NULL: service_role / editor SQL) se permite, igual
--     que el resto del módulo.
--   · REVOKE de PUBLIC y `anon`; GRANT solo a `authenticated`.
--
-- DESVIACIÓN DOCUMENTADA de R3/aging (`fn_fdi_reporte_aging`):
--   El criterio de pagos (`abs(Σ pagos.monto_eq_total − total_financiado)`)
--   se aplica solo a compras en estados en los que el pago ya se declaró
--   (`pagada`, `entrega_parcial`, `completada`, `anulada`). En `creada` y
--   `reservada` el pagado es 0 por diseño (todavía no se pagó) y en
--   `cancelada` la obligación murió con la cancelación (solo se cancela desde
--   `creada`/`reservada`, y `fn_fdi_compra_cancelar` libera las reservas): en
--   esos tres estados el criterio daría un falso positivo en toda compra. Las
--   compras abiertas ya se ven en R3 con `pagado = 0`. Si se quiere el
--   criterio literal en todos los estados, se quita el `AND d.estado IN (...)`
--   de `fn_fdi_reporte_aging` y el reporte marcará además cada compra sin
--   pagar.
--
-- ROLLBACK: 08_reportes_rollback.sql (solo `DROP FUNCTION`).
-- VERIFY:   verify/08_reportes.sql (solo lectura, una sola sentencia).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Preflight: sin estas piezas los reportes no se pueden construir
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_saldo') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_saldo;';
    END IF;
    IF to_regclass('public.fdi_dat_movimiento') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_movimiento;';
    END IF;
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_linea;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_ajuste') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_ajuste;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_reserva') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_reserva;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_pago') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_pago;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion_linea;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_aporte') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_aporte (aplique 07);';
    END IF;
    IF to_regclass('public.fdi_dat_inversor') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_inversor;';
    END IF;
    IF to_regclass('public.fdi_dat_inversor_reparto') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_inversor_reparto;';
    END IF;
    IF to_regclass('public.fdi_hist_estado_compra') IS NULL THEN
        v_falta := v_falta || ' fdi_hist_estado_compra;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '08: faltan tablas:%.', v_falta USING ERRCODE = '42P01';
    END IF;

    IF to_regprocedure('public.fn_user_can_access_tienda(bigint)') IS NULL THEN
        RAISE EXCEPTION '08: falta fn_user_can_access_tienda(bigint).' USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION '08: falta fn_fdi_conciliacion(bigint) (R1, fase 1).'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) R2 — Caja: saldo, reservado, disponible y ejecutado del periodo
-- ---------------------------------------------------------------------------
-- La clave es (id_cuenta, id_medio_pago, moneda): la misma que usan
-- `fdi_dat_saldo`, `fdi_dat_compra_reserva` y `_fdi_aplicar_movimiento`. El
-- reservado suma SOLO reservas `activa` de esa clave; las `consumida` ya
-- salieron del saldo y las `liberada` no comprometen nada.
--
-- `ejecutado_periodo` es la suma CON SIGNO de `monto` en la ventana (unos
-- movimientos restan). La ventana se devuelve en `ventana_dias`, `desde` y
-- `hasta` para que la UI no la invente.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_caja(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ventana integer := 30;
    v_desde   date    := CURRENT_DATE - 30;
    v_hasta   date    := CURRENT_DATE;
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH claves AS (
            -- LEFT JOIN al nomenclador: una clave del saldo NUNCA se cae del
            -- reporte por un medio de pago sin fila en el nomenclador.
            SELECT s.id_cuenta,
                   s.id_medio_pago,
                   s.moneda,
                   s.saldo,
                   c.nombre AS cuenta,
                   COALESCE(mp.denominacion, 'Medio ' || s.id_medio_pago::text) AS medio_pago
              FROM public.fdi_dat_saldo s
              JOIN public.fdi_dat_cuenta c  ON c.id = s.id_cuenta
              LEFT JOIN public.app_nom_medio_pago mp ON mp.id = s.id_medio_pago
             WHERE s.id_tienda = p_id_tienda
        ),
        reservado AS (
            SELECT r.id_cuenta, r.id_medio_pago, r.moneda,
                   COALESCE(sum(r.monto), 0) AS reservado
              FROM public.fdi_dat_compra_reserva r
             WHERE r.id_tienda = p_id_tienda
               AND r.estado = 'activa'
             GROUP BY 1, 2, 3
        ),
        actividad AS (
            SELECT m.id_cuenta, m.id_medio_pago, m.moneda,
                   count(*) AS n_total,
                   count(*) FILTER (WHERE m.created_at::date >= v_desde) AS n_periodo,
                   COALESCE(sum(m.monto) FILTER (WHERE m.created_at::date >= v_desde), 0) AS ejecutado
              FROM public.fdi_dat_movimiento m
             WHERE m.id_tienda = p_id_tienda
             GROUP BY 1, 2, 3
        ),
        filas AS (
            SELECT k.id_cuenta,
                   k.cuenta,
                   k.id_medio_pago,
                   k.medio_pago,
                   k.moneda,
                   k.saldo,
                   COALESCE(r.reservado, 0) AS reservado,
                   round(k.saldo - COALESCE(r.reservado, 0), 2) AS disponible,
                   COALESCE(a.n_total, 0)   AS n_movimientos,
                   COALESCE(a.n_periodo, 0) AS n_movimientos_periodo,
                   round(COALESCE(a.ejecutado, 0), 2) AS ejecutado_periodo
              FROM claves k
              LEFT JOIN reservado r
                     ON r.id_cuenta = k.id_cuenta
                    AND r.id_medio_pago = k.id_medio_pago
                    AND r.moneda = k.moneda
              LEFT JOIN actividad a
                     ON a.id_cuenta = k.id_cuenta
                    AND a.id_medio_pago = k.id_medio_pago
                    AND a.moneda = k.moneda
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'ventana_dias', v_ventana,
            'desde', v_desde,
            'hasta', v_hasta,
            'claves', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_cuenta', f.id_cuenta,
                           'cuenta', f.cuenta,
                           'id_medio_pago', f.id_medio_pago,
                           'medio_pago', f.medio_pago,
                           'moneda', f.moneda,
                           'saldo', f.saldo,
                           'reservado', f.reservado,
                           'disponible', f.disponible,
                           'n_movimientos', f.n_movimientos,
                           'n_movimientos_periodo', f.n_movimientos_periodo,
                           'ejecutado_periodo', f.ejecutado_periodo)
                       ORDER BY f.id_cuenta, f.id_medio_pago, f.moneda)
                  FROM filas f
            ), '[]'::jsonb),
            -- Un objeto por moneda. No hay total multimoneda a propósito.
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'saldo', t.saldo,
                           'reservado', t.reservado,
                           'disponible', t.disponible,
                           'ejecutado_periodo', t.ejecutado_periodo)
                       ORDER BY t.moneda)
                  FROM (
                        SELECT moneda,
                               round(sum(saldo), 2) AS saldo,
                               round(sum(reservado), 2) AS reservado,
                               round(sum(disponible), 2) AS disponible,
                               round(sum(ejecutado_periodo), 2) AS ejecutado_periodo
                          FROM filas
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_caja(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_caja(bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) R3 — Compras por estado: facturado vs aterrizado vs pagado
-- ---------------------------------------------------------------------------
-- `pagado` usa `monto_eq_total`, que ya está en la moneda de la compra
-- (`moneda_total`): es la única columna comparable con `total_mercancia` y
-- `costo_aterrizado`. Igual `reservado_activo`: se toma el equivalente en
-- moneda de la compra para que cuadre con el resto de la fila; el reservado
-- en moneda nativa por clave de saldo es R2.
--
-- Filtro: por `fecha_factura`. Una compra sin `fecha_factura` queda fuera
-- cuando se pasa alguna fecha (no hay otra fecha con la que situarla).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_compras(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH compras AS (
            SELECT c.id, c.estado, c.moneda_total, c.total_mercancia, c.costo_aterrizado
              FROM public.fdi_dat_compra c
             WHERE c.id_tienda = p_id_tienda
               AND (p_desde IS NULL OR c.fecha_factura >= p_desde)
               AND (p_hasta IS NULL OR c.fecha_factura <= p_hasta)
        ),
        pagos AS (
            SELECT p.id_compra, sum(p.monto_eq_total) AS pagado
              FROM public.fdi_dat_compra_pago p
              JOIN compras c ON c.id = p.id_compra
             GROUP BY 1
        ),
        reservas AS (
            SELECT r.id_compra, sum(r.monto_eq_total) AS reservado
              FROM public.fdi_dat_compra_reserva r
              JOIN compras c ON c.id = r.id_compra
             WHERE r.estado = 'activa'
             GROUP BY 1
        ),
        filas AS (
            SELECT c.estado,
                   c.moneda_total AS moneda,
                   count(*) AS compras,
                   round(sum(c.total_mercancia), 2) AS facturado,
                   round(sum(c.costo_aterrizado), 2) AS aterrizado,
                   round(sum(COALESCE(p.pagado, 0)), 2) AS pagado,
                   round(sum(COALESCE(r.reservado, 0)), 2) AS reservado_activo,
                   round(sum(c.costo_aterrizado) - sum(c.total_mercancia), 2) AS diferencia
              FROM compras c
              LEFT JOIN pagos p    ON p.id_compra = c.id
              LEFT JOIN reservas r ON r.id_compra = c.id
             GROUP BY 1, 2
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', p_desde,
            'hasta', p_hasta,
            'por_estado', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'estado', f.estado,
                           'moneda', f.moneda,
                           'compras', f.compras,
                           'facturado', f.facturado,
                           'aterrizado', f.aterrizado,
                           'pagado', f.pagado,
                           'reservado_activo', f.reservado_activo,
                           'diferencia', f.diferencia)
                       ORDER BY f.estado, f.moneda)
                  FROM filas f
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'compras', t.compras,
                           'facturado', t.facturado,
                           'aterrizado', t.aterrizado,
                           'pagado', t.pagado,
                           'reservado_activo', t.reservado_activo,
                           'diferencia', t.diferencia)
                       ORDER BY t.moneda)
                  FROM (
                        SELECT moneda,
                               sum(compras) AS compras,
                               round(sum(facturado), 2) AS facturado,
                               round(sum(aterrizado), 2) AS aterrizado,
                               round(sum(pagado), 2) AS pagado,
                               round(sum(reservado_activo), 2) AS reservado_activo,
                               round(sum(diferencia), 2) AS diferencia
                          FROM filas
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_compras(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_compras(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) R4 — Costo real contra la factura, por compra
-- ---------------------------------------------------------------------------
-- `pct_desvio` = (aterrizado − mercancía) / mercancía × 100, dos decimales,
-- NULL cuando la compra no tiene mercancía (no se divide por cero y no se
-- inventa un 0 que parecería «sin desvío»).
--
-- `recibido_pct` = Σ `cantidad_recibida` / Σ `cantidad` de las líneas,
-- acotado a 1 (una sobre-recepción no da más de 100 %) y 0 sin líneas. Es una
-- razón, no un importe: no lleva moneda.
--
-- El `resumen` va por moneda: el «desvío global ponderado» es
-- (Σ aterrizado − Σ mercancía) / Σ mercancía de cada moneda. No se suman
-- monedas distintas, así que no hay un único porcentaje multimoneda.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_costo(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH compras AS (
            SELECT c.id, c.numero_compra, c.numero_factura, c.estado, c.moneda_total,
                   c.total_mercancia, c.total_ajustes, c.costo_aterrizado,
                   pr.denominacion AS proveedor
              FROM public.fdi_dat_compra c
              LEFT JOIN public.app_dat_proveedor pr ON pr.id = c.id_proveedor
             WHERE c.id_tienda = p_id_tienda
               AND (p_desde IS NULL OR c.fecha_factura >= p_desde)
               AND (p_hasta IS NULL OR c.fecha_factura <= p_hasta)
        ),
        pedido AS (
            SELECT l.id_compra, sum(l.cantidad) AS cantidad
              FROM public.fdi_dat_compra_linea l
              JOIN compras c ON c.id = l.id_compra
             GROUP BY 1
        ),
        recibido AS (
            SELECT l.id_compra, sum(rl.cantidad_recibida) AS cantidad
              FROM public.fdi_dat_compra_recepcion_linea rl
              JOIN public.fdi_dat_compra_linea l ON l.id = rl.id_compra_linea
              JOIN compras c ON c.id = l.id_compra
             GROUP BY 1
        ),
        filas AS (
            SELECT c.*,
                   CASE WHEN COALESCE(c.total_mercancia, 0) <> 0
                        THEN round((c.costo_aterrizado - c.total_mercancia)
                                   / c.total_mercancia * 100, 2)
                   END AS pct_desvio,
                   CASE WHEN COALESCE(p.cantidad, 0) > 0
                        THEN LEAST(1, round(COALESCE(r.cantidad, 0) / p.cantidad, 6))
                        ELSE 0
                   END AS recibido_pct
              FROM compras c
              LEFT JOIN pedido p   ON p.id_compra = c.id
              LEFT JOIN recibido r ON r.id_compra = c.id
        ),
        resumen AS (
            SELECT moneda_total AS moneda,
                   count(*) AS compras,
                   round(sum(total_mercancia), 2) AS mercancia,
                   round(sum(total_ajustes), 2) AS adicionales,
                   round(sum(costo_aterrizado), 2) AS aterrizado,
                   round(sum(costo_aterrizado) - sum(total_mercancia), 2) AS desvio,
                   CASE WHEN sum(total_mercancia) <> 0
                        THEN round((sum(costo_aterrizado) - sum(total_mercancia))
                                   / sum(total_mercancia) * 100, 2)
                   END AS pct_desvio
              FROM filas
             GROUP BY moneda_total
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', p_desde,
            'hasta', p_hasta,
            'compras', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra', f.id,
                           'numero_compra', f.numero_compra,
                           'numero_factura', f.numero_factura,
                           'proveedor', f.proveedor,
                           'estado', f.estado,
                           'moneda', f.moneda_total,
                           'mercancia', f.total_mercancia,
                           'adicionales', f.total_ajustes,
                           'aterrizado', f.costo_aterrizado,
                           'pct_desvio', f.pct_desvio,
                           'recibido_pct', f.recibido_pct)
                       ORDER BY f.numero_compra, f.id)
                  FROM filas f
            ), '[]'::jsonb),
            'resumen', jsonb_build_object(
                'compras', (SELECT count(*) FROM filas),
                'por_moneda', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                               'moneda', r.moneda,
                               'compras', r.compras,
                               'mercancia', r.mercancia,
                               'adicionales', r.adicionales,
                               'aterrizado', r.aterrizado,
                               'desvio', r.desvio,
                               'pct_desvio', r.pct_desvio)
                           ORDER BY r.moneda)
                      FROM resumen r
                ), '[]'::jsonb)
            )
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_costo(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_costo(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) R5 — Diferencias cambiarias por documento
-- ---------------------------------------------------------------------------
-- Definición (la de `02-contabilidad.md` §6.3, R5; no se inventa otra):
--   equivalente_real        = `monto_eq_total` (lo que costó de verdad en la
--                             moneda de la compra, con la tasa del pago),
--   equivalente_a_tasa_factura = monto del pago × tasa de la factura,
--   diferencia              = real − a tasa factura,
--   signo                   = 'a favor' si la diferencia es ≤ 0 (pagaste igual
--                             o menos moneda de la compra de la que decía la
--                             factura) y 'en contra' si es > 0.
-- La moneda de ambos equivalentes es la de la COMPRA, así que los totales van
-- por `moneda` de la compra (no por la moneda del pago).
--
-- IMPORTANTE (no sumar monedas distintas): los importes NATIVOS de los pagos
-- (`monto_pago`) solo se devuelven en el detalle de cada pago y agregados por
-- su propia moneda en `pagos_por_moneda`. NO existe un `monto_pagado` por
-- compra: una compra puede pagarse con dos monedas (USD + CUP) y sumarlas
-- sería inventar un número. Lo comparable entre pagos es su equivalente en
-- moneda de la compra, que es lo que sí se agrega.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_cambiario(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH compras AS (
            SELECT c.id, c.numero_compra, c.numero_factura, c.estado,
                   c.moneda_total, c.tasa_factura
              FROM public.fdi_dat_compra c
             WHERE c.id_tienda = p_id_tienda
               AND (p_desde IS NULL OR c.fecha_factura >= p_desde)
               AND (p_hasta IS NULL OR c.fecha_factura <= p_hasta)
        ),
        pagos AS (
            SELECT p.id,
                   p.id_compra,
                   p.origen,
                   p.moneda AS moneda_pago,
                   p.monto AS monto_pago,
                   p.tasa_a_total AS tasa_pago,
                   p.monto_eq_total AS equivalente_real,
                   round(p.monto * c.tasa_factura, 2) AS equivalente_a_tasa_factura,
                   round(p.monto_eq_total - round(p.monto * c.tasa_factura, 2), 2) AS diferencia
              FROM public.fdi_dat_compra_pago p
              JOIN compras c ON c.id = p.id_compra
        ),
        pagos_moneda AS (
            -- Importe nativo agrupado por la moneda en que se pagó: es la
            -- única forma honesta de agregar `monto` dentro de una compra.
            SELECT p.id_compra,
                   p.moneda_pago,
                   count(*) AS n,
                   round(sum(p.monto_pago), 2) AS monto
              FROM pagos p
             GROUP BY 1, 2
        ),
        agregado AS (
            SELECT c.id, c.numero_compra, c.numero_factura, c.estado,
                   c.moneda_total, c.tasa_factura,
                   count(p.id) AS n_pagos,
                   round(COALESCE(sum(p.equivalente_real), 0), 2) AS equivalente_real,
                   round(COALESCE(sum(p.equivalente_a_tasa_factura), 0), 2) AS equivalente_a_tasa_factura,
                   round(COALESCE(sum(p.diferencia), 0), 2) AS diferencia
              FROM compras c
              LEFT JOIN pagos p ON p.id_compra = c.id
             GROUP BY c.id, c.numero_compra, c.numero_factura, c.estado,
                      c.moneda_total, c.tasa_factura
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', p_desde,
            'hasta', p_hasta,
            'compras', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra', a.id,
                           'numero_compra', a.numero_compra,
                           'numero_factura', a.numero_factura,
                           'estado', a.estado,
                           'moneda', a.moneda_total,
                           'tasa_factura', a.tasa_factura,
                           'n_pagos', a.n_pagos,
                           'equivalente_real', a.equivalente_real,
                           'equivalente_a_tasa_factura', a.equivalente_a_tasa_factura,
                           'diferencia', a.diferencia,
                           'signo', CASE WHEN a.diferencia <= 0
                                         THEN 'a favor' ELSE 'en contra' END,
                           'pagos_por_moneda', COALESCE((
                               SELECT jsonb_agg(jsonb_build_object(
                                          'moneda_pago', pm.moneda_pago,
                                          'n', pm.n,
                                          'monto', pm.monto)
                                      ORDER BY pm.moneda_pago)
                                 FROM pagos_moneda pm
                                WHERE pm.id_compra = a.id
                           ), '[]'::jsonb),
                           'pagos', COALESCE((
                               SELECT jsonb_agg(jsonb_build_object(
                                          'id_pago', p.id,
                                          'origen', p.origen,
                                          'moneda_pago', p.moneda_pago,
                                          'monto_pago', p.monto_pago,
                                          'tasa_pago', p.tasa_pago,
                                          'equivalente_real', p.equivalente_real,
                                          'equivalente_a_tasa_factura', p.equivalente_a_tasa_factura,
                                          'diferencia', p.diferencia,
                                          'signo', CASE WHEN p.diferencia <= 0
                                                        THEN 'a favor' ELSE 'en contra' END)
                                      ORDER BY p.id)
                                 FROM pagos p
                                WHERE p.id_compra = a.id
                           ), '[]'::jsonb))
                       ORDER BY a.numero_compra, a.id)
                  FROM agregado a
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'compras', t.compras,
                           'pagos', t.pagos,
                           'equivalente_real', t.equivalente_real,
                           'equivalente_a_tasa_factura', t.equivalente_a_tasa_factura,
                           'diferencia', t.diferencia,
                           'signo', CASE WHEN t.diferencia <= 0
                                         THEN 'a favor' ELSE 'en contra' END)
                       ORDER BY t.moneda)
                  FROM (
                        SELECT moneda_total AS moneda,
                               count(*) AS compras,
                               sum(n_pagos) AS pagos,
                               round(sum(equivalente_real), 2) AS equivalente_real,
                               round(sum(equivalente_a_tasa_factura), 2) AS equivalente_a_tasa_factura,
                               round(sum(diferencia), 2) AS diferencia
                          FROM agregado
                         GROUP BY moneda_total
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_cambiario(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_cambiario(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) R6 — Movimientos por día y usuario
-- ---------------------------------------------------------------------------
-- `usuario` = email de `auth.users` para `created_by`; si la fila no tiene
-- usuario (los movimientos automáticos de reserva/liberación) se muestra
-- 'sistema' y, si el uuid ya no está en `auth.users`, el uuid en texto.
--
-- `entradas` y `salidas` van en positivo (salidas = −Σ monto de los negativos)
-- y `neto` = entradas − salidas; el neto se calcula además con Σ monto para
-- que el invariante sea comprobable contra el libro.
--
-- Ventana: `p_desde`/`p_hasta` sobre la fecha del movimiento. Por defecto,
-- últimos 30 días (cada extremo se resuelve por separado).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_movimientos(
    p_id_tienda bigint,
    p_desde     date DEFAULT NULL,
    p_hasta     date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_desde date := COALESCE(p_desde, CURRENT_DATE - 30);
    v_hasta date := COALESCE(p_hasta, CURRENT_DATE);
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH mov AS (
            SELECT m.id,
                   m.created_at::date AS dia,
                   m.moneda,
                   m.monto,
                   COALESCE(u.email, m.created_by::text, 'sistema') AS usuario
              FROM public.fdi_dat_movimiento m
              LEFT JOIN auth.users u ON u.id = m.created_by
             WHERE m.id_tienda = p_id_tienda
               AND m.created_at::date >= v_desde
               AND m.created_at::date <= v_hasta
        ),
        filas AS (
            SELECT dia,
                   usuario,
                   moneda,
                   count(*) AS n,
                   round(COALESCE(sum(monto) FILTER (WHERE monto > 0), 0), 2) AS entradas,
                   round(COALESCE(-(sum(monto) FILTER (WHERE monto < 0)), 0), 2) AS salidas,
                   round(COALESCE(sum(monto), 0), 2) AS neto
              FROM mov
             GROUP BY 1, 2, 3
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'desde', v_desde,
            'hasta', v_hasta,
            'por_dia_usuario', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'dia', f.dia,
                           'usuario', f.usuario,
                           'moneda', f.moneda,
                           'n', f.n,
                           'entradas', f.entradas,
                           'salidas', f.salidas,
                           'neto', f.neto)
                       ORDER BY f.dia, f.usuario, f.moneda)
                  FROM filas f
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'n', t.n,
                           'entradas', t.entradas,
                           'salidas', t.salidas,
                           'neto', t.neto)
                       ORDER BY t.moneda)
                  FROM (
                        SELECT moneda,
                               sum(n) AS n,
                               round(sum(entradas), 2) AS entradas,
                               round(sum(salidas), 2) AS salidas,
                               round(sum(neto), 2) AS neto
                          FROM filas
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_movimientos(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_movimientos(bigint, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6) R7 — Inversores: aportes, devoluciones, utilidad y pendiente
-- ---------------------------------------------------------------------------
-- Por inversor y moneda, con los importes NATIVOS de cada documento (nunca
-- convertidos ni sumados entre monedas):
--   aportes_vigentes    Σ `monto` de aportes en estado 'aportado',
--   aportes_devueltos   Σ `monto` de aportes en estado 'devuelto',
--   utilidad_repartida  Σ `monto` de `fdi_dat_inversor_reparto`,
--   utilidad_pagada     Σ `monto` con `pagado_at` no nulo,
--   utilidad_pendiente  Σ `monto` con `pagado_at` nulo.
-- El bloque `aportes` de cada inversor lista las compras en las que participa
-- (compra, factura, monto, moneda, estado).
--
-- Se listan todos los inversores de la tienda, con o sin movimiento: un
-- inversor sin monedas devuelve `por_moneda` vacío.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_inversores(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH inversores AS (
            SELECT i.id, i.nombre, i.porcentaje, i.activo
              FROM public.fdi_dat_inversor i
             WHERE i.id_tienda = p_id_tienda
        ),
        aportes AS (
            SELECT a.id_inversor,
                   a.moneda,
                   COALESCE(sum(a.monto) FILTER (WHERE a.estado = 'aportado'), 0) AS vigentes,
                   COALESCE(sum(a.monto) FILTER (WHERE a.estado = 'devuelto'), 0) AS devueltos
              FROM public.fdi_dat_compra_aporte a
             WHERE a.id_tienda = p_id_tienda
             GROUP BY 1, 2
        ),
        repartos AS (
            SELECT r.id_inversor,
                   r.moneda,
                   COALESCE(sum(r.monto), 0) AS repartida,
                   COALESCE(sum(r.monto) FILTER (WHERE r.pagado_at IS NOT NULL), 0) AS pagada,
                   COALESCE(sum(r.monto) FILTER (WHERE r.pagado_at IS NULL), 0) AS pendiente
              FROM public.fdi_dat_inversor_reparto r
             WHERE r.id_tienda = p_id_tienda
             GROUP BY 1, 2
        ),
        monedas AS (
            SELECT id_inversor, moneda FROM aportes
            UNION
            SELECT id_inversor, moneda FROM repartos
        ),
        por_moneda AS (
            SELECT m.id_inversor,
                   m.moneda,
                   round(COALESCE(ap.vigentes, 0), 2)   AS aportes_vigentes,
                   round(COALESCE(ap.devueltos, 0), 2)  AS aportes_devueltos,
                   round(COALESCE(rp.repartida, 0), 2)  AS utilidad_repartida,
                   round(COALESCE(rp.pagada, 0), 2)     AS utilidad_pagada,
                   round(COALESCE(rp.pendiente, 0), 2)  AS utilidad_pendiente
              FROM monedas m
              LEFT JOIN aportes ap
                     ON ap.id_inversor = m.id_inversor AND ap.moneda = m.moneda
              LEFT JOIN repartos rp
                     ON rp.id_inversor = m.id_inversor AND rp.moneda = m.moneda
        ),
        detalle AS (
            SELECT a.id_inversor,
                   jsonb_agg(jsonb_build_object(
                       'id_compra', a.id_compra,
                       'numero_compra', c.numero_compra,
                       'numero_factura', c.numero_factura,
                       'moneda', a.moneda,
                       'monto', a.monto,
                       'monto_eq_total', a.monto_eq_total,
                       'estado', a.estado,
                       'devuelto_at', a.devuelto_at)
                     ORDER BY c.numero_compra NULLS LAST, a.id) AS compras
              FROM public.fdi_dat_compra_aporte a
              LEFT JOIN public.fdi_dat_compra c ON c.id = a.id_compra
             WHERE a.id_tienda = p_id_tienda
             GROUP BY 1
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'inversores', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_inversor', i.id,
                           'nombre', i.nombre,
                           'porcentaje', i.porcentaje,
                           'activo', i.activo,
                           'por_moneda', COALESCE((
                               SELECT jsonb_agg(jsonb_build_object(
                                          'moneda', pm.moneda,
                                          'aportes_vigentes', pm.aportes_vigentes,
                                          'aportes_devueltos', pm.aportes_devueltos,
                                          'utilidad_repartida', pm.utilidad_repartida,
                                          'utilidad_pagada', pm.utilidad_pagada,
                                          'utilidad_pendiente', pm.utilidad_pendiente)
                                      ORDER BY pm.moneda)
                                 FROM por_moneda pm
                                WHERE pm.id_inversor = i.id
                           ), '[]'::jsonb),
                           'aportes', COALESCE((
                               SELECT d.compras FROM detalle d WHERE d.id_inversor = i.id
                           ), '[]'::jsonb))
                       ORDER BY i.nombre, i.id)
                  FROM inversores i
            ), '[]'::jsonb),
            'totales_por_moneda', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'moneda', t.moneda,
                           'aportes_vigentes', t.aportes_vigentes,
                           'aportes_devueltos', t.aportes_devueltos,
                           'utilidad_repartida', t.utilidad_repartida,
                           'utilidad_pagada', t.utilidad_pagada,
                           'utilidad_pendiente', t.utilidad_pendiente)
                       ORDER BY t.moneda)
                  FROM (
                        SELECT moneda,
                               round(sum(aportes_vigentes), 2) AS aportes_vigentes,
                               round(sum(aportes_devueltos), 2) AS aportes_devueltos,
                               round(sum(utilidad_repartida), 2) AS utilidad_repartida,
                               round(sum(utilidad_pagada), 2) AS utilidad_pagada,
                               round(sum(utilidad_pendiente), 2) AS utilidad_pendiente
                          FROM por_moneda
                         GROUP BY moneda
                  ) t
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_inversores(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_inversores(bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7) Aging de reservas y descuadres declarados
-- ---------------------------------------------------------------------------
-- `reservas_activas`: una fila por reserva viva (una compra puede tener
-- varias fuentes, cada una con su antigüedad), con la antigüedad en días
-- desde `created_at`, el financiado de su compra y el estado de la compra.
--
-- `descuadres`: dos criterios sobre cada compra.
--   a) `abs(total_financiado − (Σ líneas + Σ ajustes con origen_pago='fondo')) > 0.009`
--      → el financiado congelado ya no corresponde a lo que compone la
--        compra (ajuste tardío de fondo, edición posterior...).
--   b) `abs(Σ pagos.monto_eq_total − total_financiado) > 0.009`
--      → lo pagado no cubre el financiado. Se aplica a los estados en los que
--        el pago ya se declaró (`pagada`, `entrega_parcial`, `completada`,
--        `anulada`); ver la desviación documentada en la cabecera.
-- `ultimo_motivo` es el motivo de la fila más reciente de
-- `fdi_hist_estado_compra`: ahí queda el «descuadre declarado» del alta.
--
-- El umbral 0.009 es el mismo del módulo para diferencias de céntimos.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_reporte_aging(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_can_access_tienda(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Sin acceso a la tienda %', p_id_tienda USING ERRCODE = '42501';
    END IF;

    RETURN (
        WITH reservas AS (
            SELECT r.id AS id_reserva,
                   r.id_compra,
                   r.id_cuenta,
                   r.id_medio_pago,
                   r.moneda,
                   r.monto,
                   r.created_at,
                   GREATEST(0, CURRENT_DATE - r.created_at::date) AS dias_antiguedad,
                   c.numero_compra,
                   c.numero_factura,
                   c.total_financiado,
                   c.estado AS estado_compra
              FROM public.fdi_dat_compra_reserva r
              LEFT JOIN public.fdi_dat_compra c ON c.id = r.id_compra
             WHERE r.id_tienda = p_id_tienda
               AND r.estado = 'activa'
        ),
        calculo AS (
            SELECT c.id,
                   c.numero_compra,
                   c.numero_factura,
                   c.moneda_total,
                   c.estado,
                   c.total_financiado,
                   round(COALESCE((
                       SELECT sum(COALESCE(l.costo_linea, l.cantidad * l.costo_unitario))
                         FROM public.fdi_dat_compra_linea l
                        WHERE l.id_compra = c.id), 0), 2) AS lineas,
                   round(COALESCE((
                       SELECT sum(a.monto_capitalizado)
                         FROM public.fdi_dat_compra_ajuste a
                        WHERE a.id_compra = c.id
                          AND a.origen_pago = 'fondo'), 0), 2) AS ajustes_fondo,
                   round(COALESCE((
                       SELECT sum(p.monto_eq_total)
                         FROM public.fdi_dat_compra_pago p
                        WHERE p.id_compra = c.id), 0), 2) AS pagado
              FROM public.fdi_dat_compra c
             WHERE c.id_tienda = p_id_tienda
        ),
        descuadres AS (
            SELECT x.*,
                   round(x.total_financiado - (x.lineas + x.ajustes_fondo), 2) AS diferencia_financiado,
                   round(x.pagado - x.total_financiado, 2) AS diferencia_pagos
              FROM calculo x
        )
        SELECT jsonb_build_object(
            'id_tienda', p_id_tienda,
            'reservas_activas', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_reserva', r.id_reserva,
                           'id_compra', r.id_compra,
                           'numero_compra', r.numero_compra,
                           'numero_factura', r.numero_factura,
                           'id_cuenta', r.id_cuenta,
                           'id_medio_pago', r.id_medio_pago,
                           'moneda', r.moneda,
                           'monto', r.monto,
                           'dias_antiguedad', r.dias_antiguedad,
                           'total_financiado', r.total_financiado,
                           'estado_compra', r.estado_compra)
                       ORDER BY r.dias_antiguedad DESC, r.id_reserva)
                  FROM reservas r
            ), '[]'::jsonb),
            'descuadres', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'id_compra', d.id,
                           'numero_compra', d.numero_compra,
                           'numero_factura', d.numero_factura,
                           'moneda', d.moneda_total,
                           'estado_compra', d.estado,
                           'total_financiado', d.total_financiado,
                           'lineas', d.lineas,
                           'ajustes_fondo', d.ajustes_fondo,
                           'diferencia_financiado', d.diferencia_financiado,
                           'pagado', d.pagado,
                           'diferencia_pagos', d.diferencia_pagos,
                           'ultimo_motivo', (
                               SELECT h.motivo
                                 FROM public.fdi_hist_estado_compra h
                                WHERE h.id_compra = d.id
                                ORDER BY h.created_at DESC, h.id DESC
                                LIMIT 1))
                       ORDER BY abs(d.diferencia_financiado) DESC, abs(d.diferencia_pagos) DESC, d.id)
                  FROM descuadres d
                 WHERE abs(d.diferencia_financiado) > 0.009
                    OR (abs(d.diferencia_pagos) > 0.009
                        AND d.estado IN ('pagada', 'entrega_parcial', 'completada', 'anulada'))
            ), '[]'::jsonb)
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_reporte_aging(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_reporte_aging(bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) Verificación del script
-- ---------------------------------------------------------------------------
-- Comprueba lo que el script promete: las 7 funciones con su firma exacta,
-- STABLE, SECURITY DEFINER, jsonb, ejecutables por `authenticated` y no por
-- `anon`; y que cada una responde sobre una tienda con datos sin romperse.
DO $$
DECLARE
    v        integer;
    v_tienda bigint;
    v_res    jsonb;
    v_nombre text;
    v_firmas text[] := ARRAY[
        'public.fn_fdi_reporte_caja(bigint)',
        'public.fn_fdi_reporte_compras(bigint,date,date)',
        'public.fn_fdi_reporte_costo(bigint,date,date)',
        'public.fn_fdi_reporte_cambiario(bigint,date,date)',
        'public.fn_fdi_reporte_movimientos(bigint,date,date)',
        'public.fn_fdi_reporte_inversores(bigint)',
        'public.fn_fdi_reporte_aging(bigint)'
    ];
BEGIN
    FOREACH v_nombre IN ARRAY v_firmas LOOP
        IF to_regprocedure(v_nombre) IS NULL THEN
            RAISE EXCEPTION '08: no se creó %', v_nombre USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    -- Forma: STABLE + SECURITY DEFINER + jsonb, en las 7.
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid IN (SELECT to_regprocedure(f) FROM unnest(v_firmas) f)
       AND p.prosecdef
       AND p.provolatile = 's'
       AND pg_get_function_result(p.oid) = 'jsonb';
    IF v <> 7 THEN
        RAISE EXCEPTION '08: solo % de 7 quedaron STABLE/SECURITY DEFINER/jsonb', v;
    END IF;

    -- Sin sobrecargas inesperadas (un residuo de una versión anterior con
    -- otra firma dejaría dos candidatos y PostgREST elegiría por su cuenta).
    SELECT count(*) INTO v
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_reporte_caja', 'fn_fdi_reporte_compras',
                         'fn_fdi_reporte_costo', 'fn_fdi_reporte_cambiario',
                         'fn_fdi_reporte_movimientos', 'fn_fdi_reporte_inversores',
                         'fn_fdi_reporte_aging');
    IF v <> 7 THEN
        RAISE EXCEPTION '08: hay % funciones con esos nombres (se esperaban 7); sobran % sobrecargas', v, v - 7;
    END IF;

    -- Permisos: `authenticated` sí, `anon` no.
    SELECT count(*) INTO v
      FROM unnest(v_firmas) f
     WHERE has_function_privilege('authenticated', to_regprocedure(f), 'EXECUTE');
    IF v <> 7 THEN
        RAISE EXCEPTION '08: `authenticated` no puede ejecutar % de 7 reportes', 7 - v;
    END IF;
    SELECT count(*) INTO v
      FROM unnest(v_firmas) f
     WHERE has_function_privilege('anon', to_regprocedure(f), 'EXECUTE');
    IF v <> 0 THEN
        RAISE EXCEPTION '08: `anon` puede ejecutar % reporte(s); falta REVOKE', v;
    END IF;

    -- Los cuatro con fechas llevan los dos DEFAULT (la UI puede llamarlos con
    -- solo la tienda).
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.fn_fdi_reporte_compras(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_costo(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_cambiario(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_movimientos(bigint,date,date)'))
       AND p.pronargdefaults = 2;
    IF v <> 4 THEN
        RAISE EXCEPTION '08: % de 4 reportes con fechas tienen los 2 DEFAULT', v;
    END IF;

    -- Humo (solo lectura): la tienda con más datos del módulo. Si no hay
    -- ninguna, se omite; el script no depende de que haya datos.
    SELECT id_tienda INTO v_tienda
      FROM (SELECT id_tienda FROM public.fdi_dat_compra
            UNION SELECT id_tienda FROM public.fdi_dat_saldo) x
     GROUP BY id_tienda
     ORDER BY count(*) DESC, id_tienda
     LIMIT 1;

    IF v_tienda IS NOT NULL THEN
        v_res := public.fn_fdi_reporte_caja(v_tienda);
        IF (v_res ->> 'id_tienda')::bigint IS DISTINCT FROM v_tienda
           OR jsonb_typeof(v_res -> 'claves') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_caja no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_reporte_compras(v_tienda);
        IF jsonb_typeof(v_res -> 'por_estado') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_compras no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_reporte_costo(v_tienda);
        IF jsonb_typeof(v_res -> 'compras') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'resumen') IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_costo no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_reporte_cambiario(v_tienda);
        IF jsonb_typeof(v_res -> 'compras') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_cambiario no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_reporte_movimientos(v_tienda);
        IF jsonb_typeof(v_res -> 'por_dia_usuario') IS DISTINCT FROM 'array'
           OR (v_res ->> 'desde') IS NULL OR (v_res ->> 'hasta') IS NULL THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_movimientos no devolvió la ventana esperada';
        END IF;

        v_res := public.fn_fdi_reporte_inversores(v_tienda);
        IF jsonb_typeof(v_res -> 'inversores') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'totales_por_moneda') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_inversores no devolvió la forma esperada';
        END IF;

        v_res := public.fn_fdi_reporte_aging(v_tienda);
        IF jsonb_typeof(v_res -> 'reservas_activas') IS DISTINCT FROM 'array'
           OR jsonb_typeof(v_res -> 'descuadres') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION '08: fn_fdi_reporte_aging no devolvió la forma esperada';
        END IF;
    END IF;

    -- Ninguno de los reportes toca el esquema ni el libro: las funciones
    -- heredadas del módulo siguen intactas.
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION '08: desapareció fn_fdi_conciliacion(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_saldos(bigint)') IS NULL THEN
        RAISE EXCEPTION '08: desapareció fn_fdi_saldos(bigint)';
    END IF;

    RAISE NOTICE '08 aplicado: 7 reportes de solo lectura (R2-R7 + aging) con acceso por tienda.';
END;
$$;

COMMIT;