import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/suscripcion_admin_service.dart';
import '../widgets/suscripcion_ui.dart';

/// Ficha de suscripción de una entidad.
///
/// Es donde se cierra el circuito: el cliente reportó un pago y aquí el
/// superadmin lo **verifica en el banco** y lo acredita. Nada de esta pantalla
/// acredita tiempo automáticamente — ni siquiera "Aprobar" sabe si el pago
/// llegó; solo registra que una persona lo comprobó.
///
/// Tres bloques, en el orden en que se usan:
///   1. Estado y plan, con las acciones de gestión (acreditar, suspender).
///   2. Pagos reportados: aprobar o rechazar con motivo.
///   3. Historial y movimientos.
class FlowSuscripcionDetalleScreen extends StatefulWidget {
  const FlowSuscripcionDetalleScreen({
    super.key,
    required this.idEntidad,
    required this.denominacion,
  });

  final int idEntidad;
  final String denominacion;

  @override
  State<FlowSuscripcionDetalleScreen> createState() =>
      _FlowSuscripcionDetalleScreenState();
}

class _FlowSuscripcionDetalleScreenState
    extends State<FlowSuscripcionDetalleScreen> {
  Map<String, dynamic>? _detalle;
  List<Map<String, dynamic>> _planes = const [];
  bool _cargando = true;
  String? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Los planes son para el selector de acreditación; si fallan no deben
      // impedir ver la ficha.
      final detalle = await SuscripcionAdminService.detalle(widget.idEntidad);
      List<Map<String, dynamic>> planes = const [];
      try {
        planes = await SuscripcionAdminService.planes();
      } catch (_) {
        planes = const [];
      }
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _planes = planes;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.error : AppColors.success,
        duration: Duration(seconds: esError ? 6 : 4),
      ),
    );
  }

  /// Envuelve una acción de escritura: bloquea la UI, avisa y recarga.
  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    setState(() => _ocupado = true);
    try {
      await accion();
      _avisar(exito, esError: false);
      await _cargar();
    } catch (e) {
      _avisar('$e', esError: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aprobar(Map<String, dynamic> pago) async {
    final id = enteroDe(pago['id']);
    if (id == null) return;

    final obs = await _pedirTexto(
      titulo: 'Acreditar el plan',
      descripcion:
          'Verifica el pago de ${formatearMoneda(decimalDe(pago['monto']), textoDe(pago['moneda'], porDefecto: 'CUP'))} '
          'en la plataforma del banco (confirmación ${textoDe(pago['codigo_confirmacion'], porDefecto: '—')}), '
          'y confirma. Se acreditarán los días del plan comprado.',
      etiqueta: 'Observaciones (opcional)',
      requerido: false,
    );
    if (obs == null) return;

    await _ejecutar(
      () => SuscripcionAdminService.aprobarPago(
        id,
        observaciones: obs.trim().isEmpty ? null : obs.trim(),
      ),
      'Pago verificado y plan acreditado.',
    );
  }

  Future<void> _rechazar(Map<String, dynamic> pago) async {
    final id = enteroDe(pago['id']);
    if (id == null) return;

    final motivo = await _pedirTexto(
      titulo: 'Rechazar el pago',
      descripcion:
          'El cliente verá este motivo en la app. El intento vuelve a quedar '
          'disponible para que reporte un pago nuevo.',
      etiqueta: 'Motivo del rechazo *',
      requerido: true,
    );
    if (motivo == null) return;

    await _ejecutar(
      () => SuscripcionAdminService.rechazarPago(id, motivo: motivo.trim()),
      'Pago rechazado. Se avisó al cliente.',
    );
  }

  Future<void> _acreditar() async {
    final datos = await showDialog<({int dias, int? idPlan, String motivo})>(
      context: context,
      builder: (_) => _DialogoAcreditar(planes: _planes),
    );
    if (datos == null) return;

    await _ejecutar(
      () => SuscripcionAdminService.acreditar(
        idEntidad: widget.idEntidad,
        dias: datos.dias,
        idPlan: datos.idPlan,
        motivo: datos.motivo,
      ),
      'Se acreditaron ${datos.dias} día(s).',
    );
  }

  Future<void> _suspender() async {
    final motivo = await _pedirTexto(
      titulo: 'Suspender la entidad',
      descripcion:
          'La entidad deja de mostrarse y no admite reservas, igual que si '
          'hubiera vencido, pero queda registrado que fue una decisión del '
          'administrador y no un impago. No se borra nada.',
      etiqueta: 'Motivo de la suspensión *',
      requerido: true,
    );
    if (motivo == null) return;

    await _ejecutar(
      () => SuscripcionAdminService.suspender(
        widget.idEntidad,
        motivo: motivo.trim(),
      ),
      'Entidad suspendida.',
    );
  }

  Future<void> _reactivar() async {
    final motivo = await _pedirTexto(
      titulo: 'Reactivar la entidad',
      descripcion:
          'Se quita la suspensión. Si la suscripción ya venció por fechas, el '
          'servidor lo rechazará: en ese caso hay que acreditar días o un plan.',
      etiqueta: 'Motivo (opcional)',
      requerido: false,
    );
    if (motivo == null) return;

    await _ejecutar(
      () => SuscripcionAdminService.reactivar(
        widget.idEntidad,
        motivo: motivo.trim().isEmpty ? null : motivo.trim(),
      ),
      'Entidad reactivada.',
    );
  }

  /// Diálogo de texto simple, reutilizado por las cuatro acciones con motivo.
  ///
  /// El controlador lo posee el diálogo, no este método: si se creara aquí y se
  /// liberara al completarse el `Future`, se estaría liberando mientras el
  /// diálogo todavía se está animando fuera de pantalla, con el `TextField`
  /// todavía montado.
  Future<String?> _pedirTexto({
    required String titulo,
    required String descripcion,
    required String etiqueta,
    required bool requerido,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogoTexto(
        titulo: titulo,
        descripcion: descripcion,
        etiqueta: etiqueta,
        requerido: requerido,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.denominacion),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _ocupado || _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          _cuerpo(),
          if (_ocupado)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final estado = _mapa(_detalle?['estado']);
    final pagos = _listaMapas(_detalle?['pagos']);
    final movimientos = _listaMapas(_detalle?['movimientos']);

    final pendientes = pagos.where((p) => p['estado'] == 'reportado').toList();
    final resueltos = pagos.where((p) => p['estado'] != 'reportado').toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _CabeceraEstado(estado: estado),
          const SizedBox(height: 12),
          _AccionesGestion(
            estado: estado,
            onAcreditar: _acreditar,
            onSuspender: _suspender,
            onReactivar: _reactivar,
          ),
          const SizedBox(height: 20),
          _Titulo(
            titulo: 'Pagos reportados',
            subtitulo:
                pendientes.isEmpty
                    ? 'No hay pagos esperando verificación.'
                    : 'Verifica cada pago en el banco antes de acreditarlo.',
          ),
          const SizedBox(height: 8),
          if (pendientes.isEmpty)
            const TarjetaFlow(
              child: Text(
                'Nada pendiente. Los pagos que el cliente reporte aparecerán aquí.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            ...pendientes.map(
              (p) => _TarjetaPago(
                pago: p,
                onAprobar: () => _aprobar(p),
                onRechazar: () => _rechazar(p),
              ),
            ),
          if (resueltos.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Titulo(titulo: 'Pagos anteriores'),
            const SizedBox(height: 8),
            ...resueltos.map(
              (p) => _TarjetaPago(pago: p, onAprobar: null, onRechazar: null),
            ),
          ],
          const SizedBox(height: 20),
          const _Titulo(titulo: 'Historial de la suscripción'),
          const SizedBox(height: 8),
          if (movimientos.isEmpty)
            const TarjetaFlow(
              child: Text(
                'Sin movimientos.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            ...movimientos.map((m) => _FilaMovimiento(movimiento: m)),
        ],
      ),
    );
  }

  static Map<String, dynamic> _mapa(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _listaMapas(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

/// Diálogo de un campo de texto con motivo.
///
/// Es un widget con estado a propósito: el `TextEditingController` se libera en
/// `dispose()`, cuando el diálogo ya se desmontó del todo. Crearlo en el método
/// que abre el diálogo y liberarlo al cerrarse deja el controlador vivo dentro de
/// un árbol que todavía se está animando fuera de pantalla.
class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.descripcion,
    required this.etiqueta,
    required this.requerido,
  });

  final String titulo;
  final String descripcion;
  final String etiqueta;
  final bool requerido;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  final _ctrl = TextEditingController();

  /// Se muestra solo cuando se intenta confirmar con el campo vacío en un motivo
  /// obligatorio, para no dejar al superadmin pulsando sin saber qué falta.
  bool _faltaMotivo = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _ctrl.text.trim();
    // El servidor exige el motivo en suspender/rechazar/acreditar. Validarlo aquí
    // evita un viaje de red para recibir un error que ya se sabía.
    if (widget.requerido && texto.isEmpty) {
      setState(() => _faltaMotivo = true);
      return;
    }
    Navigator.pop(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.descripcion,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: widget.requerido,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) {
              if (_faltaMotivo) setState(() => _faltaMotivo = false);
            },
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              labelText: widget.etiqueta,
              border: const OutlineInputBorder(),
              errorText: _faltaMotivo ? 'Escribe el motivo' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}

class _CabeceraEstado extends StatelessWidget {
  const _CabeceraEstado({required this.estado});

  final Map<String, dynamic> estado;

  @override
  Widget build(BuildContext context) {
    final e = textoDe(estado['estado'], porDefecto: 'sin_suscripcion');
    final activa = boolDe(estado['activa'], porDefecto: true);
    final plan = textoDe(estado['plan_nombre']);

    return TarjetaFlow(
      borde: colorDeEstado(e).withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.isEmpty ? 'Sin plan' : plan,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              EstadoPill(estado: e),
            ],
          ),
          if (textoDe(estado['mensaje']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              textoDe(estado['mensaje']),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _Dato('Estado en la app', activa ? 'Visible' : 'Oculta'),
              _Dato('Inicio', fechaCorta(fechaDe(estado['fecha_inicio']))),
              _Dato(
                'Vencimiento',
                fechaCorta(fechaDe(estado['fecha_vencimiento'])),
              ),
              _Dato(
                'Días restantes',
                enteroDe(estado['dias_restantes'])?.toString() ?? '—',
              ),
              _Dato(
                'Gracia hasta',
                fechaCorta(fechaDe(estado['fecha_gracia_fin'])),
              ),
              _Dato(
                'Días de gracia',
                enteroDe(estado['dias_gracia'])?.toString() ?? '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Acciones de gestión, cada una con su consecuencia escrita.
///
/// Suspender y reactivar son operaciones que cambian lo que ve el público, así
/// que van en botones separados y con confirmación, no en un menú desplegable
/// donde un toque accidental las dispare.
class _AccionesGestion extends StatelessWidget {
  const _AccionesGestion({
    required this.estado,
    required this.onAcreditar,
    required this.onSuspender,
    required this.onReactivar,
  });

  final Map<String, dynamic> estado;
  final VoidCallback onAcreditar;
  final VoidCallback onSuspender;
  final VoidCallback onReactivar;

  @override
  Widget build(BuildContext context) {
    final suspendida = textoDe(estado['estado']) == 'suspendida';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: onAcreditar,
          icon: const Icon(Icons.add_task, size: 18),
          label: const Text('Acreditar días o plan'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
        if (suspendida)
          OutlinedButton.icon(
            onPressed: onReactivar,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Reactivar entidad'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.success,
              side: const BorderSide(color: AppColors.success),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: onSuspender,
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Suspender entidad'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _TarjetaPago extends StatelessWidget {
  const _TarjetaPago({
    required this.pago,
    required this.onAprobar,
    required this.onRechazar,
  });

  final Map<String, dynamic> pago;
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;

  @override
  Widget build(BuildContext context) {
    final estado = textoDe(pago['estado'], porDefecto: 'reportado');
    final pendiente = estado == 'reportado';

    final color =
        estado == 'verificado'
            ? AppColors.success
            : estado == 'rechazado'
            ? AppColors.error
            : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaFlow(
        borde: pendiente ? color.withValues(alpha: 0.5) : AppColors.divider,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  pendiente ? Icons.schedule : Icons.verified_outlined,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatearMoneda(
                      decimalDe(pago['monto']),
                      textoDe(pago['moneda'], porDefecto: 'CUP'),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  estado == 'reportado'
                      ? 'Por verificar'
                      : estado == 'verificado'
                      ? 'Verificado'
                      : 'Rechazado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _Dato(
                  'Confirmación',
                  textoDe(pago['codigo_confirmacion'], porDefecto: '—'),
                ),
                _Dato('Reportado', fechaHora(fechaDe(pago['reportado_at']))),
                _Dato('Plan', textoDe(pago['plan_nombre'], porDefecto: '—')),
                _Dato(
                  'Referencia interna',
                  textoDe(pago['id_transaccion'], porDefecto: '—'),
                ),
                if (fechaDe(pago['verificado_at']) != null)
                  _Dato(
                    'Verificado',
                    fechaHora(fechaDe(pago['verificado_at'])),
                  ),
              ],
            ),
            if (textoDe(pago['comprobante_url']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      textoDe(pago['comprobante_url']),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (textoDe(pago['observaciones']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Observaciones: ${textoDe(pago['observaciones'])}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            if (pendiente) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onAprobar,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Verificar y acreditar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onRechazar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('Rechazar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.movimiento});

  final Map<String, dynamic> movimiento;

  @override
  Widget build(BuildContext context) {
    final tipo = textoDe(movimiento['tipo']);
    final dias = enteroDe(movimiento['dias']) ?? 0;
    final negativo = tipo == 'expiracion' || tipo == 'suspension';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TarjetaFlow(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              negativo ? Icons.event_busy : Icons.history,
              size: 18,
              color: negativo ? AppColors.error : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_etiquetaTipo(tipo)} · ${dias == 0 ? '—' : '$dias día(s)'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    textoDe(movimiento['motivo'], porDefecto: 'Sin motivo'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  if (fechaDe(movimiento['fecha_hasta']) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Hasta ${fechaCorta(fechaDe(movimiento['fecha_hasta']))}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              fechaCorta(fechaDe(movimiento['created_at'])),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _etiquetaTipo(String tipo) {
    switch (tipo) {
      case 'trial':
        return 'Prueba';
      case 'acreditacion':
        return 'Pago acreditado';
      case 'renovacion':
        return 'Renovación';
      case 'ajuste':
        return 'Ajuste';
      case 'expiracion':
        return 'Vencimiento';
      case 'suspension':
        return 'Suspensión';
      case 'reactivacion':
        return 'Reactivación';
      case 'inicializacion':
        return 'Alta';
      default:
        return tipo;
    }
  }
}

/// Diálogo de acreditación manual: días o plan, más el motivo obligatorio.
class _DialogoAcreditar extends StatefulWidget {
  const _DialogoAcreditar({required this.planes});

  final List<Map<String, dynamic>> planes;

  @override
  State<_DialogoAcreditar> createState() => _DialogoAcreditarState();
}

class _DialogoAcreditarState extends State<_DialogoAcreditar> {
  final _diasCtrl = TextEditingController(text: '30');
  final _motivoCtrl = TextEditingController();
  int? _idPlan;
  String? _error;

  @override
  void dispose() {
    _diasCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acreditar suscripción'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Los días se SUMAN a lo que le quede vigente. Si ya venció, se '
              'cuentan desde hoy.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _idPlan,
              decoration: const InputDecoration(
                labelText: 'Plan (opcional)',
                helperText: 'Elegir un plan rellena sus días',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sin plan (solo días)'),
                ),
                ...widget.planes.map(
                  (p) => DropdownMenuItem<int?>(
                    value: enteroDe(p['id']),
                    child: Text(
                      '${textoDe(p['nombre'])} · ${enteroDe(p['duracion_dias']) ?? 0} días',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _idPlan = v;
                  if (v != null) {
                    final plan = widget.planes.firstWhere(
                      (p) => enteroDe(p['id']) == v,
                      orElse: () => const <String, dynamic>{},
                    );
                    final dias = enteroDe(plan['duracion_dias']);
                    if (dias != null) _diasCtrl.text = '$dias';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Días *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivoCtrl,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: 'Motivo *',
                helperText: 'Queda en el historial de la entidad',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final dias = int.tryParse(_diasCtrl.text.trim()) ?? 0;
            final motivo = _motivoCtrl.text.trim();
            if (dias <= 0) {
              setState(() => _error = 'Indica días mayores que cero.');
              return;
            }
            if (motivo.isEmpty) {
              setState(() => _error = 'El motivo es obligatorio.');
              return;
            }
            Navigator.pop(context, (
              dias: dias,
              idPlan: _idPlan,
              motivo: motivo,
            ));
          },
          child: const Text('Acreditar'),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.titulo, this.subtitulo});

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
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo!,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
