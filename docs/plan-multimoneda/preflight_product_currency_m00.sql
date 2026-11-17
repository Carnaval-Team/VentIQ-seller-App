BEGIN TRANSACTION READ ONLY;

SELECT 'M00_CONTEXT' AS section,
       current_date AS server_date,
       current_setting('TimeZone') AS server_timezone,
       current_setting('server_version_num') AS postgres_version,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'app_dat_configuracion_tienda'
             AND column_name = 'permitir_moneda_por_producto'
       ) AS product_currency_flag_present,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'app_dat_precio_tpv'
             AND column_name = 'precio_venta_usd'
       ) AS tpv_usd_present;

WITH targets(name) AS (
    VALUES ('app_dat_configuracion_tienda'), ('app_dat_precio_tpv'),
           ('app_dat_precio_venta'), ('app_dat_precio_general_tienda'),
           ('app_dat_extraccion_productos'), ('app_dat_operacion_venta'),
           ('app_dat_pago_venta'), ('app_dat_operacion_offline_idempotencia'),
           ('app_dat_mesa_cuenta_abierta'), ('app_dat_mesa_cuenta_item'),
           ('app_dat_comanda'), ('app_dat_comanda_item'),
           ('app_dat_cliente_cxc'), ('app_dat_liquidacion_cxc'),
           ('app_dat_descuentos_vendedor'), ('app_mkt_promociones'),
           ('tasa_cambio_extraoficial'), ('tasas_conversion'),
           ('app_dat_tienda_moneda'), ('app_v_precio_venta_base_vigente'),
           ('app_v_precio_venta_vigente')
)
SELECT 'M00_RELATIONS' AS section, t.name, c.relkind,
       c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
       pg_get_userbyid(c.relowner) AS owner,
       (SELECT count(*) FROM pg_policies p
        WHERE p.schemaname = 'public' AND p.tablename = t.name) AS policies,
       CASE WHEN c.relkind IN ('r', 'v', 'm', 'p')
            THEN has_table_privilege('anon', c.oid, 'SELECT') END AS anon_select,
       CASE WHEN c.relkind IN ('r', 'v', 'm', 'p')
            THEN has_table_privilege('authenticated', c.oid, 'SELECT') END AS authenticated_select,
       CASE WHEN c.relkind IN ('r', 'p')
            THEN has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE') END AS authenticated_any_write_grant
FROM targets t
LEFT JOIN pg_class c ON c.oid = to_regclass(format('public.%I', t.name))
ORDER BY t.name;

SELECT 'M00_COLUMNS' AS section, table_name, column_name, data_type,
       is_nullable, column_default, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'app_dat_configuracion_tienda', 'app_dat_precio_tpv',
      'app_dat_precio_venta', 'app_dat_precio_general_tienda',
      'app_dat_extraccion_productos', 'app_dat_operacion_venta',
      'app_dat_pago_venta', 'app_dat_operacion_offline_idempotencia',
      'app_dat_mesa_cuenta_abierta', 'app_dat_mesa_cuenta_item',
      'app_dat_cliente_cxc', 'app_dat_liquidacion_cxc',
      'app_dat_descuentos_vendedor', 'app_mkt_promociones',
      'tasa_cambio_extraoficial', 'tasas_conversion'
  )
ORDER BY table_name, ordinal_position;

SELECT 'M00_POLICIES' AS section, tablename, policyname, permissive,
       cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'app_dat_configuracion_tienda', 'app_dat_precio_tpv',
      'app_dat_precio_venta', 'app_dat_precio_general_tienda',
      'app_dat_extraccion_productos', 'app_dat_operacion_venta',
      'app_dat_pago_venta', 'app_dat_operacion_offline_idempotencia',
      'app_dat_mesa_cuenta_abierta', 'app_dat_mesa_cuenta_item',
      'app_dat_comanda', 'app_dat_comanda_item',
      'app_dat_cliente_cxc', 'app_dat_liquidacion_cxc',
      'app_dat_descuentos_vendedor', 'app_mkt_promociones',
      'tasa_cambio_extraoficial', 'tasas_conversion'
  )
