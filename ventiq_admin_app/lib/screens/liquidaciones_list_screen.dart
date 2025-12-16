import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/liquidacion_service.dart';
import '../widgets/crear_liquidacion_dialog.dart';

/// Pantalla para listar y gestionar liquidaciones de un contrato
/// Funciona para ambos roles: consignatario y consignador
class LiquidacionesListScreen extends StatefulWidget {
  final int contratoId;
  final bool esConsignatario; // true = consignatario, false = consignador
  final String nombreTiendaOtra; // Nombre de la otra tienda

  const LiquidacionesListScreen({
    Key? key,
    required this.contratoId,
    required this.esConsignatario,
    required this.nombreTiendaOtra,
  }) : super(key: key);

  @override
  State<LiquidacionesListScreen> createState() => _LiquidacionesListScreenState();
}

class _LiquidacionesListScreenState extends State<LiquidacionesListScreen> {
  List<Map<String, dynamic>> _liquidaciones = [];
  Map<String, double> _totales = {};
  bool _isLoading = true;
  int? _filtroEstado; // null = todos, 0 = pendientes, 1 = confirmadas, 2 = rechazadas

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final liquidaciones = await LiquidacionService.listarLiquidaciones(
        contratoId: widget.contratoId,
        estado: _filtroEstado,
      );
      final totales = await LiquidacionService.obtenerTotalesContrato(widget.contratoId);

