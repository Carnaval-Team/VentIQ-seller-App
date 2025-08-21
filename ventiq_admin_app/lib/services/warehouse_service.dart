import '../models/warehouse.dart';
import '../models/store.dart';
import 'mock_data_service.dart';

// TODO: Swap to real HTTP client once API is available (e.g., Supabase functions or REST backend)
class WarehouseService {
  // Filters: by storeId and search by name
  Future<List<Warehouse>> listWarehouses({String? storeId, String? search}) async {
    // Mock implementation
    final all = MockDataService.getMockWarehouses();
    final filtered = all.where((w) {
      final byStore = storeId == null || storeId.isEmpty || storeId == 'all';
      final bySearch = search == null || search.trim().isEmpty
          ? true
          : w.name.toLowerCase().contains(search.toLowerCase());
      return byStore && bySearch;
    }).toList();
    await Future.delayed(const Duration(milliseconds: 250));
    return filtered;
  }

  Future<Warehouse> getWarehouseDetail(String id) async {
    final all = MockDataService.getMockWarehouses();
    final w = all.firstWhere((e) => e.id == id);
    await Future.delayed(const Duration(milliseconds: 200));
    return w;
  }

  // Stubbed methods to match API design
  Future<Warehouse> createWarehouse(Warehouse data) async {
    // POST /api/almacenes
    return data;
  }

  Future<void> updateWarehouseBasic(String id, Map<String, dynamic> payload) async {
    // PUT /api/almacenes/{id}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> deleteWarehouse(String id) async {
    // DELETE /api/almacenes/{id}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> addLayout(String warehouseId, Map<String, dynamic> layout) async {
    // POST /api/almacenes/{id}/layouts
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> updateLayout(String warehouseId, String layoutId, Map<String, dynamic> layout) async {
    // PUT /api/almacenes/{id}/layouts/{layoutId}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> deleteLayout(String warehouseId, String layoutId) async {
    // DELETE /api/almacenes/{id}/layouts/{layoutId}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<String> duplicateLayout(String warehouseId, String layoutId) async {
    // POST /api/almacenes/{id}/layouts/{layoutId}/duplicate
    await Future.delayed(const Duration(milliseconds: 150));
    return 'new-layout-id';
  }

  Future<void> bulkUpdateABC(String warehouseId, Map<String, String> layoutToAbc) async {
    // POST /api/almacenes/{id}/layouts/abc: { layoutId: 'A'|'B'|'C' }
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> updateLayoutConditions(String warehouseId, String layoutId, List<String> conditionCodes) async {
    // PUT /api/almacenes/{id}/layouts/{layoutId}/condiciones
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> updateStockLimits(String warehouseId, List<Map<String, dynamic>> limits) async {
    // POST /api/almacenes/{id}/limites-stock
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<List<Store>> listStores() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return MockDataService.getMockStores();
  }
}
