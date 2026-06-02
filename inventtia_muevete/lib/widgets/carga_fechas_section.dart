import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/carga_model.dart';

/// Fechas y ventanas horarias de recogida/entrega en el detalle de carga.
class CargaFechasSection extends StatelessWidget {
  final CargaModel carga;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const CargaFechasSection({
    super.key,
    required this.carga,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasRecogida = carga.fechaRecogida != null ||
        carga.ventanaRecogidaDisplay != null;
    final hasEntrega = carga.fechaEntrega != null ||
        carga.ventanaEntregaDisplay != null;

    if (!hasRecogida && !hasEntrega) return const SizedBox.shrink();

    final rows = <Widget>[];

    void addRow(Widget row) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(row);
    }

    if (carga.fechaRecogida != null) {
      addRow(_CargaFechaRow(
        icon: Icons.calendar_today_outlined,
        label: 'Fecha de recogida',
        value: _fmtDate(carga.fechaRecogida!),
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final horarioCarga = carga.ventanaRecogidaDisplay;
    if (horarioCarga != null) {
      addRow(_CargaFechaRow(
        icon: Icons.access_time_outlined,
        label: 'Horario de carga',
        value: horarioCarga,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.fechaEntrega != null) {
      addRow(_CargaFechaRow(
        icon: Icons.event_available_outlined,
        label: 'Fecha de entrega',
        value: _fmtDate(carga.fechaEntrega!),
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final horarioDescarga = carga.ventanaEntregaDisplay;
    if (horarioDescarga != null) {
      addRow(_CargaFechaRow(
        icon: Icons.access_time_filled_outlined,
        label: 'Horario de descarga',
        value: horarioDescarga,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(children: rows),
    );
  }
}

class _CargaFechaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;

  const _CargaFechaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
