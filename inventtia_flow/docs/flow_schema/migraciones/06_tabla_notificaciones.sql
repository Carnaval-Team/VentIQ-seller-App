-- ============================================================================
-- MIGRACION: tabla de notificaciones para los usuarios (flow.notificaciones)
--
-- Guarda CADA notificacion dirigida a un usuario: al entrar en una cola, al
-- confirmarse una reservacion (bot), avisos del sistema, etc.
-- La app lee de aqui el "Historial" de notificaciones y marca como leidas.
--
-- Convenciones de 'tipo' (texto libre, valores sugeridos):
--   'sala_espera' -> entro satisfactoriamente en una cola
--   'reserva'     -> el bot le confirmo una reservacion (paso a agenda)
--   'sistema'     -> avisos generales / novedades
--   'promo'       -> promociones
-- ============================================================================

create table if not exists flow.notificaciones (
  id                bigint generated always as identity primary key,
  uuid_usuario      uuid not null,            -- destinatario (FK a perfil)
  tipo              text not null default 'sistema',
  titulo            text not null,            -- titulo corto para la lista
  mensaje           text not null,            -- cuerpo legible para el usuario
  leida             boolean not null default false,
  leida_at          timestamp without time zone,  -- cuando se marco como leida
  id_local_servicio integer,                  -- contexto: servicio relacionado (opcional)
  id_referencia     bigint,                   -- id generico (agenda / sala_espera) opcional
  data              jsonb,                    -- payload extra (fecha, numero_cola, etc.)
  created_at        timestamp without time zone not null default current_timestamp,
  constraint notificaciones_uuid_usuario_fkey
    foreign key (uuid_usuario) references flow.perfil(uuid_usuario) on delete cascade,
  constraint notificaciones_id_local_servicio_fkey
    foreign key (id_local_servicio) references flow.local_servicio(id) on delete set null
);

-- Consulta tipica: "mis notificaciones, mas recientes primero".
create index if not exists idx_notificaciones_usuario
  on flow.notificaciones (uuid_usuario, created_at desc);

-- Indice parcial para el badge de "no leidas" (suelen ser pocas).
create index if not exists idx_notificaciones_no_leidas
  on flow.notificaciones (uuid_usuario, created_at desc)
  where leida = false;

-- ── RLS: cada usuario solo ve / gestiona SUS notificaciones ──
alter table flow.notificaciones enable row level security;

-- Ver las propias
drop policy if exists notificaciones_select_propias on flow.notificaciones;
create policy notificaciones_select_propias
  on flow.notificaciones for select
  to authenticated
  using (uuid_usuario = auth.uid());

-- Marcar como leida (update) solo las propias
drop policy if exists notificaciones_update_propias on flow.notificaciones;
create policy notificaciones_update_propias
  on flow.notificaciones for update
  to authenticated
  using (uuid_usuario = auth.uid())
  with check (uuid_usuario = auth.uid());

-- Insertar las propias (lo usa cliente_entrar_sala_espera, security invoker).
-- El bot (security definer / service_role) no pasa por estas politicas.
drop policy if exists notificaciones_insert_propias on flow.notificaciones;
create policy notificaciones_insert_propias
  on flow.notificaciones for insert
  to authenticated
  with check (uuid_usuario = auth.uid());

grant select, insert, update on flow.notificaciones to authenticated;
grant all on flow.notificaciones to service_role;
