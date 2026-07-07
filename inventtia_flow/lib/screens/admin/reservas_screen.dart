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
import '../../services/agenda_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/notificacion_service.dart';
import '../../widgets/datos_adicionales_form.dart';
import 'package:url_launcher/url_launcher.dart';

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
  EstadoAgenda? _estadoFiltro;

  List<Local> _locales = [];
  List<LocalServicio> _localServicios = [];
  List<EstadoAgenda> _estados = [];

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
    final estados = await AgendaService.getEstados();
    if (mounted) {
      setState(() {
        _locales = locales;
        _estados = estados;
        final reservado = estados
            .where((e) => e.nombre.toLowerCase() == 'reservado')
            .firstOrNull;
        _estadoFiltro = reservado ?? estados.firstOrNull;
      });
    }
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
        idEstado: _estadoFiltro?.id,
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

  Future<void> _cancelarReserva(Agenda reserva) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Text(
          '¿Estás seguro de cancelar la reserva de '
          '${reserva.cliente?.nombreCompleto ?? 'este cliente'} '
          'para el servicio ${reserva.localServicio?.servicio?.nombre ?? ''}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await AgendaService.cancelarTicket(reserva.id);

      // Notificar al cliente si tiene uuid_usuario
      final uuidCliente = reserva.uuidUsuario;
      if (uuidCliente != null && uuidCliente.isNotEmpty) {
        await NotificacionService.crearNotificacion(
          uuidUsuario: uuidCliente,
          tipo: 'reserva',
          titulo: 'Reserva cancelada',
          mensaje:
              'Tu reserva para ${reserva.localServicio?.servicio?.nombre ?? 'el servicio'} '
              'el ${DateFormat('dd/MM/yyyy HH:mm').format(reserva.fechaHoraReserva)} '
              'ha sido cancelada por la administración.',
          idLocalServicio: reserva.idLocalServicio,
          idReferencia: reserva.id,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reserva cancelada y cliente notificado'),
            backgroundColor: AppTheme.success,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editarReserva(Agenda reserva) async {
    final camposAdicionales =
        reserva.localServicio?.servicio?.camposAdicionales ?? const <CampoAdicional>[];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditarReservaSheet(
        reserva: reserva,
        camposAdicionales: camposAdicionales,
        onSaved: _load,
      ),
    );
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
      _estadoFiltro = _estados
          .where((e) => e.nombre.toLowerCase() == 'reservado')
          .firstOrNull;
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
  /// Se excluyen las claves que ya se muestran como columnas fijas.
  List<({String clave, String etiqueta})> _columnasDatos(List<Agenda> lista) {
    const clavesFijas = {'nombre', 'apellidos', 'ci', 'telefono'};
    final etiquetas = <String, String>{};
    final orden = <String>[];
    for (final r in lista) {
      // Rotula con la config del servicio (si viene).
      for (final c in r.localServicio?.servicio?.camposAdicionales ??
          const <CampoAdicional>[]) {
        if (!clavesFijas.contains(c.clave)) {
          etiquetas[c.clave] = c.etiqueta;
        }
      }
      // Asegura incluir claves presentes en los valores aunque no haya config.
      final datos = r.datosAdicionales;
      if (datos != null) {
        for (final k in datos.keys) {
          if (clavesFijas.contains(k)) continue;
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

  /// Devuelve el dato del cliente real. Si la reserva fue creada por un
  /// administrador, los datos del cliente se guardan en [datosAdicionales].
  /// Si no, se usa el perfil del cliente ([r.cliente]).
  String _datoCliente(Agenda r, String clave) {
    final v = r.datosAdicionales?[clave];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim();
    }
    final cli = r.cliente;
    switch (clave) {
      case 'nombre':
        return cli?.nombre ?? '-';
      case 'apellidos':
        return cli?.apellidos ?? '-';
      case 'ci':
        return cli?.ci ?? '-';
      case 'telefono':
        return cli?.telefono ?? '-';
      case 'email':
        return '-';
      default:
        return '-';
    }
  }

  Future<void> _exportPdf() async {
    if (!_esUnaSolaFecha()) {
      _mostrarCartelExportacion();
      return;
    }

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
                  final esTercero = r.reservadoPor != null &&
                      r.uuidUsuario != null &&
                      r.reservadoPor != r.uuidUsuario;
                  return [
                    r.localServicio?.servicio?.nombre ?? '-',
                    _fmtHora.format(r.fechaHoraReserva),
                    _datoCliente(r, 'nombre'),
                    _datoCliente(r, 'apellidos'),
                    _datoCliente(r, 'ci'),
                    _datoCliente(r, 'telefono'),
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
    if (!_esUnaSolaFecha()) {
      _mostrarCartelExportacion();
      return;
    }

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
        final esTercero = ag.reservadoPor != null &&
            ag.uuidUsuario != null &&
            ag.reservadoPor != ag.uuidUsuario;
        final row = [
          localNombre,
          ag.localServicio?.servicio?.nombre ?? '',
          _fmtHora.format(ag.fechaHoraReserva),
          _datoCliente(ag, 'nombre'),
          _datoCliente(ag, 'apellidos'),
          _datoCliente(ag, 'ci'),
          _datoCliente(ag, 'telefono'),
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

  /// True si el filtro de fecha abarca exactamente un solo día.
  bool _esUnaSolaFecha() {
    if (_desde == null || _hasta == null) return false;
    return _desde!.year == _hasta!.year &&
        _desde!.month == _hasta!.month &&
        _desde!.day == _hasta!.day;
  }

  /// Muestra cartel indicando que se debe filtrar una sola fecha para exportar.
  void _mostrarCartelExportacion() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.warning),
            SizedBox(width: 8),
            Text('Exportar reservas'),
          ],
        ),
        content: const Text(
          'Para exportar el listado de reservas debes filtrar una sola fecha.\n\n'
          'Por favor, selecciona el mismo día en los campos "Desde" y "Hasta".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
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
              const SizedBox(width: 8),
              // Estado
              Expanded(
                child: DropdownButtonFormField<EstadoAgenda?>(
                  value: _estadoFiltro,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _estados.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() => _estadoFiltro = v);
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
    // Columnas dinámicas de datos adicionales y terceros calculadas sobre todo
    // el listado para mantener consistencia entre grupos y reportes.
    final cols = _columnasDatos(_reservas);
    final conTerceros = _hayTerceros(_reservas);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ancho mínimo para forzar scroll horizontal cuando hay muchas columnas
        final minWidth = constraints.maxWidth < 800 ? 800.0 : constraints.maxWidth;
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 44,
                        columnSpacing: 12,
                        headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppTheme.textPrimary),
                        dataTextStyle: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                        columns: [
                          const DataColumn(label: Text('Servicio')),
                          const DataColumn(label: Text('Fecha')),
                          const DataColumn(label: Text('Nombre')),
                          const DataColumn(label: Text('Apellidos')),
                          const DataColumn(label: Text('CI')),
                          const DataColumn(label: Text('Teléfono')),
                          const DataColumn(label: Text('Cant.')),
                          if (conTerceros)
                            const DataColumn(label: Text('Tercero')),
                          ...cols.map((c) => DataColumn(
                                label: SizedBox(
                                  width: 120,
                                  child: Text(
                                    c.etiqueta,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )),
                          const DataColumn(label: Text('Acciones')),
                        ],
                        rows: lista.map((r) {
                          final esTercero = r.reservadoPor != null &&
                              r.uuidUsuario != null &&
                              r.reservadoPor != r.uuidUsuario;
                          final puedeCancelar = r.estado?.esCancelado != true;
                          return DataRow(cells: [
                            DataCell(Text(
                                r.localServicio?.servicio?.nombre ?? '-',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textPrimary))),
                            DataCell(Text(_fmt.format(r.fechaHoraReserva))),
                            DataCell(Text(
                              _datoCliente(r, 'nombre'),
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(Text(
                              _datoCliente(r, 'apellidos'),
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(Text(
                              _datoCliente(r, 'ci'),
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(
                              _datoCliente(r, 'telefono') == '-' || _datoCliente(r, 'telefono').isEmpty
                                  ? const Text('-')
                                  : GestureDetector(
                                      onTap: () async {
                                        final uri = Uri(scheme: 'tel', path: _datoCliente(r, 'telefono'));
                                        try {
                                          await launchUrl(uri);
                                        } catch (_) {}
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.phone, size: 12, color: AppTheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            _datoCliente(r, 'telefono'),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.primary,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            DataCell(Text('${r.cantidad}')),
                            if (conTerceros)
                              DataCell(Text(esTercero ? 'Sí' : 'No')),
                            ...cols.map((c) => DataCell(
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      _valorDato(r, c.clave),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                )),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        color: AppTheme.primary, size: 18),
                                    tooltip: 'Editar datos',
                                    padding: EdgeInsets.zero,
                                    constraints:
                                        const BoxConstraints(minWidth: 28),
                                    onPressed: () => _editarReserva(r),
                                  ),
                                  if (puedeCancelar)
                                    IconButton(
                                      icon: const Icon(Icons.cancel_outlined,
                                          color: AppTheme.error, size: 18),
                                      tooltip: 'Cancelar reserva',
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(minWidth: 28),
                                      onPressed: () => _cancelarReserva(r),
                                    )
                                  else
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Text(
                                        'Cancelada',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.error,
                                            fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
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
// Bottom sheet para editar datos del cliente de una reserva
// ─────────────────────────────────────────────────────────────────────────────
class _EditarReservaSheet extends StatefulWidget {
  final Agenda reserva;
  final List<CampoAdicional> camposAdicionales;
  final VoidCallback onSaved;
  const _EditarReservaSheet({
    required this.reserva,
    required this.camposAdicionales,
    required this.onSaved,
  });

  @override
  State<_EditarReservaSheet> createState() => _EditarReservaSheetState();
}

class _EditarReservaSheetState extends State<_EditarReservaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _datosAdicionalesKey = GlobalKey<DatosAdicionalesFormState>();

  late final TextEditingController _ciCtrl;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _apellidosCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _notasCtrl;

  Map<String, dynamic> _datosAdicionalesValores = {};
  bool _saving = false;

  String _dato(String clave) {
    final v = widget.reserva.datosAdicionales?[clave];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    final cli = widget.reserva.cliente;
    return switch (clave) {
      'nombre' => cli?.nombre ?? '',
      'apellidos' => cli?.apellidos ?? '',
      'ci' => cli?.ci ?? '',
      'telefono' => cli?.telefono ?? '',
      _ => '',
    };
  }

  @override
  void initState() {
    super.initState();
    _ciCtrl = TextEditingController(text: _dato('ci'));
    _nombreCtrl = TextEditingController(text: _dato('nombre'));
    _apellidosCtrl = TextEditingController(text: _dato('apellidos'));
    _telefonoCtrl = TextEditingController(text: _dato('telefono'));
    _emailCtrl = TextEditingController(
        text: widget.reserva.datosAdicionales?['email']?.toString() ?? '');
    _notasCtrl = TextEditingController(
        text: widget.reserva.datosAdicionales?['notas']?.toString() ?? '');
    // Valores iniciales de campos adicionales (para pre-poblar el form)
    _datosAdicionalesValores = {
      for (final c in widget.camposAdicionales)
        if (widget.reserva.datosAdicionales?[c.clave] != null)
          c.clave: widget.reserva.datosAdicionales![c.clave],
    };
  }

  @override
  void dispose() {
    _ciCtrl.dispose();
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.camposAdicionales.isNotEmpty &&
        _datosAdicionalesKey.currentState != null &&
        !_datosAdicionalesKey.currentState!.validar()) return;

    setState(() => _saving = true);
    try {
      final datos = <String, dynamic>{
        ...?widget.reserva.datosAdicionales,
        'ci': _ciCtrl.text.trim(),
        'nombre': _nombreCtrl.text.trim(),
        'apellidos': _apellidosCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'notas': _notasCtrl.text.trim(),
      };
      if (widget.camposAdicionales.isNotEmpty &&
          _datosAdicionalesKey.currentState != null) {
        datos.addAll(_datosAdicionalesKey.currentState!.valores);
      }

      await AgendaAdminService.actualizarDatosReserva(
        idAgenda: widget.reserva.id,
        datosAdicionales: datos,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos actualizados'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error al guardar'),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editar datos del cliente',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Reserva #${widget.reserva.id} · '
                          '${widget.reserva.localServicio?.servicio?.nombre ?? ''}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _ciCtrl,
                decoration: const InputDecoration(
                  labelText: 'CI',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Ingresa el CI' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _apellidosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Apellidos',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Ingresa los apellidos' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _telefonoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              if (widget.camposAdicionales.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información adicional',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      DatosAdicionalesForm(
                        key: _datosAdicionalesKey,
                        campos: widget.camposAdicionales,
                        initialValues: _datosAdicionalesValores,
                        onChanged: (v) =>
                            setState(() => _datosAdicionalesValores = v),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Guardar cambios',
                        style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
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
                _PhoneRow(cliente.telefono!),
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

class _PhoneRow extends StatelessWidget {
  final String telefono;
  const _PhoneRow(this.telefono);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri(scheme: 'tel', path: telefono);
          try {
            await launchUrl(uri);
          } catch (_) {}
        },
        child: Row(
          children: [
            const Icon(Icons.phone, size: 13, color: AppTheme.primary),
            const SizedBox(width: 4),
            Text(
              telefono,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
