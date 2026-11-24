import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/compra.dart';

/// Contrato de lectura del módulo Compras: se prueba el mapeo del jsonb de
/// `fn_fdi_compra_detalle` / `fn_fdi_compra_listar` y los getters que usan la
/// UI. Sin red ni Supabase.
void main() {
  Map<String, dynamic> cabecera({
    String? numeroFactura = 'F-2026-0041',
    String? fechaFactura = '2026-11-18',
    String? observacion = 'Carga de fin de año',
    String estado = 'creada',
  }) => {
    'id': 41,
    'id_tienda': 7,
    'numero_compra': 12,
    'id_proveedor': 3,
    'numero_factura': numeroFactura,
    'fecha_factura': fechaFactura,
    'moneda_total': 'USD',
    'tasa_factura': 320.5,
    'total_mercancia': 2500.00,
    'total_ajustes': 180.50,
    'total_financiado': 2500.00,
    'costo_aterrizado': 2680.50,
    'modo_liquidacion': 'fondo',
    'politica_pago': 'al_pagar',
    'estado': estado,
    'observacion': observacion,
    'idempotency_key': 'a1b2c3d4-1111-4222-9333-444455556666',
    'created_by': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    'created_at': '2026-11-18T14:03:11.123456+00:00',
    'updated_at': '2026-11-18T14:03:11.123456+00:00',
  };

  Map<String, dynamic> detalleJson({
    String? numeroFactura = 'F-2026-0041',
    String? fechaFactura = '2026-11-18',
  }) => {
    'compra': cabecera(
      numeroFactura: numeroFactura,
      fechaFactura: fechaFactura,
    ),
    'proveedor': {'id': 3, 'denominacion': 'Importadora El Caribe'},
    'lineas': [
      {
        'id': 101,
        'id_producto': 55,
        'id_variante': 12,
        'id_presentacion': 4,
        'cantidad': 10.5,
        'costo_unitario': 100,
        'costo_linea': 1050.00,
        'id_almacen': 2,
        'id_ubicacion': 9,
        'producto': 'Aceite 1 L',
      },
      {
        'id': 102,
        'id_producto': 56,
        'id_variante': null,
        'id_presentacion': null,
        'cantidad': 2,
        'costo_unitario': 725.25,
        'costo_linea': 1450.50,
        'id_almacen': 2,
        'id_ubicacion': null,
        'producto': 'Arroz 5 kg',
      },
    ],
    'ajustes': [
      {
        'id': 7,
        'id_compra': 41,
        'id_tienda': 7,
        'id_tipo_costo': 4,
        'base': 'global',
        'valor': 120,
        'reparto': 'valor',
        'monto_capitalizado': 120.00,
        'afecta_inventario': true,
        'origen_pago': 'fondo',
        'estado': 'declarado',
      },
      {
        'id': 8,
        'id_compra': 41,
        'id_tienda': 7,
        'id_tipo_costo': 9,
        'base': 'porcentaje',
        'valor': 2,
        'reparto': 'peso',
        'monto_capitalizado': 60.50,
        'afecta_inventario': false,
        'origen_pago': 'wallet_importadora',
        'estado': 'declarado',
      },
    ],
    'historial': [
      {
        'id': 1,
        'id_compra': 41,
        'id_tienda': 7,
        'estado_anterior': null,
        'estado_nuevo': 'creada',
        'origen': 'automatico',
        'motivo': 'Alta de compra',
        'created_by': null,
        'created_at': '2026-11-18T14:03:11.5+00:00',
      },
    ],
    'recepciones': [],
  };

  group('compra · detalle', () {
    test(
      'CompraDetalle.fromJson mapea cabecera, proveedor, líneas y ajustes',
      () {
        final d = CompraDetalle.fromJson(detalleJson());

        expect(d.idCompra, 41);
        expect(d.numeroCompra, 12);
        expect(d.proveedorNombre, 'Importadora El Caribe');
        expect(d.compra.idProveedor, 3);
        expect(d.compra.numeroFactura, 'F-2026-0041');
        expect(d.compra.fechaFactura, DateTime(2026, 11, 18));
        expect(d.compra.monedaTotal, 'USD');
        expect(d.compra.tasaFactura, 320.5);
        expect(d.compra.totalMercancia, 2500.0);
        expect(d.compra.totalAjustes, 180.5);
        expect(d.compra.totalFinanciado, 2500.0);
        expect(d.compra.costoAterrizado, 2680.5);
        expect(d.compra.modoLiquidacionLegible, 'Fondo');
        expect(d.compra.politicaPagoLegible, 'Al pagar');
        expect(d.compra.observacion, 'Carga de fin de año');
        expect(
          d.compra.createdAt?.toUtc(),
          DateTime.utc(2026, 11, 18, 14, 3, 11, 123, 456),
        );

        expect(d.lineas, hasLength(2));
        expect(d.lineas.first.idProducto, 55);
        expect(d.lineas.first.idVariante, 12);
        expect(d.lineas.first.cantidad, 10.5);
        expect(d.lineas.first.costoUnitario, 100.0);
        expect(d.lineas.first.costoLinea, 1050.0);
        expect(d.lineas.first.producto, 'Aceite 1 L');
        expect(d.lineas.last.idVariante, isNull);
        expect(d.lineas.last.idPresentacion, isNull);

        expect(d.ajustes, hasLength(2));
        expect(d.ajustes.first.baseLegible, 'Global');
        expect(d.ajustes.first.origenPagoLegible, 'Fondo');
        expect(d.ajustes.first.montoCapitalizado, 120.0);
        expect(d.ajustes.last.baseLegible, 'Porcentaje');
        expect(d.ajustes.last.repartoLegible, 'Por peso');
        expect(d.ajustes.last.origenPagoLegible, 'Wallet importadora');
        expect(d.ajustes.last.afectaInventario, isFalse);

        expect(d.historial, hasLength(1));
        expect(d.historial.single.estadoAnterior, isNull);
        expect(d.historial.single.estadoAnteriorLegible, isNull);
        expect(d.historial.single.estadoNuevoLegible, 'Creada');
        expect(d.historial.single.motivo, 'Alta de compra');
        expect(d.tieneRecepciones, isFalse);
      },
    );
  });

  group('compra · listado', () {
    test('CompraResumen.fromJson mapea la fila con conteo de líneas', () {
      final r = CompraResumen.fromJson({
        'id': 41,
        'numero_compra': 12,
        'id_proveedor': 3,
        'proveedor': 'Importadora El Caribe',
        'numero_factura': 'F-2026-0041',
        'fecha_factura': '2026-11-18',
        'moneda_total': 'USD',
        'total_mercancia': 2500.00,
        'total_ajustes': 180.50,
        'total_financiado': 2500.00,
        'costo_aterrizado': 2680.50,
        'modo_liquidacion': 'fondo',
        'politica_pago': 'al_pagar',
        'estado': 'reservada',
        'observacion': null,
        'created_at': '2026-11-18T14:03:11.123456+00:00',
        'lineas': 2,
      });

      expect(r.id, 41);
      expect(r.proveedor, 'Importadora El Caribe');
      expect(r.totalMercancia, 2500.0);
      expect(r.costoAterrizado, 2680.5);
      expect(r.lineas, 2);
      expect(r.estadoLegible, 'Reservada');
      expect(r.esCancelable, isFalse);
      expect(r.createdAt, isNotNull);
    });
  });

  group('compra · getters de estado', () {
    test('solo creada es editable y cancelable', () {
      final creada = Compra.fromJson(cabecera());
      expect(creada.esEditable, isTrue);
      expect(creada.esCancelable, isTrue);

      for (final estado in [
        'reservada',
        'pagada',
        'entrega_parcial',
        'completada',
        'cancelada',
        'anulada',
      ]) {
        final c = Compra.fromJson(cabecera(estado: estado));
        expect(c.esEditable, isFalse, reason: estado);
        expect(c.esCancelable, isFalse, reason: estado);
      }
    });

    test('estadoLegible cubre los siete estados y cae al código crudo', () {
      expect(CompraEstado.etiquetaDe('creada'), 'Creada');
      expect(CompraEstado.etiquetaDe('reservada'), 'Reservada');
      expect(CompraEstado.etiquetaDe('pagada'), 'Pagada');
      expect(CompraEstado.etiquetaDe('entrega_parcial'), 'Entrega parcial');
      expect(CompraEstado.etiquetaDe('completada'), 'Completada');
      expect(CompraEstado.etiquetaDe('cancelada'), 'Cancelada');
      expect(CompraEstado.etiquetaDe('anulada'), 'Anulada');
      expect(CompraEstado.etiquetaDe('estado_futuro'), 'estado_futuro');
      expect(CompraEstado.etiquetaDe(null), '');
      expect(
        CompraEstado.desde('entrega_parcial'),
        CompraEstado.entregaParcial,
      );
    });
  });

  group('compra · campos nulos', () {
    test('detalle sin factura ni variante no revienta', () {
      final d = CompraDetalle.fromJson(
        detalleJson(numeroFactura: null, fechaFactura: null),
      );

      expect(d.compra.numeroFactura, isNull);
      expect(d.compra.fechaFactura, isNull);
      expect(d.compra.observacion, 'Carga de fin de año');
      expect(d.lineas.last.idVariante, isNull);
      expect(d.lineas.last.idPresentacion, isNull);
      expect(d.lineas.last.idUbicacion, isNull);
      expect(d.lineas.last.producto, 'Arroz 5 kg');
      expect(d.lineas.last.costoLinea, 1450.5);
    });

    test('resumen sin fecha ni observación usa valores vacíos', () {
      final r = CompraResumen.fromJson({
        'id': 41,
        'numero_compra': 12,
        'id_proveedor': 3,
        'id_tienda': 7,
        'proveedor': null,
        'numero_factura': null,
        'fecha_factura': null,
        'moneda_total': 'CUP',
        'estado': 'creada',
        'observacion': null,
        'created_at': null,
        'lineas': null,
      });

      expect(r.proveedor, '');
      expect(r.numeroFactura, isNull);
      expect(r.fechaFactura, isNull);
      expect(r.createdAt, isNull);
      expect(r.lineas, 0);
      expect(r.monedaTotal, 'CUP');
    });

    test('detalle sin listas arma colecciones vacías', () {
      final d = CompraDetalle.fromJson({'compra': cabecera()});

      expect(d.proveedor, isNull);
      expect(d.proveedorNombre, '');
      expect(d.lineas, isEmpty);
      expect(d.ajustes, isEmpty);
      expect(d.historial, isEmpty);
      expect(d.recepciones, isEmpty);
      expect(d.tieneRecepciones, isFalse);
    });
  });

  group('compra · JSON de entrada a las RPC', () {
    test('CompraLinea emite las claves de p_lineas', () {
      final l = CompraLinea(
        idProducto: 55,
        idVariante: 12,
        idPresentacion: 4,
        cantidad: 2.5,
        costoUnitario: 40,
        idAlmacen: 2,
        idUbicacion: 9,
      );

      expect(l.toJson(), {
        'id_producto': 55,
        'id_variante': 12,
        'id_presentacion': 4,
        'cantidad': 2.5,
        'costo_unitario': 40.0,
        'id_almacen': 2,
        'id_ubicacion': 9,
      });
      expect(l.costoLinea, 100.0, reason: 'costo_linea se calcula sin red');
    });

    test('CompraAjuste emite las claves de p_ajustes', () {
      final a = CompraAjuste(
        idTipoCosto: 4,
        base: 'porcentaje',
        valor: 2,
        reparto: 'peso',
        origenPago: 'wallet_proveedor',
        afectaInventario: false,
      );

      expect(a.toJson(), {
        'id_tipo_costo': 4,
        'base': 'porcentaje',
        'valor': 2.0,
        'reparto': 'peso',
        'origen_pago': 'wallet_proveedor',
        'afecta_inventario': false,
      });
      expect(a.origenPagoLegible, 'Wallet proveedor');
      expect(a.baseLegible, 'Porcentaje');
      expect(a.repartoLegible, 'Por peso');
    });
  });
}
