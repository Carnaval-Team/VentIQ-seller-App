// Contrato de la fase 9 de Compras (pendientes de recepción, detalle,
// histórico de recepciones y facturas).
//
// Valida, sin backend:
//  · que los payloads de las cuatro funciones se parsean con las claves
//    exactas de `lib/sql/compra/09_pendientes.sql`;
//  · el cálculo de `recibido_pct` (valor del servidor y respaldo local) y la
//    antigüedad que se muestra;
//  · que **ningún agregado suma monedas distintas**;
//  · que las cuatro firmas existen en el SQL, con `p_id_tienda` primero,
//    `STABLE`, `SECURITY DEFINER`, `jsonb` y sin escrituras;
//  · que la generación de bytes de Excel y PDF devuelve archivos no vacíos.
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/pendientes.dart';
import 'package:ventiq_admin_app/services/pendientes_export_service.dart';
import 'package:ventiq_admin_app/services/permissions_service.dart';

// ===========================================================================
// Payloads con las claves del contrato (nombres copiados del SQL, no inventados)
// ===========================================================================

Map<String, dynamic> compraPanel({
  int idCompra = 42,
  int numeroCompra = 1042,
  String? numeroFactura = 'FS-0091',
  String proveedor = 'Distribuidora Andina',
  String fechaFactura = '2026-11-07',
  String estado = 'entrega_parcial',
  String moneda = 'USD',
  int diasAntiguedad = 16,
  int lineas = 3,
  num pedido = 100,
  num recibido = 40,
  num? recibidoPct = 0.4,
  num montoTotal = 7950,
  num montoPendiente = 3180,
  String? ultimaRecepcion = '2026-11-12T09:30:00Z',
  int diasSinMovimiento = 4,
}) => {
  'id_compra': idCompra,
  'numero_compra': numeroCompra,
  'numero_factura': numeroFactura,
  'proveedor': proveedor,
  'fecha_factura': fechaFactura,
  'estado': estado,
  'moneda': moneda,
  'dias_antiguedad': diasAntiguedad,
  'lineas': lineas,
  'pedido': pedido,
  'recibido': recibido,
  if (recibidoPct != null) 'recibido_pct': recibidoPct,
  'monto_total': montoTotal,
  'monto_pendiente': montoPendiente,
  'ultima_recepcion': ultimaRecepcion,
  'dias_sin_movimiento': diasSinMovimiento,
};

/// Panel con dos monedas: 3 compras en USD y 1 en CUP.
Map<String, dynamic> panelJson() => {
  'id_tienda': 4,
  'orden': 'antiguedad',
  'generado_at': '2026-11-23T13:52:00Z',
  'compras': [
    compraPanel(),
    compraPanel(
      idCompra: 41,
      numeroCompra: 1041,
      numeroFactura: 'FS-0088',
      proveedor: 'Importadora del Caribe',
      fechaFactura: '2026-11-09',
      diasAntiguedad: 14,
      pedido: 60,
      recibido: 36,
      recibidoPct: 0.6,
      montoTotal: 6000,
      montoPendiente: 2410,
      ultimaRecepcion: '2026-11-18T10:00:00Z',
      diasSinMovimiento: 2,
    ),
    compraPanel(
      idCompra: 40,
      numeroCompra: 1040,
      numeroFactura: 'FS-0082',
      proveedor: 'Suministros La Habana',
      fechaFactura: '2026-11-02',
      estado: 'pagada',
      moneda: 'CUP',
      diasAntiguedad: 21,
      lineas: 2,
      pedido: 60,
      recibido: 0,
      recibidoPct: 0,
      montoTotal: 214000,
      montoPendiente: 214000,
      ultimaRecepcion: null,
      diasSinMovimiento: 21,
    ),
    compraPanel(
      idCompra: 39,
      numeroCompra: 1039,
      numeroFactura: 'FS-0079',
      proveedor: 'Tecnohogar Mayorista',
      fechaFactura: '2026-10-28',
      diasAntiguedad: 26,
      pedido: 50,
      recibido: 0,
      recibidoPct: 0,
      montoTotal: 3000,
      montoPendiente: 1250,
      ultimaRecepcion: null,
      diasSinMovimiento: 26,
    ),
  ],
  // Agregados del servidor: uno por moneda. La suma de los dos NO existe.
  'totales_por_moneda': [
    {
      'moneda': 'CUP',
      'compras': 1,
      'monto_total': 214000,
      'monto_pendiente': 214000,
    },
    {
      'moneda': 'USD',
      'compras': 3,
      'monto_total': 16950,
      'monto_pendiente': 6840,
    },
  ],
};

