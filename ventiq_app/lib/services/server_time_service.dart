import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

/// Servicio que calcula y persiste el desfasaje (offset) entre el reloj del
/// dispositivo y la hora real del servidor, para que las fechas guardadas al
/// operar offline (apertura de turno, cierre de turno, creación de órdenes)
/// coincidan con la hora del servidor aunque el reloj del dispositivo esté
/// mal configurado o adelantado/atrasado.
///
/// Estrategia: cada vez que hay una respuesta HTTP del servidor (Supabase),
/// se lee el header `Date` (estándar HTTP, presente en toda respuesta) y se
/// compara contra `DateTime.now()` tomado justo al recibir la respuesta. La
/// diferencia se guarda como offset y se persiste para poder seguir
/// corrigiendo las fechas aunque la app se reinicie sin conexión.
class ServerTimeService {
  static final ServerTimeService _instance = ServerTimeService._internal();
  factory ServerTimeService() => _instance;
  ServerTimeService._internal();

  static const String _offsetMsKey = 'server_time_offset_ms';
  static const String _lastSyncKey = 'server_time_offset_synced_at';

  Duration _offset = Duration.zero;
  DateTime? _lastSyncedAt;
  bool _loadedFromDisk = false;

  /// Desfasaje actual conocido (servidor - dispositivo). Positivo si el
  /// servidor va adelantado respecto al dispositivo.
  Duration get offset => _offset;

  /// Última vez que se pudo medir el desfasaje contra el servidor.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Hora "corregida" equivalente a la del servidor, calculada a partir del
  /// reloj local del dispositivo + el último offset conocido. Si nunca se ha
  /// podido sincronizar, equivale a `DateTime.now()`.
  DateTime now() => DateTime.now().add(_offset);

  /// Carga el offset persistido (llamar una vez al iniciar la app).
  Future<void> loadPersistedOffset() async {
    if (_loadedFromDisk) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_offsetMsKey);
      final syncedAtStr = prefs.getString(_lastSyncKey);
      if (ms != null) {
        _offset = Duration(milliseconds: ms);
      }
      if (syncedAtStr != null) {
        _lastSyncedAt = DateTime.tryParse(syncedAtStr);
      }
      _loadedFromDisk = true;
      print(
        '🕒 ServerTimeService: offset persistido cargado '
        '(${_offset.inSeconds}s, último sync=$_lastSyncedAt)',
      );
    } catch (e) {
      print('⚠️ ServerTimeService: no se pudo cargar offset persistido: $e');
    }
  }

  /// Actualiza el offset a partir de los headers HTTP de una respuesta del
  /// servidor (usa el header `Date`). No lanza si el header no existe.
  Future<void> syncFromHeaders(Map<String, String> headers) async {
    final dateHeader = headers['date'] ?? headers['Date'];
    if (dateHeader == null) return;
    try {
      final serverTime = HttpDate.parse(dateHeader).toLocal();
      final localNow = DateTime.now();
      final newOffset = serverTime.difference(localNow);
      await _applyOffset(newOffset);
    } catch (e) {
      print('⚠️ ServerTimeService: no se pudo parsear header Date: $e');
    }
  }

  /// Fuerza una medición directa contra el servidor (petición liviana). Útil
  /// al iniciar la app o al recuperar conectividad, sin depender de que otro
  /// servicio dispare una request primero.
  Future<bool> refreshFromNetwork() async {
    try {
      final response = await http
          .get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/health'),
            headers: {'apikey': SupabaseConfig.supabaseAnonKey},
          )
          .timeout(const Duration(seconds: 8));
      await syncFromHeaders(response.headers);
      return true;
    } catch (e) {
      print('⚠️ ServerTimeService: no se pudo refrescar hora del servidor: $e');
      return false;
    }
  }

  Future<void> _applyOffset(Duration newOffset) async {
    _offset = newOffset;
    _lastSyncedAt = DateTime.now();
    print(
      '🕒 ServerTimeService: offset actualizado = ${_offset.inSeconds}s '
      '(servidor ${_offset.isNegative ? "atrás" : "adelante"} del dispositivo)',
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_offsetMsKey, _offset.inMilliseconds);
      await prefs.setString(_lastSyncKey, _lastSyncedAt!.toIso8601String());
    } catch (e) {
      print('⚠️ ServerTimeService: no se pudo persistir offset: $e');
    }
  }
}
