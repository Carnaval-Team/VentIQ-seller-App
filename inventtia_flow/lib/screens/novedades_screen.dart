import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/version_app.dart';
import '../services/update_service.dart';
import '../widgets/aviso_actualizacion.dart';

/// Historial de cambios de GoReserva.
///
/// Muestra el changelog completo (el del servidor, o el del asset si no hay
/// conexión / la migración todavía no está pegada), con la versión instalada
/// marcada, y desde aquí se puede buscar una actualización a mano.
class NovedadesScreen extends StatefulWidget {
  const NovedadesScreen({super.key});

  @override
  State<NovedadesScreen> createState() => _NovedadesScreenState();
}

class _NovedadesScreenState extends State<NovedadesScreen> {
  bool _cargando = true;
  bool _buscando = false;
  HistorialVersiones? _historial;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!_cargando) setState(() => _cargando = true);
    final historial = await UpdateService.historial();
    if (!mounted) return;
    setState(() {
      _historial = historial;
      _cargando = false;
    });
  }

  /// Comprueba si hay algo nuevo y abre el diálogo si lo hay.
  Future<void> _buscarActualizaciones() async {
    if (_buscando) return;
    setState(() => _buscando = true);
    final aviso = await UpdateService.avisoActual();
    if (!mounted) return;
    setState(() => _buscando = false);

    if (aviso.hayActualizacion) {
      // Sin callback: ya estamos en el historial, así que el enlace del diálogo
      // se limita a cerrarlo y al volver refrescamos la lista.
      await mostrarDialogoActualizacion(context, aviso);
      if (!mounted) return;
      await _cargar();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final sinRed = aviso.error != null;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sinRed
              ? 'No se pudo comprobar: revisa tu conexión.'
              : 'Tienes la última versión (v${aviso.instalada.version}).',
        ),
        backgroundColor: sinRed ? AppTheme.warning : AppTheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historial = _historial;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Novedades')),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: historial == null
            ? _cargandoVista
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _tarjetaInstalada(historial.instalada),
                  const SizedBox(height: 16),
                  if (historial.desdeRespaldo) ...[
                    _avisoRespaldo(historial),
                    const SizedBox(height: 16),
                  ],
                  _tituloSeccion(historial.versiones.length),
                  const SizedBox(height: 10),
                  if (historial.vacio)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'Todavía no hay novedades publicadas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < historial.versiones.length; i++)
                      TarjetaVersionHistorial(
                        version: historial.versiones[i],
                        esInstalada: historial.versiones[i].esLaInstalada(
                          historial.instalada,
                        ),
                        esUltima: i == 0,
                      ),
                ],
              ),
      ),
    );
  }

  /// Placeholder mientras se pide el historial (dentro de un scroll para que el
  /// gesto de refrescar siga funcionando).
  Widget get _cargandoVista {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 90),
      children: const [
        Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppTheme.primary,
            ),
          ),
        ),
        SizedBox(height: 14),
        Text(
          'Buscando novedades…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _tarjetaInstalada(VersionApp instalada) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.sombraTarjeta,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu versión instalada',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      instalada.etiquetaVersion,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _buscarActualizaciones,
              icon: _buscando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryDark,
                      ),
                    )
                  : const Icon(Icons.system_update_alt_rounded, size: 18),
              label: Text(
                _buscando ? 'Buscando…' : 'Buscar actualizaciones',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoRespaldo(HistorialVersiones historial) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            historial.esquemaPendiente
                ? Icons.hourglass_empty_rounded
                : Icons.cloud_off_rounded,
            size: 17,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              historial.mensajeRespaldo,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(int total) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Text(
            'Historial de cambios',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (_cargando)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          )
        else
          Text(
            total == 1 ? '1 versión' : '$total versiones',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
      ],
    );
  }
}
