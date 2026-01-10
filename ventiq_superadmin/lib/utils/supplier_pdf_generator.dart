import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/supplier_payment_model.dart';

class SupplierPdfGenerator {
  static Future<void> generateAndDownloadPdf({
    required SupplierPaymentSummary supplier,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required List<OrderPaymentDetail> orders,
  }) async {
    final pdf = pw.Document();

    // Load font if needed, otherwise use standard helvetica
    // For specific styling "Elegant", Helvetica is usually fine, or we can load Google Fonts
    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final dateFormat = DateFormat('dd/MM/yyyy');
    final numberFormat = NumberFormat('#,##0.00', 'es');

    // Calculations
    final cashDiscount = supplier.totalCash * 0.05;
    final netCash = supplier.totalCash - cashDiscount;
    final transferDiscount = supplier.totalTransfer * 0.15;
    final netTransfer = supplier.totalTransfer - transferDiscount;
    final totalToPay = netCash + netTransfer;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (context) {
          return [
            _buildHeader(supplier, fechaInicio, fechaFin, dateFormat),
            pw.SizedBox(height: 20),
            _buildPaymentSummaryTable(
              supplier,
              cashDiscount,
              netCash,
              transferDiscount,
              netTransfer,
              totalToPay,
              numberFormat,
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Detalle de Órdenes',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
            pw.Divider(),
            ...orders.map(
              (order) => _buildOrderItem(order, numberFormat, dateFormat),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 2),
            _buildTotalToPay(totalToPay, numberFormat),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Pago_${supplier.name.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _buildHeader(
    SupplierPaymentSummary supplier,
    DateTime fechaInicio,
    DateTime fechaFin,
    DateFormat dateFormat,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          supplier.name.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Reporte de Pagos',
          style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Fecha Inicio: ${dateFormat.format(fechaInicio)}'),
            pw.Text('Fecha Fin: ${dateFormat.format(fechaFin)}'),
          ],
        ),
        pw.Divider(thickness: 1, color: PdfColors.grey300),
      ],
    );
  }

  static pw.Widget _buildPaymentSummaryTable(
    SupplierPaymentSummary supplier,
    double cashDiscount,
    double netCash,
    double transferDiscount,
    double netTransfer,
    double totalToPay,
    NumberFormat numberFormat,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        children: [
          _buildSummaryRow(
            'Efectivo',
            supplier.totalCash,
            '5%',
            cashDiscount,
            netCash,
            numberFormat,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Divider(color: PdfColors.grey300),
          ),
          _buildSummaryRow(
            'Transferencia',
            supplier.totalTransfer,
            '15%',
            transferDiscount,
            netTransfer,
            numberFormat,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Divider(thickness: 2, color: PdfColors.blueGrey),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL A PAGAR',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '\$${numberFormat.format(totalToPay)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryRow(
    String label,
    double total,
    String discountPercent,
    double discountAmount,
    double net,
    NumberFormat numberFormat,
  ) {
    return pw.Row(
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Total: \$${numberFormat.format(total)}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Desc. ($discountPercent)',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.red700,
                ),
              ),
              pw.Text(
                '-\$${numberFormat.format(discountAmount)}',
                style: const pw.TextStyle(color: PdfColors.red700),
              ),
            ],
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Neto',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
              pw.Text(
                '\$${numberFormat.format(net)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildOrderItem(
    OrderPaymentDetail order,
    NumberFormat numberFormat,
    DateFormat dateFormat,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Orden #${order.orderId} - ${dateFormat.format(order.createdAt)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                order.isTransfer ? 'Transferencia' : 'Efectivo',
                style: pw.TextStyle(
                  fontSize: 10,
                  color:
                      order.isTransfer ? PdfColors.blue700 : PdfColors.green700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          ...order.products.map(
            (p) => pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${p.quantity} x ${p.productName}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.Text(
                  '\$${numberFormat.format(p.subtotal)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total Orden: ', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                '\$${numberFormat.format(order.total)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey200),
        ],
      ),
    );
  }

  static pw.Widget _buildTotalToPay(double total, NumberFormat numberFormat) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          'TOTAL A PAGAR: ',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '\$${numberFormat.format(total)}',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green700,
          ),
        ),
      ],
    );
  }
}
