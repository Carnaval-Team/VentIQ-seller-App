import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/identidad_service.dart';
import '../../services/seguridad_service.dart';
import '../../utils/app_error.dart';

/// Contactos de emergencia (H2 · F3).
///
/// Un contacto de prioridad 1 es obligatorio para viajar: sin él el servidor
/// rechaza publicar y tomar viajes con `P0110`. Mientras no exista proveedor
/// SMS, el contacto se muestra como **"sin verificar"** y el OTP nunca se
/// devuelve ni se enseña en la app.
class ContactosEmergenciaScreen extends StatefulWidget {
  const ContactosEmergenciaScreen({super.key});

  @override
  State<ContactosEmergenciaScreen> createState() =>
      _ContactosEmergenciaScreenState();
}

class _ContactosEmergenciaScreenState extends State<ContactosEmergenciaScreen> {
  final SeguridadService _seguridad = SeguridadService();
  final IdentidadService _identidad = IdentidadService();

  List<ContactoEmergencia> _contactos = const [];
  bool _cargando = true;
  String? _error;
  String? _motivo;

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
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final contactos = await _seguridad.contactos();
      if (!mounted) return;
      setState(() {
        _contactos = contactos;
        _cargando = false;
      });
    } on SeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = AppError.message(e, action: 'cargar tus contactos');
      });
    }
  }

  // ── Alta ────────────────────────────────────────────────────────────────

  Future<void> _agregar() async {
    final datos = await showModalBottomSheet<_ContactoFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ContactoFormSheet(),
    );
    if (datos == null) return;

    try {
      final creado = await _seguridad.crearContacto(
        nombre: datos.nombre,
        telefono: datos.telefono,
        parentesco: datos.parentesco,
        prioridad: datos.prioridad,
      );

      // Declaración explícita: el teléfono es de un tercero.
      await _registrarDeclaracion(creado);

      if (!mounted) return;
      await _cargar();
      if (!mounted) return;

      final verificar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Contacto guardado'),
          content: Text(
            '${creado.nombre} quedó registrado con prioridad '
            '${creado.prioridad}. ¿Quieres verificar el número ahora?',
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Después'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verificar'),
            ),
          ],
        ),
      );
      if (verificar == true) {
        await _verificar(creado);
      }
    } on SeguridadException catch (e) {
      _snack(e.mensaje);
    } on IdentidadException catch (e) {
      _snack(e.mensaje);
    } catch (e) {
      _snack(AppError.message(e, action: 'guardar el contacto'));
    }
  }

  /// Registra en `consentimientos` la declaración de autorización del titular
  /// del teléfono, con el número enmascarado en `metadata`.
  Future<void> _registrarDeclaracion(ContactoEmergencia contacto) async {
    final metadata = <String, dynamic>{
      'contacto_id': contacto.id,
      'telefono_enmascarado': SeguridadService.enmascararTelefono(
        contacto.telefono,
      ),
      'declaracion':
          'El titular declara tener autorización de esa persona para usar su '
          'teléfono como contacto de emergencia',
      'app_version': kAppVersion,
      'user_agent': kUserAgent,
    };
    try {
      await _identidad.aceptarDocumentoOpcional(
        'contacto_emergencia',
        metadata: metadata,
      );
    } catch (_) {
      // La declaración es obligatoria en la UI, pero si el servidor no tiene
      // publicado el documento no se bloquea el alta: queda anotado en el
      // informe como cabo suelto.
    }
  }

  // ── Verificación ────────────────────────────────────────────────────────

  Future<void> _verificar(ContactoEmergencia contacto) async {
    try {
      final res = await _seguridad.iniciarValidacion(contacto.id);
      if (!mounted) return;

      if (res['ya_validado'] == true || res['estado'] == 'aceptado') {
        await _cargar();
        if (!mounted) return;
        _snack('Ese contacto ya estaba verificado');
        return;
      }

      final entornoDev = res['entorno_dev'] == true;
      final mensajeServidor = (res['mensaje'] ?? '').toString();

      if (!entornoDev) {
        final quiereCodigo = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sin verificación automática'),
            content: Text(
              mensajeServidor.isNotEmpty
                  ? mensajeServidor
                  : 'Sin verificación automática disponible: tu contacto queda '
                        'como no verificado.',
              style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Entendido'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ya tengo un código'),
              ),
            ],
          ),
        );
        await _cargar();
        if (quiereCodigo != true) return;
      }

      final codigo = await _pedirCodigo(contacto);
      if (codigo == null) return;

      await _seguridad.confirmarContacto(contacto.id, codigo);
      await _cargar();
      if (!mounted) return;
      _snack('Contacto verificado');
    } on SeguridadException catch (e) {
      _snack(e.mensaje);
      await _cargar();
    } catch (e) {
      _snack(AppError.message(e, action: 'verificar el contacto'));
    }
  }

  /// Pide el código. **Nunca** se muestra ni se sugiere ningún valor.
  Future<String?> _pedirCodigo(ContactoEmergencia contacto) async {
    final ctrl = TextEditingController();
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escribe el código'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pídele a ${contacto.nombre} el código de 4 dígitos que recibió.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Código',
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Confirmamos que el número responde. No podemos comprobar que '
              'sea de quien dice ser.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = ctrl.text.trim();
              if (valor.isEmpty) return;
              Navigator.pop(ctx, valor);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return resultado;
  }

  // ── Editar / eliminar ───────────────────────────────────────────────────

  Future<void> _editar(ContactoEmergencia contacto) async {
    final datos = await showModalBottomSheet<_ContactoFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactoFormSheet(contacto: contacto),
    );
    if (datos == null) return;

    try {
      await _seguridad.actualizarContacto(
        contacto.id,
        nombre: datos.nombre,
        telefono: datos.telefono,
        parentesco: datos.parentesco,
        prioridad: datos.prioridad,
      );
      await _cargar();
      if (!mounted) return;
      _snack('Contacto actualizado');
    } on SeguridadException catch (e) {
      _snack(e.mensaje);
    } catch (e) {
      _snack(AppError.message(e, action: 'actualizar el contacto'));
    }
  }

  Future<void> _eliminar(ContactoEmergencia contacto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar contacto'),
        content: Text(
          '¿Quitar a ${contacto.nombre} de tus contactos de emergencia?',
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _seguridad.eliminarContacto(contacto.id);
      await _cargar();
      if (!mounted) return;
      _snack('Contacto eliminado');
    } on SeguridadException catch (e) {
      _snack(e.mensaje);
    } catch (e) {
      _snack(AppError.message(e, action: 'eliminar el contacto'));
    }
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
          'Contactos de emergencia',
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  _encabezado(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    _avisoError(isDark),
                    const SizedBox(height: 12),
                  ],
                  if (_contactos.isEmpty && _error == null)
                    _vacio(isDark, textPrimary, textSecondary)
                  else
                    for (final contacto in _contactos) ...[
                      _tarjeta(contacto, isDark, textPrimary, textSecondary),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 8),
                  Text(
                    'Nunca mostramos el código de verificación en la app ni se '
                    'lo enviamos a la otra persona. Los contactos no son '
                    'visibles para el chofer ni para el pasajero del viaje.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _agregar,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              label: Text(
                'Agregar contacto',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _encabezado(bool isDark, Color textPrimary, Color textSecondary) {
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
              color: AppTheme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.contact_emergency_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tu contacto de emergencia',
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
                    'Es a quien avisamos si activas la emergencia. Necesitamos '
                        'al menos uno para que puedas viajar.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.35,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _vacio(bool isDark, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        children: [
          Icon(Icons.person_off_outlined, size: 36, color: textSecondary),
          const SizedBox(height: 10),
          Text(
            'Todavía no tienes contactos',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sin un contacto que responda no podemos avisar a nadie si te '
            'pasa algo. Agrega al menos uno con prioridad 1.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.35,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(
    ContactoEmergencia contacto,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final esPrincipal = contacto.prioridad == 1;
    final verificado = contacto.verificado;
    final colorEstado = verificado
        ? AppTheme.success
        : (contacto.estado == 'rechazado' ? AppTheme.error : AppTheme.warning);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contacto.nombre,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (esPrincipal) ...[
                          const SizedBox(width: 6),
                          _chip('Principal', AppTheme.primaryColor, isDark),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((contacto.parentesco ?? '').isNotEmpty)
                          contacto.parentesco!,
                        contacto.telefonoEnmascarado,
                      ].join(' · '),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _chip(contacto.estadoLegible, colorEstado, isDark),
            ],
          ),
          const SizedBox(height: 10),
          if (!verificado)
            Text(
              'Este número no está verificado. El contacto recibe el aviso, '
              'pero no podemos confirmar que responda.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                height: 1.3,
                color: textSecondary,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!verificado)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _verificar(contacto),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Verificar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              if (!verificado) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editar(contacto),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textPrimary,
                    side: BorderSide(color: AppTheme.border(isDark)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => _eliminar(contacto),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Icon(Icons.delete_outline, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Datos del formulario de contacto.
class _ContactoFormData {
  final String nombre;
  final String telefono;
  final String? parentesco;
  final int prioridad;

  const _ContactoFormData({
    required this.nombre,
    required this.telefono,
    required this.prioridad,
    this.parentesco,
  });
}

/// Alta/edición de contacto con la declaración explícita obligatoria.
class _ContactoFormSheet extends StatefulWidget {
  final ContactoEmergencia? contacto;

  const _ContactoFormSheet({this.contacto});

  @override
  State<_ContactoFormSheet> createState() => _ContactoFormSheetState();
}

class _ContactoFormSheetState extends State<_ContactoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _parentescoCtrl;
  late int _prioridad;
  bool _declara = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contacto;
    _nombreCtrl = TextEditingController(text: c?.nombre ?? '');
    _telefonoCtrl = TextEditingController(
      text: (c?.telefono ?? '').replaceFirst('+53', ''),
    );
    _parentescoCtrl = TextEditingController(text: c?.parentesco ?? '');
    _prioridad = c?.prioridad ?? 1;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _parentescoCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (!_declara) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Debes declarar que tienes autorización de esa persona',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _ContactoFormData(
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        parentesco: _parentescoCtrl.text.trim(),
        prioridad: _prioridad,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);
    final editando = widget.contacto != null;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: inset),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border(isDark),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  editando ? 'Editar contacto' : 'Nuevo contacto',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nombreCtrl,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: textPrimary,
                  ),
                  decoration: _decoracion(
                    'Nombre',
                    'Ej.: Mamá, Ana Pérez',
                    Icons.person_outline,
                    isDark,
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Escribe el nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: textPrimary,
                  ),
                  decoration: _decoracion(
                    'Teléfono',
                    '55512345',
                    Icons.phone_outlined,
                    isDark,
                    prefix: '+53 ',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Escribe el teléfono';
                    }
                    if (SeguridadService.normalizarTelefono(v) == null) {
                      return 'Teléfono no válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _parentescoCtrl,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: textPrimary,
                  ),
                  decoration: _decoracion(
                    'Parentesco (opcional)',
                    'Ej.: madre, hermano, vecina',
                    Icons.people_outline,
                    isDark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Prioridad',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in const [1, 2, 3])
                      ChoiceChip(
                        label: Text(
                          p == 1 ? '1 · Principal' : '$p',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        selected: _prioridad == p,
                        selectedColor: AppTheme.primaryColor.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (_) => setState(() => _prioridad = p),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(
                      alpha: isDark ? 0.15 : 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _declara,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (v) => setState(() => _declara = v == true),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _declara = !_declara),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              'Declaro que esta persona me autorizó a usar su '
                              'teléfono como contacto de emergencia y que le '
                              'avisé de que podemos contactarla.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                height: 1.35,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El teléfono es de otra persona: sin esta autorización no '
                  'podemos guardarla. Queda registrada tu declaración.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      editando ? 'Guardar cambios' : 'Guardar contacto',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoracion(
    String label,
    String hint,
    IconData icon,
    bool isDark, {
    String? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
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
    );
  }
}
