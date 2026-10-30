-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 72: PLANES CON LÍMITES, PLANES PRIVADOS POR ENTIDAD Y
--               MODALIDAD "CONTACTO"
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   1. `flow.suscripcion_plan` gana tres columnas:
--        · id_entidad  -> NULL = plan público; NOT NULL = plan privado de ESA
--                         entidad (sólo ella y el superadmin lo ven).
--        · modalidad   -> 'pago' | 'contacto'. 'contacto' = "Contactar con
--                         ventas": no se paga por Transfermóvil, se abre WhatsApp.
--        · etiqueta    -> cinta de la tarjeta ("Más popular", "Recomendado").
--                         NULL = sin cinta.
--      `limites` ya existía; aquí se documenta su contrato:
--        claves 'entidades', 'locales', 'servicios_por_local',
--        'servicios_catalogo', 'usuarios'. Número > 0 = límite; clave ausente,
--        null, 0 o negativo = SIN LÍMITE.
--
--   2. Funciones nuevas:
--        · flow.entidad_limites(id_entidad)          -> plan vivo + limites.
--        · flow.entidad_limite_alcanzado(...)        -> ¿bloquea crear N más?
--      Y dos helpers internos (no forman parte del contrato de la app):
--        · flow._limite_plan_evaluar(...)            -> cálculo + mensaje.
--        · flow._trg_limite_plan()                   -> trigger común.
--
--   3. Seis triggers BEFORE INSERT: los INSERT de locales, servicios y usuarios
--      los hace Flutter DIRECTO por PostgREST/RLS (no hay RPC intermedio), así
--      que el trigger es el ÚNICO punto de enforcement posible:
--        · flow.trg_limite_entidades         (flow.entidad)
--        · flow.trg_limite_locales           (flow.app_dat_locales)
--        · flow.trg_limite_servicios         (flow.app_dat_servicios)
--        · flow.trg_limite_local_servicio    (flow.local_servicio)
--        · flow.trg_limite_usuarios_admin    (flow.entidad_admin)
--        · flow.trg_limite_usuarios_vendedor (flow.entidad_vendedor)
--      El mensaje SIEMPRE empieza por `ERR_LIMITE_PLAN:` y sale con SQLSTATE
--      P0001 (raise exception), para que la app lo detecte y muestre un aviso
--      limpio en vez del error crudo de PostgREST.
--
--   4. Se redefinen (misma migración, sin tocar los archivos viejos) los RPC:
--        · flow.admin_planes_listar()
--        · flow.admin_plan_guardar(...)   <-- OJO: FIRMA NUEVA, ver abajo
--        · flow.cliente_planes_suscripcion()
--        · flow.cliente_crear_intent_suscripcion(...)
--
-- ⚠ OVERLOAD, NO REEMPLAZO (corrección del lead)
--   `create or replace function` con una firma DISTINTA NO reemplaza: crea una
--   segunda función sobrecargada. PostgREST resuelve por nombre + argumentos y
--   puede volverse ambiguo. Por eso, ANTES de crear la firma nueva de 13
--   argumentos, se borra EXACTAMENTE la firma vieja de 10:
--       drop function if exists flow.admin_plan_guardar(
--         bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean);
--   Las otras tres funciones conservan firma: ahí basta `create or replace`.
--
-- REGLAS DE NEGOCIO APLICADAS (y por qué)
--   · Sin fila de suscripción o sin plan -> limites = '{}' (SIN límites). Es el
--     mismo "grandfathering" que `flow.entidad_activa`: la migración no apaga ni
--     bloquea a nadie que ya exista. Sólo los planes nuevos limitan. El trial
--     (fila viva con `id_plan` NULL) cae en este mismo caso: durante el trial no
--     hay límites; empiezan a aplicar cuando se acredita un plan.
--   · `entidades` se cuenta por `flow.entidad.owner_uuid` (la cuenta del dueño,
--     no la entidad): el plan que manda es el de la suscripción viva CON PLAN
--     más reciente de cualquiera de sus entidades (una fila de trial sin plan no
--     tapa el plan de pago). Si el dueño aún no tiene plan, no hay límite (su
--     primera entidad siempre pasa).
--   · `usuarios` = administradores + vendedores de la entidad. Es la lectura más
--     honesta con lo que anuncia la tarjeta ("3 usuarios"): se suman las DOS
--     tablas, y los dos triggers cuentan esa misma suma (si sólo contaran su
--     propia tabla, se podría duplicar el cupo).
--   · Se cuentan TODAS las filas de locales/servicios, estén activas o no:
--     despublicar no libera cupo. La app borra de verdad (`delete()` en
--     catalogo_service.dart), y eso sí libera el cupo.
--   · Las entidades que YA superan los límites nuevos no se tocan: el trigger es
--     BEFORE INSERT, sólo bloquea inserciones nuevas.
--   · Los triggers se aplican también a `postgres`/`service_role`: no hay bypass
--     para el superadmin (el contrato no lo pedía). Para hacer soporte con una
--     entidad al límite hay que subirle el plan.
--
-- DESVIACIONES / DECISIONES QUE NO ESTABAN EN EL CONTRATO (documentadas)
--   a) `p_id_entidad = 0` en `admin_plan_guardar` significa "publicar" (poner
--      id_entidad = NULL). NULL significa "conservar" en UPDATE (necesario,
--      porque el switch activo/inactivo llama `guardarPlan(id:, activo:)` sin
--      más y un NULL "publicaría" el plan privado sin querer). En INSERT, NULL
--      y 0 son lo mismo: plan público.
--   b) Se endurece la RLS de `flow.suscripcion_plan`: la política vieja
--      `using (true)` dejaba leer por tabla cualquier plan privado a cualquier
--      usuario autenticado, lo que anulaba la privacidad. Ahora sólo se ven los
--      públicos, los de las entidades que administra el llamante y todo para el
--      superadmin. Los RPC son `security definer`, así que no cambian.
--   c) Se añaden tres índices de apoyo para que los conteos de los triggers no
--      hagan seq scan en cada INSERT (app_dat_locales, app_dat_servicios,
--      entidad.owner_uuid). No había ninguno por esas columnas.
--   d) `p_id_entidad` se valida contra `flow.entidad`: si no existe, error claro
--      (la FK lo habría rechazado igual, pero con un mensaje críptico).
--
-- DEPENDE DE: 43 (tablas de suscripción), 44 (entidad_activa y planes al
--             cliente), 45 (intent de pago), 46 (RPC del superadmin y planes).
-- ORDEN:      aplicar 72 y después 73_seed_planes_2026.sql.
-- NO APLICAR AUTOMÁTICAMENTE: este archivo lo pega el usuario en el editor SQL.
--
-- REVERSIBILIDAD: ver el bloque comentado al final. No borra datos: los planes
-- semilla de la 73 se revierten por separado.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Comprobación previa (falla claro y no a mitad) ───────────────────────
do $pre$
begin
  if to_regclass('flow.entidad') is null then
    raise exception 'Falta flow.entidad (esquema base de flow).';
  end if;
  if to_regclass('flow.suscripcion_plan') is null
     or to_regclass('flow.suscripcion') is null
     or to_regclass('flow.suscripcion_config') is null then
    raise exception 'Falta el módulo de suscripciones (migraciones 43-46).';
  end if;
  if to_regclass('flow.app_dat_locales') is null
     or to_regclass('flow.app_dat_servicios') is null
     or to_regclass('flow.local_servicio') is null then
    raise exception 'Falta el catálogo base de flow (locales/servicios/local_servicio).';
  end if;
  if to_regclass('flow.entidad_admin') is null
     or to_regclass('flow.entidad_vendedor') is null then
    raise exception 'Faltan flow.entidad_admin / flow.entidad_vendedor (migraciones base).';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'app_dat_locales'
                    and column_name = 'id_entidad') then
    raise exception 'flow.app_dat_locales.id_entidad no existe: no se puede aplicar el límite de locales.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'app_dat_servicios'
                    and column_name = 'id_entidad') then
    raise exception 'flow.app_dat_servicios.id_entidad no existe: no se puede aplicar el límite de servicios de catálogo.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'local_servicio'
                    and column_name = 'id_local') then
    raise exception 'flow.local_servicio.id_local no existe: no se puede aplicar el límite de servicios por local.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'entidad'
                    and column_name = 'owner_uuid') then
    raise exception 'flow.entidad.owner_uuid no existe: no se puede contar el límite de entidades.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'entidad_admin'
                    and column_name = 'id_entidad')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'flow' and table_name = 'entidad_vendedor'
                       and column_name = 'id_entidad') then
    raise exception 'flow.entidad_admin / flow.entidad_vendedor no tienen id_entidad: no se puede contar el límite de usuarios.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access() (migración 28).';
  end if;
  if to_regprocedure('flow.admin_entidades_de_usuario(uuid)') is null then
    raise exception 'Falta flow.admin_entidades_de_usuario(uuid) (migración base).';
  end if;
  if to_regprocedure('flow.entidad_activa(integer)') is null then
    raise exception 'Falta flow.entidad_activa(integer) (migración 44).';
  end if;
