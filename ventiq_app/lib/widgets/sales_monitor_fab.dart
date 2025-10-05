import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../models/expense.dart';

class SalesMonitorFAB extends StatefulWidget {
  const SalesMonitorFAB({Key? key}) : super(key: key);

  @override
  State<SalesMonitorFAB> createState() => _SalesMonitorFABState();
}

class _SalesMonitorFABState extends State<SalesMonitorFAB>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isLoading = false;
  Map<String, dynamic>? _currentSales;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  // Expenses data
  List<Expense> _expenses = [];
  double _egresosEfectivo = 0.0;
  double _egresosTransferencias = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded) {
      _animationController.forward();
      _loadDataSequentially();
    } else {
      _animationController.reverse();
    }
  }

  Future<void> _loadDataSequentially() async {
    setState(() {
      _isLoading = true;
    });
    
    await _loadExpenses();
    await _loadSalesData();
  }

  Future<void> _loadSalesData() async {
    try {
      final userPrefs = UserPreferencesService();
      
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();
      
      if (isOfflineModeEnabled) {
        print('🔌 SalesMonitor - Modo offline activado, cargando desde cache...');
        await _loadSalesDataOffline();
        return;
      }

      // Modo online: cargar desde servidor
      print('🌐 SalesMonitor - Modo online, cargando desde servidor...');
      
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        print('🧪 Loading sales data with fn_resumen_diario_cierre - TPV: $idTpv');
        
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );
        
        print('📈 Sales Monitor Response: $resumenCierreResponse');
        print('📈 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');
        
        if (resumenCierreResponse != null) {
          Map<String, dynamic> data;
          
          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List && resumenCierreResponse.isNotEmpty) {
            data = resumenCierreResponse[0] as Map<String, dynamic>;
            print('📈 SalesMonitor datos extraídos de lista: ${data.keys.toList()}');
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            data = resumenCierreResponse;
            print('📈 SalesMonitor datos recibidos como mapa: ${data.keys.toList()}');
          } else {
            print('⚠️ Formato de respuesta no reconocido en SalesMonitor');
            setState(() {
              _currentSales = null;
              _isLoading = false;
            });
            return;
          }
          
          setState(() {
            _currentSales = data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _currentSales = null;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _currentSales = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error loading sales data: $e');
    }
  }

  /// Cargar datos de ventas en modo offline
  Future<void> _loadSalesDataOffline() async {
    try {
      print('📱 SalesMonitor - Cargando datos desde cache offline...');
      
      final userPrefs = UserPreferencesService();
      
      // Obtener resumen de cierre actualizado con órdenes offline
      final resumenCierre = await userPrefs.getResumenCierreWithOfflineOrders();
      
      if (resumenCierre != null) {
        print('✅ SalesMonitor - Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');
        
        setState(() {
          _currentSales = resumenCierre;
          _isLoading = false;
        });
        
        print('💰 SalesMonitor - Datos cargados desde cache offline:');
        print('  - Ventas totales: \$${resumenCierre['ventas_totales']}');
        print('  - Productos vendidos: ${resumenCierre['productos_vendidos']}');
        
        // Mostrar información de órdenes offline si las hay
        if (resumenCierre['ordenes_offline'] != null && resumenCierre['ordenes_offline'] > 0) {
          print('📱 SalesMonitor - Órdenes offline incluidas:');
          print('  - Órdenes offline: ${resumenCierre['ordenes_offline']}');
          print('  - Ventas offline: \$${resumenCierre['ventas_offline']}');
        }
        
      } else {
        print('⚠️ SalesMonitor - No hay resumen de cierre en cache');
        setState(() {
          _currentSales = null;
          _isLoading = false;
        });
      }
      
    } catch (e) {
      print('❌ SalesMonitor - Error cargando datos offline: $e');
      setState(() {
        _currentSales = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExpenses() async {
    try {
      final expenses = await TurnoService.getEgresosEnriquecidos();

      // Calculate expenses by payment type
      double efectivo = 0.0;
      double transferencias = 0.0;

      for (final expense in expenses) {
        // Si esDigital es false explícitamente, es efectivo
        // Si esDigital es true o null, considerarlo como transferencia/digital
        if (expense.esDigital == false) {
          efectivo += expense.montoEntrega;
        } else {
          transferencias += expense.montoEntrega;
        }
      }

      setState(() {
        _expenses = expenses;
        _egresosEfectivo = efectivo;
        _egresosTransferencias = transferencias;
      });

      print('DEBUG - Sales Monitor Expenses loaded:');
      print('Egresos efectivo: $_egresosEfectivo');
      print('Egresos transferencias: $_egresosTransferencias');
    } catch (e) {
      print('Error loading expenses in sales monitor: $e');
      setState(() {
        _expenses = [];
        _egresosEfectivo = 0.0;
        _egresosTransferencias = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Panel expandible
        AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _expandAnimation.value,
              alignment: Alignment.bottomRight,
              child: Opacity(
                opacity: _expandAnimation.value,
                child:
                    _isExpanded ? _buildSalesPanel() : const SizedBox.shrink(),
              ),
            );
          },
        ),
        // Botón flotante
        FloatingActionButton(
          onPressed: _toggleExpansion,
          backgroundColor: const Color(0xFF4A90E2),
          child: AnimatedRotation(
            turns: _isExpanded ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isExpanded ? Icons.close : Icons.trending_up,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSalesPanel() {
    return Container(
      margin: const EdgeInsets.only(right: 16, bottom: 80),
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF4A90E2),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Mis Ventas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadSalesData,
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          // Contenido
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFF4A90E2)),
            )
          else
            _buildSalesContent(),
        ],
      ),
    );
  }

  Widget _buildSalesContent() {
    if (_currentSales == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 48),
            SizedBox(height: 8),
            Text(
              'No hay ventas registradas',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Métricas principales
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Operaciones',
                  '${_currentSales!['operaciones_totales'] ?? 0}',
                  Icons.shopping_cart,
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Total',
                  '\$${(_currentSales!['ventas_totales'] ?? 0.0).toStringAsFixed(2)}',
                  Icons.attach_money,
                  const Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Desglose por método de pago
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Desglose por Pago',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Efectivo:', style: TextStyle(fontSize: 13)),
                    Text(
                      '\$${((_currentSales!['efectivo_real'] ?? 0.0) - _egresosEfectivo).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Transferencia:',
                      style: TextStyle(fontSize: 13),
                    ),
                    Text(
                      '\$${((_currentSales!['ventas_totales'] ?? 0.0) - (_currentSales!['efectivo_real'] ?? 0.0) + _egresosEfectivo).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4A90E2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Productos:', style: TextStyle(fontSize: 13)),
                    Text(
                      '${(_currentSales!['productos_vendidos'] ?? 0)} uds',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
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

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
