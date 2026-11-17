BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30s';

SELECT current_database() AS base,
       current_user AS rol_inspeccion,
       current_setting('transaction_read_only') AS transaccion_solo_lectura,
       'Inventario M01: no cambia permisos ni demuestra pruebas funcionales por rol' AS alcance;

WITH targets(nombre) AS (
    VALUES ('app_dat_dueno'), ('app_dat_gerente'), ('app_dat_superadmin'),
           ('app_dat_supervisor'), ('auditor'), ('app_dat_vendedor'),
           ('app_dat_trabajadores'), ('app_dat_tpv'), ('app_dat_almacenero'),
           ('app_dat_almacen'), ('app_dat_jefe_cocina'), ('app_dat_cocina'),
           ('app_dat_tienda'), ('app_dat_operaciones'),
           ('app_dat_operacion_offline_idempotencia'), ('app_dat_configuracion_tienda')
)
SELECT targets.nombre AS tabla,
       c.oid IS NOT NULL AS existe,
       pg_get_userbyid(c.relowner) AS propietario,
       c.relrowsecurity AS rls,
       c.relforcerowsecurity AS force_rls,
       has_table_privilege('anon', c.oid, 'SELECT') AS anon_select,
       has_table_privilege('anon', c.oid, 'INSERT') AS anon_insert,
       has_table_privilege('anon', c.oid, 'UPDATE') AS anon_update,
       has_table_privilege('anon', c.oid, 'DELETE') AS anon_delete,
       has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE') AS authenticated_alguna_escritura,
       has_table_privilege('anon', c.oid, 'TRUNCATE,TRIGGER,REFERENCES') AS anon_algun_privilegio_fuera_de_rls,
       has_table_privilege('authenticated', c.oid, 'TRUNCATE,TRIGGER,REFERENCES') AS authenticated_algun_privilegio_fuera_de_rls,
       (
           SELECT jsonb_agg(jsonb_build_object(
               'nombre', p.policyname, 'roles', p.roles, 'comando', p.cmd,
               'combinacion', p.permissive, 'using', p.qual, 'check', p.with_check
           ) ORDER BY p.policyname)
           FROM pg_policies p
           WHERE p.schemaname = 'public' AND p.tablename = targets.nombre
       ) AS policies
FROM targets
LEFT JOIN pg_namespace n ON n.nspname = 'public'
LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = targets.nombre
ORDER BY targets.nombre;

WITH targets(nombre) AS (
    VALUES ('fn_user_is_dueno'), ('fn_is_superadmin_full_access'),
           ('fn_user_can_access_tienda'), ('check_user_has_access_to_tienda'),
           ('fn_config_tienda_puede_leer'), ('fn_config_tienda_puede_escribir')
)
SELECT targets.nombre,
       p.oid::regprocedure::text AS firma,
       p.prosecdef AS security_definer,
       p.proconfig AS configuracion_funcion,
       pg_get_userbyid(p.proowner) AS propietario,
       md5(pg_get_functiondef(p.oid)) AS huella_definicion,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       position('nivel_acceso' IN p.prosrc) > 0 AS menciona_nivel_acceso_no_es_prueba_semantica
FROM targets
LEFT JOIN pg_namespace n ON n.nspname = 'public'
LEFT JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = targets.nombre AND p.prokind = 'f'
ORDER BY targets.nombre, firma;