end
$pre$;

-- ══ 1. COLUMNAS NUEVAS DE `flow.suscripcion_plan` ═══════════════════════════
--
-- Se añaden sin la FK inline y luego la FK aparte, para que reejecutar el bloque
-- sea idempotente aunque la columna ya exista de una ejecución anterior.

alter table flow.suscripcion_plan
  add column if not exists id_entidad integer;

alter table flow.suscripcion_plan
  add column if not exists modalidad text not null default 'pago';

alter table flow.suscripcion_plan
  add column if not exists etiqueta text;

-- FK del plan privado: si se borra la entidad, sus planes privados se van con
-- ella (no tiene sentido un plan privado huérfano).
-- NOTA: si esa entidad tuviera intents de compra apuntando al plan privado, el
-- borrado puede fallar por el `on delete restrict` de suscripcion_intent.id_plan
-- (PostgreSQL resuelve los cascados en orden no garantizado). En ese caso, el
-- superadmin debe desactivar el plan (admin_plan_eliminar ya lo hace) en vez de
-- borrar la entidad.
alter table flow.suscripcion_plan
  drop constraint if exists suscripcion_plan_id_entidad_fkey;
alter table flow.suscripcion_plan
  add constraint suscripcion_plan_id_entidad_fkey
  foreign key (id_entidad) references flow.entidad(id) on delete cascade;

-- CHECK de modalidad (idempotente: se recrea para que el nombre sea estable).
alter table flow.suscripcion_plan
  drop constraint if exists suscripcion_plan_modalidad_chk;
alter table flow.suscripcion_plan
  add constraint suscripcion_plan_modalidad_chk
  check (modalidad in ('pago','contacto'));

comment on column flow.suscripcion_plan.id_entidad is
  'NULL = plan público (visible para todos). NOT NULL = plan privado de esa entidad: sólo su dueño/admin y el superadmin lo ven.';
comment on column flow.suscripcion_plan.modalidad is
  'pago = se paga por Transfermóvil con intent. contacto = "Contactar con ventas" (WhatsApp), no genera intent de pago.';
comment on column flow.suscripcion_plan.etiqueta is
  'Cinta de la tarjeta del plan ("Más popular", "Recomendado"). NULL = sin cinta.';
comment on column flow.suscripcion_plan.limites is
  'Límites del plan: claves entidades, locales, servicios_por_local, servicios_catalogo, usuarios. Número > 0 = límite; ausente/null/0/negativo = SIN límite.';

-- Índice para resolver rápido la RLS por entidad y las consultas del panel.
create index if not exists idx_suscripcion_plan_entidad
  on flow.suscripcion_plan (id_entidad)
  where id_entidad is not null;

-- ══ 2. RLS DE PLANES: EL PLAN PRIVADO NO SE FILTRA POR TABLA ════════════════
--
-- La migración 43 dejó `suscripcion_plan_select_autenticados using (true)`: la
-- RLS no puede ver lo que el RPC filtra. Un usuario autenticado podía leer por
-- PostgREST los planes privados de otra entidad. Se reemplaza por una política
-- que respeta la privacidad. El superadmin conserva acceso total (la política
-- ALL de escritura ya lo cubre; el OR con la función lo deja explícito).
drop policy if exists suscripcion_plan_select_autenticados on flow.suscripcion_plan;
drop policy if exists suscripcion_plan_select_publico_o_propio on flow.suscripcion_plan;
create policy suscripcion_plan_select_publico_o_propio on flow.suscripcion_plan
  for select to authenticated
  using (
    id_entidad is null
    or public.fn_is_superadmin_full_access()
    or id_entidad in (
         select a.id_entidad
         from flow.admin_entidades_de_usuario(auth.uid()) a
       )
  );

-- ══ 3. ÍNDICES DE APOYO PARA LOS CONTEOS DE LOS TRIGGERS ════════════════════
--
-- Los triggers cuentan por estas columnas en cada INSERT y ninguna tenía índice
-- (comprobado con MCP contra la base real el 2026-10-29). Son índices pequeños y
-- baratos; evitan un seq scan en cada alta de local/servicio/entidad.
create index if not exists idx_app_dat_locales_entidad
  on flow.app_dat_locales (id_entidad);
