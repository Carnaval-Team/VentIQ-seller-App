import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bank_sms_payment.dart';
import '../utils/bank_sms_parser.dart';

/// Clave de SharedPreferences con los SMS de pago detectados y todavía no
/// conciliados con una venta.
///
/// Se usa SharedPreferences (y no SQLite) porque el handler de background
/// corre en un **isolate distinto** sin acceso a la instancia de
/// [OfflineDatabaseService] del isolate principal. SharedPreferences sí
/// funciona en ambos.
const String _kPendingSmsKey = 'bank_sms_pending_payments';

/// Handler de SMS en background.
///
/// Debe ser una función **top-level** y llevar `@pragma('vm:entry-point')`
/// para que el tree-shaking de AOT no la elimine. Corre en un isolate propio,
/// así que solo puede persistir el SMS; la conciliación contra la venta la
/// hace el isolate principal al volver a foreground.
///
/// Android mata operaciones largas en background: aquí solo se parsea y se
/// guarda.
@pragma('vm:entry-point')
Future<void> bankSmsBackgroundHandler(SmsMessage message) async {
  try {
    if (!BankSmsParser.isKnownSender(message.address)) return;
    final body = message.body;
    if (body == null || body.isEmpty) return;

    final payment = BankSmsParser.parse(
      body,
      receivedAt: message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : DateTime.now(),
    );
    if (payment == null) return;

    await BankSmsService.appendPendingPayment(payment);
    debugPrint('📩 [bg] Pago SMS almacenado: $payment');
  } catch (e) {
    debugPrint('❌ [bg] Error procesando SMS: $e');
  }
}

/// Escucha los SMS de confirmación de pago del corto `PAGOxMOVIL` y los deja
/// disponibles para conciliar con una venta.
///
/// Ciclo de vida esperado: se arranca **antes** de navegar al checkout (para
/// no perder el SMS de un cliente que transfiere mientras el cajero arma la
/// orden) y se detiene al confirmar la venta o tras 20 min de inactividad.
///
/// La confirmación es **informativa**: si no llega el SMS, la venta se cierra
/// igual. Nada en esta clase debe bloquear el flujo de cobro.
///
/// Solo funciona en Android. En iOS/Windows/Web todos los métodos son no-ops
/// y [isSupported] devuelve `false`.
class BankSmsService {
  static final BankSmsService _instance = BankSmsService._internal();
  factory BankSmsService() => _instance;
  BankSmsService._internal();

  /// Ventana de inactividad tras la cual se deja de escuchar.
  static const Duration inactivityTimeout = Duration(minutes: 20);

  /// Antigüedad máxima de un SMS del buffer. Más viejo que esto se descarta:
  /// no puede corresponder a la venta en curso.
  static const Duration maxPaymentAge = Duration(minutes: 30);

  /// Tolerancia al comparar el monto del SMS con el total de la venta.
  static const double amountTolerance = 0.01;

  /// Instancia del plugin, creada **al primer uso**.
  ///
  /// No se inicializa en el constructor a propósito: `Telephony.instance`
  /// registra un `MethodCallHandler` al construirse, lo que lanza si el
  /// binder de plataforma no está listo o si la plataforma no es Android.
  /// Como este servicio es un singleton que se referencia también en
  /// Windows/web, construirlo debe ser inocuo.
  Telephony? _telephonyInstance;
  Telephony get _telephony => _telephonyInstance ??= Telephony.instance;

  bool _listening = false;
  Timer? _inactivityTimer;
  DateTime? _sessionStartedAt;

  /// Emite cada pago detectado en foreground, para que la UI reaccione.
  final StreamController<BankSmsPayment> _paymentController =
      StreamController<BankSmsPayment>.broadcast();
  Stream<BankSmsPayment> get onPayment => _paymentController.stream;

  bool get isListening => _listening;

  /// Momento en que arrancó la sesión de escucha actual.
  DateTime? get sessionStartedAt => _sessionStartedAt;

