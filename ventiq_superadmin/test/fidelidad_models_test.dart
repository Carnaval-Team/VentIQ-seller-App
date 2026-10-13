import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_superadmin/models/fidelidad.dart';

void main() {
  group('ReglaFidelidadAdmin', () {
    test('lee la fila del listado y arma la etiqueta de la regla', () {
      final r = ReglaFidelidadAdmin.fromJson({
        'id': 1,
        'nombre': 'Programa de fidelidad',
        'id_entidad': null,
        'entidad': null,
        'moneda': 'USD',
        'puntos_por_monto': 1,
        'monto_base': 10,
        'vigencia_dias': 365,
        'activo': true,
        'desde': null,
        'hasta': null,
      });
      expect(r.esGlobal, isTrue);
      expect(r.etiquetaAlcance, 'Todos los clientes');
      expect(r.etiquetaRegla, '1 punto por cada 10 USD');
      expect(r.etiquetaVigencia, 'Caducan al año');
    });

    test('pluraliza los puntos y quita los decimales de relleno', () {
      final r = ReglaFidelidadAdmin.fromJson({
        'id': 2,
        'nombre': 'Doble',
        'puntos_por_monto': 2,
        'monto_base': 5.5,
        'moneda': 'CUP',
      });
      expect(r.etiquetaRegla, '2 puntos por cada 5.5 CUP');
    });

    test('sin moneda no deja un espacio suelto al final', () {
      final r = ReglaFidelidadAdmin.fromJson({
        'id': 3,
        'nombre': 'Sin moneda',
        'puntos_por_monto': 1,
        'monto_base': 10,
      });
      expect(r.etiquetaRegla, '1 punto por cada 10');
    });

    test('una regla por entidad usa la denominacion', () {
      final r = ReglaFidelidadAdmin.fromJson({
        'id': 4,
        'nombre': 'Local',
        'id_entidad': 7,
        'entidad': 'Barbería Central',
        'puntos_por_monto': 1,
        'monto_base': 10,
      });
      expect(r.esGlobal, isFalse);
      expect(r.etiquetaAlcance, 'Barbería Central');
    });

    test('si falta la denominacion cae al id en vez de mentir con "global"', () {
      final r = ReglaFidelidadAdmin.fromJson({
        'id': 5,
        'nombre': 'Local',
        'id_entidad': 9,
      });
      expect(r.esGlobal, isFalse);
      expect(r.etiquetaAlcance, 'Entidad 9');
    });

    test('las vigencias se leen en la unidad que se entiende', () {
      ReglaFidelidadAdmin con(dynamic dias) => ReglaFidelidadAdmin.fromJson({
        'id': 1,
        'nombre': 'x',
        'vigencia_dias': dias,
      });
      expect(con(null).etiquetaVigencia, 'No caducan');
      expect(con(15).etiquetaVigencia, 'Caducan a los 15 días');
      expect(con(30).etiquetaVigencia, 'Caducan al mes');
      expect(con(90).etiquetaVigencia, 'Caducan a los 3 meses');
      expect(con(365).etiquetaVigencia, 'Caducan al año');
      expect(con(730).etiquetaVigencia, 'Caducan a los 2 años');
    });

    test('vigente respeta activo y la ventana de fechas', () {
      final ahora = DateTime.now();
      ReglaFidelidadAdmin con({
        bool activo = true,
        DateTime? desde,
        DateTime? hasta,
      }) => ReglaFidelidadAdmin(
        id: 1,
        nombre: 'x',
        activo: activo,
        desde: desde,
        hasta: hasta,
      );

      expect(con().vigente, isTrue);
      expect(con(activo: false).vigente, isFalse);
      expect(
        con(desde: ahora.add(const Duration(days: 1))).vigente,
        isFalse,
        reason: 'todavía no empieza',
      );
      expect(
        con(hasta: ahora.subtract(const Duration(days: 1))).vigente,
        isFalse,
        reason: 'ya terminó',
      );
      expect(
        con(
          desde: ahora.subtract(const Duration(days: 1)),
          hasta: ahora.add(const Duration(days: 1)),
        ).vigente,
        isTrue,
      );
    });
  });

  group('BeneficioBienvenidaAdmin', () {
    test('porcentaje', () {
      final b = BeneficioBienvenidaAdmin.fromJson({
        'id': 1,
        'titulo': 'Bienvenida',
        'tipo': 'porcentaje',
        'valor': 20,
        'canjes': 0,
      });
      expect(b.etiquetaDescuento, '20% de descuento');
      expect(b.sePuedeBorrar, isTrue);
      expect(b.etiquetaCanjes, '0 canjes');
    });

    test('monto fijo con y sin moneda', () {
      expect(
        BeneficioBienvenidaAdmin.fromJson({
          'id': 1,
          'titulo': 'x',
          'tipo': 'monto',
          'valor': 5,
          'moneda': 'USD',
        }).etiquetaDescuento,
        '5 USD de descuento',
      );
      expect(
        BeneficioBienvenidaAdmin.fromJson({
          'id': 1,
          'titulo': 'x',
          'tipo': 'monto',
          'valor': 5,
        }).etiquetaDescuento,
        '5 de descuento',
      );
    });

    test('con canjes anotados no se puede borrar', () {
      // Es la regla que impide que borrar un beneficio resucite la bienvenida
      // de quien ya la gastó: el canje es el registro de que se usó.
      final b = BeneficioBienvenidaAdmin.fromJson({
        'id': 1,
        'titulo': 'x',
        'canjes': 3,
      });
      expect(b.sePuedeBorrar, isFalse);
      expect(b.etiquetaCanjes, '3 canjes');
    });

    test('un canje se lee en singular', () {
      expect(
        BeneficioBienvenidaAdmin.fromJson({
          'id': 1,
          'titulo': 'x',
          'canjes': 1,
        }).etiquetaCanjes,
        '1 canje',
      );
    });

    test('el minimo nulo se distingue de cero', () {
      final sinMinimo = BeneficioBienvenidaAdmin.fromJson({
        'id': 1,
        'titulo': 'x',
        'monto_minimo': null,
      });
      final conCero = BeneficioBienvenidaAdmin.fromJson({
        'id': 1,
        'titulo': 'x',
        'monto_minimo': 0,
      });
      expect(sinMinimo.montoMinimo, isNull);
      expect(conCero.montoMinimo, 0);
    });
  });

  group('MovimientoPuntosAdmin', () {
    test('signo y tipo', () {
      final suma = MovimientoPuntosAdmin.fromJson({
        'id': 1,
        'puntos': 5,
        'tipo': 'acumulacion',
      });
      final resta = MovimientoPuntosAdmin.fromJson({
        'id': 2,
        'puntos': -3,
        'tipo': 'canje',
      });
      expect(suma.etiquetaPuntos, '+5');
      expect(suma.etiquetaTipo, 'Acumulados');
      expect(resta.etiquetaPuntos, '-3');
      expect(resta.etiquetaTipo, 'Canjeados');
    });

    test('un tipo desconocido se muestra tal cual en vez de inventarse uno', () {
      final m = MovimientoPuntosAdmin.fromJson({
        'id': 1,
        'puntos': 1,
        'tipo': 'no_existe',
      });
      expect(m.etiquetaTipo, 'no_existe');
    });

    test('vencido y liquidado se leen de la fila', () {
      final m = MovimientoPuntosAdmin.fromJson({
        'id': 7,
        'puntos': 10,
        'tipo': 'acumulacion',
        'vencido': true,
        'liquidado': true,
        'id_agenda': 42,
        'regla': 'Programa de fidelidad',
      });
      expect(m.vencido, isTrue);
      expect(m.liquidado, isTrue);
      expect(m.idAgenda, 42);
      expect(m.regla, 'Programa de fidelidad');
    });
  });

  group('AuditoriaPuntos', () {
    test('lee saldo, canje y movimientos', () {
      final a = AuditoriaPuntos.fromJson({
        'uuid_usuario': '047a7f26-67bb-444b-848b-22c5267ba9e8',
        'saldo': 12,
        'ya_canjeo': true,
        'movimientos': [
          {'id': 1, 'puntos': 12, 'tipo': 'acumulacion'},
          {'id': 2, 'puntos': -5, 'tipo': 'ajuste'},
        ],
      });
      expect(a.saldo, 12);
      expect(a.yaCanjeo, isTrue);
      expect(a.movimientos, hasLength(2));
      expect(a.sinMovimientos, isFalse);
    });

    test('sin movimientos no revienta', () {
      expect(AuditoriaPuntos.fromJson(const {}).sinMovimientos, isTrue);
      expect(
        AuditoriaPuntos.fromJson({'movimientos': null}).sinMovimientos,
        isTrue,
      );
      expect(
        AuditoriaPuntos.fromJson({'movimientos': 'basura'}).sinMovimientos,
        isTrue,
      );
    });
  });

  group('FidelidadConfig', () {
    test('solo un false explicito apaga el programa', () {
      expect(FidelidadConfig.fromJson({'activa': false}).activa, isFalse);
      expect(FidelidadConfig.fromJson({'activa': true}).activa, isTrue);
    });

    test('si el campo falta se asume encendido', () {
      // El servidor ya devuelve `coalesce(activa, true)`; si algún día no
      // viniera, apagar la fidelidad por accidente sería peor que dejarla.
      expect(FidelidadConfig.fromJson(const {}).activa, isTrue);
    });

    test('lee la auditoría del cambio', () {
      final c = FidelidadConfig.fromJson({
        'activa': true,
        'updated_at': '2026-10-09T14:30:00Z',
        'updated_by': '206c4acc-9040-44cd-a363-9ab1ccc91c53',
      });
      expect(c.updatedAt, isNotNull);
      expect(c.updatedBy, '206c4acc-9040-44cd-a363-9ab1ccc91c53');
    });
  });
}