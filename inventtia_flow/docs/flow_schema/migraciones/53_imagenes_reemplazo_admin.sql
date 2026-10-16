-- ============================================================================
-- Migración 53: reemplazar la foto de un local/servicio desde el panel
-- ============================================================================
--
-- EL FALLO QUE CORRIGE (reportado: "para actualizar la foto me saltan los RLS")
--
--   La migración 06 creó las políticas del bucket `flow-imagenes` con un
--   predicado de propiedad por carpeta:
--
--     using (bucket_id = 'flow-imagenes'
--            and auth.uid()::text = (storage.foldername(name))[1])
--
--   `storage.foldername(name))[1]` es el PRIMER segmento del path. Los paths de
--   la app son `locales/{id}.jpg` y `servicios/{id}.jpg` (ver
--   `ImagenService.pathLocal` / `pathServicio`), así que ese segmento vale
--   `'locales'` o `'servicios'` — nunca el uuid del usuario. La condición es
--   **siempre falsa**.
--
--   Consecuencia exacta que se veía en la app:
--     * SUBIR la primera foto: funciona (la política de INSERT solo exige
--       `auth.role() = 'authenticated'`).
--     * REEMPLAZARLA: falla. `subirImagen` usa `upsert: true`, y un upsert sobre
--       un objeto que ya existe necesita la política de **UPDATE**, que no casa.
--
-- LA CORRECCIÓN
--
--   En vez de "el dueño del archivo" (que con estos paths no tiene sentido), la
--   política pasa a ser **el administrador de la entidad dueña del local o del
--   servicio**, que es exactamente el mismo permiso que ya hace falta para
--   editar esa fila en `flow.app_dat_locales` / `flow.app_dat_servicios`
--   (`locales_update_admin` / `servicios_update_admin` usan
--   `flow.is_entidad_admin(id_entidad)`).
--
--   Así el bucket NO se abre de más: un usuario autenticado cualquiera (un
--   cliente de la app) sigue sin poder sobrescribir ni borrar fotos ajenas.
-- ============================================================================

-- Traduce el path de una imagen a "¿puede este usuario mandar en ella?".
--
--   locales/{id}.jpg    -> es admin de la entidad dueña del local {id}
--   servicios/{id}.jpg  -> es admin de la entidad dueña del servicio {id}
--   cualquier otra cosa -> false
--
-- SECURITY DEFINER para que la comprobación no dependa de las políticas de las
-- tablas del catálogo, y con `search_path` fijo para que no se pueda desviar.
create or replace function flow.es_admin_de_la_imagen(p_name text)
returns boolean
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  with partes as (
    select
      split_part(p_name, '/', 1) as carpeta,
      -- El nombre del archivo es el id, con o sin extensión: '12.jpg' -> 12.
      nullif(regexp_replace(split_part(p_name, '/', 2), '[^0-9]', '', 'g'), '')::int as id
  )
  select coalesce(
    case
      when p.carpeta = 'locales' then exists (
        select 1
        from flow.app_dat_locales l
        where l.id = p.id
          and flow.is_entidad_admin(l.id_entidad)
      )
      when p.carpeta = 'servicios' then exists (
        select 1
        from flow.app_dat_servicios s
        where s.id = p.id
          and flow.is_entidad_admin(s.id_entidad)
      )
      else false
    end,
    false
  )
  from partes p;
$function$;

comment on function flow.es_admin_de_la_imagen(text) is
  '¿Es el usuario actual administrador de la entidad dueña del local/servicio '
  'cuya foto está en el path dado? Se usa en las políticas del bucket '
  'flow-imagenes.';

-- ── Políticas de reemplazo y borrado ────────────────────────────────────────
-- Se sustituyen las dos que nunca casaban. La lectura pública y la subida
-- autenticada de la migración 06 se mantienen tal cual.

drop policy if exists "flow_imagenes_update_auth" on storage.objects;
create policy "flow_imagenes_update_admin"
on storage.objects for update
to authenticated
using (
  bucket_id = 'flow-imagenes'
  and flow.es_admin_de_la_imagen(name)
)
with check (
  bucket_id = 'flow-imagenes'
  and flow.es_admin_de_la_imagen(name)
);

drop policy if exists "flow_imagenes_delete_auth" on storage.objects;
create policy "flow_imagenes_delete_admin"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'flow-imagenes'
  and flow.es_admin_de_la_imagen(name)
);

-- ── Comprobación del parseo del path (sin tocar datos) ──────────────────────
-- Debe devolver 'locales' / 12 y 'servicios' / 7.
--
--   select split_part('locales/12.jpg', '/', 1) as carpeta,
--          nullif(regexp_replace(split_part('locales/12.jpg', '/', 2),
--                                '[^0-9]', '', 'g'), '')::int as id,
--          split_part('servicios/7.jpg', '/', 1) as carpeta2,
--          nullif(regexp_replace(split_part('servicios/7.jpg', '/', 2),
--                                '[^0-9]', '', 'g'), '')::int as id2;