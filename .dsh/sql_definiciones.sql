select p.proname as funcion,
       pg_get_functiondef(p.oid) as definicion
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('calcular_precio_con_reglas',
                    'calcular_precio_reserva',
                    'calcular_precio_turno',
                    'admin_guardar_turno_auto')
order by p.proname;