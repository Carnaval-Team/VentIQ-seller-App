-- ============================================================================
-- verify/09_pendientes.sql — Fase 9: pendientes, detalle, histórico de
-- recepciones y facturas (09_pendientes.sql)
--
-- REQUIERE: 09_pendientes.sql aplicado en `newa` (qhprswhhfasrikhawjoz).
--
-- SOLO LECTURA: SELECT / pg_catalog / information_schema y llamadas a las 4
-- funciones del panel (STABLE + SECURITY DEFINER, no escriben). Ni DDL ni DML.
-- UNA sola sentencia (README, regla 8): un CTE no sobrevive a otra sentencia,
-- así que el resumen va como fila UNION ALL con n = 99.
--
-- Comprobaciones de CONTRATO (n = 1..4):
--   n=1  las 4 funciones existen con su firma exacta y sin sobrecargas
--   n=2  las 4 son STABLE, SECURITY DEFINER y devuelven jsonb
--   n=3  `authenticated` puede ejecutar las 4 y `anon` ninguna
--   n=4  DEFAULT: panel 1 (p_orden), histórico y facturas 2 (p_desde/p_hasta)
--
-- Comprobaciones de INVARIANTE (el criterio de salida del plan, n = 5..11):
--   n=5   el panel lista EXACTAMENTE las compras abiertas: ninguna
--         `completada` / `cancelada` / `anulada`, y ninguna abierta se queda
--         fuera (recorriendo todas las tiendas con datos)
--   n=6   por compra del panel: lineas, pedido, recibido, monto_total,
--         monto_pendiente, dias_antiguedad, dias_sin_movimiento y
--         ultima_recepcion coinciden con las tablas; monto_pendiente >= 0;
--         recibido_pct en [0,1] y coherente con pedido/recibido
--   n=7   el `monto_pendiente` (y el `recibido`) del panel = lo que devuelve
--         el detalle de esa misma compra, y la cabecera del detalle = Σ de sus
--         propias líneas
--   n=8   en TODA línea (de toda compra): pendiente = cantidad − recibido
--         (acotado a 0), monto_pendiente = pendiente × costo_unitario (±0,01)
--         y `recibido` coincide con `fdi_dat_compra_recepcion_linea`
--   n=9   el orden pedido se cumple: 'antiguedad' no crece en días y 'monto'
--         no crece en monto_pendiente; y cada respuesta declara su `orden`
--   n=10  con los datos de `newa`: hay compras abiertas (la 3 y la 68 entre
--         ellas) y el panel de la tienda 9 las lista; ninguna compra
--         `completada` de esa tienda aparece en su panel
--   n=11  el detalle de una compra SIN recepciones da recibido = 0 y
--         recibido_pct = 0 en la cabecera y en todas sus líneas
--
-- Comprobaciones de AGREGADO (n = 12..13):
--   n=12  histórico de recepciones: cada fila coincide con las tablas y sus
--         `totales_por_moneda` son la suma de las filas DE ESA MONEDA (no una
--         suma de monedas distintas)
--   n=13  facturas: todas las compras de la tienda están (incluidas las
--         cerradas), cada fila coincide con las tablas (total_factura,
--         aterrizado, pagado, recepciones, recibido_pct, estado_recepcion) y
--         sus `totales_por_moneda` son la suma de las filas de esa moneda
--
--   n=14  (informativa) volumen del módulo
--   n=99  resumen
--
-- LÍMITE HONESTO de n=12/n=13: hoy TODA la data del módulo está en USD, así
-- que una suma que mezclara monedas daría el mismo número que la suma por
-- moneda. Lo que se comprueba es la estructura: cada total se compara contra
-- las filas de SU moneda y el número de totales tiene que ser el de monedas
-- distintas. En cuanto exista una segunda moneda, esa comparación sí distingue
-- y detecta la suma cruzada. No se maquilla con un chequeo que hoy no puede
-- fallar.
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- Contrato
-- ---------------------------------------------------------------------------
funcs(firma) as (
    values ('public.fn_fdi_pendientes_panel(bigint,text)'),
           ('public.fn_fdi_pendientes_detalle(bigint,bigint)'),
           ('public.fn_fdi_recepciones_historial(bigint,date,date)'),
           ('public.fn_fdi_facturas(bigint,date,date)')
),
resueltas as (
    select f.firma, to_regprocedure(f.firma) as oid from funcs f
),
sobrecargas as (
    select count(*) as n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_fdi_pendientes_panel','fn_fdi_pendientes_detalle',
                         'fn_fdi_recepciones_historial','fn_fdi_facturas')
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
    select (select count(*) from pg_proc p
             where p.oid = to_regprocedure('public.fn_fdi_pendientes_panel(bigint,text)')
               and p.pronargdefaults = 1) as panel,
           (select count(*) from pg_proc p
             where p.oid in (to_regprocedure('public.fn_fdi_recepciones_historial(bigint,date,date)'),
                             to_regprocedure('public.fn_fdi_facturas(bigint,date,date)'))
               and p.pronargdefaults = 2) as con_fechas
),