Map<String, dynamic> detalleJson() => {
  'id_tienda': 4,
  'compra': {
    'id_compra': 42,
    'numero_compra': 1042,
    'numero_factura': 'FS-0091',
    'proveedor': 'Distribuidora Andina',
    'fecha_factura': '2026-11-07',
    'estado': 'entrega_parcial',
    'moneda': 'USD',
    'tasa_factura': 1,
    'total_mercancia': 7950,
    'total_ajustes': 0,
    'total_financiado': 7950,
    'costo_aterrizado': 7950,
    'observacion': null,
    'created_at': '2026-11-07T08:15:00Z',
    'dias_antiguedad': 16,
    'lineas': 2,
    'pedido': 100,
    'recibido': 40,
    'recibido_pct': 0.4,
    'monto_total': 7950,
    'monto_pendiente': 3180,
    'ultima_recepcion': '2026-11-12T09:30:00Z',
    'dias_sin_movimiento': 4,
  },
  'lineas': [
    {
      'id_compra_linea': 1,
      'producto': 'Aceite 15W40',
      'variante': null,
      'presentacion': 'Caja x12',
      'id_almacen': 1,
      'id_ubicacion': 2,
      'cantidad': 24,
      'recibido': 12,
      'pendiente': 12,
      'costo_unitario': 12.5,
      'monto_pendiente': 150,
      'ultima_recepcion': '2026-11-12T09:30:00Z',
      'dias_sin_movimiento': 4,
    },
    {
      'id_compra_linea': 2,
      'producto': 'Diesel 50L',
      'variante': 'Bidón',
      'presentacion': 'Bidón 20 L',
      'id_almacen': 1,
      'id_ubicacion': 2,
      'cantidad': 20,
      'recibido': 8,
      'pendiente': 12,
      'costo_unitario': 45,
      'monto_pendiente': 540,
      'ultima_recepcion': '2026-11-12T09:30:00Z',
      'dias_sin_movimiento': 4,
    },
  ],
  'totales_por_moneda': [
    {
      'moneda': 'USD',
      'lineas': 2,
      'monto_total': 7950,
      'monto_pendiente': 3180,
    },
  ],
};

Map<String, dynamic> historialJson() => {
  'id_tienda': 4,
  'desde': null,
  'hasta': null,
  'generado_at': '2026-11-23T13:52:00Z',
  'recepciones': [
    {
      'id_recepcion': 501,
      'id_operacion': 9001,
      'fecha': '2026-11-12',
      'numero_compra': 1042,
      'numero_factura': 'FS-0091',
      'proveedor': 'Distribuidora Andina',
      'monto_valorizado': 1420,
      'moneda': 'USD',
      'origen_pago': 'wallet_importadora',
      'pct_importadora': 2,
      'monto_importadora': 28.4,
      'estado_operacion': 1,
      'estado_operacion_nombre': 'Confirmada',
      'lineas': 2,
      'cantidad_recibida': 20,
      'productos': 'Aceite 15W40 +1',
      'fecha_operacion': '2026-11-12T08:00:00Z',
    },
    {
      'id_recepcion': 502,
      'id_operacion': 9002,
      'fecha': '2026-11-05',
      'numero_compra': 9999,
      'numero_factura': 'FS-0001',
      'proveedor': 'Otra',
      'monto_valorizado': 100,
      'moneda': 'USD',
      'origen_pago': 'externo',
      'pct_importadora': 0,
      'monto_importadora': 0,
      'estado_operacion': null,
      'estado_operacion_nombre': null,
      'lineas': 1,
      'cantidad_recibida': 2,
      'productos': 'Filtro',
      'fecha_operacion': null,
    },
  ],
  'totales_por_moneda': [
    {
      'moneda': 'USD',
      'recepciones': 2,
      'monto_valorizado': 1520,
      'monto_importadora': 28.4,
      'cantidad_recibida': 22,
    },
  ],
};

