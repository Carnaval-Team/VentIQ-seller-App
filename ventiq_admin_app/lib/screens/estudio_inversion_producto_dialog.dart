import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/estudio_inversion.dart';
import '../services/currency_service.dart';
import '../services/estudio_inversion_service.dart';

/// Abre el estudio histórico de inversión del producto.
Future<void> showEstudioInversionProducto(
  BuildContext context, {
  required int idProducto,
  required String nombreProducto,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => EstudioInversionProductoDialog(
      idProducto: idProducto,
      nombreProducto: nombreProducto,
    ),
  );
}

class EstudioInversionProductoDialog extends StatelessWidget {
  final int idProducto;
  final String nombreProducto;

  const EstudioInversionProductoDialog({
    super.key,
    required this.idProducto,
    required this.nombreProducto,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final futuro = EstudioInversionService().cargar(idProducto);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: size.width - 24,
        height: size.height - 24,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombreProducto,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Estudio de inversión · historia completa',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<EstudioInversion>(
                future: futuro,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar el estudio: ${snapshot.error}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    );
                  }
                  return _Cuerpo(estudio: snapshot.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cuerpo extends StatefulWidget {
  final EstudioInversion estudio;

  const _Cuerpo({required this.estudio});

  @override
  State<_Cuerpo> createState() => _CuerpoState();
}

class _CuerpoState extends State<_Cuerpo> {
  double? _tasa;
  double? _precioUsd;
  bool _precioListo = false;
  bool _tasaLista = false;

  @override
  void initState() {
    super.initState();
    _cargarTasa();
  }

  Future<void> _cargarTasa() async {
    try {
      final tasa = await CurrencyService.getEffectiveUsdToCupRate();
      if (!mounted) return;
      setState(() {
        _tasa = tasa > 0 ? tasa : null;
        _tasaLista = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _tasaLista = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estudio = widget.estudio;
    if (estudio.tramos.isEmpty && !estudio.datosIncompletos) {
      return const Center(child: Text('No hay recepciones completadas de este producto.'));
    }
    final tramos = estudio.delMasRecienteAlMasAntiguo;
    TramoInversion? abierto;
    for (final tramo in tramos) {
      if (tramo.enCurso) {
        abierto = tramo;
        break;
      }
    }
    final proyeccion = abierto ?? (tramos.isEmpty ? null : tramos.first);
    final precio = _precioListo ? _precioUsd : estudio.precioActualUsd;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (estudio.datosIncompletos)
          const _Aviso(
            'Hay recepciones sin factor de presentación. No entran en la meta y el corte por agotado puede quedar incompleto.',
          ),
        for (final tramo in tramos) _Resumen(tramo: tramo),
        if (proyeccion != null)
          _VentaInventario(
            tramo: proyeccion,
            existenciasBase: estudio.existenciasDe(proyeccion),
            precioUsd: precio,
            tasa: _tasa,
            cargandoTasa: !_tasaLista,
            precioInicialUsd: estudio.precioActualUsd,
            precioInicialCup: estudio.precioActualCup,
            mostrarTramo: tramos.length > 1,
            onChanged: (usd) => setState(() {
              _precioUsd = usd;
              _precioListo = true;
            }),
          ),
      ],
    );
  }
}

class _Resumen extends StatelessWidget {
  final TramoInversion tramo;

  const _Resumen({required this.tramo});

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat('dd/MM/yyyy');
    final cierre = tramo.fin == null ? 'en curso' : 'agotado el ${fecha.format(tramo.fin!)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Resumen', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Text(
              '${fecha.format(tramo.inicio)} → $cierre',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _Pastel(tramo: tramo),
            const SizedBox(height: 12),
            _par('Meta', _usd(tramo.meta)),
            _par('Recaudado', _usd(tramo.recaudado)),
            if (tramo.incompleto)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Recaudado incompleto: hay ventas sin tasa de ese día',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VentaInventario extends StatelessWidget {
  final TramoInversion tramo;
  final double existenciasBase;
  final double? precioUsd;
  final double? tasa;
  final bool cargandoTasa;
  final double? precioInicialUsd;
  final double? precioInicialCup;
  final bool mostrarTramo;
  final ValueChanged<double?> onChanged;

  const _VentaInventario({
    required this.tramo,
    required this.existenciasBase,
    required this.precioUsd,
    required this.tasa,
    required this.cargandoTasa,
    required this.precioInicialUsd,
    required this.precioInicialCup,
    required this.mostrarTramo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat('dd/MM/yyyy');
    final prediccion = predecirInversion(
      meta: tramo.meta,
      recaudado: tramo.recaudado,
      incompleto: tramo.incompleto,
      existenciasBase: existenciasBase,
      precioActualUsd: precioUsd,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Si se vende el inventario', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (mostrarTramo)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Inversión desde ${fecha.format(tramo.inicio)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            _par('En inventario', '${_cantidad(existenciasBase)} u.'),
            const SizedBox(height: 12),
            _PrecioTeorico(
              tasa: tasa,
              cargando: cargandoTasa,
              precioUsd: precioInicialUsd,
              precioCup: precioInicialCup,
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            if (prediccion.incompleta)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'El cálculo espera un recaudado completo.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              )
            else if (prediccion.sinPrecio)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Escribe un precio mayor que cero para valorar el inventario.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              )
            else ...[
              _par('Valor del inventario', _usd(prediccion.valorExistenciasUsd!)),
              _par('Recaudado + inventario', _usd(prediccion.proyectadoUsd!)),
              _par(
                prediccion.esGanancia ? 'Ganancia' : 'Resultado',
                _usd(prediccion.gananciaUsd!),
              ),
              _par('Sobre la inversión', _porciento(prediccion.porcentajeGanancia!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrecioTeorico extends StatefulWidget {
  final double? tasa;
  final bool cargando;
  final double? precioUsd;
  final double? precioCup;
  final ValueChanged<double?> onChanged;

  const _PrecioTeorico({
    required this.tasa,
    required this.cargando,
    required this.precioUsd,
    required this.precioCup,
    required this.onChanged,
  });

  @override
  State<_PrecioTeorico> createState() => _PrecioTeoricoState();
}

class _PrecioTeoricoState extends State<_PrecioTeorico> {
  final _cup = TextEditingController();
  final _usd = TextEditingController();
  String? _origen;
  bool _precargado = false;

  @override
  void initState() {
    super.initState();
    _precargar();
  }

  @override
  void didUpdateWidget(covariant _PrecioTeorico oldWidget) {
    super.didUpdateWidget(oldWidget);
    _precargar();
  }

  @override
  void dispose() {
    _cup.dispose();
    _usd.dispose();
    super.dispose();
  }

  void _precargar() {
    if (_precargado) return;
    final tasa = widget.tasa;
    final hayUsd = widget.precioUsd != null && widget.precioUsd! > 0;
    final hayCup = widget.precioCup != null && widget.precioCup! > 0;
    if (!hayUsd && !hayCup) {
      if (!widget.cargando) _precargado = true;
      return;
    }
    double? usd = hayUsd ? widget.precioUsd : null;
    double? cup = hayCup ? widget.precioCup : null;
    if (usd == null && cup != null) {
      if (tasa == null) return;
      usd = usdDesdeCup(cup: cup, tasaUsdACup: tasa);
    }
    if (cup == null && usd != null) {
      if (tasa == null) return;
      cup = cupDesdeUsd(usd: usd, tasaUsdACup: tasa);
    }
    _precargado = true;
    _origen = 'precarga';
    if (cup != null) _cup.text = _texto(cup);
    if (usd != null) _usd.text = _texto(usd);
    _origen = null;
    final notificar = usd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onChanged(notificar != null && notificar > 0 ? notificar : null);
    });
  }

  void _cambiarCup(String texto) {
    if (_origen == 'usd' || _origen == 'precarga') return;
    _origen = 'cup';
    final cup = parsearPrecioTeorico(texto);
    final tasa = widget.tasa;
    double? usd;
    if (tasa != null) {
      usd = cup == null ? null : usdDesdeCup(cup: cup, tasaUsdACup: tasa);
      _usd.text = usd == null ? '' : _texto(usd);
    } else {
      usd = parsearPrecioTeorico(_usd.text);
    }
    _origen = null;
    widget.onChanged(usd != null && usd > 0 ? usd : null);
  }

  void _cambiarUsd(String texto) {
    if (_origen == 'cup' || _origen == 'precarga') return;
    _origen = 'usd';
    final usd = parsearPrecioTeorico(texto);
    final tasa = widget.tasa;
    if (tasa != null) {
      final cup = usd == null ? null : cupDesdeUsd(usd: usd, tasaUsdACup: tasa);
      _cup.text = cup == null ? '' : _texto(cup);
    }
    _origen = null;
    widget.onChanged(usd != null && usd > 0 ? usd : null);
  }

  String _texto(double valor) {
    var texto = valor.toStringAsFixed(4);
    texto = texto.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return texto;
  }

  @override
  Widget build(BuildContext context) {
    final tasa = widget.tasa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tasa == null
              ? (widget.cargando
                  ? 'Cargando la tasa vigente de la tienda…'
                  : 'No hay tasa vigente de la tienda.')
              : 'Precio de venta actual. 1 USD = ${_texto(tasa)} CUP.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _casilla('CUP', _cup, _cambiarCup, !widget.cargando)),
            const SizedBox(width: 12),
            Expanded(child: _casilla('USD', _usd, _cambiarUsd, !widget.cargando)),
          ],
        ),
      ],
    );
  }

  Widget _casilla(
    String moneda,
    TextEditingController controlador,
    ValueChanged<String> alCambiar,
    bool habilitada,
  ) {
    return TextField(
      controller: controlador,
      enabled: habilitada,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: alCambiar,
      decoration: InputDecoration(
        labelText: moneda,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _Pastel extends StatelessWidget {
  final TramoInversion tramo;

  const _Pastel({required this.tramo});

  @override
  Widget build(BuildContext context) {
    final texto = _porcentaje(tramo);
    final ratio = tramo.cumplimiento;
    if (ratio == null) {
      return SizedBox(height: 120, child: Center(child: Text(texto)));
    }
    final cubierto = ratio.clamp(0, 1).toDouble();
    final pendiente = (1 - cubierto).clamp(0, 1).toDouble();
    return SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 0,
              centerSpaceRadius: 52,
              sections: [
                PieChartSectionData(
                  value: cubierto == 0 ? 0.0001 : cubierto,
                  color: AppColors.primary,
                  radius: 28,
                  showTitle: false,
                ),
                if (pendiente > 0)
                  PieChartSectionData(
                    value: pendiente,
                    color: AppColors.border,
                    radius: 28,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;

  const _Aviso(this.texto);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto),
    );
  }
}

Widget _par(String etiqueta, String valor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(etiqueta)),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

String _porcentaje(TramoInversion tramo) {
  if (tramo.meta <= 0) return 'Sin costo';
  if (tramo.incompleto) {
    return 'Recaudado incompleto: hay ventas sin tasa de ese día';
  }
  return '${(tramo.cumplimiento! * 100).toStringAsFixed(1)} %';
}

String _usd(double valor) => _moneda(valor, 'USD');

String _moneda(double valor, String codigo) {
  final texto = NumberFormat.currency(locale: 'es', symbol: '\$').format(valor);
  return '$texto $codigo';
}

String _porciento(double ratio) => '${(ratio * 100).toStringAsFixed(1)} %';

String _cantidad(double valor) {
  if (valor == valor.roundToDouble()) return valor.toStringAsFixed(0);
  return valor.toStringAsFixed(2);
}
