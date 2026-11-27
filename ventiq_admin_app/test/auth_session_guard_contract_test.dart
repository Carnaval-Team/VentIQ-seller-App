import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato: crear/vincular usuarios Auth no debe dejar al admin en otra sesión.
void main() {
  final authService = File('lib/services/auth_service.dart').readAsStringSync();
  final workers = File('lib/screens/workers_screen.dart').readAsStringSync();
  final carnaval = File('lib/services/carnaval_service.dart').readAsStringSync();
  final storeReg =
      File('lib/services/store_registration_service.dart').readAsStringSync();

  test('AuthService no usa credenciales de recordarme para autenticar', () {
    expect(authService, isNot(contains('_tryReauthenticateFromRememberMe')));
    expect(authService, isNot(contains('getSavedCredentials')));
    expect(authService, isNot(contains('shouldRememberMe')));
  });

  test('AuthService expone createOrLinkAuthUser con runWithSessionGuard', () {
    expect(authService, contains('createOrLinkAuthUser'));
    expect(authService, contains('runWithSessionGuard'));
    expect(authService, contains('restoreAdminSession'));
    // El guard debe capturar la sesión previa y restaurarla en finally.
    expect(authService, contains('priorUserId'));
    expect(authService, contains('priorJson'));
  });

  test('workers usa createOrLinkAuthUser / _resolverUsuarioAcceso', () {
    expect(workers, contains('AuthService.createOrLinkAuthUser'));
    expect(workers, contains('_resolverUsuarioAcceso'));
    // El camino legacy ya no hace signUp directo en _createWorkerWithRegistration.
    final legacyBlock = RegExp(
      r'_createWorkerWithRegistration[\s\S]*?signUp\(',
    );
    expect(legacyBlock.hasMatch(workers), isFalse);
  });

  test('carnaval addRepartidor no hace signUp directo', () {
    final start = carnaval.indexOf(
      'static Future<Map<String, dynamic>> addRepartidor',
    );
    expect(start, greaterThanOrEqualTo(0));
    final end = carnaval.indexOf('getPaqueteriaOrdersByTienda', start);
    final body = carnaval.substring(start, end);
    expect(body.contains('.auth.signUp('), isFalse);
    expect(body.contains('createOrLinkAuthUser'), isTrue);
  });

  test('store registration resolveAccessUser usa createOrLinkAuthUser', () {
    expect(storeReg, contains('AuthService.createOrLinkAuthUser'));
  });
}
