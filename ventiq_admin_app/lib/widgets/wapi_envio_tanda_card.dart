import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_envio_tanda.dart';
import '../utils/wapi_errores.dart';

/// Tarjeta de una tanda de envío.
///
/// QUÉ CAMBIÓ (UX para el cliente final)
///   1. **Diagnóstico en castellano**: antes se mostraba el código crudo del
///      servidor ("Error más frecuente: Session is not connected. The WhatsApp
///      client is not ready. (tras 3 intento(s))"). Ahora se traduce a
///      «El bot se desconectó» + qué pasó + qué hacer (ver `wapi_errores.dart`).
///   2. **Reintentar sin buscar**: el botón «Reintentar N mensajes» y, cuando
///      hace falta, «Reconectar bot» van SIEMPRE visibles en un pie de tarjeta.
///      Antes vivían en un chip diminuto del encabezado y la explicación
///      quedaba escondida tras expandir la tarjeta.
///   3. **Por qué se detuvo, de un vistazo**: el pie dice el motivo y cuándo.
///   4. Se respeta «reducir movimiento» del sistema: sin animaciones cuando el
///      usuario las tiene desactivadas.
class WapiEnvioTandaCard extends StatefulWidget {
  final WapiEnvioTanda tanda;

  /// Resalta la tanda como "la que se está enviando ahora".
  final bool destacada;

  /// Nombre legible por chat_id (etiqueta del destinatario).
  final Map<String, String> etiquetas;

  /// Denominación por id de producto.
  final String Function(int? id) productoNombre;

  /// Reanuda los mensajes que quedaron sin despachar. Si es null no se
  /// muestra el botón de reanudar.
  final Future<void> Function(WapiEnvioTanda tanda)? onReanudar;

  /// Reconecta el bot de la sesión de esta tanda. Se ofrece cuando el
  /// diagnóstico dice que el origen fue una sesión caída: reintentar sin
  /// reconectar antes volvería a fallar.
  final Future<void> Function()? onReconectar;

  const WapiEnvioTandaCard({
    super.key,
    required this.tanda,
    required this.destacada,
    this.etiquetas = const {},
    this.productoNombre = _productoPorDefecto,
    this.onReanudar,
    this.onReconectar,
  });

  static String _productoPorDefecto(int? id) =>
      id == null ? 'Producto' : 'Producto #$id';

  @override
  State<WapiEnvioTandaCard> createState() => _WapiEnvioTandaCardState();
}