create index if not exists idx_app_dat_servicios_entidad
  on flow.app_dat_servicios (id_entidad);
create index if not exists idx_entidad_owner_uuid
  on flow.entidad (owner_uuid);

-- ══ 4. FUNCIONES NUEVAS ═════════════════════════════════════════════════════

-- ── 4.1 Plan vivo de la entidad y sus límites ───────────────────────────────
--
-- Devuelve siempre la misma forma: {ok, data:{plan_id, plan_codigo,
-- plan_nombre, limites, vigente}}. Sin fila de suscripción o sin plan:
-- limites = '{}' (sin límites, mismo espíritu que `flow.entidad_activa`).
create or replace function flow.entidad_limites(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_susc    flow.suscripcion%rowtype;
  v_plan    flow.suscripcion_plan%rowtype;
  v_limites jsonb := '{}'::jsonb;
begin
  if p_id_entidad is null then
    return jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'plan_id',     null,
      'plan_codigo', null,
      'plan_nombre', null,
      'limites',     '{}'::jsonb,
      'vigente',     false
    ));
  end if;

  -- Mismo criterio de orden que `flow.entidad_activa`: primero las filas vivas
  -- (el índice único parcial de la 43 garantiza como mucho una) y después la
  -- más reciente.
  select s.* into v_susc
  from flow.suscripcion s
  where s.id_entidad = p_id_entidad
  order by
    (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
    s.updated_at desc,
    s.id desc
  limit 1;

  if found and v_susc.id_plan is not null then
    select p.* into v_plan
    from flow.suscripcion_plan p
    where p.id = v_susc.id_plan;
  end if;

  if v_plan.id is not null and jsonb_typeof(v_plan.limites) = 'object' then
    v_limites := v_plan.limites;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'plan_id',     v_plan.id,
    'plan_codigo', v_plan.codigo,
    'plan_nombre', v_plan.nombre,
    'limites',     v_limites,
    'vigente',     flow.entidad_activa(p_id_entidad)
  ));
end;
$function$;

comment on function flow.entidad_limites(integer) is
  'Plan vivo de la entidad con sus limites. Sin suscripcion/plan devuelve limites {} (=sin limites, grandfathering).';

