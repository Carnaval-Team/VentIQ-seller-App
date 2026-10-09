-- ════════════════════════════════════════════════════════════════════════════
-- PRUEBA FUNCIONAL — flow.cliente_reservar_directo / flow.admin_crear_reserva_directa
-- ════════════════════════════════════════════════════════════════════════════
--
-- Qué comprueba
--   1. El precio de lista del turno (calcular_precio_turno).
--   2. Que una promoción vigente descuenta: 35 USD -> 28 USD (20%).
--   3. Que lo COTIZADO coincide con lo COBRADO (misma resolución de promo).
--   4. Que la agenda guarda el precio descontado y el id_turno.
--   5. Que se consume cupo de la promoción (cupo_usado +1) y tramos (plan_tramo).
--   6. Que el camino de ADMIN cobra igual que el de cliente.
--   7. Que con la promo AGOTADA se cobra el precio de LISTA (nunca 0 ni NULL).
--   8. Controles negativos: servicio sin reserva directa y turno de otro servicio.
--
-- Datos verificados contra la base (release) el 2026-10-09, zona America/Havana.
--   LS 12 = servicio 7, local 5, entidad 4 · permite_reserva_directa = true
--   fecha 2026-10-14 (con plan_tramo para el turno 20, 12 disponibles)
--   turno 20 "Ida" = 35 USD      · lista 35 · promo 20% = 7.00 de descuento -> 28.00
--   cliente libre : 047a7f26-67bb-444b-848b-22c5267ba9e8
--   otro cliente  : 1a78a129-c517-4f8f-915c-12c15f8a04ec
--   otro cliente  : 1c962121-33fd-41d3-8feb-1d610447466d
--   admin (owner de la entidad 4) : 206c4acc-9040-44cd-a363-9ab1ccc91c53
--
-- ⚠ TODO termina en ROLLBACK: no persiste NADA (ni agenda, ni notificación,
--   ni cupo, ni agendados, ni la promoción de prueba).
--
-- Cómo leer el resultado
--   La penúltima consulta devuelve una fila por comprobación. La última da
--   `pasan / fallan / total`. Debe salir fallan = 0.
--
-- Nota: se ejecuta como `postgres` (el SQL Editor). Es correcto porque las dos
--   funciones son SECURITY DEFINER, así que su lógica es la misma que ve la
--   app al llamarlas como `authenticated`. Los permisos y RLS ya se validaron
--   por separado (campana/promocion/resena y los GRANT de los RPC).
-- ════════════════════════════════════════════════════════════════════════════

begin;

create temp table _r (n int, paso text, esperado text, obtenido text, ok boolean) on commit drop;
create temp table _promo (id integer) on commit drop;

-- Instantánea de plan_tramo ANTES de reservar, para medir el consumo real.
create temp table _pt0 on commit drop as
select pt.id, pt.agendados
from flow.plan_tramo pt
join flow.turno_tramo tt on tt.id_tramo = pt.id_tramo
where tt.id_turno = 20
  and (pt.fecha at time zone 'America/Havana')::date = date '2026-10-14';

-- ══ 1. Precio de LISTA del turno, sin promo ═════════════════════════════════
insert into _r
select 1, '1. precio de lista turno 20',
       '35.00 USD',
       round(x.precio_total, 2)::text || ' ' || x.moneda,
       x.precio_total = 35 and x.moneda = 'USD'
from flow.calcular_precio_turno(7, 20, '{}'::jsonb, null, 1) x;

-- El turno debe tener tramos con plan ese día, si no la prueba no sirve.
insert into _r
select 2, '2. turno 20 tiene plan_tramo el 2026-10-14',
       '> 0 filas',
       (select count(*)::text from _pt0) || ' filas',
       (select count(*) from _pt0) > 0;

-- ══ 3. Crear promo 20% (cupo 5) ═════════════════════════════════════════════
with ins as (
  insert into flow.promocion
    (titulo, tipo, valor, moneda, id_local_servicio, desde, hasta,
     cupo_total, cupo_usado, activo)
  values
    ('TEST ROLLBACK 20%', 'porcentaje', 20, 'USD', 12,
     current_timestamp - interval '1 day',
     current_timestamp + interval '1 day',
     5, 0, true)
  returning id
)
insert into _promo select id from ins;

insert into _r
select 3, '3. promo 20% creada (cupo 0/5)',
       '1 fila · valor 20 · cupo 0/5',
       (select count(*)::text from flow.promocion pr join _promo p on p.id = pr.id)
         || ' fila · valor ' || (select pr.valor::text from flow.promocion pr join _promo p on p.id = pr.id)
         || ' · cupo ' || (select pr.cupo_usado::text || '/' || pr.cupo_total::text from flow.promocion pr join _promo p on p.id = pr.id),
       (select count(*) from flow.promocion pr join _promo p on p.id = pr.id) = 1
         and (select pr.valor from flow.promocion pr join _promo p on p.id = pr.id) = 20
         and (select pr.cupo_usado from flow.promocion pr join _promo p on p.id = pr.id) = 0;