-- ---------------------------------------------------------------------------
-- Universo de tiendas con datos del módulo
-- ---------------------------------------------------------------------------
tiendas as (
    select id_tienda from public.fdi_dat_compra
    union
    select id_tienda from public.fdi_dat_compra_recepcion
),

-- ---------------------------------------------------------------------------
-- Panel: las dos órdenes, y las filas de cada respuesta
-- ---------------------------------------------------------------------------
estados_abiertos as (
    select unnest(array['creada','reservada','pagada','entrega_parcial']) as estado
),
panel_ant as (
    select t.id_tienda, public.fn_fdi_pendientes_panel(t.id_tienda) as res from tiendas t
),
panel_mon as (
    select t.id_tienda, public.fn_fdi_pendientes_panel(t.id_tienda, 'monto') as res
      from tiendas t
),
panel_filas as (
    select p.id_tienda, e.val as f
      from panel_ant p,
           jsonb_array_elements(coalesce(p.res -> 'compras', '[]'::jsonb)) e(val)
),
panel_ord_ant as (
    select p.id_tienda, e.ord,
           (e.val ->> 'dias_antiguedad')::numeric as dias
      from panel_ant p,
           jsonb_array_elements(coalesce(p.res -> 'compras', '[]'::jsonb)) with ordinality e(val, ord)
),
panel_ord_mon as (
    select p.id_tienda, e.ord,
           (e.val ->> 'monto_pendiente')::numeric as monto
      from panel_mon p,
           jsonb_array_elements(coalesce(p.res -> 'compras', '[]'::jsonb)) with ordinality e(val, ord)
),
panel_orden_clave as (
    select (select count(*) from panel_ant p
             where (p.res ->> 'orden') is distinct from 'antiguedad') as mal_ant,
           (select count(*) from panel_mon p
             where (p.res ->> 'orden') is distinct from 'monto') as mal_mon,
           (select count(*) from panel_ant p
             where (p.res ->> 'generado_at') is null) as sin_generado
),

-- ---------------------------------------------------------------------------
-- Esperado del panel, calculado directo contra las tablas
-- ---------------------------------------------------------------------------
lineas_abiertas as (
    select c.id_tienda,
           c.id as id_compra,
           l.id as id_linea,
           l.cantidad,
           l.costo_unitario,
           coalesce(l.costo_linea, l.cantidad * l.costo_unitario) as costo_linea,
           coalesce((select sum(rl.cantidad_recibida)
                       from public.fdi_dat_compra_recepcion_linea rl
                      where rl.id_compra_linea = l.id), 0) as recibido
      from public.fdi_dat_compra c
      left join public.fdi_dat_compra_linea l on l.id_compra = c.id
     where c.estado in (select estado from estados_abiertos)
),
esperado_panel as (
    select x.id_tienda,
           x.id_compra,
           count(x.id_linea) as lineas,
           round(coalesce(sum(x.cantidad), 0), 4) as pedido,
           round(coalesce(sum(x.recibido), 0), 4) as recibido,
           round(coalesce(sum(x.costo_linea), 0), 2) as monto_total,
           round(coalesce(sum(greatest(0, x.cantidad - x.recibido) * x.costo_unitario), 0), 2)
               as monto_pendiente
      from lineas_abiertas x
     group by 1, 2
),
esperado_full as (
    select e.id_tienda,
           e.id_compra,
           e.lineas,
           e.pedido,
           e.recibido,
           e.monto_total,
           e.monto_pendiente,
           c.estado,
           c.moneda_total,
           greatest(0, current_date - c.created_at::date) as dias_antiguedad,
           ur.ultima_recepcion,
           greatest(0, current_date
                       - coalesce(ur.ultima_recepcion::date, c.created_at::date)) as dias_sin_movimiento
      from esperado_panel e
      join public.fdi_dat_compra c on c.id = e.id_compra
      left join lateral (
            select max(r.created_at) as ultima_recepcion
              from public.fdi_dat_compra_recepcion r
             where r.id_compra = c.id) ur on true
),
panel_falta as (
    select e.id_tienda, e.id_compra
      from esperado_full e
     where not exists (
             select 1 from panel_filas p
              where p.id_tienda = e.id_tienda
                and (p.f ->> 'id_compra')::bigint = e.id_compra)
),
panel_sobra as (
    select p.id_tienda, (p.f ->> 'id_compra')::bigint as id_compra
      from panel_filas p
     where not exists (
             select 1 from esperado_full e
              where e.id_tienda = p.id_tienda
                and e.id_compra = (p.f ->> 'id_compra')::bigint)
),
panel_estado_cerrado as (
    select p.f
      from panel_filas p
     where (p.f ->> 'estado') not in (select estado from estados_abiertos)
),
panel_aritmetica as (
    select p.f
      from panel_filas p
     where (p.f ->> 'monto_pendiente')::numeric < -0.004
        or (p.f ->> 'recibido_pct')::numeric < -0.000001
        or (p.f ->> 'recibido_pct')::numeric > 1.000001
        or (p.f ->> 'dias_antiguedad')::int < 0
        or (p.f ->> 'dias_sin_movimiento')::int < 0
),
panel_cuadra as (
    select p.f
      from panel_filas p
     where not exists (
             select 1
               from esperado_full e
              where e.id_tienda = p.id_tienda
                and e.id_compra = (p.f ->> 'id_compra')::bigint
                and e.estado = (p.f ->> 'estado')
                and e.moneda_total = (p.f ->> 'moneda')
                and e.lineas = (p.f ->> 'lineas')::bigint
                and abs(e.pedido - (p.f ->> 'pedido')::numeric) <= 0.009
                and abs(e.recibido - (p.f ->> 'recibido')::numeric) <= 0.009
                and abs(e.monto_total - (p.f ->> 'monto_total')::numeric) <= 0.009
                and abs(e.monto_pendiente - (p.f ->> 'monto_pendiente')::numeric) <= 0.009
                and e.dias_antiguedad = (p.f ->> 'dias_antiguedad')::int
                and e.dias_sin_movimiento = (p.f ->> 'dias_sin_movimiento')::int
                and ((e.ultima_recepcion is null and (p.f ->> 'ultima_recepcion') is null)
                     or (e.ultima_recepcion is not null
                         and (p.f ->> 'ultima_recepcion')::timestamptz = e.ultima_recepcion)))
),
panel_pct_viol as (
    select p.f
      from panel_filas p
     where abs((p.f ->> 'recibido_pct')::numeric
               - (case when (p.f ->> 'pedido')::numeric > 0
                       then least(1, (p.f ->> 'recibido')::numeric / (p.f ->> 'pedido')::numeric)
                       else 0 end)) > 0.000001
),

