-- GENERADOR main → newa (solo lectura). Ejecutar en el SQL Editor de **main**.
--
-- Devuelve una fila con la columna `script`: el SQL a ejecutar en **newa**. Copiar la
-- celda; si el editor la corta, usar "Download CSV".
--
-- Cubre las secciones 3.2–3.4 de desincronizacion_newa_main.md:
--   - tablas: referidos, WhatsApp agotados, carrito (bloqueos e historial);
--   - columnas que faltan en tablas existentes;
--   - 31 funciones de public y 3 de carnavalapp, con sus GRANT;
--   - la vista carnavalapp.v_carrito_abuso_soporte;
--   - los triggers que usan esas funciones;
--   - la firma nueva de fn_listar_entregas_por_fechas_usuario (con p_id_turno), quitando
--     la vieja de newa como en main.
--
-- NO cubre (a mano, ver la sección 4 del informe):
--   - fn_descontar_venta_enrutada_v2(…,jsonb), fn_fdi_crear_liquidacion(10 params),
--     fn_actualizar_operacion_contabilizada(bigint,boolean,bigint): newa tiene otra
--     sobrecarga y dos a la vez pueden volver ambiguas las llamadas por nombre. Combinar.
--   - fn_desvincular_usuario_trabajador: M01 (24) la reemplaza.
--   - fn_trg_bloquear_operaciones_usuario y trg_bloquear_operaciones_maria: bloqueo
--     puntual de un usuario de producción.
--   - Las 86 funciones con cuerpo distinto (incluye los fixes de las migraciones
--     fix_inventario_resumen_v2_dedup_presentaciones, fix_precio_venta_order_by_id,
--     fix_fn_listar_motivos_extraccion_permisos y orden_carnaval_marca_motivo_orden).
--   - Cron jobs de main: no se copian (algunos llaman servicios de producción). El de
--     WhatsApp watchdog es: select cron.schedule('wapi_session_watchdog', '*/5 * * * *',
--     'SELECT public.fn_wapi_session_watchdog()');
--
-- RLS: las tablas de referidos tienen RLS activo y 0 policies, igual que en main (solo
-- se accede por funciones SECURITY DEFINER). El resto trae sus policies de main.
--
-- PERMISOS: el script copia los de main, que son los de Supabase por defecto (anon con
-- TRUNCATE en las tablas y funciones DEFINER ejecutables por anon/PUBLIC). Antes del
-- COMMIT hay que pegar el bloque "ENDURECIMIENTO newa" de response.sql (corrida del
-- 18/11), que cierra anon salvo en referidos (landing) y fn_app_versiones.

