import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/expense.dart';
import '../utils/price_utils.dart';
import 'currency_service.dart';
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

/// Detecta el error de PostgREST cuando una RPC todavía no está aplicada en el
/// backend (PGRST202 / "could not find the function" / "schema cache"), para
/// caer a la variante vigente **sin** tratarlo como fallo de negocio. Mismo
/// criterio que `AutoSyncService._isRpcUnavailable` y
/// `MesaCuentaService._isRpcUnavailable`.
bool _isRpcUnavailable(Object error, String functionName) {
  final text = error.toString().toLowerCase();
  final fn = functionName.toLowerCase();
  return text.contains('pgrst202') ||
      text.contains('could not find the function') ||
      text.contains('schema cache') ||
      (text.contains('does not exist') && text.contains(fn));
}

class TurnoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Primera variante de una RPC que el backend tenga aplicada.
  ///
  /// [variantes] va de la más nueva a la vigente. Una variante ausente
  /// (PGRST202 / «could not find the function») pasa a la siguiente; cualquier
  /// otro error se propaga, porque no es un problema de despliegue. Es el
  /// **único** camino de fallback entre variantes: los llamadores solo declaran
  /// el orden, no repiten el bucle.
  static Future<Map<String, dynamic>?> _primeraRpcDisponible(
    List<String> variantes,
    Map<String, dynamic> params,
  ) async {
    for (final fn in variantes) {
      try {
        final response = await _supabase.rpc(fn, params: params);
        if (response is List && response.isNotEmpty) {
          return Map<String, dynamic>.from(response.first as Map);
        }
        if (response is Map) {
          return Map<String, dynamic>.from(response);
        }
        return null;
      } catch (e) {
        if (!_isRpcUnavailable(e, fn)) rethrow;
        print('⚠️ $fn no disponible ($e). Probando la variante siguiente.');
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getResumenTurnoKPI() async {
    try {
      // Get TPV and seller IDs from preferences
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();

      print('🔍 Calling fn_resumen_turno_kpi with:');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idSeller');

      // La app no acota el KPI por fechas: la variante vigente recibe NULL en
      // las dos (son sus defaults). La `_v2` no los tiene, así que hay que
      // nombrarlos; con NULL el resultado es el de siempre más el desglose por
      // divisa (FASE 4b).
      final response = await _primeraRpcDisponible(
        const ['fn_resumen_turno_kpi_v2', 'fn_resumen_turno_kpi'],
        {
          'p_id_tpv': idTpv,
          'p_id_vendedor': idSeller,
          'p_fecha_desde': null,
          'p_fecha_hasta': null,
        },
      );

      print('📊 RPC Response: $response');

      return response;
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

      // Mismas variantes que [getResumenTurnoPorId]: la `_v2` (con desglose)
      // cuando exista, la vigente si no.
      final porId = await _primeraRpcDisponible(
        const ['fn_resumen_turno_por_id_v2', 'fn_resumen_turno_por_id'],
        {'p_turno_id': idTurno},
      );
      if (porId != null) {
        print('✅ Resumen turno cerrado $idTurno vía fn_resumen_turno_por_id');
        return porId;
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

      // FASE 4b: la `_v2` añade `desglose_monedas` + `total_base` al final del
      // RETURNS TABLE. Si el backend todavía no la tiene aplicada se usa la
      // vigente, que devuelve las mismas columnas sin el desglose.
      final response = await _primeraRpcDisponible(
        const ['fn_resumen_turno_por_id_v2', 'fn_resumen_turno_por_id'],
        {'p_turno_id': idTurno},
      );

      print('📊 RPC Response: $response');

      return response;
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
          // Un turno con cierre ya solicitado (cola offline de otro
          // dispositivo) tampoco es vendible, aunque estado siga en 1.
          .isFilter('cierre_solicitado_at', null)
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
        // 3ra fuente: marcador local persistente de cierre (cubre el caso
        // en que la entrada de cola se perdió o no matcheó).
        if (serverId != null &&
            await _userPrefs.hasClosedTurnoMarker(serverId)) {
          print(
            '🔒 Turno $serverId abierto en servidor pero con marcador local '
            'de cierre — no se expone como abierto',
          );
          return null;
        }
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

  /// Marca en servidor `cierre_solicitado_at` en cuanto se encola un cierre.
  /// estado permanece 1 para que el sync del cierre completo siga siendo
  /// viable (fn_cerrar_turno_offline), pero ventas online y otros
  /// dispositivos ya no lo ven como vendible.
  /// Best-effort: si falla (sin red, columna aún no creada), el cierre
  /// completo queda en la cola local como antes.
  static Future<bool> marcarCierreSolicitadoEnServidor({
    required int serverTurnoId,
    required DateTime fechaCierre,
  }) async {
    try {
      await _supabase
          .from('app_dat_caja_turno')
          .update({
            'cierre_solicitado_at': fechaCierre.toUtc().toIso8601String(),
          })
          .eq('id', serverTurnoId)
          .eq('estado', 1)
          .isFilter('cierre_solicitado_at', null);
      print('🔖 cierre_solicitado_at marcado en turno $serverTurnoId');
      return true;
    } catch (e) {
      print(
        '⚠️ No se pudo marcar cierre_solicitado_at '
        'en turno $serverTurnoId: $e',
      );
      return false;
    }
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

  /// Registra un egreso parcial.
  ///
  /// [moneda] es la divisa en la que SALE el dinero (`montoEntrega` es su
  /// importe nativo). Va vacía en los llamadores que todavía no eligen divisa;
  /// entonces se usa la variante vigente y la base aplica su divisa por
  /// defecto, exactamente como antes.
  static Future<Map<String, dynamic>> registrarEgresoParcial({
    required int idTurno,
    required double montoEntrega,
    required String motivoEntrega,
    required String nombreAutoriza,
    required String nombreRecibe,
    int? idMedioPago,
    String? moneda,
  }) async {
    try {
      print('🔄 Calling registrar_egreso_parcial with:');
      print('  - ID Turno: $idTurno');
      print('  - Monto: $montoEntrega');
      print('  - Motivo: $motivoEntrega');
      print('  - Autoriza: $nombreAutoriza');
      print('  - Recibe: $nombreRecibe');
      print('  - ID Medio Pago: $idMedioPago');
      print('  - Moneda: $moneda');

      final divisa = (moneda ?? '').trim().toUpperCase();
      final params = _paramsEgresoParcial(
        idTurno: idTurno,
        montoEntrega: montoEntrega,
        motivoEntrega: motivoEntrega,
        nombreAutoriza: nombreAutoriza,
        nombreRecibe: nombreRecibe,
        idMedioPago: idMedioPago,
      );

      // Sin divisa explícita no hay nada que la v3 aporte sobre la v2.
      final response =
          divisa.isEmpty
              ? await _supabase.rpc(
                'registrar_egreso_parcial_v2',
                params: params,
              )
              : await _rpcEgresoParcialConDivisa(params, divisa);

      print('✅ registrar_egreso_parcial response: $response');

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

  /// Parámetros de `registrar_egreso_parcial_v2` — los mismos que espera la v3.
  ///
  /// Un solo mapa: la v2 y la v3 se diferencian únicamente en `p_moneda`, así
  /// que la caída de una a otra no puede desincronizar los argumentos.
  static Map<String, dynamic> _paramsEgresoParcial({
    required int idTurno,
    required double montoEntrega,
    required String motivoEntrega,
    required String nombreAutoriza,
    required String nombreRecibe,
    int? idMedioPago,
  }) => {
    'p_id_turno': idTurno,
    'p_monto_entrega': montoEntrega,
    'p_motivo_entrega': motivoEntrega,
    'p_nombre_autoriza': nombreAutoriza,
    'p_nombre_recibe': nombreRecibe,
    'p_id_medio_pago': idMedioPago,
  };

  /// `registrar_egreso_parcial_v3` (la v2 + `p_moneda`) con caída a la v2.
  ///
  /// La v3 envuelve a la v2 y solo ajusta la divisa de la fila recién creada.
  /// Si el backend todavía no la tiene aplicada, el egreso se registra igual
  /// con la v2 y la base le pone su divisa por defecto: se pierde el desglose,
  /// no la operación.
  static Future<dynamic> _rpcEgresoParcialConDivisa(
    Map<String, dynamic> params,
    String divisa,
  ) async {
    const fn = 'registrar_egreso_parcial_v3';
    try {
      return await _supabase.rpc(
        fn,
        params: {...params, 'p_moneda': divisa},
      );
    } catch (e) {
      if (!_isRpcUnavailable(e, fn)) rethrow;
      print(
        '⚠️ $fn no disponible ($e). Fallback a registrar_egreso_parcial_v2 '
        '(el egreso queda en la divisa por defecto de la base).',
      );
      return await _supabase.rpc('registrar_egreso_parcial_v2', params: params);
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

  /// Cierra el turno con el efectivo real contado **por divisa** y retorna un
  /// resultado tipado distinguiendo errores de red (caer a offline está OK) vs
  /// errores de negocio (mostrar mensaje y NO crear cierre offline).
  ///
  /// [efectivoRealPorDivisa] usa importes NATIVOS (`{'CUP': 1500, 'USD': 18}`),
  /// el mismo formato que devuelve el conteo de billetes: un solo mapa como
  /// fuente de verdad, sin que el código de divisa decida la aritmética.
  ///
  /// [efectivoReal] / [efectivoRealUsd] son el **adaptador legacy** para los
  /// llamadores que todavía no tienen el desglose: se pliegan al mismo mapa,
  /// de modo que exista un único camino de escritura.
  static Future<TurnoOperationResult> cerrarTurnoDetailed({
    Map<String, double>? efectivoRealPorDivisa,
    double? efectivoReal,
    double? efectivoRealUsd,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) async {
    try {
      final realPorDivisa =
          efectivoRealPorDivisa ??
          {
            PriceUtils.baseCurrency: efectivoReal ?? 0,
            if (efectivoRealUsd != null) 'USD': efectivoRealUsd,
          };
      final monedas = _monedasNormalizadas(realPorDivisa);

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

      print('🔄 Calling fn_cerrar_turno_tpv_monedas with:');
      print('  - ID TPV: $idTpvInt');
      print('  - Efectivo real por divisa: $monedas');
      print('  - Usuario (creado_por): $usuarioParaCierre');
      print('  - Productos: ${productos.length} items');
      print('  - Observaciones: $observaciones');

      final paramsMonedas = <String, dynamic>{
        'p_id_tpv': idTpvInt,
        'p_usuario': usuarioParaCierre,
        'p_productos': productos.isNotEmpty ? productos : null,
        'p_efectivo_real_por_moneda': monedas,
        'p_observaciones': observaciones,
      };
      // La variante vigente solo conoce base + USD: decide el respaldo.
      final usaVarianteUsd = _tieneDivisaExtra(monedas);

      dynamic response;
      try {
        response = await _supabase.rpc(
          'fn_cerrar_turno_tpv_monedas',
          params: paramsMonedas,
        );
      } catch (e) {
        if (!_isRpcUnavailable(e, 'fn_cerrar_turno_tpv_monedas')) rethrow;
        // GATE: la RPC multimoneda todavía no está aplicada. La variante
        // vigente solo entiende base + USD; con más divisas se pierde el
        // desglose que no cabe en su firma, pero el cierre no se bloquea.
        print('⚠️ fn_cerrar_turno_tpv_monedas no disponible ($e). Fallback.');
        response = await _supabase.rpc(
          usaVarianteUsd ? 'fn_cerrar_turno_tpv_usd' : 'fn_cerrar_turno_tpv',
          params: {
            'p_id_tpv': idTpvInt,
            'p_efectivo_real': monedas[PriceUtils.baseCurrency] ?? 0,
            if (usaVarianteUsd) 'p_efectivo_real_usd': monedas['USD'] ?? 0,
            'p_usuario': usuarioParaCierre,
            'p_productos': productos.isNotEmpty ? productos : null,
            'p_observaciones': observaciones,
          },
        );
      }

      print('✅ fn_cerrar_turno_tpv_monedas response: $response');

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

  /// Normaliza un mapa de importes por divisa: códigos en mayúsculas, sin
  /// entradas vacías y sumando duplicados. Es el formato que hablan las RPC
  /// `*_monedas` y el jsonb `{"CUP":1000,"USD":20}`.
  static Map<String, double> _monedasNormalizadas(
    Map<String, double> montos,
  ) {
    final limpio = <String, double>{};
    montos.forEach((codigo, monto) {
      final divisa = codigo.trim().toUpperCase();
      if (divisa.isEmpty) return;
      limpio[divisa] = (limpio[divisa] ?? 0) + monto;
    });
    return limpio;
  }

  /// ¿El mapa trae alguna divisa distinta de la moneda base? Decide la variante
  /// `_usd` del respaldo legacy, que solo conoce una divisa extra.
  static bool _tieneDivisaExtra(Map<String, double> montos) =>
      _monedasNormalizadas(montos).keys.any(
        (divisa) => divisa != PriceUtils.baseCurrency,
      );

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

  /// Registra la apertura del turno con el efectivo inicial **por divisa**.
  ///
  /// [efectivoInicialPorDivisa] son importes NATIVOS (`{'CUP': 1000, 'USD': 20}`).
  /// Se envía a `registrar_apertura_turno_monedas`; si esa RPC todavía no está
  /// aplicada en el backend se cae a las variantes vigentes
  /// (`registrar_apertura_turno_usd` / `registrar_apertura_turno_v3`).
  ///
  /// [efectivoInicial] / [efectivoInicialUsd] son el **adaptador legacy** para
  /// los llamadores que aún no tienen el desglose: se pliegan al mismo mapa.
  static Future<Map<String, dynamic>> registrarAperturaTurno({
    Map<String, double>? efectivoInicialPorDivisa,
    double? efectivoInicial,
    double? efectivoInicialUsd,
    required int idTpv,
    required int idVendedor,
    required String usuario,
    required bool manejaInventario,
    List<Map<String, dynamic>>? productos,
    String? observaciones,
  }) async {
    try {
      final inicialPorDivisa =
          efectivoInicialPorDivisa ??
          {
            PriceUtils.baseCurrency: efectivoInicial ?? 0,
            if (efectivoInicialUsd != null) 'USD': efectivoInicialUsd,
          };
      final monedas = _monedasNormalizadas(inicialPorDivisa);

      print('🔄 Calling registrar_apertura_turno_monedas with:');
      print('  - Efectivo inicial por divisa: $monedas');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idVendedor');
      print('  - Usuario: $usuario');
      print('  - Maneja inventario: $manejaInventario');
      print('  - Productos: ${productos?.length ?? 0} items');
      print('  - Observaciones: ${observaciones ?? "Sin observaciones"}');

      // La variante vigente solo conoce base + USD: decide el respaldo.
      final usaVarianteUsd = _tieneDivisaExtra(monedas);

      dynamic response;
      try {
        response = await _supabase.rpc(
          'registrar_apertura_turno_monedas',
          params: {
            'p_id_tpv': idTpv,
            'p_id_vendedor': idVendedor,
            'p_usuario': usuario,
            'p_maneja_inventario': manejaInventario,
            'p_productos': productos,
            'p_efectivo_inicial_por_moneda': monedas,
            'p_observaciones': observaciones,
          },
        );
      } catch (e) {
        if (!_isRpcUnavailable(e, 'registrar_apertura_turno_monedas')) rethrow;
        // GATE: la RPC multimoneda todavía no está aplicada. La variante
        // vigente solo entiende base + USD; con más divisas se pierde el
        // desglose que no cabe en su firma, pero la apertura no se bloquea.
        print('⚠️ registrar_apertura_turno_monedas no disponible ($e). Fallback.');
        response = await _supabase.rpc(
          usaVarianteUsd
              ? 'registrar_apertura_turno_usd'
              : 'registrar_apertura_turno_v3',
          params: {
            'p_efectivo_inicial': monedas[PriceUtils.baseCurrency] ?? 0,
            if (usaVarianteUsd) 'p_efectivo_inicial_usd': monedas['USD'] ?? 0,
            'p_id_tpv': idTpv,
            'p_id_vendedor': idVendedor,
            'p_usuario': usuario,
            'p_maneja_inventario': manejaInventario,
            'p_productos': productos,
            'p_observaciones': observaciones,
          },
        );
      }

      print('✅ registrar_apertura_turno_monedas response: $response');

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

  /// Divisas con las que trabaja la caja, en orden de presentación.
  ///
  /// Fuente principal: las monedas que acepta la tienda (`app_dat_tienda_moneda`).
  /// Si la consulta no está disponible (offline, caché fría) se usan las
  /// configuradas en la caché local. La moneda base siempre entra —es la unidad
  /// contable y donde se registran los egresos— y el respaldo final es el par
  /// fijo CUP + USD que usaba la app antes de la Fase 4.
  static Future<List<String>> divisasDeCaja() async {
    final divisas = <String>[];

    void agregar(Iterable<String> codigos) {
      for (final codigo in codigos) {
        final divisa = codigo.trim().toUpperCase();
        if (divisa.isNotEmpty && !divisas.contains(divisa)) {
          divisas.add(divisa);
        }
      }
    }

    try {
      final tienda = await CurrencyService.getMonedasTienda();
      agregar(tienda.map((m) => (m['codigo'] ?? '').toString()));
    } catch (e) {
      print('⚠️ divisasDeCaja: no se pudo leer la tienda ($e)');
    }

    if (divisas.isEmpty) {
      try {
        agregar(await _userPrefs.getMonedasDisponibles());
      } catch (e) {
        print('⚠️ divisasDeCaja: sin caché de monedas ($e)');
      }
    }

    if (divisas.isEmpty) return const [PriceUtils.baseCurrency, 'USD'];

    // La base primero: es la referencia del arqueo y de los egresos.
    divisas.remove(PriceUtils.baseCurrency);
    divisas.insert(0, PriceUtils.baseCurrency);
    return divisas;
  }

  /// Resumen diario de cierre multimoneda.
  ///
  /// `fn_resumen_diario_cierre_v4` añade `desglose_monedas` (importes nativos y
  /// en base por divisa). Si el backend todavía no la tiene aplicada se cae a
  /// `fn_resumen_diario_cierre_v2`, que devuelve las mismas columnas base.
  static Future<Map<String, dynamic>?> getResumenDiarioCierre({
    required int idTpv,
    required String? usuario,
  }) => _primeraRpcDisponible(
    const ['fn_resumen_diario_cierre_v4', 'fn_resumen_diario_cierre_v2'],
    {'id_tpv_param': idTpv, 'id_usuario_param': usuario},
  );

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