-- ---------------------------------------------------------------------------
-- Detalle: una llamada por compra, y sus líneas
-- ---------------------------------------------------------------------------
detalle_todas as (
    select c.id_tienda,
           c.id as id_compra,
           public.fn_fdi_pendientes_detalle(c.id_tienda, c.id) as det
      from public.fdi_dat_compra c
),
detalle_lineas as (
    select d.id_tienda,
           d.id_compra,
           e.val as l
      from detalle_todas d,
           jsonb_array_elements(coalesce(d.det -> 'lineas', '[]'::jsonb)) e(val)
),
detalle_cabecera as (
    select d.id_tienda, d.id_compra, d.det -> 'compra' as cab from detalle_todas d
),
detalle_vs_panel as (
    select p.f
      from panel_filas p
     where not exists (
             select 1
               from detalle_cabecera d
              where d.id_tienda = p.id_tienda
                and d.id_compra = (p.f ->> 'id_compra')::bigint
                and abs((d.cab ->> 'monto_pendiente')::numeric
                        - (p.f ->> 'monto_pendiente')::numeric) <= 0.009
                and abs((d.cab ->> 'recibido')::numeric
                        - (p.f ->> 'recibido')::numeric) <= 0.009
                and (d.cab ->> 'lineas')::bigint = (p.f ->> 'lineas')::bigint)
),
detalle_suma_lineas as (
    select d.id_tienda,
           d.id_compra,
           round(coalesce(sum((e.val ->> 'monto_pendiente')::numeric), 0), 2) as suma
      from detalle_todas d,
           jsonb_array_elements(coalesce(d.det -> 'lineas', '[]'::jsonb)) e(val)
     group by 1, 2
),
detalle_suma_viol as (
    select c.cab
      from detalle_cabecera c
      join detalle_suma_lineas s on s.id_tienda = c.id_tienda and s.id_compra = c.id_compra
     where abs(s.suma - (c.cab ->> 'monto_pendiente')::numeric) > 0.009
),
detalle_viol as (
    select l as fila
      from detalle_lineas
     where (l ->> 'pendiente')::numeric < -0.004
        or (l ->> 'monto_pendiente')::numeric < -0.004
        or abs((l ->> 'monto_pendiente')::numeric
               - round((l ->> 'pendiente')::numeric * (l ->> 'costo_unitario')::numeric, 2)) > 0.009
        or (l ->> 'dias_sin_movimiento')::int < 0
),
detalle_falta_tabla as (
    select x.id as id_linea
      from public.fdi_dat_compra_linea x
     where not exists (
             select 1 from detalle_lineas l
              where (l.l ->> 'id_compra_linea')::bigint = x.id)
),
linea_esperada as (
    select l.id as id_linea,
           l.cantidad,
           l.costo_unitario,
           coalesce((select sum(rl.cantidad_recibida)
                       from public.fdi_dat_compra_recepcion_linea rl
                      where rl.id_compra_linea = l.id), 0) as recibido
      from public.fdi_dat_compra_linea l
),
linea_viol as (
    select l.l as fila
      from detalle_lineas l
      join linea_esperada e on e.id_linea = (l.l ->> 'id_compra_linea')::bigint
     where abs((l.l ->> 'recibido')::numeric - e.recibido) > 0.0001
        or abs((l.l ->> 'cantidad')::numeric - e.cantidad) > 0.0001
        or abs((l.l ->> 'pendiente')::numeric
               - greatest(0, e.cantidad - e.recibido)) > 0.0001
        or abs((l.l ->> 'monto_pendiente')::numeric
               - round(greatest(0, e.cantidad - e.recibido) * e.costo_unitario, 2)) > 0.009
),

