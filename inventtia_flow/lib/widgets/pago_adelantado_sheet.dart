import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/cobro.dart';
import '../services/auth_service.dart';
import '../services/cobro_service.dart';
import '../services/imagen_service.dart';
import '../services/suscripcion_service.dart';

/// Hoja del **pago por adelantado** de una reserva, del lado del cliente.
///
/// Es autónoma: se le pasa el [PagoReserva] que ya existe en el servidor (lo crea
/// antes `cliente_crear_pago_reserva`) y, si se tiene, el [CobroInfo] del
/// local-servicio. Con eso resuelve todo el circuito:
///
///   1. Abrir Transfermóvil con el deep link (`url_intent`, con respaldo
///      `url_http`) —el mismo patrón que `mi_suscripcion_screen.dart`— sin
///      `canLaunchUrl` previo, porque en Android 11+ devuelve `false` cuando
///      falta la entrada `<queries>` del manifiesto y abortaría un pago que sí
///      funcionaba.
///   2. «Ya he pagado» → código de confirmación opcional + comprobante opcional
///      → `cliente_reportar_pago_reserva`.
///   3. «Enviar comprobante por WhatsApp» **solo** si el admin configuró un
///      WhatsApp de verificación.
///   4. Estado actual (con el motivo si se rechazó) y cuenta atrás hasta
///      `expira_at`.
///
/// Nada de esto acredita la reserva: si el plazo vence, el servidor la cancela
/// sola (`reserva_pago_expirar`).
class PagoAdelantadoSheet extends StatefulWidget {
  const PagoAdelantadoSheet({
    super.key,
    required this.pago,
    this.info,
    this.onActualizado,
  });

  /// El intento de pago ya creado en el servidor.
  final PagoReserva pago;

  /// Config del cobro del local-servicio, si la pantalla que abre la hoja ya la
  /// consultó. Es la fuente preferida para instrucciones y WhatsApp; el propio
  /// [pago] sirve de respaldo con lo que devolvió `cliente_crear_pago_reserva`.
  final CobroInfo? info;

  /// Se avisa a la pantalla de origen cada vez que el estado cambia (reportado,
  /// verificado, reintentado) para que refresque su propia tarjeta.
  final ValueChanged<PagoReserva>? onActualizado;

  /// Abre la hoja como `showModalBottomSheet`. Es la forma recomendada de usarla
  /// desde una pantalla.
  static Future<void> mostrar(
    BuildContext context, {
    required PagoReserva pago,
    CobroInfo? info,
    ValueChanged<PagoReserva>? onActualizado,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PagoAdelantadoSheet(
        pago: pago,
        info: info,
        onActualizado: onActualizado,
      ),
    );
  }

  @override
  State<PagoAdelantadoSheet> createState() => _PagoAdelantadoSheetState();
}

