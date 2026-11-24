/// Preflight del Go Live: pantalla que revisa y activa la tienda.
///
/// Fase 4 del plan `docs/plans/alta-tienda-progresiva-go-live.md`.
///
/// El diseño sigue lo que hacen los productos que funcionan (Stripe, Shopify,
/// Framer, GOV.UK) y que está resumido en el plan:
///
///  * **Tres resultados, no dos**: listo / con advertencias / bloqueado. Un
///    aviso que se puede asumir no se pinta igual que un bloqueo.
///  * **El resumen es un documento de solo lectura**, no un formulario de
///    vuelta: secciones con «Cambiar» que devuelven a la pantalla concreta.
///  * **Los campos opcionales vacíos se muestran** como «Sin configurar» en vez
///    de desaparecer: esconderlos hace creer que el producto está roto.
///  * **El veredicto final lo da el servidor.** Esta pantalla calcula un
///    preflight para explicar, pero `fn_m01_activar_tienda` vuelve a validar y
///    devuelve el resumen real. Si discreparan, manda el servidor.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';
import '../services/onboarding_service.dart';

/// Abre el preflight y devuelve `true` si la tienda quedó activada.
Future<bool> mostrarGoLive(
  BuildContext context, {
  required List<TareaOnboarding> tareas,
  OnboardingService? servicio,
  Map<String, dynamic> resumenInicial = const {},
}) async {
  final activada = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GoLiveSheet(
      tareas: tareas,
      servicio: servicio,
      resumenInicial: resumenInicial,
    ),
  );
  return activada ?? false;
}

/// Diálogo de preflight + activación.
class GoLiveSheet extends StatefulWidget {
  const GoLiveSheet({
    super.key,
    required this.tareas,
    this.servicio,
    this.resumenInicial = const {},
    this.activar,
  });

  final List<TareaOnboarding> tareas;

  /// Servicio inyectable (pruebas).
  final OnboardingService? servicio;

  /// Conteos que ya conoce la pantalla de activación, para no enseñar huecos
  /// mientras el servidor responde.
  final Map<String, dynamic> resumenInicial;

  /// Permite montar el diálogo en una prueba sin backend. Si es nulo se llama
  /// a `OnboardingService.activarTienda()`.
  final Future<Map<String, dynamic>> Function()? activar;