-- ---------------------------------------------------------------------------
-- Orden
-- ---------------------------------------------------------------------------
orden_ant_viol as (
    select 1 as x
      from (select id_tienda, ord,
                   dias,
                   lag(dias) over (partition by id_tienda order by ord) as prev
              from panel_ord_ant) y
     where prev is not null and dias > prev + 0.000001
),
orden_mon_viol as (
    select 1 as x
      from (select id_tienda, ord,
                   monto,
                   lag(monto) over (partition by id_tienda order by ord) as prev
              from panel_ord_mon) y
     where prev is not null and monto > prev + 0.009
),

-- ---------------------------------------------------------------------------
-- Datos de `newa`: tienda 9 con sus abiertas (3, 67, 68) y ninguna cerrada
-- ---------------------------------------------------------------------------
panel9 as (
    select res from panel_ant where id_tienda = 9
),
panel9_filas as (
    select e.val as f
      from panel9 p, jsonb_array_elements(coalesce(p.res -> 'compras', '[]'::jsonb)) e(val)
),
abiertas_esperadas_newa as (
    select c.id
      from public.fdi_dat_compra c
     where c.id in (3, 68)
       and c.estado in (select estado from estados_abiertos)
),
newa_falta as (
    select a.id
      from abiertas_esperadas_newa a
     where not exists (
             select 1 from panel9_filas p
              where (p.f ->> 'id_compra')::bigint = a.id)
),
newa_cerrada_en_panel as (
    select p.f
      from panel9_filas p
      join public.fdi_dat_compra c on c.id = (p.f ->> 'id_compra')::bigint
     where c.estado in ('completada','cancelada','anulada')
),

-- ---------------------------------------------------------------------------
-- Detalle de una compra sin recepciones: recibido = 0
-- ---------------------------------------------------------------------------
sin_recepcion as (
    select c.id_tienda, c.id as id_compra
      from public.fdi_dat_compra c
     where c.estado in (select estado from estados_abiertos)
       and not exists (select 1 from public.fdi_dat_compra_recepcion r
                        where r.id_compra = c.id)
),
sin_recepcion_det as (
    select s.id_tienda,
           s.id_compra,
           public.fn_fdi_pendientes_detalle(s.id_tienda, s.id_compra) as det
      from sin_recepcion s
),
sin_recepcion_viol as (
    select d.det
      from sin_recepcion_det d
     where (d.det -> 'compra' ->> 'recibido')::numeric <> 0
        or (d.det -> 'compra' ->> 'recibido_pct')::numeric <> 0
        or exists (
             select 1
               from jsonb_array_elements(coalesce(d.det -> 'lineas', '[]'::jsonb)) e(val)
              where (e.val ->> 'recibido')::numeric <> 0)
),

