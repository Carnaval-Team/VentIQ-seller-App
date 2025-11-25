import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';
import 'crear_contrato_consignacion_screen.dart';
import 'asignar_productos_consignacion_screen.dart';
import 'detalle_contrato_consignacion_screen.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
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
            tooltip: 'Crear Contrato',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Resumen'),
            Tab(icon: Icon(Icons.handshake), text: 'Contratos'),
            Tab(icon: Icon(Icons.inventory), text: 'Productos'),
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
                _buildProductosTab(),
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
                    'Productos Enviados',
                    '${_estadisticas['productos_enviados'] ?? 0}',
                    Icons.send,
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
                    'Productos Vendidos',
                    '${_estadisticas['productos_vendidos'] ?? 0}',
                    Icons.shopping_cart,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
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

  // Tab 3: Productos
  Widget _buildProductosTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _contratos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No hay productos en consignación',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _contratos.length,
              itemBuilder: (context, index) {
                final contrato = _contratos[index];
                return _buildContratoProductosCard(contrato);
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
        title: Text(
          esConsignadora
              ? 'Enviando a: ${tiendaConsignataria['denominacion']}'
              : 'Recibiendo de: ${tiendaConsignadora['denominacion']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Comisión: ${contrato['porcentaje_comision'] ?? 0}%'),
            Text('Inicio: ${contrato['fecha_inicio']}'),
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
                        icon: const Icon(Icons.info),
                        label: const Text('Ver Detalle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _verProductosContrato(contrato),
                        icon: const Icon(Icons.inventory),
                        label: const Text('Ver Productos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (esConsignadora) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AsignarProductosConsignacionScreen(
                                  idContrato: contrato['id'],
                                  contrato: contrato,
                                ),
                              ),
                            );
                            if (result == true) {
                              _loadData();
                            }
                          },
                          icon: const Icon(Icons.add_box),
                          label: const Text('Asignar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
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

  Widget _buildContratoProductosCard(Map<String, dynamic> contrato) {
    final tiendaConsignadora = contrato['tienda_consignadora'];
    final tiendaConsignataria = contrato['tienda_consignataria'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.inventory, color: AppColors.primary),
        title: Text(
          '${tiendaConsignadora['denominacion']} → ${tiendaConsignataria['denominacion']}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: ConsignacionService.getProductosConsignacion(contrato['id']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay productos en este contrato'),
                );
              }

              return Column(
                children: snapshot.data!.map((producto) {
                  final prod = producto['producto'];
                  final cantidadEnviada = (producto['cantidad_enviada'] as num).toDouble();
                  final cantidadVendida = (producto['cantidad_vendida'] as num).toDouble();
                  final cantidadDevuelta = (producto['cantidad_devuelta'] as num).toDouble();
                  final stockDisponible = cantidadEnviada - cantidadVendida - cantidadDevuelta;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: const Icon(Icons.inventory_2, color: AppColors.primary, size: 20),
                    ),
                    title: Text(prod['denominacion']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SKU: ${prod['sku'] ?? 'N/A'}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildChip('Enviado: ${cantidadEnviada.toInt()}', Colors.blue),
                            const SizedBox(width: 4),
                            _buildChip('Vendido: ${cantidadVendida.toInt()}', Colors.green),
                            const SizedBox(width: 4),
                            _buildChip('Stock: ${stockDisponible.toInt()}', Colors.orange),
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _verDetalleProducto(producto),
                    ),
                  );
                }).toList(),
              );
            },
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

  void _verProductosContrato(Map<String, dynamic> contrato) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Productos en Consignación'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ConsignacionService.getProductosConsignacion(contrato['id']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Text('No hay productos en este contrato');
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final producto = snapshot.data![index];
                  final prod = producto['producto'];
                  return ListTile(
                    title: Text(prod['denominacion']),
                    subtitle: Text('Enviado: ${producto['cantidad_enviada']} | Vendido: ${producto['cantidad_vendida']}'),
                  );
                },
              );
            },
          ),
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
}
