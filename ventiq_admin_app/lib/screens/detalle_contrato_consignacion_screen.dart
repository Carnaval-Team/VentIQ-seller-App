import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/consignacion_movimientos_service.dart';

class DetalleContratoConsignacionScreen extends StatefulWidget {
  final Map<String, dynamic> contrato;

  const DetalleContratoConsignacionScreen({
    Key? key,
    required this.contrato,
  }) : super(key: key);

  @override
  State<DetalleContratoConsignacionScreen> createState() =>
      _DetalleContratoConsignacionScreenState();
}

class _DetalleContratoConsignacionScreenState
    extends State<DetalleContratoConsignacionScreen> {
  List<Map<String, dynamic>> _movimientos = [];
  Map<String, dynamic> _estadisticas = {};
  bool _isLoading = true;
  bool _puedeRescindirse = false;
  bool _isLoadingMovimientos = false;
  
  // Filtros de fecha
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 [INIT] Inicializando pantalla de detalle del contrato ID: ${widget.contrato['id']}');
    _loadMovimientosYEstadisticas();
    _verificarRescision();
  }

  Future<void> _verificarRescision() async {
    try {
      debugPrint('🔍 [RESCISION] Verificando si contrato puede rescindirse...');
      final puedeRescindirse =
          await ConsignacionService.puedeSerRescindido(widget.contrato['id']);
      
      if (mounted) {
        setState(() {
          _puedeRescindirse = puedeRescindirse;
          _isLoading = false;
        });
        debugPrint('✅ [RESCISION] Contrato puede rescindirse: $puedeRescindirse');
      }
    } catch (e) {
      debugPrint('❌ [RESCISION] Error verificando rescisión: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMovimientosYEstadisticas() async {
    setState(() => _isLoadingMovimientos = true);

    try {
      debugPrint('📊 [LOAD] Iniciando carga de movimientos y estadísticas');
      debugPrint('📊 [LOAD] ID Contrato: ${widget.contrato['id']}');
      debugPrint('📊 [LOAD] Tienda Consignadora: ${widget.contrato['tienda_consignadora']['denominacion']}');
      debugPrint('📊 [LOAD] Tienda Consignataria: ${widget.contrato['tienda_consignataria']['denominacion']}');
      debugPrint('📊 [LOAD] Almacén Destino: ${widget.contrato['id_almacen_destino']}');
      debugPrint('📊 [LOAD] Filtro Fecha Desde: $_fechaDesde');
      debugPrint('📊 [LOAD] Filtro Fecha Hasta: $_fechaHasta');

      debugPrint('📊 [LOAD] Obteniendo movimientos desde zona...');
      final movimientos = await ConsignacionMovimientosService.getMovimientosConsignacion(
        idContrato: widget.contrato['id'],
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      debugPrint('✅ [LOAD] Movimientos obtenidos: ${movimientos.length}');
      for (var i = 0; i < movimientos.length; i++) {
        final mov = movimientos[i];
        debugPrint('  📦 [MOV-$i] ID Op: ${mov['id_operacion']}, Producto: ${mov['denominacion_producto']}, Cantidad: ${mov['cantidad_vendida']}, Motivo: ${mov['motivo_extraccion']}');
      }

      debugPrint('📊 [LOAD] Obteniendo estadísticas consolidadas...');
      final estadisticas = await ConsignacionMovimientosService.getEstadisticasVentas(
        idContrato: widget.contrato['id'],
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      debugPrint('✅ [LOAD] Estadísticas obtenidas:');
      debugPrint('  📈 Total Enviado: ${estadisticas['totalEnviado']}');
      debugPrint('  📈 Total Vendido: ${estadisticas['totalVendido']}');
      debugPrint('  📈 Total Devuelto: ${estadisticas['totalDevuelto']}');
      debugPrint('  📈 Total Pendiente: ${estadisticas['totalPendiente']}');
      debugPrint('  📈 Total Operaciones: ${estadisticas['totalOperaciones']}');
      debugPrint('  📈 Total Monto Ventas: ${estadisticas['totalMontoVentas']}');
      debugPrint('  📈 Promedio Venta: ${estadisticas['promedioVenta']}');

      if (mounted) {
        setState(() {
          _movimientos = movimientos;
          _estadisticas = estadisticas;
          _isLoadingMovimientos = false;
        });
        debugPrint('✅ [LOAD] Estado actualizado exitosamente');
      }
    } catch (e) {
      debugPrint('❌ [LOAD] Error cargando movimientos: $e');
      if (mounted) {
        setState(() => _isLoadingMovimientos = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esConsignadora =
        widget.contrato['id_tienda_consignadora'] == widget.contrato['id_tienda_actual'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Contrato'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Información del contrato
                  _buildContratoInfo(),

                  // Filtro de fechas global
                  _buildFiltroFechasGlobal(),

                  // Estadísticas de ventas (REEMPLAZA productos)
                  _buildEstadisticasSection(),

                  // Movimientos de ventas
                  _buildMovimientosSection(),

                  // Opción de rescindir
                  if (_puedeRescindirse)
                    _buildRescindirSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildContratoInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.handshake,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información del Contrato',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID: ${widget.contrato['id']}',
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

            // Tiendas
            _buildInfoRow(
              'Tienda Consignadora:',
              widget.contrato['tienda_consignadora']['denominacion'],
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Tienda Consignataria:',
              widget.contrato['tienda_consignataria']['denominacion'],
              Colors.green,
            ),
            const SizedBox(height: 12),

            // Comisión y plazo
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Comisión',
                    '${widget.contrato['porcentaje_comision']}%',
                    Icons.percent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Plazo',
                    widget.contrato['plazo_dias'] != null
                        ? '${widget.contrato['plazo_dias']} días'
                        : 'Sin límite',
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fechas
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Inicio',
                    widget.contrato['fecha_inicio'] ?? 'N/A',
                    Icons.event_available,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Fin',
                    widget.contrato['fecha_fin'] ?? 'Sin fecha',
                    Icons.event,
                  ),
                ),
              ],
            ),

            // Condiciones
            if (widget.contrato['condiciones'] != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Condiciones:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.contrato['condiciones'],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRescindirSection() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cancel,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rescindir Contrato',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No hay productos pendientes de procesar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Puedes rescindir este contrato ya que todos los productos han sido completamente vendidos o devueltos.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _mostrarDialogoRescision,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Rescindir Contrato'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _mostrarDialogoRescision() {
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rescindir Contrato'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta acción desactivará el contrato y todos sus productos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Contrato ID: ${widget.contrato['id']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tienda: ${widget.contrato['tienda_consignadora']['denominacion']} → ${widget.contrato['tienda_consignataria']['denominacion']}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo de rescisión (opcional)',
                border: OutlineInputBorder(),
                hintText: 'Ej: Acuerdo mutuo, fin de temporada, etc.',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _rescindirContrato(motivoController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rescindir'),
          ),
        ],
      ),
    );
  }

  Future<void> _rescindirContrato(String motivo) async {
    try {
      final success = await ConsignacionService.rescindirContrato(
        idContrato: widget.contrato['id'],
        motivo: motivo.isNotEmpty ? motivo : null,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato rescindido exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        // Cerrar la pantalla después de rescindir
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se puede rescindir: hay productos pendientes'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error rescindiendo contrato: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al rescindir contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEstadisticasSection() {
    if (_estadisticas.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalEnviado = _estadisticas['totalEnviado'] as num? ?? 0;
    final totalVendido = _estadisticas['totalVendido'] as num? ?? 0;
    final totalDevuelto = _estadisticas['totalDevuelto'] as num? ?? 0;
    final totalPendiente = _estadisticas['totalPendiente'] as num? ?? 0;
    final totalOperaciones = _estadisticas['totalOperaciones'] as num? ?? 0;
    final totalMontoVentas = _estadisticas['totalMontoVentas'] as num? ?? 0;
    final promedioVenta = _estadisticas['promedioVenta'] as num? ?? 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estadísticas de Ventas en Zona',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Almacén: ${widget.contrato['id_almacen_destino']}',
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

          // Fila 1: Cantidades
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  'Enviado',
                  '${totalEnviado.toStringAsFixed(0)}',
                  Colors.blue,
                  Icons.send,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Vendido',
                  '${totalVendido.toStringAsFixed(0)}',
                  Colors.green,
                  Icons.shopping_cart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Devuelto',
                  '${totalDevuelto.toStringAsFixed(0)}',
                  Colors.orange,
                  Icons.undo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Pendiente',
                  '${totalPendiente.toStringAsFixed(0)}',
                  Colors.red,
                  Icons.pending,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fila 2: Operaciones y Montos
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  'Operaciones',
                  '${totalOperaciones.toStringAsFixed(0)}',
                  Colors.purple,
                  Icons.receipt,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildStatBox(
                  'Monto Total',
                  '\$${totalMontoVentas.toStringAsFixed(2)}',
                  Colors.teal,
                  Icons.attach_money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Promedio',
                  '\$${promedioVenta.toStringAsFixed(2)}',
                  Colors.indigo,
                  Icons.trending_up,
                ),
              ),
            ],
          ),

          // Porcentaje de venta
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Porcentaje de Venta',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      totalEnviado > 0
                          ? '${((totalVendido / totalEnviado) * 100).toStringAsFixed(1)}%'
                          : '0%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalEnviado > 0 ? (totalVendido / totalEnviado).toDouble() : 0,
                    minHeight: 8,
                    backgroundColor: Colors.blue.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientosSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Movimientos de Ventas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingMovimientos)
            const Center(child: CircularProgressIndicator())
          else if (_movimientos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay movimientos registrados',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _movimientos.length,
              itemBuilder: (context, index) {
                final mov = _movimientos[index];
                return _buildMovimientoCard(mov);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMovimientoCard(Map<String, dynamic> movimiento) {
    final cantidad = movimiento['cantidad_vendida'] as num? ?? 0;
    final motivo = movimiento['motivo_extraccion'] as String? ?? 'Venta';
    final fecha = movimiento['fecha_venta'] as String? ?? '';
    final producto = movimiento['denominacion_producto'] as String? ?? 'Producto desconocido';
    final importe = movimiento['importe_total'] as num? ?? 0;

    debugPrint('📦 [CARD] Renderizando movimiento: $producto, Motivo: $motivo, Cantidad: $cantidad');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_cart, color: Colors.green, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        motivo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Cantidad: ${cantidad.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    producto,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            _formatearFecha(fecha),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      Text(
                        '\$${importe.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroFechasGlobal() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Filtro de Fechas',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Fecha Desde
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate: _fechaDesde ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (fecha != null) {
                        setState(() => _fechaDesde = fecha);
                        debugPrint('📅 [FILTRO] Fecha Desde: $_fechaDesde');
                        _loadMovimientosYEstadisticas();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Desde',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fechaDesde?.toString().split(' ')[0] ?? 'Seleccionar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _fechaDesde != null ? Colors.blue.shade700 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Fecha Hasta
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate: _fechaHasta ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (fecha != null) {
                        setState(() => _fechaHasta = fecha);
                        debugPrint('📅 [FILTRO] Fecha Hasta: $_fechaHasta');
                        _loadMovimientosYEstadisticas();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hasta',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fechaHasta?.toString().split(' ')[0] ?? 'Seleccionar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _fechaHasta != null ? Colors.blue.shade700 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botón Limpiar
                if (_fechaDesde != null || _fechaHasta != null)
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _fechaDesde = null;
                          _fechaHasta = null;
                        });
                        debugPrint('📅 [FILTRO] Filtros limpiados');
                        _loadMovimientosYEstadisticas();
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatearFecha(String? fecha) {
    if (fecha == null) return 'N/A';
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return fecha;
    }
  }
}
