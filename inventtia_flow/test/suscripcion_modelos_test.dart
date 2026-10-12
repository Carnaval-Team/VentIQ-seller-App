import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/suscripcion.dart';

/// Contrato entre la app y los RPC de suscripciones.
///
/// Los `jsonb_build_object` de las migraciones 44–46 ya no son negociables: esta
/// app los lee campo a campo. Estos tests fijan **las claves exactas** que
/// devuelve cada RPC con un fixture copiado del SQL, de modo que si alguien
/// renombra una clave el fallo aparezca aquí y no como una pantalla llena de "—"
/// en producción.
///
/// No hay nada de Supabase aquí a propósito: son modelos puros.
void main() {
  // ── flow.cliente_estado_suscripcion ──────────────────────────────────────

  group('EstadoSuscripcion', () {
    test('traduce los 9 valores que puede devolver el servidor', () {
      expect(EstadoSuscripcion.desde('trial'), EstadoSuscripcion.trial);
      expect(EstadoSuscripcion.desde('activa'), EstadoSuscripcion.activa);
      expect(EstadoSuscripcion.desde('en_gracia'), EstadoSuscripcion.enGracia);
      expect(EstadoSuscripcion.desde('vencida'), EstadoSuscripcion.vencida);
      expect(EstadoSuscripcion.desde('sin_plan'), EstadoSuscripcion.sinPlan);
      expect(
        EstadoSuscripcion.desde('suspendida'),
        EstadoSuscripcion.suspendida,
      );
      expect(EstadoSuscripcion.desde('cancelada'), EstadoSuscripcion.cancelada);
      expect(
        EstadoSuscripcion.desde('sin_suscripcion'),
        EstadoSuscripcion.sinSuscripcion,
      );
      // Un estado nuevo que el servidor estrene no debe romper la app.
      expect(
        EstadoSuscripcion.desde('lo_que_sea'),
        EstadoSuscripcion.desconocido,
      );
      expect(EstadoSuscripcion.desde(null), EstadoSuscripcion.desconocido);
    });

    test('sin_suscripcion NO es impago: es una entidad anterior al modulo', () {
      // Es la invariante que impide que aplicar las migraciones deje a todas las
      // entidades existentes con un cartel de "no has pagado" encima.
      expect(EstadoSuscripcion.sinSuscripcion.esImpago, isFalse);
      expect(EstadoSuscripcion.sinSuscripcion.operativa, isTrue);
    });

    test('en_gracia funciona y por tanto tampoco es impago', () {
      // La gracia es el margen de 7 dias configurable: la entidad sigue visible
      // y admitiendo reservas, asi que no puede salir el aviso rojo.
      expect(EstadoSuscripcion.enGracia.esImpago, isFalse);
      expect(EstadoSuscripcion.enGracia.operativa, isTrue);
    });

    test('vencida, sin_plan, cancelada y suspendida si son impago', () {
      for (final e in const [
        EstadoSuscripcion.vencida,
        EstadoSuscripcion.sinPlan,
        EstadoSuscripcion.cancelada,
        EstadoSuscripcion.suspendida,
      ]) {
        expect(e.esImpago, isTrue, reason: '${e.name} deberia avisar');
        expect(e.operativa, isFalse, reason: '${e.name} no deberia operar');
      }
    });

    test('trial y activa son operativas y no son impago', () {
      for (final e in const [
        EstadoSuscripcion.trial,
        EstadoSuscripcion.activa,
      ]) {
        expect(e.esImpago, isFalse);
        expect(e.operativa, isTrue);
      }
    });
  });

  group('EstadoSuscripcionEntidad.fromJson', () {
    test('la rama sin_suscripcion del RPC no dispara el aviso', () {
      // Fixture literal de la rama "esta entidad todavia no tiene suscripcion
      // registrada" de cliente_estado_suscripcion.
      final estado = EstadoSuscripcionEntidad.fromJson({
        'id_entidad': 7,
        'estado': 'sin_suscripcion',
        'activa': true,
        'es_trial': false,
        'en_gracia': false,
        'plan_codigo': null,
        'plan_nombre': null,
        'duracion_dias': null,
        'precio': null,
        'moneda': null,
        'fecha_inicio': null,
        'fecha_vencimiento': null,
        'fecha_gracia_fin': null,
        'dias_restantes': null,
        'dias_gracia': null,
        'mensaje': 'Esta entidad todavia no tiene suscripcion registrada.',
      });

      expect(estado.activa, isTrue);
      expect(estado.mostrarAvisoImpago, isFalse);
      expect(estado.estado.operativa, isTrue);
      expect(estado.planNombre, isNull);
      expect(estado.precioEtiqueta, isNull);
      expect(estado.mensaje, isNotNull);
    });

    test('una entidad vencida avisa y trae dias negativos', () {
      final estado = EstadoSuscripcionEntidad.fromJson({
        'id_entidad': 7,
        'estado': 'vencida',
        'estado_guardado': 'activa',
        'activa': false,
        'es_trial': false,
        'en_gracia': false,
        'plan_codigo': 'flow_mensual',
        'plan_nombre': 'Mensual',
        'duracion_dias': 30,
        'precio': 1500,
        'moneda': 'CUP',
        'fecha_inicio': '2026-01-01T00:00:00+00:00',
        'fecha_vencimiento': '2026-01-31T00:00:00+00:00',
        'fecha_gracia_fin': '2026-02-07T00:00:00+00:00',
        'dias_restantes': -12,
        'dias_gracia': -5,
        'mensaje': 'Tu suscripcion vencio.',
      });

      expect(estado.activa, isFalse);
      expect(estado.mostrarAvisoImpago, isTrue);
      expect(estado.diasRestantes, -12);
      expect(estado.diasGracia, -5);
      // El estado guardado va por detras del derivado de fechas: el cron corre
      // cada 15 minutos. La UI se guia por el derivado.
      expect(estado.estadoGuardado, 'activa');
      expect(estado.estado, EstadoSuscripcion.vencida);
      expect(estado.precioEtiqueta, '1500 CUP');
      expect(estado.fechaVencimiento, isNotNull);
    });

    test('sin el campo activa NO se apaga la entidad', () {
      // Una respuesta incompleta no debe ocultar una entidad del catalogo: el
      // default de `activa` es `true`, no `false`.
      final estado = EstadoSuscripcionEntidad.fromJson({'estado': 'activa'});
      expect(estado.activa, isTrue);
      expect(estado.idEntidad, 0);
      expect(estado.mostrarAvisoImpago, isFalse);
    });

    test('copyWith cambia solo el estado', () {
      final base = EstadoSuscripcionEntidad.fromJson({
        'id_entidad': 3,
        'estado': 'activa',
        'activa': true,
        'plan_nombre': 'Mensual',
      });
      final cambiado = base.copyWith(estado: EstadoSuscripcion.enGracia);
      expect(cambiado.estado, EstadoSuscripcion.enGracia);
      expect(cambiado.planNombre, 'Mensual');
      expect(cambiado.activa, isTrue);
    });
  });

  // ── flow.cliente_planes_suscripcion ──────────────────────────────────────

  group('PlanSuscripcion.fromJson', () {
    test('lee las claves del catalogo de planes activos', () {
      // Claves exactas del jsonb_build_object de cliente_planes_suscripcion.
      final plan = PlanSuscripcion.fromJson({
        'id': 12,
        'codigo': 'flow_trimestral',
        'nombre': 'Trimestral',
        'descripcion': 'Suscripcion de 3 meses (90 dias)',
        'duracion_dias': 90,
        'precio': 4500,
        'moneda': 'CUP',
        'limites': <String, dynamic>{},
        'orden': 20,
      });

      expect(plan.id, 12);
      expect(plan.codigo, 'flow_trimestral');
      expect(plan.etiquetaDuracion, '3 meses');
      expect(plan.precioEtiqueta, '4500 CUP');
      // 4500 / 3 meses = 1500 al mes, para comparar planes de un vistazo.
      expect(plan.precioPorMesEtiqueta, '1500 CUP');
      expect(plan.limites, isEmpty);
    });

    test('etiqueta las duraciones exactas y las que no lo son', () {
      PlanSuscripcion de(int dias) => PlanSuscripcion(
        id: 1,
        codigo: 'x',
        nombre: 'X',
        duracionDias: dias,
        precio: 100,
        moneda: 'CUP',
      );

      expect(de(30).etiquetaDuracion, '1 mes');
      expect(de(90).etiquetaDuracion, '3 meses');
      expect(de(365).etiquetaDuracion, '1 año');
      expect(de(60).etiquetaDuracion, '2 meses');
      expect(de(7).etiquetaDuracion, '7 días');
      expect(de(1).etiquetaDuracion, '1 día');
    });

    test('no muestra precio por mes en planes de menos de un mes', () {
      // Comparar el mensual de un plan de 7 dias con uno de 30 enganaria.
      final semana = PlanSuscripcion(
        id: 1,
        codigo: 'semana',
        nombre: 'Semana',
        duracionDias: 7,
        precio: 500,
        moneda: 'CUP',
      );
      expect(semana.precioPorMesEtiqueta, isNull);
    });

    test('tolera una respuesta sin limites', () {
      final plan = PlanSuscripcion.fromJson({
        'id': 1,
        'codigo': 'flow_mensual',
        'nombre': 'Mensual',
        'duracion_dias': 30,
        'precio': 1500,
        'moneda': 'CUP',
      });
      expect(plan.limites, isEmpty);
      expect(plan.orden, 0);
    });
  });

  // ── flow.cliente_crear_intent_suscripcion ────────────────────────────────

  group('IntentPagoCreado.fromJson', () {
    /// Fixture literal de `cliente_crear_intent_suscripcion`.
    ///
    /// Ojo: el RPC devuelve un objeto **plano**, no `{ intent: {...} }`. Ese
    /// detalle ya provoco un fallo una vez; este fixture lo deja clavado.
    Map<String, dynamic> fixture({bool modoPrueba = false}) => {
      'id': 55,
      'id_entidad': 7,
      'id_plan': 12,
      'plan_nombre': 'Trimestral',
      'duracion_dias': 90,
      'monto': 4500,
      'moneda': 'CUP',
      'importe': '4500',
      'id_transaccion': 'FLW-7-20261012120000-A1B2C3',
      'numero_proveedor': '4055432',
      'titulo': 'Carnaval Alimentos',
      // El link lleva el id LITERAL de Transfermovil (bug de su app: siempre
      // "ESTATICO"), nunca nuestra referencia interna FLW-....
      'url_intent':
          'transfermovil://tm_compra_en_linea/action?id_transaccion=ESTATICO',
      'url_http':
          'https://transfermovil.app/action?id_transaccion=ESTATICO',
      'expira_at': '2026-10-13T12:00:00+00:00',
      'soporte_whatsapp': '5354590207',
      'modo_prueba': modoPrueba,
    };

    test('desenvuelve el objeto plano sin anidar', () {
      final creado = IntentPagoCreado.fromJson(fixture());

      expect(creado.intent.id, 55);
      expect(creado.intent.idPlan, 12);
      expect(creado.intent.planNombre, 'Trimestral');
      expect(creado.intent.monto, 4500);
      expect(creado.intent.moneda, 'CUP');
      expect(creado.intent.urlIntent, startsWith('transfermovil://'));
      expect(creado.intent.urlHttp, startsWith('https://'));
      expect(creado.idTransaccion, 'FLW-7-20261012120000-A1B2C3');
      expect(creado.importe, '4500');
      expect(creado.numeroProveedor, '4055432');
      expect(creado.titulo, 'Carnaval Alimentos');
      expect(creado.soporteWhatsapp, '5354590207');
      expect(creado.intent.expiraAt, isNotNull);
    });

    test('el RPC no devuelve estado: nace creado, nunca abierto', () {
      // Es la razon de que el boton "Ya he pagado" no pueda depender del estado
      // del intent: solo aparece cuando la app vuelve a primer plano.
      final creado = IntentPagoCreado.fromJson(fixture());
      expect(creado.intent.estado, 'creado');
      expect(creado.intent.vigente, isTrue);
    });

    test('respeta el aviso de modo prueba', () {
      expect(IntentPagoCreado.fromJson(fixture()).modoPrueba, isFalse);
      expect(
        IntentPagoCreado.fromJson(fixture(modoPrueba: true)).modoPrueba,
        isTrue,
      );
    });

    test('un intent vigente expira con su fecha', () {
      final expirado = IntentSuscripcion.fromJson({
        'id': 55,
        'id_plan': 12,
        'monto': 4500,
        'moneda': 'CUP',
        'id_transaccion': 'FLW-7-viejo',
        'url_intent': 'transfermovil://x',
        'estado': 'creado',
        'expira_at': '2020-01-01T00:00:00+00:00',
      });
      expect(expirado.vigente, isTrue, reason: 'vigente mira el estado');
      expect(expirado.expirado, isTrue, reason: 'expirado mira la fecha');
    });
  });

  // ── flow.cliente_reportar_pago_suscripcion ───────────────────────────────

  group('ReportePago.fromJson', () {
    test('lee las claves exactas del RPC de "Ya he pagado"', () {
      final reporte = ReportePago.fromJson({
        'id_transaccion_pago': 91,
        'estado': 'reportado',
        'monto': 4500,
        'moneda': 'CUP',
        'id_transaccion': 'FLW-7-20261012120000-A1B2C3',
        'codigo_confirmacion': '12345678',
        'soporte_whatsapp': '5354590207',
        'mensaje_soporte': 'Yo Juan Perez he pagado el plan Trimestral...',
      });

      expect(reporte.idTransaccionPago, 91);
      expect(reporte.soporteWhatsapp, '5354590207');
      expect(reporte.mensajeSoporte, contains('he pagado'));
    });

    test('cae al WhatsApp de soporte por defecto si falta el campo', () {
      final reporte = ReportePago.fromJson({'id_transaccion_pago': 1});
      expect(reporte.soporteWhatsapp, '5354590207');
      expect(reporte.mensajeSoporte, isEmpty);
    });
  });

  // ── flow.cliente_mis_pagos_suscripcion ───────────────────────────────────

  group('MiSuscripcion', () {
    Map<String, dynamic> pago(int id, String estado) => {
      'id': id,
      'id_intent': 1,
      'codigo_confirmacion': 'C$id',
      'monto': 4500,
      'moneda': 'CUP',
      'metodo': 'transfermovil',
      'comprobante_url': null,
      'estado': estado,
      'observaciones': null,
      'reportado_at': '2026-10-12T12:00:00+00:00',
      'verificado_at': null,
    };

    Map<String, dynamic> intent(int id, String estado, String expira) => {
      'id': id,
      'id_plan': 12,
      'plan_nombre': 'Trimestral',
      'monto': 4500,
      'moneda': 'CUP',
      'id_transaccion': 'FLW-7-$id',
      'url_intent': 'transfermovil://x',
      'url_http': 'https://x',
      'estado': estado,
      'expira_at': expira,
      'created_at': '2026-10-12T12:00:00+00:00',
    };

    test('pagoPendiente es el reportado, no el verificado', () {
      final mi = MiSuscripcion.fromJson({
        'pagos': [pago(1, 'verificado'), pago(2, 'reportado')],
      });
      expect(mi.pagoPendiente, isNotNull);
      expect(mi.pagoPendiente!.id, 2);
      expect(mi.pagoPendiente!.estado, 'reportado');
    });

    test('sin pagos reportados no hay nada pendiente', () {
      final mi = MiSuscripcion.fromJson({
        'pagos': [pago(1, 'verificado'), pago(2, 'rechazado')],
      });
      expect(mi.pagoPendiente, isNull);
    });

    test('intentVigente ignora los caducados y los ya pagados', () {
      // Es la regla que decide si la pantalla ofrece reanudar un pago a medias.
      final mi = MiSuscripcion.fromJson({
        'intents': [
          intent(1, 'expirado', '2020-01-01T00:00:00+00:00'),
          intent(2, 'reportado', '2030-01-01T00:00:00+00:00'),
          intent(3, 'creado', '2020-01-01T00:00:00+00:00'),
          intent(4, 'abierto', '2030-01-01T00:00:00+00:00'),
        ],
      });
      expect(mi.intentVigente, isNotNull);
      expect(mi.intentVigente!.id, 4);
    });

    test('sin intents utilizables no hay nada que reanudar', () {
      final mi = MiSuscripcion.fromJson({
        'intents': [intent(1, 'verificado', '2030-01-01T00:00:00+00:00')],
      });
      expect(mi.intentVigente, isNull);
    });

    test('una respuesta vacia no rompe nada', () {
      final mi = MiSuscripcion.fromJson({});
      expect(mi.intents, isEmpty);
      expect(mi.pagos, isEmpty);
      expect(mi.movimientos, isEmpty);
      expect(mi.pagoPendiente, isNull);
      expect(mi.intentVigente, isNull);
    });

    test('lee los movimientos del libro mayor', () {
      final mi = MiSuscripcion.fromJson({
        'movimientos': [
          {
            'tipo': 'acreditacion',
            'dias': 90,
            'fecha_desde': '2026-10-12T12:00:00+00:00',
            'fecha_hasta': '2027-01-10T12:00:00+00:00',
            'motivo': 'Pago verificado por transferencia',
            'created_at': '2026-10-12T12:00:00+00:00',
          },
        ],
      });
      expect(mi.movimientos, hasLength(1));
      final m = mi.movimientos.first;
      expect(m.tipo, 'acreditacion');
      expect(m.dias, 90);
      expect(m.motivo, contains('verificado'));
      expect(m.createdAt, isNotNull);
    });
  });
}
