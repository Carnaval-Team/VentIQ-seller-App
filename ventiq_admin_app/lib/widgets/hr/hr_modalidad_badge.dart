import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_salary_type.dart';

/// Distintivo compacto de la modalidad de pago de un trabajador (HORA / DÍA).
///
/// Se usa en tablas, listas y fichas para que quede claro de dónde sale su
/// importe, sobre todo cuando la plantilla es mixta.
class HRModalidadBadge extends StatelessWidget {
  final TipoSalario tipoSalario;
  final double fontSize;

  const HRModalidadBadge({
    super.key,
    required this.tipoSalario,
    this.fontSize = 9,
  });

  @override
  Widget build(BuildContext context) {
    // Por día en primario, por hora en gris: la modalidad nueva resalta sin
    // que la histórica genere ruido visual en pantallas llenas de datos.
    final color =
        tipoSalario.esPorDia ? AppColors.primary : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        tipoSalario.badge,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
