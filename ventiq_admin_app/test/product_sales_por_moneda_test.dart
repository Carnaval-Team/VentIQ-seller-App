import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/sales_service.dart';

void main() {
  group('regla de utilidad por moneda', () {
    test('CUP: neto − costo_usd × tasa; USD: neto − costo_usd', () {
      // Costo sistema 0.5 USD. Tasa 400. Venta 1000 CUP → ganancia 800 CUP.
      // Misma unidad vendida a 1 USD → ganancia 0.5 USD.
      const tasa = 400.0;
      const costoUsd = 0.5;
      const ventaCup = 1000.0;
      const ventaUsd = 1.0;

      final gananciaCup = ventaCup - (costoUsd * tasa);
      final gananciaUsd = ventaUsd - costoUsd;

      expect(gananciaCup, 800.0);
      expect(gananciaUsd, 0.5);
    });

    test('agregarTotalesPorMoneda no mezcla CUP con USD', () {
      final filas = [
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 10,
          nombreProducto: 'A',
          moneda: 'CUP',
          precioVentaNativo: 1000,
          precioCostoUsd: 0.5,
          precioCostoNativo: 200,
          ingresosNativos: 1000,
          costoNativo: 200,
          gananciaNativa: 800,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 10,
          nombreProducto: 'A',
          moneda: 'USD',
          precioVentaNativo: 1,
          precioCostoUsd: 0.5,
          precioCostoNativo: 0.5,
          ingresosNativos: 1,
          costoNativo: 0.5,
          gananciaNativa: 0.5,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 11,
          nombreProducto: 'B',
          moneda: 'CUP',
          precioVentaNativo: 500,
          precioCostoUsd: 0.25,
          precioCostoNativo: 100,
          ingresosNativos: 500,
          costoNativo: 100,
          gananciaNativa: 400,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
      ];

      final totales = agregarTotalesPorMoneda(filas);
      expect(totales.length, 2);

      final cup = totales.firstWhere((t) => t.moneda == 'CUP');
      final usd = totales.firstWhere((t) => t.moneda == 'USD');

      expect(cup.ingresos, 1500.0);
      expect(cup.costo, 300.0);
      expect(cup.ganancia, 1200.0);
      expect(usd.ingresos, 1.0);
      expect(usd.ganancia, 0.5);
      // Nunca un total único CUP+USD.
      expect(cup.ingresos + usd.ingresos, isNot(cup.ingresos));
    });

    test('agregarProveedoresPorMoneda agrupa proveedor×moneda sin mezclar', () {
      final filas = [
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 10,
          nombreProducto: 'Diesel',
          idProveedor: 5,
          nombreProveedor: 'Cupet',
          moneda: 'CUP',
          precioVentaNativo: 1000,
          precioCostoUsd: 1.1,
          precioCostoNativo: 1045,
          ingresosNativos: 1000,
          costoNativo: 1045,
          gananciaNativa: -45,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 10,
          nombreProducto: 'Diesel',
          idProveedor: 5,
          nombreProveedor: 'Cupet',
          moneda: 'USD',
          precioVentaNativo: 2.5,
          precioCostoUsd: 1.1,
          precioCostoNativo: 1.1,
          ingresosNativos: 2.5,
          costoNativo: 1.1,
          gananciaNativa: 1.4,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 11,
          nombreProducto: 'Gasolina',
          idProveedor: 5,
          nombreProveedor: 'Cupet',
          moneda: 'USD',
          precioVentaNativo: 3,
          precioCostoUsd: 1.4,
          precioCostoNativo: 1.4,
          ingresosNativos: 3,
          costoNativo: 1.4,
          gananciaNativa: 1.6,
          totalVendido: 1,
          equivUnidadesBase: 1,
          utilidadDisponible: true,
        ),
      ];

      final proveedores = agregarProveedoresPorMoneda(filas);
      expect(proveedores.length, 2);

      final cup = proveedores.firstWhere((p) => p.moneda == 'CUP');
      final usd = proveedores.firstWhere((p) => p.moneda == 'USD');

      expect(cup.idProveedor, 5);
      expect(cup.totalVentas, 1000);
      expect(cup.totalGanancia, -45);
      expect(usd.totalVentas, 5.5);
      expect(usd.totalGanancia, 3.0);
      expect(usd.totalCosto, 2.5);
    });

    test('sin utilidad disponible no inventa costo ni ganancia en el total', () {
      final totales = agregarTotalesPorMoneda([
        const ProductSalesReportPorMoneda(
          idTienda: 1,
          idProducto: 1,
          nombreProducto: 'Sin tasa',
          moneda: 'CUP',
          precioVentaNativo: 100,
          precioCostoUsd: 0.5,
          precioCostoNativo: 0,
          ingresosNativos: 100,
          utilidadDisponible: false,
          totalVendido: 1,
          equivUnidadesBase: 1,
        ),
      ]);
      expect(totales.single.ingresos, 100);
      expect(totales.single.utilidadCompleta, isFalse);
      expect(totales.single.costo, isNull);
      expect(totales.single.ganancia, isNull);
    });

    test('fromCupReport marca fallback y conserva magnitud CUP', () {
      final cup = ProductSalesReport(
        idTienda: 1,
        idProducto: 2,
        nombreProducto: 'Legacy',
        precioVentaCup: 50,
        precioCosto: 0.1,
        valorUsd: 400,
        precioCostoCup: 40,
        totalVendido: 2,
        ingresosTotales: 100,
        costoTotalVendido: 80,
        gananciaUnitaria: 10,
        gananciaTotal: 20,
      );
      final row = ProductSalesReportPorMoneda.fromCupReport(cup);
      expect(row.moneda, 'CUP');
      expect(row.desdeFallbackCup, isTrue);
      expect(row.ingresosNativos, 100);
      expect(row.gananciaNativa, 20);
      expect(row.utilidadDisponible, isTrue);
    });
  });

  group('contrato SQL', () {
    final sql =
        File(
          'lib/sql/fn_reporte_ventas_producto_por_moneda.sql',
        ).readAsStringSync();

    test('define la función aditiva con acceso a tienda', () {
      expect(sql, contains('fn_reporte_ventas_producto_por_moneda'));
      expect(sql, contains('check_user_has_access_to_tienda'));
      expect(sql, contains('SECURITY DEFINER'));
      expect(sql, contains("COALESCE(NULLIF(upper(trim(ep.moneda_venta)), ''), 'CUP')"));
    });

    test('CUP multiplica costo por tasa del día; USD usa costo_usd sin tasa', () {
      expect(sql, contains('THEN ve.costo_usd_op * ve.cantidad'));
      expect(
        sql,
        contains(
          'ELSE ve.costo_usd_op * COALESCE(ve.tasa_dia, 0) * ve.cantidad',
        ),
      );
      expect(sql, contains('tasa_historica_venta'));
      expect(sql, contains('tasa_cambio_extraoficial'));
      expect(sql, contains('AS tasa_dia'));
      // No valorar el costo con la tasa de la línea (en CUP es 1).
      expect(sql, isNot(contains('NULLIF(vd.tasa_cambio_cup, 0)')));
      expect(sql, isNot(contains('tasa_cambio_aplicada')));
      expect(sql, contains('utilidad_disponible'));
      expect(sql, contains('ganancia_nativa'));
    });

    test('agrupa por producto y moneda', () {
      expect(sql, contains('GROUP BY ve.id_producto, ve.moneda'));
    });
  });

  group('contrato cliente', () {
    final service = File('lib/services/sales_service.dart').readAsStringSync();
    final screen = File('lib/screens/sales_screen.dart').readAsStringSync();

    test('el servicio prefiere la RPC y cae a CUP si no existe', () {
      expect(service, contains('getProductSalesReportPorMoneda'));
      expect(service, contains('fn_reporte_ventas_producto_por_moneda'));
      expect(service, contains('_esFuncionInexistente'));
      expect(service, contains('fromCupReport'));
    });

    test('Tiempo real y Proveedores usan filas y totales por moneda', () {
      expect(screen, contains('_productSalesByMoneda'));
      expect(screen, contains('_totalesPorMoneda'));
      expect(screen, contains('agregarTotalesPorMoneda'));
      expect(screen, contains('agregarProveedoresPorMoneda'));
      expect(service, contains('agregarProveedoresPorMoneda'));
      expect(screen, contains("'Ganancia'"));
      expect(screen, contains("'TOTAL \${t.moneda}'"));
      expect(screen, contains("'Moneda'"));
    });
  });
}
