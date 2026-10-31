import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/cobro.dart';

/// Contrato entre la app y los RPC del pago por adelantado (migración 62).
///
/// Los `jsonb_build_object` de la migración son la fuente: estos tests fijan las
/// claves exactas que devuelve cada RPC con fixtures copiados del SQL, de modo
/// que un renombrado en la base rompa aquí y no como una pantalla llena de «—».
///
/// Son modelos puros: no hay Supabase.
void main() {
  // ── flow.cliente_cobro_info ──────────────────────────────────────────────

  group('CobroInfo', () {
    test('parsea la respuesta completa del RPC', () {
      final info = CobroInfo.fromJson({
        'disponible': true,
        'id_entidad': 7,
        'moneda': 'CUP',
        'horas_vigencia': 48,
        'whatsapp_verificacion': '5355555555',
        'soporte_whatsapp': '5354590207',
        'instrucciones': 'Paga a este número y mándame el comprobante.',
        'titulo': 'Salón Ana',
        'numero_proveedor': '4055432',
      });

      expect(info.disponible, isTrue);
      expect(info.idEntidad, 7);
      expect(info.moneda, 'CUP');
      expect(info.horasVigencia, 48);
      expect(info.whatsappVerificacion, '5355555555');
      expect(info.soporteWhatsapp, '5354590207');
      expect(info.instrucciones, contains('comprobante'));
      expect(info.titulo, 'Salón Ana');
      expect(info.numeroProveedor, '4055432');
      expect(info.resumenVigencia, 'Tienes 2 días para pagar');
    });

    test('sin cobro activo el RPC solo manda disponible=false', () {
      final info = CobroInfo.fromJson({'disponible': false});

      expect(info.disponible, isFalse);
      expect(info.moneda, 'CUP');
      expect(info.horasVigencia, 24);
      expect(info.whatsappVerificacion, isNull);
      expect(info.numeroProveedor, '');
      expect(info.resumenVigencia, 'Tienes 24 horas para pagar');
    });

    test('un campo ausente no oculta el cobro si el servidor dice que hay', () {
      // Tolerancia deliberada: si `disponible` viene true, la ficha ofrece pagar
      // aunque falte el resto (se pintarán valores por defecto).
      final info = CobroInfo.fromJson({'disponible': true});
      expect(info.disponible, isTrue);
    });

    test('un plazo absurdo cae al valor por defecto (24 h)', () {
      expect(CobroInfo.fromJson({'horas_vigencia': 0}).horasVigencia, 24);
      expect(CobroInfo.fromJson({'horas_vigencia': 5000}).horasVigencia, 24);
      expect(CobroInfo.fromJson({'horas_vigencia': '24'}).horasVigencia, 24);
    });

    test('los textos vacíos o en blanco se leen como null', () {
      final info = CobroInfo.fromJson({
        'disponible': true,
        'whatsapp_verificacion': '   ',
        'instrucciones': '',
      });
      expect(info.whatsappVerificacion, isNull);
      expect(info.instrucciones, isNull);
    });
  });

  // ── flow.admin_cobro_config_get ──────────────────────────────────────────

  group('CobroConfig', () {
    test('parsea la configuración guardada', () {
      final config = CobroConfig.fromJson({
        'id_entidad': 7,
        'activo': true,
        'tiene_fila': true,
        'transfermovil_numero_proveedor': '4055432',
        'transfermovil_titulo': 'Salón Ana',
        'whatsapp_verificacion': '5355555555',
        'soporte_whatsapp': '',
        'instrucciones': 'Paga y avísame',
        'moneda': 'USD',
        'intent_horas_vigencia': 72,
        'cancelar_si_expira': false,
      });

      expect(config.activo, isTrue);
      expect(config.tieneFila, isTrue);
      expect(config.numeroProveedor, '4055432');
      expect(config.titulo, 'Salón Ana');
      expect(config.whatsappVerificacion, '5355555555');
      expect(config.soporteWhatsapp, isNull);
      expect(config.moneda, 'USD');
      expect(config.horasVigencia, 72);
      expect(config.cancelarSiExpira, isFalse);
      expect(config.cobrando, isTrue);
    });

    test('sin fila devuelve los defectos seguros de la tabla', () {
      final config = CobroConfig.fromJson({
        'id_entidad': 3,
        'activo': false,
        'tiene_fila': false,
      });

      expect(config.cobrando, isFalse);
      expect(config.numeroProveedor, '');
      expect(config.moneda, 'CUP');
      expect(config.horasVigencia, 24);
      expect(config.cancelarSiExpira, isTrue);
    });

    test('cobrando exige activo Y número: la BD rechaza activo sin número', () {
      const sinNumero = CobroConfig(idEntidad: 1, activo: true);
      expect(sinNumero.configurado, isFalse);
      expect(sinNumero.cobrando, isFalse);

      const conNumeroApagado = CobroConfig(
        idEntidad: 1,
        numeroProveedor: '4055432',
      );
      expect(conNumeroApagado.configurado, isTrue);
      expect(conNumeroApagado.cobrando, isFalse);

      const completo = CobroConfig(
        idEntidad: 1,
        activo: true,
        numeroProveedor: '4055432',
      );
      expect(completo.cobrando, isTrue);
    });

    test('copyWith no pierde los campos que no se tocan', () {
      const original = CobroConfig(
        idEntidad: 9,
        activo: false,
        numeroProveedor: '4055432',
        whatsappVerificacion: '5355555555',
        moneda: 'EUR',
        horasVigencia: 12,
      );
      final copia = original.copyWith(activo: true, moneda: 'CUP');

      expect(copia.activo, isTrue);
      expect(copia.moneda, 'CUP');
      expect(copia.numeroProveedor, '4055432');
      expect(copia.whatsappVerificacion, '5355555555');
      expect(copia.horasVigencia, 12);
      expect(copia.idEntidad, 9);
    });
  });

  // ── flow.cliente_crear_pago_reserva ──────────────────────────────────────

  group('PagoReserva (crear pago)', () {
    test(
      'parsea el intento recién creado con los datos de la transferencia',
      () {
        final pago = PagoReserva.fromJson({
          'id': 12,
          'id_agenda': 41,
          'monto': 1500,
          'moneda': 'CUP',
          'importe': '1500',
          'id_transaccion': 'FLW-PAGO-41-20261027101500-AB12CD',
          'numero_proveedor': '4055432',
          'titulo': 'Salón Ana',
          'url_intent': 'transfermovil://tm_compra_en_linea/action?...',
          'url_http': 'https://transfermovil.app/action?...',
          'expira_at': '2026-10-28T10:15:00+00:00',
          'whatsapp_verificacion': '5355555555',
          'soporte_whatsapp': null,
          'instrucciones': 'Paga el importe y avísame.',
        });

        expect(pago.id, 12);
        expect(pago.idAgenda, 41);
        expect(pago.monto, 1500);
        expect(pago.moneda, 'CUP');
        expect(pago.estado, 'creado');
        expect(pago.idTransaccion, 'FLW-PAGO-41-20261027101500-AB12CD');
        expect(pago.numeroProveedor, '4055432');
        expect(pago.urlIntent, startsWith('transfermovil://'));
        expect(pago.urlHttp, startsWith('https://'));
        expect(pago.whatsappVerificacion, '5355555555');
        expect(pago.instrucciones, isNotNull);
        expect(pago.titulo, 'Salón Ana');
        expect(pago.expiraAt, isNotNull);
      },
    );

    test(
      'el importe que se muestra a Transfermóvil no lleva centavos falsos',
      () {
        expect(
          PagoReserva.fromJson({'monto': 1500}).importeTransfermovil,
          '1500',
        );
        expect(
          PagoReserva.fromJson({'monto': 12.5}).importeTransfermovil,
          '12.50',
        );
        // 18.375 no puede llegar a Transfermóvil como "18375".
        expect(
          PagoReserva.fromJson({'monto': 18.375}).importeTransfermovil,
          '18.38',
        );
      },
    );

    test('montoEtiqueta usa el formato de la app por moneda', () {
      expect(PagoReserva.fromJson({'monto': 1500}).montoEtiqueta, '1500 CUP');
      expect(
        PagoReserva.fromJson({'monto': 18, 'moneda': 'USD'}).montoEtiqueta,
        '\$18',
      );
    });
  });

  // ── flow.cliente_pago_reserva ────────────────────────────────────────────

  group('PagoReserva (estado)', () {
    test('parsea el estado con motivo de rechazo y vencido', () {
      final pago = PagoReserva.fromJson({
        'id': 12,
        'id_agenda': 41,
        'monto': 1500,
        'moneda': 'CUP',
        'estado': 'rechazado',
        'motivo_rechazo': 'No se encontró la transferencia',
        'codigo_confirmacion': 'AB-1234',
        'comprobante_url': 'https://x/comprobante.jpg',
        'reportado_at': '2026-10-27T10:20:00+00:00',
        'verificado_at': '2026-10-27T10:25:00+00:00',
        'expira_at': '2026-10-28T10:15:00+00:00',
        'vencido': false,
      });

      expect(pago.rechazado, isTrue);
      expect(pago.esPendiente, isFalse);
      expect(pago.motivoRechazo, contains('transferencia'));
      expect(pago.codigoConfirmacion, 'AB-1234');
      expect(pago.comprobanteUrl, endsWith('.jpg'));
      expect(pago.reportadoAt, isNotNull);
      expect(pago.verificadoAt, isNotNull);
      expect(pago.etiquetaEstado, 'Rechazado');
    });

    test('data:null del RPC no revienta: el servicio devuelve null', () {
      // El modelo no se construye con null; este test fija que el estado
      // «sin pago» de un mapa vacío sea coherente si alguien lo usa.
      final pago = PagoReserva.fromJson(const <String, dynamic>{});
      expect(pago.id, 0);
      expect(pago.estado, 'creado');
      expect(pago.esPendiente, isTrue);
      expect(pago.expiraAt, isNull);
    });

    test('verificado oculta las acciones de pago', () {
      final pago = PagoReserva.fromJson({
        'id': 1,
        'id_agenda': 2,
        'estado': 'verificado',
        'monto': 500,
      });
      expect(pago.verificado, isTrue);
      expect(pago.puedeReportar, isFalse);
    });

    test('expirado por estado, por bandera del servidor o por fecha', () {
      final porEstado = PagoReserva.fromJson({'estado': 'expirado'});
      expect(porEstado.expirado, isTrue);
      expect(porEstado.puedeReportar, isFalse);

      final porBandera = PagoReserva.fromJson({
        'estado': 'reportado',
        'vencido': true,
      });
      expect(porBandera.expirado, isTrue);
      expect(porBandera.puedeReportar, isFalse);

      final pasada = PagoReserva.fromJson({
        'estado': 'creado',
        'expira_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      });
      expect(pasada.expirado, isTrue);
      expect(pasada.restante, Duration.zero);
      expect(pasada.restanteEtiqueta, 'vencido');
    });

    test('restante se calcula sobre expira_at y nunca es negativo', () {
      final futuro = PagoReserva.fromJson({
        'estado': 'creado',
        'expira_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2, minutes: 5))
            .toIso8601String(),
      });
      expect(futuro.expirado, isFalse);
      expect(futuro.puedeReportar, isTrue);
      expect(futuro.restante.inMinutes, greaterThan(100));
      expect(futuro.restanteEtiqueta, contains('h'));
    });

    test('sin expira_at no hay cuenta atrás ni se da por vencido', () {
      final pago = PagoReserva.fromJson({'estado': 'creado'});
      expect(pago.restante, Duration.zero);
      expect(pago.expirado, isFalse);
      expect(pago.puedeReportar, isTrue);
    });

    test(
      'copyWith cambia el estado y conserva los datos de la transferencia',
      () {
        final creado = PagoReserva.fromJson({
          'id': 5,
          'id_agenda': 6,
          'monto': 750,
          'estado': 'creado',
          'url_intent': 'transfermovil://x',
          'numero_proveedor': '4055432',
        });
        final reportado = creado.copyWith(
          estado: 'reportado',
          codigoConfirmacion: 'ZZ-9',
          reportadoAt: DateTime(2026, 10, 27, 10, 30),
        );

        expect(reportado.estado, 'reportado');
        expect(reportado.esReportado, isTrue);
        expect(reportado.codigoConfirmacion, 'ZZ-9');
        expect(reportado.urlIntent, 'transfermovil://x');
        expect(reportado.numeroProveedor, '4055432');
        expect(reportado.monto, 750);
        expect(reportado.esPendiente, isTrue);
      },
    );

    test('estados desconocidos no rompen la etiqueta', () {
      final pago = PagoReserva.fromJson({'estado': 'anulado'});
      expect(pago.etiquetaEstado, 'Anulado');
      expect(
        PagoReserva.fromJson({'estado': 'lo_que_sea'}).etiquetaEstado,
        'lo_que_sea',
      );
    });
  });

  // ── flow.admin_listar_pagos_reserva ──────────────────────────────────────

  group('PagoAdminItem', () {
    Map<String, dynamic> fila({bool conCliente = true}) => {
      // La fila es PLANA: el pago y la reserva comparten nivel.
      'id': 12,
      'id_agenda': 41,
      'monto': 1500,
      'moneda': 'CUP',
      'estado': 'reportado',
      'id_transaccion': 'FLW-PAGO-41-X',
      'numero_proveedor': '4055432',
      'codigo_confirmacion': 'AB-1234',
      'comprobante_url': null,
      'motivo_rechazo': null,
      'reportado_at': '2026-10-27T10:20:00+00:00',
      'verificado_at': null,
      'expira_at': '2026-10-28T10:15:00+00:00',
      'created_at': '2026-10-27T10:00:00+00:00',
      'vencido': false,
      'fecha_hora_reserva': '2026-10-30T14:30:00+00:00',
      'cantidad': 2,
      'id_estado': 1,
      'motivo_cancelacion': null,
      'estado_reserva': {'id': 1, 'nombre': 'Reservado'},
      'id_local_servicio': 7,
      'servicio': {'id': 3, 'nombre': 'Corte'},
      'local': {'id': 2, 'nombre': 'Salón Ana'},
      'cliente': conCliente
          ? {
              'id': 4,
              'nombre': 'Ana',
              'apellidos': 'Pérez',
              'telefono': '54590207',
              'uuid_usuario': 'uuid-ana',
            }
          // El LEFT JOIN del RPC deja `null` cuando el perfil no existe.
          : null,
    };

    test('compone pago + reserva + cliente + servicio/local', () {
      final item = PagoAdminItem.fromJson(fila());

      expect(item.pago.id, 12);
      expect(item.pago.estado, 'reportado');
      expect(item.idAgenda, 41);
      expect(item.cantidad, 2);
      expect(item.estadoReserva, 'Reservado');
      expect(item.idLocalServicio, 7);
      expect(item.servicio, 'Corte');
      expect(item.local, 'Salón Ana');
      expect(item.servicioLocalEtiqueta, 'Corte · Salón Ana');
      expect(item.clienteEtiqueta, 'Ana Pérez');
      expect(item.telefonoEtiqueta, '54590207');
      expect(item.tieneTelefono, isTrue);
      expect(item.clienteUuid, 'uuid-ana');
      expect(item.importeEtiqueta, '1500 CUP');
      expect(item.fechaHoraReserva, isNotNull);
    });

    test('cliente sin perfil no rompe la fila', () {
      final item = PagoAdminItem.fromJson(fila(conCliente: false));

      expect(item.clienteEtiqueta, 'Cliente sin perfil');
      expect(item.telefonoEtiqueta, 'Sin teléfono');
      expect(item.tieneTelefono, isFalse);
      expect(item.clienteNombre, isNull);
    });

    test('motivo de cancelación de la reserva se conserva', () {
      final json = fila();
      json['motivo_cancelacion'] =
          'No se verifico el pago por adelantado en el plazo';
      final item = PagoAdminItem.fromJson(json);
      expect(item.motivoCancelacion, contains('plazo'));
    });

    test('tolera nulos y tipos raros sin lanzar', () {
      final item = PagoAdminItem.fromJson({
        'id': '12', // string donde se espera num
        'monto': null,
        'servicio': 'no-es-un-mapa',
        'local': null,
        'cliente': 42,
        'fecha_hora_reserva': 'no-es-una-fecha',
      });

      // Un numérico en texto se acepta: PostgREST devuelve `numeric` como num,
      // pero un jsonb puede colarlo como string y perder el importe sería peor.
      expect(item.pago.id, 12);
      expect(item.pago.monto, 0);
      expect(item.servicio, isNull);
      expect(item.local, isNull);
      expect(item.clienteEtiqueta, 'Cliente sin perfil');
      expect(item.fechaHoraReserva, isNull);
      expect(item.fechaEtiqueta, 'Sin fecha');
      expect(item.servicioLocalEtiqueta, 'Servicio');
    });

    test('lista de la bandeja: parsea y tolera respuestas raras', () {
      final pagos = pagosAdminDesde([fila(), fila()]);
      expect(pagos, hasLength(2));
      expect(pagos.first.pago.estado, 'reportado');

      expect(pagosAdminDesde(null), isEmpty);
      expect(pagosAdminDesde({'no': 'es una lista'}), isEmpty);
      expect(pagosAdminDesde([1, 2, 'x']), isEmpty);
    });

    test('la fecha de la reserva se pinta en dd/MM/yyyy HH:mm local', () {
      final item = PagoAdminItem.fromJson({
        'id': 1,
        'id_agenda': 2,
        'monto': 100,
        'fecha_hora_reserva': '2026-10-30T14:30:00',
      });
      expect(item.fechaEtiqueta, '30/10/2026 14:30');
    });
  });

  // ── Contrato de la hoja y de la bandeja ──────────────────────────────────

  group('Estados que pinta la UI', () {
    test('los cinco estados del pago tienen etiqueta en español', () {
      const esperado = {
        'creado': 'Pago sin reportar',
        'reportado': 'Pago reportado, esperando verificación',
        'verificado': 'Verificado',
        'rechazado': 'Rechazado',
        'expirado': 'Caducado',
      };
      esperado.forEach((estado, etiqueta) {
        expect(
          PagoReserva.fromJson({'estado': estado}).etiquetaEstado,
          etiqueta,
        );
      });
    });

    test('solo creado y reportado son pendientes (se puede reportar)', () {
      for (final estado in ['creado', 'reportado']) {
        final pago = PagoReserva.fromJson({'estado': estado});
        expect(pago.esPendiente, isTrue, reason: estado);
        expect(pago.puedeReportar, isTrue, reason: estado);
      }
      for (final estado in ['verificado', 'rechazado', 'expirado', 'anulado']) {
        final pago = PagoReserva.fromJson({'estado': estado});
        expect(pago.esPendiente, isFalse, reason: estado);
        expect(pago.puedeReportar, isFalse, reason: estado);
      }
    });
  });
}
