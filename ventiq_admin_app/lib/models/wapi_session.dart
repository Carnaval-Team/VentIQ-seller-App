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
        return 'Inicializando';
      case WapiStatus.scanQr:
        return 'Escanea QR';
      case WapiStatus.connecting:
        return 'Conectando';
      case WapiStatus.connected:
        return 'Conectado';
      case WapiStatus.disconnected:
        return 'Desconectado';
      case WapiStatus.failed:
        return 'Falló';
      case WapiStatus.unknown:
        return 'Desconocido';
    }
  }

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
    );
  }
}

/// Resultado de `wapi-session-status`.
class WapiSessionStatus {
  final int idSesion;
  final WapiStatus status;
  final String? phoneNumber;
  final String? qrImage;
  final String? qrCode;

  WapiSessionStatus({
    required this.idSesion,
    required this.status,
    this.phoneNumber,
    this.qrImage,
    this.qrCode,
  });

  factory WapiSessionStatus.fromJson(Map<String, dynamic> j) {
    final qr = j['qr'] as Map<String, dynamic>?;
    return WapiSessionStatus(
      idSesion: (j['id_sesion'] as num).toInt(),
      status: WapiStatus.fromString(j['status'] as String?),
      phoneNumber: j['phone_number'] as String?,
      qrImage: qr?['image'] as String?,
      qrCode: qr?['code'] as String?,
    );
  }
}
