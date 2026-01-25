import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/price_change.dart';
import 'store_selector_service.dart';

/// Servicio para listar historial de cambios de precio
class PriceChangeService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final StoreSelectorService _storeSelectorService =
      StoreSelectorService();

  static Future<int?> _getStoreId([int? providedStoreId]) async {
    if (providedStoreId != null) return providedStoreId;

    final selectedStoreId = _storeSelectorService.getSelectedStoreId();
    if (selectedStoreId != null) return selectedStoreId;

    if (!_storeSelectorService.isInitialized) {
      await _storeSelectorService.initialize();
      return _storeSelectorService.getSelectedStoreId();
    }

    if (_storeSelectorService.userStores.isNotEmpty) {
      return _storeSelectorService.userStores.first.id;
    }

    return null;
  }

  static Future<PriceChangeResponse> listPriceChanges({
    int? storeId,
    String? busqueda,
    int? idTpv,
    String? idUsuario,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int limite = 20,
    int pagina = 1,
  }) async {
    try {
      final resolvedStoreId = await _getStoreId(storeId);
      if (resolvedStoreId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      final params = {
        'p_id_tienda': resolvedStoreId,
        'p_busqueda': busqueda,
        'p_id_tpv': idTpv,
        'p_id_usuario': idUsuario,
        'p_fecha_desde': fechaDesde?.toIso8601String().split('T')[0],
        'p_fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
        'p_limite': limite,
        'p_pagina': pagina,
      };
      print('📡 RPC fn_listar_cambios_precio params: $params');

      final response = await _supabase.rpc(
        'fn_listar_cambios_precio',
        params: params,
      );

      if (response == null || response is! List || response.isEmpty) {
        return PriceChangeResponse.empty();
      }

      final items =
          response
              .map(
                (item) => PriceChange.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();
      final totalCount =
          (response.first as Map<String, dynamic>)['total_count'] ?? 0;

      return PriceChangeResponse(
        changes: items,
        totalCount:
            totalCount is int ? totalCount : (totalCount as num).toInt(),
      );
    } catch (e) {
      print('❌ Error listando cambios de precio: $e');
      rethrow;
    }
  }
}
