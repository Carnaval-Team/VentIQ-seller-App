import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/cobro.dart';
import '../../models/entidad.dart';
import '../../services/cobro_service.dart';
import '../../services/suscripcion_service.dart';

/// Bandeja del administrador: **pagos por adelantado** de las reservas de la
/// entidad, con la verificación manual en la mano.
///
/// Al abrir llama a `flow.reserva_pago_expirar()` —la misma función que el cron—
/// para que los intentos vencidos se cierren (y, si la entidad lo configuró,
/// cancelen su reserva) antes de que el admin mire la lista. Después carga todos
/// los pagos y los reparte en cuatro pestañas.
///
/// El circuito no lo cierra esta pantalla por sí sola: verificar y rechazar es
/// lo que notifica al cliente (`tipo='pago'`) y lo que confirma o desbloquea la
/// reserva.
class PagosReservaScreen extends StatefulWidget {
  /// Acepta la entidad completa ([entidad]) o solo su id ([idEntidad]), igual
  /// que [CobroConfigScreen].
  PagosReservaScreen({
    super.key,
    Entidad? entidad,
    int? idEntidad,
    String? nombreEntidad,
  }) : entidad = entidad,
       idEntidad = idEntidad ?? entidad?.id ?? 0,
       nombreEntidad = nombreEntidad ?? entidad?.denominacion;

  final Entidad? entidad;
  final int idEntidad;
  final String? nombreEntidad;

  @override
  State<PagosReservaScreen> createState() => _PagosReservaScreenState();
}

