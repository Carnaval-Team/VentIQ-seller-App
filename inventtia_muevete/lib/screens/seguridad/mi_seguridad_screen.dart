import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transport_provider.dart';
import '../../services/identidad_service.dart';
import '../../services/seguridad_service.dart';
import '../../utils/app_error.dart';
import '../seguridad/reporte_incidente_screen.dart';

/// Hub "Mi seguridad" (H2).
///
/// Reúne el estado del gate, los contactos de emergencia, el marcado al 106,
/// el estado del perfil (KYC) y el historial de incidentes propios.
///
/// El copy es deliberadamente sobrio: la app no promete respuesta de nadie.
class MiSeguridadScreen extends StatefulWidget {
  const MiSeguridadScreen({super.key});

  @override
  State<MiSeguridadScreen> createState() => _MiSeguridadScreenState();
}

class _MiSeguridadScreenState extends State<MiSeguridadScreen> {
  final SeguridadService _seguridad = SeguridadService();
  final IdentidadService _identidad = IdentidadService();

  EstadoIdentidad? _estado;
  EstadoGateSeguridad? _gate;
  List<ContactoEmergencia> _contactos = const [];
  List<IncidentePropio> _incidentes = const [];
  String _numeroPolicia = '106';

  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final numero = await _seguridad.numeroPolicia();
      final estado = await _identidad.estado();
      final contactos = await _seguridad.contactos();
      final incidentes = await _seguridad.incidentesPropios();

      EstadoGateSeguridad? gate;
      final uid = _uid;
      if (uid != null) {
        try {
          gate = await _identidad.gateSeguridad(userUuid: uid);
        } on IdentidadException catch (e) {
          if (e.clave != 'funcion_no_disponible') rethrow;
        }
      }

