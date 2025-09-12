import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../widgets/marketing_menu_widget.dart';
import '../screens/add_product_screen.dart';
import '../widgets/reception_edit_dialog.dart';

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

  // Pagination and filtering for reception operations
  int _currentPage = 1;
  int _totalPages = 0;
  int _totalCount = 0;
  bool _hasNextPage = false;
  bool _hasPreviousPage = false;
  final TextEditingController _operationFilterController = TextEditingController();
  String? _operationIdFilter;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _loadAdditionalData();
  }

  Future<void> _loadAdditionalData() async {
    await Future.wait([
      _loadStockLocations(),
      _loadReceptionOperations(),
      _loadPriceHistory(),
      _loadPromotionalPrices(),
      _loadStockHistory(),
    ]);
  }

  Future<void> _loadStockLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      _stockLocations = await ProductService.getProductStockLocations(_product.id);
    } catch (e) {
      print('Error loading stock locations: $e');
      _stockLocations = [];
    } finally {
      setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _loadReceptionOperations() async {
    setState(() => _isLoadingOperations = true);
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
      setState(() => _isLoadingOperations = false);
    }
  }

  Future<void> _loadPriceHistory() async {
    setState(() => _isLoadingCharts = true);
    try {
      _priceHistory = await ProductService.getProductPriceHistory(_product.id);
    } catch (e) {
      print('Error loading price history: $e');
      _priceHistory = [];
    } finally {
      setState(() => _isLoadingCharts = false);
    }
  }

  Future<void> _loadPromotionalPrices() async {
    try {
      _promotionalPrices = await ProductService.getProductPromotionalPrices(_product.id);
    } catch (e) {
      print('Error loading promotional prices: $e');
      _promotionalPrices = [];
    }
  }

  Future<void> _loadStockHistory() async {
    try {
      _stockHistory = await ProductService.getProductStockHistory(_product.id, _product.stockDisponible.toDouble());
      
      // Debug: Comparar stock actual del producto vs stock final del gráfico
      if (_stockHistory.isNotEmpty) {
        final stockFinalGrafico = _stockHistory.last['cantidad'];
        print('🔍 COMPARACIÓN DE STOCK:');
        print('📦 Stock actual del producto: ${_product.stockDisponible}');
        print('📈 Stock final en gráfico: $stockFinalGrafico');
        print('📊 Diferencia: ${stockFinalGrafico - _product.stockDisponible}');
      }
      
      setState(() {}); // Update UI after loading data
    } catch (e) {
      print('Error loading stock history: $e');
      _stockHistory = [];
      setState(() {}); // Update UI even on error
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
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editProduct,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'duplicate':
                  _duplicateProduct();
                  break;
                case 'delete':
                  _showDeleteConfirmation();
                  break;
              }
            },
            itemBuilder: (context) => [
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
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Eliminar producto', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                  _buildInventoryInfo(),
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
                  _buildMultimediaSection(),
                  const SizedBox(height: 20),
                  _buildTagsSection(),
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
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          )
        else
          Column(
            children: _stockLocations.map((location) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warehouse, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location['ubicacion'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Disponible: ${location['cantidad']} | Reservado: ${location['reservado']}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            )).toList(),
          ),
      ],
    );
  }

  Widget _buildReceptionOperationsSection() {
    return _buildInfoCard(
      title: 'Operaciones de Entrada',
      icon: Icons.input,
      children: [
        if (_isLoadingOperations)
          const Center(child: CircularProgressIndicator())
        else if (_receptionOperations.isEmpty)
          Text(
            'No hay operaciones de entrada registradas',
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _operationFilterController,
                      decoration: const InputDecoration(
                        labelText: 'Filtro por ID',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _operationIdFilter = value.isEmpty ? null : value;
                          _currentPage = 1;
                        });
                        _loadReceptionOperations();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _operationIdFilter = null;
                        _currentPage = 1;
                      });
                      _loadReceptionOperations();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Limpiar filtro'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: _receptionOperations.map((operation) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            operation['documento'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+${operation['cantidad']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              // Validate operation ID before opening dialog
                              final operationId = operation['id_operacion'] ?? operation['id'] ?? operation['operacion_id'];
                              if (operationId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No se puede editar: ID de operación no válido'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              showDialog(
                                context: context,
                                builder: (context) => ReceptionEditDialog(
                                  operationId: operationId.toString(),
                                  operationData: operation,
                                  onUpdated: () {
                                    _loadReceptionOperations();
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow('Fecha', DateFormat('dd/MM/yyyy HH:mm').format(operation['fecha'])),
                      _buildInfoRow('Proveedor', operation['proveedor']),
                      _buildInfoRow('Usuario', operation['usuario']),
                    ],
                  ),
                )).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: _hasPreviousPage
                        ? () {
                            setState(() => _currentPage--);
                            _loadReceptionOperations();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasPreviousPage ? AppColors.primary : AppColors.textLight,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Anterior'),
                  ),
                  Text(
                    'Página ${_currentPage} de ${_totalPages}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  ElevatedButton(
                    onPressed: _hasNextPage
                        ? () {
                            setState(() => _currentPage++);
                            _loadReceptionOperations();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasNextPage ? AppColors.primary : AppColors.textLight,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
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
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
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
                      getTitlesWidget: (value, meta) => Text(
                        '\$${value.toInt()}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
                          final date = _priceHistory[value.toInt()]['fecha'] as DateTime;
                          return Text(
                            DateFormat('dd/MM').format(date),
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _priceHistory.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value['precio'].toDouble());
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
        if (_promotionalPrices.isEmpty)
          Text(
            'No hay promociones activas para este producto',
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          )
        else
          Column(
            children: _promotionalPrices.map((promo) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: promo['activa'] ? AppColors.success.withOpacity(0.05) : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: promo['activa'] ? AppColors.success.withOpacity(0.3) : Colors.grey[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        promo['promocion'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: promo['activa'] ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          promo['activa'] ? 'Activa' : 'Inactiva',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: promo['activa'] ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Precio original: \$${NumberFormat('#,###.00').format(promo['precio_original'])}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Precio promocional: \$${NumberFormat('#,###.00').format(promo['precio_promocional'])}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: promo['activa'] ? AppColors.success : Colors.grey[600],
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
            )).toList(),
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
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
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
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _stockHistory.length > 7 ? (_stockHistory.length / 7).ceil().toDouble() : 1,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < _stockHistory.length && value.toInt() >= 0) {
                          final date = _stockHistory[value.toInt()]['fecha'] as DateTime;
                          return Text(
                            DateFormat('dd/MM').format(date),
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _stockHistory.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value['cantidad'].toDouble());
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
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _product.imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(Icons.image_not_supported, color: Colors.grey[400]),
                        ),
                      )
                    : Icon(Icons.inventory_2, color: Colors.grey[400], size: 40),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _product.isActive ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _product.isActive ? 'Activo' : 'Inactivo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _product.isActive ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _product.esVendible ? AppColors.primary.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _product.esVendible ? 'Vendible' : 'No vendible',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _product.esVendible ? AppColors.primary : AppColors.warning,
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
        _buildInfoRow('Código de Barras', _product.barcode.isEmpty ? 'No asignado' : _product.barcode),
        _buildInfoRow('Marca', _product.brand),
        if (_product.um?.isNotEmpty == true)
          _buildInfoRow('Unidad de Medida', _product.um!),
        _buildInfoRow('Creado', DateFormat('dd/MM/yyyy HH:mm').format(_product.createdAt)),
        _buildInfoRow('Actualizado', DateFormat('dd/MM/yyyy HH:mm').format(_product.updatedAt)),
      ],
    );
  }

  Widget _buildPricingInfo() {
    return _buildInfoCard(
      title: 'Información de Precios',
      icon: Icons.attach_money,
      children: [
        _buildInfoRow('Precio Base', '\$${NumberFormat('#,###.00').format(_product.basePrice)}'),
        // TODO: Add more pricing information from variants
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
        if (_product.inventario.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Detalles de Inventario:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          ..._product.inventario.map((inv) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• ${inv.toString()}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          )),
        ],
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
    if (_product.variants.isEmpty) return const SizedBox.shrink();
    
    return _buildInfoCard(
      title: 'Variantes (${_product.variants.length})',
      icon: Icons.tune,
      children: [
        ..._product.variants.map((variant) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                variant.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (variant.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  variant.description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Precio: \$${NumberFormat('#,###.00').format(variant.price)}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        )),
      ],
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
          children: _product.subcategorias.map((subcat) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Text(
              subcat['denominacion']?.toString() ?? 'Sin nombre',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildPresentationsSection() {
    if (_product.presentaciones.isEmpty) return const SizedBox.shrink();
    
    return _buildInfoCard(
      title: 'Presentaciones (${_product.presentaciones.length})',
      icon: Icons.view_module,
      children: [
        ..._product.presentaciones.map((pres) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Text(
            pres.toString(),
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        )),
      ],
    );
  }

  Widget _buildMultimediaSection() {
    if (_product.multimedias.isEmpty) return const SizedBox.shrink();
    
    return _buildInfoCard(
      title: 'Multimedia (${_product.multimedias.length})',
      icon: Icons.perm_media,
      children: [
        ..._product.multimedias.map((media) => Container(
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
        )),
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
          children: _product.etiquetas.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          )).toList(),
        ),
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductScreen(
          product: _product,
          onProductSaved: () {
            // Refresh the product data after editing
            Navigator.pop(context);
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
    try {
      setState(() => _isLoading = true);
      
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
      setState(() => _isLoading = false);
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Estás seguro de que deseas eliminar "${_product.name}"?'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
        setState(() => _isLoading = true);
        
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
