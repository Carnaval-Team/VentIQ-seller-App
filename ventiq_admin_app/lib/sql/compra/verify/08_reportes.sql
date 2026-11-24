-- ============================================================================
-- verify/08_reportes.sql — Fase 8: reportes R2-R7 y aging (08_reportes.sql)
--
-- REQUIERE: 08_reportes.sql aplicado en `newa` (qhprswhhfasrikhawjoz).
--
-- SOLO LECTURA: SELECT / pg_catalog / information_schema y llamadas a las 7
-- funciones del reporte (STABLE + SECURITY DEFINER, no escriben). Ni DDL ni
-- DML.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- Comprobaciones de CONTRATO (n = 1..5):
--   n=1  las 7 funciones existen con su firma exacta y sin sobrecargas
--   n=2  las 7 son STABLE, SECURITY DEFINER y devuelven jsonb
--   n=3  `authenticated` puede ejecutar las 7 y `anon` ninguna
--   n=4  los 4 reportes con fechas llevan los 2 DEFAULT
--   n=5  R1 sigue existiendo con su firma de 1 argumento (08 no la toca)
--
-- Comprobaciones de INVARIANTE sobre los datos reales (n = 6..13):
--   n=6   R2  en toda clave: disponible = saldo − reservado y reservado >= 0,
--             y saldo/reservado coinciden con `fdi_dat_saldo` y las reservas
--             `activa` de esa clave (una fila por clave de saldo)
--   n=7   R3  por estado y moneda: diferencia = aterrizado − facturado,
--             pagado >= 0, y las cuatro cifras coinciden con las tablas
--   n=8   R4  en toda compra: aterrizado = mercancía + adicionales,
--             pct_desvio coherente y 1 fila por compra
--   n=9   R5  en toda fila (de pago y de compra): diferencia = equivalente_real
--             − equivalente_a_tasa_factura, con su signo; y los importes
--             nativos de los pagos solo se agregan por su propia moneda
--   n=10  R6  en toda fila: neto = entradas − salidas, y los totales por
--             moneda coinciden con `fdi_dat_movimiento` en la ventana devuelta
--   n=11  R7  por moneda: utilidad_pendiente = utilidad_repartida −
--             utilidad_pagada, y repartos/aportes coinciden con las tablas
--   n=12  R7  aging: reservas_activas coincide con las reservas `activa` y sus
--             días de antigüedad; descuadres coherentes con su propio criterio
--   n=13  R1  `fn_fdi_conciliacion` sigue dando 0 descuadres en toda tienda
--   n=14  (informativa) volumen del módulo
--   n=99  resumen
--
-- NOTA sobre el criterio de pagos de `descuadres` (ver cabecera de
-- 08_reportes.sql): se aplica solo a compras en estado pagada /
-- entrega_parcial / completada / anulada. Aquí se comprueba el criterio tal
-- como quedó implementado, incluido ese filtro, para que el verify detecte
-- cualquier cambio de criterio.
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- Contrato
-- ---------------------------------------------------------------------------
funcs(firma) as (
    values ('public.fn_fdi_reporte_caja(bigint)'),
           ('public.fn_fdi_reporte_compras(bigint,date,date)'),
           ('public.fn_fdi_reporte_costo(bigint,date,date)'),
           ('public.fn_fdi_reporte_cambiario(bigint,date,date)'),
           ('public.fn_fdi_reporte_movimientos(bigint,date,date)'),
           ('public.fn_fdi_reporte_inversores(bigint)'),
           ('public.fn_fdi_reporte_aging(bigint)')
),
resueltas as (
    select f.firma, to_regprocedure(f.firma) as oid from funcs f
),
sobrecargas as (
    select count(*) as n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_fdi_reporte_caja','fn_fdi_reporte_compras',
                         'fn_fdi_reporte_costo','fn_fdi_reporte_cambiario',
                         'fn_fdi_reporte_movimientos','fn_fdi_reporte_inversores',
                         'fn_fdi_reporte_aging')
),
con_forma as (
    select count(*) as n
      from pg_proc p
      join resueltas r on r.oid = p.oid
     where p.prosecdef
       and p.provolatile = 's'
       and pg_get_function_result(p.oid) = 'jsonb'
),
permisos as (
    select (select count(*) from resueltas r
              where r.oid is not null
                and has_function_privilege('authenticated', r.oid, 'EXECUTE')) as con_auth,
           (select count(*) from resueltas r
              where r.oid is not null
                and has_function_privilege('anon', r.oid, 'EXECUTE')) as con_anon
),
con_defaults as (
    select count(*) as n
      from pg_proc p
     where p.oid in (to_regprocedure('public.fn_fdi_reporte_compras(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_costo(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_cambiario(bigint,date,date)'),
                     to_regprocedure('public.fn_fdi_reporte_movimientos(bigint,date,date)'))
       and p.pronargdefaults = 2
),

