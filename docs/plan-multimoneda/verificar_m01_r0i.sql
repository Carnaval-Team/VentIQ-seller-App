-- VERIFICADOR DE SOLO LECTURA — posterior a los scripts 13 a 23 en newa.
-- No escribe nada. Ejecutar como postgres.

-- 1) Evidencia compartida
SELECT attname, atttypid::regtype AS tipo
FROM pg_attribute
WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
  AND attname IN ('m01_solicitud', 'm01_id_tienda')
  AND NOT attisdropped
ORDER BY attname;
-- Esperado: m01_id_tienda bigint, m01_solicitud jsonb.

-- 2) RLS de la clave
SELECT relrowsecurity
FROM pg_class
WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass;
-- Esperado: true

-- 3) El cliente autenticado no inserta la clave
SELECT has_any_column_privilege(
    'authenticated',
    'public.app_dat_operacion_offline_idempotencia',
    'INSERT'
) AS authenticated_inserta;
-- Esperado: false

-- 4) Las funciones con clave nombran al actor y a la huella
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_registrar_venta_offline_v4',
      'fn_registrar_pago_venta_offline',
      'fn_registrar_cambio_estado_offline',
      'fn_apertura_turno_offline',
      'fn_cerrar_turno_offline',
      'fn_registrar_egreso_offline',
      'fn_registrar_egreso_offline_v2',
      'fn_pedir_item_cuenta_offline',
      'fn_cambiar_estado_comanda_item_offline',
      'fn_m01_cerrar_turno_residual',
      'fn_m01_aplicar_descuento_manual',
      'fn_m01_mover_pago_venta',
      'fn_m01_marcar_cierre_solicitado',
      'fn_m01_limpiar_marcador_cierre',
      'fn_m01_marcar_venta_cxc',
      'fn_m01_adjuntar_foto_operacion',
      'fn_m01_actualizar_cliente_venta',
      'fn_m01_recibir_operacion_turno',
      'fn_m01_registrar_trabajador_turno',
      'fn_m01_registrar_salida_trabajador',
      'fn_m01_registrar_cambio_precio',
      'fn_m01_actualizar_config_tienda',
      'fn_m01_quitar_foto_operacion',
      'fn_m01_limpiar_pago_sms',
      'fn_m01_reactivar_notificaciones_venta',
      'fn_m01_eliminar_notificacion'
  )
  AND p.prosrc LIKE '%auth.uid()%'
  AND p.prosrc LIKE '%m01_solicitud%'
ORDER BY p.proname;
-- Esperado: las veintiséis filas.

-- 5) anon no ejecuta esas funciones
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_registrar_venta_offline_v4',
      'fn_m01_aplicar_descuento_manual',
      'fn_m01_mover_pago_venta',
      'fn_m01_cerrar_turno_residual',
      'fn_m01_marcar_cierre_solicitado',
      'fn_m01_limpiar_marcador_cierre',
      'fn_m01_marcar_venta_cxc',
      'fn_m01_adjuntar_foto_operacion',
      'fn_m01_actualizar_cliente_venta',
      'fn_m01_recibir_operacion_turno',
      'fn_m01_registrar_trabajador_turno',
      'fn_m01_registrar_salida_trabajador',
      'fn_m01_registrar_cambio_precio',
      'fn_m01_actualizar_config_tienda',
      'fn_m01_quitar_foto_operacion',
      'fn_m01_limpiar_pago_sms',
      'fn_m01_reactivar_notificaciones_venta',
      'fn_m01_eliminar_notificacion'
  )
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname;
-- Esperado: cero filas.
