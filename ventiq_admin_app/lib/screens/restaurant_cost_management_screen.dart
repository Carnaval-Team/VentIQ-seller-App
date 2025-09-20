import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/restaurant_service.dart';
import '../models/restaurant_models.dart';

class RestaurantCostManagementScreen extends StatefulWidget {
  const RestaurantCostManagementScreen({Key? key}) : super(key: key);

  @override
  State<RestaurantCostManagementScreen> createState() => _RestaurantCostManagementScreenState();
}

class _RestaurantCostManagementScreenState extends State<RestaurantCostManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Estado
  List<PlatoElaborado> _platos = [];
  List<CostoProduccion> _costosHistorial = [];
  bool _isLoading = true;
  
  // Filtros
  String _filtroTexto = '';
  
  // Formatters
  final _currencyFormatter = NumberFormat.currency(locale: 'es_ES', symbol: '\$');

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
      final platos = await RestaurantService.getPlatosElaborados();
      
      setState(() {
        _platos = platos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error cargando datos: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<PlatoElaborado> get _platosFiltrados {
    var filtrados = _platos.where((plato) {
      final matchTexto = _filtroTexto.isEmpty ||
          plato.nombre.toLowerCase().contains(_filtroTexto.toLowerCase());
      
      return matchTexto && plato.esActivo;
    }).toList();
    
    filtrados.sort((a, b) => a.nombre.compareTo(b.nombre));
    return filtrados;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Costos de Producción'),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Platos'),
            Tab(icon: Icon(Icons.analytics), text: 'Análisis'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlatosTab(),
          _buildAnalisisTab(),
        ],
      ),
    );
  }

  Widget _buildPlatosTab() {
    return Column(
      children: [
        // Filtros
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar plato',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filtroTexto = value),
          ),
        ),
        // Lista de platos
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _platosFiltrados.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No hay platos elaborados', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _platosFiltrados.length,
                      itemBuilder: (context, index) {
                        final plato = _platosFiltrados[index];
                        return _buildPlatoCard(plato);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPlatoCard(PlatoElaborado plato) {
    final costoEstimado = plato.costoEstimado;
    final margenEstimado = plato.margenEstimado;
    final rentabilidad = _getRentabilidadColor(margenEstimado);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: rentabilidad.color,
          child: Icon(rentabilidad.icon, color: Colors.white, size: 20),
        ),
        title: Text(plato.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Precio venta: ${_currencyFormatter.format(plato.precioVenta)}'),
            if (costoEstimado > 0) ...[
              Text('Costo estimado: ${_currencyFormatter.format(costoEstimado)}'),
              Text('Margen: ${margenEstimado.toStringAsFixed(1)}%',
                style: TextStyle(color: rentabilidad.color, fontWeight: FontWeight.bold)),
            ] else
              const Text('Sin costo calculado', style: TextStyle(color: Colors.orange)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plato.descripcion != null) ...[
                  Text('Descripción:', style: Theme.of(context).textTheme.titleSmall),
                  Text(plato.descripcion!),
                  const SizedBox(height: 12),
                ],
                if (plato.recetas.isNotEmpty) ...[
                  Text('Ingredientes:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...plato.recetas.map((receta) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('• ${receta.producto?.denominacion ?? 'N/A'}')),
                        Text('${receta.cantidadRequerida} ${receta.um ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _calcularCosto(plato),
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calcular'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _verHistorialCostos(plato),
                      icon: const Icon(Icons.history),
                      label: const Text('Historial'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalisisTab() {
    final platosConCosto = _platos.where((p) => p.costoEstimado > 0).length;
    final margenPromedio = platosConCosto > 0 
        ? _platos.where((p) => p.costoEstimado > 0).map((p) => p.margenEstimado).fold(0.0, (a, b) => a + b) / platosConCosto
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resumen General', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Total Platos', _platos.length.toString(), Icons.restaurant_menu, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('Con Costo', platosConCosto.toString(), Icons.attach_money, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('Margen Promedio', '${margenPromedio.toStringAsFixed(1)}%', Icons.trending_up, Colors.orange)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  ({Color color, IconData icon}) _getRentabilidadColor(double margen) {
    if (margen >= 30) return (color: Colors.green, icon: Icons.trending_up);
    if (margen >= 20) return (color: Colors.orange, icon: Icons.trending_flat);
    return (color: Colors.red, icon: Icons.trending_down);
  }

  void _calcularCosto(PlatoElaborado plato) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Calculando costo...')],
        ),
      ),
    );

    try {
      final costo = await RestaurantService.calcularCostoProduccion(plato.id);
      Navigator.pop(context);
      _showCostoDialog(plato, costo);
    } catch (e) {
      Navigator.pop(context);
      _showErrorSnackBar('Error calculando costo: $e');
    }
  }

  void _showCostoDialog(PlatoElaborado plato, CostoProduccion costo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Costo - ${plato.nombre}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Costo ingredientes: ${_currencyFormatter.format(costo.costoIngredientes)}'),
            Text('Costo total: ${_currencyFormatter.format(costo.costoTotal)}'),
            Text('Precio sugerido: ${_currencyFormatter.format(costo.precioSugerido)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ElevatedButton(
            onPressed: () => _guardarCosto(plato, costo),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _guardarCosto(PlatoElaborado plato, CostoProduccion costo) async {
    try {
      await RestaurantService.guardarCostoProduccion(costo);
      Navigator.pop(context);
      _showSuccessSnackBar('Costo guardado correctamente');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Error guardando costo: $e');
    }
  }

  void _verHistorialCostos(PlatoElaborado plato) async {
    try {
      final costos = await RestaurantService.getCostosProduccion(plato.id);
      _showHistorialDialog(plato, costos);
    } catch (e) {
      _showErrorSnackBar('Error cargando historial: $e');
    }
  }

  void _showHistorialDialog(PlatoElaborado plato, List<CostoProduccion> costos) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historial - ${plato.nombre}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: costos.isEmpty
              ? const Center(child: Text('No hay historial'))
              : ListView.builder(
                  itemCount: costos.length,
                  itemBuilder: (context, index) {
                    final costo = costos[index];
                    return ListTile(
                      title: Text(DateFormat('dd/MM/yyyy').format(costo.fechaCalculo)),
                      subtitle: Text('Total: ${_currencyFormatter.format(costo.costoTotal)}'),
                      trailing: Text('${costo.margenDeseado}%'),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }
}
