import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../../config/app_theme.dart';
import '../../models/agenda.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../providers/auth_provider.dart';
import '../../services/agenda_admin_service.dart';
import '../../services/catalogo_service.dart';

class ReservasScreen extends StatefulWidget {
  final Entidad entidad;
  const ReservasScreen({super.key, required this.entidad});

  @override
  State<ReservasScreen> createState() => _ReservasScreenState();
}

class _ReservasScreenState extends State<ReservasScreen> {
  List<Agenda> _reservas = [];
  bool _loading = true;

  // Filtros
  Local? _localFiltro;
  LocalServicio? _lsFiltro;
  DateTime? _desde;
  DateTime? _hasta;

  List<Local> _locales = [];
  List<LocalServicio> _localServicios = [];

  final _fmt = DateFormat('dd/MM/yyyy');
  final _fmtHora = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    // Por defecto: hoy
    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, now.day);
    _hasta = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _loadFiltros();
  }

  Future<void> _loadFiltros() async {
    final locales =
        await CatalogoService.getLocalesByEntidad(widget.entidad.id);
    if (mounted) setState(() => _locales = locales);
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uuid =
          context.read<AuthProvider>().user?.id ?? '';
      final data = await AgendaAdminService.listarAgendas(
        uuidUsuario: uuid,
        idEntidad: widget.entidad.id,
        idLocal: _localFiltro?.id,
        idLocalServicio: _lsFiltro?.id,
        desde: _desde,
        hasta: _hasta,
      );
      if (mounted) setState(() => _reservas = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onLocalChange(Local? local) async {
    setState(() {
      _localFiltro = local;
      _lsFiltro = null;
      _localServicios = [];
    });
    if (local != null) {
      final ls = await CatalogoService.getLocalServicios(idLocal: local.id);
      if (mounted) setState(() => _localServicios = ls);
    }
    _load();
  }

  Future<void> _pickDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _desde ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(() =>
          _desde = DateTime(picked.year, picked.month, picked.day));
      _load();
    }
  }

  Future<void> _pickHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hasta ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(() => _hasta =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
      _load();
    }
  }

  void _clearFiltros() {
    final now = DateTime.now();
    setState(() {
      _localFiltro = null;
      _lsFiltro = null;
      _localServicios = [];
      _desde = DateTime(now.year, now.month, now.day);
      _hasta = DateTime(now.year, now.month, now.day, 23, 59, 59);
    });
    _load();
  }

  // ──────────────────────────────────────────────────────────────────
  // EXPORT PDF
  // ──────────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final filtroDesc = _buildFiltroDesc();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Reservas · ${widget.entidad.denominacion}',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (filtroDesc.isNotEmpty)
              pw.Text(filtroDesc,
                  style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 28,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerLeft,
              6: pw.Alignment.centerLeft,
            },
            headers: [
              'ID', 'Fecha reserva', 'Servicio', 'Estado',
              'Nombre', 'CI', 'Teléfono',
            ],
            data: _reservas.map((r) {
              final c = r.localServicio;
              return [
                '${r.id}',
                _fmtHora.format(r.fechaHoraReserva),
                c?.servicio?.nombre ?? '—',
                r.estado?.nombre ?? '—',
                '${r.uuidUsuario ?? '—'}',
                '—',
                '—',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'reservas_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  // ──────────────────────────────────────────────────────────────────
  // EXPORT EXCEL
  // ──────────────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Reservas'];

    final headers = [
      'ID', 'Fecha reserva', 'Fecha atención', 'Local', 'Servicio',
      'Estado', 'Nombre', 'Apellidos', 'CI', 'Teléfono',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = xl.CellStyle(bold: true);
    }

    for (var r = 0; r < _reservas.length; r++) {
      final ag = _reservas[r];
      final row = [
        ag.id.toString(),
        _fmtHora.format(ag.fechaHoraReserva),
        ag.fechaHoraAtencion != null
            ? _fmtHora.format(ag.fechaHoraAtencion!)
            : '',
        ag.localServicio?.local?.nombre ?? '',
        ag.localServicio?.servicio?.nombre ?? '',
        ag.estado?.nombre ?? '',
        '',
        '',
        '',
        '',
      ];
      for (var c = 0; c < row.length; c++) {
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: c, rowIndex: r + 1))
            .value = xl.TextCellValue(row[c]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/reservas_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Reservas exportadas'),
    );
  }

  String _buildFiltroDesc() {
    final parts = <String>[];
    if (_localFiltro != null) parts.add('Local: ${_localFiltro!.nombre}');
    if (_lsFiltro != null)
      parts.add('Servicio: ${_lsFiltro!.servicio?.nombre ?? ''}');
    if (_desde != null) parts.add('Desde: ${_fmt.format(_desde!)}');
    if (_hasta != null) parts.add('Hasta: ${_fmt.format(_hasta!)}');
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reservas'),
            Text(widget.entidad.denominacion,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportar PDF',
            onPressed: _reservas.isEmpty ? null : _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Exportar Excel',
            onPressed: _reservas.isEmpty ? null : _exportExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltros(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reservas.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _reservas.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) =>
                              _ReservaCard(agenda: _reservas[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              // Local
              Expanded(
                child: DropdownButtonFormField<Local?>(
                  value: _localFiltro,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Local',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Todos')),
                    ..._locales.map((l) => DropdownMenuItem(
                        value: l, child: Text(l.nombre, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: _onLocalChange,
                ),
              ),
              const SizedBox(width: 8),
              // LocalServicio
              Expanded(
                child: DropdownButtonFormField<LocalServicio?>(
                  value: _lsFiltro,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Servicio',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Todos')),
                    ..._localServicios.map((ls) => DropdownMenuItem(
                        value: ls,
                        child: Text(ls.servicio?.nombre ?? '',
                            overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setState(() => _lsFiltro = v);
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Desde
              Expanded(
                child: InkWell(
                  onTap: _pickDesde,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Desde',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    child: Text(
                      _desde != null ? _fmt.format(_desde!) : '—',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Hasta
              Expanded(
                child: InkWell(
                  onTap: _pickHasta,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hasta',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    child: Text(
                      _hasta != null ? _fmt.format(_hasta!) : '—',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                tooltip: 'Limpiar filtros',
                onPressed: _clearFiltros,
              ),
            ],
          ),
          if (_reservas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_reservas.length} reserva${_reservas.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_outlined,
              size: 64,
              color: AppTheme.textSecondary.withOpacity(0.35)),
          const SizedBox(height: 12),
          const Text('Sin reservas para los filtros aplicados',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de reserva
// ─────────────────────────────────────────────────────────────────────────────
class _ReservaCard extends StatelessWidget {
  final Agenda agenda;
  const _ReservaCard({required this.agenda});

  @override
  Widget build(BuildContext context) {
    final estado = agenda.estado;
    final ls = agenda.localServicio;
    final fmtHora = DateFormat('dd/MM/yyyy HH:mm');

    Color estadoColor = AppTheme.primary;
    if (estado?.nombre == 'cancelado') estadoColor = AppTheme.error;
    if (estado?.nombre == 'completado') estadoColor = AppTheme.success;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ls?.servicio?.nombre ?? '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    estado?.nombre ?? '—',
                    style: TextStyle(
                        color: estadoColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (ls?.local != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.store_outlined,
                      size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(ls!.local!.nombre,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  fmtHora.format(agenda.fechaHoraReserva),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                if (agenda.fechaHoraAtencion != null) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.check_circle_outline,
                      size: 13, color: AppTheme.success),
                  const SizedBox(width: 4),
                  Text(
                    fmtHora.format(agenda.fechaHoraAtencion!),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.success),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.tag, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text('ID: ${agenda.id}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
