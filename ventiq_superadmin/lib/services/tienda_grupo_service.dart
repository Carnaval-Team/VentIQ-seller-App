import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grupo multitienda: una tienda principal y sus secundarias.
/// La relación vive en `app_dat_tienda.id_tienda_principal`
/// (ver SQL/tienda_multitienda.sql).
class TiendaGrupoService {
  static final _supabase = Supabase.instance.client;

  /// Todas las tiendas con su principal (si tienen).
  /// Cada fila: id, denominacion, id_tienda_principal.
  static Future<List<Map<String, dynamic>>> cargarTiendas() async {
    final rows = await _supabase
        .from('app_dat_tienda')
        .select('id, denominacion, id_tienda_principal')
        .order('denominacion');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Mapa id_tienda_secundaria -> id_tienda_principal.
  static Map<int, int> mapaSecundariaPrincipal(
    List<Map<String, dynamic>> tiendas,
  ) {
    final mapa = <int, int>{};
    for (final t in tiendas) {
      final id = (t['id'] as num?)?.toInt();
      final principal = (t['id_tienda_principal'] as num?)?.toInt();
      if (id != null && principal != null && principal != id) {
        mapa[id] = principal;
      }
    }
    return mapa;
  }

  /// Mapa id_tienda -> denominacion.
  static Map<int, String> mapaNombres(List<Map<String, dynamic>> tiendas) {
    return {
      for (final t in tiendas)
        if ((t['id'] as num?)?.toInt() != null)
          (t['id'] as num).toInt(): t['denominacion']?.toString() ?? 'Tienda',
    };
  }

  /// Secundarias agrupadas por principal: principalId -> [secundariaId...].
  static Map<int, List<int>> secundariasPorPrincipal(
    List<Map<String, dynamic>> tiendas,
  ) {
    final grupos = <int, List<int>>{};
    mapaSecundariaPrincipal(tiendas).forEach((sec, principal) {
      grupos.putIfAbsent(principal, () => []).add(sec);
    });
    return grupos;
  }

  /// Vincula `idTienda` como secundaria de `idPrincipal` (null la desvincula).
  static Future<void> asignarPrincipal(
    int idTienda,
    int? idPrincipal,
  ) async {
    await _supabase
        .from('app_dat_tienda')
        .update({'id_tienda_principal': idPrincipal})
        .eq('id', idTienda);
  }

  /// Ids de las suscripciones a actualizar junto con la de la principal:
  /// la suscripción vigente (id mayor) de cada tienda secundaria.
  static Future<List<int>> suscripcionesDeSecundarias(int idPrincipal) async {
    try {
      final secundarias = await _supabase
          .from('app_dat_tienda')
          .select('id')
          .eq('id_tienda_principal', idPrincipal);
      final ids = <int>[];
      for (final s in List<Map<String, dynamic>>.from(secundarias)) {
        final idSec = (s['id'] as num?)?.toInt();
        if (idSec == null) continue;
        final sus = await _supabase
            .from('app_suscripciones')
            .select('id')
            .eq('id_tienda', idSec)
            .order('id', ascending: false)
            .limit(1);
        if (sus.isNotEmpty) {
          ids.add((sus.first['id'] as num).toInt());
        }
      }
      return ids;
    } catch (e) {
      debugPrint('Secundarias de tienda $idPrincipal no disponibles: $e');
      return [];
    }
  }
}
