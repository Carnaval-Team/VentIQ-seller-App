import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/store_list_card.dart';
import 'store_detail_screen.dart';
import '../services/store_service.dart';

/// Pantalla de tiendas
class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final TextEditingController _searchController = TextEditingController();
  final StoreService _storeService = StoreService();
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
        _errorMessage = 'Error al cargar las tiendas. Por favor, intenta de nuevo.';
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
          print('🔍 Búsqueda limpiada - Mostrando todas las ${_stores.length} tiendas');
        } else {
          final searchLower = query.toLowerCase().trim();
          
          _filteredStores = _stores.where((store) {
            // Campos a buscar
            final nombre = (store['nombre'] ?? '').toString().toLowerCase();
            final ubicacion = (store['ubicacion'] ?? '').toString().toLowerCase();
            final direccion = (store['direccion'] ?? '').toString().toLowerCase();
            final descripcion = (store['descripcion'] ?? '').toString().toLowerCase();
            
            // Buscar en todos los campos
            return nombre.contains(searchLower) ||
                   ubicacion.contains(searchLower) ||
                   direccion.contains(searchLower) ||
                   descripcion.contains(searchLower);
          }).toList();
          
          print('🔍 Búsqueda: "$query" - ${_filteredStores.length} tiendas encontradas de ${_stores.length} totales');
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
            'provincia': store['provincia']??'', // TODO: Agregar a la función RPC
            'municipio': store['municipio']??'', // TODO: Agregar a la función RPC
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
      appBar: AppBar(
        title: const Text('Tiendas'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStores,
        child: Column(
          children: [
            // Barra de búsqueda
            _buildSearchBar(),
            
            // Contador de resultados
            if (!_isLoading && _errorMessage == null) _buildResultsCounter(),
            
            // Lista de tiendas
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _filteredStores.isEmpty
                          ? _buildEmptyState()
                          : _buildStoresList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: _filterStores,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, ubicación o dirección...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterStores('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.backgroundColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.paddingM,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCounter() {
    final isFiltering = _searchController.text.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: AppTheme.paddingS,
      ),
      color: AppTheme.backgroundColor,
      child: Row(
        children: [
          if (isFiltering)
            const Icon(
              Icons.filter_list,
              size: 18,
              color: AppTheme.primaryColor,
            ),
          if (isFiltering) const SizedBox(width: 8),
          Text(
            isFiltering
                ? '${_filteredStores.length} de ${_stores.length} ${_filteredStores.length == 1 ? 'tienda' : 'tiendas'}'
                : '${_filteredStores.length} ${_filteredStores.length == 1 ? 'tienda encontrada' : 'tiendas encontradas'}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isFiltering ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: AppTheme.paddingM),
          Text(
            'Cargando tiendas...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
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
            Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red[400],
            ),
            const SizedBox(height: AppTheme.paddingM),
            Text(
              _errorMessage ?? 'Error desconocido',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
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
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppTheme.paddingS,
        bottom: AppTheme.paddingL,
      ),
      itemCount: _filteredStores.length,
      itemBuilder: (context, index) {
        final store = _filteredStores[index];
        return StoreListCard(
          storeName: store['nombre'] as String? ?? 'Tienda',
          logoUrl: store['imagen_url'] as String?,
          ubicacion: store['ubicacion'] as String? ?? 'Sin ubicación',
          provincia: 'Santo Domingo', // TODO: Agregar a la función RPC
          municipio: 'Santo Domingo Este', // TODO: Agregar a la función RPC
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
      },
    );
  }
}