WITH funcs AS (
    SELECT p.oid, p.oid::regprocedure::text AS firma, p.prosrc,
           p.prosecdef, p.proconfig, p.proowner
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND n.nspname NOT LIKE 'pg_temp_%'
      AND p.prokind = 'f'
), matches AS (
    SELECT f.oid, f.firma, f.prosecdef, f.proconfig, f.proowner, m[1] AS tabla
    FROM funcs f
    CROSS JOIN LATERAL regexp_matches(
        f.prosrc,
        '(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?"?(app_dat_(?:gerente|vendedor|supervisor|trabajadores|tpv|dueno|superadmin|tienda|almacen|almacenero|jefe_cocina|cocina|operaciones)|auditor)\M',
        'gi'
    ) m
)
SELECT m.firma, m.prosecdef AS security_definer, m.proconfig,
       pg_get_userbyid(m.proowner) AS propietario,
       has_function_privilege('anon', m.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', m.oid, 'EXECUTE') AS authenticated_execute,
       md5(pg_get_functiondef(m.oid)) AS huella_definicion,
       array_agg(DISTINCT m.tabla ORDER BY m.tabla) AS destinos_textuales,
       'Indice textual: incluye comentarios y no detecta todo SQL dinamico o llamadas indirectas' AS limite
FROM matches m
GROUP BY m.oid, m.firma, m.prosecdef, m.proconfig, m.proowner
ORDER BY m.firma;

SELECT c.relname AS tabla, t.tgname AS trigger,
       t.tgenabled AS estado, t.tgfoid::regprocedure::text AS funcion,
       pg_get_triggerdef(t.oid, true) AS definicion
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND NOT t.tgisinternal
  AND c.relname IN (
      'app_dat_dueno', 'app_dat_gerente', 'app_dat_superadmin',
      'app_dat_supervisor', 'auditor', 'app_dat_vendedor',
      'app_dat_trabajadores', 'app_dat_tpv', 'app_dat_almacenero',
      'app_dat_almacen', 'app_dat_jefe_cocina', 'app_dat_cocina',
      'app_dat_tienda', 'app_dat_operaciones'
  )
ORDER BY c.relname, t.tgname;

SELECT c.conrelid::regclass::text AS tabla,
       c.conname AS restriccion,
       c.confrelid::regclass::text AS referencia,
       c.condeferrable AS diferible, c.condeferred AS diferida_inicialmente,
       pg_get_constraintdef(c.oid, true) AS definicion
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public' AND c.contype = 'f'
  AND t.relname IN (
      'app_dat_dueno', 'app_dat_gerente', 'app_dat_superadmin',
      'app_dat_supervisor', 'auditor', 'app_dat_vendedor',
      'app_dat_trabajadores', 'app_dat_tpv', 'app_dat_almacenero',
      'app_dat_almacen', 'app_dat_jefe_cocina', 'app_dat_cocina',
      'app_dat_tienda', 'app_dat_operaciones'
  )
ORDER BY tabla, restriccion;

SELECT 'vendedor_tpv_trabajador_tienda_incoherente' AS comprobacion,
       count(*) AS cantidad,
       'No corregir ni reasignar automaticamente' AS tratamiento
FROM public.app_dat_vendedor v
LEFT JOIN public.app_dat_tpv t ON t.id = v.id_tpv
LEFT JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
WHERE v.id_tpv IS NOT NULL AND v.id_trabajador IS NOT NULL
  AND (t.id IS NULL OR w.id IS NULL OR w.id_tienda IS DISTINCT FROM t.id_tienda)
UNION ALL
SELECT 'vendedor_uuid_y_trabajador_uuid_distintos', count(*), 'Revisar identidad; no copiar UUID por suposicion'
FROM public.app_dat_vendedor v
JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
WHERE w.uuid IS NOT NULL AND w.uuid IS DISTINCT FROM v.uuid
UNION ALL
SELECT 'vendedor_sin_tpv_ni_trabajador', count(*), 'Ambito no demostrable; no asignar tienda por suposicion'
FROM public.app_dat_vendedor v
WHERE v.id_tpv IS NULL AND v.id_trabajador IS NULL
UNION ALL
SELECT 'vendedor_sin_tpv', count(*), 'Puede ser desasignacion legitima; no es vendedor habilitado para vender'
FROM public.app_dat_vendedor v
WHERE v.id_tpv IS NULL
UNION ALL
SELECT 'tpv_almacen_tienda_incoherente', count(*), 'Revisar relacion; no mover stock ni cambiar historicos'
FROM public.app_dat_tpv t
LEFT JOIN public.app_dat_almacen a ON a.id = t.id_almacen
WHERE a.id IS NULL OR a.id_tienda IS DISTINCT FROM t.id_tienda
UNION ALL
SELECT 'gerente_trabajador_tienda_incoherente', count(*), 'Separar pertenencia de gerente e integridad de perfil; revisar antes del corte'
FROM public.app_dat_gerente g
LEFT JOIN public.app_dat_trabajadores w ON w.id = g.id_trabajador
WHERE g.id_trabajador IS NOT NULL
  AND (w.id IS NULL OR w.id_tienda IS DISTINCT FROM g.id_tienda);

COMMIT;
