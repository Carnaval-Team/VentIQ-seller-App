import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'referral_payments_service.dart';

class ReferralPdfService {
  static Future<void> generateAndSaveReferralReport({
    required Map<String, dynamic> referrer,
    required String referralCode,
    required int referredCount,
    required ReferralSummary summary,
    required List<Map<String, dynamic>> orders,
    required DateTime fromDate,
    required DateTime toDate,
    required double valorUsd,
    required double valorEuro,
    required double pctNacional,
    required double pctInternacional,
  }) async {
    final pdf = pw.Document();
    final moneyFmt = NumberFormat('#,##0.00');
    final dateFormat = DateFormat('dd/MM/yyyy');
    
    // Helper function to check if order is international
    bool isInternationalOrder(Map<String, dynamic> order) {
      return ReferralPaymentsService.isInternationalOrder(order);
    }

    // Build PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          _buildHeader(referrer, referralCode, fromDate, toDate, dateFormat),
          pw.SizedBox(height: 20),
          _buildSummarySection(
            referredCount,
            summary,
            valorUsd,
            valorEuro,
            pctNacional,
            pctInternacional,
            moneyFmt,
          ),
          pw.SizedBox(height: 20),
          _buildOrdersTable(orders, moneyFmt, isInternationalOrder),
        ],
      ),
    );

    // Save and print
    final fileName = 'reporte_referido_${referrer['name']?.toString().replaceAll(' ', '_') ?? referralCode}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: fileName,
    );
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> referrer,
    String referralCode,
    DateTime fromDate,
    DateTime toDate,
    DateFormat dateFormat,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Reporte de Pago a Referido',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.Text(
              'Fecha: ${dateFormat.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Nombre:', referrer['name']?.toString() ?? 'N/A'),
              _buildInfoRow('Email:', referrer['email']?.toString() ?? 'N/A'),
              _buildInfoRow('Teléfono:', referrer['telefono']?.toString() ?? 'N/A'),
              _buildInfoRow('Código de Referido:', referralCode),
              _buildInfoRow('Período:', '${dateFormat.format(fromDate)} - ${dateFormat.format(toDate)}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(value),
        ],
      ),
    );
  }

  static pw.Widget _buildSummarySection(
    int referredCount,
    ReferralSummary summary,
    double valorUsd,
    double valorEuro,
    double pctNacional,
    double pctInternacional,
    NumberFormat moneyFmt,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Resumen de Comisiones',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'Referidos',
                      referredCount.toString(),
                      PdfColors.green,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'Total Órdenes',
                      summary.totalOrders.toString(),
                      PdfColors.blue,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'Órdenes Nacionales',
                      summary.nacionalCount.toString(),
                      PdfColors.orange,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'Órdenes Internacionales',
                      summary.internacionalCount.toString(),
                      PdfColors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.blue200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Tasas de Cambio y Porcentajes',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Text('USD: ${moneyFmt.format(valorUsd)}'),
                  pw.SizedBox(width: 20),
                  pw.Text('EUR: ${moneyFmt.format(valorEuro)}'),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text('% Nacional: $pctNacional%'),
                  pw.SizedBox(width: 20),
                  pw.Text('% Internacional: $pctInternacional%'),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [PdfColors.blue800, PdfColors.blue600],
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
            ),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'TOTAL A PAGAR AL REFERIDO',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildPaymentAmount('CUP', moneyFmt.format(summary.comisionCup)),
                  ),
                  pw.Expanded(
                    child: _buildPaymentAmount('USD', moneyFmt.format(summary.totalReferidoUsd)),
                  ),
                  pw.Expanded(
                    child: _buildPaymentAmount('EUR', moneyFmt.format(summary.totalReferidoEuro)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryCard(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _getLighterColor(color),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _getLighterColor(color)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPaymentAmount(String currency, String amount) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          currency,
          style: const pw.TextStyle(
            color: PdfColors.white,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          amount,
          style: const pw.TextStyle(
            color: PdfColors.white,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildOrdersTable(
    List<Map<String, dynamic>> orders,
    NumberFormat moneyFmt,
    bool Function(Map<String, dynamic>) isInternationalOrder,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detalle de Órdenes',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 12),
        if (orders.isEmpty)
          pw.Text(
            'No hay órdenes en este período.',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          )
        else
          pw.Table.fromTextArray(
            data: <List<String>>[
              ['ID', 'Fecha', 'Método/Moneda', 'Tipo', 'Status', 'Total CUP', 'Total USD', 'Total EUR'],
              ...orders.map((order) {
                final isIntl = isInternationalOrder(order);
                final total = (order['total'] as num?)?.toDouble() ?? 0;
                final tUsd = (order['totalUsd'] as num?)?.toDouble() ?? 0;
                final tEuro = (order['totalEuro'] as num?)?.toDouble() ?? 0;
                final metodo = order['metodo_pago'] as String? ?? '—';
                final moneda = (order['moneda'] as String? ?? 'CUP').toUpperCase();
                final fecha = order['created_at']?.toString() ?? '';
                final status = order['status'] as String? ?? '';
                
                return [
                  '#${order['id']}',
                  fecha,
                  '$metodo • $moneda',
                  isIntl ? 'Internacional' : 'Nacional',
                  status,
                  moneyFmt.format(total),
                  moneyFmt.format(tUsd),
                  moneyFmt.format(tEuro),
                ];
              }).toList(),
            ],
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
            cellStyle: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey800,
            ),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            rowDecoration: const pw.BoxDecoration(),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            cellPadding: const pw.EdgeInsets.all(6),
            columnWidths: {
              0: const pw.FixedColumnWidth(60),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FixedColumnWidth(80),
              6: const pw.FixedColumnWidth(80),
              7: const pw.FixedColumnWidth(80),
            },
          ),
      ],
    );
  }

  static PdfColor _getLighterColor(PdfColor color) {
    // Return lighter versions of colors for backgrounds
    if (color == PdfColors.blue) return PdfColors.blue100;
    if (color == PdfColors.green) return PdfColors.green100;
    if (color == PdfColors.orange) return PdfColors.orange100;
    if (color == PdfColors.purple) return PdfColors.purple100;
    return PdfColors.grey100;
  }

}
