import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/promotion.dart' hide Product;
import '../models/product.dart';
import '../services/promotion_service.dart';
import '../services/product_service.dart';
import '../widgets/marketing_menu_widget.dart';
import 'promotion_form_screen.dart';

class PromotionDetailScreen extends StatefulWidget {
  final Promotion promotion;

  const PromotionDetailScreen({super.key, required this.promotion});

  @override
  State<PromotionDetailScreen> createState() => _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends State<PromotionDetailScreen> {
  final PromotionService _promotionService = PromotionService();
  late Promotion _promotion;
  bool _isLoading = false;
  bool _isLoadingProducts = false;
  Map<String, Product> _productCache = {};
  List<Product> _promotionProducts = []; // Products affected by this promotion

  @override
  void initState() {
    super.initState();
    _promotion = widget.promotion;
    _loadProductData();
  }

  Future<void> _loadProductData() async {
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      if (_promotion.aplicaTodo) {
        // Si aplica a todos los productos, obtener todos los productos de la tienda
        final products = await ProductService.getProductsByTienda();
        
        // Crear un mapa de productos por ID para búsqueda rápida
        for (final product in products) {
          _productCache[product.id] = product;
        }
        
        _promotionProducts = products;
        print('✅ Cargados ${_productCache.length} productos (aplica a todos)');
      } else {
        // Si no aplica a todos, obtener solo los productos específicos de la promoción
        _promotionProducts = await _promotionService.getPromotionProducts(_promotion.id);
        
        // También cargar en caché para búsqueda rápida
        for (final product in _promotionProducts) {
          _productCache[product.id] = product;
        }
        
        print('✅ Cargados ${_promotionProducts.length} productos específicos de la promoción');
      }
    } catch (e) {
      print('❌ Error cargando productos: $e');
      _promotionProducts = [];
    } finally {
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _refreshPromotion() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedPromotion = await _promotionService.getPromotionById(
        _promotion.id,
      );
      setState(() {
        _promotion = updatedPromotion;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error al actualizar promoción: $e');
    }
  }

  Future<void> _toggleStatus() async {
    try {
      await _promotionService.togglePromotionStatus(
        _promotion.id,
        !_promotion.estado,
      );
      setState(() {
        _promotion = _promotion.copyWith(estado: !_promotion.estado);
      });
      _showSuccessSnackBar(
        _promotion.estado
            ? 'Promoción activada exitosamente'
            : 'Promoción desactivada exitosamente',
      );
    } catch (e) {
      _showErrorSnackBar('Error al cambiar estado: $e');
    }
  }

  Future<void> _deletePromotion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Promoción'),
            content: Text('¿Está seguro de eliminar "${_promotion.nombre}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _promotionService.deletePromotion(_promotion.id);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        _showErrorSnackBar('Error al eliminar promoción: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  Future<void> _createSpecialPromotion(Product product) async {
    try {
      // Fetch promotion types first
      final promotionTypes = await _promotionService.getPromotionTypes();
      
      // Navigate to promotion form with pre-filled product data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PromotionFormScreen(
            promotionTypes: promotionTypes,
            prefilledProduct: product,
            onPromotionCreated: (newPromotion) {
              // Refresh the current screen when a new promotion is created
              _refreshPromotion();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Promoción especial creada exitosamente'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar tipos de promoción: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _promotion.fechaFin?.isBefore(DateTime.now()) ?? false;
    final isActive = _promotion.estado && !isExpired;

    return Scaffold(
      appBar: AppBar(
        title: Text(_promotion.nombre),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          const MarketingMenuWidget(),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _navigateToEdit(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'toggle':
                  _toggleStatus();
                  break;
                case 'delete':
                  _deletePromotion();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          _promotion.estado ? Icons.pause : Icons.play_arrow,
                        ),
                        const SizedBox(width: 8),
                        Text(_promotion.estado ? 'Desactivar' : 'Activar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _refreshPromotion,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(isActive, isExpired),
                      const SizedBox(height: 16),
                      // Mostrar advertencia si es promoción con recargo
                      if (_promotion.isChargePromotion)
                        Card(
                          color: AppColors.promotionChargeBg,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.promotionCharge,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: AppColors.promotionCharge,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PROMOCIÓN CON RECARGO',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.promotionCharge,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _promotion.chargeWarningMessage,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppColors.promotionCharge,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.promotionChargeBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info,
                                        color: AppColors.promotionCharge,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Esta promoción aplicará un recargo adicional al precio base de los productos, resultando en un aumento del precio final de venta.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.promotionCharge,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_promotion.isChargePromotion)
                        const SizedBox(height: 16),
                      _buildBasicInfoCard(),
                      const SizedBox(height: 16),
                      _buildDiscountInfoCard(),
                      const SizedBox(height: 16),
                      _buildDateRangeCard(),
                      const SizedBox(height: 16),
                      _buildUsageCard(),
                      const SizedBox(height: 16),
                      _buildProductsCard(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildStatusCard(bool isActive, bool isExpired) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isExpired) {
      statusColor = AppColors.expired;
      statusText = 'Promoción Vencida';
      statusIcon = Icons.event_busy;
    } else if (isActive) {
      statusColor = AppColors.active;
      statusText = 'Promoción Activa';
      statusIcon = Icons.check_circle;
    } else {
      statusColor = AppColors.inactive;
      statusText = 'Promoción Inactiva';
      statusIcon = Icons.pause_circle;
    }

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [
              statusColor.withOpacity(0.1),
              statusColor.withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _promotion.codigoPromocion,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Información General',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Nombre', _promotion.nombre),
            _buildInfoRow(
              'Descripción',
              _promotion.descripcion ?? 'Sin descripción',
            ),
            _buildInfoRow(
              'Tipo',
              _promotion.tipoPromocion?.denominacion ?? 'No especificado',
            ),
            _buildInfoRow('Aplica a todo', _promotion.aplicaTodo ? 'Sí' : 'No'),
            if (_promotion.minCompra != null)
              _buildInfoRow(
                'Compra mínima',
                '\$${NumberFormat('#,###').format(_promotion.minCompra)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountInfoCard() {
    final isCharge = _promotion.isChargePromotion;
    final color = isCharge ? AppColors.promotionCharge : AppColors.promotionDiscount;
    final backgroundColor = isCharge ? AppColors.promotionChargeBg : AppColors.promotionDiscountBg;
    final icon = isCharge ? Icons.trending_up : Icons.local_offer;
    final text = isCharge ? 'de recargo' : 'de descuento';
    final prefix = isCharge ? '+' : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  isCharge ? 'Información de Recargo' : 'Información de Descuento',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '$prefix${_promotion.valorDescuento}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    text,
                    style: TextStyle(fontSize: 16, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeCard() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();
    final daysRemaining = _promotion.fechaFin?.difference(now).inDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Período de Vigencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDateInfo(
              'Fecha de Inicio',
              _promotion.fechaInicio,
              dateFormat,
            ),
            const SizedBox(height: 8),
            _buildDateInfo('Fecha de Fin', _promotion.fechaFin, dateFormat),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    _promotion.fechaFin == null
                        ? AppColors.neutral
                        : (daysRemaining != null && daysRemaining >= 0
                            ? AppColors.active
                            : AppColors.expired),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _promotion.fechaFin == null
                        ? Icons.all_inclusive
                        : (daysRemaining != null && daysRemaining >= 0
                            ? Icons.check_circle
                            : Icons.warning),
                    color:
                        _promotion.fechaFin == null
                            ? AppColors.neutral
                            : (daysRemaining != null && daysRemaining >= 0
                                ? AppColors.active
                                : AppColors.expired),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _promotion.fechaFin == null
                          ? 'Esta promoción no tiene fecha de vencimiento'
                          : (daysRemaining != null && daysRemaining >= 0
                              ? 'Faltan $daysRemaining días para que expire'
                              : 'Esta promoción ha expirado hace ${daysRemaining?.abs()} días'),
                      style: TextStyle(
                        color:
                            _promotion.fechaFin == null
                                ? AppColors.neutral
                                : (daysRemaining != null && daysRemaining >= 0
                                    ? AppColors.active
                                    : AppColors.expired),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageCard() {
    final usagePercentage =
        _promotion.limiteUsos != null && _promotion.limiteUsos! > 0
            ? ((_promotion.usosActuales ?? 0) / _promotion.limiteUsos!) * 100
            : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Estadísticas de Uso',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildUsageStatCard(
                    'Usos Actuales',
                    _promotion.usosActuales.toString(),
                    Icons.shopping_cart,
                    AppColors.usage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildUsageStatCard(
                    'Límite de Usos',
                    _promotion.limiteUsos?.toString() ?? 'Ilimitado',
                    Icons.flag,
                    AppColors.limit,
                  ),
                ),
              ],
            ),
            if (_promotion.limiteUsos != null) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Progreso de uso'),
                      Text('${usagePercentage.toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: usagePercentage / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usagePercentage > 80 ? AppColors.warning : AppColors.usage,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUsageStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsCard() {
    final isCharge = _promotion.isChargePromotion;
    final color = isCharge ? AppColors.promotionCharge : AppColors.promotionDiscount;
    final icon = isCharge ? Icons.trending_up : Icons.inventory;
    final title = isCharge ? 'Productos con Recargo' : 'Productos con Descuento';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Warning banner for surcharge promotions
            if (isCharge) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.promotionChargeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.promotionCharge.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: AppColors.promotionCharge, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Los siguientes productos tendrán un aumento en su precio de venta',
                        style: TextStyle(
                          color: AppColors.promotionCharge,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Information about promotion scope
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _promotion.aplicaTodo 
                          ? 'Esta promoción aplica a todos los productos de la tienda'
                          : 'Esta promoción aplica solo a productos específicos',
                      style: TextStyle(
                        color: color.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Products list
            if (_isLoadingProducts)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_promotionProducts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, 
                         color: Colors.grey[400], size: 32),
                    const SizedBox(height: 8),
                    Text(
                      _promotion.aplicaTodo 
                          ? 'No se pudieron cargar los productos de la tienda'
                          : 'No hay productos específicos asignados a esta promoción',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  // Header with product count
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory, color: Colors.grey[600], size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _promotion.aplicaTodo
                              ? 'Productos en la tienda: ${_promotionProducts.length}'
                              : 'Productos afectados: ${_promotionProducts.length}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Products list - show only affected products
                  ...(_promotionProducts.take(10).map(
                    (product) => _buildProductItemFromCache(product, isCharge, color),
                  )),
                  
                  // Show more indicator if there are more products
                  if (_promotionProducts.length > 10)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.more_horiz, color: color, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Y ${_promotionProducts.length - 10} productos más...',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItemFromCache(Product product, bool isCharge, Color color) {
    final double basePrice = product.basePrice;
    print('DEBUG: Product ${product.name} - basePrice: $basePrice, id: ${product.id}');
    final double promotionalPrice = _calculatePromotionalPrice(basePrice);
    final double priceDifference = _calculatePriceDifference(basePrice, promotionalPrice);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'Producto',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Producto',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isCharge ? Icons.trending_up : Icons.local_offer,
                color: color,
                size: 20,
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          _buildPriceInfoFromProduct(product, isCharge, color),
          
          // Add "Create Special Promotion" button for individual products
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _createSpecialPromotion(product),
              icon: Icon(Icons.add_circle_outline, size: 16, color: color),
              label: Text(
                'Crear Promoción Especial',
                style: TextStyle(fontSize: 12, color: color),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInfoFromProduct(Product product, bool isCharge, Color color) {
    final double basePrice = product.basePrice;
    print('DEBUG: PriceInfo - Product ${product.name} - basePrice: $basePrice');
    final double promotionalPrice = _calculatePromotionalPrice(basePrice);
    final double priceDifference = _calculatePriceDifference(basePrice, promotionalPrice);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Product info header
          Row(
            children: [
              Icon(Icons.inventory_2, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'SKU: ${product.sku.isNotEmpty ? product.sku : "N/A"}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (product.tieneStock)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Stock: ${product.stockDisponible}',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Base price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Precio base:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
              Text(
                '\$${NumberFormat('#,###.00').format(basePrice)}',
                style: TextStyle(
                  fontSize: 13,
                  decoration: isCharge ? TextDecoration.lineThrough : null,
                  color: isCharge ? Colors.grey[500] : Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          
          // Promotional price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isCharge ? 'Precio con recargo:' : 'Precio con descuento:',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '\$${NumberFormat('#,###.00').format(promotionalPrice)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          
          // Price difference
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCharge ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  '${isCharge ? "Aumento" : "Ahorro"}: \$${NumberFormat('#,###.00').format(priceDifference.abs())}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${_promotion.valorDescuento.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _calculatePromotionalPrice(double basePrice) {
    if (_promotion.isChargePromotion) {
      // For surcharges, add the percentage to the base price
      return basePrice * (1 + (_promotion.valorDescuento / 100));
    } else {
      // For discounts, subtract the percentage from the base price
      return basePrice * (1 - (_promotion.valorDescuento / 100));
    }
  }

  double _calculatePriceDifference(double basePrice, double promotionalPrice) {
    return promotionalPrice - basePrice;
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
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateInfo(String label, DateTime? date, DateFormat dateFormat) {
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
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              date != null ? dateFormat.format(date) : 'No especificado',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit() async {
    try {
      // Load fresh promotion types for editing
      final promotionTypes = await _promotionService.getPromotionTypes();
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PromotionFormScreen(
              promotion: _promotion,
              promotionTypes: promotionTypes,
            ),
          ),
        ).then((result) {
          if (result == true) {
            _refreshPromotion();
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error al cargar datos del formulario: $e');
    }
  }
}