class _PagoAdelantadoSheetState extends State<PagoAdelantadoSheet>
    with WidgetsBindingObserver {
  late PagoReserva _pago = widget.pago;

  bool _procesando = false;

  /// `true` cuando se lanzó Transfermóvil desde esta hoja. Solo sirve para el
  /// recordatorio de que, al volver, hay que pulsar «Ya he pagado».
  bool _lanzado = false;

  /// Cuenta atrás. Se apaga sola al vencer el plazo.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reiniciarCuentaAtras();
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lanzado && mounted) {
      // Nada de telemetría: solo se reconstruye para que el texto de ayuda
      // refleje que el usuario ya volvió.
      setState(() {});
    }
  }

  void _reiniciarCuentaAtras() {
    _tick?.cancel();
    if (!_pago.esPendiente || _pago.expirado) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_pago.expirado) {
        _tick?.cancel();
      }
      setState(() {});
    });
  }

  // ── Datos resueltos (config primero, pago como respaldo) ─────────────────

  String? get _whatsappVerificacion {
    final deConfig = widget.info?.whatsappVerificacion?.trim();
    if (deConfig != null && deConfig.isNotEmpty) return deConfig;
    final dePago = _pago.whatsappVerificacion?.trim();
    if (dePago != null && dePago.isNotEmpty) return dePago;
    return null;
  }

  String? get _instrucciones {
    final deConfig = widget.info?.instrucciones?.trim();
    if (deConfig != null && deConfig.isNotEmpty) return deConfig;
    final dePago = _pago.instrucciones?.trim();
    if (dePago != null && dePago.isNotEmpty) return dePago;
    return null;
  }

  String get _numeroProveedor {
    if (_pago.numeroProveedor.trim().isNotEmpty) return _pago.numeroProveedor;
    return widget.info?.numeroProveedor ?? '';
  }

  String get _titulo {
    final t = _pago.titulo?.trim();
    if (t != null && t.isNotEmpty) return t;
    final deConfig = widget.info?.titulo.trim();
    return (deConfig == null || deConfig.isEmpty) ? 'Reserva' : deConfig;
  }

  /// Se puede reportar mientras el intento esté vivo (`creado`/`reportado` y
  /// sin plazo vencido). Fuera de ahí solo queda reintentar o esperar.
  bool get _puedeReportar => _pago.puedeReportar;

  // ── Acciones ─────────────────────────────────────────────────────────────

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppTheme.error : AppTheme.primary,
        duration: Duration(seconds: esError ? 5 : 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Lanza Transfermóvil con el deep link y, si falla, con el respaldo https.
  Future<void> _abrirTransfermovil() async {
    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(_pago.urlIntent),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }

    if (!abierto) {
      final http = _pago.urlHttp;
      if (http != null && http.isNotEmpty) {
        try {
          abierto = await launchUrl(
            Uri.parse(http),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          abierto = false;
        }
      }
    }

    if (!mounted) return;

    if (abierto) {
      setState(() => _lanzado = true);
    } else {
      _mostrarDatosParaPagoManual();
    }
  }

  /// Sin app instalada no se deja al usuario sin salida: se le dan los datos
  /// para pagar a mano desde el banco (o desde otro teléfono).
  void _mostrarDatosParaPagoManual() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No se pudo abrir Transfermóvil',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Haz la transferencia con estos datos y luego pulsa "Ya he '
                'pagado" para avisar al administrador.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              _DatoCopiable(
                etiqueta: 'Importe',
                valor: '${_pago.importeTransfermovil} ${_pago.moneda}',
              ),
              _DatoCopiable(
                etiqueta: 'Número del comercio',
                valor: _numeroProveedor.isEmpty ? '—' : _numeroProveedor,
              ),
              _DatoCopiable(etiqueta: 'Título', valor: _titulo),
              if (_pago.idTransaccion != null)
                _DatoCopiable(
                  etiqueta: 'Referencia',
                  valor: _pago.idTransaccion!,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Paso 3: «Ya he pagado» → código de confirmación y comprobante opcionales.
  Future<void> _yaHePagado() async {
    final resultado = await showDialog<_DatosReporte>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoReportarPago(
        importe: '${_pago.importeTransfermovil} ${_pago.moneda}',
        codigoInicial: _pago.codigoConfirmacion,
      ),
    );
    if (resultado == null || !mounted) return;

    setState(() => _procesando = true);
    try {
      await CobroService.reportarPago(
        idPago: _pago.id,
        codigo: resultado.codigo,
        comprobanteUrl: resultado.comprobanteUrl,
      );
      if (!mounted) return;
      final actualizado = _pago.copyWith(
        estado: 'reportado',
        codigoConfirmacion: resultado.codigo,
        comprobanteUrl: resultado.comprobanteUrl,
        reportadoAt: DateTime.now(),
      );
      setState(() {
        _pago = actualizado;
        _procesando = false;
      });
      widget.onActualizado?.call(actualizado);
      _reiniciarCuentaAtras();
      _avisar(
        'Pago reportado. El administrador lo verificará y te avisaremos.',
        esError: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _avisar(_mensaje(e), esError: true);
    }
  }

  /// Refresca el estado contra el servidor (el admin puede haber decidido ya).
  Future<void> _refrescar() async {
    setState(() => _procesando = true);
    try {
      final actual = await CobroService.pagoDeReserva(_pago.idAgenda);
      if (!mounted) return;
      setState(() {
        if (actual != null) _pago = actual;
        _procesando = false;
      });
      if (actual != null) widget.onActualizado?.call(actual);
      _reiniciarCuentaAtras();
      if (actual == null) {
        _avisar('Este pago ya no existe en el servidor.', esError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _avisar(_mensaje(e), esError: true);
    }
  }

  /// Reintenta el pago cuando el anterior se rechazó o caducó: crea un intento
  /// nuevo con el mismo circuito.
  Future<void> _reintentar() async {
    setState(() => _procesando = true);
    try {
      final nuevo = await CobroService.crearPago(_pago.idAgenda);
      if (!mounted) return;
      setState(() {
        _pago = nuevo;
        _lanzado = false;
        _procesando = false;
      });
      widget.onActualizado?.call(nuevo);
      _reiniciarCuentaAtras();
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _avisar(_mensaje(e), esError: true);
    }
  }

  /// Manda el comprobante al WhatsApp de verificación del admin.
  Future<void> _enviarComprobante() async {
    final numero = _whatsappVerificacion;
    if (numero == null) return;

    final mensaje =
        'Hola, he pagado por adelantado ${_pago.importeTransfermovil} '
        '${_pago.moneda} de mi reserva ($_titulo). '
        '${_pago.codigoConfirmacion == null ? '' : 'Código de confirmación: ${_pago.codigoConfirmacion}. '}'
        '${_pago.idTransaccion == null ? '' : 'Referencia: ${_pago.idTransaccion}.'}';

    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(SuscripcionService.urlWhatsapp(numero, mensaje)),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }
    if (!mounted || abierto) return;

    // Sin WhatsApp instalado queda el mensaje copiado y el número a la vista.
    await Clipboard.setData(ClipboardData(text: mensaje));
    if (!mounted) return;
    _avisar(
      'No se pudo abrir WhatsApp. Copiamos el mensaje: envíalo al '
      '${SuscripcionService.normalizarTelefono(numero)}.',
      esError: false,
    );
  }

  String _mensaje(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '').trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + viewInsets),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _cabecera(),
              const SizedBox(height: 14),
              if (_pago.verificado)
                _tarjetaVerificado()
              else ...[
                _tarjetaImporte(),
                if (_instrucciones != null) ...[
                  const SizedBox(height: 12),
                  _tarjetaInstrucciones(_instrucciones!),
                ],
                const SizedBox(height: 12),
                _tarjetaEstado(),
                const SizedBox(height: 16),
                ..._acciones(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Row(
      children: [
        const Icon(Icons.payments_outlined, color: AppTheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Pago por adelantado',
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (_procesando)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            tooltip: 'Actualizar estado',
            onPressed: _refrescar,
            icon: const Icon(Icons.refresh, size: 20),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _tarjetaImporte() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Importe a pagar',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            _pago.montoEtiqueta,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _DatoCopiable(
            etiqueta: 'Número del comercio',
            valor: _numeroProveedor.isEmpty ? '—' : _numeroProveedor,
          ),
          if (_pago.idTransaccion != null)
            _DatoCopiable(etiqueta: 'Referencia', valor: _pago.idTransaccion!),
        ],
      ),
    );
  }

  Widget _tarjetaInstrucciones(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.campaign_outlined, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'Instrucciones del administrador',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Estado actual del pago, con el motivo si se rechazó y la cuenta atrás.
  Widget _tarjetaEstado() {
    final color = _colorEstado;
    final texto = _textoEstado;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconoEstado, size: 19, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (_pago.motivoRechazo != null && _pago.rechazado) ...[
            const SizedBox(height: 6),
            Text(
              'Motivo: ${_pago.motivoRechazo}',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (_pago.esPendiente &&
              !_pago.expirado &&
              _pago.expiraAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Tiempo restante para pagar y reportar: ${_pago.restanteEtiqueta}.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (_pago.expirado && !_pago.verificado) ...[
            const SizedBox(height: 6),
            const Text(
              'El plazo venció. Si la entidad lo configuró así, la reserva se '
              'canceló sola. Puedes intentar un pago nuevo si la reserva sigue '
              'activa.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaVerificado() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_outlined, color: AppTheme.success, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pago verificado',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'El administrador confirmó el pago de ${_pago.montoEtiqueta}. '
            'Tu reserva está confirmada; no tienes nada más que hacer.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _acciones() {
    final sinAcciones = !_puedeReportar;

    if (_pago.rechazado || sinAcciones) {
      return [
        if (_pago.rechazado)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Puedes intentarlo otra vez: se creará un intento de pago nuevo.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _procesando ? null : _reintentar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar el pago'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ];
    }

    return [
      const Text(
        'Paso 1: abre Transfermóvil y paga el importe.\n'
        'Paso 2: al volver aquí, pulsa "Ya he pagado" para avisar al '
        'administrador.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: AppTheme.textSecondary,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _procesando ? null : _abrirTransfermovil,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Abrir Transfermóvil'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _procesando ? null : _yaHePagado,
          icon: _procesando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Ya he pagado'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
      if (_lanzado && _pago.estado == 'creado')
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Si ya pagaste en Transfermóvil, pulsa "Ya he pagado" para avisar '
            'al administrador.',
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      if (_pago.esReportado) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _procesando ? null : _refrescar,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Actualizar estado'),
          ),
        ),
      ],
      // El botón de WhatsApp SOLO aparece si el admin dejó un WhatsApp de
      // verificación: sin número no hay a quién mandarle el comprobante.
      if (_whatsappVerificacion != null) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _procesando ? null : _enviarComprobante,
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('Enviar comprobante por WhatsApp'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF128C7E),
              side: const BorderSide(color: Color(0xFF25D366)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    ];
  }

  Color get _colorEstado {
    if (_pago.verificado) return AppTheme.success;
    if (_pago.rechazado) return AppTheme.error;
    if (_pago.expirado) return AppTheme.error;
    if (_pago.esReportado) return AppTheme.primary;
    return AppTheme.warning;
  }

  IconData get _iconoEstado {
    if (_pago.verificado) return Icons.verified_outlined;
    if (_pago.rechazado) return Icons.cancel_outlined;
    if (_pago.expirado) return Icons.timer_off_outlined;
    if (_pago.esReportado) return Icons.hourglass_top;
    return Icons.schedule;
  }

  String get _textoEstado {
    if (_pago.expirado && _pago.estado != 'expirado') {
      return 'El plazo del pago venció';
    }
    return _pago.etiquetaEstado;
  }
}

// ─────────────────────────────── Piezas de UI ──────────────────────────────

/// Dato con botón de copiar: el número del comercio y la referencia se copian a
/// mano en Transfermóvil cuando el deep link no abre.
class _DatoCopiable extends StatelessWidget {
  const _DatoCopiable({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: valor));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copiado: $valor'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, size: 16, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Diálogo «Ya he pagado» ──────────────────────────

class _DatosReporte {
  const _DatosReporte({this.codigo, this.comprobanteUrl});

  final String? codigo;
  final String? comprobanteUrl;
}

/// Código de confirmación **opcional** (Transfermóvil a veces no lo da antes de
/// verificar) y comprobante opcional, igual que en la suscripción.
class _DialogoReportarPago extends StatefulWidget {
  const _DialogoReportarPago({required this.importe, this.codigoInicial});

  final String importe;
  final String? codigoInicial;

  @override
  State<_DialogoReportarPago> createState() => _DialogoReportarPagoState();
}

class _DialogoReportarPagoState extends State<_DialogoReportarPago> {
  late final TextEditingController _codigo = TextEditingController(
    text: widget.codigoInicial ?? '',
  );
  String? _comprobanteUrl;
  bool _subiendo = false;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _adjuntarComprobante() async {
    try {
      final imagen = await ImagenService.seleccionarImagen();
      if (imagen == null) return;

      setState(() => _subiendo = true);

      // El primer segmento del path es el uuid: la política de borrado del
      // bucket solo deja tocar lo que empieza por el id del que subió.
      final uuid = AuthService.currentUserId;
      if (uuid == null) {
        if (mounted) setState(() => _subiendo = false);
        return;
      }

      final url = await ImagenService.subirImagen(
        imagen: imagen,
        path: '$uuid/pagos/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!mounted) return;
      setState(() {
        _comprobanteUrl = url;
        _subiendo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _subiendo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo subir el comprobante. Puedes enviarlo por WhatsApp.',
          ),
        ),
      );
    }
  }

  void _enviar() {
    final codigo = _codigo.text.trim();
    Navigator.of(context).pop(
      _DatosReporte(
        codigo: codigo.isEmpty ? null : codigo,
        comprobanteUrl: _comprobanteUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppTheme.success),
          SizedBox(width: 8),
          Expanded(child: Text('Ya he pagado', style: TextStyle(fontSize: 16))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirma que pagaste ${widget.importe} por Transfermóvil. El '
              'administrador comprobará el pago antes de confirmar tu reserva.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _codigo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Número de confirmación (opcional)',
                helperText: 'Aparece en Transfermóvil al terminar el pago',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _subiendo ? null : _adjuntarComprobante,
                  icon: _subiendo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _comprobanteUrl == null
                              ? Icons.add_photo_alternate_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                        ),
                  label: Text(
                    _comprobanteUrl == null
                        ? 'Adjuntar comprobante (opcional)'
                        : 'Comprobante adjunto',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _comprobanteUrl == null
                        ? AppTheme.primary
                        : AppTheme.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _subiendo ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _subiendo ? null : _enviar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
