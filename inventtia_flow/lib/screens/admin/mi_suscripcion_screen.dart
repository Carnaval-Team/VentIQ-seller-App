import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/suscripcion.dart';
import '../../providers/suscripcion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/imagen_service.dart';
import '../../services/suscripcion_service.dart';

/// Pantalla "Mi suscripción": estado, planes, pago por Transfermóvil e historial.
///
/// El circuito del pago tiene tres pasos y **ninguno acredita tiempo**:
///
///   1. Elegir plan → `cliente_crear_intent_suscripcion` devuelve un
///      `id_transaccion` único y el deep link de Transfermóvil.
///   2. Abrir Transfermóvil y pagar. La app **no recibe callback** — el deep link
///      no devuelve resultado —, así que se detecta el regreso observando el
///      ciclo de vida: cuando la app vuelve a primer plano aparece el botón
///      "Ya he pagado".
///   3. "Ya he pagado" → código de confirmación + comprobante opcional
///      (`cliente_reportar_pago_suscripcion`) y mensaje a soporte por WhatsApp.
///
/// Quien acredita es el superadmin, verificando el pago en el banco. No existe
/// ningún camino en la app que active una suscripción: eso es a propósito.
class MiSuscripcionScreen extends StatefulWidget {
  const MiSuscripcionScreen({super.key});

  @override
  State<MiSuscripcionScreen> createState() => _MiSuscripcionScreenState();
}