      if (mounted) {
        setState(() {
          _liquidaciones = liquidaciones;
          _totales = totales;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _mostrarDialogoCrearLiquidacion() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CrearLiquidacionDialog(
        contratoId: widget.contratoId,
        montoTotalContrato: _totales['monto_total'] ?? 0.0,
        totalLiquidaciones: _totales['total_liquidaciones'] ?? 0.0,
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Liquidación creada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }

  Future<void> _confirmarLiquidacion(int liquidacionId) async {
    final observaciones = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Confirmar Liquidación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Confirmar esta liquidación?'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
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
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (observaciones != null) {
      try {
        await LiquidacionService.confirmarLiquidacion(
          liquidacionId: liquidacionId,
          observaciones: observaciones.isEmpty ? null : observaciones,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Liquidación confirmada'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _rechazarLiquidacion(int liquidacionId) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Rechazar Liquidación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Rechazar esta liquidación?'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Motivo del rechazo *',
                  border: OutlineInputBorder(),
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
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debe ingresar un motivo'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, controller.text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Rechazar'),
            ),
          ],
        );
      },
    );

    if (motivo != null && motivo.trim().isNotEmpty) {
      try {
        await LiquidacionService.rechazarLiquidacion(
          liquidacionId: liquidacionId,
          motivoRechazo: motivo,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Liquidación rechazada'),
              backgroundColor: Colors.orange,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _cancelarLiquidacion(int liquidacionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Liquidación'),
        content: const Text('¿Está seguro de cancelar esta liquidación pendiente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LiquidacionService.cancelarLiquidacion(liquidacionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Liquidación cancelada'),
              backgroundColor: Colors.grey,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
            const Text('Liquidaciones'),
            Text(
              widget.esConsignatario 
                  ? 'Consignador: ${widget.nombreTiendaOtra}'
                  : 'Consignatario: ${widget.nombreTiendaOtra}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Filtro por estado
          PopupMenuButton<int?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar por estado',
            onSelected: (estado) {
              setState(() => _filtroEstado = estado);
              _loadData();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    Icon(
                      Icons.list,
                      color: _filtroEstado == null ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text('Todas'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(
                      Icons.pending,
                      color: _filtroEstado == 0 ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text('Pendientes'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: _filtroEstado == 1 ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text('Confirmadas'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Icon(
                      Icons.cancel,
                      color: _filtroEstado == 2 ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text('Rechazadas'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Resumen de totales
                _buildTotalesCard(),
                const Divider(height: 1),
                // Lista de liquidaciones
                Expanded(
                  child: _liquidaciones.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _liquidaciones.length,
                            itemBuilder: (context, index) {
                              return _buildLiquidacionCard(_liquidaciones[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: widget.esConsignatario
          ? FloatingActionButton.extended(
              onPressed: _mostrarDialogoCrearLiquidacion,
              icon: const Icon(Icons.add),
              label: const Text('Nueva Liquidación'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  Widget _buildTotalesCard() {
    final montoTotal = _totales['monto_total'] ?? 0.0;
    final totalLiquidaciones = _totales['total_liquidaciones'] ?? 0.0;
    final saldoPendiente = _totales['saldo_pendiente'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTotalItem(
                  'Valor Contrato',
                  '\$${montoTotal.toStringAsFixed(2)} USD',
                  Colors.blue,
                  Icons.description,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTotalItem(
                  'Liquidado',
                  '\$${totalLiquidaciones.toStringAsFixed(2)} USD',
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTotalItem(
            'Saldo Pendiente',
            '\$${saldoPendiente.toStringAsFixed(2)} USD',
            saldoPendiente > 0 ? Colors.orange : Colors.green,
            Icons.pending_actions,
            isLarge: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTotalItem(String label, String value, Color color, IconData icon, {bool isLarge = false}) {
    return Container(
      padding: EdgeInsets.all(isLarge ? 16 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: isLarge ? 24 : 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isLarge ? 13 : 11,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isLarge ? 18 : 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiquidacionCard(Map<String, dynamic> liquidacion) {
    final id = liquidacion['id'] as int;
    final montoCup = (liquidacion['monto_cup'] as num).toDouble();
    final montoUsd = (liquidacion['monto_usd'] as num).toDouble();
    final tasaCambio = (liquidacion['tasa_cambio'] as num).toDouble();
    final estado = liquidacion['estado'] as int;
    final observaciones = liquidacion['observaciones'] as String?;
    final motivoRechazo = liquidacion['motivo_rechazo'] as String?;
    final fechaLiquidacion = DateTime.parse(liquidacion['fecha_liquidacion'] as String);
    final fechaConfirmacion = liquidacion['fecha_confirmacion'] != null
        ? DateTime.parse(liquidacion['fecha_confirmacion'] as String)
        : null;

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    Color estadoColor;
    String estadoTexto;
    IconData estadoIcon;

    switch (estado) {
      case 0:
        estadoColor = Colors.orange;
        estadoTexto = 'Pendiente';
        estadoIcon = Icons.pending;
        break;
      case 1:
        estadoColor = Colors.green;
        estadoTexto = 'Confirmada';
        estadoIcon = Icons.check_circle;
        break;
      case 2:
        estadoColor = Colors.red;
        estadoTexto = 'Rechazada';
        estadoIcon = Icons.cancel;
        break;
      default:
        estadoColor = Colors.grey;
        estadoTexto = 'Desconocido';
        estadoIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con estado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: estadoColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(estadoIcon, size: 16, color: estadoColor),
                      const SizedBox(width: 6),
                      Text(
                        estadoTexto,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: estadoColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '#$id',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Montos
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monto CUP',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        '\$${montoCup.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monto USD',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        '\$${montoUsd.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tasa de cambio (invertida para mostrar correctamente)
            Text(
              'Tasa: 1 CUP = ${tasaCambio.toStringAsFixed(6)} USD (1 USD = ${(1.0 / tasaCambio).toStringAsFixed(2)} CUP)',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),

            // Fechas
            Text(
              'Creada: ${dateFormat.format(fechaLiquidacion)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            if (fechaConfirmacion != null)
              Text(
                'Confirmada: ${dateFormat.format(fechaConfirmacion)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),

            // Observaciones
            if (observaciones != null && observaciones.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Observaciones:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    Text(
                      observaciones,
                      style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ],

            // Motivo de rechazo
            if (motivoRechazo != null && motivoRechazo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motivo de rechazo:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                    Text(
                      motivoRechazo,
                      style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ],

            // Acciones
            if (estado == 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!widget.esConsignatario) ...[
                    // Consignador puede confirmar o rechazar
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmarLiquidacion(id),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Confirmar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _rechazarLiquidacion(id),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Rechazar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else ...[
                    // Consignatario puede cancelar
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _cancelarLiquidacion(id),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payments_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _filtroEstado == null
                  ? 'No hay liquidaciones'
                  : 'No hay liquidaciones ${_getEstadoTexto(_filtroEstado!)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.esConsignatario
                  ? 'Crea una nueva liquidación para comenzar'
                  : 'Esperando liquidaciones del consignatario',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEstadoTexto(int estado) {
    switch (estado) {
      case 0:
        return 'pendientes';
      case 1:
        return 'confirmadas';
      case 2:
        return 'rechazadas';
      default:
        return '';
    }
  }
}
