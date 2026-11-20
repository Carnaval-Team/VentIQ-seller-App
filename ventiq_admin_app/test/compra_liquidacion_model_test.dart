// Modelos de la liquidación de compras (reserva y pago): `fromJson` según el
// contrato de las RPC `fn_fdi_disponible` / `fn_fdi_compra_reservar` y la
// aritmética de `ResumenCobertura`. Sin red: solo modelos.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/compra.dart';

void main() {
  group('liquidacion · DisponibleFondo', () {
    test('liquidacion · fromJson lee el contrato de fn_fdi_disponible', () {
      final f = DisponibleFondo.fromJson({
        'id_cuenta': 7,
        'cuenta': 'Caja principal',
        'id_medio_pago': 2,
        'medio_pago': 'Transferencia',
        'moneda': 'CUP',
        'saldo': 1500.5,
        'reservado': 500.25,
        'disponible': 1000.25,
      });

      expect(f.idCuenta, 7);
      expect(f.cuenta, 'Caja principal');
      expect(f.idMedioPago, 2);
      expect(f.medioPago, 'Transferencia');
      expect(f.moneda, 'CUP');
      expect(f.saldo, 1500.5);
      expect(f.reservado, 500.25);
      expect(f.disponible, 1000.25);
      expect(f.etiqueta, 'Caja principal · Transferencia · CUP');
      expect(f.tieneDisponible, isTrue);
    });

    test('liquidacion · sin disponible y con jsonb parcial', () {
      final sinSaldo = DisponibleFondo.fromJson({
        'id_cuenta': 9,
        'cuenta': 'Caja USD',
        'id_medio_pago': 3,
        'medio_pago': 'Efectivo',
        'moneda': 'USD',
        'saldo': 0,
        'reservado': 0,
        'disponible': 0,
      });
      expect(sinSaldo.tieneDisponible, isFalse);
      expect(sinSaldo.etiqueta, 'Caja USD · Efectivo · USD');

      // Los importes faltantes caen a 0 y los enteros se aceptan como num.
      final parcial = DisponibleFondo.fromJson({'id_cuenta': 1, 'moneda': 'CUP'});
      expect(parcial.cuenta, '');
      expect(parcial.saldo, 0);
      expect(parcial.disponible, 0);
      expect(parcial.tieneDisponible, isFalse);
    });
  });

  group('liquidacion · FuenteReserva', () {
    test('liquidacion · fromJson y toJson usan las claves de p_fuentes', () {
      final f = FuenteReserva.fromJson({
        'id_cuenta': 7,
        'id_medio_pago': 2,
        'moneda': 'USD',
        'monto': 25.5,
        'tasa_a_total': 30,
      });

      expect(f.idCuenta, 7);
      expect(f.idMedioPago, 2);
      expect(f.moneda, 'USD');
      expect(f.monto, 25.5);
      expect(f.tasaATotal, 30);

      expect(f.toJson(), {
        'id_cuenta': 7,
        'id_medio_pago': 2,
        'moneda': 'USD',
        'monto': 25.5,
        'tasa_a_total': 30.0,
      });
    });

    test('liquidacion · tasaATotal por defecto 1 y montoEqTotal redondea', () {
      const sinTasa = FuenteReserva(
        idCuenta: 1,
        idMedioPago: 1,
        moneda: 'CUP',
        monto: 10,
      );
      expect(sinTasa.tasaATotal, 1);
      expect(sinTasa.montoEqTotal, 10);
      expect(sinTasa.toJson()['tasa_a_total'], 1);

      const usd = FuenteReserva(
        idCuenta: 2,
        idMedioPago: 2,
        moneda: 'USD',
        monto: 33.333,
        tasaATotal: 30,
      );
      expect(usd.montoEqTotal, 999.99);

      // 1.239 * 1 → 1.24 (dos decimales, como el recálculo en PostgreSQL).
      const centavos = FuenteReserva(
        idCuenta: 3,
        idMedioPago: 3,
        moneda: 'CUP',
        monto: 1.239,
      );
      expect(centavos.montoEqTotal, 1.24);
    });
  });

  group('liquidacion · ResumenCobertura', () {
    const total = 1000.0;

    test('liquidacion · cubre exacto', () {
      const r = ResumenCobertura(
        total: total,
        fuentes: [
          FuenteReserva(
            idCuenta: 1,
            idMedioPago: 1,
            moneda: 'CUP',
            monto: 600,
          ),
          FuenteReserva(
            idCuenta: 2,
            idMedioPago: 2,
            moneda: 'CUP',
            monto: 400,
          ),
        ],
      );

      expect(r.totalFinanciado, 1000);
      expect(r.aportado, 1000);
      expect(r.faltante, 0);
      expect(r.sobra, 0);
      expect(r.cubreExacto, isTrue);
    });

    test('liquidacion · falta 0,01 por redondeo y NO cubre', () {
      // Tres fuentes que suman 999,99 contra un total de 1.000,00.
      const r = ResumenCobertura(
        total: total,
        fuentes: [
          FuenteReserva(
            idCuenta: 1,
            idMedioPago: 1,
            moneda: 'CUP',
            monto: 333.33,
          ),
          FuenteReserva(
            idCuenta: 2,
            idMedioPago: 2,
            moneda: 'CUP',
            monto: 333.33,
          ),
          FuenteReserva(
            idCuenta: 3,
            idMedioPago: 3,
            moneda: 'CUP',
            monto: 333.33,
          ),
        ],
      );

      expect(r.totalFinanciado, 999.99);
      expect(r.faltante, 0.01);
      expect(r.sobra, 0);
      expect(r.aportado, 999.99);
      expect(r.cubreExacto, isFalse);
    });

    test('liquidacion · sobra y no cubre exacto', () {
      const r = ResumenCobertura(
        total: total,
        fuentes: [
          FuenteReserva(
            idCuenta: 1,
            idMedioPago: 1,
            moneda: 'CUP',
            monto: 600,
          ),
          FuenteReserva(
            idCuenta: 2,
            idMedioPago: 2,
            moneda: 'CUP',
            monto: 500,
          ),
        ],
      );

      expect(r.totalFinanciado, 1100);
      expect(r.aportado, 1000);
      expect(r.faltante, 0);
      expect(r.sobra, 100);
      expect(r.cubreExacto, isFalse);
      expect(r.cubre, isTrue);
    });

    test('liquidacion · lista vacía no cubre', () {
      const r = ResumenCobertura(total: total);

      expect(r.totalFinanciado, 0);
      expect(r.aportado, 0);
      expect(r.faltante, 1000);
      expect(r.sobra, 0);
      expect(r.cubreExacto, isFalse);
      expect(r.cubre, isFalse);
    });

    test('liquidacion · mezcla de monedas con tasa_a_total', () {
      // 900 CUP (tasa 1) + 10 USD (tasa 30) = 300 → 1200; cubre exacto 1200.
      const r = ResumenCobertura(
        total: 1200,
        fuentes: [
          FuenteReserva(
            idCuenta: 1,
            idMedioPago: 1,
            moneda: 'CUP',
            monto: 900,
          ),
          FuenteReserva(
            idCuenta: 2,
            idMedioPago: 2,
            moneda: 'USD',
            monto: 10,
            tasaATotal: 30,
          ),
        ],
      );

      expect(r.totalFinanciado, 1200);
      expect(r.faltante, 0);
      expect(r.cubreExacto, isTrue);
    });

    test('liquidacion · centavos de coma flotante no rompen el exacto', () {
      // 0.1 + 0.2 en double no es 0.3 exacto; en centavos sí.
      const r = ResumenCobertura(
        total: 0.3,
        fuentes: [
          FuenteReserva(
            idCuenta: 1,
            idMedioPago: 1,
            moneda: 'CUP',
            monto: 0.1,
          ),
          FuenteReserva(
            idCuenta: 2,
            idMedioPago: 2,
            moneda: 'CUP',
            monto: 0.2,
          ),
        ],
      );

      expect(r.totalFinanciado, 0.3);
      expect(r.cubreExacto, isTrue);
      expect(r.faltante, 0);
    });
  });
}