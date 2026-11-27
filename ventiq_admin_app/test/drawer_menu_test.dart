import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_admin_app/services/user_preferences_service.dart';
import 'package:ventiq_admin_app/services/drawer_menu_service.dart';
import 'package:ventiq_admin_app/services/permissions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cambiar tienda invalida el menú, repetir la tienda no', () async {
    SharedPreferences.setMockInitialValues({'id_tienda': 1});
    final generation = DrawerMenuService.changes.value;
    await UserPreferencesService().updateSelectedStore(1);
    expect(DrawerMenuService.changes.value, generation);
    await UserPreferencesService().updateSelectedStore(2);
    expect(DrawerMenuService.changes.value, generation + 1);
  });

  test('cerrar sesión descarta el menú', () async {
    SharedPreferences.setMockInitialValues({'id_tienda': 1});
    final generation = DrawerMenuService.changes.value;
    await UserPreferencesService().clearUserData();
    expect(DrawerMenuService.changes.value, generation + 1);
    expect(await UserPreferencesService().getIdTienda(), isNull);
  });

  test('invalidar descarta opciones y rol de la sesión anterior', () {
    final generation = DrawerMenuService.changes.value;
    DrawerMenuService.invalidate();
    expect(DrawerMenuService.role, UserRole.none);
    expect(DrawerMenuService.visible('/products'), isFalse);
    expect(DrawerMenuService.visible('restaurante'), isFalse);
    expect(DrawerMenuService.changes.value, generation + 1);
  });

  test('ninguna pantalla monta el drawer a la izquierda', () {
    final leftDrawer = RegExp(r'\bdrawer\s*:|\bopenDrawer\s*\(');
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final code = source.split('\n').where((line) => !line.trimLeft().startsWith('//')).join('\n');
      expect(leftDrawer.hasMatch(code), isFalse, reason: file.path);
    }
  });

  test('drawer usa decisiones precargadas sin consultas remotas en build', () {
    final source = File('lib/widgets/admin_drawer.dart').readAsStringSync();
    final build = source.substring(source.indexOf('Widget build(BuildContext context)'));
    expect(build, isNot(contains('NavigationGuard.canNavigate(')));
    expect(build, isNot(contains('future: PermissionsService()')));
    expect(source, contains('SynchronousFuture(DrawerMenuService.visible(route))'));
    expect(source, contains('DrawerMenuService.changes.removeListener'));
    for (final match in RegExp(r"_cachedCanNavigate\(\s*'([^']+)'").allMatches(build)) {
      expect(DrawerMenuService.routes, contains(match.group(1)));
    }
  });

  test('login normal, automático y selector preparan las opciones', () {
    final login = File('lib/screens/login_screen.dart').readAsStringSync();
    expect('await DrawerMenuService.prepare()'.allMatches(login).length, 2);
    for (final path in [
      'lib/screens/store_selection_screen.dart',
      'lib/services/store_selector_service.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('await DrawerMenuService.prepare()'));
    }
  });
}
