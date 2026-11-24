import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../models/store_ai_models.dart';
import '../services/store_registration_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../services/geonames_service.dart';
import '../widgets/ai_store_generator_sheet.dart';
import '../widgets/tutorial_guiado.dart';

class StoreRegistrationScreen extends StatefulWidget {
  const StoreRegistrationScreen({super.key});

  @override
  State<StoreRegistrationScreen> createState() =>
      _StoreRegistrationScreenState();
}

/// Etiqueta de campo con el mismo peso visual en todos los pasos.
class _EtiquetaCampo extends StatelessWidget {
  const _EtiquetaCampo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.01,
      ),
    );
  }
}

class _StoreRegistrationScreenState extends State<StoreRegistrationScreen> {
  final PageController _pageController = PageController();
  final StoreRegistrationService _registrationService =
      StoreRegistrationService();
  final WarehouseService _warehouseService = WarehouseService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  int _currentStep = 0;
  bool _isLoading = false;

  /// Tienda creada en el paso 1.
  ///
  /// A partir de aquí el asistente **completa** esa tienda; no vuelve a crearla.
  /// Se inicializa desde las preferencias por si el usuario entró desde el
  /// checklist con la tienda ya creada (el asistente se abre de cero en ese
  /// caso, pero el id sigue siendo el correcto).
  int? _tiendaIdBorrador;

  // ---------------------------------------------------------------------------
  // Tutorial guiado
  // ---------------------------------------------------------------------------

  // Claves de los campos que resalta el tutorial. Son `GlobalKey` porque el
  // recorrido mide el widget real en pantalla, no solo su posición teórica.
  final _claveBotonTutorial = GlobalKey();
  final _claveNombre = GlobalKey();
  final _claveTelefono = GlobalKey();
  final _claveEmail = GlobalKey();
  final _clavePassword = GlobalKey();
  final _claveConfirmPassword = GlobalKey();
  final _claveAsistenteIa = GlobalKey();
  final _claveNombreTienda = GlobalKey();
  final _claveDireccion = GlobalKey();
  final _clavePais = GlobalKey();
  final _claveMapa = GlobalKey();
  final _claveAlmacenes = GlobalKey();
  final _claveTpvs = GlobalKey();
  final _clavePersonal = GlobalKey();
  final _claveResumen = GlobalKey();
  final _claveBotonSiguiente = GlobalKey();

  /// Burbuja «¿Tienes dudas?» viva sobre el AppBar.
  AvisoTutorial? _avisoTutorial;
  bool _avisoTutorialAbierto = false;

  /// Ya se mostró en esta visita: no insiste cada vez que se pulsa el icono.
  bool _avisoTutorialMostrado = false;

  /// El tutorial arranca solo la primera vez que se abre la pantalla.
  bool _tutorialAutoLanzado = false;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

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

      _almacenesData = plan.warehouses
          .map(
            (w) => {
              'denominacion': (w.name ?? '').trim(),
              'direccion': (w.address ?? '').trim(),
              'ubicacion': (w.location ?? '').trim(),
            },
          )
          .where((w) => (w['denominacion'] ?? '').toString().isNotEmpty)
          .toList();

      _layoutsData = plan.layouts
          .map(
            (l) => {
              'denominacion': (l.name ?? '').trim(),
              // La RPC inserta `item_json->>'sku_codigo'`. Con la clave
              // `codigo` el código de la zona se perdía en silencio (8 de 9
              // layouts de newa lo tienen NULL).
              'sku_codigo': (l.code ?? '').trim(),
              'almacen_asignado': (l.warehouseName ?? '').trim(),
              'id_tipo_layout': l.tipoLayoutId ?? 1,
              'id_layout_padre': null,
              'tipo_nombre': 'Zona',
            },
          )
          .where(
            (l) =>
                (l['denominacion'] ?? '').toString().isNotEmpty &&
                (l['sku_codigo'] ?? '').toString().isNotEmpty,
          )
          .toList();

      _tpvData = plan.tpvs
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

