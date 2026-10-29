-- =====================================================================
-- VERIFICACION del fix 42P01 "app_dat_producto_ingredientes"
-- Ejecutar DESPUES de sql_updates/fix_search_path_venta_ingredientes.sql
-- En el mismo proyecto donde se aplico (release y debug).
--
-- SOLO LECTURA salvo la sonda final, que va dentro de BEGIN/ROLLBACK
-- (no deja cambios persistentes).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Las funciones de la cadena deben quedar con search_path fijado
--    ESPERADO: cfg = "search_path=public, pg_catalog" en todas las filas
-- ---------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args,
  coalesce(array_to_string(p.proconfig, ', '), '(NULL)') as cfg
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'fn_obtener_ingredientes_recursivos',
    'fn_validar_ingredientes_elaborado',
    'fn_descontar_ingredientes_elaborado',
    'fn_devolver_ingredientes_elaborado',
    'fn_ingredientes_con_parada_tanda',
    'fn_calcular_disponibilidad_productos_elaborados',
    'fn_eliminar_producto_orden',
    'fn_registrar_venta',
    'fn_registrar_venta_mesa',
    'fn_registrar_venta_v2',
    'fn_registrar_venta_mesa_v2',
    'fn_registrar_venta_v3',
    'fn_registrar_venta_mesa_v3',
    'check_user_has_access_to_tienda'
  )
order by 1, 2;

-- ---------------------------------------------------------------------
-- 2) El cuerpo de la funcion que fallaba ya no tiene referencias sin
--    calificar a las tablas de ingredientes
--    ESPERADO: 0 filas
-- ---------------------------------------------------------------------
select
  p.proname,
  btrim(l.txt) as linea_sin_cualificar
from pg_proc p,
     lateral unnest(string_to_array(p.prosrc, e'\n')) as l(txt)
where p.pronamespace = 'public'::regnamespace
  and p.proname = 'fn_obtener_ingredientes_recursivos'
  and l.txt ~* '(from|join|into|update)[[:space:]]+app_dat_producto'
order by 1, 2;

-- ---------------------------------------------------------------------
-- 3) Sonda de aceptacion: es EXACTAMENTE lo que antes devolvia
--    ERROR 42P01 relation "app_dat_producto_ingredientes" does not exist
--    ESPERADO: una fila con un numero (0 o mas), SIN error.
--    El primer id real se resuelve con la subconsulta.
-- ---------------------------------------------------------------------
begin;
  set local search_path = '';
  select count(*) as ingredientes_devueltos
  from public.fn_obtener_ingredientes_recursivos(
    (select id_producto_elaborado
       from public.app_dat_producto_ingredientes
      order by id_producto_elaborado
      limit 1),
    1
  );
rollback;

-- ---------------------------------------------------------------------
-- 4) Censo de lo que queda con search_path vacio (informativo)
--    Con A + B aplicados, el 42P01 ya no depende de estas.
-- ---------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args,
  array_to_string(p.proconfig, ', ') as cfg
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and (array_to_string(p.proconfig, ',') like '%search_path=""%'
       or p.proconfig is null)
  and p.proname in (
    'fn_obtener_ingredientes_recursivos','fn_validar_ingredientes_elaborado',
    'fn_descontar_ingredientes_elaborado','fn_ingredientes_con_parada_tanda',
    'fn_calcular_disponibilidad_productos_elaborados',
    'fn_registrar_venta','fn_registrar_venta_v2','fn_registrar_venta_v3',
    'fn_registrar_venta_offline_v2','fn_registrar_venta_offline_v3',
    'fn_ejecutar_entrega_fisica_v2','fn_preview_entrega_fisica_v2'
  )
order by cfg, 1;

-- ---------------------------------------------------------------------
-- 5) Comprobacion funcional final (manual, en la app):
--    registrar una venta con un producto ELABORADO (con receta) y verificar
--    que aparece el exito y que el inventario de los ingredientes baja.
--    Si volviera a fallar: el WHEN OTHERS del RPC no deja rastro en
--    postgres_logs, asi que hay que capturar el cuerpo de la respuesta del
--    RPC (o el mensaje en pantalla) para localizar la relacion concreta.
-- ---------------------------------------------------------------------
