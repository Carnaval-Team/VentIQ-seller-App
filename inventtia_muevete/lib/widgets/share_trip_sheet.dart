import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/seguridad_service.dart';
import '../utils/app_error.dart';

/// Hoja "Compartir viaje" (H2 · F2).
///
/// Crea un enlace con token por `fn_crear_enlace_viaje`; quien lo tenga ve el
/// recorrido, la chapa y el nombre del conductor hasta que el viaje termina.
/// No ve teléfono ni carnet. Al terminar o cancelar, el servidor revoca el
/// token y la página deja de funcionar.
class CompartirViajeSheet {
  /// Abre la hoja. [solicitudId] es obligatorio; [posicion] y [chapa] se usan
  /// sólo para el mensaje de respaldo cuando no hay datos.
  static Future<void> mostrar(
    BuildContext context, {
    required int solicitudId,
    String? conductor,
    String? chapa,
    LatLng? posicion,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CompartirViajeContenido(
        solicitudId: solicitudId,
        conductor: conductor,
        chapa: chapa,
        posicion: posicion,
      ),
    );
  }
}

class _CompartirViajeContenido extends StatefulWidget {
  final int solicitudId;
  final String? conductor;
  final String? chapa;
  final LatLng? posicion;

  const _CompartirViajeContenido({
    required this.solicitudId,
    this.conductor,
    this.chapa,
    this.posicion,
  });

  @override
  State<_CompartirViajeContenido> createState() =>
      _CompartirViajeContenidoState();
}

class _CompartirViajeContenidoState extends State<_CompartirViajeContenido> {
  final SeguridadService _seguridad = SeguridadService();

  EnlaceViaje? _enlace;
  bool _creando = false;
  bool _revocando = false;
  String? _error;
  bool _sinRed = false;

  Future<void> _crear() async {
    if (_creando) return;
    setState(() {
      _creando = true;
      _error = null;
      _sinRed = false;
    });
    try {
      final enlace = await _seguridad.crearEnlace(widget.solicitudId);
      if (!mounted) return;
      setState(() {
        _enlace = enlace;
        _creando = false;
      });
    } on SeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _error = e.mensaje;
        _sinRed = !_esFalloDeRed(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _error = AppError.message(e, action: 'crear el enlace');
        _sinRed = true;
      });
    }
  }

  bool _esFalloDeRed(SeguridadException e) {
    final texto = e.mensaje.toLowerCase();
    return texto.contains('conexión') ||
        texto.contains('conexion') ||
        texto.contains('internet') ||
        texto.contains('red');
  }

  Future<void> _revocar() async {
    final enlace = _enlace;
    if (enlace?.id == null || _revocando) return;
    setState(() => _revocando = true);
    try {
      await _seguridad.revocarEnlace(enlace!.id!);
      if (!mounted) return;
      setState(() {
        _enlace = null;
        _revocando = false;
      });
      _aviso('Dejaste de compartir el viaje');
    } catch (e) {
      if (!mounted) return;
      setState(() => _revocando = false);
      _aviso(AppError.message(e, action: 'dejar de compartir'));
    }
  }

  String get _mensajeEnlace {
    final url = _enlace?.url ?? '';
    return 'Estoy en un viaje de Muevete. Mira el recorrido aquí: $url. '
        'Si no contesto en 15 minutos, llama al 106.';
  }

  /// Mensaje de respaldo: foto del momento, no seguimiento.
  String get _mensajeEstatico {
    final partes = <String>['Estoy en un viaje de Muevete.'];
    if ((widget.conductor ?? '').isNotEmpty) {
      partes.add('Conductor: ${widget.conductor}.');
    }
    if ((widget.chapa ?? '').isNotEmpty) {
      partes.add('Chapa: ${widget.chapa}.');
    }
    final pos = widget.posicion;
    if (pos != null) {
      partes.add(
        'Última ubicación: ${pos.latitude.toStringAsFixed(4)},'
        '${pos.longitude.toStringAsFixed(4)} '
        'https://maps.google.com/?q=${pos.latitude},${pos.longitude}',
      );
    }
    partes.add(
      'Si no contesto en 15 minutos, llama al 106. Esto es una foto del '
      'momento, no un seguimiento.',
    );
    return partes.join(' ');
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    _aviso('Enlace copiado');
  }

  Future<void> _abrirUrl(String url) async {
    var abierto = false;
    try {
      abierto = await launchUrl(Uri.parse(url));
    } catch (_) {
      abierto = false;
    }
    if (!abierto && mounted) {
      _aviso('No se pudo abrir la aplicación en este teléfono');
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje, style: GoogleFonts.plusJakartaSans())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);
    final enlace = _enlace;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
              Row(
                children: [
                  const Icon(
                    Icons.share_location_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Compartir este viaje',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Quien tenga el enlace puede ver el recorrido, la chapa y el '
                'nombre del chofer hasta que el viaje termine. No ve tu '
                'teléfono ni tu carnet. El enlace deja de funcionar al '
                'terminar el viaje.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (enlace == null) ...[
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _sinRed
                          ? 'Sin datos no podemos crear el enlace en vivo. Te '
                                'dejamos un mensaje con tus datos y tu última '
                                'ubicación para que lo envíes por SMS.'
                          : _error!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.35,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirUrl(
                            'sms:?body=${Uri.encodeComponent(_mensajeEstatico)}',
                          ),
                          icon: const Icon(Icons.sms_outlined, size: 18),
                          label: const Text('Enviar por SMS'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copiar(_mensajeEstatico),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copiar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _creando ? null : _crear,
                    icon: _creando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link, size: 20),
                    label: Text(
                      'Crear enlace para compartir',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: SelectableText(
                    enlace.url,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El enlace se apaga al terminar el viaje'
                  '${enlace.expiraAt != null ? ' · vence ${_fecha(enlace.expiraAt!)}' : ''}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _copiarEnlace,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar enlace'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _abrirUrl(
                          'https://wa.me/?text=${Uri.encodeComponent(_mensajeEnlace)}',
                        ),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.whatsappGreen,
                          side: const BorderSide(color: AppTheme.whatsappGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _abrirUrl(
                          'sms:?body=${Uri.encodeComponent(_mensajeEnlace)}',
                        ),
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: const Text('SMS'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(color: AppTheme.border(isDark)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton.icon(
                    onPressed: _revocando ? null : _revocar,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: Text(
                      _revocando ? 'Revocando…' : 'Dejar de compartir',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Muevete no sustituye a la policía. Si no contestas, que '
                'llamen al 106.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  height: 1.3,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copia el enlace actual.
  void _copiarEnlace() {
    final url = _enlace?.url;
    if (url != null && url.isNotEmpty) _copiar(url);
  }

  String _fecha(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
