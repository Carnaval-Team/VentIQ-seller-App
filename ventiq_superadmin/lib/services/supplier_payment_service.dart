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
            precio_euro
          ''')
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

        if (!supplierTotals.containsKey(proveedorId)) {
          supplierTotals[proveedorId] = {
            'total_cup': 0.0,
            'total_usd': 0.0,
            'total_euro': 0.0,
            'total_orders': 0,
          };
        }

        supplierTotals[proveedorId]!['total_cup'] += price * quantity;
        supplierTotals[proveedorId]!['total_usd'] += precioUsd * quantity;
        supplierTotals[proveedorId]!['total_euro'] += precioEuro * quantity;
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

  /// Obtener detalles de productos para un proveedor específico
  /// Solo se llama cuando el usuario expande el acordeón
  static Future<List<ProductPaymentDetail>> getSupplierProductDetails(
    int proveedorId,
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint(
        '📦 Obteniendo detalles de productos para proveedor $proveedorId...',
      );

      final response = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('''
            product_id,
            quantity,
            price,
            precio_usd,
            precio_euro,
            Productos!inner(
              name,
              image
            )
          ''')
          .eq('proveedor', proveedorId)
          .gte('created_at', fechaInicio.toIso8601String())
          .lte('created_at', fechaFin.toIso8601String());

      // Agrupar por producto
      final Map<int, Map<String, dynamic>> productTotals = {};

      for (var order in response) {
        final productId = order['product_id'] as int;
        final quantity = order['quantity'] as int? ?? 0;
        final price = (order['price'] as num?)?.toDouble() ?? 0.0;
        final precioUsd = (order['precio_usd'] as num?)?.toDouble() ?? 1.0;
        final precioEuro = (order['precio_euro'] as num?)?.toDouble() ?? 1.0;
        final productData = order['Productos'];

        if (!productTotals.containsKey(productId)) {
          productTotals[productId] = {
            'product_id': productId,
            'product_name': productData?['name'] ?? 'Sin nombre',
            'product_image': productData?['image'],
            'total_quantity': 0,
            'total_cup': 0.0,
            'total_usd': 0.0,
            'total_euro': 0.0,
          };
        }

        productTotals[productId]!['total_quantity'] += quantity;
        productTotals[productId]!['total_cup'] += price * quantity;
        productTotals[productId]!['total_usd'] += precioUsd * quantity;
        productTotals[productId]!['total_euro'] += precioEuro * quantity;
      }

      final products =
          productTotals.values
              .map((json) => ProductPaymentDetail.fromJson(json))
              .toList();

      // Ordenar por total CUP descendente
      products.sort((a, b) => b.totalCup.compareTo(a.totalCup));

      debugPrint('✅ ${products.length} productos encontrados');
      return products;
    } catch (e) {
      debugPrint('❌ Error obteniendo detalles de productos: $e');
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
