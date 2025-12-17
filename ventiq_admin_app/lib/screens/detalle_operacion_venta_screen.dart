import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla para ver el detalle de una operación de venta específica
class DetalleOperacionVentaScreen extends StatefulWidget {
  final int operacionId;
  final int contratoId;

  const DetalleOperacionVentaScreen({
    Key? key,
    required this.operacionId,
    required this.contratoId,
  }) : super(key: key);

  @override
  State<DetalleOperacionVentaScreen> createState() =>
      _DetalleOperacionVentaScreenState();
}

class _DetalleOperacionVentaScreenState
    extends State<DetalleOperacionVentaScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _operacion;
  List<Map<String, dynamic>> _productos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetalles();
  }

  Future<void> _loadDetalles() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('📊 Cargando detalle de operación: ${widget.operacionId}');

      // Obtener datos de la operación
      final operacionData = await _supabase
          .from('app_dat_operaciones')
          .select('*')
          .eq('id', widget.operacionId)
          .single();

      // Obtener productos extraídos en esta operación
      final productosData = await _supabase
          .from('app_dat_extraccion_productos')
          .select('''
            id,
            cantidad,
            id_producto,
            app_dat_producto(id, denominacion),
            app_dat_producto_presentacion(precio_promedio)
          ''')
          .eq('id_operacion', widget.operacionId);

      if (mounted) {
        setState(() {
          _operacion = operacionData;
          _productos = List<Map<String, dynamic>>.from(productosData);
          _isLoading = false;
        });

        debugPrint('✅ Detalle cargado:');
        debugPrint('   Operación ID: ${operacionData['id']}');
        debugPrint('   Productos: ${_productos.length}');
      }
    } catch (e) {
      debugPrint('❌ Error cargando detalle: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detalle de Operación'),
            if (_operacion != null)
              Text(
                'Op. #${_operacion!['id']}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _operacion == null
              ? const Center(
                  child: Text('No se encontró la operación'),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOperacionCard(),
                      const SizedBox(height: 24),
                      _buildProductosSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOperacionCard() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final createdAt = DateTime.parse(_operacion!['created_at'] as String);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.receipt,
                    color: Colors.blue.shade700,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información de la Operación',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID: ${_operacion!['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Fecha', dateFormat.format(createdAt)),
            const SizedBox(height: 12),
            _buildInfoRow('Tienda', _operacion!['id_tienda'].toString()),
            const SizedBox(height: 12),
            _buildInfoRow('Descripción', _operacion!['descripcion'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildProductosSection() {
    if (_productos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No hay productos en esta operación',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    double totalMonto = 0.0;
    for (final prod in _productos) {
      final cantidad = (prod['cantidad'] as num?)?.toDouble() ?? 0.0;
      final precioPromedio = _obtenerPrecioPromedio(prod);
      totalMonto += cantidad * precioPromedio;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Productos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ..._productos.asMap().entries.map((entry) {
          return _buildProductoCard(entry.value);
        }),
        const SizedBox(height: 16),
        _buildTotalCard(totalMonto),
      ],
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> producto) {
    final cantidad = (producto['cantidad'] as num?)?.toDouble() ?? 0.0;
    final precioPromedio = _obtenerPrecioPromedio(producto);
    final monto = cantidad * precioPromedio;
    final denominacion = _obtenerDenominacion(producto);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              denominacion,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Cantidad',
                    cantidad.toStringAsFixed(0),
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailItem(
                    'Precio Costo',
                    '\$${precioPromedio.toStringAsFixed(2)}',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailItem(
                    'Monto',
                    '\$${monto.toStringAsFixed(2)}',
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalCard(double totalMonto) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total de la Operación',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '\$${totalMonto.toStringAsFixed(2)} USD',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  String _obtenerDenominacion(Map<String, dynamic> producto) {
    try {
      final productoData = producto['app_dat_producto'] as Map?;
      return productoData?['denominacion'] ?? 'Producto desconocido';
    } catch (e) {
      return 'Producto desconocido';
    }
  }

  double _obtenerPrecioPromedio(Map<String, dynamic> producto) {
    try {
      final presentacionData = producto['app_dat_producto_presentacion'] as List?;
      if (presentacionData != null && presentacionData.isNotEmpty) {
        final precio = presentacionData[0]['precio_promedio'] as num?;
        return precio?.toDouble() ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
}
