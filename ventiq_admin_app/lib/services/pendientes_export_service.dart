/// Exportación de la fase 9 de Compras: Excel y PDF del panel de pendientes y
/// del detalle de faltantes.
///
/// Este servicio es **propio** y no toca `lib/services/export_service.dart`
/// (155 KB con muchos flujos). Reutiliza la misma idea de guardado/compartido
/// (`_saveOrShareFile`: selector del sistema con FilePicker, y si no está
/// disponible, compartir con `share_plus`) y las mismas librerías: `excel`,
/// `pdf`, `share_plus` y `path_provider`.
///
/// Dos reglas que se respetan en los cuatro formatos:
///  · **ningún total suma monedas distintas**: los agregados van por moneda y
///    cada importe viaja con la suya;
///  · la generación de bytes es una función pura (sin `BuildContext`), para
///    poder probarla sin dispositivo.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../config/app_colors.dart';
import '../models/pendientes.dart';

// Descarga en web, igual que ExportService (mismo par de archivos).
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart'
    as web_download;

final NumberFormat _fmtImporte = NumberFormat('#,##0.00');
final NumberFormat _fmtCantidad = NumberFormat('#,##0.####');
final DateFormat _fmtFecha = DateFormat('dd/MM/yyyy');
final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat _fmtSello = DateFormat('yyyyMMdd_HHmmss');

String _importe(num valor) => _fmtImporte.format(valor);

String _cantidad(num valor) => _fmtCantidad.format(valor);

String _fecha(DateTime? fecha) => fecha == null ? '—' : _fmtFecha.format(fecha);

/// Fecha para el PDF: las fuentes base de PDF no dibujan el guion largo, así
/// que ahí el «sin fecha» va con un guion normal.
String _fechaPdf(DateTime? fecha) =>
    fecha == null ? '-' : _fmtFecha.format(fecha);

String _importeConMoneda(num valor, String moneda) {
  final limpia = moneda.trim();
  return limpia.isEmpty ? _importe(valor) : '${_importe(valor)} $limpia';
}

String _porcentaje(num pct) => '${(pct.clamp(0, 1) * 100).round()} %';

String _limpiarNombre(String texto) =>
    texto.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');

/// Exportación Excel/PDF de pendientes y detalle.
class PendientesExportService {
  const PendientesExportService();

  static const String _appName = 'Inventtia Gestión';

  // ==========================================================================
  // Filas puras (sin BuildContext): base de los tests de contenido
  // ==========================================================================

  /// Columnas de la hoja «Pendientes», una fila por compra abierta.
  static const List<String> cabeceraPanel = [
    'Compra',
    'Factura',
    'Proveedor',
    'Fecha factura',
    'Estado',
    'Moneda',
    'Antigüedad (días)',
    'Líneas',
    'Pedido',
    'Recibido',
    'Recibido %',
    'Monto total',
    'Monto pendiente',
    'Última recepción',
    'Días sin movimiento',
  ];

  /// Columnas de la hoja «Totales por moneda» del panel.
  static const List<String> cabeceraTotalesPanel = [
    'Moneda',
    'Compras abiertas',
    'Monto total',
    'Monto pendiente',
  ];

  /// Columnas de la hoja «Faltantes» del detalle.
  static const List<String> cabeceraDetalle = [
    'Producto',
    'Presentación',
    'Variante',
    'Cantidad',
    'Recibido',
    'Pendiente',
    'Costo unitario',
    'Monto pendiente',
    'Última recepción',
    'Días sin movimiento',
  ];

  /// Columnas de la hoja «Totales por moneda» del detalle.
  static const List<String> cabeceraTotalesDetalle = [
    'Moneda',
    'Líneas',
    'Monto total',
    'Monto pendiente',
  ];

  /// Una fila por compra, con todos los campos del contrato del panel.
  List<List<Object?>> filasExcelPanel(PendientesPanel panel) {
    return [
      for (final c in panel.compras)
        <Object?>[
          c.etiquetaCompra,
          c.numeroFactura ?? '',
          c.proveedor ?? '',
          _fecha(c.fechaFactura),
          c.estado,
          c.moneda,
          c.diasAntiguedad,
          c.lineas,
          c.pedido,
          c.recibido,
          _porcentaje(c.recibidoPct),
          c.montoTotal,
          c.montoPendiente,
          _fecha(c.ultimaRecepcion),
          c.diasSinMovimiento,
        ],
    ];
  }

