import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_preferences_service.dart';

/// Carga la disponibilidad de un elaborado para un TPV.
typedef DisponibilidadElaboradoLoader =
    Future<Map<String, dynamic>?> Function(int idProducto, int idTpv);

/// Disponibilidad **real** de los productos elaborados.
///
/// Un elaborado no se vende por su stock propio: se vende por lo que se puede
/// **preparar** con la materia prima de su cocina. `fn_disponibilidad_plato`
/// ya resuelve eso en el servidor (receta recursiva + almacén de la cocina +
/// enrutamiento del TPV), y esta clase la expone al cliente:
///
///  * `desplegable` se pinta en la lista del Home para no enseñar «Stock: 1»
///    cuando en realidad se pueden preparar 41000;
///  * el alta rápida usa el valor para limitar la cantidad.
///
/// Es tolerante: si la función no responde (offline, error, producto normal)
/// devuelve vacío y el llamador se queda con el stock directo que ya tenía.
class ElaboratedAvailabilityService {
  ElaboratedAvailabilityService({
    DisponibilidadElaboradoLoader? cargar,
    SupabaseClient? cliente,
    UserPreferencesService? prefs,
    Future<bool> Function()? offline,
  }) : _cargar = cargar ?? _cargarReal(cliente ?? Supabase.instance.client),
       _prefs = prefs ?? UserPreferencesService(),
       _offline = offline;

  final DisponibilidadElaboradoLoader _cargar;
  final UserPreferencesService _prefs;
  final Future<bool> Function()? _offline;

  /// Máximo de productos a consultar en paralelo. Una categoría normal tiene
  /// pocos elaborados; el tope evita que un catálogo raro dispare decenas de
  /// RPC desde una sola pantalla.
  static const int maxProductos = 20;

  /// Disponibilidad de varios productos. Devuelve solo los que se pudieron
  /// calcular, con la cantidad máxima preparable (>= 0).
  Future<Map<int, double>> disponibles({
    required Iterable<int> idsProductos,
    required int idTpv,
  }) async {
    final List<int> ids = idsProductos.toSet().take(maxProductos).toList();
    if (ids.isEmpty) return const <int, double>{};

    try {
      if (await _estaOffline()) return const <int, double>{};
    } catch (e) {
      debugPrint(
        '⚠️ Disponibilidad elaborados: no se pudo leer el modo offline: $e',
      );
    }

    final List<Map<String, dynamic>?> respuestas = await Future.wait(
      ids.map((int id) async {
        try {
          return await _cargar(id, idTpv);
        } catch (e) {
          debugPrint('⚠️ Disponibilidad del elaborado $id falló: $e');
          return null;
        }
      }),
    );

    final Map<int, double> salida = <int, double>{};
    for (int i = 0; i < ids.length; i++) {
      final double? valor = _leerDisponible(respuestas[i]);
      if (valor != null) salida[ids[i]] = valor;
    }
    return salida;
  }

  /// Disponibilidad de un solo producto, o `null` si no se pudo calcular.
  Future<double?> disponible({
    required int idProducto,
    required int idTpv,
  }) async {
    final Map<int, double> mapa = await disponibles(
      idsProductos: <int>[idProducto],
      idTpv: idTpv,
    );
    return mapa[idProducto];
  }

  Future<bool> _estaOffline() async {
    if (_offline != null) return _offline();
    return _prefs.shouldUseLocalData();
  }

  /// Lee `disponible` de la respuesta jsonb de `fn_disponibilidad_plato`.
  ///
  /// `null` = no aplica o no se pudo usar (error, servicio ilimitado...).
  static double? _leerDisponible(Map<String, dynamic>? respuesta) {
    if (respuesta == null) return null;
    if (respuesta['status'] != 'success') return null;
    if (respuesta['ilimitado'] == true) return null;

    final dynamic crudo = respuesta['disponible'];
    final double? valor =
        crudo is num
            ? crudo.toDouble()
            : double.tryParse(crudo?.toString() ?? '');
    if (valor == null) return null;
    return valor < 0 ? 0 : valor;
  }

  static DisponibilidadElaboradoLoader _cargarReal(SupabaseClient cliente) {
    return (int idProducto, int idTpv) async {
      final dynamic respuesta = await cliente.rpc(
        'fn_disponibilidad_plato',
        params: <String, dynamic>{
          'p_id_producto': idProducto,
          'p_id_tpv': idTpv,
        },
      );
      if (respuesta is Map) {
        return Map<String, dynamic>.from(respuesta);
      }
      return null;
    };
  }
}