-- ---------------------------------------------------------------------------
-- Tiendas con datos del módulo (el verify las recorre todas)
-- ---------------------------------------------------------------------------
tiendas as (
    select distinct id_tienda
      from (select id_tienda from public.fdi_dat_saldo
            union all select id_tienda from public.fdi_dat_compra
            union all select id_tienda from public.fdi_dat_movimiento
            union all select id_tienda from public.fdi_dat_inversor
            union all select id_tienda from public.fdi_dat_compra_aporte) x
),

-- ---------------------------------------------------------------------------
-- R2 — caja
-- ---------------------------------------------------------------------------
r2 as (
    select t.id_tienda, public.fn_fdi_reporte_caja(t.id_tienda) as res from tiendas t
),
r2_claves as (
    select r.id_tienda, e.val as k
      from r2 r, jsonb_array_elements(coalesce(r.res->'claves','[]'::jsonb)) e(val)
),
r2_esperado as (
    select s.id_tienda, s.id_cuenta, s.id_medio_pago, s.moneda, s.saldo,
           coalesce((select sum(r.monto)
                       from public.fdi_dat_compra_reserva r
                      where r.id_tienda = s.id_tienda
                        and r.id_cuenta = s.id_cuenta
                        and r.id_medio_pago = s.id_medio_pago
                        and r.moneda = s.moneda
                        and r.estado = 'activa'), 0) as reservado
      from public.fdi_dat_saldo s
),
r2_viol as (
    select c.k
      from r2_claves c
     where abs((c.k->>'disponible')::numeric
               - ((c.k->>'saldo')::numeric - (c.k->>'reservado')::numeric)) > 0.009
        or (c.k->>'reservado')::numeric < -0.004
),
r2_dif as (
    select c.k
      from r2_claves c
     where not exists (
             select 1 from r2_esperado e
              where e.id_tienda = c.id_tienda
                and e.id_cuenta = (c.k->>'id_cuenta')::bigint
                and e.id_medio_pago = (c.k->>'id_medio_pago')::smallint
                and e.moneda = (c.k->>'moneda')
                and abs(e.saldo - (c.k->>'saldo')::numeric) <= 0.009
                and abs(e.reservado - (c.k->>'reservado')::numeric) <= 0.009)
),
r2_falta as (
    select e.id_tienda
      from r2_esperado e
     where not exists (
             select 1 from r2_claves c
              where c.id_tienda = e.id_tienda
                and (c.k->>'id_cuenta')::bigint = e.id_cuenta
                and (c.k->>'id_medio_pago')::smallint = e.id_medio_pago
                and (c.k->>'moneda') = e.moneda)
),

-- ---------------------------------------------------------------------------
-- R3 — compras por estado
-- ---------------------------------------------------------------------------
r3 as (
    select t.id_tienda, public.fn_fdi_reporte_compras(t.id_tienda) as res from tiendas t
),
r3_filas as (
    select r.id_tienda, e.val as f
      from r3 r, jsonb_array_elements(coalesce(r.res->'por_estado','[]'::jsonb)) e(val)
),
r3_esperado as (
    select c.id_tienda, c.estado, c.moneda_total as moneda,
           count(*) as compras,
           round(sum(c.total_mercancia), 2) as facturado,
           round(sum(c.costo_aterrizado), 2) as aterrizado,
           round(sum(coalesce(p.pagado, 0)), 2) as pagado,
           round(sum(coalesce(rs.reservado, 0)), 2) as reservado_activo
      from public.fdi_dat_compra c
      left join lateral (
            select sum(p.monto_eq_total) as pagado
              from public.fdi_dat_compra_pago p
             where p.id_compra = c.id) p on true
      left join lateral (
            select sum(r.monto_eq_total) as reservado
              from public.fdi_dat_compra_reserva r
             where r.id_compra = c.id
               and r.estado = 'activa') rs on true
     group by 1, 2, 3
),
r3_viol as (
    select f.f
      from r3_filas f
     where abs((f.f->>'diferencia')::numeric
               - ((f.f->>'aterrizado')::numeric - (f.f->>'facturado')::numeric)) > 0.009
        or (f.f->>'pagado')::numeric < -0.004
        or (f.f->>'reservado_activo')::numeric < -0.004
),
r3_dif as (
    select f.f
      from r3_filas f
     where not exists (
             select 1 from r3_esperado e
              where e.id_tienda = f.id_tienda
                and e.estado = (f.f->>'estado')
                and e.moneda = (f.f->>'moneda')
                and e.compras = (f.f->>'compras')::bigint
                and abs(e.facturado - (f.f->>'facturado')::numeric) <= 0.009
                and abs(e.aterrizado - (f.f->>'aterrizado')::numeric) <= 0.009
                and abs(e.pagado - (f.f->>'pagado')::numeric) <= 0.009
                and abs(e.reservado_activo - (f.f->>'reservado_activo')::numeric) <= 0.009)
),
r3_falta as (
    select e.id_tienda, e.estado, e.moneda
      from r3_esperado e
     where not exists (
             select 1 from r3_filas f
              where f.id_tienda = e.id_tienda
                and (f.f->>'estado') = e.estado
                and (f.f->>'moneda') = e.moneda)
),

