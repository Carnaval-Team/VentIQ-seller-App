import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/expense.dart';
import 'payment_method_service.dart';

/// Tipo de fallo al ejecutar una operación de turno.
enum TurnoErrorKind {
  /// Falló la red o el servidor no respondió. Se puede caer a flujo offline.
  network,

  /// El backend respondió pero rechazó la operación (raise / regla de negocio).
  /// NO se debe caer a offline — el usuario debe ver el mensaje y corregir.
  business,

  /// Error inesperado (programación / datos faltantes).
  unknown,
}

/// Resultado tipado de operaciones de turno (apertura/cierre).
class TurnoOperationResult {
  final bool success;
  final String? message;
  final TurnoErrorKind? errorKind;
  final dynamic data;

  const TurnoOperationResult.success({this.message, this.data})
      : success = true,
        errorKind = null;

  const TurnoOperationResult.failure({
    required this.message,
    required this.errorKind,
    this.data,
  }) : success = false;

  bool get isNetworkError => errorKind == TurnoErrorKind.network;
  bool get isBusinessError => errorKind == TurnoErrorKind.business;
}

/// Determina si una excepción corresponde a un error de red.
bool _isNetworkException(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('timeoutexception') ||
      msg.contains('clientexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('connection closed') ||
      msg.contains('connection reset') ||
      msg.contains('network is unreachable');
}

/// Extrae un mensaje legible de un PostgrestException o error genérico.
String _extractErrorMessage(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  if (error is AuthException) {
    return error.message;
  }
  return error.toString();
}

class TurnoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  static Future<Map<String, dynamic>?> getResumenTurnoKPI() async {
    try {
      // Get TPV and seller IDs from preferences
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();

      print('🔍 Calling fn_resumen_turno_kpi with:');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idSeller');

      // aqui van las dos variables
      final response = await _supabase.rpc(
        'fn_resumen_turno_kpi',
        params: {'p_id_tpv': idTpv, 'p_id_vendedor': idSeller},
      );

      print('📊 RPC Response: $response');

      if (response != null && response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting turno KPI: $e');
      return null;
    }
  }

  /// Resumen del último turno **cerrado** del TPV/vendedor (para apertura).
  /// Si el último turno sigue abierto, busca el cerrado más reciente en BD.
  static Future<Map<String, dynamic>?> getResumenUltimoTurnoCerrado() async {
    try {
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpvRaw = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();
      final idTpv =
          idTpvRaw is int
              ? idTpvRaw
              : (idTpvRaw is num
                  ? idTpvRaw.toInt()
                  : int.tryParse('$idTpvRaw'));

      if (idTpv == null || idSeller == null) {
        print('⚠️ getResumenUltimoTurnoCerrado: falta TPV o vendedor');
        return null;
      }

      // 1) KPI del último turno; si ya está cerrado, usarlo.
      final kpi = await getResumenTurnoKPI();
      if (kpi != null) {
        final estado = kpi['estado_turno'];
        final isOpen = estado == 1 || estado == '1';
        if (!isOpen) {
          print('✅ Resumen último turno cerrado vía KPI id=${kpi['turno_id']}');
          return kpi;
        }
        print(
          'ℹ️ KPI devolvió turno abierto (id=${kpi['turno_id']}); '
          'buscando último cerrado en BD',
        );
      }

      // 2) Último turno cerrado explícitamente.
      final closedRow =
          await _supabase
              .from('app_dat_caja_turno')
              .select('id')
              .eq('id_tpv', idTpv)
              .eq('id_vendedor', idSeller)
              .eq('estado', 2)
              .order('fecha_cierre', ascending: false, nullsFirst: false)
              .limit(1)
              .maybeSingle();

      final closedId = closedRow?['id'];
      final idTurno =
          closedId is int
              ? closedId
              : (closedId is num
                  ? closedId.toInt()
                  : int.tryParse('$closedId'));
      if (idTurno == null) {
        print('ℹ️ No hay turno cerrado previo para TPV $idTpv');
        return null;
      }

      final porId = await _supabase.rpc(
        'fn_resumen_turno_por_id',
        params: {'p_turno_id': idTurno},
      );
      if (porId != null && porId is List && porId.isNotEmpty) {
        print('✅ Resumen turno cerrado $idTurno vía fn_resumen_turno_por_id');
        return Map<String, dynamic>.from(porId.first as Map);
      }

      // Fallback mínimo desde la fila del turno.
      final full =
          await _supabase
              .from('app_dat_caja_turno')
              .select(
                'id, fecha_apertura, fecha_cierre, estado, '
                'efectivo_inicial, efectivo_real, diferencia',
              )
              .eq('id', idTurno)
              .maybeSingle();
      if (full == null) return null;
      return {
        'turno_id': full['id'],
        'fecha_apertura': full['fecha_apertura'],
        'fecha_cierre': full['fecha_cierre'],
        'estado_turno': full['estado'],
        'efectivo_inicial': full['efectivo_inicial'],
        'efectivo_real': full['efectivo_real'],
        'diferencia_efectivo': full['diferencia'],
        'ventas_totales': 0,
        'productos_vendidos': 0,
        'ticket_promedio': 0,
      };
    } catch (e) {
      print('❌ Error getResumenUltimoTurnoCerrado: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getResumenTurnoPorId(int idTurno) async {
    //prueba
    try {
      // Probar la nueva función de resumen diario para cierre
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();
      if (idTpv != null) {
        print('🧪 Testing fn_resumen_diario_cierre_v2 with TPV: $idTpv');

        // FASE 3 presentaciones: v2 (la original redondeaba productos_vendidos).
        final resumenCierre = await _supabase.rpc(
          'fn_resumen_diario_cierre_v2',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print('📈 Resumen Cierre Response: $resumenCierre');

        if (resumenCierre != null &&
            resumenCierre is List &&
            resumenCierre.isNotEmpty) {
          final data = resumenCierre[0];
          print('💰 Ventas Totales: ${data['ventas_totales']}');
          print('💵 Efectivo Inicial: ${data['efectivo_inicial']}');
          print('💸 Efectivo Real: ${data['efectivo_real']}');
          print('📊 Productos Vendidos: ${data['productos_vendidos']}');
          print('🎯 Ticket Promedio: ${data['ticket_promedio']}');
          print('📋 Operaciones Totales: ${data['operaciones_totales']}');
          print('⚖️ Estado Conciliación: ${data['conciliacion_estado']}');
          print('🕐 Horas Transcurridas: ${data['horas_transcurridas']}');
        }
      }
      print('🔍 Calling fn_resumen_turno_por_id with ID: $idTurno');

      final response = await _supabase.rpc(
        'fn_resumen_turno_por_id',
        params: {'p_turno_id': idTurno},
      );

      print('📊 RPC Response: $response');

      if (response != null && response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting turno summary by ID: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getTurnoAbierto() async {
    try {
      // Full-offline / modo offline: solo cola local.
      final useLocal = await _userPrefs.shouldUseLocalData();
      if (useLocal) {
        print('🔌 Modo local - Obteniendo turno offline...');
        final turnoOffline = await _userPrefs.getOfflineTurno();
        if (turnoOffline != null) {
          print('📱 Turno offline encontrado: ${turnoOffline['id']}');
          return turnoOffline;
        } else {
          print('⚠️ No hay turno offline abierto');
          return null;
        }
      }

      // Modo online - consultar base de datos
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();

      if (idTpv == null) {
        print('❌ Missing TPV ID');
        return null;
      }

      if (idSeller == null) {
        print('❌ Missing Seller ID');
        return null;
      }

      print(
        '🔍 Searching for open shift with TPV ID: $idTpv and Seller ID: $idSeller',
      );

      final response = await _supabase
          .from('app_dat_caja_turno')
          .select('*')
          .eq('id_tpv', idTpv)
          .eq('id_vendedor', idSeller)
          .eq('estado', 1)
          .order('fecha_apertura', ascending: false, nullsFirst: false)
          .limit(1);

      print('📊 Open shift query response: $response');

      if (response.isNotEmpty) {
        final turno = response.first as Map<String, dynamic>;
        final serverId = _parseTurnoId(turno['id']);
        // Si el cierre ya está en cola local, NO tratarlo como turno
        // abierto operativo (el servidor puede seguir en estado=1 hasta
        // que el sync de cierre termine).
        final localCierre = await _userPrefs.findClosedPendingMatching(
          serverId: serverId,
          idTpv: idTpv is int ? idTpv : int.tryParse('$idTpv'),
          idVendedor: idSeller is int ? idSeller : int.tryParse('$idSeller'),
        );
        if (localCierre != null) {
          print(
            '🔒 Turno $serverId abierto en servidor pero con cierre local '
            'pendiente (${localCierre['local_id']}) — no se expone como abierto',
          );
          if (serverId != null) {
            final lid = localCierre['local_id']?.toString();
            if (lid != null) {
              await _userPrefs.setOfflineTurnoServerId(lid, serverId);
            }
          }
          return null;
        }
        print(
          '✅ Found open shift: ${turno['id']} for TPV: $idTpv, Seller: $idSeller',
        );
        return turno;
      }

      print('⚠️ No open shift found for TPV: $idTpv, Seller: $idSeller');

      // Fallback solo si el turno local aún NO tiene id en servidor.
      // Si ya tenía server_id pero el servidor no reporta abierto, la cache
      // quedó obsoleta (p.ej. tras cierre online) y debe limpiarse.
      final turnoOffline = await _userPrefs.getOfflineTurno();
      if (turnoOffline != null) {
        final serverId =
            turnoOffline['server_id_turno'] ??
            (turnoOffline['id'] is int ? turnoOffline['id'] : null);
        if (serverId == null) {
          print(
            '📱 Usando turno offline sin server_id: ${turnoOffline['local_id'] ?? turnoOffline['id']}',
          );
          return turnoOffline;
        }
        print(
          '🧹 Cache offline obsoleta (server_id=$serverId); '
          'servidor sin turno abierto — limpiando',
        );
        await _userPrefs.clearOfflineTurno();
      }

      return null;
    } catch (e) {
      print('❌ Error getting open shift: $e');
      // Solo en error de red: intentar cache offline real (sin server_id).
      try {
        final turnoOffline = await _userPrefs.getOfflineTurno();
        if (turnoOffline != null) {
          final serverId =
              turnoOffline['server_id_turno'] ??
              (turnoOffline['id'] is int ? turnoOffline['id'] : null);
          if (serverId == null) {
            print(
              '📱 Turno offline (sin server_id) tras error de red: '
              '${turnoOffline['local_id'] ?? turnoOffline['id']}',
            );
            return turnoOffline;
          }
        }
      } catch (_) {}
      return null;
    }
  }

  static int? _parseTurnoId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  /// UUID `creado_por` del turno abierto en servidor (requerido por
  /// `fn_cerrar_turno_tpv`, que filtra por ese campo — no por el vendedor).
  static Future<String?> _resolveCreadoPorForOpenTpv(int idTpv) async {
    try {
      final turnoRow =
          await _supabase
              .from('app_dat_caja_turno')
              .select('creado_por')
              .eq('id_tpv', idTpv)
              .eq('estado', 1)
              .order('fecha_apertura', ascending: false, nullsFirst: false)
              .limit(1)
              .maybeSingle();
      final creadoPor = turnoRow?['creado_por']?.toString();
      if (creadoPor != null && creadoPor.isNotEmpty) return creadoPor;
    } catch (e) {
      print('⚠️ No se pudo resolver creado_por del turno TPV $idTpv: $e');
    }
    return null;
  }

  /// Turno para mostrar en UI cuando puede haber cierre reciente en cache.
  static Future<Map<String, dynamic>?> getTurnoForDisplay() async {
    // Preferir cierre local pendiente/sincronizado antes que un "abierto"
    // fantasma del servidor.
    final closedLocal =
        await _userPrefs.getLastClosedOrSyncedTurnoForDisplay();
    if (closedLocal != null) {
      final status = closedLocal['status']?.toString();
      if (status == UserPreferencesService.offlineTurnoStatusClosedPending ||
          status == UserPreferencesService.offlineTurnoStatusSynced ||
          closedLocal['cerrado_local'] == true ||
          closedLocal['cerrado_online'] == true) {
        // Si además hay un open local genuino, ese gana.
        final openLocal = await _userPrefs.getOfflineTurno();
        if (openLocal == null) {
          return closedLocal;
        }
      }
    }

    var turno = await getTurnoAbierto();
    if (turno == null) {
      return closedLocal;
    }

    final resumen = await _userPrefs.getTurnoResumenCache();
    if (resumen?['cerrado_online'] == true ||
        resumen?['cerrado_local'] == true) {
      final closedId = resumen!['id'] ?? resumen['server_id_turno'];
      final openId = turno['id'] ?? turno['server_id_turno'];
      if (closedId != null &&
          openId != null &&
          closedId.toString() == openId.toString()) {
        await _userPrefs.clearOfflineTurno();
        turno = await _userPrefs.getLastClosedOrSyncedTurnoForDisplay();
      }
    }

    return turno;
  }

  static Future<Map<String, dynamic>> registrarEgresoParcial({
    required int idTurno,
    required double montoEntrega,
    required String motivoEntrega,
    required String nombreAutoriza,
    required String nombreRecibe,
    int? idMedioPago,
  }) async {
    try {
      print('🔄 Calling registrar_egreso_parcial_v2 with:');
      print('  - ID Turno: $idTurno');
      print('  - Monto: $montoEntrega');
      print('  - Motivo: $motivoEntrega');
      print('  - Autoriza: $nombreAutoriza');
      print('  - Recibe: $nombreRecibe');
      print('  - ID Medio Pago: $idMedioPago');

      final response = await _supabase.rpc(
        'registrar_egreso_parcial_v2',
        params: {
          'p_id_turno': idTurno,
          'p_monto_entrega': montoEntrega,
          'p_motivo_entrega': motivoEntrega,
          'p_nombre_autoriza': nombreAutoriza,
          'p_nombre_recibe': nombreRecibe,
          'p_id_medio_pago': idMedioPago,
        },
      );

      print('✅ registrar_egreso_parcial_v2 response: $response');

      if (response != null && response is Map<String, dynamic>) {
        return response;
      }

      return {
        'success': false,
        'message': 'Respuesta inválida del servidor',
        'egreso_id': null,
      };
    } catch (e) {
      print('❌ Error in registrarEgresoParcial: $e');
      return {
        'success': false,
        'message': 'Error al registrar el egreso: $e',
        'egreso_id': null,
      };
    }
  }

  /// Versión legacy: retorna sólo bool. Usar [cerrarTurnoDetailed] para
  /// distinguir errores de red vs errores de negocio.
  static Future<bool> cerrarTurno({
    required double efectivoReal,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) async {
    final result = await cerrarTurnoDetailed(
      efectivoReal: efectivoReal,
      productos: productos,
      observaciones: observaciones,
    );
    return result.success;
  }

  /// Cierra el turno y retorna un resultado tipado distinguiendo
  /// errores de red (caer a offline está OK) vs errores de negocio
  /// (mostrar mensaje y NO crear cierre offline).
  static Future<TurnoOperationResult> cerrarTurnoDetailed({
    required double efectivoReal,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) async {
    try {
      final userUuid = await _userPrefs.getUserId();
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];

      if (userUuid == null || idTpv == null) {
        print('❌ Missing user UUID or TPV ID');
        return const TurnoOperationResult.failure(
          message: 'Faltan datos del usuario o TPV',
          errorKind: TurnoErrorKind.unknown,
        );
      }

      final idTpvInt =
          idTpv is int ? idTpv : int.tryParse(idTpv.toString());
      if (idTpvInt == null) {
        return const TurnoOperationResult.failure(
          message: 'TPV inválido',
          errorKind: TurnoErrorKind.unknown,
        );
      }

      // fn_cerrar_turno_tpv filtra por ct.creado_por = p_usuario, no por
      // el UUID del vendedor ni el usuario de sesión genérico.
      final creadoPor = await _resolveCreadoPorForOpenTpv(idTpvInt);
      final usuarioParaCierre = creadoPor ?? userUuid;

      print('🔄 Calling fn_cerrar_turno_tpv with:');
      print('  - ID TPV: $idTpvInt');
      print('  - Efectivo real: $efectivoReal');
      print('  - Usuario (creado_por): $usuarioParaCierre');
      print('  - Productos: ${productos.length} items');
      print('  - Observaciones: $observaciones');

      final response = await _supabase.rpc(
        'fn_cerrar_turno_tpv',
        params: {
          'p_id_tpv': idTpvInt,
          'p_efectivo_real': efectivoReal,
          'p_usuario': usuarioParaCierre,
          'p_productos': productos.isNotEmpty ? productos : null,
          'p_observaciones': observaciones,
        },
      );

      print('✅ fn_cerrar_turno_tpv response: $response');

      if (response == true) {
        await _userPrefs.clearOfflineTurno();
        return const TurnoOperationResult.success();
      }

      // El backend respondió pero no con true → tratarlo como error de negocio.
      return TurnoOperationResult.failure(
        message: 'El servidor rechazó el cierre del turno',
        errorKind: TurnoErrorKind.business,
        data: response,
      );
    } catch (e) {
      print('❌ Error in cerrarTurno: $e');
      if (_isNetworkException(e)) {
        return const TurnoOperationResult.failure(
          message: 'Sin conexión al servidor',
          errorKind: TurnoErrorKind.network,
        );
      }
      return TurnoOperationResult.failure(
        message: _extractErrorMessage(e),
        errorKind: TurnoErrorKind.business,
      );
    }
  }

  static Future<List<Expense>> getEgresosPorTurno(int idTurno) async {
    try {
      print('🔍 Calling egresos_por_turno with ID: $idTurno');

      final response = await _supabase.rpc(
        'egresos_por_turno',
        params: {'p_id_turno': idTurno},
      );

      print('📊 Expenses RPC Response: $response');

      if (response != null && response is List) {
        return response
            .map<Expense>(
              (item) => Expense.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }

      return [];
    } catch (e) {
      print('❌ Error getting expenses for turno $idTurno: $e');
      return [];
    }
  }

  static Future<List<Expense>> getEgresosForCurrentShift() async {
    try {
      // Get current open shift
      final turnoAbierto = await getTurnoAbierto();

      if (turnoAbierto == null) {
        print('⚠️ No open shift found for expenses');
        return [];
      }

      final idTurno = turnoAbierto['id'] as int;
      return await getEgresosPorTurno(idTurno);
    } catch (e) {
      print('❌ Error getting expenses for current shift: $e');
      return [];
    }
  }

  /// Obtiene los egresos del turno actual enriquecidos con información de métodos de pago
  static Future<List<Expense>> getEgresosEnriquecidos() async {
    try {
      // Get expenses for current shift
      final expenses = await getEgresosForCurrentShift();

      if (expenses.isEmpty) {
        return expenses;
      }

      // Get payment methods to enrich the data
      final paymentMethods =
          await PaymentMethodService.getActivePaymentMethods();

      // Create maps for quick lookup
      final paymentMethodMap = <int, String>{};
      final paymentMethodDigitalMap = <int, bool>{};

      for (final method in paymentMethods) {
        paymentMethodMap[method.id] = method.denominacion;
        paymentMethodDigitalMap[method.id] = method.esDigital;
      }

      // Enrich expenses with payment method names and digital flag
      final enrichedExpenses = <Expense>[];

      for (final expense in expenses) {
        if (expense.idMedioPago != null &&
            paymentMethodMap.containsKey(expense.idMedioPago)) {
          final methodName = paymentMethodMap[expense.idMedioPago!];
          final isDigital =
              paymentMethodDigitalMap[expense.idMedioPago!] ?? false;

          // Create enriched expense with payment method data
          final enrichedExpense = expense.copyWith(
            medioPago: methodName,
            esDigital: isDigital,
          );

          enrichedExpenses.add(enrichedExpense);

          print(
            '💰 Expense ${expense.idEgreso} enriched with payment method: $methodName (Digital: $isDigital)',
          );
        } else {
          // Add expense without enrichment if no payment method found
          enrichedExpenses.add(expense);
          print(
            '⚠️ Expense ${expense.idEgreso} has no valid payment method (ID: ${expense.idMedioPago})',
          );
        }
      }

      return enrichedExpenses;
    } catch (e) {
      print('❌ Error getting enriched expenses: $e');
      return [];
    }
  }

  /// Registra apertura de turno usando la función v3 con manejo de inventario y observaciones
  static Future<Map<String, dynamic>> registrarAperturaTurno({
    required double efectivoInicial,
    required int idTpv,
    required int idVendedor,
    required String usuario,
    required bool manejaInventario,
    List<Map<String, dynamic>>? productos,
    String? observaciones,
  }) async {
    try {
      print('🔄 Calling registrar_apertura_turno_v3 with:');
      print('  - Efectivo inicial: $efectivoInicial');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idVendedor');
      print('  - Usuario: $usuario');
      print('  - Maneja inventario: $manejaInventario');
      print('  - Productos: ${productos?.length ?? 0} items');
      print('  - Observaciones: ${observaciones ?? "Sin observaciones"}');

      final response = await _supabase.rpc(
        'registrar_apertura_turno_v3',
        params: {
          'p_efectivo_inicial': efectivoInicial,
          'p_id_tpv': idTpv,
          'p_id_vendedor': idVendedor,
          'p_usuario': usuario,
          'p_maneja_inventario': manejaInventario,
          'p_productos': productos,
          'p_observaciones': observaciones,
        },
      );

      print('✅ registrar_apertura_turno_v3 response: $response');

      if (response != null) {
        return {
          'success': true,
          'message': 'Apertura registrada exitosamente',
          'operacion_id': response,
          'errorKind': null,
        };
      }

      return {
        'success': false,
        'message': 'Respuesta inválida del servidor',
        'operacion_id': null,
        'errorKind': TurnoErrorKind.business,
      };
    } catch (e) {
      print('❌ Error in registrarAperturaTurno: $e');
      final isNetwork = _isNetworkException(e);
      return {
        'success': false,
        'message': isNetwork
            ? 'Sin conexión al servidor'
            : _extractErrorMessage(e),
        'operacion_id': null,
        'errorKind': isNetwork
            ? TurnoErrorKind.network
            : TurnoErrorKind.business,
      };
    }
  }

  /// Valida si el vendedor tiene un turno abierto (online u offline)
  static Future<bool> hasOpenShift() async {
    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Verificando turno offline...');
        final hasOfflineTurno = await _userPrefs.hasOfflineTurnoAbierto();
        print('📱 Turno offline encontrado: $hasOfflineTurno');
        return hasOfflineTurno;
      } else {
        print('🌐 Modo online - Verificando turno en base de datos...');
        final turnoAbierto = await getTurnoAbierto();
        final hasOnlineTurno = turnoAbierto != null;
        print('💾 Turno online encontrado: $hasOnlineTurno');
        return hasOnlineTurno;
      }
    } catch (e) {
      print('❌ Error checking open shift: $e');
      return false;
    }
  }
}
