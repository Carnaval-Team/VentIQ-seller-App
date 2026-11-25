/// Pantalla de activación de una tienda en borrador.
///
/// Fase 3 del plan `docs/plans/alta-tienda-progresiva-go-live.md`: checklist
/// estilo Stripe con lo que le falta a la tienda para poder vender,
/// personalizado según el tipo de negocio que declaró.
///
/// El reparto de responsabilidades es a propósito:
///
/// - `models/onboarding_tareas.dart` decide **qué** tareas hay y en qué estado.
/// - `widgets/onboarding_checklist_vista.dart` pinta el estado que recibe. No
///   conoce Supabase ni `OnboardingService`, así que se puede montar en una
///   prueba de widget con una lista de tareas fabricada.
/// - `ActivacionTiendaScreen` (este archivo) es la única que habla con
///   `OnboardingService` y le pasa los datos a la vista.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_checklist_vista.dart';
import 'go_live_sheet.dart';

/// Pantalla de activación de la tienda en borrador.
class ActivacionTiendaScreen extends StatefulWidget {
  const ActivacionTiendaScreen({
    super.key,
    this.servicio,
    this.descartadoInicial,
    this.accionFinal,
  });

  /// Servicio inyectable (pruebas). Por defecto `OnboardingService`.
  final OnboardingService? servicio;

  /// Fuerza el estado «descartado». En producción se resuelve con
  /// `leerEstadoTienda().descartadoEn`; se deja como parámetro para poder
  /// montar la pantalla sin backend.
  final bool? descartadoInicial;

  /// Hueco para el botón de Go Live que añade la fase 4.
  final Widget? accionFinal;

  @override
  State<ActivacionTiendaScreen> createState() => _ActivacionTiendaScreenState();
}

class _ActivacionTiendaScreenState extends State<ActivacionTiendaScreen> {
  OnboardingService? _servicio;

  bool _cargando = true;
  String? _error;
  bool _descartado = false;
  String? _tipoNegocio;
  List<TareaOnboarding> _tareas = const [];

  /// Descarta respuestas viejas si se recarga mientras una petición vuela.
  int _cargaActual = 0;

  @override
  void initState() {
    super.initState();
    _descartado = widget.descartadoInicial ?? false;
    _cargar();
  }

  /// El servicio se crea de forma perezosa: construirlo toca
  /// `Supabase.instance`, y así el tipo se resuelve sin backend cuando la
  /// pantalla se inyecta ya cargada.
  OnboardingService get _onboarding =>
      _servicio ??= widget.servicio ?? OnboardingService();

  Future<void> _cargar() async {
    final carga = ++_cargaActual;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final estado = await _onboarding.leerEstadoTienda();
      // `listarTareas()` ya combina hechos + tipo de negocio + estados
      // guardados: la pantalla no vuelve a llamar a `construirTareas`.
      final tareas = await _onboarding.listarTareas();
      if (!mounted || carga != _cargaActual) return;
      setState(() {
        _tipoNegocio = estado.tipoNegocio;
        // `descartadoEn` nulo = el checklist sigue vivo. El parámetro de
        // pruebas tiene la última palabra para poder montar sin backend.
        _descartado = widget.descartadoInicial ?? (estado.descartadoEn != null);
        _tareas = tareas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted || carga != _cargaActual) return;
      setState(() {
        _error = _mensajeDe(e);
        _cargando = false;
      });
    }
  }

  Future<void> _elegirTipoNegocio(String tipo) async {
    // Optimista: el selector responde ya; si el guardado falla, se revierte y
    // se avisa. Elegir el tipo es un tap, no un formulario.
    final anterior = _tipoNegocio;
    setState(() => _tipoNegocio = tipo);
    try {
      await _onboarding.guardarTipoNegocio(tipo);
      if (!mounted) return;
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _tipoNegocio = anterior);
      _avisar('No se pudo guardar el tipo de negocio: ${_mensajeDe(e)}');
    }
  }

  Future<void> _abrirTarea(TareaOnboarding tarea) async {
    // Tareas que se resuelven en línea (datos de la tienda y quién cobra): la
    // pantalla completa no tiene formulario propio, así que se delega en el
    // panel, que sí lo tiene. Así la vista de detalle no queda coja respecto a
    // la burbuja del dashboard.
    if (tarea.enPanel) {
      final ruta = tarea.campoPanel == 'cobro'
          ? '/workers'
          : '/dashboard';
      await Navigator.of(context).pushNamed(
        ruta,
        arguments: tarea.campoPanel == 'cobro'
            ? const {'nuevoTrabajador': 'cobro'}
            : null,
      );
      if (mounted) await _cargar();
      return;
    }

    final ruta = tarea.ruta;
    if (ruta == null) return;
    try {
      await Navigator.of(context).pushNamed(ruta);
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo abrir esa pantalla: ${_mensajeDe(e)}');
      return;
    }
    // Al volver se releen los hechos: el contador sube sin recargar la app.
    if (mounted) await _cargar();
  }

  Future<void> _descartar() async {
    try {
      await _onboarding.descartarOnboarding();
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo descartar el checklist: ${_mensajeDe(e)}');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
  }

  Future<void> _recuperar() async {
    try {
      await _onboarding.restaurarOnboarding();
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo recuperar el checklist: ${_mensajeDe(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _descartado = false);
  }

  /// Abre el preflight de la fase 4. Si el servidor activa la tienda, se sale
  /// del checklist: ya no hay nada que completar para poder vender.
  Future<void> _abrirGoLive() async {
    final activada = await mostrarGoLive(
      context,
      tareas: _tareas,
      servicio: widget.servicio,
      resumenInicial: {'tipo_negocio': _tipoNegocio},
    );
    if (!mounted || !activada) return;
    _avisar('Tu tienda está en marcha.');
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
  }

  void _avisar(String texto) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(texto)));
  }

  String _mensajeDe(Object e) {
    final texto = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  @override
  Widget build(BuildContext context) {
    // El botón vive en la pantalla y no en la vista para que la vista siga
    // siendo pura (sin servicios) y testeable sin red.
    final accionFinal =
        widget.accionFinal ??
        (_cargando || _tareas.isEmpty
            ? null
            : SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _abrirGoLive,
                  icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                  label: const Text('Poner en marcha'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
        titleSpacing: 16,
        title: const Text(
          'Pon en marcha tu tienda',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Volver al panel',
            onPressed: () =>
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/dashboard',
                  (r) => false,
                ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: OnboardingChecklistVista(
        tareas: _tareas,
        tipoNegocio: _tipoNegocio,
        cargando: _cargando,
        error: _error,
        descartado: _descartado,
        accionFinal: accionFinal,
        onReintentar: _cargar,
        onElegirTipoNegocio: _elegirTipoNegocio,
        onAbrirTarea: _abrirTarea,
        onDescartar: _descartar,
        onRecuperar: _recuperar,
      ),
    );
  }
}