-- ---------------------------------------------------------------------------
-- R4 — costo real contra factura
-- ---------------------------------------------------------------------------
r4 as (
    select t.id_tienda, public.fn_fdi_reporte_costo(t.id_tienda) as res from tiendas t
),
r4_filas as (
    select r.id_tienda, e.val as f
      from r4 r, jsonb_array_elements(coalesce(r.res->'compras','[]'::jsonb)) e(val)
),
r4_esperado as (
    select c.id_tienda, c.id, c.total_mercancia, c.total_ajustes, c.costo_aterrizado,
           case when coalesce(c.total_mercancia, 0) <> 0
                then round((c.costo_aterrizado - c.total_mercancia) / c.total_mercancia * 100, 2)
           end as pct_desvio
      from public.fdi_dat_compra c
),
r4_viol as (
    select f.f
      from r4_filas f
     where abs((f.f->>'aterrizado')::numeric
               - ((f.f->>'mercancia')::numeric + (f.f->>'adicionales')::numeric)) > 0.009
        or ((f.f->>'mercancia')::numeric <> 0
            and abs((f.f->>'pct_desvio')::numeric
                    - round(((f.f->>'aterrizado')::numeric - (f.f->>'mercancia')::numeric)
                            / (f.f->>'mercancia')::numeric * 100, 2)) > 0.009)
        or ((f.f->>'mercancia')::numeric = 0 and (f.f->>'pct_desvio') is not null)
        or (f.f->>'recibido_pct')::numeric < -0.004
        or (f.f->>'recibido_pct')::numeric > 1.004
),
r4_dif as (
    select f.f
      from r4_filas f
     where not exists (
             select 1 from r4_esperado e
              where e.id_tienda = f.id_tienda
                and e.id = (f.f->>'id_compra')::bigint
                and abs(e.total_mercancia - (f.f->>'mercancia')::numeric) <= 0.009
                and abs(e.total_ajustes - (f.f->>'adicionales')::numeric) <= 0.009
                and abs(e.costo_aterrizado - (f.f->>'aterrizado')::numeric) <= 0.009
                and ((e.pct_desvio is null and (f.f->>'pct_desvio') is null)
                     or abs(e.pct_desvio - (f.f->>'pct_desvio')::numeric) <= 0.009))
),
r4_falta as (
    select e.id_tienda, e.id
      from r4_esperado e
     where not exists (
             select 1 from r4_filas f
              where f.id_tienda = e.id_tienda
                and (f.f->>'id_compra')::bigint = e.id)
),

-- ---------------------------------------------------------------------------
-- R5 — diferencias cambiarias
-- ---------------------------------------------------------------------------
r5 as (
    select t.id_tienda, public.fn_fdi_reporte_cambiario(t.id_tienda) as res from tiendas t
),
r5_compras as (
    select r.id_tienda, e.val as c
      from r5 r, jsonb_array_elements(coalesce(r.res->'compras','[]'::jsonb)) e(val)
),
r5_pagos as (
    select c.id_tienda, c.c as compra, p.val as p
      from r5_compras c, jsonb_array_elements(coalesce(c.c->'pagos','[]'::jsonb)) p(val)
),
-- Importes nativos de los pagos agregados por su propia moneda: así se
-- comprueba que el reporte no suma USD con CUP.
r5_pagos_moneda as (
    select c.id_tienda, c.c as compra, m.val as pm
      from r5_compras c, jsonb_array_elements(coalesce(c.c->'pagos_por_moneda','[]'::jsonb)) m(val)
),
r5_pm_esperado as (
    select p.id_tienda, p.id_compra, p.moneda as moneda_pago,
           count(*) as n, round(sum(p.monto), 2) as monto
      from public.fdi_dat_compra_pago p
     group by 1, 2, 3
),
r5_viol_pagos as (
    select p.p
      from r5_pagos p
     where abs((p.p->>'diferencia')::numeric
               - ((p.p->>'equivalente_real')::numeric
                  - (p.p->>'equivalente_a_tasa_factura')::numeric)) > 0.009
        or (p.p->>'signo') is distinct from
           (case when (p.p->>'diferencia')::numeric <= 0 then 'a favor' else 'en contra' end)
),
r5_viol_compras as (
    select c.c
      from r5_compras c
     where abs((c.c->>'diferencia')::numeric
               - ((c.c->>'equivalente_real')::numeric
                  - (c.c->>'equivalente_a_tasa_factura')::numeric)) > 0.009
        or (c.c->>'signo') is distinct from
           (case when (c.c->>'diferencia')::numeric <= 0 then 'a favor' else 'en contra' end)
        or (c.c->>'n_pagos')::bigint
           <> coalesce(jsonb_array_length(c.c->'pagos'), 0)
),
r5_esperado_pagos as (
    select p.id_tienda, p.id_compra, p.id,
           p.monto_eq_total as equivalente_real,
           round(p.monto * c.tasa_factura, 2) as equivalente_a_tasa_factura
      from public.fdi_dat_compra_pago p
      join public.fdi_dat_compra c on c.id = p.id_compra
),
r5_dif as (
    select p.p
      from r5_pagos p
     where not exists (
             select 1 from r5_esperado_pagos e
              where e.id_tienda = p.id_tienda
                and e.id = (p.p->>'id_pago')::bigint
                and abs(e.equivalente_real - (p.p->>'equivalente_real')::numeric) <= 0.009
                and abs(e.equivalente_a_tasa_factura
                        - (p.p->>'equivalente_a_tasa_factura')::numeric) <= 0.009)
),
r5_falta as (
    select e.id_tienda, e.id
      from r5_esperado_pagos e
     where not exists (
             select 1 from r5_pagos p
              where p.id_tienda = e.id_tienda
                and (p.p->>'id_pago')::bigint = e.id)
),
r5_pm_dif as (
    select x.pm
      from r5_pagos_moneda x
     where not exists (
             select 1 from r5_pm_esperado e
              where e.id_tienda = x.id_tienda
                and e.id_compra = (x.compra->>'id_compra')::bigint
                and e.moneda_pago = (x.pm->>'moneda_pago')
                and e.n = (x.pm->>'n')::bigint
                and abs(e.monto - (x.pm->>'monto')::numeric) <= 0.009)
),
r5_pm_falta as (
    select e.id_tienda, e.id_compra, e.moneda_pago
      from r5_pm_esperado e
     where not exists (
             select 1 from r5_pagos_moneda x
              where x.id_tienda = e.id_tienda
                and (x.compra->>'id_compra')::bigint = e.id_compra
                and (x.pm->>'moneda_pago') = e.moneda_pago)
),

