import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NomTipoMercancia {
  final int id;
  final String nombre;
  final String codigo;
  final String? nmfcCodigo;

  const NomTipoMercancia({
    required this.id,
    required this.nombre,
    required this.codigo,
    this.nmfcCodigo,
  });

  factory NomTipoMercancia.fromJson(Map<String, dynamic> j) => NomTipoMercancia(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        codigo: j['codigo'] as String,
        nmfcCodigo: j['nmfc_codigo'] as String?,
      );
}

class NomTipoEquipo {
  final int id;
  final String nombre;
  final String abreviacion;

  const NomTipoEquipo({
    required this.id,
    required this.nombre,
    required this.abreviacion,
  });

  factory NomTipoEquipo.fromJson(Map<String, dynamic> j) => NomTipoEquipo(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        abreviacion: j['abreviacion'] as String,
      );
}

class NomEquipoManejo {
  final int id;
  final String nombre;
  final String codigo;

  const NomEquipoManejo({
    required this.id,
    required this.nombre,
    required this.codigo,
  });

  factory NomEquipoManejo.fromJson(Map<String, dynamic> j) => NomEquipoManejo(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        codigo: j['codigo'] as String,
      );
}

class NomCommodity {
  final int id;
  final String nombre;
  final String codigo;

  const NomCommodity({
    required this.id,
    required this.nombre,
    required this.codigo,
  });

  factory NomCommodity.fromJson(Map<String, dynamic> j) => NomCommodity(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        codigo: j['codigo'] as String,
      );
}

class NomencladoresService {
  final _supabase = Supabase.instance.client;

  Future<List<NomTipoMercancia>> getTiposMercancia() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_nom_tipo_mercancia')
          .select('id, nombre, codigo, nmfc_codigo')
          .eq('activo', true)
          .order('nombre');
      return (data as List)
          .map((e) => NomTipoMercancia.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[NomencladoresService] getTiposMercancia error: $e');
      rethrow;
    }
  }

  Future<List<NomTipoEquipo>> getTiposEquipo() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_nom_tipo_equipo')
          .select('id, nombre, abreviacion')
          .eq('activo', true)
          .order('nombre');
      return (data as List)
          .map((e) => NomTipoEquipo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[NomencladoresService] getTiposEquipo error: $e');
      rethrow;
    }
  }

  Future<List<NomEquipoManejo>> getOpcionesEquipoManejo() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_nom_equipo_manejo_carga')
          .select('id, nombre, codigo')
          .eq('activo', true)
          .order('nombre');
      return (data as List)
          .map((e) => NomEquipoManejo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[NomencladoresService] getOpcionesEquipoManejo error: $e');
      rethrow;
    }
  }

  Future<List<NomCommodity>> getCommodities() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_nom_commodity')
          .select('id, nombre, codigo')
          .eq('activo', true)
          .order('nombre');
      return (data as List)
          .map((e) => NomCommodity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[NomencladoresService] getCommodities error: $e');
      rethrow;
    }
  }

  Future<void> loadAll({
    required void Function(List<NomTipoMercancia>) onMercancia,
    required void Function(List<NomTipoEquipo>) onEquipo,
    required void Function(List<NomEquipoManejo>) onEquipoManejo,
    required void Function(List<NomCommodity>) onCommodity,
  }) async {
    final results = await Future.wait([
      getTiposMercancia(),
      getTiposEquipo(),
      getOpcionesEquipoManejo(),
      getCommodities(),
    ]);
    onMercancia(results[0] as List<NomTipoMercancia>);
    onEquipo(results[1] as List<NomTipoEquipo>);
    onEquipoManejo(results[2] as List<NomEquipoManejo>);
    onCommodity(results[3] as List<NomCommodity>);
  }
}