-- ── 4.2 Cálculo interno: usado, máximo, bloqueo y mensaje ──────────────────
--
-- No es parte del contrato de la app: lo usan `entidad_limite_alcanzado` y el
-- trigger. Los parámetros extra (p_owner_uuid, p_id_local) existen porque el
-- trigger trabaja con la fila que AÚN no existe: para `entidades` hay que contar
-- por owner_uuid y para `servicios_por_local` hay que mirar un local concreto.
create or replace function flow._limite_plan_evaluar(
  p_id_entidad integer,
  p_recurso    text,
  p_extra      integer default 1,
  p_owner_uuid uuid    default null,
  p_id_local   integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_recurso       text;
  v_extra         integer;
  v_owner         uuid;
  v_plan_entidad  integer := p_id_entidad;
  v_lim_json      jsonb;
  v_limites       jsonb := '{}'::jsonb;
  v_plan_nombre   text;
  v_max           integer;
  v_usado         integer := 0;
  v_bloqueado     boolean := false;
  v_mensaje       text;
begin
  v_recurso := lower(btrim(coalesce(p_recurso, '')));

  if v_recurso not in ('entidades','locales','servicios_por_local',
                       'servicios_catalogo','usuarios') then
    return jsonb_build_object('ok', false,
      'error', 'Recurso no válido: ' || coalesce(p_recurso, '(null)') ||
               '. Valores admitidos: entidades, locales, servicios_por_local, servicios_catalogo, usuarios.');
  end if;

  v_extra := greatest(coalesce(p_extra, 1), 0);

  -- Dueño de la cuenta (para el recurso 'entidades').
  if p_owner_uuid is not null then
    v_owner := p_owner_uuid;
  elsif p_id_entidad is not null then
    select e.owner_uuid into v_owner
    from flow.entidad e
    where e.id = p_id_entidad;
  end if;

  -- Para 'entidades' el plan que manda es el del DUEÑO: el de la suscripción
  -- viva más reciente de cualquiera de sus entidades. Así el límite se aplica al
  -- crear la segunda entidad, cuando la primera ya tiene plan.
  if v_recurso = 'entidades' and v_owner is not null then
    select s.id_entidad into v_plan_entidad
    from flow.suscripcion s
    join flow.entidad e on e.id = s.id_entidad
    where e.owner_uuid = v_owner
    order by
      -- Primero las que sí tienen plan contratado (una fila de trial con id_plan
      -- NULL no debe tapar el plan de pago del dueño), después las vivas y luego
      -- la más reciente.
      (s.id_plan is not null) desc,
      (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
      s.updated_at desc,
      s.id desc
    limit 1;
  end if;

  -- Límites del plan vivo (o {} si no hay).
  if v_plan_entidad is not null then
    v_lim_json    := flow.entidad_limites(v_plan_entidad);
    v_limites     := coalesce((v_lim_json #> '{data,limites}'), '{}'::jsonb);
    v_plan_nombre := v_lim_json #>> '{data,plan_nombre}';
  end if;

  if v_limites is null or jsonb_typeof(v_limites) <> 'object' then
    v_limites := '{}'::jsonb;
  end if;

  -- Máximo del recurso: sólo un número jsonb > 0 cuenta como límite.
  v_max := case
             when jsonb_typeof(v_limites -> v_recurso) = 'number' then
               case
                 when (v_limites ->> v_recurso)::numeric > 0
                   then ceil((v_limites ->> v_recurso)::numeric)::integer
                 else null
               end
             else null
           end;

  -- Cupo usado AHORA (la fila que se está insertando no cuenta todavía).
  if v_recurso = 'entidades' then
    select count(*) into v_usado
    from flow.entidad e
    where e.owner_uuid = v_owner;
  elsif v_recurso = 'locales' then
    select count(*) into v_usado
    from flow.app_dat_locales l
    where l.id_entidad = p_id_entidad;
  elsif v_recurso = 'servicios_catalogo' then
    select count(*) into v_usado
    from flow.app_dat_servicios s
    where s.id_entidad = p_id_entidad;
  elsif v_recurso = 'servicios_por_local' then
    if p_id_local is not null then
      select count(*) into v_usado
      from flow.local_servicio ls
      where ls.id_local = p_id_local;
    else
      -- Sin local concreto (consulta pública del panel): el "usado" es el local
      -- más cargado, que es lo que de verdad se compara con el límite por local.
      select coalesce(max(q.c), 0) into v_usado
      from (
        select count(*) as c
        from flow.local_servicio ls
        join flow.app_dat_locales l on l.id = ls.id_local
        where l.id_entidad = p_id_entidad
        group by ls.id_local
      ) q;
    end if;
  elsif v_recurso = 'usuarios' then
    -- Un solo cupo para administradores + vendedores (ver cabecera).
    select
      (select count(*) from flow.entidad_admin a where a.id_entidad = p_id_entidad)
      + (select count(*) from flow.entidad_vendedor v where v.id_entidad = p_id_entidad)
    into v_usado;
  end if;

  if v_max is not null and v_usado + v_extra > v_max then
    v_bloqueado := true;
    v_mensaje := 'ERR_LIMITE_PLAN: Tu plan ' || coalesce(v_plan_nombre, 'actual')
                 || ' permite ' || v_max || ' '
                 || case v_recurso
                      when 'entidades' then
                        'entidad' || case when v_max = 1 then '' else 'es' end
                      when 'locales' then
                        'local' || case when v_max = 1 then '' else 'es' end
                      when 'servicios_catalogo' then
                        'servicio' || case when v_max = 1 then '' else 's' end
                        || ' en el catálogo'
                      when 'servicios_por_local' then
                        'servicio' || case when v_max = 1 then '' else 's' end
                        || ' por local'
                      when 'usuarios' then
                        'usuario' || case when v_max = 1 then '' else 's' end
                    end
                 || ' y '
                 || case v_recurso
                      when 'servicios_por_local' then
                        case when p_id_local is not null
                             then 'este local ya tiene '
                             else 'tu local más cargado ya tiene ' end
                      else 'ya usas '
                    end
                 || v_usado || '. Mejora tu plan para añadir más.';
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'bloqueado',   v_bloqueado,
    'recurso',     v_recurso,
    'usado',       v_usado,
    'maximo',      v_max,
    'plan_nombre', v_plan_nombre,
    'mensaje',     v_mensaje
  ));
end;
$function$;

comment on function flow._limite_plan_evaluar(integer,text,integer,uuid,integer) is
  'Calculo interno de cupo (usado/maximo/bloqueo/mensaje). Lo usan entidad_limite_alcanzado y los triggers. No es contrato de la app.';

-- ── 4.3 RPC público: ¿está alcanzado el límite al añadir p_extra? ──────────
create or replace function flow.entidad_limite_alcanzado(
  p_id_entidad integer,
  p_recurso    text,
  p_extra      integer default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
begin
  if p_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'Falta el id de la entidad');
  end if;

  return flow._limite_plan_evaluar(p_id_entidad, p_recurso, p_extra, null, null);
end;
$function$;

comment on function flow.entidad_limite_alcanzado(integer,text,integer) is
  'Dice si el plan vivo de la entidad impide añadir p_extra recursos de p_recurso. Sin limite: bloqueado=false y maximo=null. El mensaje empieza por ERR_LIMITE_PLAN: cuando bloquea.';

-- ── 4.4 Trigger común de límites ────────────────────────────────────────────
--
-- Un solo trigger para las seis tablas: deduce del TG_TABLE_NAME el recurso y
-- de la fila NEW el contexto (entidad / owner / local). Si el recurso no tiene
-- límite, no hace nada. Si lo hay y se supera, lanza P0001 con el mensaje
-- ERR_LIMITE_PLAN: ya formateado.
create or replace function flow._trg_limite_plan()
returns trigger
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_recurso   text;
  v_id_entidad integer;
  v_owner     uuid;
  v_id_local  integer;
  v_res       jsonb;
begin
  v_recurso := case tg_table_name
                 when 'entidad'         then 'entidades'
                 when 'app_dat_locales'  then 'locales'
                 when 'app_dat_servicios' then 'servicios_catalogo'
                 when 'local_servicio'   then 'servicios_por_local'
                 when 'entidad_admin'    then 'usuarios'
                 when 'entidad_vendedor' then 'usuarios'
                 else null
               end;

  if v_recurso is null then
    return new;
  end if;

  if tg_table_name = 'entidad' then
    v_id_entidad := new.id;
    v_owner      := new.owner_uuid;
  elsif tg_table_name = 'local_servicio' then
    v_id_local := new.id_local;
    select l.id_entidad into v_id_entidad
    from flow.app_dat_locales l
    where l.id = new.id_local;
  else
    v_id_entidad := new.id_entidad;
  end if;

  -- Sin entidad no hay plan que aplicar: lo rechazará la FK/RLS, no el límite.
  if v_id_entidad is null then
    return new;
  end if;

  v_res := flow._limite_plan_evaluar(v_id_entidad, v_recurso, 1, v_owner, v_id_local);

  -- Si el cálculo devolviera error (recurso desconocido), no se inventa un
  -- bloqueo: se deja pasar y que falle lo que tenga que fallar.
  if not coalesce((v_res #>> '{ok}')::boolean, false) then
    return new;
  end if;

  if coalesce((v_res #>> '{data,bloqueado}')::boolean, false) then
    raise exception using
      errcode = 'P0001',
      message = coalesce(v_res #>> '{data,mensaje}',
                         'ERR_LIMITE_PLAN: Tu plan actual no permite crear más recursos. Mejora tu plan para añadir más.'),
      hint    = 'Revisa tu plan en Mi suscripción o contacta con ventas.';
  end if;

  return new;
end;
$function$;

comment on function flow._trg_limite_plan() is
  'Trigger BEFORE INSERT comun: aplica los limites del plan vivo y lanza P0001 con el mensaje ERR_LIMITE_PLAN: cuando el cupo esta lleno.';

-- ══ 5. TRIGGERS (idempotentes: drop if exists + create) ═════════════════════
--
-- IMPORTANTE: tanto la app Flutter como el panel insertan estas filas
-- directamente por PostgREST (RLS); NO existe RPC intermedio. Este trigger es el
-- único enforcement posible. BEFORE INSERT = sólo bloquea altas nuevas, nunca
-- toca lo que ya existe.

drop trigger if exists trg_limite_entidades on flow.entidad;
create trigger trg_limite_entidades
  before insert on flow.entidad
  for each row execute function flow._trg_limite_plan();

drop trigger if exists trg_limite_locales on flow.app_dat_locales;
create trigger trg_limite_locales
  before insert on flow.app_dat_locales
  for each row execute function flow._trg_limite_plan();

drop trigger if exists trg_limite_servicios on flow.app_dat_servicios;
create trigger trg_limite_servicios
  before insert on flow.app_dat_servicios
  for each row execute function flow._trg_limite_plan();

drop trigger if exists trg_limite_local_servicio on flow.local_servicio;
create trigger trg_limite_local_servicio
  before insert on flow.local_servicio
  for each row execute function flow._trg_limite_plan();

drop trigger if exists trg_limite_usuarios_admin on flow.entidad_admin;
create trigger trg_limite_usuarios_admin
  before insert on flow.entidad_admin
  for each row execute function flow._trg_limite_plan();

drop trigger if exists trg_limite_usuarios_vendedor on flow.entidad_vendedor;
create trigger trg_limite_usuarios_vendedor
  before insert on flow.entidad_vendedor
  for each row execute function flow._trg_limite_plan();

-- ══ 6. RPC REDEFINIDOS ══════════════════════════════════════════════════════

-- ── 6.1 admin_planes_listar() ───────────────────────────────────────────────
create or replace function flow.admin_planes_listar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede ver los planes');
  end if;

  return jsonb_build_object('ok', true, 'data', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',                   p.id,
             'codigo',               p.codigo,
             'nombre',               p.nombre,
             'descripcion',          p.descripcion,
             'duracion_dias',        p.duracion_dias,
             'precio',               p.precio,
             'moneda',               p.moneda,
             'limites',              p.limites,
             'orden',                p.orden,
             'activo',               p.activo,
             'created_at',           p.created_at,
             'updated_at',           p.updated_at,
             'id_entidad',           p.id_entidad,
             'entidad_denominacion', e.denominacion,
             'modalidad',            p.modalidad,
             'etiqueta',             p.etiqueta)
           order by p.orden, p.precio, p.id)
    from flow.suscripcion_plan p
    left join flow.entidad e on e.id = p.id_entidad), '[]'::jsonb));
end;
$function$;

comment on function flow.admin_planes_listar() is
  'Superadmin: todos los planes, activos e inactivos, con id_entidad/entidad_denominacion/modalidad/etiqueta.';

-- ── 6.2 admin_plan_guardar(...) ─────────────────────────────────────────────
--
-- ⚠ La firma cambia (10 -> 13 argumentos). Hay que BORRAR la vieja o PostgreSQL
-- crea una sobrecarga y PostgREST queda ambiguo (corrección del lead).
drop function if exists flow.admin_plan_guardar(
  bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean);

create or replace function flow.admin_plan_guardar(
  p_id            bigint  default null,
  p_codigo        text    default null,
  p_nombre        text    default null,
  p_descripcion   text    default null,
  p_duracion_dias integer default null,
  p_precio        numeric default null,
  p_moneda        text    default null,
  p_limites       jsonb   default null,
  p_orden         integer default null,
  p_activo        boolean default null,
  p_modalidad     text    default null,
  p_id_entidad    integer default null,
  p_etiqueta      text    default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_uid        uuid := auth.uid();
  v_id         bigint := p_id;
  v_plan       flow.suscripcion_plan%rowtype;
  v_codigo     text;
  v_modalidad  text;
  v_id_entidad integer;
  v_etiqueta   text;
  v_aviso      text;
  v_n          integer := 1;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar planes');
  end if;

  -- ── Validaciones comunes de los campos nuevos ──
  if p_modalidad is not null and btrim(p_modalidad) <> ''
     and lower(btrim(p_modalidad)) not in ('pago','contacto') then
    return jsonb_build_object('ok', false,
      'error', 'La modalidad debe ser "pago" o "contacto"');
  end if;

  if p_limites is not null and jsonb_typeof(p_limites) <> 'object' then
    return jsonb_build_object('ok', false,
      'error', 'Los limites deben ser un objeto jsonb (por ejemplo {"locales":2})');
  end if;

  if p_id_entidad is not null and p_id_entidad < 0 then
    return jsonb_build_object('ok', false,
      'error', 'El id de entidad no puede ser negativo (0 = plan publico)');
  end if;

  -- La entidad del plan privado debe existir (la FK lo rechazaría, pero con un
  -- mensaje críptico; aquí se devuelve un error legible).
  if p_id_entidad is not null and p_id_entidad > 0
     and not exists (select 1 from flow.entidad e where e.id = p_id_entidad) then
    return jsonb_build_object('ok', false,
      'error', 'La entidad ' || p_id_entidad ||
               ' no existe: no se puede crear/editar un plan privado para ella');
  end if;

  -- ── CREAR ──
  if v_id is null then
    v_modalidad  := coalesce(nullif(lower(btrim(coalesce(p_modalidad, ''))), ''), 'pago');
    v_id_entidad := nullif(p_id_entidad, 0);  -- 0 = público
    v_codigo     := nullif(btrim(coalesce(p_codigo, '')), '');

    -- `codigo` es UNIQUE global: un plan privado sin código necesita uno
    -- generado. Se busca el primer sufijo libre para que reejecutar no choque.
    if v_codigo is null and v_id_entidad is not null then
      loop
        v_codigo := 'privado_' || v_id_entidad || '_' || v_n;
        exit when not exists (
          select 1 from flow.suscripcion_plan p2 where p2.codigo = v_codigo
        );
        v_n := v_n + 1;
      end loop;
    end if;

    if v_codigo is null or p_nombre is null or btrim(p_nombre) = ''
       or p_duracion_dias is null or p_duracion_dias <= 0 then
      return jsonb_build_object('ok', false,
        'error', 'Para crear un plan hacen falta nombre y duracion en dias (el codigo puede generarse solo si el plan es privado)');
    end if;

    if exists (select 1 from flow.suscripcion_plan p2 where p2.codigo = v_codigo) then
      return jsonb_build_object('ok', false, 'error', 'Ya existe un plan con ese codigo');
    end if;

    v_etiqueta := nullif(btrim(coalesce(p_etiqueta, '')), '');

    insert into flow.suscripcion_plan
      (codigo, nombre, descripcion, duracion_dias, precio, moneda, limites,
       orden, activo, modalidad, id_entidad, etiqueta, updated_by)
    values
      (v_codigo, btrim(p_nombre), p_descripcion, p_duracion_dias,
       coalesce(p_precio, 0),
       coalesce(nullif(btrim(coalesce(p_moneda, '')), ''), 'CUP'),
       coalesce(p_limites, '{}'::jsonb), coalesce(p_orden, 0),
       coalesce(p_activo, false),
       v_modalidad, v_id_entidad, v_etiqueta, v_uid)
    returning id into v_id;

    if v_modalidad = 'pago' and coalesce(p_precio, 0) = 0
       and coalesce(p_activo, false) then
      v_aviso := 'Plan de pago activo con precio 0: se podrá "comprar" sin pagar. Confirma que es un plan de cortesía.';
    end if;

    return jsonb_build_object('ok', true, 'data',
      jsonb_build_object('id', v_id, 'creado', true, 'codigo', v_codigo)
      || case when v_aviso is null then '{}'::jsonb
              else jsonb_build_object('aviso', v_aviso) end);
  end if;

  -- ── ACTUALIZAR ──
  select p.* into v_plan
  from flow.suscripcion_plan p
  where p.id = v_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'El plan no existe');
  end if;

  if p_codigo is not null and btrim(p_codigo) <> v_plan.codigo
     and exists (select 1 from flow.suscripcion_plan p2
                  where p2.codigo = btrim(p_codigo) and p2.id <> v_id) then
    return jsonb_build_object('ok', false, 'error', 'Ya existe un plan con ese codigo');
  end if;

  -- NULL conserva (necesario para el toggle activo/inactivo que llama
  -- guardarPlan(id:, activo:) con el resto de parámetros a NULL).
  v_modalidad := case
                   when p_modalidad is null or btrim(p_modalidad) = ''
                     then v_plan.modalidad
                   else lower(btrim(p_modalidad))
                 end;

  -- 0 publica el plan (id_entidad = NULL); NULL conserva.
  v_id_entidad := case
                    when p_id_entidad is null then v_plan.id_entidad
                    when p_id_entidad = 0    then null
                    else p_id_entidad
                  end;

  -- Cadena vacía quita la cinta; NULL conserva.
  v_etiqueta := case
                  when p_etiqueta is null then v_plan.etiqueta
                  when btrim(p_etiqueta) = '' then null
                  else btrim(p_etiqueta)
                end;

  update flow.suscripcion_plan p
     set codigo        = coalesce(nullif(btrim(coalesce(p_codigo, '')), ''), p.codigo),
         nombre        = coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), p.nombre),
         descripcion   = coalesce(p_descripcion, p.descripcion),
         duracion_dias = coalesce(p_duracion_dias, p.duracion_dias),
         precio        = coalesce(p_precio, p.precio),
         moneda        = coalesce(nullif(btrim(coalesce(p_moneda, '')), ''), p.moneda),
         limites       = coalesce(p_limites, p.limites),
         orden         = coalesce(p_orden, p.orden),
         activo        = coalesce(p_activo, p.activo),
         modalidad     = v_modalidad,
         id_entidad    = v_id_entidad,
         etiqueta      = v_etiqueta,
         updated_by    = v_uid
   where p.id = v_id;

  if v_modalidad = 'pago' and coalesce(p_precio, v_plan.precio) = 0
     and coalesce(p_activo, v_plan.activo) then
    v_aviso := 'Plan de pago activo con precio 0: se podrá "comprar" sin pagar. Confirma que es un plan de cortesía.';
  end if;

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('id', v_id, 'creado', false)
    || case when v_aviso is null then '{}'::jsonb
            else jsonb_build_object('aviso', v_aviso) end);
