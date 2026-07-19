-- ============================================================================
-- MIGRACION 18: Dejar UNA sola version de flow.cliente_reservar_directo (PGRST203)
--
-- Sintoma: al invocar cliente_reservar_directo por PostgREST/Supabase, la llamada
--   podia fallar con PGRST203 ("Could not choose the best candidate function...")
--   porque conviven 3 overloads y todos los parametros extra tienen DEFAULT, asi
--   que PostgREST no puede resolver a cual llamar cuando faltan p_moneda/p_id_turno.
--
-- Overloads presentes antes de esta migracion:
--   (uuid,int,date,int,jsonb,bool,text,text,text,text)                  -- sin moneda ni turno
--   (uuid,int,date,int,jsonb,bool,text,text,text,text,text)             -- con moneda
--   (uuid,int,date,int,jsonb,bool,text,text,text,text,text,int)         -- con moneda + turno  <-- SE CONSERVA
--
-- La version conservada es superconjunto real de las otras dos (misma logica +
-- validacion de turno, precio/moneda e insercion de id_turno en agenda), por lo
-- que eliminar las viejas no pierde funcionalidad.
--
-- Idempotente: DROP ... IF EXISTS. No altera datos.
-- ============================================================================

drop function if exists flow.cliente_reservar_directo(
  uuid, integer, date, integer, jsonb, boolean, text, text, text, text);

drop function if exists flow.cliente_reservar_directo(
  uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text);

-- Se conserva:
--   flow.cliente_reservar_directo(
--     uuid, integer, date, integer, jsonb, boolean,
--     text, text, text, text, text, integer)   -- con p_moneda y p_id_turno