Map<String, dynamic> facturasJson() => {
  'id_tienda': 4,
  'desde': null,
  'hasta': null,
  'generado_at': '2026-11-23T13:52:00Z',
  'facturas': [
    {
      'id_compra': 42,
      'numero_factura': 'FS-0091',
      'numero_compra': 1042,
      'proveedor': 'Distribuidora Andina',
      'fecha_factura': '2026-11-07',
      'estado': 'entrega_parcial',
      'moneda': 'USD',
      'total_factura': 7950,
      'aterrizado': 7950,
      'pagado': 7950,
      'recepciones': 1,
      'recibido_pct': 0.4,
      'estado_recepcion': 'parcial',
      'ultima_recepcion': '2026-11-12T09:30:00Z',
    },
    {
      'id_compra': 30,
      'numero_factura': null,
      'numero_compra': 1030,
      'proveedor': 'AgroAlimentos S.A.',
      'fecha_factura': '2026-10-20',
      'estado': 'completada',
      'moneda': 'CUP',
      'total_factura': 310500,
      'aterrizado': 310500,
      'pagado': 310500,
      'recepciones': 3,
      'recibido_pct': 1,
      'estado_recepcion': 'completa',
      'ultima_recepcion': '2026-10-30T10:00:00Z',
    },
    {
      'id_compra': 20,
      'numero_factura': 'FS-0010',
      'numero_compra': 1020,
      'proveedor': 'Suministros La Habana',
      'fecha_factura': '2026-09-15',
      'estado': 'creada',
      'moneda': 'USD',
      'total_factura': 1000,
      'aterrizado': 1000,
      'pagado': 0,
      'recepciones': 0,
      'recibido_pct': 0,
      'estado_recepcion': 'sin recibir',
      'ultima_recepcion': null,
    },
  ],
  'totales_por_moneda': [
    {
      'moneda': 'CUP',
      'compras': 1,
      'total_factura': 310500,
      'aterrizado': 310500,
      'pagado': 310500,
    },
    {
      'moneda': 'USD',
      'compras': 2,
      'total_factura': 8950,
      'aterrizado': 8950,
      'pagado': 7950,
    },
  ],
};

