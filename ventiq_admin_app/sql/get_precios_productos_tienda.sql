-- ============================================================================
-- RPC: public.get_precios_productos_tienda
-- Descripción: Devuelve todos los productos de una tienda con:
--   - Datos básicos (denominación, sku, imagen, proveedor)
--   - Último precio de venta (CUP/USD)
--   - Presentaciones con precio_promedio y stock actual
--   - Para elaborados/servicios: desglose de costo por ingrediente
--     (misma lógica que el detalle del producto: descomposición recursiva,
--      costo desde precio_promedio de la presentación base del ingrediente,
--      conversión de unidades vía presentacion_unidad_medida y conversiones)
-- Reemplaza las múltiples consultas de precios_productos_screen.dart
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: costo por ingredientes de un producto elaborado/servicio
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_costo_ingredientes_producto(p_id_producto bigint)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
  v_desglose jsonb;
  v_total    numeric := 0;
begin
  with recursive receta as (
    -- Nivel 1: ingredientes directos de la receta
    select i.id_ingrediente,
           i.cantidad_necesaria::numeric                       as cantidad,
           coalesce(nullif(trim(i.unidad_medida), ''), 'und')  as unidad_medida
    from public.app_dat_producto_ingredientes i
    where i.id_producto_elaborado = p_id_producto
    union all
    -- Descomposición recursiva de sub-elaborados
    select i2.id_ingrediente,
           r.cantidad * i2.cantidad_necesaria::numeric,
           coalesce(nullif(trim(i2.unidad_medida), ''), 'und')
    from receta r
    join public.app_dat_producto_ingredientes i2
      on i2.id_producto_elaborado = r.id_ingrediente
  ),
  hojas as (
    -- Solo ingredientes finales (que no se descomponen más)
    select r.id_ingrediente,
           sum(r.cantidad)      as cantidad,
           min(r.unidad_medida) as unidad_medida
    from receta r
    where not exists (
      select 1 from public.app_dat_producto_ingredientes x
      where x.id_producto_elaborado = r.id_ingrediente
    )
    group by r.id_ingrediente
  ),
  calc as (
    select h.id_ingrediente,
           prod.denominacion,
           prod.sku,
           h.cantidad,
           h.unidad_medida,
           -- Costo de la presentación (misma lógica que detalle del producto:
           -- precio_promedio > 0, prioridad presentación base)
           coalesce(cp.precio_promedio, 0)::numeric          as costo_presentacion,
           coalesce(pum.cantidad_um, 1)::numeric             as cantidad_por_presentacion,
           pum.id_unidad_medida                              as id_um_producto,
           um_src.id                                         as id_um_receta,
           um_src.factor_base                                as factor_base_src,
           um_dst.factor_base                                as factor_base_dst,
           coalesce(um_dst.denominacion, h.unidad_medida)    as unidad_producto
    from hojas h
    join public.app_dat_producto prod on prod.id = h.id_ingrediente
    left join lateral (
      select pp.precio_promedio
      from public.app_dat_producto_presentacion pp
      where pp.id_producto = h.id_ingrediente
        and pp.precio_promedio > 0
      order by pp.es_base desc
      limit 1
    ) cp on true
    left join lateral (
      select pum0.cantidad_um, pum0.id_unidad_medida
      from public.app_dat_presentacion_unidad_medida pum0
      where pum0.id_producto = h.id_ingrediente
      limit 1
    ) pum on true
    left join lateral (
      select um0.id, um0.factor_base
      from public.app_nom_unidades_medida um0
      where lower(um0.denominacion) = lower(h.unidad_medida)
         or lower(um0.abreviatura)  = lower(h.unidad_medida)
      limit 1
    ) um_src on true
    left join public.app_nom_unidades_medida um_dst
      on um_dst.id = pum.id_unidad_medida
  ),
  conv as (
    select c.*,
           case
             when c.id_um_receta is null
               or c.id_um_producto is null
               or c.id_um_receta = c.id_um_producto then 1
             else coalesce(
               -- Conversión directa
               (select cu.factor_conversion
                from public.app_nom_conversiones_unidades cu
                where cu.id_unidad_origen  = c.id_um_receta
                  and cu.id_unidad_destino = c.id_um_producto
                limit 1),
               -- Conversión inversa
               (select 1 / nullif(cu.factor_conversion, 0)
                from public.app_nom_conversiones_unidades cu
                where cu.id_unidad_origen  = c.id_um_producto
                  and cu.id_unidad_destino = c.id_um_receta
                limit 1),
               -- Vía factor_base de ambas unidades
               case
                 when c.factor_base_src is not null
                  and c.factor_base_dst is not null
                  and c.factor_base_dst <> 0
                 then c.factor_base_src / c.factor_base_dst
               end,
               1
             )
           end as factor
    from calc c
  ),
  final as (
    select id_ingrediente,
           denominacion,
           sku,
           cantidad,
           unidad_medida,
           unidad_producto,
           cantidad * factor as cantidad_base,
           costo_presentacion,
           cantidad_por_presentacion,
           -- costo por unidad base = costo presentación / unidades por presentación
           case when cantidad_por_presentacion > 0
                then costo_presentacion / cantidad_por_presentacion
                else costo_presentacion
           end as costo_unitario,
           (cantidad * factor) *
           (case when cantidad_por_presentacion > 0
                 then costo_presentacion / cantidad_por_presentacion
                 else costo_presentacion
            end) as costo_total
    from conv
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id_producto',        id_ingrediente,
             'denominacion',       denominacion,
             'sku',                sku,
             'cantidad_requerida', round(cantidad, 4),
             'unidad_receta',      unidad_medida,
             'cantidad_en_unidad_base', round(cantidad_base, 4),
             'unidad_producto',    unidad_producto,
             'costo_unitario_promedio', round(costo_unitario, 6),
             'costo_total',        round(costo_total, 4),
             'sin_costo',          (costo_presentacion = 0)
           ) order by denominacion
         ), '[]'::jsonb),
         coalesce(sum(costo_total), 0)
  into v_desglose, v_total
  from final;

  return jsonb_build_object(
    'costo_total', round(v_total, 4),
    'desglose',    v_desglose
  );
