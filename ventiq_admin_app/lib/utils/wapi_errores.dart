import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_envio_tanda.dart';

/// ============================================================================
///  Traductor de errores de WAPI/OpenWA a lenguaje para el dueño de la tienda.
///
///  EL PROBLEMA QUE RESUELVE
///    La bitácora guarda códigos crudos del servidor (`HTTP_409`,
///    `PRODUCT_TIMEOUT`, `TIMEOUT`...) y mensajes en inglés
///    ("Session is not connected. The WhatsApp client is not ready. (tras 3
///    intento(s))"). En la tarjeta se mostraba eso tal cual como "Error más
///    frecuente", así que el cliente final no sabía si el problema era suyo,
///    de WhatsApp o de la app, ni qué tenía que hacer.
///
///  QUÉ HACE
///    Convierte (código + mensaje) en un diagnóstico con:
///      · qué pasó, en una frase que se entiende;
///      · qué hacer ahora (o "nada, se reintenta solo");
///      · si hay que reconectar el bot antes de reintentar;
///      · si el botón Reintentar tiene sentido.
///    El texto técnico original NO se pierde: va en [WapiDiagnostico.detalle]
///    para el desplegable "Ver detalle técnico".
/// ============================================================================

/// Naturaleza del problema. Define prioridad, color y si reintentar sirve.
enum WapiDiagTipo {
  /// El bot no está conectado: hay que reconectar antes de reintentar.
  sesion,

  /// Fallo puntual de WhatsApp o del servidor: reintentar suele resolverlo.
  transitorio,

  /// Ese mensaje concreto no se puede entregar tal cual (destinatario,
  /// autorización...): reintentar daría el mismo resultado.
  definitivo,

  /// No es un fallo real (p. ej. el envío se cortó por tiempo).
  informativo,
}

@immutable
class WapiDiagnostico {
  final WapiDiagTipo tipo;

  /// Titular corto: "El bot se desconectó".
  final String titulo;

  /// Qué pasó, explicado.
  final String explicacion;

  /// Qué tiene que hacer el usuario (null = no hay nada que hacer).
  final String? queHacer;

  final IconData icono;
  final Color color;

  /// Requiere una acción sobre la sesión (reconectar) antes de reintentar.
  final bool requiereReconectar;

  /// ¿Reintentar el envío tiene sentido?
  final bool reintentable;

  /// Texto técnico original, para el detalle.
  final String? detalle;

  /// Cuántos mensajes comparten este diagnóstico (0 = no viene de una tanda).
  final int repeticiones;

  const WapiDiagnostico({
    required this.tipo,
    required this.titulo,
    required this.explicacion,
    this.queHacer,
    required this.icono,
    required this.color,
    this.requiereReconectar = false,
    this.reintentable = true,
    this.detalle,
    this.repeticiones = 0,
  });

