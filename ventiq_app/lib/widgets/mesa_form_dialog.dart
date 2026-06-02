import 'package:flutter/material.dart';
import '../models/mesa.dart';
import '../services/mesa_service.dart';

/// Dialog para crear o editar una mesa.
///
/// - Si se pasa [mesa] está en modo edición.
/// - [zonasSugeridas] alimenta el dropdown de zonas conocidas (de las mesas
///   ya creadas) para ahorrarle escribir al vendedor.
/// - Devuelve `true` por `Navigator.pop` si se guardó correctamente.
class MesaFormDialog extends StatefulWidget {
  final Mesa? mesa;
  final List<String> zonasSugeridas;

  const MesaFormDialog({
    Key? key,
    this.mesa,
    this.zonasSugeridas = const [],
  }) : super(key: key);

  @override
  State<MesaFormDialog> createState() => _MesaFormDialogState();
}

class _MesaFormDialogState extends State<MesaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _numeroController = TextEditingController();
  final _capacidadController = TextEditingController();
  final _zonaController = TextEditingController();
  final _notasController = TextEditingController();
  bool _activa = true;
  bool _saving = false;

  final MesaService _mesaService = MesaService();

  bool get _isEdit => widget.mesa != null;

  @override
  void initState() {
    super.initState();
    final m = widget.mesa;
    _numeroController.text = m?.numero ?? '';
    _capacidadController.text = (m?.capacidad ?? 4).toString();
    _zonaController.text = m?.zona ?? '';
    _notasController.text = m?.notas ?? '';
    _activa = m?.activa ?? true;
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _capacidadController.dispose();
    _zonaController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final numero = _numeroController.text.trim();
      final capacidad = int.tryParse(_capacidadController.text.trim()) ?? 4;
      final zona = _zonaController.text.trim();
      final notas = _notasController.text.trim();

      if (_isEdit) {
        await _mesaService.updateMesa(
          idMesa: widget.mesa!.id,
          numero: numero,
          capacidad: capacidad,
          zona: zona,
          notas: notas,
          activa: _activa,
        );
      } else {
        await _mesaService.createMesa(
          numero: numero,
          capacidad: capacidad,
          zona: zona.isEmpty ? null : zona,
          notas: notas.isEmpty ? null : notas,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zonas = widget.zonasSugeridas
        .where((z) => z.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.table_restaurant,
                color: Color(0xFF4A90E2), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEdit ? 'Editar Mesa' : 'Nueva Mesa',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _numeroController,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Número o nombre *',
                  hintText: 'Ej: Mesa 1, T-3, Barra 2',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'El número es requerido'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacidadController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Capacidad *',
                  hintText: 'Comensales máximos',
                  prefixIcon: const Icon(Icons.people_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Debe ser un número > 0';
                  if (n > 99) return 'Demasiados comensales';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Zona con sugerencias
              if (zonas.isEmpty)
                TextFormField(
                  controller: _zonaController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Zona (opcional)',
                    hintText: 'Terraza, Salón A, Barra...',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _zonaController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Zona (opcional)',
                        hintText: 'Terraza, Salón A, Barra...',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: zonas
                          .map(
                            (z) => InkWell(
                              onTap: () =>
                                  setState(() => _zonaController.text = z),
                              child: Chip(
                                label: Text(z, style: const TextStyle(fontSize: 12)),
                                backgroundColor: const Color(0xFF4A90E2)
                                    .withOpacity(0.1),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notasController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notas (opcional)',
                  hintText: 'Mesa VIP, cerca de ventana, ...',
                  prefixIcon: const Icon(Icons.note_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _activa,
                  onChanged: (v) => setState(() => _activa = v),
                  title: const Text('Mesa activa'),
                  subtitle: Text(
                    _activa
                        ? 'Visible en la operación diaria'
                        : 'Oculta de la grilla operativa (preserva histórico)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90E2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(_isEdit ? 'Guardar' : 'Crear mesa'),
        ),
      ],
    );
  }
}
