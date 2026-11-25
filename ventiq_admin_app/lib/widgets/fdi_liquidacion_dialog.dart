import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/fondo_inversion.dart';
import '../services/fondo_inversion_service.dart';
import '../services/sales_service.dart';
import '../services/user_preferences_service.dart';

/// Diálogo "Crear liquidación" del Fondo de Inversión.
///
/// Por moneda: venta / inversión / ganancia en columna.
/// Destinos:
/// - Inversión → cuenta del fondo (depósito) o liquidación directa.
/// - Ganancia → liquidación (inversores) o fondo de inversión (depósito).
class FdiLiquidacionDialog extends StatefulWidget {
  final DateTime desde;
  final DateTime hasta;
  final List<TotalesPorMonedaProducto> totalesPorMoneda;

  const FdiLiquidacionDialog({
    super.key,
    required this.desde,
    required this.hasta,
    this.totalesPorMoneda = const [],
  });

  @override
  State<FdiLiquidacionDialog> createState() => _FdiLiquidacionDialogState();
}

class _FdiLiquidacionDialogState extends State<FdiLiquidacionDialog> {
  final _service = FondoInversionService();
  final _fmt = NumberFormat('#,##0.00');
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _confirming = false;
  String? _error;
  int? _idTienda;

  FdiVentasPeriodo? _ventas;
  List<FdiConcepto> _conceptos = [];
  List<FdiCuenta> _cuentas = [];
  FdiCuenta? _cuentaDestino;
  List<Map<String, dynamic>> _inversores = [];
  final _seleccion = FdiSeleccionGanancia();

  /// Reparto editable por moneda.
  final Map<String, _RepartoMoneda> _repartos = {};

  bool _repartirIgual = false;
  late final String _idemKey;
  static const _modo = 'creacion';

  bool get _participacionValida =>
      _inversores.isNotEmpty &&
      (_repartirIgual ||
          (_inversores.fold<double>(
                        0,
                        (s, i) => s + (i['porcentaje'] as num).toDouble(),
                      ) -
                      100)
                  .abs() <
              0.00001);

  bool get _repartosValidos =>
      _totalesUi.every((t) => _repartos[t.moneda]?.esValido ?? false);

