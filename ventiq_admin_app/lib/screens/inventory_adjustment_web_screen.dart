import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/inventory_service.dart';
import '../services/product_search_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/product_selector_widget.dart';

class InventoryAdjustmentWebScreen extends StatefulWidget {
  final int operationType;
  final String adjustmentType;

  const InventoryAdjustmentWebScreen({
    super.key,
    required this.operationType,
    required this.adjustmentType,
  });

  @override
  State<InventoryAdjustmentWebScreen> createState() =>
      _InventoryAdjustmentWebScreenState();
}

class _AdjustRow {
  final int idProducto;
  final String nombreProducto;
  final int? idPresentacion;
  final String nombrePresentacion;
  final int idUbicacion;
  final double stockActual;
  final TextEditingController cantidadController;

  _AdjustRow({
    required this.idProducto,
    required this.nombreProducto,
    required this.idPresentacion,
    required this.nombrePresentacion,
    required this.idUbicacion,
    required this.stockActual,
    required this.cantidadController,
  });

  String get rowKey =>
      '${idProducto}_${idPresentacion ?? 'null'}_$idUbicacion';
  double? get nuevaCantidad =>
      double.tryParse(cantidadController.text.trim());
  void dispose() => cantidadController.dispose();
}

class _InventoryAdjustmentWebScreenState
    extends State<InventoryAdjustmentWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _observationsController = TextEditingController();

  List<Map<String, dynamic>> _warehousesWithZones = [];
  Map<String, dynamic>? _selectedZone;
  Map<String, dynamic>? _selectedWarehouse;

  final List<_AdjustRow> _rows = [];

  bool _isLoading = false;
  bool _isLoadingZones = false;
  bool _isLoadingProduct = false;

  @override
  void initState() {
    super.initState();
    _loadInitialZones();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _observationsController.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  Future<void> _loadInitialZones() async {
    setState(() => _isLoadingZones = true);
    try {
      final warehouses = await WarehouseService().listWarehousesOK();
      final warehousesWithZones = warehouses
          .map((warehouse) => {
                'id': int.tryParse(warehouse.id) ?? 0,
                'name': warehouse.name,
                'denominacion': warehouse.denominacion ?? warehouse.name,
                'zones': warehouse.zones
                    .map((zone) => {
                          'id': int.tryParse(zone.id) ?? 0,
                          'denominacion': zone.name,
                          'code': zone.code ?? '',
                        })
                    .toList(),
              })
          .toList();

      setState(() {
        _warehousesWithZones = warehousesWithZones;
        _isLoadingZones = false;
      });
    } catch (e) {
      setState(() => _isLoadingZones = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar zonas: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onZoneSelected(Map<String, dynamic> zone, Map<String, dynamic> warehouse) {
    setState(() {
      _selectedZone = zone;
      _selectedWarehouse = warehouse;
      for (final r in _rows) r.dispose();
      _rows.clear();
    });
  }

  Future<void> _onProductSelected(Map<String, dynamic> product) async {
    if (_selectedZone == null) return;
    setState(() => _isLoadingProduct = true);
    try {
      final productId = int.tryParse(
            (product['id_producto'] ?? product['id'])?.toString() ?? '0',
          ) ??
          0;
      final zoneId = _selectedZone!['id'] as int;

      final response = await InventoryService.getInventoryProducts(
        idProducto: productId,
        idUbicacion: zoneId,
        mostrarSinStock: true,
        limite: 100,
      );

      if (!mounted) return;
      if (response.products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se encontraron presentaciones para este producto en la zona'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      for (final inv in response.products) {
        final key = '${productId}_${inv.idPresentacion ?? 'null'}_$zoneId';
        if (_rows.any((r) => r.rowKey == key)) continue;
        if (!mounted) return;

        await _showAdjustmentDialog(
          productName: inv.nombreProducto.isNotEmpty
              ? inv.nombreProducto
              : product['denominacion']?.toString() ?? 'Producto',
          presentationName:
              inv.presentacion.isNotEmpty ? inv.presentacion : 'Sin presentación',
          currentStock: inv.cantidadFinal,
          onSave: (adjustmentAmount) {
            setState(() {
              _rows.add(_AdjustRow(
                idProducto: productId,
                nombreProducto: inv.nombreProducto.isNotEmpty
                    ? inv.nombreProducto
                    : product['denominacion']?.toString() ?? 'Producto',
                idPresentacion: inv.idPresentacion,
                nombrePresentacion: inv.presentacion.isNotEmpty
                    ? inv.presentacion
                    : 'Sin presentación',
                idUbicacion: zoneId,
                stockActual: inv.cantidadFinal,
                cantidadController:
                    TextEditingController(text: adjustmentAmount.toString()),
              ));
            });
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar producto: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingProduct = false);
    }
  }

  Future<void> _showAdjustmentDialog({
    required String productName,
    required String presentationName,
    required double currentStock,
    required Function(double) onSave,
  }) async {
    final adjustmentController = TextEditingController();
    final isExcess = widget.adjustmentType == 'excess';
    final accent = _adjustmentColor();

    return showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ajuste =
              double.tryParse(adjustmentController.text.trim()) ?? 0;
          final ajusteAplicado = isExcess ? -ajuste : ajuste;
          final resultado = currentStock + ajusteAplicado;

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isExcess
                                ? Icons.trending_down_rounded
                                : Icons.trending_up_rounded,
                            color: accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                presentationName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Stock Actual',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                currentStock.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 22),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Resultado',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                resultado.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: resultado >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: adjustmentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: false,
                        decimal: true,
                      ),
                      decoration: _inputDecoration(
                        label:
                            'Cantidad a ${isExcess ? 'Restar' : 'Sumar'}',
                        hint: '0.00',
                        prefixIcon: Icon(
                          isExcess
                              ? Icons.remove_rounded
                              : Icons.add_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: ajuste >= 0.01
                              ? () {
                                  onSave(ajuste);
                                  Navigator.pop(context);
                                }
                              : null,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Guardar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _removeRow(_AdjustRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
  }

  Future<void> _submitAdjustment() async {
    final motivo = _reasonController.text.trim();
    if (_selectedZone == null) {
      _showError('Debe seleccionar una zona');
      return;
    }
    if (_rows.isEmpty) {
      _showError('Agregue al menos un producto');
      return;
    }
    if (motivo.length < 5) {
      _showError('El motivo debe tener al menos 5 caracteres');
      return;
    }

    final rowsToProcess = _rows.where((r) {
      final ajuste = r.nuevaCantidad;
      return ajuste != null && ajuste >= 0.01;
    }).toList();

    if (rowsToProcess.isEmpty) {
      _showError(
          'Ingrese la cantidad a ajustar en al menos una fila (mínimo 0.01)');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userUuid = await UserPreferencesService().getUserId();
      if (userUuid == null || userUuid.isEmpty) {
        throw Exception('No se pudo obtener el UUID del usuario');
      }
      final observaciones = _observationsController.text.trim();

      int successCount = 0;
      int errorCount = 0;

      for (final row in rowsToProcess) {
        final ajuste = row.nuevaCantidad!;
        final ajusteAplicado =
            widget.adjustmentType == 'excess' ? -ajuste : ajuste;
        final cantidadNueva = row.stockActual + ajusteAplicado;
        final result = await InventoryService.insertInventoryAdjustment(
          idProducto: row.idProducto,
          idUbicacion: row.idUbicacion,
          idPresentacion: row.idPresentacion ?? 0,
          cantidadAnterior: row.stockActual,
          cantidadNueva: cantidadNueva,
          motivo: motivo,
          observaciones: observaciones,
          uuid: userUuid,
          idTipoOperacion: widget.operationType,
        );
        if (result['status'] == 'success') {
          successCount++;
        } else {
          errorCount++;
        }
      }

      if (mounted) {
        if (errorCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount ajuste(s) registrado(s) exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '$successCount exitoso(s), $errorCount con error.'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 5),
            ),
          );
        }
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Color _adjustmentColor() => widget.adjustmentType == 'excess'
      ? const Color(0xFFFF6B35)
      : const Color(0xFFFF8C42);

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final isExcess = widget.adjustmentType == 'excess';
    final title =
        isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante';
    final accent = _adjustmentColor();
    final mainIcon =
        isExcess ? Icons.trending_down_rounded : Icons.trending_up_rounded;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitAdjustment,
              icon: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isLoading ? 'Procesando...' : 'Registrar Ajuste'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: accent,
                disabledBackgroundColor: Colors.white70,
                disabledForegroundColor: accent,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderBanner(title, mainIcon, accent),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 980;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildReasonCard(),
                                  const SizedBox(height: 20),
                                  _buildZoneCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildProductSearchCard(),
                                  const SizedBox(height: 20),
                                  _buildRowsCard(),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildReasonCard(),
                          const SizedBox(height: 20),
                          _buildZoneCard(),
                          const SizedBox(height: 20),
                          _buildProductSearchCard(),
                          const SizedBox(height: 20),
                          _buildRowsCard(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(String title, IconData icon, Color accent) {
    final isExcess = widget.adjustmentType == 'excess';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isExcess
                      ? 'Resta unidades del inventario para corregir excesos detectados.'
                      : 'Suma unidades al inventario para corregir faltantes detectados.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard() {
    return _buildWebCard(
      title: 'Motivo y Observaciones',
      subtitle: 'Justifica el ajuste de inventario',
      icon: Icons.description_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _reasonController,
            decoration: _inputDecoration(
              label: 'Motivo del Ajuste *',
              hint: 'Ej: Conteo físico, Merma, Error de registro',
              prefixIcon: Icon(
                Icons.assignment_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 5) {
                return 'Mínimo 5 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _observationsController,
            decoration: _inputDecoration(
              label: 'Observaciones',
              hint: 'Información adicional (opcional)',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildZoneCard() {
    return _buildWebCard(
      title: 'Zona de Trabajo',
      subtitle: _selectedZone != null
          ? 'Zona seleccionada para ajustar'
          : 'Selecciona el almacén y la zona',
      icon: Icons.warehouse_outlined,
      iconColor: AppColors.warning,
      trailing: _selectedZone != null
          ? TextButton.icon(
              onPressed: () => setState(() {
                _selectedZone = null;
                _selectedWarehouse = null;
                for (final r in _rows) r.dispose();
                _rows.clear();
              }),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Cambiar'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            )
          : null,
      child: _selectedZone != null
          ? _buildSelectedZoneSummary()
          : _buildZonePicker(),
    );
  }

  Widget _buildSelectedZoneSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedWarehouse?['name'] ?? 'Almacén',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedZone!['denominacion'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZonePicker() {
    if (_isLoadingZones) {
      return _buildLoadingPlaceholder('Cargando almacenes...');
    }
    if (_warehousesWithZones.isEmpty) {
      return _buildEmptyState(
        icon: Icons.warning_amber_rounded,
        title: 'Sin almacenes',
        description: 'No hay almacenes disponibles para esta tienda.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: _warehousesWithZones.map((warehouse) {
          final zones = warehouse['zones'] as List;
          return Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warehouse_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              title: Text(
                warehouse['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${zones.length} zona(s) disponibles',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              children: (zones as List<Map<String, dynamic>>).map<Widget>((zone) {
                final code = (zone['code'] as String);
                return InkWell(
                  onTap: () => _onZoneSelected(zone, warehouse),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(48, 0, 14, 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          color: AppColors.warning,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                zone['denominacion'],
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (code.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Código: $code',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductSearchCard() {
    if (_selectedZone == null) {
      return _buildWebCard(
        title: 'Agregar Productos',
        subtitle: 'Selecciona una zona primero',
        icon: Icons.search_rounded,
        child: _buildEmptyState(
          icon: Icons.warehouse_outlined,
          title: 'Sin zona seleccionada',
          description:
              'Selecciona una zona en el panel anterior para buscar productos.',
        ),
      );
    }
    return _buildWebCard(
      title: 'Agregar Productos',
      subtitle: 'Buscando en ${_selectedZone!['denominacion']}',
      icon: Icons.search_rounded,
      trailing: _isLoadingProduct
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: 320,
          child: ProductSelectorWidget(
            searchType: ProductSearchType.withStock,
            locationId: _selectedZone!['id'],
            requireInventory: true,
            searchHint:
                'Buscar en ${_selectedZone!['denominacion']}...',
            onProductSelected: _onProductSelected,
          ),
        ),
      ),
    );
  }

  Widget _buildRowsCard() {
    final isExcess = widget.adjustmentType == 'excess';
    return _buildWebCard(
      title: 'Productos a Ajustar',
      subtitle: '${_rows.length} fila(s) preparada(s)',
      icon: Icons.list_alt_rounded,
      iconColor: AppColors.success,
      trailing: _rows.isNotEmpty
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_rows.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            )
          : null,
      child: _rows.isEmpty
          ? _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Sin productos',
              description:
                  'Agrega productos buscándolos arriba para preparar el ajuste.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRowsHeader(),
                ..._rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  return _buildRow(row, i, isExcess);
                }).toList(),
              ],
            ),
    );
  }

  Widget _buildRowsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Producto / Presentación',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              'Stock',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              'Cantidad',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'Resultado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildRow(_AdjustRow row, int index, bool isExcess) {
    return StatefulBuilder(
      builder: (ctx, setRowState) {
        final ajuste = row.nuevaCantidad;
        final ajusteAplicado = isExcess ? -(ajuste ?? 0) : (ajuste ?? 0);
        final resultado = ajuste != null
            ? row.stockActual + ajusteAplicado
            : row.stockActual;
        final hasChange = ajuste != null && ajuste >= 0.01;
        final isLast = index == _rows.length - 1;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                index.isEven ? Colors.white : const Color(0xFFFAFBFC),
            border: Border(
              left: BorderSide(color: Colors.grey.shade200),
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
            borderRadius: isLast
                ? const BorderRadius.vertical(bottom: Radius.circular(10))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.nombreProducto,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.nombrePresentacion,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  row.stockActual.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: row.cantidadController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setRowState(() {}),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  hasChange ? resultado.toStringAsFixed(1) : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: hasChange
                        ? (resultado >= 0
                            ? AppColors.success
                            : AppColors.error)
                        : Colors.grey.shade400,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.error,
                  tooltip: 'Eliminar fila',
                  onPressed: () => _removeRow(row),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // SHARED HELPERS
  // =====================================================
  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? helperText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      labelStyle: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget _buildWebCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
  }) {
    final Color accentColor = iconColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
