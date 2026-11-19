CREATE OR REPLACE FUNCTION public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado bigint, p_cantidad_producto numeric DEFAULT 1)
 RETURNS TABLE(id_ingrediente bigint, cantidad_total_necesaria numeric, nivel_recursion integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
$function$

