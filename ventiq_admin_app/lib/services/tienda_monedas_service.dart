import 'package:supabase_flutter/supabase_flutter.dart';

/// Una moneda del catálogo global junto con si la tienda la acepta.
class TiendaMoneda {
  const TiendaMoneda({
    required this.codigo,
    required this.nombre,
    required this.simbolo,
    required this.activaGlobal,
    required this.aceptada,
    required this.orden,
  });

  final String codigo;
  final String nombre;
  final String? simbolo;

  /// Activa en el catálogo global (`monedas.activo`).
  final bool activaGlobal;

  /// La tienda la acepta (`app_dat_tienda_moneda.activo`).
  final bool aceptada;

  final int orden;

  /// CUP es la moneda base contable: siempre debe estar aceptada.
  bool get esBase => codigo == 'CUP';

  TiendaMoneda copyWith({bool? aceptada, int? orden}) => TiendaMoneda(
    codigo: codigo,
    nombre: nombre,
    simbolo: simbolo,
    activaGlobal: activaGlobal,
    aceptada: aceptada ?? this.aceptada,
    orden: orden ?? this.orden,
  );

  Map<String, dynamic> toRpc() => {
    'moneda': codigo,
    'activo': aceptada,
    'orden': orden,
  };

  /// Etiqueta para la UI: `USD · Dólar Estadounidense`.
  String get etiqueta => simbolo == null || simbolo!.isEmpty
      ? '$codigo · $nombre'
      : '$codigo · $nombre ($simbolo)';
}

/// Monedas aceptadas por una tienda (Fase 2 del plan multimoneda).
///
/// Lee del catálogo global `monedas` y de `app_dat_tienda_moneda`, y escribe
/// con la RPC `fn_guardar_monedas_tienda`, que valida en servidor que el
/// usuario administre esa tienda (`fn_user_can_access_tienda`).
class TiendaMonedasService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<List<TiendaMoneda>> listar(int idTienda) async {
    final catalogo = await _supabase
        .from('monedas')
        .select('codigo, nombre, simbolo, activo, orden')
        .order('orden');

    final asignadas = await _supabase
        .from('app_dat_tienda_moneda')
        .select('moneda, activo, orden')
        .eq('id_tienda', idTienda);

    final porCodigo = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(asignadas as List)) {
      final codigo = (row['moneda'] ?? '').toString().trim();
      if (codigo.isNotEmpty) porCodigo[codigo] = row;
    }

    final lista = <TiendaMoneda>[];
    for (final row in List<Map<String, dynamic>>.from(catalogo as List)) {
      final codigo = (row['codigo'] ?? '').toString().trim();
      if (codigo.isEmpty) continue;
      final asignada = porCodigo[codigo];
      lista.add(
        TiendaMoneda(
          codigo: codigo,
          nombre: (row['nombre'] ?? codigo).toString(),
          simbolo: row['simbolo']?.toString(),
          activaGlobal: row['activo'] == true,
          aceptada: asignada != null && asignada['activo'] == true,
          orden: asignada != null
              ? ((asignada['orden'] as num?) ?? 100).toInt()
              : ((row['orden'] as num?) ?? 100).toInt(),
        ),
      );
    }

    lista.sort((a, b) {
      if (a.orden != b.orden) return a.orden.compareTo(b.orden);
      return a.codigo.compareTo(b.codigo);
    });
    return lista;
  }

  /// Guarda el conjunto. Lo que no se envíe queda desactivado en el servidor.
  ///
  /// CUP se fuerza a activa: es la moneda base y el servidor la exige.
  static Future<void> guardar(int idTienda, List<TiendaMoneda> monedas) async {
    final payload = monedas
        .map((m) => (m.esBase ? m.copyWith(aceptada: true) : m).toRpc())
        .toList();

    await _supabase.rpc(
      'fn_guardar_monedas_tienda',
      params: {'p_id_tienda': idTienda, 'p_monedas': payload},
    );
  }

  /// Mensaje legible de un error de Postgres/Supabase.
  static String mensajeError(Object e) {
    final texto = e.toString();
    final idx = texto.indexOf('P0001:');
    if (idx >= 0) {
      final resto = texto.substring(idx + 6).trim();
      final corte = resto.indexOf('\n');
      return corte > 0 ? resto.substring(0, corte).trim() : resto;
    }
    if (texto.length > 220) return '${texto.substring(0, 220)}…';
    return texto;
  }
}