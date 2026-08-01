import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/caja_turno.dart';

/// Generacion de PDF para turnos de caja.
///
/// Dos salidas:
///   * Acta de cierre individual: el documento que firma el vendedor y revisa
///     el auditor (conciliacion de efectivo + faltantes/excesos linea a linea).
///   * Listado consolidado: arqueo de los turnos filtrados en pantalla.
class CajaTurnoPdfService {
  static final DateFormat _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _fecha = DateFormat('dd/MM/yyyy');
  static final DateFormat _archivo = DateFormat('yyyyMMdd_HHmmss');
  static final NumberFormat _money = NumberFormat('#,##0.00');
  static final NumberFormat _units = NumberFormat('#,##0.##');

  static const String _appName = 'Inventtia Gestión';

  // ===================================================================
  // Acta de cierre de un turno
  // ===================================================================

  static Future<void> imprimirActaTurno({
    required CajaTurno turno,
    required String storeName,
  }) async {
    final pdf = pw.Document();
    final reporte = turno.reporte;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _headerActa(turno, storeName),
        footer: _footer,
        build: (context) {
          final bloques = <pw.Widget>[
            _seccion('Datos del turno'),
            _tablaDatos([
              ['TPV', turno.tpvDenominacion],
              ['Vendedor', turno.vendedorDisplay],
              ['Apertura', _fechaHora.format(turno.fechaApertura)],
              [
                'Cierre',
                turno.fechaCierre == null
                    ? 'En curso'
                    : _fechaHora.format(turno.fechaCierre!),
              ],
              ['Duración', turno.duracionDisplay],
              ['Estado', turno.estadoLabel],
              ['Conciliación', turno.conciliacionEstado],
              ['Cerrado por', turno.cerradoPorDisplay],
              ['Maneja inventario', turno.manejaInventario ? 'Sí' : 'No'],
              [
                'Operaciones',
                'Apertura #${turno.idOperacionApertura ?? '-'}  /  '
                    'Cierre #${turno.idOperacionCierre ?? '-'}',
              ],
            ]),
            pw.SizedBox(height: 14),
            _seccion('Conciliación de efectivo'),
            _tablaConciliacion(turno),
          ];

          if (turno.esperadoRegistradoDudoso) {
            bloques.add(pw.SizedBox(height: 6));
            bloques.add(
              _aviso(
                'El TPV registró un efectivo esperado de '
                '${_money.format(turno.efectivoEsperadoRegistrado ?? 0)} y una diferencia de '
                '${_money.format(turno.diferenciaRegistrada ?? 0)}. Para la conciliación se usa el '
                'valor recalculado a partir de fondo inicial + efectivo cobrado - egresos.',
              ),
            );
          }

          bloques.add(pw.SizedBox(height: 14));
          bloques.add(_seccion('Ventas del turno'));
          bloques.add(_tablaVentas(turno));

          if (turno.desglosePagos.isNotEmpty) {
            bloques.add(pw.SizedBox(height: 14));
            bloques.add(_seccion('Desglose de cobros por medio de pago'));
            bloques.add(_tablaPagos(turno));
          }

          if (reporte.tieneDiscrepancias) {
            bloques.add(pw.SizedBox(height: 14));
            bloques.add(
              _seccion(
                'Discrepancias de inventario  '
                '(${reporte.totalLineas} línea${reporte.totalLineas == 1 ? '' : 's'})',
              ),
            );

            if (reporte.faltantes.isNotEmpty) {
              bloques.add(
                _subtitulo(
                  'FALTANTES · ${reporte.faltantes.length} productos · '
                  '${_units.format(reporte.unidadesFaltantes)} unidades',
                  PdfColors.red800,
                ),
              );
              bloques.add(
                _tablaDiscrepancias(reporte.faltantes, PdfColors.red50),
              );
            }

            if (reporte.excesos.isNotEmpty) {
              bloques.add(pw.SizedBox(height: 10));
              bloques.add(
                _subtitulo(
                  'EXCESOS · ${reporte.excesos.length} productos · '
                  '${_units.format(reporte.unidadesExcedentes)} unidades',
                  PdfColors.orange800,
                ),
              );
              bloques.add(
                _tablaDiscrepancias(reporte.excesos, PdfColors.orange50),
              );
            }
          }

          if (reporte.notas.isNotEmpty) {
            bloques.add(pw.SizedBox(height: 14));
            bloques.add(_seccion('Otras observaciones'));
            bloques.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: reporte.notas
                    .map(
                      (nota) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(
                          '• $nota',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          }

          bloques.add(pw.SizedBox(height: 28));
          bloques.add(_firmas());

          return bloques;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Acta_Turno_${turno.id}_${_archivo.format(DateTime.now())}',
    );
  }

  // ===================================================================
  // Listado consolidado
  // ===================================================================

  static Future<void> imprimirListadoTurnos({
    required List<CajaTurno> turnos,
    required String storeName,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    String? filtroDescripcion,
  }) async {
    final pdf = pw.Document();

    double ventas = 0;
    double efectivo = 0;
    double egresos = 0;
    double contado = 0;
    double diferencias = 0;
    int conDescuadre = 0;
    int conDiscrepancias = 0;

    for (final t in turnos) {
      ventas += t.ventasTotales;
      efectivo += t.totalEfectivo;
      egresos += t.totalEgresos;
      contado += t.efectivoReal ?? 0;
      diferencias += t.diferenciaCalculada ?? 0;
      if (t.estaCerrado && t.diferenciaAbsoluta > 1.00) conDescuadre++;
      if (t.tieneDiscrepanciasInventario) conDiscrepancias++;
    }

    final periodo = (fechaDesde == null && fechaHasta == null)
        ? 'Todos los turnos'
        : 'Período: ${fechaDesde == null ? '...' : _fecha.format(fechaDesde)}'
              ' - ${fechaHasta == null ? '...' : _fecha.format(fechaHasta)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Turnos de caja - $storeName',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(periodo, style: const pw.TextStyle(fontSize: 9)),
                    if (filtroDescripcion != null &&
                        filtroDescripcion.trim().isNotEmpty)
                      pw.Text(
                        filtroDescripcion,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${turnos.length} turnos',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '$conDescuadre con descuadre · $conDiscrepancias con discrepancias',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(height: 1),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: _footer,
        build: (context) => [
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 7.5,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 2.5,
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.0),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(2.6),
              3: const pw.FlexColumnWidth(2.0),
              4: const pw.FlexColumnWidth(2.0),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.8),
              7: const pw.FlexColumnWidth(1.8),
              8: const pw.FlexColumnWidth(1.6),
              9: const pw.FlexColumnWidth(1.8),
              10: const pw.FlexColumnWidth(1.8),
              11: const pw.FlexColumnWidth(1.6),
              12: const pw.FlexColumnWidth(1.7),
              13: const pw.FlexColumnWidth(1.3),
            },
            cellAlignments: {
              0: pw.Alignment.centerRight,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
              11: pw.Alignment.centerRight,
              12: pw.Alignment.centerLeft,
              13: pw.Alignment.center,
            },
            headers: const [
              'Turno',
              'TPV',
              'Vendedor',
              'Apertura',
              'Cierre',
              'Dur.',
              'Ventas',
              'Efectivo',
              'Egresos',
              'Esperado',
              'Contado',
              'Dif.',
              'Conciliación',
              'F/E',
            ],
            data: [
              ...turnos.map(
                (t) => [
                  '#${t.id}',
                  t.tpvDenominacion,
                  t.vendedorDisplay,
                  _fechaHora.format(t.fechaApertura),
                  t.fechaCierre == null
                      ? 'En curso'
                      : _fechaHora.format(t.fechaCierre!),
                  t.duracionDisplay,
                  _money.format(t.ventasTotales),
                  _money.format(t.totalEfectivo),
                  _money.format(t.totalEgresos),
                  _money.format(t.efectivoEsperadoCalculado),
                  t.efectivoReal == null ? '-' : _money.format(t.efectivoReal!),
                  t.diferenciaCalculada == null
                      ? '-'
                      : _money.format(t.diferenciaCalculada!),
                  t.conciliacionEstado,
                  t.tieneDiscrepanciasInventario
                      ? '${t.reporte.faltantes.length}/${t.reporte.excesos.length}'
                      : '-',
                ],
              ),
              [
                'TOTALES',
                '',
                '',
                '',
                '',
                '',
                _money.format(ventas),
                _money.format(efectivo),
                _money.format(egresos),
                '',
                _money.format(contado),
                _money.format(diferencias),
                '',
                '',
              ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Esperado = fondo inicial + efectivo cobrado - egresos parciales. '
            'F/E = productos faltantes / excedentes reportados al cierre.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Turnos_Caja_${_archivo.format(DateTime.now())}',
    );
  }

  // ===================================================================
  // Piezas reutilizables
  // ===================================================================

  static pw.Widget _headerActa(CajaTurno turno, String storeName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Acta de cierre de turno',
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '$storeName · ${turno.tpvDenominacion}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Turno #${turno.id}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    turno.conciliacionEstado,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(height: 1),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generado: ${_fechaHora.format(DateTime.now())} - $_appName',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }

  static pw.Widget _seccion(String titulo) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: PdfColors.blueGrey50,
      child: pw.Text(
        titulo.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey800,
        ),
      ),
    );
  }

  static pw.Widget _subtitulo(String texto, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4, top: 2),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static pw.Widget _aviso(String texto) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber300, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        texto,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.brown800),
      ),
    );
  }

  static pw.Widget _tablaDatos(List<List<String>> filas) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.4),
        1: const pw.FlexColumnWidth(3.6),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
      },
      data: filas,
    );
  }

  static pw.Widget _tablaConciliacion(CajaTurno turno) {
    final diferencia = turno.diferenciaCalculada;
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.4),
        1: const pw.FlexColumnWidth(1.6),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
      },
      headers: const ['Concepto', 'Importe'],
      data: [
        ['Fondo inicial', _money.format(turno.efectivoInicial)],
        ['(+) Efectivo cobrado', _money.format(turno.totalEfectivo)],
        [
          '(-) Egresos parciales (${turno.egresosCantidad})',
          _money.format(turno.totalEgresos),
        ],
        [
          '(=) Efectivo esperado en caja',
          _money.format(turno.efectivoEsperadoCalculado),
        ],
        [
          'Efectivo contado al cierre',
          turno.efectivoReal == null
              ? 'Sin conteo'
              : _money.format(turno.efectivoReal!),
        ],
        [
          'Diferencia',
          diferencia == null ? '-' : _money.format(diferencia),
        ],
        ['Cobros digitales', _money.format(turno.totalDigital)],
      ],
    );
  }

  static pw.Widget _tablaVentas(CajaTurno turno) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      cellAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      headers: const [
        'Ventas',
        'Operaciones',
        'Pagadas',
        'Ticket prom.',
        'Unidades',
      ],
      data: [
        [
          _money.format(turno.ventasTotales),
          '${turno.operacionesVenta}',
          '${turno.ventasPagadas}',
          _money.format(turno.ticketPromedio),
          _units.format(turno.productosVendidos),
        ],
      ],
    );
  }

  static pw.Widget _tablaPagos(CajaTurno turno) {
    final total = turno.totalPagos;
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.0),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.6),
        3: const pw.FlexColumnWidth(1.0),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headers: const ['Medio de pago', 'Cobros', 'Monto', '%'],
      data: [
        ...turno.desglosePagos.map(
          (p) => [
            '${p.medio}${p.esEfectivo ? ' (efectivo)' : ''}',
            '${p.cantidad}',
            _money.format(p.monto),
            total > 0
                ? '${(p.monto * 100 / total).toStringAsFixed(1)}%'
                : '-',
          ],
        ),
        ['TOTAL', '', _money.format(total), '100%'],
      ],
    );
  }

  static pw.Widget _tablaDiscrepancias(
    List<DiscrepanciaInventario> lineas,
    PdfColor fondo,
  ) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: pw.BoxDecoration(color: fondo),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(5.0),
        2: const pw.FlexColumnWidth(1.4),
      },
      cellAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
      },
      headers: const ['#', 'Producto', 'Unidades'],
      data: [
        for (var i = 0; i < lineas.length; i++)
          ['${i + 1}', lineas[i].producto, _units.format(lineas[i].cantidad)],
      ],
    );
  }

  static pw.Widget _firmas() {
    pw.Widget linea(String rol) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            height: 0.8,
            width: 150,
            color: PdfColors.grey600,
          ),
          pw.SizedBox(height: 4),
          pw.Text(rol, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );

    return pw.Row(
      children: [
        linea('Vendedor'),
        linea('Supervisor / Auditor'),
      ],
    );
  }
}