-- ══ 4. Lo que se COTIZA (mismo resolutor que el cobro, sin consumir cupo) ═══
insert into _r
select 4, '4. cotización con promo (35 -> 28)',
       'lista 35.00 · descuento 7.00 · total 28.00 · id_promocion no nulo',
       'lista ' || round((a.j->>'precio_lista')::numeric, 2)::text
         || ' · descuento ' || round((a.j->>'descuento')::numeric, 2)::text
         || ' · total ' || round((a.j->>'precio_total')::numeric, 2)::text
         || ' · id_promocion ' || coalesce(a.j->>'id_promocion', 'NULL'),
       (a.j->>'precio_lista')::numeric = 35
         and (a.j->>'descuento')::numeric = 7
         and (a.j->>'precio_total')::numeric = 28
         and (a.j->>'id_promocion') is not null
from (select flow._aplicar_promocion(12, 7, 35, 'USD', 35, false) as j) a;

-- ══ 5. RESERVAR como CLIENTE ════════════════════════════════════════════════
create temp table _res_cli (j jsonb) on commit drop;
insert into _res_cli
select flow.cliente_reservar_directo(
  '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 12, date '2026-10-14',
  1, '{}'::jsonb, false, null, null, null, null, null, 20);

insert into _r
select 5, '5. cliente_reservar_directo cobra lo cotizado (28)',
       'ok=true · precio_total 28.00',
       'ok=' || coalesce((select j->>'ok' from _res_cli), 'NULL')
         || ' · precio_total ' || coalesce(round(((select j->'data'->>'precio_total' from _res_cli))::numeric, 2)::text, 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_cli), '-'),
       (select (j->>'ok')::boolean from _res_cli) is true
         and ((select j->'data'->>'precio_total' from _res_cli))::numeric = 28;

-- Subconsultas escalares + coalesce: si la reserva no creó agenda, esta fila
-- igual se emite y sale FALLA (con subconsulta en el FROM desaparecería y el
-- caso no se evaluaría).
insert into _r
select 6, '6. agenda guardada con 28.00, USD y turno 20',
       '28.00 · USD · turno 20',
       coalesce(
         (select round(a.precio_total, 2)::text || ' · ' || a.moneda
                 || ' · turno ' || coalesce(a.id_turno::text, 'NULL')
          from flow.agenda a
          where a.id = (select (j->'data'->>'id_agenda')::int from _res_cli)),
         'sin agenda (ver paso 5)'),
       coalesce(
         (select a.precio_total = 28 and a.moneda = 'USD' and a.id_turno = 20
          from flow.agenda a
          where a.id = (select (j->'data'->>'id_agenda')::int from _res_cli)),
         false);

insert into _r
select 7, '7. cupo_usado de la promo = 1',
       '1',
       (select pr.cupo_usado::text from flow.promocion pr join _promo p on p.id = pr.id),
       (select pr.cupo_usado from flow.promocion pr join _promo p on p.id = pr.id) = 1;

insert into _r
select 8, '8. plan_tramo.agendados +1 (el turno consume sus tramos)',
       'todos los tramos +1',
       (select count(*)::text from flow.plan_tramo pt
          join _pt0 z on z.id = pt.id) || ' tramos, '
         || (select count(*)::text from flow.plan_tramo pt
               join _pt0 z on z.id = pt.id
              where pt.agendados - z.agendados = 1) || ' con +1',
       (select count(*) from _pt0) > 0
         and (select count(*) from flow.plan_tramo pt join _pt0 z on z.id = pt.id)
             = (select count(*) from flow.plan_tramo pt join _pt0 z on z.id = pt.id where pt.agendados - z.agendados = 1);

-- ══ 9. RESERVAR como ADMIN (mismo turno, misma promo) ══════════════════════
create temp table _res_adm (j jsonb) on commit drop;
insert into _res_adm
select flow.admin_crear_reserva_directa(
  12, date '2026-10-14', 1, '{}'::jsonb,
  '206c4acc-9040-44cd-a363-9ab1ccc91c53'::uuid, 20);

insert into _r
select 9, '9. admin_crear_reserva_directa cobra igual (28)',
       'ok=true · precio_total 28.00',
       'ok=' || coalesce((select j->>'ok' from _res_adm), 'NULL')
         || ' · precio_total ' || coalesce(round(((select j->'data'->>'precio_total' from _res_adm))::numeric, 2)::text, 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_adm), '-'),
       (select (j->>'ok')::boolean from _res_adm) is true
         and ((select j->'data'->>'precio_total' from _res_adm))::numeric = 28;

