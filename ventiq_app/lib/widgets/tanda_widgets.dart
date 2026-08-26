import 'package:flutter/material.dart';

import '../models/tanda.dart';

/// Widgets de la pantalla de produccion por tandas.
///
/// Codigo de color, coherente con el KDS:
///   verde   hay porciones de sobra
///   ambar   quedan pocas: toca producir pronto
///   rojo    agotado
///   gris    sin receta, no se puede producir

// ── Tarjeta de plato del catalogo ────────────────────────────────────────

/// Un plato `por_tanda`: cuantas porciones hay y cuantas se pueden cocinar.
class PlatoTandaCard extends StatelessWidget {
  const PlatoTandaCard({
    super.key,
    required this.plato,
    required this.puedeProducir,
    required this.onProducir,
  });

  final PlatoPorTanda plato;
  final bool puedeProducir;
  final VoidCallback onProducir;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icono) = switch (plato) {
      _ when !plato.tieneReceta => (Colors.grey.shade600, Icons.help_outline),
      _ when plato.agotado => (Colors.red.shade600, Icons.block),
      _ when plato.quedanPocas => (Colors.amber.shade800, Icons.warning_amber),
      _ => (Colors.green.shade700, Icons.check_circle_outline),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icono, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        plato.producto,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        plato.estadoTexto,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                // Porciones hechas, grande: es el dato que se lee de un vistazo.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plato.porcionesHechas % 1 == 0
                          ? plato.porcionesHechas.toInt().toString()
                          : plato.porcionesHechas.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      'hechas',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            if (!plato.tieneReceta)
              Text(
                'Sin receta: no se puede calcular el consumo ni producir. '
                'Definela en la gestion de platos.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Se pueden hacer ${plato.maxProducible % 1 == 0 ? plato.maxProducible.toInt() : plato.maxProducible} mas',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        // El ingrediente que limita es lo que hay que pedir al
                        // almacen: se dice explicitamente.
                        if (plato.ingredienteLimite != null)
                          Text(
                            'Limita: ${plato.ingredienteLimite}'
                            '${plato.stockLimite != null ? ' (${plato.stockLimite})' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (puedeProducir)
                    FilledButton.icon(
                      onPressed: plato.sePuedeProducir ? onProducir : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Producir'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),

            if (plato.tieneLoteAbierto) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 12, color: Colors.indigo.shade400),
                  const SizedBox(width: 4),
                  Text(
                    'Lote abierto #${plato.tandaAbierta}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade400,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de lote ──────────────────────────────────────────────────────

class TandaCard extends StatelessWidget {
  const TandaCard({
    super.key,
    required this.tanda,
    required this.puedeOperar,
    required this.onCerrar,
    required this.onAnular,
  });

  final Tanda tanda;
  final bool puedeOperar;
  final VoidCallback onCerrar;
  final VoidCallback onAnular;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icono) = switch (tanda.estado) {
      EstadoTanda.abierta when tanda.consumida => (
          Colors.amber.shade800,
          Icons.hourglass_bottom
        ),
      EstadoTanda.abierta => (Colors.green.shade700, Icons.inventory_2),
      EstadoTanda.agotada => (Colors.amber.shade800, Icons.hourglass_bottom),
      EstadoTanda.cerrada => (Colors.grey.shade600, Icons.check_circle_outline),
      _ => (Colors.red.shade600, Icons.block),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icono, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tanda.producto,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tanda.estadoTexto,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Cifras del lote. "Quedan" sale del inventario del SKU, no del
            // lote: con dos tandas abiertas del mismo plato el numero se repite.
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _dato('Producidas', tanda.num2(tanda.producidas)),
                if (tanda.viva)
                  _dato('Quedan', tanda.num2(tanda.porcionesRestantes),
                      color: tanda.porcionesRestantes <= 0
                          ? Colors.red.shade600
                          : null),
                if (tanda.descartadas > 0)
                  _dato('Merma', tanda.num2(tanda.descartadas),
                      color: Colors.red.shade600),
                if (tanda.costoPorPorcion != null)
                  _dato('Costo/porcion',
                      tanda.costoPorPorcion!.toStringAsFixed(2)),
                // Costo real por porcion servida: incluye la merma. Es el numero
                // que dice si el tamano del lote fue el adecuado.
                if (tanda.cerrada && tanda.costoPorServida != null)
                  _dato('Costo real',
                      tanda.costoPorServida!.toStringAsFixed(2),
                      color: Colors.deepOrange.shade700),
              ],
            ),

            const SizedBox(height: 6),
            Text(
              '${tanda.producidoPor} · hace ${tanda.minutosAbierta} min',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),

            if (tanda.notas != null && tanda.notas!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                tanda.notas!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700,
                ),
              ),
            ],

            if (tanda.motivoDescarte != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 12, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tanda.motivoDescarte!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (puedeOperar && tanda.viva) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAnular,
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Anular'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCerrar,
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('Cerrar lote'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color ?? const Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// ── Dialogo: producir ────────────────────────────────────────────────────

/// Pide cuantas porciones producir. Devuelve `(porciones, notas)` o `null`.
class ProducirTandaDialog extends StatefulWidget {
  const ProducirTandaDialog({super.key, required this.plato});

  final PlatoPorTanda plato;

  @override
  State<ProducirTandaDialog> createState() => _ProducirTandaDialogState();
}

class _ProducirTandaDialogState extends State<ProducirTandaDialog> {
  late final TextEditingController _porciones;
  final TextEditingController _notas = TextEditingController();
  String? _errorTexto;

  @override
  void initState() {
    super.initState();
    // Se propone el maximo producible acotado a 10: producir la olla entera es
    // lo habitual, pero sugerir 200 porciones por tener mucha harina no ayuda.
    final sugerido = widget.plato.maxProducible.clamp(1, 10).floor();
    _porciones = TextEditingController(text: sugerido.toString());
  }

  @override
  void dispose() {
    _porciones.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _confirmar() {
    final n = double.tryParse(_porciones.text.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) {
      setState(() => _errorTexto = 'Escribe un numero mayor que cero');
      return;
    }
    if (n > widget.plato.maxProducible) {
      setState(() => _errorTexto =
          'Solo alcanza para ${widget.plato.maxProducible % 1 == 0 ? widget.plato.maxProducible.toInt() : widget.plato.maxProducible} porciones');
      return;
    }
    Navigator.pop(context, (
      porciones: n,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plato;
    final maxTexto =
        p.maxProducible % 1 == 0 ? p.maxProducible.toInt().toString() : p.maxProducible.toString();

    return AlertDialog(
      title: Text('Producir ${p.producto}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hay ${p.porcionesTexto}. Con la materia prima de la cocina '
            'se pueden hacer $maxTexto mas.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          if (p.ingredienteLimite != null) ...[
            const SizedBox(height: 4),
            Text(
              'Limita: ${p.ingredienteLimite}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _porciones,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Porciones a producir',
              border: const OutlineInputBorder(),
              errorText: _errorTexto,
            ),
            onChanged: (_) {
              if (_errorTexto != null) setState(() => _errorTexto = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notas,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              hintText: 'olla grande, para el almuerzo...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Se descontara la materia prima segun la receta.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Producir')),
      ],
    );
  }
}

// ── Dialogo: cerrar lote con merma ───────────────────────────────────────

/// Pide la merma al cerrar. Devuelve `(descartadas, motivo)` o `null`.
class CerrarTandaDialog extends StatefulWidget {
  const CerrarTandaDialog({super.key, required this.tanda});

  final Tanda tanda;

  @override
  State<CerrarTandaDialog> createState() => _CerrarTandaDialogState();
}

class _CerrarTandaDialogState extends State<CerrarTandaDialog> {
  late final TextEditingController _descartadas;
  final TextEditingController _motivo = TextEditingController();
  String? _errorTexto;

  @override
  void initState() {
    super.initState();
    // Se propone lo que queda en inventario: al cerrar el servicio, lo que
    // sobro es normalmente lo que se bota.
    final resto = widget.tanda.porcionesRestantes;
    _descartadas =
        TextEditingController(text: resto > 0 ? widget.tanda.num2(resto) : '0');
  }

  @override
  void dispose() {
    _descartadas.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final n = double.tryParse(_descartadas.text.trim().replaceAll(',', '.'));
    if (n == null || n < 0) {
      setState(() => _errorTexto = 'Escribe 0 o un numero positivo');
      return;
    }
    // El backend tambien lo exige; validarlo aqui evita el viaje.
    if (n > 0 && _motivo.text.trim().isEmpty) {
      setState(() => _errorTexto = 'Indica el motivo del descarte');
      return;
    }
    Navigator.pop(context, (
      descartadas: n,
      motivo: _motivo.text.trim().isEmpty ? null : _motivo.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tanda;

    return AlertDialog(
      title: const Text('Cerrar lote'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.producto}: se produjeron ${t.num2(t.producidas)} porciones y '
            'quedan ${t.num2(t.porcionesRestantes)} en inventario.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descartadas,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Porciones que se botan',
              border: const OutlineInputBorder(),
              errorText: _errorTexto,
            ),
            onChanged: (_) {
              if (_errorTexto != null) setState(() => _errorTexto = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'sobro del servicio, se paso...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'La merma se registra aparte de lo producido: asi el costo real por '
            'porcion servida sale correcto.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Cerrar lote')),
      ],
    );
  }
}

// ── Dialogo: faltantes de materia prima ──────────────────────────────────

/// Detalle de lo que falta para producir. El jefe necesita saber QUE pedir al
/// almacen, no solo que "no alcanza".
class FaltantesDialog extends StatelessWidget {
  const FaltantesDialog({super.key, required this.error});

  final TandaException error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(error.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.mensaje,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          for (final f in error.faltantes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.remove_circle_outline,
                      size: 16, color: Colors.red.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f['ingrediente']?.toString() ?? 'Ingrediente',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Hay ${f['disponible']}, hacen falta ${f['necesario']}'
                          ' · falta ${f['falta']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
