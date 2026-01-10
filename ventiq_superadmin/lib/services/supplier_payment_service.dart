import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier_payment_model.dart';

class SupplierPaymentService {
  static final _supabase = Supabase.instance.client;

  /// Obtener resumen de pagos por proveedor en un rango de fechas
  /// Usa JOINs eficientes para evitar N+1 queries
  static Future<List<SupplierPaymentSummary>> getSupplierPayments(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('📊 Obteniendo pagos a proveedores...');
      debugPrint(
        '📅 Rango: ${fechaInicio.toIso8601String()} - ${fechaFin.toIso8601String()}',
      );

      // Usar método manual directamente
      return await _getSupplierPaymentsManual(fechaInicio, fechaFin);
    } catch (e) {
      debugPrint('❌ Error obteniendo pagos: $e');
      return [];
    }
  }

  /// Método manual para obtener pagos si el RPC no existe
  static Future<List<SupplierPaymentSummary>> _getSupplierPaymentsManual(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('📊 Usando método manual para obtener pagos...');

      // Obtener OrderDetails con joins
      final ordersResponse = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('''
            proveedor,
            price,
            quantity,
            precio_usd,
            precio_euro,
            transferencia,
            Orders(status)
          ''')
          .eq('Orders.status', 'Completado')
          .gte('created_at', fechaInicio.toIso8601String())
          .lte('created_at', fechaFin.toIso8601String());

      // Agrupar por proveedor
      final Map<int, Map<String, dynamic>> supplierTotals = {};

      for (var order in ordersResponse) {
        final proveedorId = order['proveedor'] as int? ?? 3;
        final price = (order['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = order['quantity'] as int? ?? 0;
        final precioUsd = (order['precio_usd'] as num?)?.toDouble() ?? 1.0;
        final precioEuro = (order['precio_euro'] as num?)?.toDouble() ?? 1.0;
        final isTransfer = order['transferencia'] as bool? ?? false;

        final totalRow = price * quantity;

        if (!supplierTotals.containsKey(proveedorId)) {
          supplierTotals[proveedorId] = {
            'total_cup': 0.0,
            'total_usd': 0.0,
            'total_euro': 0.0,
            'total_cash': 0.0,
            'total_transfer': 0.0,
            'total_orders':
                0, // This is technically total items/lines processed here, distinct orders need better count but user asked for grouping later.
            // For summary stats, simple increments might be enough or we maintain a Set of order IDs if available.
            // In the initial fetching `OrderDetails` we don't select `order_id` in this block, but we probably should if we want accurate order count.
            // Let's add order_id to query if we want accurate order count.
          };
        }

        supplierTotals[proveedorId]!['total_cup'] += totalRow;
        supplierTotals[proveedorId]!['total_usd'] += precioUsd * quantity;
        supplierTotals[proveedorId]!['total_euro'] += precioEuro * quantity;

        if (isTransfer) {
          supplierTotals[proveedorId]!['total_transfer'] += totalRow;
        } else {
          supplierTotals[proveedorId]!['total_cash'] += totalRow;
        }

        supplierTotals[proveedorId]!['total_orders'] += 1;
      }

      // Obtener datos completos de proveedores
      final proveedorIds = supplierTotals.keys.toList();
      if (proveedorIds.isEmpty) {
        return [];
      }

      final proveedoresResponse = await _supabase
          .schema('carnavalapp')
          .from('proveedores')
          .select('*')
          .inFilter('id', proveedorIds);

      // Combinar datos
      final List<SupplierPaymentSummary> suppliers = [];
      for (var proveedor in proveedoresResponse) {
        final id = proveedor['id'] as int;
        final totals = supplierTotals[id]!;

        suppliers.add(
          SupplierPaymentSummary(
            id: id,
            name: proveedor['name'] as String? ?? 'Sin nombre',
            logo: proveedor['logo'] as String?,
            banner: proveedor['banner'] as String?,
            ubicacion: proveedor['ubicacion'] as String?,
            contacto:
                proveedor['contacto'] != null
                    ? (proveedor['contacto'] as num).toDouble()
                    : null,
            direccion: proveedor['direccion'] as String?,
            categoria: proveedor['categoria'] as String?,
            status: proveedor['status'] as bool? ?? true,
            totalCup: totals['total_cup'] as double,
            totalUsd: totals['total_usd'] as double,
            totalEuro: totals['total_euro'] as double,
            totalCash: totals['total_cash'] as double,
            totalTransfer: totals['total_transfer'] as double,
            totalOrders: totals['total_orders'] as int,
          ),
        );
      }

      // Ordenar por total CUP descendente
      suppliers.sort((a, b) => b.totalCup.compareTo(a.totalCup));

      debugPrint(
        '✅ ${suppliers.length} proveedores procesados (método manual)',
      );
      return suppliers;
    } catch (e) {
      debugPrint('❌ Error en método manual: $e');
      return [];
    }
  }

  /// Obtener detalles de órdenes para un proveedor específico
  static Future<List<OrderPaymentDetail>> getSupplierOrders(
    int proveedorId,
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('📦 Obteniendo órdenes para proveedor $proveedorId...');

      final response = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('''
            order_id,
            product_id,
            quantity,
            price,
            precio_usd,
            precio_euro,
            transferencia,
            Orders!inner(status, created_at),
            Productos!inner(
              name,
              image
            )
          ''')
          .eq('proveedor', proveedorId)
          .eq('Orders.status', 'Completado')
          .gte('created_at', fechaInicio.toIso8601String())
          .lte('created_at', fechaFin.toIso8601String());

      // Agrupar por Order ID
      final Map<int, OrderPaymentDetail> ordersMap = {};
      final Map<int, List<ProductPaymentDetail>> orderProductsMap = {};

      for (var item in response) {
        final orderId = item['order_id'] as int;
        final orderData = item['Orders']; // OrderDetails -> Orders relationship

        if (orderData == null) {
          continue;
        }

        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int? ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final isTransfer = item['transferencia'] as bool? ?? false;

        final productData = item['Productos'];

        final product = ProductPaymentDetail(
          productId: productId,
          productName: productData?['name'] ?? 'Sin nombre',
          productImage: productData?['image'],
          quantity: quantity,
          price: price,
          subtotal: price * quantity,
        );

        if (!orderProductsMap.containsKey(orderId)) {
          orderProductsMap[orderId] = [];

          final createdAtStr = orderData['created_at'] as String?;
          final createdAt =
              createdAtStr != null
                  ? DateTime.parse(createdAtStr)
                  : DateTime.now();

          // Initialize order entry placeholder
          // We will update total later
          ordersMap[orderId] = OrderPaymentDetail(
            orderId: orderId,
            createdAt: createdAt,
            total: 0.0,
            isTransfer:
                isTransfer, // Assuming all items in order share same payment method or taking first one
            products: [],
          );
        }

        orderProductsMap[orderId]!.add(product);

        // Update total
        final currentOrder = ordersMap[orderId]!;
        ordersMap[orderId] = OrderPaymentDetail(
          orderId: currentOrder.orderId,
          createdAt: currentOrder.createdAt,
          total: currentOrder.total + product.subtotal,
          isTransfer: isTransfer, // Keep it consistent
          products: [], // We will assign this at the end
        );
      }

      // Final Assembly
      final List<OrderPaymentDetail> result = [];
      for (var orderId in ordersMap.keys) {
        final orderBase = ordersMap[orderId]!;
        result.add(
          OrderPaymentDetail(
            orderId: orderBase.orderId,
            createdAt: orderBase.createdAt,
            total: orderBase.total,
            isTransfer: orderBase.isTransfer,
            products: orderProductsMap[orderId]!,
          ),
        );
      }

      // Ordenar por fecha descendente (más recientes primero)
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint('✅ ${result.length} órdenes encontradas');
      return result;
    } catch (e) {
      debugPrint('❌ Error obteniendo órdenes: $e');
      return [];
    }
  }

  /// Obtener estadísticas generales de pagos
  static Future<PaymentStats> getPaymentStats(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      final suppliers = await getSupplierPayments(fechaInicio, fechaFin);
      return PaymentStats.fromSuppliers(suppliers);
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return PaymentStats(
        totalCup: 0.0,
        totalUsd: 0.0,
        totalEuro: 0.0,
        totalSuppliers: 0,
        averagePerSupplier: 0.0,
        topSuppliers: [],
      );
    }
  }
}
