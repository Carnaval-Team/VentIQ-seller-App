import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/profile_photo_service.dart';
import '../../services/saved_address_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _ciController;
  late TextEditingController _direccionController;
  late TextEditingController _provinceController;
  late TextEditingController _municipalityController;
  late TextEditingController _paisController;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  final ProfilePhotoService _photoService = ProfilePhotoService();
  final SavedAddressService _addressService = SavedAddressService();

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().userProfile;
    _nameController =
        TextEditingController(text: profile?['name'] as String? ?? '');
    _phoneController =
        TextEditingController(text: profile?['phone'] as String? ?? '');
    _ciController =
        TextEditingController(text: profile?['ci'] as String? ?? '');
    _direccionController =
        TextEditingController(text: profile?['direccion'] as String? ?? '');
    _provinceController =
        TextEditingController(text: profile?['province'] as String? ?? '');
    _municipalityController =
        TextEditingController(text: profile?['municipality'] as String? ?? '');
    _paisController =
        TextEditingController(text: profile?['pais'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ciController.dispose();
    _direccionController.dispose();
    _provinceController.dispose();
    _municipalityController.dispose();
    _paisController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'ci': _ciController.text.trim(),
      'direccion': _direccionController.text.trim(),
      'province': _provinceController.text.trim(),
      'municipality': _municipalityController.text.trim(),
      'pais': _paisController.text.trim(),
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Perfil actualizado',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _changePhoto(ImageSource source) async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _photoService.pickCompressAndUpload(
        uuid: uuid,
        source: source,
      );
      if (url == null) return; // user cancelled

      // Persist to muevete.users.photo_url
      await _addressService.updateUserPhoto(uuid, url);

      if (!mounted) return;

      // Refresh profile in provider so avatar updates everywhere
      await context.read<AuthProvider>().updateProfile({'photo_url': url});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Foto actualizada',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error subiendo foto: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showPhotoSourceSheet() {
    final isDark = context.read<ThemeProvider>().isDark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: AppTheme.primaryColor),
                ),
                title: Text(
                  'Elegir de la galería',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _changePhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: AppTheme.primaryColor),
                ),
                title: Text(
                  'Tomar foto',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _changePhoto(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _cancelEdit() {
    final profile = context.read<AuthProvider>().userProfile;
    _nameController.text = profile?['name'] as String? ?? '';
    _phoneController.text = profile?['phone'] as String? ?? '';
    _ciController.text = profile?['ci'] as String? ?? '';
    _direccionController.text = profile?['direccion'] as String? ?? '';
    _provinceController.text = profile?['province'] as String? ?? '';
    _municipalityController.text = profile?['municipality'] as String? ?? '';
    _paisController.text = profile?['pais'] as String? ?? '';
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final authProvider = context.watch<AuthProvider>();
    final profile = authProvider.userProfile;

    final email = profile?['email'] as String? ?? '';
    final photoUrl =
        profile?['photo_url'] as String? ?? profile?['image'] as String?;
    final nameDisplay = _nameController.text.isNotEmpty
        ? _nameController.text
        : 'Usuario';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Mi Perfil',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : Colors.black87),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit_outlined,
                  size: 18,
                  color: AppTheme.primaryColor),
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
              onPressed: _isSaving ? null : _cancelEdit,
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Avatar
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.15),
                      backgroundImage:
                          photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                      child: _isUploadingPhoto
                          ? const CircularProgressIndicator(
                              color: AppTheme.primaryColor,
                              strokeWidth: 3,
                            )
                          : (photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  nameDisplay.isNotEmpty
                                      ? nameDisplay[0].toUpperCase()
                                      : 'U',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                )
                              : null),
                    ),
                    // Camera button — always visible (not only in edit mode)
                    // so users can update their photo at any time.
                    if (!_isUploadingPhoto)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showPhotoSourceSheet,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: isDark
                                      ? AppTheme.darkBg
                                      : Colors.white,
                                  width: 2),
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Email — read only
              _ReadonlyField(
                icon: Icons.email_outlined,
                label: 'Correo electrónico',
                value: email.isNotEmpty ? email : 'No registrado',
                isDark: isDark,
              ),
              const SizedBox(height: 14),

              // Editable fields
              _EditableField(
                controller: _nameController,
                icon: Icons.person_outline,
                label: 'Nombre completo',
                enabled: _isEditing,
                isDark: isDark,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _phoneController,
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                enabled: _isEditing,
                isDark: isDark,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _ciController,
                icon: Icons.badge_outlined,
                label: 'Cédula de identidad',
                enabled: _isEditing,
                isDark: isDark,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _direccionController,
                icon: Icons.home_outlined,
                label: 'Dirección',
                enabled: _isEditing,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _paisController,
                icon: Icons.public_outlined,
                label: 'País',
                enabled: _isEditing,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _provinceController,
                icon: Icons.location_city_outlined,
                label: 'Provincia / Estado',
                enabled: _isEditing,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _EditableField(
                controller: _municipalityController,
                icon: Icons.place_outlined,
                label: 'Ciudad / Municipio',
                enabled: _isEditing,
                isDark: isDark,
              ),
              const SizedBox(height: 40),

              // Sign out
              if (!_isEditing)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await authProvider.signOut();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                            context, '/login', (_) => false);
                      }
                    },
                    icon: const Icon(Icons.logout, color: AppTheme.error),
                    label: Text(
                      'Cerrar sesión',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Read-only display field (e.g. email) ──────────────────────────────────────

class _ReadonlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _ReadonlyField({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline,
              size: 16,
              color: isDark ? Colors.white24 : Colors.grey[400]),
        ],
      ),
    );
  }
}

// ── Editable field ────────────────────────────────────────────────────────────

class _EditableField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDark;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _EditableField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.isDark,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          color: enabled
              ? AppTheme.primaryColor
              : (isDark ? Colors.white38 : Colors.grey[500]),
        ),
        prefixIcon: Icon(
          icon,
          color: enabled
              ? AppTheme.primaryColor
              : (isDark ? Colors.white38 : Colors.grey[400]),
          size: 20,
        ),
        filled: true,
        fillColor: enabled
            ? (isDark
                ? AppTheme.darkCard
                : Colors.white)
            : (isDark
                ? AppTheme.darkCard.withValues(alpha: 0.5)
                : Colors.grey[50]),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: AppTheme.primaryColor, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
