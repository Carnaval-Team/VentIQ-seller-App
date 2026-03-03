import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/document_upload_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();

  bool _obscurePassword = true;
  String _selectedRole = 'client';
  String _selectedCountry = 'Cuba';
  String _selectedCountryCode = '+53';

  // Document upload state
  String _selectedDocType = 'Carnet de Identidad';
  String? _docFrenteUrl;
  String? _docDorsoUrl;
  bool _isUploadingFrente = false;
  bool _isUploadingDorso = false;

  // Temp UUID for upload before auth user is created
  String? _tempUuid;

  final DocumentUploadService _docService = DocumentUploadService();

  static const List<Map<String, String>> _countries = [
    {'name': 'Cuba', 'code': '+53'},
    {'name': 'Mexico', 'code': '+52'},
    {'name': 'Colombia', 'code': '+57'},
    {'name': 'Argentina', 'code': '+54'},
    {'name': 'Espana', 'code': '+34'},
    {'name': 'Estados Unidos', 'code': '+1'},
  ];

  static const List<String> _docTypes = [
    'Carnet de Identidad',
    'Pasaporte',
    'Licencia de Conducir',
  ];

  @override
  void initState() {
    super.initState();
    // Generate a temp UUID for storage path before account creation
    _tempUuid = DateTime.now().millisecondsSinceEpoch.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument({required bool isFront}) async {
    final isDark = context.read<ThemeProvider>().isDark;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
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
                  leading: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                  title: Text('Camara', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: AppTheme.primaryColor),
                  title: Text('Galeria', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
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
      final filename = isFront ? 'doc_frente' : 'doc_dorso';
      final url = await _docService.pickCompressAndUpload(
        uuid: _tempUuid!,
        filename: filename,
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: AppTheme.error,
          ),
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

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate documents uploaded
    if (_docFrenteUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes subir la foto del frente del documento'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (_docDorsoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes subir la foto del dorso del documento'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();

    final success = await authProvider.signUp(
      _emailController.text.trim(),
      _passwordController.text,
      name: _nameController.text.trim(),
      role: _selectedRole,
      phone: '$_selectedCountryCode${_phoneController.text.trim()}',
      pais: _selectedCountry,
      province: _stateController.text.trim(),
      municipality: _cityController.text.trim(),
      tipoDocumento: _selectedDocType,
      docFrenteUrl: _docFrenteUrl,
      docDorsoUrl: _docDorsoUrl,
    );

    if (!mounted) return;

    if (success) {
      if (authProvider.isDriver) {
        Navigator.pushReplacementNamed(context, '/driver/home');
      } else {
        Navigator.pushReplacementNamed(context, '/client/home');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error ?? 'Error al crear la cuenta',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.grey[600]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),

                      // --- Account Info ---
                      _SectionHeader(title: 'Informacion de Cuenta'),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Nombre Completo *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: textPrimary),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Tu nombre completo',
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El nombre es requerido';
                          }
                          if (value.trim().length < 2) {
                            return 'Nombre muy corto';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Correo Electronico *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'correo@ejemplo.com',
                          prefixIcon: Icon(Icons.email_outlined, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El correo es requerido';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value.trim())) {
                            return 'Ingresa un correo valido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Contrasena *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Minimo 6 caracteres',
                          prefixIcon:
                              const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.grey[500],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'La contrasena es requerida';
                          }
                          if (value.length < 6) {
                            return 'Minimo 6 caracteres';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 28),

                      // --- Location & Contact ---
                      _SectionHeader(title: 'Ubicacion y Contacto'),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Pais *'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedCountry,
                        dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                        style: TextStyle(color: textPrimary),
                        decoration: const InputDecoration(
                          prefixIcon:
                              Icon(Icons.public_outlined, size: 20),
                        ),
                        items: _countries
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c['name'],
                                child: Text(c['name']!),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedCountry = value;
                              _selectedCountryCode = _countries.firstWhere(
                                  (c) => c['name'] == value)['code']!;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Provincia / Estado *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _stateController,
                        style: TextStyle(color: textPrimary),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Ej. La Habana',
                          prefixIcon:
                              Icon(Icons.location_city_outlined, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La provincia es requerida';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Ciudad / Municipio *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _cityController,
                        style: TextStyle(color: textPrimary),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Plaza de la Revolucion',
                          prefixIcon: Icon(Icons.place_outlined, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La ciudad es requerida';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Telefono *'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _selectedCountryCode,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Numero de telefono',
                                prefixIcon:
                                    Icon(Icons.phone_outlined, size: 20),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El telefono es requerido';
                                }
                                if (!RegExp(r'^\d{6,15}$')
                                    .hasMatch(value.trim())) {
                                  return 'Numero invalido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // --- Document Verification ---
                      _SectionHeader(title: 'Documento de Identidad'),
                      const SizedBox(height: 8),
                      Text(
                        'Sube foto del frente y dorso de tu documento. Es obligatorio para verificar tu cuenta.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel(label: 'Tipo de Documento *'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedDocType,
                        dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                        style: TextStyle(color: textPrimary),
                        decoration: const InputDecoration(
                          prefixIcon:
                              Icon(Icons.badge_outlined, size: 20),
                        ),
                        items: _docTypes
                            .map(
                              (d) => DropdownMenuItem<String>(
                                value: d,
                                child: Text(d),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedDocType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Front photo
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

                      // Back photo
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

                      // --- Role selection ---
                      _SectionHeader(title: 'Tipo de Cuenta'),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _RoleToggle(
                              icon: Icons.person_outline,
                              label: 'Cliente',
                              subtitle: 'Solicitar viajes',
                              isSelected: _selectedRole == 'client',
                              onTap: () {
                                setState(() => _selectedRole = 'client');
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _RoleToggle(
                              icon: Icons.directions_car_outlined,
                              label: 'Conductor',
                              subtitle: 'Ofrecer viajes',
                              isSelected: _selectedRole == 'driver',
                              onTap: () {
                                setState(() => _selectedRole = 'driver');
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Register button
                      Consumer<AuthProvider>(
                        builder: (context, auth, _) {
                          return ElevatedButton(
                            onPressed:
                                auth.isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              disabledBackgroundColor:
                                  AppTheme.primaryColor.withValues(alpha: 0.5),
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
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: RichText(
                            text: TextSpan(
                              text: 'Ya tienes cuenta? ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: textSecondary,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Inicia Sesion',
                                  style: theme.textTheme.bodyMedium?.copyWith(
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Document upload tile ---

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
                  color: AppTheme.primaryColor,
                  strokeWidth: 2.5,
                ),
              )
            : imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.check_circle,
                              color: AppTheme.success,
                              size: 40,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
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
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Cambiar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 32,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toca para subir',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// --- Private helper widgets ---

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
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
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: isDark
            ? Colors.white.withValues(alpha: 0.8)
            : Colors.grey[700],
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textMuted = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey[500]!;
    final unselectedIcon = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.grey[500]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
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
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected
                  ? AppTheme.primaryColor
                  : unselectedIcon,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? AppTheme.primaryColor : textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
