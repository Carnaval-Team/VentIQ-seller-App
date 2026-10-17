import 'package:flutter/material.dart';

/// Estado de una sesión WhatsApp (alineado con la API WAPI).
enum WapiStatus {
  initializing,
  scanQr,
  connecting,
  connected,
  disconnected,
  failed,
  unknown;

  static WapiStatus fromString(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'INITIALIZING':
        return WapiStatus.initializing;
      case 'SCAN_QR':
        return WapiStatus.scanQr;
      case 'CONNECTING':
        return WapiStatus.connecting;
      case 'CONNECTED':
        return WapiStatus.connected;
      case 'DISCONNECTED':
        return WapiStatus.disconnected;
      case 'FAILED':
        return WapiStatus.failed;
      default:
        return WapiStatus.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case WapiStatus.initializing:
        return 'INITIALIZING';
      case WapiStatus.scanQr:
        return 'SCAN_QR';
      case WapiStatus.connecting:
        return 'CONNECTING';
      case WapiStatus.connected:
        return 'CONNECTED';
      case WapiStatus.disconnected:
        return 'DISCONNECTED';
      case WapiStatus.failed:
        return 'FAILED';
      case WapiStatus.unknown:
        return 'UNKNOWN';
    }
  }

  String get label {
    switch (this) {
      case WapiStatus.initializing:
        return 'Iniciando';
      case WapiStatus.scanQr:
        return 'Falta escanear el QR';
      case WapiStatus.connecting:
        return 'Conectando';
      case WapiStatus.connected:
        return 'Conectado';
      case WapiStatus.disconnected:
        return 'Desconectado';
      case WapiStatus.failed:
        return 'Falló';
      case WapiStatus.unknown:
        return 'Sin datos';
    }
  }

  /// Qué significa este estado para el negocio — una frase, sin tecnicismos.
  /// Se muestra bajo el nombre del bot para que nadie tenga que interpretar
  /// un color.
  String get detalle {
    switch (this) {
      case WapiStatus.connected:
        return 'Todo listo: los envíos salen solos.';
      case WapiStatus.scanQr:
        return 'Falta vincular el teléfono: sin eso no se envía nada.';
      case WapiStatus.connecting:
        return 'Se está conectando al teléfono. Espera unos segundos.';
      case WapiStatus.initializing:
        return 'Arrancando el bot en el servidor.';
      case WapiStatus.disconnected:
        return 'El bot no puede enviar mensajes ahora mismo.';
      case WapiStatus.failed:
        return 'El bot se detuvo y necesita que lo reconectes.';
      case WapiStatus.unknown:
        return 'Sin información del bot. Pulsa «Actualizar».';
    }
  }

  /// Acción que resuelve el estado, para el botón principal de la tarjeta:
  /// `'qr'` (vincular), `'restart'` (reconectar) o `null` (no hace falta nada).
  String? get accionSugerida {
    switch (this) {
      case WapiStatus.connected:
        return null;
      case WapiStatus.scanQr:
        return 'qr';
      case WapiStatus.initializing:
      case WapiStatus.connecting:
        return null; // se resuelve solo; mejor no ofrecer botón que confunda
      case WapiStatus.disconnected:
      case WapiStatus.failed:
      case WapiStatus.unknown:
        return 'restart';
    }
  }

  /// ¿Este estado impide enviar? (Lo usa el banner de la pantalla.)
  bool get bloqueaEnvios => this != WapiStatus.connected;

  /// ¿Necesita que el usuario haga algo a mano?
  bool get requiereAccion =>
      this == WapiStatus.scanQr ||
      this == WapiStatus.disconnected ||
      this == WapiStatus.failed ||
      this == WapiStatus.unknown;

  Color get color {
    switch (this) {
      case WapiStatus.connected:
        return const Color(0xFF10B981);
      case WapiStatus.scanQr:
      case WapiStatus.connecting:
      case WapiStatus.initializing:
        return const Color(0xFFF59E0B);
      case WapiStatus.disconnected:
      case WapiStatus.failed:
        return const Color(0xFFEF4444);
      case WapiStatus.unknown:
        return const Color(0xFF9CA3AF);
    }
  }

  IconData get icon {
    switch (this) {
      case WapiStatus.connected:
        return Icons.check_circle;
      case WapiStatus.scanQr:
        return Icons.qr_code_2;
      case WapiStatus.connecting:
      case WapiStatus.initializing:
        return Icons.hourglass_top;
      case WapiStatus.disconnected:
        return Icons.power_off;
      case WapiStatus.failed:
        return Icons.error_outline;
      case WapiStatus.unknown:
        return Icons.help_outline;
    }
  }
}

