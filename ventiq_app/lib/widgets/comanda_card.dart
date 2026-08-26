import 'package:flutter/material.dart';

import '../models/comanda.dart';

/// Tarjeta de comanda para el KDS.
///
/// El color del borde y de la cabecera codifica el estado del TICKET, y cada
/// item lleva su propio indicador. Es el patrón que documentan los KDS de la
/// industria: el cocinero identifica la prioridad por color antes de leer.
///
///   Pendiente   gris azulado  → nadie lo ha tomado
///   Preparando  índigo        → en marcha
///   Listo       verde         → recoger del pase
///   Entregado   gris tenue    → histórico
///   Cancelado   rojo          → anulado
///
/// Y por encima del estado manda la DEMORA: una comanda pendiente de 25 minutos
/// se pinta en rojo aunque su estado sea "pendiente", porque eso es lo que el
/// cocinero necesita ver primero.
class ComandaCard extends StatelessWidget {
  const ComandaCard({
    super.key,
    required this.comanda,
    required this.onAvanzarItem,
    required this.onCancelarItem,
    required this.onCambiarComanda,
    this.onImprimir,
    this.itemsEnVuelo = const {},
  });

  final Comanda comanda;
  final ValueChanged<ComandaItem> onAvanzarItem;
  final ValueChanged<ComandaItem> onCancelarItem;

  /// (comanda, nuevoEstado) para las acciones de ticket completo.
  final void Function(Comanda, int) onCambiarComanda;

  /// Reimprimir el ticket. Opcional: si es null no se muestra el boton.
  final ValueChanged<Comanda>? onImprimir;

  final Set<int> itemsEnVuelo;

