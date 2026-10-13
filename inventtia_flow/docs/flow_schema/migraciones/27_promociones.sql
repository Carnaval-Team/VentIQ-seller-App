-- ============================================================================
-- MIGRACION: promociones con vigencia, descuento y cupos atomicos
--
-- EL PROBLEMA QUE ESTA MIGRACION EVITA (leer antes de tocar precios)
--
--   Antes de esta migracion hay UN solo sitio que decide cuanto se cobra:
--   `flow.calcular_precio_reserva`, y lo llaman SEIS funciones:
--
--     cliente_reservar_directo           (cliente, reserva directa)
--     cliente_reservar_pasaje_omnibus    (cliente, transporte)
--     admin_crear_reserva_directa        (admin, mostrador)
--     admin_reservar_pasaje_omnibus      (admin, transporte)
--     bot_procesar_plan                  (BOT: mueve gente de la cola)
--     bot_procesar_recurso_dia           (BOT: idem, por recurso)
--
--   Si el descuento se metiera DENTRO de `calcular_precio_reserva`, el BOT
--   tambien lo aplicaria cuando mueve a alguien de la sala de espera a la
--   agenda: esa persona no eligio ninguna promocion y, peor, la promo podria
--   gastar un cupo que nadie pidio. Por eso NO se toca esa funcion.
--
--   El descuento vive en `_precio_con_promocion`, un envoltorio nuevo que solo
--   usan los 4 caminos en los que una PERSONA confirma una reserva. El bot
--   sigue usando `calcular_precio_reserva` a secas: precio de lista.
--
--   Consecuencia asumida y documentada: una entrada de cola promovida por el
--   bot nunca lleva descuento. Se aplica al reservar, no al esperar turno.
--
-- EL DESCUENTO SE RESERVA, NO SE CALCULA DOS VECES
--
--   El cliente ve el precio con descuento en la pantalla antes de confirmar.
--   Ese calculo es una CONSULTA (`cotizar_reserva`), que NO gasta cupo. Al
--   confirmar, `_precio_con_promocion` vuelve a resolver la promo, comprueba
--   que sigue vigente y con cupo, y **descuenta el cupo en el mismo instante en
--   que se inserta la agenda**. Si entre la cotizacion y la confirmacion la
--   promo se agoto, la reserva NO se cobra mas cara en silencio: se rechaza con
--   un mensaje claro para que el cliente decida.
--
--   Eso es justo lo que evita la confusion: lo que se muestra y lo que se cobra
--   salen de la MISMA funcion (`_resolver_promocion`).
--
-- REGLAS DE VIGENCIA (todas se comprueban en un solo sitio)
--   activo = true
--   and (desde is null or (now() at time zone 'America/Havana') >= desde)
--   and (hasta is null or (now() at time zone 'America/Havana') <  hasta)
--   and (cupo_total is null or cupo_usado < cupo_total)
--
--   `hasta` es EXCLUSIVO: una promo que termina el dia 10 a las 00:00 ya no
--   aplica el dia 10. Es la interpretacion menos sorprendente para una oferta
--   con hora de fin.
--
-- ALCANCE
--   La promo puede ser del servicio (`id_local_servicio`) o de TODA la entidad
--   (`id_entidad`), que es como se hacen las campanas de una tienda. Si hay
--   varias aplicables gana la de mayor descuento efectivo.
--
-- TIPOS DE DESCUENTO
--   'porcentaje' -> valor = 10 significa -10 %
--   'monto'      -> valor = 5 significa -5 en la moneda indicada
--   El total nunca baja de 0.
--
-- QUE CREA
--   - flow.promocion (+ RLS + indices)
--   - flow._resolver_promocion        (helper, no expuesto a la app)
--   - flow._aplicar_promocion         (helper: descuenta Y reserva cupo)
--   - flow._precio_con_promocion      (helper: envuelve precio de lista + descuento)
--   - flow.cotizar_reserva            (lo que llama la app para MOSTRAR precio)
--   - flow.promociones_de_servicio    (badges del detalle de UN servicio)
--   - flow.promociones_por_servicio   (badges de TODO el Home en una sola llamada)
--   - flow.admin_guardar_promocion    (CRUD admin, con auth.uid())
--   - flow.admin_eliminar_promocion
--   - flow.admin_listar_promociones
--
--   Y reescribe **2** RPC de reserva personal para que apliquen la promocion:
--   `cliente_reservar_directo` y `admin_crear_reserva_directa`. Ambos consumen
--   cupo (el bot no: ver `usa_promociones` en la verificacion).
--
--   NO toca `cliente_reservar_pasaje_omnibus` ni `admin_reservar_pasaje_omnibus`:
--   el transporte de omnibus llama a `calcular_precio_turno` hasta 3 veces por
--   operacion (ida, vuelta, ida_vuelta) y descontar en cada llamada
--   multiplicaria el descuento. Limitacion conocida y documentada, no olvido.
--
-- REVERSION
--   -- 1) Devolver los 2 RPC reescritos a `calcular_precio_reserva` a secas:
--   --    volver a aplicar las versiones originales de esos dos archivos.
--   drop function if exists flow.admin_listar_promociones(uuid, integer);
--   drop function if exists flow.admin_eliminar_promocion(uuid, integer);
--   drop function if exists flow.admin_guardar_promocion(uuid, integer, text, text, numeric, text, timestamptz, timestamptz, integer, boolean, integer);
--   drop function if exists flow.promociones_de_servicio(integer);
--   drop function if exists flow.promociones_por_servicio();
--   drop function if exists flow.cotizar_reserva(uuid, integer, jsonb, text, integer, integer);
--   drop function if exists flow._precio_con_promocion(integer, integer, jsonb, text, integer, boolean);
--   drop function if exists flow._aplicar_promocion(integer, integer, numeric, varchar, numeric, boolean);
--   drop function if exists flow._resolver_promocion(integer, integer, numeric);
--   drop table if exists flow.promocion;
--
-- DEPENDE DE: nada. Se puede aplicar sola.
-- ============================================================================


