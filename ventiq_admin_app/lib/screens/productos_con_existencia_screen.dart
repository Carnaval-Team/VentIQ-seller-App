import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../services/estudio_inversion_service.dart';
import 'estudio_inversion_producto_dialog.dart';

/// Productos con saldo positivo. Cada uno abre el mismo estudio de inversión.
class ProductosConExistenciaScreen extends StatefulWidget {
  const ProductosConExistenciaScreen({super.key});

  @override
  State<ProductosConExistenciaScreen> createState() => _ProductosConExistenciaScreenState();
}

class _ProductosConExistenciaScreenState extends State<ProductosConExistenciaScreen> {
  late final Future<List<ProductoConExistencia>> _futuro;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _futuro = EstudioInversionService().listarConExistencia();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos con existencia'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<ProductoConExistencia>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar el inventario: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }
          final productos = snapshot.data!;
          final filtro = _busqueda.trim().toLowerCase();
          final visibles = filtro.isEmpty
              ? productos
              : productos.where((p) => p.nombre.toLowerCase().contains(filtro)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (texto) => setState(() => _busqueda = texto),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${visibles.length} con existencia',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: visibles.isEmpty
                    ? const Center(child: Text('Ningún producto tiene existencia ahora.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: visibles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _TarjetaProducto(producto: visibles[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  final ProductoConExistencia producto;

  const _TarjetaProducto({required this.producto});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showEstudioInversionProducto(
          context,
          idProducto: producto.idProducto,
          nombreProducto: producto.nombre,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_cantidad(producto.existenciasBase)} u. en inventario',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    _linea('Costo', _precio(producto.costoUnitarioUsd)),
                    const SizedBox(height: 2),
                    _linea('Venta', _venta(producto)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PastelLista(cumplimiento: producto.cumplimiento),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastelLista extends StatelessWidget {
  final double? cumplimiento;

  const _PastelLista({required this.cumplimiento});

  @override
  Widget build(BuildContext context) {
    final ratio = cumplimiento;
    final texto = ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(0)}%';
    final cubierto = ratio == null ? 0.0 : ratio.clamp(0, 1).toDouble();
    final pendiente = (1 - cubierto).clamp(0, 1).toDouble();
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 0,
              centerSpaceRadius: 24,
              sections: ratio == null
                ? [
                    PieChartSectionData(
                      value: 1,
                      color: AppColors.border,
                      radius: 10,
                      showTitle: false,
                    ),
                  ]
                : [
                    PieChartSectionData(
                      value: cubierto == 0 ? 0.0001 : cubierto,
                      color: AppColors.primary,
                      radius: 10,
                      showTitle: false,
                    ),
                    if (pendiente > 0)
                      PieChartSectionData(
                        value: pendiente,
                        color: AppColors.border,
                        radius: 10,
                        showTitle: false,
                      ),
                  ],
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _linea(String etiqueta, String valor) {
  return Row(
    children: [
      SizedBox(
        width: 52,
        child: Text(
          etiqueta,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
      Expanded(
        child: Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

String _venta(ProductoConExistencia producto) {
  if (producto.precioUsd != null) return _moneda(producto.precioUsd!, 'USD');
  if (producto.precioCup != null) return _moneda(producto.precioCup!, 'CUP');
  return 'Sin precio';
}

String _precio(double? valor) {
  if (valor == null) return 'Sin costo';
  return _moneda(valor, 'USD');
}

String _cantidad(double valor) {
  if (valor == valor.roundToDouble()) return valor.toStringAsFixed(0);
  return valor.toStringAsFixed(2);
}

String _moneda(double valor, String codigo) {
  final texto = NumberFormat.currency(locale: 'es', symbol: '\$').format(valor);
  return '$texto $codigo';
}
