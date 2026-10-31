import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/version_app.dart';
import '../services/update_service.dart';

/// Abre el diálogo de actualización.
///
/// Si la actualización es obligatoria no se puede cerrar ni con el botón de
/// atrás ni tocando fuera.
///
/// [alVerHistorial] es lo que hace el enlace «Ver historial de cambios». Se
/// recibe como callback (y no se navega aquí dentro) por dos razones: el widget
/// no depende de la pantalla de novedades, y **el diálogo se queda abierto
/// debajo** — importante cuando la actualización es obligatoria, porque cerrarlo
/// para ver el historial sería una forma de saltárselo. Si no se pasa callback,
/// el enlace se limita a cerrar el diálogo (es el caso de la propia pantalla de
/// novedades, donde el historial ya está a la vista).
Future<void> mostrarDialogoActualizacion(
  BuildContext context,
  AvisoActualizacion aviso, {
  VoidCallback? alVerHistorial,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !aviso.obligatoria,
    builder: (_) =>
        DialogoActualizacion(aviso: aviso, alVerHistorial: alVerHistorial),
  );
}

/// Diálogo «Nueva versión disponible» con el changelog de la versión nueva.
class DialogoActualizacion extends StatefulWidget {
  const DialogoActualizacion({
    super.key,
    required this.aviso,
    this.alVerHistorial,
  });

  final AvisoActualizacion aviso;

  /// Ver [mostrarDialogoActualizacion].
  final VoidCallback? alVerHistorial;

  @override
  State<DialogoActualizacion> createState() => _DialogoActualizacionState();
}

class _DialogoActualizacionState extends State<DialogoActualizacion> {
  bool _descargando = false;

  AvisoActualizacion get _aviso => widget.aviso;

  /// Abre el enlace de descarga; si el sistema no puede, ofrece copiarlo.
  Future<void> _descargar() async {
    if (_descargando) return;
    setState(() => _descargando = true);

    // El messenger se toma antes de cerrar el diálogo: sigue vivo después.
    final messenger = ScaffoldMessenger.of(context);
    final url = Uri.parse(UpdateService.urlDeDescarga(_aviso.disponible));

    bool abierto = false;
    try {
      abierto = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!abierto) {
      try {
        abierto = await launchUrl(url);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _descargando = false);

    if (abierto) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Descarga iniciada — instala la nueva versión'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      await _descargaManual(messenger, url);
    }
  }

  /// Respaldo cuando `url_launcher` no puede abrir el enlace.
  Future<void> _descargaManual(
    ScaffoldMessengerState messenger,
    Uri url,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga manual',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo abrir el enlace automáticamente.\n'
              'Cópialo y ábrelo en tu navegador:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: SelectableText(
                url.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar enlace'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url.toString()));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Enlace copiado al portapapeles'),
                  backgroundColor: AppTheme.primary,
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aviso = _aviso;
    final obligatoria = aviso.obligatoria;
    final nueva = aviso.disponible;
    final altoPantalla = MediaQuery.sizeOf(context).height;

