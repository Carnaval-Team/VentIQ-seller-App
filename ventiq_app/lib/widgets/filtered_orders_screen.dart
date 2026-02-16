import 'package:flutter/material.dart';
import '../models/order.dart';

enum PaymentFilter { all, cash, digital, transfer }

class FilteredOrdersScreen extends StatelessWidget {
  final PaymentFilter filter;
  final String title;
  final List<Order> orders;
  final double totalAmount;

  const FilteredOrdersScreen({
    Key? key,
    required this.filter,
    required this.title,
    required this.orders,
    required this.totalAmount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header con estadísticas
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.blue[700]!, Colors.blue[700]!.withOpacity(0.8)],
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(
                      'Total Órdenes',
                      '${filteredOrders.length}',
                      Icons.receipt_long,
                      Colors.white,
                    ),
                    _buildStatCard(
                      'Monto Total',
                      '\$${totalAmount.toStringAsFixed(0)}',
                      Icons.attach_money,
                      Colors.white,
                    ),
                    _buildStatCard(
                      'Promedio',
                      filteredOrders.isNotEmpty
                          ? '\$${(totalAmount / filteredOrders.length).toStringAsFixed(0)}'
                          : '\$0',
                      Icons.trending_up,
                      Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Lista de órdenes
          Expanded(
            child:
                filteredOrders.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = filteredOrders[index];
                        return _buildOrderCard(context, order);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  List<Order> _getFilteredOrders() {
    print('🔍 Filtrando órdenes con filtro: $filter');
    print('📋 Total órdenes a filtrar: ${orders.length}');
    
    final filtered = orders.where((order) {
      // Verificar que la orden tenga pagos
      if (order.pagos == null || (order.pagos as List).isEmpty) {
        print('❌ Orden ${order.id} sin pagos - excluida');
        return false;
      }

      final pagos = order.pagos as List;
      print('💳 Orden ${order.id} tiene ${pagos.length} pagos: $pagos');

      switch (filter) {
        case PaymentFilter.cash:
          // Solo órdenes con pagos en efectivo
          final efectivo = pagos.any((pago) => pago['es_efectivo'] == true);
          print('💸 Orden ${order.id} tiene pagos en efectivo: $efectivo');
          return efectivo;

        case PaymentFilter.digital:
          // Solo órdenes con pagos digitales
          final digital = pagos.any((pago) => pago['es_digital'] == true);
          print('📱 Orden ${order.id} tiene pagos digitales: $digital');
          return digital;

        case PaymentFilter.transfer:
          // Solo órdenes con transferencias (es_digital = true, es_efectivo = false)
          final transfer = pagos.any(
            (pago) =>
                pago['es_efectivo'] == false && pago['es_digital'] == true,
          );
          print('💳 Orden ${order.id} tiene transferencias: $transfer');
          return transfer;

        case PaymentFilter.all:
          return true;
      }
    }).toList();
    
    print('✅ Órdenes filtradas: ${filtered.length}');
    return filtered;
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(color: color.withOpacity(0.9), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay órdenes para mostrar',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No se encontraron órdenes con el filtro seleccionado',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Order order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetails(context, order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header de la orden
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orden #${order.id}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(order.fechaCreacion),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[600]!.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green[600]!.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '\$${order.total.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[600]!,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Información del cliente si existe
              if (order.buyerName != null && order.buyerName!.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.buyerName!,
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Chips de métodos de pago
              if (order.pagos != null && (order.pagos as List).isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _buildPaymentMethodChips(order.pagos as List),
                ),
                const SizedBox(height: 8),
              ],

              // Información de productos
              Row(
                children: [
                  Icon(Icons.shopping_cart, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${order.distinctItemCount} productos',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPaymentMethodChips(List<dynamic> pagos) {
    // Agrupar pagos por método de pago y tipo
    Map<String, Map<String, dynamic>> paymentSummary = {};
    for (var pago in pagos) {
      String metodoPago = pago['medio_pago'] ?? 'N/A';
      double monto = (pago['total'] ?? 0.0).toDouble();
      bool esEfectivo = pago['es_efectivo'] ?? false;
      bool esDigital = pago['es_digital'] ?? false;

      String key = '$metodoPago-$esEfectivo-$esDigital';

      if (paymentSummary.containsKey(key)) {
        paymentSummary[key]!['monto'] += monto;
      } else {
        paymentSummary[key] = {
          'medio_pago': metodoPago,
          'monto': monto,
          'es_efectivo': esEfectivo,
          'es_digital': esDigital,
        };
      }
    }

    return paymentSummary.values.map((payment) {
      Color color = _getPaymentColorByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );
      IconData icon = _getPaymentIconByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              '${payment['medio_pago']} \$${payment['monto'].toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Color _getPaymentColorByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return Colors.green[600]!; // Verde para efectivo
    } else if (esDigital) {
      return Colors.teal; // Verde azulado para pagos digitales
    } else {
      return Colors.blue[600]!; // Azul para transferencias/otros
    }
  }

  IconData _getPaymentIconByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return Icons.money; // Ícono de dinero en efectivo
    } else if (esDigital) {
      return Icons.smartphone; // Ícono de smartphone para pagos digitales
    } else {
      return Icons.account_balance; // Ícono de banco para transferencias
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showOrderDetails(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header del modal
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue[700]!,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Orden #${order.id}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatDate(order.fechaCreacion),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Contenido del modal
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Información del cliente
                        if (order.buyerName != null &&
                            order.buyerName!.isNotEmpty) ...[
                          _buildDetailSection(
                            'Cliente',
                            Icons.person,
                            order.buyerName!,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Total de la orden
                        _buildDetailSection(
                          'Total',
                          Icons.attach_money,
                          '\$${order.total.toStringAsFixed(0)}',
                        ),
                        const SizedBox(height: 16),

                        // Productos
                        _buildDetailSection(
                          'Productos',
                          Icons.shopping_cart,
                          '${order.distinctItemCount} productos',
                        ),
                        const SizedBox(height: 16),

                        // Desglose de pagos
                        if (order.pagos != null &&
                            (order.pagos as List).isNotEmpty) ...[
                          const Text(
                            'Desglose de Pagos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...List.generate((order.pagos as List).length, (
                            paymentIndex,
                          ) {
                            final payment = (order.pagos as List)[paymentIndex];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getPaymentColorByType(
                                  payment['es_efectivo'] ?? false,
                                  payment['es_digital'] ?? false,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getPaymentColorByType(
                                    payment['es_efectivo'] ?? false,
                                    payment['es_digital'] ?? false,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _getPaymentIconByType(
                                      payment['es_efectivo'] ?? false,
                                      payment['es_digital'] ?? false,
                                    ),
                                    size: 16,
                                    color: _getPaymentColorByType(
                                      payment['es_efectivo'] ?? false,
                                      payment['es_digital'] ?? false,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          payment['medio_pago'] ?? 'N/A',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: _getPaymentColorByType(
                                              payment['es_efectivo'] ?? false,
                                              payment['es_digital'] ?? false,
                                            ),
                                          ),
                                        ),
                                        if (payment['referencia_pago'] !=
                                            null) ...[
                                          Text(
                                            'Ref: ${payment['referencia_pago']}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _getPaymentColorByType(
                                                payment['es_efectivo'] ?? false,
                                                payment['es_digital'] ?? false,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${(payment['total'] ?? 0.0).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _getPaymentColorByType(
                                        payment['es_efectivo'] ?? false,
                                        payment['es_digital'] ?? false,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailSection(String title, IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue[700]!),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
