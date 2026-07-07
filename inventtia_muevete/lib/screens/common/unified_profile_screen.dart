import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/carroceria_model.dart';
import '../../models/vehicle_type_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/document_upload_service.dart';
import '../../services/driver_service.dart';
import '../../services/mbtiles_service.dart';
import '../../services/profile_photo_service.dart';
import '../../services/saved_address_service.dart';
import '../../services/vehicle_service.dart';
import '../../services/vehicle_type_service.dart';
import '../../widgets/plan_suscripcion_widget.dart';
import '../driver/driver_ratings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Nomencladores (shipper)
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

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class UnifiedProfileScreen extends StatelessWidget {
  const UnifiedProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final t = auth.tipoUsuario;

    if (t == 'shipper') return const _ShipperProfile();
    if (t == 'carrier_carga') return const _CarrierProfile();
    if (t == 'dispatcher') return const _DispatcherProfile();
    if (t == 'conductor_pasajeros') return const _DriverProfile();
    return const _ClientProfile();
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
          color: enabled ? textPrimary : disabledColor, fontSize: 14),
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

class _AvatarSection extends StatelessWidget {
  final String nameDisplay;
  final String? photoUrl;
  final bool isUploading;
  final bool showKyc;
  final VoidCallback onTap;
  final bool isDark;

  const _AvatarSection({
    required this.nameDisplay,
    required this.photoUrl,
    required this.isUploading,
    required this.showKyc,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
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
              image: (photoUrl != null && photoUrl!.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage(photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: isUploading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primaryColor, strokeWidth: 3))
                : (photoUrl == null || photoUrl!.isEmpty)
                    ? Center(
                        child: Text(
                          nameDisplay.isNotEmpty
                              ? nameDisplay[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      )
                    : null,
          ),
          if (showKyc)
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.verified,
                    color: Colors.green, size: 18),
              ),
            ),
          if (!isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor,
                    border: Border.all(
                        color: isDark ? AppTheme.darkBg : Colors.white,
                        width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showPhotoSourceSheet(BuildContext context, bool isDark,
    Future<void> Function(ImageSource) onPick) {
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.photo_library_outlined,
                    color: AppTheme.primaryColor),
              ),
              title: Text('Elegir de la galería',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt_outlined,
                    color: AppTheme.primaryColor),
              ),
              title: Text('Tomar foto',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

Widget _signOutButton(BuildContext context) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () async {
        await context.read<AuthProvider>().signOut();
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, kIsWeb ? '/landing' : '/login', (_) => false);
        }
      },
      icon: const Icon(Icons.logout, size: 18),
      label: Text('Cerrar sesión',
          style:
              GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.error,
        side: const BorderSide(color: AppTheme.error),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

Widget _offlineMapTile(bool isDark, VoidCallback onToggle) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
    ),
    child: SwitchListTile(
      secondary:
          Icon(Icons.map_outlined, color: AppTheme.primaryColor, size: 22),
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
  );
}

AppBar _commonAppBar(BuildContext context,
    {required bool isDark,
    required bool isEditing,
    required bool isSaving,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required VoidCallback onSave,
    List<Tab>? tabs,
    TabController? tabController}) {
  final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
  return AppBar(
    backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
    elevation: 0,
    title: Text('Mi Perfil',
        style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, color: textPrimary)),
    iconTheme: IconThemeData(color: textPrimary),
    actions: [
      if (!isEditing)
        TextButton.icon(
          onPressed: onEdit,
          icon:
              Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryColor),
          label: Text('Editar',
              style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
        )
      else ...[
        TextButton(
          onPressed: isSaving ? null : onCancel,
          child: Text('Cancelar',
              style: GoogleFonts.plusJakartaSans(
                  color: isDark ? Colors.white54 : Colors.grey,
                  fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: isSaving ? null : onSave,
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primaryColor))
              : Text('Guardar',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w700)),
        ),
      ],
    ],
    bottom: (tabs != null && tabController != null)
        ? TabBar(
            controller: tabController,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor:
                isDark ? Colors.white54 : Colors.grey[500],
            indicatorColor: AppTheme.primaryColor,
            isScrollable: tabs.length > 3,
            tabs: tabs,
          )
        : null,
  );
}

void _snackOk(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Perfil actualizado',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
    backgroundColor: AppTheme.success,
    behavior: SnackBarBehavior.floating,
    shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// CLIENT PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _ClientProfile extends StatefulWidget {
  const _ClientProfile();

  @override
  State<_ClientProfile> createState() => _ClientProfileState();
}