class _MiSuscripcionScreenState extends State<MiSuscripcionScreen>
    with WidgetsBindingObserver {
  /// Intent que se acaba de crear y con el que se salió a Transfermóvil.
  IntentPagoCreado? _intentActual;

  /// `true` una vez que se lanzó Transfermóvil. Sin esto, volver de cualquier
  /// otra app mostraría el botón "Ya he pagado" sin haber pagado nada.
  bool _lanzado = false;

  /// `true` cuando la app volvió a primer plano después de lanzar Transfermóvil.
  bool _volvioDeTransfermovil = false;

  /// El intent está en curso: se atenúa el resto de la pantalla para que no se
  /// generen dos pagos de la misma suscripción.
  bool _pagoEnCurso = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Forzado: al entrar aquí el usuario quiere el dato de ahora, no el de la
      // carga inicial del shell.
      context.read<SuscripcionProvider>().recargar();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Transfermóvil no avisa cuando termina el pago: el único indicio de que el
  /// usuario volvió es que la app recupera el primer plano. Es exactamente lo que
  /// hace la app de Carnaval, y la razón de que el botón "Ya he pagado" se
  /// muestre aquí y no antes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_lanzado || _volvioDeTransfermovil || !mounted) return;

    setState(() => _volvioDeTransfermovil = true);

    final id = _intentActual?.intent.id;
    if (id != null) {
      // Telemetría del embudo del panel: no cambia ningún derecho.
      SuscripcionService.marcarIntentAbierto(id);
    }
  }

  /// El botón del paso 2 solo aparece cuando la app volvió a primer plano después
  /// de lanzar Transfermóvil.
  ///
  /// No se puede averiguar por el estado del intent: el RPC que lo crea no
  /// devuelve `estado` (nace `creado`), y Transfermóvil no avisa de nada. Lo
  /// único que se sabe con certeza es que el usuario salió y volvió.
  ///
  /// El caso de cerrar la app entre el pago y el reporte lo cubre la tarjeta de
  /// "pago sin terminar", que reanuda el intent que quedó vivo en el servidor.
  bool get _mostrarBotonYaHePagado =>
      _intentActual != null && _volvioDeTransfermovil;

  Future<void> _elegirPlan(PlanSuscripcion plan) async {
    final provider = context.read<SuscripcionProvider>();

    setState(() => _pagoEnCurso = true);
    final res = await provider.crearIntent(plan.id);
    if (!mounted) return;
    setState(() => _pagoEnCurso = false);

    if (!res.ok) {
      _avisar(res.mensajeError ?? 'No se pudo preparar el pago', esError: true);
      return;
    }

    final creado = res.data!;
    setState(() {
      _intentActual = creado;
      _lanzado = false;
      _volvioDeTransfermovil = false;
    });

    // Se abre directamente: el usuario ya eligió el plan, pedirle un toque extra
    // solo añade un paso donde abandonar.
    await _abrirTransfermovil();
  }

  /// Lanza Transfermóvil con el deep link del intent.
  ///
  /// Primero el esquema propio de la app (`transfermovil://`), que abre la
  /// pantalla de pago ya rellena. Si el dispositivo no lo tiene registrado se
  /// intenta el respaldo https. Lo que **no** se hace es `canLaunchUrl` antes:
  /// en Android 11+ devuelve `false` si falta la entrada `<queries>` del
  /// manifiesto, y eso abortaría un pago que sí funcionaba. Se intenta lanzar y
  /// se reacciona al resultado.
  Future<void> _abrirTransfermovil() async {
    final intent = _intentActual;
    if (intent == null) return;

    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(intent.intent.urlIntent),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }

    if (!abierto) {
      final http = intent.intent.urlHttp;
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
      // Sin app instalada: se muestran los datos para pagar a mano desde el
      // banco (o desde otro teléfono) en vez de dejar al usuario sin salida.
      _mostrarDatosParaPagoManual(intent);
    }
  }

  void _mostrarDatosParaPagoManual(IntentPagoCreado intent) {
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
                'Haz la transferencia con estos datos y luego pulsa "Ya he pagado" '
                'para enviar el comprobante a soporte.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              _DatoCopiable(
                etiqueta: 'Importe',
                valor: '${intent.importe} ${intent.intent.moneda}',
              ),
              _DatoCopiable(
                etiqueta: 'Número del comercio',
                valor: intent.numeroProveedor,
              ),
              _DatoCopiable(etiqueta: 'Título', valor: intent.titulo),
              _DatoCopiable(
                etiqueta: 'Referencia de soporte',
                valor: intent.idTransaccion,
              ),
              const SizedBox(height: 14),
              // Bug de la app de Transfermovil: muestra "ESTATICO" como id de la
              // transaccion aunque el link lleve otro. Se avisa para que el
              // cliente no piense que pago mal, y se le recuerda que el dato que
              // SI tiene que cuadrar es el importe.
              const Text(
                'Transfermóvil mostrará "ESTATICO" como id de la transacción: '
                'es un fallo de su app. Verifica que el importe sea el de arriba '
                'antes de pagar.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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

  /// Reabre Transfermóvil con un intent que ya existía en el servidor.
  ///
  /// Se distingue de [_abrirTransfermovil] en que aquí no se toca `_lanzado`: este
  /// intento ya está en curso y la tarjeta muestra el botón "Ya he pagado" desde
  /// el principio, así que no hace falta esperar a que la app vuelva a primer
  /// plano para revelarlo.
  ///
  /// Si no se puede abrir nada, el aviso lleva la referencia de soporte: es lo
  /// que soporte le pedira para localizar el intento en el panel.
  Future<void> _abrirIntentGuardado(IntentSuscripcion intent) async {
    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(intent.urlIntent),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }

    final http = intent.urlHttp;
    if (!abierto && http != null && http.isNotEmpty) {
      try {
        abierto = await launchUrl(
          Uri.parse(http),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        abierto = false;
      }
    }

    if (!abierto && mounted) {
      _avisar(
        'No se pudo abrir Transfermóvil. Paga el importe y pulsa "Ya he '
        'pagado". Referencia para soporte: ${intent.idTransaccion}.',
        esError: true,
      );
    }
  }

  /// Paso 3: "Ya he pagado".
  ///
  /// Recibe el intent y el importe explícitamente en vez de leerlos de
  /// `_intentActual` porque el mismo diálogo sirve para dos caminos: el intent que
  /// se acaba de crear en esta pantalla y el que quedó vivo en el servidor cuando
  /// el usuario cerró la app después de pagar.
  ///
  /// El código de confirmación es obligatorio y único en la base: es la única
  /// defensa contra acreditar dos veces el mismo pago. Por eso el diálogo no
  /// deja enviar sin él.
  Future<void> _yaHePagado({
    required int idIntent,
    required String importe,
    required String moneda,
  }) async {
    final resultado = await showDialog<_DatosReporte>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogoReportarPago(importe: importe, moneda: moneda),
    );

    if (resultado == null || !mounted) return;

    final provider = context.read<SuscripcionProvider>();

    setState(() => _pagoEnCurso = true);
    final res = await provider.reportarPago(
      idIntent: idIntent,
      codigoConfirmacion: resultado.codigo,
      comprobanteUrl: resultado.comprobanteUrl,
    );
    if (!mounted) return;
    setState(() => _pagoEnCurso = false);

    if (!res.ok) {
      _avisar(
        res.mensajeError ?? 'No se pudo registrar el pago',
        esError: true,
      );
      return;
    }

    final reporte = res.data!;
    setState(() {
      // El pago ya está reportado: se cierra el paso de pago de esta pantalla y
      // se deja el estado en "esperando verificación".
      _intentActual = null;
      _lanzado = false;
      _volvioDeTransfermovil = false;
    });

    await _avisarPagoReportado(reporte);
  }

  /// Confirma el reporte y ofrece mandar el mensaje a soporte por WhatsApp.
  Future<void> _avisarPagoReportado(ReportePago reporte) async {
    if (!mounted) return;

    final quiereEscribir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.success),
            SizedBox(width: 8),
            Expanded(
              child: Text('Pago reportado', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: const Text(
          'Soporte verificará tu pago y acreditará el tiempo del plan. Te '
          'avisaremos aquí en cuanto esté acreditado.\n\n'
          '¿Quieres enviar el comprobante a soporte por WhatsApp? Es la vía más '
          'rápida para que lo revisen.',
          style: TextStyle(fontSize: 13.5, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Más tarde'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('Escribir a soporte'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (quiereEscribir == true) {
      await _escribirSoporte(reporte.soporteWhatsapp, reporte.mensajeSoporte);
    }
  }

  /// Abre WhatsApp con el mensaje ya redactado **por el servidor**.
  ///
  /// El texto viene del RPC a propósito: dice el nombre, el plan, la entidad, el
  /// importe, la referencia de soporte y el código de confirmación. Redactarlo en la
  /// app sería duplicar el formato en dos sitios y acabarían discrepando.
  Future<void> _escribirSoporte(String numero, String mensaje) async {
    final url = SuscripcionService.urlWhatsapp(numero, mensaje);
    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }
    if (!mounted || abierto) return;

    // Sin WhatsApp instalado queda el número y el texto, para mandarlo por otra
    // vía. Se copia el mensaje al portapapeles para que sea un solo gesto.
    await Clipboard.setData(ClipboardData(text: mensaje));
    if (!mounted) return;
    _avisar(
      'No se pudo abrir WhatsApp. Copiamos el mensaje: envíalo al ${SuscripcionService.normalizarTelefono(numero)}.',
      esError: false,
    );
  }

  void _avisar(String mensaje, {required bool esError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppTheme.error : AppTheme.primary,
        duration: Duration(seconds: esError ? 5 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuscripcionProvider>();
    final estado = provider.estado;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Mi suscripción'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: provider.cargando ? null : () => provider.recargar(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.recargar(),
        child: _cuerpo(provider, estado),
      ),
    );
  }

  Widget _cuerpo(
    SuscripcionProvider provider,
    EstadoSuscripcionEntidad? estado,
  ) {
    if (provider.esquemaPendiente) {
      return _mensajeCentral(
        icono: Icons.construction,
        titulo: 'Función no disponible',
        texto:
            'El módulo de suscripciones todavía no está activo en el servidor. '
            'Vuelve a intentarlo más tarde.',
      );
    }

    if (estado == null) {
      if (provider.cargando) {
        return const Center(child: CircularProgressIndicator());
      }
      return _mensajeCentral(
        icono: Icons.cloud_off,
        titulo: 'No se pudo cargar',
        texto: provider.error ?? 'Revisa tu conexión e inténtalo de nuevo.',
        accion: TextButton(
          onPressed: () => provider.recargar(),
          child: const Text('Reintentar'),
        ),
      );
    }

    final pagos = provider.miSuscripcion.pagos;
    final pendiente = provider.miSuscripcion.pagoPendiente;

    // Un intent que quedó vivo en el servidor: el usuario pagó y cerró la app
    // antes de reportarlo, o salió de la pantalla. Se reanuda en vez de dejarle
    // crear otro, que es lo que haría sin esta tarjeta.
    final intentGuardado = _intentActual == null
        ? provider.miSuscripcion.intentVigente
        : null;

    // El servidor devuelve los pagos del más reciente al más antiguo, así que el
    // primero es el último intento. Si se rechazó y no hay otro en curso, hay que
    // decir por qué: sin el motivo el cliente vuelve a reportar lo mismo.
    final rechazado =
        pendiente == null &&
            pagos.isNotEmpty &&
            pagos.first.estado == 'rechazado'
        ? pagos.first
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _TarjetaEstado(estado: estado),

        if (estado.mostrarAvisoImpago) ...[
          const SizedBox(height: 12),
          _TarjetaBloqueo(estado: estado),
        ],

        if (rechazado != null) ...[
          const SizedBox(height: 12),
          _TarjetaPagoRechazado(pago: rechazado),
        ],

        if (pendiente != null) ...[
          const SizedBox(height: 12),
          _TarjetaVerificacionPendiente(pago: pendiente),
        ] else ...[
          const SizedBox(height: 18),
          const _TituloSeccion(
            titulo: 'Planes',
            subtitulo:
                'Elige el tiempo que quieres mantener activa tu entidad.',
          ),
          const SizedBox(height: 8),
          if (_intentActual != null)
            _TarjetaPagoEnCurso(
              intent: _intentActual!,
              mostrarYaHePagado: _mostrarBotonYaHePagado,
              procesando: _pagoEnCurso,
              onAbrirTransfermovil: _abrirTransfermovil,
              onYaHePagado: () => _yaHePagado(
                idIntent: _intentActual!.intent.id,
                importe: _intentActual!.importe,
                moneda: _intentActual!.intent.moneda,
              ),
              onCancelar: () => setState(() {
                _intentActual = null;
                _lanzado = false;
                _volvioDeTransfermovil = false;
              }),
            )
          else if (intentGuardado != null)
            _TarjetaIntentGuardado(
              intent: intentGuardado,
              procesando: _pagoEnCurso,
              onAbrirTransfermovil: () => _abrirIntentGuardado(intentGuardado),
              onYaHePagado: () => _yaHePagado(
                idIntent: intentGuardado.id,
                importe: intentGuardado.monto.toStringAsFixed(2),
                moneda: intentGuardado.moneda,
              ),
            )
          else if (_pagoEnCurso)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (provider.planes.isEmpty)
            const _Aviso(
              texto:
                  'Todavía no hay planes publicados. El administrador tiene que '
                  'poner precio y activarlos.',
            )
          else
            ...provider.planes.map(
              (p) => _TarjetaPlan(plan: p, onPagar: () => _elegirPlan(p)),
            ),
        ],

        const SizedBox(height: 22),
        const _TituloSeccion(titulo: 'Historial'),
        const SizedBox(height: 8),
        _Historial(
          movimientos: provider.miSuscripcion.movimientos,
          pagos: pagos,
        ),
      ],
    );
  }

  Widget _mensajeCentral({
    required IconData icono,
    required String titulo,
    required String texto,
    Widget? accion,
  }) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 40),
        Icon(icono, size: 46, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppTheme.textSecondary,
            height: 1.35,
          ),
        ),
        if (accion != null) ...[
          const SizedBox(height: 10),
          Center(child: accion),
        ],
      ],
    );
  }
}

