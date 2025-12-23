import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/store_list_card.dart';
import 'store_detail_screen.dart';
import '../services/store_service.dart';
import '../services/rating_service.dart';
import '../widgets/rating_input_dialog.dart';

/// Pantalla de tiendas
class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final TextEditingController _searchController = TextEditingController();
  final StoreService _storeService = StoreService();
  final RatingService _ratingService = RatingService();
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _filteredStores = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Cargar tiendas desde Supabase usando RPC
  Future<void> _loadStores() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('🔍 Cargando todas las tiendas desde Supabase...');

      // Llamar a la función RPC con límite de 9999 para traer todas las tiendas
      final stores = await _storeService.getFeaturedStores(limit: 9999);

      print('✅ ${stores.length} tiendas cargadas desde Supabase');

      setState(() {
        _stores = stores;
        _filteredStores = stores;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando tiendas: $e');
      setState(() {
        _errorMessage =
            'Error al cargar las tiendas. Por favor, intenta de nuevo.';
        _isLoading = false;
      });
    }
  }

  /// Filtrar tiendas por búsqueda interna con debounce
  /// Busca en: nombre, ubicación, dirección y descripción
  void _filterStores(String query) {
    // Cancelar el timer anterior si existe
    _debounceTimer?.cancel();

    // Crear nuevo timer con delay de 300ms
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        if (query.isEmpty) {
          _filteredStores = _stores;
          print(
            '🔍 Búsqueda limpiada - Mostrando todas las ${_stores.length} tiendas',
          );
        } else {
          final searchLower = query.toLowerCase().trim();

          _filteredStores = _stores.where((store) {
            // Campos a buscar
            final nombre = (store['nombre'] ?? '').toString().toLowerCase();
            final ubicacion = (store['ubicacion'] ?? '')
                .toString()
                .toLowerCase();
            final direccion = (store['direccion'] ?? '')
                .toString()
                .toLowerCase();
            final descripcion = (store['descripcion'] ?? '')
                .toString()
                .toLowerCase();

            // Buscar en todos los campos
            return nombre.contains(searchLower) ||
                ubicacion.contains(searchLower) ||
                direccion.contains(searchLower) ||
                descripcion.contains(searchLower);
          }).toList();

          print(
            '🔍 Búsqueda: "$query" - ${_filteredStores.length} tiendas encontradas de ${_stores.length} totales',
          );
        }
      });
    });
  }

  /// Abrir ubicación de la tienda en el mapa
  void _openMap(double? latitude, double? longitude, String storeName) {
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación no disponible para esta tienda'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // TODO: Implementar apertura de mapa con coordenadas reales
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Abrir mapa para: $storeName'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  /// Abrir detalles de la tienda
  Future<void> _showRatingDialog({
    required String title,
    required Function(double, String?) onSubmit,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => RatingInputDialog(title: title, onSubmit: onSubmit),
    );
  }

  void _rateApp() {
    _showRatingDialog(
      title: 'Calificar Aplicación',
      onSubmit: (rating, comment) async {
        await _ratingService.submitAppRating(
          rating: rating,
          comentario: comment,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Gracias por calificar la app!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      },
    );
  }

  void _openStoreDetails(Map<String, dynamic> store) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoreDetailScreen(
          store: {
            'id': store['id_tienda'],
            'nombre': store['nombre'],
            'logoUrl': store['imagen_url'],
            'ubicacion': store['ubicacion'] ?? 'Sin ubicación',
            'provincia':
                store['provincia'] ?? '', // TODO: Agregar a la función RPC
            'municipio':
                store['municipio'] ?? '', // TODO: Agregar a la función RPC
            'direccion': store['direccion'] ?? 'Sin dirección',
            'productCount': (store['total_productos'] as num?)?.toInt() ?? 0,
            'latitude': null, // TODO: Agregar coordenadas a la función RPC
            'longitude': null, // TODO: Agregar coordenadas a la función RPC
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadStores,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // AppBar moderno con gradiente
            _buildModernAppBar(),

            // Barra de búsqueda
            SliverToBoxAdapter(child: _buildSearchSection()),

            // Contador de resultados
            if (!_isLoading && _errorMessage == null)
              SliverToBoxAdapter(child: _buildResultsCounter()),

            // Contenido principal
            _isLoading
                ? SliverToBoxAdapter(child: _buildLoadingState())
                : _errorMessage != null
                ? SliverToBoxAdapter(child: _buildErrorState())
                : _filteredStores.isEmpty
                ? SliverToBoxAdapter(child: _buildEmptyState())
                : _buildStoresList(),
          ],
        ),
      ),
    );
  }

  /// AppBar moderno con SliverAppBar
  Widget _buildModernAppBar() {
    return SliverAppBar(
      expandedHeight: 140.0,
      floating: false,
      pinned: true,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor,
                AppTheme.primaryColor.withOpacity(0.85),
                AppTheme.secondaryColor.withOpacity(0.9),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.paddingM,
                vertical: AppTheme.paddingS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.warningColor.withOpacity(0.3),
                              AppTheme.warningColor.withOpacity(0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.store_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tiendas',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Descubre las mejores tiendas',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.thumb_up_alt_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          tooltip: 'Calificar App',
                          onPressed: _rateApp,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sección del buscador mejorada
  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterStores,
          decoration: InputDecoration(
            hintText: 'Buscar tiendas...',
            hintStyle: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.6),
              fontSize: 15,
            ),
            prefixIcon: Container(
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.search_rounded,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _filterStores('');
                    },
                  )
                : null,
            filled: false,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCounter() {
    final isFiltering = _searchController.text.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isFiltering
                ? AppTheme.primaryColor.withOpacity(0.08)
                : AppTheme.secondaryColor.withOpacity(0.06),
            isFiltering
                ? AppTheme.primaryColor.withOpacity(0.04)
                : AppTheme.secondaryColor.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFiltering
              ? AppTheme.primaryColor.withOpacity(0.2)
              : Colors.grey.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isFiltering
                  ? AppTheme.primaryColor.withOpacity(0.15)
                  : AppTheme.secondaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isFiltering ? Icons.filter_list_rounded : Icons.store_rounded,
              size: 18,
              color: isFiltering
                  ? AppTheme.primaryColor
                  : AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isFiltering
                  ? '${_filteredStores.length} de ${_stores.length} ${_filteredStores.length == 1 ? 'tienda' : 'tiendas'}'
                  : '${_filteredStores.length} ${_filteredStores.length == 1 ? 'tienda disponible' : 'tiendas disponibles'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isFiltering
                    ? AppTheme.primaryColor
                    : AppTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.1),
                    AppTheme.secondaryColor.withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cargando tiendas...',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Descubriendo las mejores opciones',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltering = _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.paddingL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFiltering ? Icons.search_off : Icons.store_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: AppTheme.paddingM),
            Text(
              isFiltering
                  ? 'No se encontraron tiendas'
                  : 'No hay tiendas disponibles',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.paddingS),
            Text(
              isFiltering
                  ? 'Intenta con otros términos de búsqueda'
                  : 'Aún no hay tiendas registradas en el marketplace',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            if (isFiltering) ...[
              const SizedBox(height: AppTheme.paddingL),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _filterStores('');
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpiar búsqueda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.paddingL,
                    vertical: AppTheme.paddingM,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Estado de error
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.paddingL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
            const SizedBox(height: AppTheme.paddingM),
            Text(
              _errorMessage ?? 'Error desconocido',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: AppTheme.paddingL),
            ElevatedButton.icon(
              onPressed: _loadStores,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.paddingL,
                  vertical: AppTheme.paddingM,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lista de tiendas
  Widget _buildStoresList() {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 8, bottom: AppTheme.paddingXL),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final store = _filteredStores[index];
          return StoreListCard(
            storeName: store['nombre'] as String? ?? 'Tienda',
            logoUrl: store['imagen_url'] as String?,
            ubicacion: store['ubicacion'] as String? ?? 'Sin ubicación',
            provincia: '', // TODO: Agregar a la función RPC
            municipio: '', // TODO: Agregar a la función RPC
            direccion: store['direccion'] as String? ?? 'Sin dirección',
            productCount: (store['total_productos'] as num?)?.toInt() ?? 0,
            latitude: null, // TODO: Agregar coordenadas a la función RPC
            longitude: null, // TODO: Agregar coordenadas a la función RPC
            onTap: () => _openStoreDetails(store),
            onMapTap: () => _openMap(
              null, // TODO: Agregar coordenadas a la función RPC
              null, // TODO: Agregar coordenadas a la función RPC
              store['nombre'] as String? ?? 'Tienda',
            ),
          );
        }, childCount: _filteredStores.length),
      ),
    );
  }
}