-- ============================================================================
-- 1. TABLA
-- ============================================================================
create table if not exists flow.promocion (
  id                 integer generated always as identity primary key,
  titulo             varchar(120) not null,
  descripcion        text,
  tipo               varchar(16) not null,
  valor              numeric(12,2) not null,
  moneda             varchar(8),

  -- Alcance: una promo es de un local_servicio o de toda una entidad.
  -- Exactamente uno de los dos debe estar puesto.
  id_local_servicio  integer references flow.local_servicio(id) on delete cascade,
  id_entidad         integer references flow.entidad(id) on delete cascade,

  desde              timestamptz,
  hasta              timestamptz,

  cupo_total         integer,
  cupo_usado         integer not null default 0,

  activo             boolean not null default true,
  created_at         timestamp not null default current_timestamp,
  updated_at         timestamp not null default current_timestamp,

  constraint promocion_tipo_check
    check (tipo in ('porcentaje', 'monto')),
  constraint promocion_alcance_check
    check ((id_local_servicio is null) <> (id_entidad is null)),
  constraint promocion_valor_check
    check (valor > 0 and (tipo <> 'porcentaje' or valor <= 100)),
  constraint promocion_cupo_check
    check (cupo_total is null or (cupo_total > 0 and cupo_usado >= 0 and cupo_usado <= cupo_total)),
  constraint promocion_vigencia_check
    check (desde is null or hasta is null or desde < hasta),
  -- Un descuento de monto necesita moneda; un porcentaje no.
  constraint promocion_moneda_check
    check (tipo <> 'monto' or (moneda is not null and btrim(moneda) <> ''))
);

comment on table flow.promocion is
  'Promociones vigentes. El descuento se aplica al reservar (no al entrar en cola). cupo_usado se descuenta de forma atomica.';

create index if not exists idx_promocion_ls_vigente
  on flow.promocion (id_local_servicio)
  where activo and id_local_servicio is not null;

create index if not exists idx_promocion_entidad_vigente
  on flow.promocion (id_entidad)
  where activo and id_entidad is not null;

-- ============================================================================
-- 2. RLS
--
--   SELECT -> cualquier autenticado: una promo es informacion publica del
--     catalogo (el Home muestra los badges), y el cliente necesita poder
--     cotizar. No se abre a `anon` porque la app requiere sesion.
--   INSERT/UPDATE/DELETE -> directo a tabla queda cerrado: `authenticated` solo
--     tiene SELECT. El CRUD va por los RPC `admin_*`, que **son DEFINER**
--     (obligatorio: con INVOKER no podrian escribir, porque no hay grant ni
--     politica de escritura) y validan la entidad por dentro con
--     `admin_entidades_de_usuario(auth.uid())`. Asi no hay dos caminos de
--     escritura con reglas distintas.
--
--   NO cambiar los `admin_*` de DEFINER a INVOKER "por simetria": romperia el
--   alta y el borrado de promociones. Y NO anadir politicas de escritura
--   dejandolos INVOKER: duplicaria la regla de autorizacion en dos sitios.
-- ============================================================================
alter table flow.promocion enable row level security;

drop policy if exists "promocion_select_autenticados" on flow.promocion;

create policy "promocion_select_autenticados"
on flow.promocion
for select
to authenticated
using (true);

revoke all on flow.promocion from anon;
grant select on flow.promocion to authenticated;
grant all on flow.promocion to service_role;

