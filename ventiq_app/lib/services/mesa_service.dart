import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mesa.dart';
import '../models/order.dart';
import 'user_preferences_service.dart';
import 'order_service.dart';

/// Servicio de mesas para el modo restaurante.
///
/// Wraps de las RPCs:
///   - fn_listar_mesas_con_stats
///   - fn_resumen_mesas
///   - fn_insertar_mesa
///   - fn_actualizar_mesa
///   - fn_eliminar_mesa
///
/// Para listar órdenes asociadas a una mesa, delega en
/// `OrderService.listOrdersForMesa(idMesa)`.
class MesaService {
  MesaService._internal();
  static final MesaService _instance = MesaService._internal();
  factory MesaService() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  Future<int?> _getIdTienda() async {
    final id = await _userPreferencesService.getIdTienda();
    if (id == null) {
      print('⚠️ MesaService: id_tienda no disponible en preferencias');
    }
    return id;
  }

  /// Lista todas las mesas (activas y, opcionalmente, también inactivas)
  /// con sus contadores de órdenes.
  Future<List<Mesa>> listMesasWithStats({bool incluirInactivas = false}) async {
    try {
      final idTienda = await _getIdTienda();
      if (idTienda == null) return <Mesa>[];

      final response = await _supabase.rpc(
        'fn_listar_mesas_con_stats',
        params: {'p_id_tienda': idTienda},
      );

      if (response is! List) {
        print('⚠️ fn_listar_mesas_con_stats devolvió tipo inesperado: ${response.runtimeType}');
        return <Mesa>[];
      }

      final mesas = response
          .whereType<Map>()
          .map((row) => Mesa.fromJson(Map<String, dynamic>.from(row)))
          .where((m) => incluirInactivas || m.activa)
          .toList();

      print('✅ Mesas cargadas: ${mesas.length} (incluir inactivas: $incluirInactivas)');
      return mesas;
    } catch (e, st) {
      print('❌ Error listando mesas: $e');
      print(st);
      return <Mesa>[];
    }
  }

  /// Obtiene el resumen global para el header de la pantalla de mesas.
  Future<MesasResumen> getResumenMesas() async {
    try {
      final idTienda = await _getIdTienda();
      if (idTienda == null) return MesasResumen.empty();

      final response = await _supabase.rpc(
        'fn_resumen_mesas',
        params: {'p_id_tienda': idTienda},
      );

      if (response is Map) {
        return MesasResumen.fromJson(Map<String, dynamic>.from(response));
      }
      print('⚠️ fn_resumen_mesas devolvió tipo inesperado: ${response.runtimeType}');
      return MesasResumen.empty();
    } catch (e) {
      print('❌ Error obteniendo resumen de mesas: $e');
      return MesasResumen.empty();
    }
  }

  /// Crea una mesa nueva. Devuelve el id si tuvo éxito, o lanza excepción
  /// con el `message` del RPC en caso de error.
  Future<int> createMesa({
    required String numero,
    int capacidad = 4,
    String? zona,
    String? notas,
  }) async {
    final idTienda = await _getIdTienda();
    if (idTienda == null) {
      throw Exception('Tienda no disponible');
    }

    final response = await _supabase.rpc(
      'fn_insertar_mesa',
      params: {
        'p_id_tienda': idTienda,
        'p_numero': numero.trim(),
        'p_capacidad': capacidad,
        'p_zona': zona?.trim().isEmpty ?? true ? null : zona!.trim(),
        'p_notas': notas?.trim().isEmpty ?? true ? null : notas!.trim(),
      },
    );

    final data = response is Map ? Map<String, dynamic>.from(response) : null;
    if (data == null || data['status'] != 'success') {
      throw Exception(data?['message'] ?? 'Error creando mesa');
    }
    return (data['id_mesa'] as num).toInt();
  }

  /// Actualiza campos de una mesa. Sólo se envían los que cambian (null = no tocar).
  Future<void> updateMesa({
    required int idMesa,
    String? numero,
    int? capacidad,
    String? zona,
    String? notas,
    bool? activa,
  }) async {
    final response = await _supabase.rpc(
      'fn_actualizar_mesa',
      params: {
        'p_id_mesa': idMesa,
        if (numero != null) 'p_numero': numero.trim(),
        if (capacidad != null) 'p_capacidad': capacidad,
        if (zona != null) 'p_zona': zona.trim().isEmpty ? null : zona.trim(),
        if (notas != null) 'p_notas': notas.trim().isEmpty ? null : notas.trim(),
        if (activa != null) 'p_activa': activa,
      },
    );

    final data = response is Map ? Map<String, dynamic>.from(response) : null;
    if (data == null || data['status'] != 'success') {
      throw Exception(data?['message'] ?? 'Error actualizando mesa');
    }
  }

  /// Elimina (o desactiva si tiene histórico) una mesa.
  ///
  /// Devuelve `true` si se borró del todo, `false` si fue soft-delete.
  Future<bool> deleteMesa(int idMesa) async {
    final response = await _supabase.rpc(
      'fn_eliminar_mesa',
      params: {'p_id_mesa': idMesa},
    );

    final data = response is Map ? Map<String, dynamic>.from(response) : null;
    if (data == null || data['status'] != 'success') {
      throw Exception(data?['message'] ?? 'Error eliminando mesa');
    }
    return data['mode'] == 'hard_delete';
  }

  /// Lista las órdenes asociadas a una mesa.
  /// Delega en `OrderService.listOrdersForMesa` para reutilizar la
  /// transformación de items, pagos, descuentos, etc.
  Future<List<Order>> getOrdersForMesa(int idMesa) {
    return OrderService().listOrdersForMesa(idMesa);
  }
}