      if (!mounted) return;
      setState(() {
        _numeroPolicia = numero;
        _estado = estado;
        _contactos = contactos;
        _incidentes = incidentes;
        _gate = gate;
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
        _error = AppError.message(e, action: 'cargar tu seguridad');
      });
    }
  }

  String? get _uid {
    try {
      return IdentidadService.uidActual;
    } catch (_) {
      return null;
    }
  }

  // ── Llamar al 106 ───────────────────────────────────────────────────────

  Future<void> _llamar106() async {
    final numero = _numeroPolicia;
    final uri = Uri.parse('tel:$numero');
    var abierto = false;
    try {
      abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abierto = false;
    }
    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Este teléfono no puede hacer llamadas. Busca un teléfono fijo o '
            'pide ayuda a alguien cerca.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _abrirContactos() async {
    await Navigator.pushNamed(context, '/seguridad/contactos');
    if (mounted) await _cargar();
  }

  Future<void> _abrirReporte() async {
    final tp = context.read<TransportProvider>();
    final solicitudId = tp.activeRequest?.id;
    if (solicitudId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Puedes reportar desde el viaje o hasta 7 días después de que '
            'termine.',
            style: GoogleFonts.plusJakartaSans(),
          ),
        ),
      );
      return;
    }
    final enviado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReporteIncidenteScreen(solicitudId: solicitudId),
      ),
    );
    if (enviado == true && mounted) await _cargar();
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
          'Mi seguridad',
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (_error != null) ...[
                    _avisoError(isDark),
                    const SizedBox(height: 12),
                  ],
                  _boton106(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 16),
                  _cardEstado(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 12),
                  _cardContactos(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 12),
                  _cardPerfil(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 12),
                  _cardReportes(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 16),
                  _letraPequena(isDark, textSecondary),
                ],
              ),
            ),
    );
  }

  Widget _boton106(bool isDark, Color textPrimary, Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _llamar106,
            icon: const Icon(Icons.local_phone, size: 26),
            label: Text(
              'Llamar al $_numeroPolicia',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Se abrirá el marcador de tu teléfono. Pulsa el botón verde para '
          'llamar. Muevete no puede marcar por ti.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            color: textSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
          ),
          child: Text(
            'Muevete no sustituye a la policía. Si estás en peligro, llama al '
            '$_numeroPolicia. Nadie del equipo de Muevete va a llamarte ni a '
            'ir a buscarte.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardEstado(bool isDark, Color textPrimary, Color textSecondary) {
    final estado = _estado;
    List<String> pendientes = const [];

    if (estado != null) {
      if (!estado.perfil.ok) {
        pendientes = estado.perfil.faltantes
            .map(IdentidadService.etiquetaMotivo)
            .toList();
      } else if (!estado.consentimiento.ok) {
        pendientes = const ['Documentos legales por aceptar'];
      } else if (_gate != null && !_gate!.ok) {
        pendientes = _gate!.motivos
            .map(IdentidadService.etiquetaMotivo)
            .toList();
      }
    }

    final habilitado =
        pendientes.isEmpty &&
        estado != null &&
        (estado.operarPermitido || estado.perfil.ok);

    return _contenedor(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                habilitado ? Icons.check_circle : Icons.error_outline,
                color: habilitado ? AppTheme.success : AppTheme.warning,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habilitado
                      ? 'Puedes pedir y tomar viajes'
                      : 'Aún no puedes pedir ni tomar viajes',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (!habilitado && pendientes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Falta: ${pendientes.join(', ')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (estado != null && !estado.perfil.ok)
                  OutlinedButton(
                    onPressed: () async {
                      await Navigator.pushNamed(
                        context,
                        '/identidad/onboarding',
                      );
                      if (mounted) await _cargar();
                    },
                    child: const Text('Completar perfil'),
                  ),
                if (estado != null && !estado.consentimiento.ok)
                  OutlinedButton(
                    onPressed: () async {
                      await Navigator.pushNamed(
                        context,
                        '/identidad/consentimiento',
                      );
                      if (mounted) await _cargar();
                    },
                    child: const Text('Aceptar documentos'),
                  ),
                if (estado != null &&
                    estado.perfil.ok &&
                    estado.consentimiento.ok)
                  OutlinedButton(
                    onPressed: _abrirContactos,
                    child: const Text('Agregar contacto'),
                  ),
              ],
            ),
          ],
          if (_gate != null && !_gate!.contactoVerificado) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sin verificación automática disponible: tus contactos '
                    'quedan como no verificados.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardContactos(bool isDark, Color textPrimary, Color textSecondary) {
    final principal = _contactos.where((c) => c.prioridad == 1).toList();
    final String detalle;
    if (_contactos.isEmpty) {
      detalle =
          'Sin contactos. Avisamos a quien tú elijas si activas la alerta.';
    } else {
      final partes = <String>['${_contactos.length} contacto(s)'];
      if (principal.isNotEmpty) {
        partes.add('principal: ${principal.first.nombre}');
      }
      detalle = partes.join(' · ');
    }

    return _contenedor(
      isDark,
      onTap: _abrirContactos,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.contact_emergency_outlined,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contactos de emergencia',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _cardPerfil(bool isDark, Color textPrimary, Color textSecondary) {
    final estado = _estado;
    final kyc = estado?.perfil.kycEstado ?? 'pendiente';
    final String etiqueta;
    final Color color;
    switch (kyc) {
      case 'aprobado':
        etiqueta = 'Identidad verificada';
        color = AppTheme.success;
        break;
      case 'rechazado':
        etiqueta = 'Identidad rechazada: revisa tus documentos';
        color = AppTheme.error;
        break;
      case 'en_revision':
        etiqueta = 'Identidad en revisión';
        color = AppTheme.warning;
        break;
      default:
        etiqueta = 'Identidad sin verificar';
        color = AppTheme.warning;
    }

    return _contenedor(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado de tu perfil',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  etiqueta,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'La revisión de documentos la hace el equipo. La app no verifica '
            'identidad en tiempo real: alguien podría usar la cuenta de otra '
            'persona.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardReportes(bool isDark, Color textPrimary, Color textSecondary) {
    return _contenedor(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mis reportes',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _abrirReporte,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Reportar'),
              ),
            ],
          ),
          if (_incidentes.isEmpty)
            Text(
              'No has reportado incidentes.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: textSecondary,
              ),
            )
          else
            for (final incidente in _incidentes.take(5)) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.report_outlined,
                    size: 16,
                    color: AppTheme.textTertiary(isDark),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          SeguridadService.etiquetaTipo(incidente.tipo),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          '${SeguridadService.etiquetaEstadoIncidente(incidente.estado)}'
                          ' · severidad '
                          '${SeguridadService.etiquetaSeveridad(incidente.severidad)}'
                          '${incidente.createdAt != null ? ' · ${_fecha(incidente.createdAt!)}' : ''}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: textSecondary,
                          ),
                        ),
                        if ((incidente.resolucion ?? '').isNotEmpty)
                          Text(
                            incidente.resolucion!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          const SizedBox(height: 8),
          Text(
            'Los reportes los revisa el equipo en horario laboral. La otra '
            'persona no ve quién reportó ni el texto del reporte.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _fecha(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Widget _letraPequena(bool isDark, Color textSecondary) {
    return Text(
      'Estas funciones son una ayuda: registran lo que pasa y avisan a quien '
      'tú elijas. No impiden un delito ni hacen que alguien llegue. Si el '
      'teléfono se apaga o se queda sin señal, sólo queda la llamada al 106.',
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        color: textSecondary,
        height: 1.35,
      ),
    );
  }

  Widget _contenedor(
    bool isDark, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    final contenido = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: child,
    );
    if (onTap == null) return contenido;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: contenido,
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
}