end;
$function$;

comment on function flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean,text,integer,text) is
  'Superadmin: crea o actualiza un plan. Firma nueva con modalidad/id_entidad/etiqueta al final (p_id_entidad: 0 = publicar, NULL = conservar en update).';

-- ── 6.3 cliente_planes_suscripcion() ────────────────────────────────────────
--
-- Públicos + privados de las entidades que el llamante administra. GUARDA DE
-- ANON (corrección del lead): la función está concedida a anon y `auth.uid()`
-- puede ser NULL; la condición se escribe de forma que sin sesión sólo salgan
-- los públicos y NUNCA falle.
create or replace function flow.cliente_planes_suscripcion()
returns jsonb
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  select jsonb_build_object(
    'ok', true,
    'data', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id',                   p.id,
                  'codigo',               p.codigo,
                  'nombre',               p.nombre,
                  'descripcion',          p.descripcion,
                  'duracion_dias',        p.duracion_dias,
                  'precio',               p.precio,
                  'moneda',               p.moneda,
                  'limites',              p.limites,
                  'orden',                p.orden,
                  'modalidad',            p.modalidad,
                  'etiqueta',             p.etiqueta,
                  'es_privado',           (p.id_entidad is not null),
                  'id_entidad',           p.id_entidad,
                  'entidad_denominacion', e.denominacion,
                  'contacto_whatsapp',    cfg.soporte_whatsapp
                ) order by p.orden, p.precio, p.id)
         from flow.suscripcion_plan p
         left join flow.entidad e on e.id = p.id_entidad
         left join flow.suscripcion_config cfg on cfg.id = 1
        where p.activo
          and (
            p.id_entidad is null
            or (
              auth.uid() is not null
              and p.id_entidad in (
                select a.id_entidad
                from flow.admin_entidades_de_usuario(auth.uid()) a
              )
            )
          )),
      '[]'::jsonb
    )
  );
