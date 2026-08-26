import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/global_config_tab_view.dart';
import '../widgets/categories_tab_view.dart';
import '../widgets/variants_tab_view.dart';
import '../widgets/presentations_tab_view.dart';
import '../widgets/units_tab_view.dart';
import '../widgets/carnaval_tab_view.dart';
import '../widgets/price_management_tab_view.dart';
import '../widgets/personal_rates_tab_view.dart';
import '../widgets/carnaval_prices_tab_view.dart';
import '../widgets/margins_tab_view.dart';
import '../services/store_data_service.dart';
import '../services/store_service.dart';
import '../services/catalogo_service.dart';
import '../services/warehouse_service.dart';
import '../services/permissions_service.dart';
import '../models/warehouse.dart';
import '../utils/screen_protection_mixin.dart';
import '../utils/navigation_guard.dart';
import 'store_data_management_screen.dart';
import 'catalogo_productos_screen.dart';

/// Ancho máximo del contenido para la vista web (evita cards gigantes).
const double _kMaxContentWidth = 1200.0;

/// Versión web de [SettingsScreen]. Mantiene exactamente la misma lógica y
/// funcionalidad, aplicando un layout más estético y aprovechando el ancho de
/// la pantalla en escritorio.
class SettingsWebScreen extends StatefulWidget {
  const SettingsWebScreen({super.key});

  @override
  State<SettingsWebScreen> createState() => _SettingsWebScreenState();
}

