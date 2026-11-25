import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/auto_sync_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_id': 'u1',
      'is_logged_in': true,
      'offline_inventory_store_id': 7,
    });
  });

  Future<void> guardarVentaPendiente() => UserPreferencesService()
      .savePendingOrder({'id': 'venta-1', 'items': <Object>[]});

  group('cierre de sesión con datos sin sincronizar', () {
    test('conserva la venta pendiente y la tienda del dispositivo', () async {
      final prefs = UserPreferencesService();
      await guardarVentaPendiente();

      final borroTodo = await prefs.clearAllCachedDataForOnlineLogout();

      expect(borroTodo, isFalse);
      final pendientes = await prefs.getPendingOrders();
      expect(pendientes.map((o) => o['id']), contains('venta-1'));
      expect(await prefs.getOfflineInventoryStoreId(), 7);
      expect(await prefs.isLoggedIn(), isFalse);
    });

    test('clearUserData no borra la configuración de la tienda', () async {
      SharedPreferences.setMockInitialValues({
        'user_id': 'u1',
        'is_logged_in': true,
        'store_config': '{"tickets_a_imprimir":["cliente"]}',
        'politica_moneda_v1': '{"flag":true}',
      });
      final prefs = UserPreferencesService();
      await prefs.clearUserData();
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('store_config'), isNotNull);
      expect(sp.getString('politica_moneda_v1'), isNotNull);
      expect(await prefs.isLoggedIn(), isFalse);
    });
  });

  group('cambio de tienda', () {
    test('con pendientes no borra y lanza la excepción', () async {
      final prefs = UserPreferencesService();
      await guardarVentaPendiente();

      await expectLater(
        prefs.ensureOfflineStoreScope(9),
        throwsA(isA<PendientesOtraTiendaException>()),
      );

      final pendientes = await prefs.getPendingOrders();
      expect(pendientes.map((o) => o['id']), contains('venta-1'));
      expect(await prefs.getOfflineInventoryStoreId(), 7);
    });

    test('la misma tienda no se bloquea', () async {
      final prefs = UserPreferencesService();
      await guardarVentaPendiente();

      await prefs.ensureOfflineStoreScope(7);

      expect((await prefs.getPendingOrders()), isNotEmpty);
    });
  });

  group('actualización de versión', () {
    test('no borra ventas pendientes', () async {
      final prefs = UserPreferencesService();
      await guardarVentaPendiente();

      await prefs.clearOfflinePreferencesForNewVersion();

      expect((await prefs.getPendingOrders()), isNotEmpty);
    });
  });

  group('descripción de pendientes', () {
    test('nombra cada categoría con datos', () {
      final texto = UserPreferencesService.describirPendientesOffline({
        'ventas': 2,
        'aperturas': 1,
        'cierres': 1,
        'egresos': 3,
        'adminOps': 1,
        'total': 8,
      });
      expect(texto, contains('2 venta(s)'));
      expect(texto, contains('1 apertura(s) de turno'));
      expect(texto, contains('1 cierre(s) de turno'));
      expect(texto, contains('3 egreso(s)'));
      expect(texto, contains('inventario/productos'));
    });

    test('sin datos dice nada pendiente', () {
      expect(
        UserPreferencesService.describirPendientesOffline({'total': 0}),
        'nada pendiente',
      );
    });

    test('PendientesSubida cuenta aperturas, trabajadores y admin', () {
      const solo = PendientesSubida(
        ventas: 0,
        egresos: 0,
        cambiosEstado: 0,
        cierresTurno: 0,
      );
      expect(solo.vacio, isTrue);

      const con = PendientesSubida(
        ventas: 0,
        egresos: 0,
        cambiosEstado: 0,
        cierresTurno: 0,
        aperturasTurno: 1,
        cambiosTrabajadores: 2,
        operacionesAdmin: 1,
      );
      expect(con.vacio, isFalse);
      expect(con.describir(), contains('1 apertura(s) de turno'));
      expect(con.describir(), contains('2 cambio(s) de trabajadores'));
    });
  });

  group('contratos', () {
    final sync = File('lib/services/auto_sync_service.dart').readAsStringSync();
    final orders = File('lib/services/order_service.dart').readAsStringSync();
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();

    test('la venta online exige lo offline subido', () {
      final inicio = orders.indexOf(
        'Future<Map<String, dynamic>> _registerSaleInSupabase(',
      );
      expect(inicio, isNonNegative);
      final cuerpo = orders.substring(inicio, inicio + 3000);
      expect(cuerpo, contains('asegurarSubidaPendientes()'));
      expect(cuerpo.indexOf('asegurarSubidaPendientes()'),
          lessThan(cuerpo.indexOf('_rutaProductoV1')));
    });

    test('las descargas sensibles se omiten con pendientes', () {
      expect(sync, contains('descargasSensiblesAPendientes'));
      expect(sync, contains('pendientesSinSubir'));
      expect(
        AutoSyncService.descargasSensiblesAPendientes,
        containsAll([
          SyncModule.products,
          SyncModule.turno,
          SyncModule.orders,
          SyncModule.egresos,
          SyncModule.shiftWorkers,
        ]),
      );
    });

    test('el logout online sube antes de salir y no borra a ciegas', () {
      final llamada = drawer.indexOf('_subirPendientesAntesDeSalir(dialogContext)');
      expect(llamada, isNonNegative);
      expect(
        llamada,
        lessThan(drawer.indexOf('AuthService().signOut()', llamada)),
      );
      expect(drawer, contains('final borroTodo ='));
    });

    test('el logout offline no llama clearUserData (conserva store_config)', () {
      expect(drawer, contains('Offline: nunca clearUserData'));
      expect(drawer, contains('clearSessionKeepingStoreOffline()'));
      // La rama online/errores de login pueden usar clearUserData; el flujo
      // offline del drawer no debe borrarlo tras el comentario de guarda.
      final guarda = drawer.indexOf('Offline: nunca clearUserData');
      expect(guarda, isNonNegative);
      expect(drawer.substring(guarda), isNot(contains('clearUserData()')));
    });
  });
}
