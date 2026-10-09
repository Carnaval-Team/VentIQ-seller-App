import 'package:supabase_flutter/supabase_flutter.dart';

/// Lectura del catálogo de servicios para los selectores del superadmin.
///
/// Lo usan los **patrocinados** y las **colecciones temáticas**: ambos eligen
/// servicios del **mismo** catálogo que ve el cliente (`cliente_obtener_servicios`),
/// así que comparten una única implementación en vez de duplicar la lectura.
///
/// Se usa ese RPC y no una consulta directa a `flow.local_servicio` a propósito:
/// así lo que el superadmin puede elegir es exactamente lo que el cliente puede
/// ver, sin servicios huérfanos ni de locales inactivos.
class CatalogoDestinosService {
  const CatalogoDestinosService._();

  static final _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Servicios con etiqueta "Servicio · Local", ordenados alfabéticamente.
  static Future<List<({int id, String etiqueta})>> servicios() async {
    final res = await _supabase
        .schema(_schema)
        .rpc('cliente_obtener_servicios');
    if (res is! List) return const [];
    final vistos = <int>{};
    final out = <({int id, String etiqueta})>[];
    for (final fila in res.whereType<Map>()) {
      final id = (fila['id_local_servicio'] as num?)?.toInt();
      if (id == null || !vistos.add(id)) continue;
      final s = fila['servicio'] as Map?;
      final l = fila['local'] as Map?;
      final nombreServicio = s?['nombre']?.toString() ?? 'Servicio';
      final nombreLocal = l?['nombre']?.toString() ?? 'Local';
      out.add((id: id, etiqueta: '$nombreServicio · $nombreLocal'));
    }
    out.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
    return out;
  }

  /// Entidades (negocios) para acotar una regla de puntos o un beneficio.
  ///
  /// Va contra `flow.entidad` y **no** contra el catálogo: aquí no se eligen
  /// servicios, se elige *de quién* es la regla. Un negocio sin servicios
  /// publicados también puede tener su propia regla.
  ///
  /// `flow.entidad` tiene `entidad_select_all` para `authenticated`, así que la
  /// lectura pasa con la sesión del superadmin sin RPC de por medio.
  static Future<List<({int id, String etiqueta})>> entidades() async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad')
        .select('id, denominacion')
        .order('denominacion');
    final out = <({int id, String etiqueta})>[];
    for (final fila in res.whereType<Map>()) {
      final id = (fila['id'] as num?)?.toInt();
      if (id == null) continue;
      out.add((id: id, etiqueta: fila['denominacion']?.toString() ?? 'Entidad $id'));
    }
    return out;
  }
}
