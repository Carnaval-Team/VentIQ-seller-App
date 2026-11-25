-- =============================================================================
-- Permiso que falta para que el cliente pueda guardar el avance del alta.
--
-- ESTADO: APLICADO EN NEWA (qhprswhhfasrikhawjoz). PENDIENTE DE APLICAR EN MAIN.
--
-- Sintoma reportado:
--   { "code": "42501",
--     "hint": "GRANT UPDATE ON public.app_dat_tienda TO authenticated",
--     "message": "permission denied for table app_dat_tienda" }
--
-- Causa:
--   `authenticated` tiene SELECT, INSERT, DELETE, REFERENCES, TRIGGER y
--   TRUNCATE sobre `app_dat_tienda`, pero **no tiene UPDATE**. Comprobado con
--   `has_table_privilege('authenticated','public.app_dat_tienda','UPDATE')`
--   -> false. Solo `postgres` y `service_role` lo tienen.
--
--   La politica RLS `m01_tienda_actualizar` (UPDATE, con USING y WITH CHECK)
--   existe desde el pase M01, pero una politica no concede privilegios: filtra
--   filas DESPUES de que el GRANT haya dejado pasar la sentencia. Sin el GRANT,
--   Postgres responde 42501 antes de mirar la politica. Por eso el UPDATE
--   fallaba aunque la RLS estuviera bien puesta.
--
-- Por que ahora se nota:
--   El alta progresiva (fase 2) escribe el avance parcial con un `update`
--   directo a `app_dat_tienda` desde el cliente
--   (`store_registration_screen.dart`, `_guardarAvanceParcial`). Antes de ese
--   cambio, el cliente solo INSERTABA la tienda por RPC (SECURITY DEFINER), asi
--   que la falta de UPDATE nunca se habia ejercitado.
--
-- Alcance del permiso:
--   UPDATE en toda la tabla es el mismo nivel que ya tiene INSERT y DELETE.
--   Quien puede decidir que filas se tocan es la RLS, no el GRANT: la politica
--   `m01_tienda_actualizar` exige `fn_config_tienda_puede_escribir(id)` (Dueno,
--   gerente o superadmin de esa tienda). Conceder UPDATE no amplia a que tiendas
--   se llega; solo permite que la sentencia llegue a evaluar la politica.
--
-- Nota: no se toca `estado`. Esa columna guarda el codigo de provincia.
-- =============================================================================

BEGIN;

GRANT UPDATE ON TABLE public.app_dat_tienda TO authenticated;

COMMIT;

-- =============================================================================
-- Verificacion (solo lectura)
-- =============================================================================

-- Debe dar true.
SELECT has_table_privilege('authenticated', 'public.app_dat_tienda', 'UPDATE')
       AS authenticated_puede_update;

-- Debe seguir dando false: anon no debe escribir en la tienda.
SELECT has_table_privilege('anon', 'public.app_dat_tienda', 'UPDATE')
       AS anon_puede_update;

-- La politica que decide QUE filas se actualizan debe seguir en su sitio.
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'app_dat_tienda'
ORDER BY policyname;

-- Inventario completo de privilegios de authenticated sobre la tabla.
SELECT privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tienda'
  AND grantee = 'authenticated'
ORDER BY privilege_type;
