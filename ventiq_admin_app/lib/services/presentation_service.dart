import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/presentation.dart';
import '../config/supabase_config.dart';

class PresentationService {
  static SupabaseClient get _supabase => Supabase.instance.client;

  // Get all presentations
  static Future<List<Presentation>> getPresentations() async {
    try {
      final response = await _supabase
          .from('app_nom_presentacion')
          .select()
          .order('denominacion');

      return (response as List)
          .map((json) => Presentation.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching presentations: $e');
      throw Exception('Error al cargar presentaciones: $e');
    }
  }

  // Get presentation by ID
  static Future<Presentation?> getPresentationById(int id) async {
    try {
      final response = await _supabase
          .from('app_nom_presentacion')
          .select()
          .eq('id', id)
          .maybeSingle();

      return response != null ? Presentation.fromJson(response) : null;
    } catch (e) {
      print('Error fetching presentation by ID: $e');
      throw Exception('Error al cargar presentación: $e');
    }
  }

  // Create new presentation
  static Future<Presentation> createPresentation(Presentation presentation) async {
    try {
      final response = await _supabase
          .from('app_nom_presentacion')
          .insert(presentation.toInsertJson())
          .select()
          .single();

      return Presentation.fromJson(response);
    } catch (e) {
      print('Error creating presentation: $e');
      throw Exception('Error al crear presentación: $e');
    }
  }

  // Update presentation
  static Future<Presentation> updatePresentation(Presentation presentation) async {
    try {
      final response = await _supabase
          .from('app_nom_presentacion')
          .update({
            'denominacion': presentation.denominacion,
            'descripcion': presentation.descripcion,
            'sku_codigo': presentation.skuCodigo,
          })
          .eq('id', presentation.id)
          .select()
          .single();

      return Presentation.fromJson(response);
    } catch (e) {
      print('Error updating presentation: $e');
      throw Exception('Error al actualizar presentación: $e');
    }
  }

  // Delete presentation
  static Future<bool> deletePresentation(int id) async {
    try {
      // Check if presentation is being used by products
      final productPresentations = await _supabase
          .from('app_dat_producto_presentacion')
          .select('id')
          .eq('id_presentacion', id)
          .limit(1);

      if (productPresentations.isNotEmpty) {
        throw Exception('No se puede eliminar la presentación porque está siendo utilizada por productos');
      }

      await _supabase
          .from('app_nom_presentacion')
          .delete()
          .eq('id', id);

      return true;
    } catch (e) {
      print('Error deleting presentation: $e');
      throw Exception('Error al eliminar presentación: $e');
    }
  }

  // Get product presentations for a specific product
  static Future<List<ProductPresentation>> getProductPresentations(int productId) async {
    try {
      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            *,
            presentacion:app_nom_presentacion(*)
          ''')
          .eq('id_producto', productId)
          .order('es_base', ascending: false);

      return (response as List)
          .map((json) => ProductPresentation.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching product presentations: $e');
      throw Exception('Error al cargar presentaciones del producto: $e');
    }
  }

  // Add presentation to product
  static Future<ProductPresentation> addPresentationToProduct({
    required int productId,
    required int presentationId,
    required double cantidad,
    bool esBase = false,
  }) async {
    try {
      // If this is going to be the base presentation, remove base flag from others
      //
      // FASE 2.0 presentaciones: el `.eq('es_base', true)` no es cosmetico. El
      // trigger trg_congelar_factor_presentacion rechaza (SQLSTATE 23001) apagar
      // es_base en una presentacion con movimientos, y Postgres lo dispara por
      // FILA AFECTADA — sin ese filtro este UPDATE toca todas las filas del
      // producto, incluidas las que ya tienen es_base = false, y explota.
      if (esBase) {
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({'es_base': false})
            .eq('id_producto', productId)
            .eq('es_base', true);
      }

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .insert({
            'id_producto': productId,
            'id_presentacion': presentationId,
            'cantidad': cantidad,
            'es_base': esBase,
          })
          .select('''
            *,
            presentacion:app_nom_presentacion(*)
          ''')
          .single();

      return ProductPresentation.fromJson(response);
    } catch (e) {
      print('Error adding presentation to product: $e');
      throw Exception('Error al agregar presentación al producto: $e');
    }
  }

  // Update product presentation
  static Future<ProductPresentation> updateProductPresentation(ProductPresentation productPresentation) async {
    try {
      // If this is going to be the base presentation, remove base flag from others
      // (ver la nota de addPresentationToProduct sobre el `.eq('es_base', true)`)
      if (productPresentation.esBase) {
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({'es_base': false})
            .eq('id_producto', productPresentation.idProducto)
            .eq('es_base', true)
            .neq('id', productPresentation.id);
      }

      // FASE 2.0: los dos campos van en UPDATE separados y cada uno filtrado por
      // "solo si cambia". Juntos, guardar sin tocar nada reescribia los mismos
      // valores, la fila contaba como afectada y el trigger la rechazaba con
      // 23001. Hacerlo asi mantiene el rechazo cuando el cambio es real.
      await _supabase
          .from('app_dat_producto_presentacion')
          .update({'cantidad': productPresentation.cantidad})
          .eq('id', productPresentation.id)
          .neq('cantidad', productPresentation.cantidad);

      await _supabase
          .from('app_dat_producto_presentacion')
          .update({'es_base': productPresentation.esBase})
          .eq('id', productPresentation.id)
          .neq('es_base', productPresentation.esBase);

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            *,
            presentacion:app_nom_presentacion(*)
          ''')
          .eq('id', productPresentation.id)
          .single();

      return ProductPresentation.fromJson(response);
    } catch (e) {
      print('Error updating product presentation: $e');
      throw Exception('Error al actualizar presentación del producto: $e');
    }
  }

