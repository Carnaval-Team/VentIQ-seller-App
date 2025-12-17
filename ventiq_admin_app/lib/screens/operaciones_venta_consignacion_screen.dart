import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/consignacion_movimientos_service.dart';
import 'detalle_operacion_venta_screen.dart';

/// Pantalla para listar operaciones de venta de un contrato con filtros por fechas
class OperacionesVentaConsignacionScreen extends StatefulWidget {
  final int contratoId;
  final String nombreConsignadora;
  final String nombreConsignataria;

  const OperacionesVentaConsignacionScreen({
    Key? key,
    required this.contratoId,
    required this.nombreConsignadora,
    required this.nombreConsignataria,
  }) : super(key: key);

  @override
  State<OperacionesVentaConsignacionScreen> createState() =>
      _OperacionesVentaConsignacionScreenState();
}

class _OperacionesVentaConsignacionScreenState
    extends State<OperacionesVentaConsignacionScreen> {
  List<Map<String, dynamic>> _movimientos = [];
  bool _isLoading = true;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  double _totalMontoFiltrado = 0.0;
  int _totalOperacionesFiltradas = 0;

  @override
  void initState() {
    super.initState();
    _loadMovimientos();
  }

  Future<void> _loadMovimientos() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('📊 Cargando operaciones de venta para contrato: ${widget.contratoId}');

      final movimientos = await ConsignacionMovimientosService.getMovimientosConsignacion(
        idContrato: widget.contratoId,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );

      if (mounted) {
        // Calcular totales usando importe_total de cada movimiento
        double totalMonto = 0.0;
        Set<int> operacionesUnicas = {};

        for (final mov in movimientos) {
          final importe = (mov['importe_total'] as num?)?.toDouble() ?? 0.0;
          totalMonto += importe;
          final idOperacion = mov['id_operacion'] as int? ?? 0;
          if (idOperacion > 0) {
            operacionesUnicas.add(idOperacion);
          }
        }

        setState(() {
          _movimientos = movimientos;
          _totalMontoFiltrado = totalMonto;
          _totalOperacionesFiltradas = operacionesUnicas.length;
          _isLoading = false;
        });

        debugPrint('✅ Operaciones cargadas: ${movimientos.length}');
        debugPrint('   Total operaciones únicas: ${operacionesUnicas.length}');
        debugPrint('   Total monto: \$${totalMonto.toStringAsFixed(2)}');
      }
    } catch (e) {
      debugPrint('❌ Error cargando operaciones: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _seleccionarFechaDesde() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaDesde ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (fecha != null) {
      setState(() => _fechaDesde = fecha);
      _loadMovimientos();
    }
  }

  Future<void> _seleccionarFechaHasta() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaHasta ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (fecha != null) {
      setState(() => _fechaHasta = fecha);
      _loadMovimientos();
    }
  }

  void _limpiarFiltros() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
    });
    _loadMovimientos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Operaciones de Venta'),
            Text(
              '${widget.nombreConsignadora} → ${widget.nombreConsignataria}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros de fecha
                _buildFiltrosCard(),
                const Divider(height: 1),

                // Resumen
                _buildResumenCard(),
                const Divider(height: 1),

                // Lista de movimientos
                Expanded(
                  child: _movimientos.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadMovimientos,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _movimientos.length,
                            itemBuilder: (context, index) {
                              return _buildMovimientoCard(_movimientos[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFiltrosCard() {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtros de Fecha',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _seleccionarFechaDesde,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Desde',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          _fechaDesde != null
                              ? dateFormat.format(_fechaDesde!)
                              : 'Seleccionar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _fechaDesde != null ? Colors.blue : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _seleccionarFechaHasta,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hasta',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          _fechaHasta != null
                              ? dateFormat.format(_fechaHasta!)
                              : 'Seleccionar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _fechaHasta != null ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_fechaDesde != null || _fechaHasta != null)
                ElevatedButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Limpiar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumenCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Operaciones',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  '$_totalOperacionesFiltradas',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Monto',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  '\$${_totalMontoFiltrado.toStringAsFixed(2)} USD',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay operaciones de venta',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fechaDesde != null || _fechaHasta != null
                ? 'Intenta con otros filtros de fecha'
                : 'Aún no hay movimientos registrados',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientoCard(Map<String, dynamic> movimiento) {
    final idOperacion = movimiento['id_operacion'] as int? ?? 0;
    final cantidad = (movimiento['cantidad_vendida'] as num?)?.toDouble() ?? 0.0;
    final denominacionProducto = movimiento['denominacion_producto'] as String? ?? 'Producto desconocido';
    final importe = (movimiento['importe_total'] as num?)?.toDouble() ?? 0.0;
    final fechaVentaStr = movimiento['fecha_venta'] as String?;
    final fechaCreacion = fechaVentaStr != null ? DateTime.parse(fechaVentaStr) : DateTime.now();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.shopping_bag,
            color: Colors.green.shade700,
          ),
        ),
        title: Text(
          denominacionProducto ?? 'Producto desconocido',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Op. #$idOperacion | Cantidad: ${cantidad.toStringAsFixed(0)} | Monto: \$${importe.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              dateFormat.format(fechaCreacion),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalleOperacionVentaScreen(
                operacionId: idOperacion,
                contratoId: widget.contratoId,
              ),
            ),
          );
        },
      ),
    );
  }
}
