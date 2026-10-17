select '43 tabla suscripcion_config' as marca,
       (select count(*) from information_schema.tables
         where table_schema = 'flow' and table_name = 'suscripcion_config') as existe
union all
select '44 funcion entidad_activa',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'entidad_activa')
union all
select '45 funcion cliente_crear_intent_suscripcion',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'cliente_crear_intent_suscripcion')
union all
select '46 funcion admin_notificaciones_pendientes',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'admin_notificaciones_pendientes')
union all
select '47 funcion validar_jerarquia_tipo_actividad',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'validar_jerarquia_tipo_actividad')
union all
select '48 funcion cliente_home_feed',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'cliente_home_feed')
union all
select '49 funcion campanas_activas',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'flow' and p.proname = 'campanas_activas')
order by marca;