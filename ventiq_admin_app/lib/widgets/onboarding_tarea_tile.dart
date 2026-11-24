/// Fila del checklist de activación de tienda.
///
/// Fase 3 del plan `docs/plans/alta-tienda-progresiva-go-live.md`. Es una pieza
/// **de presentación pura**: recibe la tarea ya calculada por
/// `models/onboarding_tareas.dart` y un `onTap`, y no consulta nada. Toda la
/// lógica de qué está pendiente, bloqueado o completado vive en el modelo; aquí
/// solo se decide cómo se pinta.
///
/// Reglas de color (GOV.UK, citadas por el plan):
///
/// - `completada`: texto normal sobre blanco, sin fondo de color, con un check
///   verde pequeño al final. Completado no es un estado "bueno" que haya que
///   celebrar a gritos.
/// - `pendiente` y accionable (`ruta != null`): el título en azul y la fila
///   tocable. Azul = hay algo que hacer, no es un error.
/// - `bloqueada` (`motivoBloqueo != null`): gris, **sin enlace**, y el motivo
///   visible debajo. Si el usuario no puede hacer nada todavía, se le dice por
///   qué en vez de dejarle un botón que va a fallar.
/// - pendiente **sin** ruta y sin bloqueo (informativa, p. ej. las mesas, que se
///   crean desde `ventiq_app`): texto normal, sin enlace y sin color de acción.
/// - Rojo: **no se usa aquí**. `EstadoTarea` no tiene estado de error, así que
///   no hay nada que pintar de rojo; el rojo queda reservado para los fallos
///   reales de carga de la pantalla.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';

/// Icono de cada tarea del checklist. La clave es la de `construirTareas`.
const Map<String, IconData> _iconosTarea = {
  'almacen': Icons.warehouse_outlined,
  'zona': Icons.grid_view_outlined,
  'tpv': Icons.point_of_sale_outlined,
  'producto': Icons.inventory_2_outlined,
  'cobro': Icons.badge_outlined,
  'personal': Icons.groups_outlined,
  'cocina': Icons.soup_kitchen_outlined,
  'mesas_restaurante': Icons.table_restaurant_outlined,
  'modo_restaurante': Icons.restaurant_menu,
  'servicentro_tpv': Icons.local_gas_station_outlined,
  'inventario': Icons.inventory,
  'moneda': Icons.currency_exchange,
};

/// Una fila del checklist de activación.
class OnboardingTareaTile extends StatelessWidget {
  const OnboardingTareaTile({
    super.key,
    required this.tarea,
    this.onTap,
    this.icono,
  });

  /// Tarea a pintar, ya resuelta por el modelo.
  final TareaOnboarding tarea;

  /// Se llama al tocar la fila. Solo se usa si la tarea es
  /// [TareaOnboarding.accionable]; para una bloqueada o completada no hay
  /// gesto, aunque el callback venga relleno.
  final VoidCallback? onTap;

  /// Permite sustituir el icono por defecto (el del mapa por clave).
  final IconData? icono;

  /// Clave estable para localizar la fila en pruebas de widget.
  static Key claveTarea(String clave) =>
      ValueKey<String>('onboarding_tarea_$clave');

  IconData get _icono => icono ?? _iconosTarea[tarea.clave] ?? Icons.checklist;

  /// Solo las accionables con callback son tocables. `accionable` ya excluye
  /// las completadas y las que no tienen ruta.
  bool get _tocable => tarea.accionable && onTap != null;

  bool get _completada => tarea.estado == EstadoTarea.completada;

  Color get _colorTitulo {
    if (_completada) return AppColors.textPrimary;
    if (tarea.bloqueada) return AppColors.textSecondary;
    if (_tocable) return AppColors.primary;
    return AppColors.textPrimary;
  }

  Color get _fondoIcono {
    if (_completada) return AppColors.success.withValues(alpha: 0.10);
    if (tarea.bloqueada) return AppColors.border.withValues(alpha: 0.55);
    if (_tocable) return AppColors.primary.withValues(alpha: 0.10);
    return AppColors.surfaceVariant;
  }

  Color get _colorIcono {
    if (_completada) return AppColors.success;
    if (tarea.bloqueada) return AppColors.textLight;
    if (_tocable) return AppColors.primary;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    // Fondo blanco salvo en las bloqueadas, que van sobre gris suave: así se
    // ve de un vistazo que todavía no se puede empezar.
    final fondo = tarea.bloqueada ? AppColors.surfaceVariant : AppColors.surface;

    final cuerpo = DecoratedBox(
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _fondoIcono,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_icono, size: 18, color: _colorIcono),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tarea.titulo,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: _colorTitulo,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tarea.beneficio,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (tarea.motivoBloqueo != null) ...[
                    const SizedBox(height: 8),
                    _motivoBloqueo(tarea.motivoBloqueo!),
                  ],
                ],
              ),
            ),
            if (_completada) ...[
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: AppColors.success,
                ),
              ),
            ] else if (_tocable) ...[
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!_tocable) return cuerpo;

    // El InkWell va por dentro del borde para que el ripple quede recortado por
    // el radio de la tarjeta.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: cuerpo,
      ),
    );
  }

  /// El motivo del bloqueo, a la vista. Nunca un enlace: si la tarea está
  /// bloqueada es porque hoy no hay nada que el usuario pueda hacer.
  Widget _motivoBloqueo(String motivo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline, size: 14, color: AppColors.textLight),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              motivo,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