class _PagosReservaScreenState extends State<PagosReservaScreen> {
  List<PagoAdminItem> _todos = const [];

  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  /// Intentos cerrados por la comprobación de vencimientos al abrir. Se usa
  /// solo para el aviso informativo.
  int _expiradosAlAbrir = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Primero cerrar lo vencido: así lo que se pinta es el estado real y no una
    // lista con intentos que ya no se pueden verificar.
    try {
      final expirados = await CobroService.expirarPagos();
      _expiradosAlAbrir = expirados;
    } catch (_) {
      // Si falla, la bandeja sigue siendo útil: se muestra lo que hay.
      _expiradosAlAbrir = 0;
    }
    await _cargar();
  }

  Future<void> _cargar() async {
    if (widget.idEntidad <= 0) {
      setState(() {
        _cargando = false;
        _error = 'No se pudo resolver la entidad. Vuelve a entrar.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final pagos = await CobroService.listarPagos(idEntidad: widget.idEntidad);
      if (!mounted) return;
      setState(() {
        _todos = pagos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _mensaje(e);
      });
    }
  }

  String _mensaje(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '').trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: esError ? 5 : 3),
      ),
    );
  }

  // ── Reparto en pestañas ──────────────────────────────────────────────────

  /// «Por verificar» = el intento sigue vivo: `creado` (sin reportar) o
  /// `reportado`. Los vencidos ya los cerró `reserva_pago_expirar`.
  List<PagoAdminItem> get _porVerificar => _todos
      .where((p) => p.pago.estado == 'creado' || p.pago.estado == 'reportado')
      .toList(growable: false);

  List<PagoAdminItem> get _verificados => _todos
      .where((p) => p.pago.estado == 'verificado')
      .toList(growable: false);

  List<PagoAdminItem> get _rechazados =>
      _todos.where((p) => p.pago.estado == 'rechazado').toList(growable: false);

  List<PagoAdminItem> get _expirados =>
      _todos.where((p) => p.pago.estado == 'expirado').toList(growable: false);

  // ── Acciones ─────────────────────────────────────────────────────────────

  /// Verifica el pago. Las observaciones son opcionales.
  Future<void> _verificar(PagoAdminItem item) async {
    final observaciones = await _pedirTexto(
      titulo: 'Verificar el pago',
      descripcion:
          'Confirmas que recibiste ${item.importeEtiqueta} de '
          '${item.clienteEtiqueta} para «${item.servicioLocalEtiqueta}». '
          'Se avisará al cliente de que su reserva está confirmada.',
      etiqueta: 'Observaciones (opcional)',
      textoAccion: 'Verificar',
      colorAccion: AppTheme.success,
      obligatorio: false,
    );
    if (observaciones == null || !mounted) return;

    setState(() => _procesando = true);
    try {
      await CobroService.verificarPago(
        idPago: item.pago.id,
        observaciones: observaciones.isEmpty ? null : observaciones,
      );
      if (!mounted) return;
      _avisar('Pago verificado. El cliente ya está avisado.', esError: false);
    } catch (e) {
      if (!mounted) return;
      _avisar(_mensaje(e), esError: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
      await _cargar();
    }
  }

  /// Rechaza el pago. El motivo es **obligatorio** (el servidor también lo
  /// exige): es lo que el cliente recibe para corregir.
  Future<void> _rechazar(PagoAdminItem item) async {
    final motivo = await _pedirTexto(
      titulo: 'Rechazar el pago',
      descripcion:
          'El cliente recibirá este motivo. Escribe qué falló (importe '
          'distinto, sin comprobante, transferencia no encontrada…).',
      etiqueta: 'Motivo del rechazo *',
      textoAccion: 'Rechazar',
      colorAccion: AppTheme.error,
      obligatorio: true,
    );
    if (motivo == null || motivo.trim().isEmpty || !mounted) return;

    setState(() => _procesando = true);
    try {
      await CobroService.rechazarPago(
        idPago: item.pago.id,
        motivo: motivo.trim(),
      );
      if (!mounted) return;
      _avisar('Pago rechazado. El cliente ya está avisado.', esError: false);
    } catch (e) {
      if (!mounted) return;
      _avisar(_mensaje(e), esError: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
      await _cargar();
    }
  }

  /// Diálogo de texto reutilizable. Devuelve `null` si se cancela.
  Future<String?> _pedirTexto({
    required String titulo,
    required String descripcion,
    required String etiqueta,
    required String textoAccion,
    required Color colorAccion,
    required bool obligatorio,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogoTexto(
        titulo: titulo,
        descripcion: descripcion,
        etiqueta: etiqueta,
        textoAccion: textoAccion,
        colorAccion: colorAccion,
        obligatorio: obligatorio,
      ),
    );
  }

  /// Abre el WhatsApp **del cliente** con el mensaje ya redactado.
  Future<void> _whatsappCliente(PagoAdminItem item) async {
    final telefono = item.clienteTelefono?.trim();
    if (telefono == null || telefono.isEmpty) {
      _avisar('Este cliente no tiene teléfono en su perfil.', esError: true);
      return;
    }

    final mensaje =
        'Hola ${item.clienteEtiqueta}, te escribo por tu reserva de '
        '"${item.servicioLocalEtiqueta}" del ${item.fechaEtiqueta}. '
        'Sobre el pago por adelantado de ${item.importeEtiqueta}: ';
    final conCodigo = item.pago.codigoConfirmacion == null
        ? mensaje
        : '$mensaje(confirmación ${item.pago.codigoConfirmacion}) ';

    bool abierto = false;
    try {
      abierto = await launchUrl(
        Uri.parse(
          SuscripcionService.urlWhatsapp(
            telefono,
            '$conCodigo¿me puedes confirmar el pago?',
          ),
        ),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }
    if (!mounted || abierto) return;
    _avisar(
      'No se pudo abrir WhatsApp. El teléfono es '
      '${SuscripcionService.normalizarTelefono(telefono)}.',
      esError: true,
    );
  }

  Future<void> _verComprobante(PagoAdminItem item) async {
    final url = item.pago.comprobanteUrl;
    if (url == null || url.isEmpty) return;
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
    _avisar('No se pudo abrir el comprobante.', esError: true);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final porVerificar = _porVerificar;
    final verificados = _verificados;
    final rechazados = _rechazados;
    final expirados = _expirados;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          title: const Text('Pagos por adelantado'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Por verificar (${porVerificar.length})'),
              Tab(text: 'Verificados (${verificados.length})'),
              Tab(text: 'Rechazados (${rechazados.length})'),
              Tab(text: 'Expirados (${expirados.length})'),
            ],
          ),
        ),
        body: _cargando && _todos.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _errorCentral(_error!)
            : TabBarView(
                children: [
                  _lista(
                    porVerificar,
                    conAcciones: true,
                    mostrarAviso: true,
                    vacio:
                        'No hay pagos esperando verificación. Cuando un '
                        'cliente reporte un pago por adelantado aparecerá '
                        'aquí.',
                  ),
                  _lista(
                    verificados,
                    conAcciones: false,
                    vacio: 'Todavía no has verificado ningún pago.',
                  ),
                  _lista(
                    rechazados,
                    conAcciones: false,
                    vacio: 'No has rechazado ningún pago.',
                  ),
                  _lista(
                    expirados,
                    conAcciones: false,
                    vacio:
                        'No hay pagos vencidos. Los intentos que nadie '
                        'verifica en el plazo acaban aquí.',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _errorCentral(String error) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_off, size: 44, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        const Text(
          'No se pudieron cargar los pagos',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _cargar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }

  Widget _lista(
    List<PagoAdminItem> items, {
    required bool conAcciones,
    required String vacio,
    bool mostrarAviso = false,
  }) {
    final conAviso = mostrarAviso && _expiradosAlAbrir > 0;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(28),
              children: [
                const SizedBox(height: 50),
                const Icon(
                  Icons.inbox_outlined,
                  size: 44,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  vacio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              itemCount: items.length + (conAviso ? 1 : 0),
              itemBuilder: (context, i) {
                if (conAviso && i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _expiradosAlAbrir == 1
                            ? 'Se cerró 1 intento de pago vencido al abrir la '
                                  'bandeja.'
                            : 'Se cerraron $_expiradosAlAbrir intentos de pago '
                                  'vencidos al abrir la bandeja.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                }
                final item = items[i - (conAviso ? 1 : 0)];
                return _TarjetaPago(
                  item: item,
                  procesando: _procesando,
                  conAcciones: conAcciones,
                  onWhatsapp: () => _whatsappCliente(item),
                  onVerComprobante: () => _verComprobante(item),
                  onVerificar: () => _verificar(item),
                  onRechazar: () => _rechazar(item),
                );
              },
            ),
    );
  }
}

/// Una fila de la bandeja: cliente, reserva, importe y acciones.
class _TarjetaPago extends StatelessWidget {
  const _TarjetaPago({
    required this.item,
    required this.procesando,
    required this.conAcciones,
    required this.onWhatsapp,
    required this.onVerComprobante,
    required this.onVerificar,
    required this.onRechazar,
  });

  final PagoAdminItem item;
  final bool procesando;
  final bool conAcciones;
  final VoidCallback onWhatsapp;
  final VoidCallback onVerComprobante;
  final VoidCallback onVerificar;
  final VoidCallback onRechazar;

  Color get _color {
    switch (item.pago.estado) {
      case 'verificado':
        return AppTheme.success;
      case 'rechazado':
      case 'expirado':
        return AppTheme.error;
      case 'reportado':
        return AppTheme.primary;
      default:
        return AppTheme.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pago = item.pago;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
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
                      item.clienteEtiqueta,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.telefonoEtiqueta,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pago.etiquetaEstado,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fila('Servicio', item.servicioLocalEtiqueta),
          _fila('Reserva', item.fechaEtiqueta),
          _fila('Estado reserva', item.estadoReserva ?? '—'),
          _fila('Importe', pago.montoEtiqueta),
          if (pago.codigoConfirmacion != null)
            _fila('Confirmación', pago.codigoConfirmacion!),
          if (pago.idTransaccion != null)
            _fila('Referencia', pago.idTransaccion!),
          if (pago.reportadoAt != null)
            _fila(
              'Reportado',
              '${pago.reportadoAt!.day.toString().padLeft(2, '0')}/'
                  '${pago.reportadoAt!.month.toString().padLeft(2, '0')}/'
                  '${pago.reportadoAt!.year}',
            ),
          if (pago.motivoRechazo != null && pago.rechazado)
            _fila('Motivo', pago.motivoRechazo!),
          if (item.motivoCancelacion != null)
            _fila('Cancelación', item.motivoCancelacion!),

          if (pago.comprobanteUrl != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onVerComprobante,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Ver comprobante'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],

          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (item.tieneTelefono)
                OutlinedButton.icon(
                  onPressed: procesando ? null : onWhatsapp,
                  icon: const Icon(Icons.chat, size: 17),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF128C7E),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (conAcciones) ...[
                ElevatedButton.icon(
                  onPressed: procesando ? null : onVerificar,
                  icon: const Icon(Icons.check, size: 17),
                  label: const Text('Verificar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: procesando ? null : onRechazar,
                  icon: const Icon(Icons.close, size: 17),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo de un campo de texto con acción coloreada.
///
/// Es un `StatefulWidget` (y no un `StatefulBuilder` con un controlador creado
/// fuera) para que el controlador viva y muera con el diálogo: disponerlo al
/// cerrar mientras la ruta aún se anima revienta con «used after being disposed».
class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.descripcion,
    required this.etiqueta,
    required this.textoAccion,
    required this.colorAccion,
    required this.obligatorio,
  });

  final String titulo;
  final String descripcion;
  final String etiqueta;
  final String textoAccion;
  final Color colorAccion;
  final bool obligatorio;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texto = _controller.text.trim();
    final valido = !widget.obligatorio || texto.length >= 3;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.descripcion,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: widget.obligatorio ? 3 : 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.etiqueta,
                border: const OutlineInputBorder(),
                helperText: widget.obligatorio
                    ? 'Mínimo 3 caracteres.'
                    : 'Puedes dejarlo vacío.',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: valido
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.colorAccion,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.textoAccion),
        ),
      ],
    );
  }
}
