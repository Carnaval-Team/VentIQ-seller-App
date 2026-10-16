-- ============================================================================
-- Migración 54: `flow.admin_create_user` crea usuarios COMPLETOS
-- ============================================================================
--
-- EL FALLO QUE CORRIGE
--   (reportado: "me dice que se crea el trabajador pero no veo el usuario en
--    users ni el perfil")
--
--   La función que había (solo en la base, sin archivo en el repo) insertaba
--   cinco columnas de `auth.users`:
--
--     insert into auth.users (id, email, encrypted_password,
--                             email_confirmed_at, raw_user_meta_data)
--
--   y devolvía el uuid. La fila se creaba, pero **incompleta**:
--
--     1. `created_at` / `updated_at` quedaban NULL -> el listado de usuarios del
--        panel de Supabase (Authentication > Users) ordena y pagina por
--        `created_at`, así que esas filas no aparecen bien en la lista. De ahí
--        el "dice que se crea pero no lo veo".
--     2. NO se creaba la fila de `auth.identities`. GoTrue resuelve el login por
--        identidad (`provider = 'email'`), así que esos usuarios **no podían
--        iniciar sesión nunca** ("Invalid login credentials") por mucho que la
--        contraseña fuese correcta.
--     3. Faltaban `aud`, `role`, `instance_id`, `raw_app_meta_data` y los
--        tokens de confirmación (que GoTrue espera como cadena vacía, no NULL).
--
--   Medido en el proyecto: 5360 filas en `auth.users` y exactamente 6 con
--   `created_at IS NULL` + sin identidad, todas con
--   `raw_user_meta_data ? 'nombre'` (la firma de esta RPC).
--
--   La función tampoco comprobaba QUIÉN la llamaba: su ACL incluye
--   `authenticated`, así que cualquier usuario de la app podía crear cuentas.
--
-- QUÉ HACE ESTA MIGRACIÓN
--   1. Reescribe `admin_create_user` para que inserte la fila completa de
--      `auth.users` **y** la identidad de email, con la MISMA forma que usa
--      GoTrue en un registro normal (verificado contra una fila real).
--   2. Exige que quien llame sea administrador de alguna entidad (o
--      superadmin).
--   3. Repara los usuarios ya creados por la versión rota (solo esa firma
--      exacta: `created_at IS NULL AND raw_user_meta_data ? 'nombre'`), para que
--      puedan entrar y aparezcan en el listado. NO toca ningún otro usuario.
--
-- NOTA SOBRE COLUMNAS GENERADAS (verificado contra la base real):
--   * `auth.users.confirmed_at` es GENERATED ALWAYS
--     (`least(email_confirmed_at, phone_confirmed_at)`): **no** se escribe.
--   * `auth.identities.email` es GENERATED ALWAYS
--     (`lower(identity_data ->> 'email')`): **no** se escribe. Escribirla falla
--     con `428C9: cannot insert a non-DEFAULT value into column "email"`.
--     Basta con poner `email` dentro de `identity_data`: la columna se deriva
--     sola. Ese era el error que impedía aplicar esta migración.
--
-- CAMINO RECOMENDADO A FUTURO: una Edge Function con la service_role key y
-- `auth.admin.createUser(...)`. Esto de escribir en `auth.users` a mano funciona
-- y es lo que ya había, pero es un esquema interno de GoTrue: si Supabase cambia
-- la forma, hay que revisarlo.
-- ============================================================================

create or replace function flow.admin_create_user(
  p_email text,
  p_password text,
  p_nombre text,
  p_apellidos text,
  p_ci text,
  p_telefono text
)
returns uuid
language plpgsql
security definer
set search_path to 'flow', 'extensions', 'public', 'auth'
as $function$
declare
  v_email text := lower(trim(p_email));
  v_uuid uuid := gen_random_uuid();
begin
  -- ── Quién puede crear usuarios ──────────────────────────────────────────
  if auth.uid() is null then
    raise exception 'Sesión no válida';
  end if;

  if not (
    public.fn_is_superadmin_full_access()
    or exists (select 1 from flow.entidad e where e.owner_uuid = auth.uid())
    or exists (select 1 from flow.entidad_admin a where a.uuid_usuario = auth.uid())
  ) then
    raise exception 'Solo un administrador de entidad puede crear usuarios';
  end if;

  -- ── Datos ───────────────────────────────────────────────────────────────
  if v_email is null or v_email = '' then
    raise exception 'El correo es obligatorio';
  end if;
  if coalesce(p_password, '') = '' then
    raise exception 'La contraseña es obligatoria';
  end if;

  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe un usuario con el correo %', v_email;
  end if;

  -- `flow.perfil.ci` tiene índice único (`perfil_ci_key`): sin esta comprobación
  -- el insert fallaría con un error de Postgres en vez de decir qué pasa.
  if exists (select 1 from flow.perfil where ci = trim(p_ci)) then
    raise exception 'Ya existe un perfil con ese carné de identidad';
  end if;

  -- ── Usuario de auth COMPLETO (misma forma que un registro de GoTrue) ────
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    phone_change,
    phone_change_token,
    email_change_token_current,
    reauthentication_token,
    is_sso_user,
    is_anonymous,
    email_change_confirm_status
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_uuid,
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    now(),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    -- `nombre`/`apellidos` se conservan porque la app los lee de aquí.
    jsonb_build_object(
      'sub', v_uuid::text,
      'email', v_email,
      'nombre', p_nombre,
      'apellidos', p_apellidos,
      'email_verified', true,
      'phone_verified', false
    ),
    '', '', '', '', '', '', '', '',
    false,
    false,
    0
  );

  -- ── Identidad de email: es lo que hace posible el login ────────────────
  -- `email` NO se escribe: en `auth.identities` es GENERATED ALWAYS a partir de
  -- `identity_data ->> 'email'`.
  insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_uuid,
    v_uuid,
    jsonb_build_object(
      'sub', v_uuid::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now(),
    now()
  );

  -- ── Perfil de la app ────────────────────────────────────────────────────
  insert into flow.perfil (uuid_usuario, nombre, apellidos, ci, telefono)
  values (v_uuid, p_nombre, p_apellidos, p_ci, p_telefono)
  on conflict (uuid_usuario) do update set
    nombre = excluded.nombre,
    apellidos = excluded.apellidos,
    ci = excluded.ci,
    telefono = excluded.telefono;

  return v_uuid;
