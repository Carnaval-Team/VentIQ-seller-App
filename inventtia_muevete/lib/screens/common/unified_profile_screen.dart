import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/carroceria_model.dart';
import '../../models/vehicle_type_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../screens/client/map_picker_screen.dart';
import '../../services/document_upload_service.dart';
import '../../services/driver_service.dart';
import '../../services/geonames_service.dart';
import '../../services/mbtiles_service.dart';
import '../../services/profile_photo_service.dart';
import '../../services/saved_address_service.dart';
import '../../services/vehicle_service.dart';
import '../../services/vehicle_type_service.dart';
import '../../widgets/plan_suscripcion_widget.dart';
import '../../utils/app_error.dart';

/// Fase 1 del perfil unificado.
///
/// Usa un solo [StatefulWidget] con tabs. La pestaña "Perfil" contiene los
/// campos base compartidos; las pestañas "Específico" y "Plan" se muestran
/// de forma condicional según el rol del usuario.
class UnifiedProfileScreen extends StatefulWidget {
  const UnifiedProfileScreen({super.key});

  @override
  State<UnifiedProfileScreen> createState() => _UnifiedProfileScreenState();
}

class _UnifiedProfileScreenState extends State<UnifiedProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;
  late TextEditingController _direccionCtrl;

  static const _docTypes = [
    'Carnet de Identidad',
    'Pasaporte',
    'Licencia de Conducir',
  ];
  String _tipoDocumento = 'Carnet de Identidad';
  String? _docFrenteUrl;
  String? _docDorsoUrl;

  // Driver-specific fields
  late TextEditingController _categoriaCtrl;
  late TextEditingController _marcaCtrl;
  late TextEditingController _modeloCtrl;
  late TextEditingController _chapaCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _capacidadCtrl;
  int? _vehicleId;
  int? _vehicleTypeId;
  int? _driverId;
  String? _vehiclePhotoUrl;
  String? _licCondFrenteUrl;
  String? _licCondDorsoUrl;
  String? _licCircFrenteUrl;
  String? _licCircDorsoUrl;
  String? _licOperativaFrenteUrl;
  String? _licOperativaDorsoUrl;
  List<VehicleTypeModel> _vehicleTypes = [];

  // Client-specific fields
  double? _latitud;
  double? _longitud;

  // Shipper-specific fields
  String? _tipoOrg;
  late TextEditingController _nombreLegalCtrl;
  late TextEditingController _idFiscalCtrl;
  late TextEditingController _regionEmpCtrl;
  late TextEditingController _ciudadEmpCtrl;
  late TextEditingController _direccionEmpCtrl;
  double? _empLat;
  double? _empLng;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _loadingCarrocerias = false;
  List<CarroceriaModel> _carrocerias = [];

  // Geo data (client & carrier)
  List<Map<String, dynamic>> _geoCountries = [];
  List<Map<String, dynamic>> _geoStates = [];
  List<Map<String, dynamic>> _geoCities = [];
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  Map<String, dynamic>? _selectedCity;
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;

  final _driverService = DriverService();
  final _vehicleTypeService = VehicleTypeService();
  final _docService = DocumentUploadService();
  final _photoService = ProfilePhotoService();
  final _addressService = SavedAddressService();
  final _vehicleService = VehicleService();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final p = _profile(auth);

    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: _phoneValue(p));
    _emailCtrl = TextEditingController(
      text: p?['email'] as String? ?? auth.user?.email ?? '',
    );
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
    _direccionCtrl =
        TextEditingController(text: p?['direccion'] as String? ?? '');
    _latitud = double.tryParse(p?['latitud']?.toString() ?? '');
    _longitud = double.tryParse(p?['longitud']?.toString() ?? '');
    _tipoDocumento =
        p?['tipo_documento'] as String? ?? 'Carnet de Identidad';
    _docFrenteUrl = p?['doc_frente_url'] as String?;
    _docDorsoUrl = p?['doc_dorso_url'] as String?;

    if (auth.isConductorPasajeros || auth.isCarrierCarga) {
      _driverId = p?['id'] as int?;
      _categoriaCtrl =
          TextEditingController(text: p?['categoria'] as String? ?? '');

      final veh = p?['vehiculos'] as Map<String, dynamic>?;
      _vehicleId = veh?['id'] as int?;
      _vehicleTypeId = veh?['id_tipo_vehiculo'] as int?;
      _marcaCtrl = TextEditingController(text: veh?['marca'] as String? ?? '');
      _modeloCtrl =
          TextEditingController(text: veh?['modelo'] as String? ?? '');
      _chapaCtrl = TextEditingController(text: veh?['chapa'] as String? ?? '');
      _colorCtrl = TextEditingController(text: veh?['color'] as String? ?? '');
      _capacidadCtrl =
          TextEditingController(text: veh?['capacidad'] as String? ?? '');
      _vehiclePhotoUrl = veh?['image'] as String?;

      _licCondFrenteUrl = p?['lic_conduccion_frente_url'] as String?;
      _licCondDorsoUrl = p?['lic_conduccion_dorso_url'] as String?;
      _licCircFrenteUrl = p?['lic_circulacion_frente_url'] as String?;
      _licCircDorsoUrl = p?['lic_circulacion_dorso_url'] as String?;
      _licOperativaFrenteUrl = p?['lic_operativa_frente_url'] as String?;
      _licOperativaDorsoUrl = p?['lic_operativa_dorso_url'] as String?;

      _vehicleTypeService.getActiveTypes().then((list) {
        if (mounted) setState(() => _vehicleTypes = list);
      });
    } else {
      _categoriaCtrl = TextEditingController();
      _marcaCtrl = TextEditingController();
      _modeloCtrl = TextEditingController();
      _chapaCtrl = TextEditingController();
      _colorCtrl = TextEditingController();
      _capacidadCtrl = TextEditingController();
    }

    if (auth.isClientePasajero || auth.isCarrierCarga) {
      _loadGeoData();
    }

    if (auth.isCarrierCarga && _driverId != null) {
      _loadCarrocerias();
    }

    if (auth.isShipper) {
      _tipoOrg = p?['tipo_organizacion'] as String?;
      _nombreLegalCtrl =
          TextEditingController(text: p?['nombre_legal'] as String? ?? '');
      _idFiscalCtrl =
          TextEditingController(text: p?['id_fiscal'] as String? ?? '');
      _regionEmpCtrl =
          TextEditingController(text: p?['region_empresa'] as String? ?? '');
      _ciudadEmpCtrl =
          TextEditingController(text: p?['ciudad_empresa'] as String? ?? '');
      _direccionEmpCtrl =
          TextEditingController(text: p?['direccion_empresa'] as String? ?? '');
      _empLat = (p?['emp_lat'] as num?)?.toDouble();
      _empLng = (p?['emp_lng'] as num?)?.toDouble();
    } else {
      _nombreLegalCtrl = TextEditingController();
      _idFiscalCtrl = TextEditingController();
      _regionEmpCtrl = TextEditingController();
      _ciudadEmpCtrl = TextEditingController();
      _direccionEmpCtrl = TextEditingController();
    }

    _tabs = TabController(length: _tabCount(auth), vsync: this);
  }

  Map<String, dynamic>? _profile(AuthProvider auth) =>
      auth.isDriver ? auth.driverProfile : auth.userProfile;

  String _phoneValue(Map<String, dynamic>? p) {
    final v = p?['phone'] ?? p?['telefono'];
    return v?.toString() ?? '';
  }

  // ── Geo helpers ────────────────────────────────────────────────────────────

  Future<void> _loadGeoData() async {
    final profile = _profile(context.read<AuthProvider>());
    final pais = profile?['pais'] as String?;
    final province = profile?['province'] as String?;
    final municipality = profile?['municipality'] as String?;

    setState(() => _loadingCountries = true);
    try {
      final countries = await GeonamesService.getCountries();
      if (!mounted) return;
      setState(() {
        _geoCountries = countries;
        _loadingCountries = false;
      });
      await _matchProfileGeo(pais: pais, province: province, municipality: municipality);
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _loadGeoData error: $e');
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Map<String, dynamic>? _findByName(
      List<Map<String, dynamic>> items, String? name, String key) {
    if (name == null || name.isEmpty) return null;
    for (final item in items) {
      if ((item[key] as String).toLowerCase() == name.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  Future<void> _matchProfileGeo({
    String? pais,
    String? province,
    String? municipality,
  }) async {
    final country = _findByName(_geoCountries, pais, 'countryName');
    if (country == null) return;

    setState(() => _selectedCountry = country);
    _paisCtrl.text = pais ?? '';
    await _loadStates(country['countryCode'] as String, preserveName: province);

    if (!mounted || province == null || province.isEmpty) return;
    final state = _findByName(_geoStates, province, 'name');
    if (state == null) return;

    setState(() => _selectedState = state);
    _provinciaCtrl.text = province;
    await _loadCities(
      country['countryCode'] as String,
      state['adminCode1'] as String,
      preserveName: municipality,
    );

    if (!mounted || municipality == null || municipality.isEmpty) return;
    final city = _findByName(_geoCities, municipality, 'name');
    if (city != null && mounted) {
      setState(() {
        _selectedCity = city;
        _municipioCtrl.text = municipality;
      });
    }
  }

  Future<void> _loadStates(String countryCode, {String? preserveName}) async {
    setState(() {
      _loadingStates = true;
      _geoStates = [];
      _selectedState = null;
      _geoCities = [];
      _selectedCity = null;
      _provinciaCtrl.text = '';
      _municipioCtrl.text = '';
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (!mounted) return;
      setState(() {
        _geoStates = states;
        _loadingStates = false;
        if (preserveName != null) {
          _selectedState = _findByName(states, preserveName, 'name');
        }
      });
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _loadStates error: $e');
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _loadCities(
    String countryCode,
    String adminCode, {
    String? preserveName,
  }) async {
    setState(() {
      _loadingCities = true;
      _geoCities = [];
      _selectedCity = null;
      _municipioCtrl.text = '';
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      if (!mounted) return;
      setState(() {
        _geoCities = cities;
        _loadingCities = false;
        if (preserveName != null) {
          _selectedCity = _findByName(cities, preserveName, 'name');
          if (_selectedCity != null) _municipioCtrl.text = preserveName;
        }
      });
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _loadCities error: $e');
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _loadCarrocerias() async {
    if (_driverId == null) return;
    setState(() => _loadingCarrocerias = true);
    try {
      final list =
          await _vehicleService.getCarroceriasForDriver(_driverId!);
      if (mounted) {
        setState(() {
          _carrocerias = list;
          _loadingCarrocerias = false;
        });
      }
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _loadCarrocerias error: $e');
      if (mounted) setState(() => _loadingCarrocerias = false);
    }
  }

  Future<void> _deleteCarroceria(int id) async {
    try {
      await _vehicleService.deleteCarroceria(id);
      await _loadCarrocerias();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.message(e, action: 'eliminar')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showCarroceriaDialog({CarroceriaModel? existing}) async {
    if (_driverId == null) return;
    final isDark = context.read<ThemeProvider>().isDark;

    final marcaCtrl =
        TextEditingController(text: existing?.marca ?? '');
    final modeloCtrl =
        TextEditingController(text: existing?.modelo ?? '');
    final matriculaCtrl =
        TextEditingController(text: existing?.matricula ?? '');
    final tipoCtrl =
        TextEditingController(text: existing?.tipoCarroceria ?? '');
    final capacidadCtrl =
        TextEditingController(text: existing?.capacidadTon?.toString() ?? '');
    final longitudCtrl =
        TextEditingController(text: existing?.longitudM?.toString() ?? '');
    var seguroVigente = existing?.seguroVigente ?? false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          title: Text(
            existing == null ? 'Agregar carrocería' : 'Editar carrocería',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                    controller: tipoCtrl, label: 'Tipo de carrocería'),
                const SizedBox(height: 12),
                _DialogField(controller: marcaCtrl, label: 'Marca'),
                const SizedBox(height: 12),
                _DialogField(controller: modeloCtrl, label: 'Modelo'),
                const SizedBox(height: 12),
                _DialogField(controller: matriculaCtrl, label: 'Matrícula'),
                const SizedBox(height: 12),
                _DialogField(
                  controller: capacidadCtrl,
                  label: 'Capacidad (ton)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: longitudCtrl,
                  label: 'Longitud (m)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Seguro vigente',
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87)),
                    Switch(
                      value: seguroVigente,
                      onChanged: (v) => setLocalState(() => seguroVigente = v),
                      activeColor: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                final c = CarroceriaModel(
                  id: existing?.id,
                  driverId: _driverId!,
                  tipoCarroceria: tipoCtrl.text.trim(),
                  marca: marcaCtrl.text.trim().isEmpty
                      ? null
                      : marcaCtrl.text.trim(),
                  modelo: modeloCtrl.text.trim().isEmpty
                      ? null
                      : modeloCtrl.text.trim(),
                  matricula: matriculaCtrl.text.trim().isEmpty
                      ? null
                      : matriculaCtrl.text.trim(),
                  capacidadTon: double.tryParse(capacidadCtrl.text.trim()),
                  longitudM: double.tryParse(longitudCtrl.text.trim()),
                  seguroVigente: seguroVigente,
                );
                try {
                  if (existing == null) {
                    await _vehicleService.addCarroceria(c);
                  } else {
                    await _vehicleService.updateCarroceria(
                        existing.id!, c.toJson());
                  }
                  if (context.mounted) Navigator.pop(ctx);
                  await _loadCarrocerias();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(AppError.message(e)),
                        backgroundColor: AppTheme.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    marcaCtrl.dispose();
    modeloCtrl.dispose();
    matriculaCtrl.dispose();
    tipoCtrl.dispose();
    capacidadCtrl.dispose();
    longitudCtrl.dispose();
  }

  int _tabCount(AuthProvider auth) {
    final t = auth.tipoUsuario;
    final hasSpecific =
        ['conductor_pasajeros', 'shipper', 'carrier_carga'].contains(t);
    final hasPlan =
        ['shipper', 'carrier_carga', 'dispatcher'].contains(t);
    return 1 + (hasSpecific ? 1 : 0) + (hasPlan ? 1 : 0);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _paisCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _direccionCtrl.dispose();
    _categoriaCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _chapaCtrl.dispose();
    _colorCtrl.dispose();
    _capacidadCtrl.dispose();
    _nombreLegalCtrl.dispose();
    _idFiscalCtrl.dispose();
    _regionEmpCtrl.dispose();
    _ciudadEmpCtrl.dispose();
    _direccionEmpCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthProvider>();
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        _phoneKey(auth): _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'pais': _paisCtrl.text.trim(),
        'province': _provinciaCtrl.text.trim(),
        'municipality': _municipioCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        if (_latitud != null) 'latitud': _latitud,
        if (_longitud != null) 'longitud': _longitud,
      };

      if (_hasDocument(auth)) {
        data['tipo_documento'] = _tipoDocumento;
        if (_docFrenteUrl != null) data['doc_frente_url'] = _docFrenteUrl;
        if (_docDorsoUrl != null) data['doc_dorso_url'] = _docDorsoUrl;
      }

      if (auth.isConductorPasajeros || auth.isCarrierCarga) {
        data['categoria'] = _categoriaCtrl.text.trim();
      }

      if (auth.isShipper) {
        data['tipo_organizacion'] = _tipoOrg;
        data['nombre_legal'] = _nombreLegalCtrl.text.trim();
        data['id_fiscal'] = _idFiscalCtrl.text.trim();
        data['region_empresa'] = _regionEmpCtrl.text.trim();
        data['ciudad_empresa'] = _ciudadEmpCtrl.text.trim();
        data['direccion_empresa'] = _direccionEmpCtrl.text.trim();
        if (_empLat != null) data['emp_lat'] = _empLat;
        if (_empLng != null) data['emp_lng'] = _empLng;
      }

      await auth.updateProfile(data);

      if (auth.isConductorPasajeros) {
        final licData = <String, dynamic>{
          if (_licCondFrenteUrl != null)
            'lic_conduccion_frente_url': _licCondFrenteUrl,
          if (_licCondDorsoUrl != null)
            'lic_conduccion_dorso_url': _licCondDorsoUrl,
          if (_licCircFrenteUrl != null)
            'lic_circulacion_frente_url': _licCircFrenteUrl,
          if (_licCircDorsoUrl != null)
            'lic_circulacion_dorso_url': _licCircDorsoUrl,
          if (_licOperativaFrenteUrl != null)
            'lic_operativa_frente_url': _licOperativaFrenteUrl,
          if (_licOperativaDorsoUrl != null)
            'lic_operativa_dorso_url': _licOperativaDorsoUrl,
        };
        if (licData.isNotEmpty) await auth.updateProfile(licData);

        if (_vehicleId != null) {
          final vehData = <String, dynamic>{
            if (_marcaCtrl.text.trim().isNotEmpty)
              'marca': _marcaCtrl.text.trim(),
            if (_modeloCtrl.text.trim().isNotEmpty)
              'modelo': _modeloCtrl.text.trim(),
            if (_chapaCtrl.text.trim().isNotEmpty)
              'chapa': _chapaCtrl.text.trim(),
            if (_colorCtrl.text.trim().isNotEmpty)
              'color': _colorCtrl.text.trim(),
            if (_capacidadCtrl.text.trim().isNotEmpty)
              'capacidad': _capacidadCtrl.text.trim(),
            if (_vehicleTypeId != null) 'id_tipo_vehiculo': _vehicleTypeId,
            if (_vehiclePhotoUrl != null) 'image': _vehiclePhotoUrl,
          };
          if (vehData.isNotEmpty) {
            await _driverService.updateVehicle(_vehicleId!, vehData);
          }
        }

        if (mounted) await auth.refreshDriverProfile();
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isEditing = false;
        });
        _snackOk();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.message(e, action: 'guardar los cambios')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _cancel() {
    final auth = context.read<AuthProvider>();
    final p = _profile(auth);
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = _phoneValue(p);
    _emailCtrl.text =
        p?['email'] as String? ?? auth.user?.email ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    _direccionCtrl.text = p?['direccion'] as String? ?? '';
    _latitud = double.tryParse(p?['latitud']?.toString() ?? '');
    _longitud = double.tryParse(p?['longitud']?.toString() ?? '');
    _tipoDocumento =
        p?['tipo_documento'] as String? ?? 'Carnet de Identidad';
    _docFrenteUrl = p?['doc_frente_url'] as String?;
    _docDorsoUrl = p?['doc_dorso_url'] as String?;

    if (auth.isConductorPasajeros || auth.isCarrierCarga) {
      _categoriaCtrl.text = p?['categoria'] as String? ?? '';
      final veh = p?['vehiculos'] as Map<String, dynamic>?;
      _vehicleId = veh?['id'] as int?;
      _vehicleTypeId = veh?['id_tipo_vehiculo'] as int?;
      _marcaCtrl.text = veh?['marca'] as String? ?? '';
      _modeloCtrl.text = veh?['modelo'] as String? ?? '';
      _chapaCtrl.text = veh?['chapa'] as String? ?? '';
      _colorCtrl.text = veh?['color'] as String? ?? '';
      _capacidadCtrl.text = veh?['capacidad'] as String? ?? '';
      _vehiclePhotoUrl = veh?['image'] as String?;
      _licCondFrenteUrl = p?['lic_conduccion_frente_url'] as String?;
      _licCondDorsoUrl = p?['lic_conduccion_dorso_url'] as String?;
      _licCircFrenteUrl = p?['lic_circulacion_frente_url'] as String?;
      _licCircDorsoUrl = p?['lic_circulacion_dorso_url'] as String?;
      _licOperativaFrenteUrl = p?['lic_operativa_frente_url'] as String?;
      _licOperativaDorsoUrl = p?['lic_operativa_dorso_url'] as String?;
    }

    if (auth.isShipper) {
      _tipoOrg = p?['tipo_organizacion'] as String?;
      _nombreLegalCtrl.text = p?['nombre_legal'] as String? ?? '';
      _idFiscalCtrl.text = p?['id_fiscal'] as String? ?? '';
      _regionEmpCtrl.text = p?['region_empresa'] as String? ?? '';
      _ciudadEmpCtrl.text = p?['ciudad_empresa'] as String? ?? '';
      _direccionEmpCtrl.text = p?['direccion_empresa'] as String? ?? '';
      _empLat = (p?['emp_lat'] as num?)?.toDouble();
      _empLng = (p?['emp_lng'] as num?)?.toDouble();
    }

    if (auth.isClientePasajero || auth.isCarrierCarga) {
      _loadGeoData();
    }

    setState(() => _isEditing = false);
  }

  String _phoneKey(AuthProvider auth) =>
      auth.isDriver ? 'telefono' : 'phone';

  bool _hasDocument(AuthProvider auth) =>
      auth.isClientePasajero || auth.isShipper;

  Future<void> _pickAddressOnMap({bool isEmpresa = false}) async {
    final picked = await Navigator.push<MapPickerResult>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isEmpresa) {
        _direccionEmpCtrl.text = picked.address;
        _empLat = picked.latLng.latitude;
        _empLng = picked.latLng.longitude;
      } else {
        _direccionCtrl.text = picked.address;
        _latitud = picked.latLng.latitude;
        _longitud = picked.latLng.longitude;
      }
    });
  }

  void _showOfflineMapHelp() {
    final isDark = context.read<ThemeProvider>().isDark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        title: Text(
          'Mapa Offline',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TutorialStep(
                number: '1',
                text:
                    'La app usa un archivo .mbtiles con los mapas. El administrador lo publica en Supabase Storage desde una utilidad interna.',
              ),
              _TutorialStep(
                number: '2',
                text:
                    'Si el mapa ya viene empaquetado en assets/tiles/cuba.mbtiles, se copia automáticamente al teléfono. Si no, usa el botón “Descargar / actualizar mapa” para bajarlo desde Supabase.',
              ),
              _TutorialStep(
                number: '3',
                text:
                    'Para activarlo, simplemente enciende el interruptor “Mapa Offline” en esta pantalla.',
              ),
              _TutorialStep(
                number: '4',
                text:
                    'Si el interruptor aparece deshabilitado, significa que el archivo .mbtiles no está disponible. Presiona “Descargar / actualizar mapa” o contacta al administrador.',
              ),
              _TutorialStep(
                number: '5',
                text:
                    'Una vez activado, los mapas en las pantallas de viajes usarán los datos guardados sin necesidad de internet.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadOfflineMap() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {});

    final ok = await MbTilesService.instance.syncMbtilesFromSupabase();
    if (!mounted) return;

    if (ok) {
      setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mapa descargado correctamente',
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar el mapa. Revisa tu conexión.',
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _snackOk() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Perfil actualizado',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Mi Perfil',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              label: Text(
                'Editar',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: _isSaving ? null : _cancel,
              child: Text(
                'Cancelar',
                style: GoogleFonts.plusJakartaSans(
                  color: isDark ? Colors.white54 : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : Text(
                      'Guardar',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ],
        bottom: _tabCount(auth) > 1
            ? TabBar(
                controller: _tabs,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor:
                    isDark ? Colors.white54 : Colors.grey[500],
                indicatorColor: AppTheme.primaryColor,
                tabs: _buildTabs(auth),
              )
            : null,
      ),
      body: TabBarView(
        controller: _tabs,
        children: _buildTabBodies(auth, isDark, textPrimary),
      ),
    );
  }

  List<Widget> _buildTabs(AuthProvider auth) {
    final t = auth.tipoUsuario;
    final tabs = <Widget>[const Tab(icon: Icon(Icons.person_outline), text: 'Perfil')];
    if (['conductor_pasajeros', 'shipper', 'carrier_carga']
        .contains(t)) {
      tabs.add(const Tab(icon: Icon(Icons.settings_outlined), text: 'Específico'));
    }
    if (['shipper', 'carrier_carga', 'dispatcher'].contains(t)) {
      tabs.add(const Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'Plan'));
    }
    return tabs;
  }

  List<Widget> _buildTabBodies(
    AuthProvider auth,
    bool isDark,
    Color textPrimary,
  ) {
    final t = auth.tipoUsuario;
    final bodies = <Widget>[_buildBaseTab(auth, isDark, textPrimary)];
    if (['conductor_pasajeros', 'shipper', 'carrier_carga']
        .contains(t)) {
      bodies.add(_buildSpecificTab(auth, isDark, textPrimary));
    }
    if (['shipper', 'carrier_carga', 'dispatcher'].contains(t)) {
      bodies.add(_buildPlanTab());
    }
    return bodies;
  }

  Widget _buildBaseTab(
    AuthProvider auth,
    bool isDark,
    Color textPrimary,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(auth, isDark, textPrimary),
            const SizedBox(height: 24),
            _SectionHeader(label: 'Datos personales', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _nameCtrl,
              label: 'Nombre completo',
              icon: Icons.person_outline,
              isDark: isDark,
              enabled: _isEditing,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _phoneCtrl,
              label: 'Teléfono',
              icon: Icons.phone_outlined,
              isDark: isDark,
              enabled: _isEditing,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _emailCtrl,
              label: 'Correo electrónico',
              icon: Icons.email_outlined,
              isDark: isDark,
              enabled: false,
              keyboardType: TextInputType.emailAddress,
            ),
            if (auth.isConductorPasajeros || auth.isCarrierCarga) ...[
              const SizedBox(height: 12),
              _ProfileField(
                controller: _categoriaCtrl,
                label: 'Categoría',
                icon: Icons.category_outlined,
                isDark: isDark,
                enabled: _isEditing,
              ),
            ],
            if (_hasDocument(auth)) ...[
              const SizedBox(height: 24),
              _SectionHeader(label: 'Documento de identidad', isDark: isDark),
              const SizedBox(height: 12),
              _buildDocTypeDropdown(isDark),
              const SizedBox(height: 16),
              _buildDocPhotoRow(isDark),
            ],
            const SizedBox(height: 24),
            _SectionHeader(label: 'Ubicación', isDark: isDark),
            const SizedBox(height: 12),
            _buildLocationFields(auth, isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _direccionCtrl,
              label: 'Dirección',
              icon: Icons.home_outlined,
              isDark: isDark,
              enabled: _isEditing,
              maxLines: 2,
            ),
            if (auth.isClientePasajero || auth.isShipper) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isEditing ? _pickAddressOnMap : null,
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('Seleccionar en mapa'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!kIsWeb)
              _offlineMapTile(
                isDark,
                () async {
                  await MbTilesService.instance.toggleOffline(
                      !MbTilesService.instance.useOffline);
                  setState(() {});
                },
                onHelp: _showOfflineMapHelp,
                onDownload: _downloadOfflineMap,
              ),
            const SizedBox(height: 24),
            _buildSignOutButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationFields(AuthProvider auth, bool isDark) {
    final useGeo = auth.isClientePasajero || auth.isCarrierCarga;
    if (!useGeo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileField(
            controller: _paisCtrl,
            label: 'País',
            icon: Icons.public_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _provinciaCtrl,
            label: 'Provincia / Estado',
            icon: Icons.map_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _municipioCtrl,
            label: 'Ciudad / Municipio',
            icon: Icons.location_city_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGeoDropdown(
          isDark: isDark,
          label: 'País',
          icon: Icons.public_outlined,
          loading: _loadingCountries,
          loadingLabel: 'Cargando países...',
          items: _geoCountries,
          selected: _selectedCountry,
          itemLabel: (i) => i['countryName'] as String,
          compare: (a, b) =>
              a['countryCode'] == b['countryCode'],
          enabled: _isEditing,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedCountry = v;
              _paisCtrl.text = v['countryName'] as String;
            });
            _loadStates(v['countryCode'] as String);
          },
          emptyHint: 'Selecciona un país',
        ),
        const SizedBox(height: 12),
        _buildGeoDropdown(
          isDark: isDark,
          label: 'Provincia / Estado',
          icon: Icons.map_outlined,
          loading: _loadingStates,
          loadingLabel: 'Cargando provincias...',
          items: _geoStates,
          selected: _selectedState,
          itemLabel: (i) => i['name'] as String,
          compare: (a, b) => a['geonameId'] == b['geonameId'],
          enabled: _isEditing,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedState = v;
              _provinciaCtrl.text = v['name'] as String;
            });
            _loadCities(
              _selectedCountry!['countryCode'] as String,
              v['adminCode1'] as String,
            );
          },
          emptyHint: 'Selecciona una provincia',
        ),
        const SizedBox(height: 12),
        _buildGeoDropdown(
          isDark: isDark,
          label: 'Ciudad / Municipio',
          icon: Icons.location_city_outlined,
          loading: _loadingCities,
          loadingLabel: 'Cargando ciudades...',
          items: _geoCities,
          selected: _selectedCity,
          itemLabel: (i) => i['name'] as String,
          compare: (a, b) => a['geonameId'] == b['geonameId'],
          enabled: _isEditing,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedCity = v;
              _municipioCtrl.text = v['name'] as String;
            });
          },
          emptyHint: 'Selecciona una ciudad',
        ),
      ],
    );
  }

  Widget _buildGeoDropdown({
    required bool isDark,
    required String label,
    required IconData icon,
    required bool loading,
    required String loadingLabel,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic>? selected,
    required String Function(Map<String, dynamic>) itemLabel,
    required bool Function(Map<String, dynamic>, Map<String, dynamic>) compare,
    required bool enabled,
    required ValueChanged<Map<String, dynamic>?> onChanged,
    String? emptyHint,
  }) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    if (loading) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              loadingLabel,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<Map<String, dynamic>>(
      isExpanded: true,
      value: selected,
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.primaryColor),
        filled: true,
        fillColor: enabled
            ? cardColor
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey[50]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
      items: items
          .map((i) => DropdownMenuItem(
                value: i,
                child: Text(
                  itemLabel(i),
                  style: TextStyle(color: textPrimary, fontSize: 14),
                ),
              ))
          .toList(),
      onChanged: enabled ? onChanged : null,
      hint: emptyHint != null
          ? Text(emptyHint,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.grey[500],
              ))
          : null,
    );
  }

  Widget _buildAvatar(
    AuthProvider auth,
    bool isDark,
    Color textPrimary,
  ) {
    final profile = _profile(auth);
    final photoUrl =
        profile?['photo_url'] as String? ?? profile?['image'] as String?;
    final name = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Usuario';

    return Center(
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              border: Border.all(color: AppTheme.primaryColor, width: 3),
              image: (photoUrl != null && photoUrl.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage(photoUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (photoUrl == null || photoUrl.isEmpty)
                ? Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  )
                : null,
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _isUploadingPhoto ? null : _changePhoto,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor,
                    border: Border.all(
                      color: isDark ? AppTheme.darkBg : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: _isUploadingPhoto
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _changePhoto() async {
    final source = await _showPhotoSourceSheet();
    if (source == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final uuid = auth.user?.id;
    if (uuid == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _photoService.pickCompressAndUpload(
        uuid: uuid,
        source: source,
      );
      if (url == null || !mounted) {
        setState(() => _isUploadingPhoto = false);
        return;
      }

      if (auth.isDriver) {
        await Supabase.instance.client
            .schema('muevete')
            .from('drivers')
            .update({'image': url})
            .eq('uuid', uuid);
        if (mounted) await auth.refreshDriverProfile();
      } else {
        await _addressService.updateUserPhoto(uuid, url);
        await auth.updateProfile({'photo_url': url});
      }

      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        _snackOk();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.message(e, action: 'cambiar la foto')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildDocTypeDropdown(bool isDark) {
    final items = _docTypes
        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
        .toList();
    return DropdownButtonFormField<String>(
      value: _docTypes.contains(_tipoDocumento) ? _tipoDocumento : _docTypes.first,
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: 'Tipo de documento',
        prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.primaryColor),
        filled: true,
        fillColor: _isEditing
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
      items: items,
      onChanged: _isEditing
          ? (v) {
              if (v != null) setState(() => _tipoDocumento = v);
            }
          : null,
    );
  }

  Widget _buildDocPhotoRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildDocPhoto(
            label: 'Frente',
            url: _docFrenteUrl,
            isDark: isDark,
            onTap: () => _pickDocPhoto(isFront: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDocPhoto(
            label: 'Dorso',
            url: _docDorsoUrl,
            isDark: isDark,
            onTap: () => _pickDocPhoto(isFront: false),
          ),
        ),
      ],
    );
  }

  Widget _buildDocPhoto({
    required String label,
    required String? url,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isEditing ? onTap : null,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
          image: (url != null && url.isNotEmpty)
              ? DecorationImage(
                  image: NetworkImage(url),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: (url == null || url.isEmpty)
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    color: AppTheme.primaryColor,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _pickDocPhoto({required bool isFront}) async {
    // Placeholder para fase 1; en fase 2 se integra DocumentUploadService.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Subida de documento $isFront en construcción (fase 2)'),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSpecificTab(
    AuthProvider auth,
    bool isDark,
    Color textPrimary,
  ) {
    if (auth.isConductorPasajeros) {
      return _buildDriverSpecificTab(isDark, textPrimary);
    }
    if (auth.isShipper) {
      return _buildShipperSpecificTab(isDark, textPrimary);
    }
    if (auth.isCarrierCarga) {
      return _buildCarrierSpecificTab(isDark, textPrimary);
    }
    return const SizedBox.shrink();
  }

  Widget _buildDriverSpecificTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: 'Vehículo', isDark: isDark),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _marcaCtrl,
            label: 'Marca',
            icon: Icons.directions_car_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _modeloCtrl,
            label: 'Modelo',
            icon: Icons.time_to_leave_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _chapaCtrl,
            label: 'Chapa / Matrícula',
            icon: Icons.pin_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _colorCtrl,
            label: 'Color',
            icon: Icons.palette_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _capacidadCtrl,
            label: 'Capacidad',
            icon: Icons.people_outline,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          _buildVehicleTypeDropdown(isDark),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Foto del vehículo', isDark: isDark),
          const SizedBox(height: 12),
          _buildVehiclePhoto(isDark),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Licencias', isDark: isDark),
          const SizedBox(height: 16),
          _buildLicenseRow(
            'Conducción',
            _licCondFrenteUrl,
            _licCondDorsoUrl,
            (front) => _licCondFrenteUrl = front,
            (back) => _licCondDorsoUrl = back,
          ),
          const SizedBox(height: 12),
          _buildLicenseRow(
            'Circulación',
            _licCircFrenteUrl,
            _licCircDorsoUrl,
            (front) => _licCircFrenteUrl = front,
            (back) => _licCircDorsoUrl = back,
          ),
          const SizedBox(height: 12),
          _buildLicenseRow(
            'Operativa',
            _licOperativaFrenteUrl,
            _licOperativaDorsoUrl,
            (front) => _licOperativaFrenteUrl = front,
            (back) => _licOperativaDorsoUrl = back,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildVehicleTypeDropdown(bool isDark) {
    // El perfil de conductor pasajeros solo permite tipos de pasajeros.
    // Si el conductor tiene asignado un tipo de carga, se conserva en el
    // dropdown para evitar inconsistencias, pero no se ofrece a nuevos.
    final pasajeroTypes = _vehicleTypes.where((t) => t.isPasajero).toList();
    final currentType = _vehicleTypeId != null
        ? _vehicleTypes.where((t) => t.id == _vehicleTypeId).toList()
        : <VehicleTypeModel>[];
    final displayTypes = {...pasajeroTypes, ...currentType}.toList();

    final items = displayTypes
        .map((t) => DropdownMenuItem<int>(
              value: t.id,
              child: Text(t.displayName),
            ))
        .toList();

    return DropdownButtonFormField<int>(
      value: _vehicleTypeId,
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: 'Tipo de vehículo',
        prefixIcon: const Icon(Icons.local_taxi, color: AppTheme.primaryColor),
        filled: true,
        fillColor: _isEditing
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
      items: items,
      onChanged: _isEditing
          ? (v) {
              if (v != null) setState(() => _vehicleTypeId = v);
            }
          : null,
    );
  }

  Widget _buildVehiclePhoto(bool isDark) {
    return GestureDetector(
      onTap: _isEditing ? _pickVehiclePhoto : null,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
          image: (_vehiclePhotoUrl != null && _vehiclePhotoUrl!.isNotEmpty)
              ? DecorationImage(
                  image: NetworkImage(_vehiclePhotoUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: (_vehiclePhotoUrl == null || _vehiclePhotoUrl!.isEmpty)
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      color: AppTheme.primaryColor, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'Foto del vehículo',
                    style: GoogleFonts.plusJakartaSans(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _pickVehiclePhoto() async {
    final source = await _showPhotoSourceSheet();
    if (source == null || !mounted) return;
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;

    setState(() => _vehiclePhotoUrl = null); // Mostrar loading
    try {
      final url = await _docService.pickCompressAndUpload(
        uuid: uuid,
        filename: 'vehicle_photo',
        source: source,
      );
      if (url != null && mounted) {
        setState(() => _vehiclePhotoUrl = url);
      }
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _pickVehiclePhoto error: $e');
    }
  }

  Future<void> _pickLicensePhoto({
    required String license,
    required bool isFront,
    required void Function(String?) onSet,
  }) async {
    final source = await _showPhotoSourceSheet();
    if (source == null || !mounted) return;
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;

    final filename = '${license.toLowerCase()}_${isFront ? 'frente' : 'dorso'}';
    try {
      final url = await _docService.pickCompressAndUpload(
        uuid: uuid,
        filename: filename,
        source: source,
      );
      if (url != null && mounted) {
        setState(() => onSet(url));
      }
    } catch (e) {
      debugPrint('[UnifiedProfileV2] _pickLicensePhoto error: $e');
    }
  }

  Future<ImageSource?> _showPhotoSourceSheet() async {
    final isDark = context.read<ThemeProvider>().isDark;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Seleccionar fuente',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLicenseRow(
    String label,
    String? frontUrl,
    String? backUrl,
    void Function(String?) onFront,
    void Function(String?) onBack,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Licencia de $label',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDocPhoto(
                label: 'Frente',
                url: frontUrl,
                isDark: false,
                onTap: () => _pickLicensePhoto(
                  license: label,
                  isFront: true,
                  onSet: onFront,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDocPhoto(
                label: 'Dorso',
                url: backUrl,
                isDark: false,
                onTap: () => _pickLicensePhoto(
                  license: label,
                  isFront: false,
                  onSet: onBack,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShipperSpecificTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Los campos de identificación fiscal se adaptan al país seleccionado.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: '1. Tipo de organización', isDark: isDark),
          const SizedBox(height: 10),
          _buildShipperOrgDropdown(isDark),
          const SizedBox(height: 16),
          _ProfileField(
            controller: _nombreLegalCtrl,
            label: '2. Nombre legal de la empresa',
            icon: Icons.business_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _idFiscalCtrl,
            label:
                '3. ${_labelFiscal(_paisCtrl.text.trim().isNotEmpty ? _paisCtrl.text.trim() : null)}',
            icon: Icons.numbers_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          _SectionHeader(label: 'Ubicación de la empresa', isDark: isDark),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _regionEmpCtrl,
            label: 'Estado / Región / Provincia',
            icon: Icons.location_city_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _ciudadEmpCtrl,
            label: 'Ciudad / Municipio',
            icon: Icons.map_outlined,
            isDark: isDark,
            enabled: _isEditing,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            controller: _direccionEmpCtrl,
            label: 'Dirección de la empresa',
            icon: Icons.home_outlined,
            isDark: isDark,
            enabled: _isEditing,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _isEditing ? () => _pickAddressOnMap(isEmpresa: true) : null,
              icon: const Icon(Icons.map, size: 18),
              label: const Text('Seleccionar en mapa'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildShipperOrgDropdown(bool isDark) {
    final items = _tiposOrganizacion.entries
        .map((e) => DropdownMenuItem<String>(
              value: e.key,
              child: Text(e.value),
            ))
        .toList();
    return DropdownButtonFormField<String>(
      value: _tiposOrganizacion.containsKey(_tipoOrg) ? _tipoOrg : null,
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: 'Seleccionar tipo',
        filled: true,
        fillColor: _isEditing
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
      items: items,
      onChanged: _isEditing
          ? (v) {
              if (v != null) setState(() => _tipoOrg = v);
            }
          : null,
    );
  }

  Widget _buildCarrierSpecificTab(bool isDark, Color textPrimary) {
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: _loadingCarrocerias
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _carrocerias.length + 1,
              itemBuilder: (ctx, i) {
                if (i == _carrocerias.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ElevatedButton.icon(
                      onPressed: () => _showCarroceriaDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar carrocería'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }
                final c = _carrocerias[i];
                return Card(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.local_shipping,
                        color: AppTheme.primaryColor),
                    title: Text(
                      '${c.tipoCarroceria} — ${c.marca ?? ''} ${c.modelo ?? ''}'
                          .trim(),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Matrícula: ${c.matricula ?? 'N/A'}\n'
                      'Capacidad: ${c.capacidadTon?.toStringAsFixed(1) ?? '-'} ton · '
                      'Largo: ${c.longitudM?.toStringAsFixed(1) ?? '-'} m',
                      style: GoogleFonts.plusJakartaSans(
                        color: isDark ? Colors.white60 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: AppTheme.primaryColor),
                          onPressed: () =>
                              _showCarroceriaDialog(existing: c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: AppTheme.error),
                          onPressed: () => _deleteCarroceria(c.id!),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPlanTab() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: PlanSuscripcionTile(),
    );
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await context.read<AuthProvider>().signOut();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            kIsWeb ? '/landing' : '/login',
            (_) => false,
          );
        },
        icon: const Icon(Icons.logout, size: 18),
        label: Text(
          'Cerrar sesión',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers locales (fase 1). En fase 2 se pueden mover a un archivo compartido.
// ─────────────────────────────────────────────────────────────────────────────

const _tiposOrganizacion = <String, String>{
  'empresa_privada': 'Empresa Privada',
  'empresa_estatal': 'Empresa Estatal / Pública',
  'autonomo': 'Autónomo / Cuenta Propia',
  'cooperativa': 'Cooperativa',
  'ong': 'ONG / Fundación',
  'otro': 'Otro',
};

const _fiscalIdLabel = <String, String>{
  'CU': 'NIF',
  'ES': 'NIF / CIF',
  'US': 'EIN / TIN',
  'MX': 'RFC',
};

String _labelFiscal(String? iso) =>
    _fiscalIdLabel[iso?.toUpperCase()] ?? 'Identificador Fiscal';

Widget _offlineMapTile(
  bool isDark,
  VoidCallback onToggle, {
  VoidCallback? onHelp,
  VoidCallback? onDownload,
}) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined,
                  color: AppTheme.primaryColor, size: 22),
              if (onHelp != null)
                IconButton(
                  icon: Icon(Icons.help_outline,
                      color: AppTheme.primaryColor, size: 20),
                  onPressed: onHelp,
                ),
            ],
          ),
          title: Text('Mapa Offline',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87)),
          subtitle: Text(
              MbTilesService.instance.isAvailable
                  ? 'Usar mapa descargado (sin internet)'
                  : 'Archivo de mapa no disponible',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey[500])),
          value: MbTilesService.instance.useOffline,
          activeThumbColor: AppTheme.primaryColor,
          onChanged: MbTilesService.instance.isAvailable
              ? (_) => onToggle()
              : null,
        ),
        if (onDownload != null) ...[
          Divider(
            height: 1,
            color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download,
                color: AppTheme.primaryColor),
            title: Text('Descargar / actualizar mapa',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text('Bajar el mapa desde Supabase Storage',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey[500])),
            trailing: const Icon(Icons.download,
                color: AppTheme.primaryColor),
            onTap: onDownload,
          ),
        ],
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : Colors.grey[700],
          letterSpacing: 0.4,
        ),
      );
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final bool enabled;
  final int maxLines;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final disabledColor = isDark ? Colors.white38 : Colors.grey[400]!;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: enabled ? textPrimary : disabledColor,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          size: 18,
          color: enabled ? AppTheme.primaryColor : disabledColor,
        ),
        filled: true,
        fillColor: enabled
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;

  const _DialogField({
    required this.controller,
    required this.label,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.read<ThemeProvider>().isDark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1A1D27),
      ),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? AppTheme.darkCard : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      ),
    );
  }
}

class _TutorialStep extends StatelessWidget {
  final String number;
  final String text;

  const _TutorialStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = context.read<ThemeProvider>().isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppTheme.primaryColor,
            child: Text(
              number,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