  /// Totales del panel **por moneda**: una fila por moneda, jamás una suma
  /// combinada.
  List<List<Object?>> filasExcelTotalesPanel(PendientesPanel panel) {
    return [
      for (final t in panel.totalesPorMoneda)
        <Object?>[t.moneda, t.compras, t.montoTotal, t.montoPendiente],
    ];
  }

  /// Una fila por línea de la compra.
  List<List<Object?>> filasExcelDetalle(PendienteDetalle detalle) {
    return [
      for (final l in detalle.lineas)
        <Object?>[
          l.producto,
          l.presentacion ?? '',
          l.variante ?? '',
          l.cantidad,
          l.recibido,
          l.pendiente,
          l.costoUnitario,
          l.montoPendiente,
          _fecha(l.ultimaRecepcion),
          l.diasSinMovimiento,
        ],
    ];
  }

  /// Totales del detalle, por moneda.
  List<List<Object?>> filasExcelTotalesDetalle(PendienteDetalle detalle) {
    return [
      for (final t in detalle.totalesPorMoneda)
        <Object?>[t.moneda, t.lineas, t.montoTotal, t.montoPendiente],
    ];
  }

  // ==========================================================================
  // Generación de bytes (probable sin dispositivo)
  // ==========================================================================

  /// Excel del panel: hoja «Pendientes» + hoja «Totales por moneda».
  Future<Uint8List> construirExcelPanel({
    required PendientesPanel panel,
    required String nombreTienda,
    DateTime? generadoEn,
  }) async {
    final generado = generadoEn ?? DateTime.now();
    final libro = Excel.createExcel();
    final porDefecto = libro.getDefaultSheet();
    if (porDefecto != null) libro.rename(porDefecto, 'Pendientes');
    final hoja = libro['Pendientes'];

    hoja.appendRow([TextCellValue('Pendientes de recepción')]);
    hoja.appendRow([TextCellValue('Tienda: $nombreTienda')]);
    hoja.appendRow([
      TextCellValue('Generado: ${_fmtFechaHora.format(generado)}'),
    ]);
    hoja.appendRow([TextCellValue('Orden: ${panel.orden.etiqueta}')]);
    hoja.appendRow([
      TextCellValue('Compras abiertas: ${panel.comprasAbiertas}'),
    ]);
    hoja.appendRow([TextCellValue('Sin recepción: ${panel.sinRecepcion}')]);
    hoja.appendRow([]);
    hoja.appendRow(_filaCabecera(cabeceraPanel));
    for (final fila in filasExcelPanel(panel)) {
      hoja.appendRow(_filaCeldas(fila));
    }
    hoja.appendRow([]);
    hoja.appendRow([
      TextCellValue('Los importes no se suman entre monedas distintas.'),
    ]);

    final totales = libro['Totales por moneda'];
    totales.appendRow([TextCellValue('Totales por moneda')]);
    totales.appendRow([TextCellValue('Tienda: $nombreTienda')]);
    totales.appendRow([]);
    totales.appendRow(_filaCabecera(cabeceraTotalesPanel));
    for (final fila in filasExcelTotalesPanel(panel)) {
      totales.appendRow(_filaCeldas(fila));
    }
    for (final hojaActual in [hoja, totales]) {
      hojaActual.setColumnWidth(0, 22);
      hojaActual.setColumnWidth(2, 28);
    }

    return _bytesDeLibro(libro, 'el panel de pendientes');
  }

