import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/seguridad_service.dart';
import '../../utils/app_error.dart';

/// Un tipo de incidente que el usuario puede elegir.
///
/// `codigo` es el valor exacto del CHECK `incidentes_tipo_check` de
/// `muevete.incidentes`: no se traduce ni se adorna al enviarlo.
class _TipoIncidente {
  final String codigo;
  final String etiqueta;
  final String subtitulo;
  final IconData icono;

  const _TipoIncidente(
    this.codigo,
    this.etiqueta,
    this.subtitulo,
    this.icono,
  );
}

/// Grupo de opciones por gravedad. La gravedad es **informativa**: la
/// calcula `fn_reportar_incidente` en el servidor a partir del tipo.
class _GrupoIncidentes {
  final String titulo;
  final String nota;
  final List<_TipoIncidente> tipos;

  const _GrupoIncidentes(this.titulo, this.nota, this.tipos);
}

/// Reporte de incidente (H2 · F5).
///
/// La **severidad no la elige el usuario**: `fn_reportar_incidente` la deduce
/// del tipo (robo con violencia, agresión, amenaza y acoso sexual son
/// críticos; suplantación, vehículo incorrecto, acoso verbal y extorsión son
/// altos; no-show y cobro abusivo son bajos). Aquí sólo se muestra el
/// resultado para que el usuario sepa qué esperar.
class ReporteIncidenteScreen extends StatefulWidget {
  final int solicitudId;

  const ReporteIncidenteScreen({super.key, required this.solicitudId});

  @override
  State<ReporteIncidenteScreen> createState() => _ReporteIncidenteScreenState();
}

class _ReporteIncidenteScreenState extends State<ReporteIncidenteScreen> {
  final SeguridadService _seguridad = SeguridadService();
  final _descripcionCtrl = TextEditingController();

  static const List<_GrupoIncidentes> _grupos = [
    _GrupoIncidentes(
      'Graves',
      'La plataforma los trata como críticos y los revisa primero.',
      [
        _TipoIncidente(
          'robo_con_violencia',
          'Robo con violencia',
          'Me quitaron algo a la fuerza',
          Icons.gpp_bad_outlined,
        ),
        _TipoIncidente(
          'agresion_fisica',
          'Agresión física',
          'Me golpearon o me empujaron',
          Icons.pan_tool_outlined,
        ),
        _TipoIncidente(
          'amenaza',
          'Amenaza',
          'Me dijo que me haría daño',
          Icons.warning_amber_rounded,
        ),
        _TipoIncidente(
          'acoso_sexual',
          'Acoso sexual',
          'Toques o comentarios sexuales',
          Icons.report_outlined,
        ),
      ],
    ),
    _GrupoIncidentes(
      'Serios',
      'Se investigan y pueden bloquear el emparejamiento.',
      [
        _TipoIncidente(
          'suplantacion',
          'Suplantación',
          'No era quien decía ser',
          Icons.badge_outlined,
        ),
        _TipoIncidente(
          'vehiculo_incorrecto',
          'Vehículo incorrecto',
          'La chapa o el carro no coinciden',
          Icons.directions_car_filled_outlined,
        ),
        _TipoIncidente(
          'acoso_verbal',
          'Acoso verbal',
          'Insultos, gritos o burlas',
          Icons.record_voice_over_outlined,
        ),
        _TipoIncidente(
          'extorsion',
          'Extorsión',
          'Me exigió dinero con presión',
          Icons.gavel_outlined,
        ),
      ],
    ),
    _GrupoIncidentes(
      'Menores',
      'Quedan registrados igual, para que no se repita.',
      [
        _TipoIncidente(
          'robo_sin_violencia',
          'Robo sin violencia',
          'Desapareció algo mío',
          Icons.shopping_bag_outlined,
        ),
        _TipoIncidente(
          'no_show_pasajero',
          'No apareció',
          'No llegó al punto de recogida',
          Icons.person_off_outlined,
        ),
        _TipoIncidente(
          'cobro_abusivo',
          'Cobro indebido',
          'Me cobró más de lo acordado',
          Icons.payments_outlined,
        ),
      ],
    ),
    _GrupoIncidentes(
      'Otra cosa',
      'Si no encaja en ninguna de las anteriores, cuéntalo igual.',
      [
        _TipoIncidente(
          'otro',
          'Otra cosa',
          'Descríbelo abajo con tus palabras',
          Icons.more_horiz,
        ),
      ],
    ),
  ];

