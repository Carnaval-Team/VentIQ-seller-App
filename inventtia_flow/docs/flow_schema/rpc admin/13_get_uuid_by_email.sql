-- ============================================================================
-- HELPER: obtener uuid de un usuario por su email.
-- Usado por la app para agregar vendedores/admins buscando por correo.
-- SECURITY DEFINER: necesario para leer auth.users desde rol authenticated.
-- Solo devuelve el uuid, no expone datos sensibles del usuario.
-- ============================================================================

create or replace function public.get_uuid_by_email(
  p_email text
)
returns uuid
language sql
stable
security definer
set search_path = flow, auth, public
as $$
  select id
  from auth.users
  where lower(email) = lower(trim(p_email))
    and deleted_at is null
  limit 1;
$$;

grant execute on function public.get_uuid_by_email(text) to authenticated;

-- ── Verificación ──────────────────────────────────────────────────────────────
--   select public.get_uuid_by_email('vendedor@correo.com');
--   -- Debe devolver el uuid del usuario o null si no existe.
