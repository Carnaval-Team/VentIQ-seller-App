-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 43: SUSCRIPCIONES POR ENTIDAD — TABLAS
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   Crea el modelo de datos de la suscripcion de cada `flow.entidad`:
--
--     · flow.suscripcion_config      -> 1 fila. Lo que configura el superadmin.
--     · flow.suscripcion_plan        -> planes comerciales (duracion + precio).
--     · flow.suscripcion             -> suscripcion de la entidad (1 viva + historico).
--     · flow.suscripcion_intent      -> el "intent" de pago de Transfermovil.
--     · flow.suscripcion_transaccion -> el pago reportado por el cliente.
--     · flow.suscripcion_movimiento  -> libro mayor / auditoria (append-only).
--     · flow.suscripcion_notificacion-> outbox de avisos (in-app y WhatsApp).
--
-- POR QUE TABLAS NUEVAS EN `flow` Y NO REUTILIZAR OTRAS
--   1. `carnavalapp.configuraciones_admin` (transfermovil_intent / transfermovil_url)
--      es de OTRA app y OTRO schema: decision explicita del usuario no usarla.
--   2. `public.app_suscripciones*` es el licenciamiento de las tiendas
--      Inventtia/Carnaval (id_tienda, agentes, catalogo): otra unidad de negocio.
--   3. `flow.plan_config` y `flow.plan_servicios` YA EXISTEN y son la
--      PLANIFICACION MENSUAL DE CUPOS por local-servicio. No tienen nada que ver.
--      Por eso los planes comerciales se llaman `suscripcion_plan`: la palabra
--      "plan" a secas en `flow` significa cupos, y mezclarlas seria un error caro.
--
-- POR QUE UN INTENT APARTE DE LA TRANSACCION
--   El intent es "el cliente abrio el pago" (y puede no pagar nunca). La
--   transaccion es "el cliente dice que pago, con un codigo de confirmacion".
--   Separarlos permite ver el embudo (intents creados vs pagos reportados vs
--   verificados) y deja el intent inmutable como evidencia del importe ofrecido.
--   `id_transaccion` es UNICO a proposito: en Carnaval el id fijo hacia que
--   Transfermovil reutilizara el importe de la transaccion anterior.
--
-- POR QUE `codigo_confirmacion` ES UNIQUE
--   Es la unica defensa anti-reuso que tenemos con verificacion manual: un mismo
--   codigo de confirmacion de Transfermovil no puede acreditar dos planes.
--   (Mismo criterio que `muevete.solicitudes_plan.codigo_transferencia`.)
--
-- POR QUE EL LIBRO DE MOVIMIENTOS ES APPEND-ONLY
--   Acreditar, rechazar o expirar nunca borra: escribe una fila. Asi "por que
--   esta entidad tiene 47 dias" siempre tiene respuesta y se puede auditar.
--
-- DEPENDE DE: esquema base de `flow` (flow.entidad, flow.local_servicio) y
--             public.fn_is_superadmin_full_access() (migracion 28).
--
-- REVERSIBILIDAD
--   drop table if exists flow.suscripcion_notificacion;
--   drop table if exists flow.suscripcion_movimiento;
--   drop table if exists flow.suscripcion_transaccion;
--   drop table if exists flow.suscripcion_intent;
--   drop table if exists flow.suscripcion;
--   drop table if exists flow.suscripcion_plan;
--   drop table if exists flow.suscripcion_config;
--   drop function if exists flow._susc_touch();
--   drop function if exists flow._susc_caller_ve_entidad(integer);
--   (nada mas del esquema base queda tocado: las migraciones 44-46 son las que
--    componen el predicado de visibilidad y el trial)
--
-- ORDEN: 43 -> 44 -> 45 -> 46. Esta NO cambia el comportamiento de nada: solo
--        crea tablas vacias y la configuracion por defecto.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.entidad') is null then
    raise exception 'Falta el esquema base de flow (flow.entidad).';
  end if;

  if to_regclass('flow.local_servicio') is null then
    raise exception 'Falta flow.local_servicio (migraciones base de flow).';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access() (migracion 28_patrocinados.sql).';
  end if;