  @override
  State<GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<GoLiveSheet> {
  bool _activando = false;
  String? _error;

  /// Respuesta del servidor tras un intento de activación, para pintar sus
  /// conteos reales en el resumen en vez de los estimados.
  Map<String, dynamic>? _respuestaServidor;

  OnboardingService? _servicio;

  OnboardingService get _onboarding =>
      _servicio ??= widget.servicio ?? OnboardingService();

  /// Los bloqueos reales: tareas obligatorias que no están completadas.
  List<TareaOnboarding> get _bloqueos => tareasBloqueantes(widget.tareas);

  /// Avisos: todo lo demás pendiente. No impide activar.
  List<TareaOnboarding> get _avisos => widget.tareas
      .where((t) => t.estado != EstadoTarea.completada && !t.obligatoria)
      .toList();

  bool get _puedeActivar => _bloqueos.isEmpty && !_activando;

  Future<void> _activar() async {
    setState(() {
      _activando = true;
      _error = null;
    });

    try {
      final resultado = await (widget.activar?.call() ??
          _onboarding.activarTienda());

      // Se guarda siempre: también un intento fallido trae los conteos reales,
      // y enseñarlos es mejor que seguir con los estimados del cliente.
      _respuestaServidor = resultado;

      // El servidor manda: si devuelve false, no se cierra nada.
      if (resultado['success'] == false) {
        setState(() {
          _activando = false;
          _error =
              (resultado['mensaje'] ??
                      resultado['message'] ??
                      'El servidor no activó la tienda.')
                  .toString();
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on OnboardingException catch (e) {
      if (!mounted) return;
      setState(() {
        _activando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activando = false;
        _error = 'No se pudo activar la tienda: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    final ancho = MediaQuery.sizeOf(context).width;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: ancho >= 720 ? 40 : 16,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: alto - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cabecera(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_bloqueos.isNotEmpty) _bloqueBloqueos(),
                    if (_bloqueos.isEmpty) _bloqueListo(),
                    if (_avisos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _bloqueAvisos(),
                    ],
                    const SizedBox(height: 20),
                    _resumen(),
                  ],
                ),
              ),
            ),
            _pie(),
          ],
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rocket_launch_outlined,
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Poner tu tienda en marcha',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Revisa lo que tienes. Si todo cuadra, tu tienda empieza a '
                  'vender.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            tooltip: 'Cerrar',
            onPressed: _activando
                ? null
                : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _bloqueListo() {
    return _banda(
      icono: Icons.check_circle_outline,
      color: AppColors.success,
      titulo: 'Todo lo esencial está listo',
      detalle:
          'Puedes activar la tienda ahora. Lo que falte de la lista de abajo '
          'no impide vender: puedes terminarlo cuando quieras.',
    );
  }

  Widget _bloqueBloqueos() {
    return _banda(
      icono: Icons.error_outline,
      color: AppColors.error,
      titulo: _bloqueos.length == 1
          ? 'Falta algo imprescindible para vender'
          : 'Faltan ${_bloqueos.length} cosas imprescindibles',
      detalle:
          'Sin esto la tienda no puede operar, así que no se puede activar '
          'todavía. Cada punto te lleva a donde se resuelve.',
      hijos: [
        for (final tarea in _bloqueos)
          _filaAccion(tarea, color: AppColors.error),
      ],
    );
  }

  Widget _bloqueAvisos() {
    return _banda(
      icono: Icons.info_outline,
      color: AppColors.warning,
      titulo: _avisos.length == 1
          ? 'Un detalle que puedes dejar para después'
          : '${_avisos.length} detalles que puedes dejar para después',
      detalle: 'No impiden vender. Aparecerán en tu checklist.',
      hijos: [
        for (final tarea in _avisos) _filaAccion(tarea, color: AppColors.warning),
      ],
    );
  }

  Widget _banda({
    required IconData icono,
    required Color color,
    required String titulo,
    required String detalle,
    List<Widget> hijos = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              detalle,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (hijos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: hijos,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Cada punto con su enlace para resolverlo. Un bloqueo sin salida es un
  /// callejón sin salida, y es el motivo por el que el usuario abandona.
  Widget _filaAccion(TareaOnboarding tarea, {required Color color}) {
    final ruta = tarea.ruta;
    final puedeIr = ruta != null && !_activando;

    return InkWell(
      onTap: puedeIr
          ? () {
              Navigator.of(context).pop(false);
              Navigator.of(context).pushNamed(ruta);
            }
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                Icons.arrow_right,
                size: 16,
                color: puedeIr ? color : AppColors.textLight,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                tarea.titulo,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: puedeIr ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
            if (ruta == null)
              const Text(
                'informativa',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textLight,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Resumen con el que pintar la tabla.
  ///
  /// Prioridad: lo que devolvió el servidor al activar > lo que traía la
  /// pantalla > vacío. El servidor manda porque sus conteos son los reales.
  Map<String, dynamic> _resumenDelServidor() {
    final respuesta = _respuestaServidor;
    if (respuesta == null) return widget.resumenInicial;

    final anidado = respuesta['resumen'];
    final mapa = anidado is Map
        ? Map<String, dynamic>.from(anidado)
        : <String, dynamic>{};

    // `tipo_negocio` puede venir en el nivel de arriba o dentro del resumen.
    mapa['tipo_negocio'] ??= respuesta['tipo_negocio'];
    return mapa.isEmpty ? widget.resumenInicial : mapa;
  }

  Widget _resumen() {
    // La RPC devuelve el resumen **plano** (no anidado en `data`). Se acepta
    // también anidado por si una versión futura lo envuelve, pero el caso real
    // es plano: leerlo mal dejaría toda la tabla en «Sin configurar» después de
    // una activación correcta.
    final fuente = _resumenDelServidor();
    final filas = <(String, String)>[
      ('Tipo de negocio', _textoTipo(fuente['tipo_negocio'])),
      ('Almacenes', _conteo(fuente['almacenes'], widget.tareas, 'almacen')),
      ('Cajas', _conteo(fuente['tpvs'], widget.tareas, 'tpv')),
      ('Productos', _conteo(fuente['productos'], widget.tareas, 'producto')),
      ('Quien cobra', _conteo(fuente['vendedores'], widget.tareas, 'cobro')),
      ('Equipo', _conteo(fuente['trabajadores'], widget.tareas, 'personal')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lo que hay ahora',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final (etiqueta, valor) in filas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          etiqueta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          valor,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _textoTipo(Object? valor) {
    final tipo = valor?.toString();
    if (tipo == null || tipo.isEmpty) return 'Sin declarar';
    return tiposNegocioConocidos.contains(tipo) ? tipo : 'Sin declarar';
  }

  /// Si el servidor aún no dio conteos, se deriva del estado de la tarea: es
  /// honesto decir «sin configurar» en vez de inventar un cero. Se muestra como
  /// «Sin configurar» cuando la tarea existe y no está completada.
  static String _conteo(
    Object? valor,
    List<TareaOnboarding> tareas,
    String clave,
  ) {
    if (valor is num) {
      final n = valor.toInt();
      return n == 0 ? 'Sin configurar' : '$n';
    }
    final tarea = tareas.where((t) => t.clave == clave).firstOrNull;
    if (tarea == null) return 'Sin configurar';
    return tarea.estado == EstadoTarea.completada ? 'Configurado' : 'Sin configurar';
  }

  Widget _pie() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
          Row(
            children: [
              TextButton(
                onPressed: _activando
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Ahora no'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _puedeActivar ? _activar : null,
                icon: _activando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.rocket_launch_outlined, size: 17),
                label: Text(_activando ? 'Activando...' : 'Activar tienda'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