-- ============================================================================
-- 3. HELPERS
--
--   `_resolver_promocion` es la UNICA definicion de "que promo aplica y cuanto
--   descuenta". La usan la cotizacion (mostrar) y el cobro (reservar), asi que
--   no pueden divergir.
-- ============================================================================
create or replace function flow._resolver_promocion(
  p_id_local_servicio integer,
  p_id_servicio integer,
  p_monto numeric
)
returns table (
  id_promocion integer,
  descuento numeric,
  titulo varchar
)
language sql
stable
security invoker
set search_path = flow, public
as $$
  with objetivo as (
    -- Entidad del servicio consultado. Se resuelve UNA vez y se usa para las
    -- promos de entidad. (El error facil aqui es leer `l.id_entidad` del propio
    -- registro de la promo: en una promo de entidad `id_local_servicio` es null,
    -- asi que ese join no encuentra local y la promo nunca aplicaria.)
    select ls.id as id_local_servicio, l.id_entidad
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
  ),
  candidatas as (
    select
      pr.id,
      pr.titulo,
      pr.tipo,
      pr.valor,
      pr.moneda,
      -- Descuento efectivo sobre este monto concreto.
      case
        when pr.tipo = 'porcentaje' then round(p_monto * pr.valor / 100.0, 2)
        else least(pr.valor, p_monto)
      end as desc_calc
    from flow.promocion pr
    cross join objetivo o
    where pr.activo
      and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
      and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
      and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
      -- Del servicio concreto, o de toda su entidad.
      and (
        pr.id_local_servicio = o.id_local_servicio
        or (pr.id_entidad is not null and pr.id_entidad = o.id_entidad)
      )
  )
  select c.id, greatest(c.desc_calc, 0), c.titulo
  from candidatas c
  -- Gana el descuento mas alto. A igualdad, el mas antiguo (mas predecible).
  order by c.desc_calc desc, c.id asc
  limit 1;
$$;

-- Aplica la promocion a un precio de lista YA calculado, y opcionalmente
-- consume cupo.
--
-- Recibe el precio de lista en vez de calcularlo, para que sirva a los DOS
-- caminos de precio que existen (servicio y turno de transporte) sin duplicar
-- nada. Antes se calculaba dentro y solo cubria el camino del servicio, con lo
-- que el transporte aplicaba el descuento pero NO gastaba cupo: una promo
-- podia agotarse infinitas veces.
--
-- `p_consumir_cupo = false` para COTIZAR (solo mira), `true` al COBRAR.
--
-- El consumo es atomico y condicionado:
--   `update ... where cupo_usado < cupo_total`
-- asi dos reservas simultaneas no pueden pasarse del cupo: la segunda no
-- actualiza, no encuentra fila y se rechaza en vez de regalar el descuento.
create or replace function flow._aplicar_promocion(
  p_id_local_servicio integer,
  p_id_servicio integer,
  p_precio_lista numeric,
  p_moneda varchar,
  p_precio_unit numeric,
  p_consumir_cupo boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_lista        numeric := coalesce(p_precio_lista, 0);
  v_descuento    numeric := 0;
  v_promo_id     integer;
  v_promo_titulo varchar;
  v_filas        integer;
begin
  -- Sin precio de lista no hay nada que descontar (config_precio = '{}').
  if v_lista > 0 then
    -- Escalares, no `record`: sin promo aplicable no hay fila y leer un campo
    -- de un record sin asignar lanzaria "record is not assigned yet".
    select pr.id_promocion, pr.descuento, pr.titulo
      into v_promo_id, v_descuento, v_promo_titulo
    from flow._resolver_promocion(p_id_local_servicio, p_id_servicio, v_lista) pr;

    if v_promo_id is not null then
      if p_consumir_cupo then
        -- Reserva el cupo de forma atomica. Si no actualiza, la promo se agoto
        -- entre la cotizacion y la confirmacion.
        update flow.promocion pr
           set cupo_usado = pr.cupo_usado + 1,
               updated_at = current_timestamp
         where pr.id = v_promo_id
           and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total);

        get diagnostics v_filas = row_count;
        if v_filas = 0 then
          return jsonb_build_object(
            'ok', false,
            'error', 'La promocion se agoto mientras reservabas',
            'codigo', 'promo_agotada'
          );
        end if;
      end if;

      v_descuento := coalesce(v_descuento, 0);
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'precio_lista', v_lista,
    'precio_total', greatest(v_lista - v_descuento, 0),
    'descuento',    v_descuento,
    'moneda',       coalesce(p_moneda, 'USD'),
    'precio_unit',  coalesce(p_precio_unit, 0),
    'id_promocion', v_promo_id,
    'promo_titulo', v_promo_titulo
  );
end;
$$;

