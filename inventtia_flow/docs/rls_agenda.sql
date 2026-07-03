-- Políticas RLS para flow.agenda
-- Permitir que el dueño de la reserva y los administradores/dueños de la entidad
-- puedan actualizar (cancelar) y eliminar agendas.

-- 1. Habilitar RLS en la tabla
ALTER TABLE flow.agenda ENABLE ROW LEVEL SECURITY;

-- 2. Eliminar políticas previas si existen (para evitar duplicados)
DROP POLICY IF EXISTS "agenda_update_dueño_y_admins" ON flow.agenda;
DROP POLICY IF EXISTS "agenda_delete_dueño_y_admins" ON flow.agenda;

-- 3. Función auxiliar: verifica si el usuario actual es admin o dueño de la entidad
--    a la que pertenece el local_servicio de la agenda.
CREATE OR REPLACE FUNCTION flow.es_admin_o_dueño_de_entidad_de_agenda(p_id_local_servicio int)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM flow.local_servicio ls
    JOIN flow.app_dat_locales l ON l.id = ls.id_local
    WHERE ls.id = p_id_local_servicio
      AND (
        l.id_entidad IN (SELECT id FROM flow.entidad WHERE owner_uuid = auth.uid())
        OR
        EXISTS (
          SELECT 1 FROM flow.entidad_admin ea
          WHERE ea.id_entidad = l.id_entidad
            AND ea.uuid_usuario = auth.uid()
        )
      )
  );
$$;

-- 4. Política UPDATE (cancelar reserva)
CREATE POLICY "agenda_update_dueño_y_admins"
ON flow.agenda
FOR UPDATE
TO authenticated
USING (
  auth.uid() = uuid_usuario
  OR flow.es_admin_o_dueño_de_entidad_de_agenda(id_local_servicio)
)
WITH CHECK (
  auth.uid() = uuid_usuario
  OR flow.es_admin_o_dueño_de_entidad_de_agenda(id_local_servicio)
);

-- 5. Política DELETE (eliminar reserva)
CREATE POLICY "agenda_delete_dueño_y_admins"
ON flow.agenda
FOR DELETE
TO authenticated
USING (
  auth.uid() = uuid_usuario
  OR flow.es_admin_o_dueño_de_entidad_de_agenda(id_local_servicio)
);