class _SettingsWebScreenState extends State<SettingsWebScreen>
    with SingleTickerProviderStateMixin, ScreenProtectionMixin {
  @override
  String get protectedRoute => '/settings';
  TabController? _tabController;
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
  final WarehouseService _warehouseService = WarehouseService();
  final PermissionsService _permissionsService = PermissionsService();
  Map<String, dynamic>? _storeData;
  bool _loadingStoreData = true;
  int? _storeId;
  bool _canEditSettings = false;
  bool _isSupervisor = false;
  bool _tabsReady = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionsAndTabs();
  }

  Future<void> _loadPermissionsAndTabs() async {
    final results = await Future.wait([
      NavigationGuard.canPerformAction('settings.edit'),
      _permissionsService.getUserRole(),
    ]);
    if (!mounted) return;
    final canEdit = results[0] as bool;
    final role = results[1] as UserRole;
    final isSupervisor = role == UserRole.supervisor;
    // Supervisor: Tienda + Global + Carnaval App. Gerente: todas.
    final tabCount = isSupervisor ? 3 : 11;
    _tabController?.dispose();
    setState(() {
      _canEditSettings = canEdit;
      _isSupervisor = isSupervisor;
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: 0,
      );
      _tabsReady = true;
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (isCheckingPermissions) {
      return buildPermissionLoadingWidget();
    }

    if (!hasAccess) {
      return buildAccessDeniedWidget();
    }

    if (!_tabsReady || _tabController == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = _isSupervisor
        ? const [
            _TabLabel(icon: Icons.store, text: 'Tienda'),
            _TabLabel(icon: Icons.settings_applications, text: 'Global'),
            _TabLabel(icon: Icons.storefront, text: 'Carnaval App'),
          ]
        : const [
            _TabLabel(icon: Icons.store, text: 'Tienda'),
            _TabLabel(icon: Icons.settings_applications, text: 'Global'),
            _TabLabel(icon: Icons.category, text: 'Categorías'),
            _TabLabel(icon: Icons.format_shapes, text: 'Variantes'),
            _TabLabel(icon: Icons.format_paint, text: 'Presentaciones'),
            _TabLabel(icon: Icons.straighten, text: 'Unidades'),
            _TabLabel(icon: Icons.sell, text: 'Precios'),
            _TabLabel(icon: Icons.currency_exchange, text: 'Tasas pers.'),
            _TabLabel(icon: Icons.price_check, text: 'Precios Carnaval'),
            _TabLabel(icon: Icons.storefront, text: 'Carnaval App'),
            _TabLabel(icon: Icons.trending_up, text: 'Márgenes'),
          ];

    final tabViews = _isSupervisor
        ? [
            _buildStoreDataTab(),
            GlobalConfigTabView(key: _globalConfigTabKey, isWeb: true),
            CarnavalTabView(key: _carnavalTabKey),
          ]
        : [
            _buildStoreDataTab(),
            GlobalConfigTabView(key: _globalConfigTabKey, isWeb: true),
            CategoriesTabView(
              key: _categoriesTabKey,
              canEdit: _canEditSettings,
              isWeb: true,
            ),
            VariantsTabView(key: _variantsTabKey),
            PresentationsTabView(key: _presentationsTabKey),
            UnitsTabView(key: _unitsTabKey, isWeb: true),
            PriceManagementTabView(),
            PersonalRatesTabView(canEdit: _canEditSettings),
            const CarnavalPricesTabView(),
            CarnavalTabView(key: _carnavalTabKey),
            const MarginsTabView(),
          ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildWebAppBar(tabs),
      endDrawer: const AdminDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: tabViews,
      ),
      bottomNavigationBar: const AdminBottomNavigation(
        currentRoute: '/settings',
      ),
      floatingActionButton: (!_canEditSettings || _isSupervisor)
          ? null
          : AnimatedBuilder(
              animation: _tabController!,
              builder: (context, child) {
                // Ocultar FAB en pestañas donde no aplica agregar (idéntico a la
                // vista móvil): Unidades(5), Precios(6), Tasas(7),
                // Precios Carnaval(8), Carnaval App(9), Márgenes(10).
                final isHidden = _tabController!.index == 5 ||
                    _tabController!.index == 6 ||
                    _tabController!.index == 7 ||
                    _tabController!.index == 8 ||
                    _tabController!.index == 9 ||
                    _tabController!.index == 10;
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

  PreferredSizeWidget _buildWebAppBar(List<Widget> tabs) {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        'Configuración',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      actions: [
        Builder(
          builder: (context) => _appBarIconBtn(
            Icons.menu,
            'Menú',
            () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          color: AppColors.primary,
          alignment: Alignment.centerLeft,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: tabs
                    .map((t) => Tab(height: 46, child: t))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBarIconBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
    );
  }
  // ===================================================================
  // TIENDA (datos de la tienda) — misma lógica que la vista móvil
  // ===================================================================

  Widget _buildStoreDataTab() {
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
          return _buildStoreDataContentWeb();
        },
      );
    }

    return _buildStoreDataContentWeb();
  }

  Future<int?> _getStoreIdFromContext() async {
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId != null) {
        _storeId = storeId;
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

  Future<void> _handleCatalogToggle(
    bool value,
    int? layoutId, {
    String? successMessage,
  }) async {
    try {
      await _catalogoService.actualizarMostrarEnCatalogoTienda(
        _storeId!,
        value,
        layoutCatalogo: layoutId,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successMessage ??
                  (value ? '✅ Catálogo habilitado' : '✅ Catálogo deshabilitado'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showZoneSelectionDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return _WarehouseZoneSelector(
          storeId: _storeId!,
          warehouseService: _warehouseService,
          onSelected: (layoutId) {
            Navigator.of(context).pop();
            _handleCatalogToggle(true, layoutId);
          },
        );
      },
    );
  }
  Widget _buildStoreDataContentWeb() {
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

    final hasCoords = _storeData!['latitude'] != null &&
        _storeData!['longitude'] != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWebCard(
                title: 'Información de la Tienda',
                icon: Icons.store,
                child: _buildInfoWrap([
                  _InfoData('Nombre',
                      _storeData!['denominacion'] ?? 'No especificado',
                      Icons.store),
                  _InfoData('Teléfono',
                      _storeData!['phone'] ?? 'No especificado', Icons.phone),
                  _InfoData('Dirección',
                      _storeData!['direccion'] ?? 'No especificada',
                      Icons.location_on),
                  _InfoData('País',
                      _storeData!['nombre_pais'] ?? 'No especificado',
                      Icons.public),
                  _InfoData('Provincia/Estado',
                      _storeData!['nombre_estado'] ?? 'No especificada',
                      Icons.map_outlined),
                  _InfoData(
                    'Coordenadas',
                    hasCoords
                        ? '${_storeData!['latitude']}, ${_storeData!['longitude']}'
                        : 'No especificadas',
                    Icons.my_location,
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              _buildWebCard(
                title: 'Horario de Atención',
                icon: Icons.schedule,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDiasTrabajoSelector(),
                    const SizedBox(height: 20),
                    _buildHorariosTrabajoSelector(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (hasCoords) ...[
                _buildWebCard(
                  title: 'Ubicación en Mapa',
                  icon: Icons.map,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(height: 380, child: _buildMapPreview()),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _buildWebCard(
                title: 'Publicar en Catálogo',
                icon: Icons.public,
                trailing: FutureBuilder<bool>(
                  future: _catalogoService
                      .obtenerMostrarEnCatalogoTienda(_storeId!),
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
                        if (value) {
                          _showZoneSelectionDialog();
                        } else {
                          _handleCatalogToggle(false, null);
                        }
                      },
                      activeColor: Colors.green,
                    );
                  },
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Publica tus productos en el catálogo de Inventtia para que otros clientes puedan verlos y comprarlos.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: _catalogoService
                          .obtenerMostrarEnCatalogoTienda(_storeId!),
                      builder: (context, snapshot) {
                        final mostrarEnCatalogo = snapshot.data ?? false;
                        if (!mostrarEnCatalogo) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const CatalogoProductosScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.storefront),
                              label: const Text(
                                  'Gestionar Productos en Catálogo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (context) =>
                                StoreDataManagementScreen(storeId: _storeId!),
                          ),
                        )
                        .then((_) {
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  /// Card contenedora reutilizable con encabezado (icono + título) para la
  /// vista web. Ancho completo dentro del contenedor limitado.
  Widget _buildWebCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  /// Distribuye tiles de información en columnas responsivas para aprovechar
  /// el ancho sin dejar espacio sobrante.
  Widget _buildInfoWrap(List<_InfoData> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final maxW = constraints.maxWidth;
        int cols = (maxW / 320).floor();
        cols = cols.clamp(1, 3);
        final tileWidth = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((d) => SizedBox(
                    width: tileWidth,
                    child: _buildInfoTile(d.label, d.value, d.icon),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
      options: MapOptions(center: LatLng(lat, lng), zoom: 13.0),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName:
              'InventtiaGestion/1.0 (+https://inventtia.com; contact: support@inventtia.com)',
          tileSize: 256,
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
              ),
            ),
          ],
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
  Widget _buildDiasTrabajoSelector() {
    final diasSemana = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    final diasSeleccionados = _parsearDiasTrabajoJSON(
      _storeData!['dias_trabajo'],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Días de Trabajo',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: diasSemana.map((dia) {
            final isSelected = diasSeleccionados.contains(dia.toLowerCase());
            return FilterChip(
              label: Text(dia),
              selected: isSelected,
              onSelected: (selected) async {
                final nuevosDias = List<String>.from(diasSeleccionados);
                if (selected) {
                  nuevosDias.add(dia.toLowerCase());
                } else {
                  nuevosDias.removeWhere((d) => d == dia.toLowerCase());
                }
                await _guardarDiasTrabajoJSON(nuevosDias);
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Colors.green.shade300,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHorariosTrabajoSelector() {
    final horaApertura = _storeData!['hora_apertura'] ?? '09:00:00';
    final horaCierre = _storeData!['hora_cierre'] ?? '18:00:00';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horarios',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTimePickerField(
                'Hora Apertura',
                horaApertura,
                'hora_apertura',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTimePickerField(
                'Hora Cierre',
                horaCierre,
                'hora_cierre',
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildTimePickerField(
    String label,
    String currentTime,
    String fieldKey,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _selectTime(label, currentTime, fieldKey),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currentTime.substring(0, 5),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.access_time, size: 18, color: Colors.blue.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectTime(
    String label,
    String currentTime,
    String fieldKey,
  ) async {
    final timeParts = currentTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      final formattedTime =
          '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}:00';
      await _updateStoreField(fieldKey, formattedTime);
    }
  }

  List<String> _parsearDiasTrabajoJSON(dynamic diasJSON) {
    if (diasJSON == null) return [];
    if (diasJSON is String) {
      try {
        final decoded = jsonDecode(diasJSON);
        return List<String>.from(decoded);
      } catch (e) {
        return [];
      }
    }
    if (diasJSON is List) {
      return List<String>.from(diasJSON);
    }
    return [];
  }

  Future<void> _guardarDiasTrabajoJSON(List<String> dias) async {
    try {
      if (_storeId == null) return;
      final diasJSON = jsonEncode(dias);
      await _storeDataService.updateStoreField(
        _storeId!,
        'dias_trabajo',
        diasJSON,
      );
      if (mounted) {
        setState(() {
          _storeData!['dias_trabajo'] = diasJSON;
        });
      }
    } catch (e) {
      print('Error guardando días de trabajo: $e');
    }
  }

  Future<void> _updateStoreField(String fieldKey, String value) async {
    try {
      if (_storeId == null) return;
      await _storeDataService.updateStoreField(_storeId!, fieldKey, value);
      if (mounted) {
        setState(() {
          _storeData![fieldKey] = value;
        });
      }
    } catch (e) {
      print('Error actualizando campo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  void _showAddDialog() {
    final currentTab = _tabController?.index ?? 0;
    switch (currentTab) {
      case 0:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Usa el botón "Editar Información de la Tienda" para editar',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 1:
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
    (_categoriesTabKey.currentState as dynamic)?.showAddCategoryDialog();
  }
}

/// Datos de una celda de información para la sección Tienda (vista web).
class _InfoData {
  final String label;
  final String value;
  final IconData icon;
  const _InfoData(this.label, this.value, this.icon);
}

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 7),
        Text(text),
      ],
    );
  }
}
class _WarehouseZoneSelector extends StatefulWidget {
  final int storeId;
  final WarehouseService warehouseService;
  final Function(int) onSelected;

  const _WarehouseZoneSelector({
    required this.storeId,
    required this.warehouseService,
    required this.onSelected,
  });

  @override
  State<_WarehouseZoneSelector> createState() => _WarehouseZoneSelectorState();
}

class _WarehouseZoneSelectorState extends State<_WarehouseZoneSelector> {
  bool _loading = true;
  List<Warehouse> _warehouses = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    try {
      final warehouses = await widget.warehouseService.listWarehouses(
        storeId: widget.storeId.toString(),
      );
      if (mounted) {
        setState(() {
          _warehouses = warehouses;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calcular Inventario desde...'),
      content: _loading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : _errorMessage != null
              ? Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(color: Colors.red),
                )
              : _warehouses.isEmpty
                  ? const Text(
                      'No hay almacenes configurados para esta tienda.')
                  : SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _warehouses.length,
                        itemBuilder: (context, index) {
                          final warehouse = _warehouses[index];
                          return ExpansionTile(
                            leading: const Icon(Icons.warehouse),
                            title: Text(warehouse.denominacion),
                            subtitle: Text(warehouse.direccion),
                            children: warehouse.zones.isEmpty
                                ? [
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('Sin zonas configuradas'),
                                    ),
                                  ]
                                : warehouse.zones.map((zone) {
                                    return ListTile(
                                      leading: const Icon(Icons.location_on),
                                      title: Text(zone.name),
                                      subtitle: Text(
                                        zone.type.toUpperCase(),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      onTap: () {
                                        final id = int.tryParse(zone.id);
                                        if (id != null) {
                                          widget.onSelected(id);
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content:
                                                  Text('ID de zona inválido'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  }).toList(),
                          );
                        },
                      ),
                    ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
