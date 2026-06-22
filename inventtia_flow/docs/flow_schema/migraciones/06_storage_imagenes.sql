-- ============================================================================
-- Migración 06: Storage bucket para imágenes de locales y servicios
-- Las columnas 'foto' ya existen en app_dat_locales y app_dat_servicios
-- como TEXT (URL pública). Solo se crea el bucket y sus políticas.
-- ============================================================================

-- Bucket público para imágenes de la app flow
insert into storage.buckets (id, name, public)
values ('flow-imagenes', 'flow-imagenes', true)
on conflict (id) do nothing;

-- ── Políticas de storage ──────────────────────────────────────────────────

-- Lectura pública (cualquiera puede ver las imágenes)
create policy "flow_imagenes_read_public"
on storage.objects for select
using (bucket_id = 'flow-imagenes');

-- Subida: solo usuarios autenticados
create policy "flow_imagenes_insert_auth"
on storage.objects for insert
with check (
  bucket_id = 'flow-imagenes'
  and auth.role() = 'authenticated'
);

-- Actualización: solo el usuario que subió la imagen
create policy "flow_imagenes_update_auth"
on storage.objects for update
using (
  bucket_id = 'flow-imagenes'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (bucket_id = 'flow-imagenes');

-- Borrado: solo el usuario que subió la imagen
create policy "flow_imagenes_delete_auth"
on storage.objects for delete
using (
  bucket_id = 'flow-imagenes'
  and auth.uid()::text = (storage.foldername(name))[1]
);

-- ── Notas de uso ──────────────────────────────────────────────────────────
-- Path locales:   flow-imagenes/locales/{id_local}.jpg
-- Path servicios: flow-imagenes/servicios/{id_servicio}.jpg
-- URL pública:    {SUPABASE_URL}/storage/v1/object/public/flow-imagenes/{path}