$function$;

comment on function flow.cliente_planes_suscripcion() is
  'Planes activos para "Mi suscripción": públicos + privados de las entidades del llamante. Con anon sólo públicos. Incluye modalidad, etiqueta, es_privado y contacto_whatsapp.';

-- ── 6.4 cliente_crear_intent_suscripcion(...) ───────────────────────────────
--
-- Copia exacta de la 45 + la validación de plan privado (nuevo). El resto del
-- comportamiento (mensajes, cálculo de importe, deep link y transacción) queda
-- intacto a propósito.
create or replace function flow.cliente_crear_intent_suscripcion(
  p_id_entidad integer,
  p_id_plan    bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_cfg    flow.suscripcion_config%rowtype;
  v_plan   flow.suscripcion_plan%rowtype;
  v_monto  numeric(12,2);
  v_moneda text;
  v_importe_txt text;
  v_id_trx text;
  v_url_intent text;
  v_url_http   text;
  v_expira timestamptz;
  v_id     bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  if not flow._susc_caller_ve_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false,
      'error', 'Solo el dueno o un administrador de la entidad puede pagar su suscripcion');
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta la configuracion de suscripciones');
  end if;

  select p.* into v_plan
  from flow.suscripcion_plan p
  where p.id = p_id_plan and p.activo;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El plan no existe o esta inactivo');
  end if;

  -- NUEVO (72): un plan privado sólo lo puede comprar SU entidad. Un plan
  -- público (id_entidad NULL) lo puede comprar cualquiera.
  if v_plan.id_entidad is not null and v_plan.id_entidad <> p_id_entidad then
    return jsonb_build_object('ok', false,
      'error', 'Este plan no está disponible para esta entidad');
  end if;

  v_monto  := v_plan.precio;
  v_moneda := coalesce(nullif(btrim(v_plan.moneda), ''), v_cfg.moneda_default, 'CUP');

  -- Transfermovil espera 1500, no 1500.00. Si el precio tiene centavos se envian.
  v_importe_txt := case
                     when v_monto = trunc(v_monto) then trunc(v_monto)::bigint::text
                     else to_char(v_monto, 'FM9999999990.00')
                   end;

  -- Referencia interna UNICA por intent. NO viaja en el link: es un bug de la
  -- app de Transfermovil, que trata el id_transaccion como estatico ("ESTATICO")
  -- aunque se mande uno unico. El link lleva el literal ESTATICO; esta
  -- referencia queda para que SOPORTE ubique el intento en el panel y para
  -- auditar.
  v_id_trx := 'FLW-' || p_id_entidad || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           v_moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           v_moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  insert into flow.suscripcion_intent
    (id_entidad, id_plan, uuid_usuario, monto, moneda, id_transaccion,
     numero_proveedor, url_intent, url_http, estado, expira_at)
  values
    (p_id_entidad, v_plan.id, v_uid, v_monto, v_moneda, v_id_trx,
     v_cfg.transfermovil_numero_proveedor, v_url_intent, v_url_http, 'creado', v_expira)
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                v_id,
      'id_entidad',        p_id_entidad,
      'id_plan',           v_plan.id,
      'plan_nombre',       v_plan.nombre,
      'duracion_dias',     v_plan.duracion_dias,
      'monto',             v_monto,
      'moneda',            v_moneda,
      'importe',           v_importe_txt,
      'id_transaccion',    v_id_trx,
      'numero_proveedor',  v_cfg.transfermovil_numero_proveedor,
      'titulo',            v_cfg.transfermovil_titulo,
      'url_intent',        v_url_intent,
      'url_http',          v_url_http,
      'expira_at',         v_expira,
      'soporte_whatsapp',  v_cfg.soporte_whatsapp,
      'modo_prueba',       coalesce(v_cfg.modo_prueba, false)
    )
  );