ORDER BY tablename, policyname;

SELECT 'M00_CONSTRAINTS' AS section, c.relname AS table_name,
       con.conname, con.contype, pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'app_dat_precio_tpv', 'app_dat_precio_venta',
      'app_dat_operacion_offline_idempotencia',
      'app_dat_extraccion_productos', 'app_dat_operacion_venta',
      'app_dat_pago_venta', 'app_dat_mesa_cuenta_item',
      'app_dat_liquidacion_cxc', 'tasas_conversion', 'tasa_cambio_extraoficial'
  )
ORDER BY c.relname, con.contype, con.conname;

WITH targets(name) AS (
    VALUES ('app_dat_precio_tpv'), ('app_dat_precio_venta'),
           ('app_dat_precio_general_tienda'),
           ('tasa_cambio_extraoficial'), ('tasas_conversion')
)
SELECT 'M00_TRIGGERS' AS section, c.relname AS table_name, t.tgname,
       pg_get_triggerdef(t.oid) AS trigger_definition,
       p.oid::regprocedure::text AS function_signature,
       md5(pg_get_functiondef(p.oid)) AS definition_fingerprint
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND c.oid IN (SELECT to_regclass(format('public.%I', name)) FROM targets)
ORDER BY c.relname, t.tgname;

WITH names(name) AS (
    VALUES ('fn_registrar_venta_v3'), ('fn_registrar_venta_v3_impl'),
           ('fn_registrar_venta_mesa_v3'), ('fn_registrar_venta_mesa_v3_impl'),
           ('fn_registrar_venta_offline_v4'), ('fn_registrar_pago_venta_v3'),
           ('fn_agregar_producto_orden_pendiente_v2'), ('fn_editar_orden_pendiente_v2'),
           ('fn_actualizar_cantidad_producto_orden_v2'),
           ('fn_admin_caja_precio_tpv_offline'), ('fn_pedir_item_cuenta_v2'),
           ('fn_cxc_saldo_cliente'), ('fn_cxc_registrar_liquidacion'),
           ('fn_guardar_precio_venta_base'), ('check_user_has_access_to_tienda'),
           ('fn_user_can_access_tienda'), ('fn_config_tienda_puede_leer'),
           ('fn_config_tienda_puede_escribir')
)
SELECT 'M00_FUNCTIONS' AS section, names.name,
       p.oid::regprocedure::text AS signature,
       p.prosecdef AS security_definer,
       pg_get_userbyid(p.proowner) AS owner,
       (SELECT string_agg(v, ',') FROM unnest(p.proconfig) v
        WHERE v LIKE 'search_path=%') AS search_path,
       md5(pg_get_functiondef(p.oid)) AS definition_fingerprint,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM names
LEFT JOIN pg_namespace n ON n.nspname = 'public'
LEFT JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = names.name
ORDER BY names.name, signature;

WITH targets(name) AS (
    VALUES ('app_dat_operacion_offline_idempotencia'),
           ('app_dat_extraccion_productos'), ('app_dat_precio_tpv'),
           ('tasas_conversion'), ('tasa_cambio_extraoficial')
)
SELECT 'M00_TEXTUAL_CONSUMERS' AS section, t.name,
       p.oid::regprocedure::text AS textual_consumer,
       p.prosrc ~* '\m(UPDATE|INSERT|DELETE)\M' AS mentions_write_keyword
FROM targets t
JOIN pg_proc p ON position(t.name IN p.prosrc) > 0
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE p.prokind = 'f'
ORDER BY t.name, p.proname, p.oid;

SELECT 'M00_VIEWS' AS section, c.relname, c.reloptions,
       pg_get_viewdef(c.oid, true) AS definition
FROM pg_class c
WHERE c.oid IN (
    to_regclass('public.app_v_precio_venta_base_vigente'),
    to_regclass('public.app_v_precio_venta_vigente')
)
ORDER BY c.relname;

COMMIT;
