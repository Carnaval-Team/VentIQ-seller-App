import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/dashboard_service.dart';

void main() {
  group('dashboard direct store roles', () {
    for (final role in ['Dueño', 'dueno', ' DUEÑO ', 'Gerente']) {
      test('$role no depende de pertenecer a la tabla de supervisores', () {
        expect(DashboardService.hasDirectStoreRole([role]), isTrue);
      });
    }

    test('otros roles conservan la comprobación de supervisor', () {
      for (final roles in <List<String>>[
        [], ['Supervisor'], ['Auditor'], ['Vendedor'], ['Almacenero'], ['none'],
      ]) {
        expect(DashboardService.hasDirectStoreRole(roles), isFalse);
      }
    });
  });
}
