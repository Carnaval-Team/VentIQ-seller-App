-- ============================================================================
-- 20261112150000 · Captura automática de invitaciones (referidos) SIN tocar la app
-- ============================================================================
--
-- Problema
--   r.html copia "CARNAVAL-REF:<CODIGO>" al portapapeles y la app lo lee al
--   primer arranque. La copia puede fallar (navegador in-app de WhatsApp,
--   iOS, permiso denegado, gesto fuera de contexto) o el usuario puede copiar
--   otra cosa antes de abrir la app. En esos casos el referido se pierde.
--
-- Solución (0 cambios en la app Carnaval)
--   1. La landing registra la visita en `public.referral_visits`:
--      código de invitación + token único de visita + plataforma + UA + hash
--      de IP (la IP NUNCA se guarda en claro; ver fn_referral_request_ip).
--   2. Al crear la fila del usuario en `carnavalapp."Usuarios"`, un trigger
--      busca una visita pendiente de la "misma sesión":
--        a) por teléfono (preciso, si la landing lo capturó), o
--        b) por IP móvil + ventana corta (heurística conservadora).
--      Solo aplica si hay EXACTAMENTE UNA candidata; con ambigüedad no toca
--      nada (preferimos no atribuir antes que atribuir mal).
--   3. Cuando la app aplica el código real del portapapeles con
--      `carnavalapp.fn_usuario_apply_referral` y difiere del asignado por la
--      heurística, el código de la app GANA (se reemplaza y se marca
--      `source = 'app'`). El portapapeles sigue siendo la fuente de verdad.
--
-- Por qué sin tocar la app
--   El alta del usuario ya es una petición HTTP del cliente a PostgREST. La
--   IP de esa petición está disponible dentro de la transacción vía el GUC
--   `request.headers` (PostgREST la inyecta), igual que en el RPC de la
--   landing. Comparando ambas IPs + ventana temporal no hace falta que la app
--   lea nada nuevo, ni el Install Referrer, ni un código de instalación.
--
-- Privacidad / seguridad
--   * IP: solo sha256(sal || ip). Sal aleatoria de 32 bytes generada al
--     aplicar esta migración y guardada en `public.referral_capture_config`
--     (sin grants para anon/authenticated). No es reversible sin la sal.
--   * No se guardan cookies, ni IDFA/GAID, ni datos personales del invitado.
--   * Retención por defecto: 30 días (`fn_referral_visits_purge`).
--   * Las tablas nuevas quedan con RLS activado y SIN policies: solo las
--     funciones SECURITY DEFINER (owner postgres) acceden a ellas. Se revoca
--     explícitamente el acceso directo de anon/authenticated.
--   * Solo se expone a `anon` el registro de la visita; el reclamo es interno
--     (lo hace el trigger), así que un tercero no puede "leer" invitaciones.
--
-- Riesgo conocido (documentado en docs/REFERIDOS_CAPTURA_AUTOMATICA.md)
--   En redes móviles con CGNAT muchos usuarios comparten IP pública. Por eso
--   la coincidencia por IP exige UNA sola visita pendiente desde esa IP en la
--   ventana (45 min por defecto) y que la visita venga de un navegador móvil.
--   Si dos invitados comparten IP en la ventana, no se atribuye a ninguno.
--   La vía determinista sigue siendo el portapapeles; la heurística solo
--   rescata el caso "portapapeles perdido".
--
-- Aplicación
--   Supabase SQL Editor o `supabase db push`. Es aditivo; no borra ni cambia
--   datos existentes. Rollback completo en
--   `supabase/rollback/20261112150000_referral_capture_rollback.sql`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Configuración (fila única). La sal se genera al aplicar la migración.
-- ----------------------------------------------------------------------------
create table if not exists public.referral_capture_config (
  id                         boolean primary key default true check (id),
  salt                       text    not null,
  ttl_minutes                integer not null default 120 check (ttl_minutes between 1 and 1440),
  ip_window_minutes          integer not null default 45  check (ip_window_minutes between 0 and 1440),
  ip_match_enabled           boolean not null default true,
  phone_match_enabled        boolean not null default true,
  max_registrations_per_token integer not null default 5  check (max_registrations_per_token between 1 and 50),
  retention_days             integer not null default 30  check (retention_days between 7 and 365),
  updated_at                 timestamptz not null default now()
);

