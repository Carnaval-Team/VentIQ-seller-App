import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/carga_model.dart';

/// Sección reutilizable de mercancía/equipo en el detalle de carga.
class CargaMercanciaEquipoSection extends StatelessWidget {
  final CargaModel carga;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final String? precioLabel;

  const CargaMercanciaEquipoSection({
    super.key,
    required this.carga,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    this.precioLabel,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    void addRow(Widget row) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(row);
    }

    if (carga.descripcion != null) {
      addRow(_CargaInfoRow(
        icon: Icons.description_outlined,
        label: 'Descripción',
        value: carga.descripcion!,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final mercancia = carga.tipoMercanciaDisplay;
    if (mercancia != null) {
      addRow(_CargaInfoRow(
        icon: Icons.category_outlined,
        label: 'Mercancía',
        value: mercancia,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.commodityNomNombre != null) {
      addRow(_CargaInfoRow(
        icon: Icons.inventory_2_outlined,
        label: 'Commodity',
        value: carga.commodityNomNombre!,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final peso = carga.pesoDisplay;
    if (peso != null) {
      addRow(_CargaInfoRow(
        icon: Icons.scale_outlined,
        label: 'Peso',
        value: peso,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final medidas = carga.medidasDisplay;
    if (medidas != null) {
      addRow(_CargaInfoRow(
        icon: Icons.straighten_outlined,
        label: 'Medidas (L × A × H)',
        value: medidas,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.volumenM3 != null) {
      addRow(_CargaInfoRow(
        icon: Icons.view_in_ar_outlined,
        label: 'Volumen',
        value: '${carga.volumenM3!.toStringAsFixed(2)} m³',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    final equipo = carga.tipoEquipoDisplay;
    if (equipo != null) {
      addRow(_CargaInfoRow(
        icon: Icons.local_shipping_outlined,
        label: 'Equipo',
        value: equipo,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.opcionesEquipoManejoNombres.isNotEmpty ||
        carga.opcionesEquipoManejoCodigos.isNotEmpty) {
      addRow(_CargaInfoRow(
        icon: Icons.build_outlined,
        label: 'Opciones equipo',
        value: carga.opcionesEquipoDisplay,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (precioLabel != null && carga.precioOfertado != null) {
      addRow(_CargaInfoRow(
        icon: Icons.attach_money_outlined,
        label: precioLabel!,
        value:
            '\$${carga.precioOfertado!.toStringAsFixed(2)} ${carga.moneda}',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.requiereRefrigeracion) {
      addRow(_CargaInfoRow(
        icon: Icons.ac_unit_outlined,
        label: 'Refrigeración',
        value: carga.temperaturaMin != null && carga.temperaturaMax != null
            ? 'Requerida (${carga.temperaturaMin}° – ${carga.temperaturaMax}°)'
            : 'Requerida',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.requiereSeguro) {
      addRow(_CargaInfoRow(
        icon: Icons.shield_outlined,
        label: 'Seguro',
        value: 'Requerido',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.horasCarga != null) {
      addRow(_CargaInfoRow(
        icon: Icons.timer_outlined,
        label: 'Horas de carga',
        value: '${carga.horasCarga!.toStringAsFixed(1)} h',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.horasDescarga != null) {
      addRow(_CargaInfoRow(
        icon: Icons.timer_off_outlined,
        label: 'Horas de descarga',
        value: '${carga.horasDescarga!.toStringAsFixed(1)} h',
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (carga.instrucciones != null) {
      addRow(_CargaInfoRow(
        icon: Icons.note_outlined,
        label: 'Instrucciones',
        value: carga.instrucciones!,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return _CargaInfoCard(isDark: isDark, children: rows);
  }
}

class _CargaInfoCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _CargaInfoCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _CargaInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;

  const _CargaInfoRow({
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