end;
$function$;

revoke all on function flow.admin_create_user(text, text, text, text, text, text) from public, anon;
grant execute on function flow.admin_create_user(text, text, text, text, text, text) to authenticated, service_role;

comment on function flow.admin_create_user(text, text, text, text, text, text) is
  'Crea un usuario de auth (fila completa + identidad de email, para que pueda '
  'iniciar sesión) y su perfil en flow.perfil. Solo para administradores de '
  'entidad o superadmins.';

-- ============================================================================
-- Reparación de los usuarios que creó la versión rota
-- ============================================================================
-- Firma exacta de la versión rota: sin `created_at` y con `nombre` en los
-- metadatos (lo que escribía esa función). No toca a ningún otro usuario.
do $reparar$
declare
  r record;
  v_reparados int := 0;
begin
  for r in
    select u.id, u.email
    from auth.users u
    where u.created_at is null
      and u.raw_user_meta_data ? 'nombre'
  loop
    update auth.users u
       set instance_id = coalesce(u.instance_id, '00000000-0000-0000-0000-000000000000'),
           aud = coalesce(u.aud, 'authenticated'),
           role = coalesce(u.role, 'authenticated'),
           created_at = now(),
           updated_at = now(),
           email_confirmed_at = coalesce(u.email_confirmed_at, now()),
           raw_app_meta_data = coalesce(
             u.raw_app_meta_data,
             jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'))
           ),
           raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
             || jsonb_build_object(
                  'sub', u.id::text,
                  'email', u.email,
                  'email_verified', true,
                  'phone_verified', false
                ),
           confirmation_token = coalesce(u.confirmation_token, ''),
           recovery_token = coalesce(u.recovery_token, ''),
           email_change = coalesce(u.email_change, ''),
           email_change_token_new = coalesce(u.email_change_token_new, ''),
           phone_change = coalesce(u.phone_change, ''),
           phone_change_token = coalesce(u.phone_change_token, ''),
           email_change_token_current = coalesce(u.email_change_token_current, ''),
           reauthentication_token = coalesce(u.reauthentication_token, '')
     where u.id = r.id;

    -- Otra vez: `email` no se escribe, se deriva de `identity_data`.
    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    )
    select
      gen_random_uuid(), r.id, r.id,
      jsonb_build_object(
        'sub', r.id::text,
        'email', r.email,
        'email_verified', true,
        'phone_verified', false
      ),
      'email', now(), now(), now()
    where not exists (
      select 1 from auth.identities i
      where i.user_id = r.id and i.provider = 'email'
    );

    v_reparados := v_reparados + 1;
  end loop;

  raise notice 'admin_create_user: % usuario(s) reparados', v_reparados;
end
$reparar$;

-- Comprobación posterior (debe dar 0 y 0):
--
--   select count(*) as sin_created_at
--   from auth.users where created_at is null;
--
--   select count(*) as con_perfil_sin_identidad
--   from auth.users u
--   where exists (select 1 from flow.perfil p where p.uuid_usuario = u.id)
--     and not exists (select 1 from auth.identities i where i.user_id = u.id);