with
fn_lista(sig) as (
    select unnest(array[
        'public.fn_wapi_session_watchdog()',
        'public.fn_wapi_session_recovery_report(bigint)',
        'public.fn_wapi_agotado_stock_total(bigint,bigint)',
        'public.fn_wapi_agotado_check()',
        'public.fn_info_contabilizacion_ordenes_carnaval(bigint[],bigint)',
        'public.fn_historial_contabilizacion_operacion(bigint,bigint)',
        'public.fn_fix_precio_venta_created_at_order(bigint,bigint,boolean)',
        'public.fn_verify_precio_venta_duplicate_versions(bigint,bigint,boolean)',
        'public.fn_cerrar_precios_venta_activos_duplicados(bigint,bigint,boolean)',
        'public.get_product_movements_v5(bigint,date,date,bigint,bigint,integer,integer)',
        'public.fn_reporte_ventas_por_turno_vendedor(uuid,date,date,bigint)',
        'public.fn_reporte_ventas_turno_vendedor(uuid,date,date,bigint)',
        'public.fn_carnaval_precio_base_vigente(bigint)',
        'public.rpc_recalc_carnaval_prices_for_store(bigint)',
        'public.fn_trg_recalc_carnaval_on_store_pricing()',
        'public.fn_corregir_costo_recepcion(bigint,numeric,timestamp with time zone)',
        'public.fn_corregir_costo_recepcion(bigint,numeric,timestamp with time zone,bigint,bigint)',
        'public.fn_eliminar_order_detail_con_devolucion_v2(bigint,boolean,boolean)',
        'public.fn_cancelar_orden_carnaval_v2(bigint,text)',
        'public.fn_referral_request_ip()',
        'public.fn_referral_ip_hash()',
        'public.fn_referral_phone_norm(text)',
        'public.fn_referral_phone_hash(text)',
        'public.fn_referral_visit_register(text,text,text,text)',
        'public.fn_referral_visit_attach_phone(text,text)',
        'public.fn_referral_visits_purge(integer)',
        'public.fn_listar_entregas_por_fechas_usuario(timestamp with time zone,timestamp with time zone,uuid,bigint)',
        'public.fn_version_menor(text,text)',
        'public.fn_app_versiones(character varying,integer)',
        'public.fn_app_version_guardar(integer,character varying,character varying,integer,character varying,boolean,text,jsonb,text,boolean)',
        'public.fn_app_version_eliminar(integer)'
    ])
),
fns as (
    select p.oid
    from pg_proc p
    where p.oid in (select to_regprocedure(sig) from fn_lista)
    union
    select p.oid
    from pg_proc p
    where p.pronamespace = 'carnavalapp'::regnamespace
      and p.proname in ('fn_check_carrito_abuse', 'fn_desbloquear_carrito', 'fn_log_carrito_eliminacion')
),
tablas as (
    select c.oid, n.nspname, c.relname,
           format('%I.%I', n.nspname, c.relname) q,
           c.relrowsecurity, c.relforcerowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.oid in (
        'public.referral_capture_config'::regclass,
        'public.referral_visits'::regclass,
        'public.referral_user_attributions'::regclass,
        'public.app_wapi_agotado_config'::regclass,
        'public.app_wapi_agotado_destinatario'::regclass,
        'public.app_wapi_agotado_estado'::regclass,
        'public.app_wapi_agotado_log'::regclass,
        'carnavalapp.carrito_historial_eliminaciones'::regclass,
        'carnavalapp.carrito_bloqueos'::regclass
    )
),
col_def as (
    select a.attrelid, a.attnum, a.attname,
           format('%I %s', a.attname, format_type(a.atttypid, a.atttypmod))
           || case a.attidentity
                  when 'a' then ' GENERATED ALWAYS AS IDENTITY'
                  when 'd' then ' GENERATED BY DEFAULT AS IDENTITY'
                  else '' end
           || case when a.attgenerated = 's'
                   then ' GENERATED ALWAYS AS (' || pg_get_expr(d.adbin, d.adrelid) || ') STORED'
                   when d.adbin is not null
                   then ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid)
                   else '' end
           || case when a.attnotnull then ' NOT NULL' else '' end as def
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attnum > 0 and not a.attisdropped
),
columnas_extra(tabla, col) as (
    values
        ('public.app_dat_configuracion_tienda'::regclass, 'reporte_tpvs_modo_turno'),
        ('public.app_versiones'::regclass, 'titulo'),
        ('public.app_versiones'::regclass, 'novedades'),
        ('public.app_versiones'::regclass, 'url_descarga'),
        ('public.app_wapi_sesion'::regclass, 'watchdog_enabled'),
        ('public.app_wapi_sesion'::regclass, 'recovery_attempts'),
        ('public.app_wapi_sesion'::regclass, 'last_recovery_at'),
        ('public.app_wapi_sesion'::regclass, 'last_error_code'),
        ('public.app_wapi_sesion'::regclass, 'last_error_message'),
        ('public.app_wapi_sesion'::regclass, 'raw_status'),
        ('public.app_wapi_programacion'::regclass, 'solo_disponibles')
),
partes(orden, sub, txt) as (
    -- 0. Cabecera y preflight
    select 0, 0, $h$BEGIN;
-- Generado desde main. Ejecutar en newa (postgres). Revisar antes de COMMIT.
SET LOCAL check_function_bodies = off;
SET LOCAL lock_timeout = '5s';
DO $pre$
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
  IF to_regclass('public.referral_visits') IS NOT NULL
     OR to_regclass('public.app_wapi_agotado_config') IS NOT NULL
     OR to_regclass('carnavalapp.carrito_bloqueos') IS NOT NULL THEN
    RAISE EXCEPTION 'Una tabla de este paquete ya existe en newa: revisar antes de reaplicar';
  END IF;
END $pre$;$h$
    union all
    -- 1. Secuencias de columnas serial
    select 1, 0, string_agg(format('CREATE SEQUENCE IF NOT EXISTS %I.%I;', sn.nspname, s.relname), E'\n')
    from tablas t
    join pg_depend dp on dp.refobjid = t.oid and dp.deptype = 'a' and dp.classid = 'pg_class'::regclass
    join pg_class s on s.oid = dp.objid and s.relkind = 'S'
    join pg_namespace sn on sn.oid = s.relnamespace
    union all
    -- 2. Tablas
    select 2, 0, string_agg(
        format(E'CREATE TABLE %s (\n  %s\n);', t.q,
               (select string_agg(cd.def, E',\n  ' order by cd.attnum) from col_def cd where cd.attrelid = t.oid)),
        E'\n\n')
    from tablas t
    union all
    -- 3. Dueño de las secuencias
    select 3, 0, string_agg(format('ALTER SEQUENCE %I.%I OWNED BY %s.%I;', sn.nspname, s.relname, t.q, a.attname), E'\n')
    from tablas t
    join pg_depend dp on dp.refobjid = t.oid and dp.deptype = 'a' and dp.classid = 'pg_class'::regclass
    join pg_class s on s.oid = dp.objid and s.relkind = 'S'
    join pg_namespace sn on sn.oid = s.relnamespace
    join pg_attribute a on a.attrelid = t.oid and a.attnum = dp.refobjsubid
    union all
    -- 4. Restricciones que no son FK
    select 4, 0, string_agg(format('ALTER TABLE %s ADD CONSTRAINT %I %s;', t.q, k.conname, pg_get_constraintdef(k.oid)), E'\n' order by t.q, k.contype desc, k.conname)
    from tablas t join pg_constraint k on k.conrelid = t.oid and k.contype <> 'f'
    union all
    -- 5. FK
    select 5, 0, string_agg(format('ALTER TABLE %s ADD CONSTRAINT %I %s;', t.q, k.conname, pg_get_constraintdef(k.oid)), E'\n' order by t.q, k.conname)
    from tablas t join pg_constraint k on k.conrelid = t.oid and k.contype = 'f'
    union all
    -- 6. Índices que no respaldan una restricción
    select 6, 0, string_agg(pg_get_indexdef(i.indexrelid) || ';', E'\n')
    from tablas t join pg_index i on i.indrelid = t.oid
    where not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
    union all
    -- 7. RLS (en las mismas tablas, inmediatamente después de crearlas)
    select 7, 0, string_agg(
        format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY;', t.q)
        || case when t.relforcerowsecurity then format(E'\nALTER TABLE %s FORCE ROW LEVEL SECURITY;', t.q) else '' end,
        E'\n')
    from tablas t where t.relrowsecurity
    union all
    -- 8. Policies
    select 8, 0, string_agg(
        format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
               p.policyname, p.schemaname, p.tablename, p.permissive, p.cmd,
               array_to_string(p.roles, ', '),
               case when p.qual is not null then ' USING (' || p.qual || ')' else '' end,
               case when p.with_check is not null then ' WITH CHECK (' || p.with_check || ')' else '' end),
        E'\n')
    from pg_policies p join tablas t on t.nspname = p.schemaname and t.relname = p.tablename
    union all
    -- 9. GRANT de tablas
    select 9, 0, string_agg(format('GRANT %s ON %s TO %I;', g.privs, g.q, g.grantee), E'\n')
    from (
        select t.q, r.grantee, string_agg(r.privilege_type, ', ' order by r.privilege_type) privs
        from tablas t
        join information_schema.role_table_grants r
          on r.table_schema = t.nspname and r.table_name = t.relname
        where r.grantee in ('anon', 'authenticated', 'service_role')
        group by t.q, r.grantee
    ) g
    union all
    -- 10. Columnas que faltan en tablas existentes
    select 10, 0, string_agg(format('ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s;', ce.tabla::text, cd.def), E'\n')
    from columnas_extra ce
    join col_def cd on cd.attrelid = ce.tabla and cd.attname = ce.col
    union all
    -- 11. Firma vieja de egresos (main solo tiene la que lleva p_id_turno)
    select 11, 0, 'DROP FUNCTION IF EXISTS public.fn_listar_entregas_por_fechas_usuario(timestamp without time zone, timestamp without time zone, uuid);'
    union all
    -- 12. Funciones + privilegios
    select 12, row_number() over (order by p.oid::regprocedure::text),
           rtrim(pg_get_functiondef(p.oid), E'\n') || E';\n'
           || case when p.proacl is null then '' else
                format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC;', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
                || coalesce((
                    select string_agg(
                        format(E'\nGRANT EXECUTE ON FUNCTION %I.%I(%s) TO %s;', n.nspname, p.proname,
                               pg_get_function_identity_arguments(p.oid),
                               case when x.grantee = 0 then 'PUBLIC' else quote_ident(r.rolname) end), '')
                    from aclexplode(p.proacl) x
                    left join pg_roles r on r.oid = x.grantee
                    where x.privilege_type = 'EXECUTE'
                      and (x.grantee = 0 or r.rolname in ('anon', 'authenticated', 'service_role'))
                ), '')
              end
    from fns f join pg_proc p on p.oid = f.oid join pg_namespace n on n.oid = p.pronamespace
    union all
    -- 13. Vista del carrito
    select 13, 0,
           format('CREATE OR REPLACE VIEW %I.%I%s AS %s;', n.nspname, c.relname,
                  case when c.reloptions is not null then ' WITH (' || array_to_string(c.reloptions, ', ') || ')' else '' end,
                  rtrim(pg_get_viewdef(c.oid, true), E';\n '))
           || coalesce((
               select string_agg(format(E'\nGRANT %s ON %I.%I TO %I;', r.privilege_type, n.nspname, c.relname, r.grantee), '')
               from information_schema.role_table_grants r
               where r.table_schema = n.nspname and r.table_name = c.relname
                 and r.grantee in ('anon', 'authenticated', 'service_role')
           ), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'carnavalapp' and c.relname = 'v_carrito_abuso_soporte'
    union all
    -- 14. Triggers que usan estas funciones
    select 14, 0, string_agg(
        format('DROP TRIGGER IF EXISTS %I ON %s;', tg.tgname, tg.tgrelid::regclass::text)
        || E'\n' || pg_get_triggerdef(tg.oid) || ';',
        E'\n' order by tg.tgrelid::regclass::text, tg.tgname)
    from pg_trigger tg
    where not tg.tgisinternal and tg.tgfoid in (select oid from fns)
    union all
    select 99, 0, E'-- Revisar los resultados y cerrar:\nCOMMIT;'
)
select string_agg(txt, E'\n\n' order by orden, sub) as script
from partes
where txt is not null;
