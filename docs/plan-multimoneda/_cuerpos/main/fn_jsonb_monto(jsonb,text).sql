CREATE OR REPLACE FUNCTION public.fn_jsonb_monto(p jsonb, p_moneda text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare v numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  select case
           when jsonb_typeof(e.value) = 'number' then (e.value #>> '{}')::numeric
           when jsonb_typeof(e.value) = 'string'
                and trim(e.value #>> '{}') ~ '^-?[0-9]+([.][0-9]+)?$'
             then trim(e.value #>> '{}')::numeric
         end
  into v
  from jsonb_each(p) e
  where upper(trim(e.key)) = upper(trim(p_moneda))
  limit 1;
  return v;
end $function$