-- ---------------------------------------------------------------------------
-- R6 — movimientos por día y usuario
-- ---------------------------------------------------------------------------
r6 as (
    select t.id_tienda, public.fn_fdi_reporte_movimientos(t.id_tienda) as res
      from tiendas t
),
r6_filas as (
    select r.id_tienda, e.val as f
      from r6 r, jsonb_array_elements(coalesce(r.res->'por_dia_usuario','[]'::jsonb)) e(val)
),
r6_totales as (
    select r.id_tienda, e.val as t
      from r6 r, jsonb_array_elements(coalesce(r.res->'totales_por_moneda','[]'::jsonb)) e(val)
),
r6_viol as (
    select f.f
      from r6_filas f
     where abs((f.f->>'neto')::numeric
               - ((f.f->>'entradas')::numeric - (f.f->>'salidas')::numeric)) > 0.009
        or (f.f->>'entradas')::numeric < -0.004
        or (f.f->>'salidas')::numeric < -0.004
        or (f.f->>'n')::bigint < 1
),
r6_esperado as (
    select m.id_tienda, m.moneda,
           count(*) as n,
           round(coalesce(sum(m.monto) filter (where m.monto > 0), 0), 2) as entradas,
           round(coalesce(-(sum(m.monto) filter (where m.monto < 0)), 0), 2) as salidas,
           round(coalesce(sum(m.monto), 0), 2) as neto
      from public.fdi_dat_movimiento m
      join r6 r on r.id_tienda = m.id_tienda
     where m.created_at::date >= (r.res->>'desde')::date
       and m.created_at::date <= (r.res->>'hasta')::date
     group by 1, 2
),
r6_dif as (
    select t.t
      from r6_totales t
     where not exists (
             select 1 from r6_esperado e
              where e.id_tienda = t.id_tienda
                and e.moneda = (t.t->>'moneda')
                and e.n = (t.t->>'n')::bigint
                and abs(e.entradas - (t.t->>'entradas')::numeric) <= 0.009
                and abs(e.salidas - (t.t->>'salidas')::numeric) <= 0.009
                and abs(e.neto - (t.t->>'neto')::numeric) <= 0.009)
),
r6_falta as (
    select e.id_tienda, e.moneda
      from r6_esperado e
     where not exists (
             select 1 from r6_totales t
              where t.id_tienda = e.id_tienda
                and (t.t->>'moneda') = e.moneda)
),
r6_ventana as (
    select count(*) as n
      from r6
     where (res->>'desde') is null
        or (res->>'hasta') is null
        or (res->>'desde')::date > (res->>'hasta')::date
),

