-- ============================================================================
-- IA: CIERRE DE LA FUGA DE LA API KEY + VISTA PÚBLICA PARA EL CLIENTE
--
-- PROBLEMA MEDIDO EN PRODUCCIÓN (2026-11-06):
--   `config_asistant_model` tenía **RLS DESACTIVADO**, **0 políticas** y
--   `SELECT` concedido a `anon` y a `authenticated`. Con la clave pública —que
--   va dentro del bundle del web— cualquiera podía hacer:
--       GET /rest/v1/config_asistant_model?select=api_key
--   y llevarse la API del LLM en claro. No es una exposición teórica: la clave
--   pública es pública por definición.
--
-- SOLUCIÓN (dos piezas, y las dos hacen falta):
--   1. **Cerrar la tabla**: RLS activo + sin políticas (niega a anon y
--      authenticated) y revocación explícita de los GRANT. `service_role` tiene
--      `bypassrls`, así que las Edge Functions siguen leyéndola.
--   2. **Vista pública sin el secreto** `config_asistant_model_publico`, para que
--      el cliente siga sabiendo *qué proveedor* y *qué modelo* usar (eso no es
--      secreto) sin poder leer la clave. Sin esto, cerrar la tabla dejaría a las
--      apps sin saber siquiera a qué URL llamar.
--
-- La clave ya NO viaja al cliente: el único que la usa es la Edge Function
-- `ai-proxy`, en servidor, y por eso el navegador deja de tener CORS (es una
-- llamada a `*.supabase.co`, que sí tiene CORS correcto) y deja de tener la clave.
--
-- Idempotente. ⚠️ ORDEN: aplicar la vista ANTES de revocar, para no dejar la app
-- sin ninguna de las dos.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Vista pública: todo lo que el cliente necesita para armar la petición,
--    sin `api_key`.
-- ---------------------------------------------------------------------------
create or replace view public.config_asistant_model_publico as
  select id, model, url, param_type, param_key, created_at, updated_at
  from public.config_asistant_model;

comment on view public.config_asistant_model_publico is
  'Configuracion de IA SIN la api_key, para que el cliente sepa proveedor/modelo/URL. La clave solo la usa la Edge Function ai-proxy con service_role.';

grant select on public.config_asistant_model_publico to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Cerrar la tabla del secreto
-- ---------------------------------------------------------------------------
alter table public.config_asistant_model enable row level security;
-- Sin políticas => anon y authenticated no ven ninguna fila.
-- `service_role` (las Edge Functions) tiene bypassrls y sigue accediendo.

revoke all on public.config_asistant_model from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Verificación: debe quedar prohibido para anon/authenticated y permitido
--    para service_role, con la vista devolviendo filas y SIN columna api_key.
-- ---------------------------------------------------------------------------
select
  has_table_privilege('anon',          'public.config_asistant_model', 'SELECT') as anon_leer_tabla,
  has_table_privilege('authenticated', 'public.config_asistant_model', 'SELECT') as auth_leer_tabla,
  has_table_privilege('service_role',  'public.config_asistant_model', 'SELECT') as service_leer_tabla,
  has_table_privilege('authenticated', 'public.config_asistant_model_publico', 'SELECT') as auth_leer_vista,
  (select relrowsecurity from pg_class where oid = 'public.config_asistant_model'::regclass) as rls_activo;

select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'config_asistant_model_publico'
order by ordinal_position;   -- NO debe aparecer api_key

select count(*) as filas_visibles_en_la_vista
from public.config_asistant_model_publico;