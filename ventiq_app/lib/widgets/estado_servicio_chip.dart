import 'package:flutter/material.dart';

import '../models/mesa_cuenta.dart';

/// Estado de servicio de una línea de la cuenta: dónde está el plato ahora.
///
/// Complementa a `CocinaChip` (que vive en el catálogo y habla de
/// disponibilidad). Este chip vive en la NOTA y responde otra pregunta: "¿ya
/// puedo llevarlo a la mesa?".
///
/// Código de colores tomado de los KDS de la industria (Lightspeed documenta
/// "color-coded by status"), pensado para que el mesero decida sin leer:
///
///   En cocina   gris azulado → pedido, nadie lo ha tomado
///   Preparando  índigo       → el cocinero está en ello
///   Listo       verde        → RECÓGELO, está en el pase
///   Entregado   gris tenue   → ya está en la mesa, no requiere acción
///   Servido     ámbar        → porción de tanda, salió de inmediato
///   Cancelado   rojo         → anulado
///
/// El verde es deliberadamente el único color "llamativo": es el que exige una
/// acción del mesero. Los demás son informativos.
class EstadoServicioChip extends StatelessWidget {
  const EstadoServicioChip({
    super.key,
    required this.item,
    this.compacto = false,
    this.mostrarCocina = true,
  });

  final MesaCuentaItem item;

  /// Sin nombre de cocina ni número de comanda: para filas densas.
  final bool compacto;

  final bool mostrarCocina;

  @override
  Widget build(BuildContext context) {
    final etiqueta = item.etiquetaServicio;

    // Producto de barra o línea legado: no hay nada que informar.
    if (etiqueta == null) return const SizedBox.shrink();

    final estilo = _EstiloServicio.para(item);

    final partes = <String>[etiqueta];
    if (!compacto) {
      if (mostrarCocina &&
          item.cocinaNombre != null &&
          item.cocinaNombre!.isNotEmpty) {
        partes.add(item.cocinaNombre!);
      }
      if (item.comandaNumero != null) {
        partes.add('#${item.comandaNumero}');
      }
    }

    return Tooltip(
      message: estilo.explicacion,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 6 : 8,
          vertical: compacto ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: estilo.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: estilo.color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(estilo.icono, size: compacto ? 12 : 14, color: estilo.color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                partes.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compacto ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  color: estilo.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso para la cabecera de la cuenta: cuántos platos están en cocina y
/// cuántos esperan en el pase.
///
/// Se pinta solo si hay algo que decir. El mesero lo usa para saber si puede
/// cerrar la nota o si le falta recoger algo.
class ResumenCocinaBanner extends StatelessWidget {
  const ResumenCocinaBanner({
    super.key,
    required this.cuenta,
    this.onVerPendientes,
  });

  final MesaCuenta cuenta;
  final VoidCallback? onVerPendientes;

  @override
  Widget build(BuildContext context) {
    final resumen = cuenta.resumenCocina;
    if (resumen == null) return const SizedBox.shrink();

    // Si hay platos listos, el aviso es una llamada a la acción (verde).
    // Si solo hay cosas cocinándose, es informativo (índigo).
    final hayListos = cuenta.tienePlatosListos;
    final color = hayListos ? Colors.green.shade700 : Colors.indigo.shade500;
    final icono = hayListos
        ? Icons.room_service_outlined
        : Icons.soup_kitchen_outlined;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  resumen,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  hayListos
                      ? 'Hay platos esperando en el pase'
                      : 'La cocina está preparando el pedido',
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (onVerPendientes != null)
            TextButton(
              onPressed: onVerPendientes,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Ver'),
            ),
        ],
      ),
    );
  }
}

/// Color, icono y explicación de cada estado. Se resuelve en un solo lugar
/// para que el chip de la línea y cualquier otra vista coincidan.
class _EstiloServicio {
  const _EstiloServicio(this.color, this.icono, this.explicacion);

  final Color color;
  final IconData icono;
  final String explicacion;

  static _EstiloServicio para(MesaCuentaItem item) {
    if (item.esDeTanda) {
      return _EstiloServicio(
        Colors.amber.shade800,
        Icons.inventory_2_outlined,
        'Porción ya preparada: se sirvió al pedirla',
      );
    }

    switch (item.estadoServicioEfectivo) {
      case 1:
        return _EstiloServicio(
          Colors.blueGrey.shade600,
          Icons.schedule,
          'Enviado a la cocina, aún no lo han tomado',
        );
      case 2:
        return _EstiloServicio(
          Colors.indigo.shade500,
          Icons.outdoor_grill_outlined,
          'El cocinero lo está preparando',
        );
      case 3:
        return _EstiloServicio(
          Colors.green.shade700,
          Icons.room_service_outlined,
          'Listo en el pase: hay que llevarlo a la mesa',
        );
      case 4:
        return _EstiloServicio(
          Colors.grey.shade600,
          Icons.check_circle_outline,
          'Ya entregado al comensal',
        );
      case 5:
        return _EstiloServicio(
          Colors.red.shade600,
          Icons.block,
          'Cancelado',
        );
      default:
        return _EstiloServicio(
          Colors.blueGrey.shade400,
          Icons.help_outline,
          'Estado desconocido',
        );
    }
  }
}