end;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- RPC principal: listado de productos con precios, presentaciones, stock
-- y desglose de costo por ingrediente (elaborados/servicios)
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.get_precios_productos_tienda(p_id_tienda bigint)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
  v_result jsonb;
begin
  with productos as (
    select p.id,
           p.denominacion,
           p.sku,
           p.imagen,
           p.id_proveedor,
           coalesce(p.es_elaborado, false) as es_elaborado,
           coalesce(p.es_servicio, false)  as es_servicio,
           prov.denominacion               as proveedor
    from public.app_dat_producto p
    left join public.app_dat_proveedor prov on prov.id = p.id_proveedor
    where p.id_tienda = p_id_tienda
      and p.deleted_at is null
  ),
  precios as (
    -- Último precio de venta por producto (mayor id)
    select distinct on (pv.id_producto)
           pv.id_producto,
           pv.id,
           pv.precio_venta_cup,
           pv.precio_venta_usd
    from public.app_dat_precio_venta pv
    join productos pr on pr.id = pv.id_producto
    order by pv.id_producto, pv.id desc
  ),
  stock as (
    -- Último registro por (producto, presentación, ubicación), sumado por presentación
    select t.id_producto,
           t.id_presentacion,
           sum(t.cantidad_final) as stock_total
    from (
      select distinct on (ip.id_producto, ip.id_presentacion, ip.id_ubicacion)
             ip.id_producto,
             ip.id_presentacion,
             ip.cantidad_final
      from public.app_dat_inventario_productos ip
      join productos pr on pr.id = ip.id_producto
      order by ip.id_producto, ip.id_presentacion, ip.id_ubicacion,
               ip.created_at desc, ip.id desc
    ) t
    group by t.id_producto, t.id_presentacion
  ),
  presentaciones as (
    select pp.id_producto,
           jsonb_agg(
             jsonb_build_object(
               'id',              pp.id,
               'id_producto',     pp.id_producto,
               'cantidad',        pp.cantidad,
               'es_base',         pp.es_base,
               'precio_promedio', pp.precio_promedio,
               'stock_total',     coalesce(s.stock_total, 0),
               'app_nom_presentacion', jsonb_build_object(
                 'id',           np.id,
                 'denominacion', np.denominacion
               )
             ) order by pp.es_base desc, pp.id
           ) as pres
    from public.app_dat_producto_presentacion pp
    join public.app_nom_presentacion np on np.id = pp.id_presentacion
    join productos pr on pr.id = pp.id_producto
    left join stock s
      on s.id_producto = pp.id_producto
     and s.id_presentacion = pp.id
    group by pp.id_producto
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',               pr.id,
             'denominacion',     pr.denominacion,
             'sku',              coalesce(pr.sku, ''),
             'imagen',           pr.imagen,
             'id_proveedor',     pr.id_proveedor,
             'proveedor',        pr.proveedor,
             'es_elaborado',     pr.es_elaborado,
             'es_servicio',      pr.es_servicio,
             'precio_venta',     px.precio_venta_cup,
             'precio_venta_usd', px.precio_venta_usd,
             'precio_venta_id',  px.id,
             'presentaciones',   coalesce(pres.pres, '[]'::jsonb),
             'costo_ingredientes',
               case
                 when pr.es_elaborado or pr.es_servicio
                 then public.fn_costo_ingredientes_producto(pr.id)
                 else null
               end
           ) order by pr.denominacion
         ), '[]'::jsonb)
  into v_result
  from productos pr
  left join precios px on px.id_producto = pr.id
  left join presentaciones pres on pres.id_producto = pr.id;

  return v_result;
end;
$$;

-- Permisos
revoke all on function public.fn_costo_ingredientes_producto(bigint) from public;
grant execute on function public.fn_costo_ingredientes_producto(bigint) to authenticated;
revoke all on function public.get_precios_productos_tienda(bigint) from public;
grant execute on function public.get_precios_productos_tienda(bigint) to authenticated;