  List<FdiTotalMoneda> get _totalesUi {
    if (widget.totalesPorMoneda.isNotEmpty) {
      return [
        for (final t in widget.totalesPorMoneda)
          FdiTotalMoneda(
            moneda: t.moneda,
            venta: t.ingresos,
            inversion: t.utilidadCompleta ? (t.costo ?? 0) : 0,
            ganancia: t.utilidadCompleta ? (t.ganancia ?? 0) : 0,
            utilidadCompleta: t.utilidadCompleta,
          ),
      ];
    }
    final v = _ventas;
    if (v == null) return const [];
    return [
      FdiTotalMoneda(
        moneda: 'CUP',
        venta: v.ventaTotalCup,
        inversion: v.costoTotalCup,
        ganancia: v.gananciaCup,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _idemKey = _service.newIdempotencyKey();
    _load();
  }

  @override
  void dispose() {
    for (final r in _repartos.values) {
      r.dispose();
    }
    super.dispose();
  }

  void _inicializarRepartos() {
    for (final t in _totalesUi) {
      final existente = _repartos[t.moneda];
      if (existente != null) {
        existente.actualizarTotales(
          inversion: t.utilidadCompleta ? t.inversion : 0,
          ganancia: t.utilidadCompleta ? t.ganancia : 0,
        );
        continue;
      }
      // Default: todo a liquidación (comportamiento previo).
      _repartos[t.moneda] = _RepartoMoneda(
        moneda: t.moneda,
        inversionTotal: t.utilidadCompleta ? t.inversion : 0,
        gananciaTotal: t.utilidadCompleta ? t.ganancia : 0,
      );
    }
  }

  /// Reparte un total entre medios de la misma moneda según vendido.
  List<double> _repartirEntreMedios(
    double monto,
    List<FdiVentaMedioMoneda> medios,
  ) {
    if (medios.isEmpty) return const [];
    final vendido = medios.fold<double>(0, (s, m) => s + m.montoVendido);
    if (monto <= 0 || vendido <= 0) {
      return List<double>.filled(medios.length, 0);
    }
    final out = <double>[];
    var restante = monto;
    for (var i = 0; i < medios.length; i++) {
      if (i == medios.length - 1) {
        out.add(
          double.parse(
            restante.clamp(0.0, medios[i].montoVendido).toStringAsFixed(2),
          ),
        );
      } else {
        final parte = double.parse(
          (monto * (medios[i].montoVendido / vendido))
              .clamp(0.0, medios[i].montoVendido)
              .toStringAsFixed(2),
        );
        out.add(parte);
        restante = double.parse((restante - parte).toStringAsFixed(2));
      }
    }
    return out;
  }

  void _aplicarRepartosAMedios() {
    final ventas = _ventas;
    if (ventas == null) return;
    _seleccion.origenes
      ..clear()
      ..addAll(ventas.medios);

    final porMoneda = <String, List<FdiVentaMedioMoneda>>{};
    for (final m in ventas.medios) {
      porMoneda.putIfAbsent(m.moneda, () => []).add(m);
      m.montoGananciaRetirada = 0;
      m.montoInversionDepositar = 0;
    }

    for (final entry in porMoneda.entries) {
      final moneda = entry.key;
      final medios = entry.value;
      final r = _repartos[moneda];
      if (r == null || !r.esValido) continue;

      // Ganancia a liquidación → reparto inversores.
      // Depósito FDI = inversión a cuenta + ganancia a fondo de inversión.
      final ganancias = _repartirEntreMedios(r.gananciaALiquidacion, medios);
      final depositos = _repartirEntreMedios(r.montoADepositar, medios);
      for (var i = 0; i < medios.length; i++) {
        medios[i].montoGananciaRetirada = ganancias[i];
        medios[i].montoInversionDepositar = depositos[i];
      }
    }
  }

  Future<void> _load() async {
    try {
      final idTienda = await UserPreferencesService().getIdTienda();
      if (idTienda == null) throw Exception('Sin tienda asignada');
      final results = await Future.wait([
        _service.ventasPorMedioMoneda(
          idTienda: idTienda,
          desde: widget.desde,
          hasta: widget.hasta,
          modo: _modo,
        ),
        _service.listConceptos(idTienda, soloActivos: true),
        _service.listCuentas(idTienda, soloActivas: true),
        _service.listInversores(idTienda),
      ]);
      if (!mounted) return;
      final ventas = results[0] as FdiVentasPeriodo;
      setState(() {
        _idTienda = idTienda;
        _ventas = ventas;
        _conceptos = results[1] as List<FdiConcepto>;
        _cuentas = results[2] as List<FdiCuenta>;
        _inversores = (results[3] as List<Map<String, dynamic>>)
            .where((i) => i['activo'] == true)
            .toList();
        _inicializarRepartos();
        _aplicarRepartosAMedios();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reloadVentas() async {
    try {
      final ventas = await _service.ventasPorMedioMoneda(
        idTienda: _idTienda!,
        desde: widget.desde,
        hasta: widget.hasta,
        modo: _modo,
      );
      if (!mounted) return;
      setState(() {
        _ventas = ventas;
        _inicializarRepartos();
        _aplicarRepartosAMedios();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  double _montoInversor(FdiVentaMedioMoneda medio, int index) {
    if (!_participacionValida || medio.montoGananciaRetirada <= 0) return 0;
    if (_repartirIgual) {
      return repartirGanancia(
        medio.montoGananciaRetirada,
        _inversores.map((i) => (i['porcentaje'] as num).toDouble()).toList(),
        repartirIgual: true,
      )[index];
    }
    return repartirGanancia(
      medio.montoGananciaRetirada,
      _inversores.map((i) => (i['porcentaje'] as num).toDouble()).toList(),
    )[index];
  }

  Future<void> _confirmar() async {
    final ventas = _ventas;
    final idTienda = _idTienda;
    if (ventas == null ||
        idTienda == null ||
        _confirming ||
        _loading ||
        !_participacionValida) {
      return;
    }
    if (!_repartosValidos) {
      setState(
        () => _error =
            'En cada moneda, los destinos de la inversión (cuenta / liquidación) '
            'y de la ganancia (liquidación / fondo) deben sumar el total.',
      );
      return;
    }
    if (_cuentaDestino == null) {
      setState(
        () => _error =
            'Elige la cuenta del fondo de inversión (registro de la liquidación).',
      );
      return;
    }
    if (_formKey.currentState?.validate() != true) return;

    _aplicarRepartosAMedios();
    final detalle = _seleccion.detalleDe(ventas.medios);
    final cuentaId = _cuentaDestino!.id;

    setState(() => _confirming = true);
    try {
      // Montos en moneda nativa: sin tasa de conversión a CUP.
      var resp = await _service.crearLiquidacion(
        idTienda: idTienda,
        desde: widget.desde,
        hasta: widget.hasta,
        modo: _modo,
        idCuentaDestino: cuentaId,
        detalle: detalle,
        idempotencyKey: _idemKey,
        repartirIgual: _repartirIgual,
      );

      if (resp['status'] == 'requires_confirmation' &&
          resp['code'] == 'diferencia_ganancia') {
        final ok = await _confirmDiferencia(resp);
        if (ok != true) {
          if (mounted) setState(() => _confirming = false);
          return;
        }
        resp = await _service.crearLiquidacion(
          idTienda: idTienda,
          desde: widget.desde,
          hasta: widget.hasta,
          modo: _modo,
          idCuentaDestino: cuentaId,
          detalle: detalle,
          confirmarDiferencia: true,
          idempotencyKey: _idemKey,
          repartirIgual: _repartirIgual,
        );
      }

      if (!mounted) return;
      if (resp['status'] == 'ok') {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _confirming = false;
          _error = resp['message']?.toString() ?? 'Respuesta inesperada';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = '$e';
      });
    }
  }

  Future<bool?> _confirmDiferencia(Map<String, dynamic> resp) {
    final g = (resp['ganancia_reporte'] as num?)?.toDouble() ?? 0;
    final e = (resp['ganancia_retirada_equivalente'] as num?)?.toDouble() ?? 0;
    final d = (resp['diferencia'] as num?)?.toDouble() ?? 0;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diferencia de ganancia'),
        content: Text(
          'La ganancia retirada equivalente (${_fmt.format(e)} CUP) no coincide '
          'con la ganancia del reporte (${_fmt.format(g)} CUP).\n\n'
          'Diferencia: ${_fmt.format(d)} CUP. ¿Continuar de todas formas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodo =
        '${DateFormat('dd/MM/yyyy').format(widget.desde)} - '
        '${DateFormat('dd/MM/yyyy').format(widget.hasta)}';

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Crear liquidación'),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null && _ventas == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No se pudieron cargar los datos de la liquidación.',
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _load();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            : Form(key: _formKey, child: _buildContent(periodo)),
      ),
      actions: [
        TextButton(
          onPressed: _confirming
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _confirming ||
                  _loading ||
                  !_participacionValida ||
                  !_repartosValidos ||
                  _ventas == null ||
                  _ventas!.ordenesElegibles == 0 ||
                  _cuentaDestino == null
              ? null
              : _confirmar,
          child: _confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirmar'),
        ),
      ],
    );
  }

  Widget _titulo(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _importe(String label, String value, {bool destacado = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _lineaMonto({
    required String label,
    required double? value,
    required String moneda,
    required bool disponible,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              disponible ? '${_fmt.format(value ?? 0)} $moneda' : '—',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoReparto({
    required String label,
    required TextEditingController controller,
    required String moneda,
    required VoidCallback onEdited,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_confirming,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: moneda,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) {
        onEdited();
        setState(() {
          _aplicarRepartosAMedios();
          _error = null;
        });
      },
      validator: (_) => null,
    );
  }

  Widget _seccionReparto({
    required String titulo,
    required String labelA,
    required String labelB,
    required double total,
    required String moneda,
    required TextEditingController ctrlA,
    required TextEditingController ctrlB,
    required void Function({required bool desdeA}) onEdit,
    required bool valido,
  }) {
    final theme = Theme.of(context);
    final suma =
        (_RepartoMoneda.parse(ctrlA.text) ?? 0) +
        (_RepartoMoneda.parse(ctrlB.text) ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Total: ${_fmt.format(total)} $moneda',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _campoReparto(
          label: labelA,
          controller: ctrlA,
          moneda: moneda,
          onEdited: () => onEdit(desdeA: true),
        ),
        const SizedBox(height: 8),
        _campoReparto(
          label: labelB,
          controller: ctrlB,
          moneda: moneda,
          onEdited: () => onEdit(desdeA: false),
        ),
        const SizedBox(height: 6),
        Text(
          valido
              ? 'Suma: ${_fmt.format(suma)} $moneda ✓'
              : 'Suma: ${_fmt.format(suma)} $moneda — debe ser ${_fmt.format(total)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: valido ? theme.colorScheme.primary : theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _bloqueMoneda(FdiTotalMoneda t) {
    final theme = Theme.of(context);
    final r = _repartos[t.moneda];
    if (r == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.moneda,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _lineaMonto(
              label: 'Venta',
              value: t.venta,
              moneda: t.moneda,
              disponible: true,
            ),
            _lineaMonto(
              label: 'Inversión',
              value: t.inversion,
              moneda: t.moneda,
              disponible: t.utilidadCompleta,
            ),
            _lineaMonto(
              label: 'Ganancia',
              value: t.ganancia,
              moneda: t.moneda,
              disponible: t.utilidadCompleta,
            ),
            const Divider(height: 28),
            _seccionReparto(
              titulo: 'Destino de la inversión',
              labelA: 'A cuenta del fondo',
              labelB: 'A liquidación directa',
              total: r.inversionTotal,
              moneda: t.moneda,
              ctrlA: r.inversionCuentaCtrl,
              ctrlB: r.inversionLiquidacionCtrl,
              onEdit: ({required bool desdeA}) =>
                  r.completarPar(inversion: true, desdeA: desdeA),
              valido: r.inversionValida,
            ),
            const SizedBox(height: 20),
            _seccionReparto(
              titulo: 'Destino de la ganancia',
              labelA: 'A liquidación',
              labelB: 'A fondo de inversión',
              total: r.gananciaTotal,
              moneda: t.moneda,
              ctrlA: r.gananciaLiquidacionCtrl,
              ctrlB: r.gananciaFondoCtrl,
              onEdit: ({required bool desdeA}) =>
                  r.completarPar(inversion: false, desdeA: desdeA),
              valido: r.gananciaValida,
            ),
          ],
        ),
      ),
    );
  }

  Widget _destinoCuenta() {
    final hayDeposito = _repartos.values.any((r) => r.montoADepositar > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Cuenta del fondo de inversión'),
        if (!hayDeposito)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sin montos a cuenta/fondo: no se depositará saldo '
              '(la cuenta solo registra la liquidación).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_cuentas.isEmpty)
          const Text(
            'Crea una cuenta activa en Fondo de Inversión → Config para continuar.',
          )
        else
          DropdownButtonFormField<FdiCuenta>(
            initialValue: _cuentaDestino,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cuenta destino',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in _cuentas)
                DropdownMenuItem(
                  value: c,
                  child: Text(
                    '${_conceptos.where((co) => co.id == c.idConcepto).firstOrNull?.denominacion ?? ''} · ${c.nombre}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _confirming
                ? null
                : (c) => setState(() => _cuentaDestino = c),
          ),
      ],
    );
  }

  Widget _repartoInversores() {
    final theme = Theme.of(context);
    final hayGananciaLiquidacion =
        (_ventas?.medios ?? const []).any((m) => m.montoGananciaRetirada > 0);
    if (!hayGananciaLiquidacion) {
      return Text(
        'No hay ganancia a liquidación: no se reparte a inversores.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Reparto entre inversores'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Repartir a partes iguales'),
          subtitle: Text(
            _repartirIgual
                ? '${_inversores.length} inversores activos'
                : 'Usar los porcentajes configurados',
          ),
          value: _repartirIgual,
          onChanged: _confirming || _inversores.isEmpty
              ? null
              : (v) => setState(() => _repartirIgual = v == true),
        ),
        if (!_participacionValida)
          Text(
            _inversores.isEmpty
                ? 'Agrega inversores activos en Fondo de Inversión → Config.'
                : 'Los porcentajes no suman 100%. Usa partes iguales o corrígelos en Config.',
            style: TextStyle(color: theme.colorScheme.error),
          )
        else ...[
          for (var i = 0; i < _inversores.length; i++)
            _importe(
              _repartirIgual
                  ? '${_inversores[i]['nombre']}'
                  : '${_inversores[i]['nombre']} · ${_inversores[i]['porcentaje']}%',
              _porMoneda((m) => _montoInversor(m, i)).entries
                  .where((e) => e.value > 0)
                  .map(
                    (e) => '${NumberFormat('#,##0').format(e.value)} ${e.key}',
                  )
                  .join('\n'),
            ),
        ],
      ],
    );
  }

  Map<String, double> _porMoneda(double Function(FdiVentaMedioMoneda) monto) {
    final totales = <String, double>{};
    for (final medio in _ventas!.medios) {
      totales.update(
        medio.moneda,
        (v) => v + monto(medio),
        ifAbsent: () => monto(medio),
      );
    }
    return totales;
  }

  Widget _buildContent(String periodo) {
    final v = _ventas!;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(periodo, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${v.ordenesElegibles} órdenes por liquidar'
            '${v.ordenesExcluidas > 0 ? ' · ${v.ordenesExcluidas} ya liquidadas excluidas' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final t in _totalesUi) _bloqueMoneda(t),
          Text(
            'Inversión: cuenta del fondo o liquidación directa. '
            'Ganancia: liquidación a inversores o fondo de inversión. '
            'En cada moneda, ambos importes deben sumar el total.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (v.ordenesElegibles == 0)
            const Text('No hay ventas pendientes de liquidar en este período.')
          else ...[
            _destinoCuenta(),
            const Divider(height: 40),
            _repartoInversores(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton(
              onPressed: _confirming
                  ? null
                  : () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _reloadVentas();
                    },
              child: const Text('Recargar montos'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reparto editable por moneda.
///
/// Inversión: cuenta del fondo (depósito) + liquidación directa.
/// Ganancia: liquidación (inversores) + fondo de inversión (depósito).
class _RepartoMoneda {
  final String moneda;
  double inversionTotal;
  double gananciaTotal;

  final inversionCuentaCtrl = TextEditingController();
  final inversionLiquidacionCtrl = TextEditingController();
  final gananciaLiquidacionCtrl = TextEditingController();
  final gananciaFondoCtrl = TextEditingController();

  _RepartoMoneda({
    required this.moneda,
    required this.inversionTotal,
    required this.gananciaTotal,
  }) {
    _setDefaults();
  }

  void _setDefaults() {
    // Default: inversión a cuenta; ganancia a liquidación.
    inversionCuentaCtrl.text = _fmt(inversionTotal);
    inversionLiquidacionCtrl.text = _fmt(0);
    gananciaLiquidacionCtrl.text = _fmt(gananciaTotal);
    gananciaFondoCtrl.text = _fmt(0);
  }

  void actualizarTotales({
    required double inversion,
    required double ganancia,
  }) {
    inversionTotal = inversion;
    gananciaTotal = ganancia;
    if (_enDefault) {
      _setDefaults();
    }
  }

  bool get _enDefault {
    final invC = parse(inversionCuentaCtrl.text) ?? -1;
    final invL = parse(inversionLiquidacionCtrl.text) ?? -1;
    final ganL = parse(gananciaLiquidacionCtrl.text) ?? -1;
    final ganF = parse(gananciaFondoCtrl.text) ?? -1;
    return invL == 0 && ganF == 0 && invC >= 0 && ganL >= 0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);

  static double? parse(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Al editar un destino, completa el otro para que sumen el total.
  void completarPar({
    required bool inversion,
    required bool desdeA,
  }) {
    final total = inversion ? inversionTotal : gananciaTotal;
    final aCtrl = inversion
        ? (desdeA ? inversionCuentaCtrl : inversionLiquidacionCtrl)
        : (desdeA ? gananciaLiquidacionCtrl : gananciaFondoCtrl);
    final bCtrl = inversion
        ? (desdeA ? inversionLiquidacionCtrl : inversionCuentaCtrl)
        : (desdeA ? gananciaFondoCtrl : gananciaLiquidacionCtrl);
    final a = parse(aCtrl.text);
    if (a == null || a < 0) return;
    final b = double.parse((total - a).clamp(0.0, total).toStringAsFixed(2));
    bCtrl.text = _fmt(b);
  }

  double get inversionACuenta => parse(inversionCuentaCtrl.text) ?? 0;
  double get inversionALiquidacion => parse(inversionLiquidacionCtrl.text) ?? 0;
  double get gananciaALiquidacion => parse(gananciaLiquidacionCtrl.text) ?? 0;
  double get gananciaAFondo => parse(gananciaFondoCtrl.text) ?? 0;

  /// Lo que se deposita en la cuenta FDI seleccionada.
  double get montoADepositar =>
      double.parse((inversionACuenta + gananciaAFondo).toStringAsFixed(2));

  bool _parValido(double total, TextEditingController a, TextEditingController b) {
    final va = parse(a.text);
    final vb = parse(b.text);
    if (va == null || vb == null || va < 0 || vb < 0) return false;
    return (va + vb - total).abs() < 0.015;
  }

  bool get inversionValida => _parValido(
    inversionTotal,
    inversionCuentaCtrl,
    inversionLiquidacionCtrl,
  );

  bool get gananciaValida => _parValido(
    gananciaTotal,
    gananciaLiquidacionCtrl,
    gananciaFondoCtrl,
  );

  bool get esValido => inversionValida && gananciaValida;

  void dispose() {
    inversionCuentaCtrl.dispose();
    inversionLiquidacionCtrl.dispose();
    gananciaLiquidacionCtrl.dispose();
    gananciaFondoCtrl.dispose();
  }
}