// ─────────────────────────────── Piezas de UI ──────────────────────────────

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({required this.titulo, this.subtitulo});

  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo!,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Estado actual: plan, vencimiento y cuenta atrás.
class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({required this.estado});

  final EstadoSuscripcionEntidad estado;

  Color get _color {
    if (!estado.activa) return AppTheme.error;
    switch (estado.estado) {
      case EstadoSuscripcion.enGracia:
        return AppTheme.warning;
      case EstadoSuscripcion.trial:
        return AppTheme.primary;
      default:
        return AppTheme.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vencimiento = estado.fechaVencimiento;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  estado.planNombre ?? 'Sin plan',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado.estado.etiqueta,
                  style: TextStyle(
                    color: _color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (estado.mensaje != null) ...[
            const SizedBox(height: 8),
            Text(
              estado.mensaje!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Dato(
                  etiqueta: 'Vence',
                  valor: vencimiento == null ? '—' : _fechaCorta(vencimiento),
                ),
              ),
              Expanded(
                child: _Dato(
                  etiqueta: 'Días restantes',
                  valor: estado.diasRestantes == null
                      ? '—'
                      : '${estado.diasRestantes}',
                ),
              ),
              if (estado.estado == EstadoSuscripcion.enGracia)
                Expanded(
                  child: _Dato(
                    etiqueta: 'Margen',
                    valor: estado.diasGracia == null
                        ? '—'
                        : '${estado.diasGracia} días',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explica qué deja de funcionar mientras no se pague.
///
/// El requisito es que el impago se vea, pero solo con el rótulo el admin no
/// sabe qué consecuencias tiene: aquí se dice explícitamente que los locales y
/// los servicios dejan de mostrarse y que no entran reservas.
class _TarjetaBloqueo extends StatelessWidget {
  const _TarjetaBloqueo({required this.estado});

  final EstadoSuscripcionEntidad estado;

  @override
  Widget build(BuildContext context) {
    final esSuspension = estado.estado == EstadoSuscripcion.suspendida;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_gmailerrorred, color: AppTheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  esSuspension
                      ? 'Tu entidad está suspendida'
                      : 'No has pagado la suscripción',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Mientras la suscripción esté así, tu entidad no se muestra en '
                  'la app y sus locales y servicios no aparecen ni admiten '
                  'reservas. Tus datos y tus reservas anteriores se conservan: al '
                  'acreditar el pago todo vuelve a publicarse.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaVerificacionPendiente extends StatelessWidget {
  const _TarjetaVerificacionPendiente({required this.pago});

  final PagoSuscripcion pago;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_top, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Pago reportado, esperando verificación',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Soporte está comprobando el pago de ${pago.montoEtiqueta}'
            '${pago.codigoConfirmacion == null ? '' : ' (confirmación ${pago.codigoConfirmacion})'}. '
            'En cuanto lo acrediten, tu entidad vuelve a estar activa y te llega '
            'un aviso.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pago rechazado: se muestra el motivo para que el cliente pueda corregirlo.
///
/// Sin este aviso el pago rechazado solo aparecería en el historial, y el cliente
/// volvería a reportar el mismo código pensando que no llegó.
class _TarjetaPagoRechazado extends StatelessWidget {
  const _TarjetaPagoRechazado({required this.pago});

  final PagoSuscripcion pago;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cancel_outlined, color: AppTheme.error, size: 20),
              SizedBox(width: 8),
              Text(
                'No pudimos verificar tu pago',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pago.observaciones?.trim().isNotEmpty == true
                ? 'Motivo: ${pago.observaciones}'
                : 'Soporte no pudo comprobar el pago. Revisa el número de '
                      'confirmación y vuelve a reportarlo, o escribe a soporte si '
                      'crees que es un error.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paso 1 y 2 del circuito: los datos de la transferencia y el botón que solo
/// aparece después de volver de Transfermóvil.
class _TarjetaPagoEnCurso extends StatelessWidget {
  const _TarjetaPagoEnCurso({
    required this.intent,
    required this.mostrarYaHePagado,
    required this.procesando,
    required this.onAbrirTransfermovil,
    required this.onYaHePagado,
    required this.onCancelar,
  });

  final IntentPagoCreado intent;
  final bool mostrarYaHePagado;
  final bool procesando;
  final VoidCallback onAbrirTransfermovil;
  final VoidCallback onYaHePagado;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pago por Transfermóvil',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (intent.modoPrueba)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'MODO PRUEBA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _DatoCopiable(
            etiqueta: 'Importe',
            valor: '${intent.importe} ${intent.intent.moneda}',
          ),
          _DatoCopiable(
            etiqueta: 'Número del comercio',
            valor: intent.numeroProveedor,
          ),
          _DatoCopiable(
            etiqueta: 'Id de transacción',
            valor: intent.idTransaccion,
          ),
          const SizedBox(height: 12),
          const Text(
            'Paso 1: abre Transfermóvil y paga el importe.\n'
            'Paso 2: al volver aquí, pulsa "Ya he pagado" para avisar a soporte.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAbrirTransfermovil,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir Transfermóvil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // El botón del paso 2 aparece SOLO después de volver de Transfermóvil:
          // mostrarlo antes invita a reportar un pago que todavía no se hizo.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: mostrarYaHePagado
                ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: procesando ? null : onYaHePagado,
                      icon: procesando
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
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Cuando termines de pagar y vuelvas a la app, aparecerá aquí '
                      'el botón "Ya he pagado".',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: procesando ? null : onCancelar,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
              ),
              child: const Text('Cancelar este intento'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un intent que ya estaba vivo en el servidor al abrir la pantalla.
///
/// Aparece cuando el cliente pagó (o abrió Transfermóvil) y salió de la app antes
/// de reportarlo. La diferencia con [_TarjetaPagoEnCurso] es que aquí el botón
/// "Ya he pagado" se muestra desde el primer momento: el intento existe y puede
/// estar pagado, así que no tiene sentido obligar al cliente a volver a salir a
/// Transfermóvil para que aparezca el botón.
///
/// El estado real del intento no se puede saber desde la app (Transfermóvil no
/// avisa), así que se ofrecen las dos salidas: reabrir el pago o reportarlo.
class _TarjetaIntentGuardado extends StatelessWidget {
  const _TarjetaIntentGuardado({
    required this.intent,
    required this.procesando,
    required this.onAbrirTransfermovil,
    required this.onYaHePagado,
  });

  final IntentSuscripcion intent;
  final bool procesando;
  final VoidCallback onAbrirTransfermovil;
  final VoidCallback onYaHePagado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_bottom, color: AppTheme.warning, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tienes un pago sin terminar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Empezaste un pago y no llegaste a reportarlo. Si ya pagaste, pulsa '
            '"Ya he pagado" y envía el número de confirmación; si no, puedes '
            'volver a abrir Transfermóvil.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _DatoCopiable(
            etiqueta: 'Importe',
            valor: '${intent.monto.toStringAsFixed(2)} ${intent.moneda}',
          ),
          _DatoCopiable(
            etiqueta: 'Id de transacción',
            valor: intent.idTransaccion,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: procesando ? null : onYaHePagado,
              icon: procesando
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: procesando ? null : onAbrirTransfermovil,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Volver a abrir Transfermóvil'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({required this.plan, required this.onPagar});

  final PlanSuscripcion plan;
  final VoidCallback onPagar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
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
                    Text(
                      plan.nombre,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plan.etiquetaDuracion} · ${plan.duracionDias} días',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    plan.precioEtiqueta,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  if (plan.precioPorMesEtiqueta != null)
                    Text(
                      '${plan.precioPorMesEtiqueta}/mes',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (plan.descripcion != null &&
              plan.descripcion!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.descripcion!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPagar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Pagar con Transfermóvil'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Historial: movimientos del libro y pagos reportados.
///
/// Los movimientos son la auditoría de por qué la entidad tiene el tiempo que
/// tiene (pago acreditado, ajuste del superadmin, vencimiento); los pagos son lo
/// que el cliente reportó. Se muestran juntos pero etiquetados: mezclarlos sin
/// distinguir haría pensar que un pago reportado ya está acreditado.
class _Historial extends StatelessWidget {
  const _Historial({required this.movimientos, required this.pagos});

  final List<MovimientoSuscripcion> movimientos;
  final List<PagoSuscripcion> pagos;

  @override
  Widget build(BuildContext context) {
    if (movimientos.isEmpty && pagos.isEmpty) {
      return const _Aviso(texto: 'Todavía no hay movimientos en esta entidad.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...pagos.map(
          (p) => _FilaHistorial(
            icono: p.estado == 'verificado'
                ? Icons.check_circle_outline
                : p.estado == 'rechazado'
                ? Icons.cancel_outlined
                : Icons.schedule,
            color: p.estado == 'verificado'
                ? AppTheme.success
                : p.estado == 'rechazado'
                ? AppTheme.error
                : AppTheme.warning,
            titulo: 'Pago ${p.montoEtiqueta} · ${p.etiquetaEstado}',
            subtitulo: p.codigoConfirmacion == null
                ? null
                : 'Confirmación ${p.codigoConfirmacion}',
            fecha: p.reportadoAt,
          ),
        ),
        ...movimientos.map(
          (m) => _FilaHistorial(
            icono: m.tipo == 'expiracion'
                ? Icons.event_busy
                : m.tipo == 'suspension'
                ? Icons.block
                : Icons.history,
            color: m.tipo == 'expiracion' || m.tipo == 'suspension'
                ? AppTheme.error
                : AppTheme.textSecondary,
            titulo: '${m.etiquetaTipo} · ${m.etiquetaDias}',
            subtitulo: m.motivo,
            fecha: m.createdAt,
          ),
        ),
      ],
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  const _FilaHistorial({
    required this.icono,
    required this.color,
    required this.titulo,
    this.subtitulo,
    this.fecha,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final DateTime? fecha;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (fecha != null)
            Text(
              _fechaCorta(fecha!),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12.5,
          color: AppTheme.textSecondary,
          height: 1.3,
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Dato con botón de copiar: la referencia de soporte y el número del comercio se
/// copian a mano en Transfermóvil cuando el deep link no abre.
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

// ───────────────────────────── Diálogo "Ya he pagado" ──────────────────────

class _DatosReporte {
  const _DatosReporte({required this.codigo, this.comprobanteUrl});

  final String codigo;
  final String? comprobanteUrl;
}

/// Pide el código de confirmación (obligatorio) y, si se quiere, la foto del
/// comprobante.
///
/// El código se valida en el servidor contra un `UNIQUE`: sin él, el mismo pago
/// podría acreditarse dos veces. Por eso aquí no se deja enviar vacío — el
/// servidor lo rechazaría igual, pero es mejor decirlo antes de salir a
/// WhatsApp.
class _DialogoReportarPago extends StatefulWidget {
  const _DialogoReportarPago({required this.importe, required this.moneda});

  final String importe;
  final String moneda;

  @override
  State<_DialogoReportarPago> createState() => _DialogoReportarPagoState();
}

class _DialogoReportarPagoState extends State<_DialogoReportarPago> {
  final TextEditingController _codigo = TextEditingController();
  String? _comprobanteUrl;
  bool _subiendo = false;
  String? _error;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _adjuntarComprobante() async {
    setState(() => _error = null);
    try {
      final imagen = await ImagenService.seleccionarImagen();
      if (imagen == null) return;

      setState(() => _subiendo = true);

      // El primer segmento del path es el uuid: la política de borrado del
      // bucket solo deja tocar lo que empieza por el id del que subió.
      final uuid = AuthService.currentUserId;
      if (uuid == null) {
        setState(() {
          _subiendo = false;
          _error = 'Tu sesión caducó. Vuelve a entrar.';
        });
        return;
      }

      final url = await ImagenService.subirImagen(
        imagen: imagen,
        path:
            '$uuid/suscripciones/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!mounted) return;
      setState(() {
        _comprobanteUrl = url;
        _subiendo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _error =
            'No se pudo subir el comprobante. Puedes enviarlo igual por WhatsApp.';
      });
    }
  }

  void _enviar() {
    final codigo = _codigo.text.trim();
    if (codigo.length < 4) {
      setState(
        () => _error =
            'Escribe el número de confirmación que muestra Transfermóvil.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_DatosReporte(codigo: codigo, comprobanteUrl: _comprobanteUrl));
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
              'Confirma que pagaste ${widget.importe} ${widget.moneda} por '
              'Transfermóvil. Soporte comprobará el pago antes de acreditar el plan.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _codigo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Número de confirmación *',
                helperText: 'Aparece en Transfermóvil al terminar el pago',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: _error,
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
          child: const Text('Enviar a soporte'),
        ),
      ],
    );
  }
}

/// "14/03/2026" sin depender de `intl` para algo tan simple y tan usado aquí.
String _fechaCorta(DateTime f) {
  String dos(int v) => v < 10 ? '0$v' : '$v';
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}
