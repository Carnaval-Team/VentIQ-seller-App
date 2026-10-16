select p.proname as funcion,
       pg_get_function_arguments(p.oid) as argumentos,
       pg_get_function_result(p.oid) as devuelve,
       position('calcular_precio_con_reglas' in pg_get_functiondef(p.oid)) > 0 as llama_helper_reglas,
       position('p_id_recurso' in pg_get_functiondef(p.oid)) > 0 as tiene_id_recurso,
       p.provolatile as volatilidad,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('calcular_precio_con_reglas',
                    'calcular_precio_reserva',
                    'calcular_precio_turno',
                    'admin_guardar_turno_auto',
                    'admin_guardar_turno',
                    '_admin_puede_recurso',
                    '_admin_puede_local_servicio')
order by p.proname;