  bool get esInformativo => tipo == WapiDiagTipo.informativo;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Utilidades de texto
// ─────────────────────────────────────────────────────────────────────────────

/// Quita el sufijo que añade el backend: "(tras 3 intento(s))".
String _sinSufijoIntentos(String s) =>
    s.replaceAll(RegExp(r'\s*\(tras \d+ intento\(?s?\)?\)\s*$'), '').trim();

bool _alguna(String texto, List<String> agujas) {
  final t = texto.toLowerCase();
  for (final a in agujas) {
    if (t.contains(a)) return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Diagnóstico principal
// ─────────────────────────────────────────────────────────────────────────────

/// Traduce un error de la bitácora. Nunca devuelve null: si no lo reconoce,
/// da un diagnóstico genérico pero accionable.
WapiDiagnostico diagnosticarError({
  String? codigo,
  String? mensaje,
  int repeticiones = 0,
}) {
  final code = (codigo ?? '').toUpperCase();
  final raw = _sinSufijoIntentos(mensaje ?? '');
  final detalle = <String>[
    if (code.isNotEmpty) code,
    if (raw.isNotEmpty) raw,
  ].join(' · ');

  WapiDiagnostico d(
    WapiDiagTipo tipo,
    String titulo,
    String explicacion,
    String? queHacer, {
    required IconData icono,
    required Color color,
    bool reconectar = false,
    bool reintentable = true,
  }) =>
      WapiDiagnostico(
        tipo: tipo,
        titulo: titulo,
        explicacion: explicacion,
        queHacer: queHacer,
        icono: icono,
        color: color,
        requiereReconectar: reconectar,
        reintentable: reintentable,
        detalle: detalle.isEmpty ? null : detalle,
        repeticiones: repeticiones,
      );

  // ── 1. La sesión del bot (el caso más frecuente y el más confuso) ─────
  if (_alguna(raw, [
        'not connected',
        'is not ready',
        'session is not',
        'not active',
        'start the session',
        'not found or not connected',
      ]) ||
      code == 'SESSION_DOWN' ||
      code == 'RECOVERY_FAILED' ||
      code == 'BROADCAST_SKIPPED_SESSION_DOWN') {
    return d(
      WapiDiagTipo.sesion,
      'El bot se desconectó',
      'WhatsApp cortó la sesión del bot, así que estos mensajes no llegaron a '
          'salir. No es culpa de los destinatarios ni de los productos.',
      'Reconecta el bot y vuelve a reintentar.',
      icono: Icons.link_off_rounded,
      color: AppColors.error,
      reconectar: true,
    );
  }

  // ── 2. WhatsApp recargando la página: pasa solo ───────────────────────
  if (_alguna(raw, ['re-injecting', 'reloading its page'])) {
    return d(
      WapiDiagTipo.transitorio,
      'WhatsApp estaba recargando',
      'Justo cuando se enviaba, WhatsApp Web se estaba recargando. Es algo '
          'pasajero y no depende de ti.',
      'Reintenta en unos segundos.',
      icono: Icons.autorenew_rounded,
      color: AppColors.warning,
    );
  }

  // ── 3. Autorización perdida: hay que volver a vincular ────────────────
  if (code == 'HTTP_401' || code == 'HTTP_403' ||
      _alguna(raw, ['unauthorized', 'forbidden', 'logged out'])) {
    return d(
      WapiDiagTipo.definitivo,
      'El bot perdió el acceso a WhatsApp',
      'La sesión del bot ya no está autorizada. Suele pasar cuando se cierra '
          'la sesión desde el teléfono o cuando cambia la contraseña.',
      'Vuelve a vincular el bot: elimínalo y crea uno nuevo para escanear el QR.',
      icono: Icons.no_accounts_rounded,
      color: AppColors.error,
      reconectar: true,
      reintentable: false,
    );
  }

  // ── 4. Errores del servidor del bot ──────────────────────────────────
  if (code == 'HTTP_500' || code == 'HTTP_502' || code == 'HTTP_503' ||
      code == 'HTTP_504' || _alguna(raw, ['internal server error'])) {
    return d(
      WapiDiagTipo.transitorio,
      'El servidor del bot falló',
      'El servidor del bot devolvió un error interno y el mensaje no se '
          'entregó. Normalmente se arregla reintentando.',
      'Reintenta. Si se repite muchas veces seguidas, avisa a soporte: '
          'suele ser que al servidor le falta memoria.',
      icono: Icons.cloud_off_rounded,
      color: AppColors.warning,
    );
  }

  // ── 5. Timeouts ──────────────────────────────────────────────────────
  if (code == 'PRODUCT_TIMEOUT') {
    return d(
      WapiDiagTipo.informativo,
      'Se cortó por tiempo (no fue un error)',
      'El envío de ese producto tardó más de lo permitido y se dejó para no '
          'arrastrar toda la difusión. WhatsApp no rechazó nada.',
      'Reintenta los que faltan cuando quieras.',
      icono: Icons.timer_off_outlined,
      color: AppColors.info,
    );
  }
  if (code == 'TIMEOUT' || _alguna(raw, ['no respondió', 'timed out', 'timeout'])) {
    return d(
      WapiDiagTipo.transitorio,
      'El servidor del bot tardó demasiado',
      'El bot no respondió a tiempo. El mensaje puede haber salido o no; '
          'por eso al reintentar no se duplica.',
      'Reintenta sin miedo.',
      icono: Icons.hourglass_disabled_rounded,
      color: AppColors.warning,
    );
  }

  // ── 6. Problemas de red entre la app y el servidor del bot ────────────
  if (code == 'NETWORK_ERROR' || code == 'SEND_ERROR') {
    return d(
      WapiDiagTipo.transitorio,
      'No se pudo contactar con el bot',
      'Hubo un problema de conexión al hablar con el servidor del bot.',
      'Reintenta en unos segundos.',
      icono: Icons.wifi_off_rounded,
      color: AppColors.warning,
    );
  }

  // ── 7. Límites de WhatsApp ───────────────────────────────────────────
  if (code == 'HTTP_429' || code == 'SEND_PACING_LIMITED' ||
      _alguna(raw, ['too many requests', 'rate limit', 'pacing'])) {
    return d(
      WapiDiagTipo.transitorio,
      'WhatsApp pidió esperar',
      'Se mandaron muchos mensajes seguidos y WhatsApp pidió una pausa para '
          'no bloquear la cuenta. El bot ya respeta esa espera.',
      'Reintenta en unos minutos. Si quieres, sube el tiempo entre mensajes '
          'en la programación.',
      icono: Icons.speed_rounded,
      color: AppColors.warning,
    );
  }

  // ── 8. Rechazo del mensaje a nivel de WhatsApp ───────────────────────
  if (code == 'ACK_ERROR' || code == 'MESSAGE_FAILED' ||
      _alguna(raw, ['rechazado', 'rejected'])) {
    return d(
      WapiDiagTipo.definitivo,
      'WhatsApp rechazó el mensaje',
      'El mensaje salió del bot pero WhatsApp lo devolvió como rechazado.',
      'Comprueba que el número o el grupo sigan existiendo y que el bot siga '
          'dentro del grupo.',
      icono: Icons.block_rounded,
      color: AppColors.error,
      reintentable: false,
    );
  }

  // ── 9. Descartado antes de enviar (sin imagen, URL no pública...) ────
  if (code == 'SKIPPED') {
    return d(
      WapiDiagTipo.definitivo,
      'Ese producto no se pudo preparar',
      raw.isNotEmpty
          ? raw.replaceFirst('No se puede enviar: ', '')
          : 'El producto no tiene una imagen pública con la que armar el mensaje.',
      'Revisa la imagen del producto en Inventario (tiene que ser una URL '
          'http/https pública) y reintenta.',
      icono: Icons.image_not_supported_outlined,
      color: AppColors.warning,
      reintentable: false,
    );
  }

  // ── 10. Genérico ─────────────────────────────────────────────────────
  return d(
    WapiDiagTipo.transitorio,
    'No se pudo entregar el mensaje',
    'WhatsApp no confirmó la entrega de este mensaje.',
    'Prueba a reintentar. Si sigue fallando, revisa que el destinatario exista.',
    icono: Icons.report_gmailerrorred_rounded,
    color: AppColors.warning,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Diagnóstico agregado de una tanda
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class WapiDiagnosticoTanda {
  /// Diagnóstico del error más repetido (null si no hubo fallos).
  final WapiDiagnostico? principal;

  /// Mensajes que compartían ese error.
  final int repeticiones;

  /// Total de mensajes fallidos de la tanda.
  final int totalFallidos;

  /// ¿Algún fallo pide reconectar el bot? (Decide si ofrecemos ese botón.)
  final bool hayQueReconectar;

  /// Códigos vistos, para el detalle técnico.
  final List<String> codigos;

  const WapiDiagnosticoTanda({
    this.principal,
    this.repeticiones = 0,
    this.totalFallidos = 0,
    this.hayQueReconectar = false,
    this.codigos = const [],
  });

  bool get hayDiagnostico => principal != null;
}

/// Agrupa los fallos de una tanda y traduce el más frecuente.
///
/// Se agrupa por CÓDIGO (no por mensaje completo) porque el mensaje lleva
/// ruido variable — "(tras 3 intento(s))", ids de sesión, etc. — que partía
/// en pedazos el mismo problema.
WapiDiagnosticoTanda diagnosticarTanda(WapiEnvioTanda tanda) {
  final fallidos =
      tanda.logs.where((l) => l.estado == WapiEnvioEstado.fallido).toList();
  if (fallidos.isEmpty) return const WapiDiagnosticoTanda();

  final porCodigo = <String, List<WapiEnvioLog>>{};
  for (final l in fallidos) {
    final clave = (l.errorCode ?? '').isNotEmpty
        ? l.errorCode!
        : _sinSufijoIntentos(l.errorMessage ?? 'desconocido');
    porCodigo.putIfAbsent(clave, () => []).add(l);
  }

  final orden = porCodigo.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  final top = orden.first;
  final ejemplo = top.value.first;

  var hayQueReconectar = false;
  final codigos = <String>[];
  for (final e in porCodigo.entries) {
    codigos.add(e.key);
    final diag = diagnosticarError(
      codigo: e.value.first.errorCode,
      mensaje: e.value.first.errorMessage,
    );
    if (diag.requiereReconectar) hayQueReconectar = true;
  }

  return WapiDiagnosticoTanda(
    principal: diagnosticarError(
      codigo: ejemplo.errorCode,
      mensaje: ejemplo.errorMessage,
      repeticiones: top.value.length,
    ),
    repeticiones: top.value.length,
    totalFallidos: fallidos.length,
    hayQueReconectar: hayQueReconectar,
    codigos: codigos,
  );
}

/// Traduce una excepción de la app (lo que lanza `_invoke` al recibir un
/// error del backend) al mismo lenguaje.
WapiDiagnostico diagnosticarExcepcion(Object e) {
  final texto = e.toString();
  return diagnosticarError(
    codigo: _codigoDesdeTexto(texto),
    mensaje: texto,
  );
}

String? _codigoDesdeTexto(String texto) {
  for (final c in [
    'NOT_CONNECTED',
    'RECOVERY_FAILED',
    'SESSION_DOWN',
    'NO_WEBHOOK_URL',
    'UNSIGNED_WEBHOOK',
  ]) {
    if (texto.contains(c)) return c;
  }
  final m = RegExp(r'HTTP[_ ](\d{3})').firstMatch(texto);
  if (m != null) return 'HTTP_${m.group(1)}';
  return null;
}