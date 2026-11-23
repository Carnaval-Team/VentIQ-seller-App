import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/offline_readiness.dart';

void main() {
  test('mensaje lista faltantes cuando no está listo', () {
    const r = OfflineReadiness([
      'Monedas de la tienda',
      'Tasa USD→CUP',
    ]);
    expect(r.listo, isFalse);
    expect(r.mensaje, contains('Falta para trabajar offline:'));
    expect(r.mensaje, contains('• Monedas de la tienda'));
    expect(r.mensaje, contains('• Tasa USD→CUP'));
  });

  test('mensaje listo cuando no falta nada', () {
    const r = OfflineReadiness([]);
    expect(r.listo, isTrue);
    expect(r.mensaje, contains('Datos listos'));
  });

  test('settings, prep, AppBar y switch offline usan OfflineReadiness', () {
    final settings = File('lib/screens/settings_screen.dart').readAsStringSync();
    final prep =
        File('lib/services/device_offline_prep_service.dart').readAsStringSync();
    final orders = File('lib/services/order_service.dart').readAsStringSync();
    final appBar =
        File('lib/widgets/connection_status_widget.dart').readAsStringSync();
    final manager =
        File('lib/services/smart_offline_manager.dart').readAsStringSync();
    expect(settings, contains('OfflineReadiness.inspeccionar'));
    expect(settings, contains('_showOfflineReadinessDialog'));
    expect(settings, contains('Listo para offline'));
    expect(prep, contains('OfflineReadiness.inspeccionar'));
    expect(orders, contains('OfflineReadiness.inspeccionar'));
    expect(appBar, contains('OfflineReadiness.inspeccionar'));
    expect(appBar, contains('_buildOfflineReadinessSection'));
    expect(appBar, contains('Sincronizar información faltante'));
    expect(appBar, contains('_syncMissingOfflineData'));
    expect(manager, contains('OfflineReadiness.inspeccionar'));
    expect(manager, contains('enableOfflineModeFromUi'));
    final store =
        File('lib/money/politica_moneda_store.dart').readAsStringSync();
    final readiness =
        File('lib/money/offline_readiness.dart').readAsStringSync();
    expect(store, contains('resolverUsuarioSesion'));
    expect(store, contains('getUserId'));
    expect(readiness, contains('resolverUsuarioSesion'));
  });
}
