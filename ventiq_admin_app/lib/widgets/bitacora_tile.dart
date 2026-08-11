import 'package:flutter/material.dart';

/// Una fila de la bitácora de capitán (`carnavalapp.v_bitacora_capitan`).
///
/// La usan igual el detalle de la orden y la pantalla de bitácora completa, así
/// que un cambio de presentación se hace en un solo sitio.
///
/// Cada fila responde: quién, qué hizo, cuándo, cuánto y por qué; y si el
/// movimiento llegó o no al inventario de Inventtia.
class BitacoraTile extends StatelessWidget {
  final Map<String, dynamic> row;

  /// En la pantalla de bitácora completa hace falta ver a qué orden pertenece.
  /// En el detalle de la orden es redundante.
  final bool showOrderId;

  const BitacoraTile({
    Key? key,
    required this.row,
    this.showOrderId = false,
  }) : super(key: key);

  // --------------------------------------------------------------------------
  // Presentación por acción. `accion` es el valor crudo de la tabla, no el
  // texto traducido, para que no dependa del idioma de la vista.
  // --------------------------------------------------------------------------
  static const List<Map<String, String>> acciones = [
    {'valor': 'aumento', 'texto': 'Añadió producto'},
    {'valor': 'disminucion', 'texto': 'Quitó producto'},
    {'valor': 'eliminacion', 'texto': 'Eliminó la línea'},
    {'valor': 'cambio_precio', 'texto': 'Cambió el precio'},
    {'valor': 'ajuste_sistema', 'texto': 'Ajuste del sistema'},
  ];

  static Color colorDeAccion(String? accion) {
    switch (accion) {
      case 'aumento':
        return Colors.orange.shade700;
      case 'disminucion':
        return Colors.blue.shade700;
      case 'eliminacion':
        return Colors.red.shade700;
      case 'cambio_precio':
        return Colors.purple.shade700;
      case 'ajuste_sistema':
        return Colors.grey.shade600;
      default:
        return Colors.blueGrey;
    }
  }

  static IconData iconoDeAccion(String? accion) {
    switch (accion) {
      case 'aumento':
        return Icons.add_circle_outline;
      case 'disminucion':
        return Icons.remove_circle_outline;
      case 'eliminacion':
        return Icons.delete_outline;
      case 'cambio_precio':
        return Icons.sell_outlined;
      case 'ajuste_sistema':
        return Icons.settings_suggest_outlined;
      default:
        return Icons.history;
    }
  }

  /// Fecha/hora en local, en el mismo formato que el resto de la app.
  static String formatFecha(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Cantidades: llegan como `numeric`, así que pueden venir con decimales.
  /// Se quita el `.0` cuando son enteras.
  static String formatCantidad(dynamic value) {
    final n = (value as num?)?.toDouble();
    if (n == null) return '-';
    if (n == n.truncateToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  static String _formatDinero(dynamic value, {bool conSigno = false}) {
    final n = (value as num?)?.toDouble();
    if (n == null) return '-';
    final signo = conSigno && n > 0 ? '+' : (n < 0 ? '-' : '');
    return '$signo\$${n.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final accion = row['accion'] as String?;
    final color = colorDeAccion(accion);
    final queHizo = row['que_hizo'] as String? ?? accion ?? 'Cambio';
    final producto = (row['producto_nombre'] as String?)?.trim();
    final quien = (row['quien'] as String?)?.trim();
    final actorTipo = (row['actor_tipo'] as String?)?.trim();
    final motivo = (row['motivo'] as String?)?.trim();
    final nota = (row['nota'] as String?)?.trim();
    final erpError = (row['erp_error'] as String?)?.trim();
    final aplicado = row['aplicado_erp'] == true;

    final delta = (row['delta'] as num?)?.toDouble();
    final cantAnt = row['cantidad_anterior'];
    final cantNueva = row['cantidad_nueva'];
    final importeDelta = (row['importe_delta'] as num?)?.toDouble();

    // Encabezado del delta a la derecha: lo que se movió, de un vistazo.
    String? deltaLabel;
    if (delta != null && delta != 0) {
      final signo = delta > 0 ? '+' : '-';
      deltaLabel = '$signo${formatCantidad(delta.abs())} uds';
    }

    final subtitulo = <String>[
      formatFecha(row['created_at'] as String?),
      if (quien != null && quien.isNotEmpty)
        actorTipo != null && actorTipo.isNotEmpty && actorTipo != 'desconocido'
            ? '$quien ($actorTipo)'
            : quien,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(iconoDeAccion(accion), size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showOrderId
                          ? 'Orden #${row['order_id']} · $queHizo'
                          : queHizo,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (producto != null && producto.isNotEmpty)
                      Text(
                        producto,
                        style: const TextStyle(fontSize: 13),
                      ),
                    Text(
                      subtitulo,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (deltaLabel != null)
                Text(
                  deltaLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Cantidades y dinero
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              [
                '${formatCantidad(cantAnt)} → ${formatCantidad(cantNueva)} uds',
                if (importeDelta != null && importeDelta != 0)
                  _formatDinero(importeDelta, conSigno: true),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
          ),
          if (motivo != null && motivo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                'Motivo: $motivo',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (nota != null && nota.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                nota,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          // Traza del inventario: si no se aplicó, hay que revisarlo a mano.
          if (!aplicado)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      erpError != null && erpError.isNotEmpty
                          ? 'No se ajustó el inventario: $erpError'
                          : 'No se ajustó el inventario de Inventtia',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (row['inventario_antes'] != null ||
              row['inventario_despues'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(
                'Inventario: ${formatCantidad(row['inventario_antes'])}'
                ' → ${formatCantidad(row['inventario_despues'])}'
                '${row['id_operacion_ajuste'] != null ? ' · operación #${row['id_operacion_ajuste']}' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.green[800]),
              ),
            ),
        ],
      ),
    );
  }
}