  // Remove presentation from product
  static Future<bool> removeProductPresentation(int productPresentationId) async {
    try {
      await _supabase
          .from('app_dat_producto_presentacion')
          .delete()
          .eq('id', productPresentationId);

      return true;
    } catch (e) {
      print('Error removing product presentation: $e');
      throw Exception('Error al eliminar presentación del producto: $e');
    }
  }

  // Set base presentation for product
  static Future<bool> setBasePresentation(int productId, int productPresentationId) async {
    try {
      // Remove base flag from all presentations of this product
      //
      // FASE 2.0: filtrado a las que HOY son base y dejan de serlo. Sin los dos
      // filtros, el trigger trg_congelar_factor_presentacion rechaza con 23001
      // (dispara por fila afectada, no por fila que cambia de valor).
      await _supabase
          .from('app_dat_producto_presentacion')
          .update({'es_base': false})
          .eq('id_producto', productId)
          .eq('es_base', true)
          .neq('id', productPresentationId);

      // Set the selected presentation as base
      await _supabase
          .from('app_dat_producto_presentacion')
          .update({'es_base': true})
          .eq('id', productPresentationId)
          .eq('es_base', false);

      return true;
    } catch (e) {
      print('Error setting base presentation: $e');
      throw Exception('Error al establecer presentación base: $e');
    }
  }

  // Search presentations by name
  static Future<List<Presentation>> searchPresentations(String query) async {
    try {
      final response = await _supabase
          .from('app_nom_presentacion')
          .select()
          .ilike('denominacion', '%$query%')
          .order('denominacion')
          .limit(20);

      return (response as List)
          .map((json) => Presentation.fromJson(json))
          .toList();
    } catch (e) {
      print('Error searching presentations: $e');
      throw Exception('Error al buscar presentaciones: $e');
    }
  }

  // Check if SKU code is available
  static Future<bool> isSkuCodeAvailable(String skuCode, {int? excludeId}) async {
    try {
      var query = _supabase
          .from('app_nom_presentacion')
          .select('id')
          .eq('sku_codigo', skuCode);

      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }

      final response = await query.limit(1);
      return response.isEmpty;
    } catch (e) {
      print('Error checking SKU availability: $e');
      return false;
    }
  }
}
