// Humo de las tres secciones de Reportes con los payloads del contrato.
//
// Monta los widgets sin Supabase: detecta desbordes de layout, textos clave y
// los estados vacíos. No sustituye una prueba contra la RPC real.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_calculos.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_seccion_compras.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_seccion_conciliacion.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_seccion_movimientos.dart';

Widget _envolver(Widget hijo) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: hijo),
      ),
    ),
  );
}

void _tamanoMovil(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String _iso(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

void main() {
  const bloqueVacio = BloqueReporte.vacio();

  Map<String, dynamic> conciliacion({int descuadres = 1}) => {
    'id_tienda': 4,
    'claves': 3,
    'descuadres': descuadres,
    'filas': [
      {
        'id_cuenta': 1,
        'id_medio_pago': 1,
        'moneda': 'CUP',
        'cuenta': 'Caja principal',
        'medio_pago': 'Efectivo',
        'saldo': '148300.00',
        'suma_movimientos': '148300.00',
        'ultimo_saldo_nuevo': '148300.00',
        'dif_saldo_vs_mov': '0.00',
        'dif_saldo_vs_ultimo': '0.00',
        'n_movimientos': 12,
        'ok': true,
      },
      {
        'id_cuenta': 2,
        'id_medio_pago': 2,
        'moneda': 'USD',
        'cuenta': 'Banco Metropolitano',
        'medio_pago': 'Transferencia',
        'saldo': 18420.00,
        'suma_movimientos': 18420.01,
        'ultimo_saldo_nuevo': 18420.02,
        'dif_saldo_vs_mov': 0.01,
        'dif_saldo_vs_ultimo': -0.02,
        'n_movimientos': 4,
        'ok': false,
      },
    ],
  };

  Map<String, dynamic> caja() => {
    'id_tienda': 4,
    'ventana_dias': 30,
    'desde': '2026-10-25',
    'hasta': '2026-11-23',
    'claves': [
      {
        'id_cuenta': 1,
        'cuenta': 'Caja principal',
        'id_medio_pago': 1,
        'medio_pago': 'Efectivo',
        'moneda': 'CUP',
        'saldo': '148300.00',
        'reservado': '22400.00',
        'disponible': '125900.00',
        'n_movimientos': 12,
        'n_movimientos_periodo': 4,
        'ejecutado_periodo': '-38200.00',
      },
    ],
    'totales_por_moneda': [
      {
        'moneda': 'CUP',
        'saldo': '148300.00',
        'reservado': '22400.00',
        'disponible': '125900.00',
        'ejecutado_periodo': '-38200.00',
      },
    ],
  };

  Map<String, dynamic> compras() => {
    'por_estado': [
      {
        'estado': 'completada',
        'moneda': 'USD',
        'compras': 9,
        'facturado': '205780.50',
        'aterrizado': '204360.00',
        'pagado': '204360.00',
        'reservado_activo': '0.00',
        'diferencia': '-1420.50',
      },
    ],
    'totales_por_moneda': [
      {
        'moneda': 'USD',
        'compras': 9,
        'facturado': '205780.50',
        'aterrizado': '204360.00',
        'pagado': '204360.00',
        'reservado_activo': '0.00',
        'diferencia': '-1420.50',
      },
    ],
  };

  Map<String, dynamic> costo() => {
    'compras': [
      {
        'id_compra': 42,
        'numero_compra': 'A-1042',
        'numero_factura': 'F-9',
        'proveedor': 'Distribuidora La Habana',
        'estado': 'completada',
        'moneda': 'USD',
        'mercancia': '52400.00',
        'adicionales': '1800.00',
        'aterrizado': '54200.00',
        'pct_desvio': 3.4,
        'recibido_pct': 0.78,
      },
      {
        'id_compra': 34,
        'numero_compra': 'A-1034',
        'numero_factura': null,
        'proveedor': 'AgroAlimentos S.A.',
        'estado': 'pagada',
        'moneda': 'USD',
        'mercancia': '50584.00',
        'adicionales': '-1240.00',
        'aterrizado': '49344.00',
        'pct_desvio': null,
        'recibido_pct': 1.0,
      },
    ],
    'resumen': {
      'compras': 2,
      'por_moneda': [
        {
          'moneda': 'USD',
          'compras': 2,
          'mercancia': '102984.00',
          'adicionales': '560.00',
          'aterrizado': '103544.00',
          'desvio': '560.00',
          'pct_desvio': 0.5,
        },
      ],
    },
  };

  Map<String, dynamic> cambiario() => {
    'compras': [
      {
        'id_compra': 42,
        'numero_compra': 'A-1042',
        'numero_factura': 'F-9',
        'estado': 'completada',
        'moneda': 'CUP',
        'tasa_factura': 320.0,
        'n_pagos': 1,
        'equivalente_real': '4020000.00',
        'equivalente_a_tasa_factura': '3840000.00',
        'diferencia': '180000.00',
        'signo': 'en contra',
        'pagos': [
          {
            'id_pago': 1,
            'origen': 'fondo',
            'moneda_pago': 'USD',
            'monto_pago': '12000.00',
            'tasa_pago': 335.0,
            'equivalente_real': '4020000.00',
            'equivalente_a_tasa_factura': '3840000.00',
            'diferencia': '180000.00',
            'signo': 'en contra',
          },
        ],
        'pagos_por_moneda': [
          {'moneda_pago': 'USD', 'n': 1, 'monto': '12000.00'},
        ],
      },
    ],
    'totales_por_moneda': [
      {
        'moneda': 'CUP',
        'compras': 1,
        'pagos': 1,
        'equivalente_real': '4020000.00',
        'equivalente_a_tasa_factura': '3840000.00',
        'diferencia': '180000.00',
        'signo': 'en contra',
      },
    ],
  };

  Map<String, dynamic> movimientos() => {
    'desde': '2026-11-22',
    'hasta': '2026-11-23',
    'por_dia_usuario': [
      {
        'dia': _iso(DateTime.now()),
        'usuario': 'yamile@tienda',
        'moneda': 'CUP',
        'n': 4,
        'entradas': '74320.00',
        'salidas': '12000.00',
        'neto': '62320.00',
      },
      {
        'dia': _iso(DateTime.now().subtract(const Duration(days: 1))),
        'usuario': 'carlos@tienda',
        'moneda': 'CUP',
        'n': 2,
        'entradas': '0.00',
        'salidas': '22400.00',
        'neto': '-22400.00',
      },
    ],
    'totales_por_moneda': [
      {
        'moneda': 'CUP',
        'n': 6,
        'entradas': '74320.00',
        'salidas': '34400.00',
        'neto': '39920.00',
      },
    ],
  };

  Map<String, dynamic> inversores() => {
    'inversores': [
      {
        'id_inversor': 1,
        'nombre': 'Fondo Norte S.R.L.',
        'porcentaje': 40.0,
        'activo': true,
        'por_moneda': [
          {
            'moneda': 'CUP',
            'aportes_vigentes': '420000.00',
            'aportes_devueltos': '60000.00',
            'utilidad_repartida': '88400.00',
            'utilidad_pagada': '60000.00',
            'utilidad_pendiente': '28400.00',
          },
          {
            'moneda': 'USD',
            'aportes_vigentes': '8400.00',
            'aportes_devueltos': '0.00',
            'utilidad_repartida': '1240.00',
            'utilidad_pagada': '1240.00',
            'utilidad_pendiente': '0.00',
          },
        ],
        'aportes': [],
      },
      {
        'id_inversor': 2,
        'nombre': 'Lucía Fernández',
        'porcentaje': 20.0,
        'activo': false,
        'por_moneda': [],
        'aportes': [],
      },
    ],
    'totales_por_moneda': [
      {
        'moneda': 'CUP',
        'aportes_vigentes': '420000.00',
        'aportes_devueltos': '60000.00',
        'utilidad_repartida': '88400.00',
        'utilidad_pagada': '60000.00',
        'utilidad_pendiente': '28400.00',
      },
    ],
  };

  Map<String, dynamic> aging() => {
    'reservas_activas': [
      {
        'id_reserva': 7,
        'id_compra': 18,
        'numero_compra': 'A-1018',
        'numero_factura': 'F-88',
        'id_cuenta': 3,
        'id_medio_pago': 3,
        'moneda': 'USD',
        'monto': '12400.00',
        'dias_antiguedad': 41,
        'total_financiado': '12400.00',
        'estado_compra': 'reservada',
      },
      {
        'id_reserva': 8,
        'id_compra': 23,
        'numero_compra': 'A-1023',
        'numero_factura': null,
        'id_cuenta': 3,
        'id_medio_pago': 3,
        'moneda': 'USD',
        'monto': '6500.00',
        'dias_antiguedad': 3,
        'total_financiado': '6500.00',
        'estado_compra': 'reservada',
      },
    ],
    'descuadres': [
      {
        'id_compra': 41,
        'numero_compra': 'A-1041',
        'numero_factura': 'F-71',
        'moneda': 'USD',
        'estado_compra': 'entrega_parcial',
        'total_financiado': '2000.00',
        'lineas': '1500.00',
        'ajustes_fondo': '0.00',
        'diferencia_financiado': '840.00',
        'pagado': '2000.00',
        'diferencia_pagos': '-240.00',
        'ultimo_motivo': 'Pago parcial no aplicado',
      },
    ],
  };

  Widget seccionConciliacion({int descuadres = 1}) => SeccionConciliacion(
    conciliacion: BloqueReporte(datos: conciliacion(descuadres: descuadres)),
    ultima: const BloqueReporte(
      datos: {
        'ejecutada_at': '2026-11-23T11:42:00Z',
        'claves': 3,
        'descuadres': 0,
        'diferencia_total': 0,
        'origen': 'auto',
      },
    ),
    caja: BloqueReporte(datos: caja()),
    conciliando: false,
    onConciliar: () {},
    onReintentar: () {},
  );

  Widget seccionCompras() => SeccionComprasCosto(
    compras: BloqueReporte(datos: compras()),
    costo: BloqueReporte(datos: costo()),
    cambiario: BloqueReporte(datos: cambiario()),
    onReintentar: () {},
  );

  Widget seccionMovimientos({
    BloqueReporte? movimientosDatos,
    BloqueReporte? agingDatos,
  }) => SeccionMovimientos(
    movimientos: movimientosDatos ?? BloqueReporte(datos: movimientos()),
    inversores: BloqueReporte(datos: inversores()),
    aging: agingDatos ?? BloqueReporte(datos: aging()),
    onReintentar: () {},
  );

  testWidgets('conciliación con descuadre: alarma grande y chip descuadre', (
    tester,
  ) async {
    await tester.pumpWidget(_envolver(seccionConciliacion()));
    expect(find.text('El saldo no cuadra con los movimientos'), findsOneWidget);
    expect(find.text('descuadre'), findsOneWidget);
    expect(find.textContaining('Última revisión automática'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conciliación: el estado calculado manda sobre `descuadres`', (
    tester,
  ) async {
    await tester.pumpWidget(_envolver(seccionConciliacion(descuadres: 0)));
    // El payload dice `descuadres: 0` pero una fila tiene diferencias: la
    // alarma calculada manda y la pantalla no se blanquea.
    expect(find.text('El saldo no cuadra con los movimientos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compras, costo y cambiario pintan sus tres bloques', (
    tester,
  ) async {
    await tester.pumpWidget(_envolver(seccionCompras()));
    expect(find.text('Compras por estado'), findsOneWidget);
    expect(find.text('Costo real vs factura'), findsOneWidget);
    expect(find.text('Diferencias cambiarias'), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets);
    expect(find.text('en contra'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movimientos agrupa por día y los pendientes cuadran', (
    tester,
  ) async {
    await tester.pumpWidget(_envolver(seccionMovimientos()));
    expect(find.text('Movimientos por usuario y día'), findsOneWidget);
    expect(find.textContaining('Hoy ·'), findsOneWidget);
    expect(find.textContaining('Ayer ·'), findsOneWidget);
    expect(find.text('Total del rango'), findsOneWidget);
    expect(find.text('Inversores'), findsOneWidget);
    // Franja y filas salen de la misma lista: 2 reservas, 1 descuadre.
    expect(find.textContaining('2 reservas activas'), findsOneWidget);
    expect(
      find.textContaining('1 compra con descuadre abierto'),
      findsOneWidget,
    );
    expect(find.text('Aging de reservas'), findsOneWidget);
    expect(find.text('Compras con descuadre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listas vacías: mensajes, no tablas vacías', (tester) async {
    await tester.pumpWidget(
      _envolver(
        seccionMovimientos(
          movimientosDatos: const BloqueReporte(
            datos: {'por_dia_usuario': [], 'totales_por_moneda': []},
          ),
          agingDatos: const BloqueReporte(
            datos: {'reservas_activas': [], 'descuadres': []},
          ),
        ),
      ),
    );
    expect(find.text('Sin movimientos en el periodo'), findsOneWidget);
    expect(find.text('No hay reservas activas'), findsOneWidget);
    expect(find.text('Ninguna compra con descuadre'), findsOneWidget);
    expect(find.textContaining('Sin pendientes abiertos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en móvil las tres secciones no desbordan', (tester) async {
    _tamanoMovil(tester);
    for (final seccion in [
      seccionConciliacion(),
      seccionCompras(),
      seccionMovimientos(),
    ]) {
      await tester.pumpWidget(_envolver(seccion));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('bloque cargando y bloque con error no rompen la sección', (
    tester,
  ) async {
    await tester.pumpWidget(
      _envolver(
        SeccionComprasCosto(
          compras: const BloqueReporte.vacio(),
          costo: const BloqueReporte(error: 'Sin conexión'),
          cambiario: const BloqueReporte(error: 'La función no existe'),
          onReintentar: () {},
        ),
      ),
    );
    expect(find.textContaining('Cargando compras'), findsOneWidget);
    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text('La función no existe'), findsOneWidget);
    expect(find.text('Reintentar'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
