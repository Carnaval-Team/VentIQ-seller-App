import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models/hr/hr_salary_report.dart';
import '../../models/hr/hr_audit_log.dart';

class HRSalaryReportService {
  static final _supabase = Supabase.instance.client;

  /// Obtener reporte de salarios
  static Future<List<HRSalaryReportEntry>> getSalaryReport({
    required int storeId,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    try {
      print('💰 Obteniendo reporte de salarios: tienda $storeId');
      final response = await _supabase.rpc(
        'fn_hr_salary_report',
        params: {
          'p_id_tienda': storeId,
          'p_fecha_desde': fechaDesde.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta.toIso8601String().split('T')[0],
        },
      );

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        print('📋 ${data.length} entradas en reporte de salarios');
        return data
            .map((e) => HRSalaryReportEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo reporte de salarios: $e');
      rethrow;
    }
  }

  /// Obtener log de auditoria para un trabajador
  static Future<List<HRAuditLog>> getAuditLog({
    required int workerId,
    required int storeId,
  }) async {
    try {
      print('📋 Obteniendo auditoria: trabajador $workerId');
      final response = await _supabase
          .from('hr_dat_auditoria_salario')
          .select()
          .eq('id_trabajador', workerId)
          .eq('id_tienda', storeId)
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List<dynamic>)
          .map((e) => HRAuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo auditoria: $e');
      return [];
    }
  }

  /// Actualizar salario de un trabajador
  static Future<bool> updateWorkerSalary({
    required int workerId,
    required int storeId,
    required double salarioHoras,
    required double pagoPorResultado,
    required String modificadoPor,
    String? motivo,
  }) async {
    try {
      print('💰 Actualizando salario: trabajador $workerId');
      final response = await _supabase.rpc(
        'fn_hr_update_worker_salary',
        params: {
          'p_id_trabajador': workerId,
          'p_id_tienda': storeId,
          'p_salario_horas': salarioHoras,
          'p_pago_por_resultado': pagoPorResultado,
          'p_modificado_por': modificadoPor,
          'p_motivo': motivo,
        },
      );

      if (response['success'] == true) {
        print('✅ Salario actualizado: ${response['message']}');
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al actualizar salario');
      }
    } catch (e) {
      print('❌ Error actualizando salario: $e');
      rethrow;
    }
  }

  /// Generar PDF del reporte de salarios
  static Future<void> generateSalaryPDF({
    required List<HRSalaryReportEntry> entries,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    required String storeName,
  }) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');
    final currencyFormat = NumberFormat('#,##0.00');

    // Calcular totales
    double totalHoras = 0;
    double totalBase = 0;
    double totalPPR = 0;
    double totalGeneral = 0;
    for (final e in entries) {
      totalHoras += e.totalHoras;
      totalBase += e.totalSalarioBase;
      totalPPR += e.totalPPR;
      totalGeneral += e.totalGeneral;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Reporte de Salarios - $storeName',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Periodo: ${dateFormat.format(fechaDesde)} - ${dateFormat.format(fechaHasta)}',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.center,
            },
            headers: ['Nombre', 'Horas', '\$/h', 'Salario Base', 'PPR', 'Total', 'Dias'],
            data: [
              ...entries.map((e) => [
                e.nombreCompleto,
                e.totalHoras.toStringAsFixed(1),
                currencyFormat.format(e.salarioHoras),
                currencyFormat.format(e.totalSalarioBase),
                currencyFormat.format(e.totalPPR),
                currencyFormat.format(e.totalGeneral),
                e.diasTrabajados.toString(),
              ]),
              // Fila de totales
              [
                'TOTALES',
                totalHoras.toStringAsFixed(1),
                '',
                currencyFormat.format(totalBase),
                currencyFormat.format(totalPPR),
                currencyFormat.format(totalGeneral),
                '',
              ],
            ],
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Generado: ${dateFormat.format(DateTime.now())} - Inventtia Admin',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Reporte_Salarios_${dateFormat.format(fechaDesde)}_${dateFormat.format(fechaHasta)}',
    );
  }
}