-- Conveniencia: calcula el precio de lista del SERVICIO y aplica la promo.
-- Es el camino de un servicio normal (sin turno). Para turnos se llama a
-- `_aplicar_promocion` con el precio de `calcular_precio_turno`.
create or replace function flow._precio_con_promocion(
  p_id_servicio integer,
  p_id_local_servicio integer,
  p_datos jsonb,
  p_moneda text,
  p_cantidad integer,
  p_consumir_cupo boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_lista numeric;
  v_moneda varchar;
  v_unit  numeric;
begin
  select cp.precio_total, cp.moneda, cp.precio_unit
    into v_lista, v_moneda, v_unit
  from flow.calcular_precio_reserva(
    p_id_servicio, coalesce(p_datos, '{}'::jsonb), p_moneda, p_cantidad
  ) cp;

  return flow._aplicar_promocion(
    p_id_local_servicio, p_id_servicio, v_lista, v_moneda, v_unit, p_consumir_cupo
  );
end;
$$;

-- ============================================================================
-- 4. COTIZACION (lo que la app usa para MOSTRAR el precio)
--
--   No consume cupo. La app la llama antes de confirmar y muestra exactamente
--   lo mismo que luego se cobra, porque sale de `_resolver_promocion`.
-- ============================================================================
create or replace function flow.cotizar_reserva(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_datos jsonb default null,
  p_moneda text default null,
  p_cantidad integer default 1,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
stable
-- DEFINER, no INVOKER. Motivo: llama a `_resolver_promocion`, que NO se expone
-- a los roles de la app (es un helper privado), asi que un INVOKER recibiria
-- "permission denied for function _resolver_promocion" al previsualizar precio.
-- Es seguro porque NO autoriza por el parametro: exige que `auth.uid()` sea el
-- uuid recibido (ver el guard del cuerpo), igual que los RPC de reserva.
security definer
set search_path = flow, public
as $$
declare
  v_id_servicio integer;
  v_lista       numeric;
  v_moneda      varchar;
  v_unit        numeric;
  v_descuento   numeric := 0;
  v_promo_id    integer;
  v_promo_titulo varchar;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select ls.id_servicio into v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_id_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  -- Con turno el precio puede venir del turno (transporte); sin turno, del
  -- servicio. Se obtiene el precio de LISTA por el camino que corresponda.
  if p_id_turno is not null then
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos, '{}'::jsonb),
      p_moneda, p_cantidad
    ) cp;
  else
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_reserva(
      v_id_servicio, coalesce(p_datos, '{}'::jsonb), p_moneda, p_cantidad
    ) cp;
  end if;

  v_lista := coalesce(v_lista, 0);

  -- UNA sola resolucion de promocion, igual que al cobrar. Esta funcion no
  -- consume cupo: solo informa de lo que se pagaria ahora mismo.
  --
  -- Se leen escalares y no un `record`: si no hay promo aplicable la consulta
  -- no devuelve filas, y acceder a un campo de un record sin asignar lanza
  -- "record is not assigned yet".
  if v_lista > 0 then
    select pr.id_promocion, pr.descuento, pr.titulo
      into v_promo_id, v_descuento, v_promo_titulo
    from flow._resolver_promocion(p_id_local_servicio, v_id_servicio, v_lista) pr;
    v_descuento := coalesce(v_descuento, 0);
  end if;

  return jsonb_build_object(
    'ok', true,
    'precio_lista', v_lista,
    'precio_total', greatest(v_lista - v_descuento, 0),
    'descuento',    v_descuento,
    'moneda',       coalesce(v_moneda, 'USD'),
    'precio_unit',  coalesce(v_unit, 0),
    'id_promocion', v_promo_id,
    'promo_titulo', v_promo_titulo
  );
end;
$$;

-- ============================================================================
-- 5. LECTURA PARA LA UI (badges del Home y del detalle)
-- ============================================================================
create or replace function flow.promociones_de_servicio(
  p_id_local_servicio integer
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.descuento_pct desc nulls last), '[]'::jsonb)
  from (
    select
      pr.id,
      pr.titulo,
      pr.descripcion,
      pr.tipo,
      pr.valor,
      pr.moneda,
      pr.desde,
      pr.hasta,
      pr.cupo_total,
      pr.cupo_usado,
      case when pr.cupo_total is null then null
           else greatest(pr.cupo_total - pr.cupo_usado, 0) end as cupos_restantes,
      case when pr.tipo = 'porcentaje' then pr.valor else null end as descuento_pct
    from flow.promocion pr
    where pr.activo
      and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
      and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
      and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
      and (
        pr.id_local_servicio = p_id_local_servicio
        -- Promos de entidad: la entidad se toma del servicio consultado, no del
        -- registro de la promo (que en ese caso tiene id_local_servicio null).
        or (
          pr.id_entidad is not null
          and pr.id_entidad = (
            select l.id_entidad
            from flow.local_servicio ls
            join flow.app_dat_locales l on l.id = ls.id_local
            where ls.id = p_id_local_servicio
          )
        )
      )
  ) t;
$$;

