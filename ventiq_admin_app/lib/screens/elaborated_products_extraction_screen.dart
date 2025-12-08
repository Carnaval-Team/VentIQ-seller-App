import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../widgets/conversion_info_widget.dart';
import '../models/warehouse.dart';

class ElaboratedProductsExtractionScreen extends StatefulWidget {
  const ElaboratedProductsExtractionScreen({super.key});

  @override
  State<ElaboratedProductsExtractionScreen> createState() =>
      _ElaboratedProductsExtractionScreenState();
}

class _ElaboratedProductsExtractionScreenState
    extends State<ElaboratedProductsExtractionScreen> {
  final ProductService _productService = ProductService();
  final InventoryService _inventoryService = InventoryService();
  final UserPreferencesService _prefsService = UserPreferencesService();
  final WarehouseService _warehouseService = WarehouseService();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _conversions = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  
  // Variables para selector de zona
  List<Warehouse> _warehouses = [];
  Warehouse? _selectedWarehouse;
  WarehouseZone? _selectedZone;
  bool _isLoadingWarehouses = false;
  
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isLoadingMotivos = true;
  String _searchQuery = '';
  
  // Indicadores de progreso
  int _currentStep = 0;
  final List<String> _steps = [
    'Seleccionar productos',
    'Configurar extracción', 
    'Procesar y completar'
  ];
  
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _observationsController = TextEditingController();
  final TextEditingController _autorizadoPorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadMotivoOptions();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _observationsController.dispose();
    _autorizadoPorController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    
    try {
      // Cargar todos los productos de la tienda
      final allProducts = await ProductService.getProductsByTienda();
      
      // Filtrar solo productos elaborados para esta funcionalidad
      final elaboratedProducts = allProducts.where((product) => product.esElaborado).toList();
      
      print('📦 Total productos cargados: ${allProducts.length}');
      print('🧪 Productos elaborados encontrados: ${elaboratedProducts.length}');
      
      setState(() {
        _allProducts = elaboratedProducts;
        _filteredProducts = elaboratedProducts;
        _isLoading = false;
      });
      
      if (elaboratedProducts.isEmpty) {
        _showErrorSnackBar('No se encontraron productos elaborados en esta tienda');
      }
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error al cargar productos: $e');
    }
  }

  Future<void> _loadMotivoOptions() async {
    setState(() => _isLoadingMotivos = true);

    try {
      // Load extraction motives from Supabase database
      _motivoOptions = await InventoryService.getMotivoExtraccionOptions();
      setState(() => _isLoadingMotivos = false);
    } catch (e) {
      print('Error loading motivo options: $e');
      setState(() => _isLoadingMotivos = false);
    }
  }

  Future<void> _loadWarehouses() async {
    setState(() => _isLoadingWarehouses = true);

    try {
      // Load warehouses from Supabase database using pagination
      final response = await _warehouseService.listWarehousesWithPaginationOK(
        pagina: 1,
        porPagina: 100, // Obtener todos los almacenes
      );
      
      _warehouses = response.almacenes;
      setState(() => _isLoadingWarehouses = false);
    } catch (e) {
      print('Error loading warehouses: $e');
      setState(() => _isLoadingWarehouses = false);
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts.where((product) {
          return product.denominacion.toLowerCase().contains(query.toLowerCase()) ||
                 (product.sku?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  void _showProductSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => _ProductSelectionDialog(
        products: _filteredProducts,
        onProductSelected: _addProduct,
      ),
    );
  }

  void _addProduct(Product product, double quantity) {
    setState(() {
      // Convert Product to Map format for consistency with existing code
      final productMap = {
        'id_producto': int.tryParse(product.id) ?? 0, // Convertir String ID a int de forma segura
        'denominacion': product.denominacion,
        'sku': product.sku,
        'es_elaborado': product.esElaborado,
        'imagen': product.imageUrl,
        'cantidad': quantity, // Add the quantity from the dialog
        // Add other necessary fields from the Product object
        'precio_venta_cup': product.precioVenta,
        'description': product.description,
      };
      
      _selectedProducts.add(productMap);
      
      // Actualizar progreso cuando se selecciona el primer producto
      if (_currentStep == 0 && _selectedProducts.isNotEmpty) {
        _currentStep = 1;
      }
    });
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
      // Regresar al paso 0 si no hay productos seleccionados
      if (_selectedProducts.isEmpty && _currentStep > 0) {
        _currentStep = 0;
      }
    });
  }

  void _updateProgressStep() {
    setState(() {
      if (_selectedProducts.isEmpty) {
        _currentStep = 0;
      } else if (_selectedMotivo == null || _autorizadoPorController.text.trim().isEmpty) {
        _currentStep = 1;
      } else {
        _currentStep = 2;
      }
    });
  }

  Future<void> _processExtraction() async {
    if (_selectedProducts.isEmpty) {
      _showErrorSnackBar('Debe seleccionar al menos un producto');
      return;
    }

    if (_selectedMotivo == null) {
      _showErrorSnackBar('Debe seleccionar un motivo de extracción');
      return;
    }

    if (_autorizadoPorController.text.trim().isEmpty) {
      _showErrorSnackBar('Debe ingresar quién autoriza la extracción');
      return;
    }

    // Verificar que se haya seleccionado almacén y zona
    if (_selectedWarehouse == null) {
      _showErrorSnackBar('Debe seleccionar un almacén');
      return;
    }

    if (_selectedZone == null) {
      _showErrorSnackBar('Debe seleccionar una zona');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Obtener datos del usuario con el método correcto
      String userUuid;
      try {
        userUuid = await _prefsService.getUserId() ?? '';
        
        if (userUuid.isEmpty) {
          throw Exception('No se encontró UUID del usuario');
        }
        
        print('👤 UUID usuario obtenido: $userUuid');
      } catch (e) {
        print('❌ Error obteniendo UUID del usuario: $e');
        _showErrorSnackBar('Error obteniendo datos del usuario');
        setState(() => _isProcessing = false);
        return;
      }

      // NUEVO: Verificar inventario de ingredientes en la zona seleccionada
      final checkResult = await _checkIngredientsBeforeProcessing();

      if (!checkResult['success']) {
        // Si hay error en la verificación, mostrar error y salir
        if (checkResult['error'] != null) {
          _showErrorSnackBar(checkResult['message'] ?? 'Error al verificar ingredientes');
          setState(() => _isProcessing = false);
          return;
        }
        
        // Si hay ingredientes no disponibles, mostrar diálogo de confirmación
        final unavailableIngredients = checkResult['unavailable_ingredients'] ?? [];
        if (unavailableIngredients.isNotEmpty) {
          final shouldContinue = await _showIngredientAvailabilityDialog(checkResult);
          if (!shouldContinue) {
            setState(() => _isProcessing = false);
            return;
          }
          
          // Usuario decidió continuar a pesar de ingredientes no disponibles
          print('⚠️ Usuario decidió continuar con ingredientes no disponibles');
        }
      } else {
        print('✅ Todos los ingredientes están disponibles en la zona seleccionada');
      }

      // Procesar la extracción
      final result = await _inventoryService.processElaboratedProductsExtraction(
        productos: _selectedProducts,
        autorizadoPor: _autorizadoPorController.text.trim(),
        observaciones: _observationsController.text.trim(),
        idMotivoOperacion: _selectedMotivo!['id'],
        uuid: userUuid,
        idUbicacion: int.parse(_selectedZone!.id), // Usar la zona seleccionada
      );

      if (result['status'] == 'success') {
        _showSuccessSnackBar('Extracción procesada exitosamente');
        
        // Limpiar formulario
        setState(() {
          _selectedProducts.clear();
          _conversions.clear();
          _selectedMotivo = null;
          _selectedWarehouse = null;
          _selectedZone = null;
          _autorizadoPorController.clear();
          _observationsController.clear();
          _currentStep = 0;
        });
        
        // Mostrar resultados
        _showExtractionResults(result);
      } else {
        _showErrorSnackBar(result['message'] ?? 'Error en la extracción');
      }
      
    } catch (e) {
      print('❌ Error procesando extracción: $e');
      _showErrorSnackBar('Error procesando extracción: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _checkIngredientsBeforeProcessing() async {
    try {
      print('🔍 Verificando ingredientes antes del procesamiento...');
      
      // Descomponer productos elaborados para obtener ingredientes
      final decomposedIngredients = await InventoryService.decomposeElaboratedProducts(_selectedProducts);
      
      if (decomposedIngredients.isEmpty) {
        print('⚠️ No se encontraron ingredientes para verificar');
        return {
          'success': true,
          'available_ingredients': <Map<String, dynamic>>[],
          'unavailable_ingredients': <Map<String, dynamic>>[],
          'message': 'No hay ingredientes que verificar'
        };
      }
      
      print('📋 Ingredientes a verificar: ${decomposedIngredients.length}');
      
      // Verificar inventario en la zona seleccionada
      final checkResult = await InventoryService.checkIngredientsInventoryInZone(
        ingredients: decomposedIngredients,
        zoneId: _selectedZone!.id,
      );
      
      print('📊 Resultado verificación: ${checkResult['success']}');
      print('✅ Disponibles: ${checkResult['available_ingredients']?.length ?? 0}');
      print('❌ No disponibles: ${checkResult['unavailable_ingredients']?.length ?? 0}');
      
      return checkResult;
      
    } catch (e) {
      print('❌ Error verificando ingredientes: $e');
      return {
        'success': false,
        'error': e.toString(),
        'available_ingredients': <Map<String, dynamic>>[],
        'unavailable_ingredients': <Map<String, dynamic>>[],
        'message': 'Error al verificar ingredientes: $e'
      };
    }
  }

  Future<bool> _showIngredientAvailabilityDialog(Map<String, dynamic> checkResult) async {
    final unavailableIngredients = checkResult['unavailable_ingredients'] ?? [];
    final availableIngredients = checkResult['available_ingredients'] ?? [];

    return await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            const Text('Ingredientes no disponibles'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se encontraron ${unavailableIngredients.length} ingredientes no disponibles en la zona "${_selectedZone?.name}".',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              
              // Lista de ingredientes no disponibles
              if (unavailableIngredients.isNotEmpty) ...[
                const Text(
                  'Ingredientes no disponibles:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: unavailableIngredients.length,
                    itemBuilder: (context, index) {
                      final ingredient = unavailableIngredients[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.error, color: Colors.red, size: 16),
                        title: Text(
                          ingredient['denominacion'] ?? 'Producto ${ingredient['id_producto']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          'Requerido: ${ingredient['cantidad']} | Disponible: ${ingredient['stock_disponible'] ?? 0}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              const Text(
                '¿Desea continuar con la extracción de todas formas?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continuar de todas formas'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showExtractionResults(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Extracción Completada'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('La extracción se procesó exitosamente en:'),
            const SizedBox(height: 8),
            Text('• Almacén: ${_selectedWarehouse?.name ?? 'N/A'}'),
            Text('• Zona: ${_selectedZone?.name ?? 'N/A'}'),
            const SizedBox(height: 12),
            
            if (result['productos_procesados'] != null) ...[
              Text('Productos procesados: ${result['productos_procesados']}'),
              const SizedBox(height: 8),
            ],
            if (result['ingredientes_extraidos'] != null) ...[
              Text('Ingredientes extraídos: ${result['ingredientes_extraidos']}'),
              const SizedBox(height: 8),
            ],
            Text('ID de operación: ${result['id_operacion'] ?? 'N/A'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pop(context); // Volver a pantalla anterior
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _previewIngredients() async {
    try {
      setState(() => _isLoading = true);
      
      // Descomponer productos elaborados para obtener ingredientes
      final decomposedIngredients = await InventoryService.decomposeElaboratedProducts(_selectedProducts);
      
      if (decomposedIngredients.isEmpty) {
        _showErrorSnackBar('No se encontraron ingredientes para mostrar');
        return;
      }
      
      // Verificar inventario en la zona seleccionada si hay zona seleccionada
      Map<String, dynamic>? checkResult;
      if (_selectedZone != null) {
        checkResult = await InventoryService.checkIngredientsInventoryInZone(
          ingredients: decomposedIngredients,
          zoneId: _selectedZone!.id,
        );
      }
      
      // Mostrar diálogo con previsualización
      await _showIngredientsPreviewDialog(decomposedIngredients, checkResult);
      
    } catch (e) {
      print('❌ Error obteniendo previsualización de ingredientes: $e');
      _showErrorSnackBar('Error al obtener ingredientes: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showIngredientsPreviewDialog(
    List<Map<String, dynamic>> ingredients,
    Map<String, dynamic>? checkResult,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.list_alt, color: Colors.blue, size: 24),
            const SizedBox(width: 8),
            const Text('Ingredientes a extraer'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total de ingredientes: ${ingredients.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_selectedZone != null) ...[
                const SizedBox(height: 8),
                Text('Zona seleccionada: ${_selectedZone!.name}'),
              ],
              const SizedBox(height: 16),
              
              Expanded(
                child: ListView.builder(
                  itemCount: ingredients.length,
                  itemBuilder: (context, index) {
                    final ingredient = ingredients[index];
                    
                    // Determinar estado del ingrediente
                    bool isAvailable = true;
                    
                    if (checkResult != null) {
                      final availableList = checkResult['available_ingredients'] ?? [];
                      
                      isAvailable = availableList.any((item) => 
                        item['id_producto'].toString() == ingredient['id_producto'].toString());
                    }
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isAvailable ? Icons.check_circle : Icons.error,
                          color: isAvailable ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        title: Text(
                          ingredient['denominacion'] ?? 'Producto ${ingredient['id_producto']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (checkResult != null) ...[
                              Builder(builder: (context) {
                                final availableList = checkResult['available_ingredients'] ?? [];
                                final unavailableList = checkResult['unavailable_ingredients'] ?? [];
                                
                                // Buscar el ingrediente en available o unavailable
                                Map<String, dynamic>? itemData;
                                if (availableList.any((item) => item['id_producto'].toString() == ingredient['id_producto'].toString())) {
                                  itemData = availableList.firstWhere((item) => item['id_producto'].toString() == ingredient['id_producto'].toString());
                                } else {
                                  final unavailableItems = unavailableList.where((item) => item['id_producto'].toString() == ingredient['id_producto'].toString()).toList();
                                  if (unavailableItems.isNotEmpty) {
                                    itemData = unavailableItems.first;
                                  }
                                }
                                
                                if (itemData != null) {
                                  final cantidadOriginal = itemData['cantidad_necesaria_original'] ?? ingredient['cantidad'];
                                  final cantidadConvertida = itemData['cantidad_necesaria_presentacion'] ?? ingredient['cantidad'];
                                  final unidadPresentacion = itemData['unidad_presentacion'] ?? '';
                                  final stockDisponible = itemData['stock_disponible'] ?? 0;
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Original: $cantidadOriginal ${ingredient['unidad_medida'] ?? ''}',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                      Text(
                                        'Convertida: ${cantidadConvertida.toStringAsFixed(3)} $unidadPresentacion',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                                      ),
                                      Text(
                                        'Stock disponible: ${stockDisponible.toStringAsFixed(3)} $unidadPresentacion',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isAvailable ? Colors.green : Colors.red,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                
                                // Fallback si no hay datos de conversión
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cantidad requerida: ${ingredient['cantidad']} ${ingredient['unidad_medida'] ?? ''}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Stock disponible: 0',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isAvailable ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ] else ...[
                              Text(
                                'Cantidad requerida: ${ingredient['cantidad']} ${ingredient['unidad_medida'] ?? ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                        trailing: isAvailable 
                          ? const Icon(Icons.check, color: Colors.green, size: 16)
                          : const Icon(Icons.warning, color: Colors.red, size: 16),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isTablet ? 'Extracción de Productos Elaborados' : 'Extracción Elaborados',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 18 : 16,
          ),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (_selectedProducts.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          '${_selectedProducts.length}',
                          key: ValueKey(_selectedProducts.length),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header con información
                  _buildHeader(context, isTablet),
                  
                  // Indicador de progreso
                  _buildProgressIndicator(context, isTablet),
                  
                  // Buscador
                  _buildSearchBar(context, isTablet),
                  
                  // Lista de productos seleccionados
                  if (_selectedProducts.isNotEmpty)
                    _buildSelectedProductsList(context, isTablet),
                  
                  // Resumen de ingredientes (si hay productos seleccionados)
                  if (_selectedProducts.isNotEmpty && _selectedZone != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Resumen de extracción',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('Almacén: ${_selectedWarehouse?.name ?? 'No seleccionado'}'),
                              Text('Zona: ${_selectedZone?.name ?? 'No seleccionada'}'),
                              Text('Productos elaborados: ${_selectedProducts.length}'),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _isProcessing ? null : _previewIngredients,
                                icon: const Icon(Icons.preview, size: 16),
                                label: const Text('Ver ingredientes'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade100,
                                  foregroundColor: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Motivo de extracción
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<Map<String, dynamic>>(
                      decoration: const InputDecoration(
                        labelText: 'Motivo de extracción',
                        border: OutlineInputBorder(),
                      ),
                      items: _motivoOptions.map((motivo) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: motivo,
                          child: Text(motivo['denominacion']),
                        );
                      }).toList(),
                      onChanged: (motivo) {
                        setState(() {
                          _selectedMotivo = motivo;
                          _updateProgressStep();
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Observaciones
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _observationsController,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Autorizado por
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _autorizadoPorController,
                      decoration: const InputDecoration(
                        labelText: 'Autorizado por',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) {
                        setState(() {
                          _updateProgressStep();
                        });
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 16), // Agregar margen faltante
                  
                  // Formulario de configuración
                  _buildConfigurationForm(context, isTablet),
                  
                  // Botones de acción
                  _buildActionButtons(context, isTablet),
                  
                  // Espaciado inferior
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50,
            Colors.indigo.shade50,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.science_outlined,
                  color: Colors.blue.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extracción de Productos Elaborados',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Descomposición automática de ingredientes',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Instrucciones paso a paso
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, 
                         color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Cómo funciona:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                _buildInstructionStep(
                  number: '1',
                  title: 'Seleccionar productos',
                  description: 'Elige los productos que deseas extraer',
                  icon: Icons.add_shopping_cart,
                  color: Colors.green,
                ),
                
                _buildInstructionStep(
                  number: '2',
                  title: 'Configurar extracción', 
                  description: 'Selecciona motivo y autorización',
                  icon: Icons.settings,
                  color: Colors.orange,
                ),
                
                _buildInstructionStep(
                  number: '3',
                  title: 'Procesar y completar',
                  description: 'El sistema descompone en ingredientes base',
                  icon: Icons.auto_awesome,
                  color: Colors.purple,
                  isLast: true,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Tips importantes
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, 
                     color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Tip: Esta funcionalidad no requiere stock existente, ideal para pruebas y simulaciones',
                    style: TextStyle(
                      color: Colors.amber.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context, bool isTablet) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progreso',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_steps.length, (index) {
              final isCompleted = index < _currentStep;
              final isCurrent = index == _currentStep;
              final isUpcoming = index > _currentStep;
              
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isCompleted 
                              ? Colors.green.shade100
                              : isCurrent 
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCompleted 
                                ? Colors.green.shade300
                                : isCurrent 
                                    ? Colors.blue.shade300
                                    : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isCompleted 
                                    ? Colors.green
                                    : isCurrent 
                                        ? Colors.blue
                                        : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: isCompleted
                                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                                    : Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _steps[index],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                  color: isCompleted 
                                      ? Colors.green.shade700
                                      : isCurrent 
                                          ? Colors.blue.shade700
                                          : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (index < _steps.length - 1) const SizedBox(width: 8),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isTablet) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        onChanged: _filterProducts,
      ),
    );
  }

  Widget _buildSelectedProductsList(BuildContext context, bool isTablet) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart, 
                   color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Productos Seleccionados (${_selectedProducts.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_selectedProducts.length, (index) {
            final item = _selectedProducts[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['denominacion'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item['sku'] != null) ...[
                          Text(
                            'SKU: ${item['sku']}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        Row(
                          children: [
                            Text(
                              'Cantidad: ${item['cantidad']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: item['es_elaborado'] == true
                                    ? Colors.orange.shade100
                                    : Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item['es_elaborado'] == true
                                    ? 'Elaborado'
                                    : 'Simple',
                                style: TextStyle(
                                  color: item['es_elaborado'] == true
                                      ? Colors.orange.shade700
                                      : Colors.blue.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeProduct(index),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConfigurationForm(BuildContext context, bool isTablet) {
    return Column(
      children: [
        // Selector de almacén
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<Warehouse>(
            decoration: const InputDecoration(
              labelText: 'Almacén',
              border: OutlineInputBorder(),
            ),
            items: _warehouses.map((warehouse) {
              return DropdownMenuItem<Warehouse>(
                value: warehouse,
                child: Text(warehouse.name),
              );
            }).toList(),
            onChanged: (warehouse) {
              setState(() {
                _selectedWarehouse = warehouse;
              });
            },
          ),
        ),
        const SizedBox(height: 16),

        // Selector de zona
        if (_selectedWarehouse != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<WarehouseZone>(
              decoration: const InputDecoration(
                labelText: 'Zona',
                border: OutlineInputBorder(),
              ),
              items: _selectedWarehouse!.zones.map((zone) {
                return DropdownMenuItem<WarehouseZone>(
                  value: zone,
                  child: Text(zone.name),
                );
              }).toList(),
              onChanged: (zone) {
                setState(() {
                  _selectedZone = zone;
                });
              },
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showProductSelectionDialog,
            icon: const Icon(Icons.add),
            label: const Text('Agregar Producto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _selectedProducts.isEmpty || _isProcessing
                ? null
                : _processExtraction,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white),
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_isProcessing ? 'Procesando...' : 'Procesar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionStep({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    bool isLast = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (!isLast) ...[
            const SizedBox(width: 12),
            Icon(
              icon,
              color: color,
              size: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductSelectionDialog extends StatefulWidget {
  final List<Product> products;
  final Function(Product, double) onProductSelected;

  const _ProductSelectionDialog({
    required this.products,
    required this.onProductSelected,
  });

  @override
  State<_ProductSelectionDialog> createState() =>
      _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  final TextEditingController _quantityController = TextEditingController();
  Product? _selectedProduct;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _selectProduct() {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un producto'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe ingresar una cantidad válida mayor a 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.onProductSelected(_selectedProduct!, quantity);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Seleccionar Producto')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          children: [
            // Dropdown de productos simplificado
            DropdownButtonFormField<Product>(
              value: _selectedProduct,
              decoration: const InputDecoration(
                labelText: 'Producto',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: widget.products.map((product) {
                return DropdownMenuItem<Product>(
                  value: product,
                  child: Row(
                    children: [
                      // Icono simple
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: product.esElaborado
                              ? Colors.orange.shade100
                              : Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          product.esElaborado
                              ? Icons.science_outlined
                              : Icons.inventory_2_outlined,
                          color: product.esElaborado
                              ? Colors.orange.shade700
                              : Colors.blue.shade700,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          product.denominacion,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (product) {
                setState(() {
                  _selectedProduct = product;
                });
              },
            ),

            const SizedBox(height: 16),

            // Información del producto seleccionado
            if (_selectedProduct != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Producto Seleccionado:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedProduct!.denominacion,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (_selectedProduct!.sku != null && _selectedProduct!.sku!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SKU: ${_selectedProduct!.sku}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _selectedProduct!.esElaborado
                                ? Colors.orange.shade100
                                : Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _selectedProduct!.esElaborado ? 'Elaborado' : 'Simple',
                            style: TextStyle(
                              color: _selectedProduct!.esElaborado
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_selectedProduct!.precioVenta > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '\$${_selectedProduct!.precioVenta.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_selectedProduct!.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _selectedProduct!.description,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Campo de cantidad
            TextField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
                suffixText: 'unidades',
              ),
              keyboardType: TextInputType.number,
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
          onPressed: _selectProduct,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