  /// Excel del detalle: cabecera de la compra + hoja «Faltantes» (una fila por
  /// línea) + totales por moneda.
  Future<Uint8List> construirExcelDetalle({
    required PendienteDetalle detalle,
    required String nombreTienda,
    DateTime? generadoEn,
  }) async {
    final generado = generadoEn ?? DateTime.now();
    final compra = detalle.compra;
    final libro = Excel.createExcel();
    final porDefecto = libro.getDefaultSheet();
    if (porDefecto != null) libro.rename(porDefecto, 'Faltantes');
    final hoja = libro['Faltantes'];

    hoja.appendRow([
      TextCellValue(
        'Faltantes de ${compra.etiquetaCompra}'
        '${compra.proveedor == null ? '' : ' · ${compra.proveedor}'}',
      ),
    ]);
    hoja.appendRow([
      TextCellValue('Tienda: $nombreTienda'),
    ]);
    hoja.appendRow([TextCellValue('Factura: ${compra.numeroFactura ?? '—'}')]);
    hoja.appendRow([
      TextCellValue('Fecha de factura: ${_fecha(compra.fechaFactura)}'),
    ]);
    hoja.appendRow([TextCellValue('Estado: ${compra.estado}')]);
    hoja.appendRow([TextCellValue('Moneda: ${compra.moneda}')]);
    hoja.appendRow([
      TextCellValue(
        'Pedido: ${_cantidad(compra.pedido)} · '
        'Recibido: ${_cantidad(compra.recibido)} · '
        'Avance: ${_porcentaje(compra.recibidoPct)}',
      ),
    ]);
    hoja.appendRow([
      TextCellValue(
        'Monto pendiente: ${_importeConMoneda(compra.montoPendiente, compra.moneda)}',
      ),
    ]);
    hoja.appendRow([
      TextCellValue('Generado: ${_fmtFechaHora.format(generado)}'),
    ]);
    hoja.appendRow([]);
    hoja.appendRow(_filaCabecera(cabeceraDetalle));
    for (final fila in filasExcelDetalle(detalle)) {
      hoja.appendRow(_filaCeldas(fila));
    }

    final totales = libro['Totales por moneda'];
    totales.appendRow([TextCellValue('Totales por moneda')]);
    totales.appendRow([TextCellValue('Tienda: $nombreTienda')]);
    totales.appendRow([]);
    totales.appendRow(_filaCabecera(cabeceraTotalesDetalle));
    for (final fila in filasExcelTotalesDetalle(detalle)) {
      totales.appendRow(_filaCeldas(fila));
    }
    hoja.setColumnWidth(0, 34);
    hoja.setColumnWidth(1, 20);

    return _bytesDeLibro(libro, 'el detalle de faltantes');
  }

