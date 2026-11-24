import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'rpc_m01_mock_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/auto_sync_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = '00000000-0000-4000-8000-000000000031';
  final requests = <http.Request>[];
  var enVuelo = 0;
  var maxEnVuelo = 0;
  var demora = Duration.zero;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final m01 = m01NoDesplegada(request);
        if (m01 != null) return m01;
        requests.add(request);
        enVuelo++;
        if (enVuelo > maxEnVuelo) maxEnVuelo = enVuelo;
        try {
          await Future<void>.delayed(demora);
          return http.Response(
            jsonEncode({'status': 'success'}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        } finally {
          enVuelo--;
        }
      }),
    );
  });

  setUp(() async {
    requests.clear();
    enVuelo = 0;
    maxEnVuelo = 0;
    demora = Duration.zero;
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': userId, 'exp': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000})}.test-signature';
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    SharedPreferences.setMockInitialValues({
      'user_id': userId,
      'user_email': 'test@example.com',
      'access_token': token,
      'is_logged_in': true,
      'id_tpv': 9,
    });
  });

  tearDownAll(() => Supabase.instance.dispose());

  group('cola pending_operations', () {
    test('cada operación nueva recibe op_id', () async {
      final prefs = UserPreferencesService();
      await prefs.savePendingOperation({'type': 'order_status_change'});
      final ops = await prefs.getPendingOperations();
      expect(ops.single['op_id'], isNotEmpty);
    });

    test('reemplazar conserva lo guardado durante la subida', () async {
      final prefs = UserPreferencesService();
      await prefs.savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-1',
      });
      await prefs.savePendingOperation({
        'type': 'add_shift_worker',
        'data': {'id_trabajador': 4},
      });
      final tomadas = (await prefs.getPendingOperations())
          .where((o) => o['type'] == 'order_status_change')
          .toList();

      // Llega una operación nueva mientras la subida está en curso.
      await prefs.savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-2',
      });

      await prefs.reemplazarPendingOperations(
        procesadas: tomadas.map(UserPreferencesService.claveOperacion).toSet(),
        pendientes: const [],
      );

      final quedan = await prefs.getPendingOperations();
      expect(quedan.map((o) => o['order_id'] ?? o['type']), [
        'add_shift_worker',
        'ORD-2',
      ]);
    });

    test('una operación fallida queda antes que las más nuevas', () async {
      final prefs = UserPreferencesService();
      await prefs.savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-1',
        'new_status': 'completada',
      });
      final tomada = (await prefs.getPendingOperations()).single;
      await prefs.savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-1',
        'new_status': 'cancelada',
      });

      await prefs.reemplazarPendingOperations(
        procesadas: {UserPreferencesService.claveOperacion(tomada)},
        pendientes: [tomada],
      );

      final quedan = await prefs.getPendingOperations();
      expect(quedan.map((o) => o['new_status']), ['completada', 'cancelada']);
    });

    test('operaciones antiguas sin op_id se identifican por tipo y fecha', () {
      expect(
        UserPreferencesService.claveOperacion({
          'type': 'add_shift_worker',
          'created_at': '2026-11-20T10:00:00.000',
        }),
        'add_shift_worker|2026-11-20T10:00:00.000',
      );
    });
  });

  group('una sola sincronización a la vez', () {
    test('dos pedidos simultáneos no suben el mismo cambio dos veces', () async {
      demora = const Duration(milliseconds: 80);
      await UserPreferencesService().savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-71',
        'id_operacion': 71,
        'new_status': 'completada',
      });
      final sync = AutoSyncService();

      final resultados = await Future.wait([
        sync.syncPendingOrderStatusChanges(),
        sync.syncPendingOrderStatusChanges(),
      ]);

      expect(maxEnVuelo, 1);
      expect(resultados, [1, 0]);
      expect(
        requests.where(
          (r) => r.url.path.endsWith('fn_registrar_cambio_estado_offline'),
        ),
        hasLength(1),
      );
      expect(await UserPreferencesService().getPendingOperations(), isEmpty);
    });

    test('waitUntilIdle espera a la sincronización en curso', () async {
      demora = const Duration(milliseconds: 80);
      await UserPreferencesService().savePendingOperation({
        'type': 'order_status_change',
        'order_id': 'ORD-72',
        'id_operacion': 72,
        'new_status': 'completada',
      });
      final sync = AutoSyncService();

      final enCurso = sync.syncPendingOrderStatusChanges();
      expect(sync.isSyncing, isTrue);
      await sync.waitUntilIdle(timeout: const Duration(seconds: 5));

      expect(sync.isSyncing, isFalse);
      expect(await UserPreferencesService().getPendingOperations(), isEmpty);
      expect(await enCurso, 1);
    });
  });

  group('ventas de un turno sin apertura', () {
    test('el reintento manual no sube la venta antes de la apertura', () async {
      final prefs = UserPreferencesService();
      await prefs.upsertOfflineTurno({
        'local_id': 'turno-local-1',
        'status': UserPreferencesService.offlineTurnoStatusOpen,
        'id_tpv': 9,
        'fecha_apertura': '2026-11-20T08:00:00.000Z',
      });
      await prefs.savePendingOrder({
        'id': 'venta-sin-apertura',
        'local_turno_id': 'turno-local-1',
        'client_uuid': '00000000-0000-4000-8000-000000000032',
        'estado': 'completada',
        'items': [
          {
            'id_producto': 7,
            'cantidad': 1,
            'precio_unitario': 0,
            'subtotal': 0,
          },
        ],
        'desglose_pagos': <Object>[],
      });
      requests.clear();

      final ok = await AutoSyncService().syncSinglePendingOrder(
        'venta-sin-apertura',
      );

      expect(ok, isFalse);
      expect(
        requests.where((r) => r.url.path.contains('fn_registrar_venta')),
        isEmpty,
      );
    });

    test('lo pendiente se cuenta por turno', () async {
      final prefs = UserPreferencesService();
      await prefs.savePendingOrder({
        'id': 'a',
        'local_turno_id': 'turno-a',
        'items': <Object>[],
      });
      await prefs.savePendingOrder({
        'id': 'b',
        'local_turno_id': 'turno-b',
        'items': <Object>[],
      });

      final pendientes = await AutoSyncService().contarPendientesSubida(
        turno: {'local_id': 'turno-a'},
      );

      expect(pendientes.ventas, 1);
      expect(pendientes.describir(), contains('1 venta'));
    });
  });

  group('contratos del pipeline', () {
    final servicio =
        File('lib/services/auto_sync_service.dart').readAsStringSync();

    String cuerpo(String firma) {
      final inicio = servicio.indexOf(firma);
      expect(inicio, isNonNegative, reason: firma);
      final siguiente = servicio.indexOf('\n  Future<', inicio + firma.length);
      return servicio.substring(inicio, siguiente < 0 ? null : siguiente);
    }

    test('el bloqueo es el único estado de sincronización', () {
      expect(servicio, isNot(contains('_isSyncing = ')));
      expect(servicio, isNot(contains('_pendingSyncRequested')));
      expect(servicio, isNot(contains('acquireLock')));
      expect(servicio, isNot(contains('forceSyncPendingOrders')));
      expect(servicio, isNot(contains('_syncSingleOfflineTurnoEntry')));
    });

    test('toda vía pública de escritura pasa por el bloqueo', () {
      for (final firma in [
        'Future<SyncResult> syncModules(',
        'Future<Map<String, dynamic>> syncOfflineTurnosFromAdmin(',
        'Future<Map<String, dynamic>> syncOfflineTurnoAfterLocalCierre(',
        'Future<Map<String, dynamic>> forceResolveStuckTurno(',
        'Future<void> reconcileStaleOfflineTurnos(',
        'Future<bool> syncSinglePendingOrder(',
        'Future<int> syncPendingOrderStatusChanges(',
        'Future<int> pullServerOrdersForCurrentShift(',
      ]) {
        expect(cuerpo(firma), contains('_enExclusiva'), reason: firma);
      }
    });

    test('el checkpoint nunca salta las subidas', () {
      expect(servicio, contains('completed.contains(m.name) && !m.isUpload'));
    });

    test('el cierre de la cola espera a las ventas y egresos del turno', () {
      final cola = cuerpo('Future<Map<String, dynamic>> _runOfflineTurnoQueue(');
      final gate = cola.indexOf('_pendientesDelTurno(refreshed)');
      final cierre = cola.indexOf('_syncCierreForQueueEntry(refreshed)');
      expect(gate, isNonNegative);
      expect(cola.indexOf('_syncOrderStatusChanges()'), lessThan(gate));
      expect(gate, lessThan(cierre));
    });

    test('ventas y egresos suben antes del cierre de la cola', () {
      final pipelineStart = servicio.indexOf('const pipelineOrder = [');
      final pipelineEnd = servicio.indexOf('];', pipelineStart);
      expect(pipelineStart, isNonNegative);
      final pipeline = servicio.substring(pipelineStart, pipelineEnd);
      expect(
        pipeline.indexOf('SyncModule.uploadSales'),
        allOf(
          isNonNegative,
          lessThan(pipeline.indexOf('SyncModule.uploadEgresos')),
        ),
      );
      expect(
        pipeline.indexOf('SyncModule.uploadEgresos'),
        lessThan(pipeline.indexOf('SyncModule.uploadTurno')),
      );

      final subir = cuerpo('Future<Map<String, dynamic>> _subirTodoSinLock(');
      expect(
        subir.indexOf('_syncOfflineSales()'),
        allOf(
          isNonNegative,
          lessThan(subir.indexOf('_syncOfflineEgresos()')),
        ),
      );
      expect(
        subir.indexOf('_syncOfflineEgresos()'),
        lessThan(subir.indexOf('_syncOfflineTurnoQueue()')),
      );
    });

    test('un estado desconocido nunca cuenta como turno cerrado', () {
      final cierre = cuerpo('Future<bool> _syncCierreForQueueEntry(');
      expect(cierre, contains('estado != null && estado != 1'));
      expect(cierre, contains('estadoFinal == null || estadoFinal == 1'));
    });

    test('la reconciliación no descarta turnos sin respuesta del servidor', () {
      final reconcile = cuerpo('Future<void> reconcileStaleOfflineTurnos(');
      expect(reconcile, contains("diag['hasServerId'] == true"));
      expect(reconcile, contains("diag['error'] == null"));
      expect(reconcile, contains('_pendientesDelTurno(t)'));
    });

    test('las pantallas online suben lo pendiente antes de cerrar o abrir', () {
      final cierre = File('lib/screens/cierre_screen.dart').readAsStringSync();
      expect(
        cierre.indexOf('sync.subirPendientes()'),
        allOf(
          isNonNegative,
          lessThan(cierre.indexOf('TurnoService.cerrarTurnoDetailed(')),
        ),
      );

      final apertura =
          File('lib/screens/apertura_screen.dart').readAsStringSync();
      expect(
        apertura.indexOf('faltan.cierresTurno > 0'),
        allOf(
          isNonNegative,
          lessThan(apertura.indexOf('TurnoService.registrarAperturaTurno(')),
        ),
      );
    });

    test('no quedan vías de sincronización paralelas', () {
      expect(File('lib/widgets/pending_orders_fab.dart').existsSync(), isFalse);
      final ajustes = File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(ajustes, isNot(contains('class _SyncDialog')));
      expect(ajustes, isNot(contains('class _ManualSyncDialog')));
      final ops =
          File(
            'lib/screens/admin/admin_pending_ops_screen.dart',
          ).readAsStringSync();
      expect(ops, isNot(contains('syncPendingOps()')));
    });
  });
}
