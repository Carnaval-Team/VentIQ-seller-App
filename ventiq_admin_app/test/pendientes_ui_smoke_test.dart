// Humo de UI de la fase 9 de Compras: monta el panel, el detalle y la vista de
// facturas con los payloads del contrato, a 390 px (móvil) y 800 px (tablet).
//
// No toca Supabase: las pantallas aceptan datos iniciales para montarse sin
// backend. Detecta desbordes de layout, textos clave y que las columnas de
// dinero desaparezcan cuando no hay permiso de importes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/pendientes.dart';
import 'package:ventiq_admin_app/screens/compras/compras_widgets.dart';
import 'package:ventiq_admin_app/screens/compras/facturas_screen.dart';
import 'package:ventiq_admin_app/screens/compras/pendiente_detalle_screen.dart';
import 'package:ventiq_admin_app/screens/compras/pendientes_screen.dart';

import 'pendientes_contract_test.dart'
    show detalleJson, facturasJson, historialJson, panelJson;

const String _tienda = 'Tienda Centro Habana';

PendientesPanel _datosPanel() => PendientesPanel.fromJson(panelJson());

PendienteDetalle _detalle() => PendienteDetalle.fromJson(detalleJson());

FacturasVista _facturas() => FacturasVista.fromJson(facturasJson());

List<RecepcionHistorial> _recepciones() =>
    HistorialRecepciones.fromJson(historialJson()).deCompra(1042);

void _tamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _panel(Widget pantalla) => MaterialApp(home: pantalla);

