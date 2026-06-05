import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/carroceria_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/document_upload_service.dart';
import '../../services/vehicle_service.dart';
import '../../widgets/license_photo_row.dart';
import '../../widgets/plan_suscripcion_widget.dart';

class CarrierCargaProfileScreen extends StatefulWidget {
  const CarrierCargaProfileScreen({super.key});

  @override
  State<CarrierCargaProfileScreen> createState() =>
      _CarrierCargaProfileScreenState();
}

class _CarrierCargaProfileScreenState
    extends State<CarrierCargaProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _categoriaCtrl;
  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;

  bool _isEditing = false;
  bool _isSaving = false;

  final _vehicleService = VehicleService();
  final _docService = DocumentUploadService();
  List<CarroceriaModel> _carrocerias = [];
  bool _loadingVehicles = false;

  String? _licCondFrenteUrl;
  String? _licCondDorsoUrl;
  bool _isUploadingLicCondFrente = false;
  bool _isUploadingLicCondDorso = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl =
        TextEditingController(text: p?['telefono'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
    _categoriaCtrl =
        TextEditingController(text: p?['categoria'] as String? ?? '');
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
    _syncLicensesFromProfile(p);

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadCarrocerias());
  }

  void _syncLicensesFromProfile(Map<String, dynamic>? p) {
    _licCondFrenteUrl = p?['lic_conduccion_frente_url'] as String?;
    _licCondDorsoUrl = p?['lic_conduccion_dorso_url'] as String?;
  }

  bool _hasUrl(String? url) => url != null && url.isNotEmpty;

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _categoriaCtrl.dispose();
    _paisCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCarrocerias() async {
    final driverId = context
        .read<AuthProvider>()
        .driverProfile?['id'] as int?;
    if (driverId == null) return;
    setState(() => _loadingVehicles = true);
    try {
      final list = await _vehicleService.getCarroceriasForDriver(driverId);
      if (mounted) setState(() => _carrocerias = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'telefono': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'categoria': _categoriaCtrl.text.trim(),
      'pais': _paisCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
      if (_licCondFrenteUrl != null)
        'lic_conduccion_frente_url': _licCondFrenteUrl,
      if (_licCondDorsoUrl != null)
        'lic_conduccion_dorso_url': _licCondDorsoUrl,
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Perfil actualizado',
            style:
                GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['telefono'] as String? ?? '';
    _emailCtrl.text = p?['email'] as String? ?? '';
    _categoriaCtrl.text = p?['categoria'] as String? ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    _syncLicensesFromProfile(p);
    setState(() => _isEditing = false);
  }

  Future<void> _pickLicensePhoto({
    required String filename,
    required void Function(bool) setUploading,
    required void Function(String) onSuccess,
  }) async {
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
                'Subir foto',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: AppTheme.primaryColor),
                title: Text('Cámara',
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: AppTheme.primaryColor),
                title: Text('Galería',
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
    setUploading(true);
    try {
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid == null) return;
      final url = await _docService.pickCompressAndUpload(
        uuid: uuid,
        filename: filename,
        source: source,
      );
      if (url != null && mounted) onSuccess(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al subir imagen: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setUploading(false);
    }
  }

  Widget _buildLicenciasConduccion(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _SectionHeader(label: 'Licencia de Conducción', isDark: isDark),
        const SizedBox(height: 8),
        Text(
          'Obligatoria para operar como transportista.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        LicensePhotoRow(
          label: 'Frente',
          url: _licCondFrenteUrl,
          uploading: _isUploadingLicCondFrente,
          isDark: isDark,
          onTap: _isEditing
              ? () => _pickLicensePhoto(
                    filename: 'lic_conduccion_frente',
                    setUploading: (v) =>
                        setState(() => _isUploadingLicCondFrente = v),
                    onSuccess: (url) =>
                        setState(() => _licCondFrenteUrl = url),
                  )
              : null,
        ),
        const SizedBox(height: 10),
        LicensePhotoRow(
          label: 'Dorso',
          url: _licCondDorsoUrl,
          uploading: _isUploadingLicCondDorso,
          isDark: isDark,
          onTap: _isEditing
              ? () => _pickLicensePhoto(
                    filename: 'lic_conduccion_dorso',
                    setUploading: (v) =>
                        setState(() => _isUploadingLicCondDorso = v),
                    onSuccess: (url) =>
                        setState(() => _licCondDorsoUrl = url),
                  )
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final profile = auth.driverProfile;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final kyc = (profile?['kyc'] as bool?) ?? false;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: Text('Mi Perfil',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: AppTheme.primaryColor),
              label: Text('Editar',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600)),
            )
          else ...[
            TextButton(
              onPressed: _isSaving ? null : _cancelEdit,
              child: Text('Cancelar',
                  style: GoogleFonts.plusJakartaSans(
                      color: isDark ? Colors.white54 : Colors.grey,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor))
                  : Text('Guardar',
                      style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor:
              isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          isScrollable: true,
          tabs: const [
            Tab(
                icon: Icon(Icons.person_outline),
                text: 'Perfil'),
            Tab(
                icon: Icon(Icons.local_shipping_outlined),
                text: 'Vehículos'),
            Tab(
                icon: Icon(Icons.workspace_premium_outlined),
                text: 'Mi Plan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ProfileTab(
            formKey: _formKey,
            isDark: isDark,
            isEditing: _isEditing,
            kyc: kyc,
            nameCtrl: _nameCtrl,
            phoneCtrl: _phoneCtrl,
            emailCtrl: _emailCtrl,
            categoriaCtrl: _categoriaCtrl,
            paisCtrl: _paisCtrl,
            provinciaCtrl: _provinciaCtrl,
            municipioCtrl: _municipioCtrl,
            licensesSection: _buildLicenciasConduccion(isDark),
          ),
          _VehiclesTab(
            isDark: isDark,
            loading: _loadingVehicles,
            carrocerias: _carrocerias,
            onAddVehicle: () => _showAddVehicleDialog(context, isDark),
            onEditVehicle: _showEditVehicleLicenses,
            onDeleteVehicle: _deleteVehicle,
          ),
          _CarrierPlanTab(isDark: isDark),
        ],
      ),
    );
  }

  Future<void> _deleteVehicle(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar vehículo?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _vehicleService.deleteCarroceria(id);
      await _loadCarrocerias();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  Future<void> _showAddVehicleDialog(BuildContext context, bool isDark) async {
    final marcaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final matriculaCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    String? tipoCarro;
    String? licCircFrente;
    String? licCircDorso;
    String? licOpFrente;
    String? licOpDorso;
    bool upCircF = false;
    bool upCircD = false;
    bool upOpF = false;
    bool upOpD = false;

    final tiposCarroceria = [
      'flatbed', 'dry_van', 'reefer', 'lowboy', 'tanker',
      'step_deck', 'hotshot', 'curtainsider', 'caja',
    ];

    Future<void> pickInDialog({
      required String filename,
      required void Function(bool) setUp,
      required void Function(String) onOk,
      required StateSetter setS,
    }) async {
      await _pickLicensePhoto(
        filename: filename,
        setUploading: (v) => setS(() => setUp(v)),
        onSuccess: (url) => setS(() => onOk(url)),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final textPrimary =
              isDark ? Colors.white : const Color(0xFF1A1D27);
          final bg = isDark ? AppTheme.darkCard : Colors.white;
          final circOk =
              _hasUrl(licCircFrente) && _hasUrl(licCircDorso);
          return AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Agregar Vehículo',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: tipoCarro,
                    dropdownColor: bg,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                        labelText: 'Tipo de carrocería',
                        prefixIcon: Icon(Icons.local_shipping_outlined)),
                    items: tiposCarroceria
                        .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.toUpperCase(),
                                style:
                                    TextStyle(color: textPrimary))))
                        .toList(),
                    onChanged: (v) => setS(() => tipoCarro = v),
                  ),
                  const SizedBox(height: 12),
                  _DialogField(ctrl: marcaCtrl, label: 'Marca', isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(ctrl: modeloCtrl, label: 'Modelo', isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(ctrl: matriculaCtrl, label: 'Matrícula / Chapa', isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(
                    ctrl: capCtrl,
                    label: 'Capacidad (toneladas)',
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Licencia de circulación (obligatoria)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Circulación — Frente',
                    url: licCircFrente,
                    uploading: upCircF,
                    isDark: isDark,
                    onTap: () => pickInDialog(
                      filename: 'lic_circulacion_frente_new',
                      setUp: (v) => upCircF = v,
                      onOk: (u) => licCircFrente = u,
                      setS: setS,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Circulación — Dorso',
                    url: licCircDorso,
                    uploading: upCircD,
                    isDark: isDark,
                    onTap: () => pickInDialog(
                      filename: 'lic_circulacion_dorso_new',
                      setUp: (v) => upCircD = v,
                      onOk: (u) => licCircDorso = u,
                      setS: setS,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Licencia operativa (opcional)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Operativa — Frente',
                    url: licOpFrente,
                    uploading: upOpF,
                    isDark: isDark,
                    onTap: () => pickInDialog(
                      filename: 'lic_operativa_frente_new',
                      setUp: (v) => upOpF = v,
                      onOk: (u) => licOpFrente = u,
                      setS: setS,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Operativa — Dorso',
                    url: licOpDorso,
                    uploading: upOpD,
                    isDark: isDark,
                    onTap: () => pickInDialog(
                      filename: 'lic_operativa_dorso_new',
                      setUp: (v) => upOpD = v,
                      onOk: (u) => licOpDorso = u,
                      setS: setS,
                    ),
                  ),
                  if (!circOk && tipoCarro != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Sube frente y dorso de circulación para guardar.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: tipoCarro == null || !circOk
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final driverId = context
                            .read<AuthProvider>()
                            .driverProfile?['id'] as int?;
                        if (driverId == null) return;
                        final carroceria = CarroceriaModel(
                          driverId: driverId,
                          tipoCarroceria: tipoCarro!,
                          marca: marcaCtrl.text.trim().isNotEmpty
                              ? marcaCtrl.text.trim()
                              : null,
                          modelo: modeloCtrl.text.trim().isNotEmpty
                              ? modeloCtrl.text.trim()
                              : null,
                          matricula: matriculaCtrl.text.trim().isNotEmpty
                              ? matriculaCtrl.text.trim()
                              : null,
                          capacidadTon: double.tryParse(capCtrl.text.trim()),
                          licCirculacionFrenteUrl: licCircFrente,
                          licCirculacionDorsoUrl: licCircDorso,
                          licOperativaFrenteUrl: licOpFrente,
                          licOperativaDorsoUrl: licOpDorso,
                          seguroVigente: false,
                          activo: true,
                        );
                        try {
                          await _vehicleService.addCarroceria(carroceria);
                          await _loadCarrocerias();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppTheme.error,
                            ));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    matriculaCtrl.dispose();
    capCtrl.dispose();
  }

  Future<void> _showEditVehicleLicenses(CarroceriaModel carroceria) async {
    if (carroceria.id == null) return;
    final isDark = context.read<ThemeProvider>().isDark;
    final bg = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    String? licCircFrente = carroceria.licCirculacionFrenteUrl;
    String? licCircDorso = carroceria.licCirculacionDorsoUrl;
    String? licOpFrente = carroceria.licOperativaFrenteUrl;
    String? licOpDorso = carroceria.licOperativaDorsoUrl;
    bool upCircF = false;
    bool upCircD = false;
    bool upOpF = false;
    bool upOpD = false;
    bool saving = false;

    final vid = carroceria.id!;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final circOk =
              _hasUrl(licCircFrente) && _hasUrl(licCircDorso);
          final title = [
            carroceria.marca,
            carroceria.modelo,
          ].where((e) => e != null && e.isNotEmpty).join(' ');

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title.isNotEmpty
                        ? title
                        : carroceria.tipoCarroceria.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    carroceria.matricula ?? carroceria.tipoCarroceria,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader(
                      label: 'Licencia de circulación', isDark: isDark),
                  const SizedBox(height: 10),
                  LicensePhotoRow(
                    label: 'Frente',
                    url: licCircFrente,
                    uploading: upCircF,
                    isDark: isDark,
                    onTap: () => _pickLicensePhoto(
                      filename: 'lic_circulacion_frente_$vid',
                      setUploading: (v) => setS(() => upCircF = v),
                      onSuccess: (u) => setS(() => licCircFrente = u),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Dorso',
                    url: licCircDorso,
                    uploading: upCircD,
                    isDark: isDark,
                    onTap: () => _pickLicensePhoto(
                      filename: 'lic_circulacion_dorso_$vid',
                      setUploading: (v) => setS(() => upCircD = v),
                      onSuccess: (u) => setS(() => licCircDorso = u),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                      label: 'Licencia operativa (opcional)',
                      isDark: isDark),
                  const SizedBox(height: 10),
                  LicensePhotoRow(
                    label: 'Frente',
                    url: licOpFrente,
                    uploading: upOpF,
                    isDark: isDark,
                    onTap: () => _pickLicensePhoto(
                      filename: 'lic_operativa_frente_$vid',
                      setUploading: (v) => setS(() => upOpF = v),
                      onSuccess: (u) => setS(() => licOpFrente = u),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LicensePhotoRow(
                    label: 'Dorso',
                    url: licOpDorso,
                    uploading: upOpD,
                    isDark: isDark,
                    onTap: () => _pickLicensePhoto(
                      filename: 'lic_operativa_dorso_$vid',
                      setUploading: (v) => setS(() => upOpD = v),
                      onSuccess: (u) => setS(() => licOpDorso = u),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: !circOk || saving
                          ? null
                          : () async {
                              setS(() => saving = true);
                              try {
                                await _vehicleService.updateCarroceria(
                                  vid,
                                  {
                                    if (licCircFrente != null)
                                      'lic_circulacion_frente_url':
                                          licCircFrente,
                                    if (licCircDorso != null)
                                      'lic_circulacion_dorso_url':
                                          licCircDorso,
                                    if (licOpFrente != null)
                                      'lic_operativa_frente_url': licOpFrente,
                                    if (licOpDorso != null)
                                      'lic_operativa_dorso_url': licOpDorso,
                                  },
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _loadCarrocerias();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Licencias del vehículo actualizadas',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      backgroundColor: AppTheme.success,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setS(() => saving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: AppTheme.error,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Guardar licencias'),
                    ),
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
// Tab Perfil
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isDark;
  final bool isEditing;
  final bool kyc;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController categoriaCtrl;
  final TextEditingController paisCtrl;
  final TextEditingController provinciaCtrl;
  final TextEditingController municipioCtrl;
  final Widget licensesSection;

  const _ProfileTab({
    required this.formKey,
    required this.isDark,
    required this.isEditing,
    required this.kyc,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.categoriaCtrl,
    required this.paisCtrl,
    required this.provinciaCtrl,
    required this.municipioCtrl,
    required this.licensesSection,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + KYC
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          AppTheme.primaryColor.withValues(alpha: 0.15),
                      border: Border.all(
                          color: AppTheme.primaryColor, width: 3),
                    ),
                    child: Center(
                      child: Text(
                        nameCtrl.text.isNotEmpty
                            ? nameCtrl.text[0].toUpperCase()
                            : 'C',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  if (kyc)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified,
                          color: Colors.green, size: 20),
                    ),
                ],
              ),
            ),
            if (kyc) ...[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Verificado',
                      style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            const SizedBox(height: 24),

            _SectionHeader(label: 'Datos personales', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: nameCtrl,
              label: 'Nombre completo',
              icon: Icons.person_outline,
              isDark: isDark,
              enabled: isEditing,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: phoneCtrl,
              label: 'Teléfono',
              icon: Icons.phone_outlined,
              isDark: isDark,
              enabled: isEditing,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: emailCtrl,
              label: 'Correo electrónico',
              icon: Icons.email_outlined,
              isDark: isDark,
              enabled: false,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: categoriaCtrl,
              label: 'Categoría / Licencia',
              icon: Icons.card_membership_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 20),

            _SectionHeader(label: 'Ubicación', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: paisCtrl,
              label: 'País',
              icon: Icons.public_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: provinciaCtrl,
              label: 'Provincia',
              icon: Icons.location_city_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: municipioCtrl,
              label: 'Municipio',
              icon: Icons.map_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            licensesSection,
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Vehículos
// ─────────────────────────────────────────────────────────────────────────────

class _VehiclesTab extends StatelessWidget {
  final bool isDark;
  final bool loading;
  final List<CarroceriaModel> carrocerias;
  final VoidCallback onAddVehicle;
  final void Function(CarroceriaModel) onEditVehicle;
  final Future<void> Function(int id) onDeleteVehicle;

  const _VehiclesTab({
    required this.isDark,
    required this.loading,
    required this.carrocerias,
    required this.onAddVehicle,
    required this.onEditVehicle,
    required this.onDeleteVehicle,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAddVehicle,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Vehículo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : carrocerias.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 64,
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('Sin vehículos registrados',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1D27))),
                            const SizedBox(height: 8),
                            Text(
                                'Agrega los vehículos con los que operas',
                                style: TextStyle(
                                    color: textSecondary, fontSize: 13),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: carrocerias.length,
                      itemBuilder: (_, i) => _CarroceriaCard(
                        carroceria: carrocerias[i],
                        isDark: isDark,
                        onTap: () => onEditVehicle(carrocerias[i]),
                        onDelete: () =>
                            onDeleteVehicle(carrocerias[i].id!),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _CarroceriaCard extends StatelessWidget {
  final CarroceriaModel carroceria;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CarroceriaCard({
    required this.carroceria,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  static bool _hasUrl(String? url) => url != null && url.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    final title = [
      carroceria.marca,
      carroceria.modelo,
    ].where((e) => e != null && e.isNotEmpty).join(' ');

    final circOk = _hasUrl(carroceria.licCirculacionFrenteUrl) &&
        _hasUrl(carroceria.licCirculacionDorsoUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_shipping_outlined,
              color: AppTheme.primaryColor),
        ),
        title: Text(
          title.isNotEmpty
              ? title
              : carroceria.tipoCarroceria.toUpperCase(),
          style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              [
                carroceria.tipoCarroceria.toUpperCase(),
                if (carroceria.matricula != null) carroceria.matricula!,
                if (carroceria.capacidadTon != null)
                  '${carroceria.capacidadTon!.toStringAsFixed(1)} ton',
              ].join(' · '),
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  circOk ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 14,
                  color: circOk ? AppTheme.success : AppTheme.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  circOk ? 'Circulación completa' : 'Falta licencia de circulación',
                  style: TextStyle(
                    fontSize: 11,
                    color: circOk ? AppTheme.success : AppTheme.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Toca para gestionar licencias',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.primaryColor.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: AppTheme.error),
          onPressed: carroceria.id != null ? onDelete : null,
          tooltip: 'Eliminar',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : Colors.grey[700],
          letterSpacing: 0.4,
        ));
  }
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
      style: TextStyle(
          color: enabled ? textPrimary : disabledColor, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon,
            size: 18,
            color: enabled ? AppTheme.primaryColor : disabledColor),
        filled: true,
        fillColor: enabled
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey[50]),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? AppTheme.darkBorder : Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? AppTheme.darkBorder : Colors.grey[300]!)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[200]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppTheme.primaryColor, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool isDark;
  final TextInputType keyboardType;

  const _DialogField({
    required this.ctrl,
    required this.label,
    required this.isDark,
    this.keyboardType = TextInputType.text,
  });


  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: TextStyle(color: textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Plan
// ─────────────────────────────────────────────────────────────────────────────

class _CarrierPlanTab extends StatelessWidget {
  final bool isDark;
  const _CarrierPlanTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suscripción y Facturación',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El ciclo de facturación cierra el día 2 de cada mes.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }
}
