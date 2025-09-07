import 'package:flutter/material.dart';
import '../services/seller_sales_service.dart';
import '../services/turno_service.dart';

class SalesMonitorFAB extends StatefulWidget {
  const SalesMonitorFAB({Key? key}) : super(key: key);

  @override
  State<SalesMonitorFAB> createState() => _SalesMonitorFABState();
}

class _SalesMonitorFABState extends State<SalesMonitorFAB>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isLoading = false;
  SellerSalesReport? _currentSales;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

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
      _loadSalesData();
    } else {
      _animationController.reverse();
    }
  }

  Future<void> _loadSalesData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final salesData = await SellerSalesService.getTodaySales();

      setState(() {
        _currentSales = salesData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error loading sales data: $e');
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
                  'Ventas',
                  '${_currentSales!.totalVentas}',
                  Icons.shopping_cart,
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Total',
                  '\$${_currentSales!.totalDineroGeneral.toStringAsFixed(2)}',
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
                      '\$${_currentSales!.totalDineroEfectivo.toStringAsFixed(2)}',
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
                      '\$${_currentSales!.totalDineroTransferencia.toStringAsFixed(2)}',
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
                      '${_currentSales!.totalProductosVendidos.toStringAsFixed(0)} uds',
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