void main() {
  group('panel de pendientes', () {
    testWidgets('a 390 px apila tarjetas sin desbordar', (tester) async {
      _tamano(tester, const Size(390, 844));
      await tester.pumpWidget(
        _panel(
          PendientesScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: true,
            panelInicial: _datosPanel(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Pendientes'), findsWidgets);
      expect(find.textContaining('4 compras abiertas'), findsWidgets);
      expect(find.text('#1042'), findsOneWidget);
      expect(find.text('COMPRAS ABIERTAS'), findsOneWidget);
      // Montos por moneda en bloques separados, con su moneda al lado.
      expect(find.textContaining('PENDIENTE USD'), findsOneWidget);
      expect(find.textContaining('PENDIENTE CUP'), findsOneWidget);
      expect(find.textContaining(formatearImporte(6840)), findsWidgets);
      expect(find.textContaining(formatearImporte(214000)), findsWidgets);
      // La suma de monedas distintas no se pinta en ningún sitio.
      expect(
        find.textContaining(formatearImporte(220840)),
        findsNothing,
        reason: 'USD y CUP no se pueden sumar',
      );
      // En estrecho no hay tabla: son tarjetas con su pie de recepción.
      expect(find.textContaining('sin movimiento'), findsWidgets);
      expect(find.text('MONTO PENDIENTE'), findsNothing);
    });

    testWidgets('a 800 px usa la tabla densa con todas las columnas', (
      tester,
    ) async {
      _tamano(tester, const Size(800, 1000));
      await tester.pumpWidget(
        _panel(
          PendientesScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: true,
            panelInicial: _datosPanel(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Cabecera de la tabla (TablaReporte la pinta en mayúsculas).
      expect(find.text('COMPRA / FACTURA'), findsOneWidget);
      expect(find.text('PROVEEDOR'), findsOneWidget);
      expect(find.text('ANTIGÜEDAD'), findsOneWidget);
      expect(find.text('% RECIBIDO'), findsOneWidget);
      expect(find.text('MONTO PENDIENTE'), findsOneWidget);
      expect(find.text('ESTADO'), findsOneWidget);
      expect(find.text('Distribuidora Andina'), findsOneWidget);
      // Chips de estado de compra y de antigüedad.
      expect(find.text('Entrega parcial'), findsWidgets);
      expect(find.text('26 d'), findsWidgets);
      // La más antigua del resumen (#1039, 26 días).
      expect(find.textContaining('#1039'), findsWidgets);
      expect(find.textContaining(formatearImporte(220840)), findsNothing);
    });

    testWidgets('sin permiso de importes no queda ninguna columna de dinero', (
      tester,
    ) async {
      _tamano(tester, const Size(800, 1000));
      await tester.pumpWidget(
        _panel(
          PendientesScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: false,
            panelInicial: _datosPanel(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Sin columna de monto ni bloque de importe: no hay huecos.
      expect(find.text('MONTO PENDIENTE'), findsNothing);
      expect(find.textContaining('PENDIENTE USD'), findsNothing);
      expect(find.textContaining(formatearImporte(6840)), findsNothing);
      expect(find.textContaining(formatearImporte(214000)), findsNothing);
      // Los montos se sustituyen por conteos y se dice en la franja.
      expect(find.textContaining('COMPRAS USD'), findsOneWidget);
      expect(find.textContaining('COMPRAS CUP'), findsOneWidget);
      expect(find.textContaining('sin importes'), findsWidgets);
      // Las cantidades y el avance siguen visibles.
      expect(find.text('40 / 100'), findsOneWidget);
      expect(find.text('% RECIBIDO'), findsOneWidget);
    });

    testWidgets('panel vacío: mensaje propio, no una tabla vacía', (
      tester,
    ) async {
      _tamano(tester, const Size(800, 1000));
      await tester.pumpWidget(
        _panel(
          const PendientesScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: true,
            panelInicial: PendientesPanel(idTienda: 4),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Ninguna compra abierta'), findsOneWidget);
      expect(find.textContaining('COMPRA / FACTURA'), findsNothing);
    });
  });

  group('detalle de faltantes', () {
    testWidgets('a 800 px pinta líneas, recepciones y una sola pareja', (
      tester,
    ) async {
      _tamano(tester, const Size(800, 1000));
      await tester.pumpWidget(
        _panel(
          PendienteDetalleScreen(
            idCompra: 42,
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: true,
            detalleInicial: _detalle(),
            recepcionesIniciales: _recepciones(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Faltantes por producto y línea'), findsOneWidget);
      expect(find.text('Aceite 15W40'), findsOneWidget);
      expect(find.text('Diesel 50L'), findsOneWidget);
      expect(find.text('Recepciones de esta compra'), findsOneWidget);
      expect(find.textContaining('FS-0091'), findsWidgets);
      // Una sola pareja de acciones (cada una aparece una vez).
      expect(find.text('Ir a recepción'), findsOneWidget);
      expect(find.text('Ver factura'), findsOneWidget);
      expect(find.text('MONTO PEND.'), findsOneWidget);
    });

    testWidgets('a 390 px no desborda y esconde los importes sin permiso', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      await tester.pumpWidget(
        _panel(
          PendienteDetalleScreen(
            idCompra: 42,
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: false,
            detalleInicial: _detalle(),
            recepcionesIniciales: _recepciones(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Faltantes por producto y línea'), findsOneWidget);
      expect(find.text('MONTO PEND.'), findsNothing);
      expect(find.text('COSTO UNIT.'), findsNothing);
      expect(find.textContaining(formatearImporte(3180)), findsNothing);
      // El avance y las cantidades siguen.
      expect(find.textContaining('Recibido 40 de 100'), findsOneWidget);
      expect(find.text('Ir a recepción'), findsOneWidget);
      expect(find.text('Ver factura'), findsOneWidget);
    });
  });

  group('vista de facturas', () {
    testWidgets('a 800 px lista facturas con su estado de recepción', (
      tester,
    ) async {
      _tamano(tester, const Size(800, 1000));
      await tester.pumpWidget(
        _panel(
          FacturasScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: true,
            vistaInicial: _facturas(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('FACTURA'), findsOneWidget);
      expect(find.text('FS-0091'), findsOneWidget);
      expect(find.text('Parcial'), findsWidgets);
      expect(find.text('Completa'), findsWidgets);
      expect(find.text('Sin recibir'), findsWidgets);
      expect(find.text('TOTAL FACTURA'), findsOneWidget);
      // Totales por moneda en bloques separados.
      expect(find.textContaining('FACTURADO USD'), findsOneWidget);
      expect(find.textContaining('FACTURADO CUP'), findsOneWidget);
    });

    testWidgets('a 390 px usa tarjetas y respeta «sin importes»', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      await tester.pumpWidget(
        _panel(
          FacturasScreen(
            idTienda: 4,
            nombreTienda: _tienda,
            puedeVerImportes: false,
            vistaInicial: _facturas(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('FS-0091'), findsOneWidget);
      expect(find.textContaining('FACTURADO'), findsNothing);
      expect(find.textContaining(formatearImporte(310500)), findsNothing);
      expect(find.textContaining('sin importes'), findsWidgets);
    });
  });
}