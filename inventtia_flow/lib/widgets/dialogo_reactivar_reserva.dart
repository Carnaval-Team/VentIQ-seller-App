import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../utils/reactivar_reserva.dart';
import '../utils/reserva_listado.dart';

/// Diálogo para reactivar una reserva cancelada eligiendo **en qué estado**
/// queda: pendiente (Reservado) o completada.
///
/// ANTES
///   El botón «Reactivar» solo pedía confirmación y mandaba siempre estado
///   Reservado. Desde que el servidor solo aceptaba Cancelado o Completado, ese
///   toque terminaba en un error («Estado destino no permitido»).
///
/// AHORA
///   Se ofrecen **solo** las opciones que el servidor va a aceptar para esa
///   reserva (ver [destinosReactivacion]) y, cuando una no se puede, se explica
///   por qué en vez de esconderla sin más. El botón de cada opción es el que
///   decide: no hay un «sí» genérico que adivine el estado.
///
/// Devuelve el destino elegido, o `null` si el usuario cierra.
Future<DestinoReactivacion?> mostrarDialogoReactivarReserva(
  BuildContext context, {
  required ReservaListItem item,
  DateTime? ahora,
}) {
  final reserva = item.principal;
  final destinos = destinosReactivacion(reserva, ahora: ahora);
  final noDisponibles = DestinoReactivacion.values
      .where((d) => !destinos.contains(d))
      .toList(growable: false);

  final cliente = reserva.cliente?.nombreCompleto.trim();
  final servicio = reserva.localServicio?.servicio?.nombre?.trim();

  return showDialog<DestinoReactivacion>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.restart_alt_rounded, color: AppTheme.primary, size: 22),
          SizedBox(width: 8),
          Text('Reactivar reserva'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reserva de ${(cliente == null || cliente.isEmpty) ? 'este cliente' : cliente}'
              '${(servicio == null || servicio.isEmpty) ? '' : ' para el servicio $servicio'}'
              ' del ${_fechaCorta(reserva.fechaHoraReserva)}.',
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            if (item.esIdaVueltaMismoDia)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Se reactivarán ambos tramos (ida y regreso).',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            if (destinos.isEmpty)
              Text(
                motivoSinOpciones(reserva, ahora: ahora),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                ),
              )
            else ...[
              const Text(
                '¿En qué estado la dejamos?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              for (final destino in destinos) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, destino),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(destino.etiqueta),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destino.ayuda,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            for (final destino in noDisponibles)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '«${destino.etiqueta}»: ${motivoNoDisponible(destino, reserva, ahora: ahora)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

String _fechaCorta(DateTime fecha) {
  final dia = fecha.day.toString().padLeft(2, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  return '$dia/$mes/${fecha.year}';
}
