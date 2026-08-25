import 'dart:async';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'wifi_printer_service.dart';

/// Impresión de tickets de cocina (comandas).
///
/// El CONTENIDO lo arma el backend (`fn_ticket_comanda`), no esta clase: dos
/// apps y varias impresoras tendrían que formatear igual por separado. Aquí solo
/// se resuelve el transporte y el corte de papel.
///
/// A QUÉ IMPRESORA VA
/// ------------------
/// `app_dat_cocina.impresora` guarda el nombre o la IP configurada para esa
/// cocina. Se resuelve así, en orden:
///
///   1. Si el valor parece una IP (`192.168.1.50` o `192.168.1.50:9100`), se
///      conecta directo a ella.
///   2. Si no, se busca entre las impresoras guardadas por nombre.
///   3. Si la cocina no tiene impresora, se devuelve el texto para mostrarlo en
///      pantalla: en una cocina pequeña el KDS es la pantalla y no hay térmica.
///
/// El paso 3 no es un fallo: es el caso normal de una cocina sin hardware.
class ComandaTicketService {
  static final ComandaTicketService _instance =
      ComandaTicketService._internal();
  factory ComandaTicketService() => _instance;
  ComandaTicketService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final WiFiPrinterService _wifi = WiFiPrinterService();

  /// Trae el ticket ya formateado del backend.
  ///
  /// [ancho] son las columnas del papel: 32 para térmicas de 58 mm, 40–48 para
  /// las de 80 mm. El backend hace el recorte de líneas a esa medida.
  Future<TicketComanda?> obtenerTicket(int idComanda, {int ancho = 32}) async {
    try {
      final response = await _supabase.rpc(
        'fn_ticket_comanda',
        params: {'p_id_comanda': idComanda, 'p_ancho': ancho},
      );

      final mapa = response is Map
          ? Map<String, dynamic>.from(response)
          : (response is List && response.isNotEmpty && response.first is Map
              ? Map<String, dynamic>.from(response.first as Map)
              : null);

      if (mapa == null || mapa['status'] != 'success') {
        debugPrint('⚠️ fn_ticket_comanda: ${mapa?['message']}');
        return null;
      }

      return TicketComanda.fromJson(mapa);
    } catch (e) {
      debugPrint('❌ Error obteniendo ticket de comanda: $e');
      return null;
    }
  }

  /// Imprime el ticket en la impresora de su cocina.
  ///
  /// Devuelve el resultado con el texto dentro, así la UI puede mostrarlo en
  /// pantalla cuando no hay impresora o falla la conexión — el cocinero necesita
  /// leer la comanda igual.
  Future<ResultadoImpresionTicket> imprimir(
    int idComanda, {
    int ancho = 32,
  }) async {
    final ticket = await obtenerTicket(idComanda, ancho: ancho);

    if (ticket == null) {
      return const ResultadoImpresionTicket(
        estado: EstadoImpresion.errorDatos,
        mensaje: 'No se pudo leer la comanda',
      );
    }

    if (ticket.impresora == null || ticket.impresora!.trim().isEmpty) {
      return ResultadoImpresionTicket(
        estado: EstadoImpresion.sinImpresora,
        mensaje: '${ticket.cocina} no tiene impresora configurada',
        ticket: ticket,
      );
    }

    final destino = await _resolverDestino(ticket.impresora!);

    if (destino == null) {
      return ResultadoImpresionTicket(
        estado: EstadoImpresion.impresoraNoEncontrada,
        mensaje:
            'No se encontró la impresora "${ticket.impresora}" de ${ticket.cocina}',
        ticket: ticket,
      );
    }

    try {
      final conectada = await _wifi.connectToPrinter(
        destino.ip,
        port: destino.puerto,
      );

      if (!conectada) {
        return ResultadoImpresionTicket(
          estado: EstadoImpresion.errorConexion,
          mensaje: 'No se pudo conectar a ${destino.ip}:${destino.puerto}',
          ticket: ticket,
        );
      }

      final ok = await _enviar(ticket);

      // Se desconecta siempre: la impresora de cocina la comparten varios
      // dispositivos y dejar el socket abierto bloquea al siguiente.
      await _wifi.disconnect();

      return ResultadoImpresionTicket(
        estado: ok ? EstadoImpresion.impreso : EstadoImpresion.errorImpresion,
        mensaje: ok
            ? 'Comanda #${ticket.numero ?? ticket.idComanda} impresa en ${ticket.impresora}'
            : 'La impresora no aceptó el trabajo',
        ticket: ticket,
      );
    } catch (e) {
      await _wifi.disconnect();
      return ResultadoImpresionTicket(
        estado: EstadoImpresion.errorConexion,
        mensaje: 'Error de impresión: $e',
        ticket: ticket,
      );
    }
  }

  /// Convierte el texto del backend en bytes ESC/POS.
  ///
  /// La cabecera va en negrita y doble alto: el número de comanda es lo que el
  /// cocinero canta en voz alta y tiene que leerse de lejos.
  Future<bool> _enviar(TicketComanda ticket) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    final lineas = ticket.texto.split('\n');
    var bytes = <int>[];