  /// PDF del panel: cabecera de tienda, fecha de generación, totales por
  /// moneda y la tabla de compras abiertas (A4 horizontal).
  Future<Uint8List> construirPdfPanel({
    required PendientesPanel panel,
    required String nombreTienda,
    DateTime? generadoEn,
  }) async {
    final generado = generadoEn ?? DateTime.now();
    final documento = pw.Document();
    final cabeceras = [
      'Compra',
      'Proveedor',
      'Fecha',
      'Antigüedad',
      'Recibido',
      'Pedido / recibido',
      'Monto pendiente',
      'Últ. recep.',
      'Días s/mov.',
      'Estado',
    ];
    final filas = <List<String>>[
      for (final c in panel.compras)
        [
          c.etiquetaCompra,
          c.proveedor ?? '-',
          _fechaPdf(c.fechaFactura),
          textoDiasCorto(c.diasAntiguedad),
          _porcentaje(c.recibidoPct),
          c.textoPedidoRecibido,
          _importeConMoneda(c.montoPendiente, c.moneda),
          _fechaPdf(c.ultimaRecepcion),
          textoDiasCorto(c.diasSinMovimiento),
          c.estado,
        ],
    ];

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (contexto) => _cabeceraPdf(
          titulo: 'Pendientes de recepción',
          subtitulo: nombreTienda,
          generado: generado,
        ),
        footer: (contexto) => _piePdf(contexto),
        build: (contexto) => [
          _bloqueResumenPdf([
            ['Compras abiertas', '${panel.comprasAbiertas}'],
            ['Sin recepción', '${panel.sinRecepcion}'],
            ['Orden', panel.orden.etiqueta],
          ]),
          pw.SizedBox(height: 10),
          _bloqueTotalesPdf([
            for (final t in panel.totalesPorMoneda)
              [
                t.moneda.isEmpty ? 'Sin moneda' : t.moneda,
                '${t.compras}',
                _importeConMoneda(t.montoTotal, t.moneda),
                _importeConMoneda(t.montoPendiente, t.moneda),
              ],
          ]),
          pw.SizedBox(height: 12),
          _tablaPdf(cabeceras, filas),
          pw.SizedBox(height: 8),
          pw.Text(
            'Los importes de monedas distintas no se suman: cada moneda se '
            'informa por separado.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return documento.save();
  }

  /// PDF del detalle: cabecera de la compra, avance, tabla por línea y totales
  /// por moneda.
  Future<Uint8List> construirPdfDetalle({
    required PendienteDetalle detalle,
    required String nombreTienda,
    DateTime? generadoEn,
  }) async {
    final generado = generadoEn ?? DateTime.now();
    final compra = detalle.compra;
    final documento = pw.Document();
    final cabeceras = [
      'Producto',
      'Presentación',
      'Cant.',
      'Recibido',
      'Pendiente',
      'Costo unit.',
      'Monto pend.',
      'Últ. recep.',
      'Días s/mov.',
    ];
    final filas = <List<String>>[
      for (final l in detalle.lineas)
        [
          l.producto,
          l.textoPresentacion,
          _cantidad(l.cantidad),
          _cantidad(l.recibido),
          _cantidad(l.pendiente),
          _importeConMoneda(l.costoUnitario, compra.moneda),
          _importeConMoneda(l.montoPendiente, compra.moneda),
          _fechaPdf(l.ultimaRecepcion),
          textoDiasCorto(l.diasSinMovimiento),
        ],
    ];

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (contexto) => _cabeceraPdf(
          titulo:
              'Faltantes de ${compra.etiquetaCompra}'
              '${compra.proveedor == null ? '' : ' · ${compra.proveedor}'}',
          subtitulo: nombreTienda,
          generado: generado,
        ),
        footer: (contexto) => _piePdf(contexto),
        build: (contexto) => [
          _bloqueResumenPdf([
            ['Factura', compra.numeroFactura ?? '-'],
            ['Emitida', _fechaPdf(compra.fechaFactura)],
            ['Estado', compra.estado],
            ['Pedido', _cantidad(compra.pedido)],
            ['Recibido', _cantidad(compra.recibido)],
            ['Avance', _porcentaje(compra.recibidoPct)],
            [
              'Monto pendiente',
              _importeConMoneda(compra.montoPendiente, compra.moneda),
            ],
          ]),
          pw.SizedBox(height: 10),
          _bloqueTotalesPdf([
            for (final t in detalle.totalesPorMoneda)
              [
                t.moneda.isEmpty ? 'Sin moneda' : t.moneda,
                '${t.lineas}',
                _importeConMoneda(t.montoTotal, t.moneda),
                _importeConMoneda(t.montoPendiente, t.moneda),
              ],
          ]),
          pw.SizedBox(height: 12),
          _tablaPdf(cabeceras, filas),
          pw.SizedBox(height: 8),
          pw.Text(
            'Pendiente por línea = cantidad - recibido, acotado a 0. Un total '
            'solo se compara dentro de su propia moneda.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return documento.save();
  }

  // ==========================================================================
  // Exportar (guardar o compartir)
  // ==========================================================================

  Future<bool> exportarPanelExcel({
    required BuildContext context,
    required PendientesPanel panel,
    required String nombreTienda,
  }) async {
    final bytes = await construirExcelPanel(
      panel: panel,
      nombreTienda: nombreTienda,
    );
    return _entregar(
      context,
      bytes: bytes,
      fileName:
          'Pendientes_${_limpiarNombre(nombreTienda)}_'
          '${_fmtSello.format(DateTime.now())}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      subject: 'Pendientes de recepción - $nombreTienda',
    );
  }

  Future<bool> exportarPanelPdf({
    required BuildContext context,
    required PendientesPanel panel,
    required String nombreTienda,
  }) async {
    final bytes = await construirPdfPanel(
      panel: panel,
      nombreTienda: nombreTienda,
    );
    return _entregar(
      context,
      bytes: bytes,
      fileName:
          'Pendientes_${_limpiarNombre(nombreTienda)}_'
          '${_fmtSello.format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
      subject: 'Pendientes de recepción - $nombreTienda',
    );
  }

  Future<bool> exportarDetalleExcel({
    required BuildContext context,
    required PendienteDetalle detalle,
    required String nombreTienda,
  }) async {
    final bytes = await construirExcelDetalle(
      detalle: detalle,
      nombreTienda: nombreTienda,
    );
    return _entregar(
      context,
      bytes: bytes,
      fileName:
          'Faltantes_${detalle.compra.numeroCompra}_'
          '${_fmtSello.format(DateTime.now())}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      subject: 'Faltantes de ${detalle.compra.etiquetaCompra} - $nombreTienda',
    );
  }

  Future<bool> exportarDetallePdf({
    required BuildContext context,
    required PendienteDetalle detalle,
    required String nombreTienda,
  }) async {
    final bytes = await construirPdfDetalle(
      detalle: detalle,
      nombreTienda: nombreTienda,
    );
    return _entregar(
      context,
      bytes: bytes,
      fileName:
          'Faltantes_${detalle.compra.numeroCompra}_'
          '${_fmtSello.format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
      subject: 'Faltantes de ${detalle.compra.etiquetaCompra} - $nombreTienda',
    );
  }

  /// Web: descarga directa. Nativo: diálogo guardar/compartir.
  Future<bool> _entregar(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    if (kIsWeb) {
      web_download.downloadFileWeb(bytes, fileName, mimeType);
      return true;
    }
    return _saveOrShareFile(
      context,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      subject: subject,
      text: 'Se adjunta el archivo generado desde $subject.',
    );
  }

  /// Mismo patrón que `ExportService._saveOrShareFile`: preguntar, guardar con
  /// el selector del sistema y, si no está disponible, compartir el archivo.
  Future<bool> _saveOrShareFile(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String subject,
    String? text,
  }) async {
    final accion = context.mounted
        ? await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Archivo generado'),
              content: const Text('¿Qué deseas hacer con el archivo?'),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Guardar en dispositivo'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'share'),
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir'),
                ),
              ],
            ),
          )
        : 'share';
    if (accion == null) return false;

