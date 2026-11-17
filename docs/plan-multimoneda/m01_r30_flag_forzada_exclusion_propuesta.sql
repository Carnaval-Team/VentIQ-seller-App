BEGIN;

-- BORRADOR MC-056. NO EJECUTAR en main.
-- Exclusion mutua del interruptor: "moneda por producto" y "forzar moneda de
-- venta" no pueden convivir (una fija UNA divisa para toda la venta; la otra
-- la elige por linea). Dos cambios:
--   1. fn_m01_fijar_moneda_por_producto: al activar el flag apaga
--      forzar_moneda_venta y limpia moneda_venta_forzada en el mismo UPDATE
--      (sin esto quedarian ambas encendidas y la politica guardada diria
--      "por producto" mientras el checkout legacy fuerza una divisa).
--   2. fn_validar_moneda_forzada (trigger de configuracion): rechaza
--      forzar=true cuando permitir_moneda_por_producto=true, asi ningun
--      UPDATE directo ni cliente viejo puede reabrir la combinacion.
-- No toca mostrar_selector_moneda: la columna queda para compatibilidad con
-- clientes anteriores; el TPV nuevo ya no la consulta.

SET LOCAL app.m01_r30_forzada_exclusion_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r30_forzada_exclusion_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-056: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    -- fn_validar_moneda_forzada: solo reemplaza el cuerpo vigente (valida
    -- moneda forzada contra tienda_moneda) o una corrida previa (lleva el
    -- chequeo de exclusion). Cualquier otro cuerpo aborta.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_validar_moneda_forzada()')
          AND (position('no acepta la moneda' in prosrc) > 0)
          AND (position('permitir_moneda_por_producto' in prosrc) = 0
               OR position('permitir_moneda_por_producto' in prosrc) > 0)
    ) THEN
        RAISE EXCEPTION 'fn_validar_moneda_forzada difiere del cuerpo vigente en newa; revisar sin reemplazar avances';
    END IF;
    -- fn_m01_fijar_moneda_por_producto: idem, cuerpo vigente (guarda
    -- capacidad + GUC de flag) o una corrida previa (limpia la forzada).
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_m01_fijar_moneda_por_producto(bigint,boolean)')
          AND prosecdef AND proowner = 'postgres'::regrole
          AND position('fn_m01_registrar_venta_v1' in prosrc) > 0
          AND position('m01_politica_flag_autorizada' in prosrc) > 0
    ) THEN
        RAISE EXCEPTION 'fn_m01_fijar_moneda_por_producto difiere del cuerpo vigente en newa; revisar sin reemplazar avances';
    END IF;
END;
$preflight$;

-- (1) Encender el flag apaga la forzada en el mismo UPDATE.
CREATE OR REPLACE FUNCTION public.fn_m01_fijar_moneda_por_producto(p_id_tienda bigint, p_activar boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_activar IS NULL
       OR public.fn_config_tienda_puede_escribir(p_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_activar IS TRUE
       AND to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Activacion de moneda por producto no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM set_config('app.m01_politica_flag_autorizada', 'yes', true);
    UPDATE public.app_dat_configuracion_tienda
    SET permitir_moneda_por_producto = p_activar,
        -- Exclusion mutua: con la venta por linea encendida la forzada se
        -- apaga en la misma escritura. El trigger la pondria a NULL de
        -- todos modos; aqui queda explicito y auditable en el mismo UPDATE.
        forzar_moneda_venta = CASE WHEN p_activar THEN FALSE ELSE forzar_moneda_venta END,
        moneda_venta_forzada = CASE WHEN p_activar THEN NULL ELSE moneda_venta_forzada END
    WHERE id_tienda = p_id_tienda;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object(
        'success', true,
        'permitir_moneda_por_producto', p_activar,
        'forzar_moneda_venta_apagada', p_activar
    );
END;
$function$;

-- (2) El trigger rechaza forzar=true con el flag por producto encendido.
CREATE OR REPLACE FUNCTION public.fn_validar_moneda_forzada()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.forzar_moneda_venta then
    if new.permitir_moneda_por_producto then
      raise exception 'La moneda por producto es incompatible con forzar la moneda de venta';
    end if;
    if new.moneda_venta_forzada is null then
      raise exception 'Si se fuerza la moneda de venta hay que indicar cual';
    end if;
    if not exists (select 1 from public.app_dat_tienda_moneda m
                   where m.id_tienda = new.id_tienda
                     and m.moneda = new.moneda_venta_forzada and m.activo) then
      raise exception 'La tienda % no acepta la moneda %', new.id_tienda, new.moneda_venta_forzada;
    end if;
  else
    new.moneda_venta_forzada := null;
  end if;
  return new;
end
$function$;

COMMIT;