-- ---------------------------------------------------------------------------
-- Histórico de recepciones
-- ---------------------------------------------------------------------------
hist as (
    select t.id_tienda, public.fn_fdi_recepciones_historial(t.id_tienda) as res
      from tiendas t
),
hist_filas as (
    select h.id_tienda, e.val as f
      from hist h, jsonb_array_elements(coalesce(h.res -> 'recepciones', '[]'::jsonb)) e(val)
),
hist_tot as (
    select h.id_tienda, e.val as t
      from hist h, jsonb_array_elements(coalesce(h.res -> 'totales_por_moneda', '[]'::jsonb)) e(val)
),
hist_esperado as (
    select r.id_tienda,
           r.id as id_recepcion,
           r.id_operacion,
           r.moneda,
           r.monto_valorizado,
           r.monto_importadora,
           r.created_at::date as fecha,
           (select count(*) from public.fdi_dat_compra_recepcion_linea rl
             where rl.id_compra_recepcion = r.id) as lineas,
           (select coalesce(sum(rl.cantidad_recibida), 0)
              from public.fdi_dat_compra_recepcion_linea rl
             where rl.id_compra_recepcion = r.id) as cantidad,
           (select e.estado from public.app_dat_estado_operacion e
             where e.id_operacion = r.id_operacion order by e.id desc limit 1) as estado_operacion
      from public.fdi_dat_compra_recepcion r
),
hist_dif as (
    select h.f
      from hist_filas h
     where not exists (
             select 1 from hist_esperado e
              where e.id_tienda = h.id_tienda
                and e.id_recepcion = (h.f ->> 'id_recepcion')::bigint
                and e.id_operacion = (h.f ->> 'id_operacion')::bigint
                and e.fecha = (h.f ->> 'fecha')::date
                and abs(e.monto_valorizado - (h.f ->> 'monto_valorizado')::numeric) <= 0.009
                and abs(e.monto_importadora - (h.f ->> 'monto_importadora')::numeric) <= 0.009
                and e.lineas = (h.f ->> 'lineas')::bigint
                and abs(e.cantidad - (h.f ->> 'cantidad_recibida')::numeric) <= 0.0001
                and e.moneda is not distinct from (h.f ->> 'moneda')
                and e.estado_operacion is not distinct from (h.f ->> 'estado_operacion')::int)
),
hist_falta as (
    select e.id_tienda, e.id_recepcion
      from hist_esperado e
     where not exists (
             select 1 from hist_filas h
              where h.id_tienda = e.id_tienda
                and (h.f ->> 'id_recepcion')::bigint = e.id_recepcion)
),
hist_tot_esperado as (
    select e.id_tienda,
           e.moneda,
           count(*) as recepciones,
           round(sum(e.monto_valorizado), 2) as monto_valorizado,
           round(sum(e.monto_importadora), 2) as monto_importadora,
           round(sum(e.cantidad), 4) as cantidad
      from hist_esperado e
     group by 1, 2
),
hist_tot_dif as (
    select t.t
      from hist_tot t
     where not exists (
             select 1 from hist_tot_esperado e
              where e.id_tienda = t.id_tienda
                and e.moneda is not distinct from (t.t ->> 'moneda')
                and e.recepciones = (t.t ->> 'recepciones')::bigint
                and abs(e.monto_valorizado - (t.t ->> 'monto_valorizado')::numeric) <= 0.009
                and abs(e.monto_importadora - (t.t ->> 'monto_importadora')::numeric) <= 0.009
                and abs(e.cantidad - (t.t ->> 'cantidad_recibida')::numeric) <= 0.0001)
),
hist_tot_falta as (
    select e.id_tienda, e.moneda
      from hist_tot_esperado e
     where not exists (
             select 1 from hist_tot t
              where t.id_tienda = e.id_tienda
                and e.moneda is not distinct from (t.t ->> 'moneda'))
),

