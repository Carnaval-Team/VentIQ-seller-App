import 'package:supabase_flutter/supabase_flutter.dart';

import '../money/venta_v1_envio.dart';
import '../utils/uuid_generator.dart';
import 'user_preferences_service.dart';

/// Alta y cobro producto-v1. La clave se guarda antes del primer envío.
/// Un fallo no abre el registro ni el cobro anteriores.
class VentaV1Cliente {
  static Future<Map<String, dynamic>> enviar({
    required String orderId,
    required Map<String, dynamic> orderData,
    required List<Map<String, dynamic>> lineas,
    required int idTienda,
    required int idTpv,
    required int idVendedor,
    required String origen,
    required UserPreferencesService prefs,
  }) async {
    if (orderId.isEmpty) {
      return {
        'success': false,
        'retenida': true,
        'error': 'La orden no tiene identidad. No se envio.',
      };
    }
    var intento = await prefs.leerIntentoVentaV1(orderId);
    final guardada = orderData['solicitud_v1'];
    if (intento == null && guardada is Map) {
      intento = Map<String, dynamic>.from(guardada);
    }
    if (intento == null) {
      final clientUuid = _uuid(orderData['client_uuid']) ?? UuidGenerator.v4();
      final pagoUuid = _uuid(orderData['client_uuid_pago']) ?? UuidGenerator.v4();
      final politica = await prefs.getPoliticaMoneda() ?? <String, dynamic>{};
      final venta = SolicitudV1.venta(
        clientUuid: clientUuid,
        idTienda: idTienda,
        idTpv: idTpv,
        idVendedor: idVendedor,
        politica: politica,
        lineas: lineas,
        origen: origen,
      );
      if (venta == null) {
        return {
          'success': false,
          'retenida': true,
          'error':
              'Falta la constancia de la politica. La orden se conserva.',
        };
      }
      final grupos = CheckoutV1.agrupar(VentaV1Lineas.desdeMapas(lineas));
      final pago = grupos.isEmpty
          ? null
          : SolicitudV1.pagos(
              clientUuid: clientUuid,
              pagoUuid: pagoUuid,
              grupos: grupos,
            );
      intento = {
        'venta': venta,
        'pago': pago,
        'client_uuid': clientUuid,
        'client_uuid_pago': pagoUuid,
      };
      orderData['client_uuid'] = clientUuid;
      orderData['client_uuid_pago'] = pagoUuid;
      orderData['solicitud_v1'] = intento;
      await prefs.guardarIntentoVentaV1(orderId, intento);
      await prefs.patchPendingOrder(orderId, {
        'client_uuid': clientUuid,
        'client_uuid_pago': pagoUuid,
        'solicitud_v1': intento,
      });
    }

    final venta = intento['venta'];
    if (venta is! Map) {
      return {
        'success': false,
        'retenida': true,
        'error': 'La solicitud guardada no se puede reenviar.',
      };
    }
    try {
      final ventaResp = await Supabase.instance.client.rpc(
        'fn_m01_registrar_venta_v1',
        params: {'p_solicitud': Map<String, dynamic>.from(venta)},
      );
      final op = _operacion(ventaResp);
      if (op == null) {
        return {
          'success': false,
          'retenida': true,
          'error': 'La alta v1 no devolvio la operacion. No se uso el registro anterior.',
        };
      }
      orderData['_operation_id'] = op;
      final pago = intento['pago'];
      if (pago == null) {
        return {'success': true, 'operationId': op};
      }
      if (pago is! Map) {
        return {
          'success': false,
          'retenida': true,
          'operationId': op,
          'error': 'El cobro guardado no se puede reenviar.',
        };
      }
      await Supabase.instance.client.rpc(
        'fn_m01_registrar_pagos_v1',
        params: {'p_solicitud': Map<String, dynamic>.from(pago)},
      );
      return {'success': true, 'operationId': op};
    } catch (error) {
      return {
        'success': false,
        'retenida': true,
        'error': error.toString(),
      };
    }
  }

  static String? _uuid(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return null;
    return text;
  }

  static int? _operacion(dynamic response) {
    if (response is! Map) return null;
    if (response['status'] != 'success') return null;
    final id = response['id_operacion'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }
}