-- ============================================================================
-- 5.b PROMOS ACTIVAS, EN LOTE (para el feed del Home)
--
--   El Home pinta 6 tarjetas por pagina. Cotizar cada una seria 6 llamadas, y
--   con paginacion infinita el numero crece. Esta funcion devuelve de una vez
--   todas las promos vigentes y a quien aplican, para resolverlo en memoria.
--
--   OJO: esto es solo para MOSTRAR un badge y un precio de referencia. El
--   precio que se cobra lo decide `cotizar_reserva` / `_aplicar_promocion` al
--   confirmar, que es la misma logica. Si aqui se calculara el precio final con
--   reglas por datos adicionales, podria no coincidir: el Home no conoce las
--   opciones que elegira el cliente, asi que solo aplica sobre el precio base.
-- ============================================================================
create or replace function flow.promociones_por_servicio()
returns table (
  id_local_servicio integer,
  id                integer,
  titulo            varchar,
  tipo              varchar,
  valor             numeric,
  moneda            varchar,
  hasta             timestamptz,
  cupos_restantes   integer
)
language sql
stable
security invoker
set search_path = flow, public
as $$
  with candidatas as (
    select
      ls.id as id_local_servicio,
      pr.id, pr.titulo, pr.tipo, pr.valor, pr.moneda, pr.hasta,
      -- 0 = promo propia del servicio, 1 = promo de la entidad. Se prefiere la
      -- propia: es mas especifica.
      case when pr.id_local_servicio = ls.id then 0 else 1 end as prioridad,
      case when pr.tipo = 'porcentaje' then pr.valor else 0 end as pct,
      case when pr.cupo_total is null then null
           else greatest(pr.cupo_total - pr.cupo_usado, 0) end as cupos_restantes,
      row_number() over (
        partition by ls.id
        order by
          case when pr.id_local_servicio = ls.id then 0 else 1 end asc,
          case when pr.tipo = 'porcentaje' then pr.valor else 0 end desc,
          pr.id asc
      ) as orden
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.promocion pr
      on pr.activo
     and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
     and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
     and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
     and (
       pr.id_local_servicio = ls.id
       or (pr.id_entidad is not null and pr.id_entidad = l.id_entidad)
     )
  )
  select
    id_local_servicio, id, titulo, tipo, valor, moneda, hasta, cupos_restantes
  from candidatas
  where orden = 1;
$$;