  @override
  Widget build(BuildContext context) {
    final estilo = _EstiloComanda.de(comanda);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: estilo.color, width: 2),
        boxShadow: [
          BoxShadow(
            color: estilo.color.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _cabecera(estilo),
          if (comanda.notas != null && comanda.notas!.trim().isNotEmpty)
            _notaComanda(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in comanda.items) _fila(item),
                ],
              ),
            ),
          ),
          if (comanda.viva) _pie(estilo),
        ],
      ),
    );
  }

  // ── Cabecera: número, mesa y espera ────────────────────────────────────

  Widget _cabecera(_EstiloComanda estilo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: estilo.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                comanda.titulo,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const Spacer(),
              // Reimprimir. Va en la cabecera y no en el pie porque en cocina
              // se pulsa cuando el ticket se perdio o se mancho, y hay que
              // encontrarlo sin leer la tarjeta entera.
              if (onImprimir != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => onImprimir!(comanda),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.print_outlined,
                          size: 18, color: Colors.white70),
                    ),
                  ),
                ),
              _reloj(),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.table_restaurant_outlined,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  comanda.destino,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (comanda.totalItems > 0)
                Text(
                  '${comanda.itemsListos}/${comanda.totalItems}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
          if (comanda.cocina != null) ...[
            const SizedBox(height: 2),
            Text(
              comanda.cocina!,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  /// Minutos de espera. En blanco sobre el color del estado si va bien; en
  /// cápsula blanca destacada si se está demorando, para que salte a la vista
  /// aunque la comanda esté "en preparación".
  Widget _reloj() {
    final critica = comanda.critica;
    final demorada = comanda.demorada;

    if (!critica && !demorada) {
      return Text(
        '${comanda.esperaMinutos}′',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            critica ? Icons.priority_high : Icons.schedule,
            size: 14,
            color: critica ? Colors.red.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 3),
          Text(
            '${comanda.esperaMinutos}′',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: critica ? Colors.red.shade700 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notaComanda() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.amber.shade50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.amber.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              comanda.notas!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fila de plato ──────────────────────────────────────────────────────

  Widget _fila(ComandaItem item) {
    final enVuelo = itemsEnVuelo.contains(item.id);
    final estilo = _EstiloItem.de(item);
    final terminal = item.siguienteEstado == null;

    return Opacity(
      opacity: item.cancelado ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: estilo.fondo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: estilo.color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              // Un toque avanza el plato. Sin confirmación: en cocina no hay
              // tiempo, y el backend permite deshacer un paso.
              onTap: (terminal || enVuelo) ? null : () => onAvanzarItem(item),
              onLongPress: terminal ? null : () => onCancelarItem(item),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: estilo.color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.cantidadTexto,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.denominacion,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2937),
                              decoration: item.cancelado
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(estilo.icono, size: 12, color: estilo.color),
                              const SizedBox(width: 3),
                              Text(
                                EstadoComanda.etiqueta(item.estado),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: estilo.color,
                                ),
                              ),
                              if (item.modoElaboracion == 'por_tanda') ...[
                                const SizedBox(width: 6),
                                Text(
                                  'TANDA',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (enVuelo)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (!terminal)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: estilo.color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.accionSiguiente ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // La nota del comensal va DEBAJO y destacada: es lo que provoca
            // devoluciones si se pasa por alto.
            if (item.tieneNota)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(7)),
                  border: Border(
                    top: BorderSide(color: Colors.orange.shade200),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.priority_high,
                        size: 14, color: Colors.orange.shade900),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.notas!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Pie: acciones de ticket completo ───────────────────────────────────

  Widget _pie(_EstiloComanda estilo) {
    // El botón principal cambia según el estado del ticket: empezar todo,
    // marchar todo, o entregar la mesa.
    final (int? destino, String texto, IconData icono) = switch (comanda.estado) {
      EstadoComanda.pendiente => (
          EstadoComanda.enPreparacion,
          'Empezar todo',
          Icons.play_arrow_rounded
        ),
      EstadoComanda.enPreparacion => (
          EstadoComanda.listo,
          'Marchando todo',
          Icons.done_all_rounded
        ),
      EstadoComanda.listo => (
          EstadoComanda.entregado,
          'Entregar',
          Icons.room_service_rounded
        ),
      _ => (null, '', Icons.help_outline),
    };

    if (destino == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => onCambiarComanda(comanda, destino),
          icon: Icon(icono, size: 18),
          label: Text(texto),
          style: FilledButton.styleFrom(
            backgroundColor: estilo.color,
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Estilos ──────────────────────────────────────────────────────────────

class _EstiloComanda {
  const _EstiloComanda(this.color);
  final Color color;

  static _EstiloComanda de(Comanda c) {
    // La demora manda sobre el estado: un pendiente de 25 minutos es urgente
    // aunque su estado no lo diga.
    if (c.viva && c.critica) return _EstiloComanda(Colors.red.shade700);

    switch (c.estado) {
      case EstadoComanda.pendiente:
        return _EstiloComanda(Colors.blueGrey.shade600);
      case EstadoComanda.enPreparacion:
        return _EstiloComanda(Colors.indigo.shade500);
      case EstadoComanda.listo:
        return _EstiloComanda(Colors.green.shade700);
      case EstadoComanda.entregado:
        return _EstiloComanda(Colors.grey.shade500);
      case EstadoComanda.cancelado:
        return _EstiloComanda(Colors.red.shade400);
      default:
        return _EstiloComanda(Colors.blueGrey.shade400);
    }
  }
}

class _EstiloItem {
  const _EstiloItem(this.color, this.fondo, this.icono);
  final Color color;
  final Color fondo;
  final IconData icono;

  static _EstiloItem de(ComandaItem i) {
    switch (i.estado) {
      case EstadoComanda.pendiente:
        return _EstiloItem(
            Colors.blueGrey.shade600, Colors.blueGrey.shade50, Icons.schedule);
      case EstadoComanda.enPreparacion:
        return _EstiloItem(Colors.indigo.shade500, Colors.indigo.shade50,
            Icons.outdoor_grill_outlined);
      case EstadoComanda.listo:
        return _EstiloItem(Colors.green.shade700, Colors.green.shade50,
            Icons.check_circle_outline);
      case EstadoComanda.entregado:
        return _EstiloItem(
            Colors.grey.shade600, Colors.grey.shade100, Icons.done_all);
      case EstadoComanda.cancelado:
        return _EstiloItem(
            Colors.red.shade600, Colors.red.shade50, Icons.block);
      default:
        return _EstiloItem(Colors.blueGrey.shade400, Colors.grey.shade50,
            Icons.help_outline);
    }
  }
}
