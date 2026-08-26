-- =============================================================
-- HR - Limpieza: eliminar la sobrecarga obsoleta de
--                fn_hr_update_worker_salary
--
-- 03_drop_fn_hr_update_worker_salary_v6
--
-- Aplicar en: Supabase > SQL Editor
-- Idempotente: DROP FUNCTION IF EXISTS.
--
--
-- QUE SE ELIMINA Y POR QUE
-- ------------------------
-- Existen DOS versiones sobrecargadas de la misma funcion:
--
--   A) fn_hr_update_worker_salary(integer, integer, numeric,
--        numeric, uuid, text)                      <- OBSOLETA
--   B) fn_hr_update_worker_salary(integer, integer, numeric,
--        numeric, uuid, text, text, numeric)       <- VIGENTE
--
-- La (A) es de antes de que el modulo soportara modalidad de
-- pago: solo escribe salario_horas y pago_por_resultado, y NO
-- conoce tipo_salario ni salario_dia. Si alguien la invoca, el
-- trabajador queda con su modalidad y su tarifa por dia
-- intactas mientras se le cambia la tarifa por hora, lo que
-- produce un pago incorrecto sin ningun error visible.
--
-- La (B) es la que llama la app:
-- lib/services/hr/hr_salary_report_service.dart ->
-- updateWorkerSalary() envia siempre los 8 parametros
-- (incluidos p_tipo_salario y p_salario_dia).
--
-- Ademas la (A) tiene p_motivo con DEFAULT NULL, asi que una
-- llamada con 5 argumentos posicionales tambien resolvia a ella.
--
-- Ambas estan concedidas a anon y authenticated, por lo que la
-- obsoleta es invocable desde cualquier cliente con la anon key.
--
--
-- POR QUE NO ROMPE NADA
-- ---------------------
-- - PostgREST resuelve la sobrecarga por los NOMBRES de los
--   parametros del JSON. La app manda los 8, que solo coinciden
--   con la (B): al quitar la (A) sigue resolviendo igual.
-- - Se reviso el repo completo: la unica llamada desde codigo es
--   la del servicio Dart, con 8 parametros.
-- - Ningun trigger, vista ni otra funcion la referencia.
--
-- Los .sql historicos del repo (ventiq_admin_app/hr_module_schema.sql
-- linea 451 y sql_updates/hr_salario_por_dias.sql linea 652)
-- crean la version de 6: son historico, no volver a ejecutarlos
-- tal cual o la sobrecarga reaparece.
-- =============================================================

DROP FUNCTION IF EXISTS public.fn_hr_update_worker_salary(
    INTEGER,   -- p_id_trabajador
    INTEGER,   -- p_id_tienda
    NUMERIC,   -- p_salario_horas
    NUMERIC,   -- p_pago_por_resultado
    UUID,      -- p_modificado_por
    TEXT       -- p_motivo
);


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Debe quedar UNA sola version, la de 8 parametros.
SELECT p.oid::regprocedure::text                   AS firma,
       pg_get_function_identity_arguments(p.oid)   AS args,
       p.prosecdef                                 AS security_definer,
       p.proacl::text                              AS permisos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_hr_update_worker_salary'
ORDER BY p.pronargs;

-- 2) Confirmacion explicita: la obsoleta ya no existe y la
--    vigente si. Debe devolver (false, true).
SELECT to_regprocedure(
           'public.fn_hr_update_worker_salary(integer,integer,numeric,numeric,uuid,text)'
       ) IS NOT NULL AS obsoleta_existe_debe_ser_false,
       to_regprocedure(
           'public.fn_hr_update_worker_salary(integer,integer,numeric,numeric,uuid,text,text,numeric)'
       ) IS NOT NULL AS vigente_existe_debe_ser_true;

-- 3) La vigente conserva sus permisos para la app.
SELECT has_function_privilege('authenticated',
           'public.fn_hr_update_worker_salary(integer,integer,numeric,numeric,uuid,text,text,numeric)',
           'EXECUTE') AS authenticated_puede_ejecutar,
       has_function_privilege('anon',
           'public.fn_hr_update_worker_salary(integer,integer,numeric,numeric,uuid,text,text,numeric)',
           'EXECUTE') AS anon_puede_ejecutar;