    for (var i = 0; i < lineas.length; i++) {
      final linea = lineas[i];
      if (linea.isEmpty) continue;

      // Las 2 primeras líneas son el número de comanda y la cocina.
      final esCabecera = i < 2;
      // Las notas del comensal ('   >> SIN SAL') en negrita: es lo que provoca
      // devoluciones si se pasa por alto.
      final esNota = linea.trimLeft().startsWith('>>');

      bytes += generator.text(
        linea,
        styles: PosStyles(
          bold: esCabecera || esNota,
          height: esCabecera ? PosTextSize.size2 : PosTextSize.size1,
          width: esCabecera ? PosTextSize.size2 : PosTextSize.size1,
          align: esCabecera ? PosAlign.center : PosAlign.left,
        ),
      );
    }

    bytes += generator.emptyLines(2);
    bytes += generator.cut();

    return _wifi.imprimirBytesCrudos(bytes, 'Comanda #${ticket.numero}');
  }

  /// Resuelve el valor de `app_dat_cocina.impresora` a una IP y puerto.
  Future<_DestinoImpresora?> _resolverDestino(String impresora) async {
    final valor = impresora.trim();

    // Caso 1: es una IP, con o sin puerto.
    final partes = valor.split(':');
    final posibleIp = partes.first;
    if (_pareceIp(posibleIp)) {
      final puerto = partes.length > 1 ? int.tryParse(partes[1]) ?? 9100 : 9100;
      return _DestinoImpresora(ip: posibleIp, puerto: puerto);
    }

    // Caso 2: es un nombre. Se busca entre las guardadas.
    final guardadas = await _wifi.getSavedPrinters();
    for (final p in guardadas) {
      final nombre = (p['name'] ?? p['nombre'] ?? '').toString();
      if (nombre.toLowerCase() == valor.toLowerCase()) {
        final ip = p['ip']?.toString();
        if (ip == null || ip.isEmpty) continue;
        final puerto = (p['port'] as num?)?.toInt() ?? 9100;
        return _DestinoImpresora(ip: ip, puerto: puerto);
      }
    }

    return null;
  }

  static bool _pareceIp(String v) {
    final partes = v.split('.');
    if (partes.length != 4) return false;
    return partes.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }
}

class _DestinoImpresora {
  final String ip;
  final int puerto;
  const _DestinoImpresora({required this.ip, required this.puerto});
}

/// Ticket de cocina tal como lo devuelve `fn_ticket_comanda`.
class TicketComanda {
  final int idComanda;
  final int? numero;
  final int idCocina;
  final String cocina;

  /// Nombre o IP de la impresora de la cocina. `null` = mostrar en pantalla.
  final String? impresora;

  final String? mesa;
  final String? zona;
  final String? vendedor;
  final DateTime? createdAt;

  final List<Map<String, dynamic>> items;
  final int totalItems;
  final int ancho;

  /// Texto ya formateado a [ancho] columnas por el backend.
  final String texto;

  const TicketComanda({
    required this.idComanda,
    this.numero,
    required this.idCocina,
    required this.cocina,
    this.impresora,
    this.mesa,
    this.zona,
    this.vendedor,
    this.createdAt,
    this.items = const [],
    this.totalItems = 0,
    this.ancho = 32,
    required this.texto,
  });

  bool get tieneImpresora =>
      impresora != null && impresora!.trim().isNotEmpty;

  factory TicketComanda.fromJson(Map<String, dynamic> json) {
    final its = json['items'];
    return TicketComanda(
      idComanda: (json['id_comanda'] as num).toInt(),
      numero: (json['numero'] as num?)?.toInt(),
      idCocina: (json['id_cocina'] as num?)?.toInt() ?? 0,
      cocina: json['cocina'] as String? ?? 'Cocina',
      impresora: json['impresora'] as String?,
      mesa: json['mesa'] as String?,
      zona: json['zona'] as String?,
      vendedor: json['vendedor'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String? ?? ''),
      items: its is List
          ? its.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      ancho: (json['ancho'] as num?)?.toInt() ?? 32,
      texto: json['texto'] as String? ?? '',
    );
  }
}

enum EstadoImpresion {
  impreso,
  sinImpresora,
  impresoraNoEncontrada,
  errorConexion,
  errorImpresion,
  errorDatos,
}

class ResultadoImpresionTicket {
  final EstadoImpresion estado;
  final String mensaje;
  final TicketComanda? ticket;

  const ResultadoImpresionTicket({
    required this.estado,
    required this.mensaje,
    this.ticket,
  });

  bool get ok => estado == EstadoImpresion.impreso;

  /// Se puede mostrar en pantalla: hay texto aunque no se imprimiera.
  bool get puedeMostrarse => ticket != null && ticket!.texto.isNotEmpty;

  /// No es un fallo real: la cocina simplemente no tiene térmica.
  bool get esFaltaDeConfiguracion => estado == EstadoImpresion.sinImpresora;
}
