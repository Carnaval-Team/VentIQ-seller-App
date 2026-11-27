import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show TickerCanceled;

import '../config/app_colors.dart';
import '../main.dart' show appNavigatorKey;
import '../models/notification_model.dart';
import 'notification_widget.dart';

/// Aviso flotante de «producto agotado» para el panel de administración.
///
/// Es el mismo aviso que usa la app de caja (`ventiq_app`): entra por ARRIBA,
/// con su propio color y su propia tarjeta, para que no se confunda con un
/// `SnackBar` de resultado. En el dashboard web el agotado es la señal más
/// urgente del panel —sin stock no hay venta—, así que no puede competir con
/// los mensajes de «guardado correcto».
///
/// Igual que en la app de caja, se pinta sobre el `Overlay` del navegador
/// global: el evento lo dispara `NotificationService`, que no tiene un
/// `BuildContext` propio, y así funciona en el dashboard web, en el móvil y
/// encima de cualquier modal.
class AvisoProductoAgotado {
  const AvisoProductoAgotado._();

  /// Cuánto se queda en pantalla antes de irse solo.
  static const Duration duracionEnPantalla = Duration(seconds: 7);

  /// Un aviso a la vez; el resto espera en cola para no apilarse.
  static final List<NotificationModel> _cola = <NotificationModel>[];
  static OverlayEntry? _entrada;
  static bool _visible = false;

  /// ¿Esta notificación es de las que merecen el aviso grande?
  ///
  /// Se exige `inventario` + `id_producto`: el resto de notificaciones de
  /// inventario (producto disponible, por ejemplo) siguen su camino normal.
  static bool esProductoAgotado(NotificationModel notificacion) {
    if (notificacion.tipo != NotificationType.inventario) return false;

    final Map<String, dynamic> data =
        notificacion.data ?? const <String, dynamic>{};
    if (data['id_producto'] == null) return false;

    final String titulo = notificacion.titulo.toLowerCase();
    return titulo.contains('agotad') ||
        data['stock_actual'] != null ||
        data.containsKey('almacen_nombre');
  }

  /// Encola el aviso. Silencioso a propósito: si no hay overlay (arranque,
  /// tests) o la notificación no es de agotado, no pasa nada.
  static void mostrar(NotificationModel notificacion) {
    if (!esProductoAgotado(notificacion)) return;

    if (_cola.length >= 5) {
      _cola.removeAt(0);
    }
    _cola.add(notificacion);

    if (_visible) return;
    _mostrarSiguiente();
  }

  /// Cierra lo que esté en pantalla y vacía la cola (logout, dispose).
  static void ocultarTodo() {
    _cola.clear();
    final OverlayEntry? entrada = _entrada;
    _entrada = null;
    _visible = false;
    if (entrada != null && entrada.mounted) {
      entrada.remove();
    }
  }

  static void _mostrarSiguiente() {
    final OverlayState? overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null || _cola.isEmpty) {
      _visible = false;
      return;
    }

    final NotificationModel notificacion = _cola.removeAt(0);
    _visible = true;

    late final OverlayEntry entrada;
    entrada = OverlayEntry(
      builder: (BuildContext context) => AvisoProductoAgotadoCard(
        notificacion: notificacion,
        duracion: duracionEnPantalla,
        onCerrar: () => _cerrar(entrada),
        onAbrir: () {
          _cerrar(entrada);
          abrirPanelDeNotificacionesGlobal();
        },
      ),
    );

    _entrada = entrada;

    try {
      overlay.insert(entrada);
    } catch (e) {
      // Nunca tumbar la app por un aviso.
      debugPrint('⚠️ No se pudo mostrar el aviso de agotado: $e');
      _entrada = null;
      _visible = false;
    }
  }

  static void _cerrar(OverlayEntry entrada) {
    if (_entrada != entrada) return; // idempotente: doble tap / timer + swipe
    _entrada = null;
    _visible = false;

    if (entrada.mounted) {
      entrada.remove();
    }

    _mostrarSiguiente();
  }
}

/// La tarjeta. Pública para poder montarla en tests sin el `Overlay`.
class AvisoProductoAgotadoCard extends StatefulWidget {
  const AvisoProductoAgotadoCard({
    super.key,
    required this.notificacion,
    required this.onCerrar,
    required this.onAbrir,
    this.duracion = AvisoProductoAgotado.duracionEnPantalla,
  });

