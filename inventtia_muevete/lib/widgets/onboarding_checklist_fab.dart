import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/identidad_service.dart';

/// Claves de `perfil.faltantes` que se completan en la pantalla de identidad.
const Set<String> _clavesIdentidad = <String>{
  'perfil_cliente',
  'perfil_chofer',
  'ci',
  'tipo_documento',
  'doc_frente',
  'doc_dorso',
};

/// Claves de `perfil.faltantes` que se completan en el bloque de residencia.
const Set<String> _clavesResidencia = <String>{
  'provincia',
  'municipio',
  'poblado',
  'direccion',
};

// Rutas ya registradas en `main.dart`. No se cambia la navegación existente:
// este FAB sólo es un acceso adicional a las mismas pantallas del gate.
const String _rutaOnboarding = '/identidad/onboarding';
const String _rutaConsentimiento = '/identidad/consentimiento';
const String _rutaContactos = '/seguridad/contactos';
const String _rutaSeguridad = '/seguridad';
const String _rutaPerfil = '/profile';

/// Un requisito del onboarding ya resuelto contra el servidor.
class _RequisitoOnboarding {
  const _RequisitoOnboarding({
    required this.titulo,
    required this.detalle,
    required this.icono,
    required this.listo,
    this.ruta,
    this.argumentos,
  });

  final String titulo;

  /// Sólo se pinta cuando el requisito está pendiente.
  final String detalle;
  final IconData icono;
  final bool listo;

  /// Pantalla donde se completa. `null` = pendiente sin acción del usuario
  /// (en revisión por el equipo, cuenta bloqueada...).
  final String? ruta;
  final Map<String, dynamic>? argumentos;

  bool get navegable => ruta != null;
}

/// FAB persistente con el checklist de requisitos para operar.
///
/// La fuente de verdad es el servidor: `fn_usuario_habilitado` (perfil,
/// consentimiento, KYC) y `fn_gate_seguridad` (contacto de emergencia y
/// bloqueos). Si alguna RPC falla (sin red, `PGRST202`) el FAB **no se pinta**:
/// nunca se inventa un bloqueo ni un estado.
class OnboardingChecklistFab extends StatefulWidget {
  const OnboardingChecklistFab({
    super.key,
    required this.rol,
    this.driverId,
    this.separacionInferior = 0,
  });

  /// `'cliente'` o `'chofer'`.
  final String rol;

  /// `muevete.drivers.id` cuando ya se conoce (home del chofer).
  final int? driverId;

  /// Espacio que el FAB deja debajo de sí cuando está visible. Sirve para
  /// apilarlo encima de otros FAB (home del chofer) sin dejar un hueco cuando
  /// desaparece.
  final double separacionInferior;

  @override
  State<OnboardingChecklistFab> createState() => OnboardingChecklistFabState();
}