-- ---------------------------------------------------------------------------
-- R7 — inversores
-- ---------------------------------------------------------------------------
r7 as (
    select t.id_tienda, public.fn_fdi_reporte_inversores(t.id_tienda) as res
      from tiendas t
),
r7_inv as (
    select r.id_tienda, e.val as i
      from r7 r, jsonb_array_elements(coalesce(r.res->'inversores','[]'::jsonb)) e(val)
),
r7_mon as (
    select i.id_tienda, i.i, m.val as m
      from r7_inv i, jsonb_array_elements(coalesce(i.i->'por_moneda','[]'::jsonb)) m(val)
),
r7_viol as (
    select m.m
      from r7_mon m
     where abs((m.m->>'utilidad_pendiente')::numeric
               - ((m.m->>'utilidad_repartida')::numeric
                  - (m.m->>'utilidad_pagada')::numeric)) > 0.009
        or (m.m->>'aportes_vigentes')::numeric < -0.004
        or (m.m->>'aportes_devueltos')::numeric < -0.004
        or (m.m->>'utilidad_repartida')::numeric < -0.004
),
r7_llaves as (
    select id_tienda, id_inversor, moneda from public.fdi_dat_compra_aporte
    union
    select id_tienda, id_inversor, moneda from public.fdi_dat_inversor_reparto
),
r7_esperado as (
    select k.id_tienda, k.id_inversor, k.moneda,
           round(coalesce((select sum(a.monto) from public.fdi_dat_compra_aporte a
                            where a.id_tienda = k.id_tienda
                              and a.id_inversor = k.id_inversor
                              and a.moneda = k.moneda
                              and a.estado = 'aportado'), 0), 2) as vigentes,
           round(coalesce((select sum(a.monto) from public.fdi_dat_compra_aporte a
                            where a.id_tienda = k.id_tienda
                              and a.id_inversor = k.id_inversor
                              and a.moneda = k.moneda
                              and a.estado = 'devuelto'), 0), 2) as devueltos,
           round(coalesce((select sum(r.monto) from public.fdi_dat_inversor_reparto r
                            where r.id_tienda = k.id_tienda
                              and r.id_inversor = k.id_inversor
                              and r.moneda = k.moneda), 0), 2) as repartida,
           round(coalesce((select sum(r.monto) from public.fdi_dat_inversor_reparto r
                            where r.id_tienda = k.id_tienda
                              and r.id_inversor = k.id_inversor
                              and r.moneda = k.moneda
                              and r.pagado_at is not null), 0), 2) as pagada,
           round(coalesce((select sum(r.monto) from public.fdi_dat_inversor_reparto r
                            where r.id_tienda = k.id_tienda
                              and r.id_inversor = k.id_inversor
                              and r.moneda = k.moneda
                              and r.pagado_at is null), 0), 2) as pendiente
      from r7_llaves k
),
r7_dif as (
    select m.m
      from r7_mon m
     where not exists (
             select 1 from r7_esperado e
              where e.id_tienda = m.id_tienda
                and e.id_inversor = (m.i->>'id_inversor')::bigint
                and e.moneda = (m.m->>'moneda')
                and abs(e.vigentes - (m.m->>'aportes_vigentes')::numeric) <= 0.009
                and abs(e.devueltos - (m.m->>'aportes_devueltos')::numeric) <= 0.009
                and abs(e.repartida - (m.m->>'utilidad_repartida')::numeric) <= 0.009
                and abs(e.pagada - (m.m->>'utilidad_pagada')::numeric) <= 0.009
                and abs(e.pendiente - (m.m->>'utilidad_pendiente')::numeric) <= 0.009)
),
r7_falta as (
    select e.id_tienda, e.id_inversor, e.moneda
      from r7_esperado e
     where not exists (
             select 1 from r7_mon m
              where m.id_tienda = e.id_tienda
                and (m.i->>'id_inversor')::bigint = e.id_inversor
                and (m.m->>'moneda') = e.moneda)
),
r7_inv_falta as (
    select count(*) as n
      from public.fdi_dat_inversor i
     where not exists (
             select 1 from r7_inv x
              where x.id_tienda = i.id_tienda
                and (x.i->>'id_inversor')::bigint = i.id)
),

