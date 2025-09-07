import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transfer_order.dart';
import '../services/user_preferences_service.dart';

class TransferService {
  static final _supabase = Supabase.instance.client;

  /// Crear una nueva preorden de transferencia con las 3 operaciones
  static Future<TransferOrder> createTransferPreorder({
    required String warehouseOriginId,
    required String warehouseOriginName,
    required String zoneOriginId,
    required String zoneOriginName,
    required String warehouseDestinationId,
    required String warehouseDestinationName,
    required String zoneDestinationId,
    required String zoneDestinationName,
    required List<TransferOrderItem> items,
    String? observations,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final userUuid = await userPrefs.getUserId();
      final transferId = 'TO-${DateTime.now().millisecondsSinceEpoch}';

      // Calcular total de items
      double totalItems = items.fold(0, (sum, item) => sum + item.quantity);

      // Crear la orden de transferencia
      final transferOrder = TransferOrder(
        id: transferId,
        warehouseOriginId: warehouseOriginId,
        warehouseOriginName: warehouseOriginName,
        zoneOriginId: zoneOriginId,
        zoneOriginName: zoneOriginName,
        warehouseDestinationId: warehouseDestinationId,
        warehouseDestinationName: warehouseDestinationName,
        zoneDestinationId: zoneDestinationId,
        zoneDestinationName: zoneDestinationName,
        items: items,
        status: TransferOrderStatus.pending,
        createdAt: DateTime.now(),
        createdByUserId: userUuid.toString(),
        observations: observations,
        totalItems: totalItems,
        operations: TransferOrder.generateOperations(
          transferId,
          TransferOrder(
            id: transferId,
            warehouseOriginId: warehouseOriginId,
            warehouseOriginName: warehouseOriginName,
            zoneOriginId: zoneOriginId,
            zoneOriginName: zoneOriginName,
            warehouseDestinationId: warehouseDestinationId,
            warehouseDestinationName: warehouseDestinationName,
            zoneDestinationId: zoneDestinationId,
            zoneDestinationName: zoneDestinationName,
            items: items,
            status: TransferOrderStatus.pending,
            createdAt: DateTime.now(),
            createdByUserId: userUuid.toString(),
            totalItems: totalItems,
            operations: [],
          ),
        ),
      );

      // TODO: Guardar en Supabase usando RPC
      // await _supabase.rpc('fn_crear_preorden_transferencia', {
      //   'transfer_order': transferOrder.toJson(),
      // });

      print('TransferService: Preorden creada - ${transferOrder.id}');
      print(
        'TransferService: ${transferOrder.operations.length} operaciones generadas',
      );

      return transferOrder;
    } catch (e) {
      print('TransferService Error: $e');
      throw Exception('Error al crear preorden de transferencia: $e');
    }
  }

  /// Listar preórdenes de transferencia pendientes
  static Future<List<TransferOrder>> listPendingTransferOrders({
    String? warehouseId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // TODO: Implementar consulta a Supabase
      // final response = await _supabase.rpc('fn_listar_preordenes_transferencia', {
      //   'warehouse_id_param': warehouseId,
      //   'limit_param': limit,
      //   'offset_param': offset,
      // });

      // Mock data para desarrollo
      return _getMockTransferOrders();
    } catch (e) {
      print('TransferService Error: $e');
      return [];
    }
  }

  /// Confirmar una preorden de transferencia
  static Future<bool> confirmTransferOrder(String transferOrderId) async {
    try {
      // TODO: Implementar confirmación en Supabase
      // await _supabase.rpc('fn_confirmar_preorden_transferencia', {
      //   'transfer_order_id': transferOrderId,
      //   'confirmed_by_user_id': await UserPreferencesService.getUserUuid(),
      // });

      print('TransferService: Preorden confirmada - $transferOrderId');
      return true;
    } catch (e) {
      print('TransferService Error: $e');
      return false;
    }
  }

  /// Ejecutar una operación específica de transferencia
  static Future<bool> executeTransferOperation(String operationId) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId().toString() ?? '';

      // TODO: Implementar ejecución en Supabase
      // await _supabase.rpc('fn_ejecutar_operacion_transferencia', {
      //   'operation_id': operationId,
      //   'executed_by_user_id': userId,
      // });

