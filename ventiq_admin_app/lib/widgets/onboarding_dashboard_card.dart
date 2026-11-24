/// Tarjeta compacta del dashboard para una tienda en borrador.
///
/// Fase 3 del plan `docs/plans/alta-tienda-progresiva-go-live.md`: mientras la
/// tienda no está activa, arriba del dashboard va **una tarjeta** (no un modal)
/// con el contador neutro y el acceso al checklist. El resto del dashboard no se
/// toca: hoy muestra ceros cuando no hay datos y eso es de otra fase.
///
/// La tarjeta se oculta sola si la tienda no está en borrador o si la consulta
/// falla: en el dashboard, ante la duda, no se pinta nada. Un fallo de red aquí
/// no debe tapar las métricas.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';
import '../services/onboarding_service.dart';
import 'onboarding_checklist_vista.dart' show textoProgreso;

/// Ruta del checklist de activación.
const String rutaActivacionTienda = '/activacion';

/// Tarjeta de acceso al checklist desde el dashboard.
class OnboardingDashboardCard extends StatefulWidget {
  const OnboardingDashboardCard({
    super.key,
    this.servicio,
    this.tareasIniciales,
    this.estadoInicial,
    this.onAbrir,
  });

  /// Servicio inyectable (pruebas).
  final OnboardingService? servicio;

  /// Tareas ya cargadas (pruebas o pantallas que ya las tienen).
  final List<TareaOnboarding>? tareasIniciales;

  /// Estado de onboarding ya resuelto (pruebas).
  final String? estadoInicial;

  /// Abre el checklist. Por defecto navega a [rutaActivacionTienda].
  final VoidCallback? onAbrir;

  /// Clave estable para las pruebas de widget.
  static const Key claveTarjeta = Key('onboarding_dashboard_card');

  @override
  State<OnboardingDashboardCard> createState() => _OnboardingDashboardCardState();
}

class _OnboardingDashboardCardState extends State<OnboardingDashboardCard> {
  OnboardingService? _servicio;

  List<TareaOnboarding>? _tareas;
  String? _estado;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    final tareasIniciales = widget.tareasIniciales;
    final estadoInicial = widget.estadoInicial;
    if (tareasIniciales != null && estadoInicial != null) {
      // Montaje sin backend (humo de widget).
      _tareas = tareasIniciales;
      _estado = estadoInicial;
      _cargando = false;
      return;
    }
    _cargar();
  }

  OnboardingService get _onboarding =>
      _servicio ??= widget.servicio ?? OnboardingService();

  Future<void> _cargar() async {
    try {
      final estado = await _onboarding.leerEstadoTienda();
      if (!mounted) return;
      // Tienda activa: no hay nada que recordar aquí.
      if (estado.estadoOnboarding != 'borrador') {
        setState(() {
          _estado = estado.estadoOnboarding;
          _tareas = null;
          _cargando = false;
        });
        return;
      }
      final tareas = await _onboarding.listarTareas();
      if (!mounted) return;
      setState(() {
        _estado = estado.estadoOnboarding;
        _tareas = tareas;
        _cargando = false;
      });
    } catch (_) {
      // Silencio deliberado: la tarjeta es un extra del dashboard.
      if (!mounted) return;
      setState(() {
        _estado = null;
        _tareas = null;
        _cargando = false;
      });
    }
  }

  Future<void> _abrir() async {
    final propio = widget.onAbrir;
    if (propio != null) {
      propio();
      return;
    }
    await Navigator.of(context).pushNamed(rutaActivacionTienda);
    // Al volver del checklist el contador puede haber cambiado.
    if (mounted) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    // Mientras carga no se pinta nada: una tarjeta en blanco con ceros es peor
    // que no tener tarjeta.
    if (_cargando) return const SizedBox.shrink();
    if (_estado != 'borrador') return const SizedBox.shrink();

    final tareas = _tareas ?? const <TareaOnboarding>[];
    final avance = progreso(tareas);

    return Container(
      key: OnboardingDashboardCard.claveTarjeta,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.rocket_launch_outlined,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pon tu tienda en marcha',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tu tienda todavía no puede vender. Termina los pasos '
                      'que faltan y ábrela.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  textoProgreso(tareas),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: avance.total == 0
                        ? 0.0
                        : avance.completadas / avance.total,
                    minHeight: 3,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.success,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _abrir,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Ver el checklist'),
            ),
          ),
        ],
      ),
    );
  }
}
