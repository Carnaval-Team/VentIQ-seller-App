/// Panel flotante de activación, abajo a la derecha (estilo Stripe).
///
/// Sustituye a la pantalla completa de la fase 3. El problema de la pantalla era
/// concreto: al entrar con una tienda en borrador el cliente aterrizaba en un
/// checklist a pantalla completa, sin dashboard y sin forma de cerrarlo sin
/// volver a iniciar sesión. Eso convertía una ayuda en un muro.
///
/// El patrón correcto (Stripe, Shopify) es el contrario:
///
///  * un **botón flotante** discreto en la esquina, que no tapa el trabajo;
///  * al tocarlo, un **panel** encima del contenido, no en lugar del contenido;
///  * se puede cerrar y el aviso **sigue ahí** — cerrar no borra nada, solo
///    aparta el panel un momento;
///  * el aviso no se repite como modal al entrar: aparece el botón, no un
///    diálogo.
///
/// El panel no es una ruta: se monta sobre el `Scaffold` que lo necesite, así
/// que sobrevive a la navegación interna del dashboard y nunca deja al usuario
/// en una pantalla sin salida.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';
import '../services/onboarding_service.dart';
import 'onboarding_checklist_vista.dart' show textoProgreso;

/// Ancho del panel. En pantallas estrechas ocupa el ancho menos márgenes.
const double _anchoPanel = 400;

/// Alto máximo: el 70 % de la ventana, para que siempre se vea el dashboard.
const double _altoMaximoFactor = 0.7;

/// Alto aproximado de la píldora. Se usa para colocar el panel justo encima,
/// sin tener que medirla en cada frame.
const double _altoBoton = 46;

/// Separación desde el borde inferior. La píldora y el FAB de accesos rápidos
/// comparten línea de base; lo que cambia es el desplazamiento horizontal.
const double _margenInferior = 16;

/// Botón flotante + panel de activación.
///
/// Se coloca en el `Stack` del `Scaffold` del dashboard, **después** del
/// contenido, para quedar por encima.
///
/// Si la tienda no está en borrador no pinta nada: ni botón ni panel. La
/// consulta es silenciosa a propósito — un fallo de red aquí no debe tapar el
/// dashboard.
class OnboardingBurbuja extends StatefulWidget {
  const OnboardingBurbuja({
    super.key,
    this.servicio,
    this.tareasIniciales,
    this.estadoInicial,
    this.abiertoInicial = false,
    this.margenDerecho = 16,
  });

  /// Servicio inyectable (pruebas).
  final OnboardingService? servicio;

  /// Tareas ya resueltas (pruebas o pantallas que ya las tienen).
  final List<TareaOnboarding>? tareasIniciales;

  /// Estado de onboarding ya resuelto (pruebas).
  final String? estadoInicial;

  /// Arranca con el panel abierto (pruebas).
  final bool abiertoInicial;

  /// Separación desde el borde derecho.
  ///
  /// Existe porque la esquina inferior derecha está ocupada en la web: el FAB
  /// de accesos rápidos (`bottom: 16`, 56 px) y, por encima, el del asistente
  /// de IA (`bottom: 150`). Ahí no queda hueco ni vertical ni horizontal para
  /// el aviso.
  ///
  /// Por eso la píldora se coloca **a la izquierda** del FAB, compartiendo su
  /// línea de base: 56 + 16 + 12 = 84. Se aparta el aviso y no los botones,
  /// que son permanentes y llevan ahí desde antes. En móvil no hay FAB y se
  /// queda en 16.
  final double margenDerecho;

  /// Clave estable para las pruebas.
  static const Key claveBoton = Key('onboarding_burbuja_boton');
  static const Key clavePanel = Key('onboarding_burbuja_panel');
  static const Key claveCerrarPanel = Key('onboarding_burbuja_cerrar');

  @override
  State<OnboardingBurbuja> createState() => _OnboardingBurbujaState();
}

class _OnboardingBurbujaState extends State<OnboardingBurbuja> {
  OnboardingService? _servicio;

  List<TareaOnboarding>? _tareas;
  String? _estado;

  /// El panel está desplegado. Cerrarlo no descarta nada: solo lo aparta.
  late bool _abierto = widget.abiertoInicial;