-- ============================================================================
-- 6. CRUD ADMIN (para el panel de la entidad)
--
--   Autoriza con `auth.uid()`: el uuid NO se confia del parametro.
-- ============================================================================
create or replace function flow.admin_guardar_promocion(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_titulo text,
  p_tipo text,
  p_valor numeric,
  p_moneda text default null,
  p_desde timestamptz default null,
  p_hasta timestamptz default null,
  p_cupo_total integer default null,
  p_activo boolean default true,
  p_id integer default null
)
returns jsonb
language plpgsql
volatile
-- DEFINER, no INVOKER. `flow.promocion` solo concede SELECT a `authenticated`
-- (y solo tiene politica de SELECT), asi que un INVOKER no podria insertar:
-- daria "permission denied for table promocion" + violacion de RLS. El RPC es
-- la unica frontera de autorizacion, y ya valida entidad con
-- `admin_entidades_de_usuario(auth.uid())` y el uuid contra `auth.uid()`.
security definer
set search_path = flow, public
as $$
declare
  v_id_entidad integer;
  v_id         integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  -- El local_servicio debe pertenecer a una entidad que el usuario administra.
  select l.id_entidad into v_id_entidad
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  if not exists (
    select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
    where mine.id_entidad = v_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esta entidad');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_tipo not in ('porcentaje', 'monto') then
    return jsonb_build_object('ok', false, 'error', 'Tipo invalido');
  end if;
  if p_valor is null or p_valor <= 0 then
    return jsonb_build_object('ok', false, 'error', 'El valor debe ser mayor que 0');
  end if;
  if p_tipo = 'porcentaje' and p_valor > 100 then
    return jsonb_build_object('ok', false, 'error', 'Un porcentaje no puede pasar de 100');
  end if;
  if p_tipo = 'monto' and btrim(coalesce(p_moneda, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'Un descuento de monto necesita moneda');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error', 'La fecha de fin debe ser posterior al inicio');
  end if;
  if p_cupo_total is not null and p_cupo_total <= 0 then
    return jsonb_build_object('ok', false, 'error', 'El cupo debe ser mayor que 0');
  end if;

  if p_id is null then
    insert into flow.promocion (
      titulo, tipo, valor, moneda, id_local_servicio,
      desde, hasta, cupo_total, activo
    )
    values (
      btrim(p_titulo), p_tipo, p_valor, nullif(btrim(coalesce(p_moneda, '')), ''),
      p_id_local_servicio, p_desde, p_hasta, p_cupo_total, coalesce(p_activo, true)
    )
    returning id into v_id;
  else
    -- No se toca `cupo_usado`: es contabilidad de reservas ya hechas. Bajar el
    -- cupo_total por debajo de lo ya usado lo rechaza el CHECK.
    update flow.promocion pr
       set titulo = btrim(p_titulo),
           tipo = p_tipo,
           valor = p_valor,
           moneda = nullif(btrim(coalesce(p_moneda, '')), ''),
           desde = p_desde,
           hasta = p_hasta,
           cupo_total = p_cupo_total,
           activo = coalesce(p_activo, true),
           updated_at = current_timestamp
     where pr.id = p_id
       and (pr.id_local_servicio = p_id_local_servicio or pr.id_local_servicio is null)
       and exists (
         select 1 from flow.local_servicio ls2
         join flow.app_dat_locales l2 on l2.id = ls2.id_local
         join flow.admin_entidades_de_usuario(auth.uid()) mine2
           on mine2.id_entidad = l2.id_entidad
         where ls2.id = p_id_local_servicio
           and (pr.id_local_servicio = ls2.id or pr.id_entidad = l2.id_entidad)
       )
     returning pr.id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Promocion inexistente o sin permiso');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$$;

create or replace function flow.admin_eliminar_promocion(
  p_uuid_usuario uuid,
  p_id integer
)
returns jsonb
language plpgsql
volatile
-- DEFINER por el mismo motivo que `admin_guardar_promocion`: DELETE no esta
-- concedido a `authenticated` ni tiene politica. Valida entidad y uuid.
security definer
set search_path = flow, public
as $$
declare
  v_id_entidad integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(l.id_entidad, pr.id_entidad) into v_id_entidad
  from flow.promocion pr
  left join flow.local_servicio ls on ls.id = pr.id_local_servicio
  left join flow.app_dat_locales l on l.id = ls.id_local
  where pr.id = p_id;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'Promocion inexistente');
  end if;

  if not exists (
    select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
    where mine.id_entidad = v_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esta entidad');
  end if;

  delete from flow.promocion where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function flow.admin_listar_promociones(
  p_uuid_usuario uuid,
  p_id_local_servicio integer default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = flow, public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.id desc), '[]'::jsonb)
    into v_result
  from (
    select
      pr.id, pr.titulo, pr.descripcion, pr.tipo, pr.valor, pr.moneda,
      pr.id_local_servicio, pr.id_entidad,
      pr.desde, pr.hasta, pr.cupo_total, pr.cupo_usado, pr.activo,
      pr.created_at, pr.updated_at,
      s.nombre as servicio,
      l.nombre as local
    from flow.promocion pr
    left join flow.local_servicio ls on ls.id = pr.id_local_servicio
    left join flow.app_dat_servicios s on s.id = ls.id_servicio
    left join flow.app_dat_locales l on l.id = ls.id_local
    where exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = coalesce(l.id_entidad, pr.id_entidad)
    )
      and (p_id_local_servicio is null or pr.id_local_servicio = p_id_local_servicio)
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$$;


-- ============================================================================
-- 7. LOS 4 RPC DE RESERVA PERSONAL USAN EL ENVOLTORIO
--
--   Se reescriben con `create or replace`, conservando FIRMA y forma de
--   respuesta. Solo cambia de donde sale el precio: antes
--   `calcular_precio_reserva` a secas, ahora `_precio_con_promocion` con
--   `p_consumir_cupo = true`.
--
--   El BOT **no** se toca (sigue con precio de lista).
--
--   Nota: se envuelve la llamada en un bloque que, si la promo se agoto,
--   devuelve el error tal cual para que la app lo muestre.
-- ============================================================================

-- 7.1 cliente_reservar_directo
--
-- El reemplazo por texto de `pg_get_functiondef` es fragil (CRLF, espacios),
-- asi que los RPC se reescriben completos: es mas largo, pero no deja lugar a
-- que una diferencia de un espacio deje el descuento sin aplicar en silencio.
create or replace function flow.cliente_reservar_directo(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_fecha date,
  p_cantidad integer default null,
  p_datos_adicionales jsonb default null,
  p_para_tercero boolean default false,
  p_t_nombre text default null,
  p_t_apellidos text default null,
  p_t_ci text default null,
  p_t_telefono text default null,
  p_moneda text default null,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $$
declare
  v_permite          boolean;
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_titular          uuid;
  v_nombre_servicio  text;
  v_nombre_local     text;
  v_saludo           text;
  v_cant             integer;
  v_id_servicio      integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
  v_cotizacion       jsonb;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select ls.permite_reserva_directa, ls.cantidad_default,
         ls.cantidad_max_capacidad, ls.id_servicio
    into v_permite, v_cantidad_default, v_cantidad_max, v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_permite is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if v_permite is not true then
    return jsonb_build_object('ok', false, 'error', 'Reserva directa no habilitada para este servicio');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  if exists (
    select 1 from flow.agenda a
    where a.uuid_usuario = v_titular
      and a.id_local_servicio = p_id_local_servicio
      and a.id_estado = v_estado
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date = p_fecha
      and a.id_turno is not distinct from p_id_turno
  ) then
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya tienes una reserva ese dia'
           else 'Esa persona ya tiene una reserva ese dia' end);
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
    -- Transporte: el precio puede venir del turno. Se calcula el precio de
    -- lista por turno y se pasa al MISMO envoltorio que el camino normal, para
    -- que tambien CONSUMA CUPO. Si aqui solo se restara el descuento, el
    -- transporte aplicaria la promo sin gastar cupo y se agotaria infinitas
    -- veces.
    select flow._aplicar_promocion(
             p_id_local_servicio, v_id_servicio,
             cp.precio_total, cp.moneda, cp.precio_unit, true
           )
      into v_cotizacion
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos_adicionales, '{}'::jsonb), p_moneda, v_cant
    ) cp;
  else
    -- ── Camino legacy: plan_servicios ──
    select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
    from flow.plan_servicios ps
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and (ps.fecha at time zone 'America/Havana')::date = p_fecha
    order by ps.id
    limit 1
    for update;

    if v_plan_id is null then
      return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles');
    end if;
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;

    v_cotizacion := flow._precio_con_promocion(
      v_id_servicio, p_id_local_servicio, p_datos_adicionales, p_moneda, v_cant, true
    );
  end if;

  if (v_cotizacion ->> 'ok') = 'false' then
    return jsonb_build_object('ok', false,
      'error', v_cotizacion ->> 'error',
      'codigo', v_cotizacion ->> 'codigo');
  end if;

  v_precio_total := (v_cotizacion ->> 'precio_total')::numeric;
  v_moneda       := (v_cotizacion ->> 'moneda')::varchar;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_titular, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_usuario, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    p_uuid_usuario, 'reserva', 'Reservacion confirmada',
    v_saludo || ', '
      || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
      || ', se ha realizado satisfactoriamente '
      || case when v_cant > 1 then v_cant || ' reservaciones' else 'su reservacion' end
      || case when coalesce(p_para_tercero, false)
              then ' a nombre de ' || coalesce(nullif(trim(coalesce(p_t_nombre,'') || ' ' || coalesce(p_t_apellidos,'')), ''), 'un tercero')
              else '' end
      || ' para el local "' || coalesce(v_nombre_local, 'local')
      || '" el servicio "' || coalesce(v_nombre_servicio, 'servicio')
      || '" para la fecha ' || to_char(v_fecha_ts, 'DD/MM/YYYY') || '.',
    p_id_local_servicio, v_id_agenda,
    jsonb_build_object('fecha', v_fecha_ts, 'servicio', v_nombre_servicio,
                       'local', v_nombre_local, 'cantidad', v_cant, 'id_turno', p_id_turno)
  from (select 1) x
  left join flow.perfil p on p.uuid_usuario = p_uuid_usuario;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno,
      'precio_total', v_precio_total,
      'moneda',       v_moneda
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;

