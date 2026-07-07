import 'package:flutter/material.dart';
import '../models/campo_adicional.dart';

/// Muestra los valores de datos adicionales de una reserva como filas
/// etiqueta → valor. Si recibe los [campos] del servicio, usa sus etiquetas;
/// en caso contrario rotula con la clave cruda.
class DatosAdicionalesView extends StatelessWidget {
  final Map<String, dynamic>? valores;
  final List<CampoAdicional> campos;
  final bool dense;

  const DatosAdicionalesView({
    super.key,
    required this.valores,
    this.campos = const [],
    this.dense = false,
  });

  String _etiqueta(String clave) {
    for (final c in campos) {
      if (c.clave == clave) return c.etiqueta;
    }
    return clave;
  }

  @override
  Widget build(BuildContext context) {
    final v = valores;
    if (v == null || v.isEmpty) return const SizedBox.shrink();

    // Ordena según el orden de los campos del servicio; las claves sin campo van al final.
    final claves = <String>[
      ...campos.map((c) => c.clave).where(v.containsKey),
      ...v.keys.where((k) => !campos.any((c) => c.clave == k)),
    ];

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final k in claves)
          Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 1 : 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_etiqueta(k)}: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.7),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${v[k]}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
