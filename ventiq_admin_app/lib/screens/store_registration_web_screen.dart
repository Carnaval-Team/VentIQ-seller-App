import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../models/store_ai_models.dart';
import '../services/store_registration_service.dart';
import '../services/warehouse_service.dart';
import '../services/geonames_service.dart';
import '../widgets/ai_store_generator_sheet.dart';

class StoreRegistrationWebScreen extends StatefulWidget {
  const StoreRegistrationWebScreen({super.key});

  @override
  State<StoreRegistrationWebScreen> createState() =>
      _StoreRegistrationWebScreenState();
}

class _StoreRegistrationWebScreenState
    extends State<StoreRegistrationWebScreen> {
  final PageController _pageController = PageController();
  final StoreRegistrationService _registrationService =
      StoreRegistrationService();
  final WarehouseService _warehouseService = WarehouseService();

  int _currentStep = 0;
  bool _isLoading = false;

  // Formulario controllers
  final _userFormKey = GlobalKey<FormState>();
  final _storeFormKey = GlobalKey<FormState>();

  // Datos del usuario
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Datos de la tienda
  final _storeNameController = TextEditingController();
  final _storeAddressController = TextEditingController();
  final _storeLocationController = TextEditingController();

  // Datos de país, estado y ciudad
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _cities = [];
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  Map<String, dynamic>? _selectedCity;
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;

  // Datos de localización
  double? _storeLatitude;
  double? _storeLogitude;
  bool _showMapPicker = false;

  // Datos obligatorios
  List<Map<String, dynamic>> _tpvData = [];
  List<Map<String, dynamic>> _almacenesData = [];
  List<Map<String, dynamic>> _layoutsData = [];
  List<Map<String, dynamic>> _personalData = [];

  // Los roles y layout types se manejan directamente en los métodos

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _openAiStoreAssistant() async {
    final plan = await showModalBottomSheet<StoreAiPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AiStoreGeneratorSheet(),
    );

    if (plan == null || !mounted) {
      return;
    }

    _applyAiPlan(plan);
    Future.microtask(() {
      if (mounted) {
        _createStore();
      }
    });
  }

  void _applyAiPlan(StoreAiPlan plan) {
    setState(() {
      _fullNameController.text = (plan.user.fullName ?? '').trim();
      _phoneController.text = (plan.user.phone ?? '').trim();
      _emailController.text = (plan.user.email ?? '').trim();
      _passwordController.text = (plan.user.password ?? '').trim();
      _confirmPasswordController.text = (plan.user.password ?? '').trim();

      _storeNameController.text = (plan.storeName ?? '').trim();
      _storeAddressController.text = (plan.storeAddress ?? '').trim();

      _selectedCountry = {
        'countryCode': (plan.location.countryCode ?? '').trim(),
        'countryName': (plan.location.countryName ?? '').trim(),
      };
      _selectedState = {
        'adminCode1': (plan.location.stateCode ?? '').trim(),
        'name': (plan.location.stateName ?? '').trim(),
      };
      _selectedCity = {
        'name': (plan.location.city ?? '').trim(),
        'lat': plan.location.latitude,
        'lng': plan.location.longitude,
      };
      _storeLatitude = plan.location.latitude;
      _storeLogitude = plan.location.longitude;

      _almacenesData =
          plan.warehouses
              .map(
                (w) => {
                  'denominacion': (w.name ?? '').trim(),
                  'direccion': (w.address ?? '').trim(),
                  'ubicacion': (w.location ?? '').trim(),
                },
              )
              .where((w) => (w['denominacion'] ?? '').toString().isNotEmpty)
              .toList();

      _layoutsData =
          plan.layouts
              .map(
                (l) => {
                  'denominacion': (l.name ?? '').trim(),
                  'codigo': (l.code ?? '').trim(),
                  'almacen_asignado': (l.warehouseName ?? '').trim(),
                  'id_tipo_layout': l.tipoLayoutId ?? 1,
                  'id_layout_padre': null,
                  'tipo_nombre': 'Zona',
                },
              )
              .where(
                (l) =>
                    (l['denominacion'] ?? '').toString().isNotEmpty &&
                    (l['codigo'] ?? '').toString().isNotEmpty,
              )
              .toList();

      _tpvData =
          plan.tpvs
              .map(
                (t) => {
                  'denominacion': (t.name ?? '').trim(),
                  'almacen_asignado': (t.warehouseName ?? '').trim(),
                },
              )
              .where((t) => (t['denominacion'] ?? '').toString().isNotEmpty)
              .toList();

      _personalData = [];
      _addMainUserToPersonal();

      _currentStep = 3;
    });

    _pageController.animateToPage(
      3,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadCountries() async {
    setState(() {
      _loadingCountries = true;
    });
    try {
      final countries = await GeonamesService.getCountries();
      if (mounted) {
        setState(() {
          _countries = countries;
          _loadingCountries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCountries = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar países: $e')));
      }
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _selectedState = null;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (mounted) {
        setState(() {
          _states = states;
          _loadingStates = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStates = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar estados: $e')));
      }
    }
  }

  Future<void> _loadCities(String countryCode, String adminCode) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      if (mounted) {
        setState(() {
          _cities = cities;
          _loadingCities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCities = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar ciudades: $e')));
      }
    }
  }

  String _formatPopulation(int population) {
    if (population >= 1000000) {
      return '${(population / 1000000).toStringAsFixed(1)}M';
    } else if (population >= 1000) {
      return '${(population / 1000).toStringAsFixed(1)}K';
    } else {
      return population.toString();
    }
  }

  Widget _buildLocationSummaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
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

  Widget _buildMapPreview() {
    // Si no hay coordenadas, mostrar placeholder
    if (_storeLatitude == null || _storeLogitude == null) {
      return Container(
        color: Colors.grey.shade100,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Selecciona una ciudad para mostrar el mapa',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Mostrar mapa interactivo de flutter_map
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              center: LatLng(_storeLatitude!, _storeLogitude!),
              zoom: 13.0,
              interactiveFlags: InteractiveFlag.all,
              onTap: (tapPosition, point) {
                // Al hacer clic en el mapa, actualizar la ubicación
                setState(() {
                  _storeLatitude = point.latitude;
                  _storeLogitude = point.longitude;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'VentIQAdmin/1.6.0 (+https://ventiq.com; contact: support@ventiq.com)',
                tileSize: 256,
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap:
                        () => launchUrl(
                          Uri.parse('https://openstreetmap.org/copyright'),
                        ),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 40.0,
                    height: 40.0,
                    point: LatLng(_storeLatitude!, _storeLogitude!),
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        // Permitir arrastrar el marcador
                        // Nota: Esta es una aproximación simple
                        // Para un arrastre más preciso, se necesitaría calcular las coordenadas
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Mostrar coordenadas actuales
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latitud',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _storeLatitude?.toStringAsFixed(6) ?? '0.0',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Longitud',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _storeLogitude?.toStringAsFixed(6) ?? '0.0',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  // Resetear a la ubicación de la ciudad seleccionada
                  if (_selectedCity != null) {
                    setState(() {
                      _storeLatitude =
                          double.tryParse(_selectedCity!['lat'].toString()) ??
                          0.0;
                      _storeLogitude =
                          double.tryParse(_selectedCity!['lng'].toString()) ??
                          0.0;
                    });
                  }
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Resetear'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMapPickerDialog() {
    double tempLat = _storeLatitude ?? 0.0;
    double tempLng = _storeLogitude ?? 0.0;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Ajustar Localización'),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 450,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.map,
                                  size: 64,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'OpenStreetMap',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Coordenadas Actuales:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Latitud: ${tempLat.toStringAsFixed(6)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Longitud: ${tempLng.toStringAsFixed(6)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Ejecuta: flutter pub get\npara activar el mapa interactivo',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade700,
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
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                // Guardar coordenadas temporales
                                this._storeLatitude = tempLat;
                                this._storeLogitude = tempLng;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Coordenadas guardadas: ${tempLat.toStringAsFixed(4)}, ${tempLng.toStringAsFixed(4)}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Guardar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _storeNameController.dispose();
    _storeAddressController.dispose();
    _storeLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1024;
    final isTablet = width >= 720 && width < 1024;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (!isWide) _buildModernProgressIndicator(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWide) _buildSideStepper(),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isWide ? 880 : (isTablet ? 720 : 600),
                              ),
                              child: ScrollConfiguration(
                                behavior: const _NoScrollbarBehavior(),
                                child: PageView(
                                  controller: _pageController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    _buildUserRegistrationStep(),
                                    _buildStoreInfoStep(),
                                    _buildOptionalDataStep(),
                                    _buildConfirmationStep(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildModernNavigationButtons(),
                      ],
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

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.white.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          const Text(
            'Registrar Nueva Tienda',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
              height: 1.1,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Salir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideStepper() {
    final steps = [
      {
        'title': 'Usuario',
        'subtitle': 'Cuenta del administrador',
        'icon': Icons.person_outline_rounded,
      },
      {
        'title': 'Tienda',
        'subtitle': 'Datos y ubicación',
        'icon': Icons.store_mall_directory_outlined,
      },
      {
        'title': 'Configuración',
        'subtitle': 'Almacenes, TPVs y personal',
        'icon': Icons.tune_rounded,
      },
      {
        'title': 'Confirmación',
        'subtitle': 'Revisar y crear',
        'icon': Icons.verified_outlined,
      },
    ];

    return Container(
      width: 300,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progreso',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textLight,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < steps.length; i++) ...[
            _buildSideStep(
              index: i,
              title: steps[i]['title'] as String,
              subtitle: steps[i]['subtitle'] as String,
              icon: steps[i]['icon'] as IconData,
              isLast: i == steps.length - 1,
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.promotionDiscountBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Puedes usar el asistente IA para acelerar la configuración.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryDark,
                      height: 1.4,
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

  Widget _buildSideStep({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLast,
  }) {
    final isCompleted = index < _currentStep;
    final isCurrent = index == _currentStep;

    Color circleColor;
    Color iconColor;
    Color titleColor;

    if (isCompleted) {
      circleColor = AppColors.success;
      iconColor = Colors.white;
      titleColor = AppColors.textPrimary;
    } else if (isCurrent) {
      circleColor = AppColors.primary;
      iconColor = Colors.white;
      titleColor = AppColors.primary;
    } else {
      circleColor = AppColors.surfaceVariant;
      iconColor = AppColors.textLight;
      titleColor = AppColors.textLight;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : icon,
                  size: 20,
                  color: iconColor,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: isCompleted
                        ? AppColors.success
                        : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernProgressIndicator() {
    final steps = [
      {'title': 'Usuario', 'icon': Icons.person_outline_rounded},
      {'title': 'Tienda', 'icon': Icons.store_mall_directory_outlined},
      {'title': 'Configuración', 'icon': Icons.tune_rounded},
      {'title': 'Confirmación', 'icon': Icons.verified_outlined},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Row(
            children: List.generate(steps.length, (index) {
              final isCompleted = index < _currentStep;
              final isCurrent = index == _currentStep;

              Color circleColor;
              Color iconColor;
              if (isCompleted) {
                circleColor = AppColors.success;
                iconColor = Colors.white;
              } else if (isCurrent) {
                circleColor = AppColors.primary;
                iconColor = Colors.white;
              } else {
                circleColor = AppColors.surfaceVariant;
                iconColor = AppColors.textLight;
              }

              return Expanded(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: circleColor,
                            shape: BoxShape.circle,
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            isCompleted
                                ? Icons.check_rounded
                                : steps[index]['icon'] as IconData,
                            color: iconColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          steps[index]['title'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent
                                ? AppColors.primary
                                : (isCompleted
                                    ? AppColors.textPrimary
                                    : AppColors.textLight),
                          ),
                        ),
                      ],
                    ),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(
                              left: 8, right: 8, bottom: 20),
                          decoration: BoxDecoration(
                            color: index < _currentStep
                                ? AppColors.success
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader({
    String? eyebrow,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildUserRegistrationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _userFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepHeader(
                  eyebrow: 'PASO 1 · USUARIO',
                  title: 'Crea la cuenta del administrador',
                  subtitle:
                      'Este usuario será el propietario y tendrá rol de gerente y supervisor.',
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withOpacity(0.08),
                        AppColors.primary.withOpacity(0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Asistente IA',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Genera toda la configuración con una descripción',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _openAiStoreAssistant,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Probar'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildFormCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa el nombre completo';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Número de Teléfono',
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: 'Ej: +1234567890',
                          helperText:
                              'Necesario para que nuestro equipo pueda contactarte',
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa un número de teléfono';
                          }
                          if (value.trim().length < 8) {
                            return 'Ingresa un número de teléfono válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa un email';
                          }
                          if (!value.contains('@')) {
                            return 'Ingresa un email válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa una contraseña';
                                }
                                if (value.length < 6) {
                                  return 'Mínimo 6 caracteres';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar',
                                prefixIcon: Icon(Icons.lock_person_outlined),
                              ),
                              validator: (value) {
                                if (value != _passwordController.text) {
                                  return 'No coinciden';
                                }
                                return null;
                              },
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
      ),
    );
  }

  Widget _buildStoreInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _storeFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepHeader(
                  eyebrow: 'PASO 2 · TIENDA',
                  title: 'Información de la tienda',
                  subtitle:
                      'Define el nombre, dirección y ubicación geográfica de tu punto de venta.',
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _storeNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la Tienda',
                    prefixIcon: Icon(Icons.store),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el nombre de la tienda';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _storeAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa la dirección';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Dropdown de País con búsqueda y bandera
                _loadingCountries
                    ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(),
                    )
                    : DropdownSearch<Map<String, dynamic>>(
                      items: _countries,
                      itemAsString: (item) => item['countryName'] ?? '',
                      selectedItem: _selectedCountry,
                      popupProps: PopupProps.menu(
                        showSearchBox: true,
                        searchFieldProps: const TextFieldProps(
                          decoration: InputDecoration(
                            hintText: 'Buscar país...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        itemBuilder: (context, item, isSelected) {
                          final countryCode = item['countryCode'] ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                CountryFlag.fromCountryCode(
                                  countryCode,
                                  height: 24,
                                  width: 32,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item['countryName'] ?? '',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        menuProps: const MenuProps(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(8),
                          ),
                          elevation: 8,
                        ),
                      ),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: 'País',
                          prefixIcon:
                              _selectedCountry != null
                                  ? Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: CountryFlag.fromCountryCode(
                                      _selectedCountry!['countryCode'] ?? '',
                                      height: 24,
                                      width: 32,
                                    ),
                                  )
                                  : const Icon(Icons.public),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _loadCountries,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Recargar países',
                          ),
                        ),
                      ),
                      onChanged: (country) {
                        if (country != null) {
                          setState(() {
                            _selectedCountry = country;
                          });
                          _loadStates(country['countryCode']);
                        }
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Selecciona un país';
                        }
                        return null;
                      },
                    ),
                const SizedBox(height: 16),

                // Dropdown de Estado con búsqueda
                if (_selectedCountry == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Selecciona un país primero',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else if (_loadingStates)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  )
                else if (_states.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Este país no tiene estados registrados',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  DropdownSearch<Map<String, dynamic>>(
                    items: _states,
                    itemAsString: (item) => item['name'] ?? '',
                    selectedItem: _selectedState,
                    popupProps: PopupProps.menu(
                      showSearchBox: true,
                      searchFieldProps: const TextFieldProps(
                        decoration: InputDecoration(
                          hintText: 'Buscar estado...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                      itemBuilder: (context, item, isSelected) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (item['adminName1'] != null &&
                                  item['adminName1'] != item['name'])
                                Text(
                                  item['adminName1'],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                      menuProps: const MenuProps(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                        elevation: 8,
                      ),
                    ),
                    dropdownDecoratorProps: DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Estado/Provincia',
                        prefixIcon: const Icon(Icons.location_city),
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            _selectedCountry != null
                                ? IconButton(
                                  onPressed:
                                      () => _loadStates(
                                        _selectedCountry!['countryCode'],
                                      ),
                                  icon: const Icon(Icons.refresh),
                                  tooltip: 'Recargar estados',
                                )
                                : null,
                      ),
                    ),
                    validator: (value) {
                      if (_states.isNotEmpty && value == null) {
                        return 'Selecciona un estado';
                      }
                      return null;
                    },
                    onChanged: (state) {
                      setState(() {
                        _selectedState = state;
                      });
                      if (state != null && _selectedCountry != null) {
                        _loadCities(
                          _selectedCountry!['countryCode'],
                          state['adminCode1'] ?? '',
                        );
                      }
                    },
                  ),
                const SizedBox(height: 16),

                // Dropdown de Ciudad con búsqueda
                if (_selectedState == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Selecciona un estado primero',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else if (_loadingCities)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  )
                else if (_cities.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'No hay ciudades disponibles para este estado',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  DropdownSearch<Map<String, dynamic>>(
                    items: _cities,
                    itemAsString: (item) {
                      final name = item['name'] ?? '';
                      final population = item['population'] ?? 0;
                      return population > 0
                          ? '$name (${_formatPopulation(population)})'
                          : name;
                    },
                    selectedItem: _selectedCity,
                    popupProps: PopupProps.menu(
                      showSearchBox: true,
                      searchFieldProps: const TextFieldProps(
                        decoration: InputDecoration(
                          hintText: 'Buscar ciudad...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                      itemBuilder: (context, item, isSelected) {
                        final name = item['name'] ?? '';
                        final population = item['population'] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (population > 0)
                                Text(
                                  'Población: ${_formatPopulation(population)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                      menuProps: const MenuProps(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                        elevation: 8,
                      ),
                    ),
                    dropdownDecoratorProps: DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Ciudad',
                        prefixIcon: const Icon(Icons.location_on),
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            _selectedState != null
                                ? IconButton(
                                  onPressed:
                                      () => _loadCities(
                                        _selectedCountry!['countryCode'],
                                        _selectedState!['adminCode1'] ?? '',
                                      ),
                                  icon: const Icon(Icons.refresh),
                                  tooltip: 'Recargar ciudades',
                                )
                                : null,
                      ),
                    ),
                    onChanged: (city) {
                      setState(() {
                        _selectedCity = city;
                        if (city != null) {
                          // Solo usar las coordenadas de la ciudad como punto inicial del mapa
                          // El usuario puede cambiar la ubicación en el mapa interactivo
                          try {
                            _storeLatitude =
                                double.tryParse(city['lat'].toString()) ?? 0.0;
                            _storeLogitude =
                                double.tryParse(city['lng'].toString()) ?? 0.0;
                          } catch (e) {
                            print('Error al convertir coordenadas: $e');
                            _storeLatitude = 0.0;
                            _storeLogitude = 0.0;
                          }
                        }
                      });
                    },
                    validator: (value) {
                      if (_cities.isNotEmpty && value == null) {
                        return 'Selecciona una ciudad';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 24),

                // Sección de localización en mapa
                if (_selectedCity != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Localización en Mapa',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Mapa interactivo
                            Container(
                              height: 350,
                              decoration: const BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                                color: Colors.grey,
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                                child: _buildMapPreview(),
                              ),
                            ),
                            // Información de la localización
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(0),
                                  bottomRight: Radius.circular(0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedCity?['name'] ?? 'Ciudad',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Lat: ${_storeLatitude?.toStringAsFixed(6) ?? "N/A"} | Lng: ${_storeLogitude?.toStringAsFixed(6) ?? "N/A"}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Resumen de datos
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLocationSummaryRow(
                                    'País',
                                    _selectedCountry?['countryName'] ??
                                        'No seleccionado',
                                    Icons.public,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildLocationSummaryRow(
                                    'Estado',
                                    _selectedState?['name'] ??
                                        'No seleccionado',
                                    Icons.location_city,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildLocationSummaryRow(
                                    'Ciudad',
                                    _selectedCity?['name'] ?? 'No seleccionado',
                                    Icons.location_on,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildLocationSummaryRow(
                                    'Dirección',
                                    _storeAddressController.text.isNotEmpty
                                        ? _storeAddressController.text
                                        : 'No ingresada',
                                    Icons.home,
                                  ),
                                  /* const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _showMapPicker = true;
                                    setState(() {});
                                    _showMapPickerDialog();
                                  },
                                  icon: const Icon(Icons.map),
                                  label: const Text('Ajustar Localización en Mapa'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ), */
                                ],
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
        ),
      ),
    );
  }

  Widget _buildOptionalDataStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepHeader(
                eyebrow: 'PASO 3 · CONFIGURACIÓN',
                title: 'Estructura operativa',
                subtitle:
                    'Configura los almacenes, layouts/zonas, TPVs y el personal que operará la tienda.',
              ),
              const SizedBox(height: 16),
              // Almacenes Section
              _buildSectionCard(
                title: 'Almacenes',
                icon: Icons.warehouse,
                count: _almacenesData.length,
                items: _almacenesData,
                onAdd: _showAddAlmacenDialog,
                onEdit: (index) => _showEditAlmacenDialog(index),
                onDelete: (index) => _deleteAlmacen(index),
                required: true,
              ),
              const SizedBox(height: 20),

              // Layouts Section
              _buildSectionCard(
                title: 'Layouts/Zonas',
                icon: Icons.grid_view,
                count: _layoutsData.length,
                items: _layoutsData,
                onAdd: _showAddLayoutDialog,
                onEdit: (index) => _showEditLayoutDialog(index),
                onDelete: (index) => _deleteLayout(index),
                required: true,
              ),
              const SizedBox(height: 20),

              // TPVs Section
              _buildSectionCard(
                title: 'TPVs',
                icon: Icons.point_of_sale,
                count: _tpvData.length,
                items: _tpvData,
                onAdd: _showAddTPVDialog,
                onEdit: (index) => _showEditTPVDialog(index),
                onDelete: (index) => _deleteTPV(index),
                required: true,
              ),
              const SizedBox(height: 20),

              // Personal Section
              _buildSectionCard(
                title: 'Personal',
                icon: Icons.people,
                count: _personalData.length,
                items: _personalData,
                onAdd: _showAddPersonalDialog,
                onEdit: (index) => _showEditPersonalDialog(index),
                onDelete: (index) => _deletePersonal(index),
                required: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required int count,
    required List<Map<String, dynamic>> items,
    required VoidCallback onAdd,
    required Function(int) onEdit,
    required Function(int) onDelete,
    required bool required,
  }) {
    final isEmpty = items.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.promotionDiscountBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      required && count == 0
                          ? 'Requerido para continuar'
                          : (isEmpty
                              ? 'Sin elementos configurados'
                              : '${items.length} elemento${items.length == 1 ? '' : 's'}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: required && count == 0
                            ? AppColors.error
                            : AppColors.textSecondary,
                        fontWeight: required && count == 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      size: 32, color: AppColors.textLight),
                  const SizedBox(height: 10),
                  Text(
                    'Aún no hay ${title.toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Haz clic en "Agregar" para comenzar',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            )
            else
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['denominacion'] ??
                                        '${item['nombres']} ${item['apellidos']}' ??
                                        'Sin nombre',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color:
                                          item['is_main_user'] == true
                                              ? Colors.green.shade700
                                              : Colors.black,
                                    ),
                                  ),
                                ),
                                if (item['is_main_user'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'PROPIETARIO',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (item['direccion'] != null)
                              Text(
                                item['direccion'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            if (item['tipo_rol'] != null)
                              Text(
                                'Rol: ${item['tipo_rol']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      item['is_main_user'] == true
                                          ? Colors.green.shade600
                                          : Colors.grey,
                                  fontWeight:
                                      item['is_main_user'] == true
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                ),
                              ),
                            if (item['almacen_asignado'] != null &&
                                item['tipo_rol'] == 'almacenero')
                              Text(
                                'Almacén: ${item['almacen_asignado']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            if (item['tpv_asignado'] != null &&
                                item['tipo_rol'] == 'vendedor')
                              Text(
                                'TPV: ${item['tpv_asignado']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Solo mostrar botones de editar/eliminar si no es el usuario principal
                      if (items[index]['is_main_user'] != true) ...[
                        IconButton(
                          onPressed: () => onEdit(index),
                          icon: const Icon(Icons.edit, size: 20),
                          color: Colors.blue,
                        ),
                        IconButton(
                          onPressed: () => onDelete(index),
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.red,
                        ),
                      ] else ...[
                        // Mostrar indicador de usuario principal
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.admin_panel_settings,
                                size: 16,
                                color: Colors.green,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'ADMIN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
        ],
      ),
    );
  }

  Widget _buildConfirmationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepHeader(
                eyebrow: 'PASO 4 · CONFIRMACIÓN',
                title: 'Revisa antes de crear',
                subtitle:
                    'Verifica que toda la información sea correcta. Podrás modificarla después.',
              ),
              const SizedBox(height: 14),

              _buildSummaryStatsRow(),
              const SizedBox(height: 20),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildUserSummaryCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStoreSummaryCard()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildUserSummaryCard(),
                      const SizedBox(height: 16),
                      _buildStoreSummaryCard(),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              _buildConfigSummaryCard(),

              if (_isLoading) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.promotionDiscountBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Creando tienda…',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStatsRow() {
    final stats = [
      {
        'icon': Icons.warehouse_outlined,
        'label': 'Almacenes',
        'value': _almacenesData.length,
        'color': AppColors.primary,
      },
      {
        'icon': Icons.grid_view_rounded,
        'label': 'Layouts',
        'value': _layoutsData.length,
        'color': AppColors.info,
      },
      {
        'icon': Icons.point_of_sale_rounded,
        'label': 'TPVs',
        'value': _tpvData.length,
        'color': AppColors.warning,
      },
      {
        'icon': Icons.people_outline_rounded,
        'label': 'Personal',
        'value': _personalData.length,
        'color': AppColors.success,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 620;
        const gap = 12.0;
        final cols = isWide ? 4 : 2;
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: stats.map((s) {
            final color = s['color'] as Color;
            return SizedBox(
              width: tileWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(s['icon'] as IconData,
                          color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${s['value']}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: color,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s['label'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSummaryCardShell({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
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
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textLight),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSummaryCard() {
    return _buildSummaryCardShell(
      icon: Icons.person_outline_rounded,
      iconColor: AppColors.primary,
      title: 'Usuario administrador',
      subtitle: 'Propietario de la tienda',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            icon: Icons.badge_outlined,
            label: 'Nombre',
            value: _fullNameController.text.isEmpty
                ? '—'
                : _fullNameController.text,
            emphasize: true,
          ),
          _buildInfoRow(
            icon: Icons.alternate_email_rounded,
            label: 'Email',
            value: _emailController.text.isEmpty
                ? '—'
                : _emailController.text,
          ),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Teléfono',
            value: _phoneController.text.isEmpty
                ? '—'
                : _phoneController.text,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildRoleChip('Gerente', AppColors.primary),
              _buildRoleChip('Supervisor', AppColors.info),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSummaryCard() {
    final coords =
        (_storeLatitude != null && _storeLogitude != null)
            ? '${_storeLatitude!.toStringAsFixed(4)}, ${_storeLogitude!.toStringAsFixed(4)}'
            : '—';
    return _buildSummaryCardShell(
      icon: Icons.storefront_rounded,
      iconColor: AppColors.success,
      title: 'Datos de la tienda',
      subtitle: 'Ubicación y dirección',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            icon: Icons.store_mall_directory_outlined,
            label: 'Nombre',
            value: _storeNameController.text.isEmpty
                ? '—'
                : _storeNameController.text,
            emphasize: true,
          ),
          _buildInfoRow(
            icon: Icons.home_outlined,
            label: 'Dirección',
            value: _storeAddressController.text.isEmpty
                ? '—'
                : _storeAddressController.text,
          ),
          _buildInfoRow(
            icon: Icons.public_rounded,
            label: 'País',
            value: _selectedCountry?['countryName']?.toString() ?? '—',
          ),
          _buildInfoRow(
            icon: Icons.location_city_rounded,
            label: 'Provincia',
            value: _selectedState?['name']?.toString() ?? '—',
          ),
          _buildInfoRow(
            icon: Icons.place_outlined,
            label: 'Ciudad',
            value: _selectedCity?['name']?.toString() ?? '—',
          ),
          _buildInfoRow(
            icon: Icons.my_location_rounded,
            label: 'Coords.',
            value: coords,
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildConfigSummaryCard() {
    return _buildSummaryCardShell(
      icon: Icons.tune_rounded,
      iconColor: AppColors.warning,
      title: 'Configuración operativa',
      subtitle: 'Elementos que se crearán con la tienda',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 620;
          const gap = 16.0;
          final cols = isWide ? 2 : 1;
          final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;

          final blocks = [
            _buildItemList(
              title: 'Almacenes',
              icon: Icons.warehouse_outlined,
              color: AppColors.primary,
              width: tileWidth,
              items: _almacenesData.map((a) {
                return _SummaryItem(
                  primary: a['denominacion']?.toString() ?? 'Sin nombre',
                  secondary: (a['direccion']?.toString().isNotEmpty ?? false)
                      ? a['direccion'].toString()
                      : null,
                );
              }).toList(),
            ),
            _buildItemList(
              title: 'Layouts / Zonas',
              icon: Icons.grid_view_rounded,
              color: AppColors.info,
              width: tileWidth,
              items: _layoutsData.map((l) {
                return _SummaryItem(
                  primary: l['denominacion']?.toString() ?? 'Sin nombre',
                  secondary:
                      '${l['tipo_nombre'] ?? 'Zona'} · ${l['codigo'] ?? ''}',
                  tag: l['almacen_asignado']?.toString(),
                );
              }).toList(),
            ),
            _buildItemList(
              title: 'TPVs',
              icon: Icons.point_of_sale_rounded,
              color: AppColors.warning,
              width: tileWidth,
              items: _tpvData.map((t) {
                return _SummaryItem(
                  primary: t['denominacion']?.toString() ?? 'Sin nombre',
                  tag: t['almacen_asignado']?.toString(),
                );
              }).toList(),
            ),
            _buildItemList(
              title: 'Personal',
              icon: Icons.people_outline_rounded,
              color: AppColors.success,
              width: tileWidth,
              items: _personalData.map((p) {
                final nombre =
                    '${p['nombres'] ?? ''} ${p['apellidos'] ?? ''}'.trim();
                final role = p['tipo_rol']?.toString();
                String? tag;
                if (p['almacen_asignado'] != null) {
                  tag = p['almacen_asignado'].toString();
                } else if (p['tpv_asignado'] != null) {
                  tag = p['tpv_asignado'].toString();
                }
                return _SummaryItem(
                  primary: nombre.isEmpty ? 'Sin nombre' : nombre,
                  secondary: role,
                  tag: tag,
                  highlight: p['is_main_user'] == true,
                );
              }).toList(),
            ),
          ];

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: blocks,
          );
        },
      ),
    );
  }

  Widget _buildItemList({
    required String title,
    required IconData icon,
    required Color color,
    required double width,
    required List<_SummaryItem> items,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Sin elementos',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textLight,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...items.map(
              (it) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: it.highlight
                      ? AppColors.promotionActiveBg
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: it.highlight
                        ? AppColors.success.withOpacity(0.35)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  it.primary,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (it.highlight) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (it.secondary != null &&
                              it.secondary!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              it.secondary!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (it.tag != null && it.tag!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            it.tag!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernNavigationButtons() {
    final isFinal = _currentStep == 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              'Paso ${_currentStep + 1} de 4',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            if (_currentStep > 0)
              TextButton.icon(
                onPressed: _isLoading ? null : _previousStep,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Anterior'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _nextStep,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isFinal
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
              label: Text(
                _isLoading
                    ? 'Procesando…'
                    : isFinal
                        ? 'Crear Tienda'
                        : 'Continuar',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isFinal ? AppColors.success : AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      if (_validateCurrentStep()) {
        setState(() {
          _currentStep++;
        });

        // Si navegamos al paso 3 (configuración), agregar automáticamente al usuario principal
        if (_currentStep == 2) {
          _addMainUserToPersonal();
        }

        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
      _createStore();
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _userFormKey.currentState?.validate() ?? false;
      case 1:
        return _storeFormKey.currentState?.validate() ?? false;
      case 2:
        // Validar que hay al menos uno de cada
        if (_tpvData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un TPV (Punto de Venta)');
          return false;
        }
        if (_almacenesData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un almacén');
          return false;
        }
        if (_layoutsData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un layout/zona');
          return false;
        }
        // Validar que cada almacén tenga al menos una zona asociada
        final almacenesSinZonas = <String>[];
        for (final almacen in _almacenesData) {
          final nombreAlmacen = (almacen['denominacion'] ?? '').toString();
          if (nombreAlmacen.isEmpty) {
            continue;
          }

          final tieneZonas = _layoutsData.any(
            (layout) =>
                (layout['almacen_asignado'] ?? '').toString() == nombreAlmacen,
          );

          if (!tieneZonas) {
            almacenesSinZonas.add(nombreAlmacen);
          }
        }

        if (almacenesSinZonas.isNotEmpty) {
          final detalle = almacenesSinZonas.join(', ');
          _showErrorDialog(
            'Cada almacén debe tener al menos una zona configurada.\n\n'
            'Faltan zonas en los siguientes almacenes:\n$detalle',
          );
          return false;
        }

        if (_personalData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un miembro del personal');
          return false;
        }
        return true;
      case 3:
        return true; // Confirmación
      default:
        return false;
    }
  }

  Future<void> _createStore() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🚀 Iniciando creación de tienda...');

      // Formatear coordenadas como "latitud,longitud"
      String? coordinatesString;
      if (_storeLatitude != null && _storeLogitude != null) {
        coordinatesString =
            '${_storeLatitude!.toStringAsFixed(6)},${_storeLogitude!.toStringAsFixed(6)}';
      }

      final result = await _registrationService.registerUserAndCreateStore(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        denominacionTienda: _storeNameController.text.trim(),
        direccionTienda: _storeAddressController.text.trim(),
        ubicacionTienda:
            coordinatesString ?? _storeLocationController.text.trim(),
        pais: _selectedCountry?['countryCode'],
        estado: _selectedState?['adminCode1'],
        nombrePais: _selectedCountry?['countryName'],
        nombreEstado: _selectedState?['name'],
        latitude: _storeLatitude,
        longitude: _storeLogitude,
        tpvData: _tpvData.isEmpty ? null : _tpvData,
        almacenesData: _almacenesData.isEmpty ? null : _almacenesData,
        layoutsData: _layoutsData.isEmpty ? null : _layoutsData,
        personalData: _personalData.isEmpty ? null : _personalData,
      );

      if (result['success']) {
        final userAlreadyExisted = result['user_already_existed'] == true;
        _showSuccessDialog(userAlreadyExisted: userAlreadyExisted);
      } else {
        _showErrorDialog(result['message'] ?? 'Error desconocido');
      }
    } catch (e) {
      _showErrorDialog('Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog({bool userAlreadyExisted = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('¡Éxito!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userAlreadyExisted
                      ? 'La tienda ha sido creada exitosamente. El usuario ya existía en el sistema y fue autenticado correctamente.'
                      : 'La tienda ha sido creada exitosamente. Ya puedes comenzar a usar la aplicación.',
                ),
                if (userAlreadyExisted) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Nota: El usuario con este email ya existía en el sistema.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Cerrar diálogo
                  Navigator.of(context).pop(); // Volver al login
                },
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // ===== MÉTODOS PARA TPVs =====
  void _showAddTPVDialog() {
    final nameController = TextEditingController();
    String? selectedAlmacen;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Agregar TPV'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del TPV',
                          hintText: 'Ej: TPV Principal, Caja 1',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedAlmacen,
                        decoration: const InputDecoration(
                          labelText: 'Almacén Asignado',
                        ),
                        items:
                            _almacenesData.map((almacen) {
                              return DropdownMenuItem<String>(
                                value: almacen['denominacion'],
                                child: Text(almacen['denominacion']),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedAlmacen = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Selecciona un almacén';
                          }
                          return null;
                        },
                      ),
                      if (_almacenesData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Debes crear al menos un almacén primero',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty &&
                            selectedAlmacen != null &&
                            _almacenesData.isNotEmpty) {
                          setState(() {
                            _tpvData.add({
                              'denominacion': nameController.text.trim(),
                              'almacen_asignado': selectedAlmacen,
                            });
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Agregar'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showEditTPVDialog(int index) {
    final tpv = _tpvData[index];
    final nameController = TextEditingController(text: tpv['denominacion']);
    String? selectedAlmacen = tpv['almacen_asignado'];

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Editar TPV'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del TPV',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedAlmacen,
                        decoration: const InputDecoration(
                          labelText: 'Almacén Asignado',
                        ),
                        items:
                            _almacenesData.map((almacen) {
                              return DropdownMenuItem<String>(
                                value: almacen['denominacion'],
                                child: Text(almacen['denominacion']),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedAlmacen = value;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty &&
                            selectedAlmacen != null) {
                          setState(() {
                            _tpvData[index]['denominacion'] =
                                nameController.text.trim();
                            _tpvData[index]['almacen_asignado'] =
                                selectedAlmacen;
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _deleteTPV(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar TPV'),
            content: Text(
              '¿Estás seguro de eliminar "${_tpvData[index]['denominacion']}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _tpvData.removeAt(index);
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  // ===== MÉTODOS PARA ALMACENES =====
  void _showAddAlmacenDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Agregar Almacén'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Almacén',
                    hintText: 'Ej: Almacén Principal',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    hintText: 'Dirección del almacén',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación',
                    hintText: 'Ciudad, País',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    setState(() {
                      _almacenesData.add({
                        'denominacion': nameController.text.trim(),
                        'direccion': addressController.text.trim(),
                        'ubicacion': locationController.text.trim(),
                      });
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
  }

  void _showEditAlmacenDialog(int index) {
    final almacen = _almacenesData[index];
    final nameController = TextEditingController(text: almacen['denominacion']);
    final addressController = TextEditingController(text: almacen['direccion']);
    final locationController = TextEditingController(
      text: almacen['ubicacion'],
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Editar Almacén'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Almacén',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    setState(() {
                      _almacenesData[index]['denominacion'] =
                          nameController.text.trim();
                      _almacenesData[index]['direccion'] =
                          addressController.text.trim();
                      _almacenesData[index]['ubicacion'] =
                          locationController.text.trim();
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
  }

  void _deleteAlmacen(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Almacén'),
            content: Text(
              '¿Estás seguro de eliminar "${_almacenesData[index]['denominacion']}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _almacenesData.removeAt(index);
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  // ===== MÉTODOS PARA PERSONAL =====
  void _showAddPersonalDialog() {
    final nombresController = TextEditingController();
    final apellidosController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? selectedRole;
    String? selectedAlmacen;
    String? selectedTPV;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Agregar Personal'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nombresController,
                          decoration: const InputDecoration(
                            labelText: 'Nombres',
                            hintText: 'Nombres del empleado',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos',
                            hintText: 'Apellidos del empleado',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText:
                                'Email del empleado para acceso al sistema',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Contraseña',
                            hintText:
                                'Contraseña de acceso (mínimo 6 caracteres)',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar Contraseña',
                            hintText: 'Repetir la contraseña',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(labelText: 'Rol'),
                          items: [
                            const DropdownMenuItem(
                              value: 'gerente',
                              child: Text('Gerente'),
                            ),
                            const DropdownMenuItem(
                              value: 'supervisor',
                              child: Text('Supervisor'),
                            ),
                            const DropdownMenuItem(
                              value: 'almacenero',
                              child: Text('Almacenero'),
                            ),
                            const DropdownMenuItem(
                              value: 'vendedor',
                              child: Text('Vendedor'),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value;
                              // Reset assignments when role changes
                              selectedAlmacen = null;
                              selectedTPV = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Mostrar dropdown de almacén para almaceneros
                        if (selectedRole == 'almacenero')
                          DropdownButtonFormField<String>(
                            value: selectedAlmacen,
                            decoration: const InputDecoration(
                              labelText: 'Almacén Asignado',
                            ),
                            items:
                                _almacenesData.map((almacen) {
                                  return DropdownMenuItem<String>(
                                    value: almacen['denominacion'],
                                    child: Text(almacen['denominacion']),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedAlmacen = value;
                              });
                            },
                          ),

                        // Mostrar dropdown de TPV para vendedores
                        if (selectedRole == 'vendedor')
                          DropdownButtonFormField<String>(
                            value: selectedTPV,
                            decoration: const InputDecoration(
                              labelText: 'TPV Asignado',
                            ),
                            items:
                                _tpvData.map((tpv) {
                                  return DropdownMenuItem<String>(
                                    value: tpv['denominacion'],
                                    child: Text(tpv['denominacion']),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedTPV = value;
                              });
                            },
                          ),

                        // Mostrar advertencias si no hay almacenes o TPVs
                        if (selectedRole == 'almacenero' &&
                            _almacenesData.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Debes crear al menos un almacén primero',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),

                        if (selectedRole == 'vendedor' && _tpvData.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Debes crear al menos un TPV primero',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
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
                      onPressed: () {
                        bool canAdd =
                            nombresController.text.trim().isNotEmpty &&
                            apellidosController.text.trim().isNotEmpty &&
                            emailController.text.trim().isNotEmpty &&
                            passwordController.text.trim().isNotEmpty &&
                            confirmPasswordController.text.trim().isNotEmpty &&
                            selectedRole != null;

                        // Validaciones de email y contraseña
                        if (canAdd) {
                          if (!emailController.text.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un email válido'),
                              ),
                            );
                            return;
                          }

                          if (passwordController.text.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'La contraseña debe tener al menos 6 caracteres',
                                ),
                              ),
                            );
                            return;
                          }

                          if (passwordController.text !=
                              confirmPasswordController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Las contraseñas no coinciden'),
                              ),
                            );
                            return;
                          }

                          // Verificar que el email no esté duplicado
                          final emailExists = _personalData.any(
                            (p) => p['email'] == emailController.text.trim(),
                          );
                          if (emailExists) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Este email ya está registrado'),
                              ),
                            );
                            return;
                          }
                        }

                        // Validaciones específicas por rol
                        if (selectedRole == 'almacenero') {
                          canAdd =
                              canAdd &&
                              selectedAlmacen != null &&
                              _almacenesData.isNotEmpty;
                        } else if (selectedRole == 'vendedor') {
                          canAdd =
                              canAdd &&
                              selectedTPV != null &&
                              _tpvData.isNotEmpty;
                        }

                        if (canAdd) {
                          setState(() {
                            final personalItem = {
                              'nombres': nombresController.text.trim(),
                              'apellidos': apellidosController.text.trim(),
                              'email': emailController.text.trim(),
                              'password': passwordController.text.trim(),
                              'tipo_rol': selectedRole,
                              'id_roll': _getRoleId(selectedRole!),
                              'uuid':
                                  'PLACEHOLDER_USER_UUID', // Se reemplazará con el UUID real
                            };

                            // Agregar asignaciones específicas
                            if (selectedRole == 'almacenero' &&
                                selectedAlmacen != null) {
                              personalItem['almacen_asignado'] =
                                  selectedAlmacen;
                            } else if (selectedRole == 'vendedor' &&
                                selectedTPV != null) {
                              personalItem['tpv_asignado'] = selectedTPV;
                            }

                            _personalData.add(personalItem);
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Agregar'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showEditPersonalDialog(int index) {
    final personal = _personalData[index];
    final nombresController = TextEditingController(text: personal['nombres']);
    final apellidosController = TextEditingController(
      text: personal['apellidos'],
    );
    final emailController = TextEditingController(text: personal['email']);
    String? selectedRole = personal['tipo_rol'];

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Editar Personal'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nombresController,
                          decoration: const InputDecoration(
                            labelText: 'Nombres',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(labelText: 'Rol'),
                          items: [
                            const DropdownMenuItem(
                              value: 'gerente',
                              child: Text('Gerente'),
                            ),
                            const DropdownMenuItem(
                              value: 'supervisor',
                              child: Text('Supervisor'),
                            ),
                            const DropdownMenuItem(
                              value: 'almacenero',
                              child: Text('Almacenero'),
                            ),
                            const DropdownMenuItem(
                              value: 'vendedor',
                              child: Text('Vendedor'),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value;
                            });
                          },
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
                      onPressed: () {
                        if (nombresController.text.trim().isNotEmpty &&
                            apellidosController.text.trim().isNotEmpty &&
                            emailController.text.trim().isNotEmpty &&
                            selectedRole != null) {
                          // Validar email
                          if (!emailController.text.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un email válido'),
                              ),
                            );
                            return;
                          }

                          // Verificar que el email no esté duplicado (excepto el actual)
                          final emailExists = _personalData.asMap().entries.any(
                            (entry) =>
                                entry.key != index &&
                                entry.value['email'] ==
                                    emailController.text.trim(),
                          );
                          if (emailExists) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Este email ya está registrado'),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            _personalData[index]['nombres'] =
                                nombresController.text.trim();
                            _personalData[index]['apellidos'] =
                                apellidosController.text.trim();
                            _personalData[index]['email'] =
                                emailController.text.trim();
                            _personalData[index]['tipo_rol'] = selectedRole;
                            _personalData[index]['id_roll'] = _getRoleId(
                              selectedRole!,
                            );
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _deletePersonal(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Personal'),
            content: Text(
              '¿Estás seguro de eliminar a "${_personalData[index]['nombres']} ${_personalData[index]['apellidos']}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _personalData.removeAt(index);
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  int _getRoleId(String roleType) {
    switch (roleType) {
      case 'gerente':
        return 1;
      case 'supervisor':
        return 2;
      case 'almacenero':
        return 3;
      case 'vendedor':
        return 4;
      default:
        return 4; // Default to vendedor
    }
  }

  // Agregar automáticamente al usuario principal con roles de gerente y supervisor
  void _addMainUserToPersonal() {
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) return;

    // Separar nombres y apellidos (simple split por espacio)
    final nameParts = fullName.split(' ');
    final nombres = nameParts.isNotEmpty ? nameParts.first : 'Usuario';
    final apellidos =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'Principal';

    // Verificar si ya existe el usuario principal para evitar duplicados
    final existingMainUser =
        _personalData.where((p) => p['is_main_user'] == true).toList();
    if (existingMainUser.isNotEmpty) {
      return; // Ya existe, no agregar duplicados
    }

    // Agregar como Gerente
    final gerenteItem = {
      'nombres': nombres,
      'apellidos': apellidos,
      'email': _emailController.text.trim(), // Email del usuario principal
      'password': _passwordController.text, // Contraseña del usuario principal
      'tipo_rol': 'gerente',
      'id_roll': 1,
      'uuid':
          'MAIN_USER_UUID', // Se reemplazará con el UUID real del usuario creado
      'is_main_user':
          true, // Marca especial para identificar al usuario principal
      'is_editable': false, // No se puede editar
    };

    // Agregar como Supervisor
    final supervisorItem = {
      'nombres': nombres,
      'apellidos': apellidos,
      'email': _emailController.text.trim(), // Email del usuario principal
      'password': _passwordController.text, // Contraseña del usuario principal
      'tipo_rol': 'supervisor',
      'id_roll': 2,
      'uuid':
          'MAIN_USER_UUID', // Se reemplazará con el UUID real del usuario creado
      'is_main_user':
          true, // Marca especial para identificar al usuario principal
      'is_editable': false, // No se puede editar
    };

    setState(() {
      _personalData.insert(0, gerenteItem); // Insertar al inicio
      _personalData.insert(1, supervisorItem); // Insertar después del gerente
    });

    print(
      '✅ Usuario principal agregado automáticamente como Gerente y Supervisor',
    );
    print('   - Nombres: $nombres');
    print('   - Apellidos: $apellidos');
  }

  // ===== MÉTODOS PARA LAYOUTS =====
  void _showAddLayoutDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    String? selectedAlmacen;
    int? selectedTipoLayout;
    List<Map<String, dynamic>> layoutTypes = [];
    bool loadingTypes = true;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              // Cargar tipos de layout cuando se abre el diálogo
              if (loadingTypes) {
                _warehouseService
                    .getTiposLayout()
                    .then((types) {
                      setDialogState(() {
                        layoutTypes.clear();
                        layoutTypes.addAll(types);
                        loadingTypes = false;
                        // Seleccionar el primer tipo por defecto
                        if (layoutTypes.isNotEmpty) {
                          selectedTipoLayout = layoutTypes.first['id'];
                        }
                      });
                    })
                    .catchError((e) {
                      print('Error cargando tipos de layout: $e');
                      setDialogState(() {
                        loadingTypes = false;
                        // Fallback a tipo por defecto
                        layoutTypes = [
                          {'id': 1, 'denominacion': 'Zona'},
                        ];
                        selectedTipoLayout = 1;
                      });
                    });
              }

              return AlertDialog(
                title: const Text('Agregar Layout/Zona'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Crea una zona dentro del almacén para organizar los productos.',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Layout/Zona',
                          hintText: 'Ej: Zona Principal, Estantería A',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Código',
                          hintText: 'Ej: ZP-001, EST-A-001',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (loadingTypes)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Cargando tipos de layout...'),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<int?>(
                          value: selectedTipoLayout,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Layout',
                            prefixIcon: Icon(Icons.category),
                          ),
                          isExpanded: true, // Evita overflow
                          items:
                              layoutTypes.map((tipo) {
                                return DropdownMenuItem<int?>(
                                  value: tipo['id'],
                                  child: Text(
                                    tipo['denominacion'] ?? 'Sin nombre',
                                    overflow:
                                        TextOverflow
                                            .ellipsis, // Truncar texto largo
                                    maxLines: 1,
                                  ),
                                );
                              }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedTipoLayout = value;
                            });
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'Selecciona un tipo de layout';
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedAlmacen,
                        decoration: const InputDecoration(
                          labelText: 'Almacén Asignado',
                        ),
                        isExpanded: true, // Evita overflow
                        items:
                            _almacenesData.map((almacen) {
                              return DropdownMenuItem<String>(
                                value: almacen['denominacion'],
                                child: Text(
                                  almacen['denominacion'],
                                  overflow:
                                      TextOverflow
                                          .ellipsis, // Truncar texto largo
                                  maxLines: 1,
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedAlmacen = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Selecciona un almacén';
                          }
                          return null;
                        },
                      ),
                      if (_almacenesData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Debes crear al menos un almacén primero',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
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
                    onPressed: () {
                      if (nameController.text.trim().isNotEmpty &&
                          codeController.text.trim().isNotEmpty &&
                          selectedAlmacen != null &&
                          selectedTipoLayout != null &&
                          _almacenesData.isNotEmpty) {
                        setState(() {
                          _layoutsData.add({
                            'denominacion': nameController.text.trim(),
                            'codigo': codeController.text.trim(),
                            'almacen_asignado': selectedAlmacen,
                            'id_tipo_layout':
                                selectedTipoLayout, // Tipo seleccionado por el usuario
                            'id_layout_padre': null, // Layout raíz
                            'tipo_nombre':
                                layoutTypes.firstWhere(
                                  (t) => t['id'] == selectedTipoLayout,
                                  orElse: () => {'denominacion': 'Desconocido'},
                                )['denominacion'], // Para mostrar en confirmación
                          });
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Agregar'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showEditLayoutDialog(int index) {
    final layout = _layoutsData[index];
    final nameController = TextEditingController(text: layout['denominacion']);
    final codeController = TextEditingController(text: layout['codigo']);
    String? selectedAlmacen = layout['almacen_asignado'];

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Editar Layout/Zona'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Layout/Zona',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(labelText: 'Código'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedAlmacen,
                        decoration: const InputDecoration(
                          labelText: 'Almacén Asignado',
                        ),
                        items:
                            _almacenesData.map((almacen) {
                              return DropdownMenuItem<String>(
                                value: almacen['denominacion'],
                                child: Text(almacen['denominacion']),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedAlmacen = value;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty &&
                            codeController.text.trim().isNotEmpty &&
                            selectedAlmacen != null) {
                          setState(() {
                            _layoutsData[index]['denominacion'] =
                                nameController.text.trim();
                            _layoutsData[index]['codigo'] =
                                codeController.text.trim();
                            _layoutsData[index]['almacen_asignado'] =
                                selectedAlmacen;
                            // Mantener los campos necesarios si no existen
                            _layoutsData[index]['id_tipo_layout'] ??= 1;
                            _layoutsData[index]['id_layout_padre'] ??= null;
                            _layoutsData[index]['tipo_nombre'] ??= 'Zona';
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _deleteLayout(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Layout/Zona'),
            content: Text(
              '¿Estás seguro de eliminar "${_layoutsData[index]['denominacion']}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _layoutsData.removeAt(index);
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }
}

class _SummaryItem {
  final String primary;
  final String? secondary;
  final String? tag;
  final bool highlight;

  _SummaryItem({
    required this.primary,
    this.secondary,
    this.tag,
    this.highlight = false,
  });
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
