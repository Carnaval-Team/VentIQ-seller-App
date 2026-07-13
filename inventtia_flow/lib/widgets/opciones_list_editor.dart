import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Editor de lista de opciones (chips) para campos tipo select.
class OpcionesListEditor extends StatefulWidget {
  final List<String> opciones;
  final ValueChanged<List<String>> onChanged;
  final String label;

  const OpcionesListEditor({
    super.key,
    required this.opciones,
    required this.onChanged,
    this.label = 'Opciones',
  });

  @override
  State<OpcionesListEditor> createState() => _OpcionesListEditorState();
}

class _OpcionesListEditorState extends State<OpcionesListEditor> {
  final _nuevaCtrl = TextEditingController();

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    super.dispose();
  }

  void _agregar() {
    final t = _nuevaCtrl.text.trim();
    if (t.isEmpty) return;
    if (widget.opciones.any((o) => o.toLowerCase() == t.toLowerCase())) {
      _nuevaCtrl.clear();
      return;
    }
    final next = [...widget.opciones, t];
    _nuevaCtrl.clear();
    widget.onChanged(next);
  }

  void _quitar(int i) {
    final next = [...widget.opciones]..removeAt(i);
    widget.onChanged(next);
  }

  void _editar(int i) async {
    final ctrl = TextEditingController(text: widget.opciones[i]);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar opción'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Texto'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nuevo == null || nuevo.isEmpty) return;
    final next = [...widget.opciones];
    next[i] = nuevo;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (widget.opciones.isEmpty)
          const Text('Sin opciones. Agrega al menos una.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < widget.opciones.length; i++)
              InputChip(
                label: Text(widget.opciones[i]),
                onPressed: () => _editar(i),
                onDeleted: () => _quitar(i),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nuevaCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nueva opción',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _agregar(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _agregar,
              icon: const Icon(Icons.add),
              tooltip: 'Agregar opción',
            ),
          ],
        ),
      ],
    );
  }
}
