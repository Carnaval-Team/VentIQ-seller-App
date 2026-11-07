import 'package:flutter/material.dart';

class FdiInversorDialog extends StatefulWidget {
  final Map<String, dynamic>? inversor;

  const FdiInversorDialog({super.key, this.inversor});

  @override
  State<FdiInversorDialog> createState() => _FdiInversorDialogState();
}

class _FdiInversorDialogState extends State<FdiInversorDialog> {
  final _form = GlobalKey<FormState>();
  late String _nombre;
  late String _porcentaje;
  late bool _activo;

  @override
  void initState() {
    super.initState();
    _nombre = widget.inversor?['nombre']?.toString() ?? '';
    _porcentaje = widget.inversor?['porcentaje']?.toString() ?? '';
    _activo = widget.inversor?['activo'] as bool? ?? true;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.inversor == null ? 'Nuevo inversor' : 'Editar inversor'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _nombre,
              onChanged: (value) => _nombre = value,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Indique el nombre' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _porcentaje,
              onChanged: (value) => _porcentaje = value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Participación (%)'),
              validator: (s) {
                final n = double.tryParse((s ?? '').replaceAll(',', '.'));
                if (n == null || !n.isFinite || n <= 0 || n > 100) {
                  return 'Use un porcentaje mayor que 0 y hasta 100';
                }
                return (n * 10000 - (n * 10000).round()).abs() > 0.000001
                    ? 'Use como máximo cuatro decimales'
                    : null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const Text('Los cambios solo afectan a liquidaciones futuras.'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, {
            'nombre': _nombre.trim(),
            'porcentaje': double.parse(_porcentaje.replaceAll(',', '.')),
            'activo': _activo,
          });
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
