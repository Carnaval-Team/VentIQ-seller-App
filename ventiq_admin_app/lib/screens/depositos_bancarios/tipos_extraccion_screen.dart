import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/depositos_bancarios.dart';
import '../../services/depositos_bancarios_service.dart';

class TiposExtraccionScreen extends StatefulWidget {
  const TiposExtraccionScreen({super.key});

  @override
  State<TiposExtraccionScreen> createState() => _TiposExtraccionScreenState();
}

class _TiposExtraccionScreenState extends State<TiposExtraccionScreen> {
  final DepositosBancariosService _service = DepositosBancariosService();
  List<TipoExtraccion> _tipos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTipos();
  }

  Future<void> _loadTipos() async {
    setState(() => _isLoading = true);
    try {
      final tipos = await _service.getTiposExtraccion();
      setState(() {
        _tipos = tipos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando tipos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showTipoDialog({TipoExtraccion? tipo}) {
    final isEditing = tipo != null;
    final denominacionCtrl =
        TextEditingController(text: tipo?.denominacion ?? '');
    final descripcionCtrl =
        TextEditingController(text: tipo?.descripcion ?? '');
    final ordenCtrl = TextEditingController(
      text: tipo?.orden.toString() ?? (_tipos.length + 1).toString(),
    );
    String selectedColor = tipo?.color ?? '#607D8B';
    bool activo = tipo?.activo ?? true;

    final colorOptions = [
      {'hex': '#FF9800', 'label': 'Naranja'},
      {'hex': '#2196F3', 'label': 'Azul'},
      {'hex': '#9C27B0', 'label': 'Morado'},
      {'hex': '#4CAF50', 'label': 'Verde'},
      {'hex': '#F44336', 'label': 'Rojo'},
      {'hex': '#607D8B', 'label': 'Gris'},
      {'hex': '#795548', 'label': 'Marrón'},
      {'hex': '#00BCD4', 'label': 'Cian'},
    ];

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text(
                    isEditing ? 'Editar Tipo de Extracción' : 'Nuevo Tipo de Extracción',
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: denominacionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Denominación *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descripcionCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Descripción',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: ordenCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Orden *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Color del tipo:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: colorOptions.map((c) {
                            final hex = c['hex']!;
                            final color = _hexToColor(hex);
                            final isSelected = selectedColor == hex;
                            return GestureDetector(
                              onTap:
                                  () => setDialogState(
                                    () => selectedColor = hex,
                                  ),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      isSelected
                                          ? Border.all(
                                            color: Colors.black,
                                            width: 3,
                                          )
                                          : null,
                                ),
                                child:
                                    isSelected
                                        ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 20,
                                        )
                                        : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Activo:'),
                            const SizedBox(width: 8),
                            Switch(
                              value: activo,
                              onChanged:
                                  (v) => setDialogState(() => activo = v),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final denominacion = denominacionCtrl.text.trim();
                        if (denominacion.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('La denominación es obligatoria'),
                            ),
                          );
                          return;
                        }
                        final orden = int.tryParse(ordenCtrl.text) ?? 0;

                        final nuevoTipo = TipoExtraccion(
                          id: tipo?.id ?? 0,
                          denominacion: denominacion,
                          descripcion:
                              descripcionCtrl.text.trim().isEmpty
                                  ? null
                                  : descripcionCtrl.text.trim(),
                          color: selectedColor,
                          orden: orden,
                          activo: activo,
                        );

                        Navigator.pop(ctx);

                        try {
                          if (isEditing) {
                            await _service.updateTipoExtraccion(
                              tipo.id!,
                              nuevoTipo,
                            );
                          } else {
                            await _service.createTipoExtraccion(nuevoTipo);
                          }
                          await _loadTipos();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEditing
                                      ? 'Tipo actualizado'
                                      : 'Tipo creado',
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      child: Text(isEditing ? 'Guardar' : 'Crear'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _deleteTipo(TipoExtraccion tipo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirmar Eliminación'),
            content: Text(
              '¿Desea eliminar el tipo "${tipo.denominacion}"? Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _service.deleteTipoExtraccion(tipo.id!);
        await _loadTipos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tipo eliminado'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _inicializarEstandar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Inicializar Tipos Estándar'),
            content: const Text(
              'Se crearán los tipos de extracción estándar:\n\n'
              '• Depósito bancario\n'
              '• Pago a proveedor\n'
              '• Gasto operativo\n'
              '• Otro\n\n'
              '¿Desea continuar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Inicializar'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _service.inicializarTiposExtraccionEstandar();
        await _loadTipos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tipos estándar inicializados'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Color _hexToColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tipos de Extracción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_tipos.isEmpty)
            TextButton.icon(
              onPressed: _inicializarEstandar,
              icon: const Icon(Icons.auto_fix_high, color: Colors.white),
              label: const Text(
                'Inicializar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTipos,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
              : _tipos.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _tipos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tipo = _tipos[index];
                  final color = _hexToColor(tipo.color ?? '#607D8B');
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 12,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            tipo.denominacion,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!tipo.activo)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Inactivo',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle:
                          tipo.descripcion != null
                              ? Text(tipo.descripcion!)
                              : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Orden: ${tipo.orden}',
                              style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showTipoDialog(tipo: tipo);
                              } else if (value == 'delete') {
                                _deleteTipo(tipo);
                              }
                            },
                            itemBuilder:
                                (ctx) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Eliminar',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTipoDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Tipo'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.output, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay tipos de extracción configurados',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Cree tipos personalizados o inicialice los estándar',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _inicializarEstandar,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Inicializar Tipos Estándar'),
          ),
        ],
      ),
    );
  }
}
