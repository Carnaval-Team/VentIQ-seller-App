import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String evidencia;
  late String venta;
  late String pago;
  late String estado;
  late String caja;
  late String descuento;
  late String anotaciones;
  late String turno;
  late String configTienda;
  late String foto;
  late String columnas;
  late String desvincular;
  late String harness;

  setUpAll(() {
    evidencia = File(
      '../docs/plan-multimoneda/m01_r0i_idempotencia_evidencia_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    venta = File(
      '../docs/plan-multimoneda/m01_r0i_venta_offline_v4_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    pago = File(
      '../docs/plan-multimoneda/m01_r0i_pago_offline_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    estado = File(
      '../docs/plan-multimoneda/m01_r0i_estado_offline_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    caja = File(
      '../docs/plan-multimoneda/m01_r0i_caja_cocina_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    descuento = File(
      '../docs/plan-multimoneda/m01_r0i_descuento_pago_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    anotaciones = File(
      '../docs/plan-multimoneda/m01_r0i_anotaciones_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    turno = File(
      '../docs/plan-multimoneda/m01_r0i_turno_personal_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    configTienda = File(
      '../docs/plan-multimoneda/m01_r0i_config_tienda_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    foto = File(
      '../docs/plan-multimoneda/m01_r0i_foto_sms_notificaciones_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    columnas = File(
      '../docs/plan-multimoneda/m01_r0e_tienda_columnas_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    desvincular = File(
      '../docs/plan-multimoneda/m01_r0b_desvincular_usuario_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    harness = File(
      '../docs/plan-multimoneda/m01_r0i_rol_harness.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('la evidencia compartida es el unico alta de columnas', () {
    expect(evidencia.trimLeft(), startsWith('BEGIN;'));
    expect(evidencia.trimRight(), endsWith('COMMIT;'));
    expect(
      evidencia,
      contains("current_setting('app.m01_r0i_evidencia_approved', true)"),
    );
    expect(evidencia, contains('ADD COLUMN m01_solicitud jsonb'));
    expect(evidencia, contains('ADD COLUMN m01_id_tienda bigint'));
    expect(evidencia, contains('La evidencia M01 ya existe'));
    expect(evidencia, isNot(contains('CREATE OR REPLACE FUNCTION')));
    expect(
      evidencia,
      isNot(contains('UPDATE public.app_dat_operacion_offline_idempotencia')),
    );
    expect(evidencia, isNot(contains('fn_admin_caja_')));
  });

  test('v4 exige el cuerpo baseline y no crea columnas', () {
    expect(venta.trimLeft(), startsWith('BEGIN;'));
    expect(venta.trimRight(), endsWith('COMMIT;'));
    expect(venta, contains("current_user <> 'postgres'"));
    expect(
      venta,
      contains("current_setting('app.m01_r0i_venta_approved', true)"),
    );
    expect(venta, contains('md5(prosrc)'));
    expect(venta, contains('1833dad11bafe28cddd6a67184385ced'));
    expect(venta, contains("attname = 'm01_solicitud'"));
    expect(venta, contains("atttypid = 'jsonb'::regtype"));
    expect(venta, contains("attname = 'm01_id_tienda'"));
    expect(venta, contains('relrowsecurity'));
    expect(venta, isNot(contains('ADD COLUMN')));
    expect(venta, isNot(contains('check_user_has_access_to_tienda')));
  });

  test('el replay valida la huella y no vuelve a vender ni a cobrar', () {
    expect(venta, contains('SET search_path = pg_catalog'));
    final body = venta.substring(venta.indexOf('AS \$function\$'));
    expect(body, contains('v_actor uuid := auth.uid()'));
    expect(
      body.indexOf('pg_advisory_xact_lock'),
      lessThan(body.indexOf('SELECT * INTO v_existing')),
    );
    expect(body, contains("v_existing.tipo IS DISTINCT FROM 'venta_v4'"));
    expect(body, contains('v_existing.uuid_usuario IS DISTINCT FROM v_actor'));
    expect(
      body,
      contains('v_existing.m01_solicitud IS DISTINCT FROM v_request'),
    );
    expect(body, contains('v_existing.m01_id_tienda IS NULL'));
    final replay = body.substring(
      body.indexOf('IF FOUND THEN'),
      body.indexOf('FOR v_seller_id, v_store IN'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('fn_registrar_venta_v3')));
    expect(replay, isNot(contains('fn_registrar_pago_venta_v2')));
    expect(replay, isNot(contains('INSERT ')));
    expect(replay, isNot(contains('UPDATE ')));
  });

  test('el primer envio ata vendedor trabajador y TPV antes de registrar', () {
    final body = venta.substring(venta.indexOf('FOR v_seller_id, v_store IN'));
    expect(body, contains('FOR SHARE OF v, w, t'));
    expect(body, contains('w.uuid = p_uuid'));
    expect(body, contains('w.deleted_at IS NULL'));
    expect(body, contains('v.id_tpv = p_id_tpv'));
    expect(body, contains('w.id_tienda = t.id_tienda'));
    expect(body, contains('v_matches IS DISTINCT FROM 1'));
    expect(body, contains('p_uuid IS DISTINCT FROM v_actor'));
    expect(body, contains('fn_config_tienda_puede_escribir(v_store)'));
    final register = body.indexOf('public.fn_registrar_venta_v3(');
    final guard = body.indexOf('v_matches IS DISTINCT FROM 1');
    final insert = body.indexOf(
      'INSERT INTO public.app_dat_operacion_offline_idempotencia',
    );
    final pay = body.indexOf('public.fn_registrar_pago_venta_v2(');
    expect(guard, lessThan(register));
    expect(register, lessThan(insert));
    expect(insert, lessThan(pay));
    expect(body, isNot(contains('ON CONFLICT')));
    expect(body, contains("'venta_v4', v_actor, v_request, v_store"));
  });

  test('cierra las entradas offline anteriores y conserva la venta online', () {
    expect(venta, contains('FROM PUBLIC, anon, authenticated, service_role'));
    expect(venta, contains('TO authenticated;'));
    expect(
      venta,
      contains(
        'REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v3(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)',
      ),
    );
    expect(
      venta,
      contains(
        'REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz)',
      ),
    );
    expect(
      venta,
      contains(
        'REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)',
      ),
    );
    expect(
      venta,
      contains(
        'REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v2(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)',
      ),
    );
    expect(
      venta,
      isNot(contains('REVOKE ALL ON FUNCTION public.fn_registrar_venta_v3(')),
    );
  });

  test('el cobro offline exige baseline, huella y no reescribe en el replay', () {
    expect(pago.trimLeft(), startsWith('BEGIN;'));
    expect(pago.trimRight(), endsWith('COMMIT;'));
    expect(
      pago,
      contains("current_setting('app.m01_r0i_pago_approved', true)"),
    );
    expect(pago, contains('85f5e34cf046eb9b042073c6a917e4e6'));
    expect(pago, contains('SET search_path = pg_catalog'));
    expect(pago, isNot(contains('ADD COLUMN')));
    expect(pago, isNot(contains('ON CONFLICT')));
    final body = pago.substring(pago.indexOf('AS \$function\$'));
    expect(body, contains('v_actor uuid := auth.uid()'));
    expect(
      body.indexOf('pg_advisory_xact_lock'),
      lessThan(body.indexOf('SELECT * INTO v_existing')),
    );
    expect(body, contains("v_existing.tipo IS DISTINCT FROM 'pago'"));
    expect(
      body,
      contains(
        'v_existing.id_operacion IS DISTINCT FROM p_id_operacion_venta',
      ),
    );
    final replay = body.substring(
      body.indexOf('IF FOUND THEN'),
      body.indexOf('SELECT o.id_tienda, o.uuid, ov.id_tpv'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('fn_registrar_pago_venta(')));
    expect(replay, isNot(contains('INSERT ')));
    final charge = body.indexOf('public.fn_registrar_pago_venta(');
    final guard = body.indexOf('v_actor IS DISTINCT FROM v_sale_actor');
    final insert = body.indexOf(
      'INSERT INTO public.app_dat_operacion_offline_idempotencia',
    );
    expect(guard, lessThan(charge));
    expect(charge, lessThan(insert));
    expect(body, contains('s.id_tpv = v_tpv'));
    expect(body, contains('w.id_tienda = v_store'));
    expect(pago, contains('FROM PUBLIC, anon, authenticated, service_role'));
    expect(pago, contains('TO authenticated;'));
  });

  test('el cambio de estado offline no repite el efecto en el replay', () {
    expect(estado.trimLeft(), startsWith('BEGIN;'));
    expect(estado.trimRight(), endsWith('COMMIT;'));
    expect(
      estado,
      contains("current_setting('app.m01_r0i_estado_approved', true)"),
    );
    expect(estado, contains('565daac1a8fdbecbd2faffa8efcacfce'));
    expect(estado, contains('SET search_path = pg_catalog'));
    expect(estado, isNot(contains('ADD COLUMN')));
    expect(estado, isNot(contains('ON CONFLICT')));
    expect(
      estado,
      isNot(
        contains(
          'REVOKE ALL ON FUNCTION public.fn_registrar_cambio_estado_operacion(',
        ),
      ),
    );
    final body = estado.substring(estado.indexOf('AS \$function\$'));
    expect(body, contains('v_actor uuid := auth.uid()'));
    expect(body, contains("'estado:' || p_nuevo_estado::text"));
    expect(
      body.indexOf('pg_advisory_xact_lock'),
      lessThan(body.indexOf('SELECT * INTO v_existing')),
    );
    final replay = body.substring(
      body.indexOf('IF FOUND THEN'),
      body.indexOf('SELECT o.id_tienda, o.uuid, ov.id_tpv'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('fn_registrar_cambio_estado_operacion(')));
    expect(replay, isNot(contains('INSERT ')));
    final change = body.indexOf('public.fn_registrar_cambio_estado_operacion(');
    final guard = body.indexOf('v_actor IS DISTINCT FROM v_sale_actor');
    final insert = body.indexOf(
      'INSERT INTO public.app_dat_operacion_offline_idempotencia',
    );
    expect(guard, lessThan(change));
    expect(change, lessThan(insert));
    expect(estado, contains('TO authenticated;'));
  });

  test('caja y cocina exigen huella y el replay no repite el efecto', () {
    expect(caja.trimLeft(), startsWith('BEGIN;'));
    expect(caja.trimRight(), endsWith('COMMIT;'));
    expect(caja, contains("current_user <> 'postgres'"));
    expect(
      caja,
      contains("current_setting('app.m01_r0i_caja_cocina_approved', true)"),
    );
    expect(caja, contains('8c7ddcbfb2dccd447754b2722d5d33af'));
    expect(caja, contains('5ba47aac84e2f8fcac8bffdf67199558'));
    expect(caja, contains('548113889a72572ca1c3c851f21cf174'));
    expect(caja, contains('637e84dfae7d78c14e8cb02357be5104'));
    expect(caja, contains('ffbb357d8b223c2589fc37d441723b78'));
    expect(caja, contains('SET search_path = pg_catalog'));
    expect(caja, contains('v_actor uuid := auth.uid()'));
    expect(caja, contains('pg_advisory_xact_lock'));
    expect(caja, contains('m01_solicitud IS DISTINCT FROM v_request'));
    expect(caja, contains('app.m01_caja_extra'));
    expect(caja, contains("'efectivo_por_moneda'"));
    expect(caja, contains('fn_m01_cerrar_turno_residual'));
    final residual = caja.substring(
      caja.indexOf('FUNCTION public.fn_m01_cerrar_turno_residual'),
      caja.indexOf('REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline'),
    );
    final residualReplay = residual.substring(
      residual.indexOf('IF FOUND THEN'),
      residual.indexOf('SELECT t.id_tienda'),
    );
    expect(residualReplay, isNot(contains('UPDATE ')));
    expect(
      residual.indexOf('v_inventario IS TRUE'),
      lessThan(residual.indexOf('SET estado = 2')),
    );
    expect(caja, isNot(contains('ADD COLUMN')));
    expect(caja, isNot(contains('ON CONFLICT (client_uuid)')));
    expect(caja, isNot(contains('DO NOTHING')));
    expect(caja, isNot(contains('fn_admin_caja_')));
    expect(caja, contains('public.fn_pedir_item_cuenta_v2('));
    expect(caja, isNot(contains('public.fn_pedir_item_cuenta(')));
    final pedir = caja.substring(
      caja.indexOf('FUNCTION public.fn_pedir_item_cuenta_offline'),
      caja.indexOf('FUNCTION public.fn_cambiar_estado_comanda_item_offline'),
    );
    final replay = pedir.substring(
      pedir.indexOf('IF FOUND THEN'),
      pedir.indexOf('SELECT c.id_tienda INTO v_store'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('fn_pedir_item_cuenta_v2(')));
    expect(
      pedir.indexOf('IF FOUND THEN'),
      lessThan(pedir.indexOf('public.fn_pedir_item_cuenta_v2(')),
    );
  });

  test('descuento y traslado exigen huella y el replay no reescribe', () {
    expect(descuento.trimLeft(), startsWith('BEGIN;'));
    expect(descuento.trimRight(), endsWith('COMMIT;'));
    expect(
      descuento,
      contains("current_setting('app.m01_r0i_descuento_pago_approved', true)"),
    );
    expect(descuento, contains('v_actor uuid := auth.uid()'));
    expect(descuento, contains('fn_m01_aplicar_descuento_manual'));
    expect(descuento, contains('fn_m01_mover_pago_venta'));
    expect(descuento, isNot(contains('ADD COLUMN')));
    expect(descuento, isNot(contains('ON CONFLICT')));
    expect(descuento, isNot(contains('DO NOTHING')));
    final replay = descuento.substring(
      descuento.indexOf('IF FOUND THEN'),
      descuento.indexOf('SELECT o.id_tienda, ov.id_tpv, ov.id_cliente'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('INSERT INTO public.app_dat_descuentos_vendedor')));
    expect(replay, isNot(contains('UPDATE public.app_dat_pago_venta')));
  });

  test('las anotaciones exigen huella y el replay no reescribe', () {
    expect(anotaciones.trimLeft(), startsWith('BEGIN;'));
    expect(anotaciones.trimRight(), endsWith('COMMIT;'));
    expect(
      anotaciones,
      contains("current_setting('app.m01_r0i_anotaciones_approved', true)"),
    );
    expect(anotaciones, contains('v_actor uuid := auth.uid()'));
    expect(anotaciones, contains('fn_m01_marcar_cierre_solicitado'));
    expect(anotaciones, contains('fn_m01_limpiar_marcador_cierre'));
    expect(anotaciones, contains('fn_m01_marcar_venta_cxc'));
    expect(anotaciones, contains('fn_m01_adjuntar_foto_operacion'));
    expect(anotaciones, contains('fn_m01_actualizar_cliente_venta'));
    expect(anotaciones, isNot(contains('ADD COLUMN')));
    expect(anotaciones, isNot(contains('ON CONFLICT')));
    expect(anotaciones, isNot(contains('DO NOTHING')));
    final replay = anotaciones.substring(
      anotaciones.indexOf('IF FOUND THEN'),
      anotaciones.indexOf('SELECT t.id_tienda, ct.id_tpv, ct.estado'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('UPDATE public.app_dat_caja_turno')));
  });

  test('recibir una orden y el personal exigen huella', () {
    expect(turno.trimLeft(), startsWith('BEGIN;'));
    expect(turno.trimRight(), endsWith('COMMIT;'));
    expect(
      turno,
      contains("current_setting('app.m01_r0i_turno_personal_approved', true)"),
    );
    expect(turno, contains('v_actor uuid := auth.uid()'));
    expect(turno, contains('fn_m01_recibir_operacion_turno'));
    expect(turno, contains('fn_m01_registrar_trabajador_turno'));
    expect(turno, contains('fn_m01_registrar_salida_trabajador'));
    expect(turno, contains('fn_m01_registrar_cambio_precio'));
    expect(turno, contains('fn_m01_puede_operar_tienda'));
    expect(turno, isNot(contains('ADD COLUMN')));
    expect(turno, isNot(contains('ON CONFLICT')));
    expect(turno, isNot(contains('DO NOTHING')));
    final replay = turno.substring(
      turno.indexOf('IF FOUND THEN'),
      turno.indexOf('SELECT t.id_tienda, ct.id_tpv, ct.fecha_apertura'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('UPDATE public.app_dat_operaciones')));
  });

  test('la configuracion de tienda exige huella y no reescribe en el replay', () {
    expect(configTienda.trimLeft(), startsWith('BEGIN;'));
    expect(configTienda.trimRight(), endsWith('COMMIT;'));
    expect(
      configTienda,
      contains("current_setting('app.m01_r0i_config_tienda_approved', true)"),
    );
    expect(configTienda, contains('v_actor uuid := auth.uid()'));
    expect(configTienda, contains('fn_m01_actualizar_config_tienda'));
    expect(configTienda, contains('fn_config_tienda_puede_escribir'));
    expect(configTienda, contains("'modo_restaurante'"));
    expect(configTienda, contains("'tickets_a_imprimir'"));
    expect(configTienda, contains("'copias_por_ticket'"));
    expect(configTienda, isNot(contains('ADD COLUMN')));
    expect(configTienda, isNot(contains('ON CONFLICT')));
    expect(configTienda, isNot(contains('EXECUTE format')));
    final replay = configTienda.substring(
      configTienda.indexOf('IF FOUND THEN'),
      configTienda.indexOf('fn_config_tienda_puede_escribir(p_id_tienda)'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('UPDATE public.app_dat_configuracion_tienda')));
  });

  test('quitar foto, SMS y notificaciones exigen huella', () {
    expect(foto.trimLeft(), startsWith('BEGIN;'));
    expect(foto.trimRight(), endsWith('COMMIT;'));
    expect(foto, contains('fn_m01_quitar_foto_operacion'));
    expect(foto, contains('fn_m01_limpiar_pago_sms'));
    expect(foto, contains('fn_m01_reactivar_notificaciones_venta'));
    expect(foto, contains('fn_m01_eliminar_notificacion'));
    expect(foto, contains('fn_marcar_notificacion_leida'));
    expect(foto, isNot(contains('ADD COLUMN')));
    final replay = foto.substring(
      foto.indexOf('IF FOUND THEN'),
      foto.indexOf('SELECT o.id_tienda, ov.id_tpv INTO v_store, v_tpv'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, isNot(contains('foto_operacion_url = NULL')));
  });

  test('el perfil de tienda no concede las columnas de confianza', () {
    expect(columnas.trimLeft(), startsWith('BEGIN;'));
    expect(columnas.trimRight(), endsWith('COMMIT;'));
    expect(columnas, contains('m01_tienda_actualizar'));
    expect(columnas, contains('fn_is_superadmin_full_access'));
    final grant = columnas.substring(
      columnas.indexOf('GRANT UPDATE ('),
      columnas.indexOf(') ON TABLE public.app_dat_tienda'),
    );
    expect(grant, contains('denominacion'));
    expect(grant, contains('mostrar_en_catalogo'));
    expect(grant, isNot(contains('es_prueba')));
    expect(grant, isNot(contains('validada')));
    expect(grant, isNot(contains('admin_carnaval')));
    expect(grant, isNot(contains('id_tienda_carnaval')));
    expect(grant, isNot(contains('only_catalogo')));
    expect(columnas, contains('fn_m01_vincular_tienda_carnaval'));
    expect(columnas, contains('fn_m01_marcar_tienda_prueba'));
    expect(columnas, isNot(contains('ADD COLUMN')));
  });

  test('desvincular quita el login y no borra roles ni la cuenta', () {
    expect(desvincular.trimLeft(), startsWith('BEGIN;'));
    expect(desvincular.trimRight(), endsWith('COMMIT;'));
    expect(desvincular, contains('auth.uid()'));
    expect(desvincular, contains('SET uuid = NULL'));
    expect(desvincular, contains('fn_m01_personal_desvincular_usuario_trabajador'));
    expect(desvincular, isNot(contains('DELETE FROM public.app_dat_')));
    expect(desvincular, isNot(contains('DELETE FROM auth.users')));
    expect(desvincular, contains('app_dat_dueno'));
    expect(desvincular, contains('app_dat_superadmin'));
  });

  test('el harness de rol termina en rollback', () {
    expect(harness.trimLeft(), startsWith('BEGIN;'));
    expect(harness.trimRight(), endsWith('ROLLBACK;'));
    expect(harness, contains('app.m01_fixture_vendor_uuid'));
    expect(harness, contains('app.m01_fixture_other_store_id'));
    expect(harness, contains('gen_random_uuid()'));
    expect(harness, contains('El vendedor de otra tienda no fue rechazado'));
    expect(harness, contains('escalar'));
    expect(harness, contains('El replay no devolvio la clave original'));
  });
}
