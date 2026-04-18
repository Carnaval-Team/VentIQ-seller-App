import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({super.key});

  @override
  State<InventoryTransferScreen> createState() =>
      _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorizadoPorController = TextEditingController();
  final _observacionesController = TextEditingController();

  // Static variables to persist field values across screen instances
  static String _lastAutorizadoPor = '';
  static String _lastObservaciones = '';

  List<Map<String, dynamic>> _selectedProducts = [];
  List<Warehouse> _warehouses = [];
  WarehouseZone? _selectedSourceLocation;
  WarehouseZone? _selectedDestinationLocation;
  bool _isLoading = false;
  bool _isLoadingWarehouses = true;

  // Inline product list state
  List<Map<String, dynamic>> _sourceProducts = [];
  bool _isLoadingProducts = false;
  // qty controllers keyed by variant_key
  final Map<String, TextEditingController> _qtyControllers = {};
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredProducts {
    if (_searchQuery.isEmpty) return _sourceProducts;
    final q = _searchQuery.toLowerCase();
    return _sourceProducts
        .where((p) =>
            (p['nombre_producto']?.toString().toLowerCase() ?? '').contains(q))
        .toList();
  }

  // Progress tracking
  double _transferProgress = 0.0;
  String _transferStatus = '';
  int _currentStep = 0;
  int _totalSteps = 0;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();

    // Load persisted values from previous entries
    _loadPersistedValues();
  }

  void _loadPersistedValues() {
    _autorizadoPorController.text = _lastAutorizadoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastAutorizadoPor = _autorizadoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _autorizadoPorController.dispose();
    _observacionesController.dispose();
    _searchController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    try {
      setState(() => _isLoadingWarehouses = true);
      final warehouseService = WarehouseService();
      final warehouses = await warehouseService.listWarehousesOK();

      setState(() {
        _warehouses = warehouses;
        _isLoadingWarehouses = false;
      });
    } catch (e) {
      setState(() => _isLoadingWarehouses = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar almacenes: $e')),
        );
      }
    }
  }

  Future<void> _loadSourceProducts() async {
    if (_selectedSourceLocation == null) return;
    final layoutId = _getZoneIdFromLocation(_selectedSourceLocation!);

    setState(() {
      _isLoadingProducts = true;
      _sourceProducts = [];
      // Dispose old controllers
      for (final c in _qtyControllers.values) {
        c.dispose();
      }
      _qtyControllers.clear();
      _selectedProducts = [];
      _searchController.clear();
      _searchQuery = '';
    });

    try {
      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: 0, // 0 means all products
        idLayout: layoutId,
      );

      // If returns empty with idProducto=0, fall back to getInventoryProducts
      List<Map<String, dynamic>> products;
      if (variants.isNotEmpty) {
        products = variants;
      } else {
        final resp = await InventoryService.getInventoryProducts(
          idUbicacion: layoutId,
          mostrarSinStock: false,
        );
        products = resp.products
            .where((p) => p.cantidadFinal > 0)
            .map((p) => {
                  'id_producto': p.idProducto,
                  'nombre_producto': p.nombreProducto,
                  'sku_producto': p.skuProducto,
                  'id_variante': p.idVariante,
                  'variante_nombre': p.variante,
                  'id_opcion_variante': p.idOpcionVariante,
                  'opcion_variante_nombre': p.opcionVariante,
                  'id_presentacion': p.idPresentacion,
                  'presentacion_nombre': p.presentacion,
                  'presentacion_codigo': p.presentacion,
                  'stock_disponible': p.cantidadFinal,
                  'stock_reservado': p.stockReservado,
                  'stock_actual': p.cantidadFinal,
                  'precio_unitario': p.precioVenta ?? 0.0,
                  'id_layout': layoutId,
                  'variant_key':
                      '${p.id}_${p.idVariante ?? 'null'}_${p.idOpcionVariante ?? 'null'}_${p.idPresentacion ?? 'null'}',
                })
            .toList();
      }

      // Create qty controllers for each row
      final controllers = <String, TextEditingController>{};
      for (final p in products) {
        final key = p['variant_key']?.toString() ??
            '${p['id_producto']}_${p['id_presentacion']}';
        p['variant_key'] = key;
        controllers[key] = TextEditingController(text: '');
      }

      if (mounted) {
        setState(() {
          _sourceProducts = products;
          _qtyControllers.addAll(controllers);
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando productos del origen: $e');
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  /// Build _selectedProducts from qty inputs before submitting
  void _buildSelectedProductsFromInputs() {
    final sourceLayoutId = _getZoneIdFromLocation(_selectedSourceLocation!);
    final result = <Map<String, dynamic>>[];
    for (final p in _sourceProducts) {
      final key = p['variant_key'].toString();
      final qty = double.tryParse(_qtyControllers[key]?.text.trim() ?? '') ?? 0;
      if (qty > 0) {
        result.add({
          'id_producto': p['id_producto'],
          'nombre_producto': p['nombre_producto'],
          'cantidad': qty,
          'precio_unitario': p['precio_unitario'] ?? 0.0,
          'id_variante': p['id_variante'],
          'variante_nombre': p['variante_nombre'],
          'id_opcion_variante': p['id_opcion_variante'],
          'opcion_variante_nombre': p['opcion_variante_nombre'],
          'id_presentacion': p['id_presentacion'],
          'presentacion_nombre': p['presentacion_nombre'],
          'stock_disponible': p['stock_disponible'],
          'variant_key': key,
          'id_ubicacion': sourceLayoutId,
        });
      }
    }
    _selectedProducts = result;
  }

  void _showProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: const Text('Procesando Transferencia'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _transferProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _transferProgress < 1.0
                            ? AppColors.primary
                            : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_transferProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _transferStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  if (_totalSteps > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Paso $_currentStep de $_totalSteps',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _submitTransfer() async {
    _buildSelectedProductsFromInputs();
    if (!_formKey.currentState!.validate() || _selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete todos los campos y agregue al menos un producto con cantidad > 0',
          ),
        ),
      );
      return;
    }

    if (_selectedSourceLocation == null ||
        _selectedDestinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debe seleccionar ubicaciones de origen y destino'),
        ),
      );
      return;
    }

    // Validate that source and destination are different
    if (_selectedSourceLocation!.id == _selectedDestinationLocation!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Las ubicaciones de origen y destino no pueden ser las mismas',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _showProgressDialog();

    // Initialize progress tracking
    _totalSteps = 3; // Validación, Transferencia, Completar operaciones
    _currentStep = 0;
    _transferProgress = 0.0;

    try {
      print('🚀 === INICIO TRANSFERENCIA ===');
      print(
        '📍 Origen: ${_selectedSourceLocation!.name} (ID: ${_getZoneIdFromLocation(_selectedSourceLocation!)})',
      );
      print(
        '📍 Destino: ${_selectedDestinationLocation!.name} (ID: ${_getZoneIdFromLocation(_selectedDestinationLocation!)})',
      );
      print('📦 Productos: ${_selectedProducts.length}');

      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userUuid = await userPrefs.getUserId();

      if (idTienda == null || userUuid == null) {
        throw Exception('No se encontró información del usuario');
      }

      // Update progress: Validación completada
      setState(() {
        _currentStep = 1;
        _transferProgress = 0.2;
        _transferStatus = 'Validando datos...';
      });

      // ========== LOGGING DE DATOS DEL FORMULARIO ==========
      print('🔍 ===== DATOS DEL FORMULARIO DE TRANSFERENCIA =====');
      print('👤 Usuario UUID: $userUuid');
      print('🏪 ID Tienda: $idTienda');
      print('📝 Autorizado por: ${_autorizadoPorController.text}');
      print('📋 Observaciones: ${_observacionesController.text}');
      print(
        '📍 Ubicación origen: ${_selectedSourceLocation!.displayName} (ID: ${_selectedSourceLocation!.id})',
      );
      print(
        '📍 Ubicación destino: ${_selectedDestinationLocation!.displayName} (ID: ${_selectedDestinationLocation!.id})',
      );
      print('📦 Productos seleccionados (${_selectedProducts.length}):');

      for (int i = 0; i < _selectedProducts.length; i++) {
        final product = _selectedProducts[i];
        print('   [$i] Producto:');
        print('       - ID Producto: ${product['id_producto']}');
        print('       - Nombre: ${product['nombre_producto']}');
        print('       - Cantidad: ${product['cantidad']}');
        print('       - Precio Unitario: ${product['precio_unitario']}');
        print('       - ID Variante: ${product['id_variante']}');
        print('       - Variante: ${product['variante_nombre']}');
        print('       - ID Opción Variante: ${product['id_opcion_variante']}');
        print('       - Opción: ${product['opcion_variante_nombre']}');
        print('       - ID Presentación: ${product['id_presentacion']}');
        print('       - Presentación: ${product['presentacion_nombre']}');
      }
      print('================================================');

      // Extract layout IDs from location objects FIRST
      final sourceLayoutId = _getZoneIdFromLocation(_selectedSourceLocation!);
      final destinationLayoutId = _getZoneIdFromLocation(
        _selectedDestinationLocation!,
      );

      // Extract warehouse IDs from location IDs
      final sourceWarehouseId = _getWarehouseIdFromLocation(
        _selectedSourceLocation!,
      );
      final destinationWarehouseId = _getWarehouseIdFromLocation(
        _selectedDestinationLocation!,
      );

      print('🏭 ID Almacén Origen: $sourceWarehouseId');
      print('🏭 ID Almacén Destino: $destinationWarehouseId');
      print('🔗 ID Layout Origen: $sourceLayoutId');
      print('🔗 ID Layout Destino: $destinationLayoutId');

      // Prepare products list for transfer
      final productosParaEnviar =
          _selectedProducts.map((product) {
            return {
              'id_producto': product['id_producto'],
              'cantidad': product['cantidad'],
              'precio_unitario': product['precio_unitario'] ?? 0.0,
              'id_variante': product['id_variante'],
              'id_presentacion': product['id_presentacion'],
              // CRÍTICO: Agregar ubicación de origen para la extracción
              'id_ubicacion': sourceLayoutId,
            };
          }).toList();

      print('📤 Productos preparados para envío:');
      for (int i = 0; i < productosParaEnviar.length; i++) {
        print('   [$i] ${productosParaEnviar[i]}');
        print(
          '   [$i] DEBUG id_presentacion: ${productosParaEnviar[i]['id_presentacion']} (${productosParaEnviar[i]['id_presentacion'].runtimeType})',
        );
        print(
          '   [$i] DEBUG id_ubicacion: ${productosParaEnviar[i]['id_ubicacion']} (ubicación origen)',
        );
      }

      print('🔄 Iniciando transferencia unificada entre layouts...');
      print('📞 Llamando a: InventoryService.transferBetweenLayouts');
      print('📋 Parámetros:');
      print('   - idLayoutOrigen: $sourceLayoutId');
      print('   - idLayoutDestino: $destinationLayoutId');
      print('   - productos: $productosParaEnviar');
      print('   - autorizadoPor: ${_autorizadoPorController.text}');
      print('   - observaciones: ${_observacionesController.text}');

      // Update progress: Iniciando transferencia
      setState(() {
        _currentStep = 2;
        _transferProgress = 0.4;
        _transferStatus = 'Procesando transferencia...';
      });

      // Use unified transfer function for all scenarios
      final result = await InventoryService.transferBetweenLayouts(
        idLayoutOrigen: sourceLayoutId,
        idLayoutDestino: destinationLayoutId,
        productos: productosParaEnviar,
        autorizadoPor: _autorizadoPorController.text,
        observaciones: _observacionesController.text,
        estadoInicial: 1, // Pendiente - can be confirmed later
      );

      print('📋 Resultado de la transferencia:');
      print('   - Status: ${result['status']}');
      print('   - Message: ${result['message']}');
      print('   - ID Extracción: ${result['id_extraccion']}');
      print('   - ID Recepción: ${result['id_recepcion']}');

      if (result['extraction_completion'] != null) {
        print('📤 Completado extracción:');
        print('   - Status: ${result['extraction_completion']['status']}');
        print('   - Message: ${result['extraction_completion']['message']}');
      }

      if (result['reception_completion'] != null) {
        print('📥 Completado recepción:');
        print('   - Status: ${result['reception_completion']['status']}');
        print('   - Message: ${result['reception_completion']['message']}');
      }

      if (result['status'] == 'success') {
        // Update progress: Completando operaciones
        setState(() {
          _currentStep = 3;
          _transferProgress = 0.7;
          _transferStatus = 'Completando operaciones...';
        });

        // Complete both operations automatically if transfer was successful
        if (result['id_extraccion'] != null && result['id_recepcion'] != null) {
          try {
            print('🔄 Completando operación de extracción...');
            print('📊 ID Extracción: ${result['id_extraccion']}');

            final completeExtractionResult =
                await InventoryService.completeOperation(
                  idOperacion: result['id_extraccion'],
                  comentario:
                      'Extracción de transferencia completada automáticamente - ${_observacionesController.text.trim()}',
                  uuid: userUuid,
                );

            print(
              '📋 Resultado completeOperation (extracción): $completeExtractionResult',
            );

            if (completeExtractionResult['status'] == 'success') {
              print('✅ Extracción completada exitosamente');
              print(
                '📊 Productos afectados (extracción): ${completeExtractionResult['productos_afectados']}',
              );
            } else {
              print(
                '⚠️ Advertencia al completar extracción: ${completeExtractionResult['message']}',
              );
            }

            print('🔄 Completando operación de recepción...');
            print('📊 ID Recepción: ${result['id_recepcion']}');

            final completeReceptionResult =
                await InventoryService.completeOperation(
                  idOperacion: result['id_recepcion'],
                  comentario:
                      'Recepción de transferencia completada automáticamente - ${_observacionesController.text.trim()}',
                  uuid: userUuid,
                );

            print(
              '📋 Resultado completeOperation (recepción): $completeReceptionResult',
            );

            if (completeReceptionResult['status'] == 'success') {
              print('✅ Recepción completada exitosamente');
              print(
                '📊 Productos afectados (recepción): ${completeReceptionResult['productos_afectados']}',
              );
            } else {
              print(
                '⚠️ Advertencia al completar recepción: ${completeReceptionResult['message']}',
              );
            }
          } catch (completeError, stackTrace) {
            print(
              '❌ Error al completar operaciones de transferencia: $completeError',
            );
            print('📍 StackTrace completo: $stackTrace');
            // Don't throw here - transfer was successful, completion is secondary
          }
        } else {
          print('⚠️ No se obtuvieron IDs de operaciones para completar');
        }

        // Save the values for future use before showing success message
        _savePersistedValues();

        // Update progress: Completado
        setState(() {
          _currentStep = 3;
          _transferProgress = 1.0;
          _transferStatus = '¡Transferencia completada!';
        });

        // Wait a moment to show the completed state
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.pop(context); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Transferencia registrada exitosamente',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context); // Close transfer screen
        }
      } else {
        throw Exception(
          result['message'] ?? 'Error desconocido en la transferencia',
        );
      }
    } catch (e) {
      print('❌ Error en _submitTransfer: $e');
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar transferencia: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Extract warehouse ID from location object
  int _getWarehouseIdFromLocation(WarehouseZone location) {
    // Try to get warehouse ID from the location's warehouse property
    if (location.warehouseId != null) {
      return int.tryParse(location.warehouseId) ?? 1;
    }

    // Fallback: find warehouse by looking through all warehouses
    for (final warehouse in _warehouses) {
      if (warehouse.zones.any((zone) => zone.id == location.id)) {
        return int.tryParse(warehouse.id) ?? 1;
      }
    }

    // Default fallback
    return 1;
  }

  /// Extract zone ID from location object
  int _getZoneIdFromLocation(WarehouseZone location) {
    // Clean the location ID if it has prefixes
    String cleanId = location.id;
    if (cleanId.startsWith('z') || cleanId.startsWith('w')) {
      cleanId = cleanId.substring(1);
    }
    return int.tryParse(cleanId) ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Transferencia de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildTransferInfoSection(),
                        const SizedBox(height: 24),
                        _buildSourceLocationSection(),
                        const SizedBox(height: 24),
                        _buildDestinationLocationSection(),
                        const SizedBox(height: 24),
                        _buildProductSectionHeader(),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  ),
                  ..._buildProductSlivers(),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Transferencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _autorizadoPorController,
              decoration: const InputDecoration(
                labelText: 'Autorizado por',
                border: OutlineInputBorder(),
              ),
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceLocationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación de Origen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoadingWarehouses
                ? const Center(child: CircularProgressIndicator())
                : _buildZoneDropdown(isSource: true),
            if (_selectedSourceLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.output, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Origen:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _selectedSourceLocation?.name ?? 'No seleccionado',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationLocationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación de Destino',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoadingWarehouses
                ? const Center(child: CircularProgressIndicator())
                : _buildZoneDropdown(isSource: false),
            if (_selectedDestinationLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.input, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Destino:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _selectedDestinationLocation?.name ??
                                'No seleccionado',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Header card for the product section (rendered as a sliver item)
  Widget _buildProductSectionHeader() {
    final isEnabled = _selectedSourceLocation != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: !isEnabled
                        ? Colors.grey
                        : _isLoadingProducts
                        ? Colors.blue
                        : Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Productos a Transferir',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (!isEnabled) ...[  
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Seleccione una zona de origen primero',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_isLoadingProducts) ...[  
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
            ] else if (_sourceProducts.isEmpty) ...[  
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'No hay productos con existencia en esta zona',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
              const SizedBox(height: 10),
              // Column header row
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Producto / Presentación',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'Disponible',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      'Cantidad',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      'Quedará',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  /// Product rows as lazy slivers — only visible rows are built
  List<Widget> _buildProductSlivers() {
    final filtered = _filteredProducts;
    if (_sourceProducts.isEmpty) return [];
    if (filtered.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: Text(
                'Sin resultados para "$_searchQuery"',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final isLast = index == filtered.length - 1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProductRow(filtered[index]),
                  if (!isLast) const Divider(height: 1),
                ],
              );
            },
            childCount: filtered.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final key = product['variant_key'].toString();
    final ctrl = _qtyControllers[key]!;
    final stock = (product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
    final nombre = product['nombre_producto']?.toString() ?? '';
    final presNombre = product['presentacion_nombre']?.toString() ?? '';
    final varNombre = product['variante_nombre']?.toString() ?? '';
    final hasVariant = varNombre.isNotEmpty && varNombre != 'Sin variante';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Product name + presentation
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (presNombre.isNotEmpty)
                  Text(
                    presNombre + (hasVariant ? ' · $varNombre' : ''),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          // Available stock
          SizedBox(
            width: 68,
            child: Text(
              stock.toInt().toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: stock > 0 ? Colors.green[700] : Colors.red[600],
              ),
            ),
          ),
          // Qty input
          SizedBox(
            width: 72,
            child: StatefulBuilder(
              builder: (context, setRowState) {
                return TextFormField(
                  controller: ctrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    hintText: '0',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final q = double.tryParse(val.trim());
                    if (q == null || q < 0) return 'Inválido';
                    if (q > stock) return '>stock';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                );
              },
            ),
          ),
          // Remaining after transfer
          SizedBox(
            width: 64,
            child: Builder(builder: (context) {
              final qty = double.tryParse(ctrl.text.trim()) ?? 0;
              final remaining = stock - qty;
              final isValid = qty >= 0 && qty <= stock;
              return Text(
                isValid ? remaining.toInt().toString() : '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: !isValid
                      ? Colors.red
                      : remaining == 0
                      ? Colors.orange[700]
                      : Colors.blueGrey[700],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          Builder(builder: (context) {
            final selected = _sourceProducts
                .where((p) {
                  final key = p['variant_key'].toString();
                  final qty =
                      double.tryParse(_qtyControllers[key]?.text.trim() ?? '') ??
                      0;
                  return qty > 0;
                })
                .length;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Productos a transferir:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$selected',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitTransfer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child:
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                        'Registrar Transferencia',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneDropdown({required bool isSource}) {
    final List<Map<String, dynamic>> flatZones = [];
    for (var warehouse in _warehouses) {
      for (var zone in warehouse.zones) {
        flatZones.add({'warehouse': warehouse.name, 'zone': zone});
      }
    }

    final selectedZone = isSource
        ? _selectedSourceLocation
        : _selectedDestinationLocation;

    return DropdownButtonFormField<WarehouseZone>(
      value: selectedZone,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: Text(isSource ? 'Seleccionar origen' : 'Seleccionar destino'),
      items:
          flatZones.map((item) {
            final WarehouseZone zone = item['zone'];
            final String warehouseName = item['warehouse'];
            final String displayName = '$warehouseName - ${zone.name}';

            return DropdownMenuItem<WarehouseZone>(
              value: zone,
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
      onChanged: (WarehouseZone? newZone) {
        setState(() {
          if (isSource) {
            _selectedSourceLocation = newZone;
          } else {
            _selectedDestinationLocation = newZone;
          }
        });
        if (isSource) _loadSourceProducts();
      },
    );
  }

  Widget _buildWarehouseTree({required bool isSource}) {
    // Keeping this for reference or if needed later, but it's no longer used in the build method
    return Container();
  }

  String _getWarehouseName(String warehouseId) {
    final warehouse = _warehouses.firstWhere(
      (w) => w.id == warehouseId,
      orElse:
          () => Warehouse(
            id: warehouseId,
            name: 'Almacén desconocido',
            description: 'Almacén no encontrado',
            address: '',
            city: '',
            country: 'Chile',
            type: 'principal',
            createdAt: DateTime.now(),
            zones: [],
            denominacion: 'Almacén desconocido',
            direccion: '',
          ),
    );
    return warehouse.name;
  }

}

// Product Quantity Dialog - Enhanced with location-specific variants
class _ProductQuantityDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(Map<String, dynamic>) onAdd;
  final int? sourceLayoutId; // ID de la ubicación origen para filtrar variantes

  const _ProductQuantityDialog({
    required this.product,
    required this.onAdd,
    this.sourceLayoutId,
  });

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLocationSpecificVariants();
  }

  Future<void> _loadLocationSpecificVariants() async {
    if (widget.sourceLayoutId == null) {
      print('⚠️ No se especificó ubicación origen, usando datos genéricos');
      _initializeFallbackVariants();
      return;
    }

    setState(() => _isLoadingVariants = true);

    try {
      print('🔍 Cargando variantes específicas de la ubicación...');
      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: int.parse(widget.product['id'].toString()),
        idLayout: widget.sourceLayoutId!,
      );

      if (variants.isNotEmpty) {
        setState(() {
          _availableVariants = variants;
          _selectedVariant = variants.first;
          _maxAvailableStock = _selectedVariant!['stock_disponible'];
          _isLoadingVariants = false;
        });
        print('✅ Cargadas ${variants.length} variantes con stock');
        return;
      }

      // Si no hay variantes con stock, buscar presentaciones configuradas en la zona
      print(
        '⚠️ No se encontraron variantes con stock, buscando presentaciones en la zona...',
      );
      final presentations =
          await InventoryService.getProductPresentationsInZone(
            idProducto: int.parse(widget.product['id'].toString()),
            idLayout: widget.sourceLayoutId!,
          );

      if (presentations.isNotEmpty) {
        setState(() {
          _availableVariants = presentations;
          _selectedVariant = presentations.first;
          _maxAvailableStock = _selectedVariant!['stock_disponible'];
          _isLoadingVariants = false;
        });
        print('✅ Cargadas ${presentations.length} presentaciones de la zona');
      } else {
        print(
          '⚠️ No se encontraron presentaciones configuradas, usando fallback genérico',
        );
        _initializeFallbackVariants();
      }
    } catch (e) {
      print('❌ Error cargando variantes: $e');
      _initializeFallbackVariants();
    }
  }

  void _initializeFallbackVariants() {
    // Fallback usando datos del producto base
    setState(() {
      _availableVariants = [
        {
          'id_producto': int.parse(widget.product['id'].toString()),
          'nombre_producto':
              widget.product['denominacion'] ??
              widget.product['nombre_producto'] ??
              'Sin nombre',
          'sku_producto': widget.product['sku'] ?? '',
          'id_variante': null,
          'variante_nombre': 'Sin variante',
          'id_opcion_variante': null,
          'opcion_variante_nombre': 'Única',
          'id_presentacion':
              1, // Use default presentation ID (1 = unidad) instead of null
          'presentacion_nombre': 'Unidad',
          'presentacion_codigo': 'UN',
          'stock_disponible':
              (widget.product['stock_disponible'] ?? 0).toDouble(),
          'stock_reservado': 0.0,
          'stock_actual': (widget.product['stock_disponible'] ?? 0).toDouble(),
          'precio_unitario':
              (widget.product['precio_unitario'] ?? 0).toDouble(),
          'variant_key': 'null_null_1',
        },
      ];
      _selectedVariant = _availableVariants.first;
      _maxAvailableStock = _selectedVariant!['stock_disponible'];
      _isLoadingVariants = false;
    });
  }

  void _onVariantChanged(Map<String, dynamic>? variant) {
    if (variant != null) {
      setState(() {
        _selectedVariant = variant;
        _maxAvailableStock = variant['stock_disponible'];
        // Reset quantity if it exceeds new max
        final currentQuantity = double.tryParse(_quantityController.text) ?? 1;
        if (currentQuantity > _maxAvailableStock) {
          _quantityController.text = _maxAvailableStock.toInt().toString();
        }
      });
    }
  }

  String _buildVariantDisplayName(Map<String, dynamic> variant) {
    List<String> parts = [];

    if (variant['variante_nombre'] != null &&
        variant['variante_nombre'] != 'Sin variante') {
      parts.add(variant['variante_nombre'].toString());
    }

    if (variant['opcion_variante_nombre'] != null &&
        variant['opcion_variante_nombre'] != 'Única') {
      parts.add(variant['opcion_variante_nombre'].toString());
    }

    if (variant['presentacion_nombre'] != null) {
      parts.add(variant['presentacion_nombre'].toString());
    }

    final displayName = parts.isEmpty ? 'Estándar' : parts.join(' - ');
    final stock = (variant['stock_disponible'] ?? 0).toInt();

    return '$displayName (Stock: $stock)';
  }

  @override
  Widget build(BuildContext context) {
    final productName =
        widget.product['denominacion']?.toString() ??
        widget.product['name']?.toString() ??
        widget.product['nombre_producto']?.toString() ??
        'Producto';

    return AlertDialog(
      title: Text('Agregar $productName'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Información del producto
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product['denominacion']?.toString() ??
                                widget.product['name']?.toString() ??
                                widget.product['nombre_producto']?.toString() ??
                                'Sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if ((widget.product['sku']?.toString() ?? '')
                              .isNotEmpty)
                            Text(
                              'SKU: ${widget.product['sku']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Selector de variantes/presentaciones
              if (_isLoadingVariants)
                const CircularProgressIndicator()
              else if (_availableVariants.isNotEmpty) ...[
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedVariant,
                  decoration: const InputDecoration(
                    labelText: 'Variante / Presentación',
                    border: OutlineInputBorder(),
                    helperText:
                        'Seleccione la variante específica a transferir',
                  ),
                  items:
                      _availableVariants.map((variant) {
                        return DropdownMenuItem(
                          value: variant,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              _buildVariantDisplayName(variant),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        );
                      }).toList(),
                  onChanged: _onVariantChanged,
                  validator:
                      (value) =>
                          value == null ? 'Seleccione una variante' : null,
                ),
                const SizedBox(height: 16),
              ],

              // Campo de cantidad con validación
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  border: const OutlineInputBorder(),
                  helperText:
                      _maxAvailableStock > 0
                          ? 'Máximo disponible: ${_maxAvailableStock.toInt()}'
                          : 'Sin stock disponible',
                  helperStyle: TextStyle(
                    color: _maxAvailableStock > 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty == true) return 'Campo requerido';
                  final quantity = double.tryParse(value!);
                  if (quantity == null || quantity <= 0) {
                    return 'Ingrese una cantidad válida';
                  }
                  if (quantity > _maxAvailableStock) {
                    return 'Cantidad excede el stock disponible (${_maxAvailableStock.toInt()})';
                  }
                  return null;
                },
              ),

              // Información adicional del stock
              if (_selectedVariant != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Stock disponible:',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${_selectedVariant!['stock_disponible'].toInt()}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedVariant!['stock_reservado'] > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Stock reservado:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${_selectedVariant!['stock_reservado'].toInt()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _maxAvailableStock <= 0
                  ? null
                  : () {
                    if (_formKey.currentState!.validate() &&
                        _selectedVariant != null) {
                      final productData = {
                        'id_producto': _selectedVariant!['id_producto'],
                        'nombre_producto': _selectedVariant!['nombre_producto'],
                        'cantidad': double.parse(_quantityController.text),
                        'precio_unitario': _selectedVariant!['precio_unitario'],
                        'id_variante': _selectedVariant!['id_variante'],
                        'variante_nombre': _selectedVariant!['variante_nombre'],
                        'id_opcion_variante':
                            _selectedVariant!['id_opcion_variante'],
                        'opcion_variante_nombre':
                            _selectedVariant!['opcion_variante_nombre'],
                        'id_presentacion': _selectedVariant!['id_presentacion'],
                        'presentacion_nombre':
                            _selectedVariant!['presentacion_nombre'],
                        'stock_disponible':
                            _selectedVariant!['stock_disponible'],
                        'variant_key': _selectedVariant!['variant_key'],
                      };

                      // Debug logging for presentation ID tracking
                      print('🔍 DEBUG: ProductData creado en diálogo:');
                      print('   - id_producto: ${productData['id_producto']}');
                      print(
                        '   - nombre_producto: ${productData['nombre_producto']}',
                      );
                      print(
                        '   - id_presentacion: ${productData['id_presentacion']}',
                      );
                      print(
                        '   - presentacion_nombre: ${productData['presentacion_nombre']}',
                      );
                      print(
                        '   - _selectedVariant id_presentacion: ${_selectedVariant!['id_presentacion']}',
                      );
                      print(
                        '   - Tipo de id_presentacion: ${productData['id_presentacion'].runtimeType}',
                      );

                      widget.onAdd(productData);
                    }
                  },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
