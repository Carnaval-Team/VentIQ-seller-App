import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fondo_inversion.dart';
import '../services/fondo_inversion_service.dart';
import '../services/user_preferences_service.dart';

/// Diálogo "Crear liquidación" del Fondo de Inversión.
///
/// Muestra las ventas elegibles del periodo por medio de pago + moneda,
/// permite retirar ganancia por línea, valida la ganancia contra el reporte
/// con una tasa y confirma la creación (idempotente por clave).
class FdiLiquidacionDialog extends StatefulWidget {
  final DateTime desde;
  final DateTime hasta;
  const FdiLiquidacionDialog({
    super.key,
    required this.desde,
    required this.hasta,
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
  Set<FdiVentaMedioMoneda> get _origenes => _seleccion.origenes;

  bool get _requiereTasa => _origenes.any((m) => m.moneda != 'CUP');

  void _seleccionarOrigen(FdiVentaMedioMoneda medio, bool selected) {
    setState(() {
      _seleccion.seleccionar(
        medio,
        selected,
        pendienteCup: (_ventas?.gananciaCup ?? 0) - _retiradaEquivalenteCup,
        tasaCup: double.tryParse(_tasaCtrl.text.replaceAll(',', '.')),
      );
      _reasignarGanancias();
    });
  }

  /// Reparte la ganancia completa entre los orígenes seleccionados,
  /// en el orden en que fueron marcados. No se introduce manualmente.
  void _reasignarGanancias() {
    final tasa = double.tryParse(_tasaCtrl.text.replaceAll(',', '.'));
    var pendienteCup = _ventas?.gananciaCup ?? 0;
    for (final m in _origenes) {
      final t = m.moneda == 'CUP' ? 1.0 : tasa;
      if (t == null || !t.isFinite || t <= 0) {
        m.montoGananciaRetirada = 0;
        continue;
      }
      m.montoGananciaRetirada = double.parse(
        (pendienteCup.clamp(0.0, double.infinity) / t)
            .clamp(0.0, m.montoVendido)
            .toStringAsFixed(2),
      );
      pendienteCup -= m.montoGananciaRetirada * t;
    }
  }

  bool _repartirIgual = false;

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
  final _tasaCtrl = TextEditingController();
  late final String _idemKey;
  static const _modo = 'creacion';

  @override
  void initState() {
    super.initState();
    _idemKey = _service.newIdempotencyKey();
    _load();
  }

  @override
  void dispose() {
    _tasaCtrl.dispose();
    super.dispose();
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
      // Default: una única combinación CUP recibe la ganancia del reporte;
      // con varios medios o monedas, el dueño selecciona los orígenes.
      // Lo no seleccionado va íntegramente al fondo.
      _seleccion.inicializar(ventas);
      setState(() {
        _idTienda = idTienda;
        _ventas = ventas;
        _conceptos = results[1] as List<FdiConcepto>;
        _cuentas = results[2] as List<FdiCuenta>;
        _inversores = (results[3] as List<Map<String, dynamic>>)
            .where((i) => i['activo'] == true)
            .toList();
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

  /// Recarga solo las ventas del periodo al reintentar una liquidación.
  Future<void> _reloadVentas() async {
    try {
      final ventas = await _service.ventasPorMedioMoneda(
        idTienda: _idTienda!,
        desde: widget.desde,
        hasta: widget.hasta,
        modo: _modo,
      );
      if (!mounted) return;
      _seleccion.inicializar(ventas);
      setState(() {
        _ventas = ventas;
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
    if (!_participacionValida) return 0;
    if (_repartirIgual) {
      // Partes iguales truncadas a enteros (como el trigger); la
      // diferencia con el 100% queda en el fondo.
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

  double get _retiradaEquivalenteCup {
    final ventas = _ventas;
    if (ventas == null) return 0;
    final tasa = double.tryParse(_tasaCtrl.text.replaceAll(',', '.')) ?? 0;
    var total = 0.0;
    for (final m in _origenes) {
      total += m.moneda == 'CUP'
          ? m.montoGananciaRetirada
          : m.montoGananciaRetirada * (tasa > 0 ? tasa : 0);
    }
    return total;
  }

  double get _diferencia =>
      _retiradaEquivalenteCup - (_ventas?.gananciaCup ?? 0);

  Future<void> _confirmar() async {
    final ventas = _ventas;
    final idTienda = _idTienda;
    final cuenta = _cuentaDestino;
    if (ventas == null ||
        idTienda == null ||
        cuenta == null ||
        _confirming ||
        _loading ||
        !_participacionValida) {
      return;
    }

    if (_formKey.currentState?.validate() != true) return;
    if (ventas.gananciaCup > 0 &&
        !_origenes.any((m) => m.montoGananciaRetirada > 0)) {
      setState(
        () => _error =
            'Selecciona un origen para repartir la ganancia. Si usa otra moneda, indica la tasa a CUP.',
      );
      return;
    }

    final detalle = _seleccion.detalle;

    setState(() => _confirming = true);
    try {
      final tasa = _requiereTasa
          ? double.tryParse(_tasaCtrl.text.replaceAll(',', '.'))
          : null;
      var resp = await _service.crearLiquidacion(
        idTienda: idTienda,
        desde: widget.desde,
        hasta: widget.hasta,
        modo: _modo,
        idCuentaDestino: cuenta.id,
        detalle: detalle,
        tasaValidacion: tasa,
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
          idCuentaDestino: cuenta.id,
          detalle: detalle,
          tasaValidacion: tasa,
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
          'La ganancia retirada equivalente (\$${_fmt.format(e)}) no coincide '
          'con la ganancia del reporte (\$${_fmt.format(g)}).\n\n'
          'Diferencia: \$${_fmt.format(d)}. ¿Continuar de todas formas?',
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

  double _asignado(FdiVentaMedioMoneda medio) => List.generate(
    _inversores.length,
    (i) => _montoInversor(medio, i),
  ).fold<double>(0, (a, b) => a + b);

  Widget _destino() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titulo('1. Cuenta destino'),
      if (_cuentas.isEmpty)
        const Text(
          'Crea una cuenta activa en Fondo de Inversión → Config para continuar.',
        )
      else
        DropdownButtonFormField<FdiCuenta>(
          initialValue: _cuentaDestino,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Cuenta del fondo',
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

  Widget _origenGanancia() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titulo('2. Origen de la ganancia'),
      const Text(
        'Selecciona de dónde sale el reparto. Lo no seleccionado queda en el fondo.',
      ),
      const SizedBox(height: 8),
      for (final m in _ventas!.medios)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('${m.medioPago} · ${m.moneda}'),
          subtitle: Text(
            'Disponible: ${_fmt.format(m.montoVendido)} ${m.moneda}',
          ),
          value: _origenes.contains(m),
          onChanged: _confirming
              ? null
              : (selected) => _seleccionarOrigen(m, selected == true),
        ),
      if (_requiereTasa) ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: _tasaCtrl,
          validator: (s) {
            final tasa = double.tryParse((s ?? '').replaceAll(',', '.'));
            return tasa == null || !tasa.isFinite || tasa <= 0
                ? 'Indica una tasa positiva'
                : null;
          },
          enabled: !_confirming,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tasa a CUP',
            helperText: 'Solo para comparar con la ganancia del reporte.',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(_reasignarGanancias),
        ),
      ],
      if (_origenes.any((m) => m.montoGananciaRetirada > 0))
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Validación del importe'),
          subtitle: _diferencia.abs() > 0.01
              ? const Text('Hay una diferencia con el reporte')
              : null,
          children: [
            _importe(
              'Equivalente seleccionado',
              '${_fmt.format(_retiradaEquivalenteCup)} CUP',
            ),
            _importe(
              'Diferencia con el reporte',
              '${_fmt.format(_diferencia)} CUP',
            ),
          ],
        ),
    ],
  );

  Widget _reparto() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('3. Reparto entre inversores'),
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
                  .map(
                    (e) => '${NumberFormat('#,##0').format(e.value)} ${e.key}',
                  )
                  .join('\n'),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in _porMoneda(_asignado).entries)
                  _importe(
                    'Para inversores',
                    '${NumberFormat('#,##0').format(e.value)} ${e.key}',
                    destacado: true,
                  ),
                const Divider(height: 16),
                for (final e in _porMoneda(
                  (m) => m.montoVendido - _asignado(m),
                ).entries)
                  _importe(
                    'Al fondo',
                    '${_fmt.format(e.value)} ${e.key}',
                    destacado: true,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Importes enteros, pendientes de pago. Todo sobrante queda en el fondo.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
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
            '${v.ordenesElegibles} órdenes por liquidar',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ganancia del período',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt.format(v.gananciaCup)} CUP',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Resumen de ventas'),
            children: [
              _importe('Venta', '${_fmt.format(v.ventaTotalCup)} CUP'),
              _importe('Costo', '${_fmt.format(v.costoTotalCup)} CUP'),
              if (v.ordenesExcluidas > 0)
                Text(
                  '${v.ordenesExcluidas} órdenes ya liquidadas excluidas.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (v.ordenesElegibles == 0)
            const Text('No hay ventas pendientes de liquidar en este período.')
          else ...[
            _destino(),
            const Divider(height: 40),
            _origenGanancia(),
            const Divider(height: 40),
            _reparto(),
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
