import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/seguridad_service.dart';

/// Botón de emergencia discreto (H2 · F1).
///
/// Se mantiene presionado ~1,5 s (o tres toques rápidos, para quien no puede
/// mantener el dedo). No suena, no vibra fuerte y **no cambia la pantalla**:
/// sólo aparece una franja corta con el resultado. En un robo, una pantalla
/// roja o un sonido pueden escalar la violencia.
///
/// Sin red, el evento queda en la cola local de [SeguridadService] y se envía
/// al recuperar conexión con el mismo `client_event_id` (idempotente).
class PanicButton extends StatefulWidget {
  /// Solicitud del viaje activo. Sin ella el botón queda deshabilitado.
  final int? solicitudId;

  /// Última posición conocida (opcional; si falta se manda 0,0 y el servidor
  /// guarda el evento igual).
  final LatLng? posicion;

  /// Se llama cuando la alerta quedó registrada (en servidor o en cola).
  final VoidCallback? onAlerta;

  const PanicButton({
    super.key,
    this.solicitudId,
    this.posicion,
    this.onAlerta,
  });

  @override
  State<PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<PanicButton>
    with SingleTickerProviderStateMixin {
  final SeguridadService _seguridad = SeguridadService();

  late final AnimationController _progreso;
  DateTime? _inicioPulsacion;
  final List<DateTime> _toques = [];
  bool _disparando = false;

  static const Duration _mantener = Duration(milliseconds: 1500);
  static const Duration _ventanaToques = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _progreso = AnimationController(vsync: this, duration: _mantener)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _progreso.addStatusListener((status) {
      if (status == AnimationStatus.completed) _disparar();
    });
  }

  @override
  void dispose() {
    _progreso.dispose();
    super.dispose();
  }

  // ── Gestos ──────────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (widget.solicitudId == null) return;
    _inicioPulsacion = DateTime.now();
    _progreso.forward(from: 0);
  }

  void _onPointerUp(PointerUpEvent event) {
    final inicio = _inicioPulsacion;
    _inicioPulsacion = null;
    _progreso.stop();
    _progreso.value = 0;
    if (inicio == null) return;

    final duracion = DateTime.now().difference(inicio);
    if (duracion.inMilliseconds < 350) _registrarToque();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _inicioPulsacion = null;
    _progreso.stop();
    _progreso.value = 0;
  }

  /// Tres toques rápidos son la alternativa accesible a mantener presionado.
  void _registrarToque() {
    final ahora = DateTime.now();
    _toques.removeWhere((t) => ahora.difference(t) > _ventanaToques);
    _toques.add(ahora);
    if (_toques.length >= 3) {
      _toques.clear();
      _disparar();
    }
  }

  // ── Disparo ─────────────────────────────────────────────────────────────

  Future<void> _disparar() async {
    final solicitudId = widget.solicitudId;
    if (solicitudId == null || _disparando) return;

    setState(() => _disparando = true);
    await HapticFeedback.mediumImpact();

    final posicion = widget.posicion;
    try {
      final resultado = await _seguridad.dispararPanico(
        solicitudId: solicitudId,
        lat: posicion?.latitude ?? 0,
        lon: posicion?.longitude ?? 0,
      );
      if (!mounted) return;

      widget.onAlerta?.call();

      if (resultado.enCola) {
        _franja(
          'No hay datos. Guardamos la alerta: se envía sola cuando vuelva la '
          'conexión. Ahora mismo: envía un mensaje o llama al 106. La app no '
          'puede llamar por ti.',
          esError: true,
        );
      } else {
        _franja('Alerta enviada a tus contactos · ${_hora()}');
      }
    } on SeguridadException catch (e) {
      if (!mounted) return;
      widget.onAlerta?.call();
      _franja('${e.mensaje}. Revisa tu contacto de emergencia en Mi seguridad');
    } catch (_) {
      if (!mounted) return;
      widget.onAlerta?.call();
      _franja(
        'No hay datos. Guardamos la alerta: se envía sola cuando vuelva la '
        'conexión.',
        esError: true,
      );
    } finally {
      if (mounted) setState(() => _disparando = false);
    }
  }

  String _hora() {
    final ahora = DateTime.now();
    return '${ahora.hour.toString().padLeft(2, '0')}:'
        '${ahora.minute.toString().padLeft(2, '0')}';
  }

  void _franja(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.plusJakartaSans(fontSize: 12.5, height: 1.3),
        ),
        backgroundColor: esError ? AppTheme.error : const Color(0xFF1F2430),
        duration: const Duration(seconds: 9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        action: SnackBarAction(
          label: 'Llamar al 106',
          textColor: Colors.white,
          onPressed: _llamar106,
        ),
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

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.solicitudId != null && !_disparando;
    final progreso = _progreso.value;

    return Semantics(
      button: true,
      label: 'Emergencia: mantén presionado para avisar a tus contactos',
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Opacity(
          opacity: habilitado ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15 + 0.7 * progreso),
                width: 1 + 2 * progreso,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _disparando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergencia',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Mantén presionado',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Acciones rápidas de emergencia sin disparar el pánico (para el hub).
Future<void> llamarAlPolicia(BuildContext context) async {
  final seguridad = SeguridadService();
  var numero = '106';
  try {
    numero = await seguridad.numeroPolicia();
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
  if (!abierto && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Este teléfono no puede hacer llamadas. Busca un teléfono fijo o '
          'pide ayuda a alguien cerca.',
          style: GoogleFonts.plusJakartaSans(),
        ),
      ),
    );
  }
}
