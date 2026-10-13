import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/fidelidad_service.dart';

void main() {
  group('MovimientoPuntos.fromJson', () {
    test('parsea un movimiento completo', () {
      final m = MovimientoPuntos.fromJson(const {
        'id': 7,
        'puntos': 3,
        'tipo': 'acumulacion',
        'motivo': 'Reserva completada #42',
        'moneda': 'USD',
        'monto': 35,
        'vence_en': '2027-10-09T12:00:00Z',
        'vencido': false,
        'created_at': '2026-10-09T12:00:00Z',
      });

      expect(m.id, 7);
      expect(m.puntos, 3);
      expect(m.tipo, 'acumulacion');
      expect(m.motivo, 'Reserva completada #42');
      expect(m.moneda, 'USD');
      expect(m.monto, 35);
      expect(m.venceEn, isNotNull);
      expect(m.vencido, isFalse);
      expect(m.createdAt, isNotNull);
    });

    test('tolera un movimiento mínimo sin caerse', () {
      final m = MovimientoPuntos.fromJson(const {});

      expect(m.id, 0);
      expect(m.puntos, 0);
      expect(m.tipo, 'ajuste');
      expect(m.motivo, isNull);
      expect(m.monto, isNull);
      expect(m.venceEn, isNull);
      expect(m.createdAt, isNull);
      expect(m.vencido, isFalse);
    });

    test('marca vencido solo cuando el servidor lo dice', () {
      expect(
        MovimientoPuntos.fromJson(const {'vencido': true}).vencido,
        isTrue,
      );
      // Cualquier otra cosa que no sea `true` es "no vencido": no se adivina.
      expect(
        MovimientoPuntos.fromJson(const {'vencido': 'true'}).vencido,
        isFalse,
      );
    });

    test('una fecha que no es String no revienta el parseo', () {
      final m = MovimientoPuntos.fromJson(const {'vence_en': 12345});
      expect(m.venceEn, isNull);
    });

    test('etiquetaPuntos pone el signo explícito', () {
      expect(MovimientoPuntos.fromJson(const {'puntos': 3}).etiquetaPuntos, '+3');
      expect(
        MovimientoPuntos.fromJson(const {'puntos': -5}).etiquetaPuntos,
        '-5',
      );
      expect(MovimientoPuntos.fromJson(const {'puntos': 0}).etiquetaPuntos, '+0');
    });

    test('etiquetaTipo traduce los cuatro tipos y no inventa los demás', () {
      String t(String tipo) =>
          MovimientoPuntos.fromJson({'tipo': tipo}).etiquetaTipo;

      expect(t('acumulacion'), 'Acumulados');
      expect(t('canje'), 'Canjeados');
      expect(t('vencimiento'), 'Caducados');
      expect(t('ajuste'), 'Ajuste');
      // Un tipo que la base añada mañana se muestra tal cual, sin romper.
      expect(t('otro'), 'otro');
    });
  });

  group('ReglaFidelidad', () {
    test('explicacion con la regla por defecto (1 punto por cada 10 USD)', () {
      const r = ReglaFidelidad(
        puntosPorMonto: 1,
        montoBase: 10,
        moneda: 'USD',
      );
      expect(r.explicacion, 'Ganas 1 punto por cada 10 USD');
    });

    test('explicacion en plural y sin moneda', () {
      const r = ReglaFidelidad(puntosPorMonto: 2, montoBase: 100);
      expect(r.explicacion, 'Ganas 2 puntos por cada 100');
    });

    test('explicacion no deja decimales de relleno', () {
      const r = ReglaFidelidad(puntosPorMonto: 7.5, montoBase: 10);
      expect(r.explicacion, 'Ganas 7.5 puntos por cada 10');
    });

    test('explicacion ignora una moneda en blanco', () {
      const r = ReglaFidelidad(
        puntosPorMonto: 1,
        montoBase: 10,
        moneda: '  ',
      );
      expect(r.explicacion, 'Ganas 1 punto por cada 10');
    });

    test('etiquetaVigencia habla en años, meses o días', () {
      String? v(int? d) => ReglaFidelidad(
        puntosPorMonto: 1,
        montoBase: 10,
        vigenciaDias: d,
      ).etiquetaVigencia;

      expect(v(365), 'Caducan al año');
      expect(v(730), 'Caducan a los 2 años');
      expect(v(30), 'Caducan al mes');
      expect(v(90), 'Caducan a los 3 meses');
      expect(v(45), 'Caducan a los 45 días');
      expect(v(null), isNull);
    });

    test('fromJson tolera campos ausentes', () {
      final r = ReglaFidelidad.fromJson(const {});
      expect(r.puntosPorMonto, 0);
      expect(r.montoBase, 0);
      expect(r.vigenciaDias, isNull);
      expect(r.moneda, isNull);
    });
  });

  group('BeneficioBienvenida', () {
    test('etiqueta de un porcentaje', () {
      const b = BeneficioBienvenida(
        id: 1,
        titulo: 'Bienvenida',
        tipo: 'porcentaje',
        valor: 20,
      );
      expect(b.etiqueta, '20% de descuento');
    });

    test('etiqueta de un monto con y sin moneda', () {
      const conMoneda = BeneficioBienvenida(
        id: 1,
        titulo: 'Bienvenida',
        tipo: 'monto',
        valor: 5,
        moneda: 'USD',
      );
      expect(conMoneda.etiqueta, '5 USD de descuento');

      const sinMoneda = BeneficioBienvenida(
        id: 1,
        titulo: 'Bienvenida',
        tipo: 'monto',
        valor: 5,
      );
      expect(sinMoneda.etiqueta, '5 de descuento');
    });

    test('fromJson lee monto_minimo y descripcion', () {
      final b = BeneficioBienvenida.fromJson(const {
        'id': 3,
        'titulo': 'Pack',
        'descripcion': 'Solo en tu primera reserva',
        'tipo': 'monto',
        'valor': 10,
        'moneda': 'CUP',
        'monto_minimo': 50,
      });
      expect(b.id, 3);
      expect(b.titulo, 'Pack');
      expect(b.descripcion, 'Solo en tu primera reserva');
      expect(b.valor, 10);
      expect(b.montoMinimo, 50);
    });
  });

  group('MiFidelidad', () {
    test('parsea una respuesta completa', () {
      final f = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'saldo': 12,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10, 'moneda': 'USD'},
        'beneficio': {'id': 1, 'titulo': 'Bienvenida', 'tipo': 'porcentaje', 'valor': 20},
        'ya_canjeo': false,
        'movimientos': [
          {'id': 1, 'puntos': 3, 'tipo': 'acumulacion'},
          {'id': 2, 'puntos': 9, 'tipo': 'acumulacion'},
        ],
      });

      expect(f.conSesion, isTrue);
      expect(f.saldo, 12);
      expect(f.regla, isNotNull);
      expect(f.beneficio, isNotNull);
      expect(f.yaCanjeo, isFalse);
      expect(f.movimientos, hasLength(2));
      expect(f.etiquetaPuntos, '12 puntos');
    });

    test('sin regla, sin beneficio y sin movimientos no se cae', () {
      final f = MiFidelidad.fromJson(const {'con_sesion': true, 'saldo': 0});

      expect(f.regla, isNull);
      expect(f.beneficio, isNull);
      expect(f.movimientos, isEmpty);
      expect(f.yaCanjeo, isFalse);
    });

    test('un usuario que ya canjeó no recibe beneficio, pero conserva el saldo', () {
      final f = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'saldo': 4,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10},
        'ya_canjeo': true,
      });

      expect(f.beneficio, isNull);
      expect(f.yaCanjeo, isTrue);
      expect(f.saldo, 4);
    });

    test('movimientos basura no rompen el parseo', () {
      final f = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'movimientos': ['no soy un mapa', 42, {'id': 1, 'puntos': 2}],
      });
      expect(f.movimientos, hasLength(1));
      expect(f.movimientos.first.puntos, 2);
    });

    test('un objeto suelto en campos que deberían ser mapa se ignora', () {
      final f = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'regla': 'nope',
        'beneficio': 7,
      });
      expect(f.regla, isNull);
      expect(f.beneficio, isNull);
    });

    test('etiquetaPuntos singular y plural', () {
      expect(MiFidelidad.fromJson(const {'saldo': 1}).etiquetaPuntos, '1 punto');
      expect(MiFidelidad.fromJson(const {'saldo': 0}).etiquetaPuntos, '0 puntos');
    });

    test('hayAlgoQueMostrar exige sesión', () {
      // Con regla pero sin sesión: no hay nada que contar.
      final sinSesion = MiFidelidad.fromJson(const {
        'con_sesion': false,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10},
      });
      expect(sinSesion.hayAlgoQueMostrar, isFalse);

      // Con sesión y regla: sí.
      final conRegla = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10},
      });
      expect(conRegla.hayAlgoQueMostrar, isTrue);

      // Con sesión y solo movimientos: también (el saldo tiene historia).
      final conMovimientos = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'movimientos': [
          {'id': 1, 'puntos': 3, 'tipo': 'acumulacion'},
        ],
      });
      expect(conMovimientos.hayAlgoQueMostrar, isTrue);

      // Con sesión pero sin regla ni movimientos: nada honesto que mostrar.
      final vacio = MiFidelidad.fromJson(const {'con_sesion': true});
      expect(vacio.hayAlgoQueMostrar, isFalse);
    });

    test('el interruptor global apaga la seccion aunque haya saldo y regla', () {
      final apagada = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'activa': false,
        'saldo': 40,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10},
        'movimientos': [
          {'id': 1, 'puntos': 3, 'tipo': 'acumulacion'},
        ],
      });

      // Los datos se siguen leyendo (apagar no borra), pero no se pinta nada.
      expect(apagada.activa, isFalse);
      expect(apagada.saldo, 40);
      expect(apagada.regla, isNotNull);
      expect(apagada.movimientos, hasLength(1));
      expect(apagada.hayAlgoQueMostrar, isFalse);
    });

    test('sin el campo `activa` se asume encendida', () {
      expect(MiFidelidad.fromJson(const {'con_sesion': true}).activa, isTrue);
      // Solo el booleano `false` apaga el programa: un valor raro no debe
      // ocultar la seccion por accidente.
      expect(MiFidelidad.fromJson(const {'activa': 'false'}).activa, isTrue);
      expect(MiFidelidad.fromJson(const {'activa': 0}).activa, isTrue);
    });

    test('con `activa` en true la seccion si se pinta', () {
      final encendida = MiFidelidad.fromJson(const {
        'con_sesion': true,
        'activa': true,
        'regla': {'puntos_por_monto': 1, 'monto_base': 10},
      });
      expect(encendida.activa, isTrue);
      expect(encendida.hayAlgoQueMostrar, isTrue);
    });
  });
}