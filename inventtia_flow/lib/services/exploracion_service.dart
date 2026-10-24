import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/categoria_con_conteo.dart';
import '../models/establecimiento_resumen.dart';
import '../utils/esquema_pendiente.dart';
import 'home_catalog_service.dart';

/// Datos de la «Exploración rápida» del Home: categorías con contadores,
/// establecimientos y top 10.
///
/// Las dos primeras salen de la migración **57**
/// (`cliente_categorias_resumen` y `cliente_locales_publicos`). El top 10 **no**
/// necesita nada nuevo: reusa `flow.cliente_ranking_semanal(p_limite)`, que ya
/// existía para el bloque semanal del Home.
///
/// Si la 57 no está aplicada, PostgREST responde `PGRST202` y las pantallas
/// muestran un aviso de «falta aplicar la migración» en vez de un error de red
/// genérico: ver [esMigracionPendiente].
class ExploracionService {
  ExploracionService._();

  static const String _schema = 'flow';

  /// Mensaje único para las pantallas cuando falta la migración 57.
  static const String mensajeMigracionPendiente =
      'Esta vista necesita la migración 57 (categorías y establecimientos con '
      'contadores). Aplícala en Supabase y vuelve a intentarlo.';

  /// Mensaje para el top 10, que NO depende de la 57: su RPC
  /// (`cliente_ranking_semanal`) es de la migración 36. Decirle al usuario que
  /// aplique la 57 cuando lo que falta es la 36 lo mandaría a arreglar otra cosa.
  static const String mensajeRankingPendiente =
      'Esta vista necesita la migración 36 (ranking semanal de servicios). '
      'Aplícala en Supabase y vuelve a intentarlo.';

  /// `true` cuando el fallo es «esa función todavía no existe en la base».
  ///
  /// Lo usan las pantallas para elegir entre "revisa tu conexión" (fallo real)
  /// y "falta la migración" (función ausente), sin que el usuario vea un error
  /// técnico.
  static bool esMigracionPendiente(Object error) =>
      esErrorDeEsquemaAusente(error);

  /// Nomenclador con contadores reales por categoría y subcategoría.
  static Future<ResumenCategorias> categorias() async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .rpc('cliente_categorias_resumen');

    if (res is! Map) return ResumenCategorias.vacio;
    return ResumenCategorias.fromJson(Map<String, dynamic>.from(res));
  }

  /// Establecimientos con al menos un servicio reservable bajo el filtro.
  ///
  /// Los tres filtros son de servidor y opcionales. Filtrar por categoría
  /// **incluye** sus subcategorías (misma semántica que el feed y que el
  /// catálogo).
  static Future<List<EstablecimientoResumen>> establecimientos({
    int? idCategoria,
    int? idSubcategoria,
    String? provincia,
  }) async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .rpc(
          'cliente_locales_publicos',
          params: <String, dynamic>{
            'p_id_categoria': idCategoria,
            'p_id_subcategoria': idSubcategoria,
            'p_provincia': (provincia == null || provincia.trim().isEmpty)
                ? null
                : provincia.trim(),
          },
        );

    if (res is! List) return const <EstablecimientoResumen>[];
    return res
        .whereType<Map>()
        .map((e) => EstablecimientoResumen.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.idLocal != 0)
        .toList(growable: false);
  }

  /// Top de servicios por lugares reservados en la semana en curso.
  ///
  /// Delega en el servicio del catálogo para no tener dos lecturas del mismo
  /// RPC (y para seguir beneficiándose de su conversión de ítems a
  /// `HomeCatalogItem`).
  static Future<List<HomeCatalogItem>> topServicios({int limite = 10}) =>
      HomeCatalogService.fetchRankingSemanal(limite: limite);
}