-- ---------------------------------------------------------------------------
-- Facturas
-- ---------------------------------------------------------------------------
fact as (
    select t.id_tienda, public.fn_fdi_facturas(t.id_tienda) as res from tiendas t
),
fact_filas as (
    select f.id_tienda, e.val as f
      from fact f, jsonb_array_elements(coalesce(f.res -> 'facturas', '[]'::jsonb)) e(val)
),
fact_tot as (
    select f.id_tienda, e.val as t
      from fact f, jsonb_array_elements(coalesce(f.res -> 'totales_por_moneda', '[]'::jsonb)) e(val)
),
fact_esperado as (
    select c.id_tienda,
           c.id as id_compra,
           c.numero_factura,
           c.estado,
           c.moneda_total,
           round(c.total_mercancia, 2) as total_factura,
           round(c.costo_aterrizado, 2) as aterrizado,
           round(coalesce((select sum(p.monto_eq_total)
                             from public.fdi_dat_compra_pago p
                            where p.id_compra = c.id), 0), 2) as pagado,
           (select count(*) from public.fdi_dat_compra_recepcion r
             where r.id_compra = c.id) as recepciones,
           (select max(r.created_at) from public.fdi_dat_compra_recepcion r
             where r.id_compra = c.id) as ultima_recepcion,
           round(coalesce((select sum(l.cantidad)
                             from public.fdi_dat_compra_linea l
                            where l.id_compra = c.id), 0), 4) as pedido,
           round(coalesce((select sum(rl.cantidad_recibida)
                             from public.fdi_dat_compra_recepcion_linea rl
                             join public.fdi_dat_compra_linea l on l.id = rl.id_compra_linea
                            where l.id_compra = c.id), 0), 4) as recibido
      from public.fdi_dat_compra c
),
fact_dif as (
    select f.f
      from fact_filas f
     where not exists (
             select 1 from fact_esperado e
              where e.id_tienda = f.id_tienda
                and e.id_compra = (f.f ->> 'id_compra')::bigint
                and e.numero_factura is not distinct from (f.f ->> 'numero_factura')
                and e.estado = (f.f ->> 'estado')
                and e.moneda_total = (f.f ->> 'moneda')
                and abs(e.total_factura - (f.f ->> 'total_factura')::numeric) <= 0.009
                and abs(e.aterrizado - (f.f ->> 'aterrizado')::numeric) <= 0.009
                and abs(e.pagado - (f.f ->> 'pagado')::numeric) <= 0.009
                and e.recepciones = (f.f ->> 'recepciones')::bigint
                and abs((f.f ->> 'recibido_pct')::numeric
                        - (case when e.pedido > 0 then least(1, e.recibido / e.pedido) else 0 end))
                    <= 0.000001
                and (f.f ->> 'estado_recepcion') =
                    (case when e.recibido <= 0 then 'sin recibir'
                          when e.pedido > 0 and e.recibido >= e.pedido then 'completa'
                          else 'parcial' end)
                and ((e.ultima_recepcion is null and (f.f ->> 'ultima_recepcion') is null)
                     or (e.ultima_recepcion is not null
                         and (f.f ->> 'ultima_recepcion')::timestamptz = e.ultima_recepcion)))
),
fact_falta as (
    select e.id_tienda, e.id_compra
      from fact_esperado e
     where not exists (
             select 1 from fact_filas f
              where f.id_tienda = e.id_tienda
                and (f.f ->> 'id_compra')::bigint = e.id_compra)
),
fact_estado_recepcion_viol as (
    select f.f
      from fact_filas f
     where (f.f ->> 'estado_recepcion') not in ('sin recibir','parcial','completa')
        or ((f.f ->> 'recibido_pct')::numeric = 0
            and (f.f ->> 'estado_recepcion') <> 'sin recibir')
        or ((f.f ->> 'recibido_pct')::numeric = 1
            and (f.f ->> 'recepciones')::bigint > 0
            and (f.f ->> 'estado_recepcion') <> 'completa')
        or ((f.f ->> 'recibido_pct')::numeric > 0
            and (f.f ->> 'recibido_pct')::numeric < 1
            and (f.f ->> 'estado_recepcion') <> 'parcial')
),
fact_completadas as (
    select count(*) as n
      from fact_filas f
      join public.fdi_dat_compra c on c.id = (f.f ->> 'id_compra')::bigint
     where c.estado = 'completada'
),
fact_tot_esperado as (
    select e.id_tienda,
           e.moneda_total as moneda,
           count(*) as compras,
           round(sum(e.total_factura), 2) as total_factura,
           round(sum(e.aterrizado), 2) as aterrizado,
           round(sum(e.pagado), 2) as pagado
      from fact_esperado e
     group by 1, 2
),
fact_tot_dif as (
    select t.t
      from fact_tot t
     where not exists (
             select 1 from fact_tot_esperado e
              where e.id_tienda = t.id_tienda
                and e.moneda is not distinct from (t.t ->> 'moneda')
                and e.compras = (t.t ->> 'compras')::bigint
                and abs(e.total_factura - (t.t ->> 'total_factura')::numeric) <= 0.009
                and abs(e.aterrizado - (t.t ->> 'aterrizado')::numeric) <= 0.009
                and abs(e.pagado - (t.t ->> 'pagado')::numeric) <= 0.009)
),
fact_tot_falta as (
    select e.id_tienda, e.moneda
      from fact_tot_esperado e
     where not exists (
             select 1 from fact_tot t
              where t.id_tienda = e.id_tienda
                and e.moneda is not distinct from (t.t ->> 'moneda'))
),

-- ---------------------------------------------------------------------------
-- Volumen (informativo)
-- ---------------------------------------------------------------------------
volumen as (
    select (select count(*) from public.fdi_dat_compra
             where estado in (select estado from estados_abiertos)) as compras_abiertas,
           (select count(*)
              from public.fdi_dat_compra c
              join public.fdi_dat_compra_linea l on l.id_compra = c.id
             where c.estado in (select estado from estados_abiertos)
               and coalesce((select sum(rl.cantidad_recibida)
                               from public.fdi_dat_compra_recepcion_linea rl
                              where rl.id_compra_linea = l.id), 0) < l.cantidad)
               as lineas_pendientes,
           (select count(*) from public.fdi_dat_compra_recepcion) as recepciones,
           (select count(*) from public.fdi_dat_compra) as facturas
),

