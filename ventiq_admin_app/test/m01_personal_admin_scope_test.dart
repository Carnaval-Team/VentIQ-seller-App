import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/services/permissions_service.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  const adminOnlyActions = [
    'worker.create',
    'worker.edit',
    'worker.delete',
    'tpv.create',
    'tpv.edit',
    'tpv.delete',
    'tpv_price.create',
    'tpv_price.edit',
    'tpv_price.delete',
    'tpv_price.restore',
    'tpv_price.import',
    'vendor.assign_tpv',
    'vendor.unassign_tpv',
    'vendor.create',
    'vendor.delete',
    'vendor.edit_price_permission',
    'settings.edit',
  ];

  test('contrato M01: personal, TPV y vendedores solo administracion', () {
    for (final action in adminOnlyActions) {
      expect(
        src,
        contains("'$action': [UserRole.gerente]"),
        reason:
            '$action debe quedar restringida a gerente '
            '(dueno tiene bypass y superadmin full se valida en servidor)',
      );
    }
  });

  test('contrato M01: supervisor conserva lectura en esos flujos', () {
    for (final screen in [
      '/workers',
      '/tpv-management',
      '/vendor-management',
    ]) {
      final block = src.substring(
        src.indexOf("'$screen'"),
        src.indexOf('],', src.indexOf("'$screen'")),
      );
      expect(block, contains('UserRole.supervisor'), reason: screen);
      expect(block, contains('UserRole.auditor'), reason: screen);
    }

    final workerView = src.substring(
      src.indexOf("'worker.view'"),
      src.indexOf('],', src.indexOf("'worker.view'")),
    );
    expect(workerView, contains('UserRole.supervisor'));
    expect(workerView, contains('UserRole.recursosHumanos'));
  });

  test(
    'contrato M01: recursos humanos conserva solo capacidades de nomina',
    () {
      for (final action in [
        'hr.checkin',
        'hr.checkout',
        'hr.salary_report',
        'hr.worker_config',
        'hr.dashboard',
      ]) {
        final block = src.substring(
          src.indexOf("'$action'"),
          src.indexOf('],', src.indexOf("'$action'")),
        );
        expect(block, contains('UserRole.recursosHumanos'), reason: action);
      }

      final workerCreate = src.substring(
        src.indexOf("'worker.create'"),
        src.indexOf('],', src.indexOf("'worker.create'")),
      );
      expect(workerCreate, isNot(contains('UserRole.recursosHumanos')));
    },
  );
}
