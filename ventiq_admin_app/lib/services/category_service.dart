import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart';
import 'user_preferences_service.dart';

class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Obtiene todas las categorías de una tienda.
  ///
  /// El RPC `get_categorias_by_tienda_complete` (v1) devuelve el nomenclador
  /// global y el vínculo con la tienda, pero NO la configuración del Home.
  /// `especial` y `orden_home` viven en `app_dat_categoria_tienda`, así que se
  /// leen aparte (una sola query) y se mezclan por `id_categoria`.
  ///
  /// ⚠️ NO se usa `get_categorias_by_tienda_complete_v2` (aunque existe en la
  /// BD) porque hoy falla con `P0001: structure of query does not match
  /// function result type`: su `coalesce(ct.orden_home, 0)` devuelve `integer`
  /// y el `RETURNS TABLE` declara `orden_home smallint`. Requiere un
  /// `::smallint` en la función (DDL pendiente, NO aplicada desde el admin).
  ///
  /// También se rellena [Category.productCount] con el número de productos
  /// **vendibles** de la categoría (ver [getVendibleProductCountsByCategory]).
  Future<List<Category>> getCategoriesByStore() async {
    try {
      print('🏪 Iniciando carga de categorías desde Supabase...');

      // Obtener ID de tienda desde preferencias
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en preferencias');
      }

      print('🏪 ID Tienda: $idTienda');

      // Llamar al RPC get_categorias_by_tienda_complete (v1)
      final response = await _supabase.rpc(
        'get_categorias_by_tienda_complete',
        params: {'p_id_tienda': idTienda},
      );

      print('📦 Respuesta RPC recibida: ${response?.length ?? 0} categorías');

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      // Config por tienda del Home (especial / orden_home) y conteo de
      // productos vendibles. Si cualquiera falla, se sigue sin ese dato: no
      // debe tumbar la carga de categorías.
      final configTienda = await _getConfigCategoriaTienda(idTienda);
      final conteoProductos = await getVendibleProductCountsByCategory(
        idTienda: idTienda,
      );

      // Convertir respuesta a lista de categorías
      final List<Category> categories = [];
      for (final item in response) {
        try {
          print(
            '📝 Procesando categoría: ${item['denominacion']} (ID: ${item['id']})',
          );

          // Generar color basado en el nombre para consistencia visual
          final color = _generateColorFromName(item['denominacion'] ?? '');

          final categoriaId = (item['id'] as num?)?.toInt();
          final config =
              categoriaId != null ? configTienda[categoriaId] : null;

          final category = Category.fromJson({
            ...item,
            'color': color,
            'icon': _getIconFromName(item['denominacion'] ?? ''),
            'especial': config?['especial'] ?? false,
            'orden_home': config?['orden_home'] ?? 0,
            'productCount':
                categoriaId != null ? (conteoProductos[categoriaId] ?? 0) : 0,
          });

          categories.add(category);
        } catch (e) {
          print('❌ Error procesando categoría ${item['id']}: $e');
        }
      }

      // Mismo criterio de orden que el Home del TPV: especiales primero,
      // por orden_home, y luego por denominación.
      categories.sort((a, b) {
        if (a.especial != b.especial) return a.especial ? -1 : 1;
        final porOrden = a.ordenHome.compareTo(b.ordenHome);
        return porOrden != 0 ? porOrden : a.name.compareTo(b.name);
      });

      print('✅ Categorías procesadas exitosamente: ${categories.length}');
      return categories;
    } catch (e) {
      print('❌ Error obteniendo categorías: $e');

      // Fallback a datos mock en caso de error
      print('🔄 Usando datos mock como fallback');
      return _getMockCategories();
    }
  }

  /// Lee la configuración del Home de la tienda en `app_dat_categoria_tienda`.
  ///
  /// Devuelve `{id_categoria: {especial, orden_home}}`. No lanza: si la lectura
  /// falla se devuelve un mapa vacío y las categorías quedan con los valores
  /// por defecto (`especial = false`, `orden_home = 0`).
  Future<Map<int, Map<String, dynamic>>> _getConfigCategoriaTienda(
    int idTienda,
  ) async {
    try {
      final response = await _supabase
          .from('app_dat_categoria_tienda')
          .select('id_categoria, especial, orden_home')
          .eq('id_tienda', idTienda);

      final config = <int, Map<String, dynamic>>{};
      for (final row in response) {
        final map = row as Map<String, dynamic>;
        final idCategoria = (map['id_categoria'] as num?)?.toInt();
        if (idCategoria != null) {
          config[idCategoria] = map;
        }
      }
      return config;
    } catch (e) {
      print('⚠️ No se pudo leer app_dat_categoria_tienda: $e');
      return {};
    }
  }

  /// Cuenta los productos **vendibles** de cada categoría de la tienda.
  ///
  /// Una sola consulta paginada sobre `app_dat_producto`
  /// (`id_tienda = tienda`, `es_vendible = true`) trayendo solo
  /// `id_categoria`, que se agrega en el cliente. No hay RPC/consulta
  /// agregada reutilizable para el admin, así que es PostgREST puro: **no
  /// requiere SQL nuevo** en la base.
  ///
  /// Nota: el Home (`get_home_catalogo_tpv`) cuenta productos a través de las
  /// subcategorías de la categoría; aquí se cuenta por `id_categoria` directo.
  /// Para la tienda 223 verificada ambos números coinciden. La diferencia
  /// conocida son productos vendibles sin subcategoría asignada (144 de 9081
  /// en toda la base): el contador del admin puede ser mayor que el del Home.
  Future<Map<int, int>> getVendibleProductCountsByCategory({int? idTienda}) async {
    final conteo = <int, int>{};
    try {
      final tiendaId = idTienda ?? await _userPrefs.getIdTienda();
      if (tiendaId == null) return conteo;

      const pageSize = 1000;
      var offset = 0;

      while (true) {
        final response = await _supabase
            .from('app_dat_producto')
            .select('id_categoria')
            .eq('id_tienda', tiendaId)
            .eq('es_vendible', true)
            .order('id')
            .range(offset, offset + pageSize - 1);

        for (final row in response) {
          final map = row as Map<String, dynamic>;
          final idCategoria = (map['id_categoria'] as num?)?.toInt();
          if (idCategoria != null) {
            conteo[idCategoria] = (conteo[idCategoria] ?? 0) + 1;
          }
        }

        if (response.length < pageSize) break;
        offset += pageSize;
        if (offset >= 100000) break; // guarda de seguridad
      }

      print('✅ Conteo de productos vendibles: ${conteo.length} categorías');
    } catch (e) {
      print('⚠️ No se pudo contar productos vendibles: $e');
    }
    return conteo;
  }

  /// Genera un color consistente basado en el nombre de la categoría
  String _generateColorFromName(String name) {
    final colors = [
      '#4A90E2', // Azul VentIQ
      '#10B981', // Verde
      '#F59E0B', // Amarillo
      '#EF4444', // Rojo
      '#8B5CF6', // Púrpura
      '#06B6D4', // Cyan
      '#F97316', // Naranja
      '#84CC16', // Lima
      '#EC4899', // Rosa
      '#6B7280', // Gris
    ];

    final hash = name.hashCode.abs();
    return colors[hash % colors.length];
  }

  /// Obtiene un ícono basado en el nombre de la categoría
  String _getIconFromName(String name) {
    final lowerName = name.toLowerCase();

    if (lowerName.contains('alimento') || lowerName.contains('comida')) {
      return 'restaurant';
    } else if (lowerName.contains('bebida')) {
      return 'local_drink';
    } else if (lowerName.contains('electr')) {
      return 'devices';
    } else if (lowerName.contains('hogar') || lowerName.contains('casa')) {
      return 'home';
    } else if (lowerName.contains('limpieza')) {
      return 'cleaning_services';
    } else if (lowerName.contains('cuidado') ||
        lowerName.contains('personal')) {
      return 'face';
    } else if (lowerName.contains('juguete')) {
      return 'toys';
    } else if (lowerName.contains('textil') || lowerName.contains('ropa')) {
      return 'checkroom';
    } else if (lowerName.contains('ferretería') ||
        lowerName.contains('herramienta')) {
      return 'build';
    } else if (lowerName.contains('jardín')) {
      return 'local_florist';
    } else {
      return 'category';
    }
  }

  /// Datos mock como fallback
  List<Category> _getMockCategories() {
    return [
      Category(
        id: 1,
        name: 'Alimentos',
        description: 'Productos de alimentación y bebidas no alcohólicas',
        color: '#4A90E2',
        icon: 'restaurant',
        skuCodigo: 'ALIM',
        createdAt: DateTime.now(),
        productCount: 45,
        visibleVendedor: true,
      ),
      Category(
        id: 2,
        name: 'Bebidas',
        description: 'Bebidas y refrescos no alcohólicos',
        color: '#10B981',
        icon: 'local_drink',
        skuCodigo: 'BEB',
        createdAt: DateTime.now(),
        productCount: 23,
        visibleVendedor: true,
      ),
      Category(
        id: 3,
        name: 'Electrónica',
        description: 'Dispositivos electrónicos y accesorios tecnológicos',
        color: '#F59E0B',
        icon: 'devices',
        skuCodigo: 'ELEC',
        createdAt: DateTime.now(),
        productCount: 18,
        visibleVendedor: false, // Ejemplo de categoría oculta
      ),
    ];
  }

  /// Buscar categorías por texto
  Future<List<Category>> searchCategories(String query) async {
    final allCategories = await getCategoriesByStore();

    if (query.isEmpty) return allCategories;

    return allCategories.where((category) {
      return category.name.toLowerCase().contains(query.toLowerCase()) ||
          category.description.toLowerCase().contains(query.toLowerCase()) ||
          category.skuCodigo.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  /// Obtener categoría por ID
  Future<Category?> getCategoryById(int id) async {
    final categories = await getCategoriesByStore();
    try {
      return categories.firstWhere((category) => category.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Refrescar caché de categorías (para pull-to-refresh)
  Future<List<Category>> refreshCategories() async {
    print('🔄 Refrescando categorías...');
    return await getCategoriesByStore();
  }

  /// Sube una imagen al bucket de Supabase Storage
  Future<String?> _uploadCategoryImage(
    Uint8List imageBytes,
    String fileName,
  ) async {
    try {
      print('📤 Subiendo imagen: $fileName');

      // Generar nombre único para evitar conflictos
      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Subir imagen al bucket 'images_back' con opciones específicas
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true, // Permite sobrescribir si existe
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir imagen');
      }

      // Obtener URL pública de la imagen
      final imageUrl = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);

      print('✅ Imagen subida exitosamente: $imageUrl');
      return imageUrl;
    } catch (e) {
      print('❌ Error al subir imagen: $e');

      // Si falla con RLS, intentar crear la categoría sin imagen
      if (e.toString().contains('row-level security policy')) {
        print('⚠️ Error de permisos RLS - continuando sin imagen');
        return null;
      }

      return null;
    }
  }

  /// Crea una nueva categoría en la base de datos
  Future<bool> createCategory({
    required String denominacion,
    required String descripcion,
    required String skuCodigo,
    Uint8List? imageBytes,
    String? imageFileName,
    bool visibleVendedor = true,
    bool especial = false,
  }) async {
    final categoryId = await createCategoryWithId(
      denominacion: denominacion,
      descripcion: descripcion,
      skuCodigo: skuCodigo,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      visibleVendedor: visibleVendedor,
      especial: especial,
    );

    return categoryId != null;
  }

  /// Crea una nueva categoría y retorna su ID
  Future<int?> createCategoryWithId({
    required String denominacion,
    required String descripcion,
    required String skuCodigo,
    Uint8List? imageBytes,
    String? imageFileName,
    bool visibleVendedor = true,
    bool especial = false,
  }) async {
    try {
      print('🆕 Creando nueva categoría: $denominacion');

      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      String? imageUrl;

      if (imageBytes != null && imageFileName != null) {
        imageUrl = await _uploadCategoryImage(imageBytes, imageFileName);
        if (imageUrl == null) {
          print('⚠️ Continuando sin imagen debido a restricciones de permisos');
        }
      }

      final categoryResponse =
          await _supabase
              .from('app_dat_categoria')
              .insert({
                'denominacion': denominacion,
                'descripcion': descripcion,
                'sku_codigo': skuCodigo,
                'image': imageUrl,
                'visible_vendedor': visibleVendedor,
              })
              .select()
              .single();

      final categoryId = categoryResponse['id'] as int?;
      if (categoryId == null) {
        throw Exception('No se recibió el ID de la categoría');
      }

      print('✅ Categoría creada con ID: $categoryId');

      // Si nace como especial, que arranque al final del grupo del Home.
      int? ordenInicial;
      if (especial) {
        try {
          ordenInicial = await _siguienteOrdenHome(idTienda);
        } catch (e) {
          print('⚠️ No se pudo calcular el orden inicial del Home: $e');
        }
      }

      await _supabase.from('app_dat_categoria_tienda').insert({
        'id_categoria': categoryId,
        'id_tienda': idTienda,
        'especial': especial,
        if (ordenInicial != null) 'orden_home': ordenInicial,
      });

      print('✅ Relación categoría-tienda creada exitosamente');
      return categoryId;
    } catch (e) {
      print('❌ Error al crear categoría: $e');
      return null;
    }
  }

  /// Actualiza una categoría existente.
  ///
  /// `visibleVendedor`, `especial` y `ordenHome` son opcionales: solo se
  /// escriben si llegan. Los dos últimos viven en `app_dat_categoria_tienda`
  /// (config por tienda), no en el nomenclador global `app_dat_categoria`.
  Future<bool> updateCategory({
    required int categoryId,
    required String denominacion,
    required String descripcion,
    required String skuCodigo,
    Uint8List? imageBytes,
    String? imageFileName,
    bool? visibleVendedor,
    bool? especial,
    int? ordenHome,
  }) async {
    try {
      print('✏️ Actualizando categoría ID: $categoryId');

      String? imageUrl;

      // Subir nueva imagen si se proporciona
      if (imageBytes != null && imageFileName != null) {
        imageUrl = await _uploadCategoryImage(imageBytes, imageFileName);
        if (imageUrl == null) {
          throw Exception('Error al subir la nueva imagen');
        }
      }

      // Preparar datos para actualizar
      final Map<String, dynamic> updateData = {
        'denominacion': denominacion,
        'descripcion': descripcion,
        'sku_codigo': skuCodigo,
      };

      // Agregar URL de imagen solo si se subió una nueva
      if (imageUrl != null) {
        updateData['image'] = imageUrl;
      }

      // Agregar visibilidad si se especifica
      if (visibleVendedor != null) {
        updateData['visible_vendedor'] = visibleVendedor;
      }

      // Actualizar categoría
      await _supabase
          .from('app_dat_categoria')
          .update(updateData)
          .eq('id', categoryId);

      // Config del Home: `especial` / `orden_home` viven en la tabla puente.
      if (especial != null || ordenHome != null) {
        final configActualizada = await _updateCategoriaTienda(categoryId, {
          if (especial != null) 'especial': especial,
          if (ordenHome != null) 'orden_home': ordenHome,
        });
        if (!configActualizada) {
          // No devolver `true` en silencio: si la puente no se actualiza, el
          // switch del Home parecería no hacer nada (R3 del plan).
          print(
            '❌ No se pudo actualizar la configuración del Home de la categoría $categoryId',
          );
          return false;
        }
      }

      print('✅ Categoría actualizada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar categoría: $e');
      return false;
    }
  }

  /// Actualiza una fila de `app_dat_categoria_tienda` (config por tienda).
  ///
  /// Devuelve `false` y **registra** el error si falla o si la categoría no
  /// está vinculada a la tienda activa; nunca lanza.
  Future<bool> _updateCategoriaTienda(
    int categoryId,
    Map<String, dynamic> data, {
    int? idTienda,
  }) async {
    try {
      final tiendaId = idTienda ?? await _userPrefs.getIdTienda();
      if (tiendaId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final actualizadas = await _supabase
          .from('app_dat_categoria_tienda')
          .update(data)
          .eq('id_categoria', categoryId)
          .eq('id_tienda', tiendaId)
          .select('id');

      if (actualizadas.isEmpty) {
        throw Exception(
          'La categoría $categoryId no está vinculada a la tienda $tiendaId',
        );
      }

      print('✅ app_dat_categoria_tienda actualizada ($categoryId): $data');
      return true;
    } catch (e) {
      print(
        '❌ Error actualizando app_dat_categoria_tienda ($categoryId): $e',
      );
      return false;
    }
  }

  /// Marca/desmarca una categoría como «especial» en el Home del TPV.
  ///
  /// Al marcarla se le asigna el siguiente `orden_home` (al final del grupo de
  /// especiales) para que el orden inicial sea determinista.
  Future<bool> setEspecial(int categoryId, bool valor) async {
    try {
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final data = <String, dynamic>{'especial': valor};
      if (valor) {
        data['orden_home'] = await _siguienteOrdenHome(idTienda);
      }

      return await _updateCategoriaTienda(
        categoryId,
        data,
        idTienda: idTienda,
      );
    } catch (e) {
      print('❌ Error marcando la categoría $categoryId como especial: $e');
      return false;
    }
  }

  /// Fija el `orden_home` de una categoría especial.
  Future<bool> setOrdenHome(int categoryId, int orden) async {
    return _updateCategoriaTienda(categoryId, {'orden_home': orden});
  }

  /// Reordena el grupo completo de especiales.
  ///
  /// [orderedCategoryIds] es la lista de IDs en el orden deseado: se escribe
  /// `orden_home = posición + 1` a cada una. Es secuencial (hay pocas
  /// especiales por tienda) y devuelve `false` si alguna escritura falla, para
  /// que la UI recargue el orden real desde la base.
  Future<bool> reorderEspeciales(List<int> orderedCategoryIds) async {
    if (orderedCategoryIds.isEmpty) return true;
    try {
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      for (var i = 0; i < orderedCategoryIds.length; i++) {
        final ok = await _updateCategoriaTienda(
          orderedCategoryIds[i],
          {'orden_home': i + 1},
          idTienda: idTienda,
        );
        if (!ok) return false;
      }

      print(
        '✅ Orden del Home actualizado: ${orderedCategoryIds.length} especiales',
      );
      return true;
    } catch (e) {
      print('❌ Error reordenando especiales: $e');
      return false;
    }
  }

  /// Siguiente `orden_home` libre dentro del grupo de especiales de la tienda.
  Future<int> _siguienteOrdenHome(int idTienda) async {
    final response = await _supabase
        .from('app_dat_categoria_tienda')
        .select('orden_home')
        .eq('id_tienda', idTienda)
        .eq('especial', true);

    var maximo = 0;
    for (final row in response) {
      final orden =
          ((row as Map<String, dynamic>)['orden_home'] as num?)?.toInt() ?? 0;
      if (orden > maximo) maximo = orden;
    }
    return maximo + 1;
  }

  /// Verifica si una categoría tiene subcategorías **reales** (visibles).
  ///
  /// Se consulta la tabla y no el RPC `get_subcategorias_by_categoria` porque el
  /// RPC no expone `oculta`: desde que el trigger crea una subcategoría
  /// «General» oculta para cada categoría especial, contar todo bloquearía el
  /// borrado de esas categorías para siempre («tiene subcategorías asociadas»).
  /// Las ocultas las gestiona el sistema, así que no cuentan.
  Future<bool> categoryHasSubcategories(int categoryId) async {
    try {
      final subcategories = await _supabase
          .from('app_dat_subcategorias')
          .select('id')
          .eq('idcategoria', categoryId)
          .eq('oculta', false)
          .limit(1);

      return subcategories.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando subcategorías: $e');
      return false;
    }
  }

  /// Elimina una categoría y su relación con la tienda
  Future<Map<String, dynamic>> deleteCategory(int categoryId) async {
    try {
      print('🗑️ Eliminando categoría ID: $categoryId');

      // Verificar si tiene subcategorías
      final hasSubcategories = await categoryHasSubcategories(categoryId);
      if (hasSubcategories) {
        return {
          'success': false,
          'error': 'subcategories_exist',
          'message':
              'No se puede eliminar la categoría porque tiene subcategorías asociadas. Elimine primero las subcategorías.',
        };
      }

      // Obtener ID de tienda
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Eliminar relación categoría-tienda
      await _supabase
          .from('app_dat_categoria_tienda')
          .delete()
          .eq('id_categoria', categoryId)
          .eq('id_tienda', idTienda);

      // Verificar si la categoría tiene otras relaciones con tiendas
      final otherRelations = await _supabase
          .from('app_dat_categoria_tienda')
          .select('id')
          .eq('id_categoria', categoryId);

      // Si no tiene otras relaciones, eliminar la categoría completamente
      if (otherRelations.isEmpty) {
        await _supabase.from('app_dat_categoria').delete().eq('id', categoryId);
        print('✅ Categoría eliminada completamente');
      } else {
        print(
          '✅ Relación categoría-tienda eliminada (categoría mantiene otras relaciones)',
        );
      }

      return {'success': true, 'message': 'Categoría eliminada exitosamente'};
    } catch (e) {
      print('❌ Error al eliminar categoría: $e');
      return {
        'success': false,
        'error': 'database_error',
        'message': 'Error al eliminar la categoría: $e',
      };
    }
  }
}