-- 7.2 admin_crear_reserva_directa (mostrador)
create or replace function flow.admin_crear_reserva_directa(
  p_id_local_servicio integer,
  p_fecha date,
  p_cantidad integer default null,
  p_datos_adicionales jsonb default null,
  p_uuid_admin uuid default null,
  p_id_turno integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $$
declare
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_cant             integer;
  v_uuid_admin       uuid;
  v_es_admin         boolean;
  v_id_servicio      integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
  v_cotizacion       jsonb;
begin
  v_uuid_admin := coalesce(p_uuid_admin, auth.uid());

  if v_uuid_admin is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
      and (
        e.owner_uuid = v_uuid_admin
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = e.id and ea.uuid_usuario = v_uuid_admin
        )
      )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos de administrador sobre este servicio');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select ls.cantidad_default, ls.cantidad_max_capacidad, ls.id_servicio
    into v_cantidad_default, v_cantidad_max, v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_cantidad_default is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
    select flow._aplicar_promocion(
             p_id_local_servicio, v_id_servicio,
             cp.precio_total, cp.moneda, cp.precio_unit, true
           )
      into v_cotizacion
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos_adicionales, '{}'::jsonb), null, v_cant
    ) cp;
  else
    select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
    from flow.plan_servicios ps
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and (ps.fecha at time zone 'America/Havana')::date = p_fecha
    order by ps.id
    limit 1
    for update;

    if v_plan_id is null then
      return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles para esa fecha');
    end if;
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;

    v_cotizacion := flow._precio_con_promocion(
      v_id_servicio, p_id_local_servicio, p_datos_adicionales, null, v_cant, true
    );
  end if;

  if (v_cotizacion ->> 'ok') = 'false' then
    return jsonb_build_object('ok', false,
      'error', v_cotizacion ->> 'error',
      'codigo', v_cotizacion ->> 'codigo');
  end if;

  v_precio_total := (v_cotizacion ->> 'precio_total')::numeric;
  v_moneda       := (v_cotizacion ->> 'moneda')::varchar;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, v_uuid_admin, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno,
      'precio_total', v_precio_total,
      'moneda',       v_moneda
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$$;