  @override
  void initState() {
    super.initState();
    final tareasIniciales = widget.tareasIniciales;
    final estadoInicial = widget.estadoInicial;
    if (tareasIniciales != null && estadoInicial != null) {
      _tareas = tareasIniciales;
      _estado = estadoInicial;
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
      if (estado.estadoOnboarding != 'borrador') {
        setState(() {
          _estado = estado.estadoOnboarding;
          _tareas = null;
        });
        return;
      }
      final tareas = await _onboarding.listarTareas();
      if (!mounted) return;
      setState(() {
        _estado = estado.estadoOnboarding;
        _tareas = tareas;
      });
    } catch (e) {
      // El usuario no ve un error aquí: es un extra del dashboard y taparlo con
      // un banner sería peor. Pero callarlo del todo dejaba «no aparece nada» sin
      // forma de saber por qué, así que queda en el log.
      debugPrint('⚠️ OnboardingBurbuja: no se pudo cargar el checklist: $e');
      if (!mounted) return;
      setState(() {
        _estado = null;
        _tareas = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sin datos o tienda activa: nada que enseñar.
    if (_estado != 'borrador' || _tareas == null) {
      return const SizedBox.shrink();
    }

    final tareas = _tareas!;
    final avance = progreso(tareas);
    final quedan = avance.total - avance.completadas;

    return Positioned.fill(
      child: Stack(
        children: [
          if (_abierto) _panel(tareas),
          Positioned(
            right: widget.margenDerecho,
            bottom: _margenInferior,
            child: _boton(tareas, quedan),
          ),
        ],
      ),
    );
  }
  // ---------------------------------------------------------------------
  // Botón flotante
  // ---------------------------------------------------------------------

  Widget _boton(List<TareaOnboarding> tareas, int quedan) {
    final texto = quedan == 0
        ? 'Poner en marcha'
        : '$quedan ${quedan == 1 ? 'paso' : 'pasos'} por completar';
    final completo = quedan == 0;

    return Material(
      key: OnboardingBurbuja.claveBoton,
      color: completo ? AppColors.success : AppColors.primary,
      borderRadius: BorderRadius.circular(999),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _abierto = !_abierto),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                completo
                    ? Icons.rocket_launch_outlined
                    : Icons.checklist_rtl_outlined,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 9),
              Text(
                texto,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _abierto ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                size: 18,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Panel
  // ---------------------------------------------------------------------

  Widget _panel(List<TareaOnboarding> tareas) {
    final pantalla = MediaQuery.sizeOf(context);
    final ancho = pantalla.width < _anchoPanel + 32
        ? pantalla.width - 32
        : _anchoPanel;

    return Positioned(
      // Alineado con la píldora, y el panel crece hacia arriba desde ahí.
      right: widget.margenDerecho,
      bottom: _margenInferior + _altoBoton + 12,
      width: ancho,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: pantalla.height * _altoMaximoFactor),
        child: Material(
          key: OnboardingBurbuja.clavePanel,
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabeceraPanel(tareas),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: _listaTareas(tareas),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabeceraPanel(List<TareaOnboarding> tareas) {
    final avance = progreso(tareas);
    final valor = avance.total == 0 ? 0.0 : avance.completadas / avance.total;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pon tu tienda en marcha',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      textoProgreso(tareas),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: OnboardingBurbuja.claveCerrarPanel,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Cerrar (puedes reabrirlo cuando quieras)',
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _abierto = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: valor,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lista de tareas: lo hecho se **tacha**, que es lo que pide el patrón.
  Widget _listaTareas(List<TareaOnboarding> tareas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tarea in tareas)
          _fila(tarea),
        const SizedBox(height: 6),
        _pie(tareas),
      ],
    );
  }

  Widget _fila(TareaOnboarding tarea) {
    final hecha = tarea.estado == EstadoTarea.completada;
    final bloqueada = tarea.bloqueada;
    final puedeTocar = !hecha && !bloqueada && tarea.accionable;

    final colorTexto = hecha
        ? AppColors.textLight
        : bloqueada
        ? AppColors.textSecondary
        : AppColors.textPrimary;

    return InkWell(
      onTap: puedeTocar ? () => _resolver(tarea) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                hecha
                    ? Icons.check_circle
                    : bloqueada
                    ? Icons.lock_outline
                    : Icons.radio_button_unchecked,
                size: 17,
                color: hecha
                    ? AppColors.success
                    : bloqueada
                    ? AppColors.textLight
                    : AppColors.primary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tarea.titulo,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: hecha ? FontWeight.w400 : FontWeight.w600,
                      color: colorTexto,
                      // El tachado es la señal de «esto ya está».
                      decoration: hecha ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textLight,
                    ),
                  ),
                  if (!hecha && !bloqueada) ...[
                    const SizedBox(height: 1),
                    Text(
                      tarea.obligatoria
                          ? 'Hace falta para poder vender'
                          : 'Recomendado',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: tarea.obligatoria
                            ? AppColors.warning
                            : AppColors.textLight,
                      ),
                    ),
                  ],
                  if (bloqueada) ...[
                    const SizedBox(height: 1),
                    Text(
                      tarea.motivoBloqueo!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (puedeTocar)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 1),
                child: Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: AppColors.textLight,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pie(List<TareaOnboarding> tareas) {
    final listo = puedeActivar(tareas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 18, color: AppColors.border),
        Text(
          listo
              ? 'Está todo lo imprescindible. Puedes ponerla en marcha.'
              : 'Completa lo que lleva el aviso naranja y podrás ponerla en '
                    'marcha.',
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Resuelve una tarea: navega a su pantalla o pide el dato en línea.
  Future<void> _resolver(TareaOnboarding tarea) async {
    // Las tareas de datos de tienda y el alta de quien cobra se piden en el
    // propio panel: sacar al usuario a otra pantalla para un campo rompe el
    // hilo del checklist.
    if (tarea.enPanel) {
      await _pedirEnPanel(tarea);
      return;
    }

    final ruta = tarea.ruta;
    if (ruta == null) return;
    setState(() => _abierto = false);
    try {
      await Navigator.of(context).pushNamed(ruta);
    } catch (_) {
      // Ruta no registrada: se avisa en vez de romper.
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Esa pantalla no está disponible.')),
      );
      return;
    }
    if (mounted) await _cargar();
  }

  Future<void> _pedirEnPanel(TareaOnboarding tarea) async {
    switch (tarea.campoPanel) {
      case 'nombre':
        await _pedirTexto(
          titulo: 'Ponle nombre a tu tienda',
          etiqueta: 'Nombre de la tienda',
          pista: 'Ej: Mercado Central',
          ayuda: 'Es el nombre que ven tus clientes y tu equipo.',
          alGuardar: (v) => _onboarding.guardarDatosTienda(nombre: v),
        );
      case 'direccion':
        await _pedirTexto(
          titulo: 'La dirección del local',
          etiqueta: 'Dirección',
          pista: 'Calle, número, referencia',
          ayuda: 'Sale impresa en cada ticket.',
          alGuardar: (v) => _onboarding.guardarDatosTienda(direccion: v),
        );
      case 'ubicacion':
        await _pedirTexto(
          titulo: 'Marca tu tienda en el mapa',
          etiqueta: 'Coordenadas o referencia',
          pista: 'Ej: 23.1136,-82.3666',
          ayuda: 'Las coordenadas del local, para el reparto y las rutas.',
          alGuardar: (v) => _onboarding.guardarDatosTienda(ubicacion: v),
        );
      case 'cobro':
        // El alta de trabajador vive en la pantalla de personal, con su
        // formulario completo y el rol ya marcado. Aquí solo se lleva.
        setState(() => _abierto = false);
        await Navigator.of(context).pushNamed(
          '/workers',
          arguments: const {'nuevoTrabajador': 'cobro'},
        );
        if (mounted) await _cargar();
    }
  }

  /// Pide un texto y lo guarda. El formulario es el mismo para los tres campos
  /// de tienda: cambia la etiqueta y qué columna se escribe.
  Future<void> _pedirTexto({
    required String titulo,
    required String etiqueta,
    required String pista,
    required String ayuda,
    required Future<void> Function(String) alGuardar,
  }) async {
    final controlador = TextEditingController();
    String? error;
    var guardando = false;

    await showDialog<void>(
      context: context,
      builder: (dialogo) => StatefulBuilder(
        builder: (contexto, setDialogo) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          title: Text(
            titulo,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ayuda,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controlador,
                autofocus: true,
                enabled: !guardando,
                decoration: InputDecoration(
                  labelText: etiqueta,
                  hintText: pista,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) => _guardarDelDialogo(
                  contexto: contexto,
                  setDialogo: setDialogo,
                  controlador: controlador,
                  alGuardar: alGuardar,
                  aplicar: (e) => error = e,
                  leyendo: () => guardando,
                  marcando: (v) => guardando = v,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.of(contexto).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: guardando
                  ? null
                  : () => _guardarDelDialogo(
                      contexto: contexto,
                      setDialogo: setDialogo,
                      controlador: controlador,
                      alGuardar: alGuardar,
                      aplicar: (e) => error = e,
                      leyendo: () => guardando,
                      marcando: (v) => guardando = v,
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (mounted) await _cargar();
  }

  /// Guardado compartido por el botón y el `Enter` del diálogo.
  Future<void> _guardarDelDialogo({
    required BuildContext contexto,
    required void Function(void Function()) setDialogo,
    required TextEditingController controlador,
    required Future<void> Function(String) alGuardar,
    required void Function(String?) aplicar,
    required bool Function() leyendo,
    required void Function(bool) marcando,
  }) async {
    if (leyendo()) return;
    final texto = controlador.text.trim();
    if (texto.isEmpty) {
      setDialogo(() => aplicar('Escribe algo para poder guardar.'));
      return;
    }

    setDialogo(() {
      aplicar(null);
      marcando(true);
    });

    try {
      await alGuardar(texto);
      if (!contexto.mounted) return;
      Navigator.of(contexto).pop();
    } catch (e) {
      if (!contexto.mounted) return;
      setDialogo(() {
        marcando(false);
        aplicar(e.toString().replaceFirst('Exception: ', ''));
      });
    }
  }
}
