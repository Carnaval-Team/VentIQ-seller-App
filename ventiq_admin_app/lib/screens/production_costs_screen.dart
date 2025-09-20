import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/restaurant_service.dart';
import '../services/financial_service.dart';
import '../models/restaurant_models.dart';
import '../widgets/store_selector_widget.dart';
import '../widgets/financial_menu_widget.dart';

class ProductionCostsScreen extends StatefulWidget {
  const ProductionCostsScreen({super.key});

  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Estado general
  bool _isLoading = true;
  String _filtroTexto = '';
  
  // Datos para análisis
  List<PlatoElaborado> _platos = [];
  List<CostoProduccion> _costosHistorial = [];
  Map<String, dynamic> _resumenCostos = {};
  List<Map<String, dynamic>> _platosRentables = [];
  List<Map<String, dynamic>> _platosProblematicos = [];
  
  // Formatters
  final _currencyFormatter = NumberFormat.currency(locale: 'es_ES', symbol: '\$');
  final _percentFormatter = NumberFormat.percentPattern('es_ES');

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
      await Future.wait([
        _loadPlatos(),
        _loadResumenCostos(),
        _loadAnalisisRentabilidad(),
      ]);
    } catch (e) {
      _showErrorSnackBar('Error cargando datos: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPlatos() async {
    try {
      final platos = await RestaurantService.getPlatosElaborados();
      setState(() => _platos = platos);
    } catch (e) {
      print('❌ Error cargando platos: $e');
    }
  }

  Future<void> _loadResumenCostos() async {
    try {
      double totalCostoIngredientes = 0;
      double totalCostoManoObra = 0;
      double totalCostoIndirecto = 0;
      double totalPrecioVenta = 0;
      int platosConCosto = 0;

      for (final plato in _platos) {
        final costos = await RestaurantService.getCostosProduccion(plato.id);
        if (costos.isNotEmpty) {
          final ultimoCosto = costos.first;
          totalCostoIngredientes += ultimoCosto.costoIngredientes;
          totalCostoManoObra += ultimoCosto.costoManoObra ?? 0;
          totalCostoIndirecto += ultimoCosto.costoIndirecto ?? 0;
          totalPrecioVenta += plato.precioVenta;
          platosConCosto++;
        }
      }

      final totalCostoProduccion = totalCostoIngredientes + totalCostoManoObra + totalCostoIndirecto;
      final margenBrutoTotal = totalPrecioVenta - totalCostoProduccion;
      final porcentajeMargen = totalPrecioVenta > 0 ? (margenBrutoTotal / totalPrecioVenta) : 0;

      setState(() {
        _resumenCostos = {
          'total_platos': _platos.length,
          'platos_con_costo': platosConCosto,
          'total_costo_ingredientes': totalCostoIngredientes,
          'total_costo_mano_obra': totalCostoManoObra,
          'total_costo_indirecto': totalCostoIndirecto,
          'total_costo_produccion': totalCostoProduccion,
          'total_precio_venta': totalPrecioVenta,
          'margen_bruto_total': margenBrutoTotal,
          'porcentaje_margen': porcentajeMargen,
          'costo_promedio_ingredientes': platosConCosto > 0 ? totalCostoIngredientes / platosConCosto : 0,
        };
      });
    } catch (e) {
      print('❌ Error calculando resumen: $e');
    }
  }

  Future<void> _loadAnalisisRentabilidad() async {
    try {
      final List<Map<String, dynamic>> rentables = [];
      final List<Map<String, dynamic>> problematicos = [];

      for (final plato in _platos) {
        final costos = await RestaurantService.getCostosProduccion(plato.id);
        if (costos.isNotEmpty) {
          final ultimoCosto = costos.first;
          final costoTotal = ultimoCosto.costoIngredientes + 
                           (ultimoCosto.costoManoObra ?? 0) + 
                           (ultimoCosto.costoIndirecto ?? 0);
          final margen = plato.precioVenta - costoTotal;
          final porcentajeMargen = plato.precioVenta > 0 ? (margen / plato.precioVenta) : 0;

          final platoAnalisis = {
            'plato': plato,
            'costo_total': costoTotal,
            'precio_venta': plato.precioVenta,
            'margen': margen,
            'porcentaje_margen': porcentajeMargen,
            'ultimo_calculo': ultimoCosto.fechaCalculo,
          };

          if (porcentajeMargen >= 0.25) {
            rentables.add(platoAnalisis);
          } else if (porcentajeMargen < 0.10) {
            problematicos.add(platoAnalisis);
          }
        }
      }

      rentables.sort((a, b) => (b['porcentaje_margen'] as double).compareTo(a['porcentaje_margen'] as double));
      problematicos.sort((a, b) => (a['porcentaje_margen'] as double).compareTo(b['porcentaje_margen'] as double));

      setState(() {
        _platosRentables = rentables.take(10).toList();
        _platosProblematicos = problematicos.take(10).toList();
      });
    } catch (e) {
      print('❌ Error en análisis de rentabilidad: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Costos de Producción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          FinancialMenuWidget(),
          SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Resumen'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Por Plato'),
            Tab(icon: Icon(Icons.analytics), text: 'Análisis'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResumenTab(),
          _buildPlatoTab(),
          _buildAnalisisTab(),
        ],
      ),
    );
  }

  Widget _buildResumenTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResumenGeneral(),
          const SizedBox(height: 24),
          _buildDistribucionCostos(),
        ],
      ),
    );
  }

  Widget _buildResumenGeneral() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Resumen General',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Platos',
                    '${_resumenCostos['total_platos'] ?? 0}',
                    Icons.restaurant_menu,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Con Costos',
                    '${_resumenCostos['platos_con_costo'] ?? 0}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Costo Promedio',
                    _currencyFormatter.format(_resumenCostos['costo_promedio_ingredientes'] ?? 0),
                    Icons.attach_money,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Margen Promedio',
                    _percentFormatter.format(_resumenCostos['porcentaje_margen'] ?? 0),
                    Icons.trending_up,
                    _resumenCostos['porcentaje_margen'] != null && _resumenCostos['porcentaje_margen'] >= 0.25
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDistribucionCostos() {
    final costoIngredientes = _resumenCostos['total_costo_ingredientes'] ?? 0.0;
    final costoManoObra = _resumenCostos['total_costo_mano_obra'] ?? 0.0;
    final costoIndirecto = _resumenCostos['total_costo_indirecto'] ?? 0.0;
    final costoTotal = costoIngredientes + costoManoObra + costoIndirecto;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Distribución de Costos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (costoTotal > 0) ...[
              _buildCostoItem('Ingredientes', costoIngredientes, costoIngredientes / costoTotal, Colors.green),
              _buildCostoItem('Mano de Obra', costoManoObra, costoManoObra / costoTotal, Colors.blue),
              _buildCostoItem('Costos Indirectos', costoIndirecto, costoIndirecto / costoTotal, Colors.orange),
            ] else
              const Text('No hay datos de costos disponibles'),
          ],
        ),
      ),
    );
  }

  Widget _buildCostoItem(String label, double valor, double porcentaje, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                '${_currencyFormatter.format(valor)} (${_percentFormatter.format(porcentaje)})',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: porcentaje,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatoTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final platosFiltrados = _platos.where((plato) {
      return _filtroTexto.isEmpty ||
          plato.nombre.toLowerCase().contains(_filtroTexto.toLowerCase());
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[50],
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar plato',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filtroTexto = value),
          ),
        ),
        Expanded(
          child: platosFiltrados.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No hay platos disponibles', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: platosFiltrados.length,
                  itemBuilder: (context, index) => _buildPlatoCard(platosFiltrados[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildPlatoCard(PlatoElaborado plato) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple,
          child: Text(
            plato.nombre.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(plato.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Precio: ${_currencyFormatter.format(plato.precioVenta)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.calculate, color: Colors.purple),
              onPressed: () => _calcularCostoPlato(plato),
            ),
            IconButton(
              icon: const Icon(Icons.history, color: Colors.blue),
              onPressed: () => _verHistorialCostos(plato),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalisisTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPlatosRentables(),
          const SizedBox(height: 24),
          _buildPlatosProblematicos(),
        ],
      ),
    );
  }

  Widget _buildPlatosRentables() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Platos Más Rentables', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (_platosRentables.isNotEmpty)
              ..._platosRentables.map((item) => _buildAnalisisItem(item, Colors.green))
            else
              const Text('No hay platos con análisis de rentabilidad'),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatosProblematicos() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_down, color: Colors.red),
                const SizedBox(width: 8),
                const Text('Platos con Problemas de Rentabilidad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (_platosProblematicos.isNotEmpty)
              ..._platosProblematicos.map((item) => _buildAnalisisItem(item, Colors.red))
            else
              const Text('No hay platos con problemas de rentabilidad'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalisisItem(Map<String, dynamic> item, Color color) {
    final plato = item['plato'] as PlatoElaborado;
    final margen = item['margen'] as double;
    final porcentajeMargen = item['porcentaje_margen'] as double;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plato.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Margen: ${_currencyFormatter.format(margen)}', style: TextStyle(color: color)),
              ],
            ),
          ),
          Text(
            _percentFormatter.format(porcentajeMargen),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  void _calcularCostoPlato(PlatoElaborado plato) async {
    // TODO: Implementar cálculo de costo
    _showErrorSnackBar('Función en desarrollo');
  }

  void _verHistorialCostos(PlatoElaborado plato) async {
    // TODO: Implementar historial
    _showErrorSnackBar('Función en desarrollo');
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
