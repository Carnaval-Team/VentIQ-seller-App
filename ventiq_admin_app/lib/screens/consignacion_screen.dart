import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';
import 'crear_contrato_consignacion_screen.dart';
import 'asignar_productos_consignacion_screen.dart';
import 'detalle_contrato_consignacion_screen.dart';
import 'lista_productos_pendientes_consignacion_screen.dart';
import 'consignacion_envios_listado_screen.dart';

class ConsignacionScreen extends StatefulWidget {
  const ConsignacionScreen({Key? key}) : super(key: key);

  @override
  State<ConsignacionScreen> createState() => _ConsignacionScreenState();
}

class _ConsignacionScreenState extends State<ConsignacionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  int? _idTienda;
  
  List<Map<String, dynamic>> _contratos = [];
  Map<String, dynamic> _estadisticas = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final storeData = await userPrefs.getCurrentStoreInfo();
      _idTienda = storeData?['id_tienda'] as int?;

      if (_idTienda != null) {
        final contratos = await ConsignacionService.getActiveContratos(_idTienda!);
        final estadisticas = await ConsignacionService.getEstadisticas(_idTienda!);

        setState(() {
          _contratos = contratos;
          _estadisticas = estadisticas;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Consignaciones'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Resumen'),
            Tab(icon: Icon(Icons.handshake), text: 'Contratos'),
          ],
        ),
      ),
      drawer: const AdminDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildResumenTab(),
                _buildContratosTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CrearContratoConsignacionScreen(),
            ),
          );
          if (result != null) {
            _loadData();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Contrato'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Tab 1: Resumen
  Widget _buildResumenTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estadísticas Generales',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Tarjetas de estadísticas
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Contratos Activos',
                    '${_estadisticas['contratos_activos'] ?? 0}',
                    Icons.handshake,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Pendientes',
                    '${_contratos.where((c) => (c['estado_confirmacion'] as int? ?? 0) == 0).length}',
                    Icons.schedule,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Productos Enviados',
                    '${_estadisticas['productos_enviados'] ?? 0}',
                    Icons.send,
                    Colors.indigo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Productos Vendidos',
                    '${_estadisticas['productos_vendidos'] ?? 0}',
                    Icons.shopping_cart,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Ventas',
                    '\$${(_estadisticas['total_ventas'] ?? 0.0).toStringAsFixed(2)}',
                    Icons.attach_money,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            const Text(
              'Contratos Recientes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            if (_contratos.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.handshake_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay contratos activos',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._contratos.take(5).map((contrato) => _buildContratoCard(contrato)),
          ],
        ),
      ),
    );
  }

  // Tab 2: Contratos
  Widget _buildContratosTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _contratos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.handshake_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No hay contratos activos',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Los contratos se gestionan desde el SuperAdmin',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _contratos.length,
              itemBuilder: (context, index) {
                return _buildContratoCard(_contratos[index]);
              },
            ),
    );
  }


  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContratoCard(Map<String, dynamic> contrato) {
    final tiendaConsignadora = contrato['tienda_consignadora'];
    final tiendaConsignataria = contrato['tienda_consignataria'];
    final esConsignadora = tiendaConsignadora['id'] == _idTienda;
    final estadoConfirmacion = contrato['estado_confirmacion'] as int? ?? 0;

    // Determinar color y texto del estado
    String textoEstado = '';
    Color colorEstado = Colors.grey;
    IconData iconoEstado = Icons.help_outline;

    switch (estadoConfirmacion) {
      case 0:
        textoEstado = 'Pendiente';
        colorEstado = Colors.orange;
        iconoEstado = Icons.schedule;
        break;
      case 1:
        textoEstado = 'Confirmado';
        colorEstado = Colors.green;
        iconoEstado = Icons.check_circle;
        break;
      case 2:
        textoEstado = 'Cancelado';
        colorEstado = Colors.red;
        iconoEstado = Icons.cancel;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: esConsignadora ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            esConsignadora ? Icons.send : Icons.call_received,
            color: esConsignadora ? Colors.blue : Colors.green,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                esConsignadora
                    ? 'Enviando a: ${tiendaConsignataria['denominacion']}'
                    : 'Recibiendo de: ${tiendaConsignadora['denominacion']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorEstado.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorEstado, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoEstado, size: 14, color: colorEstado),
                  const SizedBox(width: 4),
                  Text(
                    textoEstado,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorEstado,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Comisión: ${contrato['porcentaje_comision'] ?? 0}%'),
            Text('Inicio: ${contrato['fecha_inicio']}'),
            if (estadoConfirmacion == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠️ Pendiente de confirmación',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (estadoConfirmacion == 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Cancelado: ${contrato['motivo_cancelacion'] ?? 'Sin motivo especificado'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contrato['condiciones'] != null) ...[
                  const Text(
                    'Condiciones:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(contrato['condiciones']),
                  const SizedBox(height: 12),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DetalleContratoConsignacionScreen(
                                    contrato: {
                                      ...contrato,
                                      'id_tienda_actual': _idTienda,
                                    },
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.info, size: 20),
                            label: const Text('Ver Detalle', style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (esConsignadora) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Botón Rescindir: siempre disponible si puede rescindirse
                          Expanded(
                            child: FutureBuilder<bool>(
                              future: ConsignacionService.puedeSerRescindido(contrato['id']),
                              builder: (context, snapshot) {
                                final puedeRescindirse = snapshot.data ?? false;
                                return ElevatedButton.icon(
                                  onPressed: puedeRescindirse ? () => _mostrarDialogoRescision(contrato) : null,
                                  icon: const Icon(Icons.delete_forever, size: 20),
                                  label: const Text('Rescindir', style: TextStyle(fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: puedeRescindirse ? Colors.red : Colors.grey[300],
                                    foregroundColor: puedeRescindirse ? Colors.white : Colors.grey,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      // Botones de confirmación/cancelación para consignataria (solo si está pendiente)
                      if (estadoConfirmacion == 0) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _confirmarContrato(contrato),
                                icon: const Icon(Icons.check_circle, size: 20),
                                label: const Text('Confirmar', style: TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _mostrarDialogoCancelacion(contrato),
                                icon: const Icon(Icons.cancel, size: 20),
                                label: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Botón Rescindir para consignataria: siempre disponible si puede rescindirse
                      Row(
                        children: [
                          Expanded(
                            child: FutureBuilder<bool>(
                              future: ConsignacionService.puedeSerRescindido(contrato['id']),
                              builder: (context, snapshot) {
                                final puedeRescindirse = snapshot.data ?? false;
                                return ElevatedButton.icon(
                                  onPressed: puedeRescindirse ? () => _mostrarDialogoRescision(contrato) : null,
                                  icon: const Icon(Icons.delete_forever, size: 20),
                                  label: const Text('Rescindir', style: TextStyle(fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: puedeRescindirse ? Colors.red : Colors.grey[300],
                                    foregroundColor: puedeRescindirse ? Colors.white : Colors.grey,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Botón Ver envíos: AMBOS ROLES pueden ver (solo si está confirmado)
                    if (estadoConfirmacion == 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _verEnviosConfirmados(contrato),
                              icon: const Icon(Icons.local_shipping, size: 20),
                              label: const Text('Ver Envíos', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }


  Future<void> _verEnviosConfirmados(Map<String, dynamic> contrato) async {
    try {
      // Determinar rol del usuario
      final userPrefs = UserPreferencesService();
      final storeData = await userPrefs.getCurrentStoreInfo();
      final idTienda = storeData?['id_tienda'] as int?;
      
      if (idTienda == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No se pudo determinar tu tienda'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final esConsignadora = contrato['tienda_consignadora']['id'] == idTienda;
      final rol = esConsignadora ? 'consignador' : 'consignatario';

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsignacionEnviosListadoScreen(
            idContrato: contrato['id'],
            rol: rol,
            contrato: contrato, // Pasar el contrato completo
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error abriendo envíos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al abrir envíos'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _verDetalleProducto(Map<String, dynamic> producto) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(producto['producto']['denominacion']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${producto['producto']['sku'] ?? 'N/A'}'),
            const SizedBox(height: 8),
            Text('Cantidad Enviada: ${producto['cantidad_enviada']}'),
            Text('Cantidad Vendida: ${producto['cantidad_vendida']}'),
            Text('Cantidad Devuelta: ${producto['cantidad_devuelta']}'),
            Text('Stock Disponible: ${(producto['cantidad_enviada'] as num) - (producto['cantidad_vendida'] as num) - (producto['cantidad_devuelta'] as num)}'),
            const SizedBox(height: 8),
            if (producto['precio_venta_sugerido'] != null)
              Text('Precio Sugerido: \$${producto['precio_venta_sugerido']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoRescision(Map<String, dynamic> contrato) {
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
              'Contrato ID: ${contrato['id']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tienda: ${contrato['tienda_consignadora']['denominacion']} → ${contrato['tienda_consignataria']['denominacion']}',
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
              await _rescindirContrato(contrato['id'], motivoController.text);
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

  Future<void> _rescindirContrato(int idContrato, String motivo) async {
    try {
      final success = await ConsignacionService.rescindirContrato(
        idContrato: idContrato,
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
        _loadData();
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

  Future<void> _confirmarContrato(Map<String, dynamic> contrato) async {
    // Primero, pedir el almacén destino
    final idAlmacenDestino = await _mostrarDialogoSeleccionarAlmacen(
      idTienda: contrato['id_tienda_consignataria'] as int,
      titulo: 'Seleccionar Almacén Destino',
      mensaje: 'Elige el almacén donde recibirás los productos',
    );

    if (idAlmacenDestino == null) {
      // Usuario canceló
      return;
    }

    try {
      // Actualizar el contrato con el almacén destino
      await ConsignacionService.actualizarAlmacenDestino(
        contrato['id'] as int,
        idAlmacenDestino,
      );

      // Crear la zona de consignación inmediatamente
      debugPrint('🏭 Creando zona de consignación para el contrato...');
      final zona = await ConsignacionService.obtenerOCrearZonaConsignacion(
        idContrato: contrato['id'] as int,
        idAlmacenDestino: idAlmacenDestino,
        idTiendaConsignadora: contrato['id_tienda_consignadora'] as int,
        idTiendaConsignataria: contrato['id_tienda_consignataria'] as int,
        nombreTiendaConsignadora: contrato['tienda_consignadora']['denominacion'] as String,
      );

      if (zona == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al crear la zona de consignación'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      debugPrint('✅ Zona de consignación creada: ${zona['id']}');

      // Guardar el ID de la zona en el contrato
      await ConsignacionService.actualizarLayoutDestino(
        contrato['id'] as int,
        zona['id'] as int,
      );

      // Confirmar el contrato
      final success = await ConsignacionService.confirmarContrato(contrato['id']);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato confirmado y zona de consignación creada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al confirmar contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error confirmando contrato: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al confirmar contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int?> _mostrarDialogoSeleccionarAlmacen({
    required int idTienda,
    required String titulo,
    required String mensaje,
  }) async {
    List<Map<String, dynamic>> almacenes = [];

    try {
      // Obtener almacenes de la tienda
      almacenes = await ConsignacionService.getAlmacenesPorTienda(idTienda);
    } catch (e) {
      debugPrint('❌ Error obteniendo almacenes: $e');
    }

    if (!mounted) return null;

    if (almacenes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No hay almacenes disponibles en esta tienda'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    // Variable para guardar la selección dentro del diálogo
    int? idAlmacenSeleccionado;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mensaje),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(
                  maxHeight: 300,
                  minWidth: 300,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: almacenes.map((almacen) {
                      final almacenId = almacen['id'] as int;
                      final isSelected = idAlmacenSeleccionado == almacenId;

                      return Container(
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          leading: Radio<int>(
                            value: almacenId,
                            groupValue: idAlmacenSeleccionado,
                            onChanged: (value) {
                              setState(() {
                                idAlmacenSeleccionado = value;
                              });
                            },
                          ),
                          title: Text(
                            almacen['denominacion'] ?? 'Almacén $almacenId',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              idAlmacenSeleccionado = almacenId;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (idAlmacenSeleccionado == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Selecciona un almacén para continuar',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: idAlmacenSeleccionado == null
                  ? null
                  : () => Navigator.pop(context, idAlmacenSeleccionado),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Aceptar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: idAlmacenSeleccionado == null ? Colors.grey[300] : Colors.green,
                foregroundColor: idAlmacenSeleccionado == null ? Colors.grey : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoCancelacion(Map<String, dynamic> contrato) {
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Contrato'),
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
                      'Esta acción cancelará el contrato.',
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
              'Contrato ID: ${contrato['id']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tienda: ${contrato['tienda_consignadora']['denominacion']} → ${contrato['tienda_consignataria']['denominacion']}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo de cancelación',
                border: OutlineInputBorder(),
                hintText: 'Ej: No cumple con requisitos, cambio de planes, etc.',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _cancelarContrato(contrato['id'], motivoController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancelar Contrato'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelarContrato(int idContrato, String motivo) async {
    try {
      final success = await ConsignacionService.cancelarContrato(
        idContrato,
        motivo.isNotEmpty ? motivo : 'Sin motivo especificado',
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato cancelado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al cancelar contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error cancelando contrato: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al cancelar contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

}
