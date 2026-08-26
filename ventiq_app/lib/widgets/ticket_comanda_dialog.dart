import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/comanda_ticket_service.dart';

/// Vista del ticket de cocina cuando no se puede (o no se quiere) imprimir.
///
/// Se muestra en tres casos:
///   * la cocina no tiene impresora configurada (lo normal en una cocina
///     pequeña donde el KDS ES la pantalla);
///   * la impresora no responde;
///   * el cocinero quiere verlo antes de mandarlo al papel.
///
/// El texto se pinta en monoespaciada respetando el formato del backend: es el
/// mismo contenido que saldría por la térmica, así lo que se lee en pantalla y
/// lo que sale en papel no divergen nunca.
class TicketComandaDialog extends StatelessWidget {
  const TicketComandaDialog({
    super.key,
    required this.resultado,
    this.onReintentar,
  });

  final ResultadoImpresionTicket resultado;

  /// Volver a intentar imprimir. Null oculta el botón.
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final ticket = resultado.ticket;

    final (Color color, IconData icono, String titulo) = switch (resultado.estado) {
      EstadoImpresion.impreso => (
          Colors.green.shade700,
          Icons.print_outlined,
          'Ticket impreso'
        ),
      EstadoImpresion.sinImpresora => (
          Colors.blueGrey.shade600,
          Icons.receipt_long_outlined,
          'Ticket de cocina'
        ),
      EstadoImpresion.impresoraNoEncontrada => (
          Colors.amber.shade800,
          Icons.print_disabled_outlined,
          'Impresora no encontrada'
        ),
      _ => (Colors.red.shade700, Icons.error_outline, 'No se pudo imprimir'),
    };

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  Icon(icono, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          resultado.mensaje,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (ticket != null && ticket.texto.isNotEmpty)
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFFAFAF7),
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    // Monoespaciada y sin ajuste de línea: el backend ya recortó
                    // a N columnas. Reflowear el texto rompería la alineación.
                    child: SelectableText(
                      ticket.texto,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay contenido que mostrar'),
              ),

            if (resultado.esFaltaDeConfiguracion)
              Container(
                width: double.infinity,
                color: Colors.blue.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: Colors.blue.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Para imprimir automáticamente, configura la impresora '
                        'de esta cocina en Cocinas (app de administración).',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  if (ticket != null && ticket.texto.isNotEmpty)
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy_all_outlined, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ticket.texto));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ticket copiado'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  if (onReintentar != null && !resultado.ok)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onReintentar!();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
