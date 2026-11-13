import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio del catálogo de vehículos.
///
/// Siempre trae un mensaje en español listo para un SnackBar; nunca expone el
/// JSON crudo de PostgREST.
class MueveteVehiculosException implements Exception {
  final String mensaje;

  const MueveteVehiculosException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Catálogo de tipos de vehículo del taxi (H1).
///
/// `vehicle_type` es la única fuente de la lista que pinta la app del cliente:
/// nombre visible, orden, capacidad y visibilidad se cambian aquí y **no**
/// requieren recompilar la app del cliente.
///
/// Escritura: depende de la política RLS `superadmin_all_vehicle_type`.
class MueveteVehiculosService {
  static final _supabase = Supabase.instance.client;

  // ─── Límites del modelo (alineados con los CHECK de la tabla) ─────────

  /// `vehicle_type_pasajeros_chk`: 1 <= pasajeros_max <= 20.
  static const int pasajerosMin = 1;
  static const int pasajerosMax = 20;

  /// `vehicle_type_orden_chk`: 0 <= orden <= 9999.
  static const int ordenMin = 0;
  static const int ordenMax = 9999;

  /// Longitud máxima razonable del nombre que verá el cliente.
  static const int nombreMax = 40;

  /// Separa los tipos visibles de los ocultos al renumerar el orden.
  static const int _baseOcultos = 900;

  /// Columnas que consume la pantalla.
  static const String _columnas =
      'id, tipo, nombre_ui, orden, pasajeros_max, '
      'multiplicador_tarifa, status, categoria, created_at';

  // ─── Lectura ──────────────────────────────────────────────────────────

  /// Devuelve **todos** los tipos (visibles y ocultos) ordenados por `orden`.
  ///
  /// Los ocultos se devuelven a propósito: la pantalla los muestra atenuados
  /// para poder volver a encenderlos sin tocar la base de datos.
  static Future<List<Map<String, dynamic>>> listarTipos() {
    return _guard('No se pudieron cargar los tipos de vehículo', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('vehicle_type')
          .select(_columnas)
          .order('orden', ascending: true)
          .order('id', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  // ─── Escritura ────────────────────────────────────────────────────────

  /// Guarda los campos editables de un tipo.
  ///
  /// Sólo se envían las claves presentes: el multiplicador **no** se toca
  /// aquí (se edita en Tarifas y Zonas, que es donde vive el simulador).
  static Future<void> guardarTipo(
    int id, {
    String? nombreUi,
    int? pasajerosMax,
    int? orden,
    bool? status,
  }) {
    final cambios = <String, dynamic>{};
    if (nombreUi != null) {
      final limpio = nombreUi.trim();
      _validarNombre(limpio);
      cambios['nombre_ui'] = limpio;
    }
    if (pasajerosMax != null) {
      _validarPasajeros(pasajerosMax);
      cambios['pasajeros_max'] = pasajerosMax;
    }
    if (orden != null) {
      _validarOrden(orden);
      cambios['orden'] = orden;
    }
    if (status != null) cambios['status'] = status;

    if (cambios.isEmpty) {
      throw const MueveteVehiculosException(
        'No hay cambios que guardar en este tipo de vehículo.',
      );
    }

    return _guard('No se pudo guardar el tipo de vehículo', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('vehicle_type')
          .update(cambios)
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const MueveteVehiculosException(
          'El tipo de vehículo ya no existe o no tienes permisos para '
          'editarlo.',
        );
      }
    });
  }

  /// Cambia la visibilidad de un tipo (`status`).
  static Future<void> cambiarVisibilidad(int id, bool visible) {
    return guardarTipo(id, status: visible);
  }

  /// Renumera el orden de todos los tipos.
  ///
  /// Recibe la lista completa ya ordenada (visibles primero, ocultos después)
  /// y asigna 10, 20, 30… a los visibles y 900, 910, 920… a los ocultos, de
  /// modo que subir/bajar nunca deje empates ni huecos.
  static Future<void> guardarOrden(List<Map<String, dynamic>> tipos) {
    final visibles = <Map<String, dynamic>>[];
    final ocultos = <Map<String, dynamic>>[];
    for (final t in tipos) {
      (t['status'] == true ? visibles : ocultos).add(t);
    }

    final cambios = <int, int>{};
    for (var i = 0; i < visibles.length; i++) {
      cambios[visibles[i]['id'] as int] = (i + 1) * 10;
    }
    for (var i = 0; i < ocultos.length; i++) {
      cambios[ocultos[i]['id'] as int] = _baseOcultos + i * 10;
    }

    return _guard('No se pudo guardar el orden de los vehículos', () async {
      for (final entrada in cambios.entries) {
        if (entrada.value > ordenMax) continue;
        await _supabase
            .schema('muevete')
            .from('vehicle_type')
            .update({'orden': entrada.value})
            .eq('id', entrada.key);
      }
    });
  }

  /// Cuenta cuántos tipos vería el cliente (`status = true`).
  static int contarVisibles(List<Map<String, dynamic>> tipos) =>
      tipos.where((t) => t['status'] == true).length;

  // ─── Validaciones locales (además de los CHECK de la BD) ──────────────

  static void _validarNombre(String nombre) {
    if (nombre.isEmpty) {
      throw const MueveteVehiculosException(
        'El nombre visible no puede quedar vacío.',
      );
    }
    if (nombre.length > nombreMax) {
      throw const MueveteVehiculosException(
        'El nombre visible no puede superar $nombreMax caracteres.',
      );
    }
  }

  static void _validarPasajeros(int pasajeros) {
    if (pasajeros < pasajerosMin || pasajeros > pasajerosMax) {
      throw const MueveteVehiculosException(
        'La capacidad debe estar entre $pasajerosMin y $pasajerosMax '
        'pasajeros.',
      );
    }
  }

  static void _validarOrden(int orden) {
    if (orden < ordenMin || orden > ordenMax) {
      throw const MueveteVehiculosException(
        'El orden debe estar entre $ordenMin y $ordenMax.',
      );
    }
  }

  // ─── Infraestructura de errores ───────────────────────────────────────

  static Future<T> _guard<T>(String accion, Future<T> Function() cuerpo) async {
    try {
      return await cuerpo();
    } on MueveteVehiculosException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        '[MueveteVehiculosService] $accion · code=${e.code} message=${e.message}',
      );
      throw MueveteVehiculosException('$accion: ${_detalle(e)}.');
    } on AuthException catch (e) {
      debugPrint('[MueveteVehiculosService] $accion · auth=${e.message}');
      throw const MueveteVehiculosException(
        'La sesión expiró o no es válida. Vuelve a iniciar sesión.',
      );
    } catch (e) {
      debugPrint('[MueveteVehiculosService] $accion · $e');
      throw MueveteVehiculosException('$accion: $e');
    }
  }

  static String _detalle(PostgrestException e) {
    switch (e.code) {
      case '42501':
        return 'no tienes permisos de superadministrador';
      case '23514':
        return 'los valores están fuera del rango permitido por la base de datos';
      case '23505':
        return 'ya existe un registro con esos valores';
      case '42P01':
        return 'la tabla no existe en el esquema muevete';
      default:
        return e.message;
    }
  }
}