    if (accion == 'save') {
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : null;
      try {
        final ruta = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar archivo',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: extension != null ? [extension] : null,
          bytes: bytes,
        );
        if (ruta != null && context.mounted) {
          _avisar(context, 'Archivo guardado: $ruta', error: false);
        }
        return true;
      } catch (e) {
        // saveFile no soportado en este dispositivo → fallback a compartir.
        debugPrint('saveFile no disponible, usando compartir: $e');
      }
    }

    final directorio = await getTemporaryDirectory();
    final archivo = File('${directorio.path}/$fileName');
    await archivo.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(archivo.path, mimeType: mimeType)],
      subject: subject,
      text: text,
    );
    return true;
  }

  void _avisar(BuildContext context, String texto, {required bool error}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ==========================================================================
  // Piezas de Excel y PDF
  // ==========================================================================

  Uint8List _bytesDeLibro(Excel libro, String que) {
    final codificado = libro.encode();
    if (codificado == null) {
      throw Exception('No se pudo generar el Excel de $que.');
    }
    return Uint8List.fromList(codificado);
  }

  List<CellValue?> _filaCabecera(List<String> titulos) => [
    for (final titulo in titulos) TextCellValue(titulo),
  ];

  List<CellValue?> _filaCeldas(List<Object?> valores) => [
    for (final valor in valores)
      if (valor == null)
        TextCellValue('')
      else if (valor is num)
        DoubleCellValue(valor.toDouble())
      else
        TextCellValue(valor.toString()),
  ];

  pw.Widget _cabeceraPdf({
    required String titulo,
    required String subtitulo,
    required DateTime generado,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_appName, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generado: ${_fmtFechaHora.format(generado)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _piePdf(pw.Context contexto) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Pendientes de recepción · ${_appName}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'Página ${contexto.pageNumber} de ${contexto.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  /// Bloque de cifras de cabecera en dos filas de etiqueta/valor.
  pw.Widget _bloqueResumenPdf(List<List<String>> pares) {
    return pw.Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final par in pares)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                par[0].toUpperCase(),
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
              ),
              pw.Text(
                par[1],
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Tabla de totales por moneda. Si no hay ninguna, se dice; no se inventa un
  /// total combinado.
  pw.Widget _bloqueTotalesPdf(List<List<String>> filas) {
    if (filas.isEmpty) {
      return pw.Text(
        'Sin totales por moneda en la respuesta.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: const ['Moneda', 'Compras / líneas', 'Monto total', 'Pendiente'],
      data: filas,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(70),
        1: pw.FixedColumnWidth(70),
        2: pw.FixedColumnWidth(110),
        3: pw.FixedColumnWidth(110),
      },
    );
  }

  pw.Widget _tablaPdf(List<String> cabeceras, List<List<String>> filas) {
    return pw.TableHelper.fromTextArray(
      headers: cabeceras,
      data: filas,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    );
  }
}