  String _tipo = 'acoso_verbal';
  bool _noEmparejar = false;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _noEmparejar = _severidadDe(_tipo) != 'baja';
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  /// Copia local de la regla del servidor, sólo para mostrarla.
  String _severidadDe(String tipo) {
    const criticos = {
      'robo_con_violencia',
      'agresion_fisica',
      'amenaza',
      'acoso_sexual',
    };
    const altos = {
      'suplantacion',
      'vehiculo_incorrecto',
      'acoso_verbal',
      'extorsion',
    };
    const bajos = {'no_show_pasajero', 'cobro_abusivo'};
    if (criticos.contains(tipo)) return 'critica';
    if (altos.contains(tipo)) return 'alta';
    if (bajos.contains(tipo)) return 'baja';
    return 'media';
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.length < 20) {
      setState(() {
        _error = 'Cuéntanos qué pasó con al menos 20 caracteres';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final res = await _seguridad.reportarIncidente(
        solicitudId: widget.solicitudId,
        tipo: _tipo,
        descripcion: descripcion,
        noEmparejar: _noEmparejar,
      );
      if (!mounted) return;
      setState(() => _enviando = false);
      final id = (res['incidente_id'] as num?)?.toInt();
      await _mostrarConfirmacion(id);
      if (mounted) Navigator.of(context).pop(true);
    } on SeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = AppError.message(e, action: 'enviar el reporte');
      });
    }
  }

  Future<void> _mostrarConfirmacion(int? id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reporte recibido'),
        content: Text(
          'Recibimos tu reporte${id != null ? ' #$id' : ''}. Lo revisa el '
          'equipo de Muevete en horario laboral (lunes a viernes, '
          '9:00–17:00).\n\nSi estás en peligro ahora, llama al 106. Avísale '
          'también a tu contacto de emergencia.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _llamar106();
            },
            child: const Text('Llamar al 106'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _llamar106() async {
    var numero = '106';
    try {
      numero = await _seguridad.numeroPolicia();
    } catch (_) {}
    var abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse('tel:$numero'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }
    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Este teléfono no puede hacer llamadas. Busca un teléfono fijo.',
            style: GoogleFonts.plusJakartaSans(),
          ),
        ),
      );
    }
  }

  /// Una opción de la lista: etiqueta corta + subtítulo que aclara el caso.
  ///
  /// Se usa un tile con radio en vez de chips para que quepan los doce tipos
  /// con su subtítulo, agrupados por gravedad.
  Widget _opcionTipo(
    _TipoIncidente tipo,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final seleccionado = _tipo == tipo.codigo;
    return InkWell(
      onTap: () {
        setState(() {
          _tipo = tipo.codigo;
          _noEmparejar = _severidadDe(tipo.codigo) != 'baja';
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado
                ? AppTheme.primaryColor
                : AppTheme.border(isDark),
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              tipo.icono,
              size: 20,
              color: seleccionado ? AppTheme.primaryColor : textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipo.etiqueta,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tipo.subtitulo,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              seleccionado
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: seleccionado
                  ? AppTheme.primaryColor
                  : AppTheme.border(isDark),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);
    final severidad = _severidadDe(_tipo);
    final esGrave = severidad == 'alta' || severidad == 'critica';

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(isDark),
        elevation: 0,
        title: Text(
          'Reportar un problema',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '¿Qué pasó?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final grupo in _grupos) ...[
            Text(
              grupo.titulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              grupo.nota,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: textSecondary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            for (final tipo in grupo.tipos) ...[
              _opcionTipo(tipo, isDark, textPrimary, textSecondary),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: esGrave ? AppTheme.error : textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Severidad ${SeguridadService.etiquetaSeveridad(severidad)} '
                    '(la determina la plataforma según lo que reportas).',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Cuéntanos qué pasó',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descripcionCtrl,
            maxLines: 6,
            maxLength: 2000,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Escribe lo que ocurrió con el mayor detalle posible',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textTertiary(isDark),
              ),
              filled: true,
              fillColor: AppTheme.card(isDark),
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
                borderSide: const BorderSide(
                  color: AppTheme.primaryColor,
                  width: 2,
                ),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          Text(
            'Lo que escribas lo lee el equipo de Muevete, no la otra persona.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: textSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _noEmparejar,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryColor,
            title: Text(
              'No quiero que me vuelvan a asignar con esta persona',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: textPrimary,
              ),
            ),
            onChanged: (v) => setState(() => _noEmparejar = v == true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: AppTheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _enviando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primaryColor.withValues(
                  alpha: 0.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Enviar reporte',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _llamar106,
              icon: const Icon(Icons.local_phone, size: 20),
              label: Text(
                'Llamar al 106',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Muevete no sustituye a la policía. Si estás en peligro, llama al '
            '106.',
            textAlign: TextAlign.center,
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
}
