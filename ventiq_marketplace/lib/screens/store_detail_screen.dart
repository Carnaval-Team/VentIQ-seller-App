import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/product_list_card.dart';
import '../widgets/carnaval_fab.dart';
import 'product_detail_screen.dart';
import '../services/marketplace_service.dart';
import '../services/rating_service.dart';
import '../widgets/rating_input_dialog.dart';
import 'map_screen.dart';

/// Pantalla de detalles de la tienda
class StoreDetailScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreDetailScreen({super.key, required this.store});

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  final MarketplaceService _marketplaceService = MarketplaceService();
  final RatingService _ratingService = RatingService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _storeProducts = [];
  List<Map<String, dynamic>> _tpvs = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingTPVs = true;

  // Paginación
  final int _pageSize = 20;
  int _currentOffset = 0;
  bool _hasMoreProducts = true;

  @override
  void initState() {
    super.initState();
    _loadStoreProducts();
    _loadTPVsStatus();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Carga los productos de la tienda con paginación
  Future<void> _loadStoreProducts({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentOffset = 0;
        _storeProducts = [];
        _hasMoreProducts = true;
      });
    }

    if (!_hasMoreProducts && !reset) return;

    try {
      // Obtener ID de la tienda
      final storeId = widget.store['id'] as int?;

      if (storeId == null) {
        print('❌ Error: ID de tienda no disponible');
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      print('📍 Cargando productos de tienda ID: $storeId');

      final newProducts = await _marketplaceService.getProducts(
        idTienda: storeId,
        idCategoria: null,
        soloDisponibles: true,
        searchQuery: null,
        limit: _pageSize,
        offset: _currentOffset,
      );

      setState(() {
        if (reset) {
          _storeProducts = newProducts;
        } else {
          _storeProducts.addAll(newProducts);
        }

        _currentOffset += newProducts.length;
        _hasMoreProducts = newProducts.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      print('❌ Error cargando productos de la tienda: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Maneja el scroll para cargar más productos
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMoreProducts) {
        setState(() => _isLoadingMore = true);
        _loadStoreProducts();
      }
    }
  }

  /// Carga el estado de los TPVs de la tienda
  Future<void> _loadTPVsStatus() async {
    try {
      final storeId = widget.store['id'] as int?;

      if (storeId == null) {
        print('❌ Error: ID de tienda no disponible para TPVs');
        setState(() {
          _isLoadingTPVs = false;
        });
        return;
      }

      print('🏪 Cargando estado de TPVs de tienda ID: $storeId');

      final tpvs = await _marketplaceService.getStoreTPVsStatus(storeId);

      setState(() {
        _tpvs = tpvs;
        _isLoadingTPVs = false;
      });
    } catch (e) {
      print('❌ Error cargando estado de TPVs: $e');
      setState(() {
        _isLoadingTPVs = false;
      });
    }
  }

  /// Refresca los productos y TPVs
  Future<void> _refreshProducts() async {
    await Future.wait([_loadStoreProducts(reset: true), _loadTPVsStatus()]);
  }

  /// Verifica si la tienda tiene al menos un TPV abierto
  bool _isStoreOpen() {
    if (_isLoadingTPVs || _tpvs.isEmpty) {
      return false;
    }

    return _tpvs.any((tpv) => tpv['esta_abierto'] == true);
  }

  /// Obtiene el número de TPVs abiertos
  int _getOpenTPVsCount() {
    if (_isLoadingTPVs || _tpvs.isEmpty) {
      return 0;
    }

    return _tpvs.where((tpv) => tpv['esta_abierto'] == true).length;
  }

  void _openProductDetails(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: product),
      ),
    );
  }

  void _openMap() {
    final ubicacion = widget.store['ubicacion'] as String?;
    if (ubicacion == null || !ubicacion.contains(',')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación no disponible en el mapa'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          stores: [
            widget.store,
          ], // Pass only this store, or fetch all if needed context
          initialStore: widget.store,
        ),
      ),
    );
  }

  Future<void> _showRatingDialog({
    required String title,
    required Function(double, String?) onSubmit,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => RatingInputDialog(title: title, onSubmit: onSubmit),
    );
  }

  void _rateStore() {
    final storeId = widget.store['id'] as int?;
    if (storeId == null) return;

    _showRatingDialog(
      title: 'Calificar Tienda',
      onSubmit: (rating, comment) async {
        await _ratingService.submitStoreRating(
          storeId: storeId,
          rating: rating,
          comentario: comment,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Gracias por calificar la tienda!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: const CarnavalFab(),
      body: RefreshIndicator(
        onRefresh: _refreshProducts,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // AppBar con imagen de fondo
            _buildSliverAppBar(),

            // Contenido
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información de la tienda
                  _buildStoreInfo(),

                  const Divider(height: 1, thickness: 1),

                  // Sección de productos
                  _buildProductsSection(),
                ],
              ),
            ),

            // Lista de productos
            _isLoading
                ? SliverToBoxAdapter(child: _buildLoadingState())
                : _storeProducts.isEmpty
                ? SliverToBoxAdapter(child: _buildEmptyState())
                : _buildProductsList(),

            // Indicador de carga al final
            if (_isLoadingMore)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(AppTheme.paddingM),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.star_rate_rounded, color: Colors.white),
          tooltip: 'Calificar Tienda',
          onPressed: _rateStore,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
        title: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Text(
                widget.store['nombre'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen de fondo o gradiente
            widget.store['logoUrl'] != null
                ? Image.network(
                    widget.store['logoUrl'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildGradientBackground();
                    },
                  )
                : _buildGradientBackground(),

            // Overlay oscuro para mejor contraste
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.7),
            AppTheme.accentColor.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.store,
          size: 100,
          color: Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildStoreInfo() {
    final isOpen = _isStoreOpen();

    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Estado (Abierto/Cerrado)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isOpen
                      ? AppTheme.successColor.withOpacity(0.1)
                      : AppTheme.errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOpen ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: isOpen
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOpen ? 'Abierto ahora' : 'Cerrado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isOpen
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!_isLoadingTPVs)
                Text(
                  '${_getOpenTPVsCount()} de ${_tpvs.length} TPVs abiertos',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.paddingM),

          // Ubicación
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            title: 'Ubicación',
            content: '${widget.store['ubicacion']}',
            onTap: _openMap,
          ),
          const SizedBox(height: 12),

          // Dirección
          if (widget.store['direccion'] != null)
            _buildInfoRow(
              icon: Icons.home_outlined,
              title: 'Dirección',
              content: widget.store['direccion'],
            ),
          const SizedBox(height: 12),

          // Total de productos
          _buildInfoRow(
            icon: Icons.inventory_2_outlined,
            title: 'Productos disponibles',
            content: '${widget.store['productCount']} productos',
          ),
          const SizedBox(height: AppTheme.paddingM),

          // Sección de TPVs
          // if (!_isLoadingTPVs && _tpvs.isNotEmpty) _buildTPVsSection(),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String content,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  Widget _buildProductsSection() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: AppTheme.backgroundColor,
      child: Row(
        children: [
          const Text(
            'Productos de esta tienda',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          if (!_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.store['productCount']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingXL),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppTheme.paddingM),
            Text(
              'Cargando productos...',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingXL),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: AppTheme.paddingM),
            const Text(
              'Esta tienda no tiene productos disponibles',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTPVsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Puntos de Venta (TPVs)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._tpvs.map((tpv) => _buildTPVCard(tpv)),
      ],
    );
  }

  Widget _buildTPVCard(Map<String, dynamic> tpv) {
    final isOpen = tpv['esta_abierto'] as bool? ?? false;
    final tpvName = tpv['denominacion_tpv'] as String? ?? 'TPV';
    final fechaApertura = tpv['fecha_apertura'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOpen
            ? AppTheme.successColor.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOpen
              ? AppTheme.successColor.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Icono de estado
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOpen
                  ? AppTheme.successColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isOpen ? Icons.check_circle : Icons.cancel,
              size: 20,
              color: isOpen ? AppTheme.successColor : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),

          // Información del TPV
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tpvName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (fechaApertura != null && isOpen) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Abierto desde ${_formatTime(fechaApertura)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Badge de estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOpen ? AppTheme.successColor : Colors.grey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isOpen ? 'Abierto' : 'Cerrado',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (e) {
      return dateTimeStr;
    }
  }

  Widget _buildProductsList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final product = _storeProducts[index];
        final metadata = product['metadata'] as Map<String, dynamic>?;

        // Extraer presentaciones del metadata
        final presentacionesData =
            metadata?['presentaciones'] as List<dynamic>?;
        final presentaciones =
            presentacionesData?.map((p) {
              final presentacion = p as Map<String, dynamic>;
              final denominacion =
                  presentacion['denominacion'] as String? ?? '';
              final cantidad = presentacion['cantidad'] ?? 1;
              final esBase = presentacion['es_base'] as bool? ?? false;

              // Formato: "Unidad" o "Caja x24" con indicador de base
              if (cantidad == 1) {
                return esBase ? '$denominacion ⭐' : denominacion;
              } else {
                return esBase
                    ? '$denominacion x$cantidad ⭐'
                    : '$denominacion x$cantidad';
              }
            }).toList() ??
            [];

        return ProductListCard(
          productName: product['denominacion'] ?? 'Sin nombre',
          price: (product['precio_venta'] ?? 0).toDouble(),
          imageUrl: product['imagen'],
          storeName: metadata?['denominacion_tienda'] ?? 'Sin tienda',
          availableStock: (product['stock_disponible'] ?? 0).toInt(),
          rating: (metadata?['rating_promedio'] ?? 0.0).toDouble(),
          presentations: presentaciones,
          onTap: () => _openProductDetails(product),
        );
      }, childCount: _storeProducts.length),
    );
  }
}