-- ---------------------------------------------------------------------------
-- Aging y descuadres declarados
-- ---------------------------------------------------------------------------
rag as (
    select t.id_tienda, public.fn_fdi_reporte_aging(t.id_tienda) as res from tiendas t
),
rag_res as (
    select r.id_tienda, e.val as r
      from rag r, jsonb_array_elements(coalesce(r.res->'reservas_activas','[]'::jsonb)) e(val)
),
rag_desc as (
    select r.id_tienda, e.val as d
      from rag r, jsonb_array_elements(coalesce(r.res->'descuadres','[]'::jsonb)) e(val)
),
rag_res_esperado as (
    select r.id_tienda, r.id as id_reserva, r.id_compra, r.monto, r.moneda,
           greatest(0, current_date - r.created_at::date) as dias
      from public.fdi_dat_compra_reserva r
     where r.estado = 'activa'
),
rag_res_viol as (
    select x.r
      from rag_res x
     where (x.r->>'dias_antiguedad')::int < 0
        or (x.r->>'monto')::numeric < -0.004
),
rag_res_dif as (
    select x.r
      from rag_res x
     where not exists (
             select 1 from rag_res_esperado e
              where e.id_tienda = x.id_tienda
                and e.id_reserva = (x.r->>'id_reserva')::bigint
                and abs(e.monto - (x.r->>'monto')::numeric) <= 0.009
                and e.moneda = (x.r->>'moneda')
                and e.dias = (x.r->>'dias_antiguedad')::int)
),
rag_res_falta as (
    select e.id_tienda, e.id_reserva
      from rag_res_esperado e
     where not exists (
             select 1 from rag_res x
              where x.id_tienda = e.id_tienda
                and (x.r->>'id_reserva')::bigint = e.id_reserva)
),
rag_calculo as (
    select c.id_tienda, c.id, c.estado, c.total_financiado,
           round(coalesce((select sum(coalesce(l.costo_linea, l.cantidad * l.costo_unitario))
                             from public.fdi_dat_compra_linea l
                            where l.id_compra = c.id), 0), 2) as lineas,
           round(coalesce((select sum(a.monto_capitalizado)
                             from public.fdi_dat_compra_ajuste a
                            where a.id_compra = c.id
                              and a.origen_pago = 'fondo'), 0), 2) as ajustes_fondo,
           round(coalesce((select sum(p.monto_eq_total)
                             from public.fdi_dat_compra_pago p
                            where p.id_compra = c.id), 0), 2) as pagado
      from public.fdi_dat_compra c
),
rag_desc_esperado as (
    select x.*,
           round(x.total_financiado - (x.lineas + x.ajustes_fondo), 2) as diferencia_financiado,
           round(x.pagado - x.total_financiado, 2) as diferencia_pagos
      from rag_calculo x
),
rag_desc_dif as (
    select d.d
      from rag_desc d
     where not exists (
             select 1 from rag_desc_esperado e
              where e.id_tienda = d.id_tienda
                and e.id = (d.d->>'id_compra')::bigint
                and abs(e.diferencia_financiado - (d.d->>'diferencia_financiado')::numeric) <= 0.009
                and abs(e.diferencia_pagos - (d.d->>'diferencia_pagos')::numeric) <= 0.009
                and abs(e.lineas - (d.d->>'lineas')::numeric) <= 0.009
                and abs(e.ajustes_fondo - (d.d->>'ajustes_fondo')::numeric) <= 0.009
                and abs(e.total_financiado - (d.d->>'total_financiado')::numeric) <= 0.009)
),
rag_desc_falta as (
    select e.id_tienda, e.id
      from rag_desc_esperado e
     where (abs(e.diferencia_financiado) > 0.009
            or (abs(e.diferencia_pagos) > 0.009
                and e.estado in ('pagada','entrega_parcial','completada','anulada')))
       and not exists (
             select 1 from rag_desc d
              where d.id_tienda = e.id_tienda
                and (d.d->>'id_compra')::bigint = e.id)
),
rag_motivo_falta as (
    select count(*) as n
      from rag_desc d
     where (d.d->>'ultimo_motivo') is null
       and exists (select 1 from public.fdi_hist_estado_compra h
                    where h.id_compra = (d.d->>'id_compra')::bigint
                      and h.motivo is not null)
),

-- ---------------------------------------------------------------------------
-- R1 — la conciliación sigue intacta y en cero
-- ---------------------------------------------------------------------------
r1 as (
    select t.id_tienda, public.fn_fdi_conciliacion(t.id_tienda) as res from tiendas t
),
r1_tot as (
    select coalesce(sum((res->>'claves')::int), 0) as claves,
           coalesce(sum((res->>'descuadres')::int), 0) as descuadres,
           coalesce(sum((select count(*)
                           from jsonb_array_elements(coalesce(res->'filas','[]'::jsonb)) e
                          where not coalesce((e->>'ok')::boolean, false))), 0) as filas_no_ok
      from r1
),
r1_firma as (
    select count(*) as n
      from pg_proc p
     where p.oid = to_regprocedure('public.fn_fdi_conciliacion(bigint)')
       and p.pronargs = 1
       and p.provolatile = 's'
       and p.prosecdef
       and pg_get_function_result(p.oid) = 'jsonb'
),

-- ---------------------------------------------------------------------------
-- Volumen (informativo)
-- ---------------------------------------------------------------------------
volumen as (
    select (select count(*) from public.fdi_dat_compra) as compras,
           (select count(*) from public.fdi_dat_movimiento) as movimientos,
           (select count(*) from public.fdi_dat_compra_aporte) as aportes,
           (select count(*) from public.fdi_dat_compra_reserva where estado = 'activa') as reservas_activas,
           (select count(*) from public.fdi_dat_inversor) as inversores,
           (select count(*) from public.fdi_dat_inversor_reparto) as repartos
),