insert into _r
select 10, '10. cupo_usado acumulado = 2 (ambos caminos consumen)',
       '2',
       (select pr.cupo_usado::text from flow.promocion pr join _promo p on p.id = pr.id),
       (select pr.cupo_usado from flow.promocion pr join _promo p on p.id = pr.id) = 2;

insert into _r
select 11, '11. plan_tramo.agendados +2 en total',
       'todos los tramos +2',
       (select count(*)::text from flow.plan_tramo pt join _pt0 z on z.id = pt.id where pt.agendados - z.agendados = 2)
         || ' de ' || (select count(*)::text from _pt0) || ' tramos',
       (select count(*) from _pt0) > 0
         and (select count(*) from flow.plan_tramo pt join _pt0 z on z.id = pt.id where pt.agendados - z.agendados = 2)
             = (select count(*) from _pt0);

-- ══ 12. PROMO AGOTADA → se cobra LISTA, nunca 0 ni NULL ════════════════════
update flow.promocion set cupo_usado = cupo_total where id in (select id from _promo);

create temp table _res_agot (j jsonb) on commit drop;
insert into _res_agot
select flow.cliente_reservar_directo(
  '1a78a129-c517-4f8f-915c-12c15f8a04ec'::uuid, 12, date '2026-10-14',
  1, '{}'::jsonb, false, null, null, null, null, null, 20);

insert into _r
select 12, '12. promo agotada -> cobra LISTA 35 (no 0 ni NULL)',
       'ok=true · precio_total 35.00',
       'ok=' || coalesce((select j->>'ok' from _res_agot), 'NULL')
         || ' · precio_total ' || coalesce(round(((select j->'data'->>'precio_total' from _res_agot))::numeric, 2)::text, 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_agot), '-'),
       (select (j->>'ok')::boolean from _res_agot) is true
         and ((select j->'data'->>'precio_total' from _res_agot))::numeric = 35;

-- ══ 13. CONTROL NEGATIVO — servicio sin reserva directa (LS 7) ═════════════
create temp table _res_no (j jsonb) on commit drop;
insert into _res_no
select flow.cliente_reservar_directo(
  '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 7, date '2026-10-14',
  1, '{}'::jsonb, false, null, null, null, null, null, null);

insert into _r
select 13, '13. LS 7 (permite_reserva_directa=false) -> rechazado',
       'ok=false',
       'ok=' || coalesce((select j->>'ok' from _res_no), 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_no), '-'),
       (select (j->>'ok')::boolean from _res_no) is false;

-- ══ 14. CONTROL NEGATIVO — turno que pertenece a otro servicio ═════════════
create temp table _res_bad (j jsonb) on commit drop;
insert into _res_bad
select flow.cliente_reservar_directo(
  '1c962121-33fd-41d3-8feb-1d610447466d'::uuid, 12, date '2026-10-14',
  1, '{}'::jsonb, false, null, null, null, null, null, 25);

insert into _r
select 14, '14. turno 25 (es de LS 19) sobre LS 12 -> rechazado',
       'ok=false',
       'ok=' || coalesce((select j->>'ok' from _res_bad), 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_bad), '-'),
       (select (j->>'ok')::boolean from _res_bad) is false;

-- ══ 15. CONTROL NEGATIVO — reserva duplicada del mismo día ═════════════════
create temp table _res_dup (j jsonb) on commit drop;
insert into _res_dup
select flow.cliente_reservar_directo(
  '047a7f26-67bb-444b-848b-22c5267ba9e8'::uuid, 12, date '2026-10-14',
  1, '{}'::jsonb, false, null, null, null, null, null, 20);

insert into _r
select 15, '15. misma reserva dos veces -> rechazado',
       'ok=false',
       'ok=' || coalesce((select j->>'ok' from _res_dup), 'NULL')
         || ' · error=' || coalesce((select j->>'error' from _res_dup), '-'),
       (select (j->>'ok')::boolean from _res_dup) is false;

-- ══ RESULTADO ══════════════════════════════════════════════════════════════
select n as "#", paso, esperado, obtenido,
       case when ok then 'PASA' else '**FALLA**' end as veredicto
from _r order by n;

select count(*) filter (where ok)       as pasan,
       count(*) filter (where not ok)   as fallan,
       count(*)                         as total
from _r;

-- JSON crudo de cada llamada, por si algo falla y hace falta el mensaje entero.
select 'cliente'      as llamada, (select j from _res_cli)  as respuesta
union all select 'admin',        (select j from _res_adm)
union all select 'agotada',      (select j from _res_agot)
union all select 'sin_directa',  (select j from _res_no)
union all select 'turno_ajeno',  (select j from _res_bad)
union all select 'duplicada',    (select j from _res_dup);

-- ══ NADA DE ESTO PERSISTE ══════════════════════════════════════════════════
rollback;
