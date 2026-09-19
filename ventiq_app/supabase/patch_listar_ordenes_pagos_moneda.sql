-- PARCHE: Incluir moneda/tasa/monto en pagos de listar_ordenes / fn_listar_ordenes
-- Ejecutar en Supabase SQL Editor (DDL). Sin esto el TPV trata ventas USD como CUP.

DO $patch$
DECLARE
  def text;
  def2 text;
BEGIN
  -- fn_listar_ordenes
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'fn_listar_ordenes'
  LIMIT 1;

  IF def IS NOT NULL THEN
    def2 := regexp_replace(
      def,
      E'''pagos'',\\s*\\(\\s*SELECT jsonb_agg\\(jsonb_build_object\\([\\s\\S]*?\\)\\)\\s*FROM app_dat_pago_venta pv\\s*JOIN app_nom_medio_pago mp ON pv\\.id_medio_pago = mp\\.id\\s*WHERE pv\\.id_operacion_venta = of\\.id\\s*AND mp\\.es_activo = TRUE\\s*\\)',
      $repl$'pagos', (
                SELECT jsonb_agg(jsonb_build_object(
                    'medio_pago',              mp.denominacion,
                    'id_medio_pago',           mp.id,
                    'monto',                   pv.monto,
                    'total',                   pv.monto,
                    'total_sin_descuento',     pv.importe_sin_descuento,
                    'referencia_pago',         pv.referencia_pago,
                    'fecha_pago',              pv.fecha_pago,
                    'es_digital',              mp.es_digital,
                    'es_efectivo',             mp.es_efectivo,
                    'tipo_pago',               pv.tipo_pago,
                    'moneda',                  COALESCE(NULLIF(upper(trim(pv.moneda)), ''), 'CUP'),
                    'tasa_usd',                pv.tasa_usd,
                    'monto_cup_equivalente',   pv.monto_cup_equivalente
                ))
                FROM app_dat_pago_venta pv
                JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
                WHERE pv.id_operacion_venta = of.id
                  AND mp.es_activo = TRUE
            )$repl$,
      'n'
    );
    IF def2 IS DISTINCT FROM def THEN
      EXECUTE def2;
      RAISE NOTICE 'fn_listar_ordenes patched';
    ELSE
      RAISE NOTICE 'fn_listar_ordenes: pagos block already patched or not matched';
    END IF;
  END IF;

  -- listar_ordenes (legacy)
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'listar_ordenes'
  LIMIT 1;

  IF def IS NOT NULL THEN
    def2 := regexp_replace(
      def,
      E'''pagos'',\\s*\\(\\s*SELECT jsonb_agg\\(jsonb_build_object\\([\\s\\S]*?\\)\\)\\s*FROM app_dat_operacion_venta ov\\s*JOIN app_dat_pago_venta pv ON ov\\.id_operacion = pv\\.id_operacion_venta\\s*JOIN app_nom_medio_pago mp ON pv\\.id_medio_pago = mp\\.id\\s*WHERE ov\\.id_operacion = of\\.id\\s*AND mp\\.es_activo = true\\s*\\)',
      $repl$'pagos', (
        SELECT jsonb_agg(jsonb_build_object(
            'medio_pago', mp.denominacion,
            'id_medio_pago', mp.id,
            'monto', pv.monto,
            'total', pv.monto,
            'total_sin_descuento', pv.importe_sin_descuento,
            'referencia_pago', pv.referencia_pago,
            'fecha_pago', pv.fecha_pago,
            'es_digital', mp.es_digital,
            'es_efectivo', mp.es_efectivo,
            'tipo_pago', pv.tipo_pago,
            'moneda', COALESCE(NULLIF(upper(trim(pv.moneda)), ''), 'CUP'),
            'tasa_usd', pv.tasa_usd,
            'monto_cup_equivalente', pv.monto_cup_equivalente
        ))
        FROM app_dat_operacion_venta ov
        JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
        JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
        WHERE ov.id_operacion = of.id
        AND mp.es_activo = true
    )$repl$,
      'n'
    );
    IF def2 IS DISTINCT FROM def THEN
      EXECUTE def2;
      RAISE NOTICE 'listar_ordenes patched';
    ELSE
      RAISE NOTICE 'listar_ordenes: pagos block already patched or not matched';
    END IF;
  END IF;
END
$patch$;
