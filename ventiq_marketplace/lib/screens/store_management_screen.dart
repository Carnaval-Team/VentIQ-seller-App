import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/store_management_service.dart';
import '../services/user_session_service.dart';
import '../widgets/supabase_image.dart';
import 'create_product_screen.dart';
import 'product_management_detail_screen.dart';
import 'store_location_picker_screen.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key});

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen> {
  final _sessionService = UserSessionService();
  final _storeService = StoreManagementService();
  final _picker = ImagePicker();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _stores = [];
  int _selectedStoreIndex = 0;

  bool _isProductsLoading = false;
  String? _productsErrorMessage;
  List<Map<String, dynamic>> _products = [];

  final _createFormKey = GlobalKey<FormState>();
  final _denominacionController = TextEditingController();
  final _direccionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _paisController = TextEditingController();
  final _estadoController = TextEditingController();
  final _nombrePaisController = TextEditingController();
  final _nombreEstadoController = TextEditingController();

  LatLng? _selectedLocation;
  String? _imageUrl;
  bool _isUploadingImage = false;
  TimeOfDay _horaApertura = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _horaCierre = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _phoneController.dispose();
    _paisController.dispose();
    _estadoController.dispose();
    _nombrePaisController.dispose();
    _nombreEstadoController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final selectedStoreIdBefore = _getSelectedStoreId();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uuid = await _sessionService.getUserId();
      if (uuid == null) {
        setState(() {
          _isLoading = false;
          _stores = [];
        });
        return;
      }

      final storeIds = await _storeService.getManagedStoreIds(uuid: uuid);
      final stores = await _storeService.getStoresByIds(storeIds);

      var newSelectedIndex = 0;
      if (selectedStoreIdBefore != null) {
        final idx = stores.indexWhere((s) {
          final id = s['id'];
          final sid = id is int ? id : (id is num ? id.toInt() : null);
          return sid == selectedStoreIdBefore;
        });
        if (idx >= 0) newSelectedIndex = idx;
      }

      setState(() {
        _stores = stores;
        _selectedStoreIndex = newSelectedIndex;
        _isLoading = false;
      });

      await _loadProductsForSelectedStore();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error cargando tu tienda: $e';
      });
    }
  }

  int? _getSelectedStoreId() {
    if (_stores.isEmpty) return null;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return null;
    }
    final store = _stores[_selectedStoreIndex];
    final id = store['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  bool _isSelectedStoreValidated() {
    if (_stores.isEmpty) return false;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return false;
    }
    return _stores[_selectedStoreIndex]['validada'] == true;
  }

  bool _isSelectedStoreVisibleInCatalog() {
    if (_stores.isEmpty) return false;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return false;
    }
    return _stores[_selectedStoreIndex]['mostrar_en_catalogo'] == true;
  }

  bool _isSelectedStoreEffectivelyActive() {
    return _isSelectedStoreValidated() && _isSelectedStoreVisibleInCatalog();
  }

  Future<void> _loadProductsForSelectedStore() async {
    final storeId = _getSelectedStoreId();
    if (storeId == null) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _isProductsLoading = false;
        _productsErrorMessage = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isProductsLoading = true;
        _productsErrorMessage = null;
      });
    }

    try {
      final products = await _storeService.getStoreProductsOverview(
        storeId: storeId,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _isProductsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _isProductsLoading = false;
        _productsErrorMessage = 'Error cargando productos: $e';
      });
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            StoreLocationPickerScreen(initialLocation: _selectedLocation),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedLocation = result;
    });

    await _tryFillFromCoordinates(result);
  }

  Future<void> _tryFillFromCoordinates(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isEmpty) return;

      final p = placemarks.first;

      final iso = (p.isoCountryCode ?? '').trim();
      final country = (p.country ?? '').trim();
      final admin = (p.administrativeArea ?? '').trim();

      final street = (p.street ?? '').trim();
      final subLocality = (p.subLocality ?? '').trim();
      final locality = (p.locality ?? '').trim();
      final subAdmin = (p.subAdministrativeArea ?? '').trim();

      final addressParts = <String>[
        if (street.isNotEmpty) street,
        if (subLocality.isNotEmpty) subLocality,
        if (locality.isNotEmpty) locality,
        if (subAdmin.isNotEmpty) subAdmin,
        if (admin.isNotEmpty) admin,
        if (country.isNotEmpty) country,
      ];
      final address = addressParts.join(', ');

      if (_direccionController.text.trim().isEmpty && address.isNotEmpty) {
        _direccionController.text = address;
      }

      if (_paisController.text.trim().isEmpty && iso.length == 2) {
        _paisController.text = iso;
      }
      if (_nombrePaisController.text.trim().isEmpty && country.isNotEmpty) {
        _nombrePaisController.text = country;
      }
      if (_nombreEstadoController.text.trim().isEmpty && admin.isNotEmpty) {
        _nombreEstadoController.text = admin;
      }
    } catch (_) {}
  }

  String _formatTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = isOpen ? _horaApertura : _horaCierre;
    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked == null || !mounted) return;

    setState(() {
      if (isOpen) {
        _horaApertura = picked;
      } else {
        _horaCierre = picked;
      }
    });
  }

  Future<void> _pickImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.paddingM),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Elegir de galería'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;
    await _pickAndUploadImage(source);
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      setState(() => _isUploadingImage = true);

      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1400,
        imageQuality: 82,
      );

      if (file == null) {
        if (mounted) setState(() => _isUploadingImage = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final url = await _uploadStoreImage(bytes);

      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _isUploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error subiendo imagen: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<String> _uploadStoreImage(Uint8List bytes) async {
    final fileName = 'store_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage
        .from('images_back')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _supabase.storage.from('images_back').getPublicUrl(fileName);
  }

  Future<void> _createStore() async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la ubicación en el mapa'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_imageUrl == null || _imageUrl!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una imagen para la tienda'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    final uuid = await _sessionService.getUserId();
    if (uuid == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final lat = _selectedLocation!.latitude;
      final lng = _selectedLocation!.longitude;
      final ubicacion = '${lat.toStringAsFixed(7)},${lng.toStringAsFixed(7)}';

      final tienda = await _storeService.createStore(
        denominacion: _denominacionController.text.trim(),
        direccion: _direccionController.text.trim(),
        ubicacion: ubicacion,
        imagenUrl: _imageUrl!.trim(),
        phone: _phoneController.text.trim(),
        pais: _paisController.text.trim(),
        estado: _estadoController.text.trim(),
        nombrePais: _nombrePaisController.text.trim(),
        nombreEstado: _nombreEstadoController.text.trim(),
        horaApertura: _formatTime(_horaApertura),
        horaCierre: _formatTime(_horaCierre),
        latitude: lat,
        longitude: lng,
      );

      final storeId = tienda['id'];
      if (storeId is int) {
        await _storeService.ensureGerenteLink(uuid: uuid, storeId: storeId);
      } else if (storeId is num) {
        await _storeService.ensureGerenteLink(
          uuid: uuid,
          storeId: storeId.toInt(),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tienda creada. Queda en validación.'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      await _loadStores();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error creando tienda: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi tienda')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.paddingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store_mall_directory_outlined, size: 56),
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _loadStores,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_stores.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administrar mi tienda')),
        body: _buildCreateStore(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _buildStoreSelector(),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xCCFFFFFF),
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Tienda'),
              Tab(text: 'Productos'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildStoreTab(), _buildProductsTab()]),
      ),
    );
  }

  Widget _buildStoreSelector() {
    if (_stores.length <= 1) {
      return Text((_stores.first['denominacion'] ?? 'Mi tienda').toString());
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _selectedStoreIndex,
        dropdownColor: AppTheme.primaryColor,
        iconEnabledColor: Colors.white,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        items: List.generate(_stores.length, (idx) {
          final store = _stores[idx];
          return DropdownMenuItem<int>(
            value: idx,
            child: Text((store['denominacion'] ?? 'Tienda').toString()),
          );
        }),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _selectedStoreIndex = v);
          _loadProductsForSelectedStore();
        },
      ),
    );
  }

  Widget _buildStoreTab() {
    final store = _stores[_selectedStoreIndex];

    final storeIdRaw = store['id'];
    final int? storeId = storeIdRaw is int
        ? storeIdRaw
        : (storeIdRaw is num ? storeIdRaw.toInt() : null);

    final imageUrl = (store['imagen_url'] ?? '').toString().trim();
    final denominacion = (store['denominacion'] ?? 'Tienda').toString();
    final direccion = (store['direccion'] ?? '').toString();
    final phone = (store['phone'] ?? '').toString();
    final pais = (store['nombre_pais'] ?? store['pais'] ?? '').toString();
    final estado = (store['nombre_estado'] ?? store['estado'] ?? '').toString();
    final horaApertura = (store['hora_apertura'] ?? '').toString();
    final horaCierre = (store['hora_cierre'] ?? '').toString();
    final isValidated = store['validada'] == true;
    final isVisibleInCatalog = store['mostrar_en_catalogo'] == true;
    final effectiveVisible = isValidated && isVisibleInCatalog;

    return RefreshIndicator(
      onRefresh: _loadStores,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.paddingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: SizedBox(
                      height: 190,
                      child: imageUrl.isNotEmpty
                          ? SupabaseImage(
                              imageUrl: imageUrl,
                              width: double.infinity,
                              height: 190,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.store_rounded, size: 48),
                              ),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.paddingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                denominacion,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            _buildValidationChip(isValidated),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (direccion.isNotEmpty)
                          _infoRow(
                            icon: Icons.location_on_outlined,
                            text: direccion,
                          ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(icon: Icons.phone_outlined, text: phone),
                        ],
                        if (pais.isNotEmpty || estado.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                            icon: Icons.public,
                            text: [
                              if (estado.isNotEmpty) estado,
                              if (pais.isNotEmpty) pais,
                            ].join(' · '),
                          ),
                        ],
                        if (horaApertura.isNotEmpty ||
                            horaCierre.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                            icon: Icons.schedule,
                            text: 'Horario: $horaApertura - $horaCierre',
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                effectiveVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: effectiveVisible
                                    ? AppTheme.primaryColor
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  !isValidated
                                      ? 'Visibilidad bloqueada (en validación)'
                                      : (effectiveVisible
                                            ? 'Visible en el catálogo'
                                            : 'Oculta en el catálogo'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Switch(
                                value: isVisibleInCatalog,
                                onChanged: (!isValidated || storeId == null)
                                    ? null
                                    : (value) async {
                                        try {
                                          await _storeService
                                              .updateMostrarEnCatalogo(
                                                storeId: storeId,
                                                mostrarEnCatalogo: value,
                                              );
                                          if (!mounted) return;
                                          setState(() {
                                            final updated =
                                                Map<String, dynamic>.from(
                                                  store,
                                                );
                                            updated['mostrar_en_catalogo'] =
                                                value;
                                            _stores[_selectedStoreIndex] =
                                                updated;
                                          });
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'No se pudo actualizar visibilidad: $e',
                                              ),
                                              backgroundColor:
                                                  AppTheme.errorColor,
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isValidated
                                ? AppTheme.successColor.withOpacity(0.08)
                                : AppTheme.warningColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isValidated
                                    ? Icons.check_circle_outline
                                    : Icons.hourglass_bottom_rounded,
                                color: isValidated
                                    ? AppTheme.successColor
                                    : AppTheme.warningColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isValidated
                                      ? 'Tu tienda fue validada. Puedes decidir si mostrarla en el catálogo.'
                                      : 'Tu tienda está en validación. Mientras tanto no aparecerá en el catálogo y no podrás cambiar su visibilidad.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
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
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    final storeId = _getSelectedStoreId();
    final isStoreValidated = _isSelectedStoreValidated();
    final isStoreEffectiveActive = _isSelectedStoreEffectivelyActive();

    if (storeId == null) {
      return const Center(child: Text('No hay tienda seleccionada'));
    }

    if (_productsErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.paddingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 56),
              const SizedBox(height: 10),
              Text(
                _productsErrorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadProductsForSelectedStore,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadStores();
        await _loadProductsForSelectedStore();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.paddingM),
        itemCount: _products.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isStoreValidated
                        ? AppTheme.successColor.withOpacity(0.08)
                        : AppTheme.warningColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isStoreValidated
                            ? Icons.check_circle_outline
                            : Icons.hourglass_bottom_rounded,
                        color: isStoreValidated
                            ? AppTheme.successColor
                            : AppTheme.warningColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isStoreValidated
                              ? (isStoreEffectiveActive
                                    ? 'Tu tienda está activa en el catálogo.'
                                    : 'Tu tienda está validada pero no está visible en el catálogo. Activa la tienda primero para mostrar productos.')
                              : 'Tu tienda está en validación. Mientras tanto los productos no podrán mostrarse en el catálogo.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isProductsLoading
                      ? null
                      : () async {
                          final created = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => CreateProductScreen(
                                    storeId: storeId,
                                    storeAllowsCatalog: isStoreEffectiveActive,
                                  ),
                                ),
                              );

                          if (created == true && mounted) {
                            await _loadProductsForSelectedStore();
                          }
                        },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text(
                    'Nuevo producto',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isProductsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_isProductsLoading && _products.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.18)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 44),
                        SizedBox(height: 10),
                        Text(
                          'Aún no tienes productos.',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Crea tu primer producto para empezar a vender en el catálogo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

          final product = _products[index - 1];

          final idRaw = product['id'];
          final productId = idRaw is int
              ? idRaw
              : (idRaw is num ? idRaw.toInt() : null);
          final nombre = (product['denominacion'] ?? 'Producto').toString();
          final imagen = (product['imagen'] ?? '').toString().trim();
          final stock = (product['stock'] is num)
              ? (product['stock'] as num)
              : 0;
          final precio = (product['precio_venta_cup'] is num)
              ? (product['precio_venta_cup'] as num)
              : null;

          final isProductVisible = product['mostrar_en_catalogo'] == true;
          final canToggleVisibility =
              isStoreEffectiveActive && productId != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: productId == null
                  ? null
                  : () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ProductManagementDetailScreen(
                            productId: productId,
                            storeId: storeId,
                            storeAllowsCatalog: isStoreEffectiveActive,
                          ),
                        ),
                      );

                      if (updated == true && mounted) {
                        await _loadProductsForSelectedStore();
                      }
                    },
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: imagen.isNotEmpty
                          ? SupabaseImage(
                              imageUrl: imagen,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Stock: ${stock.toString()}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          precio == null
                              ? 'Precio: --'
                              : 'Precio: ${precio.toStringAsFixed(2)} CUP',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isProductVisible && isStoreEffectiveActive,
                    onChanged: !canToggleVisibility
                        ? null
                        : (value) async {
                            try {
                              await _storeService
                                  .updateProductMostrarEnCatalogo(
                                    productId: productId,
                                    mostrarEnCatalogo: value,
                                  );
                              if (!mounted) return;
                              setState(() {
                                final updated = Map<String, dynamic>.from(
                                  _products[index - 1],
                                );
                                updated['mostrar_en_catalogo'] = value;
                                _products[index - 1] = updated;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No se pudo actualizar el producto: $e',
                                  ),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildValidationChip(bool isValidated) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isValidated
            ? AppTheme.successColor.withOpacity(0.12)
            : AppTheme.warningColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isValidated ? 'Validada' : 'En validación',
        style: TextStyle(
          color: isValidated ? AppTheme.successColor : AppTheme.warningColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateStore() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: Form(
        key: _createFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.paddingM),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Crea tu tienda',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'En validación',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _denominacionController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'La denominación es obligatoria';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Denominación',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _direccionController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'La dirección es obligatoria';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Dirección',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'El teléfono es obligatorio';
                      return null;
                    },
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildLocationCard(),
                  const SizedBox(height: 14),
                  _buildImageCard(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _paisController,
                          maxLength: 2,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.length != 2) {
                              return 'Código país (2 letras)';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'País (ISO)',
                            prefixIcon: Icon(Icons.flag_outlined),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _estadoController,
                          maxLength: 10,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'Código estado';
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Estado (código)',
                            prefixIcon: Icon(Icons.map_outlined),
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombrePaisController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Nombre del país';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nombre país',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombreEstadoController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Nombre del estado';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nombre estado',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildScheduleRow(),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isUploadingImage || _isLoading
                        ? null
                        : _createStore,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Crear tienda',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _buildLocationCard() {
    final text = _selectedLocation == null
        ? 'Seleccionar en mapa'
        : '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}';

    return InkWell(
      onTap: _pickLocation,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Foto de la tienda',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _isUploadingImage ? null : _pickImageSource,
                child: Text(_imageUrl == null ? 'Subir' : 'Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _isUploadingImage
                  ? Container(
                      color: Colors.white,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : (_imageUrl != null && _imageUrl!.isNotEmpty)
                  ? SupabaseImage(
                      imageUrl: _imageUrl!,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.white,
                      child: const Center(
                        child: Icon(Icons.storefront_outlined, size: 42),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pickTime(isOpen: true),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Apertura: ${_horaApertura.format(context)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => _pickTime(isOpen: false),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cierre: ${_horaCierre.format(context)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
