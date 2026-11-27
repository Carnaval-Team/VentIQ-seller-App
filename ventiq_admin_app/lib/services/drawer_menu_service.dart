import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'carnaval_service.dart';
import 'cocina_service.dart';
import 'onboarding_service.dart';
import 'permissions_service.dart';
import 'subscription_guard_service.dart';
import 'subscription_service.dart';
import 'user_preferences_service.dart';

class DrawerMenuService {
  static final changes = ValueNotifier<int>(0);
  static Map<String, bool> _entries = const {};
  static UserRole _role = UserRole.none;
  static UserRole get role => _role;
  static String? _key;
  static Future<void>? _loading;
  static int _generation = 0;

  static const routes = [
    '/products', '/marketing-dashboard', '/sales', '/financial',
    '/crm-dashboard', '/cuentas-por-cobrar', '/fondo-inversion',
    '/compras', '/compras/pendientes', '/compras/facturas',
    '/reportes', '/workers', '/hr-dashboard', '/settings',
  ];

  static bool visible(String entry) => _entries[entry] ?? false;

  static void invalidate() {
    _generation++;
    _key = null;
    _loading = null;
    _entries = const {};
    _role = UserRole.none;
    changes.value++;
  }

  static Future<void> prepare() async {
    final prefs = UserPreferencesService();
    final storeId = await prefs.getIdTienda();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || storeId == null) {
      invalidate();
      return;
    }
    final key = '$userId:$storeId';
    if (_key == key) {
      await _loading;
      return;
    }
    invalidate();
    _key = key;
    final generation = _generation;
    _loading = _load(storeId, generation);
    await _loading;
  }

  static Future<void> _load(int storeId, int generation) async {
    final permissions = PermissionsService();
    final guard = SubscriptionGuardService();
    final entries = <String, bool>{};
    final userRole = await permissions.getUserRoleForStore(storeId);
    Future<void> resolve(String key, Future<bool> Function() load) async {
      try {
        entries[key] = await load();
      } catch (_) {
        entries[key] = false;
      }
    }
    final hasSubscription = await guard.hasActiveSubscription();
    await Future.wait([
      for (final route in routes)
        resolve(route, () async =>
            (guard.isRouteAllowedWithoutSubscription(route) || hasSubscription) &&
            await permissions.canAccessScreen(route)),
      resolve('borrador', () async =>
          (await OnboardingService().leerEstadoTienda()).estadoOnboarding == 'borrador'),
      resolve('restaurante', () async =>
          (await CocinaService.leerConfigCocina()).modoRestaurante),
      resolve('carnaval', () => CarnavalService.isStoreSyncedWithCarnaval(storeId)),
      resolve('hrPro', () => SubscriptionService().hasProPlanInAnyStore()),
    ]);
    if (generation != _generation) return;
    _role = userRole;
    _entries = Map.unmodifiable(entries);
    changes.value++;
  }
}
