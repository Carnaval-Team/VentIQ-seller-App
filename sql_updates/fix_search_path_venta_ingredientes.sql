-- =====================================================================
-- FIX 42P01 · relation "app_dat_producto_ingredientes" does not exist
-- al registrar una venta (pantalla "Finalizar Orden")
--
-- Aplicar en LOS DOS proyectos Supabase:
--   * release / produccion : vsieeihstajlrdvpuooh
--   * debug (flutter run)  : qhprswhhfasrikhawjoz
--
-- Autor: sesion de diagnostico 2026-10-29 (rama main)
-- Enfoque: modificar las funciones EXISTENTES en sitio (CREATE OR REPLACE /
--          ALTER FUNCTION). No se crean funciones nuevas _v5/_vx.
-- Idempotente: se puede ejecutar varias veces. No toca datos.
-- =====================================================================
--
-- SINTOMA
--   Al finalizar la venta la app pinta:
--     Error al registrar la venta: Error al registrar venta:
--     relation "app_dat_producto_ingredientes" does not exist
--   * prefijo externo ("Error al registrar la venta: ") -> Dart,
--     ventiq_app/lib/screens/checkout_screen.dart:2387
--   * prefijo interno ("Error al registrar venta: ") -> SQL, EXCEPTION WHEN
--     OTHERS de fn_registrar_venta / _v2 / _v3 / _mesa / _mesa_v2 / _mesa_v3
--   El RPC responde HTTP 200 con {status:error,message:...}; por eso el fallo
--   NO aparece en postgres_logs (la excepcion se captura).
--
-- CAUSA
--   fn_obtener_ingredientes_recursivos referencia app_dat_producto_ingredientes
--   y app_dat_producto SIN el prefijo public. y su proconfig es NULL: no fija
--   search_path, lo HEREDA del llamador. En la cadena de venta hay funciones
--   SECURITY DEFINER con SET search_path TO '' (fn_registrar_venta_offline_v2 /
--   _v3, fn_ejecutar_entrega_fisica_v2, fn_preview_entrega_fisica_v2,
--   fn_planificar_entrega_fisica_v2, fn_buscar_empaques_exactos_v2, ...). Al
--   heredarse el search_path vacio, PostgreSQL no resuelve la relacion -> 42P01
--   -> fn_registrar_venta_v3 lo captura y devuelve "Error al registrar venta:
--   relation \"app_dat_producto_ingredientes\" does not exist".
--   La tabla SI existe: public.app_dat_producto_ingredientes (relkind = r).
--
-- EVIDENCIA (sonda reproducida en produccion, sin cambios persistentes)
--   set local search_path = '';
--     select count(*) from public.fn_obtener_ingredientes_recursivos(10245,1);
--       -> ERROR 42P01: relation "app_dat_producto_ingredientes" does not exist
--   con search_path = public:
--       -> 8 filas
--
-- ARREGLO
--   A) fn_obtener_ingredientes_recursivos: mismo cuerpo vivo de produccion,
--      con public. en las 4 referencias a tablas + search_path propio.
--   B) Fijar search_path = 'public', 'pg_catalog' en las funciones de la
--      cadena de venta/ingredientes que hoy no lo fijan (proconfig NULL), para
--      que no dependan de lo que hereden del llamador.
--   C) (Opcional, al final y comentado) endurecer tambien los puntos de
--      entrada SECURITY DEFINER que hoy tienen search_path = ''.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- A) La funcion que falla: se recrea con public. y search_path propio
--    (cuerpo identico al vivo en produccion)
-- ---------------------------------------------------------------------
create or replace function public.fn_obtener_ingredientes_recursivos(
  p_id_producto_elaborado bigint,
  p_cantidad_producto numeric default 1)
returns table(id_ingrediente bigint, cantidad_total_necesaria numeric, nivel_recursion integer)
language plpgsql
set search_path to 'public', 'pg_catalog'
as $function$
begin
  return query
  with recursive ingredientes_recursivos as (
    -- Caso base: ingredientes directos del producto
    select
      pi.id_ingrediente,
      pi.cantidad_necesaria * p_cantidad_producto as cantidad_total,
      1 as nivel,
      array[p_id_producto_elaborado] as ruta_productos
    from public.app_dat_producto_ingredientes pi
    where pi.id_producto_elaborado = p_id_producto_elaborado

    union all

    -- Caso recursivo: ingredientes de ingredientes que tambien son elaborados
    select
      pi.id_ingrediente,
      pi.cantidad_necesaria * ir.cantidad_total as cantidad_total,
      ir.nivel + 1 as nivel,
      ir.ruta_productos || pi.id_producto_elaborado as ruta_productos
    from public.app_dat_producto_ingredientes pi
    inner join ingredientes_recursivos ir on pi.id_producto_elaborado = ir.id_ingrediente
    inner join public.app_dat_producto p on p.id = pi.id_producto_elaborado
    where p.es_elaborado = true
      and not (pi.id_producto_elaborado = any(ir.ruta_productos)) -- evitar ciclos
      and ir.nivel < 10                                            -- limite de seguridad
  )
  -- Agrupar y sumar cantidades de ingredientes duplicados
  select
    ir.id_ingrediente,
    sum(ir.cantidad_total) as cantidad_total_necesaria,
    max(ir.nivel) as nivel_recursion
  from ingredientes_recursivos ir
  inner join public.app_dat_producto p on p.id = ir.id_ingrediente
  where p.es_elaborado = false -- solo ingredientes finales (no elaborados)
  group by ir.id_ingrediente;
