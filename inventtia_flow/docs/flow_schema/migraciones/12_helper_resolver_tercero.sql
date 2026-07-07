-- ============================================================================
-- HELPER: resolver (o crear) el perfil de un TERCERO por CI.
--
-- Lo usan cliente_entrar_sala_espera y cliente_reservar_directo cuando la
-- reserva es para alguien que no es usuario del sistema. Como flow.perfil tiene
-- RLS estricto (uuid_usuario = auth.uid()), el cliente no puede insertar/leer el
-- perfil de otro: por eso este helper es SECURITY DEFINER.
--
-- Logica:
--   - Busca un perfil existente por CI -> si existe, REUSA su uuid_usuario
--     (actualiza nombre/apellidos/telefono con lo recibido, por si cambiaron).
--   - Si no existe, crea uno nuevo con uuid_usuario = gen_random_uuid()
--     (un "uuid sintetico": no corresponde a una cuenta auth, solo identifica al
--      tercero dentro de flow).
-- Devuelve el uuid_usuario del tercero.
--
-- Requiere CI no vacio (es la clave para reusar/identificar al tercero).
-- ============================================================================

create or replace function flow._resolver_perfil_tercero(
  p_nombre    text,
  p_apellidos text,
  p_ci        text,
  p_telefono  text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = flow, public
as $$
declare
  v_uuid uuid;
begin
  if p_ci is null or btrim(p_ci) = '' then
    raise exception 'CI del tercero es obligatorio';
  end if;
  if p_nombre is null or btrim(p_nombre) = ''
     or p_apellidos is null or btrim(p_apellidos) = '' then
    raise exception 'Nombre y apellidos del tercero son obligatorios';
  end if;

  -- ¿Existe ya un perfil con ese CI? -> reusar
  select uuid_usuario into v_uuid
  from flow.perfil
  where ci = btrim(p_ci)
  limit 1;

  if v_uuid is not null then
    update flow.perfil
       set nombre    = btrim(p_nombre),
           apellidos = btrim(p_apellidos),
           telefono  = nullif(btrim(coalesce(p_telefono, '')), ''),
           updated_at = current_timestamp
     where uuid_usuario = v_uuid;
    return v_uuid;
  end if;

  -- No existe: crear con uuid sintetico
  v_uuid := gen_random_uuid();
  insert into flow.perfil (uuid_usuario, nombre, apellidos, ci, telefono)
  values (v_uuid, btrim(p_nombre), btrim(p_apellidos), btrim(p_ci),
          nullif(btrim(coalesce(p_telefono, '')), ''));

  return v_uuid;
end;
$$;

revoke all on function flow._resolver_perfil_tercero(text, text, text, text) from public;
-- Lo invocan otras funciones (definer). No es necesario grant a authenticated,
-- pero lo damos por si se llama directamente desde un RPC invoker.
grant execute on function flow._resolver_perfil_tercero(text, text, text, text) to authenticated, service_role;
