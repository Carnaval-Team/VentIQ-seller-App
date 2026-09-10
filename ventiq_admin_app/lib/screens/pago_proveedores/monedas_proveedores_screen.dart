import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/pago_proveedores.dart';
import '../../services/pago_proveedores_service.dart';

class MonedasProveedoresScreen extends StatefulWidget {
  const MonedasProveedoresScreen({super.key});

  @override
  State<MonedasProveedoresScreen> createState() =>
      _MonedasProveedoresScreenState();
}

class _MonedasProveedoresScreenState extends State<MonedasProveedoresScreen> {
  final PagoProveedoresService _service = PagoProveedoresService();
  List<MonedaPago> _monedas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonedas();
  }

  Future<void> _loadMonedas() async {
    setState(() => _isLoading = true);
    try {
      final monedas = await _service.getMonedas();
      setState(() {
        _monedas = monedas;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando monedas: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showMonedaDialog({MonedaPago? moneda}) {
    final isEditing = moneda != null;
    final codigoCtrl = TextEditingController(text: moneda?.codigo ?? '');
    final denominacionCtrl =
        TextEditingController(text: moneda?.denominacion ?? '');
    final simboloCtrl = TextEditingController(text: moneda?.simbolo ?? '\$');
    bool activo = moneda?.activo ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Moneda' : 'Nueva Moneda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codigoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código *',
                    hintText: 'USD, CUP, EUR…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: denominacionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Denominación *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: simboloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Símbolo *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Activa:'),
                    const SizedBox(width: 8),
                    Switch(
                      value: activo,
                      onChanged: (v) => setDialogState(() => activo = v),
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
                final codigo = codigoCtrl.text.trim().toUpperCase();
                final denominacion = denominacionCtrl.text.trim();
                final simbolo = simboloCtrl.text.trim();
                if (codigo.isEmpty || denominacion.isEmpty || simbolo.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Complete todos los campos obligatorios'),
                    ),
                  );
                  return;
                }

                final nueva = MonedaPago(
                  id: moneda?.id,
                  codigo: codigo,
                  denominacion: denominacion,
                  simbolo: simbolo,
                  activo: activo,
                );

                Navigator.pop(ctx);
                try {
                  if (isEditing) {
                    await _service.updateMoneda(moneda.id!, nueva);
                  } else {
                    await _service.createMoneda(nueva);
                  }
                  await _loadMonedas();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing ? 'Moneda actualizada' : 'Moneda creada',
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

  Future<void> _toggleActivo(MonedaPago moneda) async {
    try {
      await _service.setMonedaActiva(moneda.id!, !moneda.activo);
      await _loadMonedas();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monedas'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMonedas,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _monedas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.attach_money, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay monedas configuradas',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showMonedaDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar moneda'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _monedas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final moneda = _monedas[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          child: Text(
                            moneda.simbolo,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          '${moneda.codigo} — ${moneda.denominacion}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          moneda.activo ? 'Activa' : 'Inactiva',
                          style: TextStyle(
                            color: moneda.activo
                                ? Colors.green[700]
                                : Colors.grey,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showMonedaDialog(moneda: moneda);
                            } else if (value == 'toggle') {
                              _toggleActivo(moneda);
                            }
                          },
                          itemBuilder: (ctx) => [
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
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    moneda.activo
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    moneda.activo ? 'Desactivar' : 'Activar',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMonedaDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Moneda'),
      ),
    );
  }
}
