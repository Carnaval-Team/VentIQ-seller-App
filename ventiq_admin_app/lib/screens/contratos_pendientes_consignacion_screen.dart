import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/user_preferences_service.dart';

class ContratosPendientesConsignacionScreen extends StatefulWidget {
  final VoidCallback? onContratoChanged;

  const ContratosPendientesConsignacionScreen({
    Key? key,
    this.onContratoChanged,
  }) : super(key: key);

  @override
  State<ContratosPendientesConsignacionScreen> createState() => _ContratosPendientesConsignacionScreenState();
}

class _ContratosPendientesConsignacionScreenState extends State<ContratosPendientesConsignacionScreen> {
  bool _isLoading = true;
  int? _idTienda;
  List<Map<String, dynamic>> _contratosPendientes = [];
  int? _idAlmacenSeleccionado;
  List<Map<String, dynamic>> _almacenesDisponibles = [];
  bool _cargandoAlmacenes = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final storeData = await userPrefs.getCurrentStoreInfo();
      _idTienda = storeData?['id_tienda'] as int?;

      if (_idTienda != null) {
        final contratos = await ConsignacionService.getContratosPendientesConfirmacion(_idTienda!);
        setState(() {
          _contratosPendientes = contratos;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error cargando contratos pendientes: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmarContrato(int idContrato, int idTiendaConsignataria) async {
    // Resetear variables
    _idAlmacenSeleccionado = null;
    _almacenesDisponibles = [];
    _cargandoAlmacenes = true;

    // Cargar almacenes de la tienda consignataria
    try {
      final almacenes = await ConsignacionService.getAlmacenesPorTienda(idTiendaConsignataria);
      if (mounted) {
        setState(() {
          _almacenesDisponibles = almacenes;
          _cargandoAlmacenes = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando almacenes: $e');
      if (mounted) {
        setState(() => _cargandoAlmacenes = false);
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmar Contrato'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('¿Deseas confirmar este contrato de consignación?'),
                const SizedBox(height: 16),
                const Text(
                  'Selecciona el almacén destino:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_cargandoAlmacenes)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  )
                else if (_almacenesDisponibles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_outlined, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No hay almacenes disponibles',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    value: _idAlmacenSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar almacén *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.warehouse),
                    ),
                    items: _almacenesDisponibles.map((almacen) {
                      return DropdownMenuItem<int>(
                        value: almacen['id'],
                        child: Text(almacen['denominacion'] ?? 'Almacén'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => _idAlmacenSeleccionado = value);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _idAlmacenSeleccionado == null ? null : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    try {
      // Actualizar contrato con el almacén destino
      await ConsignacionService.actualizarAlmacenDestino(idContrato, _idAlmacenSeleccionado!);

      final success = await ConsignacionService.confirmarContrato(idContrato);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato confirmado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        // Notificar al padre que hubo cambios
        widget.onContratoChanged?.call();
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al confirmar el contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
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

  Future<void> _cancelarContrato(int idContrato) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) {
        String motivoText = '';
        return AlertDialog(
          title: const Text('Cancelar Contrato'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Deseas cancelar este contrato de consignación?'),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Motivo de cancelación (opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: No cumple con nuestros requisitos...',
                ),
                maxLines: 3,
                onChanged: (value) => motivoText = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, motivoText),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cancelar Contrato'),
            ),
          ],
        );
      },
    );

    if (motivo == null) return;

    if (!mounted) return;

    try {
      final success = await ConsignacionService.cancelarContrato(idContrato, motivo);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato cancelado exitosamente'),
            backgroundColor: Colors.orange,
          ),
        );
        // Notificar al padre que hubo cambios
        widget.onContratoChanged?.call();
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al cancelar el contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contratos Pendientes'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _contratosPendientes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No hay contratos pendientes',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Todos tus contratos han sido confirmados',
                            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _contratosPendientes.length,
                      itemBuilder: (context, index) {
                        final contrato = _contratosPendientes[index];
                        final tiendaConsignadora = contrato['tienda_consignadora'];
                        return _buildContratoCard(contrato, tiendaConsignadora);
                      },
                    ),
            ),
    );
  }

  Widget _buildContratoCard(Map<String, dynamic> contrato, Map<String, dynamic> tiendaConsignadora) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con icono y tienda
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'De: ${tiendaConsignadora['denominacion']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (tiendaConsignadora['direccion'] != null)
                        Text(
                          tiendaConsignadora['direccion'],
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Detalles del contrato
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Comisión:', '${contrato['porcentaje_comision'] ?? 0}%'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Inicio:', contrato['fecha_inicio'] ?? 'N/A'),
                  if (contrato['fecha_fin'] != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Fin:', contrato['fecha_fin']),
                  ],
                  if (contrato['plazo_dias'] != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Plazo:', '${contrato['plazo_dias']} días'),
                  ],
                ],
              ),
            ),

            // Condiciones
            if (contrato['condiciones'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Condiciones:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contrato['condiciones'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Botones de acción
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmarContrato(contrato['id'], contrato['id_tienda_consignataria']),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelarContrato(contrato['id']),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