void main() {
  final export = const PendientesExportService();

  group('panel de pendientes', () {
    test('parsea las claves del contrato y los montos por moneda', () {
      final panel = PendientesPanel.fromJson(panelJson());

      expect(panel.idTienda, 4);
      expect(panel.orden, PendientesOrden.antiguedad);
      expect(panel.compras, hasLength(4));
      expect(panel.comprasAbiertas, 4);
      // Sin recepción: #1040 y #1039.
      expect(panel.sinRecepcion, 2);
      // 3 de 4 superan el umbral de 15 días (#1042 con 16, #1040 con 21 y #1039
      // con 26; #1041 se queda en 14).
      expect(panel.sobreUmbral, 3);
      // La más antigua según lo que devolvió el servidor, sin reordenar.
      expect(panel.masAntigua?.numeroCompra, 1039);
      expect(panel.masAntigua?.diasAntiguedad, 26);

      final primera = panel.compras.first;
      expect(primera.idCompra, 42);
      expect(primera.numeroCompra, 1042);
      expect(primera.numeroFactura, 'FS-0091');
      expect(primera.proveedor, 'Distribuidora Andina');
      expect(primera.fechaFactura, DateTime(2026, 11, 7));
      expect(primera.estado, 'entrega_parcial');
      expect(primera.moneda, 'USD');
      expect(primera.diasAntiguedad, 16);
      expect(primera.lineas, 3);
      expect(primera.pedido, 100);
      expect(primera.recibido, 40);
      expect(primera.recibidoPct, closeTo(0.4, 1e-9));
      expect(primera.montoTotal, 7950);
      expect(primera.montoPendiente, 3180);
      expect(primera.ultimaRecepcion, isNotNull);
      expect(primera.diasSinMovimiento, 4);
      expect(primera.textoPedidoRecibido, '40 / 100');
      expect(primera.etiquetaCompra, '#1042');
    });

    test('no existe un total que sume monedas distintas', () {
      final panel = PendientesPanel.fromJson(panelJson());

      // Un bloque por moneda, con su importe y su conteo.
      expect(panel.totalesPorMoneda, hasLength(2));
      expect(
        panel.totalesPorMoneda.map((t) => t.moneda).toList(),
        ['CUP', 'USD'],
      );
      final cup = panel.totalesPorMoneda.first;
      final usd = panel.totalesPorMoneda.last;
      expect(cup.montoPendiente, 214000);
      expect(cup.compras, 1);
      expect(usd.montoPendiente, 6840);
      expect(usd.compras, 3);
      expect(cup.montoPendiente, isNot(equals(usd.montoPendiente)));

      // Los conteos por moneda salen de las filas, no de los importes.
      expect(panel.comprasPorMoneda, {'USD': 3, 'CUP': 1});

      // La exportación escribe una fila por moneda: nunca una fila agregada.
      final filasTotales = export.filasExcelTotalesPanel(panel);
      expect(filasTotales, hasLength(2));
      expect(filasTotales.map((f) => f[0]).toList(), ['CUP', 'USD']);
      expect(filasTotales.first[3], 214000);
      expect(filasTotales.last[3], 6840);
      // La suma prohibida (214000 + 6840) no aparece en ninguna fila.
      for (final fila in filasTotales) {
        expect(fila.contains(220840), isFalse);
      }
    });

    test('el respaldo de recibido_pct acota y el valor del servidor manda', () {
      // Con la clave presente se usa tal cual.
      final conPct = PendienteCompra.fromJson(compraPanel(recibidoPct: 0.575));
      expect(conPct.recibidoPct, closeTo(0.575, 1e-9));

      // Sin la clave se calcula: 40 / 100.
      final sinPct = PendienteCompra.fromJson(compraPanel(recibidoPct: null));
      expect(sinPct.recibidoPct, closeTo(0.4, 1e-6));

      // Sobre-recepción: se acota a 1.
      expect(
        recibidoPctCalculado(pedido: 10, recibido: 25),
        1,
      );
      // Pedido 0: razón sin sentido, 0 (no NaN ni infinito).
      expect(recibidoPctCalculado(pedido: 0, recibido: 5), 0);
      expect(recibidoPctCalculado(pedido: 7, recibido: 0), 0);

      // Redondeo a 6 decimales, como `round(x, 6)`.
      expect(
        recibidoPctCalculado(pedido: 3, recibido: 1),
        closeTo(0.333333, 1e-9),
      );

      expect(porcentajeRecibido(0.4), 40);
      expect(porcentajeRecibido(1), 100);
      expect(porcentajeRecibido(1.7), 100);
    });

    test('la antigüedad mostrada y el umbral se leen como en la maqueta', () {
      expect(textoDias(0), 'Hoy');
      expect(textoDias(1), '1 día');
      expect(textoDias(16), '16 días');
      expect(textoDias(-3), 'Hoy');
      expect(textoDiasCorto(0), '0 d');
      expect(textoDiasCorto(39), '39 d');

      // 15 días está dentro; 16 supera. El umbral no filtra, solo avisa.
      expect(superaUmbralAntiguedad(15), isFalse);
      expect(superaUmbralAntiguedad(16), isTrue);
      expect(superaUmbralAntiguedad(5, umbral: 2), isTrue);
      expect(umbralAntiguedadDias, 15);

      expect(
        textoRecepcionYDias(DateTime(2026, 11, 12), 4),
        'Últ. recepción 12/11 · 4 d sin movimiento',
      );
      expect(
        textoRecepcionYDias(null, 21),
        'Sin recepciones · 21 d sin movimiento',
      );
    });

    test('un panel vacío no es un error', () {
      final vacio = PendientesPanel.fromJson({
        'id_tienda': 4,
        'orden': 'monto',
        'generado_at': null,
        'compras': [],
        'totales_por_moneda': [],
      });
      expect(vacio.vacio, isTrue);
      expect(vacio.comprasAbiertas, 0);
      expect(vacio.masAntigua, isNull);
      expect(vacio.sinRecepcion, 0);
      expect(vacio.comprasPorMoneda, isEmpty);
      expect(vacio.orden, PendientesOrden.monto);
    });
  });

  group('detalle de faltantes', () {
    test('cabecera y líneas cuadran con el agregado del servidor', () {
      final detalle = PendienteDetalle.fromJson(detalleJson());

      expect(detalle.idTienda, 4);
      expect(detalle.lineas, hasLength(2));
      expect(detalle.vacio, isFalse);
      expect(detalle.compra.idCompra, 42);
      expect(detalle.compra.numeroCompra, 1042);
      expect(detalle.compra.estado, 'entrega_parcial');
      expect(detalle.compra.moneda, 'USD');
      expect(detalle.compra.pedido, 100);
      expect(detalle.compra.recibido, 40);
      expect(detalle.compra.recibidoPct, closeTo(0.4, 1e-9));
      expect(detalle.compra.montoPendiente, 3180);
      expect(detalle.compra.diasAntiguedad, 16);
      expect(detalle.compra.textoPedidoRecibido, '40 de 100');

      final primera = detalle.lineas.first;
      expect(primera.idCompraLinea, 1);
      expect(primera.producto, 'Aceite 15W40');
      expect(primera.presentacion, 'Caja x12');
      expect(primera.pendiente, 12);
      expect(primera.montoPendiente, 150);
      expect(primera.tienePendiente, isTrue);
      expect(primera.textoPresentacion, 'Caja x12');
      expect(detalle.lineas.last.textoPresentacion, 'Bidón 20 L · Bidón');

      // Invariante del contrato: Σ monto_pendiente de las líneas == cabecera.
      expect(detalle.sumaLineasPendiente, 690);
      expect(detalle.lineasConPendiente, 2);
      expect(detalle.lineasSinRecepcion, 0);

      expect(detalle.totalesPorMoneda, hasLength(1));
      expect(detalle.totalesPorMoneda.first.moneda, 'USD');
      expect(detalle.totalesPorMoneda.first.montoPendiente, 3180);

      // Una fila por línea, con los totales en su propia moneda.
      final filas = export.filasExcelDetalle(detalle);
      expect(filas, hasLength(2));
      expect(filas.first[0], 'Aceite 15W40');
      expect(filas.first[6], 12.5);
      expect(filas.first[7], 150);
      expect(export.filasExcelTotalesDetalle(detalle).first[0], 'USD');
    });
  });

  group('histórico de recepciones', () {
    test('se filtra por número de compra (el JSON no trae id_compra)', () {
      final historico = HistorialRecepciones.fromJson(historialJson());
      expect(historico.recepciones, hasLength(2));

      final deLaCompra = historico.deCompra(1042);
      expect(deLaCompra, hasLength(1));
      expect(deLaCompra.first.idRecepcion, 501);
      expect(deLaCompra.first.idOperacion, 9001);
      expect(deLaCompra.first.fecha, DateTime(2026, 11, 12));
      expect(deLaCompra.first.numeroFactura, 'FS-0091');
      expect(deLaCompra.first.montoValorizado, 1420);
      expect(deLaCompra.first.moneda, 'USD');
      expect(deLaCompra.first.origenPago, 'wallet_importadora');
      expect(deLaCompra.first.origenPagoLegible, 'Wallet importadora');
      expect(deLaCompra.first.estadoOperacionNombre, 'Confirmada');
      expect(deLaCompra.first.productos, 'Aceite 15W40 +1');
      expect(historico.deCompra(1030), isEmpty);

      // Sin estado de operación no se inventa «pendiente»: queda nulo.
      expect(historico.recepciones.last.estadoOperacionNombre, isNull);
      expect(historico.totalesPorMoneda.single.montoValorizado, 1520);
    });
  });

  group('vista de facturas', () {
    test('estado de recepción, cerradas y totales por moneda', () {
      final vista = FacturasVista.fromJson(facturasJson());

      expect(vista.facturas, hasLength(3));
      expect(vista.total, 3);
      expect(vista.sinRecibir, 1);
      expect(vista.parciales, 1);
      expect(vista.completas, 1);

      // Incluye una compra cerrada (`completada`): es el listado documental.
      final cerrada = vista.facturas[1];
      expect(cerrada.estado, 'completada');
      expect(cerrada.estadoRecepcion, EstadoRecepcion.completa);
      expect(cerrada.numeroFactura, isNull);
      expect(cerrada.moneda, 'CUP');

      expect(
        vista.facturas.first.estadoRecepcion,
        EstadoRecepcion.parcial,
      );
      expect(vista.facturas.last.estadoRecepcion, EstadoRecepcion.sinRecibir);
      expect(vista.facturas.last.sinRecepcion, isTrue);
      expect(
        EstadoRecepcion.etiquetaDe('sin recibir'),
        'Sin recibir',
      );
      expect(EstadoRecepcion.etiquetaDe('parcial'), 'Parcial');
      expect(EstadoRecepcion.etiquetaDe('completa'), 'Completa');

      expect(vista.totalesPorMoneda, hasLength(2));
      expect(vista.totalesPorMoneda.first.moneda, 'CUP');
      expect(vista.totalesPorMoneda.first.pagado, 310500);
      expect(vista.totalesPorMoneda.last.moneda, 'USD');
      expect(vista.totalesPorMoneda.last.totalFactura, 8950);
      // Nada de un total combinado CUP + USD.
      expect(vista.totalesPorMoneda.first.totalFactura, isNot(319450));
    });
  });

  group('contrato SQL (09_pendientes.sql)', () {
    final sql = File(
      'lib/sql/compra/09_pendientes.sql',
    ).readAsStringSync();

    test('las cuatro funciones existen con su firma exacta', () {
      final firmas = <String, RegExp>{
        'fn_fdi_pendientes_panel': RegExp(
          r'CREATE OR REPLACE FUNCTION public\.fn_fdi_pendientes_panel\(\s*'
          r'p_id_tienda\s+bigint,\s*'
          r"p_orden\s+text DEFAULT 'antiguedad'\s*\)"
          r'\s*RETURNS jsonb',
        ),
        'fn_fdi_pendientes_detalle': RegExp(
          r'CREATE OR REPLACE FUNCTION public\.fn_fdi_pendientes_detalle\(\s*'
          r'p_id_tienda\s+bigint,\s*'
          r'p_id_compra\s+bigint\s*\)'
          r'\s*RETURNS jsonb',
        ),
        'fn_fdi_recepciones_historial': RegExp(
          r'CREATE OR REPLACE FUNCTION public\.fn_fdi_recepciones_historial\(\s*'
          r'p_id_tienda\s+bigint,\s*'
          r'p_desde\s+date DEFAULT NULL,\s*'
          r'p_hasta\s+date DEFAULT NULL\s*\)'
          r'\s*RETURNS jsonb',
        ),
        'fn_fdi_facturas': RegExp(
          r'CREATE OR REPLACE FUNCTION public\.fn_fdi_facturas\(\s*'
          r'p_id_tienda\s+bigint,\s*'
          r'p_desde\s+date DEFAULT NULL,\s*'
          r'p_hasta\s+date DEFAULT NULL\s*\)'
          r'\s*RETURNS jsonb',
        ),
      };
      firmas.forEach((nombre, patron) {
        expect(
          patron.hasMatch(sql),
          isTrue,
          reason: 'falta la firma exacta de $nombre en 09_pendientes.sql',
        );
      });
    });

    test('son de solo lectura y solo las ejecuta `authenticated`', () {
      expect(RegExp(r'\bSTABLE\b').allMatches(sql).length, greaterThanOrEqualTo(4));
      expect(
        RegExp(r'\bSECURITY DEFINER\b').allMatches(sql).length,
        greaterThanOrEqualTo(4),
      );
      for (final firma in const [
        'fn_fdi_pendientes_panel(bigint, text)',
        'fn_fdi_pendientes_detalle(bigint, bigint)',
        'fn_fdi_recepciones_historial(bigint, date, date)',
        'fn_fdi_facturas(bigint, date, date)',
      ]) {
        expect(
          sql,
          contains('REVOKE ALL ON FUNCTION public.$firma FROM PUBLIC, anon;'),
        );
        expect(
          sql,
          contains('GRANT EXECUTE ON FUNCTION public.$firma TO authenticated;'),
        );
      }
      // Solo lectura: el script no escribe filas.
      expect(RegExp(r'insert into', caseSensitive: false).hasMatch(sql), isFalse);
      expect(RegExp(r'delete from', caseSensitive: false).hasMatch(sql), isFalse);
      // `p_orden` solo admite los dos valores del contrato.
      expect(sql, contains("v_orden NOT IN ('antiguedad', 'monto')"));
    });

    test('todas reciben p_id_tienda primero y devuelven jsonb', () {
      final firmas = [
        'fn_fdi_pendientes_panel',
        'fn_fdi_pendientes_detalle',
        'fn_fdi_recepciones_historial',
        'fn_fdi_facturas',
      ];
      for (final nombre in firmas) {
        final inicio = sql.indexOf('FUNCTION public.$nombre(');
        expect(inicio, greaterThan(-1), reason: 'falta $nombre');
        final trozo = sql.substring(inicio, inicio + 400);
        expect(
          trozo.contains('p_id_tienda'),
          isTrue,
          reason: '$nombre no recibe p_id_tienda',
        );
        expect(trozo.contains('RETURNS jsonb'), isTrue);
      }
    });
  });

  group('permisos de importes (fase 9)', () {
    test('el almacenero entra sin importes; dueño y gerente ven todo', () {
      // El rol existe en el enum: es el que recibe mercancía.
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.almacenero),
        isFalse,
      );
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.dueno),
        isTrue,
      );
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.gerente),
        isTrue,
      );
      // Ni supervisor ni auditor ni vendedor ven dinero en estas pantallas.
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.supervisor),
        isFalse,
      );
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.auditor),
        isFalse,
      );
      expect(
        PermissionsService.puedeVerImportesPara(UserRole.vendedor),
        isFalse,
      );
      expect(PermissionsService.puedeVerImportesPara(UserRole.none), isFalse);
    });

    test('las rutas están en main.dart, en la matriz y en el menú', () {
      final mainDart = File('lib/main.dart').readAsStringSync();
      final permisos = File(
        'lib/services/permissions_service.dart',
      ).readAsStringSync();
      final menu = File('lib/widgets/admin_drawer.dart').readAsStringSync();
      const rutas = [
        '/compras/pendientes',
        '/compras/pendientes/detalle',
        '/compras/facturas',
      ];
      for (final ruta in rutas) {
        expect(
          mainDart.contains("'$ruta':"),
          isTrue,
          reason: 'falta la ruta $ruta en main.dart',
        );
        expect(
          permisos.contains("'$ruta': ["),
          isTrue,
          reason: 'falta $ruta en la matriz de permisos',
        );
      }
      // El menú lateral lleva a las dos pantallas con el guard de siempre.
      for (final ruta in const ['/compras/pendientes', '/compras/facturas']) {
        expect(
          menu.contains("'$ruta'"),
          isTrue,
          reason: 'falta la entrada $ruta en AdminDrawer',
        );
        expect(
          menu.contains('NavigationGuard.canNavigate('),
          isTrue,
          reason: 'el menú perdió el patrón NavigationGuard',
        );
      }
    });
  });

  group('exportación (bytes)', () {
    test('Excel del panel: bytes no vacíos', () async {
      final panel = PendientesPanel.fromJson(panelJson());
      final bytes = await export.construirExcelPanel(
        panel: panel,
        nombreTienda: 'Tienda Centro Habana',
      );
      _exigirArchivo(bytes, 'el Excel del panel');
      // Un .xlsx es un ZIP: empieza con "PK".
      expect(_empiezaCon(bytes, 'PK'), isTrue);
    });

    test('Excel del detalle: bytes no vacíos', () async {
      final detalle = PendienteDetalle.fromJson(detalleJson());
      final bytes = await export.construirExcelDetalle(
        detalle: detalle,
        nombreTienda: 'Tienda Centro Habana',
      );
      _exigirArchivo(bytes, 'el Excel del detalle');
      expect(_empiezaCon(bytes, 'PK'), isTrue);
    });

    test('PDF del panel: bytes no vacíos', () async {
      final panel = PendientesPanel.fromJson(panelJson());
      final bytes = await export.construirPdfPanel(
        panel: panel,
        nombreTienda: 'Tienda Centro Habana',
      );
      _exigirArchivo(bytes, 'el PDF del panel');
      expect(_empiezaCon(bytes, '%PDF'), isTrue);
    });

    test('PDF del detalle: bytes no vacíos', () async {
      final detalle = PendienteDetalle.fromJson(detalleJson());
      final bytes = await export.construirPdfDetalle(
        detalle: detalle,
        nombreTienda: 'Tienda Centro Habana',
      );
      _exigirArchivo(bytes, 'el PDF del detalle');
      expect(_empiezaCon(bytes, '%PDF'), isTrue);
    });

    test('el Excel del panel trae la hoja aparte de totales por moneda', () async {
      final panel = PendientesPanel.fromJson(panelJson());
      final bytes = await export.construirExcelPanel(
        panel: panel,
        nombreTienda: 'Tienda Centro Habana',
      );
      final libro = Excel.decodeBytes(bytes);
      expect(
        libro.tables.keys,
        containsAll(<String>['Pendientes', 'Totales por moneda']),
      );
      // La hoja de totales tiene una fila por moneda, no una agregada.
      final totales = libro.tables['Totales por moneda']!;
      final monedas = totales.rows
          .map((fila) => fila.isEmpty ? null : fila.first?.value?.toString())
          .where((valor) => valor == 'USD' || valor == 'CUP')
          .toList();
      expect(monedas, ['CUP', 'USD']);
    });

    test('el panel con una sola moneda no agrega una fila combinada', () {
      final panel = PendientesPanel.fromJson({
        'id_tienda': 4,
        'orden': 'monto',
        'generado_at': null,
        'compras': [compraPanel()],
        'totales_por_moneda': [
          {'moneda': 'USD', 'compras': 1, 'monto_total': 7950, 'monto_pendiente': 3180},
        ],
      });
      final filas = export.filasExcelTotalesPanel(panel);
      expect(filas, hasLength(1));
      expect(filas.single[0], 'USD');
      expect(filas.single[3], 3180);
    });
  });
}

void _exigirArchivo(Uint8List bytes, String que) {
  expect(bytes, isNotEmpty, reason: '$que salió vacío');
  expect(bytes.length, greaterThan(1000), reason: '$que parece truncado');
}

bool _empiezaCon(Uint8List bytes, String firma) {
  if (bytes.length < firma.length) return false;
  for (var i = 0; i < firma.length; i++) {
    if (bytes[i] != firma.codeUnitAt(i)) return false;
  }
  return true;
}