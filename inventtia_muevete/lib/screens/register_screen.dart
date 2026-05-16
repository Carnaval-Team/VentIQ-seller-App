import 'package:country_flags/country_flags.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/vehicle_type_model.dart';
import '../services/document_upload_service.dart';
import '../services/dispatcher_service.dart';
import '../services/geonames_service.dart';
import '../services/vehicle_type_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data class for each carrocería (vehicle platform) in the carrier form
// ─────────────────────────────────────────────────────────────────────────────
class _CarroceriaItem {
  final TextEditingController marca = TextEditingController();
  final TextEditingController modelo = TextEditingController();
  final TextEditingController matricula = TextEditingController();
  final TextEditingController capacidadTon = TextEditingController();
  final TextEditingController longitudM = TextEditingController();
  String? tipoCarroceria;
  bool seguroVigente = false;

  void dispose() {
    marca.dispose();
    modelo.dispose();
    matricula.dispose();
    capacidadTon.dispose();
    longitudM.dispose();
  }

  Map<String, dynamic> toMap() => {
        'tipo_carroceria': tipoCarroceria,
        if (marca.text.trim().isNotEmpty) 'marca': marca.text.trim(),
        if (modelo.text.trim().isNotEmpty) 'modelo': modelo.text.trim(),
        if (matricula.text.trim().isNotEmpty) 'matricula': matricula.text.trim(),
        if (capacidadTon.text.trim().isNotEmpty)
          'capacidad_ton': double.tryParse(capacidadTon.text.trim()),
        if (longitudM.text.trim().isNotEmpty)
          'longitud_m': double.tryParse(longitudM.text.trim()),
        'seguro_vigente': seguroVigente,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for each transportista row in the dispatcher form
// ─────────────────────────────────────────────────────────────────────────────
class _TransportistaItem {
  final TextEditingController nombre = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController telefono = TextEditingController();
  final TextEditingController marca = TextEditingController();
  final TextEditingController modelo = TextEditingController();
  final TextEditingController matricula = TextEditingController();
  final TextEditingController capacidadTon = TextEditingController();
  final TextEditingController mcNumber = TextEditingController();
  final TextEditingController dotNumber = TextEditingController();
  String? tipoCarroceria;

  void dispose() {
    nombre.dispose();
    email.dispose();
    telefono.dispose();
    marca.dispose();
    modelo.dispose();
    matricula.dispose();
    capacidadTon.dispose();
    mcNumber.dispose();
    dotNumber.dispose();
  }

  Map<String, dynamic> toMap() => {
        'name': nombre.text.trim(),
        'email': email.text.trim(),
        'telefono': telefono.text.trim(),
        if (tipoCarroceria != null) 'tipo_carroceria': tipoCarroceria,
        if (marca.text.trim().isNotEmpty) 'marca': marca.text.trim(),
        if (modelo.text.trim().isNotEmpty) 'modelo': modelo.text.trim(),
        if (matricula.text.trim().isNotEmpty) 'matricula': matricula.text.trim(),
        if (capacidadTon.text.trim().isNotEmpty)
          'capacidad_ton': double.tryParse(capacidadTon.text.trim()),
        if (mcNumber.text.trim().isNotEmpty) 'mc_number': mcNumber.text.trim(),
        if (dotNumber.text.trim().isNotEmpty) 'dot_number': dotNumber.text.trim(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Common fields ──────────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  String _selectedDocType = 'Carnet de Identidad';

  // ── GeoNames location ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _geoCountries = [];
  List<Map<String, dynamic>> _geoStates = [];
  List<Map<String, dynamic>> _geoCities = [];
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  Map<String, dynamic>? _selectedCity;
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;
  String? _docFrenteUrl;
  String? _docDorsoUrl;
  bool _isUploadingFrente = false;
  bool _isUploadingDorso = false;
  String? _tempUuid;

  // ── Type selection ──────────────────────────────────────────────────────────
  // 'cliente_pasajero' | 'shipper' | 'transportista' | 'dispatcher'
  String _selectedTopType = 'cliente_pasajero';
  // sub-type only when _selectedTopType == 'transportista'
  String _selectedTransportistaSubtype = 'conductor_pasajeros';

  // ── Shipper fields ──────────────────────────────────────────────────────────
  String _shipperTipoCuenta = 'individual';
  final _empresaNombreController = TextEditingController();
  final _empresaRutController = TextEditingController();
  final _empresaDireccionController = TextEditingController();
  final List<String> _mercaderiasSeleccionadas = [];

  // ── Carrier fields (multi-vehicle) ─────────────────────────────────────────
  final List<_CarroceriaItem> _carrocerias = [_CarroceriaItem()];
  final _mcNumberController = TextEditingController();
  final _dotNumberController = TextEditingController();

  // ── Conductor pasajeros — vehicle fields ──────────────────────────────
  final _vMarcaController = TextEditingController();
  final _vModeloController = TextEditingController();
  final _vChapaController = TextEditingController();
  final _vColorController = TextEditingController();
  final _vAnioController = TextEditingController();
  final _vCapacidadController = TextEditingController();
  String _vCondicion = 'bueno';
  bool _vAireAcondicionado = false;
  int? _vIdTipo;  // vehicle_type id selected

  // ── Dispatcher fields ───────────────────────────────────────────────────────
  final _dispEmpresaNombreController = TextEditingController();
  final _dispEmpresaRutController = TextEditingController();
  final _dispEmpresaDireccionController = TextEditingController();
  final List<_TransportistaItem> _transportistas = [_TransportistaItem()];

  final DocumentUploadService _docService = DocumentUploadService();
  final DispatcherService _dispatcherService = DispatcherService();

  // ── Static data ─────────────────────────────────────────────────────────────
  static const List<String> _docTypes = [
    'Carnet de Identidad',
    'Pasaporte',
    'Licencia de Conducir',
  ];

  static const List<String> _tiposCarroceria = [
    'Furgón seco',
    'Flatbed',
    'Reefer / Refrigerado',
    'Tanque',
    'Curtainsider',
    'Volcadora',
  ];

  static const List<String> _mercaderiaOpciones = [
    'General',
    'Refrigerada',
    'Peligrosa',
    'Sobredimensionada',
    'Vehículos',
    'Electrónica',
    'Otros',
  ];

  static const List<String> _tiposCuentaShipper = [
    'individual',
    'empresa',
    'cooperativa',
  ];

  // Vehicle types loaded from DB (replaces the old hardcoded list)
  List<VehicleTypeModel> _dbVehicleTypes = [];

  /// Resolves the actual tipo_usuario from UI state.
  String get _tipoUsuarioFinal {
    if (_selectedTopType == 'transportista') {
      return _selectedTransportistaSubtype;
    }
    return _selectedTopType;
  }

  @override
  void initState() {
    super.initState();
    _tempUuid = DateTime.now().millisecondsSinceEpoch.toString();
    _loadCountries();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    try {
      debugPrint('[Register] Cargando tipos de vehículo desde DB...');
      final types = await VehicleTypeService().getActiveTypes();
      debugPrint('[Register] Tipos de vehículo cargados: ${types.length}');
      if (mounted) setState(() => _dbVehicleTypes = types);
    } catch (e, st) {
      debugPrint('[Register][ERROR] _loadVehicleTypes: $e\n$st');
    }
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    try {
      debugPrint('[Register] Cargando países desde GeoNames...');
      final countries = await GeonamesService.getCountries();
      debugPrint('[Register] Países cargados: ${countries.length}');
      if (mounted) setState(() { _geoCountries = countries; _loadingCountries = false; });
    } catch (e, st) {
      debugPrint('[Register][ERROR] _loadCountries: $e\n$st');
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() { _loadingStates = true; _geoStates = []; _selectedState = null; _geoCities = []; _selectedCity = null; });
    try {
      debugPrint('[Register] Cargando estados para country=$countryCode...');
      final states = await GeonamesService.getStates(countryCode);
      debugPrint('[Register] Estados cargados: ${states.length}');
      if (mounted) setState(() { _geoStates = states; _loadingStates = false; });
    } catch (e, st) {
      debugPrint('[Register][ERROR] _loadStates($countryCode): $e\n$st');
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _loadCities(String countryCode, String adminCode) async {
    setState(() { _loadingCities = true; _geoCities = []; _selectedCity = null; });
    try {
      debugPrint('[Register] Cargando ciudades para country=$countryCode admin=$adminCode...');
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      debugPrint('[Register] Ciudades cargadas: ${cities.length}');
      if (mounted) setState(() { _geoCities = cities; _loadingCities = false; });
    } catch (e, st) {
      debugPrint('[Register][ERROR] _loadCities($countryCode,$adminCode): $e\n$st');
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _empresaNombreController.dispose();
    _empresaRutController.dispose();
    _empresaDireccionController.dispose();
    for (final c in _carrocerias) {
      c.dispose();
    }
    _mcNumberController.dispose();
    _dotNumberController.dispose();
    _vMarcaController.dispose();
    _vModeloController.dispose();
    _vChapaController.dispose();
    _vColorController.dispose();
    _vAnioController.dispose();
    _vCapacidadController.dispose();
    _dispEmpresaNombreController.dispose();
    _dispEmpresaRutController.dispose();
    _dispEmpresaDireccionController.dispose();
    for (final t in _transportistas) {
      t.dispose();
    }
    super.dispose();
  }

  // ─── Document picker ────────────────────────────────────────────────────────
  Future<void> _pickDocument({required bool isFront}) async {
    final isDark = context.read<ThemeProvider>().isDark;

    final source = await showModalBottomSheet<ImageSource>(
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
                isFront ? 'Foto del frente' : 'Foto del dorso',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                title: Text('Camara',
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: AppTheme.primaryColor),
                title: Text('Galeria',
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    setState(() {
      if (isFront) {
        _isUploadingFrente = true;
      } else {
        _isUploadingDorso = true;
      }
    });

    try {
      final url = await _docService.pickCompressAndUpload(
        uuid: _tempUuid!,
        filename: isFront ? 'doc_frente' : 'doc_dorso',
        source: source,
      );
      if (url != null && mounted) {
        setState(() {
          if (isFront) {
            _docFrenteUrl = url;
          } else {
            _docDorsoUrl = url;
          }
        });
      }
    } catch (e, st) {
      debugPrint('[Register][ERROR] _pickDocument: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir imagen: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isFront) {
            _isUploadingFrente = false;
          } else {
            _isUploadingDorso = false;
          }
        });
      }
    }
  }

  // ─── Register handler ────────────────────────────────────────────────────────
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_docFrenteUrl == null) {
      _showError('Debes subir la foto del frente del documento');
      return;
    }
    if (_docDorsoUrl == null) {
      _showError('Debes subir la foto del dorso del documento');
      return;
    }

    // Dispatcher: require at least 1 transportista with name+email+phone
    if (_tipoUsuarioFinal == 'dispatcher') {
      final valid = _transportistas.any((t) =>
          t.nombre.text.trim().isNotEmpty &&
          t.email.text.trim().isNotEmpty &&
          t.telefono.text.trim().isNotEmpty);
      if (!valid) {
        _showError(
            'Debes ingresar al menos un transportista con nombre, email y teléfono');
        return;
      }
    }

    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();

    final tipo = _tipoUsuarioFinal;

    final success = await authProvider.signUp(
      _emailController.text.trim(),
      _passwordController.text,
      name: _nameController.text.trim(),
      tipoUsuario: tipo,
      phone: '${_selectedCountry?['dialCode'] ?? ''}${_phoneController.text.trim()}',
      pais: _selectedCountry?['countryName'],
      province: _selectedState?['name'],
      municipality: _selectedCity?['name'],
      tipoDocumento: _selectedDocType,
      docFrenteUrl: _docFrenteUrl,
      docDorsoUrl: _docDorsoUrl,
      // Shipper
      tipoCuenta: tipo == 'shipper' ? _shipperTipoCuenta : null,
      empresaNombre: (tipo == 'shipper' || tipo == 'dispatcher') &&
              _empresaNombreController.text.trim().isNotEmpty
          ? (tipo == 'shipper'
              ? _empresaNombreController.text.trim()
              : _dispEmpresaNombreController.text.trim())
          : null,
      empresaRut: (tipo == 'shipper' || tipo == 'dispatcher') &&
              _empresaRutController.text.trim().isNotEmpty
          ? (tipo == 'shipper'
              ? _empresaRutController.text.trim()
              : _dispEmpresaRutController.text.trim())
          : null,
      empresaDireccion: tipo == 'shipper' &&
              _empresaDireccionController.text.trim().isNotEmpty
          ? _empresaDireccionController.text.trim()
          : tipo == 'dispatcher' &&
                  _dispEmpresaDireccionController.text.trim().isNotEmpty
              ? _dispEmpresaDireccionController.text.trim()
              : null,
      mercaderiasHabituales:
          tipo == 'shipper' && _mercaderiasSeleccionadas.isNotEmpty
              ? List<String>.from(_mercaderiasSeleccionadas)
              : null,
      // Carrier: pass all vehicle platforms
      carrocerias: tipo == 'carrier_carga'
          ? _carrocerias
              .where((c) => c.tipoCarroceria != null)
              .map((c) => c.toMap())
              .toList()
          : null,
      mcNumber: tipo == 'carrier_carga' &&
              _mcNumberController.text.trim().isNotEmpty
          ? _mcNumberController.text.trim()
          : null,
      dotNumber: tipo == 'carrier_carga' &&
              _dotNumberController.text.trim().isNotEmpty
          ? _dotNumberController.text.trim()
          : null,
      // Conductor pasajeros vehicle
      vehiculoMarca: tipo == 'conductor_pasajeros' &&
              _vMarcaController.text.trim().isNotEmpty
          ? _vMarcaController.text.trim()
          : null,
      vehiculoModelo: tipo == 'conductor_pasajeros' &&
              _vModeloController.text.trim().isNotEmpty
          ? _vModeloController.text.trim()
          : null,
      vehiculoChapa: tipo == 'conductor_pasajeros'
          ? _vChapaController.text.trim()
          : null,
      vehiculoColor: tipo == 'conductor_pasajeros' &&
              _vColorController.text.trim().isNotEmpty
          ? _vColorController.text.trim()
          : null,
      vehiculoAnio: tipo == 'conductor_pasajeros' &&
              _vAnioController.text.trim().isNotEmpty
          ? int.tryParse(_vAnioController.text.trim())
          : null,
      vehiculoCapacidad: tipo == 'conductor_pasajeros' &&
              _vCapacidadController.text.trim().isNotEmpty
          ? int.tryParse(_vCapacidadController.text.trim())
          : null,
      vehiculoCondicion:
          tipo == 'conductor_pasajeros' ? _vCondicion : null,
      vehiculoAireAcondicionado:
          tipo == 'conductor_pasajeros' ? _vAireAcondicionado : null,
      vehiculoIdTipo:
          tipo == 'conductor_pasajeros' ? _vIdTipo : null,
    );

    if (!mounted) return;

    if (success) {
      // For dispatchers: register their transportistas
      if (tipo == 'dispatcher') {
        final driverProfile = authProvider.driverProfile;
        final driverUuid = authProvider.user?.id;
        final driverDbId = driverProfile?['id'] as int?;

        if (driverUuid != null && driverDbId != null) {
          final validTransportistas = _transportistas
              .where((t) =>
                  t.nombre.text.trim().isNotEmpty &&
                  t.email.text.trim().isNotEmpty &&
                  t.telefono.text.trim().isNotEmpty)
              .map((t) => t.toMap())
              .toList();

          if (validTransportistas.isNotEmpty) {
            try {
              await _dispatcherService.registrarTransportistas(
                dispatcherUuid: driverUuid,
                dispatcherDriverId: driverDbId,
                transportistas: validTransportistas,
              );
            } catch (e) {
              debugPrint('[Register] Error registering transportistas: $e');
            }
          }
        }
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, authProvider.homeRoute);
    } else {
      _showError(authProvider.error ?? 'Error al crear la cuenta');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey[600]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;

    final Widget header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'Crear Cuenta',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    final Widget form = Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),

                      // ── SECTION: Información de cuenta ──────────────────
                      _SectionHeader(title: 'Información de Cuenta'),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Nombre Completo *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: textPrimary),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Tu nombre completo',
                          prefixIcon:
                              Icon(Icons.person_outline, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'El nombre es requerido';
                          }
                          if (v.trim().length < 2) return 'Nombre muy corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Correo Electrónico *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'correo@ejemplo.com',
                          prefixIcon:
                              Icon(Icons.email_outlined, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'El correo es requerido';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(v.trim())) {
                            return 'Ingresa un correo válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Contraseña *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Mínimo 6 caracteres',
                          prefixIcon:
                              const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: isDark
                                  ? Colors.white
                                      .withValues(alpha: 0.5)
                                  : Colors.grey[500],
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'La contraseña es requerida';
                          }
                          if (v.length < 6) return 'Mínimo 6 caracteres';
                          return null;
                        },
                      ),

                      const SizedBox(height: 28),

                      // ── SECTION: Ubicación y contacto ───────────────────
                      _SectionHeader(title: 'Ubicación y Contacto'),
                      const SizedBox(height: 16),

                      // País
                      _FieldLabel(label: 'País *'),
                      const SizedBox(height: 8),
                      _loadingCountries
                          ? const _LoadingDropdown(label: 'Cargando países...')
                          : DropdownSearch<Map<String, dynamic>>(
                              selectedItem: _selectedCountry,
                              items: _geoCountries,
                              filterFn: (item, filter) =>
                                  (item['countryName'] as String)
                                      .toLowerCase()
                                      .contains(filter.toLowerCase()),
                              itemAsString: (c) => c['countryName'] as String,
                              compareFn: (a, b) =>
                                  a['countryCode'] == b['countryCode'],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedCountry = v);
                                  _loadStates(v['countryCode'] as String);
                                }
                              },
                              validator: (v) => v == null
                                  ? 'El país es requerido'
                                  : null,
                              dropdownBuilder: (ctx, item) => item == null
                                  ? Text('Selecciona un país',
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.grey[500]))
                                  : Row(children: [
                                      CountryFlag.fromCountryCode(
                                        item['countryCode'] as String,
                                        width: 24,
                                        height: 16,
                                        borderRadius: 3,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(item['countryName'] as String,
                                          style: TextStyle(
                                              color: textPrimary,
                                              fontSize: 15)),
                                    ]),
                              dropdownDecoratorProps: DropDownDecoratorProps(
                                dropdownSearchDecoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      Icons.public_outlined, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  filled: true,
                                  fillColor: cardColor,
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: 'Buscar país...',
                                    prefixIcon:
                                        const Icon(Icons.search, size: 18),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                                menuProps: MenuProps(
                                  backgroundColor:
                                      isDark ? AppTheme.darkCard : Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                itemBuilder: (ctx, item, isSelected) =>
                                    _GeoItem(
                                  label: item['countryName'] as String,
                                  countryCode: item['countryCode'] as String,
                                  isSelected: isSelected,
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                ),
                              ),
                            ),
                      const SizedBox(height: 16),

                      // Provincia / Estado
                      _FieldLabel(label: 'Provincia / Estado *'),
                      const SizedBox(height: 8),
                      _loadingStates
                          ? const _LoadingDropdown(
                              label: 'Cargando provincias...')
                          : DropdownSearch<Map<String, dynamic>>(
                              enabled: _selectedCountry != null,
                              selectedItem: _selectedState,
                              items: _geoStates,
                              filterFn: (item, filter) =>
                                  (item['name'] as String)
                                      .toLowerCase()
                                      .contains(filter.toLowerCase()),
                              itemAsString: (s) => s['name'] as String,
                              compareFn: (a, b) =>
                                  a['geonameId'] == b['geonameId'],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedState = v);
                                  _loadCities(
                                    _selectedCountry!['countryCode'] as String,
                                    v['adminCode1'] as String,
                                  );
                                }
                              },
                              validator: (v) => v == null
                                  ? 'La provincia es requerida'
                                  : null,
                              dropdownBuilder: (ctx, item) => item == null
                                  ? Text(
                                      _selectedCountry == null
                                          ? 'Selecciona un país primero'
                                          : 'Selecciona una provincia',
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.grey[500]))
                                  : Text(item['name'] as String,
                                      style: TextStyle(
                                          color: textPrimary, fontSize: 15)),
                              dropdownDecoratorProps: DropDownDecoratorProps(
                                dropdownSearchDecoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      Icons.location_city_outlined, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  filled: true,
                                  fillColor: cardColor,
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: 'Buscar provincia...',
                                    prefixIcon:
                                        const Icon(Icons.search, size: 18),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                                menuProps: MenuProps(
                                  backgroundColor:
                                      isDark ? AppTheme.darkCard : Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                      const SizedBox(height: 16),

                      // Ciudad / Municipio
                      _FieldLabel(label: 'Ciudad / Municipio *'),
                      const SizedBox(height: 8),
                      _loadingCities
                          ? const _LoadingDropdown(
                              label: 'Cargando ciudades...')
                          : DropdownSearch<Map<String, dynamic>>(
                              enabled: _selectedState != null,
                              selectedItem: _selectedCity,
                              items: _geoCities,
                              filterFn: (item, filter) =>
                                  (item['name'] as String)
                                      .toLowerCase()
                                      .contains(filter.toLowerCase()),
                              itemAsString: (c) => c['name'] as String,
                              compareFn: (a, b) =>
                                  a['geonameId'] == b['geonameId'],
                              onChanged: (v) =>
                                  setState(() => _selectedCity = v),
                              validator: (v) => v == null
                                  ? 'La ciudad es requerida'
                                  : null,
                              dropdownBuilder: (ctx, item) => item == null
                                  ? Text(
                                      _selectedState == null
                                          ? 'Selecciona una provincia primero'
                                          : 'Selecciona una ciudad',
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.grey[500]))
                                  : Text(item['name'] as String,
                                      style: TextStyle(
                                          color: textPrimary, fontSize: 15)),
                              dropdownDecoratorProps: DropDownDecoratorProps(
                                dropdownSearchDecoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      Icons.place_outlined, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  filled: true,
                                  fillColor: cardColor,
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: 'Buscar ciudad...',
                                    prefixIcon:
                                        const Icon(Icons.search, size: 18),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                                menuProps: MenuProps(
                                  backgroundColor:
                                      isDark ? AppTheme.darkCard : Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Teléfono *'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Dial code badge (from selected country)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_selectedCountry != null) ...
                                  [
                                    CountryFlag.fromCountryCode(
                                      _selectedCountry!['countryCode']
                                          as String,
                                      width: 22,
                                      height: 15,
                                      borderRadius: 3,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                Text(
                                  _selectedCountry?['dialCode'] as String? ??
                                      '+?',
                                  style:
                                      theme.textTheme.bodyLarge?.copyWith(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Número de teléfono',
                                prefixIcon:
                                    Icon(Icons.phone_outlined, size: 20),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'El teléfono es requerido';
                                }
                                if (!RegExp(r'^\d{6,15}$')
                                    .hasMatch(v.trim())) {
                                  return 'Número inválido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── SECTION: Documento de identidad ─────────────────
                      _SectionHeader(title: 'Documento de Identidad'),
                      const SizedBox(height: 8),
                      Text(
                        'Sube foto del frente y dorso de tu documento. '
                        'Es obligatorio para verificar tu cuenta.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white54
                              : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Tipo de Documento *'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedDocType,
                        dropdownColor:
                            isDark ? AppTheme.darkCard : Colors.white,
                        style: TextStyle(color: textPrimary),
                        decoration: const InputDecoration(
                          prefixIcon:
                              Icon(Icons.badge_outlined, size: 20),
                        ),
                        items: _docTypes
                            .map((d) => DropdownMenuItem<String>(
                                  value: d,
                                  child: Text(d),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedDocType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Foto del Frente *'),
                      const SizedBox(height: 8),
                      _DocUploadTile(
                        label: 'Frente del documento',
                        imageUrl: _docFrenteUrl,
                        isUploading: _isUploadingFrente,
                        isDark: isDark,
                        onTap: () => _pickDocument(isFront: true),
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Foto del Dorso *'),
                      const SizedBox(height: 8),
                      _DocUploadTile(
                        label: 'Dorso del documento',
                        imageUrl: _docDorsoUrl,
                        isUploading: _isUploadingDorso,
                        isDark: isDark,
                        onTap: () => _pickDocument(isFront: false),
                      ),

                      const SizedBox(height: 28),

                      // ── SECTION: Tipo de cuenta ──────────────────────────
                      _SectionHeader(title: 'Tipo de Cuenta'),
                      const SizedBox(height: 16),

                      _buildTypeSelector(isDark, textPrimary),

                      // ── Sub-selector: passenger vs cargo transportista ───
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _selectedTopType == 'transportista'
                            ? Padding(
                                key: const ValueKey('transportista_sub'),
                                padding: const EdgeInsets.only(top: 16),
                                child: _buildTransportistaSubSelector(
                                    isDark, textPrimary),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('no_sub')),
                      ),

                      // ── Conditional extra fields ─────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildConditionalFields(
                            isDark, textPrimary, cardColor, borderColor),
                      ),

                      // ── Plan info (solo para tipos con plan de carga) ─────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildPlanInfo(isDark, textPrimary),
                      ),

                      const SizedBox(height: 32),

                      // ── Register button ─────────────────────────────────
                      Consumer<AuthProvider>(
                        builder: (context, auth, _) {
                          return ElevatedButton(
                            onPressed: auth.isLoading
                                ? null
                                : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                              disabledBackgroundColor: AppTheme
                                  .primaryColor
                                  .withValues(alpha: 0.5),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : Text(
                                    'Crear Cuenta',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: TextSpan(
                              text: '¿Ya tienes cuenta? ',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: textSecondary),
                              children: [
                                TextSpan(
                                  text: 'Inicia Sesión',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                );

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: kIsWeb
            ? _RegisterWebShell(
                isDark: isDark,
                header: header,
                form: form,
              )
            : Column(
                children: [
                  header,
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: form,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Type selector: 4 option cards
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTypeSelector(bool isDark, Color textPrimary) {
    final options = [
      _TypeOption(
        value: 'cliente_pasajero',
        icon: Icons.person_outline,
        label: 'Cliente de Viajes',
        subtitle: 'Solicitar viajes urbanos',
      ),
      _TypeOption(
        value: 'shipper',
        icon: Icons.inventory_2_outlined,
        label: 'Shipper de Carga',
        subtitle: 'Publicar y gestionar envíos',
      ),
      _TypeOption(
        value: 'transportista',
        icon: Icons.local_shipping_outlined,
        label: 'Transportista',
        subtitle: 'Ofrecer servicios de transporte',
      ),
      _TypeOption(
        value: 'dispatcher',
        icon: Icons.dashboard_outlined,
        label: 'Dispatcher',
        subtitle: 'Gestionar flota y choferes',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: options
          .map((opt) => _TypeCard(
                option: opt,
                isSelected: _selectedTopType == opt.value,
                isDark: isDark,
                onTap: () => setState(() {
                  _selectedTopType = opt.value;
                }),
              ))
          .toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Plan info section shown during registration
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPlanInfo(bool isDark, Color textPrimary) {
    final tipo = _tipoUsuarioFinal;
    final tiposConPlan = ['shipper', 'carrier_carga', 'dispatcher'];
    if (!tiposConPlan.contains(tipo)) {
      return const SizedBox.shrink(key: ValueKey('no_plan'));
    }

    final String planNombre;
    final String precio;
    final String descripcion;
    final List<String> planNombresUpgrade;

    switch (tipo) {
      case 'shipper':
        planNombre = 'Shipper Gratis';
        precio = '\$0 / primer mes';
        descripcion = 'Publica cargas y conecta con transportistas. Después del primer mes, el plan Shipper es de \$50/mes.';
        planNombresUpgrade = ['Shipper — \$50/mes'];
        break;
      case 'carrier_carga':
        planNombre = 'Carrier Gratis';
        precio = '\$0 / primer mes';
        descripcion = 'Recibe cargas y gestiona tus viajes. Después del primer mes puedes continuar con el plan Básico (\$20/mes) o el PRO (\$40/mes).';
        planNombresUpgrade = ['Básico — \$20/mes', 'PRO — \$40/mes'];
        break;
      case 'dispatcher':
        planNombre = 'Dispatcher Gratis';
        precio = '\$0 / primer mes';
        descripcion = 'Gestiona tu flota y asigna cargas. Después del primer mes, el plan Dispatcher es de \$150/mes.';
        planNombresUpgrade = ['Dispatcher — \$150/mes'];
        break;
      default:
        return const SizedBox.shrink(key: ValueKey('no_plan_default'));
    }

    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[200]!;
    final textSec = isDark ? Colors.white60 : Colors.grey[600]!;

    return Padding(
      key: ValueKey('plan_info_$tipo'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu plan al registrarte',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard_outlined,
                        color: AppTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      planNombre,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.success),
                    ),
                    const Spacer(),
                    Text(
                      precio,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(descripcion,
                    style: TextStyle(fontSize: 13, color: textSec, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planes disponibles después del primer mes',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary),
                ),
                const SizedBox(height: 8),
                ...planNombresUpgrade.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 15,
                              color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Text(p,
                              style: TextStyle(
                                  fontSize: 13, color: textSec)),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                Text(
                  'Puedes gestionar tu plan en cualquier momento desde tu perfil.',
                  style: TextStyle(
                      fontSize: 12,
                      color: textSec,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Sub-selector: passenger vs cargo for transportista
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTransportistaSubSelector(bool isDark, Color textPrimary) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: 'Tipo de transporte'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SubTypeToggle(
                icon: Icons.directions_car_outlined,
                label: 'Pasajeros',
                subtitle: 'Viajes urbanos',
                isSelected:
                    _selectedTransportistaSubtype == 'conductor_pasajeros',
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
                onTap: () => setState(
                    () => _selectedTransportistaSubtype = 'conductor_pasajeros'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SubTypeToggle(
                icon: Icons.local_shipping_outlined,
                label: 'Carga',
                subtitle: 'Envíos y encomiendas',
                isSelected:
                    _selectedTransportistaSubtype == 'carrier_carga',
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
                onTap: () => setState(
                    () => _selectedTransportistaSubtype = 'carrier_carga'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Conditional extra fields per type
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildConditionalFields(
      bool isDark, Color textPrimary, Color cardColor, Color borderColor) {
    final tipo = _tipoUsuarioFinal;

    if (tipo == 'shipper') {
      return Padding(
        key: const ValueKey('shipper_fields'),
        padding: const EdgeInsets.only(top: 24),
        child: _buildShipperFields(isDark, textPrimary, cardColor, borderColor),
      );
    }

    if (tipo == 'carrier_carga') {
      return Padding(
        key: const ValueKey('carrier_fields'),
        padding: const EdgeInsets.only(top: 24),
        child: _buildCarrierFields(isDark, textPrimary, cardColor, borderColor),
      );
    }

    if (tipo == 'dispatcher') {
      return Padding(
        key: const ValueKey('dispatcher_fields'),
        padding: const EdgeInsets.only(top: 24),
        child: _buildDispatcherFields(isDark, textPrimary, cardColor, borderColor),
      );
    }

    if (tipo == 'conductor_pasajeros') {
      return Padding(
        key: const ValueKey('conductor_pasajeros_fields'),
        padding: const EdgeInsets.only(top: 24),
        child: _buildConductorPasajerosFields(
            isDark, textPrimary, cardColor, borderColor),
      );
    }

    // cliente_pasajero: no extra fields
    return const SizedBox.shrink(key: ValueKey('no_extra'));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Conductor pasajeros — vehicle data
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildConductorPasajerosFields(
      bool isDark, Color textPrimary, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Datos del Vehículo'),
        const SizedBox(height: 16),

        // Tipo de vehículo (chips loaded from DB)
        _FieldLabel(label: 'Tipo de vehículo *'),
        const SizedBox(height: 8),
        _dbVehicleTypes.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dbVehicleTypes.map((vt) {
                  final selected = _vIdTipo == vt.id;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(vt.icon,
                            size: 16,
                            color: selected
                                ? AppTheme.primaryColor
                                : textPrimary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(vt.displayName),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _vIdTipo = vt.id;
                      if (_vCapacidadController.text.isEmpty) {
                        _vCapacidadController.text =
                            vt.passengerCount.toString();
                      }
                    }),
                    selectedColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: selected ? AppTheme.primaryColor : textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  );
                }).toList(),
              ),
        const SizedBox(height: 16),

        // Marca / Modelo
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(label: 'Marca *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _vMarcaController,
                    style: TextStyle(color: textPrimary),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        hintText: 'Ej. Toyota'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(label: 'Modelo *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _vModeloController,
                    style: TextStyle(color: textPrimary),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        hintText: 'Ej. Corolla'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Chapa / Matrícula
        _FieldLabel(label: 'Chapa / Matrícula *'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _vChapaController,
          style: TextStyle(color: textPrimary),
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Ej. ABC-1234',
            prefixIcon: Icon(Icons.pin_outlined, size: 20),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'La chapa es requerida' : null,
        ),
        const SizedBox(height: 16),

        // Color / Año
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(label: 'Color'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _vColorController,
                    style: TextStyle(color: textPrimary),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        hintText: 'Ej. Blanco'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(label: 'Anio'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _vAnioController,
                    style: TextStyle(color: textPrimary),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: 'Ej. 2019'),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        final y = int.tryParse(v.trim());
                        if (y == null || y < 1950 || y > 2030) {
                          return 'Anio inválido';
                        }
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Capacidad de pasajeros
        _FieldLabel(label: 'Capacidad de pasajeros *'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _vCapacidadController,
          style: TextStyle(color: textPrimary),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Número de asientos disponibles',
            prefixIcon: Icon(Icons.people_outline, size: 20),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Requerido';
            final n = int.tryParse(v.trim());
            if (n == null || n < 1 || n > 60) {
              return 'Ingresa un número válido (1-60)';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Condición del vehículo
        _FieldLabel(label: 'Condición del vehículo'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _vCondicion,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.star_outline, size: 20),
          ),
          items: const [
            DropdownMenuItem(value: 'excelente', child: Text('Excelente')),
            DropdownMenuItem(value: 'bueno',     child: Text('Bueno')),
            DropdownMenuItem(value: 'regular',   child: Text('Regular')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _vCondicion = v);
          },
        ),
        const SizedBox(height: 16),

        // Aire acondicionado
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: SwitchListTile(
            title: Text(
              'Aire acondicionado',
              style: GoogleFonts.plusJakartaSans(
                  color: textPrimary, fontWeight: FontWeight.w500),
            ),
            secondary: const Icon(Icons.ac_unit_outlined),
            value: _vAireAcondicionado,
            activeColor: AppTheme.primaryColor,
            onChanged: (v) => setState(() => _vAireAcondicionado = v),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Shipper extra fields
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildShipperFields(
      bool isDark, Color textPrimary, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Información de Empresa / Carga'),
        const SizedBox(height: 16),

        _FieldLabel(label: 'Tipo de cuenta'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _shipperTipoCuenta,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.business_outlined, size: 20),
          ),
          items: _tiposCuentaShipper
              .map((t) => DropdownMenuItem<String>(
                    value: t,
                    child: Text(t[0].toUpperCase() + t.substring(1)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _shipperTipoCuenta = v);
          },
        ),

        if (_shipperTipoCuenta == 'empresa' ||
            _shipperTipoCuenta == 'cooperativa') ...[
          const SizedBox(height: 16),
          _FieldLabel(label: 'Nombre de la empresa *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _empresaNombreController,
            style: TextStyle(color: textPrimary),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Razón social',
              prefixIcon: Icon(Icons.business, size: 20),
            ),
            validator: (v) {
              if ((_shipperTipoCuenta == 'empresa' ||
                      _shipperTipoCuenta == 'cooperativa') &&
                  (v == null || v.trim().isEmpty)) {
                return 'El nombre de la empresa es requerido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'RUT / Número fiscal *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _empresaRutController,
            style: TextStyle(color: textPrimary),
            decoration: const InputDecoration(
              hintText: 'Número de identificación fiscal',
              prefixIcon: Icon(Icons.tag, size: 20),
            ),
            validator: (v) {
              if ((_shipperTipoCuenta == 'empresa' ||
                      _shipperTipoCuenta == 'cooperativa') &&
                  (v == null || v.trim().isEmpty)) {
                return 'El número fiscal es requerido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Dirección de la empresa'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _empresaDireccionController,
            style: TextStyle(color: textPrimary),
            decoration: const InputDecoration(
              hintText: 'Dirección comercial',
              prefixIcon: Icon(Icons.location_on_outlined, size: 20),
            ),
          ),
        ],

        const SizedBox(height: 24),
        _FieldLabel(label: 'Mercancías que maneja habitualmente (opcional)'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _mercaderiaOpciones.map((m) {
            final selected = _mercaderiasSeleccionadas.contains(m);
            return FilterChip(
              label: Text(m),
              selected: selected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _mercaderiasSeleccionadas.add(m);
                  } else {
                    _mercaderiasSeleccionadas.remove(m);
                  }
                });
              },
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              checkmarkColor: AppTheme.primaryColor,
              labelStyle: GoogleFonts.plusJakartaSans(
                color: selected ? AppTheme.primaryColor : textPrimary,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Carrier extra fields — multi-carrocería
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildCarrierFields(
      bool isDark, Color textPrimary, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row with "Add vehicle" button ───────────────────────────
        Row(
          children: [
            Expanded(
              child: _SectionHeader(title: 'Vehículos de Carga'),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _carrocerias.add(_CarroceriaItem())),
              icon: const Icon(Icons.add_circle_outline,
                  color: AppTheme.primaryColor, size: 20),
              label: Text(
                'Agregar',
                style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Puedes registrar todas las plataformas / carrocerías que operas.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600]),
        ),
        const SizedBox(height: 16),

        // ── One card per carrocería ────────────────────────────────────────
        ...List.generate(_carrocerias.length, (index) {
          final item = _carrocerias[index];
          return _buildCarroceriaCard(
            index: index,
            item: item,
            isDark: isDark,
            textPrimary: textPrimary,
            cardColor: cardColor,
            borderColor: borderColor,
          );
        }),

        const SizedBox(height: 24),
        _SectionHeader(title: 'Verificación Profesional (opcional)'),
        const SizedBox(height: 8),
        Text(
          'Requerida para operar con escrow. Puedes completarla después del registro.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600]),
        ),
        const SizedBox(height: 16),

        _FieldLabel(label: 'MC Number'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mcNumberController,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            hintText: 'Motor Carrier Number',
            prefixIcon: Icon(Icons.numbers_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 16),

        _FieldLabel(label: 'DOT Number'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dotNumberController,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            hintText: 'DOT Number',
            prefixIcon: Icon(Icons.numbers_outlined, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildCarroceriaCard({
    required int index,
    required _CarroceriaItem item,
    required bool isDark,
    required Color textPrimary,
    required Color cardColor,
    required Color borderColor,
  }) {
    final isFirst = index == 0;
    return StatefulBuilder(
      key: ValueKey(item),
      builder: (ctx, setLocal) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFirst
                  ? AppTheme.primaryColor.withValues(alpha: 0.4)
                  : borderColor,
              width: isFirst ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Vehículo ${index + 1}',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (!isFirst)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppTheme.error, size: 20),
                        tooltip: 'Eliminar vehículo',
                        onPressed: () => setState(() {
                          item.dispose();
                          _carrocerias.removeAt(index);
                        }),
                      ),
                  ],
                ),
              ),
              const Divider(height: 20, indent: 16, endIndent: 16),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tipo carrocería
                    _FieldLabel(label: 'Tipo de carrocería *'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: item.tipoCarroceria,
                      dropdownColor:
                          isDark ? AppTheme.darkCard : Colors.white,
                      style: TextStyle(color: textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Selecciona el tipo',
                        prefixIcon: Icon(
                            Icons.local_shipping_outlined, size: 20),
                      ),
                      items: _tiposCarroceria
                          .map((t) => DropdownMenuItem<String>(
                                value: t,
                                child: Text(t),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setLocal(() => item.tipoCarroceria = v);
                        setState(() {});
                      },
                      validator: (v) => v == null
                          ? 'El tipo de carrocería es requerido'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // Marca / Modelo
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: 'Marca'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: item.marca,
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                    hintText: 'Ej. Volvo'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: 'Modelo'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: item.modelo,
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                    hintText: 'Ej. FH16'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Matrícula
                    _FieldLabel(label: 'Matrícula / Chapa *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: item.matricula,
                      style: TextStyle(color: textPrimary),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'Ej. ABC-1234',
                        prefixIcon: Icon(Icons.pin_outlined, size: 20),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'La matrícula es requerida'
                              : null,
                    ),
                    const SizedBox(height: 14),

                    // Capacidad / Longitud
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: 'Capacidad (ton) *'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: item.capacidadTon,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                    hintText: 'Ej. 22.5'),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Requerido';
                                  }
                                  if (double.tryParse(v.trim()) == null) {
                                    return 'Número inválido';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: 'Long. (m)'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: item.longitudM,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                    hintText: 'Ej. 13.6'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Seguro vigente
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: SwitchListTile(
                        dense: true,
                        title: Text(
                          'Seguro de carga vigente',
                          style: GoogleFonts.plusJakartaSans(
                              color: textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
                        ),
                        value: item.seguroVigente,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (v) =>
                            setLocal(() => item.seguroVigente = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Dispatcher extra fields
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDispatcherFields(
      bool isDark, Color textPrimary, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Datos de la Empresa Despachadora'),
        const SizedBox(height: 16),

        _FieldLabel(label: 'Nombre de la empresa *'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dispEmpresaNombreController,
          style: TextStyle(color: textPrimary),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Razón social',
            prefixIcon: Icon(Icons.business, size: 20),
          ),
          validator: (v) =>
              (_tipoUsuarioFinal == 'dispatcher' &&
                      (v == null || v.trim().isEmpty))
                  ? 'El nombre de la empresa es requerido'
                  : null,
        ),
        const SizedBox(height: 16),

        _FieldLabel(label: 'RUT / Número fiscal *'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dispEmpresaRutController,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            hintText: 'Número de identificación fiscal',
            prefixIcon: Icon(Icons.tag, size: 20),
          ),
          validator: (v) =>
              (_tipoUsuarioFinal == 'dispatcher' &&
                      (v == null || v.trim().isEmpty))
                  ? 'El número fiscal es requerido'
                  : null,
        ),
        const SizedBox(height: 16),

        _FieldLabel(label: 'Dirección de la empresa'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dispEmpresaDireccionController,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
            hintText: 'Dirección comercial',
            prefixIcon: Icon(Icons.location_on_outlined, size: 20),
          ),
        ),

        const SizedBox(height: 28),

        // ── Transportistas list ─────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _SectionHeader(title: 'Transportistas que Gestionarás'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Debes registrar al menos un transportista para completar el registro.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),

        // Transportista cards
        ...List.generate(_transportistas.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TransportistaFormCard(
              index: i,
              item: _transportistas[i],
              isDark: isDark,
              textPrimary: textPrimary,
              tiposCarroceria: _tiposCarroceria,
              canRemove: _transportistas.length > 1,
              onRemove: () => setState(() => _transportistas.removeAt(i)),
              onChanged: () => setState(() {}),
            ),
          );
        }),

        // Add button
        TextButton.icon(
          onPressed: () => setState(() => _transportistas.add(_TransportistaItem())),
          icon: const Icon(Icons.add_circle_outline,
              color: AppTheme.primaryColor),
          label: Text(
            'Agregar transportista',
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Web shell: scrollable card layout with background image + scroll hint
// ─────────────────────────────────────────────────────────────────────────────
class _RegisterWebShell extends StatefulWidget {
  final bool isDark;
  final Widget header;
  final Widget form;
  const _RegisterWebShell({
    required this.isDark,
    required this.header,
    required this.form,
  });

  @override
  State<_RegisterWebShell> createState() => _RegisterWebShellState();
}

class _RegisterWebShellState extends State<_RegisterWebShell> {
  final ScrollController _scrollController = ScrollController();
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final canScroll = max > 0 && (max - current) > 16;
    if (canScroll != _showHint) {
      setState(() => _showHint = canScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            isDark
                ? 'assets/images/back_oscuro.png'
                : 'assets/images/back_claro.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: AppTheme.bg(isDark)),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppTheme.darkBg.withValues(alpha: 0.45),
                        AppTheme.darkBg.withValues(alpha: 0.75),
                      ]
                    : [
                        AppTheme.lightBg.withValues(alpha: 0.35),
                        AppTheme.lightBg.withValues(alpha: 0.70),
                      ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 10,
              radius: const Radius.circular(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      decoration: BoxDecoration(
                        color: AppTheme.card(isDark)
                            .withValues(alpha: isDark ? 0.92 : 0.97),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border(isDark)),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.45)
                                : const Color(0x1F0A1D37),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          widget.header,
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            child: widget.form,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: Center(
              child: _ScrollHint(isDark: isDark, visible: _showHint),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollHint extends StatefulWidget {
  final bool isDark;
  final bool visible;
  const _ScrollHint({required this.isDark, required this.visible});

  @override
  State<_ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<_ScrollHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dy = (1 - _controller.value) * 4;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.card(widget.isDark)
                    .withValues(alpha: widget.isDark ? 0.85 : 0.95),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.border(widget.isDark)),
                boxShadow: [
                  BoxShadow(
                    color: widget.isDark
                        ? Colors.black.withValues(alpha: 0.35)
                        : const Color(0x140A1D37),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Desliza para más',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(widget.isDark),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary(widget.isDark),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transportista form card widget (used inside dispatcher flow)
// ─────────────────────────────────────────────────────────────────────────────
class _TransportistaFormCard extends StatelessWidget {
  final int index;
  final _TransportistaItem item;
  final bool isDark;
  final Color textPrimary;
  final List<String> tiposCarroceria;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _TransportistaFormCard({
    required this.index,
    required this.item,
    required this.isDark,
    required this.textPrimary,
    required this.tiposCarroceria,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Transportista ${index + 1}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close,
                      size: 18, color: Colors.redAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Name
          TextFormField(
            controller: item.nombre,
            style: TextStyle(color: textPrimary),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo *',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
            validator: (v) {
              if (index == 0 && (v == null || v.trim().isEmpty)) {
                return 'El nombre es requerido';
              }
              return null;
            },
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),

          // Email
          TextFormField(
            controller: item.email,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: textPrimary),
            decoration: const InputDecoration(
              labelText: 'Email *',
              prefixIcon: Icon(Icons.email_outlined, size: 18),
            ),
            validator: (v) {
              if (index == 0 && (v == null || v.trim().isEmpty)) {
                return 'El email es requerido';
              }
              if (v != null &&
                  v.trim().isNotEmpty &&
                  !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(v.trim())) {
                return 'Email inválido';
              }
              return null;
            },
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),

          // Phone
          TextFormField(
            controller: item.telefono,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: textPrimary),
            decoration: const InputDecoration(
              labelText: 'Teléfono *',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
            validator: (v) {
              if (index == 0 && (v == null || v.trim().isEmpty)) {
                return 'El teléfono es requerido';
              }
              return null;
            },
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),

          // Tipo carrocería
          DropdownButtonFormField<String>(
            value: item.tipoCarroceria,
            dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
            style: TextStyle(color: textPrimary),
            decoration: const InputDecoration(
              labelText: 'Tipo de carrocería',
              prefixIcon:
                  Icon(Icons.local_shipping_outlined, size: 18),
            ),
            items: tiposCarroceria
                .map((t) => DropdownMenuItem<String>(
                      value: t,
                      child: Text(t),
                    ))
                .toList(),
            onChanged: (v) {
              item.tipoCarroceria = v;
              onChanged();
            },
          ),
          const SizedBox(height: 12),

          // Marca + modelo
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.marca,
                  style: TextStyle(color: textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Marca'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: item.modelo,
                  style: TextStyle(color: textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Modelo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Matrícula + capacidad
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.matricula,
                  style: TextStyle(color: textPrimary),
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Matrícula'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: item.capacidadTon,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  style: TextStyle(color: textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Cap. (ton)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // MC + DOT
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.mcNumber,
                  style: TextStyle(color: textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'MC Number'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: item.dotNumber,
                  style: TextStyle(color: textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'DOT Number'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type option data class
// ─────────────────────────────────────────────────────────────────────────────
class _TypeOption {
  final String value;
  final IconData icon;
  final String label;
  final String subtitle;

  const _TypeOption({
    required this.value,
    required this.icon,
    required this.label,
    required this.subtitle,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Type card widget
// ─────────────────────────────────────────────────────────────────────────────
class _TypeCard extends StatelessWidget {
  final _TypeOption option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _TypeCard({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textMuted =
        isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey[500]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 28,
              color: isSelected ? AppTheme.primaryColor : textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              option.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.primaryColor : textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              option.subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-type toggle (passenger / cargo)
// ─────────────────────────────────────────────────────────────────────────────
class _SubTypeToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final bool isDark;
  final Color cardColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _SubTypeToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textMuted =
        isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey[500]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 24,
                color: isSelected ? AppTheme.primaryColor : textMuted),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.primaryColor : textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document upload tile
// ─────────────────────────────────────────────────────────────────────────────
class _DocUploadTile extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final bool isUploading;
  final bool isDark;
  final VoidCallback onTap;

  const _DocUploadTile({
    required this.label,
    required this.imageUrl,
    required this.isUploading,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: imageUrl != null
                ? AppTheme.success
                : isDark
                    ? AppTheme.darkBorder
                    : Colors.grey[300]!,
            width: imageUrl != null ? 2 : 1,
          ),
        ),
        child: isUploading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primaryColor, strokeWidth: 2.5))
            : imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                                  child: Icon(Icons.check_circle,
                                      color: AppTheme.success, size: 40),
                                )),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: AppTheme.success,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 16),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('Cambiar',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          size: 32,
                          color: isDark ? Colors.white38 : Colors.grey[500]),
                      const SizedBox(height: 8),
                      Text(label,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Toca para subir',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: AppTheme.primaryColor)),
                    ],
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Loading placeholder for dropdowns while GeoNames fetch is in progress
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingDropdown extends StatelessWidget {
  final String label;
  const _LoadingDropdown({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color:
                      isDark ? Colors.white38 : Colors.grey[500])),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row item shown inside the country popup list (flag + name)
// ─────────────────────────────────────────────────────────────────────────────
class _GeoItem extends StatelessWidget {
  final String label;
  final String countryCode;
  final bool isSelected;
  final bool isDark;
  final Color textPrimary;

  const _GeoItem({
    required this.label,
    required this.countryCode,
    required this.isSelected,
    required this.isDark,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isSelected
          ? AppTheme.primaryColor.withValues(alpha: 0.1)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CountryFlag.fromCountryCode(
            countryCode,
            width: 26,
            height: 18,
            borderRadius: 3,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: isSelected ? AppTheme.primaryColor : textPrimary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (isSelected)
            const Icon(Icons.check, color: AppTheme.primaryColor, size: 18),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: isDark ? Colors.white : const Color(0xFF1A1D27),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color:
                isDark ? Colors.white.withValues(alpha: 0.8) : Colors.grey[700],
          ),
    );
  }
}
