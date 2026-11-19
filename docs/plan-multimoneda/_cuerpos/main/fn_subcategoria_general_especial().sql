CREATE OR REPLACE FUNCTION public.fn_subcategoria_general_especial()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_denom constant text := 'General';
  v_sku   text;
begin
  -- Solo al pasar a especial. En un UPDATE que ya era especial no se repite.
  if not new.especial or new.id_categoria is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.especial, false) then
    return new;
  end if;

  -- Ya tiene una «General» (visible o no): no se toca.
  if exists (
    select 1 from public.app_dat_subcategorias s
    where s.idcategoria = new.id_categoria
      and lower(trim(s.denominacion)) = lower(v_denom)
  ) then
    return new;
  end if;

  -- `sku_codigo` es NOT NULL: se deriva del sku de la categoría.
  select upper(coalesce(nullif(trim(sku_codigo), ''), 'CAT' || id)) || '-GEN'
  into v_sku
  from public.app_dat_categoria
  where id = new.id_categoria;

  v_sku := coalesce(nullif(trim(v_sku), ''), 'CAT' || new.id_categoria || '-GEN');

  -- No hay índice único, pero repetir sku sería feo: se desambigua.
  if exists (select 1 from public.app_dat_subcategorias where sku_codigo = v_sku) then
    v_sku := v_sku || '-' || new.id_categoria;
  end if;

  insert into public.app_dat_subcategorias (idcategoria, denominacion, sku_codigo, oculta)
  values (new.id_categoria, v_denom, v_sku, true);

  return new;
end $function$

