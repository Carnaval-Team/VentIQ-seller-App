import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/catalog_store.dart';

bool _rpcAusente(Object error, String functionName) {
  final text = error.toString().toLowerCase();
  if (text.contains('42501') ||
      text.contains('insufficient_privilege') ||
      text.contains('permission denied') ||
      text.contains('acceso denegado')) {
    return false;
  }
  final fn = functionName.toLowerCase();
  return text.contains('pgrst202') ||
      text.contains('could not find the function') ||
      text.contains('schema cache') ||
      (text.contains('does not exist') && text.contains(fn));
}

class CatalogStoreService {
  static final _supabase = Supabase.instance.client;

  static Future<List<CatalogStore>> getCatalogStores() async {
    try {
      debugPrint('📦 Obteniendo tiendas catálogo (only_catalogo=true)...');

      final response = await _supabase
          .from('app_dat_tienda')
          .select(
            'id, denominacion, direccion, ubicacion, created_at, imagen_url, phone, only_catalogo, validada, mostrar_en_catalogo, nombre_pais, nombre_estado, provincia',
          )
          .eq('only_catalogo', true)
          .order('created_at', ascending: false);

      return response
          .map<CatalogStore>((json) => CatalogStore.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas catálogo: $e');
      return [];
    }
  }

  static Future<bool> updateCatalogStore(
    int storeId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final direct = Map<String, dynamic>.from(updates);
      if (direct.containsKey('validada')) {
        try {
          final respuesta = await _supabase.rpc(
            'fn_m01_validar_tienda_catalogo',
            params: {
              'p_id_tienda': storeId,
              'p_validada': direct['validada'],
            },
          );
          final mapa = respuesta is Map
              ? Map<String, dynamic>.from(respuesta)
              : null;
          if (mapa != null && mapa['success'] == true) {
            direct.remove('validada');
          }
        } catch (e) {
          if (!_rpcAusente(e, 'fn_m01_validar_tienda_catalogo')) rethrow;
        }
      }
      if (direct.isNotEmpty) {
        await _supabase.from('app_dat_tienda').update(direct).eq('id', storeId);
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando tienda catálogo: $e');
      return false;
    }
  }

  static Future<int?> getLatestActiveCatalogSubscriptionId(int storeId) async {
    try {
      final response = await _supabase
          .from('app_dat_suscripcion_catalogo')
          .select('id')
          .eq('id_tienda', storeId)
          .or('vencido.is.null,vencido.eq.false')
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final first = response.first;
        final id = first['id'];
        if (id is int) return id;
        return int.tryParse(id.toString());
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo suscripción activa: $e');
      return null;
    }
  }

  static Future<bool> expireCatalogSubscriptionById(int subscriptionId) async {
    try {
      await _supabase
          .from('app_dat_suscripcion_catalogo')
          .update({'vencido': true})
          .eq('id', subscriptionId);
      return true;
    } catch (e) {
      debugPrint('❌ Error venciendo suscripción catálogo: $e');
      return false;
    }
  }

  static Future<bool> expireActiveCatalogSubscriptions(int storeId) async {
    try {
      await _supabase
          .from('app_dat_suscripcion_catalogo')
          .update({'vencido': true})
          .eq('id_tienda', storeId)
          .or('vencido.is.null,vencido.eq.false');
      return true;
    } catch (e) {
      debugPrint('❌ Error venciendo suscripciones activas: $e');
      return false;
    }
  }

  static Future<bool> createCatalogSubscription({
    required int storeId,
    required num tiempoSuscripcionDias,
  }) async {
    try {
      await _supabase.from('app_dat_suscripcion_catalogo').insert({
        'id_tienda': storeId,
        'tiempo_suscripcion': tiempoSuscripcionDias,
        'vencido': false,
      });
      return true;
    } catch (e) {
      debugPrint('❌ Error creando suscripción catálogo: $e');
      return false;
    }
  }

  static Future<bool> renewCatalogSubscription({
    required int storeId,
    required num tiempoSuscripcionDias,
  }) async {
    try {
      final expired = await expireActiveCatalogSubscriptions(storeId);
      if (!expired) return false;

      return await createCatalogSubscription(
        storeId: storeId,
        tiempoSuscripcionDias: tiempoSuscripcionDias,
      );
    } catch (e) {
      debugPrint('❌ Error renovando suscripción catálogo: $e');
      return false;
    }
  }
}
