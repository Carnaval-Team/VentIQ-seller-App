import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'dart:io';

import '../../config/app_theme.dart';
import '../../models/agenda.dart';
import '../../models/campo_adicional.dart';
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
  // Agrupa las reservas por nombre de local
  Map<String, List<Agenda>> _agruparPorLocal() {
    final map = <String, List<Agenda>>{};
    for (final r in _reservas) {
      final key = r.localServicio?.local?.nombre ?? 'Sin local';
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }

  /// Columnas dinámicas para datos adicionales: unión ordenada de claves que
  /// aparecen en las reservas listadas. Devuelve pares (clave, etiqueta).
  /// La etiqueta sale de campos_adicionales del servicio si está disponible.
  List<({String clave, String etiqueta})> _columnasDatos(List<Agenda> lista) {
    final etiquetas = <String, String>{};
    final orden = <String>[];
    for (final r in lista) {
      // Rotula con la config del servicio (si viene).
      for (final c in r.localServicio?.servicio?.camposAdicionales ??
          const <CampoAdicional>[]) {
        etiquetas[c.clave] = c.etiqueta;
      }
      // Asegura incluir claves presentes en los valores aunque no haya config.
      final datos = r.datosAdicionales;
      if (datos != null) {
        for (final k in datos.keys) {
          if (!orden.contains(k)) orden.add(k);
          etiquetas.putIfAbsent(k, () => k);
        }
      }
    }
    return orden.map((k) => (clave: k, etiqueta: etiquetas[k] ?? k)).toList();
  }

  /// ¿Alguna reserva de la lista fue hecha para un tercero?
  bool _hayTerceros(List<Agenda> lista) =>
      lista.any((r) => r.reservadoPor != null &&
          r.uuidUsuario != null &&
          r.reservadoPor != r.uuidUsuario);

  String _valorDato(Agenda r, String clave) {
    final v = r.datosAdicionales?[clave];
    return v == null ? '-' : '$v';
  }

  Future<void> _exportPdf() async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );
    final filtroDesc = _buildFiltroDesc();
    final grupos = _agruparPorLocal();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Reservas - ${widget.entidad.denominacion}',
                style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold)),
            if (filtroDesc.isNotEmpty)
              pw.Text(filtroDesc,
                  style: pw.TextStyle(font: fontRegular, fontSize: 8)),
            pw.SizedBox(height: 6),
            pw.Divider(),
          ],
        ),
        build: (_) {
          final widgets = <pw.Widget>[];
          grupos.forEach((localNombre, lista) {
            final cols = _columnasDatos(lista);
            final conTerceros = _hayTerceros(lista);
            widgets.add(
              pw.Text(localNombre,
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold)),
            );
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(
                    font: fontBold, fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
                cellHeight: 22,
                headers: [
                  'Servicio', 'Fecha reserva',
                  'Nombre', 'Apellidos', 'CI', 'Telefono', 'Cant.',
                  if (conTerceros) 'Tercero',
                  ...cols.map((c) => c.etiqueta),
                ],
                data: lista.map((r) {
                  final cli = r.cliente;
                  final esTercero = r.reservadoPor != null &&
                      r.uuidUsuario != null &&
                      r.reservadoPor != r.uuidUsuario;
                  return [
                    r.localServicio?.servicio?.nombre ?? '-',
                    _fmtHora.format(r.fechaHoraReserva),
                    cli?.nombre ?? '-',
                    cli?.apellidos ?? '-',
                    cli?.ci ?? '-',
                    cli?.telefono ?? '-',
                    '${r.cantidad}',
                    if (conTerceros) (esTercero ? 'Sí' : 'No'),
                    ...cols.map((c) => _valorDato(r, c.clave)),
                  ];
                }).toList(),
              ),
            );
            widgets.add(pw.SizedBox(height: 14));
          });
          return widgets;
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename:
            'reservas_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  // ──────────────────────────────────────────────────────────────────
  // EXPORT EXCEL
  // ──────────────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Reservas'];

    // Columnas dinámicas (datos adicionales) y bandera de terceros sobre TODAS
    // las reservas, para que la hoja única tenga columnas consistentes.
    final cols = _columnasDatos(_reservas);
    final conTerceros = _hayTerceros(_reservas);

    final headers = [
      'Local', 'Servicio', 'Fecha reserva',
      'Nombre', 'Apellidos', 'CI', 'Telefono', 'Cantidad',
      if (conTerceros) 'Para tercero',
      ...cols.map((c) => c.etiqueta),
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = xl.CellStyle(bold: true);
    }

    // Agrupar por local para el Excel
    final grupos = _agruparPorLocal();
    int rowIdx = 1;
    grupos.forEach((localNombre, lista) {
      for (final ag in lista) {
        final cli = ag.cliente;
        final esTercero = ag.reservadoPor != null &&
            ag.uuidUsuario != null &&
            ag.reservadoPor != ag.uuidUsuario;
        final row = [
          localNombre,
          ag.localServicio?.servicio?.nombre ?? '',
          _fmtHora.format(ag.fechaHoraReserva),
          cli?.nombre ?? '',
          cli?.apellidos ?? '',
          cli?.ci ?? '',
          cli?.telefono ?? '',
          '${ag.cantidad}',
          if (conTerceros) (esTercero ? 'Sí' : 'No'),
          ...cols.map((c) => _valorDato(ag, c.clave)),
        ];
        for (var c = 0; c < row.length; c++) {
          sheet
              .cell(xl.CellIndex.indexByColumnRow(
                  columnIndex: c, rowIndex: rowIdx))
              .value = xl.TextCellValue(row[c]);
        }
        rowIdx++;
      }
    });

    final bytes = excel.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/reservas_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Reservas exportadas',
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
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
                            child: _buildTabla(),
                          ),
              ),
            ],
          ),
        ),
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
                      _desde != null ? _fmt.format(_desde!) : '-',
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
                      _hasta != null ? _fmt.format(_hasta!) : '-',
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

  Widget _buildTabla() {
    final grupos = _agruparPorLocal();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: grupos.length,
      itemBuilder: (_, gi) {
        final localNombre = grupos.keys.elementAt(gi);
        final lista = grupos[localNombre]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grupos.length > 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                child: Row(
                  children: [
                    const Icon(Icons.store_outlined,
                        size: 14, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(localNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
            ],
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 44,
                  columnSpacing: 16,
                  headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.textPrimary),
                  dataTextStyle: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                  columns: const [
                    DataColumn(label: Text('Servicio')),
                    DataColumn(label: Text('Fecha')),
                    DataColumn(label: Text('Nombre')),
                    DataColumn(label: Text('Apellidos')),
                    DataColumn(label: Text('CI')),
                  ],
                  rows: lista.map((r) {
                    final cli = r.cliente;
                    return DataRow(cells: [
                      DataCell(Text(
                          r.localServicio?.servicio?.nombre ?? '-',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary))),
                      DataCell(Text(
                          _fmt.format(r.fechaHoraReserva))),
                      DataCell(Text(cli?.nombre ?? '-')),
                      DataCell(Text(cli?.apellidos ?? '-')),
                      DataCell(Text(cli?.ci ?? '-')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
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
// Unused – kept as reference, not called
// ─────────────────────────────────────────────────────────────────────────────
// ignore: unused_element
class _ReservaCard extends StatelessWidget {
  final Agenda agenda;
  const _ReservaCard({required this.agenda});

  @override
  Widget build(BuildContext context) {
    final estado = agenda.estado;
    final ls = agenda.localServicio;
    final cliente = agenda.cliente;
    final fmtHora = DateFormat('dd/MM/yyyy HH:mm');
    final nombreEstado = estado?.nombre.toLowerCase() ?? '';

    Color estadoColor = AppTheme.primary;
    if (nombreEstado == 'cancelado') estadoColor = AppTheme.error;
    if (nombreEstado == 'completado') estadoColor = AppTheme.success;

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
            // Fila superior: servicio + estado
            Row(
              children: [
                Expanded(
                  child: Text(
                    ls?.servicio?.nombre ?? '-',
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
                    estado?.nombre ?? '-',
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
              _InfoRow(Icons.store_outlined, ls!.local!.nombre),
            ],
            const SizedBox(height: 6),
            _InfoRow(
              Icons.access_time,
              fmtHora.format(agenda.fechaHoraReserva),
            ),
            if (agenda.fechaHoraAtencion != null)
              _InfoRow(
                Icons.check_circle_outline,
                fmtHora.format(agenda.fechaHoraAtencion!),
                color: AppTheme.success,
              ),
            // Datos del cliente
            if (cliente != null) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 6),
              _InfoRow(Icons.person_outlined,
                  cliente.nombreCompleto.isNotEmpty
                      ? cliente.nombreCompleto
                      : '-'),
              if (cliente.ci != null && cliente.ci!.isNotEmpty)
                _InfoRow(Icons.badge_outlined, 'CI: ${cliente.ci}'),
              if (cliente.telefono != null && cliente.telefono!.isNotEmpty)
                _InfoRow(Icons.phone_outlined, cliente.telefono!),
            ],
            const SizedBox(height: 4),
            _InfoRow(Icons.tag, 'ID: ${agenda.id}'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoRow(this.icon, this.text,
      {this.color = AppTheme.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