end;
$function$;

comment on function flow.cliente_crear_intent_suscripcion(integer,bigint) is
  'Crea el intent de pago de Transfermovil con id_transaccion unico y devuelve el deep link y el respaldo https. Valida que el plan sea publico o privado de esa entidad.';

-- ══ 7. PERMISOS ═════════════════════════════════════════════════════════════
--
-- `admin_plan_guardar` cambió de firma: al DROP se fueron sus ACL, así que hay
-- que volver a concederlas. Las otras tres se redefinen con `create or replace`
-- (misma firma): conservan sus grants, pero se reafirman aquí para idempotencia.

revoke all on function flow.admin_plan_guardar(
  bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean,text,integer,text) from public;
grant execute on function flow.admin_plan_guardar(
  bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean,text,integer,text) to authenticated;
grant execute on function flow.admin_plan_guardar(
  bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean,text,integer,text) to service_role;

revoke all on function flow.admin_planes_listar() from public;
grant execute on function flow.admin_planes_listar() to authenticated;
grant execute on function flow.admin_planes_listar() to service_role;

revoke all on function flow.cliente_planes_suscripcion() from public;
grant execute on function flow.cliente_planes_suscripcion() to anon;
grant execute on function flow.cliente_planes_suscripcion() to authenticated;
grant execute on function flow.cliente_planes_suscripcion() to service_role;

revoke all on function flow.cliente_crear_intent_suscripcion(integer,bigint) from public;
grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to authenticated;
grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to service_role;

revoke all on function flow.entidad_limites(integer) from public;
grant execute on function flow.entidad_limites(integer) to authenticated;
grant execute on function flow.entidad_limites(integer) to service_role;

revoke all on function flow.entidad_limite_alcanzado(integer,text,integer) from public;
grant execute on function flow.entidad_limite_alcanzado(integer,text,integer) to authenticated;
grant execute on function flow.entidad_limite_alcanzado(integer,text,integer) to service_role;

-- El trigger lo disparan INSERT de authenticated y de service_role (anon nunca
-- inserta, pero se concede por si alguna política futura lo permitiera). OJO:
-- las funciones que devuelven `trigger` no se pueden invocar como RPC.
revoke all on function flow._trg_limite_plan() from public;
grant execute on function flow._trg_limite_plan() to anon, authenticated, service_role;

