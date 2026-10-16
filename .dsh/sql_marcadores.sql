select '40 local_servicio.sin_tramos' as marca,
       (select count(*) from information_schema.columns
         where table_schema = 'flow' and table_name = 'local_servicio'
           and column_name = 'sin_tramos') as existe
union all
select '40 turno.hora_inicio',
       (select count(*) from information_schema.columns
         where table_schema = 'flow' and table_name = 'turno'
           and column_name = 'hora_inicio')
union all
select '41 funcion admin_guardar_turno_auto',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'admin_guardar_turno_auto')
union all
select '42 cliente_obtener_servicios(p_incluir_inactivos)',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'cliente_obtener_servicios'
           and pg_get_function_arguments(p.oid) like '%p_incluir_inactivos%')
union all
select '51 funcion calcular_precio_con_reglas',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'calcular_precio_con_reglas')
order by marca;