import 'package:supabase_flutter/supabase_flutter.dart';

/// Nomencladores globales de costo (`app_cont_tipo_costo`, `app_nom_naturaleza_costo`).
class CostosNomencladorService {
  CostosNomencladorService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<Map<String, dynamic>>> listarTipos() async {
    final response = await _supabase
        .from('app_cont_tipo_costo')
        .select('''
          id,
          denominacion,
          descripcion,
          naturaleza,
          afecta_margen,
          created_at,
          app_nom_naturaleza_costo ( id, denominacion )
        ''')
        .order('denominacion');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> crearTipo({
    required String denominacion,
    String? descripcion,
    required int naturaleza,
    bool afectaMargen = true,
  }) async {
    final row = await _supabase
        .from('app_cont_tipo_costo')
        .insert({
          'denominacion': denominacion.trim(),
          'descripcion': descripcion?.trim(),
          'naturaleza': naturaleza,
          'afecta_margen': afectaMargen,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> actualizarTipo({
    required int id,
    required String denominacion,
    String? descripcion,
    required int naturaleza,
    required bool afectaMargen,
  }) async {
    await _supabase.from('app_cont_tipo_costo').update({
      'denominacion': denominacion.trim(),
      'descripcion': descripcion?.trim(),
      'naturaleza': naturaleza,
      'afecta_margen': afectaMargen,
    }).eq('id', id);
  }

  Future<void> eliminarTipo(int id) async {
    await _supabase.from('app_cont_tipo_costo').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> listarNaturalezas() async {
    final response = await _supabase
        .from('app_nom_naturaleza_costo')
        .select('id, denominacion, descripcion, created_at')
        .order('id');
    return List<Map<String, dynamic>>.from(response);
  }

  /// Garantiza Gasto (1) e Ingreso (2). Tras un wipe pueden faltar.
  Future<List<Map<String, dynamic>>> asegurarNaturalezasBase() async {
    final actuales = await listarNaturalezas();
    final ids = actuales
        .map((n) => n['id'] is int ? n['id'] as int : int.tryParse('${n['id']}'))
        .whereType<int>()
        .toSet();

    if (!ids.contains(1)) {
      await _supabase.from('app_nom_naturaleza_costo').upsert({
        'id': 1,
        'denominacion': 'Gasto',
        'descripcion':
            'Erogaciones que afectan negativamente el resultado',
      });
    }
    if (!ids.contains(2)) {
      await _supabase.from('app_nom_naturaleza_costo').upsert({
        'id': 2,
        'denominacion': 'Ingreso',
        'descripcion':
            'Entradas que afectan positivamente el resultado',
      });
    }
    return listarNaturalezas();
  }

  Future<Map<String, dynamic>> crearNaturaleza({
    required String denominacion,
    String? descripcion,
    int? id,
  }) async {
    var nextId = id;
    if (nextId == null) {
      final existentes = await listarNaturalezas();
      var maxId = 0;
      for (final n in existentes) {
        final v = n['id'];
        final asInt = v is int ? v : int.tryParse('$v') ?? 0;
        if (asInt > maxId) maxId = asInt;
      }
      nextId = maxId + 1;
    }

    final row = await _supabase
        .from('app_nom_naturaleza_costo')
        .insert({
          'id': nextId,
          'denominacion': denominacion.trim(),
          'descripcion': descripcion?.trim(),
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> actualizarNaturaleza({
    required int id,
    required String denominacion,
    String? descripcion,
  }) async {
    await _supabase.from('app_nom_naturaleza_costo').update({
      'denominacion': denominacion.trim(),
      'descripcion': descripcion?.trim(),
    }).eq('id', id);
  }

  Future<void> eliminarNaturaleza(int id) async {
    await _supabase.from('app_nom_naturaleza_costo').delete().eq('id', id);
  }
}
