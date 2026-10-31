-- =====================================================================
-- ENDURECIMIENTO OPCIONAL · quitar el search_path vacio de los 4 puntos
-- de entrada SECURITY DEFINER de venta offline / entrega fisica v2
--
-- Aplicar en LOS DOS proyectos: vsieeihstajlrdvpuooh (produccion) y
-- qhprswhhfasrikhawjoz (debug).
--
-- CUANDO HACE FALTA
--   * NO es necesario para el 42P01 de la venta: eso ya lo cierra
--     sql_updates/fix_search_path_venta_ingredientes.sql (bloques A + B).
--   * Sirve para eliminar del todo la clase de fallo "search_path vacio
--     heredado" (C9) en las rutas de venta offline y entrega fisica v2:
--     hoy estas 4 funciones son las unicas que pueden inyectar el vacio
--     hacia sus callees.
--
-- TRADE-OFF
--   Estas funciones son SECURITY DEFINER y tienen search_path = '' como pin
--   anti-hijacking. Al pasar a 'public', 'pg_catalog' se pierde ese pin.
--   Es seguro porque sus cuerpos son 100 % cualificados (verificado el
--   2026-10-29 sobre la BD de produccion: todas las referencias reales a
--   tablas van con public.; lo unico sin calificar son variables y
--   funciones de pg_catalog). No hay cambio funcional.
--
-- Idempotente. No toca datos. No crea funciones nuevas.
-- =====================================================================

begin;

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'fn_registrar_venta_offline_v2',
        'fn_registrar_venta_offline_v3',
        'fn_ejecutar_entrega_fisica_v2',
        'fn_preview_entrega_fisica_v2'
      )
  loop
    execute format(
      'alter function %s set search_path to ''public'', ''pg_catalog''',
      r.sig
    );
  end loop;
end $$;

commit;

-- ---------------------------------------------------------------------
-- VERIFICACION · esperado: las 4 filas con search_path=public, pg_catalog
-- (o "(NULL)" si la base no tuviera esas funciones, que no es el caso)
-- ---------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args,
  coalesce(array_to_string(p.proconfig, ', '), '(NULL)') as cfg
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'fn_registrar_venta_offline_v2',
    'fn_registrar_venta_offline_v3',
    'fn_ejecutar_entrega_fisica_v2',
    'fn_preview_entrega_fisica_v2'
  )
order by 1;

-- ---------------------------------------------------------------------
-- CENSO FINAL · cuantas funciones de public quedan con search_path vacio.
-- Con A + B + este fichero aplicados, el censo baja a las que no son de
-- venta ni de entrega fisica (catalogo/cumplimiento: get_productos_*,
-- fn_catalogo_stock_meta, fn_stock_mixto_*, ...), que se auto-corrigen con
-- set_config y no participan en el registro de ventas.
-- ---------------------------------------------------------------------
select count(*) as funciones_con_search_path_vacio
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and array_to_string(p.proconfig, ',') like '%search_path=""%';

-- ---------------------------------------------------------------------
-- ROLLBACK · devolver el pin original (search_path vacio)
-- ---------------------------------------------------------------------
-- begin;
-- do $$
-- declare r record;
-- begin
--   for r in
--     select p.oid::regprocedure as sig
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in (
--         'fn_registrar_venta_offline_v2',
--         'fn_registrar_venta_offline_v3',
--         'fn_ejecutar_entrega_fisica_v2',
--         'fn_preview_entrega_fisica_v2'
--       )
--   loop
--     execute format('alter function %s set search_path to ''''', r.sig);
--   end loop;
-- end $$;
-- commit;
-- =====================================================================
