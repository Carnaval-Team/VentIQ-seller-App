import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/product_selector_widget.dart';
import '../services/product_search_service.dart';
import '../widgets/presentacion_equivalencia_widget.dart';

class InventoryAdjustmentScreen extends StatefulWidget {
  final int operationType; // 3 para faltante (sumar), 4 para exceso (restar)
  final String adjustmentType; // 'shortage' o 'excess'

  const InventoryAdjustmentScreen({
    super.key,
    required this.operationType,
    required this.adjustmentType,
  });

  @override
  State<InventoryAdjustmentScreen> createState() => _InventoryAdjustmentScreenState();
}

// Modelo interno para una fila de ajuste (producto + presentación)
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

  String get rowKey => '${idProducto}_${idPresentacion ?? 'null'}_$idUbicacion';
  double? get nuevaCantidad => double.tryParse(cantidadController.text.trim());
  double get cantidadResultante => nuevaCantidad ?? stockActual;
  void dispose() => cantidadController.dispose();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _observationsController = TextEditingController();

  List<Map<String, dynamic>> _warehousesWithZones = [];
  Map<String, dynamic>? _selectedZone;

  final List<_AdjustRow> _rows = [];

  bool _isLoading = false;
  bool _isLoadingZones = false;
  bool _isLoadingProduct = false;

  @override
  void initState() {
    super.initState();
    // Load zones first, then products will be filtered by selected zone
    _loadInitialZones();
  }

  Future<void> _loadInitialZones() async {
    setState(() => _isLoadingZones = true);
    try {
      // Obtener todos los almacenes/zonas disponibles
      final warehouses = await WarehouseService().listWarehousesOK();
      
      // Convertir almacenes a formato de zonas para el dropdown
      final warehousesWithZones = warehouses.map((warehouse) => {
        'id': int.tryParse(warehouse.id) ?? 0,
        'name': warehouse.name,
        'denominacion': warehouse.denominacion ?? warehouse.name,
        'zones': warehouse.zones.map((zone) => {
          'id': int.tryParse(zone.id) ?? 0,
          'denominacion': zone.name,
          'code': zone.code ?? '',
        }).toList(),
      }).toList();
      
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _observationsController.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  void _onZoneSelected(Map<String, dynamic> zone) {
    setState(() {
      _selectedZone = zone;
      for (final r in _rows) r.dispose();
      _rows.clear();
    });
  }

  Future<void> _onProductSelected(Map<String, dynamic> product) async {
    if (_selectedZone == null) return;
    setState(() => _isLoadingProduct = true);
    try {
      final productId = int.tryParse(
            (product['id_producto'] ?? product['id'])?.toString() ?? '0') ?? 0;
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
            content: Text('No se encontraron presentaciones para este producto en la zona'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show dialog for each presentation
      for (final inv in response.products) {
        final key = '${productId}_${inv.idPresentacion ?? 'null'}_$zoneId';
        if (_rows.any((r) => r.rowKey == key)) continue;

        if (!mounted) return;
        
        await _showAdjustmentDialog(
          productId: productId,
          productName: inv.nombreProducto.isNotEmpty ? inv.nombreProducto : product['denominacion']?.toString() ?? 'Producto',
          presentationName: inv.presentacion.isNotEmpty ? inv.presentacion : 'Sin presentación',
          currentStock: inv.cantidadFinal,
          onSave: (adjustmentAmount) {
            setState(() {
              _rows.add(_AdjustRow(
                idProducto: productId,
                nombreProducto: inv.nombreProducto.isNotEmpty ? inv.nombreProducto : product['denominacion']?.toString() ?? 'Producto',
                idPresentacion: inv.idPresentacion,
                nombrePresentacion: inv.presentacion.isNotEmpty ? inv.presentacion : 'Sin presentación',
                idUbicacion: zoneId,
                stockActual: inv.cantidadFinal,
                cantidadController: TextEditingController(text: adjustmentAmount.toString()),
              ));
            });
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar producto: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingProduct = false);
    }
  }

  Future<void> _showAdjustmentDialog({
    required int productId,
    required String productName,
    required String presentationName,
    required double currentStock,
    required Function(double) onSave,
  }) async {
    final adjustmentController = TextEditingController();
    final isExcess = widget.adjustmentType == 'excess';

    return showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ajuste = double.tryParse(adjustmentController.text.trim()) ?? 0;
          final ajusteAplicado = isExcess ? -ajuste : ajuste;
          final resultado = currentStock + ajusteAplicado;

          return AlertDialog(
            title: Text('Ajustar: $productName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Presentación: $presentationName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  PresentacionEquivalenciaBanner(productId: productId),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Stock Actual:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            Text(currentStock.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: adjustmentController,
                          keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Cantidad a ${isExcess ? 'Restar' : 'Sumar'}',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.edit),
                            isDense: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Resultado:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            Text(resultado.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: resultado >= 0 ? Colors.green : Colors.red,
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: ajuste >= 0.01
                    ? () {
                        onSave(ajuste);
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Guardar'),
              ),
            ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una zona'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue al menos un producto'), backgroundColor: Colors.red),
      );
      return;
    }
    if (motivo.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El motivo debe tener al menos 5 caracteres'), backgroundColor: Colors.red),
      );
      return;
    }

    final rowsToProcess = _rows.where((r) {
      final ajuste = r.nuevaCantidad;
      return ajuste != null && ajuste >= 0.01;
    }).toList();

    if (rowsToProcess.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingrese la cantidad a ajustar en al menos una fila (mínimo 0.01 ${widget.adjustmentType == 'excess' ? 'a restar' : 'a sumar'})'),
          backgroundColor: Colors.orange,
        ),
      );
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
        // Apply sign based on adjustment type: excess subtracts, shortage adds
        final ajusteAplicado = widget.adjustmentType == 'excess' ? -ajuste : ajuste;
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
          print('❌ Error ajustando ${row.nombreProducto} / ${row.nombrePresentacion}: ${result['message']}');
        }
      }

      if (mounted) {
        if (errorCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount ajuste(s) registrado(s) exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount exitoso(s), $errorCount con error. Revisa la consola.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExcess = widget.adjustmentType == 'excess';
    final title = isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante';
    final color = isExcess ? const Color(0xFFFF6B35) : const Color(0xFFFF8C42);
    final icon = isExcess ? Icons.trending_up : Icons.trending_down;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20)),
        centerTitle: true,
        backgroundColor: color,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // ── Header ────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 10),
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Motivo ────────────────────────────────────────────────
              Text('Motivo del Ajuste *',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  hintText: 'Ej: Conteo físico, Merma, Error de registro',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 5) {
                    return 'Mínimo 5 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Observaciones ─────────────────────────────────────────
              Text('Observaciones',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _observationsController,
                decoration: const InputDecoration(
                  hintText: 'Información adicional (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // ── Selección de Zona ─────────────────────────────────────
              Row(children: [
                Icon(Icons.warehouse,
                    color: _selectedZone != null ? Colors.green : Colors.blue,
                    size: 20),
                const SizedBox(width: 8),
                Text('Zona',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_selectedZone != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedZone!['denominacion'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedZone = null;
                      for (final r in _rows) r.dispose();
                      _rows.clear();
                    }),
                    child: const Text('Cambiar'),
                  ),
                ],
              ]),
              const SizedBox(height: 8),

              if (_selectedZone == null) ...[
                if (_isLoadingZones)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: _warehousesWithZones.map((warehouse) {
                        return ExpansionTile(
                          leading:
                              const Icon(Icons.warehouse, color: Colors.blue),
                          title: Text(warehouse['name'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                              '${(warehouse['zones'] as List).length} zona(s)',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12)),
                          children: (warehouse['zones']
                                  as List<Map<String, dynamic>>)
                              .map<Widget>((zone) => ListTile(
                                    contentPadding: const EdgeInsets.only(
                                        left: 56, right: 16),
                                    leading: const Icon(Icons.location_on,
                                        color: Colors.orange, size: 18),
                                    title: Text(zone['denominacion'],
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    subtitle: (zone['code'] as String)
                                            .isNotEmpty
                                        ? Text('Código: ${zone['code']}',
                                            style: const TextStyle(
                                                fontSize: 11))
                                        : null,
                                    onTap: () => _onZoneSelected(zone),
                                  ))
                              .toList(),
                        );
                      }).toList(),
                    ),
                  ),
              ],

              // ── Búsqueda de productos (solo si hay zona) ──────────────
              if (_selectedZone != null) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Icon(Icons.search,
                      color: _rows.isNotEmpty ? Colors.green : Colors.blue,
                      size: 20),
                  const SizedBox(width: 8),
                  Text('Agregar Productos',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  if (_isLoadingProduct) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: ProductSelectorWidget(
                    searchType: ProductSearchType.withStock,
                    locationId: _selectedZone!['id'],
                    requireInventory: true,
                    searchHint:
                        'Buscar en ${_selectedZone!['denominacion']}...',
                    onProductSelected: _onProductSelected,
                  ),
                ),
              ],

              // ── Lista de productos a ajustar ──────────────────────────
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Icon(Icons.list_alt, color: Colors.indigo, size: 20),
                  const SizedBox(width: 8),
                  Text('Productos a Ajustar (${_rows.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),

                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                  ),
                  child: Row(children: [
                    Expanded(
                        flex: 4,
                        child: Text('Producto / Presentación',
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700))),
                    SizedBox(
                        width: 160,
                        child: Text('Stock',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700))),
                    SizedBox(
                        width: 200,
                        child: Text('Cantidad a\nAjustar',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700))),
                    SizedBox(
                        width: 160,
                        child: Text('Resultado',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700))),
                    const SizedBox(width: 32),
                  ]),
                ),

                // Table rows
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8)),
                  ),
                  child: Column(
                    children: _rows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;
                      return StatefulBuilder(
                        builder: (ctx, setRowState) {
                          final ajuste = row.nuevaCantidad; // adjustment amount (always positive from user)
                          // For excess: subtract; for shortage: add
                          final ajusteAplicado = isExcess ? -(ajuste ?? 0) : (ajuste ?? 0);
                          final resultado = ajuste != null
                              ? row.stockActual + ajusteAplicado
                              : row.stockActual;
                          final hasChange = ajuste != null && ajuste >= 0.01;

                          return Container(
                            decoration: BoxDecoration(
                              color: i.isEven
                                  ? Colors.white
                                  : Colors.grey.shade50,
                              border: i < _rows.length - 1
                                  ? Border(
                                      bottom: BorderSide(
                                          color: Colors.grey.shade200))
                                  : null,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Product + presentation name
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        row.nombreProducto,
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        row.nombrePresentacion,
                                        style: TextStyle(
                                            fontSize: 21,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Current stock
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    row.stockActual.toStringAsFixed(1),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                // Adjustment amount field (positive only)
                                SizedBox(
                                  width: 200,
                                  child: TextField(
                                    controller: row.cantidadController,
                                    keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      hintText: '0',
                                      hintStyle: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12),
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d+\.?\d{0,2}')),
                                    ],
                                    onChanged: (_) =>
                                        setRowState(() {}),
                                  ),
                                ),
                                // Resulting qty (Stock + adjustment)
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    hasChange
                                        ? resultado.toStringAsFixed(1)
                                        : '-',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: hasChange
                                          ? (resultado >= 0
                                              ? Colors.green.shade700
                                              : Colors.red.shade700)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                // Remove button
                                SizedBox(
                                  width: 40,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                    tooltip: 'Eliminar fila',
                                    onPressed: () => _removeRow(row),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // ── Submit button (fixed footer) ───────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitAdjustment,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isLoading
                        ? 'Procesando...'
                        : 'Registrar ${isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante'}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushNamedAndRemoveUntil(
                  context, '/dashboard', (route) => false);
              break;
            case 1:
              Navigator.pushNamed(context, '/products');
              break;
            case 2:
              Navigator.pushNamed(context, '/inventory');
              break;
            case 3:
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }
}