-- Helper interno: lo llaman funciones SECURITY DEFINER (postgres), no la app.
revoke all on function flow._limite_plan_evaluar(integer,text,integer,uuid,integer) from public;
grant execute on function flow._limite_plan_evaluar(integer,text,integer,uuid,integer) to service_role;

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
-- 8. VERIFICACIÓN (comentada: ejecutar a mano DESPUÉS de aplicar)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 8.1 Columnas nuevas (esperado: 3 filas).
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'flow' and table_name = 'suscripcion_plan'
--    and column_name in ('id_entidad','modalidad','etiqueta')
--  order by column_name;
--
-- 8.2 Restricciones nuevas (FK a entidad y CHECK de modalidad).
-- select conname, pg_get_constraintdef(oid) as definicion
--   from pg_constraint
--  where conrelid = 'flow.suscripcion_plan'::regclass
--    and conname in ('suscripcion_plan_id_entidad_fkey',
--                    'suscripcion_plan_modalidad_chk');
--
-- 8.3 Los seis triggers existen (esperado: 6 filas).
-- select tgname, c.relname as tabla
--   from pg_trigger t
--   join pg_class c on c.oid = t.tgrelid
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow' and not t.tgisinternal
--    and t.tgname in ('trg_limite_entidades','trg_limite_locales',
--                     'trg_limite_servicios','trg_limite_local_servicio',
--                     'trg_limite_usuarios_admin','trg_limite_usuarios_vendedor')
--  order by t.tgname;
--
-- 8.4 Firmas de las funciones (esperado: admin_plan_guardar con 13 argumentos
--     y UNA sola fila por función; si salen dos admin_plan_guardar, el DROP de la
--     firma vieja no se ejecutó).
-- select proname, pg_get_function_identity_arguments(oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('admin_plan_guardar','admin_planes_listar',
--                      'cliente_planes_suscripcion','cliente_crear_intent_suscripcion',
--                      'entidad_limites','entidad_limite_alcanzado')
--  order by p.proname, args;
--
-- 8.5 La RLS vieja ya no deja leer todo (esperado: 0 filas).
-- select tablename, policyname from pg_policies
--  where schemaname = 'flow' and tablename = 'suscripcion_plan'
--    and policyname = 'suscripcion_plan_select_autenticados';
--
-- 8.6 Sin sesión (anon) sólo salen planes públicos.
-- select flow.cliente_planes_suscripcion();  -- es_privado debe ser false en todos
--
-- 8.7 Con sesión de una entidad, `entidad_limites` devuelve su plan.
-- select flow.entidad_limites(1);            -- cambiar 1 por una entidad real
--
-- 8.8 PRUEBA DE HUMO DE UN LÍMITE (transacción + rollback: no deja basura).
--     Requiere un usuario de auth existente sin plan con límites (para que el
--     alta de la entidad de prueba no choque con el límite de `entidades`).
--
-- begin;
--   -- 1) Plan de prueba con 1 local como máximo.
--   insert into flow.suscripcion_plan
--     (codigo, nombre, duracion_dias, precio, moneda, limites, orden, activo, modalidad)
--   values
--     ('prueba_limite_72', 'Prueba límite 72', 30, 1, 'USD',
--      '{"entidades":1,"locales":1,"servicios_por_local":1,"servicios_catalogo":1,"usuarios":2}'::jsonb,
--      999, true, 'pago')
--   returning id;                              -- anotar como :pl
--
--   -- 2) Entidad de prueba (el trigger de `entidades` no bloquea: el dueño aún
--   --    no tiene ningún plan con límites). El trigger de trial de la 44 le
--   --    crea automáticamente una suscripción viva.
--   insert into flow.entidad (denominacion, owner_uuid)
--   values ('PRUEBA LIMITE 72', (select id from auth.users limit 1))
--   returning id;                              -- anotar como :ent
--
--   -- 3) Reapuntar ESA suscripción viva al plan de prueba. No se inserta otra:
--   --    el índice ux_suscripcion_entidad_viva sólo admite una por entidad.
--   update flow.suscripcion
--      set id_plan = :pl, estado = 'activa', origen = 'acreditacion_admin',
--          fecha_vencimiento = now() + interval '30 days'
--    where id_entidad = :ent
--      and estado in ('trial','activa','en_gracia','sin_plan','suspendida');
--   -- (si el trial automático estuviera apagado y no hubiera fila viva:)
--   -- insert into flow.suscripcion (id_entidad, id_plan, estado, fecha_vencimiento, origen)
--   -- values (:ent, :pl, 'activa', now() + interval '30 days', 'acreditacion_admin');
--
--   -- 4) Primer local: debe pasar (el cupo usado es 0 y el máximo 1).
--   insert into flow.app_dat_locales (nombre, id_entidad) values ('Local 1', :ent);
--
--   -- 5) Segundo local: DEBE fallar con
--   --    ERROR:  ERR_LIMITE_PLAN: Tu plan Prueba límite 72 permite 1 local y
--   --            ya usas 1. Mejora tu plan para añadir más.
--   insert into flow.app_dat_locales (nombre, id_entidad) values ('Local 2', :ent);
-- rollback;
--
-- 8.9 La consulta pública de cupo responde con la forma esperada.
-- select flow.entidad_limite_alcanzado(1, 'locales');         -- {ok:true,data:{...}}
-- select flow.entidad_limite_alcanzado(1, 'inventado');       -- {ok:false,error:...}
--
-- 8.10 Un plan privado sólo lo ve su entidad: con la sesión de OTRA entidad,
--      `cliente_planes_suscripcion` no debe listarlo (es_privado=true ausente).
-- select flow.cliente_planes_suscripcion();
--
-- ════════════════════════════════════════════════════════════════════════════
-- 9. REVERSIÓN (comentada: NO ejecutar salvo que haya que deshacer)
-- ════════════════════════════════════════════════════════════════════════════
--
-- -- 9.1 Quitar los seis triggers.
-- drop trigger if exists trg_limite_usuarios_vendedor on flow.entidad_vendedor;
-- drop trigger if exists trg_limite_usuarios_admin    on flow.entidad_admin;
-- drop trigger if exists trg_limite_local_servicio    on flow.local_servicio;
-- drop trigger if exists trg_limite_servicios         on flow.app_dat_servicios;
-- drop trigger if exists trg_limite_locales           on flow.app_dat_locales;
-- drop trigger if exists trg_limite_entidades         on flow.entidad;
--
-- -- 9.2 Quitar las funciones nuevas y los helpers.
-- drop function if exists flow.entidad_limite_alcanzado(integer,text,integer);
-- drop function if exists flow.entidad_limites(integer);
-- drop function if exists flow._trg_limite_plan();
-- drop function if exists flow._limite_plan_evaluar(integer,text,integer,uuid,integer);
--
-- -- 9.3 Restaurar `admin_plan_guardar` de 10 argumentos: borrar la nueva y
-- --     volver a pegar la definición de 46_suscripciones_admin_cron_seed.sql:546
-- --     (más sus revoke/grant de la línea 814 y 828/840).
-- drop function if exists flow.admin_plan_guardar(
--   bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean,text,integer,text);
--
-- -- 9.4 Restaurar `admin_planes_listar` (46:512), `cliente_planes_suscripcion`
-- --     (44:398) y `cliente_crear_intent_suscripcion` (45:166) volviendo a pegar
-- --     esas definiciones tal cual.
--
-- -- 9.5 Restaurar la política de lectura vieja de planes.
-- drop policy if exists suscripcion_plan_select_publico_o_propio on flow.suscripcion_plan;
-- create policy suscripcion_plan_select_autenticados on flow.suscripcion_plan
--   for select to authenticated using (true);
--
-- -- 9.6 Quitar índices.
-- drop index if exists flow.idx_suscripcion_plan_entidad;
-- drop index if exists flow.idx_app_dat_locales_entidad;
-- drop index if exists flow.idx_app_dat_servicios_entidad;
-- drop index if exists flow.idx_entidad_owner_uuid;
--
-- -- 9.7 Quitar restricciones y columnas (¡destructivo: se pierden los valores de
-- --     id_entidad/modalidad/etiqueta de los planes ya guardados!).
-- alter table flow.suscripcion_plan drop constraint if exists suscripcion_plan_modalidad_chk;
-- alter table flow.suscripcion_plan drop constraint if exists suscripcion_plan_id_entidad_fkey;
-- alter table flow.suscripcion_plan drop column if exists etiqueta;
-- alter table flow.suscripcion_plan drop column if exists modalidad;
-- alter table flow.suscripcion_plan drop column if exists id_entidad;
--
-- notify pgrst, 'reload schema';
-- ════════════════════════════════════════════════════════════════════════════