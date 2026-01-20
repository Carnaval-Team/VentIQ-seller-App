import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/expense.dart';
import 'payment_method_service.dart';

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

  static Future<Map<String, dynamic>?> getResumenTurnoPorId(int idTurno) async {
    //prueba
    try {
      // Probar la nueva función de resumen diario para cierre
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();
      if (idTpv != null) {
        print('🧪 Testing fn_resumen_diario_cierre with TPV: $idTpv');

        final resumenCierre = await _supabase.rpc(
          'fn_resumen_diario_cierre',
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
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Obteniendo turno offline...');
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
        print(
          '✅ Found open shift: ${turno['id']} for TPV: $idTpv, Seller: $idSeller',
        );
        return turno;
      }

      print('⚠️ No open shift found for TPV: $idTpv, Seller: $idSeller');
      // Fallback: intentar turno offline guardado
      final turnoOffline = await _userPrefs.getOfflineTurno();
      if (turnoOffline != null) {
        print('📱 Usando turno offline como fallback: ${turnoOffline['id']}');
        return turnoOffline;
      }
      return null;
    } catch (e) {
      print('❌ Error getting open shift: $e');
      // Fallback adicional en caso de error: consultar cache offline
      try {
        final turnoOffline = await _userPrefs.getOfflineTurno();
        if (turnoOffline != null) {
          print(
            '📱 Turno offline encontrado tras error: ${turnoOffline['id']}',
          );
          return turnoOffline;
        }
      } catch (_) {}
      return null;
    }
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

  static Future<bool> cerrarTurno({
    required double efectivoReal,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) async {
    try {
      // Get user UUID and TPV ID
      final userUuid = await _userPrefs.getUserId();
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];

      if (userUuid == null || idTpv == null) {
        print('❌ Missing user UUID or TPV ID');
        return false;
      }

      print('🔄 Calling fn_cerrar_turno_tpv with:');
      print('  - ID TPV: $idTpv');
      print('  - Efectivo real: $efectivoReal');
      print('  - Usuario: $userUuid');
      print('  - Productos: ${productos.length} items');
      print('  - Observaciones: $observaciones');

      final response = await _supabase.rpc(
        'fn_cerrar_turno_tpv',
        params: {
          'p_id_tpv': idTpv,
          'p_efectivo_real': efectivoReal,
          'p_usuario': userUuid,
          'p_productos': productos.isNotEmpty ? productos : null,
          'p_observaciones': observaciones,
        },
      );

      print('✅ fn_cerrar_turno_tpv response: $response');
      return response == true;
    } catch (e) {
      print('❌ Error in cerrarTurno: $e');
      return false;
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
        };
      }

      return {
        'success': false,
        'message': 'Respuesta inválida del servidor',
        'operacion_id': null,
      };
    } catch (e) {
      print('❌ Error in registrarAperturaTurno: $e');
      return {
        'success': false,
        'message': 'Error al registrar la apertura: $e',
        'operacion_id': null,
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
