import 'package:flutter/material.dart';
import '../models/mesa_cuenta.dart';
import '../services/mesa_cuenta_service.dart';
import '../services/sales_mode_service.dart';
import '../services/user_preferences_service.dart';

/// Helper centralizado para decisiones de navegación que dependen de banderas
/// globales (modo restaurante, cuenta activa, etc.). Consolidar la lógica
/// aquí evita duplicarla en cada `_onBottomNavTap` de las pantallas.
class NavigationHelper {
  NavigationHelper._();

  /// Destino home según rol de sesión y modo restaurante.
  ///
  /// Orden de prioridad:
  ///  1. Gerente/supervisor (solo gestión) → `/admin-home`.
  ///  2. **Personal de cocina** (jefe o cocinero) → `/kds`. Su trabajo es la
  ///     pantalla de cocina; el catálogo de venta no le sirve de nada y le
  ///     obligaba a abrir el drawer en cada arranque.
  ///  3. Modo restaurante → `/mesas`.
  ///  4. Resto → `/categories`.
  ///
  /// El orden importa: un gerente que además tenga cocinas asignadas sigue
  /// yendo a administración, porque su rol de entrada es la gestión de la
  /// tienda. Solo va al KDS quien entra *por* su rol de cocina.
  ///
  /// Durante una venta de mostrador el Home es `/categories`: el vendedor está
  /// en una venta normal y sacarlo a `/mesas` le rompe el flujo.
  static Future<String> homeRoute() async {
    final prefs = UserPreferencesService();

    final inventoryOnly = await prefs.isInventoryOnlySession();
    if (inventoryOnly) return '/admin-home';

    if (await prefs.isCocinaSession()) return '/kds';

    return SalesModeService.flujoMesaActivo ? '/mesas' : '/categories';
  }

  /// Navega al "Home" según el contexto:
  ///
  ///  - Sesión gerente/supervisor → `/admin-home` (sin venta).
  ///  - Si modo restaurante **está activado**, va a `/mesas`.
  ///  - Si no, va a `/categories`.
  static Future<void> goHome(BuildContext context, {bool removeStack = true}) async {
    final route = await homeRoute();

    if (!context.mounted) return;
    if (removeStack) {
      await Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    } else {
      await Navigator.pushNamed(context, route);
    }
  }

  /// Destino del botón de carrito (índice 1 de la barra inferior).
  ///
  /// EN MODO NORMAL va a `/preorder`, el carrito local de siempre.
  ///
  /// EN EL FLUJO DE MESA la preorden local no se usa: el carrito vive en BD por
  /// mesa (`app_dat_mesa_cuenta_item`), así que `/preorder` sale vacía y el
  /// mesero tiene que ir a Mesas → buscar la mesa → entrar a la cuenta. Se
  /// atajan esos tres toques:
  ///
  ///  1. Si hay una cuenta marcada como activa en memoria, va directo a ella.
  ///  2. Si no, se pregunta al backend por la última cuenta abierta del TPV
  ///     (`fn_ultima_cuenta_abierta_tpv`, la más reciente por `updated_at`).
  ///  3. Si no hay ninguna abierta, va a `/mesas` para que elija mesa. Ir a una
  ///     preorden vacía no le sirve de nada.
  ///
  /// Ante cualquier fallo cae a `/mesas`: es el destino útil en restaurante.
  ///
  /// En una venta de mostrador se toma la rama normal (`/preorder`) aunque la
  /// tienda sea de restaurante: no hay mesa que consultar.
  static Future<void> goCarrito(BuildContext context) async {
    if (!SalesModeService.flujoMesaActivo) {
      Navigator.popUntil(context, (route) => route.isFirst);
      await Navigator.pushNamed(context, '/preorder');
      return;
    }

    final servicio = MesaCuentaService();

    // 1. Cuenta ya activa en esta sesión: el caso más común mientras se atiende.
    final activa = servicio.activeCuentaId;
    if (activa != null) {
      Navigator.popUntil(context, (route) => route.isFirst);
      if (!context.mounted) return;
      await Navigator.pushNamed(context, '/cuenta-mesa', arguments: activa);
      return;
    }

    // 2. La última que se tocó, aunque haya sido en otro dispositivo o antes de
    //    reiniciar la app.
    final ultima = await servicio.ultimaCuentaAbierta();

    if (!context.mounted) return;

    if (ultima != null) {
      servicio.setActive(
        idCuenta: ultima.idCuenta,
        idMesa: ultima.idMesa,
        mesaNumero: ultima.mesaNumero,
        mesaZona: ultima.mesaZona,
      );

      Navigator.popUntil(context, (route) => route.isFirst);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cuenta abierta de ${ultima.etiquetaMesa}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await Navigator.pushNamed(
        context,
        '/cuenta-mesa',
        arguments: ultima.idCuenta,
      );
      return;
    }

    // 3. Sin cuentas abiertas: a elegir mesa.
    Navigator.popUntil(context, (route) => route.isFirst);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No hay cuentas abiertas. Elige una mesa.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await Navigator.pushNamed(context, '/mesas');
  }

  /// Resumen de la última cuenta abierta, para etiquetar el botón.
  ///
  /// `null` en modo normal o si no hay ninguna: quien llama deja el texto
  /// "Preorden" de siempre.
  static Future<UltimaCuentaAbierta?> cuentaParaBotonCarrito() async {
    if (!SalesModeService.flujoMesaActivo) return null;
    return MesaCuentaService().ultimaCuentaAbierta();
  }
}
