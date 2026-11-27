import 'dart:math';
import 'package:flutter/material.dart';
import '../models/fondo_inversion.dart';

class FdiRecepcionFuentes extends StatefulWidget {
  final List<FdiSaldo> saldos;
  final double total;
  final String moneda;
  final ValueChanged<List<FdiFuenteRecepcion>> onChanged;
  final bool enabled;

  /// Tasa USD→CUP configurada de la tienda. Con ella se sugiere la tasa y el
  /// importe cuando la cuenta y la compra están en monedas distintas.
  final double? tasaUsdCup;

  const FdiRecepcionFuentes({
    super.key,
    required this.saldos,
    required this.total,
    required this.moneda,
    required this.onChanged,
    this.enabled = true,
    this.tasaUsdCup,
  });

  @override
  State<FdiRecepcionFuentes> createState() => _FdiRecepcionFuentesState();
}

class _FdiRecepcionFuentesState extends State<FdiRecepcionFuentes> {
  final _montos = <int, double>{};
  final _tasas = <int, double>{};

  /// Unidades de la moneda de la compra por 1 unidad de la cuenta.
  double _tasaSugerida(FdiSaldo saldo) {
    if (saldo.moneda == widget.moneda) return 1;
    final rate = widget.tasaUsdCup;
    if (rate == null || !rate.isFinite || rate <= 0) return 0;
    if (saldo.moneda == 'CUP' && widget.moneda == 'USD') return 1 / rate;
    if (saldo.moneda == 'USD' && widget.moneda == 'CUP') return rate;
    return 0;
  }

  List<FdiFuenteRecepcion> get _fuentes => [
    for (final i in _montos.keys)
      FdiFuenteRecepcion(
        saldo: widget.saldos[i],
        monto: _montos[i]!,
        tasaARef: widget.saldos[i].moneda == widget.moneda
            ? 1
            : (_tasas[i] ?? 0),
      ),
  ];

  double get _cubierto => _fuentes.fold(0, (s, f) => s + f.equivalente);

  void _notify() => widget.onChanged(_fuentes);

  @override
  Widget build(BuildContext context) {
    final error = FdiFuenteRecepcion.validar(
      _fuentes,
      widget.total,
      widget.moneda,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fuentes del fondo: seleccione las cuentas y cuánto usar de cada una.',
        ),
        for (var i = 0; i < widget.saldos.length; i++) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${widget.saldos[i].concepto} · ${widget.saldos[i].cuenta}',
            ),
            subtitle: Text(
              '${widget.saldos[i].medioPago} · Disponible: '
              '${widget.saldos[i].saldo.toStringAsFixed(2)} ${widget.saldos[i].moneda}',
            ),
            value: _montos.containsKey(i),
            onChanged: !widget.enabled
                ? null
                : (selected) {
                    setState(() {
                      if (selected == true) {
                        final saldo = widget.saldos[i];
                        final tasa = _tasaSugerida(saldo);
                        final faltante =
                            max(0.0, widget.total - _cubierto);
                        double monto;
                        if (saldo.moneda == widget.moneda) {
                          monto = min(saldo.saldo, faltante);
                        } else if (tasa > 0) {
                          // Se completa el equivalente que falta y se deja la
                          // tasa de la tienda lista para editar.
                          monto = min(saldo.saldo, faltante / tasa);
                          _tasas[i] = tasa;
                        } else {
                          monto = 0;
                        }
                        _montos[i] = double.parse(monto.toStringAsFixed(2));
                      } else {
                        _montos.remove(i);
                        _tasas.remove(i);
                      }
                    });
                    _notify();
                  },
          ),
          if (_montos.containsKey(i)) ...[
            TextFormField(
              key: ValueKey('fdi-monto-$i'),
              initialValue: _montos[i]!.toStringAsFixed(2),
              enabled: widget.enabled,
              decoration: InputDecoration(
                labelText: 'Usar de esta cuenta (${widget.saldos[i].moneda})',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) {
                setState(
                  () =>
                      _montos[i] = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                );
                _notify();
              },
            ),
            if (widget.saldos[i].moneda != widget.moneda) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey('fdi-tasa-$i-${_tasas[i]}'),
                initialValue: (_tasas[i] ?? 0) > 0
                    ? _tasas[i]!.toStringAsFixed(
                        _tasas[i]! >= 1 ? 4 : 10,
                      )
                    : '',
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText:
                      '1 ${widget.saldos[i].moneda} equivale a cuántos ${widget.moneda}',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  final tasa = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  setState(
                    () => _tasas[i] = tasa.isFinite
                        ? double.parse(tasa.toStringAsFixed(12))
                        : 0,
                  );
                  _notify();
                },
              ),
            ],
            Text(
              'Aporta: ${FdiFuenteRecepcion(saldo: widget.saldos[i], monto: _montos[i]!, tasaARef: widget.saldos[i].moneda == widget.moneda ? 1 : (_tasas[i] ?? 0)).equivalente.toStringAsFixed(2)} ${widget.moneda}',
            ),
            const SizedBox(height: 12),
          ],
        ],
        Text(
          'Cubierto: ${_cubierto.toStringAsFixed(2)} / ${widget.total.toStringAsFixed(2)} ${widget.moneda}',
        ),
        Text(
          'Pendiente: ${max(0, widget.total - _cubierto).toStringAsFixed(2)} ${widget.moneda}',
        ),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