class _ClientProfileState extends State<_ClientProfile> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _ciCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;
  late TextEditingController _paisCtrl;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  final _photoService = ProfilePhotoService();
  final _addressService = SavedAddressService();

  @override
  void initState() {
    super.initState();
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: p?['phone'] as String? ?? '');
    _ciCtrl = TextEditingController(text: p?['ci'] as String? ?? '');
    _direccionCtrl =
        TextEditingController(text: p?['direccion'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ciCtrl.dispose();
    _direccionCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _paisCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'ci': _ciCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
      'pais': _paisCtrl.text.trim(),
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      _snackOk(context);
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['phone'] as String? ?? '';
    _ciCtrl.text = p?['ci'] as String? ?? '';
    _direccionCtrl.text = p?['direccion'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    setState(() => _isEditing = false);
  }

  Future<void> _changePhoto(ImageSource source) async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final url =
          await _photoService.pickCompressAndUpload(uuid: uuid, source: source);
      if (url == null) return;
      await _addressService.updateUserPhoto(uuid, url);
      if (!mounted) return;
      await context.read<AuthProvider>().updateProfile({'photo_url': url});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Foto actualizada',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error subiendo foto: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final profile = context.watch<AuthProvider>().userProfile;
    final email = profile?['email'] as String? ?? '';
    final photoUrl =
        profile?['photo_url'] as String? ?? profile?['image'] as String?;
    final nameDisplay =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Usuario';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: _commonAppBar(
        context,
        isDark: isDark,
        isEditing: _isEditing,
        isSaving: _isSaving,
        onEdit: () => setState(() => _isEditing = true),
        onCancel: _cancelEdit,
        onSave: _save,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 8),
              _AvatarSection(
                nameDisplay: nameDisplay,
                photoUrl: photoUrl,
                isUploading: _isUploadingPhoto,
                showKyc: false,
                onTap: () => _showPhotoSourceSheet(
                    context, isDark, _changePhoto),
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              // Email readonly
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorder
                          : Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_outlined,
                        color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Correo electrónico',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey[500])),
                          Text(email.isNotEmpty ? email : 'No registrado',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[500])),
                        ],
                      ),
                    ),
                    Icon(Icons.lock_outline,
                        size: 16,
                        color: isDark ? Colors.white24 : Colors.grey[400]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ProfileField(
                  controller: _nameCtrl,
                  label: 'Nombre completo',
                  icon: Icons.person_outline,
                  isDark: isDark,
                  enabled: _isEditing,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _phoneCtrl,
                  label: 'Teléfono',
                  icon: Icons.phone_outlined,
                  isDark: isDark,
                  enabled: _isEditing,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _ciCtrl,
                  label: 'Cédula de identidad',
                  icon: Icons.badge_outlined,
                  isDark: isDark,
                  enabled: _isEditing,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _direccionCtrl,
                  label: 'Dirección',
                  icon: Icons.home_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _paisCtrl,
                  label: 'País',
                  icon: Icons.public_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _provinciaCtrl,
                  label: 'Provincia / Estado',
                  icon: Icons.location_city_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _municipioCtrl,
                  label: 'Ciudad / Municipio',
                  icon: Icons.place_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 24),
              if (!kIsWeb)
                _offlineMapTile(isDark, () async {
                  await MbTilesService.instance
                      .toggleOffline(!MbTilesService.instance.useOffline);
                  setState(() {});
                }),
              const SizedBox(height: 24),
              if (!_isEditing) _signOutButton(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRIVER (conductor pasajeros) PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _DriverProfile extends StatefulWidget {
  const _DriverProfile();

  @override
  State<_DriverProfile> createState() => _DriverProfileState();
}

class _DriverProfileState extends State<_DriverProfile> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _categoriaCtrl;

  // Vehicle fields
  late TextEditingController _marcaCtrl;
  late TextEditingController _modeloCtrl;
  late TextEditingController _chapaCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _capacidadCtrl;
  int? _vehicleId;
  int? _vehicleTypeId;
  List<VehicleTypeModel> _vehicleTypes = [];

  // License photo fields
  String? _licCondFrenteUrl;
  String? _licCondDorsoUrl;
  String? _licCircFrenteUrl;
  String? _licCircDorsoUrl;
  String? _licOperativaFrenteUrl;
  String? _licOperativaDorsoUrl;
  bool _isUploadingLicCondFrente = false;
  bool _isUploadingLicCondDorso = false;
  bool _isUploadingLicCircFrente = false;
  bool _isUploadingLicCircDorso = false;
  bool _isUploadingLicOpFrente = false;
  bool _isUploadingLicOpDorso = false;

  // Vehicle photo
  String? _vehiclePhotoUrl;
  bool _isUploadingVehiclePhoto = false;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  final _photoService = ProfilePhotoService();
  final _driverService = DriverService();
  final _vehicleTypeService = VehicleTypeService();
  final _docService = DocumentUploadService();

  @override
  void initState() {
    super.initState();
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl =
        TextEditingController(text: p?['telefono'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
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

    _vehicleTypeService.getActiveTypes().then((list) {
      if (mounted) setState(() => _vehicleTypes = list);
    });

    _licCondFrenteUrl = p?['lic_conduccion_frente_url'] as String?;
    _licCondDorsoUrl  = p?['lic_conduccion_dorso_url']  as String?;
    _licCircFrenteUrl = p?['lic_circulacion_frente_url'] as String?;
    _licCircDorsoUrl  = p?['lic_circulacion_dorso_url']  as String?;
    _licOperativaFrenteUrl = p?['lic_operativa_frente_url'] as String?;
    _licOperativaDorsoUrl  = p?['lic_operativa_dorso_url']  as String?;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _categoriaCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _chapaCtrl.dispose();
    _colorCtrl.dispose();
    _capacidadCtrl.dispose();
    _vehiclePhotoUrl = null;
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await context.read<AuthProvider>().updateProfile({
        'name': _nameCtrl.text.trim(),
        'telefono': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'categoria': _categoriaCtrl.text.trim(),
      });
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
      // Update license photos on the driver row
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
      if (licData.isNotEmpty && mounted) {
        await context.read<AuthProvider>().updateProfile(licData);
      }
      if (mounted) {
        await context.read<AuthProvider>().refreshDriverProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating));
        setState(() {
          _isSaving = false;
          _isEditing = false;
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      _snackOk(context);
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['telefono'] as String? ?? '';
    _emailCtrl.text = p?['email'] as String? ?? '';
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
    _licCondDorsoUrl  = p?['lic_conduccion_dorso_url']  as String?;
    _licCircFrenteUrl = p?['lic_circulacion_frente_url'] as String?;
    _licCircDorsoUrl  = p?['lic_circulacion_dorso_url']  as String?;
    _licOperativaFrenteUrl = p?['lic_operativa_frente_url'] as String?;
    _licOperativaDorsoUrl  = p?['lic_operativa_dorso_url']  as String?;
    setState(() => _isEditing = false);
  }

  Future<void> _changePhoto(ImageSource source) async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final url =
          await _photoService.pickCompressAndUpload(uuid: uuid, source: source);
      if (url == null) return;
      await Supabase.instance.client
          .schema('muevete')
          .from('drivers')
          .update({'image': url}).eq('uuid', uuid);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshDriverProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Foto actualizada',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error subiendo foto: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final profile = context.watch<AuthProvider>().driverProfile;
    final email = profile?['email'] as String? ?? '';
    final photoUrl = profile?['image'] as String?;
    final kyc = (profile?['kyc'] as bool?) ?? false;
    final vehiculo = profile?['vehiculos'] as Map<String, dynamic>?;
    final nameDisplay =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Conductor';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: _commonAppBar(
        context,
        isDark: isDark,
        isEditing: _isEditing,
        isSaving: _isSaving,
        onEdit: () => setState(() => _isEditing = true),
        onCancel: _cancelEdit,
        onSave: _save,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarSection(
                nameDisplay: nameDisplay,
                photoUrl: photoUrl,
                isUploading: _isUploadingPhoto,
                showKyc: kyc,
                onTap: () => _showPhotoSourceSheet(
                    context, isDark, _changePhoto),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(email,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.grey[500])),
              ),
              const SizedBox(height: 24),
              if (vehiculo != null) ...[
                _SectionHeader(
                    label: 'Vehículo Registrado', isDark: isDark),
                const SizedBox(height: 12),
                if (_vehicleTypes.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : Colors.grey[300]!),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _vehicleTypeId,
                        isExpanded: true,
                        hint: Text('Tipo de vehículo',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey[500],
                                fontSize: 14)),
                        dropdownColor:
                            isDark ? AppTheme.darkCard : Colors.white,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 14),
                        onChanged: _isEditing
                            ? (v) => setState(() => _vehicleTypeId = v)
                            : null,
                        items: _vehicleTypes.map((t) {
                          return DropdownMenuItem(
                            value: t.id,
                            child: Row(children: [
                              Icon(t.icon,
                                  size: 18,
                                  color: _isEditing
                                      ? AppTheme.primaryColor
                                      : (isDark
                                          ? Colors.white38
                                          : Colors.grey[400]!)),
                              const SizedBox(width: 10),
                              Text(t.displayName),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                if (_vehicleTypes.isNotEmpty) const SizedBox(height: 12),
                _ProfileField(
                    controller: _marcaCtrl,
                    label: 'Marca',
                    icon: Icons.branding_watermark_outlined,
                    isDark: isDark,
                    enabled: _isEditing),
                const SizedBox(height: 12),
                _ProfileField(
                    controller: _modeloCtrl,
                    label: 'Modelo',
                    icon: Icons.directions_car_outlined,
                    isDark: isDark,
                    enabled: _isEditing),
                const SizedBox(height: 12),
                _ProfileField(
                    controller: _chapaCtrl,
                    label: 'Chapa / Matrícula',
                    icon: Icons.pin_outlined,
                    isDark: isDark,
                    enabled: _isEditing),
                const SizedBox(height: 12),
                _ProfileField(
                    controller: _colorCtrl,
                    label: 'Color',
                    icon: Icons.palette_outlined,
                    isDark: isDark,
                    enabled: _isEditing),
                const SizedBox(height: 12),
                _ProfileField(
                    controller: _capacidadCtrl,
                    label: 'Capacidad (pasajeros)',
                    icon: Icons.people_outline,
                    isDark: isDark,
                    enabled: _isEditing,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                // Vehicle Photo Upload
                _LicensePhotoRow(
                  label: 'Foto del Vehículo (opcional)',
                  url: _vehiclePhotoUrl,
                  uploading: _isUploadingVehiclePhoto,
                  isDark: isDark,
                  onTap: _isEditing
                      ? () async {
                          final source = await showModalBottomSheet<ImageSource>(
                            context: context,
                            backgroundColor:
                                isDark ? AppTheme.darkSurface : Colors.white,
                            builder: (_) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                        Icons.camera_alt_outlined),
                                    title: const Text('Cámara'),
                                    onTap: () => Navigator.pop(
                                        context, ImageSource.camera),
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.image_outlined),
                                    title: const Text('Galería'),
                                    onTap: () => Navigator.pop(
                                        context, ImageSource.gallery),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (source == null || !mounted) return;
                          setState(() => _isUploadingVehiclePhoto = true);
                          final url =
                              await _docService.pickCompressAndUpload(
                            uuid: context.read<AuthProvider>().user?.id ??
                                'driver',
                            filename:
                                'vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg',
                            source: source,
                          );
                          if (mounted) {
                            setState(() {
                              _vehiclePhotoUrl = url;
                              _isUploadingVehiclePhoto = false;
                            });
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 20),
              ],
              // Valoraciones
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const DriverRatingsScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color:
                                AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.star_rounded,
                            color: AppTheme.warning, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text('Mis Valoraciones',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87))),
                      Icon(Icons.chevron_right,
                          color:
                              isDark ? Colors.white38 : Colors.grey[400]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                  label: 'Información Personal', isDark: isDark),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _nameCtrl,
                  label: 'Nombre completo',
                  icon: Icons.person_outline,
                  isDark: isDark,
                  enabled: _isEditing,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _phoneCtrl,
                  label: 'Teléfono',
                  icon: Icons.phone_outlined,
                  isDark: isDark,
                  enabled: _isEditing,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _emailCtrl,
                  label: 'Correo electrónico',
                  icon: Icons.email_outlined,
                  isDark: isDark,
                  enabled: false),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _categoriaCtrl,
                  label: 'Categoría / Licencia',
                  icon: Icons.card_membership_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 24),
              // ── Licencias ───────────────────────────────────────────────
              _SectionHeader(
                  label: 'Licencia de Conducción', isDark: isDark),
              const SizedBox(height: 12),
              _LicensePhotoRow(
                label: 'Frente',
                url: _licCondFrenteUrl,
                uploading: _isUploadingLicCondFrente,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_conduccion_frente',
                          setUploading: (v) => setState(
                              () => _isUploadingLicCondFrente = v),
                          onSuccess: (url) =>
                              setState(() => _licCondFrenteUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 10),
              _LicensePhotoRow(
                label: 'Dorso',
                url: _licCondDorsoUrl,
                uploading: _isUploadingLicCondDorso,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_conduccion_dorso',
                          setUploading: (v) => setState(
                              () => _isUploadingLicCondDorso = v),
                          onSuccess: (url) =>
                              setState(() => _licCondDorsoUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                  label: 'Licencia de Circulación del Vehículo',
                  isDark: isDark),
              const SizedBox(height: 12),
              _LicensePhotoRow(
                label: 'Frente',
                url: _licCircFrenteUrl,
                uploading: _isUploadingLicCircFrente,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_circulacion_frente',
                          setUploading: (v) => setState(
                              () => _isUploadingLicCircFrente = v),
                          onSuccess: (url) =>
                              setState(() => _licCircFrenteUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 10),
              _LicensePhotoRow(
                label: 'Dorso',
                url: _licCircDorsoUrl,
                uploading: _isUploadingLicCircDorso,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_circulacion_dorso',
                          setUploading: (v) => setState(
                              () => _isUploadingLicCircDorso = v),
                          onSuccess: (url) =>
                              setState(() => _licCircDorsoUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                  label: 'Licencia Operativa (opcional)', isDark: isDark),
              const SizedBox(height: 12),
              _LicensePhotoRow(
                label: 'Frente',
                url: _licOperativaFrenteUrl,
                uploading: _isUploadingLicOpFrente,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_operativa_frente',
                          setUploading: (v) =>
                              setState(() => _isUploadingLicOpFrente = v),
                          onSuccess: (url) =>
                              setState(() => _licOperativaFrenteUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 10),
              _LicensePhotoRow(
                label: 'Dorso',
                url: _licOperativaDorsoUrl,
                uploading: _isUploadingLicOpDorso,
                isDark: isDark,
                onTap: _isEditing
                    ? () => _pickLicensePhoto(
                          filename: 'lic_operativa_dorso',
                          setUploading: (v) =>
                              setState(() => _isUploadingLicOpDorso = v),
                          onSuccess: (url) =>
                              setState(() => _licOperativaDorsoUrl = url),
                        )
                    : null,
              ),
              const SizedBox(height: 24),
              if (!kIsWeb)
                _offlineMapTile(isDark, () async {
                  await MbTilesService.instance
                      .toggleOffline(!MbTilesService.instance.useOffline);
                  setState(() {});
                }),
              const SizedBox(height: 24),
              if (!_isEditing) _signOutButton(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
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
              Text('Subir foto',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87)),
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
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setUploading(false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIPPER PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _ShipperProfile extends StatefulWidget {
  const _ShipperProfile();

  @override
  State<_ShipperProfile> createState() => _ShipperProfileState();
}

class _ShipperProfileState extends State<_ShipperProfile>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _personalFormKey = GlobalKey<FormState>();
  final _entityFormKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  // Documento de identidad
  String _tipoDocumento = 'Carnet de Identidad';
  String? _docFrenteUrl;
  String? _docDorsoUrl;
  bool _isUploadingDocFrente = false;
  bool _isUploadingDocDorso = false;

  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;
  late TextEditingController _direccionCtrl;

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
  final _docService = DocumentUploadService();

  static const _docTypes = ['Carnet de Identidad', 'Pasaporte', 'Licencia de Conducir'];

  Future<void> _pickDocPhoto({required bool isFront}) async {
    final isDark = context.read<ThemeProvider>().isDark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final uuid = context.read<AuthProvider>().user?.id ?? 'shipper';
    setState(() { if (isFront) _isUploadingDocFrente = true; else _isUploadingDocDorso = true; });
    final url = await _docService.pickCompressAndUpload(
      uuid: uuid,
      filename: isFront ? 'doc_frente.jpg' : 'doc_dorso.jpg',
      source: source,
    );
    if (url != null && mounted) {
      setState(() { if (isFront) _docFrenteUrl = url; else _docDorsoUrl = url; });
    }
    if (mounted) setState(() { _isUploadingDocFrente = false; _isUploadingDocDorso = false; });
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: p?['phone'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
    _tipoDocumento = p?['tipo_documento'] as String? ?? 'Carnet de Identidad';
    _docFrenteUrl = p?['doc_frente_url'] as String?;
    _docDorsoUrl = p?['doc_dorso_url'] as String?;
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
    _direccionCtrl =
        TextEditingController(text: p?['direccion'] as String? ?? '');
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
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nameCtrl, _phoneCtrl, _emailCtrl, _paisCtrl,
      _provinciaCtrl, _municipioCtrl, _direccionCtrl, _nombreLegalCtrl,
      _idFiscalCtrl, _regionEmpCtrl,
      _ciudadEmpCtrl, _direccionEmpCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ok1 = _personalFormKey.currentState?.validate() ?? true;
    final ok2 = _entityFormKey.currentState?.validate() ?? true;
    if (!ok1 || !ok2) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'tipo_documento': _tipoDocumento,
      if (_docFrenteUrl != null) 'doc_frente_url': _docFrenteUrl,
      if (_docDorsoUrl != null) 'doc_dorso_url': _docDorsoUrl,
      'pais': _paisCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      if (_tipoOrg != null) 'tipo_organizacion': _tipoOrg,
      'nombre_legal': _nombreLegalCtrl.text.trim(),
      'id_fiscal': _idFiscalCtrl.text.trim(),
      'region_empresa': _regionEmpCtrl.text.trim(),
      'ciudad_empresa': _ciudadEmpCtrl.text.trim(),
      'direccion_empresa': _direccionEmpCtrl.text.trim(),
      if (_empLat != null) 'emp_lat': _empLat,
      if (_empLng != null) 'emp_lng': _empLng,
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      _snackOk(context);
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['phone'] as String? ?? '';
    _tipoDocumento = p?['tipo_documento'] as String? ?? 'Carnet de Identidad';
    _docFrenteUrl = p?['doc_frente_url'] as String?;
    _docDorsoUrl = p?['doc_dorso_url'] as String?;
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    _direccionCtrl.text = p?['direccion'] as String? ?? '';
    _tipoOrg = p?['tipo_organizacion'] as String?;
    _nombreLegalCtrl.text = p?['nombre_legal'] as String? ?? '';
    _idFiscalCtrl.text = p?['id_fiscal'] as String? ?? '';
    _regionEmpCtrl.text = p?['region_empresa'] as String? ?? '';
    _ciudadEmpCtrl.text = p?['ciudad_empresa'] as String? ?? '';
    _direccionEmpCtrl.text = p?['direccion_empresa'] as String? ?? '';
    _empLat = (p?['emp_lat'] as num?)?.toDouble();
    _empLng = (p?['emp_lng'] as num?)?.toDouble();
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: _commonAppBar(
        context,
        isDark: isDark,
        isEditing: _isEditing,
        isSaving: _isSaving,
        onEdit: () => setState(() => _isEditing = true),
        onCancel: _cancelEdit,
        onSave: _save,
        tabController: _tabs,
        tabs: const [
          Tab(icon: Icon(Icons.person_outline), text: 'Personal'),
          Tab(icon: Icon(Icons.business_outlined), text: 'Empresa'),
          Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'Mi Plan'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Personal ──────────────────────────────────────────────────
          _buildPersonalTab(isDark, textPrimary),
          // ── Empresa ───────────────────────────────────────────────────
          _buildEmpresaTab(isDark, textPrimary, textSecondary, cardColor),
          // ── Plan ──────────────────────────────────────────────────────
          _buildPlanTab(isDark, textPrimary),
        ],
      ),
    );
  }

  Widget _buildPersonalTab(bool isDark, Color textPrimary) {
    final nameDisplay =
        (_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Shipper');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _personalFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    border:
                        Border.all(color: AppTheme.primaryColor, width: 3)),
                child: Center(
                  child: Text(
                    nameDisplay.isNotEmpty
                        ? nameDisplay[0].toUpperCase()
                        : 'S',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor),
                  ),
                ),
              ),
            ),
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
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _phoneCtrl,
                label: 'Teléfono',
                icon: Icons.phone_outlined,
                isDark: isDark,
                enabled: _isEditing,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                icon: Icons.email_outlined,
                isDark: isDark,
                enabled: false),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Documento de identidad', isDark: isDark),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _docTypes.contains(_tipoDocumento) ? _tipoDocumento : _docTypes.first,
              dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
              style: TextStyle(color: textPrimary),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
                labelText: 'Tipo de documento',
              ),
              items: _docTypes.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: _isEditing ? (v) { if (v != null) setState(() => _tipoDocumento = v); } : null,
            ),
            const SizedBox(height: 12),
            _LicensePhotoRow(
              label: 'Foto del Frente',
              url: _docFrenteUrl,
              uploading: _isUploadingDocFrente,
              isDark: isDark,
              onTap: _isEditing ? () => _pickDocPhoto(isFront: true) : null,
            ),
            const SizedBox(height: 10),
            _LicensePhotoRow(
              label: 'Foto del Dorso',
              url: _docDorsoUrl,
              uploading: _isUploadingDocDorso,
              isDark: isDark,
              onTap: _isEditing ? () => _pickDocPhoto(isFront: false) : null,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Ubicación personal', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _paisCtrl,
                label: 'País',
                icon: Icons.public_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _provinciaCtrl,
                label: 'Provincia',
                icon: Icons.location_city_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _municipioCtrl,
                label: 'Municipio',
                icon: Icons.map_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _direccionCtrl,
                label: 'Dirección',
                icon: Icons.home_outlined,
                isDark: isDark,
                enabled: _isEditing,
                maxLines: 2),
            const SizedBox(height: 32),
            if (!_isEditing) _signOutButton(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpresaTab(
      bool isDark, Color textPrimary, Color textSecondary, Color cardColor) {
    final fiscalLabel = _labelFiscal(_paisCtrl.text.trim().isNotEmpty ? _paisCtrl.text.trim() : null);

    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _entityFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      'Los campos de identificación fiscal y actividad económica se adaptan al país seleccionado.',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey[700]),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                  label: '1. Tipo de organización', isDark: isDark),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : Colors.grey[300]!)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _tipoOrg,
                    isExpanded: true,
                    hint: Text('Seleccionar tipo',
                        style:
                            TextStyle(color: textSecondary, fontSize: 14)),
                    dropdownColor: cardColor,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    onChanged: _isEditing
                        ? (v) => setState(() => _tipoOrg = v)
                        : null,
                    items: _tiposOrganizacion.entries.map((e) {
                      return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: TextStyle(color: textPrimary)));
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ProfileField(
                  controller: _nombreLegalCtrl,
                  label: '2. Nombre legal de la empresa',
                  icon: Icons.business_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _idFiscalCtrl,
                  label: '3. $fiscalLabel',
                  icon: Icons.numbers_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 16),
              _ProfileField(
                  controller: _regionEmpCtrl,
                  label: '4. Estado / Región / Provincia',
                  icon: Icons.location_city_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _ciudadEmpCtrl,
                  label: '5. Ciudad / Municipio',
                  icon: Icons.map_outlined,
                  isDark: isDark,
                  enabled: _isEditing),
              const SizedBox(height: 12),
              _ProfileField(
                  controller: _direccionEmpCtrl,
                  label: '6. Dirección completa',
                  icon: Icons.pin_drop_outlined,
                  isDark: isDark,
                  enabled: _isEditing,
                  maxLines: 2),
              const SizedBox(height: 16),
              _SectionHeader(
                  label: '7. Ubicación en mapa (opcional)', isDark: isDark),
              const SizedBox(height: 8),
              Text(
                _isEditing
                    ? 'Toca el mapa para fijar la ubicación de la empresa.'
                    : _empLat != null
                        ? 'Lat: ${_empLat!.toStringAsFixed(5)}, Lng: ${_empLng!.toStringAsFixed(5)}'
                        : 'Sin ubicación registrada.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _empLat != null
                        ? AppTheme.primaryColor
                        : isDark ? Colors.white38 : Colors.grey[500]),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        _empLat ?? 20.0,
                        _empLng ?? 0.0,
                      ),
                      initialZoom: _empLat != null ? 14 : 2,
                      onTap: _isEditing
                          ? (_, latlng) => setState(() {
                                _empLat = latlng.latitude;
                                _empLng = latlng.longitude;
                              })
                          : null,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      if (_empLat != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(_empLat!, _empLng!),
                              width: 36,
                              height: 36,
                              child: const Icon(Icons.location_pin,
                                  color: AppTheme.primaryColor, size: 36),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (_isEditing && _empLat != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _empLat = null;
                    _empLng = null;
                  }),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Quitar ubicación'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error, padding: EdgeInsets.zero),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
    );
  }

  Widget _buildPlanTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suscripción y Facturación',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary)),
          const SizedBox(height: 4),
          Text('El ciclo de facturación cierra el día 2 de cada mes.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600])),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARRIER PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _CarrierProfile extends StatefulWidget {
  const _CarrierProfile();

  @override
  State<_CarrierProfile> createState() => _CarrierProfileState();
}

class _CarrierProfileState extends State<_CarrierProfile>
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
  List<CarroceriaModel> _carrocerias = [];
  bool _loadingVehicles = false;

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadCarrocerias());
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nameCtrl, _phoneCtrl, _emailCtrl, _categoriaCtrl,
      _paisCtrl, _provinciaCtrl, _municipioCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCarrocerias() async {
    final driverId =
        context.read<AuthProvider>().driverProfile?['id'] as int?;
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
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      _snackOk(context);
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
    setState(() => _isEditing = false);
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
              child: const Text('Eliminar')),
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
            backgroundColor: AppTheme.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final profile = context.watch<AuthProvider>().driverProfile;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final kyc = (profile?['kyc'] as bool?) ?? false;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: _commonAppBar(
        context,
        isDark: isDark,
        isEditing: _isEditing,
        isSaving: _isSaving,
        onEdit: () => setState(() => _isEditing = true),
        onCancel: _cancelEdit,
        onSave: _save,
        tabController: _tabs,
        tabs: const [
          Tab(icon: Icon(Icons.person_outline), text: 'Perfil'),
          Tab(
              icon: Icon(Icons.local_shipping_outlined),
              text: 'Vehículos'),
          Tab(
              icon: Icon(Icons.workspace_premium_outlined),
              text: 'Mi Plan'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPerfilTab(isDark, textPrimary, kyc),
          _buildVehiculosTab(isDark),
          _buildPlanTab(isDark, textPrimary),
        ],
      ),
    );
  }

  Widget _buildPerfilTab(bool isDark, Color textPrimary, bool kyc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 3)),
                    child: Center(
                      child: Text(
                        _nameCtrl.text.isNotEmpty
                            ? _nameCtrl.text[0].toUpperCase()
                            : 'C',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                  if (kyc)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
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
                      borderRadius: BorderRadius.circular(20)),
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
                controller: _nameCtrl,
                label: 'Nombre completo',
                icon: Icons.person_outline,
                isDark: isDark,
                enabled: _isEditing,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _phoneCtrl,
                label: 'Teléfono',
                icon: Icons.phone_outlined,
                isDark: isDark,
                enabled: _isEditing,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                icon: Icons.email_outlined,
                isDark: isDark,
                enabled: false),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _categoriaCtrl,
                label: 'Categoría / Licencia',
                icon: Icons.card_membership_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Ubicación', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _paisCtrl,
                label: 'País',
                icon: Icons.public_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _provinciaCtrl,
                label: 'Provincia',
                icon: Icons.location_city_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 12),
            _ProfileField(
                controller: _municipioCtrl,
                label: 'Municipio',
                icon: Icons.map_outlined,
                isDark: isDark,
                enabled: _isEditing),
            const SizedBox(height: 32),
            if (!_isEditing) _signOutButton(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiculosTab(bool isDark) {
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddVehicleDialog(context, isDark),
              icon: const Icon(Icons.add),
              label: const Text('Agregar Vehículo'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ),
        Expanded(
          child: _loadingVehicles
              ? const Center(child: CircularProgressIndicator())
              : _carrocerias.isEmpty
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
                      itemCount: _carrocerias.length,
                      itemBuilder: (_, i) => _CarroceriaCard(
                        carroceria: _carrocerias[i],
                        isDark: isDark,
                        onEdit: () => _showEditVehicleDialog(
                            context, isDark, _carrocerias[i]),
                        onDelete: () =>
                            _deleteVehicle(_carrocerias[i].id!),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildPlanTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suscripción y Facturación',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary)),
          const SizedBox(height: 4),
          Text('El ciclo de facturación cierra el día 2 de cada mes.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600])),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }

  Future<void> _showAddVehicleDialog(BuildContext context, bool isDark) async {
    final marcaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final matriculaCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    String? tipoCarro;
    const tiposCarroceria = [
      'flatbed', 'dry_van', 'reefer', 'lowboy', 'tanker',
      'step_deck', 'hotshot', 'curtainsider', 'caja',
    ];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final textPrimary =
              isDark ? Colors.white : const Color(0xFF1A1D27);
          final bg = isDark ? AppTheme.darkCard : Colors.white;
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
                children: [
                  DropdownButtonFormField<String>(
                    value: tipoCarro,
                    dropdownColor: bg,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                        labelText: 'Tipo de carrocería',
                        prefixIcon: Icon(
                            Icons.local_shipping_outlined)),
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
                  _DialogField(
                      ctrl: marcaCtrl, label: 'Marca', isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(
                      ctrl: modeloCtrl, label: 'Modelo', isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(
                      ctrl: matriculaCtrl,
                      label: 'Matrícula / Chapa',
                      isDark: isDark),
                  const SizedBox(height: 12),
                  _DialogField(
                    ctrl: capCtrl,
                    label: 'Capacidad (toneladas)',
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: tipoCarro == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final driverId = context
                            .read<AuthProvider>()
                            .driverProfile?['id'] as int?;
                        if (driverId == null) return;
                        final c = CarroceriaModel(
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
                          capacidadTon:
                              double.tryParse(capCtrl.text.trim()),
                          seguroVigente: false,
                          activo: true,
                        );
                        final messenger =
                            ScaffoldMessenger.of(context);
                        try {
                          await _vehicleService.addCarroceria(c);
                          await _loadCarrocerias();
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppTheme.error,
                          ));
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

  /// Shows a dialog to edit an existing vehicle with all details including
  /// license photos, insurance, and vehicle photo.
  Future<void> _showEditVehicleDialog(
      BuildContext context, bool isDark, CarroceriaModel carroceria) async {
    final marcaCtrl =
        TextEditingController(text: carroceria.marca ?? '');
    final modeloCtrl =
        TextEditingController(text: carroceria.modelo ?? '');
    final matriculaCtrl =
        TextEditingController(text: carroceria.matricula ?? '');
    final capCtrl = TextEditingController(
        text: carroceria.capacidadTon?.toString() ?? '');
    final longitudCtrl = TextEditingController(
        text: carroceria.longitudM?.toString() ?? '');

    // Photo URLs
    String? vehiclePhotoUrl = carroceria.vehiclePhotoUrl;
    String? licCircFrenteUrl = carroceria.licCirculacionFrenteUrl;
    String? licCircDorsoUrl = carroceria.licCirculacionDorsoUrl;
    String? licOpFrenteUrl = carroceria.licOperativaFrenteUrl;
    String? licOpDorsoUrl = carroceria.licOperativaDorsoUrl;

    // Upload states
    bool uploadingVehiclePhoto = false;
    bool uploadingLicCircFrente = false;
    bool uploadingLicCircDorso = false;
    bool uploadingLicOpFrente = false;
    bool uploadingLicOpDorso = false;

    // Insurance
    bool seguroVigente = carroceria.seguroVigente;
    DateTime? seguroVence = carroceria.seguroVence;

    const tiposCarroceria = [
      'flatbed',
      'dry_van',
      'reefer',
      'lowboy',
      'tanker',
      'step_deck',
      'hotshot',
      'curtainsider',
      'caja',
    ];
    String tipoCarro = carroceria.tipoCarroceria;

    final docService = DocumentUploadService();
    final uuid = context.read<AuthProvider>().user?.id ?? 'carrier';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final textPrimary =
              isDark ? Colors.white : const Color(0xFF1A1D27);
          final bg = isDark ? AppTheme.darkCard : Colors.white;

          Future<void> pickPhoto(
              void Function() setUploading, Function(String?) onUrl) async {
            final source = await showModalBottomSheet<ImageSource>(
              context: ctx,
              backgroundColor: bg,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
            );
            if (source == null) return;
            setUploading();
            final url = await docService.pickCompressAndUpload(
              uuid: uuid,
              filename: 'doc_${DateTime.now().millisecondsSinceEpoch}.jpg',
              source: source,
            );
            onUrl(url);
          }

          Widget photoRow(String label, String? url, bool uploading,
              VoidCallback onTap) {
            final hasPhoto = url != null && url.isNotEmpty;
            return GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 40,
                        child: uploading
                            ? const Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : hasPhoto
                                ? Image.network(url!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholder())
                                : _placeholder(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            hasPhoto ? 'Cargada' : 'Sin foto',
                            style: TextStyle(
                                fontSize: 11,
                                color: hasPhoto
                                    ? AppTheme.success
                                    : (isDark
                                        ? Colors.white38
                                        : Colors.grey[500])),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      hasPhoto ? Icons.edit_outlined : Icons.upload_outlined,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Editar Vehículo',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vehicle Photo
                  Text('Foto del Vehículo (opcional)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(height: 6),
                  photoRow(
                    'Foto del vehículo',
                    vehiclePhotoUrl,
                    uploadingVehiclePhoto,
                    () => pickPhoto(
                      () => setS(() => uploadingVehiclePhoto = true),
                      (url) => setS(() {
                        vehiclePhotoUrl = url;
                        uploadingVehiclePhoto = false;
                      }),
                    ),
                  ),
                  const Divider(height: 20),

                  // Basic Info
                  _DialogField(
                      ctrl: marcaCtrl, label: 'Marca', isDark: isDark),
                  const SizedBox(height: 10),
                  _DialogField(
                      ctrl: modeloCtrl, label: 'Modelo', isDark: isDark),
                  const SizedBox(height: 10),
                  _DialogField(
                      ctrl: matriculaCtrl,
                      label: 'Matrícula / Chapa',
                      isDark: isDark),
                  const SizedBox(height: 10),
                  _DialogField(
                    ctrl: capCtrl,
                    label: 'Capacidad (ton)',
                    isDark: isDark,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  _DialogField(
                    ctrl: longitudCtrl,
                    label: 'Longitud plataforma (m)',
                    isDark: isDark,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
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
                                style: TextStyle(color: textPrimary))))
                        .toList(),
                    onChanged: (v) => setS(() => tipoCarro = v!),
                  ),

                  const Divider(height: 24),

                  // License Circulation
                  Text('Licencia de Circulación',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(height: 6),
                  photoRow(
                    'Frente',
                    licCircFrenteUrl,
                    uploadingLicCircFrente,
                    () => pickPhoto(
                      () => setS(() => uploadingLicCircFrente = true),
                      (url) => setS(() {
                        licCircFrenteUrl = url;
                        uploadingLicCircFrente = false;
                      }),
                    ),
                  ),
                  photoRow(
                    'Dorso',
                    licCircDorsoUrl,
                    uploadingLicCircDorso,
                    () => pickPhoto(
                      () => setS(() => uploadingLicCircDorso = true),
                      (url) => setS(() {
                        licCircDorsoUrl = url;
                        uploadingLicCircDorso = false;
                      }),
                    ),
                  ),

                  const Divider(height: 16),

                  // License Operativa
                  Text('Licencia Operativa',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(height: 6),
                  photoRow(
                    'Frente',
                    licOpFrenteUrl,
                    uploadingLicOpFrente,
                    () => pickPhoto(
                      () => setS(() => uploadingLicOpFrente = true),
                      (url) => setS(() {
                        licOpFrenteUrl = url;
                        uploadingLicOpFrente = false;
                      }),
                    ),
                  ),
                  photoRow(
                    'Dorso',
                    licOpDorsoUrl,
                    uploadingLicOpDorso,
                    () => pickPhoto(
                      () => setS(() => uploadingLicOpDorso = true),
                      (url) => setS(() {
                        licOpDorsoUrl = url;
                        uploadingLicOpDorso = false;
                      }),
                    ),
                  ),

                  const Divider(height: 16),

                  // Insurance
                  Text('Seguro del Vehículo',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Seguro vigente',
                        style: TextStyle(fontSize: 13, color: textPrimary)),
                    value: seguroVigente,
                    onChanged: (v) => setS(() => seguroVigente = v ?? false),
                  ),
                  if (seguroVigente) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: seguroVence ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setS(() => seguroVence = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Vencimiento del seguro',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          seguroVence != null
                              ? '${seguroVence!.day.toString().padLeft(2, '0')}/${seguroVence!.month.toString().padLeft(2, '0')}/${seguroVence!.year}'
                              : 'Seleccionar fecha',
                          style: TextStyle(color: textPrimary),
                        ),
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
                onPressed: () async {
                  Navigator.pop(ctx);
                  final vehData = <String, dynamic>{
                    'tipo_carroceria': tipoCarro,
                    if (marcaCtrl.text.trim().isNotEmpty)
                      'marca': marcaCtrl.text.trim(),
                    if (modeloCtrl.text.trim().isNotEmpty)
                      'modelo': modeloCtrl.text.trim(),
                    if (matriculaCtrl.text.trim().isNotEmpty)
                      'matricula': matriculaCtrl.text.trim(),
                    if (capCtrl.text.trim().isNotEmpty)
                      'capacidad_ton': double.tryParse(capCtrl.text.trim()),
                    if (longitudCtrl.text.trim().isNotEmpty)
                      'longitud_m': double.tryParse(longitudCtrl.text.trim()),
                    'seguro_vigente': seguroVigente,
                    if (seguroVence != null)
                      'seguro_vence':
                          seguroVence!.toIso8601String().substring(0, 10),
                    if (vehiclePhotoUrl != null)
                      'vehicle_photo_url': vehiclePhotoUrl,
                    if (licCircFrenteUrl != null)
                      'lic_circulacion_frente_url': licCircFrenteUrl,
                    if (licCircDorsoUrl != null)
                      'lic_circulacion_dorso_url': licCircDorsoUrl,
                    if (licOpFrenteUrl != null)
                      'lic_operativa_frente_url': licOpFrenteUrl,
                    if (licOpDorsoUrl != null)
                      'lic_operativa_dorso_url': licOpDorsoUrl,
                  };
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _vehicleService.updateCarroceria(carroceria.id!, vehData);
                    await _loadCarrocerias();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppTheme.error,
                    ));
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
    longitudCtrl.dispose();
  }

  Widget _placeholder() => Container(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        child: Icon(Icons.image_outlined,
            color: AppTheme.primaryColor.withValues(alpha: 0.5), size: 20),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DISPATCHER PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _DispatcherProfile extends StatefulWidget {
  const _DispatcherProfile();

  @override
  State<_DispatcherProfile> createState() => _DispatcherProfileState();
}

class _DispatcherProfileState extends State<_DispatcherProfile>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _empresaCtrl;
  late TextEditingController _rutCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl =
        TextEditingController(text: p?['telefono'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
    _empresaCtrl =
        TextEditingController(text: p?['empresa_nombre'] as String? ?? '');
    _rutCtrl =
        TextEditingController(text: p?['empresa_rut'] as String? ?? '');
    _direccionCtrl = TextEditingController(
        text: p?['empresa_direccion'] as String? ?? '');
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nameCtrl, _phoneCtrl, _emailCtrl, _empresaCtrl, _rutCtrl,
      _direccionCtrl, _paisCtrl, _provinciaCtrl, _municipioCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'telefono': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'empresa_nombre': _empresaCtrl.text.trim(),
      'empresa_rut': _rutCtrl.text.trim(),
      'empresa_direccion': _direccionCtrl.text.trim(),
      'pais': _paisCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      _snackOk(context);
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['telefono'] as String? ?? '';
    _emailCtrl.text = p?['email'] as String? ?? '';
    _empresaCtrl.text = p?['empresa_nombre'] as String? ?? '';
    _rutCtrl.text = p?['empresa_rut'] as String? ?? '';
    _direccionCtrl.text = p?['empresa_direccion'] as String? ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: _commonAppBar(
        context,
        isDark: isDark,
        isEditing: _isEditing,
        isSaving: _isSaving,
        onEdit: () => setState(() => _isEditing = true),
        onCancel: _cancelEdit,
        onSave: _save,
        tabController: _tabs,
        tabs: const [
          Tab(icon: Icon(Icons.person_outline), text: 'Perfil'),
          Tab(
              icon: Icon(Icons.workspace_premium_outlined),
              text: 'Mi Plan'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPerfilTab(isDark, textPrimary),
          _buildPlanTab(isDark, textPrimary),
        ],
      ),
    );
  }

  Widget _buildPerfilTab(bool isDark, Color textPrimary) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : Colors.grey[200]!;

    Widget field(String label, TextEditingController ctrl,
        {TextInputType? keyboard}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctrl,
          readOnly: !_isEditing,
          keyboardType: keyboard,
          style: TextStyle(color: textPrimary),
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: cardColor,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datos personales',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border)),
              child: Column(
                children: [
                  field('Nombre', _nameCtrl),
                  field('Teléfono', _phoneCtrl,
                      keyboard: TextInputType.phone),
                  field('Email', _emailCtrl,
                      keyboard: TextInputType.emailAddress),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Empresa dispatcher',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border)),
              child: Column(
                children: [
                  field('Nombre legal', _empresaCtrl),
                  field('RUT / ID fiscal', _rutCtrl),
                  field('Dirección', _direccionCtrl),
                  field('País', _paisCtrl),
                  field('Provincia', _provinciaCtrl),
                  field('Municipio', _municipioCtrl),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!_isEditing) _signOutButton(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suscripción y facturación',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary)),
          const SizedBox(height: 4),
          Text('Gestiona tu plan y solicita cambios con evidencia de pago.',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600])),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CarroceriaCard extends StatelessWidget {
  final CarroceriaModel carroceria;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _CarroceriaCard({
    required this.carroceria,
    required this.isDark,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final title = [carroceria.marca, carroceria.modelo]
        .where((e) => e != null && e.isNotEmpty)
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppTheme.darkBorder : Colors.grey[200]!)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              image: carroceria.vehiclePhotoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(carroceria.vehiclePhotoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
          ),
          child: carroceria.vehiclePhotoUrl == null
              ? const Icon(Icons.local_shipping_outlined,
                  color: AppTheme.primaryColor)
              : null,
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
        subtitle: Text(
          [
            carroceria.tipoCarroceria.toUpperCase(),
            if (carroceria.matricula != null) carroceria.matricula!,
            if (carroceria.capacidadTon != null)
              '${carroceria.capacidadTon!.toStringAsFixed(1)} ton',
          ].join(' · '),
          style: TextStyle(color: textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined, color: AppTheme.primaryColor),
              onPressed: onEdit,
              tooltip: 'Editar',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppTheme.error),
              onPressed: carroceria.id != null ? onDelete : null,
              tooltip: 'Eliminar',
            ),
          ],
        ),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// License photo row widget (frente / dorso)
// ─────────────────────────────────────────────────────────────────────────────

class _LicensePhotoRow extends StatelessWidget {
  final String label;
  final String? url;
  final bool uploading;
  final bool isDark;
  final VoidCallback? onTap;

  const _LicensePhotoRow({
    required this.label,
    required this.url,
    required this.uploading,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[200]!;
    final hasPhoto = url != null && url!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: onTap != null
                  ? AppTheme.primaryColor.withValues(alpha: 0.4)
                  : borderColor),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail or placeholder
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 44,
                child: uploading
                    ? const Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : hasPhoto
                        ? Image.network(url!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder())
                        : _placeholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto ? 'Foto cargada' : 'Sin foto',
                    style: TextStyle(
                        fontSize: 12,
                        color: hasPhoto
                            ? AppTheme.success
                            : (isDark ? Colors.white38 : Colors.grey[500])),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                hasPhoto ? Icons.edit_outlined : Icons.upload_outlined,
                size: 18,
                color: AppTheme.primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        child: Icon(Icons.image_outlined,
            color: AppTheme.primaryColor.withValues(alpha: 0.5), size: 24),
      );
}
