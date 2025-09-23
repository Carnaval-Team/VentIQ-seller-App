import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/restaurant_service.dart';
import '../services/financial_service.dart';
import '../models/restaurant_models.dart';
import '../widgets/store_selector_widget.dart';
import '../widgets/financial_menu_widget.dart';
import '../services/currency_display_service.dart';
import '../widgets/currency_converter_widget.dart';

class ProductionCostsScreen extends StatefulWidget {
  const ProductionCostsScreen({super.key});

  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _financialService = FinancialService();

  // Estado general
  bool _isLoading = true;
  String _filtroTexto = '';
  bool _showingTestData = false; // Nueva variable para indicar datos de prueba
  // ← NUEVAS VARIABLES PARA MONEDAS
  String _selectedCurrency = 'CUP';
  bool _showCurrencyConverter = false;
  // Datos para análisis
  List<Map<String, dynamic>> _productos = [];
  List<CostoProduccion> _costosHistorial = [];
  Map<String, dynamic> _resumenCostos = {};
  List<Map<String, dynamic>> _productosRentables = [];
  List<Map<String, dynamic>> _productosProblematicos = [];

  // Formatters
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'es_CU',
    symbol: '\$',
  );
  final NumberFormat _percentFormatter = NumberFormat.percentPattern('es_CU');
  final NumberFormat _highPrecisionCurrencyFormatter = NumberFormat.currency(
    locale: 'es_CU',
    symbol: '\$',
    decimalDigits: 4,
  );

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
        _loadProductosElaborados(),
        _loadResumenCostos(),
        _loadAnalisisRentabilidad(),
      ]);
    } catch (e) {
      _showErrorSnackBar('Error cargando datos: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProductosElaborados() async {
    try {
      print('🔄 Iniciando carga de productos elaborados...');
      final productos = await RestaurantService.getPlatosElaborados();
      print('✅ Productos elaborados cargados: ${productos.length}');

      if (productos.isEmpty) {
        print('⚠️ No se encontraron productos elaborados en la base de datos');
        print('💡 Verifica que existan productos con es_elaborado = true');
        print('💡 Creando datos de prueba temporales...');
        _createTestData();
      } else {
        print('📋 Primeros productos elaborados encontrados:');
        for (
          int i = 0;
          i < (productos.length > 3 ? 3 : productos.length);
          i++
        ) {
          final producto = productos[i];

          // Obtener precio del histórico o directo
          double precioCalculado = 0.0;
          if (producto['precio_actual'] != null &&
              (producto['precio_actual'] as List).isNotEmpty) {
            final precios = (producto['precio_actual'] as List);
            if (precios.isNotEmpty) {
              precioCalculado =
                  (precios.first['precio_venta_cup'] as num?)?.toDouble() ??
                  0.0;
            }
          }
          if (precioCalculado == 0.0) {
            precioCalculado =
                (producto['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
          }

          // Obtener cantidad de ingredientes del conteo
          int cantidadIngredientes = 0;
          if (producto['cantidad_ingredientes'] != null &&
              (producto['cantidad_ingredientes'] as List).isNotEmpty) {
            cantidadIngredientes =
                (producto['cantidad_ingredientes'] as List).first['count'] ?? 0;
          }

          print(
            '  - ${producto['denominacion']} (ID: ${producto['id']}, Precio: \$${precioCalculado}, Ingredientes: $cantidadIngredientes)',
          );
        }
        setState(() {
          _productos = productos;
          _showingTestData = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando productos elaborados: $e');
      print('💡 Creando datos de prueba debido al error...');
      _createTestData();
      // Mostrar error al usuario
      if (mounted) {
        _showErrorSnackBar(
          'Error cargando productos elaborados: $e. Mostrando datos de prueba.',
        );
      }
    }
  }

  Future<void> _loadResumenCostos() async {
    try {
      double totalCostoIngredientes = 0;
      double totalCostoManoObra = 0;
      double totalCostoIndirecto = 0;
      double totalPrecioVenta = 0;
      int productosConCosto = 0;

      for (final producto in _productos) {
        try {
          final costos = await RestaurantService.getCostosProduccion(
            producto['id'],
          );
          if (costos.isNotEmpty) {
            final ultimoCosto = costos.first;
            totalCostoIngredientes += ultimoCosto.costoIngredientes;
            totalCostoManoObra += ultimoCosto.costoManoObra ?? 0;
            totalCostoIndirecto += ultimoCosto.costoIndirecto ?? 0;
            totalPrecioVenta += producto['precio_venta'];
            productosConCosto++;
          }
        } catch (e) {
          print(
            '⚠️ Error cargando costos para producto ${producto['nombre']}: $e',
          );
          // Continuar con el siguiente producto
        }
      }

      final totalCostoProduccion =
          totalCostoIngredientes + totalCostoManoObra + totalCostoIndirecto;
      final margenBrutoTotal = totalPrecioVenta - totalCostoProduccion;
      final porcentajeMargen =
          totalPrecioVenta > 0 ? (margenBrutoTotal / totalPrecioVenta) : 0;

      setState(() {
        _resumenCostos = {
          'total_productos': _productos.length,
          'productos_con_costo': productosConCosto,
          'total_costo_ingredientes': totalCostoIngredientes,
          'total_costo_mano_obra': totalCostoManoObra,
          'total_costo_indirecto': totalCostoIndirecto,
          'total_costo_produccion': totalCostoProduccion,
          'total_precio_venta': totalPrecioVenta,
          'margen_bruto_total': margenBrutoTotal,
          'porcentaje_margen': porcentajeMargen,
          'costo_promedio_ingredientes':
              productosConCosto > 0
                  ? totalCostoIngredientes / productosConCosto
                  : 0,
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

      for (final producto in _productos) {
        try {
          final costos = await RestaurantService.getCostosProduccion(
            producto['id'],
          );
          if (costos.isNotEmpty) {
            final ultimoCosto = costos.first;
            final costoTotal =
                ultimoCosto.costoIngredientes +
                (ultimoCosto.costoManoObra ?? 0) +
                (ultimoCosto.costoIndirecto ?? 0);
            final margen = producto['precio_venta'] - costoTotal;
            final porcentajeMargen =
                producto['precio_venta'] > 0
                    ? (margen / producto['precio_venta']) as double
                    : 0.0;

            final productoAnalisis = {
              'producto': producto,
              'costo_total': costoTotal,
              'precio_venta': producto['precio_venta'],
              'margen': margen,
              'porcentaje_margen': porcentajeMargen,
              'ultimo_calculo': ultimoCosto.fechaCalculo,
            };

            if (porcentajeMargen >= 0.25) {
              rentables.add(productoAnalisis);
            } else if (porcentajeMargen < 0.10) {
              problematicos.add(productoAnalisis);
            }
          }
        } catch (e) {
          print('⚠️ Error procesando producto ${producto['nombre']}: $e');
          continue;
        }
      }

      rentables.sort(
        (a, b) => (b['porcentaje_margen'] as double).compareTo(
          a['porcentaje_margen'] as double,
        ),
      );
      problematicos.sort(
        (a, b) => (a['porcentaje_margen'] as double).compareTo(
          b['porcentaje_margen'] as double,
        ),
      );

      setState(() {
        _productosRentables = rentables.take(10).toList();
        _productosProblematicos = problematicos.take(10).toList();
      });
    } catch (e) {
      print('❌ Error en análisis de rentabilidad: $e');
    }
  }

  /// Método auxiliar para cargar costos de manera eficiente
  Future<Map<int, CostoProduccion>> _loadAllCostos() async {
    final costosMap = <int, CostoProduccion>{};

    for (final producto in _productos) {
      try {
        final costos = await RestaurantService.getCostosProduccion(
          producto['id'],
        );
        if (costos.isNotEmpty) {
          costosMap[producto['id']] = costos.first;
        }
      } catch (e) {
        print(
          '⚠️ Error cargando costos para producto ${producto['nombre']}: $e',
        );
      }
    }

    return costosMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Costos de Producción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _showCurrencyConverter
                  ? Icons.visibility_off
                  : Icons.currency_exchange,
            ),
            onPressed: () {
              setState(() {
                _showCurrencyConverter = !_showCurrencyConverter;
              });
            },
            tooltip: 'Convertidor de Monedas',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Resumen'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Productos'),
            Tab(icon: Icon(Icons.analytics), text: 'Análisis'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Convertidor de monedas (mostrar/ocultar)
          if (_showCurrencyConverter) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: CurrencyConverterWidget(
                initialFromCurrency: 'USD',
                initialToCurrency: 'CUP',
                onConversionChanged: (amount, fromCurrency, toCurrency) {
                  // Callback opcional para manejar cambios
                  print('Conversión: $amount $fromCurrency → $toCurrency');
                },
              ),
            ),
            const Divider(),
          ],

          // Tabs existentes
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildResumenTab(),
                _buildProductoTab(),
                _buildAnalisisTab(),
              ],
            ),
          ),
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
                    'Total Productos',
                    '${_resumenCostos['total_productos'] ?? 0}',
                    Icons.restaurant_menu,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Con Costos',
                    '${_resumenCostos['productos_con_costo'] ?? 0}',
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
                    _currencyFormatter.format(
                      _resumenCostos['costo_promedio_ingredientes'] ?? 0,
                    ),
                    Icons.attach_money,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Margen Promedio',
                    _percentFormatter.format(
                      _resumenCostos['porcentaje_margen'] ?? 0,
                    ),
                    Icons.trending_up,
                    _resumenCostos['porcentaje_margen'] != null &&
                            _resumenCostos['porcentaje_margen'] >= 0.25
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

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
              _buildCostoItem(
                'Ingredientes',
                costoIngredientes,
                costoIngredientes / costoTotal,
                Colors.green,
              ),
              _buildCostoItem(
                'Mano de Obra',
                costoManoObra,
                costoManoObra / costoTotal,
                Colors.blue,
              ),
              _buildCostoItem(
                'Costos Indirectos',
                costoIndirecto,
                costoIndirecto / costoTotal,
                Colors.orange,
              ),
            ] else
              const Text('No hay datos de costos disponibles'),
          ],
        ),
      ),
    );
  }

  Widget _buildCostoItem(
    String label,
    double valor,
    double porcentaje,
    Color color,
  ) {
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

  Widget _buildProductoTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final productosFiltrados =
        _productos.where((producto) {
          final nombre =
              producto['denominacion']?.toString() ??
              producto['nombre']?.toString() ??
              '';
          return _filtroTexto.isEmpty ||
              nombre.toLowerCase().contains(_filtroTexto.toLowerCase());
        }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[50],
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar producto',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filtroTexto = value),
          ),
        ),
        Expanded(
          child:
              productosFiltrados.isEmpty
                  ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay productos disponibles',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: productosFiltrados.length,
                    itemBuilder:
                        (context, index) =>
                            _buildProductoCard(productosFiltrados[index]),
                  ),
        ),
      ],
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> producto) {
    // Safe extraction of product name
    final nombre =
        producto['denominacion']?.toString() ??
        producto['nombre']?.toString() ??
        'Sin nombre';

    // Safe extraction of price
    double precio = 0.0;
    if (producto['precio_actual'] != null &&
        (producto['precio_actual'] as List).isNotEmpty) {
      final precios = (producto['precio_actual'] as List);
      if (precios.isNotEmpty) {
        precio = (precios.first['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
      }
    }
    if (precio == 0.0) {
      precio = (producto['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple,
          child: Text(
            nombre.isNotEmpty ? nombre.substring(0, 1).toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Precio: ${_currencyFormatter.format(precio)}',
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),

            // ← AGREGAR CONVERSIÓN DE MONEDA
            if (_selectedCurrency != 'CUP') ...[
              FutureBuilder<double>(
                future: CurrencyDisplayService.convertAmountForDisplay(
                  precio,
                  'CUP',
                  _selectedCurrency,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text(
                      'Precio en $_selectedCurrency: ${CurrencyDisplayService.formatAmountForDisplay(snapshot.data!, _selectedCurrency)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[600],
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            if (producto['categoria'] != null)
              Text(
                'Categoría: ${producto['categoria']['nombre'] ?? producto['categoria']['denominacion'] ?? 'Sin categoría'}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            Text(
              'Ingredientes: ${(producto['cantidad_ingredientes'] != null && (producto['cantidad_ingredientes'] as List).isNotEmpty) ? (producto['cantidad_ingredientes'][0]['count'] ?? 0) : 0}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEstadoDisponibilidad(producto),
            const SizedBox(width: 8),
          ],
        ),
        onTap: () {
          _verDetallesProducto(producto);
        },
      ),
    );
  }

  Widget _buildEstadoDisponibilidad(Map<String, dynamic> producto) {
    // Mostrar estado básico sin consulta automática para mejorar rendimiento
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: (producto['es_activo'] ?? true) ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
      ),
    );
  }

  Future<void> _verDetallesProducto(Map<String, dynamic> producto) async {
    try {
      // Mostrar diálogo de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Cargando ingredientes...'),
                ],
              ),
            ),
      );

      // Solo cargar ingredientes - es lo más importante y lento
      List<Map<String, dynamic>> ingredientesDetallados = [];
      try {
        print('📋 Cargando ingredientes del producto ${producto['id']}...');
        ingredientesDetallados =
            await RestaurantService.getIngredientesProductoElaborado(
              producto['id'],
            );
        print('✅ Ingredientes cargados: ${ingredientesDetallados.length}');
      } catch (e) {
        print('⚠️ Error cargando ingredientes: $e');
      }

      // Cerrar diálogo de carga
      Navigator.of(context).pop();

      // Calcular métricas básicas
      double precioVenta = 0.0;

      // Usar la misma lógica que RestaurantService.getPlatosElaborados()
      if (producto['precio_actual'] != null &&
          (producto['precio_actual'] as List).isNotEmpty) {
        final precios = (producto['precio_actual'] as List);
        if (precios.isNotEmpty) {
          precioVenta =
              _parseDoubleSafely(precios.first['precio_venta_cup']) ?? 0.0;
        }
      }
      if (precioVenta == 0.0) {
        precioVenta = _parseDoubleSafely(producto['precio_venta_cup']) ?? 0.0;
      }

      print(
        '💰 Precio calculado para ${producto['denominacion']}: $precioVenta',
      );
      print('📋 precio_actual: ${producto['precio_actual']}');
      print('📋 precio_venta_cup: ${producto['precio_venta_cup']}');

      final costoIngredientes = ingredientesDetallados.fold<double>(
        0.0,
        (sum, ing) => sum + (ing['costo_total'] ?? 0.0),
      );
      final margenReal = precioVenta - costoIngredientes;
      final porcentajeMargenReal =
          precioVenta > 0 ? (margenReal / precioVenta) : 0.0;

      // Mostrar resultados
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                'Detalles del Producto - ${producto['denominacion']}',
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Información básica del producto
                      _buildInfoSection(
                        'Información General',
                        Icons.info_outline,
                        [
                          _buildInfoRow('ID del producto', '${producto['id']}'),
                          _buildInfoRow('SKU', '${producto['sku'] ?? 'N/A'}'),
                          _buildInfoRow(
                            'Ingredientes',
                            '${ingredientesDetallados.length}',
                          ),
                          if (producto['tiempo_preparacion'] != null)
                            _buildInfoRow(
                              'Tiempo preparación',
                              '${producto['tiempo_preparacion']} min',
                            ),
                          if (producto['descripcion'] != null)
                            _buildInfoRow(
                              'Descripción',
                              producto['descripcion'],
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Lista de ingredientes detallados con diseño mejorado
                      if (ingredientesDetallados.isNotEmpty) ...[
                        _buildIngredientesSection(ingredientesDetallados),
                        const SizedBox(height: 16),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No se encontraron ingredientes para este producto',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Análisis de costos simplificado
                      _buildInfoSection('Análisis de Costos', Icons.calculate, [
                        _buildInfoRow(
                          'Precio de venta',
                          _currencyFormatter.format(precioVenta),
                          valueColor: Colors.green,
                        ),
                        _buildInfoRow(
                          'Costo ingredientes',
                          _highPrecisionCurrencyFormatter.format(
                            costoIngredientes,
                          ),
                          valueColor: Colors.blue,
                        ),
                        _buildInfoRow(
                          'Margen bruto',
                          _currencyFormatter.format(margenReal),
                          valueColor:
                              margenReal >= 0 ? Colors.green : Colors.red,
                        ),
                        _buildInfoRow(
                          'Margen %',
                          _percentFormatter.format(porcentajeMargenReal),
                          valueColor: _getMargenColor(porcentajeMargenReal),
                          isTotal: true,
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // Botones de acción
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _calcularCostoProducto(producto),
                              icon: const Icon(Icons.calculate, size: 18),
                              label: const Text('Calcular Costo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _verHistorialCostos(producto),
                              icon: const Icon(Icons.history, size: 18),
                              label: const Text('Historial'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );

      print('✅ Diálogo de detalles mostrado exitosamente');
    } catch (e) {
      // Cerrar diálogo de carga si está abierto
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('❌ Error en _verDetallesProducto: $e');
      _showErrorSnackBar('Error al cargar detalles del producto: $e');
    }
  }

  Widget _buildInfoSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.textPrimary : Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color:
                  valueColor ??
                  (isTotal ? AppColors.textPrimary : Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientesSection(List<Map<String, dynamic>> ingredientes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.restaurant_menu, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Ingredientes Detallados (${ingredientes.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Lista de ingredientes
        ...ingredientes.map((ingrediente) {
          final costoTotal = ingrediente['costo_total'] ?? 0.0;
          final cantidadRequerida = ingrediente['cantidad_requerida'] ?? 0.0;
          final costoUnitario = ingrediente['costo_unitario_promedio'] ?? 0.0;
          final unidadReceta = ingrediente['unidad_receta'] ?? '';

          // Información de conversiones
          final cantidadEnUnidadBase =
              ingrediente['cantidad_en_unidad_base'] ?? cantidadRequerida;
          final unidadProducto = ingrediente['unidad_producto'] ?? unidadReceta;
          final cantidadPorPresentacion =
              ingrediente['cantidad_por_presentacion'] ?? 1.0;
          final cantidadEnPresentaciones =
              ingrediente['cantidad_en_presentaciones'] ?? cantidadRequerida;
          final conversionAplicada =
              ingrediente['conversion_aplicada'] ?? false;
          final factorConversion = ingrediente['factor_conversion'] ?? 1.0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre del ingrediente
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${ingrediente['denominacion'] ?? ingrediente['sku'] ?? 'Ingrediente'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (conversionAplicada)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'CONVERTIDO',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'SKU: ${ingrediente['sku'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),

                  // Información de cantidades y conversiones
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        // Cantidad requerida original
                        Row(
                          children: [
                            Icon(Icons.scale, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cantidad en receta:',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            Text(
                              '$cantidadRequerida $unidadReceta',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        // Conversión de unidades (si aplica)
                        if (conversionAplicada) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.transform,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cantidad en unidad base:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              Text(
                                '$cantidadEnUnidadBase $unidadProducto',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const SizedBox(width: 24),
                              Expanded(
                                child: Text(
                                  'Factor de conversión:',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                              Text(
                                '×${factorConversion.toStringAsFixed(3)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Cantidad en presentaciones
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cantidad en presentaciones:',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            Text(
                              '${cantidadEnPresentaciones.toStringAsFixed(3)} pres.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                        if (cantidadPorPresentacion != 1.0) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const SizedBox(width: 24),
                              Expanded(
                                child: Text(
                                  'Unidades por presentación:',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                              Text(
                                '$cantidadPorPresentacion $unidadProducto',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Información de costos
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Costo por ${unidadProducto}:',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _highPrecisionCurrencyFormatter.format(
                                ingrediente['costo_por_unidad_base'] ??
                                    costoUnitario,
                              ),
                              style: const TextStyle(
                                fontSize: 12,
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
                              'Costo presentación:',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _highPrecisionCurrencyFormatter.format(
                                ingrediente['costo_presentacion_completa'] ??
                                    costoUnitario,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
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
                              'Costo total:',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _highPrecisionCurrencyFormatter.format(
                                costoTotal,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Participación en el costo total
                  Row(
                    children: [
                      Icon(Icons.pie_chart, size: 16, color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Participación en receta:',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      Text(
                        '${(costoTotal / ingredientes.fold<double>(0.0, (sum, ing) => sum + (ing['costo_total'] ?? 0.0)) * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
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
          _buildProductosRentables(),
          const SizedBox(height: 24),
          _buildProductosProblematicos(),
        ],
      ),
    );
  }

  Widget _buildProductosRentables() {
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
                Expanded(
                  child: const Text(
                    'Productos Más Rentables',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_productosRentables.isNotEmpty)
              ..._productosRentables.map(
                (item) => _buildAnalisisItem(item, Colors.green),
              )
            else
              const Text('No hay productos con análisis de rentabilidad'),
          ],
        ),
      ),
    );
  }

  Widget _buildProductosProblematicos() {
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
                Expanded(
                  child: const Text(
                    'Productos con Problemas de Rentabilidad',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_productosProblematicos.isNotEmpty)
              ..._productosProblematicos.map(
                (item) => _buildAnalisisItem(item, Colors.red),
              )
            else
              const Text('No hay productos con problemas de rentabilidad'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalisisItem(Map<String, dynamic> item, Color color) {
    final producto = item['producto'] as Map<String, dynamic>;
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
                Text(
                  producto['denominacion'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Margen: ${_currencyFormatter.format(margen)}',
                  style: TextStyle(color: color),
                ),
              ],
            ),
          ),
          Text(
            _percentFormatter.format(porcentajeMargen),
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

  void _calcularCostoProducto(Map<String, dynamic> producto) async {
    try {
      // Obtener costos directos del RestaurantService
      final costosDirectos = await RestaurantService.getCostosProduccionByPlato(
        producto['id'],
      );

      // Obtener asignaciones de costos del FinancialService
      final asignacionesCostos = await _financialService
          .getCostAssignmentsByProduct(producto['id']);

      // Calcular totales
      double costoDirectoTotal = 0.0;
      double costoIndirectoTotal = 0.0;

      // Sumar costos directos (ingredientes)
      for (var costo in costosDirectos) {
        final costoIngrediente =
            (costo['costo_unitario'] ?? 0.0) * (costo['cantidad'] ?? 0.0);
        costoDirectoTotal += costoIngrediente;
      }

      // Para costos indirectos, necesitamos obtener los gastos reales asignados
      // Por ahora usaremos un estimado basado en el porcentaje de asignación
      for (var asignacion in asignacionesCostos) {
        final porcentaje =
            (asignacion['porcentaje_asignacion'] ?? 0.0) as double;
        // Estimamos un costo indirecto basado en el costo directo y el porcentaje
        final costoAsignado = costoDirectoTotal * (porcentaje / 100);
        costoIndirectoTotal += costoAsignado;
      }

      final costoTotal = costoDirectoTotal + costoIndirectoTotal;

      // Obtener margen comercial
      final margenes = await _financialService.getProfitMargins(
        productId: producto['id'],
      );
      final margenPorcentaje =
          margenes.isNotEmpty
              ? (margenes.first['margen_deseado'] ?? 25.0) as double
              : 25.0;

      final precioSugerido = costoTotal * (1 + margenPorcentaje / 100);

      // Mostrar resultados
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('Costos Integrados - ${producto['denominacion']}'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Costos directos
                      Text(
                        'COSTOS DIRECTOS (Ingredientes)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...costosDirectos.map(
                        (costo) => Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${costo['nombre_producto']} (${costo['cantidad']} ${costo['unidad']})',
                                ),
                              ),
                              Text(
                                _highPrecisionCurrencyFormatter.format(
                                  costo['costo_total'],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Subtotal Directo:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _highPrecisionCurrencyFormatter.format(
                                costoDirectoTotal,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Costos indirectos
                      Text(
                        'COSTOS INDIRECTOS (Asignaciones)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (asignacionesCostos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: Text(
                            'No hay asignaciones de costos configuradas',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        ...asignacionesCostos.map((asignacion) {
                          final porcentaje =
                              (asignacion['porcentaje_asignacion'] ?? 0.0)
                                  as double;
                          // Estimamos un costo indirecto basado en el costo directo y el porcentaje
                          final costoAsignado =
                              costoDirectoTotal * (porcentaje / 100);
                          final tipoCosto =
                              asignacion['app_cont_tipo_costo']?['denominacion'] ??
                              'Tipo desconocido';
                          return Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$tipoCosto (${porcentaje.toStringAsFixed(1)}%)',
                                  ),
                                ),
                                Text(
                                  _highPrecisionCurrencyFormatter.format(
                                    costoAsignado,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                      if (asignacionesCostos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Subtotal Indirecto:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _highPrecisionCurrencyFormatter.format(
                                  costoIndirectoTotal,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const Divider(thickness: 2),

                      // Totales y análisis
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'COSTO TOTAL:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _highPrecisionCurrencyFormatter.format(costoTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Margen Comercial (${margenPorcentaje.toStringAsFixed(1)}%):',
                          ),
                          Text(
                            _highPrecisionCurrencyFormatter.format(
                              precioSugerido - costoTotal,
                            ),
                          ),
                        ],
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'PRECIO SUGERIDO:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            _highPrecisionCurrencyFormatter.format(
                              precioSugerido,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // TODO: Implementar actualización de costo en la base de datos
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Cálculo completado. Función de actualización pendiente.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Actualizar Costo'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorSnackBar('Error al calcular costos: $e');
    }
  }

  void _verHistorialCostos(Map<String, dynamic> producto) async {
    try {
      // Obtener historial de costos del RestaurantService
      final historialCostos = await RestaurantService.getCostosProduccion(
        producto['id'],
      );

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('Historial de Costos - ${producto['denominacion']}'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child:
                    historialCostos.isEmpty
                        ? const Center(
                          child: Text('No hay historial de costos disponible'),
                        )
                        : ListView.builder(
                          itemCount: historialCostos.length,
                          itemBuilder: (context, index) {
                            final costo = historialCostos[index];
                            final costoTotal =
                                costo.costoIngredientes +
                                costo.costoManoObra +
                                costo.costoIndirecto;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(
                                  'Costo Total: ${_highPrecisionCurrencyFormatter.format(costoTotal)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ingredientes: ${_highPrecisionCurrencyFormatter.format(costo.costoIngredientes)}',
                                    ),
                                    if (costo.costoManoObra > 0)
                                      Text(
                                        'Mano de obra: ${_highPrecisionCurrencyFormatter.format(costo.costoManoObra)}',
                                      ),
                                    if (costo.costoIndirecto > 0)
                                      Text(
                                        'Indirectos: ${_highPrecisionCurrencyFormatter.format(costo.costoIndirecto)}',
                                      ),
                                    Text(
                                      'Fecha: ${costo.fechaCalculo.toString().split(' ')[0]}',
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.history,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            );
                          },
                        ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorSnackBar('Error al cargar historial: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _createTestData() {
    final testProductos = [
      {
        'id': 1,
        'nombre': 'Pizza Margherita (PRUEBA)',
        'descripcion': 'Pizza clásica con tomate, mozzarella y albahaca',
        'precio_venta': 15.99,
        'es_activo': true,
        'created_at': DateTime.now(),
        'recetas': [],
      },
      {
        'id': 2,
        'nombre': 'Hamburguesa Clásica (PRUEBA)',
        'descripcion': 'Hamburguesa con carne, lechuga, tomate y queso',
        'precio_venta': 12.50,
        'es_activo': true,
        'created_at': DateTime.now(),
        'recetas': [],
      },
      {
        'id': 3,
        'nombre': 'Ensalada César (PRUEBA)',
        'descripcion': 'Ensalada fresca con pollo, crutones y aderezo césar',
        'precio_venta': 9.99,
        'es_activo': true,
        'created_at': DateTime.now(),
        'recetas': [],
      },
    ];

    setState(() {
      _productos = testProductos;
      _showingTestData = true;
    });
    print(
      '✅ Datos de prueba creados: ${testProductos.length} productos elaborados',
    );
  }

  double? _parseDoubleSafely(dynamic value) {
    try {
      return double.parse(value.toString());
    } catch (e) {
      return null;
    }
  }

  Color _getMargenColor(double porcentajeMargen) {
    if (porcentajeMargen >= 0.25) {
      return Colors.green; // Margen bueno (≥25%)
    } else if (porcentajeMargen >= 0.10) {
      return Colors.orange; // Margen regular (10-24%)
    } else if (porcentajeMargen >= 0) {
      return Colors.red; // Margen bajo pero positivo (0-9%)
    } else {
      return Colors.red.shade700; // Margen negativo (pérdida)
    }
  }
}