      print('TransferService: Operación ejecutada - $operationId');
      return true;
    } catch (e) {
      print('TransferService Error: $e');
      return false;
    }
  }

  /// Cancelar una preorden de transferencia
  static Future<bool> cancelTransferOrder(
    String transferOrderId,
    String reason,
  ) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId().toString() ?? '';

      // TODO: Implementar cancelación en Supabase
      // await _supabase.rpc('fn_cancelar_preorden_transferencia', {
      //   'transfer_order_id': transferOrderId,
      //   'cancelled_by_user_id': userId,
      //   'cancellation_reason': reason,
      // });

      print('TransferService: Preorden cancelada - $transferOrderId');
      return true;
    } catch (e) {
      print('TransferService Error: $e');
      return false;
    }
  }

  /// Obtener detalles de una preorden específica
  static Future<TransferOrder?> getTransferOrderDetails(
    String transferOrderId,
  ) async {
    try {
      // TODO: Implementar consulta detallada en Supabase
      // final response = await _supabase.rpc('fn_obtener_detalle_preorden_transferencia', {
      //   'transfer_order_id': transferOrderId,
      // });

      // Mock data para desarrollo
      final mockOrders = _getMockTransferOrders();
      return mockOrders.firstWhere(
        (order) => order.id == transferOrderId,
        orElse: () => mockOrders.first,
      );
    } catch (e) {
      print('TransferService Error: $e');
      return null;
    }
  }

  /// Obtener productos disponibles en una zona con variantes y presentaciones
  static Future<List<ProductVariantPresentation>> getZoneProductsWithVariants(
    String warehouseId,
    String zoneId,
  ) async {
    try {
      // TODO: Implementar consulta a Supabase
      // final response = await _supabase.rpc('fn_listar_productos_zona_variantes', {
      //   'warehouse_id_param': warehouseId,
      //   'zone_id_param': zoneId,
      // });

      // Mock data para desarrollo
      return _getMockProductVariants();
    } catch (e) {
      print('TransferService Error: $e');
      return [];
    }
  }

  /// Mock data para desarrollo
  static List<TransferOrder> _getMockTransferOrders() {
    return [
      TransferOrder(
        id: 'TO-1234567890',
        warehouseOriginId: '1',
        warehouseOriginName: 'Almacén Central',
        zoneOriginId: '1-1',
        zoneOriginName: 'Recepción Central',
        warehouseDestinationId: '2',
        warehouseDestinationName: 'Almacén Norte',
        zoneDestinationId: '2-1',
        zoneDestinationName: 'Almacenamiento Norte',
        items: [
          TransferOrderItem(
            id: '1',
            productId: '101',
            productName: 'Producto A',
            productSku: 'SKU-A-001',
            quantity: 10,
            availableStock: 50,
          ),
          TransferOrderItem(
            id: '2',
            productId: '102',
            productName: 'Producto B',
            productSku: 'SKU-B-001',
            variantName: 'Talla M',
            quantity: 5,
            availableStock: 25,
          ),
        ],
        status: TransferOrderStatus.pending,
        createdAt: DateTime.now().subtract(Duration(hours: 2)),
        createdByUserId: 'user123',
        totalItems: 15,
        operations: [
          TransferOperation(
            id: 'TO-1234567890_global',
            transferOrderId: 'TO-1234567890',
            type: TransferOperationType.global,
            description:
                'Transferencia global de Recepción Central a Almacenamiento Norte',
            warehouseId: '1',
            zoneId: '1-1',
            status: TransferOperationStatus.pending,
            createdAt: DateTime.now().subtract(Duration(hours: 2)),
          ),
          TransferOperation(
            id: 'TO-1234567890_extraction',
            transferOrderId: 'TO-1234567890',
            type: TransferOperationType.extraction,
            description: 'Extracción de productos desde Recepción Central',
            warehouseId: '1',
            zoneId: '1-1',
            status: TransferOperationStatus.pending,
            createdAt: DateTime.now().subtract(Duration(hours: 2)),
          ),
          TransferOperation(
            id: 'TO-1234567890_entry',
            transferOrderId: 'TO-1234567890',
            type: TransferOperationType.entry,
            description: 'Entrada de productos en Almacenamiento Norte',
            warehouseId: '2',
            zoneId: '2-1',
            status: TransferOperationStatus.pending,
            createdAt: DateTime.now().subtract(Duration(hours: 2)),
          ),
        ],
      ),
    ];
  }

  static List<ProductVariantPresentation> _getMockProductVariants() {
    return [
      ProductVariantPresentation(
        productId: '101',
        productName: 'Producto A',
        productSku: 'SKU-A-001',
        availableStock: 50,
      ),
      ProductVariantPresentation(
        productId: '102',
        productName: 'Producto B',
        productSku: 'SKU-B-001',
        variantId: '102-M',
        variantName: 'Talla M',
        availableStock: 25,
      ),
      ProductVariantPresentation(
        productId: '102',
        productName: 'Producto B',
        productSku: 'SKU-B-002',
        variantId: '102-L',
        variantName: 'Talla L',
        availableStock: 30,
      ),
      ProductVariantPresentation(
        productId: '103',
        productName: 'Producto C',
        productSku: 'SKU-C-001',
        presentationId: '103-500ml',
        presentationName: '500ml',
        availableStock: 100,
      ),
      ProductVariantPresentation(
        productId: '103',
        productName: 'Producto C',
        productSku: 'SKU-C-002',
        presentationId: '103-1L',
        presentationName: '1 Litro',
        availableStock: 75,
      ),
    ];
  }
}