insert into public.referral_capture_config (id, salt)
values (true, encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (id) do nothing;

comment on table public.referral_capture_config is
  'Configuración única de la captura automática de referidos (sal de hash, TTL, ventana, retención).';

-- ----------------------------------------------------------------------------
-- 2. Visitas capturadas por la landing
-- ----------------------------------------------------------------------------
create table if not exists public.referral_visits (
  id               bigserial primary key,
  visit_token      uuid        not null unique,     -- token único de la visita (lo genera la landing)
  ref_code         text        not null,            -- código del invitador (validado contra carnavalapp."Usuarios")
  platform         text,                            -- Android | iOS | Desktop
  user_agent       text,
  ip_hash          text,                            -- sha256(sal || ip) — nunca IP en claro
  phone_hash       text,                            -- sha256(sal || últimos 8 dígitos) — opcional
  registered_count integer     not null default 1,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '120 minutes',
  applied_at       timestamptz,
  applied_user_id  bigint,
  applied_uuid     uuid,
  matched_by       text                             -- phone | ip
);

comment on table public.referral_visits is
  'Cada visita a r.html con código de invitación. La landing la registra; el trigger del alta de usuario la consume como respaldo del portapapeles.';

create index if not exists referral_visits_ip_idx
  on public.referral_visits (ip_hash, created_at desc)
  where applied_at is null;
create index if not exists referral_visits_phone_idx
  on public.referral_visits (phone_hash)
  where applied_at is null;
create index if not exists referral_visits_expires_idx
  on public.referral_visits (expires_at);

-- Origen de la atribución: permite que el código REAL de la app (portapapeles)
-- reemplace al asignado por heurística. No se toca la tabla "Usuarios".
create table if not exists public.referral_user_attributions (
  user_id    bigint primary key,
  user_uuid  uuid,
  ref_code   text not null,
  source     text not null check (source in ('ip_trigger', 'phone_trigger', 'app')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.referral_user_attributions is
  'Procedencia de referal_from: ip_trigger/phone_trigger = puesto por el trigger; app = código del portapapeles (manda).';

-- ----------------------------------------------------------------------------
-- 3. Utilidades: IP de la petición (PostgREST) y hashes con sal
-- ----------------------------------------------------------------------------

-- IP del cliente según las cabeceras que PostgREST inyecta en el GUC
-- `request.headers`. Devuelve NULL fuera de una petición HTTP (p. ej. psql).
create or replace function public.fn_referral_request_ip()
returns text
language plpgsql
stable
security definer
set search_path = pg_temp
as $$
declare
  v_raw     text;
  v_headers jsonb;
begin
  v_raw := nullif(current_setting('request.headers', true), '');
  if v_raw is null then
    return null;
  end if;
  v_headers := v_raw::jsonb;
  return nullif(
           btrim(split_part(
             coalesce(v_headers->>'x-forwarded-for', v_headers->>'x-real-ip', ''),
             ',', 1)),
           '');
exception when others then
  return null;
end;
$$;

revoke all on function public.fn_referral_request_ip() from public, anon, authenticated;

create or replace function public.fn_referral_ip_hash()
returns text
language plpgsql
stable
security definer
set search_path = pg_temp
as $$
declare
  v_salt text;
  v_ip   text;
begin
  select c.salt into v_salt from public.referral_capture_config c where c.id;
  v_ip := public.fn_referral_request_ip();
  if v_salt is null or v_ip is null then
    return null;
  end if;
  return encode(extensions.digest(v_salt || '|ip|' || v_ip, 'sha256'), 'hex');
end;
$$;

revoke all on function public.fn_referral_ip_hash() from public, anon, authenticated;

-- Normaliza a los últimos 8 dígitos (Cuba: 8 dígitos, con o sin +53).
create or replace function public.fn_referral_phone_norm(p_phone text)
returns text
language sql
immutable
as $$
  select case when length(d) >= 8 then right(d, 8) else null end
  from (select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') as d) t;
$$;

revoke all on function public.fn_referral_phone_norm(text) from public, anon, authenticated;

create or replace function public.fn_referral_phone_hash(p_phone text)
returns text
language plpgsql
stable
security definer
set search_path = pg_temp
as $$
declare
  v_salt text;
  v_norm text := public.fn_referral_phone_norm(p_phone);
begin
  if v_norm is null then
    return null;
  end if;
  select c.salt into v_salt from public.referral_capture_config c where c.id;
  if v_salt is null then
    return null;
  end if;
  return encode(extensions.digest(v_salt || '|ph|' || v_norm, 'sha256'), 'hex');
end;
$$;

revoke all on function public.fn_referral_phone_hash(text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. RPC pública: la landing registra la visita (idempotente por token)
-- ----------------------------------------------------------------------------
create or replace function public.fn_referral_visit_register(
  p_ref_code    text,
  p_visit_token text,
  p_platform    text default null,
  p_user_agent  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_temp
as $$
declare
  v_cfg      public.referral_capture_config%rowtype;
  v_code     text := nullif(upper(btrim(coalesce(p_ref_code, ''))), '');
  v_token    uuid;
  v_ip_hash  text;
  v_ip_count integer;
  v_id       bigint;
  v_expires  timestamptz;
begin
  if v_code is null or length(v_code) > 32 then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_invalido');
  end if;

  begin
    v_token := btrim(p_visit_token)::uuid;
  exception when others then
    return jsonb_build_object('ok', false, 'motivo', 'token_invalido');
  end;

  select * into v_cfg from public.referral_capture_config c where c.id;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'config_ausente');
  end if;

  -- No se registran visitas con códigos que no existen: así el trigger nunca
  -- asigna un referidor inexistente y no se ensucia la métrica.
  if not exists (
    select 1
      from carnavalapp."Usuarios" u
     where upper(btrim(coalesce(u.referal_code, ''))) = v_code
  ) then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_inexistente');
  end if;

  v_ip_hash := public.fn_referral_ip_hash();

  -- Cortafuegos básico contra spam del endpoint público.
  if v_ip_hash is not null then
    select count(*) into v_ip_count
      from public.referral_visits v
     where v.ip_hash = v_ip_hash
       and v.created_at > now() - interval '10 minutes';
    if v_ip_count >= 25 then
      return jsonb_build_object('ok', false, 'motivo', 'rate_limit');
    end if;
  end if;

  insert into public.referral_visits as v
    (visit_token, ref_code, platform, user_agent, ip_hash, expires_at)
  values
    (v_token, v_code,
     left(coalesce(p_platform, ''), 20),
     left(coalesce(p_user_agent, ''), 400),
     v_ip_hash,
     now() + make_interval(mins => v_cfg.ttl_minutes))
  on conflict (visit_token) do update
    set registered_count = v.registered_count + 1,
        ip_hash   = coalesce(v.ip_hash, excluded.ip_hash),
        platform  = coalesce(nullif(excluded.platform, ''), v.platform),
        user_agent = coalesce(nullif(excluded.user_agent, ''), v.user_agent),
        -- Volver a abrir la ventana solo si la visita caducó SIN haberse usado:
        -- así un reintento horas después sigue sirviendo, pero una visita ya
        -- consumida no puede reutilizarse para atribuir a otro usuario.
        expires_at = case
                       when v.expires_at <= now()
                         then now() + make_interval(mins => v_cfg.ttl_minutes)
                       else v.expires_at
                     end
    where v.applied_at is null
      and (v.registered_count < v_cfg.max_registrations_per_token
           or v.expires_at <= now())
  returning v.id, v.expires_at into v_id, v_expires;

  if v_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'visita_no_disponible');
  end if;

  return jsonb_build_object('ok', true, 'visit_token', v_token, 'expires_at', v_expires);
end;
$$;

comment on function public.fn_referral_visit_register(text, text, text, text) is
  'La landing registra la visita (código + token único + plataforma + UA). Idempotente por token; valida que el código exista.';

revoke all on function public.fn_referral_visit_register(text, text, text, text) from public;
grant execute on function public.fn_referral_visit_register(text, text, text, text)
  to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. RPC pública: adjuntar el teléfono a una visita (para el emparejamiento
--    preciso; queda lista para cuando la landing muestre el campo).
-- ----------------------------------------------------------------------------
create or replace function public.fn_referral_visit_attach_phone(
  p_visit_token text,
  p_phone       text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_temp
as $$
declare
  v_token uuid;
  v_hash  text := public.fn_referral_phone_hash(p_phone);
  v_rows  integer := 0;
begin
  if v_hash is null then
    return jsonb_build_object('ok', false, 'motivo', 'telefono_invalido');
  end if;

  begin
    v_token := btrim(p_visit_token)::uuid;
  exception when others then
    return jsonb_build_object('ok', false, 'motivo', 'token_invalido');
  end;

  update public.referral_visits v
     set phone_hash = v_hash
   where v.visit_token = v_token
     and v.applied_at is null
     and v.expires_at > now();
  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'visita_no_encontrada');
  end if;

  return jsonb_build_object('ok', true, 'visit_token', v_token);
end;
$$;

revoke all on function public.fn_referral_visit_attach_phone(text, text) from public;
grant execute on function public.fn_referral_visit_attach_phone(text, text)
  to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Trigger: al crear (o actualizar el teléfono de) un usuario, resolver la
--    visita pendiente. Nunca rompe el alta: cualquier error se descarta.
-- ----------------------------------------------------------------------------
create or replace function carnavalapp.fn_usuarios_aplicar_visita_pendiente()
returns trigger
language plpgsql
security definer
set search_path = pg_temp
as $$
declare
  v_cfg        public.referral_capture_config%rowtype;
  v_ref        text;
  v_user_code  text;
  v_phone_hash text;
  v_ip_hash    text;
  v_candidates integer;
  v_visit      public.referral_visits%rowtype;
  v_source     text;
begin
  -- NEW no se puede usar en inicializadores de DECLARE: se resuelve al entrar.
  v_ref := nullif(upper(btrim(coalesce(new.referal_from, ''))), '');

  -- La app ya trajo un código (portapapeles) o el usuario ya tenía referidor.
  if v_ref is not null then
    return null;
  end if;

  select * into v_cfg from public.referral_capture_config c where c.id;
  if not found then
    return null;
  end if;

  select nullif(upper(btrim(coalesce(u.referal_code, ''))), '')
    into v_user_code
    from carnavalapp."Usuarios" u
   where u.id = new.id;

  -- (a) Teléfono: señal precisa. Solo si la landing lo capturó y hay UNA visita.
  if v_cfg.phone_match_enabled then
    v_phone_hash := public.fn_referral_phone_hash(new.telefono);
    if v_phone_hash is not null then
      select count(*) into v_candidates
        from public.referral_visits v
       where v.phone_hash = v_phone_hash
         and v.applied_at is null
         and v.expires_at > now()
         and v.ref_code is distinct from v_user_code;

      if v_candidates = 1 then
        select v.* into v_visit
          from public.referral_visits v
         where v.phone_hash = v_phone_hash
           and v.applied_at is null
           and v.expires_at > now()
           and v.ref_code is distinct from v_user_code
         order by v.created_at desc
         limit 1;
        v_source := 'phone_trigger';
      end if;
    end if;
  end if;

  -- (b) IP móvil + ventana corta: solo si hay UNA candidata. Con dos o más
  --     invitados detrás de la misma IP (CGNAT) NO se atribuye (evita fraude).
  if v_visit.id is null and v_cfg.ip_match_enabled and v_cfg.ip_window_minutes > 0 then
    v_ip_hash := public.fn_referral_ip_hash();
    if v_ip_hash is not null then
      select count(*) into v_candidates
        from public.referral_visits v
       where v.ip_hash = v_ip_hash
         and v.applied_at is null
         and v.expires_at > now()
         and v.created_at > now() - make_interval(mins => v_cfg.ip_window_minutes)
         and coalesce(v.platform, '') in ('Android', 'iOS')
         and v.ref_code is distinct from v_user_code;

      if v_candidates = 1 then
        select v.* into v_visit
          from public.referral_visits v
         where v.ip_hash = v_ip_hash
           and v.applied_at is null
           and v.expires_at > now()
           and v.created_at > now() - make_interval(mins => v_cfg.ip_window_minutes)
           and coalesce(v.platform, '') in ('Android', 'iOS')
           and v.ref_code is distinct from v_user_code
         order by v.created_at desc
         limit 1;
        v_source := 'ip_trigger';
      end if;
    end if;
  end if;

  if v_visit.id is null then
    return null;
  end if;

  -- Revalidar el código (el invitador pudo borrarse entre la visita y el alta).
  if not exists (
    select 1
      from carnavalapp."Usuarios" r
     where upper(btrim(coalesce(r.referal_code, ''))) = upper(btrim(v_visit.ref_code))
  ) then
    return null;
  end if;

  update carnavalapp."Usuarios" u
     set referal_from = upper(btrim(v_visit.ref_code))
   where u.id = new.id
     and nullif(btrim(coalesce(u.referal_from, '')), '') is null;

  if found then
    update public.referral_visits v
       set applied_at      = now(),
           applied_user_id = new.id,
           applied_uuid    = new.uuid,
           matched_by      = case when v_source = 'phone_trigger' then 'phone' else 'ip' end
     where v.id = v_visit.id;

    insert into public.referral_user_attributions (user_id, user_uuid, ref_code, source)
    values (new.id, new.uuid, upper(btrim(v_visit.ref_code)), v_source)
    on conflict (user_id) do update
      set ref_code   = excluded.ref_code,
          source     = excluded.source,
          user_uuid  = excluded.user_uuid,
          updated_at = now();
  end if;

  return null;
exception when others then
  -- Un fallo en la atribución NUNCA debe impedir que el usuario se registre.
  raise log 'referral trigger usuario %: %', new.id, sqlerrm;
  return null;
end;
$$;

revoke all on function carnavalapp.fn_usuarios_aplicar_visita_pendiente() from public, anon, authenticated;

drop trigger if exists trg_usuarios_aplicar_visita on carnavalapp."Usuarios";
create trigger trg_usuarios_aplicar_visita
after insert or update of telefono on carnavalapp."Usuarios"
for each row
when (nullif(btrim(coalesce(new.referal_from, '')), '') is null)
execute function carnavalapp.fn_usuarios_aplicar_visita_pendiente();

-- ----------------------------------------------------------------------------
-- 7. Prioridad del portapapeles: el código real de la app reemplaza al
--    heurístico. Único cambio sobre una función existente (rama nueva).
-- ----------------------------------------------------------------------------
create or replace function carnavalapp.fn_usuario_apply_referral(
  p_referal_from text,
  p_uuid         uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path = carnavalapp, public, pg_temp
as $function$
declare
  v_uuid      uuid := coalesce(p_uuid, carnavalapp.fn_require_auth_uid());
  v_from      text := upper(btrim(coalesce(p_referal_from, '')));
  v_user_id   bigint;
  v_existing  text;
  v_mi_codigo text;
  v_tocadas   integer := 0;
  v_attr_src  text;
begin
  -- Aborta si el uuid no es el de la sesion.
  perform carnavalapp.fn_assert_usuario_uuid(v_uuid);

  if v_from = '' then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_vacio', 'ordenes_estampadas', 0);
  end if;

  select u.id,
         nullif(btrim(coalesce(u.referal_from, '')), ''),
         nullif(btrim(coalesce(u.referal_code, '')), '')
    into v_user_id, v_existing, v_mi_codigo
    from carnavalapp."Usuarios" u
   where u.uuid = v_uuid;

  if v_user_id is null then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'usuario_no_encontrado', 'ordenes_estampadas', 0);
  end if;

  if v_mi_codigo is not null and upper(v_mi_codigo) = v_from then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_propio', 'ordenes_estampadas', 0);
  end if;

  if not exists (
    select 1 from carnavalapp."Usuarios" r
     where upper(btrim(coalesce(r.referal_code, ''))) = v_from
  ) then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_inexistente', 'ordenes_estampadas', 0);
  end if;

  -- NUEVO: si el referidor actual lo puso el trigger heurístico y el código
  -- del portapapeles es otro, la app manda (fuente más fiable).
  if v_existing is not null and v_existing is distinct from v_from then
    select a.source into v_attr_src
      from public.referral_user_attributions a
     where a.user_id = v_user_id;

    if v_attr_src in ('ip_trigger', 'phone_trigger') then
      v_tocadas := carnavalapp.fn_estampar_referal_en_ordenes_abiertas(
                     v_user_id, v_from, 48);

      update carnavalapp."Usuarios" u
         set referal_from = v_from
       where u.id = v_user_id;

      update public.referral_user_attributions a
         set ref_code = v_from, source = 'app', updated_at = now()
       where a.user_id = v_user_id;

      return jsonb_build_object(
        'aplicado', true, 'motivo', 'reemplazado_heuristica',
        'referal_from', v_from, 'ordenes_estampadas', v_tocadas);
    end if;
  end if;

  -- Ya tenia referidor: el codigo NO se cambia (regla de siempre), pero se
  -- aprovecha para estampar con el codigo que YA tiene las ordenes abiertas que
  -- se hubieran quedado sin el. Asi un reintento del usuario recupera la orden.
  if v_existing is not null then
    v_tocadas := carnavalapp.fn_estampar_referal_en_ordenes_abiertas(
                   v_user_id, v_existing, 48);
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'ya_tenia_referidor',
      'referal_from', v_existing, 'ordenes_estampadas', v_tocadas);
  end if;

  -- Se estampa ANTES del UPDATE a proposito: el trigger del punto 2 se dispara
  -- con ese UPDATE y haria el trabajo, dejando a la RPC reportando 0 ordenes.
  -- Haciendolo antes, el contador que ve la app es el real. El trigger corre
  -- despues y no encuentra nada que hacer (el helper ya no ve filas vacias).
  v_tocadas := carnavalapp.fn_estampar_referal_en_ordenes_abiertas(
                 v_user_id, v_from, 48);

  update carnavalapp."Usuarios" u
     set referal_from = v_from
   where u.id = v_user_id;

  insert into public.referral_user_attributions (user_id, user_uuid, ref_code, source)
  values (v_user_id, v_uuid, v_from, 'app')
  on conflict (user_id) do update
    set ref_code   = excluded.ref_code,
        source     = 'app',
        updated_at = now();

  return jsonb_build_object(
    'aplicado', true, 'motivo', 'ok',
    'referal_from', v_from, 'ordenes_estampadas', v_tocadas);
end;
$function$;

-- ----------------------------------------------------------------------------
-- 8. Retención: purga de visitas antiguas (llamar a diario o programar cron)
-- ----------------------------------------------------------------------------
create or replace function public.fn_referral_visits_purge(p_days integer default null)
returns integer
language plpgsql
security definer
set search_path = pg_temp
as $$
declare
  v_days    integer;
  v_deleted integer;
begin
  select coalesce(p_days, c.retention_days)
    into v_days
    from public.referral_capture_config c
   where c.id;
  v_days := coalesce(v_days, 30);

  delete from public.referral_visits v
   where v.created_at < now() - make_interval(days => v_days);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.fn_referral_visits_purge(integer) from public, anon, authenticated;
grant execute on function public.fn_referral_visits_purge(integer) to service_role;

-- Opcional (recomendado): purga diaria con pg_cron (disponible en este proyecto).
-- select cron.schedule(
--   'referral-visits-purge', '17 4 * * *',
--   $$select public.fn_referral_visits_purge();$$
-- );

-- ----------------------------------------------------------------------------
-- 9. Bloqueo de acceso directo: solo las funciones SECURITY DEFINER acceden.
-- ----------------------------------------------------------------------------
alter table public.referral_visits        enable row level security;
alter table public.referral_capture_config enable row level security;
alter table public.referral_user_attributions enable row level security;

revoke all on table public.referral_visits from public, anon, authenticated;
revoke all on table public.referral_capture_config from public, anon, authenticated;
revoke all on table public.referral_user_attributions from public, anon, authenticated;
revoke all on sequence public.referral_visits_id_seq from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 10. Pruebas manuales (ejecutar en una transacción y hacer ROLLBACK)
-- ----------------------------------------------------------------------------
--   begin;
--   -- 1) código existente
--   select referal_code from carnavalapp."Usuarios"
--    where nullif(btrim(coalesce(referal_code,'')),'') is not null limit 1;
--   -- 2) simular la landing
--   select set_config('request.headers','{"x-forwarded-for":"203.0.113.77"}',true);
--   select public.fn_referral_visit_register('CODIGO','<uuid>','Android','UA');
--   -- 3) simular el alta de la app (misma IP) y ver referal_from
--   insert into carnavalapp."Usuarios"(email,rol,uuid,created_at)
--   values ('prueba@example.com','cliente',gen_random_uuid(),now());
--   select referal_from from carnavalapp."Usuarios"
--    where email='prueba@example.com';
--   rollback;