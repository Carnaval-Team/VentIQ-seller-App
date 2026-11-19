CREATE OR REPLACE FUNCTION public.fn_fdi_repartir_ganancia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_tienda bigint;
    v_igual  boolean;
    v_total  numeric;
    v_n      integer;
    v_asignado numeric := 0;
    v_monto  numeric;
    v_pct    numeric;
    v_i record;
    v_ultimo bigint;
BEGIN
    SELECT id_tienda, repartir_igual INTO STRICT v_tienda, v_igual
    FROM public.fdi_dat_liquidacion WHERE id = NEW.id_liquidacion;
    IF NOT COALESCE(public.fn_user_is_dueno(v_tienda), false) THEN
        RAISE EXCEPTION 'Solo el dueño puede liquidar ganancias' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('fdi_inversores:' || v_tienda, 0));
    SELECT sum(porcentaje), max(id), count(*) INTO v_total, v_ultimo, v_n
    FROM public.fdi_dat_inversor WHERE id_tienda = v_tienda AND activo;
    IF v_n IS NULL OR v_n = 0 THEN
        RAISE EXCEPTION 'No hay inversores activos para repartir la ganancia';
    END IF;
    IF NOT v_igual AND v_total IS DISTINCT FROM 100::numeric THEN
        RAISE EXCEPTION 'La participación de los inversores activos debe sumar 100%%';
    END IF;
    IF NEW.monto_ganancia_retirada = 0 THEN RETURN NEW; END IF;
    IF NEW.monto_ganancia_retirada <> round(NEW.monto_ganancia_retirada, 2) THEN
        RAISE EXCEPTION 'La ganancia retirada debe tener como máximo dos decimales';
    END IF;
    FOR v_i IN SELECT * FROM public.fdi_dat_inversor WHERE id_tienda = v_tienda AND activo ORDER BY id LOOP
        v_pct := CASE WHEN v_igual THEN 100.0 / v_n ELSE v_i.porcentaje END;
        -- En reparto igual nadie absorbe el remanente: la diferencia con el
        -- 100% queda en el fondo. En reparto por % el último cierra la suma.
        v_monto := CASE WHEN NOT v_igual AND v_i.id = v_ultimo
                        THEN NEW.monto_ganancia_retirada - v_asignado
                        ELSE trunc(NEW.monto_ganancia_retirada * v_pct / 100, 2) END;
        INSERT INTO public.fdi_dat_inversor_reparto(id_tienda, id_inversor, id_detalle, nombre_snapshot, porcentaje_snapshot, moneda, monto)
        VALUES (v_tienda, v_i.id, NEW.id, v_i.nombre, v_pct, NEW.moneda, v_monto);
        v_asignado := v_asignado + v_monto;
    END LOOP;
    RETURN NEW;
END;
$function$

