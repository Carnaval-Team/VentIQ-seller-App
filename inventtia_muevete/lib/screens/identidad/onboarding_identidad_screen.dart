import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/document_upload_service.dart';
import '../../services/identidad_service.dart';
import '../../utils/app_error.dart';
import '../../utils/gate_seguridad.dart';

/// Pantalla bloqueante "Completa tu perfil" (H1).
///
/// Sube CI + fotos del carnet + ubicación a `muevete.users`/`muevete.drivers`
/// por `fn_guardar_identidad` y, al terminar, continúa con el siguiente paso
/// pendiente del gate (consentimiento o contacto de emergencia).
class OnboardingIdentidadScreen extends StatefulWidget {
  const OnboardingIdentidadScreen({super.key});

  @override
  State<OnboardingIdentidadScreen> createState() =>
      _OnboardingIdentidadScreenState();
}

class _OnboardingIdentidadScreenState extends State<OnboardingIdentidadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identidad = IdentidadService();
  final _documentos = DocumentUploadService();

  final _ciCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _provinciaCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _pobladoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  String _tipoDocumento = 'carnet';
  String _rol = 'cliente';
  String? _frenteUrl;
  String? _dorsoUrl;
  bool _subiendoFrente = false;
  bool _subiendoDorso = false;

  EstadoIdentidad? _estado;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _motivo;

  static const Map<String, String> _tiposDocumento = {
    'carnet': 'Carnet de identidad',
    'pasaporte': 'Pasaporte',
    'otro': 'Otro documento',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && _motivo == null) {
      _motivo = args['motivo']?.toString();
      final rolArg = args['rol']?.toString();
      if (rolArg == 'chofer' || rolArg == 'cliente') _rol = rolArg!;
    }
  }

  @override
  void dispose() {
    _ciCtrl.dispose();
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _pobladoCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  // ── Carga ───────────────────────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final estado = await _identidad.estado();
      if (!mounted) return;

      final auth = context.read<AuthProvider>();
      final rol =
          estado.rol ??
          (auth.isDriver || auth.isConductorPasajeros ? 'chofer' : 'cliente');

      final datos = await _perfilActual(rol);
      if (!mounted) return;

      setState(() {
        _estado = estado;
        _rol = rol;
        _aplicarDatos(datos);
        _cargando = false;
      });
    } on IdentidadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = AppError.message(e, action: 'cargar tu perfil');
      });
    }
  }

  /// Lee lo ya guardado para no pedir dos veces los mismos datos.
  Future<Map<String, dynamic>> _perfilActual(String rol) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const {};

    final tabla = rol == 'chofer' ? 'drivers' : 'users';
    try {
      final row = await Supabase.instance.client
          .schema('muevete')
          .from(tabla)
          .select()
          .eq('uuid', uid)
          .maybeSingle();
      if (row == null) return const {};
      return Map<String, dynamic>.from(row);
    } catch (_) {
      // Sin permiso de lectura queda el formulario vacío; el guardado usa
      // `coalesce` en el servidor y no borra nada.
      return const {};
    }
  }

  void _aplicarDatos(Map<String, dynamic> datos) {
    String texto(dynamic v) => (v ?? '').toString().trim();

    _ciCtrl.text = texto(datos['ci']);
    _nombreCtrl.text = texto(datos['name']);
    _telefonoCtrl.text = texto(datos['phone']).isNotEmpty
        ? texto(datos['phone'])
        : texto(datos['telefono']);
    _provinciaCtrl.text = texto(datos['province']);
    _municipioCtrl.text = texto(datos['municipality']);
    _pobladoCtrl.text = texto(datos['poblado']);
    _direccionCtrl.text = texto(datos['direccion']);

    final tipo = texto(datos['tipo_documento']).toLowerCase();
    _tipoDocumento = _tiposDocumento.containsKey(tipo) ? tipo : 'carnet';

    final frente = texto(datos['doc_frente_url']);
    final dorso = texto(datos['doc_dorso_url']);
    if (frente.isNotEmpty) _frenteUrl = frente;
    if (dorso.isNotEmpty) _dorsoUrl = dorso;
  }

  // ── Fotos ───────────────────────────────────────────────────────────────

  Future<void> _elegirFoto(bool frente) async {
    final source = await _elegirFuente();
    if (source == null) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() {
      if (frente) {
        _subiendoFrente = true;
      } else {
        _subiendoDorso = true;
      }
    });

    try {
      final url = await _documentos.pickCompressAndUpload(
        uuid: uid,
        filename: frente ? 'ci_frente' : 'ci_dorso',
        source: source,
      );
      if (url != null && mounted) {
        setState(() {
          if (frente) {
            _frenteUrl = url;
          } else {
            _dorsoUrl = url;
          }
        });
      }
    } catch (e) {
      if (mounted) _snack(AppError.message(e, action: 'subir la foto'));
    } finally {
      if (mounted) {
        setState(() {
          if (frente) {
            _subiendoFrente = false;
          } else {
            _subiendoDorso = false;
          }
        });
      }
    }
  }

  Future<ImageSource?> _elegirFuente() async {
    final isDark = context.read<ThemeProvider>().isDark;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar la foto ahora'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  // ── Guardado ────────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (_guardando) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (!IdentidadService.ciValido(_ciCtrl.text)) {
      _snack('El carnet debe tener 11 dígitos con una fecha válida');
      return;
    }
    if ((_frenteUrl ?? '').isEmpty || (_dorsoUrl ?? '').isEmpty) {
      _snack('Faltan las fotos del carnet (frente y dorso)');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final estado = await _identidad.guardarIdentidad(
        rol: _rol,
        ci: _ciCtrl.text,
        poblado: _pobladoCtrl.text,
        direccion: _direccionCtrl.text,
        provincia: _provinciaCtrl.text,
        municipio: _municipioCtrl.text,
        tipoDocumento: _tipoDocumento,
        docFrenteUrl: _frenteUrl,
        docDorsoUrl: _dorsoUrl,
        nombre: _nombreCtrl.text,
        telefono: _telefonoCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _guardando = false;
      });
      await _continuar(estado);
    } on IdentidadException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
      _snack(e.mensaje);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = AppError.message(e, action: 'guardar tu identidad');
      });
      _snack(AppError.message(e, action: 'guardar tu identidad'));
    }
  }

  /// Siguiente paso del gate, en orden: consentimiento → contactos → listo.
  Future<void> _continuar(EstadoIdentidad estado) async {
    final navigator = Navigator.of(context);

    if (!estado.perfil.ok) {
      _snack('Faltan datos del perfil: revisa los campos marcados');
      return;
    }

    if (!estado.consentimiento.ok) {
      navigator.pushReplacementNamed(
        '/identidad/consentimiento',
        arguments: {
          'motivo': 'Acepta la privacidad y los términos para continuar',
        },
      );
      return;
    }

    // Chofer: la aprobación de KYC la hace el equipo; el perfil ya está bien.
    final kycPendiente = estado.motivos.contains('kyc_pendiente_aprobacion');
    if (kycPendiente) {
      _snack('Perfil guardado. Tu verificación de identidad está en revisión');
    }

    final gate = await GateSeguridad.evaluar(rol: _rol);
    if (!mounted) return;

    if (gate.paso == PasoSeguridad.contactos) {
      navigator.pushReplacementNamed(
        '/seguridad/contactos',
        arguments: {'motivo': gate.motivo},
      );
      return;
    }

    if (gate.paso == PasoSeguridad.bloqueado) {
      _snack(gate.motivo);
      return;
    }

    navigator.pop(true);
  }

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje, style: GoogleFonts.plusJakartaSans()),
        backgroundColor: AppTheme.error,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(isDark),
        elevation: 0,
        title: Text(
          'Completa tu perfil',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _encabezado(isDark, textPrimary, textSecondary),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      _avisoError(isDark),
                      const SizedBox(height: 16),
                    ],
                    _seccion('Documento de identidad', isDark, textPrimary),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _ciCtrl,
                      label: 'Carnet de identidad',
                      hint: '11 dígitos',
                      icon: Icons.badge_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Escribe tu carnet de identidad';
                        }
                        if (!IdentidadService.ciValido(v)) {
                          return 'Deben ser 11 dígitos con fecha válida';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _dropdownTipo(isDark, textPrimary),
                    const SizedBox(height: 16),
                    Text(
                      'Fotos del carnet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _fotoCarnet(
                            titulo: 'Frente',
                            url: _frenteUrl,
                            subiendo: _subiendoFrente,
                            isDark: isDark,
                            onTap: () => _elegirFoto(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _fotoCarnet(
                            titulo: 'Dorso',
                            url: _dorsoUrl,
                            subiendo: _subiendoDorso,
                            isDark: isDark,
                            onTap: () => _elegirFoto(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'La foto se usa sólo para verificar tu identidad. '
                      'No se muestra a otros usuarios.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _seccion('Dónde vives', isDark, textPrimary),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _provinciaCtrl,
                      label: 'Provincia',
                      hint: 'Villa Clara',
                      icon: Icons.map_outlined,
                      isDark: isDark,
                      validator: _obligatorio('Escribe tu provincia'),
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _municipioCtrl,
                      label: 'Municipio',
                      hint: 'Santa Clara',
                      icon: Icons.location_city_outlined,
                      isDark: isDark,
                      validator: _obligatorio('Escribe tu municipio'),
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _pobladoCtrl,
                      label: 'Poblado o reparto',
                      hint: 'Ej.: Condado',
                      icon: Icons.holiday_village_outlined,
                      isDark: isDark,
                      validator: _obligatorio('Escribe tu poblado'),
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _direccionCtrl,
                      label: 'Dirección',
                      hint: 'Calle, número y entre calles',
                      icon: Icons.home_outlined,
                      isDark: isDark,
                      maxLines: 2,
                      validator: _obligatorio('Escribe tu dirección'),
                    ),
                    const SizedBox(height: 24),
                    _seccion('Cómo te contactamos', isDark, textPrimary),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _nombreCtrl,
                      label: 'Nombre y apellidos',
                      hint: 'Como aparece en tu carnet',
                      icon: Icons.person_outline,
                      isDark: isDark,
                      validator: _obligatorio('Escribe tu nombre'),
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      controller: _telefonoCtrl,
                      label: 'Teléfono',
                      hint: '55512345',
                      icon: Icons.phone_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.phone,
                      validator: _obligatorio('Escribe tu teléfono'),
                    ),
                    const SizedBox(height: 24),
                    _nota(isDark, textSecondary),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _guardando ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.primaryColor
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Guardar y continuar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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

  Widget _encabezado(bool isDark, Color textPrimary, Color textSecondary) {
    final faltantes = _estado?.perfil.faltantes ?? const <String>[];
    final motivos = _estado?.motivos ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(
              alpha: isDark ? 0.18 : 0.08,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Necesitamos verificar quién eres',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _motivo ??
                    _estado?.mensaje ??
                    'Sin estos datos no puedes pedir ni tomar viajes.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (faltantes.isNotEmpty || motivos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Lo que falta',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in faltantes) _chipFaltante(f, isDark),
              for (final m in motivos)
                if (m != 'consentimiento_pendiente') _chipFaltante(m, isDark),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chipFaltante(String clave, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: isDark ? 0.22 : 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.6)),
      ),
      child: Text(
        IdentidadService.etiquetaMotivo(clave),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _avisoError(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, bool isDark, Color textPrimary) {
    return Text(
      titulo,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
    );
  }

  Widget _nota(bool isDark, Color textSecondary) {
    final esChofer = _rol == 'chofer';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              esChofer
                  ? 'Cuando guardes, el equipo revisa tus documentos. Hasta que '
                        'se aprueben no podrás tomar viajes.'
                  : 'Guardamos tus datos cifrados y sólo los usa el equipo para '
                        'verificar tu identidad.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.35,
                color: textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  FormFieldValidator<String> _obligatorio(String mensaje) {
    return (v) => (v == null || v.trim().isEmpty) ? mensaje : null;
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    String? hint,
    TextInputType? keyboardType,
    int? maxLength,
    int maxLines = 1,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: AppTheme.textPrimary(isDark),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppTheme.card(isDark),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          color: AppTheme.textTertiary(isDark),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border(isDark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border(isDark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _dropdownTipo(bool isDark, Color textPrimary) {
    return DropdownButtonFormField<String>(
      initialValue: _tipoDocumento,
      dropdownColor: AppTheme.surface(isDark),
      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textPrimary),
      decoration: InputDecoration(
        labelText: 'Tipo de documento',
        prefixIcon: const Icon(Icons.assignment_ind_outlined, size: 20),
        filled: true,
        fillColor: AppTheme.card(isDark),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border(isDark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border(isDark)),
        ),
      ),
      items: [
        for (final entry in _tiposDocumento.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _tipoDocumento = v);
      },
    );
  }

  Widget _fotoCarnet({
    required String titulo,
    required String? url,
    required bool subiendo,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final tiene = (url ?? '').isNotEmpty;
    return InkWell(
      onTap: subiendo ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tiene
                ? AppTheme.success.withValues(alpha: 0.7)
                : AppTheme.border(isDark),
            width: tiene ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (tiene)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url!, fit: BoxFit.cover),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tiene ? Colors.black.withValues(alpha: 0.25) : null,
                ),
                child: Center(
                  child: subiendo
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tiene
                                  ? Icons.check_circle
                                  : Icons.add_a_photo_outlined,
                              color: tiene
                                  ? AppTheme.success
                                  : AppTheme.textSecondary(isDark),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tiene ? 'Cambiar $titulo' : titulo,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tiene
                                    ? Colors.white
                                    : AppTheme.textPrimary(isDark),
                              ),
                            ),
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