class OnboardingChecklistFabState extends State<OnboardingChecklistFab>
    with WidgetsBindingObserver {
  final IdentidadService _identidad = IdentidadService();

  List<_RequisitoOnboarding> _requisitos = const [];
  bool _fallo = false;

  /// Descarta respuestas viejas cuando se solapan dos consultas.
  int _generacion = 0;

  bool get _esChofer => widget.rol.trim().toLowerCase() == 'chofer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fuera del primer frame: el FAB puede montarse dentro de un build ajeno.
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void didUpdateWidget(covariant OnboardingChecklistFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rol != widget.rol || oldWidget.driverId != widget.driverId) {
      refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  // ── Carga ───────────────────────────────────────────────────────────────

  /// Vuelve a consultar el gate en el servidor.
  ///
  /// Es público para que las pantallas que alojan el FAB lo refresquen al
  /// volver de una navegación.
  Future<void> refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final generacion = ++_generacion;
    if (uid == null) {
      _aplicar(const [], fallo: false);
      return;
    }

    try {
      final estado = await _identidad.estado(rol: widget.rol);
      final gate = await _identidad.gateSeguridad(
        userUuid: uid,
        driverId: widget.driverId,
      );
      final fila = _esChofer ? await _filaConductor(uid) : null;
      final conteo = await _conteoDocumentos(estado);
      if (!mounted || generacion != _generacion) return;

      _aplicar(
        _construir(estado: estado, gate: gate, fila: fila, conteo: conteo),
        fallo: false,
      );
    } on IdentidadException {
      if (!mounted || generacion != _generacion) return;
      // RPC ausente o sin permiso: no se pinta el FAB.
      _aplicar(const [], fallo: true);
    } catch (_) {
      if (!mounted || generacion != _generacion) return;
      // Sin red: tampoco se inventa el estado.
      _aplicar(const [], fallo: true);
    }
  }

  void _aplicar(List<_RequisitoOnboarding> requisitos, {required bool fallo}) {
    if (!mounted) return;
    setState(() {
      _requisitos = requisitos;
      _fallo = fallo;
    });
  }

  /// Fila del chofer en `muevete.drivers`: `kyc` (aprobación), `kyc_estado` y
  /// el vehículo asignado. Es la misma tabla que ya lee `driver_service`.
  Future<Map<String, dynamic>?> _filaConductor(String uid) async {
    try {
      final consulta = Supabase.instance.client
          .schema('muevete')
          .from('drivers')
          .select('id, kyc, kyc_estado, vehiculo');
      final row = await (widget.driverId != null
              ? consulta.eq('id', widget.driverId!)
              : consulta.eq('uuid', uid))
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      // Sin lectura fiable de la fila no se inventan requisitos del chofer.
      return null;
    }
  }

  /// "1 de 3 aceptados": el total sale de los documentos obligatorios
  /// publicados y los pendientes de `consentimiento.faltantes`.
  Future<({int aceptados, int total})?> _conteoDocumentos(
    EstadoIdentidad estado,
  ) async {
    if (estado.consentimiento.ok) return null;
    try {
      final documentos = await _identidad.documentosLegales();
      final total = documentos.length;
      if (total == 0) return null;
      final pendientes = estado.consentimiento.faltantes.length;
      final aceptados = (total - pendientes).clamp(0, total);
      return (aceptados: aceptados, total: total);
    } catch (_) {
      return null;
    }
  }

  // ── Construcción de la lista ─────────────────────────────────────────────

  List<_RequisitoOnboarding> _construir({
    required EstadoIdentidad estado,
    required EstadoGateSeguridad gate,
    required Map<String, dynamic>? fila,
    required ({int aceptados, int total})? conteo,
  }) {
    final faltantes = estado.perfil.faltantes;
    final requisitos = <_RequisitoOnboarding>[];

    final faltanIdentidad = faltantes.where(_clavesIdentidad.contains).toList();
    requisitos.add(
      _RequisitoOnboarding(
        titulo: 'Identidad (CI y fotos)',
        detalle: faltanIdentidad.isEmpty
            ? ''
            : 'Falta: ${_resumen(faltanIdentidad)}',
        icono: Icons.badge_outlined,
        listo: faltanIdentidad.isEmpty,
        ruta: _rutaOnboarding,
        argumentos: {
          'rol': widget.rol,
          'motivo': 'Completa tu identidad para poder operar',
        },
      ),
    );

    final faltanResidencia = faltantes
        .where(_clavesResidencia.contains)
        .toList();
    requisitos.add(
      _RequisitoOnboarding(
        titulo: 'Datos de residencia',
        detalle: faltanResidencia.isEmpty
            ? ''
            : 'Falta: ${_resumen(faltanResidencia)}',
        icono: Icons.home_work_outlined,
        listo: faltanResidencia.isEmpty,
        ruta: _rutaOnboarding,
        argumentos: {
          'rol': widget.rol,
          'motivo': 'Completa tus datos de residencia para poder operar',
        },
      ),
    );

    final consentimiento = estado.consentimiento;
    requisitos.add(
      _RequisitoOnboarding(
        titulo: 'Documentos legales',
        detalle: consentimiento.ok
            ? ''
            : conteo == null
            ? 'Tienes documentos por aceptar'
            : '${conteo.aceptados} de ${conteo.total} aceptados',
        icono: Icons.description_outlined,
        listo: consentimiento.ok,
        ruta: _rutaConsentimiento,
        argumentos: {
          'motivo': 'Acepta la privacidad y los términos para continuar',
        },
      ),
    );

    final sinContacto = gate.motivos.contains('sin_contacto_emergencia');
    requisitos.add(
      _RequisitoOnboarding(
        titulo: 'Contacto de emergencia',
        detalle: sinContacto ? 'Designa a quién avisamos si algo pasa' : '',
        icono: Icons.emergency_share_outlined,
        listo: !sinContacto,
        ruta: _rutaContactos,
        argumentos: {
          'motivo': 'Necesitas un contacto de emergencia para viajar',
        },
      ),
    );

    // ── KYC ───────────────────────────────────────────────────────────────
    final kycEstado = (estado.perfil.kycEstado ?? fila?['kyc_estado'] ?? '')
        .toString()
        .toLowerCase();
    final kycAprobado = kycEstado == 'aprobado' || fila?['kyc'] == true;
    final kycRechazado = kycEstado == 'rechazado';
    final kycEnRevision = kycEstado == 'en_revision';

    if (_esChofer) {
      requisitos.add(
        _RequisitoOnboarding(
          titulo: 'Verificación de conductor',
          detalle: kycAprobado
              ? ''
              : kycRechazado
              ? 'Rechazada: revisa tus documentos'
              : kycEnRevision
              ? 'En revisión por el equipo'
              : 'Pendiente de revisión del equipo',
          icono: Icons.verified_user_outlined,
          listo: kycAprobado,
          // Sólo el rechazo tiene algo que el chofer pueda hacer.
          ruta: kycRechazado ? _rutaSeguridad : null,
        ),
      );
    } else if (kycEnRevision || kycRechazado) {
      requisitos.add(
        _RequisitoOnboarding(
          titulo: 'Verificación de identidad',
          detalle: kycRechazado
              ? 'Rechazada: revisa tus documentos'
              : 'En revisión',
          icono: Icons.verified_user_outlined,
          listo: false,
          ruta: kycRechazado ? _rutaSeguridad : null,
        ),
      );
    }

    // ── Vehículo (sólo chofer, y sólo si la fila se pudo leer) ────────────
    if (_esChofer && fila != null) {
      final tieneVehiculo = fila['vehiculo'] != null;
      requisitos.add(
        _RequisitoOnboarding(
          titulo: 'Vehículo registrado',
          detalle: tieneVehiculo ? '' : 'Registra tu vehículo en tu perfil',
          icono: Icons.directions_car_outlined,
          listo: tieneVehiculo,
          ruta: _rutaPerfil,
        ),
      );
    }

    // ── Bloqueo de cuenta: lo dice el servidor, no hay pantalla que lo
    //    resuelva desde la app.
    if (gate.motivos.contains('bloqueado')) {
      requisitos.add(
        _RequisitoOnboarding(
          titulo: 'Cuenta habilitada',
          detalle:
              gate.motivoBloqueoPublico ??
              'Tu cuenta tiene reportes de seguridad confirmados',
          icono: Icons.block_outlined,
          listo: false,
        ),
      );
    }

    return requisitos;
  }

  static String _resumen(List<String> claves) {
    final etiquetas = claves.map(IdentidadService.etiquetaMotivo).toList();
    if (etiquetas.length <= 2) return etiquetas.join(', ');
    return '${etiquetas.take(2).join(', ')}…';
  }

  // ── Hoja ────────────────────────────────────────────────────────────────

  Future<void> _abrirHoja() async {
    if (_requisitos.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaRequisitos(origen: this),
    );
    if (!mounted) return;
    // Al cerrar la hoja se vuelve a preguntar al servidor.
    await refresh();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final total = _requisitos.length;
    final pendientes = _requisitos.where((r) => !r.listo).length;

    // Nada pendiente (o sin datos fiables): el FAB no se pinta.
    if (_fallo || total == 0 || pendientes == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: widget.separacionInferior),
      child: FloatingActionButton.extended(
        heroTag: 'onboarding_checklist_fab',
        onPressed: _abrirHoja,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        extendedPadding: const EdgeInsetsDirectional.only(start: 14, end: 14),
        extendedIconLabelSpacing: 8,
        extendedTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.checklist_rounded, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Completa tu perfil'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              // Se muestra lo que FALTA (no los cumplidos): el FAB existe
              // justamente para recordar lo pendiente.
              child: Text(
                'Faltan $pendientes',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja arrastrable con la lista de requisitos.
class _HojaRequisitos extends StatefulWidget {
  const _HojaRequisitos({required this.origen});

  final OnboardingChecklistFabState origen;

  @override
  State<_HojaRequisitos> createState() => _HojaRequisitosState();
}

class _HojaRequisitosState extends State<_HojaRequisitos> {
  late List<_RequisitoOnboarding> _visibles;
  bool _recargando = false;

  @override
  void initState() {
    super.initState();
    _visibles = widget.origen._requisitos;
  }

  Future<void> _irA(_RequisitoOnboarding requisito) async {
    final ruta = requisito.ruta;
    if (ruta == null || _recargando) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Bloquea la fila mientras se navega: evita abrir dos veces la pantalla.
    setState(() => _recargando = true);

    await navigator.pushNamed(ruta, arguments: requisito.argumentos);
    if (!mounted) return;

    await widget.origen.refresh();
    if (!mounted) return;

    final actualizados = widget.origen._requisitos;
    setState(() {
      _recargando = false;
      if (actualizados.isNotEmpty) _visibles = actualizados;
    });

    // Si ya no falta nada, la hoja se cierra sola.
    if (actualizados.isNotEmpty && actualizados.every((r) => r.listo)) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Ya cumpliste todos los requisitos',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    final total = _visibles.length;
    final pendientes = _visibles.where((r) => !r.listo).length;
    final listos = total - pendientes;
    final progreso = total == 0 ? 0.0 : listos / total;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                const SizedBox(height: 18),
                Text(
                  'Requisitos para operar',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pendientes == 0
                      ? 'Ya cumpliste todos los requisitos'
                      : 'Te faltan $pendientes de $total',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progreso.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppTheme.border(isDark),
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card(isDark),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _visibles.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: AppTheme.border(isDark),
                            ),
                          _fila(_visibles[i], isDark),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_recargando) ...[
                  const SizedBox(height: 14),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fila(_RequisitoOnboarding requisito, bool isDark) {
    final textPrimary = AppTheme.textPrimary(isDark);
    final textTertiary = AppTheme.textTertiary(isDark);
    final detalle = requisito.listo ? 'Listo' : requisito.detalle;

    final contenido = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            requisito.listo ? Icons.check_circle : requisito.icono,
            size: 22,
            color: requisito.listo ? AppTheme.success : textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requisito.titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: requisito.listo ? textTertiary : textPrimary,
                    decoration: requisito.listo
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: textTertiary,
                  ),
                ),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.textSecondary(isDark),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!requisito.listo && requisito.navegable)
            TextButton(
              onPressed: _recargando ? null : () => _irA(requisito),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Completar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
        ],
      ),
    );

    if (!requisito.listo && requisito.navegable) {
      return InkWell(
        onTap: _recargando ? null : () => _irA(requisito),
        child: contenido,
      );
    }
    return contenido;
  }
}