class WapiSession {
  final int id;
  final int idTienda;
  final String nombre;
  final String wapiSessionId;
  final WapiStatus status;
  final String? phoneNumber;
  final String? lastQrImage;
  final DateTime lastStatusAt;
  final DateTime createdAt;

  /// Status CRUDO que reporta OpenWA (`ready`, `qr_ready`, `action_required`,
  /// `failed`...). Útil para diagnosticar: el normalizado colapsa matices.
  final String? rawStatus;

  /// Último problema registrado por el watchdog / los envíos.
  final String? lastErrorCode;
  final String? lastErrorMessage;

  /// Recuperaciones automáticas intentadas y si el watchdog sigue vigilando.
  final int recoveryAttempts;
  final bool watchdogEnabled;

  WapiSession({
    required this.id,
    required this.idTienda,
    required this.nombre,
    required this.wapiSessionId,
    required this.status,
    this.phoneNumber,
    this.lastQrImage,
    required this.lastStatusAt,
    required this.createdAt,
    this.rawStatus,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.recoveryAttempts = 0,
    this.watchdogEnabled = true,
  });

  factory WapiSession.fromJson(Map<String, dynamic> j) {
    return WapiSession(
      id: (j['id'] as num).toInt(),
      idTienda: (j['id_tienda'] as num).toInt(),
      nombre: (j['nombre'] ?? '') as String,
      wapiSessionId: (j['wapi_session_id'] ?? '') as String,
      status: WapiStatus.fromString(j['status'] as String?),
      phoneNumber: j['phone_number'] as String?,
      lastQrImage: j['last_qr_image'] as String?,
      lastStatusAt:
          DateTime.tryParse(j['last_status_at'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      rawStatus: j['raw_status'] as String?,
      lastErrorCode: j['last_error_code'] as String?,
      lastErrorMessage: j['last_error_message'] as String?,
      recoveryAttempts: (j['recovery_attempts'] as num?)?.toInt() ?? 0,
      // Si la columna no existiera (proyecto sin migrar), asumimos activo.
      watchdogEnabled: (j['watchdog_enabled'] as bool?) ?? true,
    );
  }

  /// ¿El estado guardado es viejo? Si la app no ha sondeado en >10 min puede
  /// estar mostrando una foto desactualizada: conviene decirlo en vez de
  /// afirmar que el bot está bien.
  bool esEstadoViejo(DateTime ahora) =>
      ahora.difference(lastStatusAt).inMinutes > 10;

  /// ¿El bot fue vinculado alguna vez? Sin teléfono no hay credenciales y
  /// cualquier mensaje fallará hasta escanear el QR.
  bool get estaVinculado =>
      (phoneNumber != null && phoneNumber!.trim().isNotEmpty) ||
      status == WapiStatus.connected;
}

/// Resultado de `wapi-session-status`.
class WapiSessionStatus {
  final int idSesion;
  final WapiStatus status;
  final String? phoneNumber;
  final String? qrImage;
  final String? qrCode;

  /// El backend marca `true` cuando OpenWA pide `action_required`: la sesión
  /// necesita que se confirme el aviso "What's new" en el teléfono **y**
  /// después un reinicio. Sin ese dato, la UI mostraría un QR que no resuelve.
  final bool requiereConfirmacionManual;

  WapiSessionStatus({
    required this.idSesion,
    required this.status,
    this.phoneNumber,
    this.qrImage,
    this.qrCode,
    this.requiereConfirmacionManual = false,
  });

  factory WapiSessionStatus.fromJson(Map<String, dynamic> j) {
    final qr = j['qr'] as Map<String, dynamic>?;
    return WapiSessionStatus(
      idSesion: (j['id_sesion'] as num).toInt(),
      status: WapiStatus.fromString(j['status'] as String?),
      phoneNumber: j['phone_number'] as String?,
      qrImage: qr?['image'] as String?,
      qrCode: qr?['code'] as String?,
      requiereConfirmacionManual:
          (j['requiere_confirmacion_manual'] as bool?) ?? false,
    );
  }
}
