import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/global_config_tab_view.dart';
import '../widgets/categories_tab_view.dart';
import '../widgets/variants_tab_view.dart';
import '../widgets/presentations_tab_view.dart';
import '../widgets/units_tab_view.dart';
import '../widgets/carnaval_tab_view.dart';
import '../services/store_data_service.dart';
import '../services/store_service.dart';
import '../services/catalogo_service.dart';
import '../utils/screen_protection_mixin.dart';
import 'store_data_management_screen.dart';
import 'catalogo_productos_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin, ScreenProtectionMixin {
  @override
  String get protectedRoute => '/settings';
  late TabController _tabController;
  final GlobalKey<State<GlobalConfigTabView>> _globalConfigTabKey =
      GlobalKey<State<GlobalConfigTabView>>();
  final GlobalKey<State<CategoriesTabView>> _categoriesTabKey =
      GlobalKey<State<CategoriesTabView>>();
  final GlobalKey<State<VariantsTabView>> _variantsTabKey =
      GlobalKey<State<VariantsTabView>>();
  final GlobalKey<State<PresentationsTabView>> _presentationsTabKey =
      GlobalKey<State<PresentationsTabView>>();
  final GlobalKey<State<UnitsTabView>> _unitsTabKey =
      GlobalKey<State<UnitsTabView>>();
  final GlobalKey<State<CarnavalTabView>> _carnavalTabKey =
      GlobalKey<State<CarnavalTabView>>();
  
  final StoreDataService _storeDataService = StoreDataService();
  final CatalogoService _catalogoService = CatalogoService();
  Map<String, dynamic>? _storeData;
  bool _loadingStoreData = true;
  int? _storeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Verificar permisos antes de mostrar contenido
    if (isCheckingPermissions) {
      return buildPermissionLoadingWidget();
    }

    if (!hasAccess) {
      return buildAccessDeniedWidget();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Global', icon: Icon(Icons.settings_applications)),
            Tab(text: 'Tienda', icon: Icon(Icons.store)),
            Tab(text: 'Categorías', icon: Icon(Icons.category)),
            Tab(text: 'Variantes', icon: Icon(Icons.format_shapes)),
            Tab(text: 'Presentaciones', icon: Icon(Icons.format_paint)),
            Tab(text: 'Unidades', icon: Icon(Icons.straighten)),
            Tab(text: 'Carnaval App', icon: Icon(Icons.storefront)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GlobalConfigTabView(key: _globalConfigTabKey),
          _buildStoreDataTab(),
          CategoriesTabView(key: _categoriesTabKey),
          VariantsTabView(key: _variantsTabKey),
          PresentationsTabView(key: _presentationsTabKey),
          UnitsTabView(key: _unitsTabKey),
          CarnavalTabView(key: _carnavalTabKey),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentRoute: '/settings',
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          // Ocultar FAB en la pestaña de Carnaval (índice 5)
          // También se puede ocultar en Global (índice 0) si se desea
          final isHidden = _tabController.index == 5;
          return isHidden
              ? const SizedBox.shrink()
              : FloatingActionButton(
                onPressed: _showAddDialog,
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
              );
        },
      ),
    );
  }

  Widget _buildStoreDataTab() {
    // Si no tenemos ID de tienda, intentar obtenerlo
    if (_storeId == null) {
      return FutureBuilder<int?>(
        future: _getStoreIdFromContext(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No se pudo obtener la información de la tienda',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _storeId = null;
                        _storeData = null;
                      });
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          _storeId = snapshot.data;
          return _buildStoreDataContent();
        },
      );
    }

    return _buildStoreDataContent();
  }

  Future<int?> _getStoreIdFromContext() async {
    try {
      // Obtener el ID de tienda guardado en las preferencias locales
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId != null) {
        _storeId = storeId;
        // Cargar datos de la tienda
        final storeData = await _storeDataService.getStoreData(storeId);
        if (mounted) {
          setState(() {
            _storeData = storeData;
            _loadingStoreData = false;
          });
        }
      }
      return storeId;
    } catch (e) {
      print('Error obteniendo ID de tienda: $e');
      if (mounted) {
        setState(() => _loadingStoreData = false);
      }
      return null;
    }
  }

  Widget _buildStoreDataContent() {
    if (_loadingStoreData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_storeData == null || _storeId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar la información de la tienda',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Información básica
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información de la Tienda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'Nombre',
                    _storeData!['denominacion'] ?? 'No especificado',
                    Icons.store,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    'Dirección',
                    _storeData!['direccion'] ?? 'No especificada',
                    Icons.location_on,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    'Teléfono',
                    _storeData!['phone'] ?? 'No especificado',
                    Icons.phone,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ubicación geográfica
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ubicación Geográfica',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'País',
                    _storeData!['nombre_pais'] ?? 'No especificado',
                    Icons.public,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    'Provincia/Estado',
                    _storeData!['nombre_estado'] ?? 'No especificado',
                    Icons.location_on,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    'Coordenadas',
                    _storeData!['latitude'] != null && _storeData!['longitude'] != null
                        ? '${_storeData!['latitude']}, ${_storeData!['longitude']}'
                        : 'No especificadas',
                    Icons.map,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Mapa con ubicación
          if (_storeData != null && _storeData!['latitude'] != null && _storeData!['longitude'] != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ubicación en Mapa',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 350,
                        child: _buildMapPreview(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Sección de Catálogo (solo si tiene plan Pro o Avanzado)
          FutureBuilder<bool>(
            future: _catalogoService.tienePlanCatalogo(_storeId!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }

              final tienePlanPro = snapshot.data ?? false;

              if (!tienePlanPro) {
                return Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Catálogo de Productos',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Requiere plan Pro',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
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

              // Si tiene plan Pro, mostrar opciones de catálogo
              return Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Publicar en Catálogo',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              FutureBuilder<bool>(
                                future: _catalogoService.obtenerMostrarEnCatalogoTienda(_storeId!),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  }

                                  final mostrar = snapshot.data ?? false;
                                  return Switch(
                                    value: mostrar,
                                    onChanged: (value) async {
                                      await _catalogoService.actualizarMostrarEnCatalogoTienda(_storeId!, value);
                                      if (mounted) {
                                        setState(() {});
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              value
                                                  ? '✅ Catálogo habilitado'
                                                  : '✅ Catálogo deshabilitado',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    activeColor: Colors.green,
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Publica tus productos en el catálogo de VentIQ para que otros clientes puedan verlos y comprarlos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<bool>(
                    future: _catalogoService.obtenerMostrarEnCatalogoTienda(_storeId!),
                    builder: (context, snapshot) {
                      final mostrarEnCatalogo = snapshot.data ?? false;
                      
                      if (!mostrarEnCatalogo) {
                        return const SizedBox.shrink();
                      }
                      
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const CatalogoProductosScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.storefront),
                          label: const Text('Gestionar Productos en Catálogo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Botón editar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => StoreDataManagementScreen(
                      storeId: _storeId!,
                    ),
                  ),
                ).then((_) {
                  // Recargar datos después de volver
                  if (mounted) {
                    setState(() {
                      _storeData = null;
                      _loadingStoreData = true;
                    });
                    _getStoreIdFromContext();
                  }
                });
              },
              icon: const Icon(Icons.edit),
              label: const Text('Editar Información de la Tienda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    final lat = (_storeData?['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (_storeData?['longitude'] as num?)?.toDouble() ?? 0.0;

    return FlutterMap(
      options: MapOptions(
        center: LatLng(lat, lng),
        zoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 40,
              height: 40,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddDialog() {
    final currentTab = _tabController.index;
    switch (currentTab) {
      case 0:
        // Tab Tienda - no tiene funcionalidad de agregar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Usa el botón "Gestionar Información de la Tienda" para editar',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 1:
        // Tab Global - no tiene funcionalidad de agregar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La configuración global no permite agregar elementos',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 2:
        _showAddCategoryDialog();
        break;
      case 3:
        (_variantsTabKey.currentState as dynamic)?.showAddVariantDialog();
        break;
      case 4:
        (_presentationsTabKey.currentState as dynamic)
            ?.showAddPresentationDialog();
        break;
      case 5:
        (_unitsTabKey.currentState as dynamic)?.showAddDialog();
        break;
      case 6:
        // Tab Carnaval - no tiene funcionalidad de agregar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La configuración de Carnaval no permite agregar elementos',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        break;
    }
  }

  void _showAddCategoryDialog() {
    // Llamar directamente al método del CategoriesTabView usando la key
    (_categoriesTabKey.currentState as dynamic)?.showAddCategoryDialog();
  }

  void _onBottomNavTap(int index) {
    // El AdminBottomNavigation ya maneja la navegación automáticamente
    // Esta función se mantiene por compatibilidad pero no es necesaria
    // ya que AdminBottomNavigation usa _handleTap internamente
  }
}