class _WapiEnvioTandaCardState extends State<WapiEnvioTandaCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;

  /// Parpadeo del botón "Reintentar". Corre sólo cuando hay algo que reanudar,
  /// y es deliberadamente más rápido que [_pulse] para que llame la atención.
  late final AnimationController _blink;

  bool _expandida = false;
  bool _reanudando = false;
  bool _reconectando = false;
  bool _verDetalleTecnico = false;

  /// El sistema pide menos movimiento (accesibilidad): apagamos parpadeos.
  bool _movimientoReducido = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _expandida = widget.destacada;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducido = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reducido != _movimientoReducido) {
      _movimientoReducido = reducido;
      if (reducido) {
        _pulse.stop();
        _blink.stop();
      }
    }
    _sincronizarPulso();
  }

  @override
  void didUpdateWidget(WapiEnvioTandaCard old) {
    super.didUpdateWidget(old);
    _sincronizarPulso();
  }

  /// ¿Mostramos las acciones de reintento? Requiere callback, mensajes sin
  /// entregar y que no haya un reanudar en vuelo.
  bool get _puedeReanudar =>
      widget.onReanudar != null &&
      widget.tanda.puedeReanudarse(DateTime.now());

  /// El pulso solo corre mientras la tanda está activa — una animación infinita
  /// en tarjetas terminadas gasta frames sin aportar nada.
  void _sincronizarPulso() {
    final activa =
        widget.tanda.estadoPara(DateTime.now()) == WapiTandaEstado.enCurso;
    if (activa && !_movimientoReducido && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if ((!activa || _movimientoReducido) && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }

    // Mismo criterio para el parpadeo: sólo mientras haya algo que reanudar.
    final parpadea = _puedeReanudar && !_reanudando && !_movimientoReducido;
    if (parpadea && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!parpadea && _blink.isAnimating) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  Future<void> _reanudar() async {
    final cb = widget.onReanudar;
    if (cb == null || _reanudando) return;
    setState(() => _reanudando = true);
    _sincronizarPulso();
    try {
      await cb(widget.tanda);
    } finally {
      if (mounted) {
        setState(() => _reanudando = false);
        _sincronizarPulso();
      }
    }
  }

  Future<void> _reconectar() async {
    final cb = widget.onReconectar;
    if (cb == null || _reconectando) return;
    setState(() => _reconectando = true);
    try {
      await cb();
    } finally {
      if (mounted) setState(() => _reconectando = false);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _blink.dispose();
    super.dispose();
  }

  _EstiloEstado _estilo(WapiTandaEstado e) {
    switch (e) {
      case WapiTandaEstado.enCurso:
        return const _EstiloEstado(
          color: AppColors.info,
          icono: Icons.send_rounded,
          rotulo: 'Enviando ahora',
        );
      case WapiTandaEstado.completada:
        return const _EstiloEstado(
          color: AppColors.success,
          icono: Icons.check_circle_rounded,
          rotulo: 'Completado',
        );
      case WapiTandaEstado.conFallos:
        return const _EstiloEstado(
          color: AppColors.warning,
          icono: Icons.error_outline_rounded,
          rotulo: 'Terminó con fallos',
        );
      case WapiTandaEstado.fallida:
        return const _EstiloEstado(
          color: AppColors.error,
          icono: Icons.cancel_rounded,
          rotulo: 'No se envió nada',
        );
      case WapiTandaEstado.interrumpida:
        return const _EstiloEstado(
          color: AppColors.warning,
          icono: Icons.pause_circle_outline_rounded,
          rotulo: 'Se quedó a medias',
        );
    }
  }

  String _nombreChat(String chatId) {
    final etq = widget.etiquetas[chatId];
    if (etq != null && etq.isNotEmpty) return etq;
    // Fallback: los ids de grupo son larguísimos, mostramos algo acotado.
    if (chatId.endsWith('@g.us')) {
      final n = chatId.split('@').first;
      return 'Grupo ...${n.length > 4 ? n.substring(n.length - 4) : n}';
    }
    return chatId.split('@').first;
  }

  String _nombreProducto(int? id) => widget.productoNombre(id);

  String _hora(DateTime d) => DateFormat('dd/MM HH:mm').format(d.toLocal());

  String _hace(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tanda;
    final ahora = DateTime.now();
    final estado = t.estadoPara(ahora);
    final st = _estilo(estado);
    final enCurso = estado == WapiTandaEstado.enCurso;
    final diag = diagnosticarTanda(t);

    return TweenAnimationBuilder<double>(
      // Al pasar de "en curso" a terminada, el realce se apaga suavemente en
      // vez de saltar.
      tween: Tween(begin: 0, end: widget.destacada ? 1 : 0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (context, realce, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.lerp(AppColors.border, st.color, realce * 0.85)!,
              width: 1 + realce * 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: st.color.withOpacity(0.16 * realce),
                blurRadius: 18 * realce,
                spreadRadius: realce,
                offset: Offset(0, 3 * realce),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (enCurso) _barraViva(st.color),
              InkWell(
                onTap: () => setState(() => _expandida = !_expandida),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _encabezado(t, st, enCurso, diag),
                      const SizedBox(height: 12),
                      _progreso(t, st, enCurso),
                      const SizedBox(height: 10),
                      _chips(t, estado),
                    ],
                  ),
                ),
              ),
              // Acciones SIEMPRE visibles (no dentro del desplegable).
              if (!enCurso && _puedeReanudar)
                _pieAcciones(t, estado, diag),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: _expandida
                    ? _detalle(t, estado, diag)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Línea indeterminada en el borde superior: señal inequívoca de "esto está
  /// pasando ahora mismo".
  Widget _barraViva(Color color) => SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );

  Widget _encabezado(
    WapiEnvioTanda t,
    _EstiloEstado st,
    bool enCurso,
    WapiDiagnosticoTanda diag,
  ) {
    // Segunda línea: contexto útil en vez de solo metadatos. Cuando algo se
    // quedó a medias, dice CUÁNDO y por qué en el mismo renglón.
    final String subtitulo;
    if (enCurso) {
      subtitulo = 'Producto ${t.productosCompletados + 1} de '
          '${t.productos.length} · ${_nombreProducto(t.productoActual)}';
    } else if (diag.hayDiagnostico && diag.principal != null) {
      subtitulo = '${diag.principal!.titulo} · ${_hace(t.ultimaActividad)}';
    } else {
      subtitulo = '${t.productos.length} producto(s) · '
          '${t.chats.length} destino(s) · ${_hora(t.inicio)}';
    }

    return Row(
      children: [
        // Ícono con halo pulsante mientras envía.
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final p = enCurso ? _pulse.value : 0.0;
            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: st.color.withOpacity(0.10 + 0.10 * p),
                borderRadius: BorderRadius.circular(12),
                boxShadow: enCurso
                    ? [
                        BoxShadow(
                          color: st.color.withOpacity(0.28 * p),
                          blurRadius: 14 * p,
                          spreadRadius: 2 * p,
                        ),
                      ]
                    : null,
              ),
              child: Icon(st.icono, color: st.color, size: 22),
            );
          },
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      st.rotulo,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: st.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _tipoBadge(t),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (diag.hayDiagnostico && !enCurso) ...[
                    Icon(
                      diag.principal!.icono,
                      size: 13,
                      color: diag.principal!.color,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      subtitulo,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AnimatedRotation(
          turns: _expandida ? 0.5 : 0,
          duration: const Duration(milliseconds: 240),
          child: const Icon(Icons.expand_more,
              size: 22, color: AppColors.textLight),
        ),
      ],
    );
  }

  Widget _tipoBadge(WapiEnvioTanda t) {
    final prog = t.esProgramado;
    final c = prog ? AppColors.primary : AppColors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(prog ? Icons.schedule : Icons.touch_app, size: 10, color: c),
          const SizedBox(width: 3),
          Text(
            prog ? 'AUTOMÁTICO' : 'MANUAL',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w800, color: c),
          ),
        ],
      ),
    );
  }

  Widget _progreso(WapiEnvioTanda t, _EstiloEstado st, bool enCurso) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          // El valor se interpola: al refrescar, la barra "avanza" en lugar de
          // saltar al nuevo porcentaje.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: t.progreso),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 7,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(st.color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${t.procesados} de ${t.total} mensajes',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const Spacer(),
            Text(
              '${(t.progreso * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: st.color),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chips(WapiEnvioTanda t, WapiTandaEstado estado) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Contador(
          icono: Icons.check_circle_rounded,
          color: AppColors.success,
          etiqueta: 'Entregados',
          valor: t.enviados,
        ),
        if (t.pendientes > 0)
          _Contador(
            icono: Icons.pause_circle_outline_rounded,
            color: AppColors.warning,
            etiqueta: 'Sin enviar',
            valor: t.pendientes,
            animado: estado == WapiTandaEstado.enCurso,
          ),
        if (t.fallidos > 0)
          _Contador(
            icono: Icons.error_rounded,
            color: AppColors.error,
            etiqueta: 'Fallaron',
            valor: t.fallidos,
          ),
      ],
    );
  }

  /// ── PIE DE ACCIONES ──────────────────────────────────────────────────
  /// El corazón del arreglo de UX: cuando la tanda no terminó, aquí está el
  /// motivo en una frase y los botones para arreglarlo, sin expandir nada.
  Widget _pieAcciones(
    WapiEnvioTanda t,
    WapiTandaEstado estado,
    WapiDiagnosticoTanda diag,
  ) {
    final d = diag.principal;
    final color = d?.color ?? AppColors.warning;
    final faltan = t.logIdsSinEnviar.length;
    final necesitaReconectar =
        diag.hayQueReconectar && widget.onReconectar != null;

    // Motivo en una frase: "WhatsApp cortó la sesión..." / "N mensajes sin
    // enviar porque...".
    final motivo = d == null
        ? 'Quedaron $faltan mensaje(s) sin enviar.'
        : diag.totalFallidos > 0
            ? '${d.titulo} · ${d.explicacion}'
            : d.explicacion;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(d?.icono ?? Icons.info_outline_rounded,
                  size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  motivo,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (d?.queHacer != null) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                '👉 ${d!.queHacer}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                flex: necesitaReconectar ? 3 : 1,
                child: _BotonReintentar(
                  blink: _blink,
                  cargando: _reanudando,
                  pendientes: faltan,
                  onTap: _reanudar,
                ),
              ),
              if (necesitaReconectar) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _reconectando ? null : _reconectar,
                    icon: _reconectando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded, size: 17),
                    label: Text(
                      _reconectando ? 'Reconectando…' : 'Reconectar bot',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _detalle(
    WapiEnvioTanda t,
    WapiTandaEstado estado,
    WapiDiagnosticoTanda diag,
  ) {
    // Desglose por destino: deja ver de un golpe si a algún grupo no le llegó.
    final porChat = <String, List<WapiEnvioLog>>{};
    for (final l in t.logs) {
      porChat.putIfAbsent(l.chatId, () => []).add(l);
    }
    final entradas = porChat.entries.toList()
      ..sort((a, b) => _nombreChat(a.key).compareTo(_nombreChat(b.key)));

    final d = diag.principal;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Diagnóstico completo ───────────────────────────────────────
          if (d != null) ...[
            _BloqueDiagnostico(
              diagnostico: d,
              totalFallidos: diag.totalFallidos,
              verTecnico: _verDetalleTecnico,
              onToggleTecnico: () =>
                  setState(() => _verDetalleTecnico = !_verDetalleTecnico),
            ),
            const SizedBox(height: 12),
          ] else if (estado == WapiTandaEstado.interrumpida) ...[
            _Aviso(
              color: AppColors.warning,
              icono: Icons.warning_amber_rounded,
              texto: 'El envío se detuvo con ${t.pendientes} mensaje(s) sin '
                  'despachar. Reintenta sólo los que faltan.',
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'DETALLE POR DESTINO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 8),
          ...entradas.map((e) {
            final ls = e.value;
            final ok =
                ls.where((l) => l.estado == WapiEnvioEstado.enviado).length;
            final err =
                ls.where((l) => l.estado == WapiEnvioEstado.fallido).length;
            final pend =
                ls.where((l) => l.estado == WapiEnvioEstado.pendiente).length;
            final completo = ok == ls.length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Icon(
                    e.key.endsWith('@g.us')
                        ? Icons.groups_rounded
                        : Icons.person_rounded,
                    size: 15,
                    color: completo ? AppColors.success : AppColors.textLight,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _nombreChat(e.key),
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$ok/${ls.length}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: completo
                          ? AppColors.success
                          : (err > 0 ? AppColors.error : AppColors.info),
                    ),
                  ),
                  if (pend > 0) ...[
                    const SizedBox(width: 5),
                    Text('· $pend sin enviar',
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textLight)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// ── BLOQUE DE DIAGNÓSTICO ───────────────────────────────────────────────────
/// Explica el problema en tres niveles: titular, qué pasó, qué hacer. El
/// código técnico queda detrás de un desplegable para soporte.
class _BloqueDiagnostico extends StatelessWidget {
  final WapiDiagnostico diagnostico;
  final int totalFallidos;
  final bool verTecnico;
  final VoidCallback onToggleTecnico;

  const _BloqueDiagnostico({
    required this.diagnostico,
    required this.totalFallidos,
    required this.verTecnico,
    required this.onToggleTecnico,
  });

  @override
  Widget build(BuildContext context) {
    final d = diagnostico;
    final encabezado = d.repeticiones > 1
        ? '${d.titulo} · ${d.repeticiones} de $totalFallidos mensaje(s)'
        : d.titulo;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: d.color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: d.color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(d.icono, size: 16, color: d.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  encabezado,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: d.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            d.explicacion,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textPrimary, height: 1.35),
          ),
          if (d.queHacer != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    d.queHacer!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (d.detalle != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onToggleTecnico,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      verTecnico
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      verTecnico
                          ? 'Ocultar detalle técnico'
                          : 'Ver detalle técnico',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (verTecnico)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(
                  d.detalle!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Botón principal "Reintentar N mensajes". El parpadeo va sobre el halo y el
/// fondo, no sobre la opacidad del texto, para que siga siendo legible.
class _BotonReintentar extends StatelessWidget {
  final Animation<double> blink;
  final bool cargando;
  final int pendientes;
  final VoidCallback onTap;

  const _BotonReintentar({
    required this.blink,
    required this.cargando,
    required this.pendientes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const c = AppColors.warning;
    final label = pendientes == 1
        ? 'Reintentar 1 mensaje'
        : 'Reintentar $pendientes mensajes';

    return Tooltip(
      message: cargando
          ? 'Reintentando…'
          : 'Vuelve a enviar los $pendientes mensaje(s) que no se entregaron',
      child: AnimatedBuilder(
        animation: blink,
        builder: (_, __) {
          final b = cargando ? 0.0 : blink.value;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: cargando ? null : onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14 + 0.16 * b),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: c.withOpacity(0.55 + 0.45 * b),
                    width: 1.2,
                  ),
                  boxShadow: b > 0
                      ? [
                          BoxShadow(
                            color: c.withOpacity(0.35 * b),
                            blurRadius: 12 * b,
                            spreadRadius: 0.5 * b,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cargando)
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(c),
                        ),
                      )
                    else
                      const Icon(Icons.replay_rounded, size: 18, color: c),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        cargando ? 'Reintentando…' : label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: c,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EstiloEstado {
  final Color color;
  final IconData icono;
  final String rotulo;
  const _EstiloEstado({
    required this.color,
    required this.icono,
    required this.rotulo,
  });
}

/// Chip contador. Con [animado] el número cambia con una transición vertical,
/// para que se note cuando "sin enviar" baja en vivo.
class _Contador extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String etiqueta;
  final int valor;
  final bool animado;
  const _Contador({
    required this.icono,
    required this.color,
    required this.etiqueta,
    required this.valor,
    this.animado = false,
  });

  @override
  Widget build(BuildContext context) {
    final numero = Text(
      '$valor',
      key: ValueKey(valor),
      style:
          TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 5),
          if (animado)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.6),
                  end: Offset.zero,
                ).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: numero,
            )
          else
            numero,
          const SizedBox(width: 4),
          Text(
            etiqueta,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String texto;
  const _Aviso({
    required this.color,
    required this.icono,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}