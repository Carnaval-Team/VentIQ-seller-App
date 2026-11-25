import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/auto_sync_service.dart';

void main() {
  test('SyncModuleCatalog cubre todos los SyncModule sin huecos', () {
    expect(
      SyncModuleCatalog.all,
      SyncModule.values.toSet(),
      reason: 'uploads+downloads deben igualar el enum completo',
    );
    expect(
      SyncModuleCatalog.downloads.toSet().intersection(
        SyncModuleCatalog.uploads.toSet(),
      ),
      isEmpty,
    );
    expect(
      SyncModuleCatalog.offlineReadinessRequired,
      isNot(contains(SyncModule.defaultCashFund)),
      reason: 'fondo de caja es opcional para activar offline',
    );
    expect(
      SyncModuleCatalog.downloads,
      containsAll([
        SyncModule.shiftWorkers,
        SyncModule.defaultCashFund,
        SyncModule.storeConfig,
      ]),
    );
  });

  test('Ajustes deja solo Manual + por módulos, ambos con catálogo completo', () {
    final settings = File('lib/screens/settings_screen.dart').readAsStringSync();
    final selective =
        File('lib/widgets/selective_sync_dialog.dart').readAsStringSync();
    final connection =
        File('lib/widgets/connection_status_widget.dart').readAsStringSync();

    expect(settings, contains('Sincronización Manual'));
    expect(settings, contains('Sincronizar por módulos'));
    expect(settings, isNot(contains('Forzar Sincronización')));
    expect(settings, contains('SyncModuleCatalog.all'));
    expect(settings, contains('SyncModuleCatalog.offlineReadinessRequired'));

    expect(selective, contains('SyncModuleCatalog.uploads'));
    expect(selective, contains('SyncModuleCatalog.downloads'));
    expect(selective, contains('suspenderModoOffline: true'));

    expect(connection, contains('SyncModuleCatalog.offlineReadinessRequired'));
  });

  test('auto-sync fuerza catálogo si el cache offline está vacío', () {
    final sync = File('lib/services/auto_sync_service.dart').readAsStringSync();
    expect(sync, contains('_offlineCatalogoVacio'));
    expect(
      sync,
      contains('Cache offline sin catálogo → forzando categorías/productos/layouts'),
    );
    expect(sync, contains('Future<Set<SyncModule>> _modulesForAutoSyncPass()'));
    expect(sync, contains('Future<Set<SyncModule>> _modulesForReconnectPass()'));
  });

  test('volver online tras login offline exige sesión Supabase', () {
    final smart =
        File('lib/services/smart_offline_manager.dart').readAsStringSync();
    final reauth =
        File('lib/services/reauthentication_service.dart').readAsStringSync();
    expect(smart, contains('ensureAuthenticated()'));
    expect(
      smart,
      contains('No se pudo restaurar la sesión con el servidor'),
    );
    expect(reauth, contains('hasSession'));
    expect(
      reauth,
      contains('Sin sesión Supabase'),
    );
  });
}
