import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/reservas_provider.dart';
import '../utils/shell_navegacion.dart';

/// Barra de navegación inferior del **cliente**.
///
/// Es la misma que pinta `HomeShell` para un cliente puro (Inicio, Servicios, Mis
/// Listas, Reservas con badge y Perfil), extraída a un widget para que las vistas
/// apiladas de «Exploración rápida» puedan llevarla también. No es una copia: hay
/// una sola definición de las pestañas del cliente y así no se pueden
/// desincronizar.
///
/// Al tocar, por defecto cierra lo apilado y cambia de pestaña en el shell
/// (`ShellNavegacion.irAPestana`). El shell pasa su propio `onSeleccion` porque él
/// además refresca la pestaña que se abre.
class BarraNavegacionCliente extends StatelessWidget {
  const BarraNavegacionCliente({
    super.key,
    this.indiceActivo = ShellNavegacion.inicio,
    this.onSeleccion,
    this.mostrarBadgeReservas = true,
    this.pendientesReservas,
  });

  /// Pestaña que se pinta como activa.
  ///
  /// En una pantalla apilada es **Inicio**: las cuatro vistas nuevas cuelgan del
  /// Home (la rejilla, la tarjeta de categorías, la de establecimientos…), así que
  /// marcar otra pestaña diría que estás en un sitio en el que no estás.
  final int indiceActivo;

  /// Qué hacer al tocar. `null` = volver al shell y cambiar de pestaña.
  final ValueChanged<int>? onSeleccion;

  /// En el shell del vendedor el badge de reservas no se muestra.
  final bool mostrarBadgeReservas;

  /// Reservas activas para el badge. `null` = se leen del [ReservasProvider]
  /// (uso normal). El shell pasa el número que ya tiene calculado y los tests
  /// pueden inyectarlo sin levantar el provider, que necesita sesión.
  final int? pendientesReservas;

  /// Barra para una pantalla apilada, o `null` si no hay shell detrás.
  ///
  /// Se usa directo en `bottomNavigationBar`, que admite `null`:
  /// `bottomNavigationBar: BarraNavegacionCliente.dePantalla()`.
  static Widget? dePantalla({int indiceActivo = ShellNavegacion.inicio}) {
    if (!ShellNavegacion.disponible) return null;
    return BarraNavegacionCliente(indiceActivo: indiceActivo);
  }

  @override
  Widget build(BuildContext context) {
    // `select` para que el badge se repinte solo cuando cambia el número de
    // reservas activas. El provider vive en la raíz de la app, así que también
    // está disponible en una ruta apilada.
    final pendientes =
        pendientesReservas ??
        context.select<ReservasProvider, int>((p) => p.pendientes);

    return NavigationBar(
      selectedIndex: indiceActivo,
      onDestinationSelected: (indice) {
        final callback = onSeleccion;
        if (callback != null) {
          callback(indice);
          return;
        }
        ShellNavegacion.irAPestana(context, indice);
      },
      backgroundColor: Colors.white,
      indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primary),
          label: 'Inicio',
        ),
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view, color: AppTheme.primary),
          label: 'Servicios',
        ),
        const NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt, color: AppTheme.primary),
          label: 'Mis Listas',
        ),
        NavigationDestination(
          icon: IconoReservaConBadge(
            pendientes: pendientes,
            showBadge: mostrarBadgeReservas,
          ),
          selectedIcon: IconoReservaConBadge(
            pendientes: pendientes,
            showBadge: mostrarBadgeReservas,
            selected: true,
          ),
          label: 'Reservas',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outlined),
          selectedIcon: Icon(Icons.person, color: AppTheme.primary),
          label: 'Perfil',
        ),
      ],
    );
  }
}

/// Icono de la pestaña «Reservas»: el número de reservas activas como badge.
///
/// Vivía dentro de `home_shell.dart`; se movió aquí al extraer la barra, porque
/// ahora lo usan las dos (la del shell y la de las pantallas apiladas).
class IconoReservaConBadge extends StatelessWidget {
  final bool showBadge;
  final bool selected;

  /// Reservas activas del usuario. El badge solo aparece si hay alguna.
  final int pendientes;

  const IconoReservaConBadge({
    super.key,
    this.showBadge = false,
    this.selected = false,
    this.pendientes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final mostrar = showBadge && pendientes > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          selected
              ? Icons.confirmation_number
              : Icons.confirmation_number_outlined,
          color: selected ? AppTheme.primary : null,
        ),
        if (mostrar)
          Positioned(
            right: -8,
            top: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 15),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  pendientes > 99 ? '99+' : '$pendientes',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}