import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/permissions_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/location_selector_widget.dart';
import '../widgets/presentacion_equivalencia_widget.dart';

class InventoryTransferWebScreen extends StatefulWidget {
  const InventoryTransferWebScreen({super.key});

  @override
  State<InventoryTransferWebScreen> createState() =>
      _InventoryTransferWebScreenState();
}

class _InventoryTransferWebScreenState
    extends State<InventoryTransferWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entregadoPorController = TextEditingController();
  final _transportadoPorController = TextEditingController();
  final _recibidoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _permissionsService = PermissionsService();

  // Persist across screen instances
  static String _lastEntregadoPor = '';
  static String _lastTransportadoPor = '';
  static String _lastRecibidoPor = '';
  static String _lastObservaciones = '';

  List<Map<String, dynamic>> _selectedProducts = [];
  WarehouseZone? _selectedSourceLocation;
  WarehouseZone? _selectedDestinationLocation;
  bool _isLoading = false;

  /// Solo el gerente puede "Registrar y Completar" en un solo paso.
  bool _canRegisterAndComplete = false;

  // Inline product list state
  List<Map<String, dynamic>> _sourceProducts = [];
  bool _isLoadingProducts = false;
  // qty controllers keyed by variant_key
  final Map<String, TextEditingController> _qtyControllers = {};
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Progress tracking
  double _transferProgress = 0.0;
  String _transferStatus = '';
  int _currentStep = 0;
  int _totalSteps = 0;

  List<Map<String, dynamic>> get _filteredProducts {
    if (_searchQuery.isEmpty) return _sourceProducts;
    final q = _searchQuery.toLowerCase();
    return _sourceProducts
        .where((p) =>
            (p['nombre_producto']?.toString().toLowerCase() ?? '').contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedValues();
    _loadGerentePermission();
  }

  Future<void> _loadGerentePermission() async {
    final role = await _permissionsService.getUserRole();
    if (!mounted) return;
    setState(() => _canRegisterAndComplete = role == UserRole.gerente);
  }

  void _loadPersistedValues() {
    _entregadoPorController.text = _lastEntregadoPor;
    _transportadoPorController.text = _lastTransportadoPor;
    _recibidoPorController.text = _lastRecibidoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastEntregadoPor = _entregadoPorController.text;
    _lastTransportadoPor = _transportadoPorController.text;
    _lastRecibidoPor = _recibidoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _transportadoPorController.dispose();
    _recibidoPorController.dispose();
    _observacionesController.dispose();
    _searchController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Extract zone/layout ID from location object.
  int _getLayoutIdFromLocation(WarehouseZone location) {
    return int.tryParse(location.id) ?? 0;
  }
  Future<void> _loadSourceProducts() async {
    if (_selectedSourceLocation == null) return;
    final layoutId = _getLayoutIdFromLocation(_selectedSourceLocation!);

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

      // Deduplicate by id_producto + id_presentacion, summing stock for duplicates
      final Map<String, Map<String, dynamic>> deduped = {};
      for (final p in products) {
        final dedupKey =
            '${p['id_producto']}_${p['id_presentacion'] ?? 'null'}';
        if (!deduped.containsKey(dedupKey)) {
          final entry = Map<String, dynamic>.from(p);
          entry['variant_key'] = dedupKey;
          deduped[dedupKey] = entry;
        } else {
          final existing = deduped[dedupKey]!;
          existing['stock_disponible'] =
              ((existing['stock_disponible'] as num?) ?? 0) +
                  ((p['stock_disponible'] as num?) ?? 0);
          existing['stock_actual'] =
              ((existing['stock_actual'] as num?) ?? 0) +
                  ((p['stock_actual'] as num?) ?? 0);
        }
      }
      final dedupedProducts = deduped.values.toList();

      // Create qty controllers for each row
      final controllers = <String, TextEditingController>{};
      for (final p in dedupedProducts) {
        final key = p['variant_key'].toString();
        controllers[key] = TextEditingController(text: '');
      }

      if (mounted) {
        setState(() {
          _sourceProducts = dedupedProducts;
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
    final sourceLayoutId = _getLayoutIdFromLocation(_selectedSourceLocation!);
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
      builder: (context) => WillPopScope(
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
                    _transferProgress < 1.0 ? AppColors.primary : Colors.green,
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
  Future<void> _submitTransfer({required bool completarOperaciones}) async {
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
        const SnackBar(
          content: Text('Debe seleccionar ubicaciones de origen y destino'),
        ),
      );
      return;
    }

    // Validate that source and destination are different
    if (_selectedSourceLocation!.id == _selectedDestinationLocation!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las ubicaciones de origen y destino no pueden ser las mismas',
          ),
        ),
      );
      return;
    }

    if (completarOperaciones && !_canRegisterAndComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo el gerente puede registrar y completar en un solo paso',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _showProgressDialog();

    // Initialize progress tracking
    _totalSteps = 2; // Validación + transferencia atómica (RPC)
    _currentStep = 0;
    _transferProgress = 0.0;

    try {
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

      // Extract layout IDs from location objects
      final sourceLayoutId =
          _getLayoutIdFromLocation(_selectedSourceLocation!);
      final destinationLayoutId =
          _getLayoutIdFromLocation(_selectedDestinationLocation!);

      // Prepare products list for transfer
      final productosParaEnviar = _selectedProducts.map((product) {
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

      // Update progress: Iniciando transferencia
      setState(() {
        _currentStep = 2;
        _transferProgress = 0.4;
        _transferStatus = completarOperaciones
            ? 'Registrando y completando transferencia...'
            : 'Registrando transferencia (pendiente)...';
      });

      // Use unified transfer function for all scenarios
      final result = await InventoryService.transferBetweenLayouts(
        idLayoutOrigen: sourceLayoutId,
        idLayoutDestino: destinationLayoutId,
        productos: productosParaEnviar,
        entregadoPor: _entregadoPorController.text.trim(),
        transportadoPor: _transportadoPorController.text.trim(),
        recibidoPor: _recibidoPorController.text.trim(),
        observaciones: _observacionesController.text,
        completarOperaciones: completarOperaciones,
      );

      if (result['status'] == 'success') {
        _savePersistedValues();

        setState(() {
          _currentStep = 2;
          _transferProgress = 1.0;
          _transferStatus = completarOperaciones
              ? '¡Transferencia registrada y completada!'
              : '¡Transferencia registrada (pendiente)!';
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
  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Transferencia de Inventario',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _submitTransfer(completarOperaciones: false),
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isLoading ? 'Procesando...' : 'Registrar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white70,
                disabledForegroundColor: AppColors.primary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTransferInfoCard(),
                  const SizedBox(height: 20),
                  _buildSourceLocationCard(),
                  const SizedBox(height: 20),
                  _buildDestinationLocationCard(),
                  const SizedBox(height: 20),
                  _buildProductsCard(),
                  const SizedBox(height: 20),
                  _buildSummaryCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // CARDS
  // =====================================================
  Widget _buildTransferInfoCard() {
    return _buildWebCard(
      title: 'Información de Transferencia',
      subtitle:
          'Indique quién entrega en origen, quién transporta y quién recibe',
      icon: Icons.swap_horiz,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _entregadoPorController,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: 'Entrega (origen) *',
              hint: 'Quién entrega la mercancía en el origen',
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ),
            validator: (value) =>
                value?.trim().isEmpty == true ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _transportadoPorController,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: 'Transporta *',
              hint: 'Quién lleva la mercancía al destino',
              prefixIcon: Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ),
            validator: (value) =>
                value?.trim().isEmpty == true ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _recibidoPorController,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: 'Recibe (destino) *',
              hint: 'Quién recibe la mercancía en el destino',
              prefixIcon: Icon(
                Icons.how_to_reg_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ),
            validator: (value) =>
                value?.trim().isEmpty == true ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _observacionesController,
            decoration: _inputDecoration(
              label: 'Observaciones',
              hint: 'Notas adicionales sobre la transferencia',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildSourceLocationCard() {
    return _buildWebCard(
      title: 'Ubicación de Origen',
      subtitle: 'Zona desde donde se transferirán los productos',
      icon: Icons.warehouse_outlined,
      iconColor: AppColors.warning,
      child: LocationSelectorWidget(
        type: LocationSelectorType.single,
        title: 'Seleccionar Ubicación de Origen',
        subtitle: 'Zona desde donde se transferirán los productos',
        selectedLocation: _selectedSourceLocation,
        onLocationChanged: (location) {
          setState(() => _selectedSourceLocation = location);
          _loadSourceProducts();
        },
        validationMessage: _selectedSourceLocation == null
            ? 'Debe seleccionar una ubicación de origen'
            : null,
      ),
    );
  }

  Widget _buildDestinationLocationCard() {
    return _buildWebCard(
      title: 'Ubicación de Destino',
      subtitle: 'Zona donde se recibirán los productos',
      icon: Icons.input,
      iconColor: AppColors.success,
      child: LocationSelectorWidget(
        type: LocationSelectorType.single,
        title: 'Seleccionar Ubicación de Destino',
        subtitle: 'Zona donde se recibirán los productos transferidos',
        selectedLocation: _selectedDestinationLocation,
        onLocationChanged: (location) =>
            setState(() => _selectedDestinationLocation = location),
        validationMessage: _selectedDestinationLocation == null
            ? 'Debe seleccionar una ubicación de destino'
            : null,
      ),
    );
  }
  Widget _buildProductsCard() {
    final int selectedCount = _sourceProducts.where((p) {
      final key = p['variant_key'].toString();
      final qty =
          double.tryParse(_qtyControllers[key]?.text.trim() ?? '') ?? 0;
      return qty > 0;
    }).length;

    return _buildWebCard(
      title: 'Productos a Transferir',
      subtitle: _selectedSourceLocation == null
          ? 'Selecciona una zona de origen primero'
          : 'Indica la cantidad a transferir por producto',
      icon: Icons.inventory_2_outlined,
      trailing: selectedCount > 0
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$selectedCount',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            )
          : null,
      child: _buildProductsContent(),
    );
  }

  Widget _buildProductsContent() {
    if (_selectedSourceLocation == null) {
      return _buildEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Sin zona de origen',
        description:
            'Selecciona una zona de origen en el panel anterior para cargar los productos con existencia.',
      );
    }
    if (_isLoadingProducts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_sourceProducts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Sin existencias',
        description: 'No hay productos con existencia en esta zona.',
      );
    }

    final filtered = _filteredProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          decoration: _inputDecoration(
            label: 'Buscar producto',
            hint: 'Filtrar por nombre...',
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: Colors.grey.shade500,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
        ),
        const SizedBox(height: 14),
        _buildRowsHeader(),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Sin resultados para "$_searchQuery"',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildProductRow(filtered[index]),
          ),
      ],
    );
  }

  Widget _buildRowsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Producto / Presentación',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.4,
                ),
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
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Cantidad',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
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
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final key = product['variant_key'].toString();
    final ctrl = _qtyControllers[key]!;
    final stock = (product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
    final nombre = product['nombre_producto']?.toString() ?? '';
    final presNombre = product['presentacion_nombre']?.toString() ?? '';
    final varNombre = product['variante_nombre']?.toString() ?? '';
    final hasVariant = varNombre.isNotEmpty && varNombre != 'Sin variante';
    final idProducto = (product['id_producto'] as num?)?.toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
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
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (presNombre.isNotEmpty)
                  Text(
                    presNombre + (hasVariant ? ' · $varNombre' : ''),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
          if (idProducto != null)
            PresentacionEquivalenciaIconButton(
              productId: idProducto,
              productName: nombre,
              iconSize: 18,
            ),
          // Qty input
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: ctrl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                hintText: '0',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return null;
                final q = double.tryParse(val.trim());
                if (q == null || q < 0) return 'Inv.';
                if (q > stock) return '>stock';
                return null;
              },
              onChanged: (_) => setState(() {}),
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

  Widget _buildSummaryCard() {
    final int selectedCount = _sourceProducts.where((p) {
      final key = p['variant_key'].toString();
      final qty =
          double.tryParse(_qtyControllers[key]?.text.trim() ?? '') ?? 0;
      return qty > 0;
    }).length;

    return _buildWebCard(
      title: 'Resumen',
      subtitle: 'Confirma y registra la transferencia',
      icon: Icons.summarize_outlined,
      iconColor: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Productos a transferir',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$selectedCount',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : () => _submitTransfer(completarOperaciones: false),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 20),
            label: Text(
              _isLoading ? 'Procesando...' : 'Registrar Transferencia',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_canRegisterAndComplete) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _submitTransfer(completarOperaciones: true),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _isLoading
                    ? 'Procesando...'
                    : 'Registrar y Completar Transferencia',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  // =====================================================
  // UI HELPERS
  // =====================================================
  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? helperText,
    String? prefixText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixText: prefixText,
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
