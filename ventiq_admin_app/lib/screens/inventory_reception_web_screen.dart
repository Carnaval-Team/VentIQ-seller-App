import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../models/ai_reception_models.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';
import '../services/product_search_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/ai_reception_sheet.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/location_selector_widget.dart';
import '../widgets/product_quantity_dialog.dart';
import '../widgets/product_selector_widget.dart';
import '../widgets/reception_total_widget.dart';

class InventoryReceptionWebScreen extends StatefulWidget {
  const InventoryReceptionWebScreen({super.key});

  @override
  State<InventoryReceptionWebScreen> createState() =>
      _InventoryReceptionWebScreenState();
}

class _InventoryReceptionWebScreenState
    extends State<InventoryReceptionWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entregadoPorController = TextEditingController();
  final _recibidoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _montoTotalController = TextEditingController();

  static String _lastEntregadoPor = '';
  static String _lastRecibidoPor = '';
  static String _lastObservaciones = '';

  final String _selectedCurrency = 'USD';
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  WarehouseZone? _selectedLocation;
  bool _isLoading = false;
  bool _isLoadingMotivos = true;
  Supplier? _selectedSupplier;
  List<Map<String, dynamic>> _proveedores = [];
  Map<String, dynamic>? _selectedProveedor;
  bool _isLoadingProveedores = false;

  @override
  void initState() {
    super.initState();
    _loadMotivoOptions();
    _loadProveedores();
    _entregadoPorController.text = _lastEntregadoPor;
    _recibidoPorController.text = _lastRecibidoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastEntregadoPor = _entregadoPorController.text;
    _lastRecibidoPor = _recibidoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _recibidoPorController.dispose();
    _observacionesController.dispose();
    _montoTotalController.dispose();
    super.dispose();
  }

  Future<void> _loadMotivoOptions() async {
    try {
      setState(() => _isLoadingMotivos = true);
      final motivos = await InventoryService.getMotivoRecepcionOptions();
      setState(() {
        _motivoOptions = motivos;
        if (motivos.isNotEmpty) _selectedMotivo = motivos.first;
        _isLoadingMotivos = false;
      });
    } catch (e) {
      setState(() => _isLoadingMotivos = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar motivos: $e')),
        );
      }
    }
  }

  Future<void> _loadProveedores() async {
    try {
      setState(() => _isLoadingProveedores = true);
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) throw Exception('No se encontró ID de tienda');

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_dat_proveedor')
          .select('id, denominacion, sku_codigo')
          .eq('idtienda', idTienda)
          .order('denominacion', ascending: true);

      setState(() {
        _proveedores = List<Map<String, dynamic>>.from(response);
        _selectedProveedor = null;
        _isLoadingProveedores = false;
      });
    } catch (e) {
      setState(() => _isLoadingProveedores = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
        );
      }
    }
  }

  Future<void> _openAiAssistant() async {
    final result = await showModalBottomSheet<AiReceptionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AiReceptionSheet(),
    );

    if (result == null) return;

    WarehouseZone? matchedLocation;
    if (result.location != null) {
      try {
        final warehouseService = WarehouseService();
        final warehouses = await warehouseService.listWarehousesOK();
        for (final w in warehouses) {
          for (final z in w.zones) {
            if (z.name.toLowerCase().contains(result.location!.toLowerCase()) ||
                result.location!.toLowerCase().contains(z.name.toLowerCase())) {
              matchedLocation = WarehouseZone(
                id: z.id,
                warehouseId: w.id,
                name: z.name,
                code: z.code,
                type: z.type,
                conditions: z.conditions,
                capacity: z.capacity,
                currentOccupancy: z.currentOccupancy,
                locations: z.locations,
                conditionCodes: z.conditionCodes,
              );
              break;
            }
          }
          if (matchedLocation != null) break;
        }
      } catch (_) {}
    }

    setState(() {
      if (result.observations != null) {
        _observacionesController.text = result.observations!;
      }
      if (result.receivedBy != null && result.receivedBy!.isNotEmpty) {
        _recibidoPorController.text = result.receivedBy!;
      }
      if (result.deliveredBy != null && result.deliveredBy!.isNotEmpty) {
        _entregadoPorController.text = result.deliveredBy!;
      }
      if (matchedLocation != null) _selectedLocation = matchedLocation;
      if (result.reason != null) {
        try {
          final matched = _motivoOptions.firstWhere(
            (m) =>
                m['denominacion'].toString().toLowerCase().contains(
                      result.reason!.toLowerCase(),
                    ) ||
                result.reason!.toLowerCase().contains(
                      m['denominacion'].toString().toLowerCase(),
                    ),
          );
          _selectedMotivo = matched;
        } catch (_) {}
      }
    });

    if (result.items.isNotEmpty) {
      int addedCount = 0;
      for (final draft in result.items) {
        if (draft.productId != null) {
          setState(() {
            _selectedProducts.add({
              'id': draft.productId,
              'denominacion': draft.productName,
              'sku_producto': draft.productSku ?? '',
              'cantidad': draft.quantity,
              'precio_unitario': draft.price ?? 0.0,
              'sku': draft.productSku ?? '',
              'descripcion': '',
              'es_vendible': true,
              'es_elaborado': false,
              'es_servicio': false,
              'stock_disponible': false,
              'presentaciones': [],
              'variantes_disponibles': [],
            });
            addedCount++;
          });
        }
      }
      if (addedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Datos importados: $addedCount productos + Encabezados'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  void _addProductToReception(Product product) {
    showDialog(
      context: context,
      builder: (context) => ProductQuantityDialog(
        product: product,
        selectedLocation: _selectedLocation,
        invoiceCurrency: _selectedCurrency,
        exchangeRate: null,
        onProductAdded: (productData) {
          setState(() => _selectedProducts.add(productData));
        },
      ),
    );
  }

  void _removeProduct(int index) {
    setState(() => _selectedProducts.removeAt(index));
  }

  double get _totalAmount {
    return _selectedProducts.fold(0.0, (sum, item) {
      final cantidad = item['cantidad'] as double;
      final precio = item['precio_unitario'] as double? ?? 0.0;
      return sum + (cantidad * precio);
    });
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

  Future<void> _submitReception() async {
    if (!_formKey.currentState!.validate()) {
      _showError('Complete todos los campos requeridos');
      return;
    }
    if (_selectedProducts.isEmpty) {
      _showError('Debe agregar al menos un producto');
      return;
    }
    if (_selectedLocation == null) {
      _showError('Debe seleccionar una ubicación de destino');
      return;
    }
    for (final product in _selectedProducts) {
      final precio = product['precio_unitario'] as double?;
      final cantidad = product['cantidad'] as double?;
      if (precio == null || precio < 0) {
        _showError('Producto "${product['denominacion']}" tiene precio inválido');
        return;
      }
      if (cantidad == null || cantidad <= 0) {
        _showError('Producto "${product['denominacion']}" tiene cantidad inválida');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userUuid = await userPrefs.getUserId();
      if (idTienda == null || userUuid == null) {
        throw Exception('No se encontró información del usuario');
      }

      final productosParaEnviar = _selectedProducts.map((product) {
        final productWithLocation = Map<String, dynamic>.from(product);
        if (productWithLocation['id_producto'] == null &&
            productWithLocation['id'] != null) {
          productWithLocation['id_producto'] = productWithLocation['id'];
        }
        if (_selectedLocation != null) {
          try {
            productWithLocation['id_ubicacion'] =
                int.parse(_selectedLocation!.id);
          } catch (_) {
            throw Exception(
                'Error: ID de ubicación inválido "${_selectedLocation!.id}"');
          }
        }
        return productWithLocation;
      }).toList();

      final result = await InventoryService.insertInventoryReception(
        entregadoPor: _entregadoPorController.text,
        idTienda: idTienda,
        montoTotal: _montoTotalController.text.isNotEmpty
            ? double.parse(_montoTotalController.text)
            : _totalAmount,
        motivo: _selectedMotivo?['id'] ?? '',
        observaciones: _observacionesController.text,
        productos: productosParaEnviar,
        recibidoPor: _recibidoPorController.text,
        idProveedor: _selectedSupplier?.id,
        uuid: userUuid,
        monedaFactura: _selectedCurrency,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          _savePersistedValues();
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                  'Recepción registrada exitosamente. ID: ${result['id_operacion']}'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw Exception(result['message'] ?? 'Error desconocido');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar recepción: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          'Recepción de Inventario',
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
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: TextButton.icon(
              onPressed: _openAiAssistant,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Asistente IA'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.15),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitReception,
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
              label: Text(_isLoading ? 'Guardando...' : 'Registrar Recepción'),
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
              child: LayoutBuilder(
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
                              _buildReceptionInfoCard(),
                              const SizedBox(height: 20),
                              _buildLocationCard(),
                              const SizedBox(height: 20),
                              _buildTotalsCard(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildProductSelectionCard(),
                              const SizedBox(height: 20),
                              _buildSelectedProductsCard(),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildReceptionInfoCard(),
                      const SizedBox(height: 20),
                      _buildLocationCard(),
                      const SizedBox(height: 20),
                      _buildProductSelectionCard(),
                      const SizedBox(height: 20),
                      _buildSelectedProductsCard(),
                      const SizedBox(height: 20),
                      _buildTotalsCard(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
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

  // =====================================================
  // CARDS
  // =====================================================
  Widget _buildReceptionInfoCard() {
    return _buildWebCard(
      title: 'Información de Recepción',
      subtitle: 'Datos generales de la operación',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _entregadoPorController,
                  decoration: _inputDecoration(
                    label: 'Entregado por',
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _recibidoPorController,
                  decoration: _inputDecoration(
                    label: 'Recibido por',
                    prefixIcon: Icon(
                      Icons.person_pin_outlined,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _isLoadingMotivos
              ? _buildLoadingPlaceholder('Cargando motivos...')
              : DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedMotivo,
                  decoration: _inputDecoration(
                    label: 'Motivo',
                    prefixIcon: Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  items: _motivoOptions.map((motivo) {
                    return DropdownMenuItem(
                      value: motivo,
                      child: Text(
                          motivo['denominacion'] ?? 'Sin denominación'),
                    );
                  }).toList(),
                  onChanged: (motivo) =>
                      setState(() => _selectedMotivo = motivo),
                  validator: (value) =>
                      value == null ? 'Campo requerido' : null,
                ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _observacionesController,
            decoration: _inputDecoration(
              label: 'Observaciones',
              hint: 'Notas adicionales sobre la recepción',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _montoTotalController,
            decoration: _inputDecoration(
              label: 'Monto Total (Opcional)',
              hint:
                  'Calculado: \$${_totalAmount.toStringAsFixed(2)}',
              prefixText: '\$ ',
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return _buildWebCard(
      title: 'Ubicación de Destino',
      subtitle: 'Zona donde se almacenarán los productos',
      icon: Icons.place_outlined,
      iconColor: AppColors.warning,
      child: LocationSelectorWidget(
        type: LocationSelectorType.single,
        title: 'Seleccionar Ubicación de Destino',
        subtitle: 'Zona donde se almacenarán los productos recibidos',
        selectedLocation: _selectedLocation,
        onLocationChanged: (location) =>
            setState(() => _selectedLocation = location),
        validationMessage: _selectedLocation == null
            ? 'Debe seleccionar una ubicación'
            : null,
      ),
    );
  }

  Widget _buildProductSelectionCard() {
    return _buildWebCard(
      title: 'Buscar y Agregar Productos',
      subtitle: 'Filtra por proveedor y selecciona los productos a recibir',
      icon: Icons.search_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProveedorFilter(),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 360,
              child: ProductSelectorWidget(
                key: ValueKey(_selectedProveedor?['id']),
                searchType: ProductSearchType.all,
                requireInventory: false,
                searchHint: 'Buscar productos para recibir...',
                supplierId: _selectedProveedor?['id'] as int?,
                onProductSelected: (productData) {
                  final product = Product(
                    id: productData['id']?.toString() ?? '',
                    name: productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    denominacion: productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    description: productData['descripcion'] ?? '',
                    categoryId:
                        productData['id_categoria']?.toString() ?? '',
                    categoryName: productData['categoria_nombre'] ?? '',
                    brand: '',
                    sku: productData['sku_producto'] ??
                        productData['sku'] ??
                        '',
                    barcode: productData['codigo_barras'] ?? '',
                    basePrice: (productData['precio_venta_cup'] as num?)
                            ?.toDouble() ??
                        0.0,
                    imageUrl: '',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                    um: productData['um'],
                    precioVenta: (productData['precio_venta_cup'] as num?)
                            ?.toDouble() ??
                        0.0,
                    esVendible: productData['es_vendible'] ?? true,
                    esElaborado: productData['es_elaborado'] ?? false,
                    esServicio: productData['es_servicio'] ?? false,
                    stockDisponible:
                        productData['stock_disponible'] ?? false,
                    presentaciones: (productData['presentaciones'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [],
                    variantesDisponibles:
                        (productData['variantes_disponibles'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [],
                  );
                  _addProductToReception(product);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProveedorFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'FILTRAR POR PROVEEDOR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                letterSpacing: 0.8,
              ),
            ),
            if (_selectedProveedor != null)
              TextButton.icon(
                onPressed: () => setState(() => _selectedProveedor = null),
                icon: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('Limpiar'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _isLoadingProveedores
            ? _buildLoadingPlaceholder('Cargando proveedores...')
            : DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedProveedor,
                decoration: _inputDecoration(
                  label: 'Proveedor',
                  hint: _proveedores.isEmpty
                      ? 'No hay proveedores disponibles'
                      : 'Todos los proveedores',
                  prefixIcon: Icon(
                    Icons.local_shipping_outlined,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ),
                items: [
                  const DropdownMenuItem<Map<String, dynamic>>(
                    value: null,
                    child: Text('Todos los proveedores'),
                  ),
                  ..._proveedores.map((proveedor) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: proveedor,
                      child: Text(
                        proveedor['denominacion'] ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (proveedor) =>
                    setState(() => _selectedProveedor = proveedor),
              ),
      ],
    );
  }

  Widget _buildSelectedProductsCard() {
    return _buildWebCard(
      title: 'Productos Seleccionados',
      subtitle:
          '${_selectedProducts.length} producto(s) en esta recepción',
      icon: Icons.inventory_2_outlined,
      iconColor: AppColors.success,
      trailing: _selectedProducts.isNotEmpty
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_selectedProducts.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedProducts.isEmpty)
            _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Sin productos',
              description:
                  'Busca productos arriba y selecciónalos para añadirlos a la recepción.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedProducts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildSelectedProductTile(index),
            ),
          if (_selectedProducts.isNotEmpty) ...[
            const SizedBox(height: 14),
            ConversionInfoWidget(
              conversions: _selectedProducts,
              showDetails: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedProductTile(int index) {
    final item = _selectedProducts[index];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['denominacion'] ??
                      item['nombre_producto'] ??
                      'Producto sin nombre',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU: ${item['sku_producto'] ?? item['sku'] ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildInfoBadge(
                      _buildQuantityDisplay(item),
                      AppColors.primary,
                      Icons.numbers_rounded,
                    ),
                    _buildInfoBadge(
                      _buildPriceDisplay(item),
                      AppColors.success,
                      Icons.attach_money_rounded,
                    ),
                    if (item['precio_referencia'] != null &&
                        item['precio_referencia'] > 0)
                      _buildInfoBadge(
                        'Ref: \$${item['precio_referencia']?.toStringAsFixed(2)}',
                        Colors.grey.shade700,
                        Icons.bookmark_outline_rounded,
                      ),
                    if ((item['descuento_porcentaje'] ?? 0) > 0 ||
                        (item['descuento_monto'] ?? 0) > 0)
                      _buildInfoBadge(
                        'Desc: ${item['descuento_porcentaje'] ?? 0}% + \$${item['descuento_monto']?.toStringAsFixed(2) ?? '0.00'}',
                        AppColors.warning,
                        Icons.percent_rounded,
                      ),
                    if ((item['bonificacion_cantidad'] ?? 0) > 0)
                      _buildInfoBadge(
                        '+${item['bonificacion_cantidad']} bonif.',
                        AppColors.success,
                        Icons.card_giftcard_rounded,
                      ),
                    if (_buildVariantInfo(item).isNotEmpty)
                      _buildInfoBadge(
                        _buildVariantInfo(item),
                        AppColors.primary,
                        Icons.layers_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.error,
            onPressed: () => _removeProduct(index),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard() {
    return _buildWebCard(
      title: 'Resumen y Total',
      subtitle: 'Total calculado de la operación',
      icon: Icons.calculate_outlined,
      iconColor: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReceptionTotalWidget(
            totalAmount: _totalAmount,
            invoiceCurrency: _selectedCurrency,
            selectedProducts: _selectedProducts,
            onTotalConverted: (convertedAmount, currency) {},
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitReception,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(
              _isLoading ? 'Procesando...' : 'Registrar Recepción',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
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
        ],
      ),
    );
  }

  // =====================================================
  // SMALL HELPERS
  // =====================================================
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

  String _buildQuantityDisplay(Map<String, dynamic> item) {
    final cantidad = item['cantidad'] as double;
    final conversionApplied = item['conversion_applied'] == true;
    final cantidadOriginal = item['cantidad_original'] as double?;

    if (conversionApplied && cantidadOriginal != null) {
      final presentacionOriginal = item['presentacion_original_info'];
      final presentacionFinal = item['presentation_info'];
      String pOrig = 'unidades';
      String pFinal = 'unidades base';
      if (presentacionOriginal != null &&
          presentacionOriginal['denominacion'] != null) {
        pOrig = presentacionOriginal['denominacion'];
      }
      if (presentacionFinal != null &&
          presentacionFinal['denominacion'] != null) {
        pFinal = presentacionFinal['denominacion'];
      }
      return '${cantidadOriginal.toInt()} $pOrig → ${cantidad.toInt()} $pFinal';
    }
    return 'Cant: ${cantidad.toInt()}';
  }

  String _buildPriceDisplay(Map<String, dynamic> item) {
    final precio = item['precio_unitario'] as double? ?? 0.0;
    return '\$${precio.toStringAsFixed(2)} USD';
  }

  String _buildVariantInfo(Map<String, dynamic> item) {
    List<String> variantParts = [];
    if (item['variant_info'] != null) {
      final variantInfo = item['variant_info'];
      final atributo = variantInfo['atributo']?['denominacion'] ??
          variantInfo['atributo']?['label'] ??
          '';
      final opcion = variantInfo['opcion']?['valor'] ?? '';
      if (atributo.isNotEmpty && opcion.isNotEmpty) {
        variantParts.add('$atributo: $opcion');
      } else if (atributo.isNotEmpty) {
        variantParts.add(atributo);
      }
    }
    if (item['presentation_info'] != null) {
      final presentationInfo = item['presentation_info'];
      final denominacion = presentationInfo['denominacion'] ??
          presentationInfo['presentacion'] ??
          presentationInfo['nombre'] ??
          presentationInfo['tipo'] ??
          '';
      final cantidad = presentationInfo['cantidad'] ?? 1;
      if (denominacion.isNotEmpty) {
        variantParts.add('Pres: $denominacion (${cantidad}x)');
      }
    }
    return variantParts.join(' | ');
  }
}
