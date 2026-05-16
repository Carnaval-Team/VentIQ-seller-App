import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'dart:typed_data';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/permissions_service.dart';
import '../utils/navigation_guard.dart';
import '../widgets/marketing_menu_widget.dart';
import '../screens/add_product_screen.dart';
import '../widgets/reception_edit_dialog.dart';
import '../screens/product_movements_screen.dart';
import '../services/supplier_service.dart';
import '../models/supplier.dart';
import '../screens/suppliers/add_edit_supplier_screen.dart';
import '../services/currency_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _product;
  bool _isLoading = false;
  bool _isLoadingLocations = false;
  bool _isLoadingOperations = false;
  bool _isLoadingCharts = false;

  List<Map<String, dynamic>> _stockLocations = [];
  List<Map<String, dynamic>> _receptionOperations = [];
  List<Map<String, dynamic>> _priceHistory = [];
  List<Map<String, dynamic>> _promotionalPrices = [];
  List<Map<String, dynamic>> _stockHistory = [];
  List<Map<String, dynamic>> _ingredientes = [];
  bool _isLoadingIngredients = false;
  bool _isLoadingPromotions = false; // ✅ AGREGAR ESTA LÍNEA
  List<Map<String, dynamic>> _productsUsingThisIngredient = [];
  bool _isLoadingProductsUsingIngredient = false;
  List<Map<String, dynamic>> _equivalenciasPresentacion = [];
  bool _isLoadingEquivalencias = false;
  final PermissionsService _permissionsService = PermissionsService();
  bool _canEditProduct = false;
  bool _canDeleteProduct = false;
  bool _isGerente = false;
  bool _isInitializingPrices = false;
  bool _isLoadingPricingData = true;
  // Pagination and filtering for reception operations
  // Pagination and filtering for reception operations
  int _currentPage = 1;
  int _totalPages = 0;
  int _totalCount = 0;
  bool _hasNextPage = false;
  bool _hasPreviousPage = false;
  final TextEditingController _operationFilterController =
      TextEditingController();
  String? _operationIdFilter;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _checkPermissions();
    _loadAdditionalData();
  }

  void _checkPermissions() async {
    print('🔐 Verificando permisos de edición de producto...');
    final permissions = await Future.wait([
      _permissionsService.canPerformAction('product.edit'),
      _permissionsService.canPerformAction('product.delete'),
    ]);
    final canEdit = permissions[0];
    final canDelete = permissions[1];
    print('  • Editar producto: $canEdit');
    print('  • Eliminar producto: $canDelete');

    // Solo el gerente puede editar productos, así que el permiso es suficiente
    final isGerente = canEdit;
    print('  • Es Gerente: $isGerente');

    print('✅ Puede editar productos: $canEdit');
    if (mounted) {
      setState(() {
        _canEditProduct = canEdit;
        _canDeleteProduct = canDelete;
        _isGerente = isGerente;
      });
    }
  }

  Future<void> _loadAdditionalData() async {
    print('🔍 ===== INICIANDO CARGA DE DATOS ADICIONALES =====');
    print('🔍 Producto ID: ${_product.id}');
    print('🔍 Producto nombre: ${_product.denominacion}');
    print('🔍 Es elaborado (desde modelo): ${_product.esElaborado}');
    print('🔍 Verificando si debe cargar ingredientes...');

    // Establecer estado de carga
    if (mounted) {
      setState(() {
        _isLoadingPricingData = true;
      });
    }

    // Recargar el producto completo para obtener datos actualizados
    try {
      final productActualizado = await ProductService.getProductoCompletoById(
        int.parse(_product.id),
      );
      if (productActualizado != null && mounted) {
        setState(() {
          _product = productActualizado;
          _isLoadingPricingData = false;
        });
        print('✅ Producto recargado con datos actualizados');
      }
    } catch (e) {
      print('⚠️ Error al recargar producto: $e');
      if (mounted) {
        setState(() {
          _isLoadingPricingData = false;
        });
      }
    }

    await Future.wait([
      _loadStockLocations(),
      _loadReceptionOperations(),
      _loadPriceHistory(),
      _loadPromotionalPrices(),
      _loadStockHistory(),
      if (_product.esElaborado) _loadIngredients(),
      _loadProductsUsingThisIngredient(),
      _loadEquivalenciasPresentacion(),
    ]);

    print('✅ Carga de datos adicionales completada');
    if (_product.esElaborado) {
      print(
        '📊 Producto elaborado - Ingredientes cargados: ${_ingredientes.length}',
      );
    } else {
      print('📊 Producto NO elaborado - No se cargan ingredientes');
    }
  }

  Future<void> _loadIngredients() async {
    if (mounted) setState(() => _isLoadingIngredients = true);
    try {
      _ingredientes = await ProductService.getProductIngredients(_product.id);
    } catch (e) {
      print('Error loading ingredients: $e');
      _ingredientes = [];
    } finally {
      if (mounted) setState(() => _isLoadingIngredients = false);
    }
  }

  Future<void> _loadProductsUsingThisIngredient() async {
    if (mounted) setState(() => _isLoadingProductsUsingIngredient = true);
    try {
      print(' Cargando productos que usan este producto como ingrediente...');
      _productsUsingThisIngredient =
          await ProductService.getProductsUsingThisIngredient(_product.id);
      print(
        ' Productos encontrados que usan este ingrediente: ${_productsUsingThisIngredient.length}',
      );
    } catch (e) {
      print('Error loading products using this ingredient: $e');
      _productsUsingThisIngredient = [];
    } finally {
      if (mounted) setState(() => _isLoadingProductsUsingIngredient = false);
    }
  }

  Future<void> _loadStockLocations() async {
    if (mounted) setState(() => _isLoadingLocations = true);
    try {
      _stockLocations = await ProductService.getProductStockLocations(
        _product.id,
      );
    } catch (e) {
      print('Error loading stock locations: $e');
      _stockLocations = [];
    } finally {
      if (mounted) setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _loadReceptionOperations() async {
    if (mounted) setState(() => _isLoadingOperations = true);
    try {
      final response = await ProductService.getProductReceptionOperations(
        _product.id,
        page: _currentPage,
        operationIdFilter: _operationIdFilter,
      );
      _receptionOperations = response['operations'];
      _totalPages = response['totalPages'];
      _totalCount = response['totalCount'];
      _hasNextPage = response['hasNextPage'];
      _hasPreviousPage = response['hasPreviousPage'];
    } catch (e) {
      print('Error loading reception operations: $e');
      _receptionOperations = [];
    } finally {
      if (mounted) setState(() => _isLoadingOperations = false);
    }
  }

  Future<void> _loadPriceHistory() async {
    if (mounted) setState(() => _isLoadingCharts = true);
    try {
      _priceHistory = await ProductService.getProductPriceHistory(_product.id);
    } catch (e) {
      print('Error loading price history: $e');
      _priceHistory = [];
    } finally {
      if (mounted) setState(() => _isLoadingCharts = false);
    }
  }

  Future<void> _loadPromotionalPrices() async {
    if (mounted) setState(() => _isLoadingPromotions = true);
    try {
      print(' ===== CARGANDO PROMOCIONES =====');
      print(' Producto ID: ${_product.id}');

      final promociones = await ProductService.getProductPromotionalPrices(
        _product.id,
      );

      print(' Promociones recibidas en pantalla: ${promociones.length}');
      if (promociones.isNotEmpty) {
        print(' Primera promoción:');
        print('   ${promociones.first}');
      }

      if (mounted) {
        setState(() {
          _promotionalPrices = promociones;
          _isLoadingPromotions = false;
        });
      }

      print(
        ' Estado actualizado - Promociones en _promotionalPrices: ${_promotionalPrices.length}',
      );
    } catch (e, stackTrace) {
      print(' Error loading promotional prices: $e');
      print(' StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _promotionalPrices = [];
          _isLoadingPromotions = false;
        });
      }
    }
  }

  Future<void> _loadStockHistory() async {
    try {
      _stockHistory = await ProductService.getProductStockHistory(
        _product.id,
        _product.stockDisponible.toDouble(),
      );

      // Debug: Comparar stock actual del producto vs stock final del gráfico
      if (_stockHistory.isNotEmpty) {
        final stockFinalGrafico = _stockHistory.last['cantidad'];
        print(' COMPARACIÓN DE STOCK:');
        print(' Stock actual del producto: ${_product.stockDisponible}');
        print(' Stock final en gráfico: $stockFinalGrafico');
        print(' Diferencia: ${stockFinalGrafico - _product.stockDisponible}');
      }

      if (mounted) setState(() {}); // Update UI after loading data
    } catch (e) {
      print('Error loading stock history: $e');
      _stockHistory = [];
      if (mounted) setState(() {}); // Update UI even on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Detalles del Producto',
          style: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.grey[800]),
        actions: [
          if (_canEditProduct)
            IconButton(icon: const Icon(Icons.edit), onPressed: _editProduct),
          if (_canEditProduct || _canDeleteProduct)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'duplicate':
                    _duplicateProduct();
                    break;
                  case 'import_excel':
                    _importExcelCodes();
                    break;
                  case 'delete':
                    _showDeleteConfirmation();
                    break;
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<String>>[];

                if (_canEditProduct) {
                  items.add(
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(Icons.copy, size: 20),
                          SizedBox(width: 8),
                          Text('Duplicar producto'),
                        ],
                      ),
                    ),
                  );

                  items.add(
                    const PopupMenuItem(
                      value: 'import_excel',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, size: 20, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Importar códigos Excel',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (_canDeleteProduct) {
                  items.add(
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Eliminar producto',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return items;
              },
            ),
        ],
      ),
      body:
          _isLoadingPricingData
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Cargando información del producto...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductHeader(),
                    const SizedBox(height: 20),
                    _buildBasicInfo(),
                    const SizedBox(height: 20),
                    _buildPricingInfo(),
                    const SizedBox(height: 20),
                    _buildIngredientsSection(),
                    const SizedBox(height: 20),
                    _buildStockLocationsSection(),
                    const SizedBox(height: 20),
                    _buildReceptionOperationsSection(),
                    const SizedBox(height: 20),
                    _buildPriceHistoryChart(),
                    const SizedBox(height: 20),
                    _buildPromotionalPricesSection(),
                    const SizedBox(height: 20),
                    _buildStockHistorySection(),
                    const SizedBox(height: 20),
                    _buildCategoryInfo(),
                    const SizedBox(height: 20),
                    _buildVariantsSection(),
                    const SizedBox(height: 20),
                    _buildSubcategoriesSection(),
                    const SizedBox(height: 20),
                    _buildPresentationsSection(),
                    const SizedBox(height: 20),
                    _buildEquivalenciaCantidadesSection(),
                    const SizedBox(height: 20),
                    _buildMultimediaSection(),
                    const SizedBox(height: 20),
                    _buildTagsSection(),
                    const SizedBox(height: 20),
                    _buildIsIngredientSection(),
                  ],
                ),
              ),
    );
  }

  Widget _buildStockLocationsSection() {
    return _buildInfoCard(
      title: 'Ubicaciones y Stock',
      icon: Icons.location_on,
      children: [
        if (_isLoadingLocations)
          const Center(child: CircularProgressIndicator())
        else if (_stockLocations.isEmpty)
          Text(
            'No hay ubicaciones registradas',
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Column(
            children:
                _stockLocations
                    .map(
                      (location) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warehouse,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${location['almacen'] ?? 'Almacén'} - ${location['ubicacion'] ?? 'Zona'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Disponible: ${location['cantidad']} | Reservado: ${location['reservado']}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${location['cantidad']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
      ],
    );
  }

  Widget _buildIngredientsSection() {
    // Solo mostrar si el producto es elaborado
    if (!(_product.esElaborado ?? false)) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      title:
          'Ingredientes${_ingredientes.isNotEmpty ? ' (${_ingredientes.length})' : ''}',
      icon: Icons.restaurant_menu,
      children: [
        if (_isLoadingIngredients)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_ingredientes.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Este producto elaborado aún no tiene ingredientes registrados',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Los ingredientes se pueden agregar durante la creación del producto',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          )
        else ...[
          // Lista de ingredientes
          ..._ingredientes
              .map(
                (ingredient) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Imagen del ingrediente
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child:
                            ingredient['producto_imagen'] != null &&
                                    ingredient['producto_imagen']
                                        .toString()
                                        .isNotEmpty
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    ingredient['producto_imagen'],
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                          Icons.fastfood,
                                          color: Colors.grey[400],
                                          size: 30,
                                        ),
                                  ),
                                )
                                : Icon(
                                  Icons.fastfood,
                                  color: Colors.grey[400],
                                  size: 30,
                                ),
                      ),
                      const SizedBox(width: 16),

                      // Información del ingrediente
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ingredient['producto_nombre'] ??
                                  'Ingrediente sin nombre',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (ingredient['producto_sku'] != null &&
                                ingredient['producto_sku']
                                    .toString()
                                    .isNotEmpty)
                              Text(
                                'SKU: ${ingredient['producto_sku']}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            const SizedBox(height: 8),

                            // Cantidad y unidad
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Text(
                                '${ingredient['cantidad_necesaria']} ${ingredient['unidad_medida']}',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Icono indicador
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.check_circle_outline,
                          color: Colors.green[600],
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),

          // Resumen de ingredientes
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[50]!, Colors.blue[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen de Ingredientes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[800],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total de componentes: ${_ingredientes.length}',
                        style: TextStyle(color: Colors.blue[700], fontSize: 14),
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
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_ingredientes.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReceptionOperationsSection() {
    return _buildInfoCard(
      title: 'Operaciones de Inventario',
      icon: Icons.input,
      children: [
        // Acceso a movimientos
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProductMovementsScreen(product: _product),
                      ),
                    );
                  },
                  icon: const Icon(Icons.table_chart, size: 18),
                  label: const Text(
                    'Tarjeta de Estiba',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        ],
    );
  }

  Widget _buildPriceHistoryChart() {
    return _buildInfoCard(
      title: 'Histórico de Precios (30 días)',
      icon: Icons.trending_up,
      children: [
        if (_isLoadingCharts)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_priceHistory.isEmpty)
          Text(
            'No hay datos de precios disponibles',
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          )
        else
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget:
                          (value, meta) => Text(
                        '\$${value.toInt()}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 7,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < _priceHistory.length) {
                          final date =
                              _priceHistory[value.toInt()]['fecha'] as DateTime;
                          return Text(
                            DateFormat('dd/MM').format(date),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots:
                        _priceHistory.asMap().entries.map((entry) {
                          return FlSpot(
                            entry.key.toDouble(),
                            entry.value['precio'].toDouble(),
                          );
                        }).toList(),
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPromotionalPricesSection() {
    return _buildInfoCard(
      title: 'Precios Promocionales',
      icon: Icons.local_offer,
      children: [
        // AGREGAR: Indicador de carga
        if (_isLoadingPromotions)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_promotionalPrices.isEmpty)
          Column(
            children: [
              Text(
                'No hay promociones activas para este producto',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              // AGREGAR: Botón para recargar
              TextButton.icon(
                onPressed: () {
                  print(' Recargando promociones manualmente...');
                  _loadPromotionalPrices();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Recargar promociones'),
              ),
            ],
          )
        else
          Column(
            children: [
              // AGREGAR: Contador de promociones
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${_promotionalPrices.length} promoción(es) encontrada(s)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              ..._promotionalPrices.map(
                (promo) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        promo['activa']
                            ? AppColors.success.withOpacity(0.05)
                            : Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          promo['activa']
                              ? AppColors.success.withOpacity(0.3)
                              : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              promo['promocion'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  promo['activa']
                                      ? AppColors.success.withOpacity(0.1)
                                      : AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              promo['activa'] ? 'Activa' : 'Inactiva',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    promo['activa']
                                        ? AppColors.success
                                        : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // CORRECCIÓN: Cambiar Row por Column para evitar overflow
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Precio original: \$${NumberFormat('#,###.00').format(promo['precio_original'])}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Precio promocional: \$${NumberFormat('#,###.00').format(promo['precio_promocional'])}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color:
                                  promo['activa']
                                      ? AppColors.success
                                      : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vigencia: ${promo['vigencia']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStockHistorySection() {
    return _buildInfoCard(
      title: 'Histórico de Stock (30 días)',
      icon: Icons.inventory_2,
      children: [
        if (_isLoadingCharts)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_stockHistory.isEmpty)
          Text(
            'No hay datos de stock disponibles',
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          )
        else
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget:
                          (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval:
                          _stockHistory.length > 7
                              ? (_stockHistory.length / 7).ceil().toDouble()
                              : 1,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < _stockHistory.length &&
                            value.toInt() >= 0) {
                          final date =
                              _stockHistory[value.toInt()]['fecha'] as DateTime;
                          return Text(
                            DateFormat('dd/MM').format(date),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots:
                        _stockHistory.asMap().entries.map((entry) {
                          return FlSpot(
                            entry.key.toDouble(),
                            entry.value['cantidad'].toDouble(),
                          );
                        }).toList(),
                    isCurved: true,
                    color: AppColors.secondary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.secondary.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProductHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              GestureDetector(
                onTap: () {
                  // Solo mostrar en pantalla completa si hay imagen
                  if (_product.imageUrl.isNotEmpty) {
                    _showFullScreenImage(_product.imageUrl);
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child:
                      _product.imageUrl.isNotEmpty
                          ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _product.imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder:
                                      (context, error, stackTrace) => Icon(
                                        Icons.image_not_supported,
                                        color: Colors.grey[400],
                                      ),
                                ),
                              ),
                              // Indicador de que se puede hacer clic
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          )
                          : Icon(
                            Icons.inventory_2,
                            color: Colors.grey[400],
                            size: 40,
                          ),
                ),
              ),
              const SizedBox(width: 16),

              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _product.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_product.nombreComercial?.isNotEmpty == true)
                      Text(
                        _product.nombreComercial!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, // Espacio horizontal entre elementos
            runSpacing: 8, // Espacio vertical entre líneas
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      _product.isActive
                          ? AppColors.success.withOpacity(0.1)
                          : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _product.isActive ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color:
                        _product.isActive ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      _product.esVendible
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _product.esVendible ? 'Vendible' : 'No vendible',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color:
                        _product.esVendible
                            ? AppColors.primary
                            : AppColors.warning,
                  ),
                ),
              ),
              // Etiqueta "Elaborado"
              if (_product.esElaborado == true && !_product.esServicio)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: 14,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Elaborado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
              // Etiqueta "Servicio" - CORREGIDO el texto
              if (_product.esServicio == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.build, size: 14, color: Colors.purple[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Servicio', // CORREGIDO: Cambié "Elaborado" por "Servicio"
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color:
                              Colors.purple[700], // CORREGIDO: Cambié el color
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (_product.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Descripción',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _product.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return _buildInfoCard(
      title: 'Información Básica',
      icon: Icons.info_outline,
      children: [
        _buildInfoRow('SKU', _product.sku),
        _buildInfoRow(
          'Código de Barras',
          _product.barcode.isEmpty ? 'No asignado' : _product.barcode,
        ),
        _buildInfoRow('Marca', _product.brand),
        if (_product.um?.isNotEmpty == true)
          _buildInfoRow('Unidad de Medida', _product.um!),
        _buildInfoRow(
          'Creado',
          DateFormat('dd/MM/yyyy HH:mm').format(_product.createdAt),
        ),
        _buildInfoRow(
          'Actualizado',
          DateFormat('dd/MM/yyyy HH:mm').format(_product.updatedAt),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildInfoRow(
                'Proveedor',
                _product.nombreProveedor ?? 'No asignado',
              ),
            ),
            if (_canEditProduct)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: _showSupplierSelectionDialog,
                tooltip: 'Cambiar proveedor',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPricingInfo() {
    // Mostrar skeleton loader mientras se cargan los datos
    if (_isLoadingPricingData) {
      return _buildInfoCard(
        title: 'Información de Precios',
        icon: Icons.attach_money,
        children: [
          // Skeleton loader para precio base
          Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          // Skeleton loaders para presentaciones
          ...List.generate(
            3,
            (index) => Column(
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                if (index < 2) const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      );
    }

    return FutureBuilder<double>(
      future: CurrencyService.getEffectiveUsdToCupRate(),
      builder: (context, rateSnap) {
        final usdRate = rateSnap.data ?? 0.0;
        final cup = _product.basePrice;
        final usd = _product.precioVentaUsd;
        final hasBoth = cup > 0 && usd != null && usd > 0;
        final mismatch = hasBoth && usdRate > 0
            ? ((cup - usd * usdRate).abs() / (usd * usdRate)) > 0.02
            : false;

        return _buildPricingInfoContent(mismatch: mismatch, usdRate: usdRate);
      },
    );
  }

  Widget _buildPricingInfoContent({
    required bool mismatch,
    required double usdRate,
  }) {
    final allPricesZero =
        _product.presentaciones.isEmpty ||
        _product.presentaciones.every(
          (pres) => (pres['precio_promedio'] ?? 0.0) == 0.0,
        );

    final cup = _product.basePrice;
    final usd = _product.precioVentaUsd;

    return _buildInfoCard(
      title: 'Información de Precios',
      icon: Icons.attach_money,
      children: [
        // ── Precio de Venta CUP + USD ──────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Precio de Venta',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (mismatch) ...[  
                        const SizedBox(width: 6),
                        Tooltip(
                          message:
                              'Los precios CUP y USD no coinciden con la tasa\n'
                              'de conversión vigente (${usdRate.toStringAsFixed(0)} CUP/USD)',
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cup > 0
                        ? '₱${NumberFormat("#,###.00").format(cup)} CUP'
                        : 'Sin precio CUP',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cup > 0 ? AppColors.primary : AppColors.error,
                    ),
                  ),
                  if (usd != null && usd > 0) ...[  
                    const SizedBox(height: 2),
                    Text(
                      '\$${NumberFormat("#,###.00").format(usd)} USD',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: mismatch
                            ? Colors.orange[700]
                            : const Color(0xFF4A90E2),
                      ),
                    ),
                  ] else ...[  
                    const SizedBox(height: 2),
                    Text(
                      'Sin precio USD',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ],
              ),
            ),
            if (_isGerente)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: _editBasePriceDialog,
                tooltip: 'Editar precio de venta',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        if (mismatch) ...[  
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CUP esperado: ₱${NumberFormat("#,###.00").format((_product.precioVentaUsd ?? 0) * usdRate)} '
                    '(${usdRate.toStringAsFixed(0)} × USD)',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_product.presentaciones.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Sección de inicialización si todos los precios son 0
          if (allPricesZero && _isGerente) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Precios de Costo no Configurados',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Inicializa automáticamente desde operaciones de recepción',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isInitializingPrices
                              ? null
                              : _initializeAveragePrices,
                      icon:
                          _isInitializingPrices
                              ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.orange[700]!,
                                  ),
                                ),
                              )
                              : const Icon(Icons.calculate),
                      label: Text(
                        _isInitializingPrices
                            ? 'Inicializando...'
                            : 'Inicializar Precios Automáticamente',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Sección de precios de costo por presentación
          Text(
            'Precio Costo por Presentación',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          ..._product.presentaciones.map(
            (pres) => FutureBuilder<double>(
              future: CurrencyService.getEffectiveUsdToCupRate(),
              builder: (context, snapshot) {
                final exchangeRate = snapshot.data ?? 1.0;
                final precioUsd = (pres['precio_promedio'] as num?)?.toDouble() ?? 0.0;
                final precioCup = precioUsd * exchangeRate;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pres['presentacion'] ?? 'Presentación',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cantidad: ${pres['cantidad']?.toString() ?? '1'} unds',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '\$${NumberFormat('#,###.00').format(precioUsd)} USD',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₱${NumberFormat('#,###.00').format(precioCup)} CUP',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isGerente) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _editPresentationPrice(pres),
                          tooltip: 'Editar precio',
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInventoryInfo() {
    return _buildInfoCard(
      title: 'Inventario',
      icon: Icons.inventory,
      children: [
        _buildInfoRow('Stock Disponible', _product.stockDisponible.toString()),
        _buildInfoRow('Tiene Stock', _product.tieneStock ? 'Sí' : 'No'),
        // if (_product.inventario.isNotEmpty) ...[
        //   const SizedBox(height: 12),
        //   Text(r
        //     'Detalles de Inventario:',
        //     style: TextStyle(
        //       fontSize: 14,
        //       fontWeight: FontWeight.w600,
        //       color: Colors.grey[700],
        //     ),
        //   ),
        //   const SizedBox(height: 8),
        //   ..._product.inventario.map((inv) => Padding(
        //     padding: const EdgeInsets.only(bottom: 4),
        //     child: Text(
        //       '• ${inv.toString()}',
        //       style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        //     ),
        //   )),
        // ],
      ],
    );
  }

  Widget _buildCategoryInfo() {
    return _buildInfoCard(
      title: 'Categorización',
      icon: Icons.category,
      children: [
        _buildInfoRow('Categoría', _product.categoryName),
        _buildInfoRow('ID Categoría', _product.categoryId),
      ],
    );
  }

  Widget _buildVariantsSection() {
    // Usar variantesDisponibles en lugar de variants
    if (_product.variantesDisponibles.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'Variantes (${_getVariantCount()})',
      icon: Icons.tune,
      children: [..._buildVariantsList()],
    );
  }

  int _getVariantCount() {
    int totalVariants = 0;
    for (final varianteDisponible in _product.variantesDisponibles) {
      if (varianteDisponible['variante'] != null) {
        final variant = varianteDisponible['variante'];
        if (variant['opciones'] != null && variant['opciones'] is List) {
          totalVariants += (variant['opciones'] as List).length;
        } else {
          totalVariants += 1; // Single variant without options
        }
      }
    }
    return totalVariants;
  }

  List<Widget> _buildVariantsList() {
    List<Widget> variantWidgets = [];

    for (final varianteDisponible in _product.variantesDisponibles) {
      if (varianteDisponible['variante'] != null) {
        final variant = varianteDisponible['variante'];
        final atributo = variant['atributo'];

        if (variant['opciones'] != null && variant['opciones'] is List) {
          final opciones = variant['opciones'] as List<dynamic>;
          for (final opcion in opciones) {
            variantWidgets.add(
              _buildVariantCard(
                atributo: atributo,
                opcion: opcion,
                presentations: varianteDisponible['presentaciones'] ?? [],
              ),
            );
          }
        } else {
          // Variante sin opciones específicas
          variantWidgets.add(
            _buildVariantCard(
              atributo: atributo,
              opcion: null,
              presentations: varianteDisponible['presentaciones'] ?? [],
            ),
          );
        }
      }
    }

    if (variantWidgets.isEmpty) {
      variantWidgets.add(
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'No hay variantes configuradas para este producto',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return variantWidgets;
  }

  Widget _buildVariantCard({
    required Map<String, dynamic> atributo,
    required Map<String, dynamic>? opcion,
    required List<dynamic> presentations,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título de la variante
          Row(
            children: [
              Icon(Icons.tune, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${atributo['denominacion'] ?? 'Atributo'}: ${opcion?['valor'] ?? 'Sin opciones'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Información de la opción
          if (opcion != null) ...[
            if (opcion['sku_codigo'] != null &&
                opcion['sku_codigo'].toString().isNotEmpty)
              _buildInfoRow('SKU', opcion['sku_codigo'].toString()),

            if (opcion['codigo_barras'] != null &&
                opcion['codigo_barras'].toString().isNotEmpty)
              _buildInfoRow(
                'Código de Barras',
                opcion['codigo_barras'].toString(),
              ),
          ],

          // Información del atributo
          if (atributo['descripcion'] != null &&
              atributo['descripcion'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              atributo['descripcion'].toString(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // Presentaciones disponibles para esta variante
          if (presentations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.view_module,
                        color: Colors.blue[700],
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Presentaciones disponibles:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...presentations
                      .map(
                        (presentation) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${presentation['presentacion'] ?? presentation['denominacion'] ?? 'Presentación'} (${presentation['cantidad'] ?? 1} unidades)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubcategoriesSection() {
    if (_product.subcategorias.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'Subcategorías (${_product.subcategorias.length})',
      icon: Icons.subdirectory_arrow_right,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _product.subcategorias
                  .map(
                    (subcat) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        subcat['denominacion']?.toString() ?? 'Sin nombre',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  Future<void> _loadEquivalenciasPresentacion() async {
    if (mounted) setState(() => _isLoadingEquivalencias = true);
    try {
      _equivalenciasPresentacion =
          await ProductService.getEquivalenciasPresentacion(
        int.parse(_product.id),
      );
    } catch (e) {
      debugPrint('Error cargando equivalencias: $e');
      _equivalenciasPresentacion = [];
    } finally {
      if (mounted) setState(() => _isLoadingEquivalencias = false);
    }
  }

  String get _nombrePresentacionBase {
    for (final pres in _product.presentaciones) {
      if (pres['es_base'] == true) {
        return pres['presentacion']?.toString() ?? 'unidad base';
      }
    }
    if (_product.presentaciones.isNotEmpty) {
      return _product.presentaciones.first['presentacion']?.toString() ??
          'unidad base';
    }
    return _product.um?.isNotEmpty == true ? _product.um! : 'unidad base';
  }

  Widget _buildEquivalenciaCantidadesSection() {
    return _buildInfoCard(
      title: 'Equivalencia de cantidades',
      icon: Icons.swap_horiz,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Define cuántas unidades de "$_nombrePresentacionBase" equivale cada presentación. '
                  'Esta información es referencial para inventario, ventas y reportes.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_canEditProduct)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showEquivalenciaDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar equivalencia'),
            ),
          ),
        if (_isLoadingEquivalencias)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_equivalenciasPresentacion.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.compare_arrows, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No hay equivalencias configuradas',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                if (_canEditProduct) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ejemplo: 1 Caja = 12 $_nombrePresentacionBase',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ],
            ),
          )
        else
          ..._equivalenciasPresentacion.map((eq) {
            final nombre = eq['presentacion'] as String? ?? 'Presentación';
            final cantidad = (eq['cantidad'] as num?)?.toDouble() ?? 0;
            final linea = ProductService.formatEquivalenciaLine(
              presentacionNombre: nombre,
              cantidad: cantidad,
              unidadBaseNombre: _nombrePresentacionBase,
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          linea,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if ((eq['observaciones'] as String?)?.isNotEmpty ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              eq['observaciones'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_canEditProduct) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Editar',
                      onPressed: () => _showEquivalenciaDialog(equivalencia: eq),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: Colors.red[400]),
                      tooltip: 'Eliminar',
                      onPressed: () => _confirmDeleteEquivalencia(eq),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _showEquivalenciaDialog({Map<String, dynamic>? equivalencia}) async {
    final isEdit = equivalencia != null;
    final productId = int.parse(_product.id);

    List<Map<String, dynamic>> presentacionesNom =
        await ProductService.getPresentaciones();

    final idsUsados = _equivalenciasPresentacion
        .where((e) => e['id'] != equivalencia?['id'])
        .map((e) => e['id_presentacion'] as int)
        .toSet();

    presentacionesNom = presentacionesNom
        .where((p) {
          final id = (p['id'] as num).toInt();
          if (isEdit && id == equivalencia!['id_presentacion']) return true;
          return !idsUsados.contains(id);
        })
        .toList();

    if (presentacionesNom.isEmpty && !isEdit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay presentaciones disponibles para agregar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int? selectedPresentacionId = isEdit
        ? (equivalencia!['id_presentacion'] as num?)?.toInt()
        : (presentacionesNom.isNotEmpty
            ? (presentacionesNom.first['id'] as num).toInt()
            : null);

    final cantidadController = TextEditingController(
      text: isEdit
          ? (equivalencia!['cantidad'] as num?)?.toString() ?? ''
          : '',
    );
    final observacionesController = TextEditingController(
      text: equivalencia?['observaciones'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Editar equivalencia' : 'Nueva equivalencia'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unidad base: $_nombrePresentacionBase',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  if (presentacionesNom.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedPresentacionId,
                      decoration: const InputDecoration(
                        labelText: 'Presentación',
                        border: OutlineInputBorder(),
                      ),
                      items: presentacionesNom.map((p) {
                        final id = (p['id'] as num).toInt();
                        return DropdownMenuItem(
                          value: id,
                          child: Text(p['denominacion'] as String? ?? ''),
                        );
                      }).toList(),
                      onChanged: isEdit
                          ? null
                          : (v) => setDialogState(() => selectedPresentacionId = v),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cantidadController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Cantidad equivalente',
                      hintText: 'Ej: 12',
                      suffixText: _nombrePresentacionBase,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.replaceAll(',', '.') ?? '');
                      if (n == null || n <= 0) {
                        return 'Ingrese una cantidad válida mayor que 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: observacionesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                if (selectedPresentacionId == null) return;
                Navigator.pop(ctx, true);
              },
              child: Text(isEdit ? 'Guardar' : 'Agregar'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) {
      cantidadController.dispose();
      observacionesController.dispose();
      return;
    }

    try {
      final cantidad =
          double.parse(cantidadController.text.replaceAll(',', '.'));
      await ProductService.upsertEquivalenciaPresentacion(
        idProducto: productId,
        idPresentacion: selectedPresentacionId!,
        cantidad: cantidad,
        observaciones: observacionesController.text.trim().isEmpty
            ? null
            : observacionesController.text.trim(),
        id: isEdit ? (equivalencia!['id'] as int?) : null,
      );
      await _loadEquivalenciasPresentacion();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Equivalencia actualizada' : 'Equivalencia agregada'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      cantidadController.dispose();
      observacionesController.dispose();
    }
  }

  Future<void> _confirmDeleteEquivalencia(Map<String, dynamic> eq) async {
    final nombre = eq['presentacion'] as String? ?? 'esta presentación';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar equivalencia'),
        content: Text('¿Eliminar la equivalencia de "$nombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final ok = await ProductService.deleteEquivalenciaPresentacion(eq['id'] as int);
    await _loadEquivalenciasPresentacion();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Equivalencia eliminada' : 'No se pudo eliminar'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Widget _buildPresentationsSection() {
    if (_product.presentaciones.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'Presentaciones (${_product.presentaciones.length})',
      icon: Icons.view_module,
      children: [
        ..._product.presentaciones.map(
          (pres) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              'Tipo: ' +
                  pres['presentacion'] +
                  ' Cantidad equivalente: ' +
                  pres['cantidad'].toString() +
                  'unds',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultimediaSection() {
    if (_product.multimedias.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'Multimedia (${_product.multimedias.length})',
      icon: Icons.perm_media,
      children: [
        ..._product.multimedias.map(
          (media) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              media.toString(),
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection() {
    if (_product.etiquetas.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'Etiquetas (${_product.etiquetas.length})',
      icon: Icons.label,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _product.etiquetas
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  Widget _buildIsIngredientSection() {
    return _buildInfoCard(
      title:
          'Es Ingrediente${_productsUsingThisIngredient.isNotEmpty ? ' (${_productsUsingThisIngredient.length})' : ''}',
      icon: Icons.restaurant,
      children: [
        if (_isLoadingProductsUsingIngredient)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_productsUsingThisIngredient.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Este producto no es utilizado como ingrediente en otros productos',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          )
        else ...[
          // Lista de productos que usan este ingrediente
          ..._productsUsingThisIngredient
              .map(
                (product) => InkWell(
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: Colors.orange[50],
                  splashColor: Colors.orange[100],
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Icono del producto
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Icon(
                            product['es_elaborado'] == true
                                ? Icons.restaurant_menu
                                : product['es_servicio'] == true
                                ? Icons.room_service
                                : Icons.inventory_2,
                            color: Colors.grey[400],
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Información del producto
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['denominacion_producto'] ??
                                    'Producto sin nombre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (product['sku_producto'] != null &&
                                  product['sku_producto'].toString().isNotEmpty)
                                Text(
                                  'SKU: ${product['sku_producto']}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              const SizedBox(height: 8),

                              // Cantidad necesaria y unidad
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.orange[200]!,
                                      ),
                                    ),
                                    child: Text(
                                      '${product['cantidad_necesaria']} ${product['unidad_medida']}',
                                      style: TextStyle(
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Tipo de producto
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          product['es_elaborado'] == true
                                              ? Colors.green[50]
                                              : product['es_servicio'] == true
                                              ? Colors.blue[50]
                                              : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      product['es_elaborado'] == true
                                          ? 'Elaborado'
                                          : product['es_servicio'] == true
                                          ? 'Servicio'
                                          : 'Producto',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            product['es_elaborado'] == true
                                                ? Colors.green[700]
                                                : product['es_servicio'] == true
                                                ? Colors.blue[700]
                                                : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),

          // Resumen de productos
          if (_productsUsingThisIngredient.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange[50]!, Colors.orange[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.summarize, color: Colors.orange[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de Uso',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[800],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Este producto es ingrediente en ${_productsUsingThisIngredient.length} producto(s)',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 14,
                          ),
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
                      color: Colors.orange[600],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_productsUsingThisIngredient.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToProductDetail(
    Map<String, dynamic> productData,
  ) async {
    try {
      print(
        ' Navegando al detalle del producto: ${productData['denominacion_producto']}',
      );
      print(' ID del producto: ${productData['id_producto_elaborado']}');

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Obtener el producto completo por ID
      final product = await ProductService.getProductoCompletoById(
        productData['id_producto_elaborado'],
      );

      // Cerrar el indicador de carga
      Navigator.pop(context);

      if (product != null) {
        // Navegar al detalle del producto
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: product),
          ),
        );
      } else {
        // Mostrar error si no se pudo cargar el producto
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cargar el detalle del producto'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      // Cerrar el indicador de carga si está abierto
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      print(' Error navegando al detalle del producto: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar el producto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _editProduct() {
    if (!_canEditProduct) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddProductScreen(
              product: _product,
              onProductSaved: () {
                // Refresh the product data after editing
                print(' Producto editado, recargando datos...');
                _loadAdditionalData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Producto actualizado exitosamente'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
            ),
      ),
    );
  }

  Future<void> _duplicateProduct() async {
    final canEdit = await _permissionsService.canPerformAction('product.edit');
    if (!canEdit) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      }
      return;
    }
    try {
      if (mounted) setState(() => _isLoading = true);

      final result = await ProductService.duplicateProduct(_product.id);

      if (result != null && result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Producto duplicado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );

        // Navigate back to products list
        Navigator.pop(context);
      } else {
        throw Exception('Error al duplicar el producto');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al duplicar producto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importExcelCodes() async {
    final canEdit = await _permissionsService.canPerformAction('product.edit');
    if (!canEdit) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      }
      return;
    }
    try {
      // Seleccionar archivo Excel
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        if (mounted) setState(() => _isLoading = true);

        Uint8List bytes = result.files.single.bytes!;
        var excel = excel_lib.Excel.decodeBytes(bytes);

        // Obtener la primera hoja
        String sheetName = excel.tables.keys.first;
        excel_lib.Sheet sheet = excel.tables[sheetName]!;

        List<Map<String, String>> validData = [];
        int processedRows = 0;
        int skippedRows = 0;

        // Procesar filas (empezar desde la fila 1 para saltar encabezados)
        for (int rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
          var row = sheet.rows[rowIndex];

          if (row.length >= 2) {
            String? codigo = row[0]?.value?.toString()?.trim();
            String? denominacion = row[1]?.value?.toString()?.trim();

            // Filtrar solo los que tienen valor en código
            if (codigo != null &&
                codigo.isNotEmpty &&
                denominacion != null &&
                denominacion.isNotEmpty) {
              validData.add({'codigo': codigo, 'denominacion': denominacion});
              processedRows++;
            } else {
              skippedRows++;
            }
          } else {
            skippedRows++;
          }
        }

        if (validData.isEmpty) {
          throw Exception('No se encontraron datos válidos en el Excel');
        }

        // Mostrar diálogo de confirmación con resumen
        bool? confirmed = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Confirmar Importación'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Se procesarán $processedRows registros válidos:'),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              validData
                                  .take(10)
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '• ${item['denominacion']} → ${item['codigo']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  )
                                  .toList() +
                              (validData.length > 10
                                  ? [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '... y ${validData.length - 10} más',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ]
                                  : []),
                        ),
                      ),
                    ),
                    if (skippedRows > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Se omitieron $skippedRows filas sin datos válidos',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Esto actualizará la "denominación corta" de los productos encontrados.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Importar'),
                  ),
                ],
              ),
        );

        if (confirmed == true) {
          // Procesar actualizaciones usando el método masivo
          final result = await ProductService.updateMultipleProductShortNames(
            validData,
          );

          // Extraer estadísticas del resultado
          final summary = result['summary'] ?? {};
          final updatedCount = summary['successful'] ?? 0;
          final notFoundCount = summary['failed'] ?? 0;
          final totalProcessed = summary['total_processed'] ?? 0;
          final successRate = summary['success_rate'] ?? 0.0;

          // Extraer errores detallados si existen
          List<String> errors = [];
          if (result['results'] != null) {
            final results = result['results'] as List<dynamic>;
            for (var res in results) {
              if (res['success'] == false) {
                final denomination =
                    res['searched_denomination'] ?? 'Desconocido';
                final error = res['error'] ?? 'Error desconocido';
                errors.add('$denomination: $error');
              }
            }
          }

          // Mostrar resultado
          showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        result['success'] == true
                            ? Icons.check_circle
                            : Icons.warning,
                        color:
                            result['success'] == true
                                ? Colors.green
                                : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      const Text('Importación Completada'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumen de Procesamiento',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('📊 Total procesados: $totalProcessed'),
                              Text(
                                '✅ Actualizados exitosamente: $updatedCount',
                              ),
                              Text(
                                '⚠️ No encontrados/fallidos: $notFoundCount',
                              ),
                              Text(
                                '📈 Tasa de éxito: ${successRate.toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                        ),
                        if (errors.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            '❌ Detalles de errores (${errors.length}):',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children:
                                    errors
                                        .take(10)
                                        .map(
                                          (error) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 1,
                                            ),
                                            child: Text(
                                              '• $error',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList() +
                                    (errors.length > 10
                                        ? [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 1,
                                            ),
                                            child: Text(
                                              '... y ${errors.length - 10} errores más',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                        ]
                                        : []),
                              ),
                            ),
                          ),
                        ],
                        if (updatedCount > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '✨ Se actualizaron $updatedCount productos exitosamente',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al importar Excel: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDeleteConfirmation() async {
    final canDelete = await _permissionsService.canPerformAction(
      'product.delete',
    );
    if (!canDelete) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Eliminar producto');
      }
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Producto'),
            content: Text(
              '¿Estás seguro de que deseas eliminar "${_product.name}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteProduct();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteProduct() async {
    final canDelete = await _permissionsService.canPerformAction(
      'product.delete',
    );
    if (!canDelete) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Eliminar producto');
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirmar eliminación'),
            content: Text(
              '¿Estás seguro de que deseas eliminar el producto "${_product.name}"?\n\n'
              'Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        if (mounted) setState(() => _isLoading = true);

        final success = await ProductService.deleteProduct(_product.id);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Producto eliminado exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );

          // Navigate back to products list
          Navigator.pop(context);
        } else {
          throw Exception('Error al eliminar el producto');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar producto: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Muestra la imagen del producto en pantalla completa
  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              // Imagen en pantalla completa
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Cargando imagen...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error al cargar la imagen',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Botón de cerrar
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Información del producto en la parte inferior
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _product.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_product.sku.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'SKU: ${_product.sku}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Toca y arrastra para mover • Pellizca para hacer zoom',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Abre un diálogo para editar el precio base del producto
  void _editBasePriceDialog() {
    final priceController = TextEditingController(
      text: _product.basePrice.toStringAsFixed(2),
    );
    final screenContext = context;

    showDialog(
      context: screenContext,
      builder: (BuildContext dialogContext) {
        return FutureBuilder<double>(
          future: CurrencyService.getEffectiveUsdToCupRate(),
          builder: (context, rateSnapshot) {
            final exchangeRate = rateSnapshot.data ?? 1.0;
            final rateLoaded = rateSnapshot.connectionState == ConnectionState.done;

            return _BasePriceEditDialog(
              denominacion: _product.denominacion,
              priceController: priceController,
              exchangeRate: exchangeRate,
              rateLoaded: rateLoaded,
              initialUsdPrice: _product.precioVentaUsd,
              onSave: (double finalCupPrice, double? finalUsdPrice) async {
                try {
                  final success = await ProductService.updateBasePriceVenta(
                    productId: int.parse(_product.id),
                    newPrice: finalCupPrice,
                    newPriceUsd: finalUsdPrice,
                  );

                  if (!mounted) return;

                  if (success) {
                    Navigator.pop(dialogContext);
                    await _loadAdditionalData();
                    if (!mounted) return;
                    ScaffoldMessenger.of(screenContext).showSnackBar(
                      const SnackBar(
                        content: Text('Precio base actualizado exitosamente'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(screenContext).showSnackBar(
                      const SnackBar(
                        content: Text('Error al actualizar el precio'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(screenContext).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar precio: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  /// Inicializa los precios promedio de las presentaciones
  /// Busca operaciones de recepción y calcula el promedio
  Future<void> _initializeAveragePrices() async {
    if (!mounted) return;

    setState(() => _isInitializingPrices = true);

    try {
      print('🔍 Iniciando inicialización de precios promedio...');

      final result = await ProductService.initializePresentationAveragePrices(
        productId: _product.id,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final updated = result['updated'] as int? ?? 0;
        print('✅ Precios inicializados: $updated presentaciones actualizadas');

        // Recargar los datos del producto
        await _loadAdditionalData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$updated presentaciones actualizadas con precios promedio',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        final error = result['error'] ?? 'Error desconocido';
        print('❌ Error: $error');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error al inicializar precios: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al inicializar precios: $e'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isInitializingPrices = false);
      }
    }
  }

  /// Abre un diálogo para editar el precio promedio de una presentación
  void _editPresentationPrice(Map<String, dynamic> presentation) {
    final priceController = TextEditingController(
      text: ((presentation['precio_promedio'] ?? 0.0) as num)
          .toDouble()
          .toStringAsFixed(2),
    );
    final screenContext = context;

    showDialog(
      context: screenContext,
      builder: (BuildContext dialogContext) {
        return FutureBuilder<double>(
          future: CurrencyService.getEffectiveUsdToCupRate(),
          builder: (context, rateSnapshot) {
            final exchangeRate = rateSnapshot.data ?? 1.0;
            final rateLoaded =
                rateSnapshot.connectionState == ConnectionState.done;

            return _PresentationPriceEditDialog(
              presentationName:
                  presentation['presentacion'] ?? 'Presentación',
              cantidad: presentation['cantidad']?.toString() ?? '1',
              priceController: priceController,
              exchangeRate: exchangeRate,
              rateLoaded: rateLoaded,
              onSave: (double finalUsdPrice) async {
                try {
                  final success =
                      await ProductService.updatePresentationAveragePrice(
                        presentationId: presentation['id'].toString(),
                        newPrice: finalUsdPrice,
                      );

                  if (!mounted) return;

                  if (success) {
                    Navigator.pop(dialogContext);
                    await _loadAdditionalData();
                    if (!mounted) return;
                    ScaffoldMessenger.of(screenContext).showSnackBar(
                      const SnackBar(
                        content: Text('Precio actualizado exitosamente'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(screenContext).showSnackBar(
                      const SnackBar(
                        content: Text('Error al actualizar el precio'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(screenContext).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showSupplierSelectionDialog() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      List<Supplier> suppliers = await SupplierService.getAllSuppliers();
      if (mounted) setState(() => _isLoading = false);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Seleccionar Proveedor'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: suppliers.isEmpty
                      ? const Text('No hay proveedores registrados para esta tienda.')
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: suppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = suppliers[index];
                            return ListTile(
                              title: Text(supplier.denominacion),
                              subtitle: Text(supplier.skuCodigo),
                              selected: _product.idProveedor == supplier.id,
                              onTap: () {
                                Navigator.pop(context);
                                _updateProductSupplier(supplier);
                              },
                            );
                          },
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddEditSupplierScreen(),
                        ),
                      );
                      if (result == true) {
                        setDialogState(() => _isLoading = true);
                        final updatedSuppliers = await SupplierService.getAllSuppliers();
                        setDialogState(() {
                          suppliers = updatedSuppliers;
                          _isLoading = false;
                        });
                      }
                    },
                    child: const Text('Nuevo'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  if (_product.idProveedor != null)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateProductSupplier(null);
                      },
                      child: const Text('Quitar Proveedor', style: TextStyle(color: Colors.red)),
                    ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
        );
      }
    }
  }

  Future<void> _updateProductSupplier(Supplier? supplier) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final success = await ProductService.updateProductSupplier(
        int.parse(_product.id),
        supplier?.id,
      );

      if (success) {
        // Recargar datos para ver el nombre actualizado
        final updatedProduct = await ProductService.getProductoCompletoById(int.parse(_product.id));
        if (updatedProduct != null && mounted) {
          setState(() {
            _product = updatedProduct;
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proveedor actualizado correctamente')),
          );
        }
      } else {
        throw Exception('No se pudo actualizar el proveedor');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar proveedor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _operationFilterController.dispose();
    super.dispose();
  }

  Color _getOperationTypeColor(String tipoOperacion) {
    switch (tipoOperacion.toLowerCase()) {
      case 'recepción':
        return AppColors.success;
      case 'venta':
        return AppColors.primary;
      case 'extracción':
        return AppColors.warning;
      default:
        return AppColors.textLight;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Diálogo para editar Precio Base con dos campos (CUP y USD).
// Ambos campos están siempre visibles y se auto-convierten con la tasa actual.
// ──────────────────────────────────────────────────────────────────────────────
class _BasePriceEditDialog extends StatefulWidget {
  final String denominacion;
  final TextEditingController priceController;
  final double exchangeRate;
  final bool rateLoaded;
  final double? initialUsdPrice;
  final Future<void> Function(double finalCupPrice, double? finalUsdPrice) onSave;

  const _BasePriceEditDialog({
    required this.denominacion,
    required this.priceController,
    required this.exchangeRate,
    required this.rateLoaded,
    this.initialUsdPrice,
    required this.onSave,
  });

  @override
  State<_BasePriceEditDialog> createState() => _BasePriceEditDialogState();
}

class _BasePriceEditDialogState extends State<_BasePriceEditDialog> {
  late final TextEditingController _usdController;
  bool _isSaving = false;
  bool _updatingFromCup = false;
  bool _updatingFromUsd = false;

  @override
  void initState() {
    super.initState();
    _usdController = TextEditingController(
      text: widget.initialUsdPrice != null && widget.initialUsdPrice! > 0
          ? widget.initialUsdPrice!.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _usdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Precio Base'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Producto: ${widget.denominacion}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (widget.rateLoaded && widget.exchangeRate > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Tasa: ${widget.exchangeRate.toStringAsFixed(0)} CUP/USD',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('Obteniendo tasa...', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Campo CUP
            TextField(
              controller: widget.priceController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
              onChanged: (value) {
                if (_updatingFromUsd) return;
                _updatingFromCup = true;
                if (widget.exchangeRate > 0) {
                  final cup = double.tryParse(value);
                  if (cup != null && cup > 0) {
                    final usdText = (cup / widget.exchangeRate).toStringAsFixed(2);
                    if (_usdController.text != usdText) {
                      _usdController.text = usdText;
                    }
                  } else {
                    _usdController.clear();
                  }
                }
                setState(() {});
                _updatingFromCup = false;
              },
              decoration: const InputDecoration(
                labelText: 'Precio en CUP',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 12),
            // Campo USD
            TextField(
              controller: _usdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
              onChanged: (value) {
                if (_updatingFromCup) return;
                _updatingFromUsd = true;
                if (widget.exchangeRate > 0) {
                  final usd = double.tryParse(value);
                  if (usd != null && usd > 0) {
                    final cupText = (usd * widget.exchangeRate).toStringAsFixed(2);
                    if (widget.priceController.text != cupText) {
                      widget.priceController.text = cupText;
                    }
                  } else {
                    widget.priceController.clear();
                  }
                }
                setState(() {});
                _updatingFromUsd = false;
              },
              decoration: const InputDecoration(
                labelText: 'Precio en USD',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _isSaving
                  ? null
                  : () async {
                    final cup = double.tryParse(widget.priceController.text);
                    if (cup == null || cup <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ingresa un precio CUP válido'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    final usd = double.tryParse(_usdController.text);
                    final finalUsd = (usd != null && usd > 0) ? usd : null;
                    setState(() => _isSaving = true);
                    await widget.onSave(cup, finalUsd);
                    if (mounted) setState(() => _isSaving = false);
                  },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90E2),
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Diálogo para editar Precio de Presentación (almacenado en USD)
// El usuario puede ingresar en USD o CUP.
// Si ingresa USD  → se guarda directo.
// Si ingresa CUP  → se convierte a USD antes de guardar (cup / tasa).
// ──────────────────────────────────────────────────────────────────────────────
class _PresentationPriceEditDialog extends StatefulWidget {
  final String presentationName;
  final String cantidad;
  final TextEditingController priceController;
  final double exchangeRate;
  final bool rateLoaded;
  final Future<void> Function(double finalUsdPrice) onSave;

  const _PresentationPriceEditDialog({
    required this.presentationName,
    required this.cantidad,
    required this.priceController,
    required this.exchangeRate,
    required this.rateLoaded,
    required this.onSave,
  });

  @override
  State<_PresentationPriceEditDialog> createState() =>
      _PresentationPriceEditDialogState();
}

class _PresentationPriceEditDialogState
    extends State<_PresentationPriceEditDialog> {
  String _inputCurrency = 'usd'; // 'cup' | 'usd'
  bool _isSaving = false;

  String get _equivalentText {
    if (!widget.rateLoaded || widget.exchangeRate <= 0) return '';
    final v = double.tryParse(widget.priceController.text) ?? 0.0;
    if (_inputCurrency == 'usd') {
      final cup = v * widget.exchangeRate;
      return '≈ ₱${NumberFormat("#,###.00").format(cup)} CUP';
    } else {
      final usd = v / widget.exchangeRate;
      return '≈ \$${NumberFormat("#,###.00").format(usd)} USD';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar Precio – ${widget.presentationName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cantidad: ${widget.cantidad} unds',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          // Selector de moneda
          Row(
            children: [
              Expanded(
                child: _CurrencyToggleButton(
                  label: 'USD',
                  icon: Icons.attach_money,
                  color: const Color(0xFF4A90E2),
                  selected: _inputCurrency == 'usd',
                  onTap: () => setState(() {
                    _inputCurrency = 'usd';
                    widget.priceController.clear();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CurrencyToggleButton(
                  label: 'CUP',
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF10B981),
                  selected: _inputCurrency == 'cup',
                  onTap: () => setState(() {
                    _inputCurrency = 'cup';
                    widget.priceController.clear();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.priceController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: false,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText:
                  _inputCurrency == 'usd'
                      ? 'Nuevo precio en USD'
                      : 'Nuevo precio en CUP',
              prefixText: _inputCurrency == 'usd' ? '\$ ' : '₱ ',
              border: const OutlineInputBorder(),
              hintText: '0.00',
            ),
          ),
          if (_equivalentText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _equivalentText,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (!widget.rateLoaded)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Obteniendo tasa de cambio...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _isSaving
                  ? null
                  : () async {
                    final raw = double.tryParse(widget.priceController.text);
                    if (raw == null || raw < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ingresa un precio válido'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    // Convertir a USD si el usuario ingresó CUP
                    final finalUsd =
                        _inputCurrency == 'cup'
                            ? (widget.exchangeRate > 0
                                ? raw / widget.exchangeRate
                                : raw)
                            : raw;
                    setState(() => _isSaving = true);
                    await widget.onSave(finalUsd);
                    if (mounted) setState(() => _isSaving = false);
                  },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A90E2), foregroundColor: Colors.white),
          child:
              _isSaving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                  : const Text('Guardar'),
        ),
      ],
    );
  }
}

// Botón de toggle de moneda reutilizable
class _CurrencyToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CurrencyToggleButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