  /// Solo Android puede leer SMS. iOS lo prohíbe de raíz.
  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Pide los permisos de SMS. Devuelve `false` si el usuario los niega o si
  /// la plataforma no los soporta.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      final granted = await _telephony.requestSmsPermissions;
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ Error pidiendo permisos de SMS: $e');
      return false;
    }
  }

  /// Arranca la escucha. Idempotente: llamarlo dos veces solo reinicia el
  /// temporizador de inactividad.
  ///
  /// Devuelve `false` si no hay soporte o permisos — el llamador debe seguir
  /// con el cobro normal, sin confirmación automática.
  Future<bool> startListening() async {
    if (!isSupported) {
      debugPrint('ℹ️ Escucha de SMS no soportada en esta plataforma');
      return false;
    }

    if (_listening) {
      _resetInactivityTimer();
      return true;
    }

    final granted = await requestPermissions();
    if (!granted) {
      debugPrint('⚠️ Permisos de SMS denegados — sin confirmación automática');
      return false;
    }

    try {
      _telephony.listenIncomingSms(
        onNewMessage: _handleForegroundSms,
        onBackgroundMessage: bankSmsBackgroundHandler,
      );
      _listening = true;
      _sessionStartedAt = DateTime.now();
      _resetInactivityTimer();
      debugPrint('👂 Escuchando SMS de PAGOxMOVIL');
      return true;
    } catch (e) {
      debugPrint('❌ No se pudo iniciar la escucha de SMS: $e');
      return false;
    }
  }

  /// Detiene la escucha y limpia el temporizador.
  ///
  /// No borra el buffer: un SMS puede haber llegado justo antes de cerrar y
  /// aún servir para conciliar.
  void stopListening() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _listening = false;
    _sessionStartedAt = null;
    debugPrint('🛑 Escucha de SMS detenida');
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, () {
      debugPrint(
        '⏰ ${inactivityTimeout.inMinutes} min sin actividad — '
        'deteniendo escucha de SMS',
      );
      stopListening();
    });
  }

  Future<void> _handleForegroundSms(SmsMessage message) async {
    if (!BankSmsParser.isKnownSender(message.address)) return;
    final body = message.body;
    if (body == null || body.isEmpty) return;

    final payment = BankSmsParser.parse(
      body,
      receivedAt: message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : DateTime.now(),
    );
    if (payment == null) {
      if (BankSmsParser.looksLikePartialPayment(body)) {
        debugPrint('📨 Fragmento de SMS de pago incompleto — se ignora');
      }
      return;
    }

    debugPrint('📩 Pago SMS recibido: $payment');
    await appendPendingPayment(payment);
    _resetInactivityTimer();
    if (!_paymentController.isClosed) {
      _paymentController.add(payment);
    }
  }

  // --------------------------------------------------------------------------
  // Buffer de pagos pendientes de conciliar
  // --------------------------------------------------------------------------

  /// Guarda un pago en el buffer, deduplicando por `nroTransaccionBanco`.
  ///
  /// `static` porque también la usa el isolate de background.
  static Future<void> appendPendingPayment(BankSmsPayment payment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Releer justo antes de escribir: el isolate de background y el
      // principal pueden tocar la lista casi a la vez.
      await prefs.reload();
      final list = _decodePayments(prefs.getStringList(_kPendingSmsKey));

      if (list.any(
        (p) => p.nroTransaccionBanco == payment.nroTransaccionBanco,
      )) {
        return;
      }

      list.add(payment);
      _pruneOld(list);
      await prefs.setStringList(
        _kPendingSmsKey,
        list.map((p) => jsonEncode(p.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('❌ Error guardando pago SMS pendiente: $e');
    }
  }

  /// Pagos detectados y aún no asociados a una venta, del más reciente al más
  /// antiguo. Descarta los más viejos que [maxPaymentAge].
  Future<List<BankSmsPayment>> getPendingPayments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = _decodePayments(prefs.getStringList(_kPendingSmsKey));
      _pruneOld(list);
      list.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return list;
    } catch (e) {
      debugPrint('❌ Error leyendo pagos SMS pendientes: $e');
      return [];
    }
  }

  /// Saca un pago del buffer, tras haberlo asociado a una venta.
  Future<void> removePendingPayment(String nroTransaccionBanco) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = _decodePayments(prefs.getStringList(_kPendingSmsKey))
        ..removeWhere((p) => p.nroTransaccionBanco == nroTransaccionBanco);
      await prefs.setStringList(
        _kPendingSmsKey,
        list.map((p) => jsonEncode(p.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('❌ Error removiendo pago SMS: $e');
    }
  }

  Future<void> clearPendingPayments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingSmsKey);
    } catch (e) {
      debugPrint('❌ Error limpiando pagos SMS: $e');
    }
  }

  static List<BankSmsPayment> _decodePayments(List<String>? raw) {
    if (raw == null || raw.isEmpty) return [];
    final out = <BankSmsPayment>[];
    for (final s in raw) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          final p = BankSmsPayment.fromJson(decoded);
          if (p.nroTransaccionBanco.isNotEmpty) out.add(p);
        }
      } catch (_) {
        // Entrada corrupta: se descarta en silencio.
      }
    }
    return out;
  }

  static void _pruneOld(List<BankSmsPayment> list) {
    final cutoff = DateTime.now().subtract(maxPaymentAge);
    list.removeWhere((p) => p.receivedAt.isBefore(cutoff));
  }

  // --------------------------------------------------------------------------
  // Conciliación
  // --------------------------------------------------------------------------

  /// Busca en el buffer un pago cuyo monto coincida con [expectedAmount].
  ///
  /// Ante varios candidatos devuelve el más reciente. Si dos ventas del mismo
  /// monto compiten, el `nroTransaccionBanco` con índice unique en BD impide
  /// que el mismo SMS confirme ambas.
  Future<BankSmsPayment?> findMatchingPayment(double expectedAmount) async {
    final pending = await getPendingPayments();
    for (final p in pending) {
      if ((p.monto - expectedAmount).abs() <= amountTolerance) return p;
    }
    return null;
  }

  /// Relee el inbox y reincorpora al buffer los pagos de los últimos
  /// [within] minutos.
  ///
  /// Es el respaldo para cuando Android mata el proceso y el broadcast
  /// receiver no llega a dispararse: al volver a foreground recuperamos lo que
  /// se perdió. Requiere permiso `READ_SMS`.
  Future<int> reconcileFromInbox({
    Duration within = maxPaymentAge,
  }) async {
    if (!isSupported) return 0;

    try {
      final granted = await requestPermissions();
      if (!granted) return 0;

      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );

      final cutoff = DateTime.now().subtract(within);
      // Snapshot de lo ya conocido, para contar solo lo realmente nuevo sin
      // releer prefs en cada iteración.
      final known = (await getPendingPayments())
          .map((p) => p.nroTransaccionBanco)
          .toSet();
      var recovered = 0;

      for (final m in messages) {
        if (!BankSmsParser.isKnownSender(m.address)) continue;
        final body = m.body;
        if (body == null || body.isEmpty) continue;

        final receivedAt = m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : null;
        if (receivedAt == null || receivedAt.isBefore(cutoff)) continue;

        final payment = BankSmsParser.parse(body, receivedAt: receivedAt);
        if (payment == null) continue;
        if (!known.add(payment.nroTransaccionBanco)) continue;

        await appendPendingPayment(payment);
        recovered++;
      }

      if (recovered > 0) {
        debugPrint('🔄 $recovered pago(s) recuperado(s) del inbox');
      }
      return recovered;
    } catch (e) {
      debugPrint('⚠️ Error reconciliando desde inbox: $e');
      return 0;
    }
  }

  void dispose() {
    stopListening();
    _paymentController.close();
  }
}