-- Nombres de columna explícitos: la 5.a es un booleano sin alias en cada rama.
base(n, chequeo, esperado, actual, ok) as (

  -- 1) Las 4 funciones existen con su firma exacta y sin sobrecargas
  select 1 as n, 'funciones_4_firmas' as chequeo,
    'las 4 funciones de la fase 9 registradas con la firma exacta' as esperado,
    (4 - (select count(*) from resueltas where oid is null))::text || ' de 4 resueltas, '
      || (select n::text from sobrecargas) || ' funciones con esos nombres' as actual,
    (select count(*) from resueltas where oid is null) = 0
    and (select n from sobrecargas) = 4

  union all
  -- 2) STABLE + SECURITY DEFINER + jsonb
  select 2, 'funciones_4_stable_definer_jsonb',
    'las 4 son STABLE, SECURITY DEFINER y devuelven jsonb',
    (select n::text from con_forma) || ' de 4 con esa forma',
    (select n from con_forma) = 4

  union all
  -- 3) Permisos: authenticated sí, anon no
  select 3, 'permisos_authenticated_sin_anon',
    'authenticated puede ejecutar las 4; anon ninguna',
    'authenticated=' || (select con_auth::text from permisos)
      || ', anon=' || (select con_anon::text from permisos),
    (select con_auth from permisos) = 4
    and (select con_anon from permisos) = 0

  union all
  -- 4) DEFAULT
  select 4, 'defaults_panel_y_fechas',
    'panel con 1 DEFAULT (p_orden); histórico y facturas con 2 (p_desde, p_hasta)',
    'panel=' || (select panel::text from con_defaults)
      || ', con fechas=' || (select con_fechas::text from con_defaults) || ' de 2',
    (select panel from con_defaults) = 1
    and (select con_fechas from con_defaults) = 2

  union all
  -- 5) El panel lista exactamente las compras abiertas
  select 5, 'panel_solo_compras_abiertas',
    'el panel lista exactamente las compras en creada/reservada/pagada/entrega_parcial: ninguna completa/cancelada/anulada y ninguna abierta fuera',
    (select count(*)::text from panel_filas) || ' fila(s), '
      || (select count(*)::text from panel_estado_cerrado) || ' con estado cerrado, '
      || (select count(*)::text from panel_sobra) || ' que no están abiertas, '
      || (select count(*)::text from panel_falta) || ' abierta(s) sin listar',
    (select count(*) from panel_estado_cerrado) = 0
    and (select count(*) from panel_sobra) = 0
    and (select count(*) from panel_falta) = 0
    and (select count(*) from panel_filas) = (select count(*) from esperado_full)

  union all
  -- 6) Aritmética del panel contra las tablas
  select 6, 'panel_cifras_contra_tablas',
    'por compra abierta: lineas/pedido/recibido/monto_total/monto_pendiente y los días coinciden con las tablas; monto_pendiente >= 0; recibido_pct en [0,1] y = recibido/pedido',
    (select count(*)::text from panel_filas) || ' fila(s), '
      || (select count(*)::text from panel_aritmetica) || ' con imposibles, '
      || (select count(*)::text from panel_cuadra) || ' que no cuadran con las tablas, '
      || (select count(*)::text from panel_pct_viol) || ' con pct incoherente',
    (select count(*) from panel_aritmetica) = 0
    and (select count(*) from panel_cuadra) = 0
    and (select count(*) from panel_pct_viol) = 0

  union all
  -- 7) Panel vs detalle vs líneas
  select 7, 'panel_cuadra_con_detalle',
    'el monto_pendiente y el recibido del panel = los del detalle de esa compra, y la cabecera del detalle suma sus propias líneas',
    (select count(*)::text from panel_filas) || ' compra(s) en el panel, '
      || (select count(*)::text from detalle_vs_panel) || ' que no cuadran con su detalle, '
      || (select count(*)::text from detalle_suma_viol) || ' detalle(s) cuya cabecera no suma sus líneas',
    (select count(*) from detalle_vs_panel) = 0
    and (select count(*) from detalle_suma_viol) = 0

  union all
  -- 8) pendiente = comprado − recibido en TODA línea
  select 8, 'pendiente_es_comprado_menos_recibido',
    'en toda línea: pendiente = cantidad − recibido (acotado a 0), monto_pendiente = pendiente × costo_unitario (±0,01) y el recibido coincide con la tabla',
    (select count(*)::text from detalle_lineas) || ' línea(s), '
      || (select count(*)::text from detalle_viol) || ' con aritmética rota, '
      || (select count(*)::text from linea_viol) || ' que no cuadran con la tabla, '
      || (select count(*)::text from detalle_falta_tabla) || ' línea(s) de la tabla sin fila en el detalle',
    (select count(*) from detalle_viol) = 0
    and (select count(*) from linea_viol) = 0
    and (select count(*) from detalle_falta_tabla) = 0
    and (select count(*) from detalle_lineas) = (select count(*) from public.fdi_dat_compra_linea)

  union all
  -- 9) El orden pedido se cumple
  select 9, 'orden_antiguedad_y_monto',
    'p_orden = antiguedad devuelve días no crecientes; p_orden = monto devuelve monto_pendiente no creciente; cada respuesta declara su orden',
    (select count(*)::text from orden_ant_viol) || ' quiebre(s) en antiguedad, '
      || (select count(*)::text from orden_mon_viol) || ' quiebre(s) en monto, '
      || ((select mal_ant from panel_orden_clave)
          + (select mal_mon from panel_orden_clave))::text || ' respuesta(s) con el orden mal declarado, '
      || (select sin_generado::text from panel_orden_clave) || ' sin generado_at',
    (select count(*) from orden_ant_viol) = 0
    and (select count(*) from orden_mon_viol) = 0
    and (select mal_ant from panel_orden_clave) = 0
    and (select mal_mon from panel_orden_clave) = 0
    and (select sin_generado from panel_orden_clave) = 0

  union all
  -- 10) Datos de newa: la 3 y la 68 abiertas y listadas, sin cerradas
  select 10, 'newa_panel_tienda_9',
    'con los datos de newa: las compras abiertas 3 y 68 (y las demás) están en el panel de la tienda 9, cuyo tamaño es el de las abiertas de esa tienda; ninguna completada aparece',
    'panel9=' || (select count(*)::text from panel9_filas)
      || ' (abiertas tienda 9=' || (select count(*)::text from public.fdi_dat_compra
                                     where id_tienda = 9
                                       and estado in (select estado from estados_abiertos)) || '), '
      || (select count(*)::text from newa_falta) || ' abierta(s) esperada(s) sin listar, '
      || (select count(*)::text from newa_cerrada_en_panel) || ' cerrada(s) en el panel',
    (select count(*) from newa_falta) = 0
    and (select count(*) from newa_cerrada_en_panel) = 0
    and (select count(*) from panel9_filas) =
        (select count(*) from public.fdi_dat_compra
          where id_tienda = 9
            and estado in (select estado from estados_abiertos))

  union all
  -- 11) Detalle de una compra sin recepciones
  select 11, 'detalle_sin_recepcion_recibido_cero',
    'el detalle de una compra abierta sin recepciones da recibido = 0 y recibido_pct = 0 en la cabecera y en todas sus líneas',
    (select count(*)::text from sin_recepcion) || ' compra(s) abierta(s) sin recepción, '
      || (select count(*)::text from sin_recepcion_viol) || ' con recibido distinto de 0',
    (select count(*) from sin_recepcion) > 0
    and (select count(*) from sin_recepcion_viol) = 0

  union all
  -- 12) Histórico de recepciones
  select 12, 'historial_recepciones_y_totales',
    'cada recepción coincide con la tabla (fecha, importes, líneas, cantidad, estado de la operación) y los totales por moneda son la suma de las filas de ESA moneda',
    (select count(*)::text from hist_filas) || ' recepción(es), '
      || (select count(*)::text from hist_dif) || ' que no cuadran con la tabla, '
      || (select count(*)::text from hist_falta) || ' de la tabla sin fila, '
      || (select count(*)::text from hist_tot) || ' total(es) por moneda, '
      || (select count(*)::text from hist_tot_dif) || ' que no cuadran, '
      || (select count(*)::text from hist_tot_falta) || ' moneda(s) sin total',
    (select count(*) from hist_dif) = 0
    and (select count(*) from hist_falta) = 0
    and (select count(*) from hist_tot_dif) = 0
    and (select count(*) from hist_tot_falta) = 0
    and (select count(*) from hist_filas) =
        (select count(*) from public.fdi_dat_compra_recepcion r
          where r.id_tienda in (select id_tienda from tiendas))

  union all
  -- 13) Facturas
  select 13, 'facturas_incluye_cerradas_y_cuadra',
    'la vista de facturas incluye TODAS las compras de la tienda (también completadas/canceladas/anuladas), cada fila coincide con las tablas y los totales por moneda son la suma de las filas de esa moneda',
    (select count(*)::text from fact_filas) || ' factura(s), '
      || (select count(*)::text from fact_falta) || ' compra(s) sin fila, '
      || (select count(*)::text from fact_dif) || ' que no cuadran con las tablas, '
      || (select count(*)::text from fact_estado_recepcion_viol) || ' con estado de recepción incoherente, '
      || (select n::text from fact_completadas) || ' completada(s) incluidas, '
      || (select count(*)::text from fact_tot) || ' total(es) por moneda, '
      || (select count(*)::text from fact_tot_dif) || ' que no cuadran, '
      || (select count(*)::text from fact_tot_falta) || ' moneda(s) sin total',
    (select count(*) from fact_falta) = 0
    and (select count(*) from fact_dif) = 0
    and (select count(*) from fact_estado_recepcion_viol) = 0
    and (select count(*) from fact_tot_dif) = 0
    and (select count(*) from fact_tot_falta) = 0
    and (select count(*) from fact_filas) = (select count(*) from public.fdi_dat_compra)
    and (select n from fact_completadas) =
        (select count(*) from public.fdi_dat_compra where estado = 'completada')

  union all
  -- 14) (informativa) volumen
  select 14, 'volumen_modulo',
    'foto de datos, no un fallo',
    'compras_abiertas=' || compras_abiertas::text
      || ', lineas_pendientes=' || lineas_pendientes::text
      || ', recepciones=' || recepciones::text
      || ', facturas=' || facturas::text
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