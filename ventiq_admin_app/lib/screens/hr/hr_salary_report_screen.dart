import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_salary_report.dart';
import '../../services/hr/hr_salary_report_service.dart';
import '../../services/store_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/hr/hr_drawer.dart';

class HRSalaryReportScreen extends StatefulWidget {
  const HRSalaryReportScreen({super.key});

  @override
  State<HRSalaryReportScreen> createState() => _HRSalaryReportScreenState();
}

class _HRSalaryReportScreenState extends State<HRSalaryReportScreen> {
  bool _isLoading = true;
  int? _storeId;
  String _storeName = 'Tienda';

  List<HRSalaryReportEntry> _entries = [];

  late DateTime _fechaDesde;
  late DateTime _fechaHasta;

  final _currencyFormat = NumberFormat('#,##0.00');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaDesde = DateTime(now.year, now.month, 1);
    _fechaHasta = DateTime(now.year, now.month + 1, 0);
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      final storeData = await StoreService.getWorkerRequiredData();
      if (storeData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final userPrefs = UserPreferencesService();
      final storeInfo = await userPrefs.getCurrentStoreInfo();

      setState(() {
        _storeId = storeData['storeId'] as int?;
        _storeName = storeInfo?['denominacion'] as String? ?? 'Tienda';
      });
      await _loadReport();
    } catch (e) {
      print('❌ Error inicializando reporte: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReport() async {
    if (_storeId == null) return;
    setState(() => _isLoading = true);

    try {
      final entries = await HRSalaryReportService.getSalaryReport(
        storeId: _storeId!,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );

      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando reporte: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _fechaDesde, end: _fechaHasta),
      helpText: 'Seleccionar periodo',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Guardar',
    );

    if (picked != null) {
      setState(() {
        _fechaDesde = picked.start;
        _fechaHasta = picked.end;
      });
      await _loadReport();
    }
  }

  void _exportPDF() {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay datos para exportar'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    HRSalaryReportService.generateSalaryPDF(
      entries: _entries,
      fechaDesde: _fechaDesde,
      fechaHasta: _fechaHasta,
      storeName: _storeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calcular totales
    double totalHoras = 0;
    double totalBase = 0;
    double totalPPR = 0;
    double totalGeneral = 0;
    for (final e in _entries) {
      totalHoras += e.totalHoras;
      totalBase += e.totalSalarioBase;
      totalPPR += e.totalPPR;
      totalGeneral += e.totalGeneral;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Reporte de Salarios',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadReport,
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: const HRDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _exportPDF,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.picture_as_pdf, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Date range selector
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: InkWell(
                    onTap: _selectDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.background,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Text(
                            '${_dateFormat.format(_fechaDesde)} - ${_dateFormat.format(_fechaHasta)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),

                // Table
                Expanded(
                  child: _entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                'Sin datos para este periodo',
                                style: TextStyle(color: Colors.grey[500], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            // Resumen rapido
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              color: Colors.white,
                              child: Row(
                                children: [
                                  _buildSummaryChip('${_entries.length} trabajadores', Icons.people, AppColors.info),
                                  const SizedBox(width: 10),
                                  _buildSummaryChip('${totalHoras.toStringAsFixed(1)}h totales', Icons.access_time, AppColors.primary),
                                  const SizedBox(width: 10),
                                  _buildSummaryChip('\$${_currencyFormat.format(totalGeneral)}', Icons.account_balance_wallet, AppColors.success),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // Table
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: MediaQuery.of(context).size.width - 16,
                                    ),
                                    child: DataTable(
                                      columnSpacing: 12,
                                      headingTextStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        color: AppColors.textPrimary,
                                      ),
                                      dataTextStyle: const TextStyle(fontSize: 11),
                                      headingRowColor: WidgetStateProperty.all(
                                        AppColors.primary.withOpacity(0.05),
                                      ),
                                      columns: const [
                                        DataColumn(label: Text('#')),
                                        DataColumn(label: Text('Nombre')),
                                        DataColumn(label: Text('Rol')),
                                        DataColumn(label: Text('Dias'), numeric: true),
                                        DataColumn(label: Text('Horas'), numeric: true),
                                        DataColumn(label: Text('\$/h'), numeric: true),
                                        DataColumn(label: Text('Salario Base'), numeric: true),
                                        DataColumn(label: Text('PPR'), numeric: true),
                                        DataColumn(label: Text('Total'), numeric: true),
                                        DataColumn(label: Text('Prom/dia'), numeric: true),
                                      ],
                                      rows: [
                                        ...List.generate(_entries.length, (i) {
                                          final e = _entries[i];
                                          final avgPerDay = e.diasTrabajados > 0 ? e.totalGeneral / e.diasTrabajados : 0.0;
                                          return DataRow(
                                            color: i == 0
                                                ? WidgetStateProperty.all(AppColors.success.withOpacity(0.05))
                                                : null,
                                            cells: [
                                              DataCell(Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontWeight: i < 3 ? FontWeight.w700 : FontWeight.normal,
                                                  color: i == 0 ? AppColors.success : null,
                                                ),
                                              )),
                                              DataCell(Text(
                                                e.nombreCompleto,
                                                style: const TextStyle(fontWeight: FontWeight.w500),
                                              )),
                                              DataCell(Text(
                                                e.rolNombre ?? '-',
                                                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                              )),
                                              DataCell(Text('${e.diasTrabajados}')),
                                              DataCell(Text('${e.totalHoras.toStringAsFixed(1)}h')),
                                              DataCell(Text('\$${_currencyFormat.format(e.salarioHoras)}')),
                                              DataCell(Text('\$${_currencyFormat.format(e.totalSalarioBase)}')),
                                              DataCell(Text(
                                                '\$${_currencyFormat.format(e.totalPPR)}',
                                                style: TextStyle(
                                                  color: e.totalPPR > 0 ? AppColors.success : null,
                                                ),
                                              )),
                                              DataCell(Text(
                                                '\$${_currencyFormat.format(e.totalGeneral)}',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              )),
                                              DataCell(Text(
                                                '\$${avgPerDay.toStringAsFixed(2)}',
                                                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                              )),
                                            ],
                                          );
                                        }),
                                        // Totals row
                                        DataRow(
                                          color: WidgetStateProperty.all(
                                            AppColors.primary.withOpacity(0.08),
                                          ),
                                          cells: [
                                            const DataCell(Text('')),
                                            const DataCell(Text(
                                              'TOTALES',
                                              style: TextStyle(fontWeight: FontWeight.w700),
                                            )),
                                            const DataCell(Text('')),
                                            const DataCell(Text('')),
                                            DataCell(Text(
                                              '${totalHoras.toStringAsFixed(1)}h',
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            )),
                                            DataCell(Text(
                                              totalHoras > 0
                                                  ? '\$${(totalBase / totalHoras).toStringAsFixed(2)}'
                                                  : '-',
                                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                            )),
                                            DataCell(Text(
                                              '\$${_currencyFormat.format(totalBase)}',
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            )),
                                            DataCell(Text(
                                              '\$${_currencyFormat.format(totalPPR)}',
                                              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success),
                                            )),
                                            DataCell(Text(
                                              '\$${_currencyFormat.format(totalGeneral)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary,
                                              ),
                                            )),
                                            const DataCell(Text('')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryChip(String text, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
