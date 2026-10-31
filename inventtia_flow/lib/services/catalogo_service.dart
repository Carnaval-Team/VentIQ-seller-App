import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/servicio.dart';
import 'suscripcion_service.dart';
import 'tipo_actividad_service.dart';

/// Centinela para distinguir "no toques este campo" de "ponlo a `null`".
///
/// Con `Map`, un `null` no puede significar las dos cosas: PostgREST necesita
/// saber si el campo va en el body. Los parámetros nuevos que deben poder
/// **limpiarse** (`horario_detalle`) usan este valor por defecto.
class _NoCambiar {
  const _NoCambiar();
}

const _NoCambiar _noCambiar = _NoCambiar();

class CatalogoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Check if we have access to the flow schema
  static Future<bool> checkSchemaAccess() async {
    try {
      await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .select('id')
          .limit(1);
      return true;
    } catch (e) {
      print('[flow] CatalogoService.checkSchemaAccess ERROR: $e');
      if (e.toString().contains('permission denied') ||
          e.toString().contains('42501')) {
        print('[flow] ERROR CRÍTICO: Permiso denegado para el esquema "flow".');
        print('[flow] ================================================');
        print('[flow] SOLUCIÓN - Ejecutar estos comandos SQL en Supabase:');
        print('[flow] 1. GRANT USAGE ON SCHEMA flow TO authenticated;');
        print('[flow] 2. GRANT USAGE ON SCHEMA flow TO anon;');
        print(
          '[flow] 3. GRANT ALL ON ALL TABLES IN SCHEMA flow TO authenticated;',
        );
        print('[flow] 4. GRANT ALL ON ALL TABLES IN SCHEMA flow TO anon;');
        print(
          '[flow] 5. GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO authenticated;',
        );
        print('[flow] 6. GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO anon;');
        print('[flow] ================================================');
      }
      return false;
    }
  }

  /// Handle schema permission errors with user-friendly messages
  static Exception handleSchemaPermissionError(Exception e) {
    if (e.toString().contains('permission denied') ||
        e.toString().contains('42501')) {
      return Exception(
        'ERROR DE PERMISOS DE BASE DE DATOS\n\n'
        'No se puede acceder al esquema "flow" de la base de datos.\n\n'
        'SOLUCIÓN:\n'
        '1. Ve al panel de Supabase > SQL Editor\n'
        '2. Ejecuta los siguientes comandos:\n\n'
        'GRANT USAGE ON SCHEMA flow TO authenticated;\n'
        'GRANT USAGE ON SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO anon;\n\n'
        'Error original: ${e.toString()}',
      );
    }
    return e;
  }

  /// Nodos de la taxonomía activos (`flow.nom_tipo_actividad_servicio`).
  ///
  /// Delega en [TipoActividadService] a propósito: es el único sitio que sabe
  /// leer `id_padre`/`orden` y degradar a taxonomía plana si la migración
  /// `47_categorias_reales_subcategorias.sql` todavía no está aplicada. Antes
  /// esta función repetía la consulta y el formulario de servicios se quedaba
  /// sin saber a qué categoría pertenece cada subcategoría.
  static Future<List<Map<String, dynamic>>> getTiposActividadServicio() =>
      TipoActividadService.listarMapas(soloActivos: true);

  static Future<List<Servicio>> getServicios() async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .select()
          .order('nombre');
      return (res as List).map((e) => Servicio.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<List<Servicio>> getServiciosByEntidad(int idEntidad) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .select()
          .eq('id_entidad', idEntidad)
          .order('nombre');
      return (res as List).map((e) => Servicio.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Vuelve a leer un servicio de la base de datos.
  ///
  /// Se usa después de guardar desde el formulario para devolver a la pantalla
  /// de detalle la fila REAL (con `config_precio`, campos adicionales y
  /// `permite_tercero` ya persistidos) en vez de un objeto armado a mano. Ese
  /// era el bug del punto 5: el detalle seguía mostrando el `Servicio` viejo
  /// porque el bottom sheet se cerraba sin devolver nada.
  static Future<Servicio> getServicio(int id) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .select()
          .eq('id', id)
          .single();
      return Servicio.fromJson(res);
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<Servicio> createServicio({
    required String nombre,
    String? descripcion,
    String? foto,
    required int idEntidad,
    int? idTipoActividad,
    bool activo = true,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .insert({
            'nombre': nombre,
            'descripcion': descripcion,
            'foto': foto,
            'id_entidad': idEntidad,
            'activo': activo,
            if (idTipoActividad != null) 'id_tipo_actividad': idTipoActividad,
          })
          .select()
          .single();
      return Servicio.fromJson(res);
    } catch (e) {
      // El trigger `trg_limite_servicios` bloquea el INSERT cuando el plan no
      // permite más servicios de catálogo. Se traduce a un aviso accionable; si
      // el error no es de límite, se relanza intacto.
      final limite = SuscripcionService.traducirLimitePlan(
        e,
        recurso: 'servicios_catalogo',
      );
      if (limite != null) throw limite;
      rethrow;
    }
  }

  static Future<Servicio> updateServicio({
    required int id,
    required String nombre,
    String? descripcion,
    String? foto,
    int? idTipoActividad,
    bool? activo,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .update({
            'nombre': nombre,
            'descripcion': descripcion,
            if (foto != null) 'foto': foto,
            if (activo != null) 'activo': activo,
            if (idTipoActividad != null) 'id_tipo_actividad': idTipoActividad,
          })
          .eq('id', id)
          .select()
          .single();
      return Servicio.fromJson(res);
    } catch (e) {
      // Ver [updateLocal]: los triggers son BEFORE INSERT, pero la traducción se
      // mantiene por si el límite acaba aplicándose también al editar.
      final limite = SuscripcionService.traducirLimitePlan(
        e,
        recurso: 'servicios_catalogo',
      );
      if (limite != null) throw limite;
      rethrow;
    }
  }

  /// Activa/desactiva un servicio sin tocar el resto de sus campos.
  ///
  /// Va por PostgREST (no por RPC): la política `app_dat_servicios_*_admin`
  /// valida la pertenencia a la entidad vía `flow.is_entidad_admin`.
  static Future<void> setServicioActivo({
    required int id,
    required bool activo,
  }) async {
    await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .update({'activo': activo})
        .eq('id', id);
  }

  /// Activa/desactiva el **pago por adelantado** de un servicio (migración 67).
  ///
  /// Va por PostgREST, como [setServicioActivo]: la política de UPDATE de
  /// `app_dat_servicios` valida la pertenencia a la entidad. El interruptor
  /// maestro sigue siendo el de la entidad (`flow.cobro_config`).
  ///
  /// Devuelve las filas tocadas (`select('id')`) a propósito: un update que la
  /// RLS deja en **0 filas** no lanza en PostgREST, y ese no-op silencioso es
  /// justo el síntoma de «lo activo, guardo y sigue apagado». Si no se actualizó
  /// nada, se lanza para que la pantalla lo diga en vez de fingir que guardó.
  static Future<void> setCobroAdelantado({
    required int id,
    required bool activo,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .update({'cobro_adelantado': activo})
        .eq('id', id)
        .select('id');
    if (res.isEmpty) {
      throw Exception(
        'el servidor no actualizó el pago por adelantado '
        '(servicio inexistente o sin permiso)',
      );
    }
  }

  static Future<void> deleteServicio(int id) async {
    await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .delete()
        .eq('id', id);
  }

  static Future<List<Local>> getLocales() async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_locales')
          .select()
          .order('nombre');
      return (res as List).map((e) => Local.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<List<Local>> getLocalesByEntidad(int idEntidad) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_locales')
          .select()
          .eq('id_entidad', idEntidad)
          .order('nombre');
      return (res as List).map((e) => Local.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<Local> createLocal({
    required String nombre,
    String? descripcion,
    String? direccion,
    String? horarioAtencion,
    Map<String, dynamic>? horarioDetalle,
    String? pais,
    String? provincia,
    String? foto,
    required int idEntidad,
    bool activo = true,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_locales')
          .insert({
            'nombre': nombre,
            'descripcion': descripcion,
            'direccion': direccion,
            'horario_atencion': horarioAtencion,
            'horario_detalle': horarioDetalle,
            'pais': pais,
            'provincia': provincia,
            'foto': foto,
            'id_entidad': idEntidad,
            'activo': activo,
          })
          .select()
          .single();
      return Local.fromJson(res);
    } catch (e) {
      // Trigger `trg_limite_locales`: el plan no permite más locales.
      final limite = SuscripcionService.traducirLimitePlan(e, recurso: 'locales');
      if (limite != null) throw limite;
      rethrow;
    }
  }

  static Future<Local> updateLocal({
    required int id,
    required String nombre,
    String? descripcion,
    String? direccion,
    String? horarioAtencion,
    String? pais,
    String? provincia,
    String? foto,
    bool? activo,

    /// `_noCambiar` = no toques la columna; `null` = bórrala (el admin pasó a
    /// texto libre); un mapa = guárdalo.
    Object? horarioDetalle = _noCambiar,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('app_dat_locales')
          .update({
            'nombre': nombre,
            'descripcion': descripcion,
            'direccion': direccion,
            'horario_atencion': horarioAtencion,
            'pais': pais,
            'provincia': provincia,
            if (foto != null) 'foto': foto,
            if (activo != null) 'activo': activo,
            if (!identical(horarioDetalle, _noCambiar))
              'horario_detalle': horarioDetalle,
          })
          .eq('id', id)
          .select()
          .single();
      return Local.fromJson(res);
    } catch (e) {
      // Hoy los triggers de la 72 son BEFORE INSERT, así que editar no bloquea.
      // Se deja igualmente la traducción: si el servidor algún día limita el
      // UPDATE, el admin verá el mismo aviso claro que al crear.
      final limite = SuscripcionService.traducirLimitePlan(e, recurso: 'locales');
      if (limite != null) throw limite;
      rethrow;
    }
  }

  /// Activa/desactiva un local sin tocar el resto de sus campos. Al desactivarlo
  /// desaparecen también TODOS sus servicios del lado cliente: la regla es
  /// `flow._ls_disponible` (local AND servicio AND par).
  static Future<void> setLocalActivo({
    required int id,
    required bool activo,
  }) async {
    await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .update({'activo': activo})
        .eq('id', id);
  }

  static Future<void> deleteLocal(int id) async {
    await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .delete()
        .eq('id', id);
  }

  static Future<List<LocalServicio>> getLocalServicios({
    int? idServicio,
    int? idLocal,
    int? idEntidad,
    String? nombreServicio,
    String? nombreLocal,
    String? pais,
    String? provincia,

    /// false (default) = sólo lo visible y reservable para el cliente.
    /// true = todo, para la administración (ver y reactivar lo desactivado).
    bool incluirInactivos = false,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'cliente_obtener_servicios',
          params: {
            if (idLocal != null) 'p_id_local': idLocal,
            if (idServicio != null) 'p_id_servicio': idServicio,
            if (idEntidad != null) 'p_id_entidad': idEntidad,
            if (nombreLocal != null) 'p_nombre_local': nombreLocal,
            if (nombreServicio != null) 'p_nombre_servicio': nombreServicio,
            if (pais != null) 'p_pais': pais,
            if (provincia != null) 'p_provincia': provincia,
            if (incluirInactivos) 'p_incluir_inactivos': true,
          },
        );
    final list = res as List;
    return list
        .map((e) => LocalServicio.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<LocalServicio> getLocalServicio(int id) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .select(
          '*, app_dat_locales(*), app_dat_servicios(*, tipo_actividad:nom_tipo_actividad_servicio(*))',
        )
        .eq('id', id)
        .single();
    return LocalServicio.fromJson(res);
  }

  static Future<List<LocalServicio>> getLocalServiciosByEntidad(
    int idEntidad,
  ) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('local_servicio')
          .select('*, app_dat_locales(*), app_dat_servicios(*)')
          .eq('app_dat_locales.id_entidad', idEntidad);
      return (res as List)
          .where((e) => e['app_dat_locales'] != null)
          .map((e) => LocalServicio.fromJson(e))
          .toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<LocalServicio> createLocalServicio({
    required int idLocal,
    required int idServicio,
    bool permiteReservaDirecta = false,
    int cantidadDefault = 1,
    int cantidadMaxCapacidad = 1,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('local_servicio')
          .insert({
            'id_local': idLocal,
            'id_servicio': idServicio,
            'permite_reserva_directa': permiteReservaDirecta,
            'cantidad_default': cantidadDefault,
            'cantidad_max_capacidad': cantidadMaxCapacidad,
          })
          .select('*, app_dat_locales(*), app_dat_servicios(*)')
          .single();
      return LocalServicio.fromJson(res);
    } catch (e) {
      // Trigger `trg_limite_local_servicio`: el plan no permite más servicios
      // asociados a este local.
      final limite = SuscripcionService.traducirLimitePlan(
        e,
        recurso: 'servicios_por_local',
      );
      if (limite != null) throw limite;
      rethrow;
    }
  }

  static Future<LocalServicio> updateLocalServicio({
    required int id,
    bool? permiteReservaDirecta,
    int? cantidadDefault,
    int? cantidadMaxCapacidad,
    bool? activo,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('local_servicio')
          .update({
            if (permiteReservaDirecta != null)
              'permite_reserva_directa': permiteReservaDirecta,
            if (cantidadDefault != null) 'cantidad_default': cantidadDefault,
            if (cantidadMaxCapacidad != null)
              'cantidad_max_capacidad': cantidadMaxCapacidad,
            if (activo != null) 'activo': activo,
          })
          .eq('id', id)
          .select('*, app_dat_locales(*), app_dat_servicios(*)')
          .single();
      return LocalServicio.fromJson(res);
    } catch (e) {
      final limite = SuscripcionService.traducirLimitePlan(
        e,
        recurso: 'servicios_por_local',
      );
      if (limite != null) throw limite;
      rethrow;
    }
  }

  static Future<void> deleteLocalServicio(int id) async {
    await _supabase
        .schema(_schema)
        .from('local_servicio')
        .delete()
        .eq('id', id);
  }

  /// `campos_adicionales` y `permite_tercero` **tal cual están en la base**.
  ///
  /// Existe porque `admin_guardar_datos_servicio` **sobrescribe** los tres
  /// campos que recibe (`campos_adicionales`, `permite_tercero` y
  /// `config_precio`). Quien guarda desde un sitio que solo edita precios —la
  /// pestaña «Precios» de `LocalServicioAdminScreen`— tiene que devolver los
  /// datos adicionales sin tocarlos; si los regenerara desde el modelo
  /// ([Servicio.fromJson] → [CampoAdicional.toJson]) perdería cualquier clave
  /// del jsonb que el modelo no conozca. Se leen crudos y se devuelven igual.
  static Future<({List<Map<String, dynamic>> campos, bool permiteTercero})>
  getDatosServicioBrutos(int id) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .select('campos_adicionales, permite_tercero')
        .eq('id', id)
        .single();

    final crudo = res['campos_adicionales'];
    final campos = crudo is List
        ? crudo
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    return (
      campos: campos,
      permiteTercero: (res['permite_tercero'] as bool?) ?? false,
    );
  }

  /// Guarda los datos adicionales (campos configurables) y el flag de terceros
  /// de un servicio. RPC admin, valida pertenencia a la entidad.
  static Future<void> guardarDatosServicio({
    required String uuidUsuario,
    required int idServicio,
    required List<Map<String, dynamic>> campos,
    required bool permiteTercero,
    Map<String, dynamic>? configPrecio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_datos_servicio',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_servicio': idServicio,
            'p_campos': campos,
            'p_permite_tercero': permiteTercero,
            'p_config_precio': configPrecio ?? {},
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(
        json['error'] ?? 'No se pudieron guardar los datos del servicio',
      );
    }
  }

  /// Habilita/deshabilita la reserva directa de un local_servicio (RPC admin,
  /// valida pertenencia a la entidad).
  static Future<bool> setReservaDirecta({
    required String uuidUsuario,
    required int idLocalServicio,
    required bool permite,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_set_reserva_directa',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            'p_permite': permite,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cambiar la reserva directa');
    }
    return (json['data'] as Map<String, dynamic>)['permite_reserva_directa']
        as bool;
  }

  static Future<bool> existeLocalServicio({
    required int idLocal,
    required int idServicio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .select('id')
        .eq('id_local', idLocal)
        .eq('id_servicio', idServicio);
    return (res as List).isNotEmpty;
  }
}