    return PopScope(
      canPop: !obligatoria,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            // En pantallas pequeñas el cuerpo hace scroll, no se desborda.
            maxHeight: altoPantalla * 0.84,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _cabecera(nueva, obligatoria),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: _cuerpo(aviso, nueva),
                ),
              ),
              _acciones(obligatoria),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cabecera ───────────────────────────────────────────────────────────────

  Widget _cabecera(VersionApp? nueva, bool obligatoria) {
    final inicio = obligatoria ? const Color(0xFFE65100) : AppTheme.primaryDark;
    final fin = obligatoria ? AppTheme.warning : AppTheme.primaryLight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [inicio, fin],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  obligatoria
                      ? Icons.warning_amber_rounded
                      : Icons.system_update_alt_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      obligatoria
                          ? 'Actualización obligatoria'
                          : 'Nueva versión disponible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nueva?.etiquetaVersion ?? '—',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!obligatoria)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.92),
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (obligatoria)
                _Pastilla(
                  icono: Icons.lock_clock_rounded,
                  texto: 'Debes instalarla para seguir',
                ),
              if (nueva?.fechaLegible != null)
                _Pastilla(
                  icono: Icons.event_rounded,
                  texto: nueva!.fechaLegible!,
                ),
              if (_aviso.desdeRespaldo)
                _Pastilla(
                  icono: Icons.cloud_off_rounded,
                  texto: _aviso.esquemaPendiente
                      ? 'Datos de la app'
                      : 'Sin conexión',
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Cuerpo ─────────────────────────────────────────────────────────────────

  Widget _cuerpo(AvisoActualizacion aviso, VersionApp? nueva) {
    final cambios = nueva?.cambios ?? const <CambioVersion>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nueva?.tieneTitulo == true) ...[
          Text(
            nueva!.titulo!,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _filaDato(
          'Instalada',
          aviso.instalada.build > 0
              ? 'v${aviso.instalada.version} (build ${aviso.instalada.build})'
              : 'v${aviso.instalada.version}',
        ),
        if (nueva != null) _filaDato('Nueva', nueva.etiquetaVersion),
        if (aviso.desdeRespaldo) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aviso.mensajeRespaldo,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.primary),
            SizedBox(width: 6),
            Text(
              'Qué hay de nuevo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (cambios.isEmpty)
          const Text(
            'Esta versión trae mejoras de rendimiento y correcciones. '
            'Instálala para seguir al día.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          )
        else
          for (final cambio in cambios)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TarjetaCambioVersion(cambio: cambio),
            ),
      ],
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pie de acciones ────────────────────────────────────────────────────────

  Widget _acciones(bool obligatoria) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () {
              final callback = widget.alVerHistorial;
              if (callback == null) {
                Navigator.of(context).pop();
                return;
              }
              // El diálogo no se cierra: el historial se abre encima.
              callback();
            },
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text(
              'Ver historial de cambios',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!obligatoria) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Más tarde',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: obligatoria ? 1 : 2,
                child: ElevatedButton.icon(
                  onPressed: _descargando ? null : _descargar,
                  icon: _descargando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    _descargando ? 'Abriendo…' : 'Descargar ahora',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: obligatoria
                        ? AppTheme.warning
                        : AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Piezas reutilizables ─────────────────────────────────────────────────────

/// Un cambio del changelog: icono y color según su tipo, título y detalle.
class TarjetaCambioVersion extends StatelessWidget {
  const TarjetaCambioVersion({super.key, required this.cambio});

  final CambioVersion cambio;

  @override
  Widget build(BuildContext context) {
    final color = cambio.tipo.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 12, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(cambio.tipo.icono, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cambio.titulo,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CintaTipoCambio(tipo: cambio.tipo),
                  ],
                ),
                if (cambio.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    cambio.descripcion,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cinta «NOVEDAD» / «MEJORA» / «CORRECCIÓN» del tipo de cambio.
class CintaTipoCambio extends StatelessWidget {
  const CintaTipoCambio({super.key, required this.tipo});

  final TipoCambio tipo;

  @override
  Widget build(BuildContext context) {
    final color = tipo.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tipo.etiqueta.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Tarjeta de una versión del historial, con su changelog.
///
/// Marca la versión instalada (borde y cinta «TU VERSIÓN») y pliega los
/// changelogs largos para que la lista se pueda recorrer de un vistazo.
class TarjetaVersionHistorial extends StatefulWidget {
  const TarjetaVersionHistorial({
    super.key,
    required this.version,
    this.esInstalada = false,
    this.esUltima = false,
  });

  final VersionApp version;
  final bool esInstalada;
  final bool esUltima;

  @override
  State<TarjetaVersionHistorial> createState() =>
      _TarjetaVersionHistorialState();
}

class _TarjetaVersionHistorialState extends State<TarjetaVersionHistorial> {
  /// Cuántos cambios se ven antes de plegar el resto.
  static const int _visibles = 4;

  bool _expandida = false;

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    final cambios = version.cambios;
    final plegado = !_expandida && cambios.length > _visibles;
    final visibles = plegado ? cambios.sublist(0, _visibles) : cambios;
    final restantes = cambios.length - _visibles;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.esInstalada
              ? AppTheme.primary.withValues(alpha: 0.55)
              : AppTheme.border,
          width: widget.esInstalada ? 1.4 : 1,
        ),
        boxShadow: AppTheme.sombraTarjeta,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: widget.esInstalada
                  ? AppTheme.primary.withValues(alpha: 0.06)
                  : AppTheme.surface.withValues(alpha: 0.7),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'v${version.version}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (version.build > 0)
                            _Etiqueta(
                              texto: 'build ${version.build}',
                              color: AppTheme.textSecondary,
                            ),
                          if (widget.esInstalada)
                            const _Etiqueta(
                              texto: 'TU VERSIÓN',
                              color: AppTheme.primary,
                              icono: Icons.check_circle_rounded,
                            ),
                          if (widget.esUltima && !widget.esInstalada)
                            const _Etiqueta(
                              texto: 'ÚLTIMA',
                              color: AppTheme.success,
                            ),
                        ],
                      ),
                      if (version.tieneTitulo) ...[
                        const SizedBox(height: 6),
                        Text(
                          version.titulo!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (version.fechaLegible != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      version.fechaLegible!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (visibles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final cambio in visibles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaCambioVersion(cambio: cambio),
                    ),
                ],
              ),
            ),
          if (plegado || (_expandida && restantes > 0))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _expandida = !_expandida),
                icon: Icon(
                  _expandida
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _expandida
                      ? 'Ver menos'
                      : restantes == 1
                      ? 'Ver 1 cambio más'
                      : 'Ver los $restantes cambios más',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Etiqueta pequeña en forma de pastilla.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastilla translúcida de la cabecera del diálogo (sobre el degradado).
class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