  Future<void> _loadCountries({bool preserveSelection = false}) async {
    final previousCountry = _selectedCountry;
    setState(() {
      _loadingCountries = true;
    });
    try {
      final countries = await GeonamesService.getCountries();
      if (mounted) {
        setState(() {
          _countries = countries;
          _loadingCountries = false;
          if (preserveSelection && previousCountry != null) {
            for (final country in countries) {
              if (country['countryCode'] == previousCountry['countryCode']) {
                _selectedCountry = country;
                break;
              }
            }
          }
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

  Future<void> _loadStates(
    String countryCode, {
    bool clearSelection = true,
  }) async {
    final previousState = _selectedState;
    setState(() {
      _loadingStates = true;
      if (clearSelection) {
        _states = [];
        _selectedState = null;
        _cities = [];
        _selectedCity = null;
      }
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (mounted) {
        setState(() {
          _states = states;
          _loadingStates = false;
          if (!clearSelection && previousState != null) {
            for (final state in states) {
              if (state['adminCode1'] == previousState['adminCode1']) {
                _selectedState = state;
                break;
              }
            }
          }
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

  Future<void> _loadCities(
    String countryCode,
    String adminCode, {
    bool clearSelection = true,
  }) async {
    final previousCity = _selectedCity;
    setState(() {
      _loadingCities = true;
      if (clearSelection) {
        _cities = [];
        _selectedCity = null;
      }
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      if (mounted) {
        setState(() {
          _cities = cities;
          _loadingCities = false;
          if (!clearSelection && previousCity != null) {
            for (final city in cities) {
              if (city['name'] == previousCity['name']) {
                _selectedCity = city;
                break;
              }
            }
          }
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

  void _reloadCountries() => _loadCountries(preserveSelection: true);

  void _reloadStates() {
    final country = _selectedCountry;
    if (country == null) return;
    _loadStates(country['countryCode'], clearSelection: false);
  }

  void _reloadCities() {
    final country = _selectedCountry;
    final state = _selectedState;
    if (country == null || state == null) return;
    _loadCities(
      country['countryCode'],
      state['adminCode1'] ?? '',
      clearSelection: false,
    );
  }

  Widget _locationPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(message, style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _locationLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  /// Selector geográfico con botón de recarga manual a la derecha.
  Widget _buildLocationSelectorRow({
    required Widget child,
    required VoidCallback? onReload,
    bool isLoading = false,
    String reloadTooltip = 'Recargar',
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.outlined(
            onPressed: isLoading ? null : onReload,
            tooltip: reloadTooltip,
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ),
      ],
    );
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
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                      style: const TextStyle(fontSize: 13),
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
                                      style: const TextStyle(fontSize: 13),
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
                            border: Border.all(color: Colors.orange.shade200),
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
  void initState() {
    super.initState();
    _loadCountries();
    _cargarTiendaBorrador();
    // La burbuja «¿Tienes dudas?» aparece sola al entrar: es la única forma de
    // que un cliente nuevo descubra que hay un recorrido explicativo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tutorialAutoLanzado) return;
      _tutorialAutoLanzado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mostrarAvisoTutorial();
      });
    });
  }

  /// Recupera la tienda activa de las preferencias.
  ///
  /// El asistente se abre también desde el checklist de una tienda que ya
  /// existe; en ese caso los pasos 2-4 tienen que completar **esa** tienda y no
  /// una nueva. Se lee en segundo plano: sin id, el paso 1 simplemente creará
  /// la tienda como siempre.
  Future<void> _cargarTiendaBorrador() async {
    try {
      final id = await _userPreferencesService.getIdTienda();
      if (!mounted || id == null) return;
      setState(() => _tiendaIdBorrador = id);

      // Precarga el nombre de la tienda para no enseñar campos vacíos si ya
      // existe. Un fallo de lectura no rompe nada: se queda vacío.
      final fila = await Supabase.instance.client
          .from('app_dat_tienda')
          .select('denominacion, direccion, ubicacion')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || fila == null) return;

      final nombre = (fila['denominacion'] ?? '').toString();
      // El nombre provisional del paso 1 no se pinta como si fuera real.
      if (nombre.isNotEmpty && !nombre.startsWith('Tienda de ') &&
          nombre != 'Mi tienda') {
        _storeNameController.text = nombre;
      }
      _storeAddressController.text = (fila['direccion'] ?? '').toString();
      final ubicacion = (fila['ubicacion'] ?? '').toString();
      // Si la ubicación son coordenadas ya se pintan en el mapa.
      if (ubicacion.isNotEmpty && !RegExp(r'^-?\d+\.\d+,-?\d+\.\d+$').hasMatch(ubicacion)) {
        _storeLocationController.text = ubicacion;
      }
    } catch (e) {
      print('⚠️ No se pudo precargar la tienda en borrador: $e');
    }
  }

  @override
  void dispose() {
    _cerrarAvisoTutorial(notificar: false);
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

  // ==========================================================================
  // Tutorial: burbuja del AppBar + recorrido campo por campo
  // ==========================================================================

  Widget _botonTutorial() {
    return IconButton(
      key: _claveBotonTutorial,
      icon: const Icon(Icons.school_outlined),
      tooltip: 'Tutorial de esta pantalla',
      onPressed: () {
        if (_avisoTutorialAbierto) {
          _cerrarAvisoTutorial();
        } else {
          _mostrarAvisoTutorial();
        }
      },
    );
  }

  void _mostrarAvisoTutorial() {
    if (_avisoTutorialAbierto) return;
    _avisoTutorialMostrado = true;
    final aviso = insertarAvisoTutorial(
      context,
      ancla: _claveBotonTutorial,
      alAceptar: _abrirTutorial,
      alCerrar: _alCerrarAvisoPorUsuario,
      titulo: '¿Tienes dudas?',
      descripcion:
          'Ve el tutorial: recorre el alta campo por campo, resaltando cada '
          'uno sobre la pantalla mientras te explica qué se pone.',
      textoBoton: 'Ver tutorial',
    );
    if (aviso == null) return;
    _avisoTutorial = aviso;
    setState(() => _avisoTutorialAbierto = true);
  }

  /// La burbuja ya retiró su entrada: aquí solo se sincroniza el estado.
  void _alCerrarAvisoPorUsuario() {
    _avisoTutorial = null;
    if (!mounted) return;
    if (!_avisoTutorialAbierto) return;
    setState(() => _avisoTutorialAbierto = false);
  }

  /// Retirada programática (al salir de la pantalla, al arrancar el recorrido).
  /// `AvisoTutorial.cerrar` es idempotente.
  ///
  /// [notificar] es `false` desde [dispose]: tocar `setState` con el elemento ya
  /// desmontado revienta con «setState() called after dispose()».
  void _cerrarAvisoTutorial({bool notificar = true}) {
    final aviso = _avisoTutorial;
    _avisoTutorial = null;
    if (aviso != null && !aviso.cerrada) aviso.cerrar();
    if (!notificar || !mounted) return;
    if (!_avisoTutorialAbierto) return;
    setState(() => _avisoTutorialAbierto = false);
  }

  Future<void> _abrirTutorial() async {
    _cerrarAvisoTutorial();
    if (!mounted) return;
    // La página la cambia cada paso con su `alEntrar`: forzar el paso 1 aquí
    // rompería el recorrido cuando el usuario ya está en otra página.
    await mostrarTutorialGuiado(context, pasos: _pasosTutorial());
  }

  /// Lleva el asistente a un paso concreto y espera a que la página esté
  /// montada. Lo llama cada `PasoGuiado.alEntrar`.
  Future<void> _irAPasoAsistente(int paso) async {
    if (!mounted || _currentStep == paso) {
      // Ya está montada: un frame para que el layout esté asentado.
      await Future<void>.delayed(const Duration(milliseconds: 90));
      return;
    }
    setState(() => _currentStep = paso);
    _pageController.jumpToPage(paso);
    await Future<void>.delayed(const Duration(milliseconds: 260));
  }

  /// Pasos del recorrido. Todos viven en el asistente: cada uno lleva su
  /// `alEntrar` para que el recorrido pueda saltar entre páginas.
  List<PasoGuiado> _pasosTutorial() {
    Future<void> Function() en(int paso) =>
        () => _irAPasoAsistente(paso);

    return [
      PasoGuiado(
        clave: _claveNombre,
        titulo: 'Nombre completo',
        icono: Icons.badge_outlined,
        texto:
            'Tu nombre y apellidos, como quieres aparecer en la app y en los '
            'reportes. No es el nombre de la tienda: ese va en el paso '
            'siguiente.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _claveTelefono,
        titulo: 'Teléfono de contacto',
        icono: Icons.phone_outlined,
        texto:
            'Un número donde podamos localizarte si hay un problema con tu '
            'cuenta o tu suscripción. No se muestra a los clientes.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _claveEmail,
        titulo: 'Email de acceso',
        icono: Icons.alternate_email,
        texto:
            'Con este correo entras a la app. Escríbelo bien: es donde llegan '
            'los avisos y desde donde se recupera la contraseña.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _clavePassword,
        titulo: 'Contraseña',
        icono: Icons.lock_outline,
        texto:
            'Mínimo 6 caracteres. La barra de debajo dice si es débil o fuerte '
            'mientras escribes. El ojo a la derecha la muestra para que '
            'compruebes que no hay erratas.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _claveConfirmPassword,
        titulo: 'Confirmar contraseña',
        icono: Icons.lock_reset_outlined,
        texto:
            'La misma contraseña otra vez. Si no coinciden, la app no te deja '
            'avanzar: es la última red antes de quedarte sin acceso.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _claveAsistenteIa,
        titulo: 'Crear tienda asistida (IA)',
        icono: Icons.auto_awesome,
        texto:
            'Si prefieres no rellenar todo a mano, describe tu negocio y la IA '
            'propone almacenes, cajas y personal. Lo revisas antes de crear '
            'nada.',
        alEntrar: en(0),
      ),
      PasoGuiado(
        clave: _claveNombreTienda,
        titulo: 'Nombre de la tienda',
        icono: Icons.storefront_outlined,
        texto:
            'El nombre comercial que verán tus clientes y tu equipo en todas '
            'las pantallas. Piensa que puede haber más de una tienda tuya: '
            'mejor uno que se distinga.',
        alEntrar: en(1),
      ),
      PasoGuiado(
        clave: _claveDireccion,
        titulo: 'Dirección',
        icono: Icons.location_on_outlined,
        texto:
            'Calle y número del local. Aparece en los tickets y sirve para que '
            'el repartidor o el cliente lleguen. Puedes afinarla abajo, en el '
            'mapa.',
        alEntrar: en(1),
      ),
      PasoGuiado(
        clave: _clavePais,
        titulo: 'País, provincia y ciudad',
        icono: Icons.public,
        texto:
            'Se eligen en cascada: primero el país, luego la provincia y por '
            'último la ciudad. Cada uno se carga al elegir el anterior. Si una '
            'lista llega vacía, el botón de recargar está a la derecha.',
        alEntrar: en(1),
      ),
      PasoGuiado(
        clave: _claveMapa,
        titulo: 'Ubicación en el mapa',
        icono: Icons.my_location,
        texto:
            'Toca el mapa para mover el alfiler a tu puerta exacta. Esa '
            'coordenada se guarda con la tienda y la usan las apps de reparto y '
            'las rutas.',
        alEntrar: en(1),
      ),
      PasoGuiado(
        clave: _claveAlmacenes,
        titulo: 'Almacenes y zonas',
        icono: Icons.warehouse_outlined,
        texto:
            'Un almacén es donde guardas la mercancía; las zonas, las '
            'estanterías o áreas dentro de él. Si no lo tienes claro ahora, '
            'puedes continuar: el checklist de activación te lo recordará.',
        alEntrar: en(2),
      ),
      PasoGuiado(
        clave: _claveTpvs,
        titulo: 'TPV (cajas)',
        icono: Icons.point_of_sale_outlined,
        texto:
            'Cada TPV es un punto de venta: una caja física o una caja virtual. '
            'Cada uno se asigna a un almacén, que es de donde descuenta el '
            'stock al vender.',
        alEntrar: en(2),
      ),
      PasoGuiado(
        clave: _clavePersonal,
        titulo: 'Personal',
        icono: Icons.groups_outlined,
        texto:
            'Tu usuario aparece ya como administrador. Aquí añades al resto: '
            'gerentes ven todo, supervisores controlan, almaceneros mueven '
            'inventario y vendedores solo cobran en su caja.',
        alEntrar: en(2),
      ),
      PasoGuiado(
        clave: _claveResumen,
        titulo: 'Resumen antes de guardar',
        icono: Icons.fact_check_outlined,
        texto:
            'Todo lo que has puesto, junto. Si algo está mal, vuelve con '
            '«Anterior»; al pulsar «Guardar y continuar» se añaden los '
            'almacenes y las cajas a la tienda que ya creaste en el paso 1.',
        alEntrar: en(3),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.storefront,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'Nueva tienda',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          _botonTutorial(),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Salir',
            onPressed: _isLoading
                ? null
                : () {
                    _cerrarAvisoTutorial();
                    Navigator.of(context).maybePop();
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Stepper sobre fondo blanco: el azul se reserva para lo accionable.
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: _buildModernProgressIndicator(),
          ),

          // Content: ancho adaptable (móvil → web)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = _contentMaxWidth(constraints.maxWidth);
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
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
                );
              },
            ),
          ),

          // Navigation buttons mejorados
          _buildModernNavigationButtons(),
        ],
      ),
    );
  }

  double _contentMaxWidth(double availableWidth) {
    if (availableWidth >= 1200) return 1100;
    if (availableWidth >= 900) return 900;
    if (availableWidth >= 700) return 720;
    return availableWidth;
  }

  bool get _isWideLayout {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  Widget _buildModernProgressIndicator() {
    const steps = [
      ('Tu cuenta', Icons.person_outline),
      ('Tu tienda', Icons.storefront_outlined),
      ('Configuración', Icons.tune),
      ('Listo', Icons.check),
    ];

    // En móvil el texto de los pasos no cabe: quedan solo los círculos
    // conectados, que siguen diciendo dónde estás.
    final compacto = MediaQuery.sizeOf(context).width < 520;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _isWideLayout ? 24 : 16,
        vertical: compacto ? 12 : 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _isWideLayout ? 660 : 440),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (index) {
              final (titulo, icono) = steps[index];
              final completado = index < _currentStep;
              final actual = index == _currentStep;

              return Expanded(
                flex: index == steps.length - 1 ? 0 : 1,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: completado
                                ? AppColors.primary
                                : actual
                                ? AppColors.primary.withValues(alpha: 0.10)
                                : AppColors.surfaceVariant,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: completado || actual
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: actual ? 2 : 1,
                            ),
                          ),
                          child: completado
                              ? const Icon(
                                  Icons.check,
                                  size: 15,
                                  color: Colors.white,
                                )
                              : Icon(
                                  icono,
                                  size: 14,
                                  color: actual
                                      ? AppColors.primary
                                      : AppColors.textLight,
                                ),
                        ),
                        if (!compacto) ...[
                          const SizedBox(height: 6),
                          Text(
                            titulo,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: actual
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: actual || completado
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 14,
                            left: 6,
                            right: 6,
                            bottom: compacto ? 0 : 22,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 2,
                            decoration: BoxDecoration(
                              color: index < _currentStep
                                  ? AppColors.primary
                                  : AppColors.border,
                              borderRadius: BorderRadius.circular(1),
                            ),
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

  /// Campo de texto con la estética del asistente: etiqueta propia encima,
  /// altura 56, radio 8 y el anillo de foco en azul corporativo.
  Widget _campo({
    required GlobalKey clave,
    required TextEditingController controller,
    required String etiqueta,
    required IconData icono,
    String? ayuda,
    String? pista,
    TextInputType? teclado,
    bool oscuro = false,
    VoidCallback? alternarOscuro,
    TextInputAction accionTeclado = TextInputAction.next,
    String? Function(String?)? validador,
    List<TextInputFormatter>? formateadores,
    void Function(String)? alCambiar,
    void Function(String)? alEnviar,
  }) {
    return Column(
      key: clave,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: 0.01,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: teclado,
          obscureText: oscuro,
          textInputAction: accionTeclado,
          inputFormatters: formateadores,
          validator: validador,
          onChanged: alCambiar,
          onFieldSubmitted: alEnviar,
          style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
          decoration: _decoracionCampo(
            icono: icono,
            pista: pista,
            ayuda: ayuda,
            sufijo: alternarOscuro == null
                ? null
                : IconButton(
                    icon: Icon(
                      oscuro
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                    color: AppColors.textSecondary,
                    tooltip: oscuro ? 'Mostrar' : 'Ocultar',
                    onPressed: alternarOscuro,
                  ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoracionCampo({
    required IconData icono,
    String? pista,
    String? ayuda,
    Widget? sufijo,
  }) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      isDense: true,
      hintText: pista,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.textLight),
      helperText: ayuda,
      helperMaxLines: 2,
      helperStyle: const TextStyle(
        fontSize: 11.5,
        height: 1.3,
        color: AppColors.textSecondary,
      ),
      prefixIcon: Icon(icono, size: 19, color: AppColors.textSecondary),
      suffixIcon: sufijo,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.6),
      ),
    );
  }

  /// Tarjeta blanca con borde fino y sombra suave: la unidad visual del
  /// asistente. Nada de `Card` con elevación por defecto.
  Widget _tarjeta({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1F2937),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Cabecera del paso: título, subtítulo y, si se pasa, una acción a la
  /// derecha. Es el mismo bloque en los cuatro pasos.
  Widget _cabeceraPaso({
    required String titulo,
    required String subtitulo,
    Widget? accion,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                titulo,
                style: TextStyle(
                  fontSize: _isWideLayout ? 26 : 22,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (accion != null) ...[const SizedBox(width: 12), accion],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitulo,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Tarjeta de valor del panel lateral (`solo en pantallas anchas`).
  Widget _panelLateral() {
    const beneficios = [
      (
        Icons.storefront_outlined,
        'Tu tienda con sus datos',
        'Nombre, dirección y ubicación en el mapa, listos para los tickets.',
      ),
      (
        Icons.inventory_2_outlined,
        'Almacenes y zonas',
        'Donde vive el inventario. Cada zona agrupa los productos.',
      ),
      (
        Icons.point_of_sale_outlined,
        'Cajas listas para vender',
        'Cada TPV descuenta del almacén que le asignes.',
      ),
      (
        Icons.groups_outlined,
        'Equipo con permisos',
        'Gerentes, supervisores, almaceneros y vendedores.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qué vas a conseguir',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              for (final (icono, titulo, detalle) in beneficios) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icono, size: 16, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detalle,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tiempo estimado: 3 minutos',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¿Primera vez? Pulsa el birrete de arriba y te lo explico '
                  'campo por campo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Medidor de fortaleza de la contraseña. No bloquea: informa.
  Widget _medidorPassword() {
    final valor = _passwordController.text;
    var fuerza = 0;
    if (valor.length >= 6) fuerza++;
    if (valor.length >= 10) fuerza++;
    if (RegExp(r'[A-Z]').hasMatch(valor) && RegExp(r'[0-9]').hasMatch(valor)) {
      fuerza++;
    }
    const etiquetas = ['Muy corta', 'Débil', 'Aceptable', 'Fuerte'];
    const colores = [
      AppColors.border,
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      AppColors.success,
    ];
    final indice = fuerza.clamp(0, 3);

    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              decoration: BoxDecoration(
                color: i < fuerza ? colores[indice] : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 4),
        ],
        const SizedBox(width: 10),
        Text(
          valor.isEmpty ? '' : etiquetas[indice],
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colores[indice],
          ),
        ),
      ],
    );
  }

  Widget _buildUserRegistrationStep() {
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho >= 1080;
    final margen = ancho >= 720 ? 32.0 : 16.0;

    final formulario = _tarjeta(
      child: Form(
        key: _userFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cabeceraPaso(
              titulo: 'Crea la cuenta del administrador',
              subtitulo:
                  'Serás el Dueño de la tienda: verás las ganancias y podrás '
                  'invitar a tu equipo después.',
            ),
            const SizedBox(height: 26),

            _campo(
              clave: _claveNombre,
              controller: _fullNameController,
              etiqueta: 'Nombre completo',
              icono: Icons.badge_outlined,
              pista: 'Ej: Ana Pérez',
              ayuda: 'Como quieres aparecer en la app y en los reportes.',
              validador: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Ingresa tu nombre completo';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            _campo(
              clave: _claveTelefono,
              controller: _phoneController,
              etiqueta: 'Teléfono de contacto',
              icono: Icons.phone_outlined,
              pista: 'Ej: +53 5555 1234',
              ayuda: 'Solo lo usamos para contactarte si hay un problema.',
              teclado: TextInputType.phone,
              validador: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Ingresa un número de teléfono';
                }
                if (valor.trim().length < 8) {
                  return 'Ingresa un número de teléfono válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            _campo(
              clave: _claveEmail,
              controller: _emailController,
              etiqueta: 'Email de acceso',
              icono: Icons.alternate_email,
              pista: 'tu@correo.com',
              ayuda:
                  'Con este correo entras a la app y recuperas la contraseña.',
              teclado: TextInputType.emailAddress,
              validador: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Ingresa tu email';
                }
                final email = valor.trim();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return 'Ingresa un email válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            _campo(
              clave: _clavePassword,
              controller: _passwordController,
              etiqueta: 'Contraseña',
              icono: Icons.lock_outline,
              pista: 'Mínimo 6 caracteres',
              oscuro: _obscurePassword,
              alternarOscuro: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              alCambiar: (_) => setState(() {}),
              validador: (valor) {
                if (valor == null || valor.isEmpty) {
                  return 'Ingresa una contraseña';
                }
                if (valor.length < 6) {
                  return 'La contraseña debe tener al menos 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            _medidorPassword(),
            const SizedBox(height: 18),

            _campo(
              clave: _claveConfirmPassword,
              controller: _confirmPasswordController,
              etiqueta: 'Confirmar contraseña',
              icono: Icons.lock_reset_outlined,
              pista: 'Repite la contraseña',
              oscuro: _obscureConfirm,
              alternarOscuro: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              accionTeclado: TextInputAction.done,
              validador: (valor) {
                if (valor != _passwordController.text) {
                  return 'Las contraseñas no coinciden';
                }
                return null;
              },
            ),
            const SizedBox(height: 26),

            // Atajo: la IA rellena todo esto y salta al resumen.
            Container(
              key: _claveAsistenteIa,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Crear tienda asistida (IA)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Describe tu negocio y preparamos almacenes, cajas y '
                          'personal. Lo revisas antes de crear nada.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _openAiStoreAssistant,
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Configurar con IA'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: dosColumnas
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: formulario),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: _panelLateral()),
                  ],
                )
              : formulario,
        ),
      ),
    );
  }

  Widget _buildStoreInfoStep() {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 720 ? 32.0 : 16.0;
    final dosColumnasMapa = ancho >= 1000;

    final campos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campo(
          clave: _claveNombreTienda,
          controller: _storeNameController,
          etiqueta: 'Nombre de la tienda',
          icono: Icons.storefront_outlined,
          pista: 'Ej: Mercado Central',
          ayuda: 'El nombre que verán tus clientes y tu equipo.',
          validador: (valor) {
            if (valor == null || valor.trim().isEmpty) {
              return 'Ingresa el nombre de la tienda';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        _campo(
          clave: _claveDireccion,
          controller: _storeAddressController,
          etiqueta: 'Dirección',
          icono: Icons.location_on_outlined,
          pista: 'Calle, número, referencia',
          ayuda: 'Sale en los tickets. Puedes afinarla en el mapa.',
          validador: (valor) {
            if (valor == null || valor.trim().isEmpty) {
              return 'Ingresa la dirección';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),

        // País → provincia → ciudad: cada uno carga el siguiente.
        Column(
          key: _clavePais,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _EtiquetaCampo('País, provincia y ciudad'),
            const SizedBox(height: 6),
            _buildLocationSelectorRow(
              isLoading: _loadingCountries,
              onReload: _reloadCountries,
              reloadTooltip: 'Recargar países',
              child: _loadingCountries && _countries.isEmpty
                  ? _locationLoadingIndicator()
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
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
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
                                  height: 20,
                                  width: 28,
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
                        dropdownSearchDecoration:
                            _decoracionCampo(
                              icono: Icons.public,
                              pista: 'Selecciona un país',
                            ).copyWith(
                              prefixIcon: _selectedCountry != null
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                      child: CountryFlag.fromCountryCode(
                                        _selectedCountry!['countryCode'] ?? '',
                                        height: 18,
                                        width: 26,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.public,
                                      size: 19,
                                      color: AppColors.textSecondary,
                                    ),
                            ),
                      ),
                      onChanged: (country) {
                        if (country != null) {
                          setState(() => _selectedCountry = country);
                          _loadStates(country['countryCode']);
                        }
                      },
                      validator: (value) {
                        if (value == null) return 'Selecciona un país';
                        return null;
                      },
                    ),
            ),
            const SizedBox(height: 12),
            _buildLocationSelectorRow(
              isLoading: _loadingStates,
              onReload: _selectedCountry != null ? _reloadStates : null,
              reloadTooltip: 'Recargar provincias',
              child: _selectedCountry == null
                  ? _locationPlaceholder('Selecciona un país primero')
                  : _loadingStates && _states.isEmpty
                  ? _locationLoadingIndicator()
                  : _states.isEmpty
                  ? _locationPlaceholder(
                      'Este país no tiene provincias registradas',
                    )
                  : DropdownSearch<Map<String, dynamic>>(
                      items: _states,
                      itemAsString: (item) => item['name'] ?? '',
                      selectedItem: _selectedState,
                      popupProps: PopupProps.menu(
                        showSearchBox: true,
                        searchFieldProps: const TextFieldProps(
                          decoration: InputDecoration(
                            hintText: 'Buscar provincia...',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
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
                                      color: AppColors.textSecondary,
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
                        dropdownSearchDecoration: _decoracionCampo(
                          icono: Icons.map_outlined,
                          pista: 'Selecciona una provincia',
                        ),
                      ),
                      validator: (value) {
                        if (_states.isNotEmpty && value == null) {
                          return 'Selecciona una provincia';
                        }
                        return null;
                      },
                      onChanged: (state) {
                        setState(() => _selectedState = state);
                        if (state != null && _selectedCountry != null) {
                          _loadCities(
                            _selectedCountry!['countryCode'],
                            state['adminCode1'] ?? '',
                          );
                        }
                      },
                    ),
            ),
            const SizedBox(height: 12),
            _buildLocationSelectorRow(
              isLoading: _loadingCities,
              onReload: _selectedState != null ? _reloadCities : null,
              reloadTooltip: 'Recargar ciudades',
              child: _selectedState == null
                  ? _locationPlaceholder('Selecciona una provincia primero')
                  : _loadingCities && _cities.isEmpty
                  ? _locationLoadingIndicator()
                  : _cities.isEmpty
                  ? _locationPlaceholder(
                      'No hay ciudades disponibles para esta provincia',
                    )
                  : DropdownSearch<Map<String, dynamic>>(
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
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
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
                                      color: AppColors.textSecondary,
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
                        dropdownSearchDecoration: _decoracionCampo(
                          icono: Icons.location_city_outlined,
                          pista: 'Selecciona una ciudad',
                        ),
                      ),
                      onChanged: (city) {
                        setState(() {
                          _selectedCity = city;
                          if (city != null) {
                            _storeLatitude =
                                double.tryParse(
                                  city['lat']?.toString() ?? '',
                                ) ??
                                _storeLatitude;
                            _storeLogitude =
                                double.tryParse(
                                  city['lng']?.toString() ?? '',
                                ) ??
                                _storeLogitude;
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
            ),
          ],
        ),
      ],
    );

    final mapa = KeyedSubtree(
      key: _claveMapa,
      child: _tarjeta(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.my_location,
                  size: 17,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 8),
                Text(
                  'Ubicación en el mapa',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Toca el mapa para mover el alfiler a tu puerta.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: dosColumnasMapa ? 380 : 260,
                child: _selectedCity == null && _storeLatitude == null
                    ? Container(
                        color: AppColors.surfaceVariant,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 40,
                                color: AppColors.textLight,
                              ),
                              SizedBox(height: 10),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Elige una ciudad y aquí aparece el mapa',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildMapPreview(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _storeLatitude == null || _storeLogitude == null
                        ? 'Sin coordenadas todavía'
                        : '${_storeLatitude!.toStringAsFixed(5)}, '
                              '${_storeLogitude!.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (_storeLatitude != null)
                  TextButton(
                    onPressed: () {
                      final city = _selectedCity;
                      if (city == null) return;
                      setState(() {
                        _storeLatitude = double.tryParse(
                          city['lat']?.toString() ?? '',
                        );
                        _storeLogitude = double.tryParse(
                          city['lng']?.toString() ?? '',
                        );
                      });
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Centrar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Form(
            key: _storeFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cabeceraPaso(
                  titulo: 'Datos de la tienda',
                  subtitulo:
                      'Dónde está y cómo se llama. La dirección sale impresa '
                      'en los tickets.',
                ),
                const SizedBox(height: 24),
                if (dosColumnasMapa)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: _tarjeta(child: campos)),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: mapa),
                    ],
                  )
                else ...[
                  _tarjeta(child: campos),
                  const SizedBox(height: 16),
                  mapa,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionalDataStep() {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final margen = MediaQuery.sizeOf(context).width >= 720 ? 32.0 : 16.0;

    Widget campos() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cabeceraPaso(
          titulo: 'Configura tu operación',
          subtitulo:
              'Dónde guardas la mercancía, con qué cobras y quién trabaja '
              'contigo. Puedes ajustarlo después desde Configuración.',
        ),
        const SizedBox(height: 16),
        // Aviso explícito de que este paso ya no bloquea. Antes exigía TPV,
        // almacén, zona y personal para dejar continuar; ese muro es justo el
        // que hacía abandonar el alta. Ahora es opcional y lo que falte se
        // resuelve desde el checklist de activación.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Todo esto es opcional. Si prefieres empezar con lo mínimo, '
                  'puedes continuar sin rellenarlo: lo que falte aparecerá en '
                  'tu checklist de activación.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Almacenes con sus zonas anidándose en la misma tarjeta.
        KeyedSubtree(
          key: _claveAlmacenes,
          child: _buildAlmacenesConLayoutsSection(),
        ),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: _claveTpvs,
                  child: _buildSectionCard(
                    title: 'TPVs (cajas)',
                    icon: Icons.point_of_sale_outlined,
                    count: _tpvData.length,
                    items: _tpvData,
                    onAdd: _showAddTPVDialog,
                    onEdit: (index) => _showEditTPVDialog(index),
                    onDelete: (index) => _deleteTPV(index),
                    required: true,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KeyedSubtree(
                  key: _clavePersonal,
                  child: _buildSectionCard(
                    title: 'Personal',
                    icon: Icons.groups_outlined,
                    count: _personalData.length,
                    items: _personalData,
                    onAdd: _showAddPersonalDialog,
                    onEdit: (index) => _showEditPersonalDialog(index),
                    onDelete: (index) => _deletePersonal(index),
                    required: true,
                  ),
                ),
              ),
            ],
          )
        else ...[
          KeyedSubtree(
            key: _claveTpvs,
            child: _buildSectionCard(
              title: 'TPVs (cajas)',
              icon: Icons.point_of_sale_outlined,
              count: _tpvData.length,
              items: _tpvData,
              onAdd: _showAddTPVDialog,
              onEdit: (index) => _showEditTPVDialog(index),
              onDelete: (index) => _deleteTPV(index),
              required: true,
            ),
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _clavePersonal,
            child: _buildSectionCard(
              title: 'Personal',
              icon: Icons.groups_outlined,
              count: _personalData.length,
              items: _personalData,
              onAdd: _showAddPersonalDialog,
              onEdit: (index) => _showEditPersonalDialog(index),
              onDelete: (index) => _deletePersonal(index),
              required: true,
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: campos(),
        ),
      ),
    );
  }

  List<MapEntry<int, Map<String, dynamic>>> _layoutsEntriesForAlmacen(
    String nombreAlmacen,
  ) {
    final entries = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < _layoutsData.length; i++) {
      if ((_layoutsData[i]['almacen_asignado'] ?? '').toString() ==
          nombreAlmacen) {
        entries.add(MapEntry(i, _layoutsData[i]));
      }
    }
    return entries;
  }

  Widget _buildAlmacenesConLayoutsSection() {
    final wide = _isWideLayout;
    final hasMissingLayouts = _almacenesData.any((almacen) {
      final nombre = (almacen['denominacion'] ?? '').toString();
      return !_layoutsData.any(
        (layout) => (layout['almacen_asignado'] ?? '').toString() == nombre,
      );
    });
    final alerta = _almacenesData.isEmpty || hasMissingLayouts;

    return _tarjeta(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warehouse_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Almacenes y zonas',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: alerta
                      ? AppColors.error.withValues(alpha: 0.08)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: alerta
                      ? Border.all(
                          color: AppColors.error.withValues(alpha: 0.25),
                        )
                      : null,
                ),
                child: Text(
                  _almacenesData.isEmpty
                      ? 'REQUERIDO'
                      : hasMissingLayouts
                      ? 'FALTAN ZONAS'
                      : '${_almacenesData.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: alerta ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _showAddAlmacenDialog,
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Agregar almacén',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(34, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Un almacén es donde guardas la mercancía. Cada uno necesita al '
            'menos una zona.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (_almacenesData.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Todavía no hay almacenes. Usa el + para añadir el primero.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final useGrid = wide && constraints.maxWidth >= 640;
                final cardWidth = useGrid
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: List.generate(_almacenesData.length, (index) {
                    return SizedBox(
                      width: cardWidth,
                      child: _buildAlmacenConLayoutsCard(index),
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAlmacenConLayoutsCard(int almacenIndex) {
    final almacen = _almacenesData[almacenIndex];
    final nombreAlmacen = (almacen['denominacion'] ?? '').toString();
    final layouts = _layoutsEntriesForAlmacen(nombreAlmacen);
    final tieneLayouts = layouts.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tieneLayouts
              ? Colors.blue.withOpacity(0.25)
              : Colors.orange.withOpacity(0.6),
          width: tieneLayouts ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreAlmacen.isEmpty ? 'Sin nombre' : nombreAlmacen,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if ((almacen['direccion'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      Text(
                        almacen['direccion'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    if ((almacen['ubicacion'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      Text(
                        almacen['ubicacion'].toString(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEditAlmacenDialog(almacenIndex),
                icon: const Icon(Icons.edit, size: 20),
                color: Colors.blue,
                tooltip: 'Editar almacén',
              ),
              IconButton(
                onPressed: () => _deleteAlmacen(almacenIndex),
                icon: const Icon(Icons.delete, size: 20),
                color: Colors.red,
                tooltip: 'Eliminar almacén',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.grid_view, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Layouts/Zonas (${layouts.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _showAddLayoutDialog(preselectedAlmacen: nombreAlmacen),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Zona'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (!tieneLayouts)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.35)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Debes agregar al menos un layout/zona en este almacén.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            )
          else
            ...layouts.map((entry) {
              final layoutIndex = entry.key;
              final layout = entry.value;
              return Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            layout['denominacion']?.toString() ?? 'Sin nombre',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${layout['tipo_nombre'] ?? 'Zona'} · Código: ${layout['sku_codigo'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showEditLayoutDialog(layoutIndex),
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.blue,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => _deleteLayout(layoutIndex),
                      icon: const Icon(Icons.delete, size: 18),
                      color: Colors.red,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Tarjeta de una colección (TPVs, personal): cabecera con icono, contador y
  /// botón de alta, y una fila por elemento. Misma piel que el resto del
  /// asistente: borde fino, radio 12 y cero elevación.
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
    final falta = required && count == 0;

    return _tarjeta(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (falta)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Text(
                    'REQUERIDO',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Agregar',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(34, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Todavía no hay ${title.toLowerCase()}. Usa el + para añadir.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            for (final entry in items.asMap().entries)
              _filaElemento(
                item: entry.value,
                onEdit: () => onEdit(entry.key),
                onDelete: () => onDelete(entry.key),
              ),
        ],
      ),
    );
  }

  /// Fila de un TPV o de una persona. El usuario principal no se edita ni se
  /// borra: se marca como Dueño.
  Widget _filaElemento({
    required Map<String, dynamic> item,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final esPrincipal = item['is_main_user'] == true;
    final titulo =
        item['denominacion'] ??
        '${item['nombres'] ?? ''} ${item['apellidos'] ?? ''}'.trim();
    final detalles = <String>[
      if (item['direccion'] != null) item['direccion'].toString(),
      if (item['tipo_rol'] != null) 'Rol: ${item['tipo_rol']}',
      if (item['almacen_asignado'] != null && item['tipo_rol'] == 'almacenero')
        'Almacén: ${item['almacen_asignado']}',
      if (item['tpv_asignado'] != null && item['tipo_rol'] == 'vendedor')
        'TPV: ${item['tpv_asignado']}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: esPrincipal
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: esPrincipal
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        titulo.isEmpty ? 'Sin nombre' : titulo,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (esPrincipal) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'DUEÑO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (detalles.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalles.join(' · '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!esPrincipal)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textSecondary,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 17),
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.error,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Fila «etiqueta : valor» del resumen. Sin adornos: solo jerarquía.
  Widget _filaResumen(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor.trim().isEmpty ? '—' : valor,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bloque del resumen: cabecera con icono y las filas de esa sección.
  Widget _bloqueResumen({
    required IconData icono,
    required String titulo,
    required List<Widget> hijos,
    Widget? pie,
  }) {
    return _tarjeta(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...hijos,
          if (pie != null) ...[const SizedBox(height: 10), pie],
        ],
      ),
    );
  }

  Widget _buildConfirmationStep() {
    final wide = MediaQuery.sizeOf(context).width >= 1080;
    final margen = MediaQuery.sizeOf(context).width >= 720 ? 32.0 : 16.0;

    final personal = _personalData.isEmpty
        ? const Text(
            'Sin personal configurado',
            style: TextStyle(fontSize: 12.5, color: AppColors.warning),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in _personalData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: AppColors.textLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${p['nombres'] ?? ''} ${p['apellidos'] ?? ''}'
                          ' · ${p['tipo_rol'] ?? ''}'
                          '${p['is_main_user'] == true ? ' (tú, Dueño)' : ''}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );

    final almacenes = _almacenesData.isEmpty
        ? const Text(
            'Sin almacenes',
            style: TextStyle(fontSize: 12.5, color: AppColors.warning),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in _almacenesData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a['denominacion']?.toString() ?? 'Almacén',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      for (final l in _layoutsData.where(
                        (l) =>
                            (l['almacen_asignado'] ?? '').toString() ==
                            (a['denominacion'] ?? '').toString(),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 2),
                          child: Text(
                            '↳ ${l['denominacion']} · ${l['sku_codigo'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );

    final resumen = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cabeceraPaso(
          titulo: 'Revisa antes de crear',
          subtitulo:
              'Si algo no cuadra, vuelve con «Anterior». Al crear, se crea el '
              'usuario, la tienda, sus almacenes y sus cajas de una vez.',
        ),
        const SizedBox(height: 24),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _bloqueResumen(
                      icono: Icons.person_outline,
                      titulo: 'Tu cuenta (Dueño)',
                      hijos: [
                        _filaResumen('Nombre', _fullNameController.text),
                        _filaResumen('Teléfono', _phoneController.text),
                        _filaResumen('Email', _emailController.text),
                      ],
                      pie: const Text(
                        'Entrarás como Dueño: ves las ganancias y gestionas el '
                        'equipo.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _bloqueResumen(
                      icono: Icons.storefront_outlined,
                      titulo: 'La tienda',
                      hijos: [
                        _filaResumen('Nombre', _storeNameController.text),
                        _filaResumen('Dirección', _storeAddressController.text),
                        _filaResumen(
                          'País',
                          _selectedCountry?['countryName']?.toString() ?? '—',
                        ),
                        _filaResumen(
                          'Provincia',
                          _selectedState?['name']?.toString() ?? '—',
                        ),
                        _filaResumen(
                          'Ciudad',
                          _selectedCity?['name']?.toString() ?? '—',
                        ),
                        _filaResumen(
                          'Coordenadas',
                          _storeLatitude == null || _storeLogitude == null
                              ? 'Sin ubicar en el mapa'
                              : '${_storeLatitude!.toStringAsFixed(5)}, '
                                    '${_storeLogitude!.toStringAsFixed(5)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _bloqueResumen(
                      icono: Icons.warehouse_outlined,
                      titulo: 'Almacenes y zonas (${_almacenesData.length})',
                      hijos: [almacenes],
                    ),
                    const SizedBox(height: 16),
                    _bloqueResumen(
                      icono: Icons.point_of_sale_outlined,
                      titulo: 'TPVs (${_tpvData.length})',
                      hijos: [
                        if (_tpvData.isEmpty)
                          const Text(
                            'Sin cajas',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.warning,
                            ),
                          )
                        else
                          for (final t in _tpvData)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${t['denominacion']} · '
                                '${t['almacen_asignado'] ?? 'sin almacén'}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _bloqueResumen(
                      icono: Icons.groups_outlined,
                      titulo: 'Personal (${_personalData.length})',
                      hijos: [personal],
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _bloqueResumen(
                icono: Icons.person_outline,
                titulo: 'Tu cuenta (Dueño)',
                hijos: [
                  _filaResumen('Nombre', _fullNameController.text),
                  _filaResumen('Teléfono', _phoneController.text),
                  _filaResumen('Email', _emailController.text),
                ],
              ),
              const SizedBox(height: 12),
              _bloqueResumen(
                icono: Icons.storefront_outlined,
                titulo: 'La tienda',
                hijos: [
                  _filaResumen('Nombre', _storeNameController.text),
                  _filaResumen('Dirección', _storeAddressController.text),
                  _filaResumen(
                    'Ciudad',
                    _selectedCity?['name']?.toString() ?? '—',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _bloqueResumen(
                icono: Icons.warehouse_outlined,
                titulo: 'Almacenes y zonas (${_almacenesData.length})',
                hijos: [almacenes],
              ),
              const SizedBox(height: 12),
              _bloqueResumen(
                icono: Icons.point_of_sale_outlined,
                titulo:
                    'TPVs (${_tpvData.length}) · '
                    'Personal (${_personalData.length})',
                hijos: [personal],
              ),
            ],
          ),
        if (_isLoading) ...[
          const SizedBox(height: 24),
          const Center(
            child: Column(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(height: 12),
                Text(
                  'Creando tu tienda...',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: KeyedSubtree(key: _claveResumen, child: resumen),
        ),
      ),
    );
  }

  Widget _buildModernNavigationButtons() {
    final ancho = MediaQuery.sizeOf(context).width;
    final esUltimo = _currentStep == 3;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ancho >= 720 ? 32 : 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  if (_currentStep > 0 && ancho >= 480) ...[
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _previousStep,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Anterior'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: SizedBox(
                          key: esUltimo ? _claveBotonSiguiente : null,
                          height: 48,
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _nextStep,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    esUltimo
                                        ? Icons.check
                                        : Icons.arrow_forward,
                                    size: 18,
                                  ),
                            label: Text(
                              _isLoading
                                  ? 'Procesando...'
                                  : esUltimo
                                  ? 'Guardar y continuar'
                                  : 'Siguiente',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

  /// Avanza de paso.
  ///
  /// Desde la fase 2 del plan `alta-tienda-progresiva-go-live.md` el paso 1
  /// **crea la tienda en borrador** en vez de solo validar: a partir de ahí el
  /// Dueño existe y puede entrar cuando quiera, aunque abandone el asistente.
  Future<void> _nextStep() async {
    if (_currentStep == 0) {
      await _crearBorradorYDecidir();
      return;
    }

    if (_currentStep < 3) {
      if (!_validateCurrentStep()) return;

      // El paso 2 persiste lo que haya antes de pasar al 3: el nombre, la
      // dirección y la ubicación se pierden si el cliente cierra la app y la
      // tienda ya existe en la base.
      if (_currentStep == 1) {
        await _guardarAvanceParcial();
        if (!mounted) return;
      }

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
    } else {
      _crearEstructuraRestante();
    }
  }

  /// Paso 1 → crea usuario + tienda en borrador y ofrece las dos salidas.
  ///
  /// Es el punto crítico del alta progresiva: se pide lo mínimo (la cuenta) y
  /// se le devuelve al cliente la decisión de seguir o irse. Las dos opciones
  /// son honestas porque la tienda ya existe: no se pierde nada si elige
  /// «Entrar a la app».
  Future<void> _crearBorradorYDecidir() async {
    if (!(_userFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final resultado = await _registrationService
          .registrarUsuarioYCrearBorrador(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _fullNameController.text.trim(),
          );

      if (!mounted) return;

      if (resultado['success'] != true) {
        _showErrorDialog(resultado['message'] ?? 'No se pudo crear la tienda.');
        return;
      }

      // El usuario recién creado queda autenticado; se refleja en preferencias
      // para que el resto de la app (y el arranque en frío) sepa en qué tienda
      // está. Sin esto, «Entrar a la app» aterrizaría sin tienda activa.
      final tiendaId = resultado['tienda_id'];
      final userId = (resultado['user'] as User?)?.id;
      if (tiendaId is int) {
        // Los pasos 2-4 completan **esta** tienda; sin el id en memoria,
        // `_guardarAvanceParcial` no tendría dónde escribir.
        _tiendaIdBorrador = tiendaId;
      }
      if (tiendaId is int && userId != null) {
        try {
          await _userPreferencesService.saveUserData(
            userId: userId,
            email: _emailController.text.trim(),
            accessToken:
                Supabase.instance.client.auth.currentSession?.accessToken ?? '',
            adminName: _fullNameController.text.trim(),
            adminRole: 'Dueño',
            idTienda: tiendaId,
            userStores: [
              {
                'id_tienda': tiendaId,
                'id': tiendaId,
                'denominacion':
                    (resultado['denominacion'] ?? 'Mi tienda').toString(),
              },
            ],
          );
          await _userPreferencesService.saveUserRolesByStore({
            tiendaId: 'Dueño',
          });
        } catch (e) {
          // No es fatal: el login reconstruye las preferencias.
          print('⚠️ No se pudieron guardar las preferencias del alta: $e');
        }
      }

      if (!mounted) return;
      await _mostrarDialogoPrimerPaso();
    } catch (e) {
      if (mounted) {
        _showErrorDialog('No se pudo crear tu cuenta: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Diálogo con las dos salidas del paso 1.
  Future<void> _mostrarDialogoPrimerPaso() async {
    final seguirConfigurando = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Tu cuenta está lista',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Ya tienes tu usuario y tu tienda. Todavía no puede vender: le '
            'faltan la caja, el catálogo y el equipo.\n\n'
            'Puedes configurarla ahora, paso a paso, o entrar a la app y '
            'dejarlo para después. Tu avance se guarda igual.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Configurar mi tienda ahora'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Entrar a la app'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (seguirConfigurando == true) {
      setState(() => _currentStep = 1);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    // «Entrar a la app»: al checklist, que es donde se ve lo que falta.
    Navigator.pushReplacementNamed(context, '/activacion');
  }

  /// Guarda lo que haya del paso 2 sin bloquear por campos vacíos.
  ///
  /// La tienda ya existe desde el paso 1, así que aquí no se crea nada: se
  /// escribe encima lo que el usuario haya rellenado. Se hace con un `update`
  /// directo a `app_dat_tienda` en vez de añadir otro método al servicio de
  /// registro porque es una sola fila y tres columnas; el servicio de registro
  /// se reserva para lo que crea estructura (RPC).
  ///
  /// **Nunca toca `estado`**: esa columna guarda el código de provincia
  /// geográfico, no el estado de la tienda.
  Future<void> _guardarAvanceParcial() async {
    final tiendaId = _tiendaIdBorrador;
    if (tiendaId == null) {
      // Sin id (alta antigua o preferencias limpias) no hay dónde escribir.
      return;
    }

    final nombre = _storeNameController.text.trim();
    final direccion = _storeAddressController.text.trim();
    final ubicacion = _ubicacionTexto();

    // Solo las columnas que de verdad se tocaron: escribir nulos encima de lo
    // que ya hay borraría datos buenos por no haber pasado por el campo.
    final cambios = <String, dynamic>{};
    if (nombre.isNotEmpty) cambios['denominacion'] = nombre;
    if (direccion.isNotEmpty) cambios['direccion'] = direccion;
    if (ubicacion != null && ubicacion.isNotEmpty) {
      cambios['ubicacion'] = ubicacion;
    }
    if (_selectedCountry != null) {
      cambios['pais'] = _selectedCountry!['countryCode'];
      cambios['nombre_pais'] = _selectedCountry!['countryName'];
    }
    if (_selectedState != null) {
      cambios['estado'] = _selectedState!['adminCode1'];
      cambios['nombre_estado'] = _selectedState!['name'];
    }
    if (_storeLatitude != null) cambios['latitude'] = _storeLatitude;
    if (_storeLogitude != null) cambios['longitude'] = _storeLogitude;

    if (cambios.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('app_dat_tienda')
          .update(cambios)
          .eq('id', tiendaId);
      print('💾 Avance parcial guardado en la tienda $tiendaId: $cambios');
    } catch (e) {
      // Guardar a medias no debe impedir seguir: el usuario está en el
      // asistente y lo que ha escrito sigue en pantalla.
      print('⚠️ No se pudo guardar el avance parcial: $e');
    }
  }

  /// Texto de ubicación: coordenadas si hay mapa, si no lo que se escribió.
  String? _ubicacionTexto() {
    if (_storeLatitude != null && _storeLogitude != null) {
      return '${_storeLatitude!.toStringAsFixed(6)},'
          '${_storeLogitude!.toStringAsFixed(6)}';
    }
    final texto = _storeLocationController.text.trim();
    return texto.isEmpty ? null : texto;
  }

  /// Paso 3 → crea lo que falte (almacenes, zonas, TPVs, personal) sobre la
  /// tienda que ya existe.
  ///
  /// Ya no se llama a `registerUserAndCreateStore`: eso insertaría una segunda
  /// tienda, porque la del paso 1 ya está creada.
  Future<void> _crearEstructuraRestante() async {
    final tiendaId = _tiendaIdBorrador;
    if (tiendaId == null) {
      _showErrorDialog(
        'No se encontró la tienda que se creó al principio. '
        'Vuelve a iniciar sesión y continúa desde el checklist.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final resultado = await _registrationService.completarTiendaBorrador(
        idTienda: tiendaId,
        almacenesData: _almacenesData.isEmpty ? null : _almacenesData,
        layoutsData: _layoutsData.isEmpty ? null : _layoutsData,
        tpvData: _tpvData.isEmpty ? null : _tpvData,
        personalData: _personalData.isEmpty ? null : _personalData,
      );

      if (!mounted) return;

      final errores = (resultado['errores'] as List?) ?? const [];
      if (errores.isEmpty) {
        _showSuccessDialog(userAlreadyExisted: false);
        return;
      }

      // Éxito parcial: se celebra lo guardado y se listan los fallos. Perder
      // un TPV no debe ocultar que el almacén sí se creó.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Guardado con pendientes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Almacenes: ${resultado['almacenes_creados']} · '
                  'Cajas: ${resultado['tpvs_creados']} · '
                  'Personal: ${resultado['personal_creado']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                for (final error in errores)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• $error',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Puedes arreglarlo desde la app, en Configuración.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/activacion');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('No se pudo completar la tienda: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// `_validateCurrentStep` del asistente progresivo.
  ///
  /// El único paso obligatorio es el 1. A partir de ahí:
  ///
  /// - Paso 2 (datos de tienda): **no bloquea**. Si hay algo escrito se valida
  ///   el formato de los campos rellenados; vacío se permite pasar, porque la
  ///   tienda ya existe y el nombre/dirección se pueden completar después.
  /// - Paso 3 (operación): **no bloquea**. TPV, almacén, zona y personal pasan
  ///   de requisitos a avisos: son justo los pasos que hacían abandonar el alta
  ///   y ahora viven en el checklist de activación.
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _userFormKey.currentState?.validate() ?? false;
      case 1:
        // Validar solo si el usuario escribió algo: un formulario vacío no
        // tiene errores que mostrar y bloquearlo sería volver al alta de antes.
        final hayDatos = _storeNameController.text.trim().isNotEmpty ||
            _storeAddressController.text.trim().isNotEmpty ||
            _storeLocationController.text.trim().isNotEmpty;
        if (!hayDatos) return true;
        return _storeFormKey.currentState?.validate() ?? true;
      case 2:
        // Los avisos siguen en la UI (cada sección tiene su `required: true`
        // y las tarjetas dicen qué falta), pero ya no impiden avanzar.
        return true;
      case 3:
        return true; // Confirmación
      default:
        return false;
    }
  }

  /// Alta completa desde el asistente de IA.
  ///
  /// El plan de IA rellena todos los pasos de golpe, así que no tiene sentido
  /// obligar a pasar por el diálogo del paso 1. Pero **sí** hay que pasar por
  /// las dos mismas fases que el flujo manual: primero la tienda en borrador,
  /// después su estructura. Antes este método llamaba a
  /// `registerUserAndCreateStore`, que inserta una tienda nueva: con el paso 1
  /// creando ya el borrador, habría dejado dos tiendas por alta.
  Future<void> _createStore() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Alta desde el asistente de IA...');

      final tiendaId = _tiendaIdBorrador;
      if (tiendaId == null) {
        // Sin borrador previo (el usuario no pasó por el paso 1) se crea ahora.
        final borrador = await _registrationService
            .registrarUsuarioYCrearBorrador(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              fullName: _fullNameController.text.trim(),
            );

        if (!mounted) return;

        if (borrador['success'] != true) {
          _showErrorDialog(
            borrador['message'] ?? 'No se pudo crear la tienda.',
          );
          return;
        }

        final creado = borrador['tienda_id'];
        if (creado is! int) {
          _showErrorDialog(
            'La tienda se creó pero no se recibió su identificador. '
            'Entra a la app: aparecerá en tu checklist de activación.',
          );
          return;
        }
        _tiendaIdBorrador = creado;
      }

      final idTienda = _tiendaIdBorrador;
      if (idTienda == null) {
        _showErrorDialog('No se pudo determinar la tienda recién creada.');
        return;
      }

      // El nombre y la ubicación que propuso la IA se guardan antes de añadir
      // la estructura: el borrador nació con un nombre provisional.
      await _guardarAvanceParcial();
      if (!mounted) return;

      final resultado = await _registrationService.completarTiendaBorrador(
        idTienda: idTienda,
        almacenesData: _almacenesData.isEmpty ? null : _almacenesData,
        layoutsData: _layoutsData.isEmpty ? null : _layoutsData,
        tpvData: _tpvData.isEmpty ? null : _tpvData,
        personalData: _personalData.isEmpty ? null : _personalData,
      );

      if (!mounted) return;

      final errores = (resultado['errores'] as List?) ?? const [];
      if (errores.isEmpty) {
        _showSuccessDialog();
        return;
      }

      _showErrorDialog(
        'Se guardó casi todo, pero quedó pendiente:\n\n'
        '${errores.map((e) => '• $e').join('\n')}\n\n'
        'Puedes completarlo desde Configuración.',
      );
    } catch (e) {
      if (mounted) _showErrorDialog('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog({bool userAlreadyExisted = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Tu tienda está lista',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userAlreadyExisted
                    ? 'Guardamos la configuración de tu tienda. Tu usuario ya '
                          'existía: lo vinculamos como Dueño de esta tienda.'
                    : 'Guardamos la configuración de tu tienda. Todavía puedes '
                          'ajustar lo que falte desde la app.',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Entras como Dueño',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Eso significa que ves las ganancias y puedes '
                            'asignar el rol Dueño a otra persona. Los demás '
                            'roles operan sin ver esas cifras.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.95,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cerrar diálogo
                // El usuario ya está autenticado y su tienda existe: mandarlo
                // al login le obligaría a escribir la contraseña otra vez sin
                // motivo. Al checklist, que es donde se ve lo que falta.
                Navigator.pushReplacementNamed(context, '/activacion');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Ir a poner en marcha mi tienda'),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No se pudo continuar',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                items: _almacenesData.map((almacen) {
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar TPV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nombre del TPV'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedAlmacen,
                decoration: const InputDecoration(
                  labelText: 'Almacén Asignado',
                ),
                items: _almacenesData.map((almacen) {
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
                    _tpvData[index]['denominacion'] = nameController.text
                        .trim();
                    _tpvData[index]['almacen_asignado'] = selectedAlmacen;
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
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
                final oldName = (_almacenesData[index]['denominacion'] ?? '')
                    .toString();
                final newName = nameController.text.trim();
                setState(() {
                  _almacenesData[index]['denominacion'] = newName;
                  _almacenesData[index]['direccion'] = addressController.text
                      .trim();
                  _almacenesData[index]['ubicacion'] = locationController.text
                      .trim();

                  // Mantener relaciones por nombre al renombrar
                  if (oldName != newName) {
                    for (final layout in _layoutsData) {
                      if ((layout['almacen_asignado'] ?? '').toString() ==
                          oldName) {
                        layout['almacen_asignado'] = newName;
                      }
                    }
                    for (final tpv in _tpvData) {
                      if ((tpv['almacen_asignado'] ?? '').toString() ==
                          oldName) {
                        tpv['almacen_asignado'] = newName;
                      }
                    }
                    for (final personal in _personalData) {
                      if ((personal['almacen_asignado'] ?? '').toString() ==
                          oldName) {
                        personal['almacen_asignado'] = newName;
                      }
                    }
                  }
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
    final nombre = (_almacenesData[index]['denominacion'] ?? '').toString();
    final layoutsAsociados = _layoutsData
        .where((l) => (l['almacen_asignado'] ?? '').toString() == nombre)
        .length;
    final tpvsAsociados = _tpvData
        .where((t) => (t['almacen_asignado'] ?? '').toString() == nombre)
        .length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Almacén'),
        content: Text(
          layoutsAsociados > 0 || tpvsAsociados > 0
              ? '¿Eliminar "$nombre"? También se eliminarán $layoutsAsociados zona(s) y se desasignarán $tpvsAsociados TPV(s) vinculados.'
              : '¿Estás seguro de eliminar "$nombre"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _layoutsData.removeWhere(
                  (l) => (l['almacen_asignado'] ?? '').toString() == nombre,
                );
                for (final tpv in _tpvData) {
                  if ((tpv['almacen_asignado'] ?? '').toString() == nombre) {
                    tpv['almacen_asignado'] = null;
                  }
                }
                for (final personal in _personalData) {
                  if ((personal['almacen_asignado'] ?? '').toString() ==
                      nombre) {
                    personal['almacen_asignado'] = null;
                  }
                }
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    hintText: 'Email del empleado para acceso al sistema',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    hintText: 'Contraseña de acceso (mínimo 6 caracteres)',
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
                    items: _almacenesData.map((almacen) {
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
                    items: _tpvData.map((tpv) {
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
                if (selectedRole == 'almacenero' && _almacenesData.isEmpty)
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
                      const SnackBar(content: Text('Ingresa un email válido')),
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
                  canAdd = canAdd && selectedTPV != null && _tpvData.isNotEmpty;
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
                      personalItem['almacen_asignado'] = selectedAlmacen;
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Personal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombresController,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: apellidosController,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
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
                      const SnackBar(content: Text('Ingresa un email válido')),
                    );
                    return;
                  }

                  // Verificar que el email no esté duplicado (excepto el actual)
                  final emailExists = _personalData.asMap().entries.any(
                    (entry) =>
                        entry.key != index &&
                        entry.value['email'] == emailController.text.trim(),
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
                    _personalData[index]['nombres'] = nombresController.text
                        .trim();
                    _personalData[index]['apellidos'] = apellidosController.text
                        .trim();
                    _personalData[index]['email'] = emailController.text.trim();
                    _personalData[index]['tipo_rol'] = selectedRole;
                    _personalData[index]['id_roll'] = _getRoleId(selectedRole!);
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
      builder: (context) => AlertDialog(
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

  // Agrega automáticamente al usuario principal como Dueño (y como Gerente y
  // Supervisor, para que las RPC históricas que comprueban esos roles lo
  // autoricen). El Dueño lo escribe la RPC; aquí solo se refleja en la lista.
  void _addMainUserToPersonal() {
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) return;

    // Separar nombres y apellidos (simple split por espacio)
    final nameParts = fullName.split(' ');
    final nombres = nameParts.isNotEmpty ? nameParts.first : 'Usuario';
    final apellidos = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : 'Principal';

    // Verificar si ya existe el usuario principal para evitar duplicados
    final existingMainUser = _personalData
        .where((p) => p['is_main_user'] == true)
        .toList();
    if (existingMainUser.isNotEmpty) {
      return; // Ya existe, no agregar duplicados
    }

    final principal = {
      'nombres': nombres,
      'apellidos': apellidos,
      'email': _emailController.text.trim(),
      'password': _passwordController.text,
      'tipo_rol': 'gerente',
      'id_roll': 1,
      'uuid': 'MAIN_USER_UUID', // Se reemplaza con el UUID real
      'is_main_user': true,
      'is_editable': false,
    };

    final supervisorItem = {
      'nombres': nombres,
      'apellidos': apellidos,
      'email': _emailController.text.trim(),
      'password': _passwordController.text,
      'tipo_rol': 'supervisor',
      'id_roll': 2,
      'uuid': 'MAIN_USER_UUID',
      'is_main_user': true,
      'is_editable': false,
    };

    setState(() {
      _personalData.insert(0, principal);
      _personalData.insert(1, supervisorItem);
    });

    print('✅ Usuario principal agregado como Dueño, Gerente y Supervisor');
    print('   - Nombres: $nombres');
    print('   - Apellidos: $apellidos');
  }

  // ===== MÉTODOS PARA LAYOUTS =====
  void _showAddLayoutDialog({String? preselectedAlmacen}) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    String? selectedAlmacen = preselectedAlmacen;
    int? selectedTipoLayout;
    List<Map<String, dynamic>> layoutTypes = [];
    bool loadingTypes = true;
    final lockAlmacen =
        preselectedAlmacen != null && preselectedAlmacen.trim().isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
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
            title: Text(
              lockAlmacen
                  ? 'Agregar zona en $preselectedAlmacen'
                  : 'Agregar Layout/Zona',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lockAlmacen
                        ? 'Crea una zona dentro de este almacén para organizar los productos.'
                        : 'Crea una zona dentro del almacén para organizar los productos.',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                      isExpanded: true,
                      items: layoutTypes.map((tipo) {
                        return DropdownMenuItem<int?>(
                          value: tipo['id'],
                          child: Text(
                            tipo['denominacion'] ?? 'Sin nombre',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedTipoLayout = value;
                        });
                      },
                    ),
                  const SizedBox(height: 16),
                  if (lockAlmacen)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Almacén',
                        prefixIcon: Icon(Icons.warehouse),
                      ),
                      child: Text(
                        selectedAlmacen ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedAlmacen,
                      decoration: const InputDecoration(
                        labelText: 'Almacén Asignado',
                      ),
                      isExpanded: true,
                      items: _almacenesData.map((almacen) {
                        return DropdownMenuItem<String>(
                          value: almacen['denominacion'],
                          child: Text(
                            almacen['denominacion'],
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedAlmacen = value;
                        });
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
                        // `sku_codigo` y no `codigo`: es la clave que lee
                        // `item_json->>'sku_codigo'` en la RPC.
                        'sku_codigo': codeController.text.trim(),
                        'almacen_asignado': selectedAlmacen,
                        'id_tipo_layout': selectedTipoLayout,
                        'id_layout_padre': null,
                        'tipo_nombre': layoutTypes.firstWhere(
                          (t) => t['id'] == selectedTipoLayout,
                          orElse: () => {'denominacion': 'Desconocido'},
                        )['denominacion'],
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
    final codeController = TextEditingController(text: layout['sku_codigo']);
    String? selectedAlmacen = layout['almacen_asignado'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                items: _almacenesData.map((almacen) {
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
                    _layoutsData[index]['denominacion'] = nameController.text
                        .trim();
                    _layoutsData[index]['sku_codigo'] = codeController.text
                        .trim();
                    _layoutsData[index]['almacen_asignado'] = selectedAlmacen;
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
      builder: (context) => AlertDialog(
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