-- ============================================================================
-- 8. PERMISOS
-- ============================================================================
revoke all on function flow.cotizar_reserva(uuid, integer, jsonb, text, integer, integer) from public, anon;
revoke all on function flow.promociones_de_servicio(integer) from public, anon;
revoke all on function flow.promociones_por_servicio() from public, anon;
revoke all on function flow.admin_guardar_promocion(uuid, integer, text, text, numeric, text, timestamptz, timestamptz, integer, boolean, integer) from public, anon;
revoke all on function flow.admin_eliminar_promocion(uuid, integer) from public, anon;
revoke all on function flow.admin_listar_promociones(uuid, integer) from public, anon;
-- Los helpers no se exponen a la app.
revoke all on function flow._resolver_promocion(integer, integer, numeric) from public, anon, authenticated;
revoke all on function flow._precio_con_promocion(integer, integer, jsonb, text, integer, boolean) from public, anon, authenticated;
revoke all on function flow._aplicar_promocion(integer, integer, numeric, varchar, numeric, boolean) from public, anon, authenticated;

grant execute on function flow.cotizar_reserva(uuid, integer, jsonb, text, integer, integer) to authenticated, service_role;
grant execute on function flow.promociones_de_servicio(integer) to authenticated, service_role;
grant execute on function flow.promociones_por_servicio() to authenticated, service_role;
grant execute on function flow.admin_guardar_promocion(uuid, integer, text, text, numeric, text, timestamptz, timestamptz, integer, boolean, integer) to authenticated, service_role;
grant execute on function flow.admin_eliminar_promocion(uuid, integer) to authenticated, service_role;
grant execute on function flow.admin_listar_promociones(uuid, integer) to authenticated, service_role;

-- Los 2 RPC de reserva reescritos conservan sus permisos previos; se reafirman
-- (no se tocan los de pasaje_omnibus, que esta migracion no reescribe).
grant execute on function flow.cliente_reservar_directo(uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text, integer) to authenticated;
grant execute on function flow.admin_crear_reserva_directa(integer, date, integer, jsonb, uuid, integer) to authenticated;

-- Los helpers los invocan funciones `security definer`, que corren como el
-- owner: no necesitan EXECUTE para los roles de la app.
grant execute on function flow._resolver_promocion(integer, integer, numeric) to service_role;
grant execute on function flow._precio_con_promocion(integer, integer, jsonb, text, integer, boolean) to service_role;
grant execute on function flow._aplicar_promocion(integer, integer, numeric, varchar, numeric, boolean) to service_role;

notify pgrst, 'reload schema';

-- ============================================================================
-- 9. VERIFICACION
-- ============================================================================
select 'tabla' as objeto, c.relname as nombre, c.relrowsecurity as rls,
       coalesce(array_to_string(c.relacl::text[], ' | '), 'default') as acl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname = 'promocion'
union all
select 'policy', policyname, true, cmd::text || ' → ' || roles::text
from pg_policies where schemaname = 'flow' and tablename = 'promocion'
union all
select 'funcion', p.proname, p.prosecdef,
       coalesce(array_to_string(p.proacl::text[], ' | '), 'default(PUBLIC)')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow' and p.proname in (
  'cotizar_reserva', 'promociones_de_servicio', 'promociones_por_servicio',
  'admin_guardar_promocion',
  'admin_eliminar_promocion', 'admin_listar_promociones',
  '_resolver_promocion', '_precio_con_promocion', '_aplicar_promocion'
)
order by objeto, nombre;

-- El bot NO debe haber cambiado: sigue llamando a `calcular_precio_reserva`
-- a secas, sin promociones.
select p.proname,
       (pg_get_functiondef(p.oid) ilike '%_aplicar_promocion%'
        or pg_get_functiondef(p.oid) ilike '%_precio_con_promocion%') as usa_promociones,
       (pg_get_functiondef(p.oid) ilike '%calcular_precio_reserva%') as usa_precio_lista
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('bot_procesar_plan', 'bot_procesar_recurso_dia',
                    'cliente_reservar_directo', 'admin_crear_reserva_directa')
order by p.proname;

-- Esperado: los 2 bots con usa_promociones = false y usa_precio_lista = true;
-- los 2 RPC personales con usa_promociones = true.