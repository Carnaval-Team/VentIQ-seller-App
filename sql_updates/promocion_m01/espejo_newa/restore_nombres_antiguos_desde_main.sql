-- =====================================================================
-- ESPEJO NEWA: nombres antiguos <- cuerpo de MAIN (14 funciones)
-- Fuente: pg_get_functiondef(oid) en main (solo lectura), 2026-11-23.
-- Destino: SOLO newa. NO se toca ninguna *_m01 ni los helpers
-- (fn_turno_alinear_*, fn_caja_disponible_*, fn_config_tienda_puede_leer).
--
-- Cada bloque DO reproduce la definicion exacta de main. Los cuerpos de main
-- usan fin de linea CRLF (salvo fn_cambiar_estado_comanda_item_offline, que
-- usa LF); el literal $q$ se escribe con LF y el bloque convierte el cuerpo
-- (lo que sigue a "AS $function$") a CRLF para que md5(prosrc) coincida.
-- CREATE OR REPLACE conserva los GRANT vigentes en newa (hardening: sin
-- PUBLIC/anon); no se concede nada nuevo.
-- Baseline: baseline_main_md5.txt
-- =====================================================================

-- 1/14 fn_apertura_turno_offline (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_turno_abierto bigint;
    v_new_id bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';

    IF v_existing IS NOT NULL THEN
        -- Solo reutilizar si el turno sigue abierto; si ya cerró, crear uno nuevo.
        IF EXISTS (
            SELECT 1 FROM app_dat_caja_turno
            WHERE id = v_existing AND estado = 1
        ) THEN
            RETURN jsonb_build_object(
                'status', 'success', 'id_turno', v_existing, 'idempotent', true
            );
        END IF;

        DELETE FROM public.app_dat_operacion_offline_idempotencia
        WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_turno_abierto, 'idempotent', true,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_new_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_new_id, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        -- Forzar la hora real de apertura del dispositivo.
        IF p_fecha_apertura IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_apertura = p_fecha_apertura
            WHERE id = v_new_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 2/14 fn_apertura_turno_offline_usd (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_usd(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_inicial_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result JSONB;
  v_turno_id BIGINT;
BEGIN
  v_result := public.fn_apertura_turno_offline(
    p_client_uuid, p_efectivo_inicial, p_id_tpv, p_id_vendedor, p_usuario,
    p_maneja_inventario, p_productos, p_observaciones, p_fecha_apertura
  );
  v_turno_id := NULLIF(v_result->>'id_turno', '')::BIGINT;
  IF v_turno_id IS NOT NULL THEN
    UPDATE public.app_dat_caja_turno
    SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
    WHERE id = v_turno_id;
  END IF;
  RETURN v_result;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 3/14 fn_apertura_turno_offline_monedas (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_monedas(p_client_uuid uuid, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean, p_productos jsonb, p_efectivo_inicial_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res      jsonb;
  v_turno_id bigint;
  v_cup      numeric;
  v_usd      numeric;
begin
  if p_efectivo_inicial_por_moneda is null
     or jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);

  v_res := public.fn_apertura_turno_offline_usd(
    p_client_uuid        := p_client_uuid,
    p_efectivo_inicial   := v_cup,
    p_id_tpv             := p_id_tpv,
    p_id_vendedor        := p_id_vendedor,
    p_usuario            := p_usuario,
    p_maneja_inventario  := p_maneja_inventario,
    p_productos          := p_productos,
    p_observaciones      := p_observaciones,
    p_fecha_apertura     := p_fecha_apertura,
    p_efectivo_inicial_usd := v_usd);

  -- La variante vigente SÍ devuelve `id_turno` (a diferencia del camino online,
  -- que devuelve el id de la operación).
  if (v_res->>'status') = 'success' then
    v_turno_id := nullif(v_res->>'id_turno', '')::bigint;
    if v_turno_id is not null then
      insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
      select v_turno_id, upper(trim(e.key)),
             public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
      from jsonb_each(p_efectivo_inicial_por_moneda) e
      where public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) is not null
        and exists (select 1 from public.monedas m where m.codigo = upper(trim(e.key)))
      on conflict (id_turno, moneda) do update
        set efectivo_inicial = excluded.efectivo_inicial,
            updated_at       = now();
    end if;
  end if;

  return v_res;
end $function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 4/14 fn_cerrar_turno_offline (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
    v_turno_abierto bigint;
BEGIN
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'cierre_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'cierre_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        IF p_fecha_cierre IS NOT NULL THEN
            UPDATE app_dat_caja_turno
            SET fecha_cierre = p_fecha_cierre
            WHERE id = v_turno_abierto;
        END IF;

        RETURN jsonb_build_object('status', 'success', 'idempotent', false);
    END IF;

    RETURN jsonb_build_object(
        'status', 'error', 'message', 'El servidor rechazó el cierre del turno'
    );
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 5/14 fn_cerrar_turno_offline_usd (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_real_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result JSONB;
  v_turno_id BIGINT;
  v_efectivo_esperado_usd NUMERIC := 0;
BEGIN
  SELECT id INTO v_turno_id
  FROM public.app_dat_caja_turno
  WHERE id_tpv = p_id_tpv AND estado = 1
  ORDER BY fecha_apertura DESC NULLS LAST
  LIMIT 1;

  SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
  FROM public.app_dat_pago_venta pv
  JOIN public.app_dat_operacion_venta ov
    ON ov.id_operacion = pv.id_operacion_venta
  JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
  WHERE pv.moneda = 'USD'
    AND mp.es_efectivo = TRUE
    AND ov.id_turno_apertura = v_turno_id;

  v_result := public.fn_cerrar_turno_offline(
    p_client_uuid, p_id_tpv, p_efectivo_real, p_usuario,
    p_productos, p_observaciones, p_fecha_cierre
  );

  IF v_turno_id IS NOT NULL AND (v_result->>'status') = 'success' THEN
    UPDATE public.app_dat_caja_turno
    SET efectivo_real_usd = p_efectivo_real_usd,
        diferencia_usd = CASE
          WHEN p_efectivo_real_usd IS NULL THEN NULL
          ELSE p_efectivo_real_usd -
            (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
        END
    WHERE id = v_turno_id;
  END IF;

  RETURN v_result;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 6/14 fn_cerrar_turno_offline_monedas (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_monedas(p_client_uuid uuid, p_id_tpv bigint, p_usuario uuid, p_productos jsonb, p_efectivo_real_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res      jsonb;
  v_turno_id bigint;
  v_cup      numeric;
  v_usd      numeric;
  v_esperado record;
begin
  if p_efectivo_real_por_moneda is null
     or jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);

  -- Resolver ANTES de cerrar: el resultado de la RPC vigente no trae el turno.
  select ct.id into v_turno_id
  from public.app_dat_caja_turno ct
  where ct.id_tpv = p_id_tpv and ct.estado = 1 and ct.creado_por = p_usuario
  order by ct.fecha_apertura desc
  limit 1;

  v_res := public.fn_cerrar_turno_offline_usd(
    p_client_uuid        := p_client_uuid,
    p_id_tpv             := p_id_tpv,
    p_efectivo_real      := v_cup,
    p_usuario            := p_usuario,
    p_productos          := p_productos,
    p_observaciones      := p_observaciones,
    p_fecha_cierre       := p_fecha_cierre,
    p_efectivo_real_usd  := v_usd);

  if (v_res->>'status') = 'success' and v_turno_id is not null then
    for v_esperado in
      select moneda, esperado from public.fn_esperado_turno_por_moneda(v_turno_id)
    loop
      insert into public.app_dat_caja_turno_moneda
        (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
      values (v_turno_id, v_esperado.moneda,
              coalesce((select m.efectivo_inicial
                        from public.app_dat_caja_turno_moneda m
                        where m.id_turno = v_turno_id
                          and m.moneda = v_esperado.moneda), 0),
              v_esperado.esperado,
              public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda))
      on conflict (id_turno, moneda) do update
        set efectivo_esperado = excluded.efectivo_esperado,
            efectivo_real     = coalesce(excluded.efectivo_real,
                                         public.app_dat_caja_turno_moneda.efectivo_real),
            updated_at        = now();
    end loop;
  end if;

  return v_res;
end $function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 7/14 fn_cambiar_estado_comanda_item_offline (LF, sin conversion)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item_offline(p_client_uuid uuid, p_id_item bigint, p_nuevo_estado smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_existing bigint;
    v_res      jsonb;
BEGIN
    IF p_client_uuid IS NULL THEN
        RETURN jsonb_build_object('status','error','message','Falta el client_uuid','error_code','CLIENT_UUID_REQUERIDO');
    END IF;

    SELECT id_operacion INTO v_existing
      FROM app_dat_operacion_offline_idempotencia
     WHERE client_uuid = p_client_uuid AND tipo = 'estado_comanda_item';

    IF v_existing IS NOT NULL THEN
        RETURN (
            SELECT jsonb_build_object('status','success','idempotent',true,
                     'id_item',ci.id,'plato',ci.denominacion,'estado',ci.estado,
                     'id_comanda',ci.id_comanda,'message','Este cambio ya se habia aplicado')
              FROM app_dat_comanda_item ci WHERE ci.id = v_existing
        );
    END IF;

    v_res := fn_cambiar_estado_comanda_item(p_id_item, p_nuevo_estado);

    IF (v_res->>'status') = 'success' THEN
        INSERT INTO app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_item, 'estado_comanda_item', auth.uid())
        ON CONFLICT (client_uuid) DO NOTHING;

        v_res := v_res || jsonb_build_object('idempotent', false);
    END IF;

    RETURN v_res;
END;
$function$
$q$;
BEGIN
  EXECUTE d;
END
$do$;

-- 8/14 fn_registrar_cambio_estado_offline (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_offline(p_client_uuid uuid, p_id_operacion bigint, p_nuevo_estado smallint, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
BEGIN
    -- 1) ¿Ya se aplicó este cambio de estado? -> idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'message', 'Cambio de estado ya aplicado (idempotente)'
        );
    END IF;

    -- 2) Aplicar el cambio de estado usando la función existente.
    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion := p_id_operacion,
        p_nuevo_estado := p_nuevo_estado,
        p_uuid_usuario := p_uuid_usuario
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, p_id_operacion, 'estado:' || p_nuevo_estado, p_uuid_usuario)
    ON CONFLICT (client_uuid) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 9/14 fn_registrar_egreso_offline (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_result jsonb;
    v_new_id bigint;
BEGIN
    -- 1) ¿Ya se procesó este egreso offline? -> devolver idempotente.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'egreso_id', v_existing,
            'idempotent', true,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar usando la función existente.
    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );

    -- 3) Si fue exitoso, persistir el mapeo de idempotencia.
    IF v_result IS NOT NULL AND (v_result->>'success') = 'true' THEN
        v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
        IF v_new_id IS NOT NULL THEN
            INSERT INTO public.app_dat_operacion_offline_idempotencia
                (client_uuid, id_operacion, tipo, uuid_usuario)
            VALUES (p_client_uuid, v_new_id, 'egreso', p_uuid_usuario)
            ON CONFLICT (client_uuid) DO NOTHING;
        END IF;

        v_result := v_result || jsonb_build_object(
            'idempotent', false,
            'client_uuid', p_client_uuid
        );
    END IF;

    RETURN v_result;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 10/14 fn_registrar_egreso_offline_v2 (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid, p_moneda text DEFAULT 'CUP'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res    jsonb;
  v_id     bigint;
  v_moneda text;
begin
  v_moneda := upper(trim(coalesce(nullif(p_moneda, ''), 'CUP')));

  if not exists (select 1 from public.monedas m where m.codigo = v_moneda and m.activo) then
    raise exception 'La moneda % no existe o no está activa en el catálogo', v_moneda;
  end if;

  -- Toda la lógica (idempotencia por client_uuid, validaciones, alta) la sigue
  -- haciendo la vigente: aquí no se duplica nada.
  v_res := public.fn_registrar_egreso_offline(
             p_client_uuid, p_id_turno, p_monto_entrega,
             p_nombre_recibe, p_nombre_autoriza, p_motivo_entrega,
             p_id_medio_pago, p_uuid_usuario);

  -- En un replay idempotente `egreso_id` es el de la fila ya existente y la
  -- divisa es la misma, así que este UPDATE es inocuo.
  if coalesce((v_res->>'success')::boolean, false) then
    v_id := nullif(v_res->>'egreso_id', '')::bigint;
    if v_id is not null then
      update public.app_dat_entregas_parciales_caja
      set moneda = v_moneda
      where id = v_id;
    end if;
  end if;

  return v_res;
end $function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 11/14 fn_registrar_pago_venta_offline (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_offline(p_client_uuid uuid, p_id_operacion_venta bigint, p_pagos jsonb, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
BEGIN
    -- 1) ¿Ya se registraron estos pagos? -> idempotente, no duplicar.
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'id_operacion', v_existing,
            'message', 'Pagos ya registrados previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar pagos usando la función existente.
    v_ok := public.fn_registrar_pago_venta(
        p_id_operacion_venta := p_id_operacion_venta,
        p_pagos := p_pagos
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_operacion_venta, 'pago', p_uuid_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'success', true, 'idempotent', false,
            'id_operacion', p_id_operacion_venta
        );
    END IF;

    RETURN jsonb_build_object(
        'success', false, 'message', 'El servidor rechazó el registro de pagos'
    );
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 12/14 fn_registrar_venta_offline_v4 (CRLF)
-- Nota: los literales con "Ã³" / "Ã­" son mojibake que ya existe en main; se
-- conservan tal cual (el espejo copia main, no lo corrige).
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(p_client_uuid uuid, p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text DEFAULT NULL::text, p_denominacion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_estado_inicial smallint DEFAULT 1, p_id_cliente bigint DEFAULT NULL::bigint, p_fecha_creacion timestamp with time zone DEFAULT NULL::timestamp with time zone, p_pagos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_existing_op bigint; v_result jsonb; v_op bigint; v_ok boolean;
  v_id_tienda bigint;
BEGIN
  SELECT t.id_tienda INTO v_id_tienda FROM public.app_dat_tpv t WHERE t.id = p_id_tpv;
  IF v_id_tienda IS NULL THEN
    RETURN jsonb_build_object('status','error','error_code','TPV_NOT_FOUND','message','El TPV no existe');
  END IF;
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

  SELECT i.id_operacion INTO v_existing_op
  FROM public.app_dat_operacion_offline_idempotencia i
  WHERE i.client_uuid = p_client_uuid;
  IF v_existing_op IS NOT NULL THEN
    v_op := v_existing_op;
    v_result := jsonb_build_object('status','success','id_operacion',v_op,'idempotent',true,
                                   'message','OperaciÃ³n ya registrada previamente (idempotente)');
  ELSE
    v_result := public.fn_registrar_venta_v3(p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
                                             p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
    IF v_result IS NULL OR v_result->>'status' IS DISTINCT FROM 'success' THEN RETURN v_result; END IF;
    v_op := NULLIF(v_result->>'id_operacion','')::bigint;
    IF v_op IS NULL THEN RAISE EXCEPTION 'fn_registrar_venta_v3 no devolviÃ³ id_operacion'; END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia(client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_op, 'venta_v4', p_uuid) ON CONFLICT(client_uuid) DO NOTHING;
    IF p_fecha_creacion IS NOT NULL THEN
      UPDATE public.app_dat_operaciones SET created_at = p_fecha_creacion WHERE id = v_op;
      UPDATE public.app_dat_operacion_venta SET created_at = p_fecha_creacion WHERE id_operacion = v_op;
    END IF;
    v_result := v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
  END IF;

  -- Pagos: fn_registrar_pago_venta_v2 es idempotente (reescribe los no liquidados),
  -- asÃ­ que se reparan tambiÃ©n los desgloses parciales de intentos anteriores.
  IF p_pagos IS NOT NULL AND jsonb_typeof(p_pagos) = 'array' AND jsonb_array_length(p_pagos) > 0 THEN
    v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
    IF NOT COALESCE(v_ok, false) THEN
      RAISE EXCEPTION 'No se pudieron registrar los pagos de la operaciÃ³n %', v_op;
    END IF;
    v_result := v_result || jsonb_build_object('pagos_registrados', true);
  END IF;

  RETURN v_result;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 13/14 fn_listar_ordenes (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_listar_ordenes(id_tienda_param bigint DEFAULT NULL::bigint, id_tpv_param bigint DEFAULT NULL::bigint, id_usuario_param uuid DEFAULT NULL::uuid, id_estado_param smallint DEFAULT NULL::smallint, fecha_desde_param date DEFAULT NULL::date, fecha_hasta_param date DEFAULT NULL::date, id_tipo_operacion_param bigint DEFAULT NULL::bigint, con_inventario_param boolean DEFAULT false, solo_pendientes_param boolean DEFAULT false, limite_param integer DEFAULT 0, pagina_param integer DEFAULT 1)
 RETURNS TABLE(id_operacion bigint, tipo_operacion character varying, id_tienda bigint, tienda_nombre character varying, id_tpv bigint, tpv_nombre character varying, usuario_nombre text, estado smallint, estado_nombre text, fecha_operacion timestamp with time zone, total_operacion numeric, cantidad_items integer, observaciones text, detalles jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_fecha_inicio          TIMESTAMPTZ;
    v_fecha_fin             TIMESTAMPTZ;
    v_tiene_turno_abierto   BOOLEAN := FALSE;
    v_id_turno_abierto      BIGINT;
    v_uuid_usuario          UUID := NULL;
BEGIN
    -- Obtener el usuario autenticado si no se pasa
    v_uuid_usuario := COALESCE(id_usuario_param, auth.uid());

    -- Verificar que el usuario tenga permisos en al menos una tienda
    PERFORM check_user_has_access_to_any_tienda();

    -- Si NO se pasan fechas, usar el turno abierto del vendedor en el TPV
    IF fecha_desde_param IS NULL AND fecha_hasta_param IS NULL
       AND id_tpv_param IS NOT NULL AND v_uuid_usuario IS NOT NULL
    THEN
        SELECT ct.id, ct.fecha_apertura
          INTO v_id_turno_abierto, v_fecha_inicio
          FROM app_dat_caja_turno ct
          JOIN app_dat_vendedor vend ON ct.id_vendedor = vend.id
         WHERE ct.id_tpv = id_tpv_param
           AND vend.uuid = v_uuid_usuario
           AND ct.estado = 1
         ORDER BY ct.fecha_apertura DESC
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN;
        END IF;

        v_fecha_fin := NOW();
        v_tiene_turno_abierto := TRUE;
    ELSE
        v_fecha_inicio := fecha_desde_param;
        v_fecha_fin    := COALESCE(fecha_hasta_param, CURRENT_DATE)
                          + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    RETURN QUERY
    WITH operaciones_filtradas AS (
        SELECT
            o.id,
            o.created_at,
            o.id_tipo_operacion,
            top.denominacion                    AS tipo_operacion_nombre,
            o.id_tienda,
            t.denominacion                      AS tienda_nombre,
            o.uuid,
            COALESCE(u.email, 'Sistema')        AS usuario_email,
            e.estado,
            desc_vendedor.descuento             AS descuento,
            COALESCE(es.denominacion::text, 'Desconocido')
                                                AS estado_nombre,
            o.observaciones::TEXT,
            -- Datos específicos de TPV
            CASE
                WHEN o.id_tipo_operacion = (
                    SELECT id FROM app_nom_tipo_operacion
                     WHERE LOWER(denominacion) = 'venta' LIMIT 1
                ) THEN (
                    SELECT jsonb_build_object(
                        'id_tpv',            ov.id_tpv,
                        'tpv_nombre',        tp.denominacion,
                        'codigo_promocion',  ov.codigo_promocion,
                        'id_cliente',        ov.id_cliente,
                        'id_cliente_cxc',    ov.id_cliente_cxc,
                        'cliente_nombre',    COALESCE(cli_cxc.nombre_completo, cli.nombre_completo),
                        'cliente_telefono',  COALESCE(cli_cxc.telefono, cli.telefono)
                    )
                      FROM app_dat_operacion_venta ov
                      JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
                      LEFT JOIN app_dat_clientes cli ON ov.id_cliente = cli.id
                      LEFT JOIN app_dat_cliente_cxc cli_cxc ON ov.id_cliente_cxc = cli_cxc.id
                     WHERE ov.id_operacion = o.id
                     LIMIT 1
                )
                ELSE NULL
            END                                 AS datos_especificos,
            (SELECT COUNT(*)::INTEGER
               FROM app_dat_extraccion_productos ep
              WHERE ep.id_operacion = o.id)     AS cantidad_items,
            (SELECT COALESCE(SUM(ep.importe), 0)
               FROM app_dat_extraccion_productos ep
              WHERE ep.id_operacion = o.id)     AS total_operacion
        FROM app_dat_operaciones o
        JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda t           ON o.id_tienda = t.id
        LEFT JOIN auth.users u          ON o.uuid = u.id
        LEFT JOIN LATERAL (
            SELECT jsonb_build_object(
                'id',               d.id,
                'id_vendedor',      d.id_vendedor,
                'uuid_usuario',     d.uuid_usuario,
                'monto_real',       d.monto_real,
                'monto_descontado', d.monto_descontado,
                'tipo_descuento',   d.tipo_descuento,
                'valor_descuento',  d.valor_descuento,
                'created_at',       d.created_at
            ) AS descuento
              FROM app_dat_descuentos_vendedor d
             WHERE d.id_operacion = o.id
             ORDER BY d.created_at DESC
             LIMIT 1
        ) desc_vendedor ON TRUE
        LEFT JOIN app_dat_estado_operacion e
               ON e.id_operacion = o.id
              AND e.id = (
                  SELECT MAX(id) FROM app_dat_estado_operacion er
                   WHERE er.id_operacion = o.id
              )
        LEFT JOIN app_nom_estado_operacion es ON e.estado = es.id
        WHERE
            (id_tienda_param IS NULL OR o.id_tienda = id_tienda_param)
            AND (id_tpv_param IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov
                 WHERE ov.id_operacion = o.id AND ov.id_tpv = id_tpv_param
            ))
            AND (v_uuid_usuario IS NULL OR o.uuid = v_uuid_usuario)
            AND (id_estado_param IS NULL OR e.estado = id_estado_param)
            AND (v_fecha_inicio IS NULL OR o.created_at >= v_fecha_inicio)
            AND (v_fecha_fin    IS NULL OR o.created_at <= v_fecha_fin)
            AND (id_tipo_operacion_param IS NULL OR o.id_tipo_operacion = id_tipo_operacion_param)
            AND EXISTS (
                SELECT 1 FROM (
                    SELECT gr.id_tienda  FROM app_dat_gerente gr    WHERE gr.uuid = auth.uid()
                    UNION
                    SELECT sup.id_tienda FROM app_dat_supervisor sup WHERE sup.uuid = auth.uid()
                    UNION
                    SELECT aud.id_tienda FROM auditor aud           WHERE aud.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda
                      FROM app_dat_almacenero al
                      JOIN app_dat_almacen a ON al.id_almacen = a.id
                     WHERE al.uuid = auth.uid()
                    UNION
                    SELECT tpv.id_tienda
                      FROM app_dat_vendedor vend2
                      JOIN app_dat_tpv tpv ON vend2.id_tpv = tpv.id
                     WHERE vend2.uuid = auth.uid()
                ) AS tiendas_usuario
                WHERE tiendas_usuario.id_tienda = o.id_tienda
            )
        ORDER BY o.created_at DESC
        LIMIT  CASE WHEN limite_param = 0 THEN NULL ELSE limite_param END
        OFFSET CASE WHEN limite_param = 0 THEN 0 ELSE (pagina_param - 1) * limite_param END
    )
    SELECT
        of.id                                                   AS id_operacion,
        of.tipo_operacion_nombre                                AS tipo_operacion,
        of.id_tienda,
        of.tienda_nombre,
        (of.datos_especificos->>'id_tpv')::BIGINT               AS id_tpv,
        (of.datos_especificos->>'tpv_nombre')::VARCHAR          AS tpv_nombre,
        COALESCE(
            (SELECT nombres || ' ' || apellidos
               FROM app_dat_trabajadores
              WHERE uuid = of.uuid
              LIMIT 1),
            of.usuario_email
        )                                                       AS usuario_nombre,
        of.estado,
        of.estado_nombre,
        of.created_at                                           AS fecha_operacion,
        of.total_operacion,
        of.cantidad_items::INTEGER,
        of.observaciones::TEXT,
        jsonb_build_object(
            'detalles_especificos', of.datos_especificos,
            'cliente', jsonb_build_object(
                'id_cliente',       of.datos_especificos->>'id_cliente',
                'nombre_completo',  of.datos_especificos->>'cliente_nombre',
                'telefono',         of.datos_especificos->>'cliente_telefono'
            ),
            'items', (
                SELECT jsonb_agg(jsonb_build_object(
                    'id_extraccion',    ep.id,
                    'id_producto',      ep.id_producto,
                    'producto_nombre',  p.denominacion,
                    'sku_producto',     p.sku,
                    'descripcion',      p.descripcion,
                    'cantidad',         ep.cantidad,
                    'precio_unitario',  ep.precio_unitario,
                    'importe',          ep.importe,
                    'presentacion',     np.denominacion,
                    'id_ubicacion',     ep.id_ubicacion,
                    'nombre_ubicacion',  ubi.denominacion,
                    'sku_ubicacion',     ep.sku_ubicacion,
                    'cantidad_inicial', ip.cantidad_inicial,
                    'cantidad_final',   ip.cantidad_final,
                    'es_elaborado',     p.es_elaborado,
                    'entradas_producto', (
                        SELECT COALESCE(SUM(ip2.cantidad_final - ip2.cantidad_inicial), 0)
                          FROM app_dat_inventario_productos ip2
                         WHERE ip2.id_producto = ep.id_producto
                           AND ip2.id_recepcion IS NOT NULL
                           AND ip2.created_at >= v_fecha_inicio
                           AND ip2.created_at <= v_fecha_fin
                    ),
                    'variante', CASE
                        WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                            'id',       ep.id_variante,
                            'atributo', atr.denominacion,
                            'opcion',   ao.valor
                        )
                        ELSE NULL
                    END
                ))
                FROM app_dat_extraccion_productos ep
                JOIN app_dat_producto p              ON ep.id_producto = p.id
                LEFT JOIN app_dat_inventario_productos ip ON ep.id = ip.id_extraccion
                LEFT JOIN app_dat_layout_almacen ubi   ON ep.id_ubicacion = ubi.id
                LEFT JOIN app_dat_variantes var         ON ep.id_variante = var.id
                LEFT JOIN app_dat_atributos atr         ON var.id_atributo = atr.id
                LEFT JOIN app_dat_atributo_opcion ao    ON ep.id_opcion_variante = ao.id
                LEFT JOIN app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
                LEFT JOIN app_nom_presentacion np        ON pp.id_presentacion = np.id
                WHERE ep.id_operacion = of.id
            ),
            'pagos', (
                SELECT jsonb_agg(jsonb_build_object(
                    'medio_pago',           mp.denominacion,
                    'total',                pv.monto,
                    'total_sin_descuento',  pv.importe_sin_descuento,
                    'referencia_pago',      pv.referencia_pago,
                    'fecha_pago',           pv.fecha_pago,
                    'es_digital',           mp.es_digital,
                    'es_efectivo',          mp.es_efectivo,
                    'tipo_pago',            pv.tipo_pago
                ))
                FROM app_dat_operacion_venta ov
                JOIN app_dat_pago_venta pv      ON ov.id_operacion = pv.id_operacion_venta
                JOIN app_nom_medio_pago mp       ON pv.id_medio_pago = mp.id
                WHERE ov.id_operacion = of.id
                  AND mp.es_activo = TRUE
            ),
            'descuento', of.descuento,
            'paqueteria', (
                SELECT jsonb_build_object(
                    'numero_paquete', paq.numero_paquete,
                    'descripcion',    paq.descripcion,
                    'paqueteria',     ord.paqueteria,
                    'order_id',       ord.id
                )
                FROM public.paqueteria_ordenes paq
                JOIN carnavalapp."Orders" ord ON ord.id = paq.id_orden_carnaval
                WHERE paq.id_operacion = of.id
                LIMIT 1
            )
        ) AS detalles
    FROM operaciones_filtradas of;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;

-- 14/14 fn_actualizar_precio_promedio_recepcion_v2 (CRLF)
DO $do$
DECLARE
  d text := $q$CREATE OR REPLACE FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(p_id_operacion bigint, p_productos jsonb)
 RETURNS TABLE(success boolean, mensaje text, productos_actualizados integer, tiempo_ms integer)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inicio        timestamptz := clock_timestamp();
    v_actualizados  int := 0;
    v_tiempo        int;
    v_es_devolucion boolean;
    v_fila          record;
    v_id_base       bigint;
    v_saldo_base    numeric;
    v_costo_ant     numeric;
    v_costo_nuevo   numeric;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM app_dat_consignacion_envio
         WHERE id_operacion_recepcion = p_id_operacion
           AND tipo_envio = 2
    ) INTO v_es_devolucion;

    IF v_es_devolucion THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'Operacion de devolucion - precio promedio no actualizado'::text, 0, v_tiempo;
        RETURN;
    END IF;

    IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'La operacion es una transferencia, devolucion u operacion interna; no modifica el costo promedio'::text,
            0, v_tiempo;
        RETURN;
    END IF;

    IF p_productos IS NULL
       OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE, 'No hay productos para procesar'::text, 0, v_tiempo;
        RETURN;
    END IF;

    FOR v_fila IN
        SELECT (e->>'id_presentacion')::bigint AS id_pp
          FROM jsonb_array_elements(p_productos) e
         WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
    LOOP
        IF NOT EXISTS (SELECT 1 FROM app_dat_producto_presentacion pp
                        WHERE pp.id = v_fila.id_pp) THEN
            v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
            RETURN QUERY SELECT FALSE,
                format('La presentacion %s no existe', v_fila.id_pp)::text, 0, v_tiempo;
            RETURN;
        END IF;
    END LOOP;

    FOR v_fila IN
        WITH entrada AS (
            SELECT (e->>'id_presentacion')::bigint AS id_pp,
                   (e->>'precio_unitario')::numeric AS precio_unitario,
                   (e->>'cantidad')::numeric        AS cantidad
              FROM jsonb_array_elements(p_productos) e
             WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
               AND NULLIF(e->>'precio_unitario','') IS NOT NULL
               AND NULLIF(e->>'cantidad','')        IS NOT NULL
               AND (e->>'precio_unitario')::numeric > 0
               AND (e->>'cantidad')::numeric        > 0
        ),
        con_factor AS (
            SELECT pp.id_producto,
                   en.cantidad * COALESCE(f.factor_rel, 1)        AS cant_base,
                   en.precio_unitario / NULLIF(COALESCE(f.factor_rel, 1), 0) AS costo_base
              FROM entrada en
              JOIN app_dat_producto_presentacion pp ON pp.id = en.id_pp
              LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                     ON f.id_presentacion = pp.id
        )
        SELECT id_producto,
               SUM(cant_base)              AS cant_base,
               SUM(cant_base * costo_base) AS importe_base
          FROM con_factor
         WHERE cant_base > 0 AND costo_base IS NOT NULL
         GROUP BY id_producto
    LOOP
        SELECT c.id_presentacion INTO v_id_base
          FROM public.fn_presentaciones_producto(v_fila.id_producto) c
         WHERE c.es_base
         LIMIT 1;

        IF v_id_base IS NULL THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(pp.precio_promedio, 0) INTO v_costo_ant
          FROM app_dat_producto_presentacion pp
         WHERE pp.id = v_id_base
           FOR UPDATE;

        SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
          FROM public.fn_stock_saldos_presentacion(v_fila.id_producto, NULL, NULL, false) s;

        v_saldo_base := GREATEST(v_saldo_base - v_fila.cant_base, 0);

        IF v_costo_ant <= 0 OR v_saldo_base <= 0 THEN
            v_costo_nuevo := v_fila.importe_base / v_fila.cant_base;
        ELSE
            v_costo_nuevo := ((v_costo_ant * v_saldo_base) + v_fila.importe_base)
                             / (v_saldo_base + v_fila.cant_base);
        END IF;

        -- precio_promedio es `real` (float4): la guarda compara en la
        -- precision de destino para no meter filas falsas al historial.
        UPDATE app_dat_producto_presentacion
           SET precio_promedio = v_costo_nuevo
         WHERE id = v_id_base
           AND COALESCE(precio_promedio, -1) <> v_costo_nuevo::real;

        IF FOUND THEN
            v_actualizados := v_actualizados + 1;
        END IF;

        -- Propagación: costo_presentacion = costo_base_nuevo * factor_rel en
        -- TODAS las filas del producto (incluida la base, que la guarda filtra).
        -- La base es la fuente de verdad; las demás son caché desnormalizado
        -- para lectores que consultan precio_promedio por fila.
        UPDATE app_dat_producto_presentacion pp
           SET precio_promedio = v_costo_nuevo * f.factor_rel
          FROM public.fn_presentaciones_producto(v_fila.id_producto) f
         WHERE f.id_presentacion = pp.id
           AND pp.id_producto = v_fila.id_producto
           AND COALESCE(pp.precio_promedio, -1)
               <> (v_costo_nuevo * f.factor_rel)::real;
    END LOOP;

    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;

    RETURN QUERY SELECT TRUE,
        format('Se actualizaron %s costos promedio (ponderados en unidades base)', v_actualizados)::text,
        v_actualizados, v_tiempo;

EXCEPTION WHEN OTHERS THEN
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
    RETURN QUERY SELECT FALSE,
        format('Error en fn_actualizar_precio_promedio_recepcion_v2 [%s]: %s', SQLSTATE, SQLERRM)::text,
        0, v_tiempo;
END;
$function$
$q$;
  k text := 'AS $function$';
  i int;
BEGIN
  i := position(k in d) + length(k) - 1;
  d := left(d, i) || replace(substr(d, i + 1), E'\n', E'\r\n');
  EXECUTE d;
END
$do$;