end;
$function$;

-- ---------------------------------------------------------------------
-- B) Cortar la herencia del search_path en la cadena de venta/ingredientes
--    (todas estas tienen proconfig NULL hoy: heredan lo que ponga el llamador)
-- ---------------------------------------------------------------------
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
        -- RPCs de venta (online y mesa)
        'fn_registrar_venta',
        'fn_registrar_venta_mesa',
        'fn_registrar_venta_v2',
        'fn_registrar_venta_mesa_v2',
        'fn_registrar_venta_v3',
        'fn_registrar_venta_mesa_v3',
        -- cadena de ingredientes / disponibilidad
        'fn_obtener_ingredientes_recursivos',
        'fn_validar_ingredientes_elaborado',
        'fn_descontar_ingredientes_elaborado',
        'fn_devolver_ingredientes_elaborado',
        'fn_ingredientes_con_parada_tanda',
        'fn_calcular_disponibilidad_productos_elaborados',
        'fn_eliminar_producto_orden',
        -- guard de acceso a tienda (idempotente: ya suele estar fijado)
        'check_user_has_access_to_tienda'
      )
  loop
    execute format(
      'alter function %s set search_path to ''public'', ''pg_catalog''',
      r.sig
    );
  end loop;
end $$;

commit;

-- =====================================================================
-- C) OPCIONAL · puntos de entrada SECURITY DEFINER con search_path = ''
--    Con A + B ya no son necesarios para este fallo; tienen el vacio como
--    medida anti-hijacking, asi que si se cambian se pierde ese pin.
--    Descomentar solo si se quiere eliminar el search_path vacio del todo.
-- ---------------------------------------------------------------------
-- begin;
-- do $$
-- declare r record;
-- begin
--   for r in
--     select p.oid::regprocedure as sig
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in (
--         'fn_registrar_venta_offline_v2',
--         'fn_registrar_venta_offline_v3',
--         'fn_ejecutar_entrega_fisica_v2',
--         'fn_preview_entrega_fisica_v2'
--       )
--   loop
--     execute format(
--       'alter function %s set search_path to ''public'', ''pg_catalog''',
--       r.sig
--     );
--   end loop;
-- end $$;
-- commit;

-- =====================================================================
-- ROLLBACK (por si hiciera falta; ejecutar en el mismo proyecto)
-- ---------------------------------------------------------------------
-- begin;
-- -- A) devolver el cuerpo sin public. (cuerpo original de produccion):
-- --    repetir el create or replace de arriba quitando "public." de las 4
-- --    referencias y quitando la linea "set search_path to 'public', 'pg_catalog'".
-- -- B) quitar el search_path fijado en B:
-- do $$
-- declare r record;
-- begin
--   for r in
--     select p.oid::regprocedure as sig
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in (
--         'fn_registrar_venta','fn_registrar_venta_mesa',
--         'fn_registrar_venta_v2','fn_registrar_venta_mesa_v2',
--         'fn_registrar_venta_v3','fn_registrar_venta_mesa_v3',
--         'fn_obtener_ingredientes_recursivos','fn_validar_ingredientes_elaborado',
--         'fn_descontar_ingredientes_elaborado','fn_devolver_ingredientes_elaborado',
--         'fn_ingredientes_con_parada_tanda',
--         'fn_calcular_disponibilidad_productos_elaborados','fn_eliminar_producto_orden'
--       )
--   loop
--     execute format('alter function %s reset search_path', r.sig);
--   end loop;
-- end $$;
-- commit;

-- =====================================================================
-- DESPUES DE APLICAR
--   1) Ejecutar sql_updates/verificar_fix_search_path_venta_ingredientes.sql
--   2) Hacer una venta de prueba con un producto ELABORADO (con receta)
--      desde la app: debe registrarse sin el cartel rojo.
--   3) Repetir la aplicacion en el otro proyecto (debug/release).
--
-- NOTA DE MANTENIMIENTO
--   * ventiq_app/sql/fn_registrar_venta_offline_v3.sql:34 sigue con
--     SET search_path TO '' en main: si se rehace la BD desde el repo, el pin
--     vuelve (aunque A + B lo cubren).
--   * El cuerpo de fn_obtener_ingredientes_recursivos NO esta versionado en
--     main (solo existe en la BD). Este fichero pasa a ser su copia de
--     referencia corregida hasta que se exporte al repo.
-- =====================================================================