end
$pre$;

-- ══ 0. Utilidades internas ══════════════════════════════════════════════════

-- updated_at automatico, propio de este modulo: NO se reutiliza
-- `update_updated_at_column` porque vive solo en la base y su firma no esta
-- definida en el repo (ver plan.md), y depender de una firma que no se puede
-- leer es como no tenerla.
create or replace function flow._susc_touch()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

comment on function flow._susc_touch() is
  'Trigger generico de updated_at para las tablas de suscripcion.';

-- Quien consulta: dueno de la entidad o admin asignado. La usa la RLS y los RPC.
-- SECURITY DEFINER para que la RLS pueda resolverla sin recursion y sin depender
-- de `flow.is_entidad_admin` (que existe solo en la base, sin definicion en el
-- repo). Se apoya en `flow.admin_entidades_de_usuario`, que SI esta en el repo.
create or replace function flow._susc_caller_ve_entidad(p_id_entidad integer)
returns boolean
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  select exists (
           select 1
           from flow.entidad e
           where e.id = p_id_entidad
             and e.owner_uuid = auth.uid()
         )
      or exists (
           select 1
           from flow.admin_entidades_de_usuario(auth.uid()) a
           where a.id_entidad = p_id_entidad
         );
$function$;

comment on function flow._susc_caller_ve_entidad(integer) is
  'TRUE si auth.uid() es el owner o un admin asignado de la entidad. Autoriza la lectura de sus datos de suscripcion.';

-- ══ 1. CONFIGURACION (fila unica, la edita el superadmin) ═══════════════════