  final NotificationModel notificacion;
  final Duration duracion;
  final VoidCallback onCerrar;
  final VoidCallback onAbrir;

  /// Mismo rojo que el aviso de la app de caja, para que el aviso se reconozca
  /// igual en las dos apps aunque aquí la paleta se llame distinto.
  static const Color acento = Color(0xFFE53935);

  @override
  State<AvisoProductoAgotadoCard> createState() =>
      _AvisoProductoAgotadoCardState();
}

class _AvisoProductoAgotadoCardState extends State<AvisoProductoAgotadoCard>
    with TickerProviderStateMixin {
  late final AnimationController _entrada;
  late final AnimationController _vida;
  late final Animation<double> _curva;
  bool _saliendo = false;

  @override
  void initState() {
    super.initState();

    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _curva = CurvedAnimation(
      parent: _entrada,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _vida = AnimationController(vsync: this, duration: widget.duracion)
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          _salir();
        }
      });

    _entrada.forward();
    _vida.forward();
  }

  @override
  void dispose() {
    (_curva as CurvedAnimation).dispose();
    _entrada.dispose();
    _vida.dispose();
    super.dispose();
  }

  Future<void> _salir() async {
    if (_saliendo) return;
    _saliendo = true;

    _vida.stop();

    try {
      await _entrada.reverse();
    } on TickerCanceled {
      // El árbol se fue antes de terminar la salida: no hay nada que cerrar.
      return;
    }

    if (mounted) {
      widget.onCerrar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.1),
          end: Offset.zero,
        ).animate(_curva),
        child: FadeTransition(
          opacity: _curva,
          child: SafeArea(
            bottom: false,
            child: GestureDetector(
              // Un tirón hacia arriba lo manda fuera.
              onVerticalDragEnd: (DragEndDetails detalles) {
                if ((detalles.primaryVelocity ?? 0) < -200) {
                  _salir();
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _construirTarjeta(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirTarjeta() {
    final Map<String, dynamic> data =
        widget.notificacion.data ?? const <String, dynamic>{};

    final String producto =
        (data['producto_nombre'] as String?)?.trim().isNotEmpty == true
            ? (data['producto_nombre'] as String).trim()
            : widget.notificacion.titulo;

    final String? almacen = (data['almacen_nombre'] as String?)?.trim();
    final String? ubicacion = (data['ubicacion_nombre'] as String?)?.trim();

    final String lugar = <String>[
      if (almacen != null && almacen.isNotEmpty) almacen,
      if (ubicacion != null && ubicacion.isNotEmpty) ubicacion,
    ].join(' · ');

    final String detalle = lugar.isNotEmpty ? lugar : widget.notificacion.mensaje;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Producto agotado. $producto. $detalle',
      child: Container(
        key: const Key('aviso_agotado_tarjeta'),
        // En web el dashboard puede llegar a 1600 px: sin tope, la tarjeta se
        // estira de lado a lado y el texto queda perdido en una franja enorme.
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x2633405C),
              blurRadius: 26,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: AppColors.surface,
            child: InkWell(
              onTap: widget.onAbrir,
              child: Stack(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 6, 15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _construirIcono(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _construirEtiqueta(),
                              const SizedBox(height: 5),
                              Text(
                                producto,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                detalle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _construirCerrar(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _construirProgreso(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirIcono() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AvisoProductoAgotadoCard.acento.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.inventory_2_rounded,
        size: 21,
        color: AvisoProductoAgotadoCard.acento,
      ),
    );
  }

  Widget _construirEtiqueta() {
    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AvisoProductoAgotadoCard.acento,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'PRODUCTO AGOTADO',
          style: TextStyle(
            color: AvisoProductoAgotadoCard.acento,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _construirCerrar() {
    return IconButton(
      onPressed: _salir,
      tooltip: 'Cerrar',
      splashRadius: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: const Icon(
        Icons.close_rounded,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// Línea de vida: se va vaciando mientras el aviso espera. Da la pista de
  /// que se cierra solo, sin necesidad de un contador de texto.
  Widget _construirProgreso() {
    return SizedBox(
      height: 3,
      child: AnimatedBuilder(
        animation: _vida,
        builder: (BuildContext context, Widget? child) {
          final double restante = (1 - _vida.value).clamp(0.0, 1.0);
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: restante,
              child: Container(
                color: AvisoProductoAgotadoCard.acento.withValues(alpha: 0.55),
              ),
            ),
          );
        },
      ),
    );
  }
}