-- Nombres de columna explícitos: la 5.ª es un booleano sin alias en cada rama.
base(n, chequeo, esperado, actual, ok) as (

  -- 1) Las 7 funciones existen con su firma exacta y sin sobrecargas
  select 1 as n, 'funciones_7_firmas' as chequeo,
    'las 7 funciones de reportes registradas con la firma exacta (bigint[/date,date])' as esperado,
    (7 - (select count(*) from resueltas where oid is null))::text || ' de 7 resueltas, '
      || (select n::text from sobrecargas) || ' funciones con esos nombres' as actual,
    (select count(*) from resueltas where oid is null) = 0
    and (select n from sobrecargas) = 7

  union all
  -- 2) STABLE + SECURITY DEFINER + jsonb
  select 2, 'funciones_7_stable_definer_jsonb',
    'las 7 son STABLE, SECURITY DEFINER y devuelven jsonb',
    (select n::text from con_forma) || ' de 7 con esa forma',
    (select n from con_forma) = 7

  union all
  -- 3) Permisos: authenticated sí, anon no
  select 3, 'permisos_authenticated_sin_anon',
    'authenticated puede ejecutar las 7; anon ninguna',
    'authenticated=' || (select con_auth::text from permisos)
      || ', anon=' || (select con_anon::text from permisos),
    (select con_auth from permisos) = 7
    and (select con_anon from permisos) = 0

  union all
  -- 4) DEFAULT de las fechas
  select 4, 'fechas_con_default',
    'los 4 reportes con fechas llevan 2 DEFAULT (p_desde y p_hasta)',
    (select n::text from con_defaults) || ' de 4',
    (select n from con_defaults) = 4

  union all
  -- 5) R1 sigue con su firma
  select 5, 'r1_firma_intacta',
    'fn_fdi_conciliacion(bigint): 1 argumento, STABLE, SECURITY DEFINER, jsonb (08 no la toca)',
    (select n::text from r1_firma) || ' de 1',
    (select n from r1_firma) = 1

  union all
  -- 6) R2: invariante + contra tablas
  select 6, 'r2_disponible_y_reservado',
    'en toda clave: disponible = saldo − reservado, reservado >= 0 y las cifras coinciden con saldo/reservas (una fila por clave de saldo)',
    (select count(*)::text from r2_claves) || ' clave(s), '
      || (select count(*)::text from r2_viol) || ' con aritmética rota, '
      || (select count(*)::text from r2_dif) || ' que no cuadran con las tablas, '
      || (select count(*)::text from r2_falta) || ' clave(s) de saldo sin fila',
    (select count(*) from r2_viol) = 0
    and (select count(*) from r2_dif) = 0
    and (select count(*) from r2_falta) = 0
    and (select count(*) from r2_claves) = (select count(*) from public.fdi_dat_saldo)

  union all
  -- 7) R3: invariante + contra tablas
  select 7, 'r3_diferencia_aterrizado_facturado',
    'por estado y moneda: diferencia = aterrizado − facturado, pagado >= 0 y las cifras coinciden con compras/pagos/reservas',
    (select count(*)::text from r3_filas) || ' fila(s), '
      || (select count(*)::text from r3_viol) || ' con aritmética rota, '
      || (select count(*)::text from r3_dif) || ' que no cuadran con las tablas, '
      || (select count(*)::text from r3_falta) || ' combinación(es) sin fila',
    (select count(*) from r3_viol) = 0
    and (select count(*) from r3_dif) = 0
    and (select count(*) from r3_falta) = 0
    and (select count(*) from r3_filas) = (select count(*) from r3_esperado)

  union all
  -- 8) R4: aterrizado = mercancía + adicionales, pct coherente
  select 8, 'r4_aterrizado_es_mercancia_mas_adicionales',
    'en toda compra: aterrizado = mercancía + adicionales, pct_desvio = (aterrizado−mercancía)/mercancía × 100 (NULL si mercancía = 0) y 1 fila por compra',
    (select count(*)::text from r4_filas) || ' compra(s), '
      || (select count(*)::text from r4_viol) || ' con la suma o el % incoherente, '
      || (select count(*)::text from r4_dif) || ' que no cuadran con la tabla, '
      || (select count(*)::text from r4_falta) || ' compra(s) sin fila',
    (select count(*) from r4_viol) = 0
    and (select count(*) from r4_dif) = 0
    and (select count(*) from r4_falta) = 0
    and (select count(*) from r4_filas) = (select count(*) from r4_esperado)

  union all
  -- 9) R5: diferencia y signo
  select 9, 'r5_diferencia_cambiaria_y_signo',
    'en toda fila (pago y compra): diferencia = equivalente_real − equivalente_a_tasa_factura, con su signo; el equivalente real de cada pago es el de la tabla y los importes nativos se agregan por su propia moneda de pago',
    (select count(*)::text from r5_pagos) || ' pago(s), '
      || (select count(*)::text from r5_viol_pagos) || ' pago(s) incoherente(s), '
      || (select count(*)::text from r5_viol_compras) || ' compra(s) incoherente(s), '
      || (select count(*)::text from r5_dif) || ' que no cuadran con la tabla, '
      || (select count(*)::text from r5_falta) || ' pago(s) sin fila, '
      || (select count(*)::text from r5_pagos_moneda) || ' (compra, moneda de pago) '
      || (select count(*)::text from r5_pm_dif) || ' mal sumadas, '
      || (select count(*)::text from r5_pm_falta) || ' sin fila',
    (select count(*) from r5_viol_pagos) = 0
    and (select count(*) from r5_viol_compras) = 0
    and (select count(*) from r5_dif) = 0
    and (select count(*) from r5_falta) = 0
    and (select count(*) from r5_pm_dif) = 0
    and (select count(*) from r5_pm_falta) = 0

  union all
  -- 10) R6: neto = entradas − salidas y totales contra el libro
  select 10, 'r6_neto_entradas_salidas',
    'en toda fila: neto = entradas − salidas; los totales por moneda coinciden con fdi_dat_movimiento en la ventana devuelta',
    (select count(*)::text from r6_filas) || ' fila(s), '
      || (select count(*)::text from r6_viol) || ' con aritmética rota, '
      || (select count(*)::text from r6_dif) || ' total(es) que no cuadran con el libro, '
      || (select count(*)::text from r6_falta) || ' moneda(s) sin total, '
      || (select n::text from r6_ventana) || ' ventana(s) inválida(s)',
    (select count(*) from r6_viol) = 0
    and (select count(*) from r6_dif) = 0
    and (select count(*) from r6_falta) = 0
    and (select n from r6_ventana) = 0

  union all
  -- 11) R7: pendiente = repartida − pagada, y contra las tablas
  select 11, 'r7_utilidad_pendiente',
    'por inversor y moneda: utilidad_pendiente = utilidad_repartida − utilidad_pagada, y aportes/utilidad coinciden con las tablas',
    (select count(*)::text from r7_mon) || ' (inversor, moneda), '
      || (select count(*)::text from r7_viol) || ' con aritmética rota, '
      || (select count(*)::text from r7_dif) || ' que no cuadran con las tablas, '
      || (select count(*)::text from r7_falta) || ' (inversor, moneda) sin fila, '
      || (select n::text from r7_inv_falta) || ' inversor(es) fuera del reporte',
    (select count(*) from r7_viol) = 0
    and (select count(*) from r7_dif) = 0
    and (select count(*) from r7_falta) = 0
    and (select n from r7_inv_falta) = 0

  union all
  -- 12) Aging: reservas y descuadres
  select 12, 'aging_reservas_y_descuadres',
    'reservas_activas = reservas `activa` con su antigüedad; descuadres = exactamente los que cumplen el criterio, con su último motivo',
    (select count(*)::text from rag_res) || ' reserva(s) activa(s), '
      || (select count(*)::text from rag_res_viol) || ' con dato imposible, '
      || (select count(*)::text from rag_res_dif) || ' que no cuadran con la tabla, '
      || (select count(*)::text from rag_res_falta) || ' sin fila; '
      || (select count(*)::text from rag_desc) || ' descuadre(s), '
      || (select count(*)::text from rag_desc_dif) || ' incoherente(s), '
      || (select count(*)::text from rag_desc_falta) || ' sin listar, '
      || (select n::text from rag_motivo_falta) || ' sin motivo pudiendo tenerlo',
    (select count(*) from rag_res_viol) = 0
    and (select count(*) from rag_res_dif) = 0
    and (select count(*) from rag_res_falta) = 0
    and (select count(*) from rag_desc_dif) = 0
    and (select count(*) from rag_desc_falta) = 0
    and (select n from rag_motivo_falta) = 0

  union all
  -- 13) R1 sigue en cero
  select 13, 'r1_conciliacion_en_cero',
    'fn_fdi_conciliacion: 0 descuadres y ninguna fila con ok = false en toda tienda',
    (select claves::text || ' clave(s), ' || descuadres::text || ' descuadre(s), '
            || filas_no_ok::text || ' fila(s) no ok'
       from r1_tot),
    (select descuadres = 0 and filas_no_ok = 0 and claves > 0 from r1_tot)

  union all
  -- 14) (informativa) volumen
  select 14, 'volumen_modulo',
    'foto de datos, no un fallo',
    'compras=' || compras::text
      || ', movimientos=' || movimientos::text
      || ', aportes=' || aportes::text
      || ', reservas_activas=' || reservas_activas::text
      || ', inversores=' || inversores::text
      || ', repartos=' || repartos::text
      || ', tiendas=' || (select count(*)::text from tiendas),
    true
    from volumen
)

-- 99) Resumen: cuenta las filas con ok = false (las informativas siempre ok).
select * from base
union all
select 99 as n, 'RESUMEN' as chequeo,
       '0 fallos' as esperado,
       (select count(*)::text from base where not ok) || ' fallo(s) de '
         || (select count(*)::text from base) || ' comprobaciones' as actual,
       (select count(*) = 0 from base where not ok) as ok
  from (select 1) z
order by n;