create table if not exists flow.suscripcion_config (
  id                          smallint primary key default 1,

  -- Meses gratis por entidad nueva (x 30 dias). `trial_auto = false` desactiva
  -- el otorgamiento automatico: las entidades nuevas quedan sin fila (activas,
  -- como hoy) hasta que el superadmin acredite a mano.
  trial_meses_default         integer  not null default 1
                              check (trial_meses_default between 0 and 24),
  trial_auto                  boolean  not null default true,

  -- Anti-abuso: un mismo owner_uuid solo recibe UN trial. Las demas entidades
  -- de ese owner nacen en `sin_plan` (bloqueadas hasta pagar).
  trial_por_usuario           boolean  not null default true,

  -- Margen de retraso antes de cortar la entidad (la "semana de gracia").
  dias_gracia                 integer  not null default 7
                              check (dias_gracia between 0 and 90),

  -- Dias de antelacion con que se avisa "tu suscripcion vence pronto".
  dias_aviso_previo           integer  not null default 7
                              check (dias_aviso_previo between 0 and 90),

  -- Soporte: WhatsApp por defecto al que el cliente reporta su pago.
  soporte_whatsapp            text     not null default '5354590207',
  whatsapp_notif_activa       boolean  not null default false,
  -- Interruptor del despachador automatico. Hoy NO hay bot de WhatsApp para Flow
  -- (Q33: se degrada a deep link wa.me abierto por la app), asi que nace en false
  -- y el outbox registra los avisos como 'omitida' en vez de acumular una cola
  -- 'pendiente' que nadie vacia. Cuando exista el bot se pone en true y las
  -- notificaciones pasan a 'pendiente' para que las recoja la Edge Function.
  whatsapp_bot_activo         boolean  not null default false,

  -- Transfermovil: el intent se arma con estas plantillas. Los tokens son
  -- $id_transaccion, $importe, $moneda, $numero_proveedor, $titulo.
  -- Valores iniciales: los que ya usa Carnaval (decision del usuario: "por
  -- ahora usaremos ese en la tabla, luego pondremos el otro"). Editables desde
  -- el panel del superadmin sin tocar codigo ni recompilar.
  --
  -- id_transaccion va FIJO en "ESTATICO" a proposito: es un bug de la app de
  -- Transfermovil, que trata el id como estatico aunque se mande uno unico
  -- (en carnavalAPP se genero un txId por pago y se acabó comentando:
  -- validacionform_widget.dart:530). Si una plantilla lleva el token
  -- $id_transaccion, la 45 lo sustituye por el LITERAL 'ESTATICO', nunca por
  -- la referencia interna FLW-....
  transfermovil_numero_proveedor text  not null default '4055432',
  transfermovil_titulo           text  not null default 'Carnaval Alimentos',
  transfermovil_intent_template  text  not null default
    'transfermovil://tm_compra_en_linea/action?id_transaccion=ESTATICO&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=1.0.0&titulo=$titulo&set_title=$titulo',
  transfermovil_url_template     text  not null default
    'https://transfermovil.app/action?id_transaccion=ESTATICO&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=5&titulo=$titulo&set_title=$titulo',

  moneda_default              text     not null default 'CUP',

  -- Vigencia de un intent antes de considerarlo expirado.
  intent_horas_vigencia       integer  not null default 24
                              check (intent_horas_vigencia between 1 and 720),

  -- Modo prueba: la app puede generar intents de importe minimo para probar el
  -- circuito sin cobrar de verdad. NUNCA acredita solo: la aprobacion sigue
  -- siendo manual del superadmin.
  modo_prueba                 boolean  not null default false,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  updated_by                  uuid,
  constraint suscripcion_config_fila_unica check (id = 1)
);

comment on table flow.suscripcion_config is
  'Fila unica con la configuracion de suscripciones que administra el superadmin: trial, gracia, soporte y plantillas de Transfermovil.';

insert into flow.suscripcion_config (id)
select 1
where not exists (select 1 from flow.suscripcion_config where id = 1);

drop trigger if exists trg_suscripcion_config_touch on flow.suscripcion_config;
create trigger trg_suscripcion_config_touch
  before update on flow.suscripcion_config
  for each row execute function flow._susc_touch();

-- ══ 2. PLANES COMERCIALES ═══════════════════════════════════════════════════

create table if not exists flow.suscripcion_plan (
  id             bigint generated always as identity primary key,
  codigo         text not null unique,
  nombre         text not null,
  descripcion    text,
  -- Duracion en dias exactos (decision del usuario: 30/90/365, no mes calendario).
  duracion_dias  integer not null check (duracion_dias between 1 and 3650),
  precio         numeric(12,2) not null default 0 check (precio >= 0),
  moneda         text not null default 'CUP',
  -- Limites funcionales del plan. Hoy solo se usan duracion y precio, pero la
  -- columna nace para no migrar despues (decision del usuario).
  -- El check exige un OBJETO jsonb: evita que se cuele un array, un string o un
  -- null escalar y que la UI tenga que defenderse de tres formas distintas.
  limites        jsonb not null default '{}'::jsonb
                 check (jsonb_typeof(limites) = 'object'),
  orden          integer not null default 0,
  activo         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid
);

comment on table flow.suscripcion_plan is
  'Planes comerciales de suscripcion por entidad. Los configura el superadmin. NO confundir con flow.plan_config / flow.plan_servicios (cupos mensuales de servicios).';

create index if not exists idx_suscripcion_plan_activo
  on flow.suscripcion_plan (activo, orden);

drop trigger if exists trg_suscripcion_plan_touch on flow.suscripcion_plan;
create trigger trg_suscripcion_plan_touch
  before update on flow.suscripcion_plan
  for each row execute function flow._susc_touch();

-- ══ 3. SUSCRIPCION DE LA ENTIDAD ════════════════════════════════════════════

create table if not exists flow.suscripcion (
  id                 bigint generated always as identity primary key,
  id_entidad         integer not null
                     references flow.entidad(id) on delete cascade,
  id_plan            bigint references flow.suscripcion_plan(id) on delete set null,

  -- 'trial'      -> meses gratis otorgados
  -- 'activa'     -> al dia
  -- 'en_gracia'  -> vencio pero dentro del margen: sigue operando
  -- 'vencida'    -> se le acabo el margen: la entidad queda desactivada
  -- 'sin_plan'   -> nace sin derecho (anti-abuso del trial): desactivada
  -- 'suspendida' -> la apago el superadmin a proposito (no es impago)
  -- 'cancelada'  -> historico: ya no aplica
  estado             text not null default 'activa'
                     check (estado in ('trial','activa','en_gracia','vencida',
                                       'sin_plan','suspendida','cancelada')),
  fecha_inicio       timestamptz not null default now(),
  fecha_vencimiento  timestamptz not null,
  -- Fin del margen de retraso. Es ESTE valor (no fecha_vencimiento) el que
  -- decide el corte: `coalesce(fecha_gracia_fin, fecha_vencimiento) > now()`.
  fecha_gracia_fin   timestamptz,
  origen             text not null default 'trial'
                     check (origen in ('trial','compra','acreditacion_admin','promocion')),
  -- Aviso "vence pronto" ya enviado (evita repetirlo en cada barrido del cron).
  aviso_previo_at    timestamptz,
  notas              text,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table flow.suscripcion is
  'Suscripcion de una entidad. Puede haber historicas (vencida/cancelada) pero SOLO UNA viva por entidad (indice unico parcial).';
comment on column flow.suscripcion.fecha_gracia_fin is
  'Fin del margen de retraso. El corte de la entidad ocurre cuando pasa esta fecha (o fecha_vencimiento si es NULL).';

-- Una sola suscripcion "viva" por entidad: la que gobierna el estado actual.
-- Las historicas (vencida/cancelada) pueden ser muchas.
create unique index if not exists ux_suscripcion_entidad_viva
  on flow.suscripcion (id_entidad)
  where estado in ('trial','activa','en_gracia','sin_plan','suspendida');

create index if not exists idx_suscripcion_entidad
  on flow.suscripcion (id_entidad, updated_at desc);

create index if not exists idx_suscripcion_vencimiento
  on flow.suscripcion (fecha_vencimiento)
  where estado in ('trial','activa','en_gracia');

drop trigger if exists trg_suscripcion_touch on flow.suscripcion;
create trigger trg_suscripcion_touch
  before update on flow.suscripcion
  for each row execute function flow._susc_touch();

-- ══ 4. INTENT DE PAGO (Transfermovil) ═══════════════════════════════════════

create table if not exists flow.suscripcion_intent (
  id               bigint generated always as identity primary key,
  id_entidad       integer not null references flow.entidad(id) on delete cascade,
  id_plan          bigint  not null references flow.suscripcion_plan(id) on delete restrict,
  uuid_usuario     uuid    not null references auth.users(id),
  monto            numeric(12,2) not null check (monto >= 0),
  moneda           text    not null default 'CUP',
  -- UNICO: viaja en &id_transaccion del deep link. Si se repite, Transfermovil
  -- reutiliza el importe de la transaccion anterior.
  id_transaccion   text    not null unique,
  numero_proveedor text    not null,
  url_intent       text    not null,   -- deep link transfermovil://
  url_http         text    not null,   -- respaldo https:// para copiar/pegar
  estado           text    not null default 'creado'
                   check (estado in ('creado','abierto','reportado',
                                     'verificado','rechazado','expirado','cancelado')),
  expira_at        timestamptz not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table flow.suscripcion_intent is
  'Intento de pago con Transfermovil: el importe ofrecido y el id_transaccion unico que viaja en el deep link. Inmutable como evidencia.';

create index if not exists idx_suscripcion_intent_entidad
  on flow.suscripcion_intent (id_entidad, created_at desc);

create index if not exists idx_suscripcion_intent_estado
  on flow.suscripcion_intent (estado, expira_at);

drop trigger if exists trg_suscripcion_intent_touch on flow.suscripcion_intent;
create trigger trg_suscripcion_intent_touch
  before update on flow.suscripcion_intent
  for each row execute function flow._susc_touch();

-- ══ 5. TRANSACCION (el pago reportado por el cliente) ══════════════════════

create table if not exists flow.suscripcion_transaccion (
  id                   bigint generated always as identity primary key,
  -- Un intent genera COMO MUCHO una transaccion: asi el reuso de un intent queda
  -- cerrado tambien por base, no solo por logica.
  id_intent            bigint not null unique
                       references flow.suscripcion_intent(id) on delete restrict,
  id_entidad           integer not null references flow.entidad(id) on delete cascade,
  -- Codigo/numbero de confirmacion que muestra Transfermovil. UNIQUE: es la
  -- defensa anti-reuso (un pago no puede acreditar dos planes).
  codigo_confirmacion  text not null unique,
  monto                numeric(12,2) not null,
  moneda               text not null default 'CUP',
  metodo               text not null default 'transfermovil',
  comprobante_url      text,
  estado               text not null default 'reportado'
                       check (estado in ('reportado','verificado','rechazado')),
  reportado_por        uuid not null references auth.users(id),
  reportado_at         timestamptz not null default now(),
  verificado_por       uuid references auth.users(id),
  verificado_at        timestamptz,
  observaciones        text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table flow.suscripcion_transaccion is
  'Pago reportado por el cliente para una entidad. Nace en `reportado`; el superadmin lo pasa a `verificado` o `rechazado` al comprobarlo en el banco.';
comment on column flow.suscripcion_transaccion.codigo_confirmacion is
  'Numero de confirmacion de Transfermovil. UNIQUE para impedir que el mismo pago acredite dos planes.';

create index if not exists idx_suscripcion_transaccion_estado
  on flow.suscripcion_transaccion (estado, reportado_at);

create index if not exists idx_suscripcion_transaccion_entidad
  on flow.suscripcion_transaccion (id_entidad, reportado_at desc);

drop trigger if exists trg_suscripcion_transaccion_touch on flow.suscripcion_transaccion;
create trigger trg_suscripcion_transaccion_touch
  before update on flow.suscripcion_transaccion
  for each row execute function flow._susc_touch();

-- ══ 6. LIBRO MAYOR (append-only) ════════════════════════════════════════════

create table if not exists flow.suscripcion_movimiento (
  id              bigint generated always as identity primary key,
  id_entidad      integer not null references flow.entidad(id) on delete cascade,
  id_suscripcion  bigint references flow.suscripcion(id) on delete set null,
  id_transaccion  bigint references flow.suscripcion_transaccion(id) on delete set null,
  tipo            text not null check (tipo in ('trial','acreditacion','renovacion',
                                                'ajuste','expiracion','suspension',
                                                'reactivacion','inicializacion')),
  dias            integer not null default 0,
  fecha_desde     timestamptz,
  fecha_hasta     timestamptz,
  motivo          text,
  admin_uuid      uuid,
  created_at      timestamptz not null default now()
);

comment on table flow.suscripcion_movimiento is
  'Libro mayor de la suscripcion: cada acreditacion, trial, ajuste o expiracion. NUNCA se borra; es la respuesta a "por que esta entidad tiene estos dias".';

create index if not exists idx_suscripcion_movimiento_entidad
  on flow.suscripcion_movimiento (id_entidad, created_at desc);

-- ══ 7. OUTBOX DE NOTIFICACIONES ════════════════════════════════════════════

create table if not exists flow.suscripcion_notificacion (
  id            bigint generated always as identity primary key,
  id_entidad    integer not null references flow.entidad(id) on delete cascade,
  uuid_destino  uuid,
  canal         text not null check (canal in ('in_app','whatsapp')),
  destino       text,                       -- telefono en formato internacional
  asunto        text,
  mensaje       text not null,
  -- 'pendiente' -> la recogera el despachador (Edge Function) cuando exista bot
  -- 'enviada'   -> entregada
  -- 'fallida'   -> intentada y fallo
  -- 'omitida'   -> no habia canal disponible (p. ej. WhatsApp sin bot)
  estado        text not null default 'pendiente'
                check (estado in ('pendiente','enviada','fallida','omitida')),
  intentos      integer not null default 0,
  error         text,
  enviada_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table flow.suscripcion_notificacion is
  'Outbox de avisos de suscripcion. Los in_app se escriben ademas en flow.notificaciones; los whatsapp quedan en cola hasta que exista un bot emisor (ver Q33: hoy degrada a deep link wa.me).';

create index if not exists idx_suscripcion_notificacion_pendiente
  on flow.suscripcion_notificacion (estado, canal, created_at)
  where estado = 'pendiente';

drop trigger if exists trg_suscripcion_notificacion_touch on flow.suscripcion_notificacion;
create trigger trg_suscripcion_notificacion_touch
  before update on flow.suscripcion_notificacion
  for each row execute function flow._susc_touch();

-- ══ 8. RLS Y PERMISOS ══════════════════════════════════════════════════════
--
-- Criterio: LECTURA para el dueno/admin de la entidad (y el superadmin siempre);
-- ESCRITURA por RPC `security definer` (que valida por dentro). La RLS queda como
-- red de seguridad, no como la unica puerta.

-- ── 8.1 config ──
alter table flow.suscripcion_config enable row level security;

drop policy if exists suscripcion_config_select_autenticados on flow.suscripcion_config;
create policy suscripcion_config_select_autenticados on flow.suscripcion_config
  for select to authenticated using (true);

drop policy if exists suscripcion_config_write_superadmin on flow.suscripcion_config;
create policy suscripcion_config_write_superadmin on flow.suscripcion_config
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.2 planes ──
alter table flow.suscripcion_plan enable row level security;

-- Los planes no son secretos: el cliente tiene que poder verlos para elegir.
drop policy if exists suscripcion_plan_select_autenticados on flow.suscripcion_plan;
create policy suscripcion_plan_select_autenticados on flow.suscripcion_plan
  for select to authenticated using (true);

drop policy if exists suscripcion_plan_write_superadmin on flow.suscripcion_plan;
create policy suscripcion_plan_write_superadmin on flow.suscripcion_plan
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.3 suscripcion ──
alter table flow.suscripcion enable row level security;

drop policy if exists suscripcion_select_propia on flow.suscripcion;
create policy suscripcion_select_propia on flow.suscripcion
  for select to authenticated
  using (flow._susc_caller_ve_entidad(id_entidad));

drop policy if exists suscripcion_write_superadmin on flow.suscripcion;
create policy suscripcion_write_superadmin on flow.suscripcion
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.4 intents ──
alter table flow.suscripcion_intent enable row level security;

drop policy if exists suscripcion_intent_select_propio on flow.suscripcion_intent;
create policy suscripcion_intent_select_propio on flow.suscripcion_intent
  for select to authenticated
  using (flow._susc_caller_ve_entidad(id_entidad));

drop policy if exists suscripcion_intent_write_superadmin on flow.suscripcion_intent;
create policy suscripcion_intent_write_superadmin on flow.suscripcion_intent
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.5 transacciones ──
alter table flow.suscripcion_transaccion enable row level security;

drop policy if exists suscripcion_transaccion_select_propia on flow.suscripcion_transaccion;
create policy suscripcion_transaccion_select_propia on flow.suscripcion_transaccion
  for select to authenticated
  using (flow._susc_caller_ve_entidad(id_entidad));

drop policy if exists suscripcion_transaccion_write_superadmin on flow.suscripcion_transaccion;
create policy suscripcion_transaccion_write_superadmin on flow.suscripcion_transaccion
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.6 movimientos ──
alter table flow.suscripcion_movimiento enable row level security;

drop policy if exists suscripcion_movimiento_select_propio on flow.suscripcion_movimiento;
create policy suscripcion_movimiento_select_propio on flow.suscripcion_movimiento
  for select to authenticated
  using (flow._susc_caller_ve_entidad(id_entidad));

drop policy if exists suscripcion_movimiento_write_superadmin on flow.suscripcion_movimiento;
create policy suscripcion_movimiento_write_superadmin on flow.suscripcion_movimiento
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.7 outbox ──
alter table flow.suscripcion_notificacion enable row level security;

drop policy if exists suscripcion_notificacion_select_propia on flow.suscripcion_notificacion;
create policy suscripcion_notificacion_select_propia on flow.suscripcion_notificacion
  for select to authenticated
  using (flow._susc_caller_ve_entidad(id_entidad));

drop policy if exists suscripcion_notificacion_write_superadmin on flow.suscripcion_notificacion;
create policy suscripcion_notificacion_write_superadmin on flow.suscripcion_notificacion
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- ── 8.8 grants ──
revoke all on flow.suscripcion_config,
              flow.suscripcion_plan,
              flow.suscripcion,
              flow.suscripcion_intent,
              flow.suscripcion_transaccion,
              flow.suscripcion_movimiento,
              flow.suscripcion_notificacion
  from anon;

grant select on flow.suscripcion_config,
                flow.suscripcion_plan,
                flow.suscripcion,
                flow.suscripcion_intent,
                flow.suscripcion_transaccion,
                flow.suscripcion_movimiento,
                flow.suscripcion_notificacion
  to authenticated;

grant all on flow.suscripcion_config,
             flow.suscripcion_plan,
             flow.suscripcion,
             flow.suscripcion_intent,
             flow.suscripcion_transaccion,
             flow.suscripcion_movimiento,
             flow.suscripcion_notificacion
  to service_role;

-- La RLS necesita poder evaluar este helper para `authenticated`.
grant execute on function flow._susc_caller_ve_entidad(integer) to authenticated;

-- ══ 9. VERIFICACION (ejecutar a mano despues de aplicar) ═══════════════════
--
-- 9.a Las 7 tablas existen y estan vacias salvo la config.
-- select
--   (select count(*) from flow.suscripcion_config)      as config,      -- 1
--   (select count(*) from flow.suscripcion_plan)        as planes,      -- 0
--   (select count(*) from flow.suscripcion)             as suscripciones,-- 0
--   (select count(*) from flow.suscripcion_intent)      as intents,     -- 0
--   (select count(*) from flow.suscripcion_transaccion) as transacciones,-- 0
--   (select count(*) from flow.suscripcion_movimiento)  as movimientos;  -- 0
--
-- 9.b La configuracion arranca con los valores esperados.
-- select trial_meses_default, trial_auto, trial_por_usuario, dias_gracia,
--        soporte_whatsapp, transfermovil_numero_proveedor, moneda_default
--   from flow.suscripcion_config where id = 1;
--
-- 9.c RLS activa en las 7 tablas (esperado: 7 filas).
-- select relname, relrowsecurity
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow'
--    and c.relname in ('suscripcion_config','suscripcion_plan','suscripcion',
--                      'suscripcion_intent','suscripcion_transaccion',
--                      'suscripcion_movimiento','suscripcion_notificacion')
--    and c.relrowsecurity;
--
-- 9.d El indice parcial existe (esperado: 1 fila).
-- select indexname from pg_indexes
--  where schemaname = 'flow' and indexname = 'ux_suscripcion_entidad_viva';
--
-- 9.e NO cambio el comportamiento de nada: `flow.local_servicio` sigue igual
--     (la 44 es la que compone el predicado de visibilidad).
-- select count(*) from flow.local_servicio;  -- mismo que antes de migrar
-- ════════════════════════════════════════════════════════════════════════════
