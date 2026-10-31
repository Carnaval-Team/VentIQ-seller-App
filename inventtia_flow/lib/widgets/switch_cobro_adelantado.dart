import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/catalogo_service.dart';
import '../services/cobro_service.dart';

/// Interruptor del «pago por adelantado» de UN servicio, con guardado inmediato.
///
/// POR QUE EXISTE (y por que no es un `SwitchListTile` suelto)
///
///   El mismo ajuste se ofrece en tres sitios —el formulario de alta/edicion y
///   las pestanas «Configuracion» y «Precios» del par local-servicio— y los tres
///   tienen que decir lo mismo. Dos trampas que concentra este widget:
///
///   1. **El `Servicio` que llega a la pantalla puede traer el flag MAL.** El
///      listado del local se lee con `flow.cliente_obtener_servicios`, un payload
///      pensado para el CLIENTE que **no incluye `cobro_adelantado`** (migracion
///      67: se anadio la columna pero no el campo del payload). `Servicio.fromJson`
///      lo deja en `false` y la pantalla ensenaria un interruptor apagado sobre
///      un servicio que si cobra; al guardar, se escribiria ese `false` y el
///      cobro se apagaria en silencio. Por eso el host tiene que pasar un valor
///      fresco (`CatalogoService.getServicio`, que si trae la columna) y por eso
///      este widget avisa al host con [onGuardado] para que refresque su copia.
///   2. **El interruptor maestro manda.** `flow.cobro_config.activo` (entidad) y
///      `cobro_adelantado` (servicio) se exigen LOS DOS en el servidor
///      (`cliente_cobro_info`). Con el maestro apagado el flag se puede marcar,
///      pero no se ofrece al cliente: hay que decirlo, no esconderlo.
///
///   Guarda al instante (como los demas interruptores de «Configuracion») porque
///   es una sola casilla: obligar a pulsar «Guardar» en una pestana que no
///   tiene boton seria peor. La escritura va por [CatalogoService.setCobroAdelantado],
///   que ahora falla si el servidor no actualiza la fila (antes era un no-op
///   silencioso cuando la RLS no casaba).
class SwitchCobroAdelantado extends StatefulWidget {
  const SwitchCobroAdelantado({
    super.key,
    required this.idServicio,
    required this.idEntidad,
    required this.valorInicial,
    this.onGuardado,
  });

  /// Servicio cuyo flag se edita.
  final int idServicio;

  /// Entidad duena del servicio: de ella sale el interruptor maestro.
  final int idEntidad;

  /// Valor **fresco** del flag (idealmente leido de `app_dat_servicios`).
  final bool valorInicial;

  /// Se llama con el valor YA persistido, para que el host refresque su copia
  /// del servicio (las demas pestanas y el formulario pintan ese dato).
  final ValueChanged<bool>? onGuardado;

  @override
  State<SwitchCobroAdelantado> createState() => _SwitchCobroAdelantadoState();
}

class _SwitchCobroAdelantadoState extends State<SwitchCobroAdelantado> {
  late bool _activo;

  /// `null` = todavia no se sabe: leyendo, o la lectura fallo (sin migracion
  /// 62, sin permisos, sin red). Nunca se bloquea la pantalla por esto.
  bool? _maestroActivo;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _activo = widget.valorInicial;
    _cargarMaestro();
  }

  @override
  void didUpdateWidget(covariant SwitchCobroAdelantado oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El host relee el par despues de guardar (o de cambiar algo en otra
    // pestana). Mientras no haya una escritura en vuelo, manda la copia del
    // host: es la que viene de la base.
    if (!_guardando && oldWidget.valorInicial != widget.valorInicial) {
      _activo = widget.valorInicial;
    }
  }

  /// Lee el interruptor maestro de la entidad, solo para poder explicarlo.
  Future<void> _cargarMaestro() async {
    bool? activo;
    try {
      activo = (await CobroService.configGet(widget.idEntidad)).activo;
    } catch (_) {
      activo = null;
    }
    if (!mounted) return;
    setState(() => _maestroActivo = activo);
  }

  Future<void> _cambiar(bool valor) async {
    if (_guardando || valor == _activo) return;
    final anterior = _activo;
    // Optimista: el switch responde al toque y, si el guardado falla, se
    // revierte con el aviso. Asi no se queda un boton muerto mientras escribe.
    setState(() {
      _guardando = true;
      _activo = valor;
    });
    try {
      await CatalogoService.setCobroAdelantado(
        id: widget.idServicio,
        activo: valor,
      );
      if (!mounted) return;
      widget.onGuardado?.call(valor);
      _avisar(
        valor
            ? 'Pago por adelantado activado para este servicio'
            : 'Pago por adelantado desactivado para este servicio',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _activo = anterior);
      _avisar(
        'No se pudo guardar el pago por adelantado: '
        '${'$e'.replaceFirst('Exception: ', '')}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: error ? AppTheme.error : AppTheme.success,
        ),
      );
  }

  /// Explicacion bajo el interruptor: que pasa de verdad al activarlo.
  String get _subtitulo {
    if (_maestroActivo == false) {
      return 'La entidad tiene el pago por adelantado apagado: este servicio '
          'quedara marcado, pero no se ofrecera al cliente hasta que lo actives '
          'en «Mi suscripcion → Cobro por adelantado».';
    }
    if (_activo) {
      return 'El cliente podra pagar este servicio con Transfermovil antes de '
          'la cita. Se ofrece en todos los locales donde este el servicio.';
    }
    return 'El cliente no vera la opcion de pagar por adelantado en este '
        'servicio.';
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _activo,
      // Se bloquea solo mientras escribe, para que dos toques seguidos no
      // manden dos updates en carreras.
      onChanged: _guardando ? null : _cambiar,
      secondary: _guardando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _activo ? Icons.payments_outlined : Icons.money_off_outlined,
              color: _activo ? AppTheme.success : AppTheme.textSecondary,
            ),
      title: const Text('Pago por adelantado en linea'),
      subtitle: Text(
        _subtitulo,
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    );
  }
}