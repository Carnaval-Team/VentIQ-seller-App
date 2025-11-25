import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/store.dart';
import '../services/consignacion_service.dart';
import '../services/store_service.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class ConsignacionScreen extends StatefulWidget {
  const ConsignacionScreen({super.key});

  @override
  State<ConsignacionScreen> createState() => _ConsignacionScreenState();
}

class _ConsignacionScreenState extends State<ConsignacionScreen> {
  List<Map<String, dynamic>> _contratos = [];
  List<Store> _tiendas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'activos';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📋 Cargando datos de consignación...');
      debugPrint('   Filtro: $_selectedFilter');
      
      final tiendas = await StoreService.getAllStores();
      final contratos = _selectedFilter == 'activos'
          ? await ConsignacionService.getActiveContratos()
          : await ConsignacionService.getAllContratos();

      debugPrint('✅ Contratos cargados: ${contratos.length}');

      if (mounted) {
        setState(() {
          _tiendas = tiendas;
          _contratos = contratos;
          _isLoading = false;
        });
        // Aplicar filtro de búsqueda si existe
        _filterContratos();
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterContratos() {
    if (_searchQuery.isEmpty) {
      return; // Si no hay búsqueda, no hacer nada
    }

    setState(() {
      _contratos = _contratos.where((contrato) {
        final consignadora = contrato[
            'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignadora_fkey'];
        final consignataria = contrato[
            'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignataria_fkey'];

        final consignadoraNombre =
            (consignadora?['denominacion'] ?? '').toString().toLowerCase();
        final consignatariaNombre =
            (consignataria?['denominacion'] ?? '').toString().toLowerCase();
        final searchLower = _searchQuery.toLowerCase();

        return consignadoraNombre.contains(searchLower) ||
            consignatariaNombre.contains(searchLower);
      }).toList();
    });
  }

  String _getTiendaNombre(int tiendaId) {
    try {
      final tienda = _tiendas.firstWhere((t) => t.id == tiendaId);
      return tienda.denominacion;
    } catch (e) {
      return 'Tienda #$tiendaId';
    }
  }

  Future<void> _showCreateContratoDialog() async {
    int? selectedConsignadora;
    int? selectedConsignataria;
    DateTime selectedFechaInicio = DateTime.now();
    DateTime? selectedFechaFin;
    final comisionController = TextEditingController();
    final plazoController = TextEditingController();
    final condicionesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Crear Nuevo Contrato de Consignación',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tienda Consignadora
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<int>(
                            value: selectedConsignadora,
                            hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Seleccionar tienda consignadora'),
                            ),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _tiendas
                                .map((tienda) => DropdownMenuItem(
                                      value: tienda.id,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        child: Text(
                                          tienda.denominacion,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => selectedConsignadora = value);
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tienda Consignataria
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<int>(
                            value: selectedConsignataria,
                            hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Seleccionar tienda consignataria'),
                            ),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _tiendas
                                .where((tienda) => tienda.id != selectedConsignadora)
                                .map((tienda) => DropdownMenuItem(
                                      value: tienda.id,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        child: Text(
                                          tienda.denominacion,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => selectedConsignataria = value);
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Fecha Inicio
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedFechaInicio,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => selectedFechaInicio = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Fecha de Inicio',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              '${selectedFechaInicio.day}/${selectedFechaInicio.month}/${selectedFechaInicio.year}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Fecha Fin (opcional)
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedFechaFin ?? DateTime.now(),
                                    firstDate: selectedFechaInicio,
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => selectedFechaFin = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Fecha de Fin (Opcional)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    selectedFechaFin != null
                                        ? '${selectedFechaFin!.day}/${selectedFechaFin!.month}/${selectedFechaFin!.year}'
                                        : 'Sin fecha de fin',
                                  ),
                                ),
                              ),
                            ),
                            if (selectedFechaFin != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() => selectedFechaFin = null);
                                },
                                icon: const Icon(Icons.clear),
                                tooltip: 'Limpiar fecha',
                                color: AppColors.error,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Porcentaje Comisión (OBLIGATORIO)
                        TextField(
                          controller: comisionController,
                          decoration: InputDecoration(
                            labelText: 'Comisión % *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintText: 'Ej: 5',
                            suffixText: '%',
                            errorText: comisionController.text.isEmpty
                                ? null
                                : (double.tryParse(comisionController.text) == null ||
                                        double.parse(comisionController.text) < 0 ||
                                        double.parse(comisionController.text) > 100)
                                    ? 'Debe estar entre 0 y 100'
                                    : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 16),

                        // Plazo en Días
                        TextField(
                          controller: plazoController,
                          decoration: InputDecoration(
                            labelText: 'Plazo en Días (Opcional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintText: 'Ej: 30',
                            suffixText: 'días',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        // Condiciones
                        TextField(
                          controller: condicionesController,
                          decoration: InputDecoration(
                            labelText: 'Condiciones (Opcional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintText: 'Ej: Pago a 30 días, Devoluciones permitidas',
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedConsignadora == null ||
                                selectedConsignataria == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Debe seleccionar ambas tiendas'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }

                            // Verificar que no exista contrato activo
                            final exists =
                                await ConsignacionService.existsActiveContrato(
                              selectedConsignadora!,
                              selectedConsignataria!,
                            );

                            if (exists) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Ya existe un contrato activo entre estas tiendas'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                              return;
                            }

                            // Parsear comisión (OBLIGATORIO)
                            if (comisionController.text.isEmpty) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('La comisión es obligatoria'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                              return;
                            }

                            double? comision;
                            try {
                              comision = double.parse(comisionController.text);
                              if (comision < 0 || comision > 100) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('La comisión debe estar entre 0 y 100'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                                return;
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Comisión inválida'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                              return;
                            }

                            // Parsear plazo
                            int? plazo;
                            if (plazoController.text.isNotEmpty) {
                              try {
                                plazo = int.parse(plazoController.text);
                                if (plazo <= 0) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('El plazo debe ser mayor a 0'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                  return;
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Plazo inválido'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                                return;
                              }
                            }

                            final success = await ConsignacionService.createContrato(
                              idTiendaConsignadora: selectedConsignadora!,
                              idTiendaConsignataria: selectedConsignataria!,
                              fechaInicio: selectedFechaInicio,
                              fechaFin: selectedFechaFin,
                              porcentajeComision: comision,
                              plazoDias: plazo,
                              condiciones: condicionesController.text.isEmpty
                                  ? null
                                  : condicionesController.text,
                            );

                            if (mounted) {
                              Navigator.pop(context);
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Contrato creado exitosamente'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                _loadData();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Error al crear el contrato'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Crear'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmDialog(int contratoId) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Contrato'),
        content: const Text(
          '¿Está seguro de que desea eliminar este contrato de consignación?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              debugPrint('🗑️ Eliminando contrato ID: $contratoId');
              final success =
                  await ConsignacionService.deleteContrato(contratoId);

              if (!mounted) return;

              if (success) {
                debugPrint('✅ Contrato eliminado, recargando lista...');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contrato eliminado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                await _loadData();
              } else {
                debugPrint('❌ Error al eliminar contrato');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al eliminar el contrato'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeactivateConfirmDialog(int contratoId) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desactivar Contrato'),
        content: const Text(
          '¿Está seguro de que desea desactivar este contrato de consignación?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              debugPrint('🔴 Desactivando contrato ID: $contratoId');
              final success =
                  await ConsignacionService.deactivateContrato(contratoId);

              if (!mounted) return;

              if (success) {
                debugPrint('✅ Contrato desactivado, recargando lista...');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contrato desactivado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                await _loadData();
              } else {
                debugPrint('❌ Error al desactivar contrato');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al desactivar el contrato'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Consignaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateContratoDialog,
            tooltip: 'Nuevo Contrato',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isDesktop ? null : const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Barra de búsqueda y filtros
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Búsqueda
                      TextField(
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                          _filterContratos();
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar por tienda...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filtro de estado
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'activos',
                                  label: Text('Activos'),
                                ),
                                ButtonSegment(
                                  value: 'todos',
                                  label: Text('Todos'),
                                ),
                              ],
                              selected: {_selectedFilter},
                              onSelectionChanged: (Set<String> newSelection) {
                                setState(() =>
                                    _selectedFilter = newSelection.first);
                                _loadData();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Lista de contratos
                Expanded(
                  child: _contratos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.handshake_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay contratos de consignación',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _contratos.length,
                          itemBuilder: (context, index) {
                            final contrato = _contratos[index];
                            final estado = contrato['estado'] == 1;
                            final consignadora = contrato[
                                'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignadora_fkey'];
                            final consignataria = contrato[
                                'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignataria_fkey'];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ExpansionTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${consignadora['denominacion']} → ${consignataria['denominacion']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Desde: ${DateTime.parse(contrato['fecha_inicio']).day}/${DateTime.parse(contrato['fecha_inicio']).month}/${DateTime.parse(contrato['fecha_inicio']).year}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: estado
                                            ? Colors.green[100]
                                            : Colors.grey[100],
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        estado ? 'Activo' : 'Inactivo',
                                        style: TextStyle(
                                          color: estado
                                              ? Colors.green[800]
                                              : Colors.grey[800],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Detalles
                                        _buildDetailRow(
                                          'Tienda Consignadora:',
                                          consignadora['denominacion'],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(
                                          'Tienda Consignataria:',
                                          consignataria['denominacion'],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(
                                          'Fecha de Inicio:',
                                          '${DateTime.parse(contrato['fecha_inicio']).day}/${DateTime.parse(contrato['fecha_inicio']).month}/${DateTime.parse(contrato['fecha_inicio']).year}',
                                        ),
                                        if (contrato['fecha_fin'] != null) ...[
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Fecha de Fin:',
                                            '${DateTime.parse(contrato['fecha_fin']).day}/${DateTime.parse(contrato['fecha_fin']).month}/${DateTime.parse(contrato['fecha_fin']).year}',
                                          ),
                                        ],
                                        if (contrato['porcentaje_comision'] != null) ...[
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Comisión:',
                                            '${contrato['porcentaje_comision']}%',
                                          ),
                                        ],
                                        if (contrato['plazo_dias'] != null) ...[
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Plazo:',
                                            '${contrato['plazo_dias']} días',
                                          ),
                                        ],
                                        if (contrato['condiciones'] != null) ...[
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Condiciones:',
                                            contrato['condiciones'],
                                          ),
                                        ],
                                        const SizedBox(height: 16),

                                        // Botones de acción
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            if (estado)
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    _showDeactivateConfirmDialog(
                                                  contrato['id'],
                                                ),
                                                icon: const Icon(
                                                    Icons.pause_circle),
                                                label: const Text('Desactivar'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.orange,
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showDeleteConfirmDialog(
                                                contrato['id'],
                                              ),
                                              icon:
                                                  const Icon(Icons.delete),
                                              label: const Text('Eliminar'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.error,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }
}
