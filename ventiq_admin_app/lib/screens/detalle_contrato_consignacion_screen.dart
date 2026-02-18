import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/consignacion_movimientos_service.dart';
import '../services/liquidacion_service.dart';
import 'liquidaciones_list_screen.dart';
import 'operaciones_venta_consignacion_screen.dart';
import 'productos_zona_destino_screen.dart';
import '../utils/navigation_guard.dart';
import '../services/currency_service.dart';

class DetalleContratoConsignacionScreen extends StatefulWidget {
  final Map<String, dynamic> contrato;

  const DetalleContratoConsignacionScreen({Key? key, required this.contrato})
    : super(key: key);

  @override
  State<DetalleContratoConsignacionScreen> createState() =>
      _DetalleContratoConsignacionScreenState();
}

class _DetalleContratoConsignacionScreenState
    extends State<DetalleContratoConsignacionScreen> {
  Map<String, dynamic> _estadisticas = {};
  Map<String, dynamic> _totalesContrato = {};
  bool _isLoading = true;
  bool _puedeRescindirse = false;
  double _totalDineroEnviado = 0.0;
  double _tasaUsdCup = 0.0;

  bool _canDeleteConsignacion = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🔍 [INIT] Inicializando pantalla de detalle del contrato ID: ${widget.contrato['id']}',
    );
    _loadPermissions();
    _loadMovimientosYEstadisticas();
    _verificarRescision();
    _calcularTotalDineroEnviado();
    _loadTotalesContrato();
    _loadTasaCambio();
  }

  Future<void> _loadPermissions() async {
    final canDelete = await NavigationGuard.canPerformAction(
      'consignacion.delete',
    );
    if (!mounted) return;
    setState(() {
      _canDeleteConsignacion = canDelete;
    });
  }

  Future<void> _verificarRescision() async {
    try {
      debugPrint('🔍 [RESCISION] Verificando si contrato puede rescindirse...');
      final puedeRescindirse = await ConsignacionService.puedeSerRescindido(
        widget.contrato['id'],
      );

      if (mounted) {
        setState(() {
          _puedeRescindirse = puedeRescindirse;
          _isLoading = false;
        });
        debugPrint(
          '✅ [RESCISION] Contrato puede rescindirse: $puedeRescindirse',
        );
      }
    } catch (e) {
      debugPrint('❌ [RESCISION] Error verificando rescisión: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _calcularTotalDineroEnviado() async {
    try {
      debugPrint('💰 [TOTAL] Obteniendo monto_total del contrato...');

      // Obtener el monto_total directamente del contrato
      final montoTotal =
          (widget.contrato['monto_total'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        setState(() {
          _totalDineroEnviado = montoTotal;
        });
        debugPrint('✅ [TOTAL] Monto total del contrato: $_totalDineroEnviado');
      }
    } catch (e) {
      debugPrint('❌ [TOTAL] Error obteniendo monto total: $e');
    }
  }

  Future<void> _loadTotalesContrato() async {
    try {
      debugPrint('💰 [LIQUIDACIONES] Cargando totales del contrato...');

      final totales = await LiquidacionService.obtenerTotalesContrato(
        widget.contrato['id'],
      );

      if (mounted) {
        setState(() {
          _totalesContrato = totales;
        });
        debugPrint('✅ [LIQUIDACIONES] Totales cargados:');
        debugPrint('  💵 Monto Total: ${totales['monto_total']}');
        debugPrint('  ✅ Total Liquidado: ${totales['total_liquidado']}');
        debugPrint('  ⏳ Saldo Pendiente: ${totales['saldo_pendiente']}');
      }
    } catch (e) {
      debugPrint('❌ [LIQUIDACIONES] Error cargando totales: $e');
    }
  }

  Future<void> _loadTasaCambio() async {
    try {
      final tasa = await CurrencyService.getEffectiveUsdToCupRate();
      if (mounted) {
        setState(() => _tasaUsdCup = tasa);
        debugPrint('💱 [TASA] USD→CUP: $_tasaUsdCup');
      }
    } catch (e) {
      debugPrint('❌ [TASA] Error obteniendo tasa: $e');
    }
  }

  Future<void> _loadMovimientosYEstadisticas() async {
    try {
      debugPrint('📊 [LOAD] Iniciando carga de estadísticas');
      debugPrint('📊 [LOAD] ID Contrato: ${widget.contrato['id']}');

      debugPrint(
        '📊 [LOAD] Obteniendo estadísticas consolidadas (TODO el tiempo)...',
      );
      final estadisticas =
          await ConsignacionMovimientosService.getEstadisticasVentas(
            idContrato: widget.contrato['id'],
            fechaDesde: null,
            fechaHasta: null,
          );
      debugPrint('✅ [LOAD] Estadísticas obtenidas:');
      debugPrint('  📈 Total Enviado: ${estadisticas['totalEnviado']}');
      debugPrint('  📈 Total Vendido: ${estadisticas['totalVendido']}');
      debugPrint('  📈 Total Devuelto: ${estadisticas['totalDevuelto']}');
      debugPrint('  📈 Total Pendiente: ${estadisticas['totalPendiente']}');
      debugPrint(
        '  📈 Total Monto Ventas: ${estadisticas['totalMontoVentas']}',
      );

      if (mounted) {
        setState(() {
          _estadisticas = estadisticas;
        });
        debugPrint('✅ [LOAD] Estado actualizado exitosamente');
      }
    } catch (e) {
      debugPrint('❌ [LOAD] Error cargando estadísticas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final esConsignadora =
        widget.contrato['id_tienda_consignadora'] ==
        widget.contrato['id_tienda_actual'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Contrato'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  children: [
                    // Información del contrato
                    _buildContratoInfo(),

                    // Estadísticas de ventas y productos
                    _buildEstadisticasSection(),

                    // Opción de rescindir
                    if (_puedeRescindirse && _canDeleteConsignacion)
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

            // Almacén destino (si existe)
            if (widget.contrato['almacen_destino'] != null)
              _buildInfoRow(
                'Almacén de Recepción:',
                widget.contrato['almacen_destino']['denominacion'],
                Colors.purple,
              ),
            if (widget.contrato['almacen_destino'] != null)
              const SizedBox(height: 12),

            // Total de dinero enviado y plazo
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Total Enviado',
                    '\$${_totalDineroEnviado.toStringAsFixed(2)}',
                    Icons.attach_money,
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

            // Liquidaciones
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Liquidado',
                    '\$${(_totalesContrato['total_liquidado'] ?? 0.0).toStringAsFixed(2)}',
                    Icons.payments,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Pendiente',
                    '\$${(_totalesContrato['saldo_pendiente'] ?? 0.0).toStringAsFixed(2)}',
                    Icons.pending_actions,
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
            const SizedBox(height: 16),

            // Botón para ver liquidaciones
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Determinar si es consignatario o consignador
                  final esConsignatario =
                      widget.contrato['id_tienda_consignataria'] ==
                      widget.contrato['id_tienda_actual'];
                  final nombreTiendaOtra =
                      esConsignatario
                          ? widget
                              .contrato['tienda_consignadora']['denominacion']
                          : widget
                              .contrato['tienda_consignataria']['denominacion'];

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => LiquidacionesListScreen(
                            contratoId: widget.contrato['id'],
                            esConsignatario: esConsignatario,
                            nombreTiendaOtra: nombreTiendaOtra,
                          ),
                    ),
                  ).then(
                    (_) => _loadTotalesContrato(),
                  ); // Recargar totales al volver
                },
                icon: const Icon(Icons.account_balance_wallet, size: 20),
                label: const Text('Gestionar Liquidaciones'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Botón para ver stock en destino
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final titulo =
                      '${widget.contrato['tienda_consignadora']['denominacion']} → ${widget.contrato['tienda_consignataria']['denominacion']}';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => ProductosZonaDestinoScreen(
                            idContrato: widget.contrato['id'],
                            tituloContrato: titulo,
                            idZonaDestino: widget.contrato['id_layout_destino'],
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.inventory, size: 20),
                label: const Text('Ver Stock en Destino'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
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
              style: TextStyle(fontWeight: FontWeight.w500, color: color),
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
                  child: const Icon(Icons.cancel, color: Colors.red, size: 28),
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
              style: TextStyle(fontSize: 13, color: Colors.red.shade800),
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
    if (!_canDeleteConsignacion) {
      NavigationGuard.showActionDeniedMessage(context, 'Rescindir contrato');
      return;
    }
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
    if (!_canDeleteConsignacion) {
      NavigationGuard.showActionDeniedMessage(context, 'Rescindir contrato');
      return;
    }
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
    final totalMontoVentasUsd = (_estadisticas['totalMontoVentas'] as num? ?? 0).toDouble();

    final totalLiquidado = _totalesContrato['total_liquidado'] as num? ?? 0;
    final saldoPendiente = _totalesContrato['saldo_pendiente'] as num? ?? 0;

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
                      'Estadísticas del Contrato',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Almacén: ${widget.contrato['id_almacen_destino']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fila 1: Productos
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
                  'Monto Total Vendido',
                  '\$${totalMontoVentasUsd.toStringAsFixed(2)} USD',
                  Colors.teal,
                  Icons.attach_money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Liquidado',
                  '\$${totalLiquidado.toStringAsFixed(2)} USD',
                  Colors.green,
                  Icons.payments,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  'Saldo',
                  '\$${saldoPendiente.toStringAsFixed(2)} USD',
                  Colors.orange,
                  Icons.pending_actions,
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
                    value:
                        totalEnviado > 0
                            ? (totalVendido / totalEnviado).toDouble()
                            : 0,
                    minHeight: 8,
                    backgroundColor: Colors.blue.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Botón para ver operaciones de venta
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => OperacionesVentaConsignacionScreen(
                          contratoId: widget.contrato['id'],
                          nombreConsignadora:
                              widget
                                  .contrato['tienda_consignadora']['denominacion'],
                          nombreConsignataria:
                              widget
                                  .contrato['tienda_consignataria']['denominacion'],
                        ),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text('Ver Operaciones de Venta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
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
}
