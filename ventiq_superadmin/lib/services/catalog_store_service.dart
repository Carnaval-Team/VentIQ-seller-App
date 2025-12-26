import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/catalog_store.dart';

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
      await _supabase.from('app_dat_tienda').update(updates).eq('id', storeId);
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando tienda catálogo: $e');
      return false;
    }
  }
}
